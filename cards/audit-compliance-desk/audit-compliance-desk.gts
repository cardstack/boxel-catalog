import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import { FittedCard } from '@cardstack/boxel-ui/components';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';

import { AppShell } from '@cardstack/pretui/components/app-shell';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Tabs } from '@cardstack/pretui/components/tabs';
import { SeverityBadge } from '../audit/components/severity-badge';
import { StatePill } from '../../components/state-pill';
import { Document } from '../audit/document';
import { CertificationAuthority } from '../audit/certification-authority';
import { SEVERITY_LEVELS, SEVERITY_LABELS } from '../audit/severity-vocabulary';
import {
  EVALUATION_STATUSES,
  EVALUATION_LABELS,
  EVALUATION_HUE,
} from '../../fields/evaluation-status/evaluation-status-field';
import {
  RESOLUTION_CODES,
  RESOLUTION_LABELS,
  RESOLUTION_HUE,
} from '../../fields/resolution-code/resolution-code-field';
import {
  TRUST_LEVELS,
  TRUST_LABELS,
  TRUST_HUE,
} from '../../fields/trust-metadata/trust-metadata-field';
import { shortHash } from '../audit/utils/evidence-hash';
import type { Hue } from '../../components/state-pill';

const TABS = [
  { value: 'evidence', label: 'Evidence' },
  { value: 'vocabulary', label: 'Vocabulary' },
];

interface LegendRow {
  value: string;
  label: string;
  hue: Hue;
}

function legend(
  values: readonly string[],
  labels: Record<string, string>,
  hues: Record<string, Hue>,
): LegendRow[] {
  return values.map((value) => ({
    value,
    label: labels[value] ?? value,
    hue: hues[value] ?? 'slate',
  }));
}

// The isolated desk, hoisted out of the card class so its fields can be
// @tracked.
class AuditComplianceDeskIsolated extends Component<
  typeof AuditComplianceDesk
