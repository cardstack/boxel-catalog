// The desk's report surfaces that aren't a statement card: the library reports, each a customization
// of the posting lines or a list of records, and My reports, which reopens a saved report.
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { getComponent } from '@cardstack/base/card-api';
import type { CardContext, CardDef } from '@cardstack/base/card-api';
import { Callout } from '@cardstack/pretui/components/callout';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import { DataTable } from '@cardstack/pretui/components/data-table';
import { operations } from '@cardstack/base/operations';
import {
  SavedReport,
  settingsOfSaved,
  type SavedLike,
} from './ledger-saved-report';
import {
  CustomReportRunner,
  PRESETS,
  ReportActions,
  statementCopy,
} from './ledger-report-custom';
import { ListReport, LIST_REPORTS } from './ledger-report-lists';

/** Whether a report kind is one the library runs here, rather than a desk statement card. */
export const isLibraryKind = (kind: string | null | undefined) =>
  !!PRESETS[kind ?? ''] || !!LIST_REPORTS[kind ?? ''];
export const libraryLabel = (kind: string) =>
  PRESETS[kind]?.label ?? LIST_REPORTS[kind]?.label ?? kind;

// A fresh object for each kind and saved report, so the each above remounts on a change.
const one = (kind: string | null | undefined, saved?: SavedLike) => [
  { kind: kind ?? '', saved },
];

