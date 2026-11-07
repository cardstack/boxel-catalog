import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import HistoryIcon from '@cardstack/boxel-icons/history';

import { AuditEntry } from '../audit-entry';
import { AuditTimeline } from '../components/audit-timeline';

// Usage page for the Audit Timeline block: a short real trail over one
// report, with a sign-off moment set so the after-sign-off marker is visible
// rather than described.
export class AuditTimelineExample extends CardDef {
  static displayName = 'Audit Timeline Example';
  static icon = HistoryIcon;

  @field entries = linksToMany(() => AuditEntry);
  @field signedOffAt = contains(DateTimeField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AuditTimelineExample) {
      return 'Audit Timeline — a trail with a sign-off';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='demo'>
        <h2>With a sign-off — later entries are marked</h2>
        <AuditTimeline
          @entries={{@model.entries}}
          @signedOffAt={{@model.signedOffAt}}
        />

        <h2>Empty state</h2>
        <AuditTimeline @entries={{null}} />
      </div>
      <style scoped>
        .demo {
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          max-width: 44rem;
        }
        h2 {
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <HistoryIcon class='ic' />
        <span class='name'>{{@model.cardTitle}}</span>
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .ic {
          width: 1.125rem;
          height: 1.125rem;
          flex: none;
        }
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fit'>
        <span class='fit-name'>Audit Timeline</span>
        <span class='fit-sub'>usage page</span>
      </div>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-name {
          font-weight: 600;
          font-size: 0.9375rem;
        }
        .fit-sub {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export default AuditTimelineExample;
