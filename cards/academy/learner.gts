import {
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import GraduationCapIcon from '@cardstack/boxel-icons/graduation-cap';
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

import { PersonBase } from '@cardstack/catalog/cards/people/person-base';
import { Employee } from '@cardstack/catalog/cards/hr/employee';

/**
 * A person who takes cohorts. Extends the realm's PersonBase (name, email,
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
    <template>
      <article class='learner'>
        <header class='hero'>
          {{#if @model.photo.resolvedUrl}}
            <img class='avatar' src={{@model.photo.resolvedUrl}} alt='' />
          {{else}}
            <span class='avatar avatar-text'>{{@model.initials}}</span>
          {{/if}}
          <div class='hero-text'>
            <span class='eyebrow'>Learner{{#if @model.organisation}}
                ·
                {{@model.organisation}}{{/if}}</span>
            <h1>{{@model.title}}</h1>
            <p class='contact'>
              {{#if @model.email}}<a
                  href='mailto:{{@model.email}}'
                >{{@model.email}}</a>{{/if}}
              {{#if @model.phone}}<span
                  class='dot'
                >·</span>{{@model.phone}}{{/if}}
              {{#if @model.timezone}}<span
                  class='dot'
                >·</span>{{@model.timezone}}{{/if}}
            </p>
          </div>
        </header>
        {{#if @model.linkedEmployee}}
          <section class='panel'>
            <h2>Staff record</h2>
            <@fields.linkedEmployee @format='embedded' />
          </section>
        {{/if}}
        {{#if @model.notes}}
          <section class='panel'>
            <h2>Notes</h2>
            <p class='notes'>{{@model.notes}}</p>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .learner {
          max-width: 48rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground, var(--boxel-dark));
          background: var(--background, var(--boxel-light));
        }
        .hero {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: var(--boxel-sp);
          align-items: center;
        }
        .avatar {
          width: 4.5rem;
          height: 4.5rem;
          border-radius: 50%;
          object-fit: cover;
        }
        .avatar-text {
          display: grid;
          place-items: center;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font: 700 1.5rem var(--font-heading, var(--boxel-font-family));
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15
            var(--font-heading, var(--boxel-font-family));
        }
        .contact {
          margin: var(--boxel-sp-xs) 0 0;
          color: var(--muted-foreground, var(--boxel-450));
          font-size: var(--boxel-font-size-sm);
        }
        .contact a {
          color: inherit;
        }
        .dot {
          margin: 0 var(--boxel-sp-4xs);
        }
        .panel {
          padding: var(--boxel-sp);
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card, var(--boxel-light));
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .notes {
          margin: 0;
          white-space: pre-wrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        {{#if @model.photo.resolvedUrl}}
          <img class='avatar' src={{@model.photo.resolvedUrl}} alt='' />
        {{else}}
          <span class='avatar avatar-text'>{{@model.initials}}</span>
        {{/if}}
        <div class='text'>
          <span class='name'>{{@model.title}}</span>
          <span class='sub'>{{if
              @model.organisation
              @model.organisation
              @model.email
            }}</span>
        </div>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .avatar {
          width: 2.25rem;
          height: 2.25rem;
          border-radius: 50%;
          object-fit: cover;
        }
        .avatar-text {
          display: grid;
          place-items: center;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub {
          font-size: var(--boxel-font-size-sm);
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
      <span class='atom'><span class='ini'>{{@model.initials}}</span>
        {{@model.title}}</span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
        .ini {
          width: 1.25rem;
          height: 1.25rem;
          display: grid;
          place-items: center;
          border-radius: 50%;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font-size: 11px;
          font-weight: 700;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'contact', label: 'Contact' },
      { id: 'photo', label: 'Photo' },
      { id: 'links', label: 'Staff & notes' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Learner sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{2}}>
          <FieldContainer @label='Name' @vertical={{true}}><@fields.name
            /></FieldContainer>
          <FieldContainer
            @label='Organisation'
            @vertical={{true}}
          ><@fields.organisation /></FieldContainer>
        </e.Section>
        <e.Section @id='contact' @title='Contact' @cols={{3}}>
          <FieldContainer @label='Email' @vertical={{true}}><@fields.email
            /></FieldContainer>
          <FieldContainer @label='Phone' @vertical={{true}}><@fields.phone
            /></FieldContainer>
          <FieldContainer
            @label='Timezone (IANA)'
            @vertical={{true}}
          ><@fields.timezone /></FieldContainer>
        </e.Section>
        <e.Section @id='photo' @title='Photo' @cols={{1}}>
          <FieldContainer @label='Photo' @vertical={{true}}><@fields.photo
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='links'
          @title='Staff & notes'
          @hint='link the Employee when the learner is on staff'
          @cols={{1}}
        >
          <FieldContainer
            @label='Linked employee'
            @vertical={{true}}
          ><@fields.linkedEmployee /></FieldContainer>
          <FieldContainer @label='Notes' @vertical={{true}}><@fields.notes
            /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <div class='fit-top'>
          {{#if @model.photo.resolvedUrl}}
            <img class='avatar' src={{@model.photo.resolvedUrl}} alt='' />
          {{else}}
            <span class='avatar avatar-text'>{{@model.initials}}</span>
          {{/if}}
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{#if @model.organisation}}<span
                class='fit-eb'
              >{{@model.organisation}}</span>{{/if}}
          </div>
        </div>
        <dl class='fit-add'>
          {{#if @model.email}}<div><dt>Email</dt><dd
              >{{@model.email}}</dd></div>{{/if}}
          {{#if @model.timezone}}<div><dt>Zone</dt><dd
              >{{@model.timezone}}</dd></div>{{/if}}
        </dl>
      </article>
      <style scoped>
        .fit {
          height: 100%;
          padding: var(--boxel-sp-xs);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-top {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
          min-width: 0;
        }
        .avatar {
          flex: none;
          width: 2.25rem;
          height: 2.25rem;
          border-radius: 50%;
          object-fit: cover;
        }
        .avatar-text {
          display: grid;
          place-items: center;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
        }
        .fit-head {
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          font-size: 11px;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .fit-add {
          display: none;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
        }
        .fit-add div {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          padding: 2px 0;
          border-top: 1px solid var(--border, var(--boxel-200));
          min-width: 0;
        }
        dt {
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 150px) {
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (width <= 120px) {
          .fit-top {
            flex-direction: column;
            align-items: flex-start;
          }
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (min-width: 250px) and (min-height: 120px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
        @container fitted-card (min-width: 150px) and (min-height: 190px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
      </style>
    </template>
  };
}

export default Learner;
