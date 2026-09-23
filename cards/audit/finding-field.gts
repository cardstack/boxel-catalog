import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
  type BaseDefComponent,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import FlagIcon from '@cardstack/boxel-icons/flag';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { Task } from '@cardstack/catalog/cards/tasks/task';
import { ValidationRuleField } from './validation-rule-field';
import { SeverityField } from '@cardstack/catalog/cards/audit/severity-field';
import {
  ResolutionCodeField,
  RESOLUTION_CODES,
} from '@cardstack/catalog/fields/resolution-code/resolution-code-field';
import { ApprovalStepField } from '@cardstack/catalog/cards/hr/approval-step-field';
import { ProofField } from './proof-field';
import { AnnotationField } from './annotation-field';
import { SeverityBadge } from '@cardstack/catalog/cards/audit/components/severity-badge';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { closureGap } from './utils/finding-closure';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export const FINDING_STATES = ['open', 'in-remediation', 'closed'] as const;

export const FINDING_STATE_LABELS: Record<string, string> = {
  open: 'Open',
  'in-remediation': 'In remediation',
  closed: 'Closed',
};

export const FINDING_STATE_HUE: Record<string, Hue> = {
  open: 'red',
  'in-remediation': 'amber',
  closed: 'green',
};

export const FindingStateField = enumField(StringField, {
  displayName: 'Finding State',
  options: FINDING_STATES.map((value) => ({
    value,
    label: FINDING_STATE_LABELS[value],
  })),
});

/**
 * A recorded gap between a rule and reality — where the risk lives, and the
 * whole point of running an audit.
 *
 * It keeps the rule that raised it *by value*, not by reference. A rule
 * edited next quarter must not silently rewrite what last quarter's finding
 * said was wrong; the finding is a statement about a moment and has to stay
 * readable as one.
 *
 * `recurrenceOfId` is the prior finding's id as a string rather than a link.
 * A finding is a FieldDef, so it has no identity of its own to link to — the
 * card carrying it does. Naming the id keeps the chain readable without a
 * module cycle between this field and the result card that contains it.
 *
 * `closureBlocker` is the gate that matters: a finding cannot honestly be
 * closed without a resolution code and a name, `remediated` additionally
 * needs its corrective action actually done, and `risk-accepted` needs an
 * approval on record. The field reports the gap in a sentence; the close
 * command refuses on the same one.
 */
export class FindingField extends FieldDef {
  static displayName = 'Finding';
  static icon = FlagIcon;

  /** "F-2026-014" — cited in reports and by later recurrences. */
  @field findingId = contains(StringField);
  /** The rule as it stood when this was raised. */
  @field rule = contains(ValidationRuleField);
  @field subject = linksTo(CardDef, { searchable: true });
  @field severity = contains(SeverityField);
  /** What was observed against what was required, in the auditor's words. */
  @field statement = contains(TextAreaField);
  @field evidence = containsMany(ProofField);
  @field annotations = containsMany(AnnotationField);
  @field state = contains(FindingStateField);
  @field resolution = contains(ResolutionCodeField);
  @field correctiveAction = linksTo(() => Task);
  @field raisedBy = linksTo(() => Employee);
  @field raisedAt = contains(DateTimeField);
  /** The findingId this repeats, when the same rule failed the same subject before. */
  @field recurrenceOfId = contains(StringField);
  @field closedBy = linksTo(() => Employee);
  @field closedAt = contains(DateTimeField);
  /**
   * The decision that a `risk-accepted` closure rests on — one approver, one
   * decision, which is the shape Approve Request already implements. A chain
   * would be the wrong instrument: accepting a risk is somebody putting their
   * name to it, not a sequence of sign-offs.
   */
  @field riskAcceptance = contains(ApprovalStepField);

  @field isClosed = contains(BooleanField, {
    computeVia: function (this: FindingField) {
      return this.state === 'closed';
    },
  });

  @field evidenceCount = contains(NumberField, {
    computeVia: function (this: FindingField) {
      return (this.evidence ?? []).filter(Boolean).length;
    },
  });

  @field isRecurrence = contains(BooleanField, {
    computeVia: function (this: FindingField) {
      return Boolean((this.recurrenceOfId ?? '').trim());
    },
  });

