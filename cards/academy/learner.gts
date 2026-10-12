import {
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import GraduationCapIcon from '@cardstack/boxel-icons/graduation-cap';
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { Avatar } from '@cardstack/pretui/components/avatar';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

import { PersonBase } from '@cardstack/catalog/cards/people/person-base';
import { Employee } from '@cardstack/catalog/cards/hr/employee';

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
    <template>
      <article class='learner'>
        <header class='hero'>
          <Avatar
            @name={{learnerName @model.title}}
            @src={{@model.photo.resolvedUrl}}
            @size={{72}}
          />
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
          color: var(--foreground);
          background: var(--background);
        }
        .hero {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr);
          gap: var(--boxel-sp);
          align-items: center;
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15 var(--font-sans);
        }
        .contact {
          margin: var(--boxel-sp-xs) 0 0;
          color: var(--muted-foreground);
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
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
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
        <Avatar
          @name={{learnerName @model.title}}
          @src={{@model.photo.resolvedUrl}}
          @size={{36}}
        />
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
          grid-template-columns: auto minmax(0, 1fr);
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
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
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'><Avatar
          @name={{learnerName @model.title}}
          @src={{@model.photo.resolvedUrl}}
          @size={{20}}
        />
        {{@model.title}}</span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
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
      <FittedCard @titleTag='h3' @imageUrl={{@model.photo.resolvedUrl}}>
        <:placeholder><Avatar
            @name={{learnerName @model.title}}
            @size={{40}}
          /></:placeholder>
        <:eyebrow>Learner</:eyebrow>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{@model.organisation}}</:subtitle>
        <:footer>{{if @model.timezone @model.timezone @model.email}}</:footer>
      </FittedCard>
    </template>
  };
}

export default Learner;
