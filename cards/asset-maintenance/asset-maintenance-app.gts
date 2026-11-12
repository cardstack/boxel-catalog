import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import NumberField from '@cardstack/base/number';
import WrenchIcon from '@cardstack/boxel-icons/wrench';
import { AppConfigurationField } from '@cardstack/catalog/fields/app-configuration/app-configuration-field';
import { Location } from '../events/location';
import { Schedule } from '../service-desk/schedule';
import { WorkOrder } from '../maintenance/work-order';
import { SparePart } from '../maintenance/spare-part';
import { WO_TERMINAL } from '../maintenance/maintenance-vocabulary';
import { Detail, Metric, RichFittedCard } from '../shared/rich-fitted-card';
import { AssetMaintenanceDesk } from './asset-maintenance-desk';

export { nextIdentifier } from './desk-helpers';

/**
 * One estate's maintenance desk. It owns the desk-level settings: Assets added
 * here mint ids from the App Configuration field's `idPattern` and
 * `identifierSeq`, and Work Orders keep their own `workOrderPattern` and
 * `workOrderSeq`, since the two never share a sequence. Plans and Parts carry
 * no identifier. Every tab reads live queries against the card's own realm.
 */
export class AssetMaintenanceApp extends CardDef {
  static displayName = 'Asset & Maintenance Desk';
  static icon = WrenchIcon;
  static prefersWideFormat = true;

  @field name = contains(StringField);
  @field config = contains(AppConfigurationField, {
    description: 'Asset Record Identifier pattern + setup progress.',
  });
  @field workOrderPattern = contains(StringField, {
    description: 'Work Order Record Identifier pattern, e.g. WO-{seq4}.',
  });
  @field workOrderSeq = contains(NumberField, {
    description: 'Mint counter for Work Order identifiers.',
  });
  @field timeZone = contains(StringField);
  @field schedule = linksTo(() => Schedule);
  @field estateRoot = linksTo(() => Location);
  @field teamNames = containsMany(StringField);
  @field costApprovalThreshold = contains(NumberField, {
    description:
      'Work Orders above this total cost need approval before close.',
  });
  @field currency = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AssetMaintenanceApp) {
      return this.name ?? 'Asset & Maintenance Desk';
    },
  });

  static isolated = AssetMaintenanceDesk;

  static embedded = class Embedded extends Component<
    typeof AssetMaintenanceApp
  > {
    <template>
      <div class='app-emb'>
        <span class='app-name'>{{@model.cardTitle}}</span>
        <span class='app-sub'>Assets · work orders · plans · parts</span>
      </div>
      <style scoped>
        .app-emb {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          background: var(--card);
          color: var(--card-foreground);
        }
        .app-name {
          font-weight: 700;
        }
        .app-sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof AssetMaintenanceApp> {
    <template>
      <span class='app-atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .app-atom {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof AssetMaintenanceApp> {
    // The desk's work-order and parts counts, from two queries that are not
    // live: the tile shows the numbers as of its last render.
    private query = (cls: typeof CardDef) => {
      let ref = identifyCard(cls);
      let query = ref ? { filter: { type: ref } } : undefined;
      let url = this.args.model?.[realmURL];
      let realms = url ? [url.href] : undefined;
      return this.args.context?.getCards(
        this,
        () => query,
        () => realms,
      );
    };
    private workOrders = this.query(WorkOrder);
    private parts = this.query(SparePart);
    private rows<T>(q: ReturnType<getCards> | undefined): T[] {
      return ((q?.instances ?? []) as T[]).filter(Boolean);
    }

    // Undefined while loading, so the metric and details render nothing.
    get s() {
      if ([this.workOrders, this.parts].some((q) => !q || q.isLoading)) {
        return undefined;
      }
      let open = this.rows<WorkOrder>(this.workOrders).filter(
        (wo) => !WO_TERMINAL.has(wo.status ?? ''),
      );
      let limit = this.args.model?.costApprovalThreshold;
      return {
        late: String(open.filter((wo) => wo.isOverdue).length),
        open: String(open.length),
        // Without a threshold no work order needs approval; the row is hidden.
        approval:
          limit == null
            ? undefined
            : String(
                open.filter(
                  (wo) =>
                    wo.status === 'requested' && (wo.totalCost ?? 0) > limit,
                ).length,
              ),
        lowParts: String(
          this.rows<SparePart>(this.parts).filter((p) => p.belowReorderPoint)
            .length,
        ),
      };
    }

    <template>
      <RichFittedCard>
        <:avatar><WrenchIcon class='app-mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Facilities</:subtitle>
        <:metric>{{#if this.s}}<Metric
              @value={{this.s.late}}
              @label='Late work orders'
            />{{/if}}</:metric>
        <:fact>Assets · work orders · plans · parts</:fact>
        <:details>{{#if this.s}}
            <Detail @label='Open work' @value={{this.s.open}} />
            {{#if this.s.approval}}<Detail
                @label='Awaiting approval'
                @value={{this.s.approval}}
              />{{/if}}
            <Detail @label='Parts below reorder' @value={{this.s.lowParts}} />
          {{/if}}</:details>
      </RichFittedCard>
      <style scoped>
        .app-mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export default AssetMaintenanceApp;
