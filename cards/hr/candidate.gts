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
import { htmlSafe } from '@ember/template';
import { guidFor } from '@ember/object/internals';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/boxel-ui/components';
import { Alert } from '@cardstack/pretui/components/alert';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import type { KeyValueItem } from '@cardstack/pretui/components/key-value';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';

import { PersonBase } from '@cardstack/catalog/cards/people/person-base';
import ScoreField from '@cardstack/catalog/fields/rating/rating';
import { DurationField } from './duration-field';
import { Employee } from './employee';
import { Position } from './position';
import { Offer } from './offer';
import { Skill, skillCategoryHue } from './skill';
import { BackgroundCheckField } from './background-check-field';
import { InterviewFeedbackField } from './interview-feedback-field';
import { RejectionReasonField } from './rejection-reason-field';
import { WorkHistoryEntryField } from './work-history-entry-field';
import { EducationEntryField } from './education-entry-field';
import { INTERVIEW_ROUND_OPTIONS } from './interview-round-field';
import {
  StatePill,
  stateColor,
  stateColorOf,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { daysBetween, liveCount } from './utils';
import { FactList, QUIET_AVATAR_HUE, hueOf } from './hr-ui';
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

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class CandidateIsolated extends Component<typeof Candidate> {
  @tracked busyTool: 'extract' | 'questions' | undefined;
  @tracked toolError: string | undefined;
  @tracked toolMessage: string | undefined;
  @tracked selectedTab: 'overview' | 'tools' | 'resume' = 'overview';
  @tracked selectedRoundType: string | undefined = 'technical';

  setTab = (tab: 'overview' | 'tools' | 'resume') => {
    this.selectedTab = tab;
  };

  // A segmented control, not a <select>: all five rounds stay visible. This
  // is a MODE (which round the next generation call targets), not a one-shot
  // action, so it is a single-choice radio group rather than a disabled
  // state.
  roundTypeOptions = INTERVIEW_ROUND_OPTIONS;

  setRoundType = (value: string) => {
    this.selectedRoundType = value;
  };

  get stageHue() {
    return hueOf(CANDIDATE_STAGE_HUES, this.args.model?.status);
  }

  // The stage ring sits on a wrapper: Avatar writes its own inline style, and
  // a caller's `style` would replace it.
  get avatarRingStyle() {
    let ring = stateColorOf(CANDIDATE_STAGE_COLORS, this.args.model?.status);
    return htmlSafe(`--stage-ring: ${ring.ring}`);
  }

  get extractDisabled(): boolean {
    return Boolean(this.busyTool) || !this.args.model?.resumeText?.trim();
  }

  get generateDisabled(): boolean {
    return Boolean(this.busyTool);
  }

  get noticePeriodLabel(): string | undefined {
    let n = this.args.model?.noticePeriodDays;
    if (n == null) {
      return undefined;
    }
    return n === 0 ? '0 days · available immediately' : `${n} days`;
  }

  get overallScoreLabel(): string | undefined {
    let v = this.args.model?.overallScore;
    if (v == null) {
      return undefined;
    }
    return v === 0 ? '0/5 · not yet scored' : `${v}/5`;
  }

  get scorePillLabel(): string | undefined {
    let label = this.overallScoreLabel;
    return label ? `\u2605 ${label}` : undefined;
  }

  roundLabelId = `round-label-${guidFor(this)}`;

  get matchScoreLabel(): string | undefined {
    let v = this.args.model?.skillMatchPct;
    return v == null ? undefined : `${v}% match`;
  }

  get visibleSkills() {
    return (this.args.model?.skills ?? []).slice(0, 6);
  }

  get extraSkillLabel(): string | undefined {
    let extra = Math.max(0, liveCount(this.args.model?.skills) - 6);
    return extra ? `+${extra}` : undefined;
  }

  // The Overview facts as Pret UI `KeyValue` rows; the applied-on row renders
  // the date field through the `<:value>` block.
  get overviewFacts(): KeyValueItem[] {
    let m = this.args.model;
    return [
      { key: 'Applied for', value: m?.appliedRole || '—' },
      { key: 'Applied on', value: m?.appliedDate ? 'appliedDate' : '—' },
      { key: 'Email', value: m?.email || '—' },
      { key: 'Notice period', value: this.noticePeriodLabel ?? '—' },
      { key: 'Overall score', value: this.overallScoreLabel ?? '—' },
      { key: 'Time to decision', value: m?.timeToHire?.label || '—' },
    ];
  }

  // Each rating carries its scale, the same `n/5` as the overall score beside
  // it and the 5-star read-only Rating the feedback field renders.
  get feedbackFacts(): KeyValueItem[] {
    return (this.args.model?.interviewFeedback ?? []).map((fb) => ({
      key: fb?.interviewer?.name || 'Unnamed',
      value: [fb?.rating ? `\u2605 ${fb.rating}/5` : undefined, fb?.notes]
        .filter(Boolean)
        .join(' · '),
    }));
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
      <header class='hero'>
        <span class='avatar-ring' style={{this.avatarRingStyle}}>
          <Avatar
            @name={{if @model.title @model.title '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{52}}
            aria-hidden='true'
          />
        </span>
        <div class='hero-text'>
          <h1>{{@model.title}}</h1>
          <p class='byline'>
            {{if @model.appliedRole @model.appliedRole 'Role not recorded'}}
            {{#if @model.appliedDate}}
              <span class='sep-dot'>&middot;</span>
              applied
              <@fields.appliedDate />
            {{/if}}
          </p>
          <div class='pill-row'>
            <StatePill
              @label={{@model.status}}
              @hue={{this.stageHue}}
              @dot={{true}}
            />
            <StatePill @label={{this.scorePillLabel}} />
            <StatePill @label={{this.matchScoreLabel}} />
            <StatePill @label={{this.noticePeriodLabel}} />
          </div>
        </div>
      </header>

      <div class='body'>
        <div class='main'>
          <h2 class='panel-title'>Overview</h2>
          <FactList @items={{this.overviewFacts}}>
            <:value as |row|>
              {{#if (eq row.value 'appliedDate')}}
                <@fields.appliedDate />
              {{else}}
                {{row.value}}
              {{/if}}
            </:value>
          </FactList>

          <h2 class='panel-title spaced'>Skills</h2>
          {{#if @model.skills.length}}
            <ul class='chips'>
              {{#each this.visibleSkills as |skill|}}
                <li><StatePill
                    @label={{skill.title}}
                    @hue={{skillCategoryHue skill.category}}
                  /></li>
              {{/each}}
              {{#if this.extraSkillLabel}}
                <li><StatePill @label={{this.extraSkillLabel}} /></li>
              {{/if}}
            </ul>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No skills recorded'
              @message='Running Extract Resume will match them against the skill library.'
            />
          {{/if}}

          <h2 class='panel-title spaced'>Work history</h2>
          {{#if @model.workHistory.length}}
            <ul class='entry-list'>
              <@fields.workHistory />
            </ul>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No work history recorded'
              @message='Running Extract Resume will populate it from the resume text.'
            />
          {{/if}}

          <h2 class='panel-title spaced'>Education</h2>
          {{#if @model.education.length}}
            <ul class='entry-list'>
              <@fields.education />
            </ul>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No education recorded'
              @message='Running Extract Resume will populate it from the resume text.'
            />
          {{/if}}

          {{#if @model.interviewFeedback.length}}
            <h2 class='panel-title spaced'>Interview feedback</h2>
            <FactList @items={{this.feedbackFacts}} />
          {{/if}}

          <h2 class='panel-title spaced'>Background check</h2>
          {{#if @model.backgroundCheck.status}}
            <@fields.backgroundCheck />
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No background check started'
            />
          {{/if}}

          <h2 class='panel-title spaced'>Interview plan</h2>
          {{#if @model.position.interviewPlan}}
            <@fields.position.interviewPlan @format='embedded' />
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No interview plan yet'
              @message='Generate questions to create one.'
            />
          {{/if}}

          <h2 class='panel-title spaced'>Resume</h2>
          {{! Two surfaces, two jobs: the PDF is what a human reads, the text
              is what the AI commands parse. Neither substitutes for the
              other — a PDF's bytes are not something the model can read. }}
          {{#if @model.resumeFile}}
            <div class='attach'>
              <FileDownloadLink @file={{@model.resumeFile}} />
            </div>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No resume file attached'
            />
          {{/if}}
          {{#if @model.resumeText}}
            <p class='prose'>{{@model.resumeText}}</p>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No resume text on file'
              @message='Paste it into the Resume Text field to enable Extract resume and Generate questions — the AI commands read the text, not the PDF.'
            />
          {{/if}}
        </div>

        <aside class='side'>
          {{! Actions live in the aside rather than behind a tab — hiding
              them one click away taxes every single use. }}
          <h2 class='panel-title'>Actions</h2>
          {{#if @model.resumeText}}
            {{! Extract only renders when there is resume text to extract
                from — a tool with an unmet precondition is noise, and the
                Resume panel's empty state already explains how to enable
                it. }}
            <div class='actions'>
              <Button
                type='button'
                @kind='secondary'
                class='act'
                @disabled={{this.extractDisabled}}
                {{on 'click' this.extractResume}}
              >Extract resume</Button>
            </div>
          {{/if}}
          <p class='act-hint round-label' id={{this.roundLabelId}}>Round to
            generate questions for</p>
          <SegmentedControl
            class='round-toggle'
            @options={{this.roundTypeOptions}}
            @value={{this.selectedRoundType}}
            @onValueChange={{this.setRoundType}}
            aria-labelledby={{this.roundLabelId}}
          />
          <div class='actions'>
            <Button
              type='button'
              @kind='secondary'
              class='act'
              @disabled={{this.generateDisabled}}
              {{on 'click' this.generateQuestions}}
            >Generate questions</Button>
          </div>
          {{#unless @model.resumeText}}
            <p class='act-hint'>Paste resume text below before extracting.</p>
          {{/unless}}
          {{#if this.toolMessage}}
            <Alert
              class='notice'
              @tone='success'
              style={{ALERT_STYLE.success}}
            >{{this.toolMessage}}</Alert>
          {{/if}}
          {{#if this.toolError}}
            <Alert
              class='notice'
              @tone='danger'
              style={{ALERT_STYLE.danger}}
            >{{this.toolError}}</Alert>
          {{/if}}

          <h2 class='panel-title spaced'>Related</h2>
          <dl class='stacked'>
            <dt>Position</dt>
            <dd>{{#if @model.position}}<@fields.position
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}&mdash;{{/if}}</dd>
            <dt>Referred by</dt>
            <dd>{{#if @model.referredBy}}<@fields.referredBy
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}&mdash;{{/if}}</dd>
            <dt>Offer</dt>
            <dd>{{#if @model.offer}}<@fields.offer
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}&mdash; not extended{{/if}}</dd>
            <dt>Hired as</dt>
            <dd>{{#if @model.hiredAs}}<@fields.hiredAs
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}&mdash;{{/if}}</dd>
          </dl>

          {{#if @model.rejectionReason}}
            <h2 class='panel-title spaced'>Rejection reason</h2>
            <p class='side-note'>
              <@fields.rejectionReason
                @format='atom'
                @displayContainer={{false}}
              />
              {{#if @model.rejectionNote}}
                &mdash;
                {{@model.rejectionNote}}
              {{/if}}
            </p>
          {{/if}}
        </aside>
      </div>
    </article>
    <style scoped>
      .candidate-isolated {
        container-type: inline-size;
        container-name: iso;
        height: 100%;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        --cand-strong: color-mix(
          in oklch,
          var(--primary) 45%,
          var(--foreground)
        );
      }
      .avatar-ring {
        flex: none;
        display: inline-flex;
        border-radius: 50%;
        box-shadow:
          0 0 0 0.1875rem var(--background),
          0 0 0 0.3125rem var(--stage-ring);
      }
      .entry-list {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .attach {
        font-size: var(--boxel-font-size-sm);
        margin-bottom: var(--boxel-sp-xs);
      }
      .actions {
        display: grid;
        gap: 0.4rem;
      }
      .act {
        --boxel-button-secondary-background: transparent;
        --boxel-button-secondary-foreground: var(--cand-strong);
        --boxel-button-secondary-border: var(--cand-strong);
        --boxel-button-border-radius: var(--boxel-border-radius-sm);
        --boxel-button-padding: 0.5rem 0.75rem;
        --boxel-button-min-height: 2.75rem;
        --boxel-button-min-width: 0;
        font: inherit;
        font-size: var(--boxel-font-size-sm);
        font-weight: 700;
      }
      .act:disabled {
        cursor: not-allowed;
      }
      .act-hint {
        margin: 0.4rem 0 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .round-label {
        margin-top: 0.6rem;
      }
      /* Five rounds do not fit one row of the aside, so the rail wraps;
         SegmentedControl's highlight measures both axes and follows. */
      .round-toggle {
        display: flex;
        flex-wrap: wrap;
        margin: 0.3rem 0 0.6rem;
      }
      .notice {
        margin-top: var(--boxel-sp-xs);
      }
      .side-note {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.6;
        color: var(--muted-foreground);
      }
      .hero {
        flex: none;
        display: flex;
        align-items: flex-start;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-lg);
        border-bottom: 1px solid var(--border);
      }
      .hero-text {
        flex: 1;
        min-width: 0;
      }
      h1 {
        margin: 0;
        font-size: var(--boxel-font-size-xl);
        font-weight: 750;
        letter-spacing: -0.02em;
        line-height: 1.2;
        overflow-wrap: anywhere;
      }
      .byline {
        margin: var(--boxel-sp-5xs) 0 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .sep-dot {
        margin: 0 0.25rem;
      }
      .pill-row {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        margin-top: var(--boxel-sp-xs);
      }
      .body {
        display: grid;
        grid-template-columns: 1fr 17rem;
        /* Fill whatever height is left so the aside's surface reaches the
           bottom edge. Without this the grid is only as tall as its content
           and the panel stops mid-card, reading as a cut-off seam. */
        flex: 1;
        min-height: 0;
        align-content: start;
      }
      .main {
        padding: var(--boxel-sp-lg);
        min-width: 0;
      }
      .side {
        padding: var(--boxel-sp-lg);
        border-left: 1px solid var(--border);
        background-color: var(--muted);
        color: var(--foreground);
      }
      .panel-title {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        font-weight: 700;
      }
      .panel-title.spaced {
        margin-top: var(--boxel-sp-lg);
      }
      .prose {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.65;
        max-width: 56ch;
        max-height: 16rem;
        overflow-y: auto;
      }
      .chips {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-2xs) var(--boxel-sp-xs);
      }
      .stacked {
        margin: 0;
        display: grid;
      }
      .stacked dt {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
        padding-top: 0.45rem;
      }
      .stacked dd {
        margin: 0;
        padding: 0.1rem 0 0.45rem;
        font-size: var(--boxel-font-size-sm);
        border-bottom: 1px solid var(--border);
        overflow-wrap: anywhere;
      }
      .empty {
        --space-9: var(--boxel-sp);
        --space-6: var(--boxel-sp);
        --text-heading: var(--boxel-font-size);
      }
      /* The resume panel can stack a missing-file and a missing-text state. */
      .empty + .empty,
      .empty + .prose {
        margin-top: var(--boxel-sp-xs);
      }
      @container iso (max-width: 40rem) {
        .body {
          grid-template-columns: 1fr;
        }
        .side {
          border-left: 0;
          border-top: 1px solid var(--border);
        }
        .hero {
          flex-wrap: wrap;
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
    get stageHue() {
      return hueOf(CANDIDATE_STAGE_HUES, this.args.model?.status);
    }
    get scoreLabel() {
      let v = this.args.model?.overallScore;
      return typeof v === 'number' ? `\u2605 ${v}` : null;
    }
    <template>
      <div class='candidate-embedded'>
        <EntityDisplay
          class='entity'
          @title={{if @model.name @model.name 'Unnamed'}}
          @subtitle={{@model.appliedRole}}
          @center={{true}}
        >
          <:visual>
            <Avatar
              @name={{if @model.name @model.name '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{QUIET_AVATAR_HUE}}
              @size={{30}}
              aria-hidden='true'
            />
          </:visual>
        </EntityDisplay>
        <div class='ce-side'>
          <StatePill
            class='ce-stage'
            @label={{@model.status}}
            @hue={{this.stageHue}}
          />
          {{#if this.scoreLabel}}
            <span class='ce-score'>{{this.scoreLabel}}</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .candidate-embedded {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.75rem;
          font-size: 0.8125rem;
        }
        /* EntityDisplay's name and secondary line keep the row's sizes. */
        .entity {
          flex: 1;
          --pretui-entity-visual-size: 1.875rem;
          --text-ui-md: 0.8125rem;
          --text-ui-sm: 0.6875rem;
          --space-3: 0.625rem;
        }
        .ce-side {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: var(--boxel-sp-3xs);
          flex-shrink: 0;
        }
        .ce-stage {
          text-transform: capitalize;
        }
        .ce-score {
          font-size: 0.6875rem;
          font-weight: 600;
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='candidate-atom'>
        <UserSearchIcon class='candidate-atom-icon' />
        <span class='candidate-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .candidate-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .candidate-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .candidate-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get stageHue() {
      return hueOf(CANDIDATE_STAGE_HUES, this.args.model?.status);
    }

    get avatarRingStyle() {
      let ring = stateColorOf(CANDIDATE_STAGE_COLORS, this.args.model?.status);
      return htmlSafe(`--stage-ring: ${ring.ring}`);
    }
    get daysInPipeline(): number | undefined {
      return daysBetween(this.args.model?.appliedDate);
    }
    get scoreShort(): string | undefined {
      let v = this.args.model?.overallScore;
      return typeof v === 'number' ? `\u2605 ${v}/5` : undefined;
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          <span class='avatar-ring' style={{this.avatarRingStyle}}>
            <Avatar
              @name={{if @model.title @model.title '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{26}}
              aria-hidden='true'
            />
          </span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{#if @model.appliedRole}}
              <span class='fit-eb'>{{@model.appliedRole}}</span>
            {{/if}}
          </div>
          {{! Stage pill survives every tier — it is the only thing that says
              where this person is in the pipeline. }}
          <StatePill
            class='fit-pill'
            @label={{@model.status}}
            @hue={{this.stageHue}}
            @dot={{true}}
          />
        </div>

        <div class='fit-mid'>
          {{#if this.scoreShort}}
            <span class='money'>{{this.scoreShort}}</span>
          {{/if}}
          {{#if this.daysInPipeline}}
            <span class='fit-sub'>{{this.daysInPipeline}}d in pipeline</span>
          {{/if}}
        </div>

        <dl class='fit-add'>
          {{! Reads the denormalized tally, not skills.length — a linksToMany
              read here is not resolved in prerendered fitted. }}
          {{#if @model.skillTally}}
            <div><dt>Skills</dt><dd>{{@model.skillTally}}</dd></div>
          {{/if}}
          {{#if @model.appliedDate}}
            <div><dt>Applied</dt><dd><@fields.appliedDate /></dd></div>
          {{/if}}
          {{#if @model.noticePeriodDays}}
            <div><dt>Notice</dt><dd>{{@model.noticePeriodDays}}d</dd></div>
          {{/if}}
          {{#if @model.timeToHire.label}}
            <div><dt>To hire</dt><dd>{{@model.timeToHire.label}}</dd></div>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        /* Four tiers, each ADDING fields. 11px floor (was 8px). Pill always on. */
        .fit {
          height: 100%;
          /* Flex, not a three-row grid: with `minmax(0, 1fr)` in the middle
             a taller bottom block squeezed the middle row and clipped its
             text. Here the middle keeps its natural height and the extras
             block is pushed to the bottom by `margin-top: auto`. */
          display: flex;
          flex-direction: column;
          gap: 0.28rem;
          padding: 0.55rem 0.6rem;
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
          --fit-name: clamp(0.6875rem, 3.2cqi, 0.9375rem);
          --fit-small: clamp(0.6875rem, 2.6cqi, 0.75rem);
        }
        .avatar-ring {
          flex: none;
          display: inline-flex;
          border-radius: 50%;
          box-shadow:
            0 0 0 0.125rem var(--background),
            0 0 0 0.1875rem var(--stage-ring);
        }
        .fit > * {
          min-height: 0;
          overflow: hidden;
        }
        .fit-top {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: 0.4rem;
          flex-wrap: wrap;
          /* The photo avatar's ring (box-shadow, painted outside its own
             box) was being clipped along its top edge by the inherited
             `.fit > * { overflow: hidden }` rule — the ring bled above
             this row's flex-start-aligned top edge with no padding to
             absorb it, reading as a cropped circle. */
          overflow: visible;
        }
        .fit-head {
          flex: 1;
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--fit-name);
          font-weight: 700;
          line-height: 1.25;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          display: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-pill {
          flex: none;
          align-self: flex-start;
        }
        .fit-mid {
          flex: none;
          display: none;
          flex-direction: column;
          gap: 0.0625rem;
        }
        .money {
          font-size: calc(var(--fit-name) * 1.15);
          font-weight: 800;
          letter-spacing: -0.02em;
          font-variant-numeric: tabular-nums;
        }
        .fit-sub {
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-add {
          display: none;
          margin: 0;
          margin-top: auto;
          padding-top: 0.3rem;
          border-top: 1px dashed var(--border);
          grid-template-columns: 1fr 1fr;
          gap: 0.125rem 0.5rem;
        }
        .fit-add > div {
          display: flex;
          gap: 0.25rem;
          min-width: 0;
        }
        .fit-add dt {
          flex: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
        }
        .fit-add dd {
          margin: 0;
          font-size: var(--fit-small);
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          font-variant-numeric: tabular-nums;
        }

        /* TIER 2 — add the secondary line. Container queries have no `or`,
           so this is reached either by height (tile) or width (strip). */
        @container fitted-card (height > 80px) {
          .fit-eb {
            display: block;
          }
        }
        @container fitted-card (width > 240px) {
          .fit-eb {
            display: block;
          }
        }
        /* TIER 3 — add the headline figure block. */
        @container fitted-card (height > 130px) and (width > 180px) {
          .fit-mid {
            display: flex;
          }
        }
        /* TIER 4 — width-driven extra facts. Previously absent entirely,
           which is why a 500x400 tile showed the same as a 200x140 one. */
        @container fitted-card (height > 150px) and (width > 180px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr;
          }
        }
        @container fitted-card (width > 340px) and (height > 130px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr 1fr;
          }
        }
        /* Short strip: horizontal, single-line name. */
        @container fitted-card (height <= 90px) {
          .fit {
            grid-template-rows: 1fr;
            align-content: center;
          }
          .fit-top {
            align-items: center;
            flex-wrap: nowrap;
          }
          .fit-pill {
            align-self: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        /* Smallest tier: secondary line goes, the status pill stays. */
        @container fitted-card (height <= 50px) {
          .fit-eb {
            display: none;
          }
        }
      </style>
    </template>
  };
}
