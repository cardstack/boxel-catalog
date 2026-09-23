import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import LayoutDashboardIcon from '@cardstack/boxel-icons/layout-dashboard';
import { tracked } from '@glimmer/tracking';

import { Dashboard, type DashboardTile } from '../dashboard';
import type { Hue } from '../state-pill';

export class DashboardExampleTile extends FieldDef {
  static displayName = 'Dashboard Example Tile';

  @field label = contains(StringField);
  @field value = contains(StringField);
  /** 'neutral' or a state-pill hue name. */
  @field intent = contains(StringField);
  @field detail = contains(StringField);
  /** When set, the tile is a door: opening it reports this set. */
  @field opensTo = contains(StringField);
}

class DashboardExampleIsolated extends Component<typeof DashboardExample> {
  @tracked opened: string | undefined;

  get tiles(): DashboardTile[] {
    return (this.args.model?.tiles ?? [])
      .filter((t) => t?.label)
      .map((t) => ({
        label: t.label!,
        value: t.value ?? '—',
        intent: (t.intent as Hue | 'neutral' | undefined) ?? 'neutral',
        detail: t.detail ?? undefined,
        onOpen: t.opensTo
          ? () => {
              this.opened = t.opensTo ?? undefined;
            }
          : undefined,
      }));
  }

  <template>
    <div class='dashboard-example'>
      <Dashboard @tiles={{this.tiles}} />
      {{#if this.opened}}
        <p class='opened' role='status'>Opened: {{this.opened}}</p>
      {{/if}}
    </div>
    <style scoped>
      .dashboard-example {
        padding: var(--boxel-sp);
      }
      .opened {
        margin: var(--boxel-sp-sm) 0 0;
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}

/**
 * One tile per intent — neutral, healthy, warning and breach — so the
 * dashboard's state colouring reads side by side. The two tiles that report
 * a set of tickets open it; the example says which set a host would show.
 */
export class DashboardExample extends CardDef {
  static displayName = 'Dashboard Example';
  static icon = LayoutDashboardIcon;

  @field tiles = containsMany(DashboardExampleTile);

  static isolated = DashboardExampleIsolated;
}
