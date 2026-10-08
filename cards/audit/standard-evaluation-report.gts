import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import DateRangeField from '@cardstack/base/date-range-field';
import BooleanField from '@cardstack/base/boolean';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';

import { Document } from '@cardstack/catalog/cards/audit/document';
import { AuditResult } from '@cardstack/catalog/cards/audit/audit-result';
import { RegimeMetadataField } from '@cardstack/catalog/cards/audit/regime-metadata-field';
import {
  EvaluationStatusField,
  EVALUATION_HUE,
} from '@cardstack/catalog/fields/evaluation-status/evaluation-status-field';
import { ApprovalChainField } from '@cardstack/catalog/cards/hr/approval-chain-field';
import { LifecycleDatesField } from '@cardstack/catalog/fields/lifecycle-dates/lifecycle-dates-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { SeverityBadge } from '@cardstack/catalog/cards/audit/components/severity-badge';
import { certificateAtRisk } from '@cardstack/catalog/cards/audit/severity-vocabulary';

/**
 * What the certifier receives: a period, a boundary, the results, and a name
 * against them.
 *
 * **Findings are not stored here.** They live on the results that raised
 * them and are read back by walking `results`, so a finding can never be
 * closed in one place and still read open in another. The product spec kept
 * a separate `findings` list; one copy is worth more than two views of it.
 *
 * `coverage` counts conclusive verdicts over rules that applied, so a run
 * full of `unproven` reports thin coverage rather than a clean bill — the
 * single most common way a compliance dashboard flatters itself.
 *
 * Sign-off is the existing Approval Chain block, unchanged. A report with an
 * open critical finding reports `signOffBlocked`, and the chain's second step
 * is meant to be held on it: a certificate must not be signed over a gap that
 * puts it at risk.
 */
export class StandardEvaluationReport extends CardDef {
  static displayName = 'Standard Evaluation Report';
  static icon = ClipboardCheckIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  /** Regime-level: the clause is empty, each result's rule names its own. */
  @field regime = contains(RegimeMetadataField);
  @field period = contains(DateRangeField);
  /** The boundary in words — what was in scope and what was deliberately not. */
  @field scope = contains(TextAreaField);
  @field subjectsEvaluated = contains(NumberField);
  @field results = linksToMany(() => AuditResult);
  @field rollup = contains(EvaluationStatusField);
  @field coverage = contains(NumberField);
  @field signOff = contains(ApprovalChainField);
  @field certificate = linksTo(() => Document);
  @field lifecycle = contains(LifecycleDatesField);

  @field resultCount = contains(NumberField, {
    computeVia: function (this: StandardEvaluationReport) {
      return (this.results ?? []).filter(Boolean).length;
    },
  });

  @field findingCount = contains(NumberField, {
    computeVia: function (this: StandardEvaluationReport) {
      return (this.results ?? []).filter((r) => r?.finding?.findingId).length;
    },
  });

  @field openCriticalCount = contains(NumberField, {
    computeVia: function (this: StandardEvaluationReport) {
      return (this.results ?? []).filter(
        (r) =>
          r?.finding?.findingId &&
          r.finding.state !== 'closed' &&
          certificateAtRisk(r.finding.severity?.level),
      ).length;
    },
  });

