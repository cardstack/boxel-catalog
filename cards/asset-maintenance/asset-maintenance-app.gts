import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import WrenchIcon from '@cardstack/boxel-icons/wrench';
import { AppConfigurationField } from '@cardstack/catalog/fields/app-configuration/app-configuration-field';
import { Location } from '../events/location';
import { Schedule } from '../service-desk/schedule';
import { RichFittedCard } from '../shared/rich-fitted-card';
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
    <template>
      <RichFittedCard>
        <:avatar><WrenchIcon class='app-mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Facilities</:subtitle>
        <:fact>Assets · work orders · plans · parts</:fact>
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
