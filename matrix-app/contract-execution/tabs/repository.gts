import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { evaluateRules } from '../../legal/approval-rule';
import { contractTypeLabel } from '../../legal/contract-type';
import {
  DEFAULT_REVIEWER,
  openStep,
  openStepIndex,
} from '../contract-execution-data';
import { formatDay } from '../../shared/compact-format';
import { Block, CeTable, Note, type Col } from '../components';

interface Signature {
  Args: { app: ContractExecutionView };
}

export class RepositoryTab extends GlimmerComponent<Signature> {
  /**
   * SUBMIT FOR APPROVAL — the action that puts a contract into the queue.
   *
   * `evaluateRules` computes which approvers a contract needs, and this builds
   * the chain from that answer.
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
    // No rule matched: submit against a default reviewer. A contract that
    // matches no rule is common (a small pilot, a routine renewal), and the
    // message names the fallback so nobody mistakes it for a rule that fired.
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
   * Ready for its signature ceremony: the chain finished with no rejection.
   * Signing itself runs in the Workspace through Execute Contract, which owns
   * the move to signed.
   */
  isSignable = (c: any): boolean => {
    if (
      c?.status === 'signed' ||
      c?.status === 'terminated' ||
      c?.status === 'expired'
    )
      return false;
    let steps = (c?.approvalChain?.steps ?? []).filter(Boolean);
    if (!steps.length) return false;
    // every step decided, and none of them rejected
    return (
      openStepIndex(c) < 0 &&
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

  columns: Col[] = [
    { label: 'Number', kind: 'mono', value: (c) => c.contractNumber ?? '—' },
    { label: 'Contract', kind: 'title', value: (c) => c.cardTitle },
    {
      label: 'Type',
      value: (c) => (c.contractType ? contractTypeLabel(c.contractType) : '—'),
    },
    {
      label: 'Status',
      kind: 'dot',
      value: (c) => this.args.app.statusLabelOf(c.status),
      tone: (c) => this.args.app.statusToneOf(c.status),
    },
    {
      label: 'Risk',
      kind: 'dot',
      value: (c) => this.args.app.riskLabelOf(c.riskGrade),
      tone: (c) => this.args.app.riskToneOf(c.riskGrade),
    },
    {
      label: 'Expires',
      kind: 'mono',
      align: 'end',
      value: (c) => formatDay(c.endDate),
    },
    { label: 'Next step', kind: 'custom', align: 'end' },
  ];

  get rows() {
    return this.args.app.search(this.args.app.contracts, (c: any) => [
      c.cardTitle,
      c.contractNumber,
      c.account?.cardTitle,
    ]);
  }

  <template>
    {{#if @app.submitProblem}}
      <Note
        class='repo-note'
        @tone='danger'
        @lead='Not submitted'
        @text={{@app.submitProblem}}
      />
    {{else if @app.submitNote}}
      <Note
        class='repo-note'
        @tone='success'
        @lead='Submitted'
        @text={{@app.submitNote}}
      />
    {{/if}}
    <Block @title='Contracts' @count={{this.rows.length}}>
      {{#if this.rows.length}}
        <CeTable
          @label='Contracts'
          @columns={{this.columns}}
          @rows={{this.rows}}
          @onOpen={{@app.openCard}}
        >
          <:cell as |c|>
            {{#if (this.needsSubmission c)}}
              <Button
                @size='xs'
                @variant='ghost'
                @disabled={{this.submitDisabled}}
                {{on 'click' (fn this.submitForApproval c)}}
              >Submit for approval</Button>
            {{else if (this.isSignable c)}}
              <Button
                @size='xs'
                @variant='ghost'
                {{on 'click' (fn @app.openInWorkspace c)}}
              >Sign in workspace</Button>
            {{else if (this.isInFlight c)}}
              <span class='repo-muted'>in approval</span>
            {{else}}
              <span class='repo-muted'>{{@app.statusLabelOf c.status}}</span>
            {{/if}}
          </:cell>
        </CeTable>
      {{else}}
        <p class='repo-empty'>No contracts match this view.</p>
      {{/if}}
    </Block>
    <style scoped>
      .repo-note {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
      }
      .repo-muted {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .repo-empty {
        margin: 0;
        padding: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
