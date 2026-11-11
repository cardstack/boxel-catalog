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

import { ApprovalStepField } from './approval-step-field';
import { daysBetween } from './utils';
import { DotLabel } from './dot-enum-field';
import { Avatar } from '@cardstack/pretui/components/avatar';

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

    shortDate = (d?: Date | string | null): string | undefined => {
      if (!d) {
        return undefined;
      }
      let t = new Date(d);
      return isNaN(t.getTime())
        ? undefined
        : t.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
          });
    };

    // One flat 28px row per step: approver, date · comment, decision.
    <template>
      <ol class='steps' aria-label='Approval chain: {{this.statusLabel}}'>
        {{#each @model.steps as |step index|}}
          <li
            class='step'
            data-current={{if (this.isCurrentPendingIndex index) 'true'}}
          >
            <span class='who'><Avatar
                @name={{if step.approver.name step.approver.name '?'}}
                @src={{step.approver.photo.resolvedUrl}}
                @size={{18}}
                aria-hidden='true'
              /><strong>{{if
                  step.approver.name
                  step.approver.name
                  'Unassigned'
                }}</strong></span>
            <span class='meta'>{{#if (this.shortDate step.decidedAt)}}<span
                  class='mono'
                >{{this.shortDate step.decidedAt}}</span>{{/if}}{{#if
                step.comment
              }}
                ·
                {{step.comment}}{{/if}}{{#if (this.bottleneckLabel index)}}
                ·
                {{this.bottleneckLabel index}}{{/if}}</span>
            <span class='decision'>{{#if step.decision}}<DotLabel
                  @label={{step.decision}}
                  @hue={{this.decisionHue step.decision}}
                />{{/if}}</span>
          </li>
        {{else}}
          <li class='step'><span class='meta'>No approval chain configured. This
              record proceeds without a sign-off gate.</span></li>
        {{/each}}
      </ol>
      <style scoped>
        .steps {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .step {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
          min-height: 1.75rem;
          padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
          box-sizing: border-box;
          border-top: 1px solid var(--border);
          font-size: var(--boxel-font-size-xs);
        }
        .who {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-weight: 700;
        }
        .meta {
          flex: 1 1 10rem;
          min-width: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
        }
        .decision {
          margin-left: auto;
        }
      </style>
    </template>

    decisionHue = (decision?: string | null) =>
      (decision === 'approved'
        ? 'green'
        : decision === 'rejected'
          ? 'red'
          : 'amber') as 'green' | 'red' | 'amber';
  };

  static isolated = ApprovalChainField.embedded;
}
