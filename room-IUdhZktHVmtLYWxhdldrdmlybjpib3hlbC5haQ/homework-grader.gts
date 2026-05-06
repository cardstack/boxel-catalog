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
          flex-direction: column;
          gap: 20px;
          font-family:
            -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', sans-serif;
        }

        .grade-circle {
          flex-shrink: 0;
          width: 48px;
          height: 48px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 20px;
          font-weight: 800;
          color: white;
          background: linear-gradient(135deg, #2563eb 0%, #7c3aed 100%);
        }

        .grade-circle.grade-A {
          background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        }

        .grade-circle.grade-B {
          background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
        }

        .grade-circle.grade-C {
          background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
        }

        .grade-circle.grade-D,
        .grade-circle.grade-E,
        .grade-circle.grade-F {
          background: linear-gradient(135deg, #ef4444 0%, #b91c1c 100%);
        }

        .details-column {
          display: flex;
          flex-direction: column;
          gap: 16px;
          flex: 1;
        }

        .feedback-row {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }

        .detail-label {
          font-size: 11px;
          font-weight: 600;
          color: #64748b;
          text-transform: uppercase;
          letter-spacing: 0.07em;
          white-space: nowrap;
        }

        .feedback-content {
          flex: 1;
          font-size: 14px;
          line-height: 1.75;
          color: #1e293b;
        }

        .feedback-content :deep(.markdown-content) {
          display: flex;
          flex-direction: column;
          gap: 14px;
        }

        .feedback-content :deep(.markdown-content h1),
        .feedback-content :deep(.markdown-content h2),
        .feedback-content :deep(.markdown-content h3) {
          font-size: 15px;
          font-weight: 700;
          color: #0f172a;
          margin: 0;
          padding-bottom: 8px;
          border-bottom: 1px solid #e2e8f0;
        }

        .feedback-content :deep(.markdown-content h4) {
          font-size: 13px;
          font-weight: 600;
          color: #334155;
          margin: 0;
        }

        .feedback-content :deep(.markdown-content p) {
          margin: 0;
          font-size: 14px;
          line-height: 1.75;
          color: #334155;
        }

        .feedback-content :deep(.markdown-content strong) {
          color: #0f172a;
          font-weight: 700;
        }

        .feedback-content :deep(.markdown-content em) {
          color: #475569;
        }

        .feedback-content :deep(.markdown-content ul),
        .feedback-content :deep(.markdown-content ol) {
          padding-left: 20px;
          margin: 0;
          display: flex;
          flex-direction: column;
          gap: 5px;
        }

        .feedback-content :deep(.markdown-content li) {
          font-size: 14px;
          line-height: 1.65;
          color: #334155;
        }

        .feedback-content :deep(.markdown-content blockquote) {
          border-left: 3px solid #2563eb;
          padding: 8px 14px;
          background: #eff6ff;
          border-radius: 0 6px 6px 0;
          margin: 0;
          color: #1e40af;
          font-style: italic;
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

  get scoreRingStyle() {
    const circ = 326.73;
    const offset = circ * (1 - this.percentage / 100);
    return htmlSafe(`stroke-dashoffset: ${offset}`);
  }

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
    <article class='hw-app'>

      {{! Answer-update floating toast }}
      {{#if this.showAnswerUpdateToast}}
        <aside class='hw-answer-toast-wrapper' aria-live='polite'>
          <section class='hw-answer-toast'>
            <header class='hw-answer-toast-top'>
              <span class='hw-answer-toast-icon'>✎</span>
              <div class='hw-answer-toast-text'>
                <h2 class='hw-answer-toast-title'>Answers Updated</h2>
                <p class='hw-answer-toast-sub'>Would you like to re-grade?</p>
              </div>
              <IconButton
                class='hw-answer-toast-close'
                @icon={{CloseIcon}}
                @size='small'
                {{on 'click' this.dismissAnswerUpdateToast}}
              />
            </header>
            <Button
              class='hw-answer-toast-regrade {{if this.isGrading "is-loading"}}'
              @kind='primary'
              @size='small'
              @disabled={{this.isGrading}}
              {{on 'click' this.gradeFromToast}}
            >
              <span class='hw-btn-icon'>↺</span>
              {{if this.isGrading 'Grading…' 'Re-grade now'}}
            </Button>
          </section>
        </aside>
      {{/if}}

      {{! Grade notification toast }}
      {{#if this.showToast}}
        <aside class='hw-grade-toast' aria-live='polite'>
          <div class='hw-toast-badge'>
            <span class='hw-toast-letter'>{{this.toastGrade}}</span>
          </div>
          <div class='hw-toast-copy'>
            <p class='hw-toast-eyebrow'>Assignment Graded</p>
            <p class='hw-toast-grade'>Grade:
              <strong>{{this.toastGrade}}</strong></p>
          </div>
          <IconButton
            class='hw-toast-close'
            @icon={{CloseIcon}}
            @size='small'
            {{on 'click' this.dismissGradeNotification}}
          />
        </aside>
      {{/if}}

      <div class='hw-layout'>

        {{! Sidebar }}
        <aside class='hw-sidebar'>
          <div class='hw-sidebar-top'>
            <div class='hw-sidebar-brand'>
              <div class='hw-brand-icon'>
                <BookOpenIcon width='18' height='18' />
              </div>
              <div class='hw-brand-text'>
                <h1 class='hw-brand-title'>{{@model.cardTitle}}</h1>
                <p class='hw-brand-sub'>Homework Grader</p>
              </div>
            </div>

            <nav class='hw-sidebar-nav'>
              <Button
                class='hw-nav-btn
                  {{if (eq this.activeTab "overview") "is-active"}}'
                @kind='text-only'
                @size='small'
                {{on 'click' (fn this.setTab 'overview')}}
              >
                <svg
                  width='16'
                  height='16'
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
                Overview
              </Button>
              <Button
                class='hw-nav-btn
                  {{if (eq this.activeTab "questions") "is-active"}}'
                @kind='text-only'
                @size='small'
                {{on 'click' (fn this.setTab 'questions')}}
              >
                <svg
                  width='16'
                  height='16'
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
                Questions
              </Button>
              <Button
                class='hw-nav-btn
                  {{if (eq this.activeTab "feedback") "is-active"}}'
                @kind='text-only'
                @size='small'
                {{on 'click' (fn this.setTab 'feedback')}}
              >
                <svg
                  width='16'
                  height='16'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                ><path
                    d='M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z'
                  /></svg>
                Feedback
              </Button>
            </nav>
          </div>

          <div class='hw-sidebar-bottom'>
            {{#if this.sidebarBackgroundURL}}
              <img
                class='hw-sidebar-thumb'
                src={{this.sidebarBackgroundURL}}
                alt=''
                aria-hidden='true'
              />
            {{/if}}
            <div class='hw-sidebar-cta'>
              <p class='hw-cta-title'>Keep improving!</p>
              <p class='hw-cta-body'>Review your feedback and re-grade to boost
                your score.</p>
              {{#if @model.gradingSkill}}
                <Button
                  class='hw-cta-btn {{if this.isGrading "is-loading"}}'
                  @kind='primary'
                  @size='small'
                  @disabled={{this.isGrading}}
                  {{on 'click' this.grade}}
                >
                  <span class='hw-btn-icon'>↺</span>
                  {{if
                    this.isGrading
                    'Grading…'
                    (if this.hasGrade 'Re-grade Assignment' 'Grade Homework')
                  }}
                </Button>
              {{/if}}
            </div>
          </div>
        </aside>

        {{! Main body }}
        <div class='hw-body'>

          <header class='hw-topbar'>
            <div class='hw-topbar-titles'>
              <h2 class='hw-topbar-heading'>
                {{if (eq this.activeTab 'overview') 'Overview'}}
                {{if (eq this.activeTab 'questions') 'Questions'}}
                {{if (eq this.activeTab 'feedback') 'Feedback'}}
              </h2>
              <p class='hw-topbar-sub'>
                {{if
                  (eq this.activeTab 'overview')
                  'See your results and feedback summary'
                }}
                {{if
                  (eq this.activeTab 'questions')
                  'Answer each question below'
                }}
                {{if
                  (eq this.activeTab 'feedback')
                  'Detailed feedback from your grader'
                }}
              </p>
            </div>
            {{#if @model.gradingSkill}}
              <Button
                class='hw-grade-btn {{if this.isGrading "is-loading"}}'
                @kind='primary'
                @size='small'
                @disabled={{this.isGrading}}
                {{on 'click' this.grade}}
              >
                <span class='hw-btn-icon'>↺</span>
                {{if
                  this.isGrading
                  'Grading…'
                  (if this.hasGrade 'Re-grade Assignment' 'Grade Homework')
                }}
              </Button>
            {{/if}}
          </header>

          {{#if this.isGradeStale}}
            <aside class='hw-stale-banner'>
              <span>⚠</span>
              <p>Answers updated — click
                <strong>Re-grade</strong>
                for a fresh score.</p>
            </aside>
          {{/if}}

          <main class='hw-main'>

            {{! OVERVIEW TAB }}
            {{#if (eq this.activeTab 'overview')}}

              {{#if this.hasGrade}}
                <section class='hw-score-card'>
                  <div class='hw-score-left'>
                    <div class='hw-score-ring-wrap'>
                      <svg class='hw-score-ring' viewBox='0 0 120 120'>
                        <circle class='hw-ring-track' cx='60' cy='60' r='52' />
                        <circle
                          class='hw-ring-fill'
                          cx='60'
                          cy='60'
                          r='52'
                          style={{this.scoreRingStyle}}
                        />
                      </svg>
                      <div class='hw-score-inner'>
                        <span
                          class='hw-score-grade-letter'
                        >{{@model.grade.overallGrade}}</span>
                      </div>
                    </div>
                    <div class='hw-score-info'>
                      <p class='hw-score-num'>
                        <strong>{{this.totalPoints}}</strong><span
                          class='hw-score-denom'
                        >
                          /
                          {{this.maxPoints}}</span>
                      </p>
                      {{#if this.gradeVerdict}}
                        <p class='hw-score-verdict'>{{this.gradeVerdict}}</p>
                      {{/if}}
                      {{#if @model.grade.overallFeedback}}
                        <p
                          class='hw-score-summary'
                        >{{@model.grade.overallFeedback}}</p>
                      {{/if}}
                    </div>
                  </div>
                  <div class='hw-score-divider'></div>
                  <section class='hw-breakdown' aria-label='Score breakdown'>
                    <h3 class='hw-breakdown-heading'>Score Breakdown</h3>
                    {{#each @model.grade.questionPoints as |pts qi|}}
                      <div class='hw-bd-row'>
                        <span class='hw-bd-label'>Q{{add qi 1}}.
                          {{this.getQuestionTitle qi}}</span>
                        <div class='hw-bd-track'>
                          <div
                            class='hw-bd-fill'
                            style={{this.getBreakdownBarStyle qi}}
                          ></div>
                        </div>
                        <span class='hw-bd-score'>{{pts}}
                          /
                          {{this.getMaxForQuestion qi}}</span>
                      </div>
                    {{/each}}
                    <div class='hw-bd-total'>
                      <span class='hw-bd-total-label'>Total Score</span>
                      <span class='hw-bd-total-score'>{{this.totalPoints}}
                        /
                        {{this.maxPoints}}</span>
                    </div>
                  </section>
                </section>

                {{#if @model.grade.overallFeedback}}
                  <section class='hw-feedback-preview'>
                    <div class='hw-feedback-preview-icon'>
                      <svg
                        width='16'
                        height='16'
                        viewBox='0 0 24 24'
                        fill='currentColor'
                      ><polygon
                          points='12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2'
                        /></svg>
                    </div>
                    <div class='hw-feedback-preview-body'>
                      <h3 class='hw-feedback-preview-title'>Feedback Summary</h3>
                      <p
                        class='hw-feedback-preview-text'
                      >{{@model.grade.overallFeedback}}</p>
                    </div>
                    <Button
                      class='hw-view-feedback-btn'
                      @kind='secondary'
                      @size='small'
                      {{on 'click' (fn this.setTab 'feedback')}}
                    >View Full Feedback →</Button>
                  </section>
                {{/if}}

              {{else}}
                <section class='hw-pending'>
                  <div class='hw-pending-icon'>✎</div>
                  <div>
                    <h2 class='hw-pending-title'>Not yet graded</h2>
                    {{#if @model.gradingSkill}}
                      <p class='hw-pending-hint'>Complete your answers and click
                        <em>Grade Homework</em></p>
                    {{/if}}
                  </div>
                </section>
              {{/if}}

              <section class='hw-questions-overview'>
                <h3 class='hw-section-title'>Questions</h3>
                {{#each @model.questions as |_question qi|}}
                  <Button
                    class='hw-q-item'
                    @kind='text-only'
                    @size='small'
                    {{on 'click' (fn this.setTab 'questions')}}
                  >
                    <div class='hw-q-num'>{{add qi 1}}</div>
                    <div class='hw-q-meta'>
                      <span class='hw-q-name'>{{this.getQuestionTitle
                          qi
                        }}</span>
                      {{#let (this.getPointsDisplay qi) as |pts|}}
                        {{#if pts.hasEarned}}
                          <span class='hw-q-hint'>{{this.getQuestionHint
                              qi
                            }}</span>
                        {{/if}}
                      {{/let}}
                    </div>
                    {{#let (this.getPointsDisplay qi) as |pts|}}
                      <span
                        class='hw-q-pts
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
                    <span class='hw-q-arrow'>›</span>
                  </Button>
                {{/each}}
              </section>

            {{/if}}

            {{! QUESTIONS TAB }}
            {{#if (eq this.activeTab 'questions')}}
              <section class='hw-questions-full'>

                {{#if this.hasGrade}}
                  <div class='hw-q-score-strip'>
                    <div
                      class='hw-q-strip-badge'
                    >{{@model.grade.overallGrade}}</div>
                    <div class='hw-q-strip-info'>
                      <span class='hw-q-strip-pts'>{{this.totalPoints}}
                        /
                        {{this.maxPoints}}
                        pts</span>
                      <span class='hw-q-strip-pct'>{{this.percentage}}%</span>
                    </div>
                    <div class='hw-q-strip-sep'></div>
                    <p class='hw-q-strip-verdict'>{{this.gradeVerdict}}</p>
                  </div>
                {{/if}}

                {{#if @model.instructions}}
                  <section class='hw-instructions'>
                    <h3 class='hw-instr-label'>Instructions</h3>
                    <p class='hw-instr-body'>{{@model.instructions}}</p>
                  </section>
                {{/if}}

                {{#each @model.questions as |_question qi|}}
                  <article class='hw-question-card'>
                    <div class='hw-question-header'>
                      <div class='hw-q-num'>{{add qi 1}}</div>
                      <h3 class='hw-question-title'>{{this.getQuestionTitle
                          qi
                        }}</h3>
                      {{#let (this.getPointsDisplay qi) as |pts|}}
                        {{#if pts.hasEarned}}
                          <span
                            class='hw-question-pts
                              {{if (eq pts.earned pts.max) "full" "partial"}}'
                          >{{pts.earned}}/{{pts.max}}</span>
                        {{else}}
                          <span class='hw-question-max'>{{pts.max}} pts</span>
                        {{/if}}
                      {{/let}}
                    </div>
                    <div class='hw-question-body'>
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

            {{! FEEDBACK TAB }}
            {{#if (eq this.activeTab 'feedback')}}
              <section class='hw-feedback-full'>
                {{#if this.hasGrade}}
                  <div class='hw-feedback-header'>
                    <div class='hw-feedback-grade-badge'>
                      {{@model.grade.overallGrade}}
                    </div>
                    <div class='hw-feedback-grade-meta'>
                      <span class='hw-feedback-score'>{{this.totalPoints}}
                        /
                        {{this.maxPoints}}
                        pts</span>
                      <span class='hw-feedback-pct'>{{this.percentage}}% ·
                        {{this.gradeVerdict}}</span>
                    </div>
                  </div>
                  <div class='hw-feedback-content'>
                    <@fields.grade />
                  </div>
                {{else}}
                  <p class='hw-no-feedback'>No feedback yet — grade your
                    homework first.</p>
                {{/if}}
              </section>
            {{/if}}

          </main>
        </div>
      </div>

    </article>

    <style scoped>
      /* ── Design tokens + base ── */
      .hw-app {
        --c-blue: #2563eb;
        --c-blue-hover: #1d4ed8;
        --c-blue-bg: #eff6ff;
        --c-blue-border: #bfdbfe;
        --c-blue-muted: #93c5fd;
        --c-bg: #f1f5f9;
        --c-white: #ffffff;
        --c-text: #0f172a;
        --c-text-2: #1e293b;
        --c-muted: #64748b;
        --c-border: #e2e8f0;
        --c-border-2: #cbd5e1;
        --c-success: #10b981;
        --c-danger: #ef4444;
        --c-warn: #f59e0b;
        --c-shadow:
          0 1px 3px rgba(0, 0, 0, 0.07), 0 1px 2px rgba(0, 0, 0, 0.04);
        --c-shadow-md:
          0 4px 12px rgba(0, 0, 0, 0.08), 0 2px 4px rgba(0, 0, 0, 0.04);

        min-height: 100%;
        display: flex;
        flex-direction: column;
        background: var(--c-bg);
        font-family:
          -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Roboto,
          sans-serif;
        color: var(--c-text);
        font-size: 14px;
        line-height: 1.5;
        position: relative;
      }

      .hw-layout {
        display: flex;
        flex: 1;
        min-height: 0;
      }

      /* ── Sidebar ── */
      .hw-sidebar {
        width: 220px;
        flex-shrink: 0;
        background: var(--c-white);
        border-right: 1px solid var(--c-border);
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }

      .hw-sidebar-top {
        flex: 1;
        display: flex;
        flex-direction: column;
        overflow-y: auto;
      }

      .hw-sidebar-brand {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 18px 16px 14px;
        border-bottom: 1px solid var(--c-border);
      }

      .hw-brand-icon {
        width: 34px;
        height: 34px;
        border-radius: 8px;
        background: var(--c-blue);
        color: white;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }

      .hw-brand-text {
        min-width: 0;
      }

      .hw-brand-title {
        font-size: 13px;
        font-weight: 700;
        color: var(--c-text);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        margin: 0;
        line-height: 1.3;
      }

      .hw-brand-sub {
        font-size: 11px;
        color: var(--c-muted);
        margin: 0;
        line-height: 1.3;
      }

      .hw-sidebar-nav {
        padding: 10px 8px;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .hw-nav-btn {
        --boxel-button-border-radius: 8px;
        --boxel-button-font: 500 13px -apple-system, 'Segoe UI', sans-serif;
        --boxel-button-padding: 0;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;
        --boxel-button-text-color: var(--c-muted);
        --boxel-button-color: transparent;

        display: flex;
        align-items: center;
        gap: 10px;
        width: 100%;
        padding: 9px 10px;
        border-radius: 8px;
        font-size: 13px;
        font-weight: 500;
        color: var(--c-muted);
        background: transparent;
        border: none;
        cursor: pointer;
        text-align: left;
        transition:
          background 0.15s,
          color 0.15s;
        text-transform: none;
        letter-spacing: 0;
      }

      .hw-nav-btn:hover {
        background: var(--c-bg);
        color: var(--c-text-2);
      }

      .hw-nav-btn.is-active {
        background: var(--c-blue-bg);
        color: var(--c-blue);
        font-weight: 600;
      }

      .hw-nav-btn svg {
        flex-shrink: 0;
        opacity: 0.7;
      }

      .hw-nav-btn.is-active svg {
        opacity: 1;
      }

      .hw-sidebar-bottom {
        border-top: 1px solid var(--c-border);
        flex-shrink: 0;
      }

      .hw-sidebar-thumb {
        width: 100%;
        height: 120px;
        object-fit: cover;
        display: block;
      }

      .hw-sidebar-cta {
        padding: 14px 16px;
        display: flex;
        flex-direction: column;
        gap: 5px;
      }

      .hw-cta-title {
        font-size: 13px;
        font-weight: 700;
        color: var(--c-text);
        margin: 0;
      }

      .hw-cta-body {
        font-size: 11px;
        color: var(--c-muted);
        line-height: 1.5;
        margin: 0;
      }

      .hw-cta-btn {
        --boxel-button-border-radius: 8px;
        --boxel-button-font: 600 12px -apple-system, sans-serif;
        --boxel-button-padding: 8px 14px;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;

        margin-top: 6px;
        width: 100%;
        justify-content: center;
        gap: 6px;
      }

      .hw-cta-btn.is-loading .hw-btn-icon {
        display: inline-block;
        animation: hw-spin 1s linear infinite;
      }

      /* ── Main body ── */
      .hw-body {
        flex: 1;
        display: flex;
        flex-direction: column;
        min-width: 0;
        overflow: hidden;
      }

      .hw-topbar {
        background: var(--c-white);
        border-bottom: 1px solid var(--c-border);
        padding: 16px 24px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        flex-shrink: 0;
      }

      .hw-topbar-titles {
        min-width: 0;
      }

      .hw-topbar-heading {
        font-size: 20px;
        font-weight: 700;
        color: var(--c-text);
        margin: 0;
        line-height: 1.2;
      }

      .hw-topbar-sub {
        font-size: 13px;
        color: var(--c-muted);
        margin: 2px 0 0;
      }

      .hw-grade-btn {
        --boxel-button-border-radius: 8px;
        --boxel-button-font: 600 13px -apple-system, sans-serif;
        --boxel-button-padding: 9px 18px;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;

        flex-shrink: 0;
        gap: 6px;
        white-space: nowrap;
      }

      .hw-grade-btn.is-loading .hw-btn-icon {
        display: inline-block;
        animation: hw-spin 1s linear infinite;
      }

      @keyframes hw-spin {
        from {
          transform: rotate(0deg);
        }
        to {
          transform: rotate(360deg);
        }
      }

      .hw-btn-icon {
        font-size: 14px;
        line-height: 1;
      }

      .hw-stale-banner {
        display: flex;
        align-items: center;
        gap: 8px;
        background: #fffbeb;
        border-bottom: 1px solid #fde68a;
        padding: 8px 24px;
        font-size: 13px;
        color: #78350f;
        flex-shrink: 0;
      }

      .hw-main {
        flex: 1;
        padding: 20px 24px;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 16px;
        min-height: 0;
      }

      /* ── Score card ── */
      .hw-score-card {
        background: var(--c-white);
        border: 1px solid var(--c-border);
        border-radius: 12px;
        display: flex;
        flex-wrap: wrap;
        overflow: hidden;
        box-shadow: var(--c-shadow);
      }

      .hw-score-left {
        padding: 24px 28px;
        display: flex;
        align-items: center;
        gap: 24px;
        flex: 1;
        min-width: 240px;
      }

      .hw-score-ring-wrap {
        position: relative;
        width: 110px;
        height: 110px;
        flex-shrink: 0;
      }

      .hw-score-ring {
        width: 110px;
        height: 110px;
        transform: rotate(-90deg);
      }

      .hw-ring-track {
        fill: none;
        stroke: #e2e8f0;
        stroke-width: 8;
      }

      .hw-ring-fill {
        fill: none;
        stroke: var(--c-blue);
        stroke-width: 8;
        stroke-linecap: round;
        stroke-dasharray: 326.73;
        transition: stroke-dashoffset 0.6s cubic-bezier(0.4, 0, 0.2, 1);
      }

      .hw-score-inner {
        position: absolute;
        inset: 0;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .hw-score-grade-letter {
        font-size: 30px;
        font-weight: 800;
        color: var(--c-blue);
        line-height: 1;
      }

      .hw-score-info {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .hw-score-num {
        font-size: 28px;
        font-weight: 800;
        color: var(--c-text);
        line-height: 1;
        margin: 0;
      }

      .hw-score-denom {
        font-size: 16px;
        font-weight: 400;
        color: var(--c-muted);
      }

      .hw-score-verdict {
        font-size: 15px;
        font-weight: 600;
        color: var(--c-blue);
        margin: 0;
      }

      .hw-score-summary {
        font-size: 13px;
        line-height: 1.55;
        color: var(--c-muted);
        margin: 0;
        max-width: 30ch;
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
      }

      .hw-score-divider {
        width: 1px;
        background: var(--c-border);
        flex-shrink: 0;
        margin: 20px 0;
      }

      .hw-breakdown {
        padding: 20px 24px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        min-width: 200px;
        flex: 1;
        justify-content: center;
      }

      .hw-breakdown-heading {
        font-size: 12px;
        font-weight: 600;
        color: var(--c-muted);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        margin: 0 0 4px;
      }

      .hw-bd-row {
        display: grid;
        grid-template-columns: 1fr 80px 52px;
        align-items: center;
        gap: 8px;
      }

      .hw-bd-label {
        font-size: 12px;
        color: var(--c-text-2);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .hw-bd-track {
        height: 6px;
        border-radius: 3px;
        background: var(--c-border);
        overflow: hidden;
      }

      .hw-bd-fill {
        height: 100%;
        background: var(--c-blue);
        border-radius: 3px;
        transition: width 0.4s ease;
      }

      .hw-bd-score {
        font-size: 12px;
        color: var(--c-muted);
        text-align: right;
        white-space: nowrap;
      }

      .hw-bd-total {
        display: flex;
        justify-content: space-between;
        align-items: center;
        border-top: 1px solid var(--c-border);
        padding-top: 10px;
        margin-top: 2px;
      }

      .hw-bd-total-label {
        font-size: 12px;
        font-weight: 600;
        color: var(--c-text-2);
      }

      .hw-bd-total-score {
        font-size: 14px;
        font-weight: 700;
        color: var(--c-blue);
      }

      /* ── Pending state ── */
      .hw-pending {
        background: var(--c-white);
        border: 1px solid var(--c-border);
        border-radius: 12px;
        padding: 28px 24px;
        display: flex;
        align-items: center;
        gap: 20px;
        box-shadow: var(--c-shadow);
      }

      .hw-pending-icon {
        font-size: 30px;
        color: var(--c-border-2);
        line-height: 1;
        flex-shrink: 0;
      }

      .hw-pending-title {
        font-size: 15px;
        font-weight: 600;
        color: var(--c-text-2);
        margin: 0;
      }

      .hw-pending-hint {
        font-size: 13px;
        color: var(--c-muted);
        margin: 4px 0 0;
      }

      /* ── Feedback preview card ── */
      .hw-feedback-preview {
        background: var(--c-blue-bg);
        border: 1px solid var(--c-blue-border);
        border-radius: 12px;
        padding: 18px 20px;
        display: flex;
        align-items: flex-start;
        gap: 14px;
        box-shadow: var(--c-shadow);
      }

      .hw-feedback-preview-icon {
        width: 32px;
        height: 32px;
        border-radius: 8px;
        background: var(--c-blue);
        color: white;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        margin-top: 1px;
      }

      .hw-feedback-preview-body {
        flex: 1;
        min-width: 0;
      }

      .hw-feedback-preview-title {
        font-size: 13px;
        font-weight: 600;
        color: var(--c-text);
        margin: 0 0 6px;
      }

      .hw-feedback-preview-text {
        font-size: 13px;
        line-height: 1.6;
        color: var(--c-text-2);
        margin: 0;
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
      }

      .hw-view-feedback-btn {
        --boxel-button-border-radius: 8px;
        --boxel-button-font: 500 12px -apple-system, sans-serif;
        --boxel-button-padding: 7px 14px;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;

        flex-shrink: 0;
        align-self: flex-end;
        white-space: nowrap;
      }

      /* ── Questions overview list ── */
      .hw-questions-overview {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .hw-section-title {
        font-size: 15px;
        font-weight: 700;
        color: var(--c-text);
        margin: 0 0 4px;
      }

      .hw-q-item {
        --boxel-button-border-radius: 10px;
        --boxel-button-color: var(--c-white);
        --boxel-button-text-color: var(--c-text);
        --boxel-button-padding: 0;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;
        --boxel-button-font: 400 14px -apple-system, sans-serif;

        display: flex;
        align-items: center;
        gap: 12px;
        background: var(--c-white);
        border: 1px solid var(--c-border);
        border-radius: 10px;
        padding: 12px 16px;
        cursor: pointer;
        text-align: left;
        width: 100%;
        transition:
          border-color 0.15s,
          box-shadow 0.15s;
        box-shadow: var(--c-shadow);
      }

      .hw-q-item:hover {
        border-color: var(--c-blue-border);
        box-shadow:
          var(--c-shadow),
          0 0 0 3px var(--c-blue-bg);
      }

      .hw-q-num {
        width: 30px;
        height: 30px;
        border-radius: 50%;
        background: var(--c-blue);
        color: white;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 13px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .hw-q-meta {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
      }

      .hw-q-name {
        font-size: 14px;
        font-weight: 600;
        color: var(--c-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .hw-q-hint {
        font-size: 12px;
        color: var(--c-muted);
      }

      .hw-q-pts {
        font-size: 13px;
        font-weight: 600;
        color: var(--c-muted);
        white-space: nowrap;
        flex-shrink: 0;
      }

      .hw-q-pts.full {
        color: var(--c-success);
      }

      .hw-q-pts.partial {
        color: var(--c-blue);
      }

      .hw-q-pts strong {
        color: inherit;
      }

      .hw-q-arrow {
        font-size: 18px;
        color: var(--c-border-2);
        line-height: 1;
        flex-shrink: 0;
      }

      /* ── Questions full tab ── */
      .hw-questions-full {
        display: flex;
        flex-direction: column;
        gap: 14px;
      }

      .hw-q-score-strip {
        background: var(--c-blue);
        border-radius: 10px;
        padding: 12px 18px;
        display: flex;
        align-items: center;
        gap: 14px;
      }

      .hw-q-strip-badge {
        width: 40px;
        height: 40px;
        border-radius: 50%;
        background: white;
        color: var(--c-blue);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 17px;
        font-weight: 800;
        flex-shrink: 0;
      }

      .hw-q-strip-info {
        display: flex;
        flex-direction: column;
        gap: 1px;
      }

      .hw-q-strip-pts {
        font-size: 15px;
        font-weight: 700;
        color: white;
        line-height: 1;
      }

      .hw-q-strip-pct {
        font-size: 12px;
        color: rgba(255, 255, 255, 0.7);
        font-weight: 500;
      }

      .hw-q-strip-sep {
        width: 1px;
        height: 30px;
        background: rgba(255, 255, 255, 0.25);
        flex-shrink: 0;
      }

      .hw-q-strip-verdict {
        font-size: 14px;
        color: rgba(255, 255, 255, 0.85);
        font-style: italic;
        margin: 0;
      }

      .hw-instructions {
        background: #fffbeb;
        border: 1px solid #fde68a;
        border-radius: 10px;
        padding: 14px 16px;
      }

      .hw-instr-label {
        font-size: 11px;
        font-weight: 600;
        color: #92400e;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        margin: 0 0 4px;
      }

      .hw-instr-body {
        font-size: 13px;
        color: #78350f;
        line-height: 1.6;
        margin: 0;
      }

      .hw-question-card {
        background: var(--c-white);
        border: 1px solid var(--c-border);
        border-radius: 10px;
        overflow: hidden;
        box-shadow: var(--c-shadow);
      }

      .hw-question-header {
        background: var(--c-bg);
        border-bottom: 1px solid var(--c-border);
        padding: 10px 16px;
        display: flex;
        align-items: center;
        gap: 10px;
      }

      .hw-question-title {
        flex: 1;
        font-size: 14px;
        font-weight: 600;
        color: var(--c-text);
        margin: 0;
      }

      .hw-question-pts {
        font-size: 12px;
        font-weight: 700;
        color: var(--c-muted);
        padding: 2px 9px;
        border-radius: 20px;
        background: var(--c-border);
      }

      .hw-question-pts.full {
        color: var(--c-success);
        background: #ecfdf5;
      }

      .hw-question-pts.partial {
        color: var(--c-blue);
        background: var(--c-blue-bg);
      }

      .hw-question-max {
        font-size: 12px;
        color: var(--c-muted);
      }

      .hw-question-body {
        padding: 16px;
        min-height: 140px;
      }

      /* ── Feedback full tab ── */
      .hw-feedback-full {
        display: flex;
        flex-direction: column;
        gap: 14px;
      }

      .hw-feedback-header {
        display: flex;
        align-items: center;
        gap: 14px;
        padding: 16px 20px;
        background: var(--c-white);
        border: 1px solid var(--c-border);
        border-radius: 12px;
        box-shadow: var(--c-shadow);
      }

      .hw-feedback-grade-badge {
        width: 52px;
        height: 52px;
        border-radius: 50%;
        background: linear-gradient(135deg, var(--c-blue) 0%, #7c3aed 100%);
        color: white;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 22px;
        font-weight: 800;
        flex-shrink: 0;
        box-shadow: 0 2px 10px rgba(37, 99, 235, 0.3);
      }

      .hw-feedback-grade-meta {
        display: flex;
        flex-direction: column;
        gap: 3px;
      }

      .hw-feedback-score {
        font-size: 18px;
        font-weight: 700;
        color: var(--c-text);
      }

      .hw-feedback-pct {
        font-size: 13px;
        color: var(--c-muted);
      }

      .hw-feedback-content {
        background: var(--c-white);
        border: 1px solid var(--c-border);
        border-radius: 12px;
        padding: 24px 28px;
        box-shadow: var(--c-shadow);
      }

      .hw-no-feedback {
        font-size: 14px;
        color: var(--c-muted);
        font-style: italic;
        text-align: center;
        padding: 40px 0;
        margin: 0;
      }

      /* ── Grade notification toast ── */
      .hw-grade-toast {
        position: sticky;
        top: 0;
        z-index: 50;
        display: flex;
        align-items: center;
        gap: 14px;
        background: var(--c-white);
        border-bottom: 1px solid var(--c-border);
        border-left: 4px solid var(--c-blue);
        padding: 12px 20px;
        box-shadow: var(--c-shadow-md);
        animation: hw-toast-in 0.3s cubic-bezier(0.22, 1, 0.36, 1) both;
      }

      @keyframes hw-toast-in {
        from {
          opacity: 0;
          transform: translateY(-100%);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }

      .hw-toast-badge {
        width: 40px;
        height: 40px;
        border-radius: 50%;
        background: linear-gradient(135deg, var(--c-blue) 0%, #7c3aed 100%);
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }

      .hw-toast-letter {
        font-size: 17px;
        font-weight: 800;
        color: white;
        line-height: 1;
      }

      .hw-toast-copy {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 1px;
      }

      .hw-toast-eyebrow {
        font-size: 11px;
        color: var(--c-muted);
        font-weight: 500;
        margin: 0;
      }

      .hw-toast-grade {
        font-size: 14px;
        font-weight: 600;
        color: var(--c-text);
        margin: 0;
      }

      .hw-toast-close {
        flex-shrink: 0;
      }

      /* ── Answer update floating toast ── */
      .hw-answer-toast-wrapper {
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

      .hw-answer-toast {
        pointer-events: all;
        margin-top: 16px;
        background: var(--c-white);
        border: 1px solid var(--c-border);
        border-radius: 12px;
        padding: 14px 16px 12px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        box-shadow: var(--c-shadow-md);
        max-width: 256px;
        min-width: 200px;
        height: fit-content;
        animation: hw-answer-toast-in 0.25s cubic-bezier(0.22, 1, 0.36, 1) both;
      }

      @keyframes hw-answer-toast-in {
        from {
          opacity: 0;
          transform: translateX(18px);
        }
        to {
          opacity: 1;
          transform: translateX(0);
        }
      }

      .hw-answer-toast-top {
        display: flex;
        align-items: flex-start;
        gap: 10px;
      }

      .hw-answer-toast-icon {
        font-size: 16px;
        color: var(--c-blue);
        line-height: 1.3;
        flex-shrink: 0;
      }

      .hw-answer-toast-text {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
      }

      .hw-answer-toast-title {
        font-size: 13px;
        font-weight: 600;
        color: var(--c-text);
        line-height: 1.2;
        margin: 0;
      }

      .hw-answer-toast-sub {
        font-size: 11px;
        color: var(--c-muted);
        margin: 0;
      }

      .hw-answer-toast-close {
        flex-shrink: 0;
      }

      .hw-answer-toast-regrade {
        --boxel-button-border-radius: 8px;
        --boxel-button-padding: 8px 12px;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: 100%;
        --boxel-button-font: 600 12px -apple-system, sans-serif;

        justify-content: center;
        gap: 6px;
        width: 100%;
      }

      .hw-answer-toast-regrade.is-loading .hw-btn-icon {
        display: inline-block;
        animation: hw-spin 1s linear infinite;
      }
    </style>
  </template>
}

class HomeworkFitted extends Component<typeof HomeworkGrader> {
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

  get gradeClass() {
    const g = this.args.model?.grade?.overallGrade?.toUpperCase() ?? '';
    if (g.startsWith('A')) return 'grade-a';
    if (g.startsWith('B')) return 'grade-b';
    if (g.startsWith('C')) return 'grade-c';
    if (g.startsWith('D') || g.startsWith('E') || g.startsWith('F'))
      return 'grade-f';
    return '';
  }

  <template>
    <article class='hw-fitted {{this.gradeClass}}'>

      {{! ══ BADGE ≤150 × <170 ══ }}
      <section class='badge'>
        <div class='badge-seal'>
          {{#if this.hasGrade}}
            <span class='badge-letter'>{{@model.grade.overallGrade}}</span>
          {{else}}
            <BookOpenIcon class='badge-book' width='20' height='20' />
          {{/if}}
        </div>
        <span class='badge-title'>{{if
            @model.cardTitle
            @model.cardTitle
            'HW'
          }}</span>
      </section>

      {{! ══ STRIP >150 × <170 ══ }}
      <section class='strip'>
        <div class='strip-seal {{unless this.hasGrade "strip-pending"}}'>
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

      {{! ══ TILE <400 × ≥170 ══ }}
      <article class='tile'>
        <header class='tile-hd'>
          <div class='tile-brand-icon'>
            <BookOpenIcon width='14' height='14' />
          </div>
          <span class='tile-title'>{{if
              @model.cardTitle
              @model.cardTitle
              'Untitled'
            }}</span>
        </header>
        <section class='tile-body'>
          {{#if this.hasGrade}}
            <div class='tile-grade-circle'>
              <span
                class='tile-grade-letter'
              >{{@model.grade.overallGrade}}</span>
            </div>
            <p class='tile-score'>{{this.totalPoints}}/{{this.maxPoints}}
              pts</p>
            <p class='tile-pct'>{{this.percentage}}%</p>
          {{else}}
            <div class='tile-pending'>
              <ClockIcon width='20' height='20' />
              <span>Not graded</span>
            </div>
          {{/if}}
        </section>
        <footer class='tile-ft'>{{this.questionsCount}}
          question{{if (eq this.questionsCount 1) '' 's'}}</footer>
      </article>

      {{! ══ CARD ≥400 × ≥170 ══ }}
      <article class='card'>
        <div class='card-left'>
          <div class='card-grade-ring'>
            {{#if this.hasGrade}}
              <span
                class='card-grade-letter'
              >{{@model.grade.overallGrade}}</span>
            {{else}}
              <BookOpenIcon width='24' height='24' />
            {{/if}}
          </div>
          {{#if this.hasGrade}}
            <span class='card-pct'>{{this.percentage}}%</span>
            <span class='card-pts'>{{this.totalPoints}}/{{this.maxPoints}}
              pts</span>
          {{else}}
            <span class='card-pending-label'>Not graded</span>
          {{/if}}
        </div>
        <div class='card-divider'></div>
        <section class='card-body'>
          <div class='card-icon-row'>
            <div class='card-brand-icon'>
              <BookOpenIcon width='13' height='13' />
            </div>
            <span class='card-eyebrow'>Homework Grader</span>
          </div>
          <h2 class='card-title'>{{if
              @model.cardTitle
              @model.cardTitle
              'Untitled Homework'
            }}</h2>
          <p class='card-meta'>{{this.questionsCount}}
            question{{if (eq this.questionsCount 1) '' 's'}}</p>
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

    <style scoped>
      .hw-fitted {
        --c-blue: #2563eb;
        --c-blue-bg: #eff6ff;
        --c-blue-border: #bfdbfe;
        --c-bg: #f1f5f9;
        --c-white: #ffffff;
        --c-text: #0f172a;
        --c-text-2: #1e293b;
        --c-muted: #64748b;
        --c-border: #e2e8f0;
        --c-success: #10b981;
        --c-warn: #f59e0b;
        --c-danger: #ef4444;
        --c-grade: var(--c-blue);
        --c-shadow:
          0 1px 3px rgba(0, 0, 0, 0.07), 0 1px 2px rgba(0, 0, 0, 0.04);

        width: 100%;
        height: 100%;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', sans-serif;
      }

      /* Grade accent colours */
      .hw-fitted.grade-a {
        --c-grade: #10b981;
      }
      .hw-fitted.grade-b {
        --c-grade: #2563eb;
      }
      .hw-fitted.grade-c {
        --c-grade: #f59e0b;
      }
      .hw-fitted.grade-f {
        --c-grade: #ef4444;
      }

      /* ── All sub-formats hidden by default ── */
      .badge,
      .strip,
      .tile,
      .card {
        display: none;
        width: 100%;
        height: 100%;
        box-sizing: border-box;
        overflow: hidden;
      }

      /* ══════════════════════════════════════
         BADGE  ≤150 × <170
      ══════════════════════════════════════ */
      @container fitted-card (max-width: 150px) and (max-height: 169px) {
        .badge {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 6px;
          background: var(--c-bg);
          padding: 10px 8px;
        }
      }

      .badge-seal {
        width: 48px;
        height: 48px;
        border-radius: 50%;
        background: linear-gradient(
          135deg,
          var(--c-grade) 0%,
          color-mix(in srgb, var(--c-grade) 70%, #7c3aed) 100%
        );
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: var(--c-shadow);
      }

      .badge-letter {
        font-size: 24px;
        font-weight: 800;
        color: white;
        line-height: 1;
      }

      .badge-book {
        color: white;
      }

      .badge-title {
        font-size: 9px;
        font-weight: 600;
        color: var(--c-muted);
        text-align: center;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        max-width: 100%;
        letter-spacing: 0.03em;
      }

      /* ══════════════════════════════════════
         STRIP  >150 × <170
      ══════════════════════════════════════ */
      @container fitted-card (min-width: 151px) and (max-height: 169px) {
        .strip {
          display: flex;
          align-items: center;
          gap: 10px;
          padding: 0 14px;
          background: var(--c-white);
          border-left: 3px solid var(--c-grade);
        }
      }

      .strip-seal {
        flex-shrink: 0;
        width: 32px;
        height: 32px;
        border-radius: 50%;
        background: linear-gradient(
          135deg,
          var(--c-grade) 0%,
          color-mix(in srgb, var(--c-grade) 70%, #7c3aed) 100%
        );
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 14px;
        font-weight: 800;
        color: white;
        line-height: 1;
      }

      .strip-seal.strip-pending {
        background: var(--c-border);
        color: var(--c-muted);
        font-size: 16px;
      }

      .strip-title {
        flex: 1;
        font-size: 13px;
        font-weight: 600;
        color: var(--c-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .strip-pct {
        flex-shrink: 0;
        font-size: 12px;
        font-weight: 700;
        color: var(--c-grade);
      }

      .strip-qs {
        flex-shrink: 0;
        font-size: 10px;
        font-weight: 600;
        color: var(--c-muted);
        background: var(--c-bg);
        border: 1px solid var(--c-border);
        border-radius: 4px;
        padding: 2px 6px;
      }

      /* ══════════════════════════════════════
         TILE  <400 × ≥170
      ══════════════════════════════════════ */
      @container fitted-card (max-width: 399px) and (min-height: 170px) {
        .tile {
          display: flex;
          flex-direction: column;
          background: var(--c-white);
        }
      }

      .tile-hd {
        background: var(--c-white);
        border-bottom: 1px solid var(--c-border);
        padding: 10px 13px;
        display: flex;
        align-items: center;
        gap: 8px;
        flex-shrink: 0;
      }

      .tile-brand-icon {
        width: 22px;
        height: 22px;
        border-radius: 5px;
        background: var(--c-blue);
        display: flex;
        align-items: center;
        justify-content: center;
        color: white;
        flex-shrink: 0;
      }

      .tile-title {
        font-size: 12px;
        font-weight: 600;
        color: var(--c-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        flex: 1;
      }

      .tile-body {
        flex: 1;
        background: var(--c-bg);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 4px;
        padding: 12px;
      }

      .tile-grade-circle {
        width: clamp(44px, 12cqh, 64px);
        height: clamp(44px, 12cqh, 64px);
        border-radius: 50%;
        background: linear-gradient(
          135deg,
          var(--c-grade) 0%,
          color-mix(in srgb, var(--c-grade) 70%, #7c3aed) 100%
        );
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: var(--c-shadow);
      }

      .tile-grade-letter {
        font-size: clamp(22px, 6cqh, 32px);
        font-weight: 800;
        color: white;
        line-height: 1;
      }

      .tile-score {
        font-size: 12px;
        font-weight: 600;
        color: var(--c-text-2);
        margin: 0;
      }

      .tile-pct {
        font-size: 11px;
        color: var(--c-muted);
        margin: 0;
      }

      .tile-pending {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 5px;
        color: var(--c-muted);
        font-size: 11px;
      }

      .tile-ft {
        background: var(--c-white);
        border-top: 1px solid var(--c-border);
        padding: 6px 13px;
        font-size: 10px;
        font-weight: 500;
        color: var(--c-muted);
        flex-shrink: 0;
        text-align: center;
      }

      /* ══════════════════════════════════════
         CARD  ≥400 × ≥170
      ══════════════════════════════════════ */
      @container fitted-card (min-width: 400px) and (min-height: 170px) {
        .card {
          display: flex;
          flex-direction: row;
          background: var(--c-white);
        }
      }

      .card-left {
        width: 130px;
        flex-shrink: 0;
        background: var(--c-bg);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 4px;
        padding: 18px 12px;
      }

      .card-grade-ring {
        width: clamp(44px, 10cqh, 64px);
        height: clamp(44px, 10cqh, 64px);
        border-radius: 50%;
        background: linear-gradient(
          135deg,
          var(--c-grade) 0%,
          color-mix(in srgb, var(--c-grade) 70%, #7c3aed) 100%
        );
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: var(--c-shadow);
        margin-bottom: 4px;
      }

      .card-grade-letter {
        font-size: clamp(22px, 5cqh, 32px);
        font-weight: 800;
        color: white;
        line-height: 1;
      }

      .card-pct {
        font-size: 15px;
        font-weight: 700;
        color: var(--c-text);
      }

      .card-pts {
        font-size: 10px;
        color: var(--c-muted);
        letter-spacing: 0.02em;
      }

      .card-pending-label {
        font-size: 11px;
        color: var(--c-muted);
        font-style: italic;
      }

      .card-divider {
        width: 1px;
        background: var(--c-border);
        flex-shrink: 0;
        margin: 16px 0;
      }

      .card-body {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 4px;
        padding: 16px 18px;
        min-width: 0;
        justify-content: center;
      }

      .card-icon-row {
        display: flex;
        align-items: center;
        gap: 6px;
        margin-bottom: 2px;
      }

      .card-brand-icon {
        width: 20px;
        height: 20px;
        border-radius: 4px;
        background: var(--c-blue);
        display: flex;
        align-items: center;
        justify-content: center;
        color: white;
        flex-shrink: 0;
      }

      .card-eyebrow {
        font-size: 10px;
        font-weight: 600;
        color: var(--c-muted);
        text-transform: uppercase;
        letter-spacing: 0.06em;
      }

      .card-title {
        font-size: 15px;
        font-weight: 700;
        color: var(--c-text);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        line-height: 1.2;
        margin: 0;
      }

      .card-meta {
        font-size: 11px;
        color: var(--c-muted);
        margin: 0;
      }

      .card-bar {
        margin-top: 8px;
        --boxel-progress-bar-fill-color: var(--c-grade);
        --boxel-progress-bar-background-color: var(--c-border);
        --boxel-progress-bar-border-radius: 3px;
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
