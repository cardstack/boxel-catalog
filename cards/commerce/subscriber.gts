import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import RepeatIcon from '@cardstack/boxel-icons/repeat';

import { Contact } from '../crm/contact';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Subscription } from './subscription';
import { IsoFrame } from '../shared/compact-sheet';

/**
 * The party on the receiving end of subscriptions — who holds them, since
 * when, and which ones. The Subscription card owns each plan's own life
 * (price, billing cycle, status); this card is the holder-side view that
 * groups them, which is what renewals, upgrade prompts and "your plans"
 * pages address.
 *
 * `subscriptions` is a link array deliberately: a holder's subscriptions
 * are a small, bounded set maintained by whatever command starts or stops
 * one — the rollup rule's link-array case, not its query case.
 */
export class Subscriber extends CardDef {
  static displayName = 'Subscriber';
  static icon = RepeatIcon;

  @field holder = linksTo(Contact);
  @field since = contains(DateField);
  @field subscriptions = linksToMany(Subscription);

  @field activeCount = contains(NumberField, {
    computeVia: function (this: Subscriber) {
      return (this.subscriptions ?? []).filter((s) => s?.status === 'active')
        .length;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Subscriber) {
      return this.holder?.name ?? `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Subscriber> {
    <template>
      <span class='sub-atom'>
        <RepeatIcon class='sub-icon' width='14' height='14' />
        <span class='sub-name'>{{if
            @model.holder.name
            @model.holder.name
            'Unassigned subscriber'
          }}</span>
      </span>
      <style scoped>
        .sub-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
        }
        .sub-icon {
          flex-shrink: 0;
          color: var(--muted-foreground);
        }
        .sub-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Subscriber> {
    get planCount() {
      let n = (this.args.model.subscriptions ?? []).length;
      return n === 1 ? '1 plan' : `${n} plans`;
    }
    <template>
      <div class='sub-row'>
        <div class='sub-id'>
          <span class='sub-name'>{{if
              @model.holder.name
              @model.holder.name
              'Unassigned subscriber'
            }}</span>
          <span class='sub-meta'>{{this.planCount}}
            {{#if @model.since}}· since <@fields.since />{{/if}}</span>
        </div>
        <span class='sub-active'>
          {{#if @model.activeCount}}
            {{@model.activeCount}}
            active
          {{else}}
            none active
          {{/if}}
        </span>
      </div>
      <style scoped>
        .sub-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .sub-id {
          min-width: 0;
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
        }
        .sub-name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        /* Constant-width slot so subscriber rows column-align. */
        .sub-active {
          width: 5.5rem;
          text-align: end;
          flex-shrink: 0;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Subscriber> {
    get planCount() {
      let n = (this.args.model.subscriptions ?? []).length;
      return n === 1 ? '1 plan' : `${n} plans`;
    }
    <template>
      <div class='fitted'>
        <span class='name'>{{if
            @model.holder.name
            @model.holder.name
            'Unassigned subscriber'
          }}</span>
        <span class='meta line-plans'>{{this.planCount}}</span>
        {{#if @model.since}}
          <span class='meta line-since'>Since <@fields.since /></span>
        {{/if}}
      </div>
      <style scoped>
        .fitted {
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: var(--boxel-sp-4xs);
          width: 100%;
          height: 100%;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          box-sizing: border-box;
          overflow: hidden;
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-xs);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .line-plans,
        .line-since {
          display: none;
        }
        /* Badge degradation: strip height keeps only the first line. */
        @container fitted-card (max-height: 50px) {
          .fitted {
            padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
            gap: var(--boxel-sp-6xs);
          }
        }
        @container fitted-card (min-height: 65px) {
          .line-plans {
            display: block;
          }
        }
        @container fitted-card (min-height: 170px) {
          .line-since {
            display: block;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Subscriber> {
    <template>
      <IsoFrame>
        <article class='sub-page'>
          <header class='sh'>
            <div class='sh-id'>
              <p class='doc-kind'>Subscriber</p>
              <h1>{{if
                  @model.holder.name
                  @model.holder.name
                  'Unassigned subscriber'
                }}</h1>
              {{#if @model.since}}
                <p class='sh-since'>Subscriber since <@fields.since /></p>
              {{/if}}
            </div>
            <StatePill
              @label='{{if @model.activeCount @model.activeCount 0}} active'
              @hue={{if @model.activeCount 'green' 'slate'}}
              @dot={{true}}
            />
          </header>
          {{#if @model.holder}}
            <section class='panel'>
              <h2>Holder</h2>
              <div class='linked'><@fields.holder @format='embedded' /></div>
            </section>
          {{/if}}
          <section class='panel'>
            <h2>Subscriptions</h2>
            {{#if @model.subscriptions.length}}
              <div class='subs'><@fields.subscriptions
                  @format='embedded'
                /></div>
            {{else}}
              <EmptyState
                @title='No subscriptions yet'
                @texture={{false}}
                @size='s'
              />
            {{/if}}
          </section>
        </article>
      </IsoFrame>
      <style scoped>
        .sub-page {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          max-width: 40rem;
          margin: 0 auto;
          inline-size: 100%;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
        }
        .sh {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          border-bottom: 2px solid var(--foreground);
          padding-bottom: var(--boxel-sp-lg);
        }
        .sh-id {
          flex: 1;
          min-width: 0;
        }
        .doc-kind {
          margin: 0 0 var(--boxel-sp-6xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .sh-since {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp) var(--boxel-sp-lg);
          background: var(--card);
          color: var(--card-foreground);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-sm);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .subs {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
      </style>
    </template>
  };
}
