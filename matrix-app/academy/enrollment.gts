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
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { Button } from '@cardstack/pretui/components/button';
import { Alert } from '@cardstack/pretui/components/alert';

import {
  EnrollmentStatusField,
  ENROLLMENT_STATUSES,
} from './enrollment-status-field';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { Learner } from './learner';
import { Cohort } from './cohort';
import { Certificate } from './certificate';
import { LearnerProgress } from './components/learner-progress';
import { LearnerActions } from './components/learner-actions';
import WithdrawEnrollmentCommand from './commands/withdraw-enrollment-command';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import {
  AtomChip,
  Dot,
  Embed,
  Kv,
  Mark,
  Section,
  Sheet,
  Stat,
} from './components/record-sheet';
import { FitTile } from '../shared/fit-tile';
import { KvList } from './components/desk-status';

function hueOf(m: any) {
  return statusHue(EnrollmentStatusField, m?.enrollmentStatus);
}

function metaLine(m: any): string {
  return [
    m?.cohortName,
    m?.enrolledAt ? `enrolled ${fmtDate(m.enrolledAt)}` : '',
  ]
    .filter(Boolean)
    .join(' · ');
}

function factLine(m: any): string {
  return [
    m?.enrolledAt ? `Enrolled ${fmtDate(m.enrolledAt)}` : 'Not enrolled yet',
    m?.certificate ? 'certificate issued' : 'no certificate yet',
  ].join(' · ');
}

function seatItems(m: any) {
  return [
    { key: 'Learner', value: m?.learnerName },
    { key: 'Cohort', value: m?.cohortName },
    { key: 'Status', value: m?.statusLabel },
    { key: 'Enrolled', value: fmtDate(m?.enrolledAt) },
    { key: 'Payment ref', value: m?.paymentRef },
    { key: 'Withdrawn', value: fmtDate(m?.withdrawnAt) },
    { key: 'Completed', value: fmtDate(m?.completedAt) },
  ];
}

class EnrollmentIsolated extends Component<typeof Enrollment> {
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked notice: string | undefined;

  get stats(): {
    label: string;
    value?: string | null;
    hint?: string | null;
  }[] {
    let m = this.args.model;
    return [
      {
        label: 'Status',
        value: m?.statusLabel,
        hint: m?.enrolledAt ? `since ${fmtDate(m.enrolledAt)}` : '',
      },
      {
        label: 'Completed',
        value: m?.completedAt ? fmtDate(m.completedAt) : '',
        hint: m?.certificate ? 'certificate issued' : 'not yet',
      },
      { label: 'Payment', value: m?.paymentRef, hint: 'invoice ref' },
    ];
  }
  get details() {
    let m = this.args.model;
    return [
      ...seatItems(m),
      { key: 'Certificate', value: m?.certificate ? 'issued' : 'not issued' },
    ];
  }
  get canWithdraw() {
    let s = this.args.model?.enrollmentStatus;
    return (
      (s === 'active' || s === 'invited') && !!this.args.context?.commandContext
    );
  }
  withdraw = async () => {
    let ctx = this.args.context?.commandContext;
    if (!ctx) return;
    this.busy = true;
    this.error = undefined;
    this.notice = undefined;
    try {
      let res = (await new WithdrawEnrollmentCommand(ctx).execute({
        enrollment: this.args.model,
      } as any)) as any;
      this.notice = res?.message;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  <template>
    <Sheet @mark='En' @title={{@model.cardTitle}} @meta={{metaLine @model}}>
      <:status>
        <Dot @hue={{hueOf @model}}>{{@model.statusLabel}}</Dot>
        {{#if @model.paymentRef}}<Dot>{{@model.paymentRef}}</Dot>{{/if}}
      </:status>
      <:actions>
        {{#if this.canWithdraw}}
          <Button
            type='button'
            @size='xs'
            @tone='danger'
            @appearance='outlined'
            @busy={{this.busy}}
            @disabled={{this.busy}}
            {{on 'click' this.withdraw}}
          >Withdraw</Button>
        {{/if}}
      </:actions>
      <:stats>{{#each this.stats as |st|}}<Stat
            @label={{st.label}}
            @value={{st.value}}
            @sub={{st.hint}}
          />{{/each}}</:stats>
      <:main>
        {{#if this.error}}
          <Alert @tone='danger' @title='Not withdrawn'>{{this.error}}</Alert>
        {{/if}}
        {{#if this.notice}}<Alert @tone='success'>{{this.notice}}</Alert>{{/if}}

        <Section @title='Enrollment'><KvList
            @items={{seatItems @model}}
          /></Section>
        <Section @title='Progress'>
          <div class='pad'><LearnerProgress
              @enrollment={{@model}}
              @context={{@context}}
              @compact={{true}}
            /></div>
        </Section>
        {{#if @context.getCards}}
          <Section @title='Work'>
            <div class='pad'><LearnerActions
                @enrollment={{@model}}
                @context={{@context}}
              /></div>
          </Section>
        {{/if}}
      </:main>
      <:side>
        <Section @title='Linked'>
          <Kv @label='Learner'>{{#if @model.learner}}<@fields.learner
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
          <Kv @label='Cohort'>{{#if @model.cohort}}<@fields.cohort
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
          {{#if @model.certificate}}
            <Kv @label='Certificate'><@fields.certificate
                @format='atom'
                @displayContainer={{false}}
              /></Kv>
          {{/if}}
        </Section>
        <Section @title='Details'><KvList @items={{this.details}} /></Section>
      </:side></Sheet>
    <style scoped>
      .pad {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-top: 1px solid var(--border);
      }
    </style>
  </template>
}

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

  static isolated = EnrollmentIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <Embed @mark='En' @title={{@model.cardTitle}} @meta={{metaLine @model}}>
        <:status><Dot
            @hue={{hueOf @model}}
          >{{@model.statusLabel}}</Dot></:status>
        <:fact>{{factLine @model}}</:fact>
        <:default>
          <KvList @items={{seatItems @model}} />
          <Kv @label='Learner'>{{#if @model.learner}}<@fields.learner
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
          <Kv @label='Cohort'>{{#if @model.cohort}}<@fields.cohort
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
        </:default>
      </Embed>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <AtomChip @mark='En' @title={{@model.cardTitle}}><Dot
          @hue={{hueOf @model}}
        >{{@model.statusLabel}}</Dot></AtomChip>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FitTile>
        <:avatar><Mark @text='En' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><Dot
            @hue={{hueOf @model}}
          >{{@model.statusLabel}}</Dot></:status>
        <:fact>{{factLine @model}}</:fact>
        <:relations>{{#if @model.learner}}<@fields.learner
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}{{#if @model.cohort}}<@fields.cohort
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
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
