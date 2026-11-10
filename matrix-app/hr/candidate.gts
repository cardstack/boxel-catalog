import { markDefinition } from '@cardstack/base/mark-definition';
import { realmURL } from 'https://cardstack.com/base/card-api';
import { codeRef } from '@cardstack/runtime-common';
import type { Meeting } from './meeting';
import { RejectCandidateCommand } from './commands/reject-candidate-command';
import { ScheduleInterviewCommand } from './commands/schedule-interview-command';
import { RejectCandidateDialog } from './components/reject-candidate-dialog';
import { ScheduleInterviewDialog } from './components/schedule-interview-dialog';
import {
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import NumberField from 'https://cardstack.com/base/number';
import TextAreaField from 'https://cardstack.com/base/text-area';
import UrlField from 'https://cardstack.com/base/url';
import { dotEnumField } from './dot-enum-field';
import { FileDef } from 'https://cardstack.com/base/file-api';
import UserSearchIcon from '@cardstack/boxel-icons/user-search';
import { guidFor } from '@ember/object/internals';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { type DescriptionsItem } from '@cardstack/pretui/components/descriptions';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';

import { PersonBase } from '../people/person-base';
import ScoreField from '@cardstack/catalog/fields/rating/rating';
import { DurationField } from './duration-field';
import { Employee } from './employee';
import { Position } from './position';
import { Offer } from './offer';
import { Skill } from './skill';
import {
  BackgroundCheckField,
  BACKGROUND_CHECK_STATUS_LABELS,
} from './background-check-field';
import { InterviewFeedbackField } from './interview-feedback-field';
import { RejectionReasonField } from './rejection-reason-field';
import { WorkHistoryEntryField } from './work-history-entry-field';
import { EducationEntryField } from './education-entry-field';
import { INTERVIEW_ROUND_OPTIONS } from './interview-round-field';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { daysBetween, liveCount } from './utils';
import {
  ALERT_STYLE,
  AVATAR_HUE,
} from '@cardstack/catalog/components/pretui-helpers';
import { ExtractResumeCommand } from './commands/extract-resume-command';
import { GenerateInterviewQuestionsCommand } from './commands/generate-interview-questions-command';
import FileDownloadLink from './components/file-download-link';
import {
  EmbCard,
  FitCard,
  FitRow,
  IsoHead,
  IsoPage,
  Kv,
  kv,
  Panel,
  SheetEmpty,
  SheetLine,
  StatStrip,
  type StripItem,
} from './compact-sheet';

export const CANDIDATE_STAGES = [
  'applied',
  'screening',
  'interviewing',
  'offer',
  'hired',
  'rejected',
];

// Colocated with Candidate — the hue map colours the stage pill, and
// `CANDIDATE_STAGE_COLORS` below gives the avatar's stage ring the same hue in
// the isolated and fitted views. A stage is a status, so it reads the status hues: green is active work
// (screening, interviewing) and the hire the pipeline resolves into, the same
// green as Employee's "active"; offer is orange, the seal going out; rejected
// is red.
export const CANDIDATE_STAGE_HUES: Record<string, Hue> = {
  applied: 'amber',
  screening: 'green',
  interviewing: 'green',
  offer: 'orange',
  hired: 'green',
  rejected: 'red',
};

export const CANDIDATE_STAGE_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(CANDIDATE_STAGE_HUES).map(([k, hue]) => [
      k,
      stateColor(hue),
    ]),
  );

export const CandidateStatusField = markDefinition(
  dotEnumField(
    {
      options: CANDIDATE_STAGES.map((stage) => ({
        value: stage,
        label: stage,
      })),
      displayName: 'Candidate Stage',
    },
    CANDIDATE_STAGE_HUES,
  ),
);

// The stage chip's tone, on the theme's tone axis: a candidate still in
// the funnel is info, an offer out is warning, a hire is success and a
// rejection is danger.
export const CANDIDATE_STAGE_TONES: Record<string, PretuiToneArg> = {
  applied: 'info',
  screening: 'info',
  interviewing: 'info',
  offer: 'warning',
  hired: 'success',
  rejected: 'danger',
};

function scoreLabel(m?: Partial<Candidate>): string {
  let v = m?.overallScore;
  return typeof v === 'number' && v > 0 ? `${v} / 5` : '';
}

