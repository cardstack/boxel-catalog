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
import enumField from 'https://cardstack.com/base/enum';
import { FileDef } from 'https://cardstack.com/base/file-api';
import UserSearchIcon from '@cardstack/boxel-icons/user-search';
import { guidFor } from '@ember/object/internals';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '../../ui-component/components/alert';
import { Avatar } from '../../ui-component/components/avatar';
import { Button } from '../../ui-component/components/button';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { EmptyState } from '../../ui-component/components/empty-state';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Panel } from '../../ui-component/components/panel';
import { SegmentedControl } from '../../ui-component/components/segmented-control';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';

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

export const CandidateStatusField = enumField(StringField, {
  options: CANDIDATE_STAGES.map((stage) => ({ value: stage, label: stage })),
  displayName: 'Candidate Stage',
});

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

const CHECK_TONES: Record<string, PretuiToneArg> = {
  'not-started': 'neutral',
  pending: 'warning',
  clear: 'success',
  flagged: 'danger',
};

function stageTone(status?: string | null): PretuiToneArg {
  return (status && CANDIDATE_STAGE_TONES[status]) || 'neutral';
}

function checkTone(status?: string | null): PretuiToneArg {
  return (status && CHECK_TONES[status]) || 'neutral';
}

// '' when absent: a template `#if` reads it as false and glint keeps a string
function checkChip(m?: Partial<Candidate>): string {
  let status = m?.backgroundCheck?.status;
  return status && status !== 'not-started'
    ? `check ${(BACKGROUND_CHECK_STATUS_LABELS[status] ?? status).toLowerCase()}`
    : '';
}

function scoreLabel(m?: Partial<Candidate>): string {
  let v = m?.overallScore;
  return typeof v === 'number' && v > 0 ? `${v} / 5` : '';
}

