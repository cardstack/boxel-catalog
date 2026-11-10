// The desk's report surfaces that aren't a statement card: the library reports, each a customization
// of the posting lines or a list of records, and My reports, which reopens a saved report.
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { identifyCard } from '@cardstack/runtime-common';
import type { CardContext, CardDef } from '@cardstack/base/card-api';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import { DataTable } from '@cardstack/pretui/components/data-table';
import { SavedReport } from './ledger-saved-report';
import {
  CustomReportRunner,
  PRESETS,
  applySettings,
  instancesOf,
  loadingOf,
} from './ledger-report-custom';
import { ListReport, LIST_REPORTS } from './ledger-report-lists';

/** Whether a report kind is one the library runs here, rather than a desk statement card. */
export const isLibraryKind = (kind: string | undefined) =>
  !!PRESETS[kind ?? ''] || !!LIST_REPORTS[kind ?? ''];
export const libraryLabel = (kind: string) =>
  PRESETS[kind]?.label ?? LIST_REPORTS[kind]?.label ?? kind;

// A fresh object for each kind and saved report, so the each above remounts on a change.
const one = (kind: string | undefined, saved?: SavedReport) => [
  { kind: kind ?? '', saved },
];

interface LibrarySignature {
  Args: {
    context?: CardContext;
    realms: string[];
    refRealms?: string[];
    ledger?: CardDef;
    kind?: string;
    saved?: SavedReport;
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
type SavedRow = {
  id: string;
  name: string;
  kindLabel: string;
  period: string;
  savedBy: string;
  visibility: string;
  card: SavedReport;
};
const SAVED_COLUMNS = [
  { key: 'name', label: 'Name' },
  { key: 'kindLabel', label: 'Report' },
  { key: 'period', label: 'Period', mono: true },
  { key: 'visibility', label: 'Shared' },
  { key: 'savedBy', label: 'Saved by', mono: true },
];
/** The saved reports in the books, each opening with its settings applied. */
export class MyReports extends GlimmerComponent<MineSignature> {
  @tracked open: SavedReport | undefined;
  savedData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: { type: identifyCard(SavedReport) },
        sort: [{ by: 'name', on: identifyCard(SavedReport) }],
        page: { size: 200 },
      }) as never,
    () => this.args.realms,
    { isLive: true },
  );
  get loading() {
    return loadingOf(this.savedData);
  }
  get rows(): SavedRow[] {
    return instancesOf(this.savedData).map((c: SavedReport) => ({
      id: c.id,
      name: c.name ?? '',
      kindLabel: c.kindLabel || c.kind || '',
      period: c.asOfMonth
        ? `as of ${c.asOfMonth}`
        : [c.fromMonth, c.toMonth].filter(Boolean).join(' – '),
      savedBy: c.savedBy ?? '',
      visibility: c.visibility === 'private' ? 'Only its saver' : 'Shared',
      card: c,
    }));
  }
  rowKey = (r: SavedRow) => r.id;
  rowLabel = (r: SavedRow) => r.name;
  isRunner = (kind: string | undefined) => isLibraryKind(kind ?? '');
  openReport = (r: SavedRow) => {
    let c = r.card;
    if (this.isRunner(c.kind)) {
      this.open = c;
      return;
    }
    let page = this.args.pages.find((p) => p.id === c.kind);
    if (!page) return;
    applySettings((this.args.app as any)?.[page.report], c.settings());
    this.args.onOpenPage(page.id);
  };
  back = () => (this.open = undefined);
  <template>
    {{#if this.open}}
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
    </style>
  </template>
}
