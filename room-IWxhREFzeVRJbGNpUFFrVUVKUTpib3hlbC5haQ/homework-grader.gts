import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { debounce } from 'lodash';

import BookOpenIcon from '@cardstack/boxel-icons/book-open';
import ClockIcon from '@cardstack/boxel-icons/clock';
import CloseIcon from '@cardstack/boxel-icons/cross';
import UseAiAssistantCommand from '@cardstack/boxel-host/commands/ai-assistant';
import SetActiveLLMCommand from '@cardstack/boxel-host/commands/set-active-llm';
import {
  Button,
  IconButton,
  ProgressBar,
} from '@cardstack/boxel-ui/components';
import { add, eq } from '@cardstack/boxel-ui/helpers';
import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  FieldDef,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import BooleanField from 'https://cardstack.com/base/boolean';
import MarkdownField from 'https://cardstack.com/base/markdown';
import NumberField from 'https://cardstack.com/base/number';
import { Skill } from 'https://cardstack.com/base/skill';
import StringField from 'https://cardstack.com/base/string';
import TextAreaField from 'https://cardstack.com/base/text-area';

export class GradeField extends FieldDef {
  @field overallGrade = contains(StringField);
  @field overallFeedback = contains(MarkdownField);
  @field questionPoints = containsMany(NumberField);

  @field overallPoints = contains(NumberField, {
    computeVia: function (this: GradeField) {
      return this.questionPoints.reduce((acc, num) => acc + (num || 0), 0);
    },
  });

