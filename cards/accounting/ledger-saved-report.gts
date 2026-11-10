// A report someone saved: which report, its settings and its customization, under a name, with who
// saved it. The desk lists these under My reports and opens each with its settings applied. This
// module imports nothing from the books so the ledger can declare the operation that saves one.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import enumField from '@cardstack/base/enum';
import BookmarkIcon from '@cardstack/boxel-icons/bookmark';
import {
  operation,
  actor,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { Sheet, Part, Facts, Strip, Fit, type Fact } from './record-kit';

/** What a report's lines can be filtered and grouped by. */
export const DIMENSIONS = [
  { value: 'account', label: 'Account' },
  { value: 'cls', label: 'Class' },
  { value: 'loc', label: 'Location' },
  { value: 'customer', label: 'Customer' },
  { value: 'vendor', label: 'Vendor' },
  { value: 'project', label: 'Project' },
] as const;
export type Dimension = (typeof DIMENSIONS)[number]['value'];

export const ReportVisibilityField = enumField(StringField, {
  displayName: 'Report visibility',
  options: [
    { value: 'shared', label: "Shared with the books' users" },
    { value: 'private', label: 'Not listed for others' },
  ],
});

export class ReportFilter extends FieldDef {
  static displayName = 'Report filter';
  @field dimension = contains(StringField);
  @field value = contains(StringField);
}

/** The plain shape of a report's customization, as the engine reads it. */
export interface Customization {
  columns: string[]; // the column keys shown, in order; empty shows the report's own
  filters: { dimension: string; value: string }[];
  groupBy: string; // a dimension, or '' for none
  sortBy: string; // a column key, or '' for the report's own order
  sortDir: 'asc' | 'desc';
}
export const NO_CUSTOMIZATION: Customization = {
  columns: [],
  filters: [],
  groupBy: '',
  sortBy: '',
  sortDir: 'asc',
};

/** A saved report's stored values, from the card or from a search row's attributes. */
export interface SavedLike {
  id?: string;
  name?: string | null;
  kind?: string | null;
  kindLabel?: string | null;
  fromMonth?: string | null;
  toMonth?: string | null;
  asOfMonth?: string | null;
  basis?: string | null;
  columns?: string | null;
  compare?: string | null;
  account?: string | null;
  statement?: string | null;
  columnKeys?: string | null;
  filters?: ({ dimension?: string | null; value?: string | null } | null)[];
  groupBy?: string | null;
  sortBy?: string | null;
  sortDir?: string | null;
  visibility?: string | null;
  savedBy?: string | null;
}

/** The saved settings of a report, as plain values. */
export interface SavedSettings {
  fromMonth: string;
  toMonth: string;
  asOfMonth: string;
  basis: string;
  columns: string;
  compare: string;
  account: string;
  // A desk statement's own settings, as JSON: whichever of its period, date, year and account
  // fields it has, so it reopens with exactly those.
  statement: string;
}

export class SavedReport extends CardDef {
  static displayName = 'Saved report';
  static icon = BookmarkIcon;
  @field name = contains(StringField);
  @field kind = contains(StringField); // the report it reopens: a desk report page, or a library report
  @field kindLabel = contains(StringField);
  @field fromMonth = contains(StringField);
  @field toMonth = contains(StringField);
  @field asOfMonth = contains(StringField);
  @field basis = contains(StringField);
  @field columns = contains(StringField);
  @field compare = contains(StringField);
  @field account = contains(StringField);
  @field statement = contains(StringField);
  @field columnKeys = contains(StringField); // comma-separated, in order
  @field filters = containsMany(ReportFilter);
  @field groupBy = contains(StringField);
  @field sortBy = contains(StringField);
  @field sortDir = contains(StringField);
  @field visibility = contains(ReportVisibilityField);
  @field savedBy = contains(StringField); // stamped by the realm: actor()
  @field cardTitle = contains(StringField, {
    computeVia: function (this: SavedReport) {
      return this.name || 'Saved report';
    },
  });

  customization(): Customization {
    return customizationOf(this);
  }
  settings(): SavedSettings {
    return settingsOfSaved(this);
  }

  // The reports a viewer may see: every shared one, and the private ones they saved. The realm runs
  // it with the caller it authenticated, so who is asking isn't the caller's to say.
  @operation static visibleReports = {
    base: 'query',
    query: {
      filter: {
        every: [
          { type: () => SavedReport },
          {
            any: [
              { on: () => SavedReport, eq: { visibility: 'shared' } },
              { on: () => SavedReport, eq: { savedBy: actor() } },
            ],
          },
        ],
      },
      sort: [{ on: () => SavedReport, by: 'name', direction: 'asc' }],
      page: { size: 500 }, // My reports warns when it is full
    },
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof SavedReport> {
    get facts(): Fact[] {
      let m = this.args.model,
        c = customizationOf(m);
      return [
        { key: 'Report', value: m.kindLabel || m.kind || '' },
        {
          key: 'Period',
          value: m.asOfMonth
            ? `As of ${m.asOfMonth}`
            : [m.fromMonth, m.toMonth].filter(Boolean).join(' to '),
        },
        ...(m.basis ? [{ key: 'Basis', value: m.basis }] : []),
        ...(c.columns.length
          ? [{ key: 'Columns', value: c.columns.join(', ') }]
          : []),
        ...(c.filters.length
          ? [
              {
                key: 'Filters',
                value: c.filters
                  .map((f) => `${f.dimension} is ${f.value}`)
                  .join('; '),
              },
            ]
          : []),
        ...(c.groupBy ? [{ key: 'Grouped by', value: c.groupBy }] : []),
        ...(c.sortBy
          ? [{ key: 'Sorted by', value: `${c.sortBy} (${c.sortDir})` }]
          : []),
        {
          key: 'Visibility',
          value:
            m.visibility === 'private' ? 'Not listed for others' : 'Shared',
        },
        { key: 'Saved by', value: m.savedBy ?? '' },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Saved report'
        @title={{@model.cardTitle}}
        @meta={{@model.kindLabel}}
        @note='Open it from My reports in the books to run it with these settings.'
      >
        <Part @title='Settings'><Facts @items={{this.facts}} /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof SavedReport> {
    <template>
      <Strip
        @eyebrow='Saved report'
        @title={{@model.cardTitle}}
        @meta={{@model.kindLabel}}
      />
    </template>
  };
  static fitted = class extends Component<typeof SavedReport> {
    <template>
      <Fit
        @eyebrow='Saved report'
        @title={{@model.cardTitle}}
        @meta={{@model.kindLabel}}
      />
    </template>
  };
}

/** A saved report's settings as plain values. */
export const settingsOfSaved = (m: SavedLike): SavedSettings => ({
  fromMonth: m.fromMonth ?? '',
  toMonth: m.toMonth ?? '',
  asOfMonth: m.asOfMonth ?? '',
  basis: m.basis ?? '',
  columns: m.columns ?? '',
  compare: m.compare ?? '',
  account: m.account ?? '',
  statement: m.statement ?? '',
});

/** A saved report's customization as plain values. */
export function customizationOf(m: {
  columnKeys?: string | null;
  filters?: ({ dimension?: string | null; value?: string | null } | null)[];
  groupBy?: string | null;
  sortBy?: string | null;
  sortDir?: string | null;
}): Customization {
  return {
    columns: (m.columnKeys ?? '')
      .split(',')
      .map((k) => k.trim())
      .filter(Boolean),
    filters: (m.filters ?? [])
      .filter((f) => f?.dimension && f?.value)
      .map((f) => ({ dimension: f!.dimension!, value: f!.value! })),
    groupBy: m.groupBy ?? '',
    sortBy: m.sortBy ?? '',
    sortDir: m.sortDir === 'desc' ? 'desc' : 'asc',
  };
}
