import type { AuditComplianceDesk } from './audit-compliance-desk';
import { Component, realmURL } from '@cardstack/base/card-api';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import { Stat } from '@cardstack/pretui/components/stat';
import { eq } from '@cardstack/boxel-ui/helpers';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import type Owner from '@ember/owner';
import BookOpenIcon from '@cardstack/boxel-icons/book-open';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import PlusIcon from '@cardstack/boxel-icons/plus';

import {
  Document,
  DOCUMENT_KIND_LABELS,
  kindTone,
  hueTone,
} from '../audit/document';
import { shortHash } from '../audit/utils/evidence-hash';
import {
  SEVERITY_LEVELS,
  SEVERITY_LABELS,
  SEVERITY_HUE,
} from '../audit/severity-vocabulary';
import {
  EVALUATION_STATUSES,
  EVALUATION_LABELS,
  EVALUATION_HUE,
} from '@cardstack/catalog/fields/evaluation-status/evaluation-status-field';
import {
  RESOLUTION_CODES,
  RESOLUTION_LABELS,
  RESOLUTION_HUE,
} from '@cardstack/catalog/fields/resolution-code/resolution-code-field';
import {
  TRUST_LEVELS,
  TRUST_LABELS,
  TRUST_HUE,
} from '@cardstack/catalog/fields/trust-metadata/trust-metadata-field';

type Tab = 'evidence' | 'vocabulary';

const TABS: { key: Tab; label: string; title: string; sub: string }[] = [
  {
    key: 'evidence',
    label: 'Evidence',
    title: 'Evidence register',
    sub: 'Every artefact the desk can produce on request, with the hash recorded when it was taken. An unhashed document is a record, not yet evidence.',
  },
  {
    key: 'vocabulary',
    label: 'Vocabulary',
    title: 'Vocabulary',
    sub: 'The closed vocabularies every audit surface reads. One definition each, so a verdict cannot mean two things.',
  },
];

const KIND_FILTERS = [
  { value: 'all', label: 'All' },
  { value: 'policy', label: 'Policy' },
  { value: 'evidence', label: 'Evidence' },
  { value: 'report', label: 'Report' },
];

const ORDER_FILTERS = [
  { value: 'all', label: 'All' },
  { value: 'ordered', label: 'Ordered' },
  { value: 'unordered', label: 'Unordered' },
];

// LayoutControl forms, richest first; minWidth in rem.
const forms = (...list: [string, number][]) =>
  list.map(([name, minWidth]) => ({ name, minWidth }));
const SEARCH_FORMS = forms(['field', 12], ['menu', 0]);
const CHIP_FORMS = forms(['chips', 14], ['menu', 0]);
const ADD_FORMS = forms(['label', 8], ['icon', 2]);

interface VocabRow {
  label: string;
  tone?: string;
}
interface Vocab {
  title: string;
  note: string;
  ordered: boolean;
  rows: VocabRow[];
}

function vocab(
  title: string,
  note: string,
  ordered: boolean,
  values: readonly string[],
  labels: Record<string, string>,
  hues: Record<string, string>,
): Vocab {
  return {
    title,
    note,
    ordered,
    rows: values.map((v) => ({ label: labels[v] ?? v, tone: hueTone(hues[v]) })),
  };
}

const VOCABULARIES: Vocab[] = [
  vocab(
    'Severity',
    'How bad a finding is. Major and above put the certificate at risk.',
    true,
    SEVERITY_LEVELS,
    SEVERITY_LABELS,
    SEVERITY_HUE,
  ),
  vocab(
    'Evaluation status',
    'The outcome of one rule against one subject. Unproven counts against coverage, never as a pass.',
    false,
    EVALUATION_STATUSES,
    EVALUATION_LABELS,
    EVALUATION_HUE,
  ),
  vocab(
    'Trust',
    'How far an artefact can be relied on, in order. Self-asserted is dull, not alarming.',
    true,
    TRUST_LEVELS,
    TRUST_LABELS,
    TRUST_HUE,
  ),
  vocab(
    'Resolution',
    'How a finding was closed. Remediated needs the action done; risk-accepted needs an approval.',
    false,
    RESOLUTION_CODES,
    RESOLUTION_LABELS,
    RESOLUTION_HUE,
  ),
];

const ROADMAP = [
  {
    title: 'Programme',
    text: 'Regimes, rules and the auditor arrive with Validation Rule and Auditor Bot.',
  },
  {
    title: 'Fieldwork',
    text: 'Findings and their proof arrive with Finding and the Audit command.',
  },
  {
    title: 'Report',
    text: 'Results, coverage and sign-off arrive with Audit Result and Standard Evaluation Report.',
  },
];

