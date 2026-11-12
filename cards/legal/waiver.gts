import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';

import { Contract } from './contract';
import { LegalEntity } from './legal-entity';
import { Alert } from '@cardstack/pretui/components/alert';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import HandStopIcon from '@cardstack/boxel-icons/hand-stop';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';

export const WAIVER_SCOPES = ['one-time', 'ongoing'];

export const WaiverScopeField = markDefinition(
  enumField(StringField, {
    options: WAIVER_SCOPES.map((value) => ({ value, label: value })),
    displayName: 'Waiver Scope',
  }),
);

// A waiver EXCUSES one obligation without changing the contract's text —
// "we will not enforce the late fee for the March invoice." The scope
// distinction is the legally dangerous part and is therefore a first-class
// field: a one-time waiver expires with its occasion; an ongoing one can be
// read as abandoning the right, which is why real waivers name an expiry.
// Contrast with Amendment (changes terms) and Addendum (adds terms).
export class Waiver extends CardDef {
  static displayName = 'Waiver';

  @field contract = linksTo(() => Contract);
  @field grantedTo = linksTo(() => LegalEntity);
  @field provisionWaived = contains(StringField, {
    description: 'Which section/obligation is being waived',
  });
  @field scope = contains(WaiverScopeField);
  @field effectiveDate = contains(DateField);
  @field expiresOn = contains(DateField);
  @field reason = contains(TextAreaField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Waiver) {
      return this.provisionWaived?.trim()?.length
        ? `Waiver — ${this.provisionWaived}`
        : 'Waiver';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get windowLabel() {
      let from = this.args.model?.effectiveDate;
      let to = this.args.model?.expiresOn;
      if (from && to) {
        return `${formatDay(from)} → ${formatDay(to)}`;
      }
      if (from) {
        return `from ${formatDay(from)}`;
      }
      if (to) {
        return `until ${formatDay(to)}`;
      }
      return '—';
    }
    <template>
      <IsoFrame>
        <article class='doc'>
          <header class='head'>
            <div>
              <p class='kicker'>Waiver</p>
              <h1>{{@model.cardTitle}}</h1>
              <p class='sub'>{{this.windowLabel}}</p>
            </div>
            <StatePill
              @label='{{@model.scope}}'
              @hue={{if (isOngoing @model.scope) 'amber' 'slate'}}
              @emphatic={{true}}
            />
          </header>
          <div class='grid'>
            {{#if @model.contract}}
              <section class='panel'>
                <h2>Under Contract</h2>
                <@fields.contract @format='atom' />
              </section>
            {{/if}}
            {{#if @model.grantedTo}}
              <section class='panel'>
                <h2>Granted To</h2>
                <@fields.grantedTo @format='atom' />
              </section>
            {{/if}}
          </div>
          {{#if @model.reason}}
            <section class='panel'>
              <h2>Reason</h2>
              <p class='reason'>{{@model.reason}}</p>
            </section>
          {{/if}}
          {{#if (needsExpiry @model.scope @model.expiresOn)}}
            <Alert
              @tone='attention'
              @title='Ongoing waiver'
              style={{ALERT_STYLE.attention}}
            >Without an expiry this can read as abandoning the right entirely.</Alert>
          {{/if}}
        </article>
      </IsoFrame>
      <style scoped>
        .doc {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          color: var(--foreground);
          font-family: var(--font-sans);
          display: grid;
          gap: var(--boxel-sp);
        }
        .head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--boxel-sp);
          border-bottom: 1px solid var(--border);
          padding-bottom: var(--boxel-sp);
        }
        .kicker {
          font-size: 0.5625rem; /* 9px ladder label: no token */
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-5xs) 0;
          font-family: var(--font-heading);
          font-size: var(--boxel-font-size-lg);
        }
        .sub {
          color: var(--muted-foreground);
        }
        .grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--boxel-sp);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp);
          background: var(--card);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .reason {
          font-size: var(--boxel-font-size-sm);
          white-space: pre-wrap;
        }
        @container (max-width: 480px) {
          .grid {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };

  /**
   * Fitted — attribute-only (prerendered fitted does not resolve links),
   * on RichFittedCard like the rest of the legal family.
   */
  static fitted = class Fitted extends Component<typeof Waiver> {
    get hue() {
      return this.args.model?.scope === 'ongoing'
        ? ('amber' as const)
        : ('slate' as const);
    }
    <template>
      <RichFittedCard>
        <:avatar><HandStopIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status><StatePill
            @label={{if @model.scope @model.scope 'one-time'}}
            @hue={{this.hue}}
          /></:status>
        <:subtitle>{{@model.reason}}</:subtitle>
        <:details>
          {{#if @model.effectiveDate}}<Detail
              @label='From'
              @value={{formatDay @model.effectiveDate}}
            />{{/if}}
          {{#if @model.expiresOn}}<Detail
              @label='Until'
              @value={{formatDay @model.expiresOn}}
            />{{/if}}
        </:details>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='name'>{{@model.provisionWaived}}</span>
        <StatePill
          @label='{{@model.scope}}'
          @hue={{if (isOngoing @model.scope) 'amber' 'slate'}}
          @dot={{true}}
        />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

// An ongoing waiver with no expiry can read as giving the right up entirely.
function needsExpiry(scope?: string | null, expiresOn?: Date | null) {
  return isOngoing(scope) && !expiresOn;
}

function isOngoing(scope?: string | null) {
  return scope === 'ongoing';
}
