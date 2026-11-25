import {
  CardDef,
  Component,
  FieldDef,
  contains,
  containsMany,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import ScrollTextIcon from '@cardstack/boxel-icons/scroll-text';
import UserCheckIcon from '@cardstack/boxel-icons/user-check';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { ApprovalRule } from '@cardstack/catalog/cards/legal/approval-rule';
import {
  settingsLink,
  settingsOf,
} from '@cardstack/catalog/cards/accounting/ledger-settings';
import { Ledger } from '@cardstack/catalog/cards/accounting/ledger-cards';
import { ExpenseCategory } from './expense-category';
import { DEFAULT_SCAN_MODEL } from './scan-logic';

// Who fills a role that an ApprovalRule names (ApprovalRule leaves role → person to
// the consuming app on purpose).
export class RoleApproverField extends FieldDef {
  static displayName = 'Role Approver';
  static icon = UserCheckIcon;

  /** A role an ApprovalRule lists in requiredRoles, e.g. Finance. */
  @field role = contains(StringField);
  @field approver = linksTo(() => Employee);

  static embedded = class Embedded extends Component<typeof RoleApproverField> {
    <template>
      <div class='role-approver' data-test-role-approver>
        <span class='role'>{{if @model.role @model.role 'Role'}}</span>
        <span class='arrow' aria-hidden='true'>→</span>
        {{#if @model.approver}}
          <@fields.approver @format='atom' />
        {{else}}
          <span class='missing'>No approver set</span>
        {{/if}}
      </div>
      <style scoped>
        .role-approver {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .role {
          font-weight: 600;
        }
        .arrow,
        .missing {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

// The rules a company sets for claims. Every number and name here is data an admin
// edits; nothing is hard-coded in the claim. The currency is not stored here: it is
// the books' home currency from realm.json, read the same way the Ledger reads it.
export class ExpensePolicy extends CardDef {
  static displayName = 'Expense Policy';
  static icon = ScrollTextIcon;

  @field policyName = contains(StringField);
  @field categories = linksToMany(() => ExpenseCategory);
  /** A line at or above this amount needs a receipt. */
  @field receiptRequiredAbove = contains(NumberField);
  /** Days after the receipt date a claim may still be submitted. */
  @field submitWithinDays = contains(NumberField);
  /** Extra sign-off by amount: the catalog's ApprovalRule (minValue → requiredRoles). */
  @field approvalRules = linksToMany(() => ApprovalRule);
  @field roleApprovers = containsMany(RoleApproverField);
  /** OpenRouter model id for reading receipts; empty = DEFAULT_SCAN_MODEL (scan-logic.ts). */
  @field scanModel = contains(StringField);
  /** The books approved claims go into as draft bills (Ledger.enterBill). */
  @field ledger = linksTo(() => Ledger);
  /**
   * The books' settings: realm.json → config (query-backed, so a new policy finds them itself).
   * Measured 17 Nov: a plain link instead changed edit-form typing by < 10%, so not worth losing that.
   */
  @field settings = settingsLink();

  @field currency = contains(StringField, {
    computeVia: function (this: ExpensePolicy) {
      return settingsOf(this).currency;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ExpensePolicy) {
      return (
        this.cardInfo?.name?.trim() ||
        this.policyName?.trim() ||
        'Untitled Expense Policy'
      );
    },
  });

  static isolated = class Isolated extends Component<typeof ExpensePolicy> {
    defaultScanModel = `${DEFAULT_SCAN_MODEL} (default)`;
    <template>
      <article class='policy' data-test-expense-policy>
        <header>
          <p class='eyebrow'>Expense policy</p>
          <h1 data-test-policy-name><@fields.cardTitle /></h1>
        </header>

        <dl class='facts'>
          <div><dt>Currency</dt><dd
              data-test-currency
            >{{@model.currency}}</dd></div>
          <div><dt>Receipt required from</dt><dd>{{if
                @model.receiptRequiredAbove
                @model.receiptRequiredAbove
                'Every line'
              }}</dd></div>
          <div><dt>Submit within</dt><dd>{{if
                @model.submitWithinDays
                @model.submitWithinDays
                '—'
              }}
              days</dd></div>
          <div><dt>Receipt reader model</dt><dd data-test-scan-model>{{if
                @model.scanModel
                @model.scanModel
                this.defaultScanModel
              }}</dd></div>
          <div><dt>Approved claims go to</dt><dd data-test-ledger>{{#if
                @model.ledger
              }}<@fields.ledger
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}No books linked{{/if}}</dd></div>
        </dl>

        <section>
          <h2>Categories</h2>
          {{#if @model.categories.length}}
            <ul class='list'>
              {{#each @fields.categories as |Category|}}
                <li><Category @format='embedded' /></li>
              {{/each}}
            </ul>
          {{else}}
            <p class='empty'>No categories yet. Link at least one.</p>
          {{/if}}
        </section>

        <section>
          <h2>Extra sign-off</h2>
          {{#if @model.approvalRules.length}}
            <ul class='list'>
              {{#each @fields.approvalRules as |Rule|}}
                <li><Rule @format='embedded' /></li>
              {{/each}}
            </ul>
          {{else}}
            <p class='empty'>Only the employee's manager approves.</p>
          {{/if}}
        </section>

        <section>
          <h2>Who approves each role</h2>
          {{#if @model.roleApprovers.length}}
            <ul class='list'>
              {{#each @fields.roleApprovers as |RoleApprover|}}
                <li><RoleApprover @format='embedded' /></li>
              {{/each}}
            </ul>
          {{else}}
            <p class='empty'>No role approvers set.</p>
          {{/if}}
        </section>
      </article>
      <style scoped>
        .policy {
          padding: var(--boxel-sp-xl);
          display: grid;
          grid-template-columns: minmax(0, 1fr);
          gap: var(--boxel-sp-lg);
        }
        .eyebrow {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-xl);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size);
        }
        .facts {
          margin: 0;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
          gap: var(--boxel-sp);
        }
        dt {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        dd {
          margin: 0;
        }
        .list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .list > li {
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          overflow: hidden;
        }
        .empty {
          margin: 0;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ExpensePolicy> {
    <template>
      <div class='row' data-test-expense-policy>
        <span class='name'><@fields.cardTitle /></span>
        <span class='meta'>{{@model.categories.length}}
          categories ·
          {{@model.currency}}</span>
      </div>
      <style scoped>
        .row {
          display: flex;
          flex-wrap: wrap;
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

  static fitted = class Fitted extends Component<typeof ExpensePolicy> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow>Expense policy</:eyebrow>
        <:title><@fields.cardTitle /></:title>
        <:footer>{{@model.currency}}</:footer>
      </FittedCard>
    </template>
  };
}