> {
  @tracked activeTab = 'evidence';

  private documentList: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let ctx = this.args.context;
    this.documentList = ctx?.getCards(
      this,
      () => {
        let ref = identifyCard(Document);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  private get realms(): string[] | undefined {
    let url = this.args.model?.[realmURL];
    return url ? [url.href] : undefined;
  }

  // The interactive surfaces need the host's CRUD functions; prerender has
  // none, so it gets the masthead and the counts and stops there.
  private get isInteractive() {
    return Boolean(this.args.viewCard);
  }

  private get canCreate() {
    return this.showEvidence && Boolean(this.args.createCard);
  }

  get isLoading() {
    return Boolean(this.documentList?.isLoading);
  }

  get documents(): Document[] {
    return ((this.documentList?.instances ?? []) as Document[]).filter(Boolean);
  }

  get hashedCount() {
    return this.documents.filter((d) => (d.contentHash ?? '').trim()).length;
  }

  get unhashedCount() {
    return this.documents.length - this.hashedCount;
  }

  get supersededCount() {
    return this.documents.filter((d) => d.supersedes).length;
  }

  get rows() {
    return this.documents.map((d) => ({
      card: d,
      title: d.cardTitle,
      kind: d.kind ?? '',
      hash: shortHash(d.contentHash),
      hashed: Boolean((d.contentHash ?? '').trim()),
      hasFile: Boolean(d.file),
      supersedes: d.supersedes?.cardTitle ?? null,
    }));
  }

  get severityLegend() {
    return SEVERITY_LEVELS.map((value) => ({
      value,
      label: SEVERITY_LABELS[value] ?? value,
    }));
  }
  get evaluationLegend() {
    return legend(EVALUATION_STATUSES, EVALUATION_LABELS, EVALUATION_HUE);
  }
  get resolutionLegend() {
    return legend(RESOLUTION_CODES, RESOLUTION_LABELS, RESOLUTION_HUE);
  }
  get trustLegend() {
    return legend(TRUST_LEVELS, TRUST_LABELS, TRUST_HUE);
  }

  get showEvidence() {
    return this.activeTab === 'evidence';
  }
  get showVocabulary() {
    return this.activeTab === 'vocabulary';
  }

  get subtitle() {
    return this.showEvidence
      ? 'Every artefact the desk can produce on request, with the hash recorded when it was taken. An unhashed document is a record, not yet evidence.'
      : 'The closed vocabularies every audit surface reads. One definition each, so a verdict cannot mean two things.';
  }

  @action setTab(tabId: string) {
    this.activeTab = tabId;
  }

  @action openCard(card: CardDef) {
    this.args.viewCard?.(card, 'isolated');
  }

  // A register a manager cannot add to is a report, not a desk. Quick-add
  // pre-sets `kind: evidence` because that is what arrives here — a policy
  // or a report is filed deliberately, and the field is editable anyway.
  @action newDocument() {
    let ref = identifyCard(Document);
    let realm = this.realms?.[0];
    if (!ref || !realm) {
      return;
    }
    this.args.createCard?.(ref, undefined, {
      realmURL: new URL(realm),
      doc: {
        data: {
          attributes: { kind: 'evidence' },
          meta: { adoptsFrom: ref },
        },
      },
    });
  }

  <template>
    <AppShell
      class='desk {{if this.showEvidence "dense" "roomy"}}'
      @asideLabel='Programme'
      @asideWidth='18rem'
      @maxWidth='none'
    >
      <:masthead>
        <div class='mast'>
          <ClipboardCheckIcon class='mast-icon' role='presentation' />
          <h1 class='mast-title'>Audit &amp; Compliance</h1>
          <Tabs
            class='mast-tabs'
            @options={{TABS}}
            @value={{this.activeTab}}
            @onValueChange={{this.setTab}}
          />
          {{#if this.canCreate}}
            <Button
              class='new-doc'
              @tone='neutral'
              @appearance='outlined'
              @size='s'
              {{on 'click' this.newDocument}}
            >New document</Button>
          {{/if}}
        </div>
      </:masthead>

      <:subhead>
        <div class='brief'>
          <p class='eyebrow'>{{if
              this.showEvidence
              'Evidence register'
              'Reference'
            }}</p>
          {{#if this.subtitle}}
            <p class='subtitle'>{{this.subtitle}}</p>
          {{/if}}
          <div class='meta'>
            {{#if this.showEvidence}}
              <span class='stat'>
                <span class='sv'>{{if
                    this.isLoading
                    '—'
                    this.documents.length
                  }}</span>
                <span class='sl'>documents</span>
              </span>
              <span class='stat'>
                <span class='sv'>{{if
                    this.isLoading
                    '—'
                    this.hashedCount
                  }}</span>
                <span class='sl'>hashed</span>
              </span>
              <span class='stat'>
                <span class='sv'>{{if
                    this.isLoading
                    '—'
                    this.unhashedCount
                  }}</span>
                <span class='sl'>not yet hashed</span>
              </span>
              <span class='stat'>
                <span class='sv'>{{if
                    this.isLoading
                    '—'
                    this.supersededCount
                  }}</span>
                <span class='sl'>supersede an earlier version</span>
              </span>
            {{else}}
              <span class='stat'>
                <span class='sv'>{{this.severityLegend.length}}</span>
                <span class='sl'>severity levels</span>
              </span>
              <span class='stat'>
                <span class='sv'>{{this.evaluationLegend.length}}</span>
                <span class='sl'>evaluation statuses</span>
              </span>
              <span class='stat'>
                <span class='sv'>{{this.trustLegend.length}}</span>
                <span class='sl'>trust levels</span>
              </span>
              <span class='stat'>
                <span class='sv'>{{this.resolutionLegend.length}}</span>
                <span class='sl'>resolution codes</span>
              </span>
            {{/if}}
          </div>
        </div>
      </:subhead>

      <:default>
        {{#if this.showEvidence}}
          {{#if this.isLoading}}
            <p class='loading' role='status'>Loading the register…</p>
          {{else if this.rows.length}}
            <div class='register-scroll'>
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
                      <td>
                        {{#if this.isInteractive}}
                          <Button
                            class='link'
                            @tone='neutral'
                            @appearance='link'
                            @size='s'
                            {{on 'click' (fn this.openCard row.card)}}
                          >{{row.title}}</Button>
                        {{else}}
                          <span class='link-static'>{{row.title}}</span>
                        {{/if}}
                      </td>
                      <td class='muted'>{{row.kind}}</td>
                      <td>
                        {{#if row.hashed}}
                          <span class='mono'>{{row.hash}}</span>
                        {{else}}
                          <StatePill @label='not hashed' @hue='slate' />
                        {{/if}}
                      </td>
                      <td>
                        {{#if row.hasFile}}
                          <StatePill
                            @label='attached'
                            @hue='green'
                            @dot={{true}}
                          />
                        {{else}}
                          <StatePill
                            @label='no file'
                            @hue='slate'
                            @dot={{true}}
                          />
                        {{/if}}
                      </td>
                      <td class='muted'>{{if
                          row.supersedes
                          row.supersedes
                          '—'
                        }}</td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{else}}
            <EmptyState
              @size='s'
              @title='No documents in the register yet'
              @message='A document is the artefact plus who owns it and what it replaced. Evidence arrives here before it is ever cited.'
            />
          {{/if}}
        {{/if}}

        {{#if this.showVocabulary}}
          <div class='vocab'>
            <section>
              <h2>Severity</h2>
              <p class='note'>How bad a finding is. Major and above put the
                certificate at risk. The rank meter carries the level without
                colour.</p>
              <div class='chips'>
                {{#each this.severityLegend as |row|}}
                  <SeverityBadge @level={{row.value}} />
                {{/each}}
              </div>
            </section>

            <section>
              <h2>Evaluation status</h2>
              <p class='note'>The outcome of one rule against one subject. Only
                verdicts are coloured —
                <strong>unproven</strong>
                is a control that satisfied the rule with no evidence attached,
                and it counts against coverage, never as a pass.</p>
              <div class='chips'>
                {{#each this.evaluationLegend as |row|}}
                  <StatePill
                    @label={{row.label}}
                    @hue={{row.hue}}
                    @dot={{true}}
                  />
                {{/each}}
              </div>
            </section>

            <section>
              <h2>Trust</h2>
              <p class='note'>How far an artefact can be relied on, in order.
                Self-asserted is normal and acceptable for a low-risk control;
                it is dull, not alarming.</p>
              <div class='chips'>
                {{#each this.trustLegend as |row|}}
                  <StatePill
                    @label={{row.label}}
                    @hue={{row.hue}}
                    @dot={{true}}
                  />
                {{/each}}
              </div>
            </section>

            <section>
              <h2>Resolution</h2>
              <p class='note'>How a finding was closed. Remediated needs the
                corrective action done; risk-accepted needs an approval.
                "Closed" on its own hides which happened.</p>
              <div class='chips'>
                {{#each this.resolutionLegend as |row|}}
                  <StatePill
                    @label={{row.label}}
                    @hue={{row.hue}}
                    @dot={{true}}
                  />
                {{/each}}
              </div>
            </section>
          </div>
        {{/if}}
      </:default>

      <:aside>
        <div class='rail-card'>
          <h3>Programme</h3>
          <p>Regimes, rules and the auditor arrive with Validation Rule and
            Auditor Bot.</p>
        </div>
        <div class='rail-card'>
          <h3>Fieldwork</h3>
          <p>Findings and their proof arrive with Finding and the Audit command.</p>
        </div>
        <div class='rail-card'>
          <h3>Report</h3>
          <p>Results, coverage and sign-off arrive with Audit Result and
            Standard Evaluation Report.</p>
        </div>
        {{#if @model.authority}}
          <div class='rail-card'>
            <h3>Authority</h3>
            <@fields.authority @format='embedded' />
          </div>
        {{/if}}
      </:aside>
    </AppShell>

    <style scoped>
      .desk {
        --desk-gutter: var(--boxel-sp-lg);
      }
      .desk.dense {
        --desk-gutter: var(--boxel-sp);
      }
      .mast {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp-sm) var(--desk-gutter) 0;
        border-bottom: 1px solid var(--border);
        flex-wrap: wrap;
      }
      .mast-icon {
        width: 1.125rem;
        height: 1.125rem;
      }
      /* A masthead label, deliberately smaller than the page h1 role. */
      .mast-title {
        font-size: var(--boxel-font-size-md);
      }
      .mast-tabs {
        margin-inline-start: var(--boxel-sp);
        align-self: flex-end;
      }
      .new-doc {
        margin-inline-start: auto;
      }
      .brief {
        display: grid;
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp) var(--desk-gutter);
        border-bottom: 1px solid var(--border);
      }
      .eyebrow {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .subtitle {
        max-width: 46rem;
        line-height: 1.55;
      }
      .meta {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp);
        margin-top: var(--boxel-sp-xs);
      }
      .stat {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-6xs);
      }
      .sv {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1.05;
      }
      .sl {
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: var(--boxel-lsp-sm);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .loading {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      /* A register is wide by nature, so it scrolls inside its own box
         rather than pushing the surface sideways. */
      .register-scroll {
        overflow-x: auto;
        max-width: 100%;
      }
      .register {
        width: 100%;
        min-width: 34rem;
        border-collapse: collapse;
        font-size: var(--boxel-font-size-sm);
      }
      .register td:first-child,
      .register th:first-child {
        white-space: nowrap;
      }
      .register th {
        text-align: left;
        font-size: var(--boxel-font-size-2xs);
        font-weight: 700;
        letter-spacing: var(--boxel-lsp-sm);
        text-transform: uppercase;
        color: var(--muted-foreground);
        padding: var(--boxel-sp-5xs) var(--boxel-sp-sm) var(--boxel-sp-5xs) 0;
        border-bottom: 1px solid var(--border);
      }
      .register td {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-xs) 0;
        border-bottom: 1px solid var(--border);
        vertical-align: baseline;
      }
      .muted {
        color: var(--muted-foreground);
      }
      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
      }
      .link {
        font-weight: 600;
      }
      .link-static {
        font-weight: 600;
      }
      .vocab {
        display: grid;
        gap: var(--boxel-sp-lg);
        max-width: 44rem;
      }
      .vocab h2 {
        margin-bottom: var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        letter-spacing: var(--boxel-lsp-sm);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .note {
        margin-bottom: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        line-height: 1.55;
      }
      .chips {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      .rail-card {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp-sm);
        background: var(--card);
        color: var(--card-foreground);
      }
      .rail-card h3 {
        margin-bottom: var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 700;
        letter-spacing: var(--boxel-lsp-sm);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .rail-card p {
        font-size: var(--boxel-font-size-sm);
        line-height: 1.5;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

/**
 * The compliance manager's desk.
 *
 * Stage-2 consumer of the audit blocks: it composes them and owns nothing but
 * its own chrome. The Evidence surface is the live document register with the
 * hash and provenance strip that makes "show me" answerable; Vocabulary is the
 * desk's shared language, rendered from the same exported colour maps the
 * fields use, so a status can never read one way here and another on a record.
 *
 * The programme, fieldwork and report surfaces arrive with their blocks
 * (Validation Rule, Finding, Audit Result, Standard Evaluation Report). They
 * are deliberately absent rather than stubbed: an empty tab that promises a
 * screen is a lying affordance, and this desk would rather show two finished
 * surfaces than four unfinished ones.
 */
export class AuditComplianceDesk extends CardDef {
  static displayName = 'Audit & Compliance Desk';
  static icon = ClipboardCheckIcon;
  static prefersWideFormat = true;

  @field organisation = contains(StringField);
  @field authority = linksTo(() => CertificationAuthority);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AuditComplianceDesk) {
      return this.organisation
        ? `${this.organisation} — Audit & Compliance`
        : 'Audit & Compliance Desk';
    },
  });

  static isolated = AuditComplianceDeskIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <ClipboardCheckIcon class='ic' role='presentation' />
        <div class='what'>
          <span class='name'>{{@model.cardTitle}}</span>
          <span class='sub'>Evidence register and audit vocabulary</span>
        </div>
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .ic {
          width: 1.125rem;
          height: 1.125rem;
          flex: none;
        }
        .what {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FittedCard @titleTag='h3'>
        <:placeholder><ClipboardCheckIcon role='presentation' /></:placeholder>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Compliance desk</:subtitle>
      </FittedCard>
    </template>
  };
}

export default AuditComplianceDesk;
