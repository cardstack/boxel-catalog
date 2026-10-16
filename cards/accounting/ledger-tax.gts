// Information returns as cards: each vendor's tax profile (entity, W-9), and the year's 1099-NEC
// report computed from the bill payments in the journal.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { Vendor } from './ledger-cards';
import { JournalMonth, journalPostings } from './ledger-journal';
import {
  Sheet,
  Part,
  Facts,
  Strip,
  Fit,
  money,
  toneFor,
  type Fact,
} from './record-kit';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';

export class VendorTaxProfile extends CardDef {
  static displayName = 'Vendor tax profile';
  static icon = BookIcon;
  @field vendor = linksTo(() => Vendor);
  @field vendorId = contains(StringField);
  @field name = contains(StringField);
  @field entity = contains(StringField); // llc, corp, partnership, government, individual
  @field track1099 = contains(BooleanField);
  @field w9OnFile = contains(BooleanField);
  @field medicalLegal = contains(BooleanField); // corporations still get a 1099 for medical and legal services
  @field employee = contains(BooleanField); // employees get a W-2, not a 1099
  @field reportable = contains(BooleanField, {
    computeVia: function (this: VendorTaxProfile) {
      return (
        !!this.track1099 &&
        !this.employee &&
        (this.entity !== 'corp' || !!this.medicalLegal)
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: VendorTaxProfile) {
      return `Tax profile · ${this.name ?? this.vendorId ?? ''}`;
    },
  });
  static isolated = class extends Component<typeof VendorTaxProfile> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Vendor', value: m.vendorId ?? '', mono: true },
        { key: 'Entity', value: m.entity ?? '' },
        { key: 'Tracked for 1099', value: m.track1099 ? 'Yes' : 'No' },
        { key: 'W-9 on file', value: m.w9OnFile ? 'Yes' : 'No' },
        {
          key: 'Gets a 1099-NEC',
          value: m.reportable ? 'Yes' : 'No',
          strong: true,
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Vendor tax profile'
        @title={{@model.name}}
        @meta={{@model.vendorId}}
        @status={{if @model.reportable '1099' 'No 1099'}}
      ><Part @title='Profile'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof VendorTaxProfile> {
    <template>
      <Strip
        @eyebrow='Tax profile'
        @title={{@model.name}}
        @meta={{@model.entity}}
      />
    </template>
  };
  static fitted = class extends Component<typeof VendorTaxProfile> {
    <template>
      <Fit
        @eyebrow='Tax profile'
        @title={{@model.name}}
        @meta={{@model.entity}}
      />
    </template>
  };
}

export class Form1099Row extends FieldDef {
  @field vendorId = contains(StringField);
  @field name = contains(StringField);
  @field amountMinor = contains(NumberField);
  @field required = contains(BooleanField);
  @field w9OnFile = contains(BooleanField);
}

export class Form1099Report extends CardDef {
  static displayName = '1099-NEC report';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field year = contains(NumberField);
  @field fromDate = contains(StringField, {
    computeVia: function (this: Form1099Report) {
      return this.year ? `${this.year}-01-01` : '';
    },
  });
  @field toDate = contains(StringField, {
    computeVia: function (this: Form1099Report) {
      return this.year ? `${this.year}-12-31` : '';
    },
  });
  // The IRS threshold for the payment year: $600 through 2025, $2,000 for 2026.
  @field thresholdMinor = contains(NumberField, {
    computeVia: function (this: Form1099Report) {
      return !this.year ? 0 : this.year < 2026 ? 60000 : 200000;
    },
  });
  @field profiles = linksToMany(() => VendorTaxProfile, {
    query: { page: { size: 500 } },
  });
  @field fromMonth = contains(StringField, {
    computeVia: function (this: Form1099Report) {
      return this.year ? `${this.year}-01` : '';
    },
  });
  @field toMonth = contains(StringField, {
    computeVia: function (this: Form1099Report) {
      return this.year ? `${this.year}-12` : '';
    },
  });
  @field journal = linksToMany(() => JournalMonth, {
    query: {
      filter: {
        range: { month: { gte: '$this.fromMonth', lte: '$this.toMonth' } },
      },
      page: { size: 12 },
    },
  });
  @field rows = containsMany(Form1099Row, {
    computeVia: function (this: Form1099Report) {
      let paid = new Map<string, number>();
      for (let p of journalPostings(this.journal, ['bill-payment']))
        if (p.fact('method') !== 'card')
          paid.set(
            p.party,
            (paid.get(p.party) ?? 0) +
              p.lines.reduce((n, l) => n + (l.creditMinor ?? 0), 0),
          );
      return (this.profiles ?? [])
        .filter((v) => v?.reportable && paid.get(v.vendorId ?? ''))
        .map(
          (v) =>
            new Form1099Row({
              vendorId: v!.vendorId,
              name: v!.name,
              amountMinor: paid.get(v!.vendorId ?? '') ?? 0,
              required:
                (paid.get(v!.vendorId ?? '') ?? 0) >=
                (this.thresholdMinor ?? 0),
              w9OnFile: v!.w9OnFile,
            }),
        )
        .sort((a, b) => (b.amountMinor ?? 0) - (a.amountMinor ?? 0));
    },
  });
  @field requiredCount = contains(NumberField, {
    computeVia: function (this: Form1099Report) {
      return (this.rows ?? []).filter((r) => r?.required).length;
    },
  });
  @field missingW9 = contains(NumberField, {
    computeVia: function (this: Form1099Report) {
      return (this.rows ?? []).filter((r) => r?.required && !r.w9OnFile).length;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Form1099Report) {
      return `1099-NEC · ${this.year ?? ''}`;
    },
  });
  static isolated = class extends Component<typeof Form1099Report> {
    cols: Col[] = [
      { key: 'vendor', label: 'Vendor', kind: 'code' },
      { key: 'name', label: 'Name' },
      { key: 'paid', label: 'Paid', kind: 'amount' },
      { key: 'form', label: 'Form', kind: 'custom' },
      { key: 'w9', label: 'W-9', kind: 'custom' },
    ];
    get rows(): Line[] {
      let m = this.args.model,
        rows = (m.rows ?? []).filter(Boolean);
      return [
        ...rows.map((r) => ({
          key: r!.vendorId ?? '',
          cells: {
            vendor: r!.vendorId,
            name: r!.name,
            paid: r!.amountMinor,
            form: r!.required ? 'Required' : 'Below threshold',
            w9: r!.w9OnFile ? 'On file' : 'Missing',
          },
          data: { row: true, key: r!.vendorId, total: r!.amountMinor ?? 0 },
        })),
        {
          key: 'total',
          role: 'total' as const,
          cells: {
            vendor: '',
            name: 'Total',
            paid: rows.reduce((n, r) => n + (r!.amountMinor ?? 0), 0),
          },
        },
      ];
    }
    status = (v: unknown) => String(v ?? '');
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Threshold', value: money(m.thresholdMinor) },
        {
          key: 'Forms required',
          value: String(m.requiredCount ?? 0),
          strong: true,
        },
        { key: 'W-9s missing', value: String(m.missingW9 ?? 0) },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Information returns'
        @title={{@model.cardTitle}}
        @figure={{count @model.requiredCount}}
        @figureLabel='Forms to file'
        @note='Payments by check or ACH to vendors tracked for 1099, from the posted bill payments. Card payments are reported by the card processor (1099-K) and left out.'
      >
        <Part @title='Summary'><Facts @items={{this.facts}} /></Part>
        <Part @title='Vendors'>
          <StatementTable
            @label='Vendors paid'
            @columns={{this.cols}}
            @rows={{this.rows}}
          >
            <:cell as |value|>{{#if value}}<StatusChip
                  @value={{this.status value}}
                  @tone={{toneFor (this.status value)}}
                />{{/if}}</:cell>
          </StatementTable>
        </Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof Form1099Report> {
    <template>
      <Strip
        @eyebrow='1099-NEC'
        @title={{@model.cardTitle}}
        @meta='Forms required'
      />
    </template>
  };
  static fitted = class extends Component<typeof Form1099Report> {
    <template>
      <Fit
        @eyebrow='1099-NEC'
        @title={{@model.cardTitle}}
        @meta='Information returns'
      />
    </template>
  };
}
const count = (n: number | undefined) => `${n ?? 0}`;
