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
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import type { KeyValueItem } from '../../ui-component/components/key-value';
import { FittedExtras } from '../procurement/vendor';

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
    get subtitle() {
      let m = this.args.model;
      return [
        m?.cohortName,
        m?.enrolledAt ? `enrolled ${fmtDate(m.enrolledAt)}` : '',
      ]
        .filter(Boolean)
        .join(' · ');
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Enrolled', value: fmtDate(m?.enrolledAt) || '—' },
        { key: 'Payment ref', value: m?.paymentRef || '—' },
        { key: 'Withdrawn', value: fmtDate(m?.withdrawnAt) || '—' },
        { key: 'Completed', value: fmtDate(m?.completedAt) || '—' },
        { key: 'Certificate', value: m?.certificate ? 'issued' : 'not issued' },
      ];
    }
    <template>
      <article class='enrollment'>
        <header class='iso-head'>
          <Avatar @name='E N' @size={{48}} aria-hidden='true' />
          <div class='iso-id'>
            <h1>{{if
                @model.learnerName
                @model.learnerName
                'Unlinked learner'
              }}</h1>
            {{#if this.subtitle}}<p class='iso-sub'>{{this.subtitle}}</p>{{/if}}
          </div>
          <span class='iso-chips'>
            <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
            {{#if @model.paymentRef}}<StatePill
                @label={{@model.paymentRef}}
                @hue='slate'
              />{{/if}}
          </span>
        </header>

        <section class='progress'>
          <LearnerProgress @enrollment={{@model}} @context={{@context}} />
        </section>

        {{#if @context.getCards}}
          <LearnerActions @enrollment={{@model}} @context={{@context}} />
        {{/if}}

        <div class='iso-body'>
          <section class='panel'>
            <h2>Enrollment</h2>
            <dl class='kv'>
              {{#each this.details as |f|}}
                <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
              {{/each}}
            </dl>
          </section>
          <section class='panel'>
            <h2>Linked</h2>
            <dl class='kv'>
              <div><dt>Learner</dt><dd>{{#if @model.learner}}<@fields.learner
                      @format='atom'
                    />{{else}}—{{/if}}</dd></div>
              <div><dt>Cohort</dt><dd>{{#if @model.cohort}}<@fields.cohort
                      @format='atom'
                    />{{else}}—{{/if}}</dd></div>
            </dl>
          </section>
        </div>

        {{#if @model.certificate}}
          <section class='panel'>
            <h2>Certificate</h2>
            <@fields.certificate @format='embedded' />
          </section>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .enrollment {
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
    get subtitle() {
      let m = this.args.model;
      return [
        m?.cohortName,
        m?.enrolledAt ? `enrolled ${fmtDate(m.enrolledAt)}` : '',
      ]
        .filter(Boolean)
        .join(' · ');
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Status', value: m?.statusLabel ?? '—' },
        { key: 'Enrolled', value: fmtDate(m?.enrolledAt) || '—' },
        { key: 'Payment', value: m?.paymentRef || '—' },
        { key: 'Withdrawn', value: fmtDate(m?.withdrawnAt) || '—' },
        { key: 'Completed', value: fmtDate(m?.completedAt) || '—' },
      ];
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <Avatar @name='E N' @size={{40}} aria-hidden='true' />
          <div class='emb-id'>
            <h4 class='emb-title'>{{if
                @model.learnerName
                @model.learnerName
                'Unlinked learner'
              }}</h4>
            {{#if this.subtitle}}<p class='emb-sub'>{{this.subtitle}}</p>{{/if}}
          </div>
          <div class='emb-chips'>
            <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
            {{#if @model.paymentRef}}<StatePill
                @label={{@model.paymentRef}}
                @hue='slate'
              />{{/if}}
          </div>
        </header>
        <dl class='emb-kv'>
          {{#each this.facts as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        {{#if @model.learner}}
          <div class='emb-rels'>
            <span class='emb-rel'>Learner
              <@fields.learner @format='atom' /></span>
            {{#if @model.cohort}}<span class='emb-rel'>Cohort
                <@fields.cohort @format='atom' /></span>{{/if}}
          </div>
        {{else if @model.cohort}}
          <div class='emb-rels'><span class='emb-rel'>Cohort
              <@fields.cohort @format='atom' /></span></div>
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
    get hue() {
      return statusHue(
        EnrollmentStatusField,
        this.args.model?.enrollmentStatus,
      );
    }
    <template>
      <span class='enr-atom'>
        <Avatar @name='E N' @size={{20}} aria-hidden='true' />
        <span class='enr-atom-name'>{{@model.cardTitle}}</span>
        {{#if @model.enrollmentStatus}}<span class='enr-atom-chip'><StatePill
              @label={{@model.statusLabel}}
              @hue={{this.hue}}
            /></span>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .enr-atom {
            /* the host's atom wrapper pads 0.25rem all round; FitTile's relation line is 1.375rem, so pull the atom up by that padding and the pill is not cut */
            margin-block: -0.25rem;
            display: flex;
            inline-size: fit-content;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.375rem;
            row-gap: 1.375rem;
            overflow: hidden;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.375rem;
            color: var(--foreground);
            white-space: nowrap;
          }
          .enr-atom-name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .enr-atom-chip {
            flex: none;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(
        EnrollmentStatusField,
        this.args.model?.enrollmentStatus,
      );
    }
    get fact() {
      let m = this.args.model;
      if (m?.completedAt) return `Completed ${fmtDate(m.completedAt)}`;
      if (m?.enrolledAt) return `Enrolled ${fmtDate(m.enrolledAt)}`;
      return '';
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Learner', value: m?.learnerName || '—' },
        { key: 'Cohort', value: m?.cohortName || '—' },
        { key: 'Status', value: m?.statusLabel ?? '—' },
        { key: 'Enrolled', value: fmtDate(m?.enrolledAt) || '—' },
        { key: 'Payment', value: m?.paymentRef || '—' },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar @name='E N' @size={{32}} aria-hidden='true' />
            </:avatar>
            <:title><span class='fit-title' role='heading' aria-level='3'>{{if
                  @model.learnerName
                  @model.learnerName
                  'Unlinked learner'
                }}</span></:title>
            <:subtitle>{{@model.cohortName}}</:subtitle>
            <:status>
              <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
            </:status>
            <:fact>{{this.fact}}</:fact>
            <:relations>
              {{#if @model.learner}}<@fields.learner @format='atom' />{{/if}}
              {{#if @model.cohort}}<@fields.cohort @format='atom' />{{/if}}
            </:relations>
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

export function fmtDate(d?: Date | string | null): string {
  if (!d) return '';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export default Enrollment;
