import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { CardDef } from '@cardstack/base/card-api';
import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { NativeSelect } from '@cardstack/pretui/components/native-select';
import { Textarea } from '@cardstack/pretui/components/textarea';
import { eq } from '@cardstack/boxel-ui/helpers';
import { identifyCard } from '@cardstack/runtime-common';
import { Contract } from '../../legal/contract';
import { evaluateRules } from '../../legal/approval-rule';
import { AuditEntry, auditActionLabel } from '../../audit/audit-entry';
import { ContractVersion } from '../../legal/contract-version';
import { VersionDiff } from '../../legal/components/version-diff';
import { Employee } from '../../hr/employee';
import { formatMoney } from '../../commerce/line-item-totals';
import { StatePill } from '../../../components/state-pill';
import { Table } from '../../../components/table';
import {
  personLabelOrUndefined,
  personLabel,
  humanise,
  formatStamp,
  openStep,
  APPROVAL_COLUMNS,
  asAny,
} from '../contract-execution-data';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class ApprovalsTab extends GlimmerComponent<Signature> {
  get leadValueLabel(): string {
    let v: any = (this.leadApproval as any)?.value;
    return formatMoney(v?.amount, v?.currency?.code) || '';
  }

  selectApproval = (c: CardDef) => {
    this.args.app.selectedApprovalId = c?.id;
    // A new subject means the previous reason no longer applies to what is
    // on screen — carrying it over would attach one contract's rationale to
    // another contract's decision.
    this.args.app.decisionNote = '';
    this.args.app.decisionProblem = undefined;
    this.args.app.lastDecision = undefined;
  };

  /** Who this step is waiting on, so the requirement is visible before acting. */
  get expectedApproverName(): string | undefined {
    let st: any = openStep(this.leadApproval);
    return (
      personLabelOrUndefined(st?.delegatedTo) ??
      personLabelOrUndefined(st?.approver)
    );
  }

  /**
   * Assign a person to an approval step, in place.
   *
   * `submitForApproval` builds steps from ROLES ("Legal"), and a role is not a
   * person — so a freshly submitted chain has nobody on it, the step reads
   * "Unassigned" and its clock sits at 0d forever. This is the missing half of
   * submitting.
   *
   * Inline rather than a separate edit screen: it is one field, in the place
   * the reader is already looking, and routing a routine assignment through
   * the contract's edit format costs four clicks to change one link.
   */
  assignApprover = async (stepIndex: number, event: Event) => {
    let id = (event.target as HTMLSelectElement)?.value;
    let contract: any = this.leadApproval;
    let store = this.args.app.args.context?.store;
    if (!store || !contract?.id) return;
    if (!id) return;
    this.args.app.assignBusy = true;
    this.args.app.assignProblem = undefined;
    try {
      // The dotted path addresses a linksTo INSIDE a containsMany entry — the
      // same shape the seeded instances use, so the two cannot disagree.
      await store.patch(contract.id, {
        relationships: {
          [`approvalChain.steps.${stepIndex}.approver`]: {
            links: { self: id },
          },
        },
      } as any);
    } catch (error: any) {
      this.args.app.assignProblem =
        error?.message ?? 'Could not assign that approver.';
    } finally {
      this.args.app.assignBusy = false;
    }
  };

  approvalRowClass = (c: CardDef): string => this.args.app.contractSeverity(c);

  /**
   * The approval chain rendered FOR THE APPROVER rather than for the person who
   * configured the workflow. Research across six CLM products found none that
   * do this: DocuSign draws the chain to the author as a designer graph, Agiloft
   * and Juro list it on the record, Ironclad names only who is next. Knowing
   * "step 2 of 4, Finance is behind me" is what tells an approver whether to
   * chase or wait.
   */
  get leadChain() {
    let c: any = this.leadApproval;
    let steps = (c?.approvalChain?.steps ?? []).filter(Boolean);
    let current = c?.approvalChain?.currentStepIndex ?? steps.length;
    return steps.map((st: any, i: number) => ({
      index: i + 1,
      total: steps.length,
      who:
        personLabelOrUndefined(st?.approver) ??
        personLabelOrUndefined(st?.delegatedTo) ??
        'Unassigned',
      zeroIndex: i,
      // Only the step that is actually open gets an assign control. A done
      // step's approver is history and must not be editable from here; a
      // queued one is assigned when its turn comes, not speculatively.
      needsApprover: i === current && !st?.approver?.id && !st?.delegatedTo?.id,
      role: st?.approver?.department ?? '',
      state: i < current ? 'done' : i === current ? 'now' : 'queued',
      isNow: i === current,
      when: st?.decidedAt
        ? formatStamp(st.decidedAt)
        : st?.waitingDays != null
          ? `open ${st.waitingDays}d`
          : '',
    }));
  }

  /**
   * The two most recent versions of the lead contract, oldest first.
   *
   * Two, not all: a diff answers "what changed last time", and offering an
   * arbitrary pair to compare is a control nobody uses on a portfolio this size.
   */
  get leadVersionPair() {
    let id = (this.leadApproval as any)?.id;
    let rows = this.versions
      .filter((v: any) => v?.contract?.id === id)
      .sort(
        (a: any, b: any) => (a?.versionNumber ?? 0) - (b?.versionNumber ?? 0),
      );
    return rows.length >= 2 ? rows.slice(-2) : [];
  }

  /**
   * Why this needs approval, in one sentence, derived from the rules that fired.
   *
   * Falls back to nothing rather than to a guess: an approver told the wrong
   * reason is worse off than one told no reason, because they will act on it.
   */
  get leadWhy(): string | undefined {
    let fired = this.leadFiredRules;
    if (!fired.length) return undefined;
    return fired.map((f) => `${f.name} — because ${f.because}`).join('; ');
  }

  setActingAsFromEvent = (event: Event) => {
    let id = (event.target as HTMLSelectElement)?.value;
    this.args.app.actingAs = this.employees.find((e) => e.id === id);
  };

  // `name` first: it is a stored attribute and always present on a query row,
  // whereas `cardTitle` is computed and read as '' on rows whose cardInfo has
  // not resolved — which is how the approver dropdown rendered six blank
  // options and the STEP column showed nobody.
  employeeLabel = (e: any): string => personLabel(e);

  setDecisionNote = (value: string) => {
    this.args.app.decisionNote = value ?? '';
  };

  approve = () => this.recordDecision('approved');

  approveWithConditions = () =>
    this.recordDecision('approved_with_conditions', true);

  reject = () => this.recordDecision('rejected');

  delegate = () => this.recordDecision('delegated');

  hold = () => this.recordDecision('on_hold');

  /** Can a decision be recorded at all here? */
  get canDecide(): boolean {
    return Boolean(this.args.app.args.createCard && this.args.app.realmList[0]);
  }

  stepLabelOf = (c: any): string => humanise(this.stepStateOf(c));

  get employees(): Employee[] {
    return ((this.args.app.employeeQuery?.instances ?? []) as any[]).filter(
      Boolean,
    ) as Employee[];
  }

  stepStateOf = (c: any): string => openStep(c)?.stepState ?? 'pending';

  isSelectedApproval = (c: any): boolean => c?.id === this.leadApproval?.id;

  get versions(): ContractVersion[] {
    return ((this.args.app.versionQuery?.instances ?? []) as any[]).filter(
      Boolean,
    ) as ContractVersion[];
  }

  /**
   * The rules that fired for the contract at the head of the queue.
   *
   * Replaces a hardcoded $100K constant. Every researched CLM product models
   * its trigger condition and then discards it at render time, falling back to
   * instruction text a human typed; keeping the rule as data means the sentence
   * shown to the approver cannot drift from the routing that produced it.
   */
  get leadFiredRules() {
    let c: any = this.leadApproval;
    if (!c) return [];
    return evaluateRules(this.args.app.rules, {
      contractType: c.contractType,
      value: c.value,
      riskGrade: c.riskGrade,
      deviationCount: this.args.app.deviationCountFor(c.id),
      handlesSensitiveData: c.handlesSensitiveData,
    });
  }

  /**
   * Record a decision.
   *
   * WHAT THIS DOES AND DOES NOT DO. It writes an AuditEntry — the durable,
   * append-only record of what was decided, by whom, with what conditions.
   * It does NOT advance `approvalChain.currentStepIndex` on the contract,
   * because a card's own fields are edited through its edit format and this
   * app has no write path to another card's fields.
   *
   * That split is stated in the UI rather than hidden: the tray says the
   * decision is recorded and the chain is advanced on the contract. A button
   * that claimed to advance the chain and silently didn't would be the worst
   * of the three options — the reviewer would believe the work was done.
   */
  recordDecision = async (action: string, withConditions = false) => {
    let make = this.args.app.args.createCard;
    let realm = this.args.app.realmList[0];
    let ref = identifyCard(AuditEntry);
    let subject: any = this.leadApproval;
    if (!make || !realm || !ref || !subject) {
      this.args.app.decisionProblem =
        'No write access in this context — open the app in the interactive host.';
      return;
    }
    if (!this.args.app.actingAs?.id) {
      this.args.app.decisionProblem =
        'Choose who is deciding before recording anything.';
      return;
    }
    // Is this person actually the one the step is waiting on?
    //
    // Until now the app checked only that SOMEBODY was named, so Dana Kim
    // could approve a step assigned to Marcus Webb and the audit trail would
    // record it as legitimate. Ironclad hides the Approve button entirely
    // until it is your turn; the same idea, stated rather than hidden, so the
    // reader learns whose decision it actually is.
    let step: any = openStep(subject);
    let expected = step?.delegatedTo?.id ?? step?.approver?.id;
    if (expected && expected !== this.args.app.actingAs.id) {
      let name =
        personLabelOrUndefined(step?.delegatedTo) ??
        personLabelOrUndefined(step?.approver);
      this.args.app.decisionProblem = `This step is waiting on ${name}. Switch "Acting as" to them, or use Delegate to hand it over.`;
      return;
    }
    if (withConditions && !this.args.app.decisionNote.trim()) {
      this.args.app.decisionProblem =
        'Say what the condition is. An approval "with conditions" that names none is just an approval.';
      return;
    }
    this.args.app.decisionBusy = true;
    this.args.app.decisionProblem = undefined;
    try {
      await make(ref, new URL(realm), {
        realmURL: new URL(realm),
        // Keeps new entries inside the mirror directory, so they push with
        // the rest of it. Without this the card lands at the realm root —
        // `interact-submode.gts` used to forward `localDir` only on its
        // empty-instance branch and drop it whenever `doc` was supplied, which
        // put audit entries outside the directory they belong to.
        localDir: this.args.app.localDirFor('AuditEntry'),
        doc: {
          data: {
            // `doc` is a LooseSingleCardDocument — it carries its own
            // `meta.adoptsFrom`, and omitting it fails with
            // "Cannot read properties of undefined (reading 'adoptsFrom')"
            // rather than anything that names the missing field.
            meta: { adoptsFrom: ref },
            attributes: {
              action,
              occurredAt: new Date().toISOString(),
              subjectTitle: subject.cardTitle,
              note: this.args.app.decisionNote.trim() || null,
              conditions: withConditions
                ? this.args.app.decisionNote.trim()
                : null,
            },
            relationships: {
              doneBy: {
                links: {
                  self: this.args.app.actingAs.id,
                },
              },
              // `subject` is a linksTo now, so it belongs in relationships —
              // writing it as an attribute silently produced no link at all.
              subject: { links: { self: subject.id } },
            },
          },
        },
      } as any);
      // The audit entry is the record; the chain is the STATE. Both must move,
      // or the queue shows the same step forever after it was decided.
      await this.advanceChain(
        subject,
        action,
        this.args.app.decisionNote.trim(),
      );
      this.args.app.lastDecision = auditActionLabel(action);
      this.args.app.decisionNote = '';
    } catch (error: any) {
      this.args.app.decisionProblem =
        error?.message ?? 'Could not record the decision.';
    } finally {
      this.args.app.decisionBusy = false;
    }
  };

  /**
   * The contract under review — the selected one, or the longest-waiting.
   *
   * Defaulting to the head of the queue rather than to nothing means the pane
   * is useful before anyone clicks; hard-coding it to the head (which is what
   * this used to do) meant the other rows could be read but never acted on.
   */
  get leadApproval(): Contract | undefined {
    let rows = this.args.app.approvalRows;
    if (this.args.app.selectedApprovalId) {
      let picked = rows.find((c) => c.id === this.args.app.selectedApprovalId);
      if (picked) return picked;
    }
    return rows[0];
  }

  /**
   * Advance the chain by writing the decision onto the step.
   *
   * `currentStepIndex` is `computeVia` over the steps' decisions, so setting
   * this step's decision IS the advance — there is no stored index to update.
   * An earlier version of this app claimed otherwise and stopped short here;
   * the blocker was never the index, it was that nothing called `store.patch`.
   *
   * `containsMany` patches replace the whole array, so the untouched steps are
   * rewritten as they were rather than being dropped.
   */
  advanceChain = async (contract: any, action: string, note: string) => {
    let store = this.args.app.args.context?.store;
    let steps = (contract?.approvalChain?.steps ?? []).filter(Boolean);
    // Derive the open step here rather than reading the chain's computed
    // `currentStepIndex`: a live-query row does not always carry computed
    // fields, and an `undefined` index silently skipped the write.
    let idx = steps.findIndex(
      (st: any) => (st?.decision ?? 'pending') === 'pending',
    );
    if (!store || !contract?.id || idx < 0 || idx >= steps.length) return;
    // `delegated` needs a hand-over target the tray does not collect yet; it
    // is recorded in the audit log only (see the Delegate button's title).
    if (action === 'delegated') return;
    let now = new Date().toISOString();
    // Every date goes out as an ISO string or null. A live-query step can
    // carry an `Invalid Date` (a DateTimeField deserialized from a value the
    // index never had), and passing that through `store.patch` fails the whole
    // save with "RangeError: Invalid time value" — silently, from the tray's
    // point of view, because the audit entry had already been written.
    let iso = (v: any): string | null => {
      if (v == null || v === '') return null;
      let d = v instanceof Date ? v : new Date(v);
      return Number.isNaN(d.getTime()) ? null : d.toISOString();
    };
    let decided =
      action === 'approved' || action === 'approved_with_conditions';
    let isLast = idx === steps.length - 1;
    let attributes: Record<string, any> = {
      approvalChain: {
        startedAt: iso(contract.approvalChain?.startedAt) ?? now,
        steps: steps.map((st: any, i: number) => {
          let base = {
            decision: st?.decision ?? 'pending',
            decidedAt: iso(st?.decidedAt),
            openedAt: iso(st?.openedAt),
            comment: st?.comment ?? null,
            conditions: st?.conditions ?? null,
            holdReason: st?.holdReason ?? null,
          };
          if (i === idx) {
            if (action === 'on_hold') {
              return { ...base, holdReason: note || 'On hold' };
            }
            if (action === 'rejected') {
              return {
                ...base,
                decision: 'rejected',
                decidedAt: now,
                comment: note || base.comment,
                holdReason: null,
              };
            }
            // approved / approved_with_conditions
            return {
              ...base,
              decision: 'approved',
              decidedAt: now,
              comment:
                action === 'approved' ? note || base.comment : base.comment,
              conditions:
                action === 'approved_with_conditions' ? note : base.conditions,
              holdReason: null,
            };
          }
          if (i === idx + 1 && decided) {
            return { ...base, openedAt: now };
          }
          return base;
        }),
      },
    };
    // The last approval is what makes the contract `approved` — the state
    // Request Signature requires. Only the pipeline stages move here; a
    // signed or terminated contract keeps its status.
    if (
      decided &&
      isLast &&
      ['draft', 'negotiating', 'in review'].includes(contract.status)
    ) {
      attributes.status = 'approved';
    }
    await store.patch(contract.id, { attributes });
  };

  <template>
    <section class='cx-sec cx-ap-split' aria-label='Approval queue'>
      <div class='cx-ap-list'>
        <h2 class='cx-h'>Waiting on an approver
          <span class='cx-h-sub'>{{@app.approvalRows.length}}</span></h2>
        <p class='cx-note'>Pick a contract to review it. Longest waiting first.</p>
        <Table
          @columns={{APPROVAL_COLUMNS}}
          @items={{@app.approvalRows}}
          @onRowClick={{this.selectApproval}}
          @caption='Open approval steps, longest waiting first'
          @emptyMessage='No contract is waiting on an approval.'
          @rowClass={{this.approvalRowClass}}
        >
          <:cell as |cellRow column|>{{#let (asAny cellRow) as |row|}}
              {{#if (eq column.key 'cardTitle')}}
                <span
                  class='cx-ap-name
                    {{if (this.isSelectedApproval row) "is-picked"}}'
                  aria-current={{if (this.isSelectedApproval row) 'true'}}
                >{{row.cardTitle}}</span>
              {{else if (eq column.key 'step')}}
                <StatePill
                  @label={{this.stepLabelOf row}}
                  @hue='blue'
                  @dot={{true}}
                />
              {{else if (eq column.key 'riskGrade')}}
                <StatePill
                  @label={{@app.riskLabelOf row.riskGrade}}
                  @hue={{@app.riskHueOf row.riskGrade}}
                  @dot={{true}}
                />
              {{/if}}
            {{/let}}</:cell>
        </Table>
      </div>

      <div class='cx-ap-detail'>
        {{#if this.leadApproval}}
          <article class='cx-ap'>
            <header
              class='cx-ap-head'
              aria-label='Contract awaiting your approval'
            >
              <div class='cx-ap-id'>
                <h2 class='cx-ap-t'>{{this.leadApproval.cardTitle}}</h2>
                <p class='cx-ap-m'>
                  {{this.leadApproval.contractNumber}}
                  {{#if this.leadApproval.account}}
                    ·
                    {{this.leadApproval.account.cardTitle}}
                  {{/if}}
                </p>
              </div>
              <p class='cx-ap-amt'>{{this.leadValueLabel}}</p>
            </header>

            <ol class='cx-chain' aria-label='Approval chain'>
              {{#each this.leadChain as |st|}}
                <li class='cx-step is-{{st.state}}'>
                  <span class='cx-step-bar'></span>
                  <span class='cx-step-n'>Step
                    {{st.index}}
                    of
                    {{st.total}}
                    ·
                    {{st.state}}</span>
                  {{#if st.needsApprover}}
                    <div class='cx-assign'>
                      <label
                        class='cx-assign-l'
                        for='cx-assign-{{st.index}}'
                      >Assign approver</label>
                      <NativeSelect
                        class='cx-assign-sel'
                        id='cx-assign-{{st.index}}'
                        @disabled={{@app.assignBusy}}
                        {{on 'change' (fn this.assignApprover st.zeroIndex)}}
                      >
                        <option value=''>Unassigned — pick someone</option>
                        {{#each this.employees as |who|}}
                          <option value={{who.id}}>
                            {{this.employeeLabel who}}
                          </option>
                        {{/each}}
                      </NativeSelect>
                    </div>
                  {{else}}
                    <span class='cx-step-who'>{{st.who}}</span>
                  {{/if}}
                  <span class='cx-step-w'>{{st.role}}
                    {{#if st.when}}· {{st.when}}{{/if}}</span>
                </li>
              {{/each}}
            </ol>

            <section class='cx-tray' aria-label='Record a decision'>
              <h3 class='cx-h'>Your decision</h3>
              {{#if this.canDecide}}
                <div class='cx-tray-who'>
                  <label class='cx-tray-l' for='cx-acting'>Acting as</label>
                  {{#if this.expectedApproverName}}
                    <span class='cx-tray-expect'>this step is
                      {{this.expectedApproverName}}'s</span>
                  {{/if}}
                  {{! A native select, not BoxelSelect.
                  ember-power-select mounts its dropdown through a
                  wormhole into the host document; inside a card's
                  isolated template that left the whole app wedged —
                  after opening Approvals, even tab switching stopped
                  responding. A native select needs no portal, is
                  keyboard-accessible for free, and this list is short. }}
                  <NativeSelect
                    class='cx-acting'
                    id='cx-acting'
                    {{on 'change' this.setActingAsFromEvent}}
                  >
                    <option value=''>Choose who is deciding</option>
                    {{#each this.employees as |who|}}
                      <option
                        value={{who.id}}
                        selected={{eq who.id @app.actingAs.id}}
                      >
                        {{this.employeeLabel who}}
                      </option>
                    {{/each}}
                  </NativeSelect>
                </div>

                <Textarea
                  class='cx-tray-note'
                  aria-label='Decision note'
                  @value={{@app.decisionNote}}
                  @onInput={{this.setDecisionNote}}
                  @placeholder='Reason, or the condition that must be met'
                />
                <div class='cx-tray-row'>
                  <Button
                    @tone='primary'
                    @appearance='accent'
                    @disabled={{@app.decisionBusy}}
                    {{on 'click' this.approve}}
                  >Approve</Button>
                  <Button
                    @appearance='outlined'
                    @disabled={{@app.decisionBusy}}
                    {{on 'click' this.approveWithConditions}}
                  >Approve with conditions</Button>
                  <Button
                    @appearance='outlined'
                    @disabled={{@app.decisionBusy}}
                    title='Recorded in the audit log only — the tray has no hand-over target yet'
                    {{on 'click' this.delegate}}
                  >Delegate</Button>
                  <Button
                    @appearance='outlined'
                    @disabled={{@app.decisionBusy}}
                    {{on 'click' this.hold}}
                  >Put on hold</Button>
                  <Button
                    @tone='danger'
                    @appearance='outlined'
                    @disabled={{@app.decisionBusy}}
                    {{on 'click' this.reject}}
                  >Reject</Button>
                </div>

                {{#if @app.decisionProblem}}
                  <p
                    class='cx-tray-err'
                    role='alert'
                  >{{@app.decisionProblem}}</p>
                {{else if @app.lastDecision}}
                  <p class='cx-tray-ok' role='status'>Recorded:
                    {{@app.lastDecision}}. It appears in the Audit tab.</p>
                {{/if}}

                <p class='cx-tray-scope'>Delegate and hold are recorded without
                  moving the contract forward.</p>
              {{else}}
                <p class='cx-tray-scope'>Open this card in the app to record a
                  decision.</p>
              {{/if}}
            </section>

            {{#if this.leadVersionPair}}
              <section
                class='cx-diff'
                aria-label='What the last amendment changed'
              >
                <h3 class='cx-h'>What changed in the last amendment</h3>
                <VersionDiff
                  @before={{get this.leadVersionPair 0}}
                  @after={{get this.leadVersionPair 1}}
                />
              </section>
            {{/if}}

            {{#if this.leadWhy}}
              <p class='cx-why'>
                <span class='cx-why-l'>Why this needs approval</span>
                Approval is required because
                {{this.leadWhy}}.
              </p>
            {{/if}}
          </article>
        {{/if}}

      </div>
    </section>

    <style scoped>
      .cx-ct.is-alarm dd {
        color: var(--_cx-danger);
      }

      .cx-sec {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .cx-h {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .cx-kpi-v.is-alarm {
        color: var(--destructive-ink);
      }
      .cx-kpi-v.is-none {
        color: var(--_cx-muted-fg);
      }
      .cx-h-sub {
        margin-left: 6px;
        font-family: var(--font-mono);
        font-size: 11px;
        font-weight: 400;
        color: var(--_cx-muted-fg);
      }
      .cx-num.is-money {
        white-space: nowrap;
      }

      .cx-tray {
        margin-top: var(--boxel-sp);
        padding-top: var(--boxel-sp);
        border-top: 1px solid var(--_cx-rule);
      }
      .cx-tray-who {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        margin-bottom: var(--boxel-sp-xs);
      }
      .cx-tray-expect {
        font-size: var(--boxel-font-size-xs);
        color: var(--_cx-muted-fg);
      }
      .cx-tray-l {
        font-family: var(--font-mono);
        font-size: 10px;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--_cx-muted-fg);
      }

      .cx-tray-note {
        margin: var(--boxel-sp-xs) 0;
        max-width: var(--_cx-measure);
      }
      .cx-tray-row {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      .cx-tray-err {
        margin: var(--boxel-sp-xs) 0 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--destructive-ink);
      }
      .cx-tray-ok {
        margin: var(--boxel-sp-xs) 0 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--success);
      }
      .cx-tray-scope {
        margin: var(--boxel-sp-xs) 0 0;
        font-size: var(--boxel-font-size-xs);
        line-height: 1.5;
        color: var(--_cx-muted-fg);
        max-width: var(--_cx-measure);
      }
      .cx-diff {
        margin-top: var(--boxel-sp);
      }

      .cx-note {
        margin: 0 0 var(--boxel-sp);
        font-size: var(--boxel-font-size-sm);
        line-height: 1.55;
        color: var(--_cx-muted-fg);
        max-width: var(--_cx-measure);
      }
      .cx-submit-msg.is-err {
        background: color-mix(in oklch, var(--destructive) 10%, transparent);
        border-left: 3px solid var(--destructive);
      }
      .cx-submit-msg.is-ok {
        background: color-mix(in oklch, var(--success) 10%, transparent);
        border-left: 3px solid var(--success);
      }
      .cx-ws-chip.is-active {
        background: var(--_cx-fg);
        border-color: var(--_cx-fg);
        color: var(--_cx-bg);
        font-weight: 600;
      }
      .cx-fig.is-money {
        white-space: nowrap;
      }
      .cx-split.is-full {
        grid-template-columns: minmax(0, 1fr);
      }
      .cx-kpi.is-alarm {
        --stat-value-color: var(--destructive-ink);
        color: var(--destructive-ink);
      }
      .cx-ap-split {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1.15fr);
        gap: var(--boxel-sp-lg);
        align-items: start;
      }
      .cx-ap-list,
      .cx-ap-detail {
        min-width: 0;
      }
      /* The picked approval is marked in its own title cell: an accent bar and
         heavier type, so the selection reads without styling Table's rows. */
      .cx-ap-name.is-picked {
        padding-left: var(--boxel-sp-xs);
        box-shadow: inset 0.1875rem 0 0 var(--primary);
        font-weight: 650;
      }
      .cx-ap-detail {
        position: sticky;
        top: 0;
      }

      @container cx-app (width < 900px) {
        .cx-ap-split {
          grid-template-columns: minmax(0, 1fr);
        }
        .cx-ap-detail {
          position: static;
        }
      }

      .cx-ap {
        padding: var(--boxel-sp) 0 var(--boxel-sp-lg);
        border-bottom: 1px solid var(--_cx-rule);
        margin-bottom: var(--boxel-sp);
      }
      .cx-ap-head {
        display: flex;
        align-items: flex-start;
        gap: var(--boxel-sp-lg);
        flex-wrap: wrap;
      }
      .cx-ap-id {
        min-width: 0;
      }
      .cx-ap-t {
        margin: 0;
        font-size: var(--boxel-font-size);
        font-weight: 620;
        letter-spacing: -0.01em;
      }
      .cx-ap-m {
        margin: 2px 0 0;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--_cx-muted-fg);
      }
      .cx-ap-amt {
        margin: 0 0 0 auto;
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        font-size: 1.4rem;
        font-weight: 600;
        letter-spacing: -0.01em;
        white-space: nowrap;
      }

      .cx-chain {
        list-style: none;
        margin: var(--boxel-sp) 0 0;
        padding: 0;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
        gap: var(--boxel-sp-xs) var(--boxel-sp);
      }
      .cx-step {
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
      }
      .cx-step-bar {
        height: 4px;
        border-radius: 2px;
        background: var(--_cx-rule);
        margin-bottom: 5px;
      }
      .cx-step.is-done .cx-step-bar {
        background: var(--success);
      }
      .cx-step.is-now .cx-step-bar {
        background: var(--_cx-accent);
      }
      .cx-step-n {
        font-family: var(--font-mono);
        font-size: 10px;
        letter-spacing: 0.09em;
        text-transform: uppercase;
        color: var(--_cx-muted-fg);
      }
      .cx-step.is-now .cx-step-n {
        color: var(--_cx-fg);
      }
      .cx-assign {
        display: flex;
        flex-direction: column;
        gap: 3px;
        margin: 2px 0 4px;
      }
      .cx-assign-l {
        font-family: var(--font-mono);
        font-size: 9.5px;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--_cx-fg);
      }

      .cx-step-who {
        font-size: var(--boxel-font-size-sm);
        font-weight: 560;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .cx-step.is-now .cx-step-who {
        color: var(--_cx-fg);
        font-weight: 650;
      }
      .cx-step-w {
        font-family: var(--font-mono);
        font-size: 11px;
        color: var(--_cx-muted-fg);
      }

      .cx-why {
        margin: var(--boxel-sp) 0 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        background: var(
          --_cx-sunk,
          color-mix(in oklch, currentColor 4%, transparent)
        );
        color: var(--_cx-sunk-fg);
        border-left: 3px solid var(--_cx-muted-fg);
        border-radius: 0 var(--radius) var(--radius) 0;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.55;
        max-width: var(--_cx-measure);
      }
      .cx-why-l {
        display: block;
        margin-bottom: 4px;
        font-family: var(--font-mono);
        font-size: 10px;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--_cx-muted-fg);
      }

      @container cx-app (width < 560px) {
        .cx-ap-amt {
          margin-left: 0;
          font-size: 1.2rem;
        }
        .cx-chain {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}
