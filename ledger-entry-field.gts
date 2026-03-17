// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  FieldDef, // ¹ FieldDef for embedded data
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';

export class LedgerEntryField extends FieldDef { // ² FieldDef, not CardDef
  static displayName = 'Ledger Entry';

  @field entryDate = contains(DateField);
  @field description = contains(StringField);
  @field debit = contains(NumberField);
  @field credit = contains(NumberField);
  @field reference = contains(StringField);
  @field category = contains(StringField);

  // ³ Embedded template for display within parent
  static embedded = class Embedded extends Component<typeof LedgerEntryField> {
    get debitDisplay() {
      const d = this.args.model?.debit;
      if (!d || d <= 0) return '';
      return d.toLocaleString('en-US', { minimumFractionDigits: 2 });
    }

    get creditDisplay() {
      const c = this.args.model?.credit;
      if (!c || c <= 0) return '';
      return c.toLocaleString('en-US', { minimumFractionDigits: 2 });
    }

    <template>
      <div class="entry-row">
        <span class="date">{{if @model.entryDate @model.entryDate "—"}}</span>
        <span class="desc">{{if @model.description @model.description "—"}}</span>
        <span class="ref">{{if @model.reference @model.reference ""}}</span>
        <span class="debit">{{this.debitDisplay}}</span>
        <span class="credit">{{this.creditDisplay}}</span>
      </div>

      <style scoped>
        .entry-row {
          display: grid;
          grid-template-columns: 100px 1fr 80px 90px 90px;
          gap: 0.5rem;
          padding: 0.5rem 0.75rem;
          font-size: 0.875rem;
          border-bottom: 1px solid var(--border, #e5e5e5);
          align-items: center;
        }
        .entry-row:hover { background: var(--muted, #f5f5f5); }
        .date { color: var(--muted-foreground, #6b7280); }
        .desc { font-weight: 500; }
        .ref { color: var(--muted-foreground, #6b7280); font-size: 0.75rem; }
        .debit, .credit { text-align: right; font-weight: 500; }
        .debit { color: hsl(0 84% 50%); }
        .credit { color: hsl(142 76% 36%); }
      </style>
    </template>
  };
}
