import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import LayoutDashboardIcon from '@cardstack/boxel-icons/layout-dashboard';
import { FittedCard } from '@cardstack/boxel-ui/components';
import {
  settingsLink,
  settingsOf,
} from '@cardstack/catalog/cards/accounting/ledger-settings';
import { ExpensePolicy } from './expense-policy';
import { ExpenseClaim } from './expense-claim';
import { DeskIsolated } from './components/desk-isolated';

// The app's home: every claim in this workspace, in the sets people act on
// (waiting on approvers, ready for the books, in the books, drafts), and a
// "New claim" button. `claims` is a query-backed link (like the Ledger's
// accounts), so a new claim shows up on its own and each row is the claim's
// own card. Names and the number pattern are data.
export class ExpenseDesk extends CardDef {
  static displayName = 'Expense Desk';
  static icon = LayoutDashboardIcon;
  static prefersWideFormat = true;

  @field deskName = contains(StringField);
  /** New claims are numbered <prefix>-<year>-0001 onward (e.g. EC-2026-0003). */
  @field claimNoPrefix = contains(StringField);
  /** The policy a new claim starts with (and, through it, the books). */
  @field policy = linksTo(() => ExpensePolicy);
  /** Every claim in this workspace. */
  @field claims = linksToMany(() => ExpenseClaim, {
    query: { page: { size: 500 } },
  });
  /** The books' settings (realm.json → config), for the currency. */
  @field settings = settingsLink();

  @field currency = contains(StringField, {
    computeVia: function (this: ExpenseDesk) {
      return settingsOf(this).currency;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: ExpenseDesk) {
      return (
        this.cardInfo?.name?.trim() || this.deskName?.trim() || 'Expense Desk'
      );
    },
  });

  // The page lives in its own module: components/desk-isolated.gts.
  static isolated = DeskIsolated;

  static embedded = class Embedded extends Component<typeof ExpenseDesk> {
    <template>
      <div class='row' data-test-expense-desk>
        <LayoutDashboardIcon width='18' height='18' aria-hidden='true' />
        <span class='name'>{{@model.cardTitle}}</span>
        <span class='meta'>Staff expense claims · {{@model.currency}}</span>
      </div>
      <style scoped>
        .row {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .name {
          font-weight: 600;
        }
        .meta {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ExpenseDesk> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow>Expense desk</:eyebrow>
        <:title>{{@model.cardTitle}}</:title>
        <:footer>{{@model.currency}}</:footer>
      </FittedCard>
    </template>
  };
}
