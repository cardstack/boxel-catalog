import {
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import GraduationCapIcon from '@cardstack/boxel-icons/graduation-cap';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import type { KeyValueItem } from '../../ui-component/components/key-value';
import { FittedExtras } from '../procurement/vendor';
import { PersonBase } from '../people/person-base';
import { Employee } from '../hr/employee';

function learnerName(title?: string): string {
  return title ?? 'Unnamed learner';
}

/**
 * A person who takes cohorts. Extends PersonBase (name, email,
 * phone, photo, initials) and adds only what a learner has that a contact
 * does not. `linkedEmployee` is set when the academy trains its own staff —
 * the learner IS an employee — so attendance can roll up to HR without the
 * Employee card learning anything about courses.
 */
export class Learner extends PersonBase {
  static displayName = 'Learner';
  static icon = GraduationCapIcon;

  @field organisation = contains(StringField);
  @field timezone = contains(StringField, {
    description:
      'IANA zone, e.g. Asia/Kuala_Lumpur. Used to show live lesson times.',
  });
  @field notes = contains(StringField);
  @field linkedEmployee = linksTo(() => Employee);

  @field title = contains(StringField, {
    computeVia: function (this: Learner) {
      return this.name?.trim() || 'Unnamed learner';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Learner) {
      return this.name?.trim() || 'Unnamed learner';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get subtitle() {
      let m = this.args.model;
      return [m?.organisation, m?.timezone].filter(Boolean).join(' · ');
    }
    get contact(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Email', value: m?.email || '—' },
        { key: 'Phone', value: m?.phone || '—' },
        { key: 'Organisation', value: m?.organisation || '—' },
        { key: 'Time zone', value: m?.timezone || '—' },
      ];
    }
    <template>
      <article class='learner'>
        <header class='iso-head'>
          <Avatar
            @name={{learnerName @model.title}}
            @src={{@model.photo.resolvedUrl}}
            @size={{48}}
          />
          <div class='iso-id'>
            <h1>{{@model.title}}</h1>
            {{#if this.subtitle}}<p class='iso-sub'>{{this.subtitle}}</p>{{/if}}
          </div>
          {{#if @model.linkedEmployee}}<span class='iso-chips'><StatePill
                @label='staff'
                @hue='blue'
              /></span>{{/if}}
        </header>
        <div class='iso-body'>
          <section class='panel'>
            <h2>Contact</h2>
            <dl class='kv'>
              {{#each this.contact as |f|}}
                <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
              {{/each}}
            </dl>
          </section>
          {{#if @model.linkedEmployee}}
            <section class='panel'>
              <h2>Linked</h2>
              <dl class='kv'>
                <div><dt>Staff record</dt><dd><@fields.linkedEmployee
                      @format='atom'
                    /></dd></div>
              </dl>
            </section>
          {{/if}}
          {{#if @model.notes}}
            <section class='panel wide'>
              <h2>Notes</h2>
              <p class='notes'>{{@model.notes}}</p>
            </section>
          {{/if}}
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .learner {
            container-type: inline-size;
            padding: var(--boxel-sp-lg);
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            color: var(--foreground);
            background: var(--background);
          }
          .iso-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
          }
          .iso-id {
            flex: 1 1 14rem;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
          }
          .iso-sub {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .iso-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .iso-body {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
            gap: var(--boxel-sp-lg);
          }
          .panel {
            min-width: 0;
            padding: var(--boxel-sp-lg);
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: var(--shadow);
          }
          .panel.wide {
            grid-column: 1 / -1;
          }
          h2 {
            margin: 0 0 var(--boxel-sp);
            font-size: var(--boxel-font-size);
            font-weight: 600;
          }
          .kv {
            display: grid;
            gap: var(--boxel-sp-xs);
            margin: 0;
          }
          .kv > div {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            align-items: center;
            gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
            min-width: 0;
          }
          .kv dt {
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .kv dd {
            margin: 0;
            min-width: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            overflow-wrap: anywhere;
          }
          .notes {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            white-space: pre-wrap;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get subtitle() {
      let m = this.args.model;
      return [m?.organisation, m?.timezone].filter(Boolean).join(' · ');
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Email', value: m?.email || '—' },
        { key: 'Phone', value: m?.phone || '—' },
        { key: 'Organisation', value: m?.organisation || '—' },
        { key: 'Time zone', value: m?.timezone || '—' },
      ];
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <Avatar
            @name={{learnerName @model.title}}
            @src={{@model.photo.resolvedUrl}}
            @size={{40}}
          />
          <div class='emb-id'>
            <h4 class='emb-title'>{{@model.title}}</h4>
            {{#if this.subtitle}}<p class='emb-sub'>{{this.subtitle}}</p>{{/if}}
          </div>
          {{#if @model.linkedEmployee}}<div class='emb-chips'><StatePill
                @label='staff'
                @hue='blue'
              /></div>{{/if}}
        </header>
        <dl class='emb-kv'>
          {{#each this.facts as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        {{#if @model.linkedEmployee}}
          <div class='emb-rels'><span class='emb-rel'>Staff record
              <@fields.linkedEmployee @format='atom' /></span></div>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-sm);
            font-size: var(--boxel-font-size-sm);
          }
          .emb-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 12rem;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .emb-sub {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-kv {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
            margin: 0;
          }
          .emb-kv > div {
            min-width: 0;
          }
          .emb-kv dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-kv dd {
            margin: 0;
            font-weight: 600;
            overflow-wrap: anywhere;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-rel {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
            color: var(--muted-foreground);
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='learner-atom'>
        <Avatar
          @name={{learnerName @model.title}}
          @src={{@model.photo.resolvedUrl}}
          @size={{20}}
          aria-hidden='true'
        />
        <span class='learner-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .learner-atom {
            /* the host's atom wrapper pads 0.25rem all round; FitTile's relation line is 1.375rem, so pull the atom up by that padding and the pill is not cut */
            margin-block: -0.25rem;
            display: flex;
            inline-size: fit-content;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            block-size: 1.375rem;
            overflow: hidden;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.375rem;
            color: var(--foreground);
            white-space: nowrap;
          }
          .learner-atom-name {
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get subtitle() {
      let m = this.args.model;
      return m?.organisation || m?.email || '';
    }
    get fact() {
      let m = this.args.model;
      return m?.timezone || m?.email || '';
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Organisation', value: m?.organisation || '—' },
        { key: 'Time zone', value: m?.timezone || '—' },
        { key: 'Email', value: m?.email || '—' },
        { key: 'Phone', value: m?.phone || '—' },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name={{learnerName @model.title}}
                @src={{@model.photo.resolvedUrl}}
                @size={{32}}
                aria-hidden='true'
              />
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.title}}</span></:title>
            <:subtitle>{{this.subtitle}}</:subtitle>
            <:status>{{#if @model.linkedEmployee}}<StatePill
                  @label='staff'
                  @hue='blue'
                />{{/if}}</:status>
            <:fact>{{this.fact}}</:fact>
            <:relations>{{#if @model.linkedEmployee}}<@fields.linkedEmployee
                  @format='atom'
                />{{/if}}</:relations>
          </FitTile>
        </:default>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        }
      </style>
    </template>
  };
}

export default Learner;
