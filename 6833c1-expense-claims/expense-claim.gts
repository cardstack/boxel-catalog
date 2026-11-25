import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { Chip } from '@cardstack/pretui/components/chip';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { ApprovalChainField } from '@cardstack/catalog/cards/hr/approval-chain-field';
import { Bill } from '@cardstack/catalog/cards/accounting/ledger-cards';
import {
  settingsLink,
  settingsOf,
} from '@cardstack/catalog/cards/accounting/ledger-settings';
import { ExpenseLine } from './expense-line';
import { ClaimFlagField } from './claim-flag';
import { ClaimIsolated } from './components/claim-isolated';
import { ClaimEdit } from './components/claim-edit';
import { ExpensePolicy } from './expense-policy';
import {
  CLAIM_STATUS_LABELS,
  CLAIM_STATUS_TONES,
  claimStatus,
  flagCountText,
  moneyText,
  totalMinor,
  type ClaimStatus,
} from './claim-logic';

// A staff expense claim: receipts from one employee, approved through the HR approval
// chain (reused unchanged, like PtoRequest), then sent to the books as a draft Bill.
export class ExpenseClaim extends CardDef {
  static displayName = 'Expense Claim';
  static icon = ReceiptIcon;

  /** Becomes the Bill's billNo, so it is also the key that stops a second bill. */
  @field claimNo = contains(StringField);
  @field employee = linksTo(() => Employee);
  @field purpose = contains(TextAreaField);
  @field lines = containsMany(ExpenseLine);
  @field policy = linksTo(() => ExpensePolicy);
  @field approvalChain = contains(ApprovalChainField);
  /** Why each extra approver is on the chain (policy ApprovalRules), recorded at submission. */
  @field approvalNotes = containsMany(StringField);
  /** What the policy flagged when the claim was submitted (P1, P3, P4); for the approvers. */
  @field policyFlags = containsMany(ClaimFlagField);
  @field submittedDate = contains(DateField);
  /** The draft Bill this claim became in the books. */
  @field bill = linksTo(() => Bill);
  /** The books' settings (realm.json → config), for the currency. */
  @field settings = settingsLink();

  @field currency = contains(StringField, {
    computeVia: function (this: ExpenseClaim) {
      return settingsOf(this).currency;
    },
  });
  @field totalMinor = contains(NumberField, {
    computeVia: function (this: ExpenseClaim) {
      return totalMinor(this.lines);
    },
  });
  @field lineCount = contains(NumberField, {
    computeVia: function (this: ExpenseClaim) {
      return (this.lines ?? []).filter(Boolean).length;
    },
  });
  @field status = contains(StringField, {
    computeVia: function (this: ExpenseClaim) {
      let bill = this.bill;
      return claimStatus({
        chainStepCount: this.approvalChain?.steps?.length ?? 0,
        chainStatus: this.approvalChain?.status,
        bill: bill
          ? {
              status: bill.status,
              openMinor: bill.openMinor,
              voidDate: bill.voidDate,
            }
          : null,
      });
    },
  });
  @field flagCount = contains(NumberField, {
    computeVia: function (this: ExpenseClaim) {
      return (this.policyFlags ?? []).filter(Boolean).length;
    },
  });
  // Text copies for formats that do not load links (fitted, listings).
  @field statusLabel = contains(StringField, {
    computeVia: function (this: ExpenseClaim) {
      return CLAIM_STATUS_LABELS[(this.status ?? 'draft') as ClaimStatus];
    },
  });
  @field flagText = contains(StringField, {
    computeVia: function (this: ExpenseClaim) {
      return flagCountText(this.flagCount);
    },
  });
  @field totalText = contains(StringField, {
    computeVia: function (this: ExpenseClaim) {
      return moneyText(this.totalMinor, this.currency);
    },
  });
  @field employeeName = contains(StringField, {
    computeVia: function (this: ExpenseClaim) {
      return this.employee?.name ?? '';
    },
  });
  @field employeeId = contains(StringField, {
    computeVia: function (this: ExpenseClaim) {
      return this.employee?.id ?? '';
    },
  });
  @field title = contains(StringField, {
    computeVia: function (this: ExpenseClaim) {
      let no = this.claimNo?.trim() || 'New claim';
      let who = this.employeeName?.trim();
      return who ? `${no} · ${who}` : no;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: ExpenseClaim) {
      return this.cardInfo?.name?.trim() || this.title;
    },
  });

  // The page lives in its own module (HR kit layout + actions): components/claim-isolated.gts.
  static isolated = ClaimIsolated;
  // Only the employee's fields; locked once submitted (components/claim-edit.gts).
  static edit = ClaimEdit;

  static embedded = class Embedded extends Component<typeof ExpenseClaim> {
    get tone() {
      return CLAIM_STATUS_TONES[
        (this.args.model.status ?? 'draft') as ClaimStatus
      ] as any;
    }
    <template>
      <div class='row' data-test-expense-claim>
        <span class='no'>{{@model.claimNo}}</span>
        <span class='who'>{{@model.employeeName}}</span>
        <span class='count'>{{@model.lineCount}} receipts</span>
        <span class='amount'>{{@model.totalText}}</span>
        {{#if @model.flagCount}}
          <Chip
            @label={{@model.flagText}}
            @tone='warning'
            @appearance='plain'
            data-test-flag-count
          />
        {{/if}}
        <Chip @label={{@model.statusLabel}} @tone={{this.tone}} />
      </div>
      <style scoped>
        .row {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .no {
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        .who {
          font-weight: 600;
        }
        .count {
          color: var(--muted-foreground);
        }
        .amount {
          margin-left: auto;
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ExpenseClaim> {
    get tone() {
      return CLAIM_STATUS_TONES[
        (this.args.model.status ?? 'draft') as ClaimStatus
      ] as any;
    }
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow>Claim {{@model.claimNo}}</:eyebrow>
        <:title>{{if
            @model.employeeName
            @model.employeeName
            'No employee'
          }}</:title>
        <:subtitle>{{@model.purpose}}</:subtitle>
        <:footer>
          <span class='amount'>{{@model.totalText}}</span>
          <Chip @label={{@model.statusLabel}} @tone={{this.tone}} />
        </:footer>
      </FittedCard>
      <style scoped>
        .amount {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}
