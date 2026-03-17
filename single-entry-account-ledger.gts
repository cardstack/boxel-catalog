// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
// Single-Entry Account Ledger (Cash Book Style)
// Uses containsMany(FieldDef) for embedded data
import {
  CardDef,
  field,
  contains,
  containsMany,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BookOpenIcon from '@cardstack/boxel-icons/book-open';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { LedgerEntryField } from './ledger-entry-field';

export class SingleEntryAccountLedger extends CardDef {
  static displayName = 'Single-Entry Account Ledger';
  static icon = BookOpenIcon;
  static prefersWideFormat = true;

  @field accountName = contains(StringField);
  @field accountNumber = contains(StringField);
  @field currency = contains(StringField);
  @field openingBalance = contains(NumberField);
  @field entries = containsMany(LedgerEntryField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: SingleEntryAccountLedger) {
      return this.accountName ?? 'Account Ledger';
    },
  });

  static isolated = class Isolated extends Component<typeof SingleEntryAccountLedger> {
    @tracked newDescription = '';
    @tracked newAmount = '';
    @tracked newType: 'credit' | 'debit' = 'credit';
    @tracked newReference = '';
    @tracked newCategory = '';
    @tracked creationStatus = '';
    @tracked showForm = false;

    get entries() {
      return this.args.model?.entries ?? [];
    }

    get currency() {
      return this.args.model?.currency || 'USD';
    }

    get openingBalance() {
      return this.args.model?.openingBalance ?? 0;
    }

    get totalDebits() {
      let sum = 0;
      for (const entry of this.entries) {
        sum += entry.debit ?? 0;
      }
      return sum;
    }

    get totalCredits() {
      let sum = 0;
      for (const entry of this.entries) {
        sum += entry.credit ?? 0;
      }
      return sum;
    }

    get currentBalance() {
      return this.openingBalance + this.totalCredits - this.totalDebits;
    }

    get balanceDisplay() {
      const bal = this.currentBalance;
      const formatted = Math.abs(bal).toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
      return bal >= 0 ? `$${formatted}` : `-$${formatted}`;
    }

    formatCurrency = (amount: number) => {
      return amount.toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
    };

    getRunningBalance = (index: number) => {
      let balance = this.openingBalance;
      for (let i = 0; i <= index; i++) {
        const entry = this.entries[i];
        if (entry) {
          balance += (entry.credit ?? 0) - (entry.debit ?? 0);
        }
      }
      return balance;
    };

    toggleForm = () => {
      this.showForm = !this.showForm;
      if (!this.showForm) {
        this.resetForm();
      }
    };

    resetForm = () => {
      this.newDescription = '';
      this.newAmount = '';
      this.newType = 'credit';
      this.newReference = '';
      this.newCategory = '';
    };

    setType = (type: 'credit' | 'debit') => {
      this.newType = type;
    };

    updateDescription = (event: Event) => {
      this.newDescription = (event.target as HTMLInputElement).value;
    };

    updateAmount = (event: Event) => {
      this.newAmount = (event.target as HTMLInputElement).value;
    };

    updateReference = (event: Event) => {
      this.newReference = (event.target as HTMLInputElement).value;
    };

    updateCategory = (event: Event) => {
      this.newCategory = (event.target as HTMLInputElement).value;
    };

    addEntry = () => {
      if (!this.newDescription.trim()) {
        this.creationStatus = 'Please enter description';
        setTimeout(() => { this.creationStatus = ''; }, 2000);
        return;
      }

      const amount = parseFloat(this.newAmount) || 0;
      if (amount <= 0) {
        this.creationStatus = 'Please enter a valid amount';
        setTimeout(() => { this.creationStatus = ''; }, 2000);
        return;
      }

      try {
        const newEntry = new LedgerEntryField();
        newEntry.description = this.newDescription.trim();
        newEntry.debit = this.newType === 'debit' ? amount : undefined;
        newEntry.credit = this.newType === 'credit' ? amount : undefined;
        newEntry.reference = this.newReference.trim() || undefined;
        newEntry.category = this.newCategory.trim() || undefined;
        newEntry.entryDate = new Date();

        const currentEntries = this.args.model?.entries || [];
        (this.args.model as any).entries = [...currentEntries, newEntry];

        this.resetForm();
        this.showForm = false;
        this.creationStatus = 'Entry added!';
        setTimeout(() => { this.creationStatus = ''; }, 2000);
      } catch (e: any) {
        this.creationStatus = `Error: ${e?.message || e}`;
      }
    };

    <template>
      <article class="ledger">
        <header class="ledger-header">
          <div class="account-info">
            <h1>{{if @model.accountName @model.accountName "Single-Entry Ledger"}}</h1>
            <span class="variant-badge">Single-Entry</span>
            {{#if @model.accountNumber}}
              <span class="account-number">Account: {{@model.accountNumber}}</span>
            {{/if}}
          </div>

          <div class="balance-card">
            <span class="balance-label">Current Balance</span>
            <span class="balance-amount {{if this.currentBalance 'positive' 'negative'}}">
              {{this.balanceDisplay}}
            </span>
          </div>
        </header>

        <div class="summary-bar">
          <div class="summary-item">
            <span class="summary-label">Opening</span>
            <span class="summary-value">${{this.formatCurrency this.openingBalance}}</span>
          </div>
          <div class="summary-item credits">
            <span class="summary-label">Total Credits</span>
            <span class="summary-value">+${{this.formatCurrency this.totalCredits}}</span>
          </div>
          <div class="summary-item debits">
            <span class="summary-label">Total Debits</span>
            <span class="summary-value">-${{this.formatCurrency this.totalDebits}}</span>
          </div>
          <div class="summary-item entries-count">
            <span class="summary-label">Entries</span>
            <span class="summary-value">{{this.entries.length}}</span>
          </div>
        </div>

        {{#if this.creationStatus}}
          <div class="status-bar">{{this.creationStatus}}</div>
        {{/if}}

        <div class="actions-bar">
          <button
            class="add-entry-btn {{if this.showForm 'active'}}"
            type="button"
            {{on "click" this.toggleForm}}
          >
            {{if this.showForm "Cancel" "+ New Entry"}}
          </button>
        </div>

        {{#if this.showForm}}
          <div class="entry-form">
            <div class="form-row">
              <div class="type-toggle">
                <button
                  class="type-btn {{if this.isCredit 'active credit'}}"
                  type="button"
                  {{on "click" (fn this.setType "credit")}}
                >Credit (+)</button>
                <button
                  class="type-btn {{if this.isDebit 'active debit'}}"
                  type="button"
                  {{on "click" (fn this.setType "debit")}}
                >Debit (-)</button>
              </div>
              <input
                type="number"
                class="form-input amount"
                placeholder="Amount *"
                step="0.01"
                min="0"
                value={{this.newAmount}}
                {{on "input" this.updateAmount}}
              />
            </div>
            <div class="form-row">
              <input
                type="text"
                class="form-input desc"
                placeholder="Description *"
                value={{this.newDescription}}
                {{on "input" this.updateDescription}}
              />
            </div>
            <div class="form-row">
              <input
                type="text"
                class="form-input"
                placeholder="Reference (optional)"
                value={{this.newReference}}
                {{on "input" this.updateReference}}
              />
              <input
                type="text"
                class="form-input"
                placeholder="Category (optional)"
                value={{this.newCategory}}
                {{on "input" this.updateCategory}}
              />
              <button class="submit-btn" type="button" {{on "click" this.addEntry}}>
                Add Entry
              </button>
            </div>
          </div>
        {{/if}}

        <div class="ledger-table">
          <div class="table-header">
            <span class="col-date">Date</span>
            <span class="col-desc">Description</span>
            <span class="col-ref">Ref</span>
            <span class="col-debit">Debit</span>
            <span class="col-credit">Credit</span>
            <span class="col-balance">Balance</span>
          </div>

          <div class="table-body">
            {{#if this.entries.length}}
              {{#each this.entries as |entry index|}}
                <div class="table-row">
                  <span class="col-date">{{if entry.entryDate entry.entryDate "—"}}</span>
                  <span class="col-desc">
                    {{if entry.description entry.description "—"}}
                    {{#if entry.category}}
                      <span class="category-tag">{{entry.category}}</span>
                    {{/if}}
                  </span>
                  <span class="col-ref">{{if entry.reference entry.reference ""}}</span>
                  <span class="col-debit">
                    {{#if entry.debit}}
                      ${{this.formatCurrency entry.debit}}
                    {{/if}}
                  </span>
                  <span class="col-credit">
                    {{#if entry.credit}}
                      ${{this.formatCurrency entry.credit}}
                    {{/if}}
                  </span>
                  <span class="col-balance">${{this.formatCurrency (this.getRunningBalance index)}}</span>
                </div>
              {{/each}}
            {{else}}
              <div class="empty-state">
                <p>No entries yet. Click "+ New Entry" to add your first transaction.</p>
              </div>
            {{/if}}
          </div>
        </div>
      </article>

      <style scoped>
        .ledger {
          height: 100%;
          display: flex;
          flex-direction: column;
          background: var(--background, #fafafa);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .ledger-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: var(--boxel-sp-lg, 1.5rem);
          background: var(--card, #fff);
          border-bottom: 1px solid var(--border, #e5e5e5);
          flex-wrap: wrap;
          gap: var(--boxel-sp, 1rem);
        }

        .account-info h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg, 1.25rem);
          font-weight: 700;
          color: var(--foreground, #1a1a1a);
        }

        .variant-badge {
          display: inline-block;
          font-size: var(--boxel-font-size-xs, 0.75rem);
          padding: 2px 8px;
          background: hsl(200 80% 90%);
          color: hsl(200 80% 35%);
          border-radius: 4px;
          margin-left: 8px;
        }

        .account-number {
          display: block;
          font-size: var(--boxel-font-size-sm, 0.875rem);
          color: var(--muted-foreground, #6b7280);
        }

        .balance-card { text-align: right; }

        .balance-label {
          display: block;
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--muted-foreground, #6b7280);
          text-transform: uppercase;
          margin-bottom: 4px;
        }

        .balance-amount {
          font-size: 1.75rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }

        .balance-amount.positive { color: hsl(142 76% 36%); }
        .balance-amount.negative { color: hsl(0 84% 50%); }

        .summary-bar {
          display: flex;
          gap: var(--boxel-sp, 1rem);
          padding: var(--boxel-sp, 1rem) var(--boxel-sp-lg, 1.5rem);
          background: var(--muted, #f5f5f5);
          border-bottom: 1px solid var(--border, #e5e5e5);
          flex-wrap: wrap;
        }

        .summary-item {
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp, 1rem);
          background: var(--card, #fff);
          border-radius: var(--boxel-border-radius, 0.5rem);
          text-align: center;
          min-width: 100px;
        }

        .summary-label {
          display: block;
          font-size: var(--boxel-font-size-xs, 0.75rem);
          color: var(--muted-foreground, #6b7280);
          margin-bottom: 2px;
        }

        .summary-value {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }

        .summary-item.credits .summary-value { color: hsl(142 76% 36%); }
        .summary-item.debits .summary-value { color: hsl(0 84% 50%); }

        .status-bar {
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp-lg, 1.5rem);
          background: var(--secondary, #e0f2fe);
          color: var(--secondary-foreground, #0369a1);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          text-align: center;
        }

        .actions-bar {
          padding: var(--boxel-sp-sm, 0.75rem) var(--boxel-sp-lg, 1.5rem);
          background: var(--card, #fff);
          border-bottom: 1px solid var(--border, #e5e5e5);
        }

        .add-entry-btn {
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp, 1rem);
          background: var(--primary, #3b82f6);
          color: var(--primary-foreground, #fff);
          border: none;
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 600;
          cursor: pointer;
        }

        .add-entry-btn.active {
          background: var(--muted, #e5e5e5);
          color: var(--foreground, #1a1a1a);
        }

        .entry-form {
          padding: var(--boxel-sp, 1rem) var(--boxel-sp-lg, 1.5rem);
          background: var(--muted, #f5f5f5);
          border-bottom: 1px solid var(--border, #e5e5e5);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm, 0.75rem);
        }

        .form-row {
          display: flex;
          gap: var(--boxel-sp-sm, 0.75rem);
          flex-wrap: wrap;
        }

        .type-toggle {
          display: flex;
          border: 1px solid var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          overflow: hidden;
        }

        .type-btn {
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp, 1rem);
          background: var(--card, #fff);
          border: none;
          font-size: var(--boxel-font-size-sm, 0.875rem);
          cursor: pointer;
        }

        .type-btn.active.credit {
          background: hsl(142 76% 90%);
          color: hsl(142 76% 30%);
          font-weight: 600;
        }

        .type-btn.active.debit {
          background: hsl(0 84% 92%);
          color: hsl(0 84% 40%);
          font-weight: 600;
        }

        .form-input {
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp-sm, 0.75rem);
          border: 1px solid var(--border, #e5e5e5);
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          flex: 1;
          min-width: 120px;
        }

        .form-input.desc { flex: 2; }
        .form-input.amount { max-width: 120px; }

        .form-input:focus {
          outline: none;
          border-color: var(--primary, #3b82f6);
        }

        .submit-btn {
          padding: var(--boxel-sp-xs, 0.5rem) var(--boxel-sp, 1rem);
          background: hsl(142 76% 36%);
          color: white;
          border: none;
          border-radius: var(--boxel-border-radius, 0.5rem);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          font-weight: 600;
          cursor: pointer;
        }

        .submit-btn:hover { filter: brightness(1.1); }

        .ledger-table {
          flex: 1;
          display: flex;
          flex-direction: column;
          overflow: hidden;
        }

        .table-header {
          display: grid;
          grid-template-columns: 100px 1fr 80px 100px 100px 110px;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding: var(--boxel-sp-sm, 0.75rem) var(--boxel-sp-lg, 1.5rem);
          background: var(--card, #fff);
          border-bottom: 2px solid var(--border, #e5e5e5);
          font-size: var(--boxel-font-size-xs, 0.75rem);
          font-weight: 600;
          color: var(--muted-foreground, #6b7280);
          text-transform: uppercase;
        }

        .table-body {
          flex: 1;
          overflow-y: auto;
          background: var(--card, #fff);
        }

        .table-row {
          display: grid;
          grid-template-columns: 100px 1fr 80px 100px 100px 110px;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding: var(--boxel-sp-sm, 0.75rem) var(--boxel-sp-lg, 1.5rem);
          border-bottom: 1px solid var(--border, #e5e5e5);
          font-size: var(--boxel-font-size-sm, 0.875rem);
          align-items: center;
        }

        .table-row:hover { background: var(--muted, #f5f5f5); }

        .col-date {
          color: var(--muted-foreground, #6b7280);
          font-variant-numeric: tabular-nums;
        }

        .col-desc {
          font-weight: 500;
          color: var(--foreground, #1a1a1a);
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs, 0.5rem);
          overflow: hidden;
        }

        .category-tag {
          font-size: var(--boxel-font-size-xs, 0.75rem);
          padding: 2px 6px;
          background: var(--muted, #f5f5f5);
          border-radius: 4px;
          color: var(--muted-foreground, #6b7280);
          flex-shrink: 0;
        }

        .col-ref {
          color: var(--muted-foreground, #6b7280);
          font-size: var(--boxel-font-size-xs, 0.75rem);
        }

        .col-debit, .col-credit, .col-balance {
          text-align: right;
          font-variant-numeric: tabular-nums;
          font-weight: 500;
        }

        .col-debit { color: hsl(0 84% 50%); }
        .col-credit { color: hsl(142 76% 36%); }
        .col-balance { color: var(--foreground, #1a1a1a); }

        .empty-state {
          padding: var(--boxel-sp-2xl, 3rem);
          text-align: center;
          color: var(--muted-foreground, #6b7280);
        }
      </style>
    </template>

    get isCredit() { return this.newType === 'credit'; }
    get isDebit() { return this.newType === 'debit'; }
  };

  static embedded = class Embedded extends Component<typeof SingleEntryAccountLedger> {
    get balance() {
      let bal = this.args.model?.openingBalance ?? 0;
      for (const entry of this.args.model?.entries ?? []) {
        bal += (entry.credit ?? 0) - (entry.debit ?? 0);
      }
      return bal;
    }

    get balanceDisplay() {
      const bal = this.balance;
      const formatted = Math.abs(bal).toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
      return bal >= 0 ? `$${formatted}` : `-$${formatted}`;
    }

    <template>
      <div class="embedded">
        <span class="icon">📒</span>
        <div class="info">
          <span class="name">{{if @model.accountName @model.accountName "Account Ledger"}}</span>
          <span class="badge">Single-Entry</span>
          <span class="balance">{{this.balanceDisplay}}</span>
        </div>
      </div>

      <style scoped>
        .embedded {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm, 0.75rem);
          padding: var(--boxel-sp-xs, 0.5rem);
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }
        .icon { font-size: 1.5rem; }
        .info { display: flex; flex-direction: column; }
        .name { font-weight: 600; color: var(--foreground, #1a1a1a); }
        .badge {
          font-size: 0.625rem;
          padding: 1px 4px;
          background: hsl(200 80% 90%);
          color: hsl(200 80% 35%);
          border-radius: 2px;
          width: fit-content;
        }
        .balance {
          font-size: var(--boxel-font-size-sm, 0.875rem);
          color: var(--muted-foreground, #6b7280);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof SingleEntryAccountLedger> {
    get balance() {
      let bal = this.args.model?.openingBalance ?? 0;
      for (const entry of this.args.model?.entries ?? []) {
        bal += (entry.credit ?? 0) - (entry.debit ?? 0);
      }
      return bal;
    }

    get balanceShort() {
      const bal = this.balance;
      const abs = Math.abs(bal);
      const sign = bal >= 0 ? '' : '-';
      if (abs >= 1000000) return `${sign}$${(abs / 1000000).toFixed(1)}M`;
      if (abs >= 1000) return `${sign}$${(abs / 1000).toFixed(1)}K`;
      return `${sign}$${abs.toFixed(0)}`;
    }

    get entryCount() {
      return this.args.model?.entries?.length ?? 0;
    }

    <template>
      <div class="fitted">
        <div class="badge">
          <span class="balance">{{this.balanceShort}}</span>
        </div>
        <div class="strip">
          <span class="icon">📒</span>
          <span class="name">{{if @model.accountName @model.accountName "Ledger"}}</span>
          <span class="balance">{{this.balanceShort}}</span>
        </div>
        <div class="tile">
          <span class="icon">📒</span>
          <span class="name">{{if @model.accountName @model.accountName "Account Ledger"}}</span>
          <span class="variant">Single-Entry</span>
          <span class="balance">{{this.balanceShort}}</span>
          <span class="meta">{{this.entryCount}} entries</span>
        </div>
      </div>

      <style scoped>
        .fitted {
          container-type: size;
          width: 100%;
          height: 100%;
          font-family: var(--font-sans, 'Inter', -apple-system, sans-serif);
        }

        .badge, .strip, .tile { display: none; }

        @container (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100%;
            background: var(--card, #fff);
          }
          .badge .balance {
            font-size: 1.25rem;
            font-weight: 700;
            color: hsl(200 80% 40%);
          }
        }

        @container (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm, 0.75rem);
            height: 100%;
            padding: 0 var(--boxel-sp, 1rem);
            background: var(--card, #fff);
          }
          .strip .icon { font-size: 1.25rem; }
          .strip .name { flex: 1; font-weight: 600; font-size: 0.875rem; }
          .strip .balance { font-weight: 700; color: hsl(200 80% 40%); }
        }

        @container (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 4px;
            height: 100%;
            padding: var(--boxel-sp, 1rem);
            background: var(--card, #fff);
            text-align: center;
          }
          .tile .icon { font-size: 2rem; }
          .tile .name { font-weight: 600; font-size: 1rem; }
          .tile .variant {
            font-size: 0.625rem;
            padding: 1px 4px;
            background: hsl(200 80% 90%);
            color: hsl(200 80% 35%);
            border-radius: 2px;
          }
          .tile .balance {
            font-size: 1.25rem;
            font-weight: 700;
            color: hsl(200 80% 40%);
          }
          .tile .meta {
            font-size: 0.75rem;
            color: var(--muted-foreground, #6b7280);
          }
        }
      </style>
    </template>
  };
}