  /**
   * What still stands between this finding and an honest closure — empty
   * while it is open, since nothing is being claimed yet.
   *
   * The gate lives in `utils/finding-closure` so this readout and the close
   * command's refusal are the same sentence.
   */
  @field closureBlocker = contains(StringField, {
    computeVia: function (this: FindingField) {
      if (this.state !== 'closed') {
        return '';
      }
      return (
        closureGap(
          {
            code: this.resolution?.code,
            hasCorrectiveAction: Boolean(this.correctiveAction),
            correctiveActionDone: this.correctiveAction?.status === 'Done',
            acceptanceDecision: this.riskAcceptance?.decision,
            closedById: this.closedBy?.id,
          },
          RESOLUTION_CODES,
        ) ?? ''
      );
    },
  });

  /** Closed with a code, and the code's own obligation met. */
  @field closureValid = contains(BooleanField, {
    computeVia: function (this: FindingField) {
      return this.state === 'closed' && !this.closureBlocker;
    },
  });

  @field label = contains(StringField, {
    computeVia: function (this: FindingField) {
      let id = this.findingId ? `${this.findingId} ` : '';
      return `${id}${this.rule?.ruleId ?? ''}`.trim();
    },
  });

  // `BaseDefComponent` keeps a subclass's embedded view (Inspection Finding)
  // assignable.
  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    get stateLabel() {
      return FINDING_STATE_LABELS[this.args.model?.state ?? ''] ?? '';
    }
    get stateHue() {
      return FINDING_STATE_HUE[this.args.model?.state ?? ''] ?? 'slate';
    }
    <template>
      <div class='finding'>
        <div class='head'>
          {{#if @model.findingId}}
            <span class='fid mono'>{{@model.findingId}}</span>
          {{/if}}
          {{#if @model.severity.level}}
            <SeverityBadge @level={{@model.severity.level}} />
          {{/if}}
          <StatePill
            @label={{this.stateLabel}}
            @hue={{this.stateHue}}
            @dot={{true}}
          />
          {{#if @model.isRecurrence}}
            <StatePill
              @label='recurrence of {{@model.recurrenceOfId}}'
              @hue='orange'
            />
          {{/if}}
          {{#unless @model.closureValid}}
            <StatePill @label='closure incomplete' @hue='red' @dot={{true}} />
          {{/unless}}
        </div>

        {{#if @model.rule.statement}}
          <p class='required'>Required: {{@model.rule.statement}}</p>
        {{/if}}
        {{#if @model.statement}}
          <p class='observed'>{{@model.statement}}</p>
        {{/if}}

        <div class='foot'>
          {{#if @model.subject}}
            <span><@fields.subject @format='atom' /></span>
          {{/if}}
          <span>{{@model.evidenceCount}} evidence item(s)</span>
          {{#if @model.resolution.code}}
            <span><@fields.resolution @format='atom' /></span>
          {{/if}}
          {{#if @model.correctiveAction}}
            <span>action: <@fields.correctiveAction @format='atom' /></span>
          {{/if}}
          {{#if @model.closedBy}}
            <span>closed by
              <@fields.closedBy @format='atom' />
              {{#if @model.closedAt}}<@fields.closedAt />{{/if}}</span>
          {{/if}}
        </div>

        {{#if @model.riskAcceptance.decision}}
          <div class='acceptance'><@fields.riskAcceptance /></div>
        {{/if}}
        {{#if @model.closureBlocker}}
          <p class='blocker'>{{@model.closureBlocker}}</p>
        {{/if}}
      </div>
      <style scoped>
        .finding {
          display: grid;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs) 0;
          min-width: 0;
        }
        .head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .fid {
          font-size: 0.8125rem;
          font-weight: 700;
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        .required {
          margin: 0;
          font-size: 0.8125rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .observed {
          margin: 0;
          font-size: 0.875rem;
          line-height: 1.5;
        }
        .foot {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-sm);
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .acceptance {
          padding-top: var(--boxel-sp-5xs);
        }
        /* The red pill in the head already carries the signal; a second
           colour here would compete with severity for the eye. */
        .blocker {
          margin: 0;
          font-size: 0.8125rem;
          font-weight: 600;
          color: var(--foreground, var(--boxel-dark));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        {{#if @model.severity.level}}
          <SeverityBadge @level={{@model.severity.level}} @compact={{true}} />
        {{/if}}
        <span class='mono'>{{@model.findingId}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
          font-size: 0.75rem;
          font-weight: 700;
        }
      </style>
    </template>
  };
}

export default FindingField;
