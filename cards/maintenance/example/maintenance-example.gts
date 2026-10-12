import {
  CardDef,
  Component,
  StringField,
  containsMany,
  field,
  linksToMany,
} from '@cardstack/base/card-api';
import WrenchIcon from '@cardstack/boxel-icons/wrench';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Tabs } from '@cardstack/pretui/components/tabs';
import { Location } from '@cardstack/catalog/cards/events/location';

import { Asset } from '../asset';
import { AssetCategory } from '../asset-category';
import { MaintenancePlan } from '../maintenance-plan';
import { Meter } from '../meter';
import { SparePart } from '../spare-part';
import { WorkOrder } from '../work-order';
import { AssetRegister } from '../components/asset-register';
import { LocationTree } from '../components/location-tree';
import { MaintenanceCalendar } from '../components/maintenance-calendar';
import { MaintenanceHome } from '../components/maintenance-home';
import { WorkOrderBoard } from '../components/work-order-board';

const VIEWS = [
  { value: 'home', label: 'Overview' },
  { value: 'assets', label: 'Assets' },
  { value: 'sites', label: 'Sites' },
  { value: 'board', label: 'Work board' },
  { value: 'calendar', label: 'Calendar' },
];

class Isolated extends Component<typeof MaintenanceExample> {
  get assets(): Asset[] {
    return (this.args.model.assets ?? []).filter(Boolean);
  }
  get workOrders(): WorkOrder[] {
    return (this.args.model.workOrders ?? []).filter(Boolean);
  }
  get plans(): MaintenancePlan[] {
    return (this.args.model.plans ?? []).filter(Boolean);
  }
  get parts(): SparePart[] {
    return (this.args.model.parts ?? []).filter(Boolean);
  }
  get meters(): Meter[] {
    return (this.args.model.meters ?? []).filter(Boolean);
  }
  get locations(): Location[] {
    return (this.args.model.locations ?? []).filter(Boolean);
  }
  get categories(): AssetCategory[] {
    return (this.args.model.categories ?? []).filter(Boolean);
  }

  open = (card: unknown) => {
    (this.args as any).viewCard?.(card, 'isolated');
  };

  <template>
    <section class='example'>
      <h1><@fields.cardTitle /></h1>
      <Tabs @options={{VIEWS}} as |view|>
        <div class='panel'>
          {{#if (eq view 'home')}}
            <MaintenanceHome
              @assets={{this.assets}}
              @workOrders={{this.workOrders}}
              @plans={{this.plans}}
              @parts={{this.parts}}
              @meters={{this.meters}}
              @teams={{@model.teamNames}}
              @locations={{this.locations}}
              @onOpen={{this.open}}
            />
          {{else if (eq view 'assets')}}
            <AssetRegister
              @assets={{this.assets}}
              @locations={{this.locations}}
              @categories={{this.categories}}
              @onOpen={{this.open}}
            />
          {{else if (eq view 'sites')}}
            <LocationTree
              @locations={{this.locations}}
              @defaultExpanded={{true}}
            />
          {{else if (eq view 'board')}}
            <WorkOrderBoard
              @workOrders={{this.workOrders}}
              @onOpen={{this.open}}
            />
          {{else}}
            <MaintenanceCalendar
              @workOrders={{this.workOrders}}
              @plans={{this.plans}}
              @onOpenWorkOrder={{this.open}}
            />
          {{/if}}
        </div>
      </Tabs>
    </section>
    <style scoped>
      .example {
        display: grid;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-lg);
      }
      .panel {
        padding-top: var(--boxel-sp);
      }
    </style>
  </template>
}

/**
 * Sample maintenance data for the Overview, Asset Register, Location Tree,
 * Work Order Board and Maintenance Calendar components, each on its own tab.
 */
export class MaintenanceExample extends CardDef {
  static displayName = 'Maintenance Example';
  static icon = WrenchIcon;

  @field assets = linksToMany(() => Asset);
  @field workOrders = linksToMany(() => WorkOrder);
  @field plans = linksToMany(() => MaintenancePlan);
  @field parts = linksToMany(() => SparePart);
  @field meters = linksToMany(() => Meter);
  @field locations = linksToMany(() => Location);
  @field categories = linksToMany(() => AssetCategory);
  @field teamNames = containsMany(StringField);

  static isolated = Isolated;
}
