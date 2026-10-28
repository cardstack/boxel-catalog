import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { realmURL } from '@cardstack/base/card-api';
import {
  identifyCard,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { CsvFileDef } from '@cardstack/base/csv-file-def';
import WriteTextFileCommand from '@cardstack/boxel-host/commands/write-text-file';
import { Button } from '../../../ui-component/components/button';
import { Field } from '../../../ui-component/components/field';
import { FileTrigger } from '../../../ui-component/components/file-trigger';
import { Input } from '../../../ui-component/components/input';
import { Textarea } from '../../../ui-component/components/textarea';
import {
  isValidIdentifierPattern,
  mintIdentifier,
} from '../../../fields/record-identifier/record-identifier-field';
import ImportLegacyDataCommand from '../../service-desk/commands/import-legacy-data-command';
import type { SupportCaseApp } from '../support-case-app';

interface Signature {
  Args: {
    model: SupportCaseApp;
    context: any;
    onNote: (message: string) => void;
    /** live Role count and agent-pool size from the desk's queries ('—' while loading) */
    roleCount: number | string;
    agentCount: number | string;
  };
}

/** The desk's Setup tab: a guided wizard over the desk's configuration, ending
    in a legacy-case import. */
export class DeskSetup extends GlimmerComponent<Signature> {
  @tracked importCsv = '';
  @tracked importReport: string[] = [];
  /** The chosen CSV file card (preferred); paste is the fallback. */
  @tracked importFileId: string | null = null;
  @tracked importBusy = false;
  @tracked uploadBusy = false;
  @tracked uploadNote: string | null = null;

  get commandContext() {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      throw new Error('No command context available in this render mode');
    }
    return ctx;
  }
  get realm(): string | undefined {
    return (this.args.model as any)?.[realmURL]?.href;
  }
  get realms(): string[] {
    return this.realm ? [this.realm] : [];
  }
  note = (message: string) => this.args.onNote(message);

  // ── import ─────────────────────────────────────────────────────────
  setImportCsv = (v: string) => (this.importCsv = v);
  /** The import function proper: a CSV from the user's machine becomes a
      CSV file card in the desk's realm (provenance), then is pre-selected. */
  uploadCsv = async (files: File[]) => {
    let file = files[0];
    if (!file || !this.realm) return;
    this.uploadBusy = true;
    this.uploadNote = null;
    try {
      let content = await file.text();
      let header = (content.split(/\r?\n/)[0] ?? '').toLowerCase();
      if (!header.includes('subject') || !header.includes('legacy_id')) {
        throw new Error(
          `${file.name}: header must include subject, status, opened and legacy_id (got "${header.slice(0, 80)}")`,
        );
      }
      let safeName =
        file.name.replace(/[^A-Za-z0-9._-]+/g, '-').replace(/\.csv$/i, '') +
        '.csv';
      let result = await new WriteTextFileCommand(this.commandContext).execute({
        realm: this.realm,
        path: `imports/${safeName}`,
        content,
        useNonConflictingFilename: true,
      } as any);
      let url = (result as any).fileIdentifier as string;
      this.importFileId = url;
      this.importReport = [];
      this.uploadNote = `Uploaded ${file.name} — pick it below if it is not highlighted yet, then Import rows.`;
    } catch (e: any) {
      this.uploadNote = e?.message ?? String(e);
    } finally {
      this.uploadBusy = false;
    }
  };
  pickImportFile = (id: string) => {
    this.importFileId = this.importFileId === id ? null : id;
    this.importReport = [];
  };
  private fileKey = (id?: string | null) => (id ?? '').replace(/\.csv$/i, '');
  isPickedFile = (id: string) =>
    Boolean(this.importFileId) &&
    this.fileKey(this.importFileId) === this.fileKey(id);
  get importFileName() {
    return this.importFileId?.split('/').pop() ?? null;
  }
  get canImport() {
    return (
      !this.importBusy && Boolean(this.importFileId || this.importCsv.trim())
    );
  }
  /** Every CSV file card in the desk's realms — the import picks from these. */
  get csvWireQuery(): SearchEntryWireQuery | undefined {
    let ref = identifyCard(CsvFileDef);
    if (!ref || !this.realms.length) return undefined;
    // Only files that can be imported are offered: the index knows each
    // CSV's header (CsvFileDef.columns), so files with other columns never
    // reach the picker. One distinctive header name tells an export apart
    // (`status` is a reserved search_doc member on file rows, so eq on it
    // never matches). The filter stays flat: the host binds its htmlQuery
    // into the filter's top-level `eq`, so a top-level `every` wrapper
    // returns no rows.
    return {
      ...searchEntryWireQueryFromQuery(
        {
          filter: { type: ref, eq: { columns: 'legacy_id' } } as any,
          // file rows carry `name`, not cardTitle — sorting on cardTitle drops them all
          sort: [{ by: 'name', on: ref, direction: 'asc' }],
        } as any,
        { scope: 'files' },
      ),
      realms: this.realms,
    };
  }
  runImport = async () => {
    if (!this.canImport) return;
    this.importBusy = true;
    try {
      let cfg = this.args.model.config;
      let result = await new ImportLegacyDataCommand(
        this.commandContext,
      ).execute({
        sourceUrl: this.importFileId ?? undefined,
        csvText: this.importFileId ? undefined : this.importCsv,
        idPattern: cfg?.idPattern ?? 'CASE-{yyyy}-{seq4}',
        startSeq: (cfg?.identifierSeq ?? 0) + 1,
        systemName: 'legacy helpdesk',
        realm: this.realm,
      } as any);
      let r = result as any;
      this.importReport = [...(r.results ?? [])];
      if (cfg && typeof r.nextSeq === 'number') {
        cfg.identifierSeq = r.nextSeq - 1;
      }
    } catch (e: any) {
      this.importReport = [e?.message ?? String(e)];
    } finally {
      this.importBusy = false;
    }
  };

  // ── setup wizard ───────────────────────────────────────────────────
  get wizardSteps(): {
    label: string;
    valid?: boolean;
    blockedReason?: string;
  }[] {
    return [
      { label: 'Business hours' },
      {
        label: 'Case ID pattern',
        valid: isValidIdentifierPattern(this.args.model.config?.idPattern),
        blockedReason:
          'The pattern needs {yyyy} and {seqN}, for example CASE-{yyyy}-{seq4}.',
      },
      { label: 'Roles & pool' },
      { label: 'Workflow' },
      { label: 'Sample import' },
    ];
  }
  // The step on screen; the stored setupStep only records progress.
  @tracked wizardView: number | null = null;
  get wizardIndex() {
    return (
      this.wizardView ?? Math.min(this.wizardStep, this.wizardSteps.length - 1)
    );
  }
  showWizardStep = (index: number) => {
    this.wizardView = index;
    this.advanceWizard(index);
  };
  completeWizard = () => this.advanceWizard(-1);
  // The stored setupStep records progress; the step on screen is wizardView.
  get wizardStep() {
    return Number(this.args.model.config?.setupStep) || 0;
  }
  advanceWizard = (next: number) => {
    let cfg = this.args.model.config;
    if (!cfg) return;
    if (next === -1) {
      cfg.setupCompletedAt = new Date();
      cfg.setupStep = this.wizardSteps.length;
      this.note('Setup complete — the desk is live.');
    } else if (next > (cfg.setupStep ?? 0)) {
      cfg.setupStep = next;
    }
  };
  get stepNumber() {
    return this.wizardIndex + 1;
  }
  get isFirst() {
    return this.wizardIndex === 0;
  }
  get isLast() {
    return this.wizardIndex === this.wizardSteps.length - 1;
  }
  @tracked refusal = '';
  get railSteps() {
    return this.wizardSteps.map((st, index) => {
      let current = index === this.wizardIndex;
      let done = !current && index < this.wizardStep;
      return {
        index,
        number: index + 1,
        label: st.label,
        current,
        done,
        state: current ? 'current' : done ? 'done' : 'todo',
      };
    });
  }
  /** Moving forward passes every step in between, so each must be valid. */
  goTo = (target: number) => {
    let steps = this.wizardSteps;
    if (target < 0 || target >= steps.length) return;
    for (let k = this.wizardIndex; k < target; k++) {
      if (steps[k]?.valid === false) {
        this.refusal = steps[k]?.blockedReason ?? 'Finish this step first.';
        return;
      }
    }
    this.refusal = '';
    this.showWizardStep(target);
  };
  back = () => this.goTo(this.wizardIndex - 1);
  next = () => {
    if (!this.isLast) return this.goTo(this.wizardIndex + 1);
    let blocked = this.wizardSteps.find((st) => st.valid === false);
    if (blocked) {
      this.refusal = blocked.blockedReason ?? 'Finish every step first.';
      return;
    }
    this.refusal = '';
    this.completeWizard();
  };
  setIdPattern = (v: string) => {
    let cfg = this.args.model.config;
    if (cfg) cfg.idPattern = v;
  };
  setTimeZone = (v: string) => {
    let cfg = this.args.model.config;
    if (cfg) cfg.timeZone = v;
  };
  get patternPreview() {
    return mintIdentifier(this.args.model.config?.idPattern, 1);
  }
  get patternValid() {
    return isValidIdentifierPattern(this.args.model.config?.idPattern);
  }

  <template>
    <section class='setup-card' aria-labelledby='setup-card-title'>
      <header class='setup-head'>
        <h2 class='setup-title' id='setup-card-title'>Setup steps</h2>
        <span class='setup-count'>step
          {{this.stepNumber}}
          of
          {{this.wizardSteps.length}}</span>
      </header>
      <div class='setup-grid'>
        <div class='setup-rail'>
          <ol class='rail-list' aria-label='Setup steps'>
            {{#each this.railSteps as |step|}}
              <li class='rail-item'>
                <button
                  type='button'
                  class='rail-btn'
                  data-state={{step.state}}
                  aria-current={{if step.current 'step'}}
                  {{on 'click' (fn this.goTo step.index)}}
                >
                  <span class='rail-mark' aria-hidden='true'>{{if
                      step.done
                      '✓'
                      step.number
                    }}</span>
                  <span class='rail-label'>{{step.label}}</span>
                </button>
              </li>
            {{/each}}
          </ol>
        </div>
        <div class='setup-panel'>
          {{#let this.wizardIndex as |i|}}
            {{#if (eq i 0)}}
              <h3 class='wiz-h'>Business hours</h3>
              <Field @label='Timezone (IANA)' as |controlId|>
                <Input
                  @controlId={{controlId}}
                  @value={{@model.config.timeZone}}
                  @onInput={{this.setTimeZone}}
                  @placeholder='Asia/Kuala_Lumpur'
                />
              </Field>
              <p class='wiz-hint'>Working windows and holidays are edited on the
                desk's edit view — this step sets the zone every clock runs in.
                Empty windows mean always-on (24/7).</p>
            {{/if}}
            {{#if (eq i 1)}}
              <h3 class='wiz-h'>Case ID pattern</h3>
              <Field @label='Pattern' as |controlId|>
                <Input
                  @controlId={{controlId}}
                  @value={{@model.config.idPattern}}
                  @onInput={{this.setIdPattern}}
                  @placeholder='CASE-{yyyy}-{seq4}'
                />
              </Field>
              <p class='wiz-preview'>Preview:
                <code>{{this.patternPreview}}</code>
                {{#if this.patternValid}}<span class='wiz-ok'>✓ valid</span>{{else}}<span
                    class='wiz-bad'
                  >needs {yyyy} and {seqN}</span>{{/if}}
              </p>
              <p class='wiz-hint'>Ids are minted at create time and never edited
                or recycled.</p>
            {{/if}}
            {{#if (eq i 2)}}
              <h3 class='wiz-h'>Roles & round-robin pool</h3>
              <p class='wiz-hint'>Roles and the agent pool come from the Role
                cards: the agents are the members of each role. There is nothing
                to link here. Right now there are
                {{@roleCount}}
                role(s) and
                {{@agentCount}}
                agent(s) in the pool. The escalation ladder assigns toward a
                role's on-duty member.</p>
            {{/if}}
            {{#if (eq i 3)}}
              <h3 class='wiz-h'>Workflow</h3>
              {{#if @model.defaultWorkflow}}
                <p class='wiz-hint'>Linked:
                  {{@model.defaultWorkflow.title}}
                  —
                  {{@model.defaultWorkflow.states.length}}
                  states. Waiting-kind states pause SLA clocks.</p>
              {{else}}
                <p class='wiz-hint'>No workflow linked yet — create a Workflow
                  card and link it on the desk's edit view, then return here.</p>
              {{/if}}
            {{/if}}
            {{#if (eq i 4)}}
              <div class='wiz-import'>
                <h3 class='wiz-h'>Import legacy cases</h3>
                <p class='wiz-hint'>Upload the old helpdesk's CSV export
                  (columns: subject, status, opened, legacy_id). It is kept in
                  this workspace as the import's provenance, so it can be
                  re-run; earlier uploads are listed below. Per-row results —
                  failures are reported, never skipped.</p>
                <div class='wiz-row wiz-upload'>
                  <FileTrigger
                    @accept='.csv,text/csv'
                    @label={{if this.uploadBusy 'Uploading…' 'Upload CSV'}}
                    @disabled={{this.uploadBusy}}
                    @tone='primary'
                    @appearance='accent'
                    @size='s'
                    @onSelect={{this.uploadCsv}}
                  />
                  {{#if this.uploadNote}}<span
                      class='wiz-picked'
                    >{{this.uploadNote}}</span>{{/if}}
                </div>
                {{#if @context.searchResultsComponent}}
                  {{#let
                    (component @context.searchResultsComponent)
                    as |SearchResults|
                  }}
                    <SearchResults
                      @query={{this.csvWireQuery}}
                      @mode='none'
                      as |results|
                    >
                      <ul
                        class='csv-picker'
                        aria-label='CSV files in this workspace'
                      >
                        {{#each results.entries key='id' as |entry|}}
                          <li class='csv-cell'>
                            <button
                              type='button'
                              class='csv-pick'
                              aria-label='Use this CSV file'
                              aria-pressed='{{this.isPickedFile entry.id}}'
                              {{on 'click' (fn this.pickImportFile entry.id)}}
                            >
                              <entry.component class='csv-face' />
                            </button>
                          </li>
                        {{else}}
                          {{#if results.isLoading}}
                            <li class='desk-loading' role='status'>Looking for
                              CSV files…</li>
                          {{else}}
                            <li class='desk-empty'>No importable CSV in this
                              workspace yet — upload the export with columns
                              subject, status, opened, legacy_id and it appears
                              here.</li>
                          {{/if}}
                        {{/each}}
                      </ul>
                    </SearchResults>
                  {{/let}}
                {{/if}}
                <details class='wiz-alt'>
                  <summary>No file at hand? Paste CSV rows instead</summary>
                  <Textarea
                    aria-label='CSV rows'
                    @value={{this.importCsv}}
                    @onInput={{this.setImportCsv}}
                    @placeholder='subject,status,opened,legacy_id'
                  />
                </details>
                <div class='wiz-row'>
                  <span class='wiz-picked'>{{#if this.importFileName}}Source:
                      <code>{{this.importFileName}}</code>{{else if
                      this.importCsv
                    }}Source: pasted rows{{else}}Pick a file or paste rows to
                      enable import{{/if}}</span>
                  <Button
                    @tone='primary'
                    @appearance='accent'
                    @size='s'
                    @disabled={{unless this.canImport true}}
                    @busy={{this.importBusy}}
                    {{on 'click' this.runImport}}
                  >Import rows</Button>
                </div>
                {{#if this.importReport.length}}
                  <ul class='import-report'>
                    {{#each this.importReport as |line|}}<li><code
                        >{{line}}</code></li>{{/each}}
                  </ul>
                {{/if}}
              </div>
            {{/if}}
          {{/let}}
          <p class='setup-refusal' role='alert'>{{this.refusal}}</p>
          <footer class='setup-foot'>
            <Button
              @tone='neutral'
              @appearance='outlined'
              @disabled={{this.isFirst}}
              {{on 'click' this.back}}
            >Back</Button>
            <Button
              @tone='primary'
              @appearance='accent'
              {{on 'click' this.next}}
            >{{if this.isLast 'Finish setup' 'Next'}}</Button>
          </footer>
        </div>
      </div>
    </section>
    <style scoped>
      .setup-card {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-lg);
        border-radius: var(--boxel-border-radius-lg, var(--radius));
        background: var(--card);
        color: var(--card-foreground);
      }
      .setup-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      .setup-title {
        margin: 0;
        font-size: var(--boxel-font-size-lg);
        font-weight: 600;
      }
      .setup-count {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .setup-grid {
        display: grid;
        grid-template-columns: minmax(12rem, 16rem) 1fr;
        gap: var(--boxel-sp-xl);
        align-items: start;
      }
      .setup-rail {
        padding: var(--boxel-sp-xs);
        border-radius: var(--boxel-border-radius-lg, var(--radius));
        background: var(--muted);
      }
      .rail-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
      }
      .rail-btn {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        width: 100%;
        padding: var(--boxel-sp-xs);
        border: 0;
        border-radius: var(--radius);
        background: transparent;
        color: var(--muted-foreground);
        font: inherit;
        font-size: var(--boxel-font-size);
        text-align: start;
        cursor: pointer;
      }
      .rail-btn:hover {
        background: color-mix(in oklab, var(--card) 60%, transparent);
      }
      .rail-btn:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: 0.125rem;
      }
      .rail-btn[data-state='current'] {
        background: var(--card);
        color: var(--primary);
        font-weight: 600;
      }
      .rail-btn[data-state='done'] {
        color: var(--foreground);
      }
      .rail-mark {
        display: inline-grid;
        place-items: center;
        flex: none;
        width: 1.5rem;
        height: 1.5rem;
        border: 1px solid var(--border);
        border-radius: 50%;
        background: var(--card);
        font-size: var(--boxel-font-size-xs);
      }
      .rail-btn[data-state='current'] .rail-mark {
        background: var(--primary);
        border-color: var(--primary);
        color: var(--primary-foreground);
      }
      .rail-btn[data-state='done'] .rail-mark {
        border-color: var(--success);
        color: var(--success-ink);
      }
      .setup-refusal {
        margin: 0;
        min-height: 1.25rem;
        font-size: var(--boxel-font-size-sm);
        color: var(--destructive-ink);
      }
      .setup-panel {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .setup-foot {
        display: flex;
        justify-content: space-between;
        padding-top: var(--boxel-sp-sm);
        border-top: 1px solid var(--border);
      }
      .wiz-h {
        margin: 0;
        font-size: var(--boxel-font-size);
        font-weight: 600;
      }
      .wiz-hint {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        max-width: 60ch;
      }
      .wiz-preview {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
      }
      .wiz-row {
        display: flex;
        justify-content: flex-end;
      }
      .wiz-preview code {
        font-family: var(--font-mono);
        background: var(--muted);
        border-radius: var(--radius);
        padding: 0.125rem 0.5rem;
      }
      .wiz-ok {
        color: var(--success-ink);
        margin-left: var(--boxel-sp-4xs);
      }
      .wiz-bad {
        color: var(--destructive-ink);
        margin-left: var(--boxel-sp-4xs);
      }
      .wiz-import {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .wiz-upload {
        justify-content: flex-start;
      }
      .csv-picker {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(15.625rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .csv-cell {
        container-name: fitted-card;
        container-type: size;
        height: 4.0625rem;
      }
      .csv-pick {
        display: block;
        width: 100%;
        height: 100%;
        padding: 0;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: inherit;
        text-align: start;
        cursor: pointer;
        overflow: hidden;
      }
      .csv-pick[aria-pressed='true'] {
        border-color: var(--primary);
        box-shadow: inset 0.1875rem 0 0 var(--primary);
      }
      .csv-pick:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .csv-face {
        width: 100%;
        height: 100%;
        pointer-events: none;
      }
      .wiz-alt {
        font-size: var(--boxel-font-size-sm);
      }
      .wiz-alt summary {
        cursor: pointer;
        color: var(--muted-foreground);
        margin-bottom: var(--boxel-sp-4xs);
      }
      .wiz-picked {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        margin-right: auto;
      }
      .import-report {
        margin: 0;
        padding-left: 1.2em;
        font-size: var(--boxel-font-size-xs);
        max-height: 12rem;
        overflow: auto;
      }

      .desk-loading,
      .desk-empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