interface LibrarySignature {
  Args: {
    context?: CardContext;
    realms: string[];
    refRealms?: string[];
    ledger?: CardDef;
    kind?: string | null;
    saved?: SavedLike;
  };
}
export class LibraryReport extends GlimmerComponent<LibrarySignature> {
  get isList() {
    return !!LIST_REPORTS[this.args.kind ?? ''];
  }
  <template>
    {{! One report per kind, so a new kind starts from its own settings. }}
    {{#each (one @kind @saved) as |k|}}
      {{#if this.isList}}
        <ListReport
          @context={{@context}}
          @realms={{@realms}}
          @refRealms={{@refRealms}}
          @ledger={{@ledger}}
          @kind={{k.kind}}
          @saved={{k.saved}}
        />
      {{else}}
        <CustomReportRunner
          @context={{@context}}
          @realms={{@realms}}
          @refRealms={{@refRealms}}
          @ledger={{@ledger}}
          @kind={{k.kind}}
          @saved={{k.saved}}
        />
      {{/if}}
    {{/each}}
  </template>
}

// ── My reports ──────────────────────────────────────────────────────────────
export interface ReportPage {
  id: string;
  label: string;
  report: string; // the desk field holding the statement card
}
interface MineSignature {
  Args: {
    context?: CardContext;
    realms: string[];
    refRealms?: string[];
    ledger?: CardDef;
    app: unknown; // the desk card, whose fields hold the statement cards
    pages: ReportPage[];
    onOpenPage: (id: string) => void;
  };
}
const eqKey = (a: unknown, b: unknown) => a === b;
const componentOf = (card: CardDef) => getComponent(card);
const SAVED_PAGE = 500;
type SavedRow = {
  id: string;
  name: string;
  kindLabel: string;
  period: string;
  savedBy: string;
  visibility: string;
  card: SavedLike;
};
/** A search row's saved report, as its stored values. */
export const savedOfEntry = (e: {
  id: string;
  item?: { attributes?: Record<string, unknown> } | unknown;
}): SavedLike => ({
  ...(((e.item as { attributes?: Record<string, unknown> })?.attributes ??
    {}) as SavedLike),
  id: e.id,
});
const SAVED_COLUMNS = [
  { key: 'name', label: 'Name' },
  { key: 'kindLabel', label: 'Report' },
  { key: 'period', label: 'Period', mono: true },
  { key: 'visibility', label: 'Shared' },
  { key: 'savedBy', label: 'Saved by', mono: true },
];
/** The saved reports in the books, each opening with its settings applied. */
export class MyReports extends GlimmerComponent<MineSignature> {
  @tracked open: SavedLike | undefined;
  @tracked statement: CardDef | undefined;
  @tracked statementKind = '';
  @tracked statementLabel = '';
  @tracked openError = '';
  // The realm answers with the shared reports and the viewer's own unlisted ones.
  visible = operations(SavedReport).visibleReports(
    {},
    { realms: this.args.realms, owner: this },
  );
  get loading() {
    return this.visible.isLoading && !this.visible.entries.length;
  }
  get capped() {
    let total = (this.visible.meta as any)?.page?.total;
    return (
      this.visible.entries.length >= SAVED_PAGE ||
      (typeof total === 'number' && total > this.visible.entries.length)
    );
  }
  get rows(): SavedRow[] {
    return this.visible.entries.map((e) => {
      let c = savedOfEntry(e);
      return {
        id: e.id,
        name: c.name ?? '',
        kindLabel: c.kindLabel || c.kind || '',
        period: c.asOfMonth
          ? `as of ${c.asOfMonth}`
          : [c.fromMonth, c.toMonth].filter(Boolean).join(' – '),
        savedBy: c.savedBy ?? '',
        visibility:
          c.visibility === 'private' ? 'Not listed for others' : 'Shared',
        card: c,
      };
    });
  }
  rowKey = (r: SavedRow) => r.id;
  rowLabel = (r: SavedRow) => r.name;
  isRunner = (kind: string | null | undefined) => isLibraryKind(kind ?? '');
  openReport = (r: SavedRow) => {
    let c = r.card;
    if (this.isRunner(c.kind)) {
      this.open = c;
      return;
    }
    let page = this.args.pages.find((p) => p.id === c.kind);
    let card = page && (this.args.app as any)?.[page.report];
    if (!page || !card) return;
    this.openStatement(card, c, page);
  };
  // A saved statement opens as its own unsaved copy, held only while it's shown here.
  openStatement = async (card: CardDef, c: SavedLike, page: ReportPage) => {
    this.openError = '';
    let copy = statementCopy(card, settingsOfSaved(c));
    try {
      let store = this.args.context?.store;
      this.statement = store
        ? await store.addWithoutPersisting(copy, { realm: this.args.realms[0] })
        : copy;
      this.statementKind = page.id;
      this.statementLabel = c.name || page.label;
    } catch (e: any) {
      this.openError = e?.message ?? String(e);
    }
  };
  back = () => {
    this.open = undefined;
    this.statement = undefined;
  };
  <template>
    {{#if this.openError}}<Callout
        @tone='danger'
        @title="The report didn't open"
      >{{this.openError}}</Callout>{{/if}}
    {{#if this.statement}}
      <div class='mine-back'><Button
          @appearance='plain'
          @size='s'
          {{on 'click' this.back}}
        >← My reports</Button></div>
      <section class='report' data-report-body>
        <ReportActions
          @context={{@context}}
          @ledger={{@ledger}}
          @kind={{this.statementKind}}
          @kindLabel={{this.statementLabel}}
          @card={{this.statement}}
        />
        {{#let (componentOf this.statement) as |Statement|}}<Statement
            @format='isolated'
          />{{/let}}
      </section>
    {{else if this.open}}
      <div class='mine-back'><Button
          @appearance='plain'
          @size='s'
          {{on 'click' this.back}}
        >← My reports</Button></div>
      <LibraryReport
        @context={{@context}}
        @realms={{@realms}}
        @refRealms={{@refRealms}}
        @ledger={{@ledger}}
        @kind={{this.open.kind}}
        @saved={{this.open}}
      />
    {{else if this.loading}}
      <Skeleton @height='6rem' />
    {{else if this.rows.length}}
      {{#if this.capped}}<Callout
          @tone='warning'
          @title='Not every report is listed'
        >
          Only the first
          {{SAVED_PAGE}}
          saved reports are listed.
        </Callout>{{/if}}
      <p class='muted'>A report saved as not listed for others is left out of
        their lists, but anyone who can read the books can still open it by its
        link or find it in a search.</p>
      <DataTable
        @columns={{SAVED_COLUMNS}}
        @rows={{this.rows}}
        @key={{this.rowKey}}
        @rowLabel={{this.rowLabel}}
        @label='My reports'
        @size='s'
        data-saved-reports
      >
        <:cell as |text row col|>
          {{#if (eqKey col.key 'name')}}<Button
              @appearance='link'
              @tone='neutral'
              @size='s'
              data-test-open-saved-report={{row.name}}
              {{on 'click' (fn this.openReport row)}}
            >{{text}}</Button>{{else}}{{text}}{{/if}}
        </:cell>
      </DataTable>
    {{else}}
      <EmptyState
        @title='No saved reports yet'
        @message='Open any report, set it up the way you want it, then choose Save as. It lists here and opens with those settings.'
      />
    {{/if}}
    <style scoped>
      .mine-back {
        margin-bottom: var(--boxel-sp-xs);
      }
      .muted {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