  /** A certificate must not be signed over a gap that puts it at risk. */
  @field signOffBlocked = contains(BooleanField, {
    computeVia: function (this: StandardEvaluationReport) {
      return (this.openCriticalCount ?? 0) > 0;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: StandardEvaluationReport) {
      return this.title ?? 'Standard evaluation report';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get hue() {
      return EVALUATION_HUE[this.args.model?.rollup?.status ?? ''] ?? 'slate';
    }
    get findings() {
      return (this.args.model?.results ?? [])
        .filter((r) => r?.finding?.findingId)
        .map((r) => r.finding);
    }
    <template>
      <article class='report'>
        <header>
          <p class='kicker'>Standard evaluation report</p>
          <h1>{{@model.title}}</h1>
          <div class='head-meta'>
            <StatePill
              @label={{@model.rollup.label}}
              @hue={{this.hue}}
              @dot={{true}}
            />
            {{#if @model.period}}
              <span class='meta'><@fields.period /></span>
            {{/if}}
            {{#if @model.regime.regime}}
              <span class='meta'>{{@model.regime.regime}}</span>
            {{/if}}
          </div>
        </header>

        <section class='stats'>
          <div class='stat'>
            <span class='sv'>{{@model.subjectsEvaluated}}</span>
            <span class='sl'>subjects</span>
          </div>
          <div class='stat'>
            <span class='sv'>{{@model.resultCount}}</span>
            <span class='sl'>results</span>
          </div>
          <div class='stat'>
            <span class='sv'>{{@model.findingCount}}</span>
            <span class='sl'>findings</span>
          </div>
          <div class='stat'>
            <span class='sv'>{{@model.coverage}}%</span>
            <span class='sl'>coverage</span>
          </div>
        </section>

        {{#if @model.scope}}
          <section>
            <h2>Scope</h2>
            <p class='scope'>{{@model.scope}}</p>
          </section>
        {{/if}}

        {{#if @model.signOffBlocked}}
          <p class='blocked'>
            <SeverityBadge @level='critical' @compact={{true}} />
            Sign-off is held:
            {{@model.openCriticalCount}}
            open finding(s) put the certificate at risk.
          </p>
        {{/if}}

        <section>
          <h2>Findings</h2>
          {{#if this.findings.length}}
            {{#each this.findings as |f|}}
              <div class='finding-row'>{{f.findingId}}
                ·
                {{f.rule.ruleId}}
                ·
                {{f.state}}</div>
            {{/each}}
          {{else}}
            <p class='muted'>No findings raised in this period.</p>
          {{/if}}
        </section>

        <section>
          <h2>Results</h2>
          {{#if @model.results.length}}
            <@fields.results />
          {{else}}
            <p class='muted'>No results yet — the audit has not been run.</p>
          {{/if}}
        </section>

        {{#if @model.signOff}}
          <section>
            <h2>Sign-off</h2>
            <@fields.signOff />
          </section>
        {{/if}}
      </article>
      <style scoped>
        .report {
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          max-width: 60rem;
          color: var(--foreground, var(--boxel-dark));
        }
        header {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .kicker {
          margin: 0;
          font-size: 0.6875rem;
          font-weight: 700;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        h1 {
          margin: 0;
          font-size: 1.5rem;
          font-family: var(--font-heading, inherit);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .head-meta {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: 0.8125rem;
        }
        .meta,
        .muted {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .stats {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp) 0;
          border-top: 1px solid var(--border, var(--boxel-200));
          border-bottom: 1px solid var(--border, var(--boxel-200));
        }
        .stat {
          display: flex;
          flex-direction: column;
        }
        .sv {
          font-size: 1.5rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          line-height: 1.1;
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        .sl {
          font-size: 0.6875rem;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .scope {
          margin: 0;
          font-size: 0.875rem;
          line-height: 1.55;
          max-width: 46rem;
        }
        .blocked {
          margin: 0;
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: 0.875rem;
          font-weight: 600;
        }
        .finding-row {
          font-size: 0.8125rem;
          font-family: var(--font-mono, ui-monospace, monospace);
          padding: 0.2rem 0;
          border-bottom: 1px solid var(--border-subtle, var(--border, #f3f4f6));
        }
        .muted {
          margin: 0;
          font-size: 0.875rem;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return EVALUATION_HUE[this.args.model?.rollup?.status ?? ''] ?? 'slate';
    }
    <template>
      <div class='row'>
        <div class='what'>
          <span class='name'>{{@model.title}}</span>
          <span class='sub'>{{@model.resultCount}}
            results ·
            {{@model.findingCount}}
            findings ·
            {{@model.coverage}}% coverage</span>
        </div>
        <StatePill
          @label={{@model.rollup.label}}
          @hue={{this.hue}}
          @dot={{true}}
        />
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .what {
          display: flex;
          flex-direction: column;
          gap: 1px;
          min-width: 0;
          flex: 1;
        }
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
        }
        .sub {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.title}}</span>
      <style scoped>
        .atom {
          font-size: 0.8125rem;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fit'>
        <span class='fit-name'>{{@model.title}}</span>
        <span class='fit-sub'>{{@model.rollup.label}}</span>
        <div class='tier-tile'>
          <span class='row'>{{@model.resultCount}}
            results ·
            {{@model.findingCount}}
            findings</span>
          <span class='row'>{{@model.coverage}}% coverage</span>
        </div>
      </div>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-name {
          font-weight: 600;
          font-size: 0.9375rem;
          line-height: 1.2;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .fit-sub,
        .row {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .tier-tile {
          display: none;
          flex-direction: column;
          gap: 2px;
          margin-top: auto;
          padding-top: var(--boxel-sp-5xs);
          border-top: 1px solid var(--border-subtle, var(--border, #f3f4f6));
        }
        @container fitted-card (height <= 65px) {
          .fit {
            flex-direction: row;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (height > 120px) {
          .tier-tile {
            display: flex;
          }
        }
      </style>
    </template>
  };
}

export default StandardEvaluationReport;
