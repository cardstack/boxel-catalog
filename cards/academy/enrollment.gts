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
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';

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
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { Avatar } from '@cardstack/pretui/components/avatar';

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
          color: var(--foreground);
          background: var(--background);
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
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
          font: 700 1.25rem var(--font-sans);
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15 var(--font-sans);
        }
        .meta {
          margin: var(--boxel-sp-xs) 0 0;
          display: flex;
          gap: var(--boxel-sp-sm);
          align-items: center;
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
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
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
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
          color: var(--muted-foreground);
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
      <FittedCard @titleTag='h3'>
        <:placeholder><Avatar
            @name={{if @model.learnerName @model.learnerName 'Learner'}}
            @size={{40}}
          /></:placeholder>
        <:eyebrow>{{@model.cohortName}}</:eyebrow>
        <:title>{{if
            @model.learnerName
            @model.learnerName
            'Unlinked learner'
          }}</:title>
        <:subtitle>{{#if @model.completedAt}}Completed
            {{fmtDate @model.completedAt}}{{else if @model.enrolledAt}}Enrolled
            {{fmtDate @model.enrolledAt}}{{/if}}</:subtitle>
        <:badgeRight><StatePill
            @label={{@model.statusLabel}}
            @hue={{this.hue}}
          /></:badgeRight>
        <:footer>{{@model.paymentRef}}</:footer>
      </FittedCard>
    </template>
  };
}

export function fmtDate(d?: Date | string | null): string {
  if (!d) return '';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export default Enrollment;
