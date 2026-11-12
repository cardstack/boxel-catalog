import { array, hash } from '@ember/helper';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';
import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import MapPinIcon from '@cardstack/boxel-icons/map-pin';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { orEmpty } from './compact-parts';
import { User } from '../crm/user';
import { IsoFrame } from '../shared/compact-sheet';

// Territory — a named sales region or account segment with an owning rep.
// Deals/Opportunities and forecasts are scoped to a Territory, not to an
// individual rep directly, so quota reporting survives a rep being
// reassigned. Domain-neutral: `region` is a free-text string rather than an
// enum, because territory carving (by geography, by industry vertical, by
// account tier) is the consumer's call, not this block's.

export class Territory extends CardDef {
  static displayName = 'Territory';
  static icon = MapPinIcon;

  @field name = contains(StringField);
  @field region = contains(StringField);
  @field owner = linksTo(User);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Territory) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Territory> {
    <template>
      <span class='atom'>
        <Avatar
          @name={{orEmpty @model.cardTitle}}
          @shape='square'
          @size={{16}}
        />
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          min-width: 0;
          max-width: 100%;
          color: var(--foreground);
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Territory> {
    <template>
      <article class='emb'>
        <header>
          <Avatar
            @name={{orEmpty @model.cardTitle}}
            @shape='square'
            @size={{28}}
          />
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p>{{@model.region}} · {{@model.owner.name}}</p>
          </div>
          {{#if @model.region}}<Chip
              @label={{@model.region}}
              @appearance='plain'
            />{{/if}}
        </header>
        <p class='fact'>{{@model.region}} · owner {{@model.owner.name}}</p>
        <KeyValue
          @items={{this.rows}}
          @labelStyle='eyebrow'
          @divided={{true}}
          class='kv'
        />
        {{#if @model.owner}}
          <div class='linked'>
            <span class='cap'>Owner</span>
            <@fields.owner @format='atom' @displayContainer={{false}} />
          </div>
        {{/if}}
      </article>
      <style scoped>
        .emb {
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          display: flex;
          flex-direction: column;
          color: var(--foreground);
        }
        header {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h3 {
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        p {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .fact {
          padding: 0 var(--boxel-sp-xs) var(--boxel-sp-2xs);
        }
        .kv {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
        }
        h3 {
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .linked {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          min-width: 5rem;
        }
      </style>
    </template>
    get rows() {
      return rowsOf(this.args.model as Territory);
    }
  };

  static fitted = class Fitted extends Component<typeof Territory> {
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name='Territory'
            @shape='square'
            @size={{20}}
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status>{{#each
            if @model.region (array (hash label=@model.region))
            as |t|
          }}<Chip
              @label={{t.label}}
              @tone={{t.tone}}
              @appearance='plain'
            />{{/each}}</:status>
        <:subtitle>{{@model.region}} · {{@model.owner.name}}</:subtitle>
        <:fact>{{@model.region}} · owner {{@model.owner.name}}</:fact>
        <:details>
          {{#if @model.region}}<Detail
              @label='Region'
              @value={{@model.region}}
            />{{/if}}
          {{#if @model.owner}}<Detail
              @label='Owner'
              @value={{@model.owner.name}}
            />{{/if}}
          {{#if @model.owner}}<Detail @label='Owner'><@fields.owner
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
        </:details>
      </RichFittedCard>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Territory> {
    get rows() {
      return rowsOf(this.args.model as Territory);
    }
    get nameRows() {
      return this.rows.filter((r) => r.key !== 'Owner');
    }
    get detailRows() {
      return this.rows.filter((r) => r.key !== 'Name');
    }
    <template>
      <IsoFrame>
        <article class='page'>
          <header>
            <Avatar
              @name={{orEmpty @model.cardTitle}}
              @shape='square'
              @size={{32}}
            />
            <div class='id'>
              <h1>{{@model.cardTitle}}</h1>
              <p>{{@model.region}} · {{@model.owner.name}}</p>
            </div>
            {{#if @model.region}}<Chip
                @label={{@model.region}}
                @appearance='plain'
              />{{/if}}
          </header>
          <div class='stats'>
            <Stat
              @label='Region'
              @tone='neutral'
              @value={{if @model.region @model.region '—'}}
              @hint='territory'
              @roll={{false}}
            />
            <Stat
              @label='Owner'
              @tone='neutral'
              @value={{if @model.owner.name @model.owner.name '—'}}
              @roll={{false}}
            />
          </div>
          <section>
            <h2>Territory</h2>
            <KeyValue
              @items={{this.nameRows}}
              @labelStyle='eyebrow'
              @divided={{true}}
              class='kv'
            />
          </section>
          {{#if @model.owner}}
            <section>
              <h2>Linked</h2>
              <div class='linked'>
                <span class='cap'>Owner</span>
                <@fields.owner @format='atom' />
              </div>
            </section>
          {{/if}}
          <section>
            <h2>Details</h2>
            <KeyValue
              @items={{this.detailRows}}
              @labelStyle='eyebrow'
              @divided={{true}}
              class='kv'
            />
          </section>
        </article>
      </IsoFrame>
      <style scoped>
        .page {
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          display: flex;
          flex-direction: column;
          background: var(--card);
          color: var(--foreground);
          container-type: inline-size;
        }
        header {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-sm);
          border-bottom: 1px solid var(--border);
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h1 {
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size);
          font-weight: 700;
        }
        p {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .kv {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
        }
        .stats > * {
          padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        }
        .stats > * + * {
          border-inline-start: 1px solid var(--border);
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
          border-bottom: 1px solid var(--border);
        }
        section h2 {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          border-bottom: 1px solid var(--border);
        }
        .linked {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        }
        .cap {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          min-width: 5rem;
        }
      </style>
    </template>
  };
}

function rowsOf(m: Territory) {
  let rows = [];
  if (m?.name) rows.push({ key: 'Name', value: m.name });
  if (m?.region) rows.push({ key: 'Region', value: m.region });
  if (m?.owner?.name) rows.push({ key: 'Owner', value: m.owner.name });
  return rows;
}