  static embedded = class Embedded extends Component<typeof GradeField> {
    get gradeClass() {
      return `grade-${(this.args.model?.overallGrade ?? 'unknown').toUpperCase()}`;
    }

    <template>
      <div class='grade-layout'>
        {{#if @model.overallGrade}}
          <div class='grade-circle {{this.gradeClass}}'>
            {{@model.overallGrade}}
          </div>
        {{/if}}

        <div class='details-column'>
          {{#if @model.overallPoints}}
            <div class='points-row'>
              <span class='detail-label'>Total Points</span>
              <span class='points-chip'>{{@model.overallPoints}}</span>
            </div>
          {{/if}}

          {{#if @model.overallFeedback}}
            <div class='feedback-row'>
              <span class='detail-label'>Feedback</span>
              <div class='feedback-content'>
                <@fields.overallFeedback />
              </div>
            </div>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .grade-layout {
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-lg);
        }

        .grade-circle {
          flex-shrink: 0;
          width: 56px;
          height: 56px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          color: white;
          background: var(--boxel-400);
        }

        .grade-circle.grade-A {
          background: var(--boxel-dark-green);
        }
        .grade-circle.grade-B {
          background: var(--boxel-blue);
        }
        .grade-circle.grade-C {
          background: var(--boxel-orange);
        }
        .grade-circle.grade-D {
          background: var(--boxel-red);
        }
        .grade-circle.grade-E {
          background: var(--boxel-red);
        }
        .grade-circle.grade-F {
          background: var(--boxel-danger);
        }

        .details-column {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          flex: 1;
        }

        .points-row,
        .feedback-row {
          display: flex;
          flex-wrap: wrap;
          align-items: flex-start;
          gap: var(--boxel-sp-sm);
        }

        .detail-label {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--boxel-500);
          text-transform: uppercase;
          letter-spacing: 0.05em;
          white-space: nowrap;
          min-width: 80px;
          padding-top: 2px;
        }

        .points-chip {
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          color: var(--boxel-navy);
          background: var(--boxel-100);
          border: 1px solid var(--boxel-200);
          border-radius: var(--boxel-border-radius-xs);
          padding: 1px var(--boxel-sp-xs);
        }

        .feedback-content {
          flex: 1;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
          color: var(--boxel-600);
        }

        .feedback-content :deep(.markdown-content) {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-2xs);
        }

        .feedback-content :deep(.markdown-content h3),
        .feedback-content :deep(.markdown-content h4),
        .feedback-content :deep(.markdown-content p) {
          margin: 0;
          font-style: italic;
        }

        .feedback-content :deep(.markdown-content p:nth-child(even)) {
          margin-bottom: var(--boxel-sp-2xs);
          border-bottom: 1px solid var(--boxel-200);
          padding-bottom: var(--boxel-sp-2xs);
        }
      </style>
    </template>
  };
}

export class QuestionField extends FieldDef {
  static displayName = 'Question';

  @field cardTitle = contains(StringField);
  @field questionText = contains(MarkdownField);
  @field answer = contains(MarkdownField);
  @field maxPoints = contains(NumberField);

  @field isAnswered = contains(BooleanField, {
    computeVia: function (this: QuestionField) {
      return this.answer?.length > 0;
    },
  });

  static isolated = class Isolated extends Component<typeof QuestionField> {
    <template>
      <div class='question-field'>
        <div class='question-content'>
          <@fields.questionText />
        </div>
        <div class='answer-section'>
          <label class='answer-label'>Your Answer</label>
          <div class='answer-input'>
            <@fields.answer @format='edit' />
          </div>
        </div>
      </div>

      <style scoped>
        .question-field {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
        }

        .answer-label {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--boxel-500);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof QuestionField> {
    <template>
      <div class='embedded-question'>
        <div class='question-preview'>
          <@fields.questionText />
        </div>
        {{#if @model.answer}}
          <div class='answer-preview'>
            <span class='answer-label'>Answer:</span>
            <span class='answer-text'>{{@model.answer}}</span>
          </div>
        {{/if}}
      </div>
    </template>
  };

  static fitted = class Fitted extends Component<typeof QuestionField> {
    <template>
      <div class='fitted-question' data-answered='{{@model.isAnswered}}'>
        <div class='question-block'>
          <@fields.questionText />
        </div>
        <div class='answer-section'>
          <span class='answer-label'>Your answer</span>
          <@fields.answer @format='edit' />
        </div>
      </div>

      <style scoped>
        .fitted-question {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          height: 100%;
        }

        .question-block {
          background: var(--boxel-100);
          border-radius: var(--boxel-border-radius-sm);
          border-left: 3px solid var(--boxel-purple);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
        }

        .fitted-question[data-answered='true'] .question-block {
          border-left-color: var(--boxel-dark-green);
        }

        .answer-label {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--boxel-500);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }

        .answer-section {
          display: flex;
          flex-direction: column;
          gap: 4px;
          flex: 1;
        }
      </style>
    </template>
  };
}

class HomeworkIsolated extends Component<typeof HomeworkGrader> {
  @tracked isGrading = false;
  @tracked lastGradedAnswers: string | null = null;
  @tracked activeTab: 'overview' | 'questions' | 'feedback' = 'overview';
  @tracked showToast = false;
  @tracked toastGrade: string | null = null;
  @tracked showAnswerUpdateToast = false;
  roomId: string | null = null;
  _gradePoller: ReturnType<typeof setInterval> | null = null;
  _lastSeenAnswers: string | null = null;
  _answerPoller: ReturnType<typeof setInterval> | null = null;

  private debouncedShowAnswerUpdateToast = debounce(() => {
    if (!this.isGrading) {
      this.showAnswerUpdateToast = true;
    }
  }, 1000);

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this._lastSeenAnswers = this.currentAnswersSnapshot;
    this._answerPoller = setInterval(() => {
      const current = this.currentAnswersSnapshot;
      if (current !== this._lastSeenAnswers) {
        this._lastSeenAnswers = current;
        this.debouncedShowAnswerUpdateToast();
      }
    }, 500);
  }

  willDestroy() {
    super.willDestroy();
    if (this._answerPoller) {
      clearInterval(this._answerPoller);
      this._answerPoller = null;
    }
    if (this._gradePoller) {
      clearInterval(this._gradePoller);
      this._gradePoller = null;
    }
    this.debouncedShowAnswerUpdateToast.cancel();
  }

  dismissGradeNotification = () => {
    this.showToast = false;
  };

  dismissAnswerUpdateToast = () => {
    this.debouncedShowAnswerUpdateToast.cancel();
    this.showAnswerUpdateToast = false;
  };

  gradeFromToast = async () => {
    this.debouncedShowAnswerUpdateToast.cancel();
    this.showAnswerUpdateToast = false;
    await this.grade();
  };

  startGradePolling = (prevGrade: string | null) => {
    if (this._gradePoller) clearInterval(this._gradePoller);
    this.showToast = false;
    let attempts = 0;
    this._gradePoller = setInterval(() => {
      attempts++;
      const current = this.args.model?.grade?.overallGrade ?? null;
      if (current && current !== prevGrade) {
        clearInterval(this._gradePoller!);
        this._gradePoller = null;
        this.toastGrade = current;
        this.showToast = true;
      }
      if (attempts > 240) {
        clearInterval(this._gradePoller!);
        this._gradePoller = null;
      }
    }, 500);
  };

  get maxPoints() {
    if (!this.args.model.questions) return 0;
    return this.args.model.questions.reduce(
      (sum: number, q: QuestionField) => sum + (q.maxPoints || 0),
      0,
    );
  }

  get totalPoints() {
    if (!this.args.model.grade?.questionPoints) return 0;
    return this.args.model.grade.questionPoints.reduce(
      (sum: number, p: number) => sum + (p || 0),
      0,
    );
  }

  get percentage() {
    if (!this.maxPoints) return 0;
    return Math.round((this.totalPoints / this.maxPoints) * 100);
  }

  get hasGrade() {
    return Boolean(
      this.args.model.grade?.overallGrade &&
      this.args.model.grade?.questionPoints.length > 0,
    );
  }

  get gradeVerdict() {
    const g = this.args.model?.grade?.overallGrade?.toUpperCase() ?? '';
    if (g.startsWith('A')) return 'Great work!';
    if (g.startsWith('B')) return 'Good work!';
    if (g.startsWith('C')) return 'Keep going!';
    if (g.startsWith('D') || g.startsWith('F')) return 'Needs improvement.';
    return null;
  }

  get currentAnswersSnapshot() {
    return JSON.stringify(
      this.args.model.questions?.map((q: QuestionField) => q.answer) ?? [],
    );
  }

  get isGradeStale() {
    if (!this.hasGrade) return false;
    if (this.lastGradedAnswers === null) return false;
    return this.lastGradedAnswers !== this.currentAnswersSnapshot;
  }

  get sidebarBackgroundURL() {
    return (
      this.args.model?.cardInfo?.cardThumbnail?.url ??
      this.args.model?.cardInfo?.cardThumbnailURL ??
      null
    );
  }

  setTab = (tab: 'overview' | 'questions' | 'feedback') => {
    this.activeTab = tab;
  };

  getPointsDisplay = (questionIndex: number) => {
    const question = this.args.model?.questions?.[questionIndex];
    const maxPoints = question?.maxPoints ?? 5;
    const earnedPoints =
      this.args.model?.grade?.questionPoints?.[questionIndex];
    return {
      earned: earnedPoints ?? 0,
      max: maxPoints,
      hasEarned: earnedPoints !== undefined && earnedPoints !== null,
    };
  };

  getQuestionTitle = (index: number): string => {
    return (
      this.args.model?.questions?.[index]?.cardTitle ?? `Question ${index + 1}`
    );
  };

  getMaxForQuestion = (index: number): number => {
    return this.args.model?.questions?.[index]?.maxPoints ?? 0;
  };

  getBreakdownBarStyle = (index: number) => {
    const pts = this.getPointsDisplay(index);
    if (!pts.max) return htmlSafe('width: 0%');
    const pct = Math.round((pts.earned / pts.max) * 100);
    return htmlSafe(`width: ${pct}%`);
  };

  getQuestionHint = (index: number): string => {
    const pts = this.getPointsDisplay(index);
    if (!pts.hasEarned) return '';
    const ratio = pts.max > 0 ? pts.earned / pts.max : 0;
    if (ratio >= 1) return 'Perfect score!';
    if (ratio >= 0.9) return 'Excellent work!';
    if (ratio >= 0.7) return 'Good progress.';
    return 'Room for improvement.';
  };

  getQuestionField = (index: number) => {
    return this.args.fields?.questions?.[index];
  };

  setupRoom = async () => {
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) throw new Error('In wrong mode');
    if (!this.args.model.gradingSkill)
      throw new Error('No grading skill is linked');
    if (!this.roomId) {
      let useAiAssistantCommand = new UseAiAssistantCommand(commandContext);
      let result = await useAiAssistantCommand.execute({
        roomName: `Grading: ${this.args.model.cardTitle}`,
        openRoom: true,
        skillCards: [this.args.model.gradingSkill],
        attachedCards: [this.args.model as CardDef],
        prompt: 'Please grade this homework assignment.',
      });
      this.roomId = result.roomId;
      let setActiveLLMCommand = new SetActiveLLMCommand(commandContext);
      await setActiveLLMCommand.execute({ roomId: this.roomId, mode: 'act' });
    }
    return this.roomId;
  };

  grade = async () => {
    if (this.isGrading) return;
    this.isGrading = true;
    this.debouncedShowAnswerUpdateToast.cancel();
    this.showAnswerUpdateToast = false;
    this.lastGradedAnswers = this.currentAnswersSnapshot;
    this._lastSeenAnswers = this.currentAnswersSnapshot;
    const prevGrade = this.args.model?.grade?.overallGrade ?? null;
    this.roomId = null;
    try {
      let commandContext = this.args.context?.commandContext;
      if (!commandContext)
        throw new Error(
          'Command context does not exist. Please switch to Interact Mode',
        );
      if (!this.args.model?.gradingSkill)
        throw new Error('You need a grading skill to be linked to grade');
      await this.setupRoom();
      if (!this.roomId) throw new Error('Room setup failed');
      this.startGradePolling(prevGrade);
    } catch (error) {
      console.error('Error grading homework:', error);
      alert('There was an error grading your homework. Please try again.');
    } finally {
      this.isGrading = false;
    }
  };

  <template>
    <article class='retro-hw'>

      {{! ── Answer-update floating toast ── }}
      {{#if this.showAnswerUpdateToast}}
        <aside class='retro-answer-toast-wrapper' aria-live='polite'>
          <section class='retro-answer-toast'>
            <header class='retro-answer-toast-top'>
              <span class='retro-answer-toast-icon'>✎</span>
              <div class='retro-answer-toast-text'>
                <h2 class='retro-answer-toast-title'>Answers Updated</h2>
                <p class='retro-answer-toast-sub'>Would you like to re-grade?</p>
              </div>
              <IconButton
                class='retro-answer-toast-close'
                @icon={{CloseIcon}}
                @size='small'
                {{on 'click' this.dismissAnswerUpdateToast}}
              />
            </header>
            <Button
              class='retro-answer-toast-regrade
                {{if this.isGrading "is-loading"}}'
              @kind='primary'
              @size='small'
              @disabled={{this.isGrading}}
              {{on 'click' this.gradeFromToast}}
            >
              <span class='retro-btn-icon'>↺</span>
              {{if this.isGrading 'Grading…' 'Re-grade now'}}
            </Button>
          </section>
        </aside>
      {{/if}}

      {{! ── Grade notification toast ── }}
      {{#if this.showToast}}
        <aside class='retro-grade-toast' aria-live='polite'>
          <div class='retro-toast-seal'>
            <span class='retro-toast-letter'>{{this.toastGrade}}</span>
          </div>
          <div class='retro-toast-copy'>
            <p class='retro-toast-eyebrow'>✦ GRADED ✦</p>
            <p class='retro-toast-grade'>{{this.toastGrade}}</p>
          </div>
          <IconButton
            class='retro-toast-close'
            @icon={{CloseIcon}}
            @size='small'
            {{on 'click' this.dismissGradeNotification}}
          />
        </aside>
      {{/if}}

      {{! ── Page Header ── }}
      <header class='retro-header'>
        <div class='retro-title-block'>
          <h1 class='retro-main-title'>{{@model.cardTitle}}</h1>
          <div class='retro-sub-title'>
            <span class='retro-title-rule'></span>
            <span class='retro-title-label'>HOMEWORK</span>
            <span class='retro-title-rule'></span>
          </div>
        </div>
        {{#if @model.gradingSkill}}
          <Button
            class='retro-grade-btn {{if this.isGrading "is-loading"}}'
            @kind='primary'
            @size='small'
            @disabled={{this.isGrading}}
            {{on 'click' this.grade}}
          >
            <span class='retro-btn-icon'>↺</span>
            {{if
              this.isGrading
              'Grading…'
              (if this.hasGrade 'Re-Grade' 'Grade Homework')
            }}
          </Button>
        {{/if}}
      </header>

      {{! ── Stale warning ── }}
      {{#if this.isGradeStale}}
        <aside class='retro-stale-banner'>
          <span>⚠</span>
          <p>Answers updated — click
            <strong>Re-grade</strong>
            for a fresh score.</p>
        </aside>
      {{/if}}

      {{! ── Body: sidebar + main ── }}
      <div class='retro-layout'>

        {{! ── Left nav ── }}
        <nav class='retro-sidebar'>
          {{#if this.sidebarBackgroundURL}}
            <img
              class='retro-sidebar-image'
              src={{this.sidebarBackgroundURL}}
              alt=''
              aria-hidden='true'
            />
          {{/if}}
          <div class='retro-sidebar-media-slot' aria-hidden='true'></div>
          <div class='retro-sidebar-nav'>
            <Button
              class='retro-nav-btn
                {{if (eq this.activeTab "overview") "is-active"}}'
              @kind='text-only'
              @size='small'
              {{on 'click' (fn this.setTab 'overview')}}
            >
              <svg
                width='15'
                height='15'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><rect x='3' y='3' width='18' height='18' rx='2' /><line
                  x1='3'
                  y1='9'
                  x2='21'
                  y2='9'
                /><line x1='9' y1='21' x2='9' y2='9' /></svg>
              OVERVIEW
            </Button>
            <Button
              class='retro-nav-btn
                {{if (eq this.activeTab "questions") "is-active"}}'
              @kind='text-only'
              @size='small'
              {{on 'click' (fn this.setTab 'questions')}}
            >
              <svg
                width='15'
                height='15'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><line x1='8' y1='6' x2='21' y2='6' /><line
                  x1='8'
                  y1='12'
                  x2='21'
                  y2='12'
                /><line x1='8' y1='18' x2='21' y2='18' /><circle
                  cx='3'
                  cy='6'
                  r='0.5'
                  fill='currentColor'
                /><circle cx='3' cy='12' r='0.5' fill='currentColor' /><circle
                  cx='3'
                  cy='18'
                  r='0.5'
                  fill='currentColor'
                /></svg>
              QUESTIONS
            </Button>
            <Button
              class='retro-nav-btn
                {{if (eq this.activeTab "feedback") "is-active"}}'
              @kind='text-only'
              @size='small'
              {{on 'click' (fn this.setTab 'feedback')}}
            >
              <svg
                width='15'
                height='15'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path
                  d='M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z'
                /></svg>
              FEEDBACK
            </Button>
          </div>
        </nav>

        {{! ── Main content ── }}
        <main class='retro-main'>

          {{! ══ OVERVIEW TAB ══ }}
          {{#if (eq this.activeTab 'overview')}}

            {{#if this.hasGrade}}
              {{! Score card }}
              <section class='retro-score-card'>
                <div class='retro-score-left'>
                  <div class='retro-grade-badge'>
                    {{@model.grade.overallGrade}}
                  </div>
                  <p class='retro-score-display'>
                    <span class='retro-score-num'>{{this.totalPoints}}</span>
                    <span class='retro-score-denom'>/
                      {{this.maxPoints}}
                      pts</span>
                  </p>
                  {{#if this.gradeVerdict}}
                    <p class='retro-score-verdict'>{{this.gradeVerdict}}</p>
                  {{/if}}
                  {{#if @model.grade.overallFeedback}}
                    <p class='retro-score-summary'>
                      {{@model.grade.overallFeedback}}
                    </p>
                  {{/if}}
                </div>
                <div class='retro-score-divider'></div>
                <section class='retro-score-right' aria-label='Score breakdown'>
                  <h2 class='retro-breakdown-heading'>SCORE BREAKDOWN</h2>
                  {{#each @model.grade.questionPoints as |pts qi|}}
                    <article class='retro-breakdown-row'>
                      <span class='retro-bd-label'>Q{{add qi 1}}</span>
                      <div class='retro-bd-bar-track'>
                        <div
                          class='retro-bd-bar-fill'
                          style={{this.getBreakdownBarStyle qi}}
                        ></div>
                      </div>
                      <span class='retro-bd-score'>{{pts}}
                        /
                        {{this.getMaxForQuestion qi}}</span>
                    </article>
                  {{/each}}
                  <footer class='retro-breakdown-total'>
                    <span class='retro-bd-total-label'>TOTAL</span>
                    <span class='retro-bd-total-score'>{{this.totalPoints}}
                      /
                      {{this.maxPoints}}</span>
                  </footer>
                </section>
              </section>

              {{! Feedback summary }}
              {{#if @model.grade.overallFeedback}}
                <section class='retro-feedback-summary'>
                  <div class='retro-starburst'>✦</div>
                  <div class='retro-feedback-inner'>
                    <h2 class='retro-feedback-heading'>FEEDBACK SUMMARY</h2>
                    <p class='retro-feedback-text'>
                      {{@model.grade.overallFeedback}}
                    </p>
                  </div>
                  <Button
                    class='retro-view-btn'
                    @kind='primary-dark'
                    @size='small'
                    {{on 'click' (fn this.setTab 'feedback')}}
                  >VIEW FULL FEEDBACK ▾</Button>
                </section>
              {{/if}}

            {{else}}
              <section class='retro-pending'>
                <div class='retro-pending-glyph'>✎</div>
                <div class='retro-pending-text'>
                  <h2 class='retro-pending-title'>Not yet graded</h2>
                  {{#if @model.gradingSkill}}
                    <p class='retro-pending-hint'>Complete your answers and
                      click
                      <em>Grade Homework</em></p>
                  {{/if}}
                </div>
              </section>
            {{/if}}

            {{! Questions overview list }}
            <section class='retro-questions-overview'>
              <div class='retro-section-head'>
                <h2 class='retro-section-title'>QUESTIONS</h2>
                <span class='retro-section-rule'></span>
              </div>
              {{#each @model.questions as |_question qi|}}
                <Button
                  class='retro-q-item'
                  @kind='text-only'
                  @size='small'
                  {{on 'click' (fn this.setTab 'questions')}}
                >
                  <div class='retro-q-circle'>{{add qi 1}}</div>
                  <div class='retro-q-meta'>
                    <span class='retro-q-name'>{{this.getQuestionTitle
                        qi
                      }}</span>
                    {{#let (this.getPointsDisplay qi) as |pts|}}
                      {{#if pts.hasEarned}}
                        <span class='retro-q-hint'>{{this.getQuestionHint
                            qi
                          }}</span>
                      {{/if}}
                    {{/let}}
                  </div>
                  {{#let (this.getPointsDisplay qi) as |pts|}}
                    <span
                      class='retro-q-pts
                        {{if
                          pts.hasEarned
                          (if (eq pts.earned pts.max) "full" "partial")
                          ""
                        }}'
                    >
                      {{#if pts.hasEarned}}
                        <strong>{{pts.earned}}</strong>
                        /
                        {{pts.max}}
                      {{else}}
                        — /
                        {{pts.max}}
                      {{/if}}
                    </span>
                  {{/let}}
                  <span class='retro-q-arrow'>›</span>
                </Button>
              {{/each}}
            </section>

          {{/if}}

          {{! ══ QUESTIONS TAB ══ }}
          {{#if (eq this.activeTab 'questions')}}
            <section class='retro-questions-full'>

              {{! ── Score strip (visible when graded) ── }}
              {{#if this.hasGrade}}
                <div class='retro-q-score-strip'>
                  <div
                    class='retro-q-strip-badge'
                  >{{@model.grade.overallGrade}}</div>
                  <div class='retro-q-strip-info'>
                    <span class='retro-q-strip-pts'>{{this.totalPoints}}
                      /
                      {{this.maxPoints}}
                      pts</span>
                    <span class='retro-q-strip-pct'>{{this.percentage}}%</span>
                  </div>
                  <div class='retro-q-strip-divider'></div>
                  <p class='retro-q-strip-label'>{{this.gradeVerdict}}</p>
                </div>
              {{/if}}

              {{#if @model.instructions}}
                <section class='retro-instructions-block'>
                  <h2 class='retro-instr-label'>INSTRUCTIONS</h2>
                  <p class='retro-instr-body'>{{@model.instructions}}</p>
                </section>
              {{/if}}
              {{#each @model.questions as |_question qi|}}
                <article class='retro-full-question'>
                  <div class='retro-full-q-header'>
                    <div class='retro-q-circle'>{{add qi 1}}</div>
                    <h2 class='retro-full-q-title'>{{this.getQuestionTitle
                        qi
                      }}</h2>
                    {{#let (this.getPointsDisplay qi) as |pts|}}
                      {{#if pts.hasEarned}}
                        <span
                          class='retro-full-q-pts
                            {{if (eq pts.earned pts.max) "full" "partial"}}'
                        >{{pts.earned}}/{{pts.max}}</span>
                      {{else}}
                        <span class='retro-full-q-max'>{{pts.max}} pts</span>
                      {{/if}}
                    {{/let}}
                  </div>
                  <div class='retro-full-q-body'>
                    {{#let (this.getQuestionField qi) as |questionField|}}
                      {{#if questionField}}
                        {{component questionField format='fitted'}}
                      {{/if}}
                    {{/let}}
                  </div>
                </article>
              {{/each}}
            </section>
          {{/if}}

          {{! ══ FEEDBACK TAB ══ }}
          {{#if (eq this.activeTab 'feedback')}}
            <section class='retro-feedback-full'>
              {{#if this.hasGrade}}
                <div class='retro-feedback-grade-row'>
                  <div class='retro-grade-badge'>
                    {{@model.grade.overallGrade}}
                  </div>
                  <div class='retro-feedback-grade-info'>
                    <span class='retro-feedback-pts'>{{this.totalPoints}}
                      /
                      {{this.maxPoints}}
                      pts</span>
                    <span class='retro-feedback-pct'>{{this.percentage}}%</span>
                  </div>
                </div>
                <section class='retro-feedback-content'>
                  <@fields.grade />
                </section>
              {{else}}
                <p class='retro-no-feedback'>No feedback yet — grade your
                  homework first.</p>
              {{/if}}
            </section>
          {{/if}}

        </main>
      </div>

      {{! ── Footer CTA ── }}
      {{#if @model.gradingSkill}}
        <footer class='retro-footer-cta'>
          <span class='retro-cta-star'>✦</span>
          <div class='retro-cta-copy'>
            <p class='retro-cta-main'>Ready to improve your score?</p>
            <p class='retro-cta-sub'>Re-grade your homework with our AI tutor.</p>
          </div>
        </footer>
      {{/if}}

    </article>

    <style scoped>
      /* ── Tokens ── */
      .retro-hw {
        --r-bg: #f4e8c4;
        --r-paper: #faf6ed;
        --r-dark: #1a1008;
        --r-dark2: #2e1e0e;
        --r-red: #8b1a1a;
        --r-red2: #a82020;
        --r-border: rgba(26, 16, 8, 0.15);
        --r-border-dark: rgba(26, 16, 8, 0.35);
        --r-text: #1a1008;
        --r-text-muted: #6b5540;
        --r-gold: #c8992d;

        min-height: 100%;
        display: flex;
        flex-direction: column;
        background: var(--r-bg);
        font-family: Georgia, 'Times New Roman', serif;
        color: var(--r-text);
        position: relative;
      }

      /* ── Header ── */
      .retro-header {
        background: var(--r-dark);
        padding: 24px 32px 20px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 20px;
        flex-shrink: 0;
      }

      .retro-title-block {
        position: relative;
        z-index: 1;
      }

      .retro-title-block {
        min-width: 0;
      }

      .retro-main-title {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: clamp(1.6rem, 4vw, 2.8rem);
        font-weight: 900;
        color: var(--r-bg);
        margin: 0;
        line-height: 1;
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }

      .retro-sub-title {
        display: flex;
        align-items: center;
        gap: 10px;
        margin-top: 6px;
        color: var(--r-red);
      }

      .retro-title-rule {
        height: 1.5px;
        width: 28px;
        background: var(--r-red);
        flex-shrink: 0;
      }

      .retro-title-label {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.3em;
        text-transform: uppercase;
        color: var(--r-red);
        white-space: nowrap;
      }

      /* ── Retro grade button via Boxel UI Button ── */
      .retro-grade-btn {
        --boxel-button-color: var(--r-gold);
        --boxel-button-text-color: var(--r-dark);
        --boxel-button-border: 2px solid
          color-mix(in srgb, var(--r-gold) 70%, #000 30%);
        --boxel-button-border-radius: 3px;
        --boxel-button-font: 700 12px Georgia, 'Times New Roman', serif;
        --boxel-button-letter-spacing: 0.12em;
        --boxel-button-padding: 9px 18px;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;
        --boxel-button-box-shadow: 3px 3px 0 rgba(0, 0, 0, 0.5);
        --boxel-button-transition: box-shadow 0.1s, transform 0.1s;

        gap: 7px;
        text-transform: uppercase;
        white-space: nowrap;
        flex-shrink: 0;
        position: relative;
        z-index: 1;
      }

      .retro-grade-btn:hover:not(:disabled) {
        --boxel-button-color: #daa832;
        --boxel-button-box-shadow: 2px 2px 0 rgba(0, 0, 0, 0.5);
        transform: translate(1px, 1px);
      }

      .retro-grade-btn:active:not(:disabled) {
        --boxel-button-box-shadow: 0 0 0 rgba(0, 0, 0, 0.5);
        transform: translate(3px, 3px);
      }

      .retro-grade-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }

      .retro-btn-icon {
        font-size: 14px;
        line-height: 1;
      }

      .retro-grade-btn.is-loading .retro-btn-icon {
        display: inline-block;
        animation: retro-spin 1s linear infinite;
      }

      @keyframes retro-spin {
        from {
          transform: rotate(0deg);
        }
        to {
          transform: rotate(360deg);
        }
      }

      /* ── Stale banner ── */
      .retro-stale-banner {
        display: flex;
        align-items: center;
        gap: 8px;
        background: #fef3c7;
        border-bottom: 2px solid #d97706;
        padding: 9px 32px;
        font-size: 13px;
        color: #78350f;
        font-family: Georgia, serif;
      }

      /* ── Body layout ── */
      .retro-layout {
        display: flex;
        flex: 1;
        min-height: 0;
      }

      /* ── Sidebar ── */
      .retro-sidebar {
        background: var(--r-dark);
        width: 200px;
        flex-shrink: 0;
        display: grid;
        grid-template-rows: 1fr 30%;
        border-right: 1px solid var(--r-dark2);
        position: relative;
        z-index: 2;
        overflow: hidden;
      }

      .retro-sidebar-image {
        position: absolute;
        inset: auto 0 0;
        width: 100%;
        height: 30%;
        object-fit: cover;
        opacity: 1;
        z-index: 0;
        pointer-events: none;
      }

      .retro-sidebar-media-slot {
        grid-row: 2;
        min-height: 0;
      }

      .retro-sidebar-nav {
        display: flex;
        flex-direction: column;
        gap: 4px;
        padding: 24px 0;
        background: linear-gradient(
          to top,
          rgba(26, 16, 8, 0.08),
          rgba(26, 16, 8, 0.92) 24px,
          var(--r-dark) 72px
        );
        position: relative;
        z-index: 1;
      }

      .retro-nav-btn {
        --boxel-button-border-radius: 0;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 11px 18px;
        background: transparent;
        border: none;
        border-left: 3px solid transparent;
        cursor: pointer;
        font-family: Georgia, serif;
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.12em;
        color: rgba(244, 232, 196, 0.45);
        text-align: left;
        transition:
          color 0.15s,
          border-color 0.15s,
          background 0.15s;
        position: relative;
        z-index: 1;
      }

      .retro-nav-btn:hover {
        color: rgba(244, 232, 196, 0.75);
        background: rgba(255, 255, 255, 0.04);
      }

      .retro-nav-btn.is-active {
        color: var(--r-bg);
        border-left-color: var(--r-red);
        background: rgba(139, 26, 26, 0.15);
      }

      /* ── Main content area ── */
      .retro-main {
        flex: 1;
        padding: 24px;
        display: flex;
        flex-direction: column;
        gap: 20px;
        overflow-y: auto;
        min-width: 0;
      }

      /* ── Score card ── */
      .retro-score-card {
        background: var(--r-paper);
        border: 2px solid var(--r-dark);
        border-radius: 10px;
        display: flex;
        flex-wrap: wrap;
        overflow: hidden;
        gap: 0;
      }

      .retro-score-left {
        padding: 24px 28px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        flex: 1;
        min-width: 0;
      }

      .retro-grade-badge {
        width: 62px;
        height: 62px;
        border-radius: 50%;
        background: var(--r-red);
        display: flex;
        align-items: center;
        justify-content: center;
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 26px;
        font-weight: 900;
        color: white;
        flex-shrink: 0;
        box-shadow:
          0 2px 0 rgba(0, 0, 0, 0.25),
          0 0 0 3px rgba(139, 26, 26, 0.18);
      }

      .retro-score-display {
        display: flex;
        align-items: baseline;
        gap: 6px;
        line-height: 1;
      }

      .retro-score-num {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 52px;
        font-weight: 900;
        color: var(--r-text);
        line-height: 1;
        letter-spacing: -0.02em;
      }

      .retro-score-denom {
        font-size: 15px;
        color: var(--r-text-muted);
        font-weight: 400;
      }

      .retro-score-verdict {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 17px;
        font-weight: 700;
        color: var(--r-red);
        font-style: italic;
      }

      .retro-score-summary {
        font-size: 13px;
        line-height: 1.55;
        color: var(--r-text-muted);
        margin: 0;
        max-width: 28ch;
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
      }

      .retro-score-divider {
        width: 1px;
        background: var(--r-border-dark);
        flex-shrink: 0;
        margin: 20px 0;
      }

      .retro-score-right {
        padding: 24px 24px 24px 20px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        min-width: 190px;
        justify-content: center;
      }

      .retro-breakdown-heading {
        font-size: 9px;
        font-weight: 700;
        letter-spacing: 0.22em;
        color: var(--r-text-muted);
        text-transform: uppercase;
        margin-bottom: 4px;
        font-family: Georgia, serif;
      }

      .retro-breakdown-row {
        display: grid;
        grid-template-columns: 24px 1fr 56px;
        align-items: center;
        gap: 8px;
      }

      .retro-bd-label {
        font-size: 12px;
        font-weight: 700;
        color: var(--r-text);
        font-family: Georgia, serif;
      }

      .retro-bd-bar-track {
        height: 5px;
        border-radius: 3px;
        background: rgba(26, 16, 8, 0.12);
        overflow: hidden;
      }

      .retro-bd-bar-fill {
        height: 100%;
        background: var(--r-red);
        border-radius: 3px;
        transition: width 0.4s ease;
      }

      .retro-bd-score {
        font-size: 12px;
        color: var(--r-text-muted);
        text-align: right;
        font-family: Georgia, serif;
        white-space: nowrap;
      }

      .retro-breakdown-total {
        display: flex;
        justify-content: space-between;
        align-items: center;
        border-top: 1.5px solid var(--r-border-dark);
        padding-top: 10px;
        margin-top: 4px;
      }

      .retro-bd-total-label {
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.18em;
        color: var(--r-text);
      }

      .retro-bd-total-score {
        font-size: 15px;
        font-weight: 700;
        color: var(--r-red);
        font-family: 'Playfair Display', Georgia, serif;
      }

      /* ── Pending state ── */
      .retro-pending {
        background: var(--r-paper);
        border: 2px dashed var(--r-border-dark);
        border-radius: 10px;
        padding: 28px;
        display: flex;
        align-items: center;
        gap: 20px;
      }

      .retro-pending-glyph {
        font-size: 36px;
        color: var(--r-border-dark);
        line-height: 1;
        flex-shrink: 0;
      }

      .retro-pending-text {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }

      .retro-pending-title {
        font-size: 15px;
        font-weight: 700;
        color: var(--r-text-muted);
        font-family: 'Playfair Display', Georgia, serif;
        font-style: italic;
      }

      .retro-pending-hint {
        font-size: 13px;
        color: var(--r-text-muted);
        opacity: 0.7;
      }

      /* ── Feedback summary ── */
      .retro-feedback-summary {
        background: var(--r-bg);
        border: 1.5px solid var(--r-border-dark);
        border-radius: 8px;
        padding: 18px 20px;
        display: flex;
        align-items: flex-start;
        gap: 16px;
        position: relative;
      }

      .retro-starburst {
        font-size: 28px;
        color: var(--r-red);
        line-height: 1;
        flex-shrink: 0;
        margin-top: 2px;
      }

      .retro-feedback-inner {
        flex: 1;
        min-width: 0;
      }

      .retro-feedback-heading {
        font-size: 9px;
        font-weight: 700;
        letter-spacing: 0.22em;
        color: var(--r-text-muted);
        margin-bottom: 6px;
      }

      .retro-feedback-text {
        font-size: 13px;
        line-height: 1.6;
        color: var(--r-text);
        margin: 0;
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
      }

      .retro-view-btn {
        --boxel-button-color: var(--r-dark);
        --boxel-button-text-color: var(--r-bg);
        --boxel-button-border: none;
        --boxel-button-border-radius: 100px;
        --boxel-button-font: 700 11px Georgia, serif;
        --boxel-button-letter-spacing: 0.12em;
        --boxel-button-padding: 9px 18px;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;
        --boxel-button-box-shadow: none;

        white-space: nowrap;
        flex-shrink: 0;
        align-self: flex-end;
      }

      .retro-view-btn:hover {
        --boxel-button-color: var(--r-red);
      }

      /* ── Questions overview ── */
      .retro-questions-overview {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .retro-section-head {
        display: flex;
        align-items: center;
        gap: 14px;
        margin-bottom: 4px;
      }

      .retro-section-title {
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.25em;
        color: var(--r-text);
        white-space: nowrap;
        font-family: Georgia, serif;
      }

      .retro-section-rule {
        flex: 1;
        height: 1px;
        background: var(--r-border-dark);
      }

      .retro-q-item {
        display: flex;
        align-items: center;
        gap: 14px;
        background: var(--r-paper);
        border: 1.5px solid var(--r-border);
        border-radius: 8px;
        padding: 14px 16px;
        cursor: pointer;
        text-align: left;
        width: 100%;
        transition:
          border-color 0.15s,
          background 0.15s;
        font-family: inherit;
      }

      .retro-q-item:hover {
        border-color: var(--r-red);
        background: white;
      }

      .retro-q-circle {
        width: 34px;
        height: 34px;
        border-radius: 50%;
        background: var(--r-red);
        color: white;
        display: flex;
        align-items: center;
        justify-content: center;
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 15px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .retro-q-meta {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
      }

      .retro-q-name {
        font-size: 14px;
        font-weight: 700;
        color: var(--r-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .retro-q-hint {
        font-size: 12px;
        color: var(--r-text-muted);
        font-style: italic;
      }

      .retro-q-pts {
        font-size: 14px;
        color: var(--r-text-muted);
        white-space: nowrap;
        flex-shrink: 0;
        font-family: 'Playfair Display', Georgia, serif;
      }

      .retro-q-pts.full {
        color: #1a7a3f;
      }

      .retro-q-pts.partial {
        color: var(--r-red);
      }

      .retro-q-pts strong {
        color: var(--r-red);
      }

      .retro-q-pts.full strong {
        color: #1a7a3f;
      }

      .retro-q-arrow {
        font-size: 20px;
        color: var(--r-border-dark);
        line-height: 1;
        flex-shrink: 0;
      }

      /* ── Questions full tab ── */
      .retro-questions-full {
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      /* Score strip in questions tab */
      .retro-q-score-strip {
        background: var(--r-dark);
        border-radius: 8px;
        padding: 12px 18px;
        display: flex;
        align-items: center;
        gap: 14px;
      }

      .retro-q-strip-badge {
        width: 44px;
        height: 44px;
        border-radius: 50%;
        background: var(--r-red);
        border: 2px solid var(--r-gold);
        display: flex;
        align-items: center;
        justify-content: center;
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 20px;
        font-weight: 900;
        color: white;
        flex-shrink: 0;
        box-shadow: 2px 2px 0 rgba(0, 0, 0, 0.4);
      }

      .retro-q-strip-info {
        display: flex;
        flex-direction: column;
        gap: 1px;
      }

      .retro-q-strip-pts {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 16px;
        font-weight: 700;
        color: var(--r-bg);
        line-height: 1;
      }

      .retro-q-strip-pct {
        font-size: 11px;
        color: var(--r-gold);
        font-family: Georgia, serif;
        font-weight: 700;
        letter-spacing: 0.06em;
      }

      .retro-q-strip-divider {
        width: 1px;
        height: 32px;
        background: rgba(244, 232, 196, 0.15);
        flex-shrink: 0;
      }

      .retro-q-strip-label {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 14px;
        font-style: italic;
        color: rgba(244, 232, 196, 0.6);
      }

      .retro-instructions-block {
        background: #fef9ed;
        border: 1.5px solid #d4a843;
        border-radius: 8px;
        padding: 16px 18px;
      }

      .retro-instr-label {
        font-size: 9px;
        font-weight: 700;
        letter-spacing: 0.22em;
        color: #78350f;
      }

      .retro-instr-body {
        font-size: 13px;
        color: #78350f;
        line-height: 1.6;
        margin: 6px 0 0;
      }

      .retro-full-question {
        background: var(--r-paper);
        border: 1.5px solid var(--r-border-dark);
        border-radius: 8px;
        overflow: hidden;
      }

      .retro-full-q-header {
        background: var(--r-dark);
        padding: 12px 16px;
        display: flex;
        align-items: center;
        gap: 12px;
      }

      .retro-full-q-title {
        flex: 1;
        font-size: 14px;
        font-weight: 700;
        color: var(--r-bg);
        font-family: 'Playfair Display', Georgia, serif;
      }

      .retro-full-q-pts {
        font-size: 13px;
        font-weight: 700;
        color: var(--r-bg);
        opacity: 0.8;
      }

      .retro-full-q-pts.full {
        color: #6ee7b7;
        opacity: 1;
      }

      .retro-full-q-pts.partial {
        color: #fca5a5;
        opacity: 1;
      }

      .retro-full-q-max {
        font-size: 12px;
        color: rgba(244, 232, 196, 0.5);
      }

      .retro-full-q-body {
        padding: 16px;
        min-height: 160px;
      }

      /* ── Feedback full tab ── */
      .retro-feedback-full {
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      .retro-feedback-grade-row {
        display: flex;
        align-items: center;
        gap: 16px;
        padding-bottom: 16px;
        border-bottom: 1.5px solid var(--r-border-dark);
      }

      .retro-feedback-grade-info {
        display: flex;
        flex-direction: column;
        gap: 3px;
      }

      .retro-feedback-pts {
        font-size: 18px;
        font-weight: 700;
        color: var(--r-text);
        font-family: 'Playfair Display', Georgia, serif;
      }

      .retro-feedback-pct {
        font-size: 13px;
        color: var(--r-text-muted);
      }

      .retro-feedback-content {
        background: var(--r-paper);
        border: 1.5px solid var(--r-border);
        border-radius: 8px;
        padding: 24px 28px;
      }

      .retro-no-feedback {
        font-size: 14px;
        color: var(--r-text-muted);
        font-style: italic;
        text-align: center;
        padding: 40px 0;
        margin: 0;
      }

      /* ── Footer CTA ── */
      .retro-footer-cta {
        background: var(--r-dark);
        padding: 20px 32px;
        display: flex;
        align-items: center;
        gap: 18px;
        flex-shrink: 0;
      }

      .retro-cta-star {
        font-size: 26px;
        color: var(--r-gold);
        flex-shrink: 0;
        line-height: 1;
      }

      .retro-cta-copy {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .retro-cta-main {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 17px;
        font-weight: 700;
        font-style: italic;
        color: var(--r-bg);
      }

      .retro-cta-sub {
        font-size: 12px;
        color: rgba(244, 232, 196, 0.5);
      }

      /* ── Grade notification toast ── */
      .retro-grade-toast {
        position: sticky;
        top: 0;
        z-index: 50;
        display: flex;
        align-items: center;
        gap: 14px;
        background: var(--r-dark);
        border-bottom: 3px solid var(--r-gold);
        padding: 12px 20px;
        animation: retro-toast-in 0.3s cubic-bezier(0.22, 1, 0.36, 1) both;
      }

      @keyframes retro-toast-in {
        from {
          opacity: 0;
          transform: translateY(-100%);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }

      .retro-toast-seal {
        width: 46px;
        height: 46px;
        border-radius: 50%;
        background: var(--r-red);
        border: 2px solid var(--r-gold);
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        box-shadow:
          2px 2px 0 rgba(0, 0, 0, 0.5),
          0 0 0 4px color-mix(in srgb, var(--r-gold) 15%, transparent);
      }

      .retro-toast-letter {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 24px;
        font-weight: 900;
        color: white;
        line-height: 1;
      }

      .retro-toast-copy {
        display: flex;
        flex-direction: column;
        gap: 2px;
        flex: 1;
      }

      .retro-toast-eyebrow {
        font-size: 9px;
        font-weight: 700;
        letter-spacing: 0.25em;
        color: var(--r-gold);
        font-family: Georgia, serif;
      }

      .retro-toast-grade {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 20px;
        font-weight: 900;
        color: var(--r-bg);
        line-height: 1;
      }

      .retro-toast-close {
        background: none;
        border: 1.5px solid rgba(244, 232, 196, 0.25);
        border-radius: 50%;
        color: rgba(244, 232, 196, 0.5);
        font-size: 16px;
        line-height: 1;
        cursor: pointer;
        padding: 0;
        width: 28px;
        height: 28px;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        transition:
          color 0.12s,
          border-color 0.12s;
        font-family: Georgia, serif;
      }

      .retro-toast-close:hover {
        color: var(--r-bg);
        border-color: var(--r-bg);
      }

      /* ── Answer-update floating toast ── */

      /*
        Zero-height sticky wrapper: sticks at the top of the scroll
        container but contributes no height to the flow, so it never
        pushes content down. overflow:visible lets the toast render
        below it. pointer-events:none on the transparent area so clicks
        pass through to whatever is behind it.
      */
      .retro-answer-toast-wrapper {
        position: sticky;
        top: 0;
        height: 0;
        overflow: visible;
        display: flex;
        justify-content: flex-end;
        padding-right: 16px;
        z-index: 10;
        pointer-events: none;
      }

      .retro-answer-toast {
        pointer-events: all;
        margin-top: 16px;
        background: #120a05;
        border: 2px solid var(--r-gold);
        border-radius: 8px;
        padding: 14px 16px 12px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        box-shadow:
          4px 4px 0 rgba(0, 0, 0, 0.6),
          0 0 0 1px color-mix(in srgb, var(--r-gold) 30%, transparent);
        max-width: 256px;
        min-width: 200px;
        height: fit-content;
        animation: retro-answer-toast-in 0.25s cubic-bezier(0.22, 1, 0.36, 1)
          both;
      }

      @keyframes retro-answer-toast-in {
        from {
          opacity: 0;
          transform: translateX(18px);
        }
        to {
          opacity: 1;
          transform: translateX(0);
        }
      }

      .retro-answer-toast-top {
        display: flex;
        align-items: flex-start;
        gap: 10px;
      }

      .retro-answer-toast-icon {
        font-size: 18px;
        color: var(--r-gold);
        line-height: 1.2;
        flex-shrink: 0;
      }

      .retro-answer-toast-text {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
      }

      .retro-answer-toast-title {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 13px;
        font-weight: 700;
        color: #fff7e2;
        line-height: 1.2;
      }

      .retro-answer-toast-sub {
        font-size: 11px;
        color: rgba(255, 247, 226, 0.82);
        font-family: Georgia, serif;
      }

      .retro-answer-toast-close {
        background: none;
        border: 1px solid rgba(255, 247, 226, 0.42);
        border-radius: 50%;
        color: rgba(255, 247, 226, 0.78);
        font-size: 14px;
        width: 22px;
        height: 22px;
        display: flex;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        flex-shrink: 0;
        padding: 0;
        transition:
          color 0.12s,
          border-color 0.12s;
        font-family: Georgia, serif;
      }

      .retro-answer-toast-close:hover {
        color: #ffffff;
        border-color: #fff7e2;
      }

      .retro-answer-toast-regrade {
        --boxel-button-color: var(--r-gold);
        --boxel-button-text-color: var(--r-dark);
        --boxel-button-border: 2px solid
          color-mix(in srgb, var(--r-gold) 70%, #000 30%);
        --boxel-button-border-radius: 4px;
        --boxel-button-padding: 8px 12px;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: 100%;
        --boxel-button-font: 700 11px Georgia, 'Times New Roman', serif;
        --boxel-button-letter-spacing: 0.1em;
        --boxel-button-box-shadow: 2px 2px 0 rgba(0, 0, 0, 0.45);
        --boxel-button-transition: box-shadow 0.1s, transform 0.1s;

        justify-content: center;
        gap: 6px;
        width: 100%;
        text-transform: uppercase;
      }

      .retro-answer-toast-regrade:hover:not(:disabled) {
        --boxel-button-color: #daa832;
        --boxel-button-box-shadow: 1px 1px 0 rgba(0, 0, 0, 0.45);
        transform: translate(1px, 1px);
      }

      .retro-answer-toast-regrade:active:not(:disabled) {
        --boxel-button-box-shadow: none;
        transform: translate(2px, 2px);
      }

      .retro-answer-toast-regrade:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }

      .retro-answer-toast-regrade.is-loading .retro-btn-icon {
        display: inline-block;
        animation: retro-spin 1s linear infinite;
      }
    </style>
  </template>
}

class HomeworkFitted extends Component<typeof HomeworkGrader> {
  get fittedImageURL() {
    return (
      this.args.model?.cardInfo?.cardThumbnail?.url ??
      this.args.model?.cardInfo?.cardThumbnailURL ??
      null
    );
  }

  get hasGrade() {
    return !!this.args.model?.grade?.overallGrade;
  }

  get questionsCount() {
    return this.args.model?.questions?.length ?? 0;
  }

  get totalPoints() {
    return (
      this.args.model?.grade?.questionPoints?.reduce(
        (sum: number, p: number) => sum + (p || 0),
        0,
      ) ?? 0
    );
  }

  get maxPoints() {
    return (
      this.args.model?.questions?.reduce(
        (sum: number, q: QuestionField) => sum + (q.maxPoints || 0),
        0,
      ) ?? 0
    );
  }

  get percentage() {
    if (!this.maxPoints) return 0;
    return Math.round((this.totalPoints / this.maxPoints) * 100);
  }

  get gradeKey() {
    return this.args.model?.grade?.overallGrade?.toUpperCase() ?? '';
  }

  get gradeClass() {
    const g = this.gradeKey;
    if (g.startsWith('A')) return 'grade-a';
    if (g.startsWith('B')) return 'grade-b';
    if (g.startsWith('C')) return 'grade-c';
    if (g.startsWith('D') || g.startsWith('E') || g.startsWith('F'))
      return 'grade-f';
    return '';
  }

  <template>
    <article class='retro-fitted {{this.gradeClass}}'>

      {{! ══ BADGE: dark seal with serif grade ══ }}
      <section class='badge-fmt' aria-label='Homework badge'>
        {{#if this.fittedImageURL}}
          <img
            class='fitted-media-image'
            src={{this.fittedImageURL}}
            alt=''
            aria-hidden='true'
          />
        {{/if}}
        <div class='badge-seal'>
          {{#if this.hasGrade}}
            <span class='badge-letter'>{{@model.grade.overallGrade}}</span>
          {{else}}
            <BookOpenIcon class='badge-icon' width='22' height='22' />
          {{/if}}
        </div>
        <span class='badge-label'>{{if
            @model.cardTitle
            @model.cardTitle
            'HW'
          }}</span>
      </section>

      {{! ══ STRIP: warm-cream editorial bar ══ }}
      <section class='strip-fmt' aria-label='Homework summary strip'>
        {{#if this.fittedImageURL}}
          <img
            class='fitted-media-image'
            src={{this.fittedImageURL}}
            alt=''
            aria-hidden='true'
          />
        {{/if}}
        <div class='strip-grade {{unless this.hasGrade "strip-pending"}}'>
          {{if this.hasGrade @model.grade.overallGrade '—'}}
        </div>
        <span class='strip-title'>{{if
            @model.cardTitle
            @model.cardTitle
            'Untitled Homework'
          }}</span>
        {{#if this.hasGrade}}
          <span class='strip-pct'>{{this.percentage}}%</span>
        {{/if}}
        <span class='strip-qs'>{{this.questionsCount}}Q</span>
      </section>

      {{! ══ TILE: dark header + warm body with hero grade ══ }}
      <article class='tile-fmt'>
        {{#if this.fittedImageURL}}
          <img
            class='fitted-media-image'
            src={{this.fittedImageURL}}
            alt=''
            aria-hidden='true'
          />
        {{/if}}
        <header class='tile-hd'>
          <span class='tile-eyebrow'>
            <span class='tile-rule'></span>
            HOMEWORK
            <span class='tile-rule'></span>
          </span>
          <span class='tile-name'>{{if
              @model.cardTitle
              @model.cardTitle
              'Untitled'
            }}</span>
        </header>
        <section class='tile-body'>
          {{#if this.hasGrade}}
            <p class='tile-grade'>{{@model.grade.overallGrade}}</p>
            <p class='tile-score-row'>
              <span class='tile-pct'>{{this.percentage}}%</span>
              <span class='tile-pts'>{{this.totalPoints}}/{{this.maxPoints}}
                pts</span>
            </p>
          {{else}}
            <div class='tile-pending'>
              <ClockIcon width='18' height='18' />
              <span>Awaiting grade</span>
            </div>
          {{/if}}
        </section>
        <footer class='tile-ft'>{{this.questionsCount}} questions</footer>
      </article>

      {{! ══ CARD: dark panel + warm editorial body ══ }}
      <article class='card-fmt'>
        {{#if this.fittedImageURL}}
          <img
            class='fitted-media-image'
            src={{this.fittedImageURL}}
            alt=''
            aria-hidden='true'
          />
        {{/if}}
        <div class='card-panel'>
          <span class='card-panel-label'>GRADE</span>
          {{#if this.hasGrade}}
            <p class='card-grade'>{{@model.grade.overallGrade}}</p>
            <span class='card-pct'>{{this.percentage}}%</span>
            <span class='card-pts'>{{this.totalPoints}}
              /
              {{this.maxPoints}}
              pts</span>
          {{else}}
            <div class='card-pending-icon'>
              <ClockIcon width='26' height='26' />
            </div>
            <span class='card-pending-label'>Pending</span>
          {{/if}}
        </div>
        <section class='card-body'>
          <div class='card-eyebrow'>
            <span class='card-rule'></span>
            <span class='card-eyebrow-text'>HOMEWORK</span>
            <span class='card-rule'></span>
          </div>
          <h2 class='card-title'>{{if
              @model.cardTitle
              @model.cardTitle
              'Untitled Homework'
            }}</h2>
          <p class='card-meta'>{{this.questionsCount}} questions</p>
          {{#if this.hasGrade}}
            <ProgressBar
              @value={{this.totalPoints}}
              @max={{this.maxPoints}}
              class='card-bar'
            />
          {{/if}}
        </section>
      </article>
    </article>

    {{! template-lint-disable no-whitespace-for-layout  }}
    <style scoped>
      /* ── Retro tokens ── */
      .retro-fitted {
        --r-bg: #f4e8c4;
        --r-paper: #faf6ed;
        --r-dark: #1a1008;
        --r-red: #8b1a1a;
        --r-gold: #c8992d;
        --r-text: #1a1008;
        --r-text-muted: #6b5540;
        --r-border: rgba(26, 16, 8, 0.15);
        --r-border-dark: rgba(26, 16, 8, 0.35);
        --r-accent: var(--r-red);

        width: 100%;
        height: 100%;
        font-family: Georgia, 'Times New Roman', serif;
      }

      /* Grade-keyed accent */
      .retro-fitted.grade-a {
        --r-accent: #1a7a3f;
      }
      .retro-fitted.grade-b {
        --r-accent: #1d4ed8;
      }
      .retro-fitted.grade-c {
        --r-accent: #b45309;
      }
      .retro-fitted.grade-f {
        --r-accent: #8b1a1a;
      }

      /* All sub-formats hidden by default */
      .badge-fmt,
      .strip-fmt,
      .tile-fmt,
      .card-fmt {
        display: none;
        width: 100%;
        height: 100%;
        box-sizing: border-box;
        overflow: hidden;
        position: relative;
        isolation: isolate;
      }

      .fitted-media-image {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        opacity: 0.15;
        z-index: 0;
        pointer-events: none;
      }

      /* ══════════════════════════════════════
         BADGE  ≤150 × <170
      ══════════════════════════════════════ */
      @container fitted-card (max-width: 150px) and (max-height: 169px) {
        .badge-fmt {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 7px;
          background: linear-gradient(
            to bottom,
            transparent 0 30%,
            var(--r-dark) 30% 100%
          );
          padding: 10px 8px;
        }
      }

      .badge-seal {
        width: 52px;
        height: 52px;
        border-radius: 50%;
        background: var(--r-red);
        border: 2px solid color-mix(in srgb, var(--r-gold) 60%, transparent);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 0 0 4px color-mix(in srgb, var(--r-gold) 12%, transparent);
        position: relative;
        z-index: 1;
      }

      .badge-letter {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 30px;
        font-weight: 900;
        color: white;
        line-height: 1;
      }

      .badge-icon {
        color: var(--r-gold);
      }

      .badge-label {
        font-size: 9px;
        font-weight: 700;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: rgba(244, 232, 196, 0.55);
        text-align: center;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        max-width: 100%;
        position: relative;
        z-index: 1;
      }

      /* ══════════════════════════════════════
         STRIP  >150 × <170
      ══════════════════════════════════════ */
      @container fitted-card (min-width: 151px) and (max-height: 169px) {
        .strip-fmt {
          display: flex;
          align-items: center;
          gap: 10px;
          padding: 0 14px;
          background: linear-gradient(
            to bottom,
            transparent 0 30%,
            var(--r-bg) 30% 100%
          );
          border-left: 4px solid var(--r-dark);
        }
      }

      .strip-grade {
        flex-shrink: 0;
        width: 30px;
        height: 30px;
        border-radius: 3px;
        background: var(--r-red);
        display: flex;
        align-items: center;
        justify-content: center;
        font-family: 'Playfair Display', Georgia, serif;
        font-size: 17px;
        font-weight: 900;
        color: white;
        line-height: 1;
        position: relative;
        z-index: 1;
      }

      .strip-grade.strip-pending {
        background: color-mix(in srgb, var(--r-dark) 12%, transparent);
        color: var(--r-text-muted);
        font-family: Georgia, serif;
      }

      .strip-title {
        flex: 1;
        font-size: 13px;
        font-weight: 700;
        color: var(--r-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        position: relative;
        z-index: 1;
      }

      .strip-pct {
        flex-shrink: 0;
        font-size: 12px;
        font-weight: 700;
        color: var(--r-accent);
        font-family: 'Playfair Display', Georgia, serif;
        position: relative;
        z-index: 1;
      }

      .strip-qs {
        flex-shrink: 0;
        font-size: 10px;
        font-weight: 600;
        letter-spacing: 0.04em;
        color: var(--r-text-muted);
        background: color-mix(in srgb, var(--r-dark) 8%, transparent);
        border: 1px solid var(--r-border);
        border-radius: 3px;
        padding: 2px 5px;
        position: relative;
        z-index: 1;
      }

      /* ══════════════════════════════════════
         TILE  <400 × ≥170
      ══════════════════════════════════════ */
      @container fitted-card (max-width: 399px) and (min-height: 170px) {
        .tile-fmt {
          display: flex;
          flex-direction: column;
        }
      }

      .tile-hd {
        background: linear-gradient(
          to bottom,
          rgba(26, 16, 8, 0.18),
          rgba(26, 16, 8, 0.9)
        );
        padding: 10px 13px 8px;
        display: flex;
        flex-direction: column;
        gap: 4px;
        flex-shrink: 0;
        position: relative;
        z-index: 1;
      }

      .tile-eyebrow {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 8px;
        font-weight: 700;
        letter-spacing: 0.2em;
        color: var(--r-gold);
        text-transform: uppercase;
      }

      .tile-rule {
        flex: 1;
        height: 1px;
        background: color-mix(in srgb, var(--r-gold) 35%, transparent);
      }

      .tile-name {
        font-size: 12px;
        font-weight: 700;
        color: var(--r-bg);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .tile-body {
        flex: 1;
        background: linear-gradient(
          to bottom,
          transparent 0 8%,
          var(--r-bg) 32% 100%
        );
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 5px;
        padding: 10px;
        position: relative;
        z-index: 1;
      }

      .tile-grade {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: clamp(44px, 16cqh, 76px);
        font-weight: 900;
        color: var(--r-red);
        line-height: 0.88;
        letter-spacing: -0.02em;
      }

      .tile-score-row {
        display: flex;
        align-items: baseline;
        gap: 7px;
      }

      .tile-pct {
        font-size: 14px;
        font-weight: 700;
        color: var(--r-text);
        font-family: 'Playfair Display', Georgia, serif;
      }

      .tile-pts {
        font-size: 10px;
        color: var(--r-text-muted);
      }

      .tile-pending {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 5px;
        color: var(--r-text-muted);
        font-size: 11px;
        font-style: italic;
      }

      .tile-ft {
        background: var(--r-dark);
        padding: 5px 13px;
        font-size: 9px;
        font-weight: 700;
        letter-spacing: 0.12em;
        color: rgba(244, 232, 196, 0.45);
        text-transform: uppercase;
        flex-shrink: 0;
        position: relative;
        z-index: 1;
      }

      /* ══════════════════════════════════════
         CARD  ≥400 × ≥170
      ══════════════════════════════════════ */
      @container fitted-card (min-width: 400px) and (min-height: 170px) {
        .card-fmt {
          display: flex;
          flex-direction: row;
        }
      }

      .card-panel {
        width: 33%;
        flex-shrink: 0;
        background: linear-gradient(
          to bottom,
          rgba(26, 16, 8, 0.18),
          rgba(26, 16, 8, 0.92)
        );
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 3px;
        padding: 18px 12px;
        position: relative;
      }

      .card-panel::after {
        content: '';
        position: absolute;
        top: 20px;
        bottom: 20px;
        right: 0;
        width: 1px;
        background: linear-gradient(
          to bottom,
          transparent,
          color-mix(in srgb, var(--r-gold) 55%, transparent),
          transparent
        );
      }

      .card-panel-label {
        font-size: 8px;
        font-weight: 700;
        letter-spacing: 0.22em;
        color: var(--r-gold);
        opacity: 0.75;
        margin-bottom: 4px;
      }

      .card-grade {
        font-family: 'Playfair Display', Georgia, serif;
        font-size: clamp(48px, 13cqw, 84px);
        font-weight: 900;
        color: white;
        line-height: 0.85;
        letter-spacing: -0.03em;
        text-shadow: 0 2px 14px rgba(0, 0, 0, 0.45);
      }

      .card-pct {
        font-size: 13px;
        font-weight: 700;
        color: color-mix(in srgb, var(--r-red) 60%, white 40%);
        margin-top: 5px;
      }

      .card-pts {
        font-size: 10px;
        color: rgba(244, 232, 196, 0.4);
        letter-spacing: 0.03em;
      }

      .card-pending-icon {
        color: rgba(244, 232, 196, 0.28);
        margin: 6px 0;
      }

      .card-pending-label {
        font-size: 11px;
        color: rgba(244, 232, 196, 0.38);
        font-style: italic;
      }

      .card-body {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 5px;
        padding: 16px 18px;
        background: linear-gradient(
          to bottom,
          transparent 0 8%,
          var(--r-bg) 32% 100%
        );
        min-width: 0;
        justify-content: center;
        position: relative;
        overflow: hidden;
      }

      .card-eyebrow,
      .card-title,
      .card-meta,
      .card-bar {
        position: relative;
        z-index: 1;
      }

      .card-eyebrow {
        display: flex;
        align-items: center;
        gap: 8px;
        margin-bottom: 2px;
      }

      .card-rule {
        width: 16px;
        height: 1.5px;
        background: var(--r-gold);
        flex-shrink: 0;
      }

      .card-eyebrow-text {
        font-size: 8px;
        font-weight: 700;
        letter-spacing: 0.2em;
        color: var(--r-text-muted);
      }

      .card-title {
        font-size: 14px;
        font-weight: 700;
        color: var(--r-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        line-height: 1.2;
        font-family: 'Playfair Display', Georgia, serif;
      }

      .card-meta {
        font-size: 10px;
        color: var(--r-text-muted);
        font-weight: 500;
      }

      .card-bar {
        margin-top: 7px;
        --boxel-progress-bar-fill-color: var(--r-red);
        --boxel-progress-bar-background-color: color-mix(
          in srgb,
          var(--r-dark) 12%,
          transparent
        );
        --boxel-progress-bar-border-radius: 2px;
      }
    </style>
  </template>
}

export class HomeworkGrader extends CardDef {
  static displayName = 'Homework Grader';
  static icon = BookOpenIcon;
  static prefersWideFormat = true;

  @field instructions = contains(TextAreaField);
  @field questions = containsMany(QuestionField);
  @field grade = contains(GradeField);
  @field gradingSkill = linksTo(() => Skill);

  static isolated = HomeworkIsolated;
  static embedded = HomeworkIsolated;
  static fitted = HomeworkFitted;
}
