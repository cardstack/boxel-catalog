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
import { Button } from '@cardstack/pretui/components/button';
import { Card } from '@cardstack/pretui/components/card';
import { Field } from '@cardstack/pretui/components/field';
import { FileTrigger } from '@cardstack/pretui/components/file-trigger';
import { Input } from '@cardstack/pretui/components/input';
import { Textarea } from '@cardstack/pretui/components/textarea';
import { Wizard, type WizardStep } from '@cardstack/pretui/components/wizard';
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
  get wizardSteps(): WizardStep[] {
    return [
      { id: 'hours', label: 'Business hours' },
      {
        id: 'id-pattern',
        label: 'Case ID pattern',
        valid: isValidIdentifierPattern(this.args.model.config?.idPattern),
        blockedReason:
          'The pattern needs {yyyy} and {seqN}, for example CASE-{yyyy}-{seq4}.',
      },
      { id: 'roles', label: 'Roles & pool' },
      { id: 'workflow', label: 'Workflow' },
      { id: 'import', label: 'Sample import' },
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
  get wizardStep() {
    return this.args.model.config?.setupStep ?? 0;
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
  setIdPattern = (v: string) => {
    let cfg = this.args.model.config;
    if (cfg) cfg.idPattern = v;
  };
  setTimeZone = (v: string) => {
    let w = this.args.model.config?.defaultSlaWindow;
    if (w) (w as any).timeZone = v;
  };
  get patternPreview() {
    return mintIdentifier(this.args.model.config?.idPattern, 1);
  }
  get patternValid() {
    return isValidIdentifierPattern(this.args.model.config?.idPattern);
  }

  <template>
    <Wizard
      @label='Setup steps'
      @steps={{this.wizardSteps}}
      @activeIndex={{this.wizardIndex}}
      @onStepChange={{this.showWizardStep}}
      @onComplete={{this.completeWizard}}
      @hideTitle={{true}}
      @completeLabel='Finish setup'
    >
      <:step as |_step i|>
        {{#if (eq i 0)}}
          <h3 class='wiz-h'>Business hours</h3>
          <Field @label='Timezone (IANA)' as |controlId|>
            <Input
              @controlId={{controlId}}
              @value={{@model.config.defaultSlaWindow.timeZone}}
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
          <p class='wiz-hint'>Ids are minted at create time and never edited or
            recycled.</p>
        {{/if}}
        {{#if (eq i 2)}}
          <h3 class='wiz-h'>Roles & round-robin pool</h3>
          <p class='wiz-hint'>Link Roles and the candidate pool on the desk's
            edit view. Currently linked:
            {{@model.roles.length}}
            role(s),
            {{@model.candidatePool.length}}
            in the pool. The escalation ladder assigns toward a role's on-duty
            member.</p>
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
            <p class='wiz-hint'>No workflow linked yet — create a Workflow card
              and link it on the desk's edit view, then return here.</p>
          {{/if}}
        {{/if}}
        {{#if (eq i 4)}}
          <div class='wiz-import'>
            <h3 class='wiz-h'>Import legacy cases</h3>
            <p class='wiz-hint'>Upload the old helpdesk's CSV export (columns:
              subject, status, opened, legacy_id). It is kept in this workspace
              as the import's provenance, so it can be re-run; earlier uploads
              are listed below. Per-row results — failures are reported, never
              skipped.</p>
            <div class='wiz-row wiz-upload'>
              <FileTrigger
                @accept='.csv,text/csv'
                @label={{if this.uploadBusy 'Uploading…' 'Upload CSV'}}
                @disabled={{this.uploadBusy}}
                @tone='primary'
                @appearance='filled'
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
                        <Card
                          class='csv-pick'
                          @onSelect={{fn this.pickImportFile entry.id}}
                          @selected={{this.isPickedFile entry.id}}
                          @selectLabel='Use this CSV file'
                        >
                          <entry.component class='csv-face' />
                        </Card>
                      </li>
                    {{else}}
                      {{#if results.isLoading}}
                        <li class='desk-loading' role='status'>Looking for CSV
                          files…</li>
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
                }}Source: pasted rows{{else}}Pick a file or paste rows to enable
                  import{{/if}}</span>
              <Button
                @tone='primary'
                @appearance='filled'
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
      </:step>
    </Wizard>
    <style scoped>
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
        height: 100%;
        overflow: hidden;
      }
      .csv-face {
        width: 100%;
        height: 100%;
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
