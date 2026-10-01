import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateTimeField from 'https://cardstack.com/base/datetime';
import NumberField from 'https://cardstack.com/base/number';

import { EmptyState } from '@cardstack/pretui/components/empty-state';

import { ApprovalStepField } from './approval-step-field';
import { AttentionPill } from './hr-ui';
import { daysBetween } from './utils';

// A pending step this many days or more past its predecessor's decision (or
// past the chain's start, for step 0) is flagged as a bottleneck in the
// stepper. Matches the spec's "surface a stuck approval" intent.
const BOTTLENECK_THRESHOLD_DAYS = 3;

function currentStepIndexOf(steps: ApprovalStepField[] | undefined): number {
  let list = steps ?? [];
  let idx = list.findIndex((s) => s?.decision === 'pending');
  return idx === -1 ? list.length : idx;
}

function statusOf(steps: ApprovalStepField[] | undefined): string {
  let list = (steps ?? []).filter(Boolean);
  if (!list.length) {
    return 'not-started';
  }
  if (list.some((s) => s.decision === 'rejected')) {
    return 'rejected';
  }
  if (list.every((s) => s.decision === 'approved')) {
    return 'approved';
  }
  return 'in-progress';
}

// Reusable sequential sign-off block. Renders as a linear stepper (an
// ordered list) rather than a tree — every step here has exactly one
// predecessor and one successor, which is a different shape from the
// manager-hierarchy forest utils/build-tree builds, so this does not
// reuse TreeNode/buildTree.
//
// The embedded/isolated format here is READ-ONLY: it shows the sequence,
// each approver, decision pill, decided-at date, and a bottleneck badge on
// whichever step is currently pending. The actual approve/reject action is
// NOT performed via `@set` inside this field's own template: a FieldDef's
// embedded format has no first-class way to mutate one element of its own
// parent's `containsMany` array and then persist the OWNING card — every
// other mutation in this app (ApproveOfferCommand, RejectCandidateCommand,
// etc.) instead goes through a Command invoked from the CONSUMING card, not
// from inside the field's own template. So Position and Offer's own isolated
// templates render the click-to-decide buttons next to
// `<@fields.approvalChain />` and call ApproveChainStepCommand
// (commands/approve-chain-step-command.gts) rather than this field mutating
// itself.
export class ApprovalChainField extends FieldDef {
  static displayName = 'Approval Chain';

  @field steps = containsMany(ApprovalStepField);
  @field startedAt = contains(DateTimeField);

  @field currentStepIndex = contains(NumberField, {
    computeVia: function (this: ApprovalChainField) {
      return currentStepIndexOf(this.steps);
    },
  });

  @field status = contains(StringField, {
    computeVia: function (this: ApprovalChainField) {
      return statusOf(this.steps);
    },
  });

  static embedded = class Stepper extends Component<typeof this> {
    get statusLabel(): string {
      switch (this.args.model?.status) {
        case 'approved':
          return 'Fully approved';
        case 'rejected':
          return 'Rejected';
        case 'in-progress':
          return 'In progress';
        default:
          return 'Not started';
      }
    }

    isCurrentPendingIndex = (index: number): boolean => {
      let steps = this.args.model?.steps ?? [];
      let currentIndex = this.args.model?.currentStepIndex ?? steps.length;
      return index === currentIndex && steps[index]?.decision === 'pending';
    };

    pendingDaysFor = (index: number): number | undefined => {
      if (!this.isCurrentPendingIndex(index)) {
        return undefined;
      }
      let steps = this.args.model?.steps ?? [];
      let priorDecidedAt = index > 0 ? steps[index - 1]?.decidedAt : undefined;
      let since = priorDecidedAt ?? this.args.model?.startedAt;
      return daysBetween(since);
    };

    bottleneckLabel = (index: number): string | undefined => {
      let days = this.pendingDaysFor(index);
      return days != null && days >= BOTTLENECK_THRESHOLD_DAYS
        ? `pending ${days} days · bottleneck`
        : undefined;
    };

    <template>
      <div class='approval-chain'>
        <div class='chain-head'>
          <span class='chain-status'>{{this.statusLabel}}</span>
        </div>
        {{#if @model.steps.length}}
          <ol class='steps'>
            {{#each @fields.steps as |StepComponent index|}}
              <li
                class='step {{if (this.isCurrentPendingIndex index) "current"}}'
              >
                <span class='step-index'>{{index}}</span>
                <div class='step-body'>
                  <StepComponent
                    @format='embedded'
                    @displayContainer={{false}}
                  />
                  <AttentionPill
                    class='bottleneck'
                    @label={{this.bottleneckLabel index}}
                  />
                </div>
              </li>
            {{/each}}
          </ol>
        {{else}}
          <EmptyState
            class='empty'
            @texture={{false}}
            @title='No approval chain configured'
            @message='This record proceeds without a sign-off gate.'
          />
        {{/if}}
      </div>
      <style scoped>
        .approval-chain {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .chain-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }
        .chain-status {
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
        }
        .steps {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
          gap: 0;
        }
        .step {
          display: flex;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) 0;
          border-bottom: 1px solid var(--border);
        }
        .step:last-child {
          border-bottom: 0;
        }
        .step-index {
          flex: none;
          width: 1.25rem;
          height: 1.25rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          background-color: var(--muted);
          color: var(--muted-foreground);
        }
        .step.current .step-index {
          background-color: var(--primary);
          color: var(--primary-foreground);
        }
        .step-body {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
        }
        .bottleneck {
          align-self: flex-start;
        }
        .empty {
          --space-9: var(--boxel-sp);
          --space-6: var(--boxel-sp);
          --text-heading: var(--boxel-font-size);
        }
      </style>
    </template>
  };

  static isolated = ApprovalChainField.embedded;
}
