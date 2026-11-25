import { CardDef, Component, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import TagIcon from '@cardstack/boxel-icons/tag';
import { FittedCard } from '@cardstack/boxel-ui/components';

// One kind of spend staff can claim (Travel, Client meals, …). A card rather than a
// field so a claim line links to it, and so the policy's edit form lists categories
// as rows instead of an inline editor per category. Labels are data in both
// languages; `account` is the books' expense account code the bill line posts to.
export class ExpenseCategory extends CardDef {
  static displayName = 'Expense Category';
  static icon = TagIcon;

  @field labelEn = contains(StringField);
  @field labelMs = contains(StringField);
  /** Expense account code in the chart (a BillLine posts to it). */
  @field account = contains(StringField);
  /** Highest amount one line may claim, in the books' currency; empty = no cap. */
  @field capAmount = contains(NumberField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ExpenseCategory) {
      return (
        this.cardInfo?.name?.trim() ||
        this.labelEn?.trim() ||
        'Untitled Expense Category'
      );
    },
  });

  static isolated = class Isolated extends Component<typeof ExpenseCategory> {
    <template>
      <article class='category' data-test-expense-category>
        <p class='eyebrow'>Expense category</p>
        <h1 data-test-label-en>{{@model.labelEn}}</h1>
        {{#if @model.labelMs}}
          <p class='alt' data-test-label-ms>{{@model.labelMs}}</p>
        {{/if}}
        <dl class='facts'>
          <div><dt>Ledger account</dt><dd class='mono'>{{if
                @model.account
                @model.account
                '—'
              }}</dd></div>
          <div><dt>Cap per line</dt><dd class='mono'>{{if
                @model.capAmount
                @model.capAmount
                'No cap'
              }}</dd></div>
        </dl>
      </article>
      <style scoped>
        .category {
          padding: var(--boxel-sp-xl);
          display: grid;
          grid-template-columns: minmax(0, 1fr);
          gap: var(--boxel-sp-xs);
        }
        .eyebrow {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
        }
        .alt {
          margin: 0;
          color: var(--muted-foreground);
        }
        .facts {
          margin: var(--boxel-sp) 0 0;
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
        .mono {
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ExpenseCategory> {
    <template>
      <div class='row' data-test-expense-category>
        <span class='name'>{{@model.labelEn}}</span>
        {{#if @model.labelMs}}<span class='alt'>{{@model.labelMs}}</span>{{/if}}
        <span class='account'>{{@model.account}}</span>
      </div>
      <style scoped>
        .row {
          display: flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .name {
          font-weight: 600;
        }
        .alt {
          color: var(--muted-foreground);
        }
        .account {
          margin-left: auto;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ExpenseCategory> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow>Category</:eyebrow>
        <:title>{{@model.labelEn}}</:title>
        <:subtitle>{{@model.labelMs}}</:subtitle>
        <:footer>{{@model.account}}</:footer>
      </FittedCard>
    </template>
  };
}
