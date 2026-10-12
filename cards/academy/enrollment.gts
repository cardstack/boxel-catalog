import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import UserPlusIcon from '@cardstack/boxel-icons/user-plus';
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

import {
  EnrollmentStatusField,
  ENROLLMENT_STATUSES,
} from './enrollment-status-field';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Learner } from './learner';
import { Cohort } from './cohort';
import { Certificate } from './certificate';
import { LearnerProgress } from './components/learner-progress';
import { LearnerActions } from './components/learner-actions';

/**
 * One learner's seat in one cohort — the card everything about that
 * learner's run hangs off: submissions, attendance, quiz attempts, and
 * finally the certificate. Own attributes are the seat facts (status,
 * dates, payment reference). Attendance %, progress % and the completion
 * verdict are computed from the realm by the Learner Progress block, never
 * stored here — so a corrected attendance mark corrects the verdict.
 */
export class Enrollment extends CardDef {
  static displayName = 'Enrollment';
  static icon = UserPlusIcon;

  @field learner = linksTo(() => Learner);
  @field cohort = linksTo(() => Cohort);
  @field enrollmentStatus = contains(EnrollmentStatusField);
  @field enrolledAt = contains(DateTimeField);
  @field withdrawnAt = contains(DateTimeField);
  @field completedAt = contains(DateTimeField, {
    description: 'Written once by Issue Certificate or a cohort close.',
  });
  @field paymentRef = contains(StringField, {
    description: 'Invoice or payment reference, if the seat was paid.',
  });
  @field certificate = linksTo(() => Certificate as any);

