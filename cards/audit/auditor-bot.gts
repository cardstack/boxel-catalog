import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import BotIcon from '@cardstack/boxel-icons/bot';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { RegimeMetadataField } from './regime-metadata-field';
import { ValidationRuleField } from './validation-rule-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { parametersAreValid } from './utils/rule-evaluation';

/**
 * A configured evaluation: which rules, over which subjects, answerable to whom.
 *
 * **It is configuration, not a process.** Nothing here runs on a timer — the
 * platform has no card-reachable scheduler, so a "scheduled quarterly review"
 * is a person or an assistant invoking the Audit command against this card,
 * and `lastRunAt` records that it happened. Naming it a bot and then having
 * it never run itself would be the misleading kind of block; naming it and
 * recording who ran it is honest.
 *
 * `runsAs` is the accountable human and is not decoration. A bot never signs
 * off a report: an automated result still needs a name against it, which is
 * the rule every certification scheme states and most tools quietly drop.
 */
export class AuditorBot extends CardDef {
  static displayName = 'Auditor Bot';
  static icon = BotIcon;

  @field name = contains(StringField);
  /** Regime-level: the clause is empty here, each rule names its own. */
  @field regime = contains(RegimeMetadataField);
  @field rules = containsMany(ValidationRuleField);
  /** A Search Cards filter, as JSON, selecting the subjects to evaluate. */
  @field subjectQuery = contains(StringField);
  @field runsAs = linksTo(() => Employee);
  @field lastRunAt = contains(DateTimeField);

  @field ruleCount = contains(NumberField, {
    computeVia: function (this: AuditorBot) {
      return (this.rules ?? []).length;
    },
  });

  /** Rules that can never fire are worse than absent — they look like cover. */
  @field brokenRuleCount = contains(NumberField, {
    computeVia: function (this: AuditorBot) {
      return (this.rules ?? []).filter(
        (r) => !r?.fieldPath || !parametersAreValid(r?.parameters),
      ).length;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AuditorBot) {
      return this.name ?? 'Auditor bot';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get broken() {
      return this.args.model?.brokenRuleCount ?? 0;
    }
    get queryValid() {
      let q = this.args.model?.subjectQuery;
      return !q || parametersAreValid(q);
    }
    <template>
      <article class='bot'>
        <header>
          <p class='kicker'>Auditor</p>
          <h1>{{@model.name}}</h1>
          <div class='head-meta'>
            {{#if @model.regime.reference}}
              <@fields.regime @format='atom' />
            {{/if}}
            <span class='meta'>{{@model.ruleCount}} rule(s)</span>
            {{#if this.broken}}
              <StatePill
                @label='rules that cannot fire'
                @hue='red'
                @dot={{true}}
              />
            {{/if}}
          </div>
        </header>

        <section class='facts'>
          <div class='fact'>
            <span class='k'>Runs as</span>
            <span class='v'>
              {{#if @model.runsAs}}
                <@fields.runsAs @format='atom' />
              {{else}}
                <span class='warn'>Nobody — an automated result still needs a
                  name against it.</span>
              {{/if}}
            </span>
          </div>
          <div class='fact'>
            <span class='k'>Last run</span>
            <span class='v'>
              {{#if @model.lastRunAt}}
                <@fields.lastRunAt />
              {{else}}
                <span class='muted'>Never</span>
              {{/if}}
            </span>
          </div>
          <div class='fact'>
            <span class='k'>Subjects</span>
            <span class='v'>
              {{#if @model.subjectQuery}}
                <code class='mono'>{{@model.subjectQuery}}</code>
                {{#unless this.queryValid}}
                  <StatePill @label='not valid JSON' @hue='red' />
                {{/unless}}
              {{else}}
                <span class='muted'>No subject query — nothing would be
                  evaluated.</span>
              {{/if}}
            </span>
          </div>
        </section>

        <section>
          <h2>Rules</h2>
          {{#if @model.rules.length}}
            <@fields.rules />
          {{else}}
            <p class='muted'>No rules yet. A bot with no rules passes
              everything, which is worse than no bot.</p>
          {{/if}}
        </section>
      </article>
      <style scoped>
        .bot {
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          max-width: 52rem;
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
        .warn {
          color: var(--state-next-fg, var(--foreground, var(--boxel-dark)));
        }
        .facts {
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .fact {
          display: grid;
          grid-template-columns: 7rem minmax(0, 1fr);
          gap: var(--boxel-sp-sm);
          align-items: baseline;
          font-size: 0.875rem;
        }
        .k {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
          font-size: 0.8125rem;
          overflow-wrap: anywhere;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <BotIcon class='ic' />
        <div class='what'>
          <span class='name'>{{@model.name}}</span>
          <span class='sub'>{{@model.ruleCount}} rule(s){{#if
              @model.regime.regime
            }} · {{@model.regime.regime}}{{/if}}</span>
        </div>
        {{#if @model.brokenRuleCount}}
          <StatePill @label='needs fixing' @hue='red' @dot={{true}} />
        {{/if}}
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .ic {
          width: 18px;
          height: 18px;
          flex: none;
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
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.name}}</span>
      <style scoped>
        .atom {
          font-size: 0.8125rem;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get regimeLabel() {
      return this.args.model?.regime?.regime ?? '';
    }
    get lastRun() {
      let d = this.args.model?.lastRunAt;
      return d ? d.toISOString().slice(0, 10) : 'never run';
    }
    <template>
      <div class='fit'>
        <span class='fit-name'>{{@model.name}}</span>
        <span class='fit-sub'>{{@model.ruleCount}} rule(s)</span>
        <div class='tier-tile'>
          <span class='row'>{{this.regimeLabel}}</span>
          <span class='row'>Last run {{this.lastRun}}</span>
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

export default AuditorBot;