const inc = (n: number) => n + 1;

export class AuditComplianceDeskIsolated extends Component<
  typeof AuditComplianceDesk
> {
  @tracked tab: Tab = 'evidence';
  @tracked docSearch = '';
  @tracked docKind = 'all';
  @tracked vocabSearch = '';
  @tracked vocabOrder = 'all';

  private documentList: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.documentList = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(Document);
        return ref
          ? {
              filter: { type: ref },
              sort: [{ by: 'lastModified', direction: 'desc' }],
            }
          : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  private get realms(): string[] | undefined {
    let url = this.args.model?.[realmURL];
    return url ? [url.href] : undefined;
  }

  // Prerender has no host CRUD; it gets the shell and the counts.
  get isInteractive() {
    return Boolean(this.args.viewCard);
  }

  get current() {
    return TABS.find((t) => t.key === this.tab) ?? TABS[0];
  }

  get documents(): Document[] {
    return ((this.documentList?.instances ?? []) as Document[]).filter(Boolean);
  }

  get isLoading() {
    return Boolean(this.documentList?.isLoading);
  }

  get hashedCount() {
    return this.documents.filter((d) => (d.contentHash ?? '').trim()).length;
  }

  get stats() {
    let total = this.documents.length;
    let hashed = this.hashedCount;
    let pct = total ? Math.round((hashed / total) * 100) : 0;
    let dash = this.isLoading;
    return [
      {
        label: 'Documents',
        value: dash ? '—' : total,
        hint: 'in this realm',
      },
      {
        label: 'Hashed',
        value: dash ? '—' : hashed,
        tone: 'success',
        hint: `${pct}% usable as evidence`,
      },
      {
        label: 'Not yet hashed',
        value: dash ? '—' : total - hashed,
        tone: 'destructive',
        hint: 'records, not evidence',
      },
      {
        label: 'Superseding',
        value: dash ? '—' : this.documents.filter((d) => d.supersedes).length,
        tone: 'info',
        hint: 'replacement chain kept',
      },
    ];
  }

  get rows() {
    let q = this.docSearch.trim().toLowerCase();
    return this.documents
      .filter((d) => this.docKind === 'all' || d.kind === this.docKind)
      .filter((d) => !q || (d.cardTitle ?? '').toLowerCase().includes(q))
      .map((d) => {
        let hashed = Boolean((d.contentHash ?? '').trim());
        return {
          card: d,
          title: d.cardTitle,
          kind: DOCUMENT_KIND_LABELS[d.kind ?? ''] ?? '—',
          kindTone: kindTone(d.kind),
          hashed,
          hash: shortHash(d.contentHash),
          hasFile: Boolean(d.file),
          supersedes: d.supersedes?.cardTitle ?? '—',
        };
      });
  }

  get vocabularies() {
    let q = this.vocabSearch.trim().toLowerCase();
    return VOCABULARIES.filter(
      (v) =>
        this.vocabOrder === 'all' ||
        v.ordered === (this.vocabOrder === 'ordered'),
    )
      .map((v) => ({
        ...v,
        rows: q
          ? v.rows.filter((r) => r.label.toLowerCase().includes(q))
          : v.rows,
      }))
      .filter((v) => v.rows.length);
  }

  get navItems() {
    return [
      {
        key: 'evidence' as Tab,
        label: 'Evidence',
        icon: FileTextIcon,
        badge: this.isLoading ? undefined : String(this.documents.length),
      },
      {
        key: 'vocabulary' as Tab,
        label: 'Vocabulary',
        icon: BookOpenIcon,
        badge: String(VOCABULARIES.length),
      },
    ];
  }


  @action setTab(key: Tab) {
    this.tab = key;
  }
  @action setDocSearch(value: string) {
    this.docSearch = value;
  }
  @action setDocKind(value: string) {
    this.docKind = value;
  }
  @action setVocabSearch(value: string) {
    this.vocabSearch = value;
  }
  @action setVocabOrder(value: string) {
    this.vocabOrder = value;
  }
  @action openCard(card: Document) {
    this.args.viewCard?.(card, 'isolated');
  }

  // Quick-add files evidence: that is what arrives here. A policy or a report
  // is filed deliberately, and the kind stays editable.
  @action newDocument() {
    let ref = identifyCard(Document);
    let realm = this.realms?.[0];
    if (!ref || !realm) {
      return;
    }
    this.args.createCard?.(ref, undefined, {
      realmURL: new URL(realm),
      doc: {
        data: { attributes: { kind: 'evidence' }, meta: { adoptsFrom: ref } },
      },
    });
  }

  <template>
    <Sidebar
      class='acd-shell'
      @label='Audit & Compliance'
      @collapsible='rail'
      @railBreakpoint={{1100}}
      @mobileBreakpoint={{720}}
      @scroll='content'
      @resizable={{true}}
      @width='13.5rem'
      @shortcut={{false}}
    >
      <:header as |bar|>
        <div class='brand'>
          <span class='mark' aria-hidden='true'>AC</span>
          {{#unless bar.collapsed}}
            <p class='brand-text'>
              <small class='eyebrow'>Audit &amp; Compliance</small>
              {{@model.organisation}}
            </p>
          {{/unless}}
        </div>
      </:header>
      <:nav as |bar|>
        <SidebarGroup @label='Desk'>
          {{#each this.navItems as |item|}}
            <SidebarItem
              @label={{item.label}}
              @icon={{item.icon}}
              @badge={{unless bar.collapsed item.badge}}
              @active={{eq this.tab item.key}}
              @collapsed={{bar.collapsed}}
              @onClick={{fn this.setTab item.key}}
            />
          {{/each}}
        </SidebarGroup>
      </:nav>
      <:footer as |bar|>
        {{#unless bar.collapsed}}
          {{#if @model.authority}}
            <p class='foot'>Certified by {{@model.authority.name}}</p>
          {{/if}}
        {{/unless}}
      </:footer>
      <:default as |bar|>
        <div class='layout'>
          <main class='main'>
            {{#if bar.mobile}}
              <SidebarTrigger
                @open={{bar.open}}
                @onToggle={{bar.toggle}}
                @controls={{bar.controls}}
                @label='navigation'
              />
            {{/if}}
            <header class='head'>
              <p class='eyebrow'>Audit &amp; Compliance · {{this.current.label}}</p>
              <h1 class='h1'>{{this.current.title}}</h1>
              <p class='sub'>{{this.current.sub}}</p>
            </header>

            {{#if (eq this.tab 'evidence')}}
              <section class='stats' aria-label='Register totals'>
                <div class='stat-cells'>
                  {{#each this.stats as |st|}}
                    <div class='stat'>
                      <Stat
                        @label={{st.label}}
                        @value={{st.value}}
                        @tone={{st.tone}}
                        @hint={{st.hint}}
                        @roll={{false}}
                      />
                    </div>
                  {{/each}}
                </div>
              </section>

              {{#if this.isInteractive}}
                <LayoutControl
                  @label='Register tools'
                  @controlHeight='1.625rem'
                  as |lc|
                >
                  <lc.Slot
                    @id='search'
                    @priority={{2}}
                    @forms={{SEARCH_FORMS}}
                    @label='Search'
                  >
                    <div class='search'><SearchInput
                        @value={{this.docSearch}}
                        @placeholder='Search documents…'
                        @onInput={{this.setDocSearch}}
                      /></div>
                  </lc.Slot>
                  <lc.Slot
                    @id='kind'
                    @priority={{1}}
                    @forms={{CHIP_FORMS}}
                    @label='Kind'
                  >
                    <FilterChips
                      @options={{KIND_FILTERS}}
                      @value={{this.docKind}}
                      @onValueChange={{this.setDocKind}}
                      @label='Kind'
                    />
                  </lc.Slot>
                  <lc.Slot
                    @id='add'
                    @priority={{0}}
                    @pinned={{true}}
                    @forms={{ADD_FORMS}}
                    @label='New document'
                    as |form|
                  >
                    <Button
                      class='push'
                      @icon={{PlusIcon}}
                      @tone='primary'
                      @size='s'
                      @display={{if (eq form 'icon') 'icon' 'label'}}
                      @label='New document'
                      {{on 'click' this.newDocument}}
                    >New document</Button>
                  </lc.Slot>
                </LayoutControl>
              {{/if}}

              <section class='block' aria-labelledby='acd-docs'>
                <header class='block-head'>
                  <h2 id='acd-docs'>Documents</h2>
                  <span class='block-meta mono'>{{this.rows.length}}
                    documents · newest first</span>
                </header>
                {{#if this.isLoading}}
                  <p class='block-body muted' role='status'>Loading the
                    register…</p>
                {{else if this.rows.length}}
                  <div class='table-scroll'>
                    <table class='register'>
                      <thead>
                        <tr>
                          <th>Document</th>
                          <th>Kind</th>
                          <th>Hash</th>
                          <th>Artefact</th>
                          <th>Supersedes</th>
                        </tr>
                      </thead>
                      <tbody>
                        {{#each this.rows as |row|}}
                          <tr>
                            <td class='name-cell'>
                              <span class='doc-mark' aria-hidden='true'>Dc</span>
                              {{#if this.isInteractive}}
                                <Button
                                  class='name'
                                  @tone='neutral'
                                  @appearance='link'
                                  @size='s'
                                  {{on 'click' (fn this.openCard row.card)}}
                                >{{row.title}}</Button>
                              {{else}}
                                <span class='name'>{{row.title}}</span>
                              {{/if}}
                            </td>
                            <td><span class='st' data-tone={{row.kindTone}}><span
                                  class='dot'
                                ></span>{{row.kind}}</span></td>
                            <td>
                              {{#if row.hashed}}
                                <span class='mono muted'>{{row.hash}}</span>
                              {{else}}
                                <span class='st' data-tone='warn'><span
                                    class='dot'
                                  ></span>Not hashed</span>
                              {{/if}}
                            </td>
                            <td><span
                                class='st'
                                data-tone={{if row.hasFile 'ok'}}
                              ><span class='dot'></span>{{if
                                  row.hasFile
                                  'Attached'
                                  'No file'
                                }}</span></td>
                            <td class='muted'>{{row.supersedes}}</td>
                          </tr>
                        {{/each}}
                      </tbody>
                    </table>
                  </div>
                {{else}}
                  <div class='block-body'>
                    <EmptyState
                      @size='s'
                      @title='No documents match'
                      @message='A document is the artefact plus who owns it and what it replaced. Evidence arrives here before it is ever cited.'
                    />
                  </div>
                {{/if}}
              </section>
            {{else}}
              {{#if this.isInteractive}}
                <LayoutControl
                  @label='Vocabulary tools'
                  @controlHeight='1.625rem'
                  as |lc|
                >
                  <lc.Slot
                    @id='search'
                    @priority={{1}}
                    @forms={{SEARCH_FORMS}}
                    @label='Filter values'
                  >
                    <div class='search'><SearchInput
                        @value={{this.vocabSearch}}
                        @placeholder='Filter values…'
                        @onInput={{this.setVocabSearch}}
                      /></div>
                  </lc.Slot>
                  <lc.Slot
                    @id='order'
                    @priority={{2}}
                    @forms={{CHIP_FORMS}}
                    @label='Order'
                  >
                    <FilterChips
                      @options={{ORDER_FILTERS}}
                      @value={{this.vocabOrder}}
                      @onValueChange={{this.setVocabOrder}}
                      @label='Order'
                    />
                  </lc.Slot>
                </LayoutControl>
              {{/if}}

              <div class='vocab-grid'>
                {{#each this.vocabularies as |v|}}
                  <section class='block' aria-label={{v.title}}>
                    <header class='block-head'>
                      <h2>{{v.title}}</h2>
                      <span class='block-meta mono push'>{{v.rows.length}}
                        values</span>
                    </header>
                    <p class='note'>{{v.note}}</p>
                    <ul class='rows'>
                      {{#each v.rows as |r i|}}
                        <li class='row'>
                          {{#if v.ordered}}
                            <span class='rank mono'>{{inc i}}</span>
                          {{/if}}
                          <span class='st strong' data-tone={{r.tone}}><span
                              class='dot'
                            ></span>{{r.label}}</span>
                        </li>
                      {{/each}}
                    </ul>
                  </section>
                {{else}}
                  <EmptyState @size='s' @title='No values match' />
                {{/each}}
              </div>
            {{/if}}
          </main>

          <aside class='aside' aria-label='Programme'>
            {{#if @model.authority}}
              <section class='aside-block'>
                <h2>Certification authority</h2>
                <@fields.authority
                  @format='atom'
                  @displayContainer={{false}}
                />
                <dl class='authority-kv'>
                  <dt>Signatory</dt>
                  <dd>{{if
                      @model.authority.signatoryName
                      @model.authority.signatoryName
                      '—'
                    }}{{#if @model.authority.signatoryTitle}},
                      {{@model.authority.signatoryTitle}}{{/if}}</dd>
                  <dt>Certificate prefix</dt>
                  <dd class='mono'>{{if
                      @model.authority.numberPrefix
                      @model.authority.numberPrefix
                      '—'
                    }}</dd>
                </dl>
              </section>
            {{/if}}
            {{#each ROADMAP as |r|}}
              <section class='aside-block'>
                <h2>{{r.title}}</h2>
                <p class='muted'>{{r.text}}</p>
              </section>
            {{/each}}
          </aside>
        </div>
      </:default>
    </Sidebar>

    <style scoped>
      .acd-shell {
        container-type: inline-size;
        block-size: 100%;
        min-block-size: 0;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: 0.75rem;
      }
      p {
        margin: 0;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .mark,
      .doc-mark {
        display: grid;
        place-items: center;
        flex: none;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border-radius: var(--radius);
        background: var(--muted);
        font: 600 0.5625rem/1 var(--font-mono);
      }
      .doc-mark {
        inline-size: 1.25rem;
        block-size: 1.25rem;
      }
      .brand-text {
        display: grid;
        min-inline-size: 0;
        font-weight: 700;
        line-height: 1.2;
      }
      .foot {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .eyebrow {
        font: 600 0.5625rem/1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }

      /* main column + the programme panel docked flush right */
      .layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 18.75rem;
        min-block-size: 100%;
      }
      .main {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
      }
      .aside {
        min-inline-size: 0;
        border-inline-start: 1px solid var(--border);
        background: var(--card);
        color: var(--card-foreground);
      }
      @container (width < 60rem) {
        .layout {
          grid-template-columns: minmax(0, 1fr);
        }
        .aside {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
      }
      .aside-block {
        display: grid;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .authority-kv {
        display: grid;
        grid-template-columns: auto 1fr;
        margin: 0;
        font-size: 0.75rem;
      }
      .authority-kv dt,
      .authority-kv dd {
        margin: 0;
        padding: var(--boxel-sp-4xs) 0;
        border-block-end: 1px solid var(--border);
      }
      .authority-kv dt {
        padding-inline-end: var(--boxel-sp-sm);
        font: 600 0.5625rem/1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        align-self: center;
      }
      .aside-block + .aside-block {
        border-block-start: 1px solid var(--border);
      }
      .aside-block h2,
      .block-head h2 {
        margin: 0;
        font-size: 0.75rem;
        font-weight: 700;
      }

      .head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .h1 {
        margin: 0;
        font-family: var(--boxel-heading-font-family, var(--font-sans));
        font-weight: 400;
        font-size: 2.5rem;
        line-height: 1;
        text-transform: uppercase;
      }
      .sub {
        max-inline-size: 34rem;
        color: var(--muted-foreground);
      }
      .search {
        inline-size: 13.75rem;
      }
      .push {
        margin-inline-start: auto;
      }

      /* stat strip: each cell draws its right and bottom line and the frame
         clips the overhang, so a wrapped row keeps every divider */
      .stats {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .stat-cells {
        --text-stat: 1.375rem;
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        margin: 0 -1px -1px 0;
      }
      .stat {
        min-inline-size: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      @container (width <= 30rem) {
        .stat-cells {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }

      /* one flat block: radius outside only, hairline sections inside */
      .block {
        min-inline-size: 0;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .block-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .block-meta {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .block-body {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .muted {
        color: var(--muted-foreground);
      }
      .mono {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        font-size: 0.6875rem;
      }

      .table-scroll {
        overflow-x: auto;
      }
      .register {
        inline-size: 100%;
        min-inline-size: 40rem;
        border-collapse: collapse;
      }
      .register th {
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
        text-align: start;
        font: 600 0.5625rem/1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .register td {
        block-size: 1.75rem;
        padding: 0 var(--boxel-sp-sm);
        white-space: nowrap;
      }
      .register tbody tr + tr td {
        border-block-start: 1px solid var(--border);
      }
      .name-cell {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .name {
        --pretui-button-fg: var(--card-foreground);
        font-weight: 600;
      }

      /* status: dot + text, never a pill */
      .st {
        --tone: var(--muted-foreground);
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
      }
      .st[data-tone='ok'] {
        --tone: var(--success);
      }
      .st[data-tone='warn'] {
        --tone: var(--warning);
      }
      .st[data-tone='bad'] {
        --tone: var(--destructive);
      }
      .st[data-tone='info'] {
        --tone: var(--info);
      }
      .strong {
        font-weight: 600;
      }
      .dot {
        flex: none;
        inline-size: 0.4375rem;
        block-size: 0.4375rem;
        border-radius: 50%;
        background: var(--tone);
      }

      .vocab-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        align-items: start;
        gap: var(--boxel-sp-xs);
      }
      @container (width < 40rem) {
        .vocab-grid {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      .note {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .rows {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        block-size: 1.75rem;
        padding: 0 var(--boxel-sp-sm);
      }
      .row + .row {
        border-block-start: 1px solid var(--border);
      }
      .rank {
        inline-size: 1.5rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