  @field learnerName = contains(StringField, {
    computeVia: function (this: Enrollment) {
      return this.learner?.name ?? '';
    },
  });
  @field learnerInitials = contains(StringField, {
    computeVia: function (this: Enrollment) {
      return this.learner?.initials ?? '?';
    },
  });
  @field cohortName = contains(StringField, {
    computeVia: function (this: Enrollment) {
      return this.cohort?.cardTitle ?? '';
    },
  });
  @field statusLabel = contains(StringField, {
    computeVia: function (this: Enrollment) {
      return (
        ENROLLMENT_STATUSES.find((s) => s.value === this.enrollmentStatus)
          ?.label ?? 'Invited'
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Enrollment) {
      let who = this.learner?.name ?? 'Learner';
      let where = this.cohort?.cardTitle;
      return where ? `${who} · ${where}` : who;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get hue() {
      return statusHue(
        EnrollmentStatusField,
        this.args.model?.enrollmentStatus,
      );
    }
    <template>
      <article class='enrollment'>
        <header class='hero'>
          <span class='avatar'>{{@model.learnerInitials}}</span>
          <div class='hero-text'>
            <span class='eyebrow'>Enrollment ·
              {{#if @model.cohort}}<@fields.cohort @format='atom' />{{else}}no
                cohort{{/if}}</span>
            <h1>{{if
                @model.learnerName
                @model.learnerName
                'Unlinked learner'
              }}</h1>
            <p class='meta'>
              <StatePill
                @label={{@model.statusLabel}}
                @hue={{this.hue}}
                @dot={{true}}
              />
              {{#if @model.enrolledAt}}<span>enrolled
                  {{fmtDate @model.enrolledAt}}</span>{{/if}}
              {{#if @model.withdrawnAt}}<span>withdrew
                  {{fmtDate @model.withdrawnAt}}</span>{{/if}}
              {{#if @model.completedAt}}<span>completed
                  {{fmtDate @model.completedAt}}</span>{{/if}}
              {{#if @model.paymentRef}}<span
                  class='mono'
                >{{@model.paymentRef}}</span>{{/if}}
            </p>
          </div>
        </header>

        <section class='progress'>
          <LearnerProgress @enrollment={{@model}} @context={{@context}} />
        </section>

        {{#if @context.getCards}}
          <LearnerActions @enrollment={{@model}} @context={{@context}} />
        {{/if}}

        {{#if @model.certificate}}
          <section class='panel'>
            <h2>Certificate</h2>
            <@fields.certificate @format='embedded' />
          </section>
        {{/if}}
      </article>
      <style scoped>
        .enrollment {
          max-width: 60rem;
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
          width: 3.5rem;
          height: 3.5rem;
          display: grid;
          place-items: center;
          border-radius: 50%;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font: 700 1.25rem var(--font-heading, var(--boxel-font-family));
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15
            var(--font-heading, var(--boxel-font-family));
        }
        .meta {
          margin: var(--boxel-sp-xs) 0 0;
          display: flex;
          gap: var(--boxel-sp-sm);
          align-items: center;
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
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
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return statusHue(
        EnrollmentStatusField,
        this.args.model?.enrollmentStatus,
      );
    }
    <template>
      <div class='row'>
        <span class='avatar'>{{@model.learnerInitials}}</span>
        <div class='text'>
          <span class='name'>{{if
              @model.learnerName
              @model.learnerName
              'Unlinked learner'
            }}</span>
          <span class='sub'>{{@model.cohortName}}{{#if @model.enrolledAt}}
              · since
              {{fmtDate @model.enrolledAt}}{{/if}}</span>
        </div>
        <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .avatar {
          width: 2.25rem;
          height: 2.25rem;
          display: grid;
          place-items: center;
          border-radius: 50%;
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
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'seat', label: 'Seat' },
      { id: 'dates', label: 'Dates' },
      { id: 'payment', label: 'Payment & certificate' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Enrollment sections'
        as |e|
      >
        <e.Section @id='seat' @title='Seat' @cols={{3}}>
          <FieldContainer @label='Learner' @vertical={{true}}><@fields.learner
            /></FieldContainer>
          <FieldContainer @label='Cohort' @vertical={{true}}><@fields.cohort
            /></FieldContainer>
          <FieldContainer
            @label='Status'
            @vertical={{true}}
          ><@fields.enrollmentStatus /></FieldContainer>
        </e.Section>
        <e.Section
          @id='dates'
          @title='Dates'
          @hint='completed is normally written by Issue Certificate'
          @cols={{3}}
        >
          <FieldContainer
            @label='Enrolled'
            @vertical={{true}}
          ><@fields.enrolledAt /></FieldContainer>
          <FieldContainer
            @label='Withdrawn'
            @vertical={{true}}
          ><@fields.withdrawnAt /></FieldContainer>
          <FieldContainer
            @label='Completed'
            @vertical={{true}}
          ><@fields.completedAt /></FieldContainer>
        </e.Section>
        <e.Section @id='payment' @title='Payment & certificate' @cols={{2}}>
          <FieldContainer
            @label='Payment reference'
            @vertical={{true}}
          ><@fields.paymentRef /></FieldContainer>
          <FieldContainer
            @label='Certificate'
            @vertical={{true}}
          ><@fields.certificate /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(
        EnrollmentStatusField,
        this.args.model?.enrollmentStatus,
      );
    }
    <template>
      <article class='fit'>
        <div class='fit-top'>
          <span class='avatar'>{{@model.learnerInitials}}</span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{if
                @model.learnerName
                @model.learnerName
                'Unlinked learner'
              }}</h3>
            <span class='fit-eb'>{{@model.cohortName}}</span>
          </div>
          <span class='fit-pill'><StatePill
              @label={{@model.statusLabel}}
              @hue={{this.hue}}
            /></span>
        </div>
        <dl class='fit-add'>
          {{#if @model.enrolledAt}}<div><dt>Enrolled</dt><dd>{{fmtDate
                  @model.enrolledAt
                }}</dd></div>{{/if}}
          {{#if @model.completedAt}}<div><dt>Completed</dt><dd>{{fmtDate
                  @model.completedAt
                }}</dd></div>{{/if}}
          {{#if @model.paymentRef}}<div><dt>Payment</dt><dd
                class='mono'
              >{{@model.paymentRef}}</dd></div>{{/if}}
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
          width: 2rem;
          height: 2rem;
          display: grid;
          place-items: center;
          border-radius: 50%;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font-weight: 700;
          font-size: var(--boxel-font-size-xs);
        }
        .fit-head {
          min-width: 0;
          flex: 1;
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
        .fit-pill {
          flex: none;
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
        }
        dt {
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
          font-weight: 600;
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 220px) {
          .fit-pill {
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

export function fmtDate(d?: Date | string | null): string {
  if (!d) return '';
  return new Date(d).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export default Enrollment;
