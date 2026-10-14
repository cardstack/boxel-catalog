import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { eq } from '@cardstack/boxel-ui/helpers';
import { identifyCard } from '@cardstack/runtime-common';
import { Contract } from '../../legal/contract';
import { evaluateRules } from '../../legal/approval-rule';
import { AuditEntry } from '../../audit/audit-entry';
import { CollectionPanel } from '../../../components/collection-panel';
import { StatePill } from '../../../components/state-pill';
import {
  DEFAULT_REVIEWER,
  CONTRACT_COLUMNS,
  openStep,
  asAny,
} from '../contract-execution-data';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class RepositoryTab extends GlimmerComponent<Signature> {
  /**
   * SUBMIT FOR APPROVAL — the action that puts a contract into the queue.
   *
   * This is what the rules engine was always for. `evaluateRules` already
   * computes which approvers a contract needs; until now that answer was only
   * used to EXPLAIN a chain someone had hand-written into the JSON. Here it
   * builds the chain, which is the difference between a rules engine and a
   * rules description.
   *
   * A contract enters the queue when a step has `decision: 'pending'` —
   * `currentStepIndex` is computed from exactly that, so there is no index to
   * maintain and no state machine to keep in sync.
   */
  submitForApproval = async (contract: any) => {
    let store = this.args.app.args.context?.store;
    if (!store || !contract?.id) {
      this.args.app.submitProblem = 'No write access in this context.';
      return;
    }
    let fired = evaluateRules(this.args.app.rules, {
      contractType: contract.contractType,
      value: contract.value,
      riskGrade: contract.riskGrade,
      deviationCount: this.args.app.deviationCountFor(contract.id),
      handlesSensitiveData: contract.handlesSensitiveData,
    });
    // De-duplicated in order: two rules that both demand Legal produce one
    // Legal step, and it sits at the earliest position either rule wanted.
    let roles: string[] = [];
    for (let f of fired) {
      for (let r of f.roles) if (!roles.includes(r)) roles.push(r);
    }
    // No rule matched. Submit anyway, against a default reviewer.
    //
    // The earlier build refused here, which was defensible on paper and wrong
    // in use: a contract that matches no rule is the COMMON case (a small
    // pilot, a routine renewal), and answering a submit with a refusal makes
    // the button feel broken. Real products carry a catch-all reviewer for
    // exactly this; the fallback is named in the message so nobody mistakes it
    // for a rule that fired.
    let usedFallback = false;
    if (!roles.length) {
      if (this.rulesLoading) {
        this.args.app.submitProblem =
          'Approval rules are still loading — try again in a moment.';
        return;
      }
      roles = [DEFAULT_REVIEWER];
      usedFallback = true;
    }

    this.args.app.submitBusy = true;
    this.args.app.submitProblem = undefined;
    try {
      let now = new Date().toISOString();
      await store.patch(contract.id, {
        attributes: {
          approvalChain: {
            startedAt: now,
            steps: roles.map((role, i) => ({
              // Only the first step opens; the rest wait their turn, which is
              // what makes the queue sequential rather than a free-for-all.
              decision: 'pending',
              openedAt: i === 0 ? now : null,
              comment: `Required by: ${fired.find((f) => f.roles.includes(role))?.name ?? role}`,
            })),
          },
        },
      });
      this.args.app.submitNote = usedFallback
        ? `Submitted to ${roles.join(' → ')} — no approval rule matched this contract, so the default reviewer was used.`
        : `Submitted — ${roles.length} approver${roles.length === 1 ? '' : 's'}: ${roles.join(' → ')} (${fired.map((f) => f.name).join('; ')})`;
    } catch (error: any) {
      this.args.app.submitProblem =
        error?.message ?? 'Could not submit for approval.';
    } finally {
      this.args.app.submitBusy = false;
    }
  };

  /**
   * Never submitted: no chain at all.
   *
   * Deliberately not keyed on `status`. A contract can sit at "draft" with a
   * chain already running, and one marked "signed" by hand may never have been
   * through approval — the chain is the fact, the status is a label.
   */
  needsSubmission = (c: any): boolean =>
    (c?.approvalChain?.steps ?? []).filter(Boolean).length === 0;

  /** Has a chain with somewhere still to go. */
  isInFlight = (c: any): boolean => Boolean(openStep(c));

  /**
   * MARK AS SIGNED — records that a contract was executed.
   *
   * NOT an e-signature dispatch. The spec assigns sending to a colleague's app
   * and this one has nothing to call; what it can honestly own is the fact that
   * signing happened, the date it happened, and an audit entry saying who
   * recorded it. The button says "Mark as signed" rather than "Sign" for that
   * reason — it records, it does not execute.
   *
   * Exists because the submit flow told people to "sign it directly" while the
   * app offered no way to do so. A message that points at a missing action is
   * worse than no message.
   */
  markSigned = async (contract: any) => {
    let store = this.args.app.args.context?.store;
    if (!store || !contract?.id) {
      this.args.app.submitProblem = 'No write access in this context.';
      return;
    }
    if (!this.args.app.actingAs?.id) {
      this.args.app.submitProblem =
        'Choose who is recording this on the Approvals tab first — a signature recorded by nobody is not a record.';
      return;
    }
    this.args.app.submitBusy = true;
    this.args.app.submitProblem = undefined;
    try {
      let today = new Date();
      let day = `${today.getFullYear()}-${`${today.getMonth() + 1}`.padStart(2, '0')}-${`${today.getDate()}`.padStart(2, '0')}`;
      await store.patch(contract.id, {
        attributes: { status: 'signed', signedAt: day },
      });
      let ref = identifyCard(AuditEntry);
      let realm = this.args.app.realmList[0];
      let make = this.args.app.args.createCard;
      if (make && ref && realm) {
        await make(ref, new URL(realm), {
          realmURL: new URL(realm),
          localDir: this.args.app.localDirFor('AuditEntry'),
          doc: {
            data: {
              meta: { adoptsFrom: ref },
              attributes: {
                action: 'signed',
                occurredAt: new Date().toISOString(),
                subjectTitle: contract.cardTitle,
                note: 'Recorded as signed from the repository.',
              },
              relationships: {
                doneBy: {
                  links: {
                    self: this.args.app.actingAs.id,
                  },
                },
                subject: { links: { self: contract.id } },
              },
            },
          },
        } as any);
      }
      this.args.app.submitNote = `${contract.cardTitle ?? 'Contract'} marked as signed on ${day}.`;
    } catch (error: any) {
      this.args.app.submitProblem =
        error?.message ?? 'Could not mark it as signed.';
    } finally {
      this.args.app.submitBusy = false;
    }
  };

  /** Ready to sign: no chain needed, or the chain finished with an approval. */
  isSignable = (c: any): boolean => {
    if (
      c?.status === 'signed' ||
      c?.status === 'terminated' ||
      c?.status === 'expired'
    )
      return false;
    let steps = (c?.approvalChain?.steps ?? []).filter(Boolean);
    if (!steps.length) return true;
    let idx = c?.approvalChain?.currentStepIndex ?? 0;
    // past the end AND nothing was rejected
    return (
      idx >= steps.length &&
      !steps.some((st: any) => st?.decision === 'rejected')
    );
  };

  /** Disabled while busy or while the rules that drive it are still arriving. */
  get submitDisabled(): boolean {
    return this.args.app.submitBusy || this.rulesLoading;
  }

  /** The live query has not answered yet — not the same as "there are none". */
  get rulesLoading(): boolean {
    return Boolean(this.args.app.ruleQuery?.isLoading);
  }

  <template>
    {{#if @app.submitProblem}}
      <p class='cx-submit-msg is-err' role='alert'>{{@app.submitProblem}}</p>
    {{else if @app.submitNote}}
      <p class='cx-submit-msg is-ok' role='status'>{{@app.submitNote}}</p>
    {{/if}}
    <CollectionPanel
      @cardClass={{Contract}}
      @app.context={{@app.context}}
      @realms={{@app.realmList}}
      @columns={{CONTRACT_COLUMNS}}
      @label='Contracts'
      @searchPlaceholder='Search contracts…'
      @newLabel='contract'
      @defaultView='table'
      @rowFilter={{@app.activeViewTest}}
    >
      <:cell as |cellRow column|>{{#let (asAny cellRow) as |row|}}
          {{#if (eq column.key 'submit')}}
            {{#if (this.needsSubmission row)}}
              <Button
                @tone='primary'
                @appearance='accent'
                @disabled={{this.submitDisabled}}
                title={{if
                  this.rulesLoading
                  'Approval rules are still loading'
                  'Build the approval chain from the rules that match this contract'
                }}
                {{on 'click' (fn this.submitForApproval row)}}
              >{{if
                  this.rulesLoading
                  'Loading rules…'
                  'Submit for approval'
                }}</Button>
            {{else if (this.isInFlight row)}}
              <span class='cx-none'>in approval</span>
            {{else if (this.isSignable row)}}
              <Button
                @tone='success'
                @appearance='accent'
                @disabled={{@app.submitBusy}}
                {{on 'click' (fn this.markSigned row)}}
              >Mark as signed</Button>
            {{else}}
              <span class='cx-none'>{{@app.statusLabelOf row.status}}</span>
            {{/if}}
          {{else if (eq column.key 'status')}}
            <StatePill
              @label={{@app.statusLabelOf row.status}}
              @hue={{@app.statusHueOf row.status}}
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
    </CollectionPanel>

    <style scoped>
      .cx-submit-msg {
        margin: 0 0 var(--boxel-sp-xs);
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        border-radius: var(--radius);
        font-size: var(--boxel-font-size-sm);
        line-height: 1.5;
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
      .cx-none {
        color: var(--_cx-muted-fg);
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}
