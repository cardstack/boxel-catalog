import {
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import CoordinateField from '@cardstack/base/coordinate';
import ClipboardListIcon from '@cardstack/boxel-icons/clipboard-list';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import {
  FindingField,
  FINDING_STATE_LABELS,
  FINDING_STATE_HUE,
} from './finding-field';
import { ProofField } from './proof-field';
import { SeverityBadge } from '@cardstack/catalog/cards/audit/components/severity-badge';
import { StatePill } from '@cardstack/catalog/components/state-pill';

/**
 * A finding raised in the physical world: on a site, at an asset, by a person
 * who was standing there.
 *
 * It extends Finding rather than restating it, so a report can hold both kinds
 * side by side and every consumer that reads `severity`, `state` or
 * `closureValid` keeps working unchanged. What it adds is only what a desk
 * audit has no use for — where, and the photographs.
 *
 * `photos` is a second evidence list rather than a flag on the first. A
 * physical inspection's proof is almost always images and they are read as a
 * set, so keeping them apart lets a consumer show a strip without filtering
 * documents out of it. Both lists are Proof, so both carry the same hash and
 * trust machinery.
 */
export class InspectionFindingField extends FindingField {
  static displayName = 'Inspection Finding';
  static icon = ClipboardListIcon;

  /** Site, room, or asset tag — where a reader would go to see it. */
  @field location = contains(StringField);
  @field coordinate = contains(CoordinateField);
  @field inspector = linksTo(() => Employee);
  @field photos = containsMany(ProofField);

  static embedded = class Embedded extends Component<typeof this> {
    get stateLabel() {
      return FINDING_STATE_LABELS[this.args.model?.state ?? ''] ?? '';
    }
    get stateHue() {
      return FINDING_STATE_HUE[this.args.model?.state ?? ''] ?? 'slate';
    }
    get photoCount() {
      return (this.args.model?.photos ?? []).filter(Boolean).length;
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
          {{#if @model.location}}
            <span class='where'>{{@model.location}}</span>
          {{/if}}
        </div>

        {{#if @model.statement}}
          <p class='observed'>{{@model.statement}}</p>
        {{/if}}

        <div class='foot'>
          {{#if @model.inspector}}
            <span>inspected by <@fields.inspector @format='atom' /></span>
          {{/if}}
          <span>{{this.photoCount}} photo(s)</span>
          <span>{{@model.evidenceCount}} other evidence item(s)</span>
        </div>
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
        .where {
          font-size: 0.8125rem;
          font-weight: 600;
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
      </style>
    </template>
  };
}

export default InspectionFindingField;