function shortDay(d?: Date | string | null): string | undefined {
  if (!d) {
    return undefined;
  }
  let t = new Date(d);
  return isNaN(t.getTime())
    ? undefined
    : t.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function subLine(m?: Partial<Candidate>): string {
  let role = m?.appliedRole || 'Role not recorded';
  let applied = shortDay(m?.appliedDate);
  return applied ? `${role} · applied ${applied}` : role;
}

function noticeLabel(m?: Partial<Candidate>): string {
  let n = m?.noticePeriodDays;
  return n == null ? '' : `${n} days`;
}

// How many of the linked position's required skills this candidate's skills
// cover, by card id; undefined when the position lists none.
function skillMatch(
  m?: Partial<Candidate>,
): { matched: number; required: number } | undefined {
  let required = (m?.position?.requiredSkills ?? []).filter(Boolean);
  if (!required.length) {
    return undefined;
  }
  let ids = new Set(required.map((skill) => skill.id));
  let matched = (m?.skills ?? [])
    .filter(Boolean)
    .filter((skill) => ids.has(skill.id)).length;
  return { matched, required: ids.size };
}

function skillMatchLabel(m?: Partial<Candidate>): string | undefined {
  let match = skillMatch(m);
  return match ? `${match.matched} of ${match.required} required` : undefined;
}

function backgroundLabel(m?: Partial<Candidate>): string | undefined {
  let check = m?.backgroundCheck;
  let status = check?.status
    ? (BACKGROUND_CHECK_STATUS_LABELS[check.status] ?? check.status)
    : undefined;
  let parts = [check?.provider, status?.toLowerCase()].filter(Boolean);
  return parts.length ? parts.join(' · ') : undefined;
}

// The facts every format draws from, in the mockup's order; isolated shows
// them all, embedded the first six.
function candidateFacts(m?: Partial<Candidate>): DescriptionsItem[] {
  return [
    {
      label: 'Applied',
      value: m?.appliedDate ? formatDay(m.appliedDate) : '—',
    },
    { label: 'Score', value: scoreLabel(m) || '—' },
    { label: 'Notice', value: noticeLabel(m) || '—' },
    { label: 'Background', value: backgroundLabel(m) ?? '—' },
    { label: 'Skill match', value: skillMatchLabel(m) ?? '—' },
    { label: 'Email', value: m?.email || '—' },
    { label: 'Phone', value: m?.phone || '—' },
    { label: 'Portfolio', value: m?.portfolioUrl || '—' },
  ];
}

function capitalize(s?: string | null): string {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : '—';
}

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
// Type refs for the schedule dialog's queries; runtime refs, not imports,
// because meeting.gts imports candidate.gts.
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const candidateHere: string = import.meta.url;
const employeeCodeRef = codeRef(candidateHere, './employee', 'Employee');
const meetingCodeRef = codeRef(candidateHere, './meeting', 'Meeting');

class CandidateIsolated extends Component<typeof Candidate> {
  // the dialog reads a whole Candidate; the template model types every field as optional
  get candidate(): Candidate {
    return this.args.model as Candidate;
  }

  // Header actions: the mock's Schedule interview / Reject, through the same
  // dialogs and commands the tracker's pipeline uses.
  @tracked rejectOpen = false;
  @tracked scheduleOpen = false;
  @tracked actionBusy = false;
  @tracked actionError: string | undefined;

  get canAct(): boolean {
    let status = this.args.model?.status;
    return status !== 'hired' && status !== 'rejected';
  }

  get realmHrefs(): string[] {
    let url = this.args.model?.[realmURL]?.href;
    return url ? [url] : [];
  }

  employeesQuery = this.args.context?.getCards(
    this,
    () =>
      this.scheduleOpen ? { filter: { type: employeeCodeRef } } : undefined,
    () => this.realmHrefs,
    { isLive: true },
  );
  meetingsQuery = this.args.context?.getCards(
    this,
    () =>
      this.scheduleOpen ? { filter: { type: meetingCodeRef } } : undefined,
    () => this.realmHrefs,
    { isLive: true },
  );
  get employees(): Employee[] {
    return (this.employeesQuery?.instances ?? []) as Employee[];
  }
  get meetings(): Meeting[] {
    return (this.meetingsQuery?.instances ?? []) as Meeting[];
  }

  openReject = () => (this.rejectOpen = true);
  closeReject = () => (this.rejectOpen = false);
  openSchedule = () => (this.scheduleOpen = true);
  closeSchedule = () => {
    this.scheduleOpen = false;
    this.actionError = undefined;
  };

  confirmReject = async (reason: string, note: string) => {
    this.rejectOpen = false;
    await this.runAction((ctx) =>
      new RejectCandidateCommand(ctx).execute({
        candidate: this.args.model,
        reason,
        note,
      } as any),
    );
  };

  confirmSchedule = async (opts: {
    date: Date;
    interviewers: Employee[];
    roundType: string;
    ignoreConflicts: boolean;
  }) => {
    let ok = await this.runAction((ctx) =>
      new ScheduleInterviewCommand(ctx).execute({
        candidate: this.args.model,
        ...opts,
      } as any),
    );
    if (ok) {
      this.scheduleOpen = false;
    }
  };

  private async runAction(
    run: (ctx: any) => Promise<unknown>,
  ): Promise<boolean> {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      this.actionError = 'Commands are unavailable in this mode';
      return false;
    }
    this.actionBusy = true;
    this.actionError = undefined;
    try {
      await run(ctx);
      return true;
    } catch (e: any) {
      this.actionError = e?.message ?? String(e);
      return false;
    } finally {
      this.actionBusy = false;
    }
  }

  @tracked busyTool: 'extract' | 'questions' | undefined;
  @tracked toolError: string | undefined;
  @tracked toolMessage: string | undefined;
  @tracked selectedRoundType: string | undefined = 'technical';

  // A segmented control, not a <select>: all five rounds stay visible. This
  // is a MODE (which round the next generation call targets), not a one-shot
  // action, so it is a single-choice radio group rather than a disabled
  // state.
  roundTypeOptions = INTERVIEW_ROUND_OPTIONS;

  setRoundType = (value: string) => {
    this.selectedRoundType = value;
  };

  roundLabelId = `round-label-${guidFor(this)}`;

  get extractDisabled(): boolean {
    return Boolean(this.busyTool) || !this.args.model?.resumeText?.trim();
  }

  get generateDisabled(): boolean {
    return Boolean(this.busyTool);
  }

  get appliedHint(): string | undefined {
    let d = this.args.model?.appliedDate;
    return d ? `applied ${formatDay(d)}` : undefined;
  }

  get scoredHint(): string | undefined {
    let n = (this.args.model?.interviewFeedback ?? []).filter(
      (fb) => fb?.rating,
    ).length;
    return n ? `${n} interview${n === 1 ? '' : 's'} scored` : undefined;
  }

  get matchPct(): string {
    let v = this.args.model?.skillMatchPct;
    return v == null ? '—' : `${v}%`;
  }

  get matchHint(): string | undefined {
    let match = skillMatch(this.args.model);
    return match
      ? `${match.matched} of ${match.required} required skills`
      : undefined;
  }

  get feedbackRows(): DescriptionsItem[] {
    return (this.args.model?.interviewFeedback ?? []).map((fb) => ({
      label: fb?.interviewer?.name || 'Unnamed',
      value: [
        fb?.interviewDate ? formatDay(fb.interviewDate) : undefined,
        fb?.rating ? `rating ${fb.rating} / 5` : undefined,
        fb?.notes,
      ]
        .filter(Boolean)
        .join(' · '),
    }));
  }

  get checkFacts(): DescriptionsItem[] {
    let check = this.args.model?.backgroundCheck;
    return [
      { label: 'Provider', value: check?.provider || '—' },
      {
        label: 'Requested',
        value: check?.requestedDate ? formatDay(check.requestedDate) : '—',
      },
      {
        label: 'Completed',
        value: check?.completedDate ? formatDay(check.completedDate) : '—',
      },
      {
        label: 'Status',
        value: check?.status
          ? (BACKGROUND_CHECK_STATUS_LABELS[check.status] ?? check.status)
          : '—',
      },
    ];
  }

  get linkFacts(): DescriptionsItem[] {
    let m = this.args.model;
    return [
      { label: 'LinkedIn', value: m?.linkedInUrl || '—' },
      { label: 'Portfolio', value: m?.portfolioUrl || '—' },
      { label: 'Email', value: m?.email || '—' },
      { label: 'Phone', value: m?.phone || '—' },
    ];
  }

  linkedFacts: DescriptionsItem[] = [
    { label: 'Position' },
    { label: 'Referred by' },
    { label: 'Offer' },
    { label: 'Hired as' },
  ];

  get detailFacts(): DescriptionsItem[] {
    return candidateFacts(this.args.model);
  }

  extractResume = async () => {
    if (this.extractDisabled) {
      return;
    }
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.toolError = 'Commands are unavailable in this mode';
      return;
    }
    this.toolError = undefined;
    this.toolMessage = undefined;
    this.busyTool = 'extract';
    try {
      let result = await new ExtractResumeCommand(commandContext).execute({
        candidate: this.args.model,
      } as any);
      this.toolMessage = (result as any)?.summary;
    } catch (error: any) {
      this.toolError = error?.message ?? String(error);
    } finally {
      this.busyTool = undefined;
    }
  };

  generateQuestions = async () => {
    if (this.generateDisabled) {
      return;
    }
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.toolError = 'Commands are unavailable in this mode';
      return;
    }
    this.toolError = undefined;
    this.toolMessage = undefined;
    this.busyTool = 'questions';
    try {
      await new GenerateInterviewQuestionsCommand(commandContext).execute({
        candidate: this.args.model,
        roundType: this.selectedRoundType,
      } as any);
      this.toolMessage = 'Interview questions generated below.';
    } catch (error: any) {
      this.toolError = error?.message ?? String(error);
    } finally {
      this.busyTool = undefined;
    }
  };

  get strip(): StripItem[] {
    let m = this.args.model;
    return [
      {
        label: 'Stage',
        value: capitalize(m?.status),
        hint: this.appliedHint,
        tone: 'info',
      },
      {
        label: 'Overall score',
        value: scoreLabel(m) || '—',
        hint: this.scoredHint,
        tone: 'success',
      },
      {
        label: 'Notice period',
        value: noticeLabel(m) || '—',
        tone: 'neutral',
      },
      {
        label: 'Skill match',
        value: this.matchPct,
        hint: this.matchHint,
        tone: 'success',
      },
    ];
  }

  get skillLine(): string {
    return (this.args.model?.skills ?? [])
      .filter(Boolean)
      .map((s) => s.title)
      .join(' · ');
  }

  <template>
    <IsoPage>
      <:head>
        <IsoHead @title={{@model.title}} @meta={{subLine @model}}>
          <:mark><Avatar
              @name={{if @model.title @model.title '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{36}}
              aria-hidden='true'
            /></:mark>
          <:aside>{{#if @model.status}}<@fields.status
                @format='atom'
                @displayContainer={{false}}
              />{{/if}}</:aside>
          <:actions as |bar|>{{#if this.canAct}}
              <bar.Action
                @id='schedule'
                @label='Schedule interview'
                @primary={{true}}
                @loading={{this.actionBusy}}
                @onClick={{this.openSchedule}}
              />
              <bar.Action
                @id='reject'
                @label='Reject'
                @onClick={{this.openReject}}
              />
            {{/if}}</:actions>
          <:stats><StatStrip @items={{this.strip}} /></:stats>
        </IsoHead>
        {{#if this.actionError}}{{#unless this.scheduleOpen}}<Alert
              @tone='danger'
              style={{ALERT_STYLE.danger}}
            >{{this.actionError}}</Alert>{{/unless}}{{/if}}
        <RejectCandidateDialog
          @isOpen={{this.rejectOpen}}
          @candidateName={{@model.title}}
          @onConfirm={{this.confirmReject}}
          @onCancel={{this.closeReject}}
        />
        {{#if this.scheduleOpen}}
          <ScheduleInterviewDialog
            @candidate={{this.candidate}}
            @employees={{this.employees}}
            @meetings={{this.meetings}}
            @isRunning={{this.actionBusy}}
            @error={{this.actionError}}
            @onConfirm={{this.confirmSchedule}}
            @onCancel={{this.closeSchedule}}
          />
        {{/if}}
      </:head>
      <:main>
        <Panel @title='Skills'>
          <SheetLine>{{#if this.skillLine}}{{this.skillLine}}{{else}}<span
                class='note'
              >No skills recorded. Extract resume matches them against the skill
                library.</span>{{/if}}</SheetLine>
        </Panel>
        {{#if @model.interviewFeedback.length}}
          <Panel @title='Interview feedback'>
            {{#each @model.interviewFeedback as |fb|}}
              <SheetLine>
                <span class='fb'>
                  <span class='mono'>{{if
                      fb.interviewDate
                      (formatDay fb.interviewDate)
                    }}{{#if fb.rating}}
                      · rating
                      {{fb.rating}}
                      / 5{{/if}}{{#if fb.interviewer.name}}
                      ·
                      {{fb.interviewer.name}}{{/if}}</span>
                  {{#if fb.notes}}<span class='note'>{{fb.notes}}</span>{{/if}}
                </span>
                {{#if fb.rating}}<span class='mono'>{{fb.rating}}
                    / 5</span>{{/if}}
              </SheetLine>
            {{/each}}
          </Panel>
        {{/if}}
        <Panel @title='Background check'><Kv
            @items={{kv this.checkFacts}}
          /></Panel>
        <Panel @title='Links'><Kv @items={{kv this.linkFacts}} /></Panel>
        <Panel @title='Work history'>
          {{#if @model.workHistory.length}}
            <ul class='entry-list'><@fields.workHistory /></ul>
          {{else}}
            <SheetEmpty
              @title='No work history recorded'
              @message='Extract resume populates it from the resume text.'
            />
          {{/if}}
        </Panel>
        <Panel @title='Education'>
          {{#if @model.education.length}}
            <ul class='entry-list'><@fields.education /></ul>
          {{else}}
            <SheetEmpty
              @title='No education recorded'
              @message='Extract resume populates it from the resume text.'
            />
          {{/if}}
        </Panel>
        <Panel @title='Interview plan'>
          {{#if @model.position.interviewPlan}}
            <@fields.position.interviewPlan @format='embedded' />
          {{else}}
            <SheetEmpty
              @title='No interview plan yet'
              @message='Generate questions to create one.'
            />
          {{/if}}
        </Panel>
        <Panel @title='Resume'>
          <div class='stack'>
            {{#if @model.resumeFile}}
              <FileDownloadLink @file={{@model.resumeFile}} />
            {{/if}}
            {{#if @model.resumeText}}
              <p class='prose'>{{@model.resumeText}}</p>
            {{else}}
              <p class='note'>No resume text on file. Paste it into Resume Text
                to enable Extract resume and Generate questions.</p>
            {{/if}}
          </div>
        </Panel>
      </:main>
      <:aside>
        <Panel @title='Linked'>
          <Kv @items={{kv this.linkedFacts}}>
            <:value as |item|>
              {{#if (eq item.key 'Position')}}
                {{#if @model.position}}<@fields.position
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}
              {{else if (eq item.key 'Referred by')}}
                {{#if @model.referredBy}}<@fields.referredBy
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}
              {{else if (eq item.key 'Offer')}}
                {{#if @model.offer}}<@fields.offer
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}— not extended{{/if}}
              {{else if (eq item.key 'Hired as')}}
                {{#if @model.hiredAs}}<@fields.hiredAs
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}
              {{/if}}
            </:value>
          </Kv>
        </Panel>
        {{#if @model.rejectionReason}}
          <Panel @title='Rejection reason'>
            <SheetLine><@fields.rejectionReason
                @format='atom'
                @displayContainer={{false}}
              />{{#if @model.rejectionNote}}
                —
                {{@model.rejectionNote}}{{/if}}</SheetLine>
          </Panel>
        {{/if}}
        <Panel @title='Details'><Kv @items={{kv this.detailFacts}} /></Panel>
        <Panel @title='Tools'>
          <div class='stack'>
            {{#if @model.resumeText}}
              <Button
                @tone='primary'
                @appearance='link'
                @size='xs'
                @disabled={{this.extractDisabled}}
                @busy={{eq this.busyTool 'extract'}}
                {{on 'click' this.extractResume}}
              >Extract resume</Button>
            {{/if}}
            <p class='note' id={{this.roundLabelId}}>Round to generate questions
              for</p>
            <SegmentedControl
              class='round-toggle'
              @options={{this.roundTypeOptions}}
              @value={{this.selectedRoundType}}
              @onValueChange={{this.setRoundType}}
              aria-labelledby={{this.roundLabelId}}
            />
            <Button
              @tone='primary'
              @appearance='accent'
              @size='xs'
              @disabled={{this.generateDisabled}}
              @busy={{eq this.busyTool 'questions'}}
              {{on 'click' this.generateQuestions}}
            >Generate questions</Button>
            {{#if this.toolMessage}}
              <Alert
                @tone='success'
                style={{ALERT_STYLE.success}}
              >{{this.toolMessage}}</Alert>
            {{/if}}
            {{#if this.toolError}}
              <Alert
                @tone='danger'
                style={{ALERT_STYLE.danger}}
              >{{this.toolError}}</Alert>
            {{/if}}
          </div>
        </Panel>
      </:aside>
    </IsoPage>
    <style scoped>
      .fb {
        display: grid;
        flex: 1 1 12rem;
        min-width: 0;
      }
      .mono {
        font: 500 0.6875rem var(--font-mono);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .note {
        margin: 0;
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .entry-list {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .stack {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: 0.5rem;
        padding: 0.4375rem 0.625rem;
        border-top: 1px solid var(--border);
        min-width: 0;
      }
      .prose {
        margin: 0;
        max-width: 56ch;
        max-height: 16rem;
        overflow-y: auto;
        white-space: pre-line;
      }
      .round-toggle {
        display: flex;
        flex-wrap: wrap;
      }
    </style>
  </template>
}

export class Candidate extends PersonBase {
  static displayName = 'Candidate';
  static icon = UserSearchIcon;

  @field appliedRole = contains(StringField);
  @field position = linksTo(() => Position);
  @field offer = linksTo(() => Offer);
  @field appliedDate = contains(DateField);
  @field decisionDate = contains(DateField);
  @field status = contains(CandidateStatusField);
  @field resumeText = contains(TextAreaField, {
    description: 'Raw resume text; parsed by the Extract Resume command',
  });
  @field resumeFile = linksTo(FileDef, {
    searchable: true,
    description: 'The original resume file (PDF, etc.) for HR review',
  });
  @field linkedInUrl = contains(UrlField);
  @field portfolioUrl = contains(UrlField);
  @field referredBy = linksTo(() => Employee, {
    description: 'Employee who referred this candidate, if any',
  });
  @field noticePeriodDays = contains(NumberField, {
    description: 'Days of notice the candidate needs before starting',
  });
  @field interviewFeedback = containsMany(InterviewFeedbackField);
  @field skills = linksToMany(() => Skill);
  @field workHistory = containsMany(WorkHistoryEntryField);
  @field education = containsMany(EducationEntryField);
  @field overallScore = contains(ScoreField);
  // Status-tracking only — recording what the screening vendor reported, not
  // running the check. See background-check-field.gts for the boundary.
  @field backgroundCheck = contains(BackgroundCheckField);
  @field rejectionReason = contains(RejectionReasonField);
  // Free-text detail alongside the categorical reason — the reason drives
  // the Offers dashboard breakdown, this is the human-readable "what
  // happened" a recruiter can read back later.
  @field rejectionNote = contains(StringField);

  // Scalar mirror of the linked Offer's lifecycle, written by the offer
  // commands. The Pipeline board needs to tell "drafted but not sent" from
  // "sent, awaiting reply" on every render; reading the `offer` linksTo
  // synchronously in that hot path races the async link load and trips
  // Ember's "updated after use" assertion, which is why this scalar exists.
  @field offerState = contains(StringField, {
    description:
      "One of draft | extended | accepted | declined — mirrors the linked Offer's status for cheap board-side checks",
  });
  @field hiredAs = linksTo(() => Employee);
  @field boardOrder = contains(NumberField, {
    description:
      'Position within this candidate’s Kanban column; 1-based, lower sorts first',
  });

  // Denormalized for fitted — prerendered fitted does not resolve
  // linksToMany, so the fitted view reads this instead of skills.length.
  @field skillTally = contains(StringField, {
    computeVia: function (this: Candidate) {
      let n = liveCount(this.skills);
      return n === 0 ? '' : String(n);
    },
  });

  @field timeToHire = contains(DurationField, {
    computeVia: function (this: Candidate) {
      let days = daysBetween(this.appliedDate, this.decisionDate);
      if (days == null) {
        return undefined;
      }
      return new DurationField({ value: days, unit: 'days' });
    },
  });

  // What share of the linked Position's required skills this candidate's
  // linked skills cover, by card id. `undefined` (not 0%) when the position
  // isn't linked or lists no required skills — a missing denominator is not
  // the same fact as "matches nothing".
  @field skillMatchPct = contains(NumberField, {
    computeVia: function (this: Candidate) {
      let required = (this.position?.requiredSkills ?? []).filter(Boolean);
      if (required.length === 0) {
        return undefined;
      }
      let requiredIds = new Set(required.map((skill) => skill.id));
      let matchedSkillCount = (this.skills ?? [])
        .filter(Boolean)
        .filter((skill) => requiredIds.has(skill.id)).length;
      return Math.round(
        (matchedSkillCount / Math.max(1, requiredIds.size)) * 100,
      );
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Candidate) {
      return this.name?.trim() || 'Unnamed Candidate';
    },
  });

  static isolated = CandidateIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get rows() {
      return [
        ...kv(candidateFacts(this.args.model).slice(0, 6)),
        { key: 'Position', value: '' },
        { key: 'Referred by', value: '' },
      ];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{subLine @model}}>
        <:mark><Avatar
            @name={{if @model.title @model.title '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:aside>
        <:default>
          <Kv @items={{this.rows}}>
            <:value as |item|>
              {{#if (eq item.key 'Position')}}
                {{#if @model.position}}<@fields.position
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}
              {{else if (eq item.key 'Referred by')}}
                {{#if @model.referredBy}}<@fields.referredBy
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}
              {{else}}{{item.value}}{{/if}}
            </:value>
          </Kv>
        </:default>
      </EmbCard>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='candidate-atom'>
        <Avatar
          @name={{if @model.title @model.title '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          aria-hidden='true'
        />
        <span class='name'>{{@model.title}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .candidate-atom {
            /* same avatar and text size as the Employee atom beside it */
            --pretui-avatar-size: 1.25rem;
            display: inline-flex;
            align-items: center;
            gap: 0.375rem;
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.375rem;
            row-gap: 1.375rem;
            overflow: hidden;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.375rem;
            white-space: nowrap;
            color: var(--foreground);
          }
          /* the name gives way first; the stage chip is never cut */
          .name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .stage {
            flex: none;
            display: inline-flex;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get strip(): StripItem[] {
      let m = this.args.model;
      let pct = m?.skillMatchPct;
      return [
        { label: 'Score', value: scoreLabel(m) || '—' },
        {
          label: 'Notice',
          value: m?.noticePeriodDays == null ? '—' : `${m.noticePeriodDays} d`,
        },
        { label: 'Match', value: pct == null ? '—' : `${pct}%` },
      ];
    }
    <template>
      <FitCard @title={{@model.title}}>
        <:mark><Avatar
            @name={{if @model.title @model.title '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{20}}
            aria-hidden='true'
          /></:mark>
        <:status>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:status>
        <:default>
          <FitRow @left={{true}}><span class='meta'>{{subLine
                @model
              }}</span></FitRow>
          <FitRow @label='Score'><span class='mono'>{{if
                (scoreLabel @model)
                (scoreLabel @model)
                '—'
              }}</span></FitRow>
          <FitRow @label='Applied'><span class='mono'>{{if
                @model.appliedDate
                (formatDay @model.appliedDate)
                '—'
              }}</span></FitRow>
          {{#if @model.position}}
            <FitRow @label='Position' @left={{true}}><@fields.position
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/if}}
          <StatStrip @compact={{true}} @items={{this.strip}} />
          <FitRow @label='Notice'><span class='mono'>{{if
                (noticeLabel @model)
                (noticeLabel @model)
                '—'
              }}</span></FitRow>
          <FitRow @label='Skill match'>{{if
              (skillMatchLabel @model)
              (skillMatchLabel @model)
              '—'
            }}</FitRow>
          <FitRow @label='Background'>{{if
              (backgroundLabel @model)
              (backgroundLabel @model)
              '—'
            }}</FitRow>
          {{#if @model.referredBy}}
            <FitRow @label='Referred by' @left={{true}}><@fields.referredBy
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/if}}
          <FitRow @label='Email'><span
              class='mono'
            >{{@model.email}}</span></FitRow>
        </:default>
      </FitCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .mono {
          overflow: hidden;
          text-overflow: ellipsis;
          font: 500 0.6875rem var(--font-mono);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
