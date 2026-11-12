import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { CardDef } from '@cardstack/base/card-api';
import { on } from '@ember/modifier';
import { fn, get, uniqueId } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { NativeSelect } from '@cardstack/pretui/components/native-select';
import { Textarea } from '@cardstack/pretui/components/textarea';
import { eq } from '@cardstack/pretui/helpers';
import { identifyCard } from '@cardstack/runtime-common';
import { Contract } from '../../legal/contract';
import { evaluateRules } from '../../legal/approval-rule';
import { AuditEntry, auditActionLabel } from '../../audit/audit-entry';
import { ContractVersion } from '../../legal/contract-version';
import { VersionDiff } from '../../legal/components/version-diff';
import { Employee } from '../../hr/employee';
import { formatMoney } from '../../commerce/line-item-totals';
import {
  personLabelOrUndefined,
  personLabel,
  openStep,
  openStepIndex,
} from '../contract-execution-data';
import { formatStamp, humanise, type Tone } from '../../shared/compact-format';
import { Block, CeTable, Dot, Note, SubHead, type Col } from '../components';

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

  /**
   * The approval chain rendered for the approver: "step 2 of 4, Finance is
   * behind me" tells an approver whether to chase or wait.
   */
  get leadChain() {
    let c: any = this.leadApproval;
    let steps = (c?.approvalChain?.steps ?? []).filter(Boolean);
    let open = openStepIndex(c);
    let current = open < 0 ? steps.length : open;
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
   * The rule stays data, so the sentence shown to the approver cannot drift
   * from the routing that produced it.
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
   * Moves the contract's approval chain and writes an AuditEntry: the
   * append-only record of what was decided, by whom, with what conditions.
   * The two writes succeed or fail together (see the rollback below).
   */
  recordDecision = async (action: string, withConditions = false) => {
    let make = this.args.app.args.createCard;
    let realm = this.args.app.realmURLValue;
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
    // Only the person the step is waiting on (or their delegate) can decide
    // it; anyone else is told whose decision it is.
    let step: any = openStep(subject);
    let expected = step?.delegatedTo?.id ?? step?.approver?.id;
    if (expected && expected !== this.args.app.actingAs.id) {
      let name =
        personLabelOrUndefined(step?.delegatedTo) ??
        personLabelOrUndefined(step?.approver);
      this.args.app.decisionProblem = `This step is waiting on ${name}. Switch "Acting as" to them.`;
      return;
    }
    if (action === 'rejected' && !this.args.app.decisionNote.trim()) {
      this.args.app.decisionProblem =
        'Say why in the decision note, then reject again.';
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
      // The chain moves first and the audit entry follows. If the entry
      // cannot be saved, the chain is put back, so a failed decision leaves
      // no trace and a retry starts clean.
      let rollback = await this.advanceChain(
        subject,
        action,
        this.args.app.decisionNote.trim(),
      );
      try {
        await make(ref, realm, {
          realmURL: realm,
          // Keeps new entries beside the app's own records.
          localDir: this.args.app.localDirFor('AuditEntry'),
          doc: {
            data: {
              // A LooseSingleCardDocument carries its own `meta.adoptsFrom`.
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
                // `subject` is a linksTo, so it goes in relationships.
                subject: { links: { self: subject.id } },
                ...this.args.app.themeRelationship,
              },
            },
          },
        } as any);
      } catch (error) {
        try {
          await rollback?.();
        } catch {
          // the original failure is the one to report; a failed restore must
          // not replace it
        }
        throw error;
      }
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
   * Defaulting to the head of the queue makes the pane useful before anyone
   * clicks, and any row can still be picked.
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
   * this step's decision is the advance; there is no stored index to update.
   * It returns a rollback that restores the chain as it was.
   *
   * `containsMany` patches replace the whole array, so the untouched steps are
   * rewritten as they were rather than being dropped.
   */
  advanceChain = async (
    contract: any,
    action: string,
    note: string,
  ): Promise<(() => Promise<void>) | undefined> => {
    let store = this.args.app.args.context?.store;
    let steps = (contract?.approvalChain?.steps ?? []).filter(Boolean);
    let idx = openStepIndex(contract);
    if (!store || !contract?.id || idx < 0 || idx >= steps.length) {
      return undefined;
    }
    let now = new Date().toISOString();
    // Every date goes out as an ISO string or null: a live-query step can
    // carry an Invalid Date, which `store.patch` refuses.
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
    // A containsMany patch replaces the steps, so each step's approver and
    // delegate links are sent again or they would be dropped.
    let relationships: Record<string, any> = {};
    steps.forEach((st: any, i: number) => {
      for (let key of ['approver', 'delegatedTo']) {
        let id = st?.[key]?.id;
        if (id) {
          relationships[`approvalChain.steps.${i}.${key}`] = {
            links: { self: id },
          };
        }
      }
    });
    let before: Record<string, any> = {
      approvalChain: {
        startedAt: iso(contract.approvalChain?.startedAt),
        steps: steps.map((st: any) => ({
          decision: st?.decision ?? 'pending',
          decidedAt: iso(st?.decidedAt),
          openedAt: iso(st?.openedAt),
          comment: st?.comment ?? null,
          conditions: st?.conditions ?? null,
          holdReason: st?.holdReason ?? null,
        })),
      },
    };
    if (attributes.status) {
      before.status = contract.status;
    }
    await store.patch(contract.id, { attributes, relationships });
    return async () => {
      await store.patch(contract.id, { attributes: before, relationships });
    };
  };

  columns: Col[] = [
    { label: 'Contract', kind: 'title', value: (c) => c.cardTitle },
    {
      label: 'Step',
      kind: 'dot',
      value: (c) => {
        let steps = (c.approvalChain?.steps ?? []).filter(Boolean);
        return `Step ${openStepIndex(c) + 1} of ${steps.length}`;
      },
      tone: () => 'info',
    },
    {
      label: 'With',
      value: (c) => {
        let s = openStep(c);
        return (
          personLabelOrUndefined(s?.delegatedTo) ??
          personLabelOrUndefined(s?.approver) ??
          'Unassigned'
        );
      },
    },
    {
      label: 'Waiting',
      kind: 'mono',
      align: 'end',
      value: (c) => {
        let d = openStep(c)?.waitingDays;
        return typeof d === 'number' ? `${d}d` : '—';
      },
    },
    {
      label: 'Risk',
      kind: 'dot',
      value: (c) => this.args.app.riskLabelOf(c.riskGrade),
      tone: (c) => this.args.app.riskToneOf(c.riskGrade),
    },
  ];

  get rows() {
    return this.args.app.search(this.args.app.approvalRows, (c: any) => [
      c.cardTitle,
      c.contractNumber,
    ]);
  }

  stepTone = (state: string): Tone =>
    state === 'done' ? 'success' : state === 'now' ? 'warning' : 'neutral';

  <template>
    <div class='ap'>
      <Block
        class='ap-main'
        @flat={{true}}
        @title='Waiting on an approver'
        @count={{this.rows.length}}
        @sub='Pick a contract to review it. Longest waiting first.'
      >
        {{#if this.rows.length}}
          <CeTable
            @label='Approval queue'
            @columns={{this.columns}}
            @rows={{this.rows}}
            @onOpen={{this.selectApproval}}
            @isSelected={{this.isSelectedApproval}}
          />
        {{else}}
          <p class='ap-empty'>Nothing is waiting on an approver. Submit a
            contract from the Repository to start its chain.</p>
        {{/if}}
      </Block>

      {{#if this.leadApproval}}
        {{#let this.leadApproval as |c|}}
          <Block
            class='ap-side'
            @flat={{true}}
            @title={{c.cardTitle}}
            @count={{this.leadValueLabel}}
            @sub='{{c.contractNumber}} · {{c.account.cardTitle}}'
          >
            <SubHead @label='Approval chain' />
            <ol class='ap-chain'>
              {{#each this.leadChain as |st|}}
                <li class='ap-step'>
                  <Dot @tone={{this.stepTone st.state}} @label={{st.state}} />
                  <div class='ap-step-body'>
                    {{#if st.needsApprover}}
                      <span class='ap-step-meta'>Step
                        {{st.index}}
                        of
                        {{st.total}}
                        · waiting</span>
                      {{#let (uniqueId) as |assignId|}}
                        <label class='ap-label' for={{assignId}}>Assign approver</label>
                        <NativeSelect
                          id={{assignId}}
                          @disabled={{@app.assignBusy}}
                          {{on 'change' (fn this.assignApprover st.zeroIndex)}}
                        >
                          <option value=''>Unassigned — pick someone</option>
                          {{#each this.employees as |who|}}
                            <option value={{who.id}}>{{this.employeeLabel
                                who
                              }}</option>
                          {{/each}}
                        </NativeSelect>
                      {{/let}}
                    {{else}}
                      <strong>{{st.who}}</strong>
                      <span class='ap-step-meta'>Step
                        {{st.index}}
                        of
                        {{st.total}}
                        ·
                        {{st.state}}
                        {{#if st.role}}· {{st.role}}{{/if}}
                        {{#if st.when}}· {{st.when}}{{/if}}</span>
                    {{/if}}
                  </div>
                </li>
              {{/each}}
            </ol>
            {{#if @app.assignProblem}}
              <Note
                @tone='danger'
                @lead='Not assigned'
                @text={{@app.assignProblem}}
              />
            {{/if}}

            <SubHead @label='Your decision' />
            <div class='ap-tray'>
              {{#if this.canDecide}}
                {{#let (uniqueId) (uniqueId) as |actingId noteId|}}
                  <label class='ap-label' for={{actingId}}>Acting as</label>
                  {{#if this.expectedApproverName}}
                    <span class='ap-step-meta'>this step is
                      {{this.expectedApproverName}}'s</span>
                  {{/if}}
                  <NativeSelect
                    id={{actingId}}
                    {{on 'change' this.setActingAsFromEvent}}
                  >
                    <option value=''>Choose who is deciding</option>
                    {{#each this.employees as |who|}}
                      <option
                        value={{who.id}}
                        selected={{eq who.id @app.actingAs.id}}
                      >{{this.employeeLabel who}}</option>
                    {{/each}}
                  </NativeSelect>
                  <label class='ap-label' for={{noteId}}>Decision note</label>
                  <Textarea
                    id={{noteId}}
                    @value={{@app.decisionNote}}
                    @onInput={{this.setDecisionNote}}
                    @placeholder='Reason, or the condition that must be met'
                  />
                  <div class='ap-actions'>
                    <Button
                      @size='xs'
                      @tone='primary'
                      @appearance='accent'
                      @disabled={{@app.decisionBusy}}
                      {{on 'click' this.approve}}
                    >Approve</Button>
                    <Button
                      @size='xs'
                      @appearance='outlined'
                      @disabled={{@app.decisionBusy}}
                      {{on 'click' this.approveWithConditions}}
                    >Approve with conditions</Button>
                    <Button
                      @size='xs'
                      @appearance='outlined'
                      @disabled={{true}}
                    >Delegate</Button>
                    <Button
                      @size='xs'
                      @appearance='outlined'
                      @disabled={{@app.decisionBusy}}
                      {{on 'click' this.hold}}
                    >Put on hold</Button>
                    <Button
                      @size='xs'
                      @tone='danger'
                      @appearance='outlined'
                      @disabled={{@app.decisionBusy}}
                      {{on 'click' this.reject}}
                    >Reject</Button>
                  </div>
                  {{#if @app.decisionProblem}}
                    <Note @tone='danger' @lead={{@app.decisionProblem}} />
                  {{/if}}
                  <p class='ap-msg' role='status'>
                    {{#if @app.lastDecision}}
                      {{#unless @app.decisionProblem}}
                        Recorded:
                        {{@app.lastDecision}}
                      {{/unless}}
                    {{/if}}
                  </p>
                {{/let}}
              {{else}}
                <p class='ap-step-meta'>Decisions need write access — open the
                  app in the interactive host.</p>
              {{/if}}
            </div>
            <p class='ap-foot'>Hold is recorded without moving the contract
              forward. Reject needs a reason in the decision note. Delegate
              stays off until the tray can name who the step goes to.</p>

            {{#if this.leadVersionPair.length}}
              <SubHead @label='What changed in the last amendment' />
              <VersionDiff
                @before={{get this.leadVersionPair 0}}
                @after={{get this.leadVersionPair 1}}
              />
            {{/if}}
            {{#if this.leadWhy}}
              <Note
                class='ap-why'
                @tone='info'
                @lead='Why this needs approval.'
                @text={{this.leadWhy}}
              />
            {{else if @app.rulesUnconfigured}}
              <Note
                class='ap-why'
                @tone='warning'
                @lead='No approval rules.'
                @text='Every contract goes to the default reviewer until rules are configured.'
              />
            {{/if}}
          </Block>
        {{/let}}
      {{/if}}
    </div>
    <style scoped>
      .ap {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(18rem, 24rem);
        align-items: stretch;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
      }
      /* a grid item cannot shrink below its content unless told it may */
      .ap-main,
      .ap-side {
        min-inline-size: 0;
        overflow-x: auto;
      }
      .ap-side {
        border-inline-start: 1px solid var(--border);
      }
      .ap-chain {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .ap-step {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-2xs);
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
      }
      .ap-step-body {
        display: grid;
        gap: var(--boxel-sp-5xs);
        flex: 1;
        min-inline-size: 0;
      }
      .ap-step-meta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .ap-label {
        font-family: var(--font-mono);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .ap-tray {
        display: grid;
        gap: var(--boxel-sp-2xs);
        padding: var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
      }
      .ap-actions {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: var(--boxel-sp-2xs);
      }
      .ap-msg {
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
      }
      .ap-foot,
      .ap-empty {
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .ap-why {
        border-top: 1px solid var(--border);
      }
      @container cx-app (width < 52rem) {
        .ap {
          grid-template-columns: minmax(0, 1fr);
        }
        .ap-side {
          border-inline-start: 0;
          border-top: 1px solid var(--border);
        }
      }
    </style>
  </template>
}
