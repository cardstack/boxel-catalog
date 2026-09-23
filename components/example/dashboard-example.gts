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

import { Dashboard, type DashboardTile } from '../dashboard';
import type { Hue } from '../state-pill';

export class DashboardExampleTile extends FieldDef {
  static displayName = 'Dashboard Example Tile';

  @field label = contains(StringField);
  @field value = contains(StringField);
  /** 'neutral' or a state-pill hue name. */
  @field intent = contains(StringField);
  @field detail = contains(StringField);
}

class DashboardExampleIsolated extends Component<typeof DashboardExample> {
  get tiles(): DashboardTile[] {
    return (this.args.model?.tiles ?? [])
      .filter((t) => t?.label)
      .map((t) => ({
        label: t.label!,
        value: t.value ?? '—',
        intent: (t.intent as Hue | 'neutral' | undefined) ?? 'neutral',
        detail: t.detail ?? undefined,
      }));
  }

  <template>
    <div class='dashboard-example'>
      <Dashboard @tiles={{this.tiles}} />
    </div>
    <style scoped>
      .dashboard-example {
        padding: var(--boxel-sp);
      }
    </style>
  </template>
}

/**
 * One tile per intent — neutral, healthy, warning and breach — so the
 * dashboard's state colouring reads side by side.
 */
export class DashboardExample extends CardDef {
  static displayName = 'Dashboard Example';
  static icon = LayoutDashboardIcon;

  @field tiles = containsMany(DashboardExampleTile);

  static isolated = DashboardExampleIsolated;
}