function scoreChip(m?: Partial<Candidate>): string {
  let label = scoreLabel(m);
  return label ? `score ${label}` : '';
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

function daysInPipeline(m?: Partial<Candidate>): string | undefined {
  if (m?.status === 'hired' || m?.status === 'rejected') {
    return undefined;
  }
  let d = daysBetween(m?.appliedDate);
  return d == null ? undefined : `${d} days`;
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
class CandidateIsolated extends Component<typeof Candidate> {
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

  <template>
    <article class='candidate-isolated'>
      <header class='iso-head'>
        <Avatar
          @name={{if @model.title @model.title '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          @size={{48}}
          aria-hidden='true'
        />
        <div class='iso-id'>
          <h1>{{@model.title}}</h1>
          <p class='iso-sub'>{{subLine @model}}</p>
        </div>
        <div class='chips'>
          {{#if @model.status}}
            <StatusChip
              @value={{@model.status}}
              @tone={{stageTone @model.status}}
            />
          {{/if}}
          {{#if (scoreChip @model)}}
            <StatusChip @value={{scoreChip @model}} @tone='success' />
          {{/if}}
          {{#if (checkChip @model)}}
            <StatusChip
              @value={{checkChip @model}}
              @tone={{checkTone @model.backgroundCheck.status}}
            />
          {{/if}}
        </div>
      </header>

      <div class='stat-row'>
        <div class='stat-tile'><Stat
            @label='Stage'
            @value={{capitalize @model.status}}
            @hint={{this.appliedHint}}
            @roll={{false}}
          /></div>
        <div class='stat-tile'><Stat
            @label='Overall score'
            @value={{if (scoreLabel @model) (scoreLabel @model) '—'}}
            @hint={{this.scoredHint}}
            @roll={{false}}
          /></div>
        <div class='stat-tile'><Stat
            @label='Notice period'
            @value={{if (noticeLabel @model) (noticeLabel @model) '—'}}
            @roll={{false}}
          /></div>
        <div class='stat-tile'><Stat
            @label='Skill match'
            @value={{this.matchPct}}
            @hint={{this.matchHint}}
            @roll={{false}}
          /></div>
      </div>

      <div class='iso-body'>
        <div class='iso-col'>
          <Panel>
            <:header><h2 class='panel-h'>Skills</h2></:header>
            <:default>
              {{#if @model.skills.length}}
                <ul class='tag-row'>
                  {{#each @model.skills as |skill|}}
                    {{#if skill}}
                      <li><StatusChip
                          @value={{skill.title}}
                          @tone='neutral'
                        /></li>
                    {{/if}}
                  {{/each}}
                </ul>
              {{else}}
                <EmptyState
                  @texture={{false}}
                  @title='No skills recorded'
                  @message='Running Extract Resume will match them against the skill library.'
                />
              {{/if}}
            </:default>
          </Panel>

          {{#if @model.interviewFeedback.length}}
            <Panel>
              <:header><h2 class='panel-h'>Interview feedback</h2></:header>
              <:default>
                <Descriptions
                  @items={{this.feedbackRows}}
                  @columns={{1}}
                  @size='xl'
                >
                  <:value as |item|><span>{{item.value}}</span></:value>
                </Descriptions>
              </:default>
            </Panel>
          {{/if}}

          <Panel>
            <:header><h2 class='panel-h'>Background check</h2></:header>
            <:default>
              <Descriptions
                @items={{this.checkFacts}}
                @columns={{1}}
                @size='xl'
              >
                <:value as |item|><span class='v'>{{item.value}}</span></:value>
              </Descriptions>
            </:default>
          </Panel>

          <Panel>
            <:header><h2 class='panel-h'>Links</h2></:header>
            <:default>
              <Descriptions @items={{this.linkFacts}} @columns={{1}} @size='xl'>
                <:value as |item|><span class='v'>{{item.value}}</span></:value>
              </Descriptions>
            </:default>
          </Panel>

          <Panel>
            <:header><h2 class='panel-h'>Work history</h2></:header>
            <:default>
              {{#if @model.workHistory.length}}
                <ul class='entry-list'>
                  <@fields.workHistory />
                </ul>
              {{else}}
                <EmptyState
                  @texture={{false}}
                  @title='No work history recorded'
                  @message='Running Extract Resume will populate it from the resume text.'
                />
              {{/if}}
            </:default>
          </Panel>

          <Panel>
            <:header><h2 class='panel-h'>Education</h2></:header>
            <:default>
              {{#if @model.education.length}}
                <ul class='entry-list'>
                  <@fields.education />
                </ul>
              {{else}}
                <EmptyState
                  @texture={{false}}
                  @title='No education recorded'
                  @message='Running Extract Resume will populate it from the resume text.'
                />
              {{/if}}
            </:default>
          </Panel>

          <Panel>
            <:header><h2 class='panel-h'>Interview plan</h2></:header>
            <:default>
              {{#if @model.position.interviewPlan}}
                <@fields.position.interviewPlan @format='embedded' />
              {{else}}
                <EmptyState
                  @texture={{false}}
                  @title='No interview plan yet'
                  @message='Generate questions to create one.'
                />
              {{/if}}
            </:default>
          </Panel>

          <Panel>
            <:header><h2 class='panel-h'>Resume</h2></:header>
            <:default>
              {{! Two surfaces, two jobs: the PDF is what a human reads, the
                  text is what the AI commands parse. }}
              <div class='stack'>
                {{#if @model.resumeFile}}
                  <FileDownloadLink @file={{@model.resumeFile}} />
                {{else}}
                  <EmptyState
                    @texture={{false}}
                    @title='No resume file attached'
                  />
                {{/if}}
                {{#if @model.resumeText}}
                  <p class='prose'>{{@model.resumeText}}</p>
                {{else}}
                  <EmptyState
                    @texture={{false}}
                    @title='No resume text on file'
                    @message='Paste it into the Resume Text field to enable Extract resume and Generate questions — the AI commands read the text, not the PDF.'
                  />
                {{/if}}
              </div>
            </:default>
          </Panel>
        </div>

        <div class='iso-col'>
          <Panel>
            <:header><h2 class='panel-h'>Tools</h2></:header>
            <:default>
              <div class='stack'>
                {{#if @model.resumeText}}
                  <Button
                    @tone='primary'
                    @appearance='outlined'
                    @disabled={{this.extractDisabled}}
                    @busy={{eq this.busyTool 'extract'}}
                    {{on 'click' this.extractResume}}
                  >Extract resume</Button>
                {{/if}}
                <p class='note' id={{this.roundLabelId}}>Round to generate
                  questions for</p>
                <SegmentedControl
                  class='round-toggle'
                  @options={{this.roundTypeOptions}}
                  @value={{this.selectedRoundType}}
                  @onValueChange={{this.setRoundType}}
                  aria-labelledby={{this.roundLabelId}}
                />
                <Button
                  @tone='primary'
                  @appearance='outlined'
                  @disabled={{this.generateDisabled}}
                  @busy={{eq this.busyTool 'questions'}}
                  {{on 'click' this.generateQuestions}}
                >Generate questions</Button>
                {{#unless @model.resumeText}}
                  <p class='note'>Paste resume text before extracting.</p>
                {{/unless}}
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
            </:default>
          </Panel>

          <Panel>
            <:header><h2 class='panel-h'>Linked</h2></:header>
            <:default>
              <Descriptions
                @items={{this.linkedFacts}}
                @columns={{1}}
                @size='xl'
              >
                <:value as |item|>
                  {{#if (eq item.label 'Position')}}
                    {{#if @model.position}}<@fields.position
                        @format='atom'
                        @displayContainer={{false}}
                      />{{else}}—{{/if}}
                  {{else if (eq item.label 'Referred by')}}
                    {{#if @model.referredBy}}<@fields.referredBy
                        @format='atom'
                        @displayContainer={{false}}
                      />{{else}}—{{/if}}
                  {{else if (eq item.label 'Offer')}}
                    {{#if @model.offer}}<@fields.offer
                        @format='atom'
                        @displayContainer={{false}}
                      />{{else}}— not extended{{/if}}
                  {{else if (eq item.label 'Hired as')}}
                    {{#if @model.hiredAs}}<@fields.hiredAs
                        @format='atom'
                        @displayContainer={{false}}
                      />{{else}}—{{/if}}
                  {{/if}}
                </:value>
              </Descriptions>
            </:default>
          </Panel>

          {{#if @model.rejectionReason}}
            <Panel>
              <:header><h2 class='panel-h'>Rejection reason</h2></:header>
              <:default>
                <p class='note'>
                  <@fields.rejectionReason
                    @format='atom'
                    @displayContainer={{false}}
                  />
                  {{#if @model.rejectionNote}}
                    —
                    {{@model.rejectionNote}}
                  {{/if}}
                </p>
              </:default>
            </Panel>
          {{/if}}

          <Panel>
            <:header><h2 class='panel-h'>Details</h2></:header>
            <:default>
              <Descriptions
                @items={{this.detailFacts}}
                @columns={{1}}
                @size='xl'
              >
                <:value as |item|><span class='v'>{{item.value}}</span></:value>
              </Descriptions>
            </:default>
          </Panel>
        </div>
      </div>
    </article>
    <style scoped>
      @layer PretComponent {
        .candidate-isolated {
          container: candidate-iso / inline-size;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          box-sizing: border-box;
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-lg);
        }
        .iso-head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp);
        }
        .iso-id {
          flex: 1 1 12rem;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          line-height: 1.25;
          color: var(--primary-ink);
          overflow-wrap: anywhere;
        }
        .iso-sub {
          margin: var(--boxel-sp-6xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .chips,
        .tag-row {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .tag-row,
        .entry-list {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .stat-row {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
          gap: var(--boxel-sp);
        }
        .stat-tile {
          padding: var(--boxel-sp);
          border-radius: var(--boxel-border-radius);
          background-color: var(--card);
          color: var(--primary-ink);
          box-shadow: var(--shadow-md);
        }
        .iso-body {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
          align-items: start;
          gap: var(--boxel-sp-lg);
        }
        .iso-col,
        .stack {
          display: flex;
          flex-direction: column;
          min-width: 0;
        }
        .iso-col {
          gap: var(--boxel-sp-lg);
        }
        .stack {
          align-items: flex-start;
          gap: var(--boxel-sp-xs);
        }
        .panel-h {
          margin: 0;
          font-size: var(--boxel-font-size);
          font-weight: 600;
          line-height: 1.25;
        }
        .v {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          overflow-wrap: anywhere;
        }
        .note {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .prose {
          margin: 0;
          max-width: 56ch;
          max-height: 16rem;
          overflow-y: auto;
          font-size: var(--boxel-font-size-sm);
          white-space: pre-line;
        }
        /* five rounds do not fit one row of the side column, so it wraps */
        .round-toggle {
          display: flex;
          flex-wrap: wrap;
        }
        @container candidate-iso (width < 45rem) {
          .iso-body {
            grid-template-columns: minmax(0, 1fr);
          }
        }
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
    get facts(): DescriptionsItem[] {
      return candidateFacts(this.args.model).slice(0, 6);
    }
    <template>
      <div class='candidate-embedded'>
        <article class='emb'>
          <header class='emb-head'>
            <Avatar
              @name={{if @model.title @model.title '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{40}}
              aria-hidden='true'
            />
            <div class='emb-id'>
              <h3 class='emb-title'>{{@model.title}}</h3>
              <p class='emb-sub'>{{subLine @model}}</p>
            </div>
            <div class='chips'>
              {{#if @model.status}}
                <StatusChip
                  @value={{@model.status}}
                  @tone={{stageTone @model.status}}
                />
              {{/if}}
              {{#if (scoreChip @model)}}
                <StatusChip @value={{scoreChip @model}} @tone='success' />
              {{/if}}
              {{#if (checkChip @model)}}
                <StatusChip
                  @value={{checkChip @model}}
                  @tone={{checkTone @model.backgroundCheck.status}}
                />
              {{/if}}
            </div>
          </header>
          {{#if (daysInPipeline @model)}}
            <p class='emb-fact'><strong>{{daysInPipeline @model}}</strong>
              in pipeline{{#if (noticeLabel @model)}}
                · notice
                {{noticeLabel @model}}{{/if}}</p>
          {{/if}}
          <Descriptions
            class='emb-kv'
            @items={{this.facts}}
            @layout='vertical'
            @columns={{3}}
          >
            <:value as |item|><span class='v'>{{item.value}}</span></:value>
          </Descriptions>
          {{#if @model.position}}
            <p class='emb-rels'>Position
              <@fields.position @format='atom' @displayContainer={{false}} />
              {{#if @model.referredBy}}
                Referred by
                <@fields.referredBy
                  @format='atom'
                  @displayContainer={{false}}
                />
              {{/if}}
            </p>
          {{/if}}
        </article>
      </div>
      <style scoped>
        @layer PretComponent {
          .candidate-embedded {
            container-type: inline-size;
          }
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 auto;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
          }
          .emb-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            justify-content: flex-end;
            gap: var(--boxel-sp-4xs);
          }
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-fact strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .emb-kv {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
          }
          .v {
            font-weight: 600;
            font-variant-numeric: tabular-nums;
            overflow-wrap: anywhere;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs);
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          /* under 400 the chips move under the name */
          @container (width < 25rem) {
            .emb-head {
              flex-wrap: wrap;
            }
            .chips {
              flex-basis: 100%;
              justify-content: flex-start;
            }
          }
        }
      </style>
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
        {{#if @model.status}}
          <span class='stage'>
            <StatusChip
              @value={{@model.status}}
              @tone={{stageTone @model.status}}
            />
          </span>
        {{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .candidate-atom {
            /* same avatar and text size as the Employee atom beside it */
            --pretui-avatar-size: 1.25rem;
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.5rem;
            row-gap: 1.5rem;
            overflow: hidden;
            vertical-align: middle;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
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
    // Each fact is its own KeyValue row, so a row that doesn't fit wraps
    // out of sight whole instead of showing half.
    get factRows(): KeyValueItem[][] {
      return candidateFacts(this.args.model).map((f) => [
        { key: f.label, value: f.value ?? '—' },
      ]);
    }
    <template>
      <div class='fit'>
        <FitTile class='tile'>
          <:avatar>
            <Avatar
              @name={{if @model.title @model.title '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            />
          </:avatar>
          <:title><span
              role='heading'
              aria-level='3'
            >{{@model.title}}</span></:title>
          <:subtitle>{{subLine @model}}</:subtitle>
          {{! The stage is the only thing that says where this person is in
              the pipeline, so it is the first chip. }}
          <:status>
            {{#if @model.status}}
              <StatusChip
                @value={{@model.status}}
                @tone={{stageTone @model.status}}
              />
            {{/if}}
            {{#if (scoreChip @model)}}
              <StatusChip @value={{scoreChip @model}} @tone='success' />
            {{/if}}
            {{#if (checkChip @model)}}
              <StatusChip
                @value={{checkChip @model}}
                @tone={{checkTone @model.backgroundCheck.status}}
              />
            {{/if}}
          </:status>
          <:fact>{{#if (daysInPipeline @model)}}<strong
                class='strong'
              >{{daysInPipeline @model}}</strong>
              in pipeline{{/if}}{{#if (noticeLabel @model)}}{{#if
                (daysInPipeline @model)
              }}
                ·
              {{/if}}notice
              {{noticeLabel @model}}{{/if}}</:fact>
        </FitTile>
        {{! Relations, then the key facts: shown from 170 tall, and the
            relation line on a 400-wide strip. }}
        <div class='more'>
          {{#if @model.position}}
            <p class='rel'><span class='k'>Position</span><@fields.position
                @format='atom'
              /></p>
          {{/if}}
          {{#if @model.referredBy}}
            <p class='rel'><span class='k'>Referred by</span><@fields.referredBy
                @format='atom'
              /></p>
          {{/if}}
          {{#if @model.offer}}
            <p class='rel'><span class='k'>Offer</span><@fields.offer
                @format='atom'
              /></p>
          {{/if}}
          {{#each this.factRows as |row|}}
            <KeyValue class='kv' @items={{row}} />
          {{/each}}
        </div>
      </div>
      <style scoped>
        @layer PretComponent, PretComposite;
        /* FitTile sizes to its rows here, so the extra rows below it get the
           rest of the card */
        @layer PretComposite {
          .tile {
            flex: none;
            block-size: auto;
          }
        }
        @layer PretComponent {
          .fit {
            display: flex;
            flex-direction: column;
            block-size: 100%;
            overflow: hidden;
          }
          .strong {
            font-weight: 600;
            color: var(--foreground);
          }
          /* a column that wraps: a row past the bottom moves to a second
             column outside the card, whole */
          .more {
            display: none;
            flex: 1 1 0;
            flex-flow: column wrap;
            align-content: flex-start;
            row-gap: var(--boxel-sp-4xs);
            column-gap: var(--boxel-sp-sm);
            min-block-size: 0;
            padding: 0 var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.5;
          }
          .rel,
          .kv,
          .bar {
            inline-size: 100%;
          }
          .rel {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-inline-size: 0;
            margin: 0;
            overflow: hidden;
            white-space: nowrap;
          }
          .k {
            flex: none;
            color: var(--muted-foreground);
          }
          @container fitted-card (height >= 170px) {
            .more {
              display: flex;
            }
          }
          @container fitted-card (105px <= height < 170px) and (width >= 400px) {
            .more {
              display: flex;
            }
          }
        }
      </style>
    </template>
  };
}
