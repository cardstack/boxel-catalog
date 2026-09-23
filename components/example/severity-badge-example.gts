import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import AlertTriangleIcon from '@cardstack/boxel-icons/alert-triangle';

import { SeverityBadge } from '../severity-badge';
import { SeverityField } from '../../fields/severity/severity-field';

// Usage page for the Severity Badge block: every level in every mode, plus
// one real Severity field so the embedded and atom renders are exercised.
export class SeverityBadgeExample extends CardDef {
  static displayName = 'Severity Badge Example';
  static icon = AlertTriangleIcon;

  @field severity = contains(SeverityField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: SeverityBadgeExample) {
      return 'Severity Badge — every state';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='demo'>
        <section>
          <h2>Levels</h2>
          <div class='row'>
            <SeverityBadge @level='minor' />
            <SeverityBadge @level='major' />
            <SeverityBadge @level='critical' />
          </div>
        </section>
        <section>
          <h2>With counts</h2>
          <div class='row'>
            <SeverityBadge @level='minor' @count={{2}} />
            <SeverityBadge @level='major' @count={{3}} />
            <SeverityBadge @level='critical' @count={{1}} />
          </div>
        </section>
        <section>
          <h2>Compact (table cells, fitted tiles)</h2>
          <div class='row'>
            <SeverityBadge @level='minor' @compact={{true}} />
            <SeverityBadge @level='major' @compact={{true}} />
            <SeverityBadge @level='critical' @compact={{true}} @count={{4}} />
          </div>
        </section>
        <section>
          <h2>The Severity field, embedded and atom</h2>
          <div class='row'>
            <@fields.severity />
            <@fields.severity @format='atom' />
          </div>
        </section>
        <section>
          <h2>Unknown level renders nothing</h2>
          <div class='row'>
            <SeverityBadge @level='bogus' />
            <span class='hint'>(intentionally empty)</span>
          </div>
        </section>
      </div>
      <style scoped>
        .demo {
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          max-width: 40rem;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .row {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-sm);
        }
        .hint {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <SeverityBadge @level='minor' />
        <SeverityBadge @level='major' />
        <SeverityBadge @level='critical' />
      </div>
      <style scoped>
        .row {
          display: flex;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fit'>
        <SeverityBadge @level='critical' @compact={{true}} />
        <span class='name'>Severity Badge</span>
      </div>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .name {
          font-weight: 600;
          font-size: 0.875rem;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
      </style>
    </template>
  };
}

export default SeverityBadgeExample;
