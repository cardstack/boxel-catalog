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
import { add, and, bool, eq } from '@cardstack/boxel-ui/helpers';
import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import { Skill } from '@cardstack/base/skill';
import TextAreaField from '@cardstack/base/text-area';
import { isGradeConsistent, GradeField, QuestionField } from './fields';

class HomeworkIsolated extends Component<typeof HomeworkGrader> {
  get hasLinkedTheme(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  @tracked isGrading = false;
  @tracked lastGradedAnswers: string | null = null;
  @tracked activeTab: 'overview' | 'questions' = 'overview';
  @tracked showToast = false;
  @tracked toastGrade: string | null = null;
  @tracked showAnswerUpdateToast = false;
  @tracked gradeError: string | null = null;
  @tracked editingQuestionIndex = -1;
  @tracked armedRemoveIndex = -1;
  _disarmTimer: ReturnType<typeof setTimeout> | null = null;
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
        // adding/removing a question changes the snapshot length — that's a
        // structure change, not an answer mutation, so move the baseline
        // silently; the re-grade prompt is only for edited answers on an
        // already-graded assignment
        const prevLen = JSON.parse(this._lastSeenAnswers ?? '[]').length;
        const currLen = JSON.parse(current).length;
        const answersMutated = prevLen === currLen;
        this._lastSeenAnswers = current;
        if (answersMutated && this.hasGrade) {
          this.debouncedShowAnswerUpdateToast();
        }
      }
    }, 500);
  }

  willDestroy() {
    super.willDestroy();
    if (this._disarmTimer) {
      clearTimeout(this._disarmTimer);
      this._disarmTimer = null;
    }
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
      if (
        current &&
        current !== prevGrade &&
        isGradeConsistent(
          this.args.model?.grade,
          this.args.model?.questions?.length ?? 0,
        )
      ) {
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
    // a grade only counts while it still matches the question structure —
    // adding/removing questions invalidates every score/feedback display
    return Boolean(
      this.args.model.grade?.overallGrade &&
      isGradeConsistent(
        this.args.model.grade,
        this.args.model?.questions?.length ?? 0,
      ),
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

  setTab = (tab: 'overview' | 'questions') => {
    this.activeTab = tab;
  };

  getPointsDisplay = (questionIndex: number) => {
    const question = this.args.model?.questions?.[questionIndex];
    const maxPoints = question?.maxPoints ?? 5;
    const earnedPoints = this.hasGrade
      ? this.args.model?.grade?.questionPoints?.[questionIndex]
      : undefined;
    return {
      earned: earnedPoints ?? 0,
      max: maxPoints,
      hasEarned: earnedPoints !== undefined && earnedPoints !== null,
    };
  };

  getQuestionTitle = (index: number): string => {
    // questions are identified by position only — the numbered circle plus
    // "Question N" (cardTitle isn't part of the authoring UI)
    return `Question ${index + 1}`;
  };

  getQuestionExcerpt = (index: number): string => {
    let text = this.args.model?.questions?.[index]?.questionText ?? '';
    let plain = String(text)
      .replace(/[#*_>`]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
    if (!plain) return `Question ${index + 1}`;
    return plain.length > 46 ? plain.slice(0, 46).trimEnd() + '…' : plain;
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

  dismissError = () => {
    this.gradeError = null;
  };

  getQuestionFeedback = (index: number): string | undefined => {
    if (!this.hasGrade) return undefined;
    return this.args.model?.grade?.questionFeedbacks?.[index] || undefined;
  };

  // changing the question structure invalidates any existing grade — its
  // per-question points/feedbacks are keyed by index, so clear it outright
  // rather than leaving stale data behind
  clearGrade = () => {
    if (this.args.model.grade?.overallGrade) {
      this.args.model.grade = new GradeField();
    }
  };

  addQuestion = () => {
    let q = new QuestionField();
    q.maxPoints = 10;
    this.args.model.questions = [...(this.args.model.questions ?? []), q];
    this.clearGrade();
    // open the new question in author mode right away
    this.editingQuestionIndex = (this.args.model.questions?.length ?? 1) - 1;
  };

  // two-tap delete (same pattern as TSP's armed clear): the first click arms
  // the button for a few seconds, only a second click actually removes
  removeQuestion = (index: number) => {
    if (this.armedRemoveIndex !== index) {
      this.armedRemoveIndex = index;
      if (this._disarmTimer) clearTimeout(this._disarmTimer);
      this._disarmTimer = setTimeout(() => {
        this.armedRemoveIndex = -1;
      }, 3500);
      return;
    }
    if (this._disarmTimer) clearTimeout(this._disarmTimer);
    this.armedRemoveIndex = -1;
    this.args.model.questions = (this.args.model.questions ?? []).filter(
      (_q: QuestionField, i: number) => i !== index,
    );
    this.clearGrade();
    this.editingQuestionIndex = -1;
  };

  toggleEditQuestion = (index: number) => {
    this.editingQuestionIndex =
      this.editingQuestionIndex === index ? -1 : index;
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
    this.gradeError = null;
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
      this.gradeError =
        error instanceof Error
          ? error.message
          : 'There was an error grading your homework. Please try again.';
    } finally {
      this.isGrading = false;
    }
  };

  <template>
    <article class='hw-app {{unless this.hasLinkedTheme "hw-default-theme"}}'>

      {{#if this.gradeError}}
        <aside class='hw-error-banner' role='alert' aria-label='Grading error'>
          <span class='hw-error-text'>{{this.gradeError}}</span>
          <Button
            @kind='text-only'
            @size='auto'
            class='hw-error-dismiss'
            aria-label='Dismiss error'
            {{on 'click' this.dismissError}}
          >✕</Button>
        </aside>
      {{/if}}

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
        <aside class='hw-sidebar' aria-label='Assignment summary'>
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
          </div>
        </aside>

        {{! Main body }}
        <div class='hw-body'>

          <header class='hw-topbar'>
            <div class='hw-topbar-titles'>
              <h2 class='hw-topbar-heading'>
                {{if (eq this.activeTab 'overview') 'Overview'}}
                {{if (eq this.activeTab 'questions') 'Questions'}}
              </h2>
              <p class='hw-topbar-sub'>
                {{if
                  (eq this.activeTab 'overview')
                  'See your results and feedback summary'
                }}
                {{if
                  (eq this.activeTab 'questions')
                  'Answer each question and review its feedback'
                }}
              </p>
            </div>
            {{#if
              (and (bool @model.gradingSkill) (bool @model.questions.length))
            }}
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
            <aside class='hw-stale-banner' aria-label='Stale grade notice'>
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
                          {{this.getQuestionExcerpt qi}}</span>
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
                      {{on 'click' (fn this.setTab 'questions')}}
                    >Per-question feedback →</Button>
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
                    {{else}}
                      <p class='hw-pending-hint'>Link a grading skill (open the
                        card editor and pick one under
                        <em>Grading Skill</em>) to enable AI grading.</p>
                    {{/if}}
                  </div>
                </section>
              {{/if}}

              <section class='hw-questions-overview'>
                <h3 class='hw-section-title'>Questions</h3>
                {{#unless @model.questions.length}}
                  <div class='hw-empty-questions'>
                    <p class='hw-empty-title'>No questions yet</p>
                    <p class='hw-empty-hint'>Head to the Questions tab and add
                      your first question to build the assignment.</p>
                  </div>
                {{/unless}}
                {{#each @model.questions as |_question qi|}}
                  <Button
                    class='hw-q-item'
                    @kind='text-only'
                    @size='small'
                    {{on 'click' (fn this.setTab 'questions')}}
                  >
                    <div class='hw-q-num'>{{add qi 1}}</div>
                    <div class='hw-q-meta'>
                      <span class='hw-q-name'>{{this.getQuestionExcerpt
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
                      <Button
                        @kind='text-only'
                        @size='auto'
                        class='hw-q-edit
                          {{if (eq qi this.editingQuestionIndex) "is-on"}}'
                        title={{if
                          (eq qi this.editingQuestionIndex)
                          'Done editing'
                          'Edit this question'
                        }}
                        aria-label='Edit question {{add qi 1}}'
                        {{on 'click' (fn this.toggleEditQuestion qi)}}
                      >✎</Button>
                      <Button
                        @kind='text-only'
                        @size='auto'
                        class='hw-q-remove
                          {{if (eq qi this.armedRemoveIndex) "is-armed"}}'
                        title={{if
                          (eq qi this.armedRemoveIndex)
                          'Click again to remove this question'
                          'Remove this question'
                        }}
                        aria-label='Remove question {{add qi 1}}'
                        {{on 'click' (fn this.removeQuestion qi)}}
                      >{{if
                          (eq qi this.armedRemoveIndex)
                          'Confirm ✕'
                          '✕'
                        }}</Button>
                    </div>
                    <div class='hw-question-body'>
                      {{#let (this.getQuestionField qi) as |questionField|}}
                        {{#if questionField}}
                          {{#if (eq qi this.editingQuestionIndex)}}
                            {{component questionField format='edit'}}
                          {{else}}
                            {{component questionField format='fitted'}}
                          {{/if}}
                        {{/if}}
                      {{/let}}
                    </div>
                    {{#unless (eq qi this.editingQuestionIndex)}}
                      {{#if (this.getQuestionFeedback qi)}}
                        <div class='hw-q-feedback'>
                          <span class='hw-q-feedback-label'>Feedback</span>
                          <p
                            class='hw-q-feedback-text'
                          >{{this.getQuestionFeedback qi}}</p>
                        </div>
                      {{/if}}
                    {{/unless}}
                  </article>
                {{else}}
                  <div class='hw-empty-questions'>
                    <p class='hw-empty-title'>No questions yet</p>
                    <p class='hw-empty-hint'>Add your first question to build
                      the assignment.</p>
                  </div>
                {{/each}}
                <Button
                  class='hw-add-question'
                  @kind='secondary'
                  @size='small'
                  {{on 'click' this.addQuestion}}
                >+ Add question</Button>
              </section>
            {{/if}}

            {{! FEEDBACK TAB }}
          </main>
        </div>
      </div>

    </article>

    <style scoped>
      /* ── Design tokens + base ── */
      /* Default palette when NO theme is linked — pins the semantic tokens
         so app-level defaults can't restyle the card arbitrarily. A linked
         theme omits this class, so its tokens win. */
      .hw-default-theme {
        color: var(--card-foreground);
      }

      .hw-app {
        container-type: inline-size;
        container-name: hw-app;
        /* Each token resolves to the active theme token (--primary,
           --foreground, …) with the card's blue-slate default as the
           literal fallback. Derived shades come from color-mix so a theme
           only has to supply the semantic set. */
        --c-blue-hover: color-mix(
          in oklch,
          var(--primary) 85%,
          var(--foreground)
        );
        --c-blue-bg: color-mix(in oklch, var(--card) 8%, var(--card));
        --c-blue-border: color-mix(in oklch, var(--primary) 28%, var(--card));
        --c-blue-muted: color-mix(in oklch, var(--primary) 45%, var(--card));
        --c-shadow:
          0 1px 0.1875rem
            color-mix(in oklch, var(--shadow-color) 7%, transparent),
          0 1px 2px color-mix(in oklch, var(--shadow-color) 4%, transparent);
        --c-shadow-md:
          0 0.25rem 0.75rem
            color-mix(in oklch, var(--shadow-color) 8%, transparent),
          0 2px 0.25rem color-mix(in oklch, var(--shadow-color) 4%, transparent);

        min-height: 100%;
        display: flex;
        flex-direction: column;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Roboto,
          sans-serif;
        font-size: 0.875rem;
        line-height: 1.5;
        position: relative;
        background-color: var(--canvas);
        color: var(--foreground);
      }

      .hw-layout {
        display: flex;
        flex: 1;
        min-height: 0;
      }

      /* ── Sidebar ── */
      .hw-sidebar {
        width: 13.75rem;
        flex-shrink: 0;
        background-color: var(--sidebar);
        color: var(--sidebar-foreground);
        border-right: 1px solid var(--border);
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
        gap: 0.625rem;
        padding: 1.125rem 1rem 0.875rem;
        border-bottom: 1px solid var(--border);
      }

      .hw-brand-icon {
        width: 2.125rem;
        height: 2.125rem;
        border-radius: 0.5rem;
        background-color: var(--primary);
        color: var(--primary-foreground);
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }

      .hw-brand-text {
        min-width: 0;
      }

      .hw-brand-title {
        font-size: 0.8125rem;
        font-weight: 700;
        color: var(--foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        margin: 0;
        line-height: 1.3;
      }

      .hw-brand-sub {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
        margin: 0;
        line-height: 1.3;
      }

      .hw-sidebar-nav {
        padding: 0.625rem 0.5rem;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .hw-nav-btn {
        --boxel-button-border-radius: 0.5rem;
        --boxel-button-font:
          500 0.8125rem -apple-system, 'Segoe UI', sans-serif;
        --boxel-button-padding: 0;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;
        --boxel-button-text-color: var(--muted-foreground);
        --boxel-button-color: transparent;

        display: flex;
        align-items: center;
        gap: 0.625rem;
        width: 100%;
        padding: 0.5625rem 0.625rem;
        border-radius: 0.5rem;
        font-size: 0.8125rem;
        font-weight: 500;
        color: var(--muted-foreground);
        background-color: transparent;
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
        background-color: var(--background);
        color: var(--foreground);
      }

      .hw-nav-btn.is-active {
        background-color: var(--c-blue-bg);
        color: var(--primary-ink);
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
        border-top: 1px solid var(--border);
        flex-shrink: 0;
      }

      .hw-sidebar-thumb {
        width: 100%;
        height: 7.5rem;
        object-fit: cover;
        display: block;
      }

      .hw-sidebar-cta {
        padding: 0.875rem 1rem;
        display: flex;
        flex-direction: column;
        gap: 0.3125rem;
      }

      .hw-cta-title {
        font-size: 0.8125rem;
        font-weight: 700;
        color: var(--foreground);
        margin: 0;
      }

      .hw-cta-body {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
        line-height: 1.5;
        margin: 0;
      }

      .hw-cta-btn {
        --boxel-button-border-radius: 0.5rem;
        --boxel-button-font: 600 0.75rem -apple-system, sans-serif;
        --boxel-button-padding: 0.5rem 0.875rem;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;

        margin-top: 0.375rem;
        width: 100%;
        justify-content: center;
        gap: 0.375rem;
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
        background-color: var(--card);
        color: var(--card-foreground);
        border-bottom: 1px solid var(--border);
        padding: 1rem 1.5rem;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
        flex-shrink: 0;
      }

      .hw-topbar-titles {
        min-width: 0;
      }

      .hw-topbar-heading {
        font-size: 1.25rem;
        font-weight: 700;
        color: var(--foreground);
        margin: 0;
        line-height: 1.2;
      }

      .hw-topbar-sub {
        font-size: 0.8125rem;
        color: var(--muted-foreground);
        margin: 2px 0 0;
      }

      .hw-grade-btn {
        --boxel-button-border-radius: 0.5rem;
        --boxel-button-font: 600 0.8125rem -apple-system, sans-serif;
        --boxel-button-padding: 0.5625rem 1.125rem;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;

        flex-shrink: 0;
        gap: 0.375rem;
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
        font-size: 0.875rem;
        line-height: 1;
      }

      .hw-stale-banner {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        background-color: color-mix(in oklch, var(--card) 10%, var(--card));
        border-bottom: 1px solid var(--border);
        padding: 0.5rem 1.5rem;
        font-size: 0.8125rem;
        color: var(--card-foreground);
        flex-shrink: 0;
      }

      .hw-main {
        flex: 1;
        padding: 1.25rem 1.5rem;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 1rem;
        min-height: 0;
        /* isolated width varies with the host panels (e.g. AI assistant
           open), so layout shifts key off the card's own width */
        container-type: inline-size;
        container-name: hw-main;
      }

      /* Very narrow card: the fixed 220px sidebar would starve the body, so
         the whole layout stacks — sidebar becomes a top strip */
      @container hw-app (max-width: 640px) {
        .hw-layout {
          flex-direction: column;
        }
        .hw-sidebar {
          width: 100%;
          border-right: none;
          border-bottom: 1px solid var(--border);
          background-color: var(--sidebar);
          color: var(--sidebar-foreground);
        }
        .hw-sidebar-bottom {
          display: none;
        }
      }

      /* Narrow container: stack every multi-column row instead of letting
         text squeeze into slivers */
      @container hw-main (max-width: 560px) {
        .hw-score-left {
          flex-direction: column;
          align-items: center;
          text-align: center;
          gap: 0.875rem;
        }
        .hw-score-divider {
          display: none;
        }
        .hw-score-card .hw-breakdown {
          flex: 1 1 100%;
          border-top: 1px solid var(--border);
        }
        .hw-feedback-preview {
          flex-direction: column;
          align-items: stretch;
          text-align: left;
        }
        .hw-view-feedback-btn {
          align-self: flex-start;
        }
        .hw-q-score-strip {
          flex-wrap: wrap;
        }
        .hw-q-strip-sep {
          display: none;
        }
        .hw-question-header {
          flex-wrap: wrap;
          background-color: var(--inset);
          color: var(--foreground);
        }
      }

      /* ── Score card ── */
      .hw-score-card {
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        display: flex;
        flex-wrap: wrap;
        overflow: hidden;
        box-shadow: var(--c-shadow);
      }

      .hw-score-left {
        padding: 1.5rem 1.75rem;
        display: flex;
        align-items: center;
        gap: 1.5rem;
        flex: 1;
        min-width: 15rem;
      }

      .hw-score-ring-wrap {
        position: relative;
        width: 6.875rem;
        height: 6.875rem;
        flex-shrink: 0;
      }

      .hw-score-ring {
        width: 6.875rem;
        height: 6.875rem;
        transform: rotate(-90deg);
      }

      .hw-ring-track {
        fill: none;
        stroke: var(--card-foreground);
        stroke-width: 8;
      }

      .hw-ring-fill {
        fill: none;
        stroke: var(--primary-ink);
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
        font-size: 1.875rem;
        font-weight: 800;
        color: var(--primary-ink);
        line-height: 1;
      }

      .hw-score-info {
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
      }

      .hw-score-num {
        font-size: 1.75rem;
        font-weight: 800;
        color: var(--foreground);
        line-height: 1;
        margin: 0;
      }

      .hw-score-denom {
        font-size: 1rem;
        font-weight: 400;
        color: var(--muted-foreground);
      }

      .hw-score-verdict {
        font-size: 0.9375rem;
        font-weight: 600;
        color: var(--primary-ink);
        margin: 0;
      }

      .hw-score-summary {
        font-size: 0.8125rem;
        line-height: 1.55;
        color: var(--muted-foreground);
        margin: 0;
        max-width: 30ch;
      }

      .hw-score-divider {
        width: 1px;
        background-color: var(--border);
        flex-shrink: 0;
        margin: 1.25rem 0;
      }

      .hw-breakdown {
        padding: 1.25rem 1.5rem;
        display: flex;
        flex-direction: column;
        gap: 0.625rem;
        min-width: 12.5rem;
        flex: 1;
        justify-content: center;
      }

      .hw-breakdown-heading {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--muted-foreground);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        margin: 0 0 0.25rem;
      }

      .hw-bd-row {
        display: grid;
        grid-template-columns: 1fr 5rem 3.25rem;
        align-items: center;
        gap: 0.5rem;
      }

      .hw-bd-label {
        font-size: 0.75rem;
        color: var(--foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .hw-bd-track {
        height: 0.375rem;
        border-radius: 0.1875rem;
        background-color: var(--border);
        overflow: hidden;
      }

      .hw-bd-fill {
        height: 100%;
        background-color: var(--primary);
        color: var(--primary-foreground);
        border-radius: 0.1875rem;
        transition: width 0.4s ease;
      }

      .hw-bd-score {
        font-size: 0.75rem;
        color: var(--muted-foreground);
        text-align: right;
        white-space: nowrap;
      }

      .hw-bd-total {
        display: flex;
        justify-content: space-between;
        align-items: center;
        border-top: 1px solid var(--border);
        padding-top: 0.625rem;
        margin-top: 2px;
      }

      .hw-bd-total-label {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--foreground);
      }

      .hw-bd-total-score {
        font-size: 0.875rem;
        font-weight: 700;
        color: var(--primary-ink);
      }

      /* ── Pending state ── */
      .hw-pending {
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        padding: 1.75rem 1.5rem;
        display: flex;
        align-items: center;
        gap: 1.25rem;
        box-shadow: var(--c-shadow);
      }

      .hw-pending-icon {
        font-size: 1.875rem;
        color: var(--subtle-foreground);
        line-height: 1;
        flex-shrink: 0;
      }

      .hw-pending-title {
        font-size: 0.9375rem;
        font-weight: 600;
        color: var(--foreground);
        margin: 0;
      }

      .hw-pending-hint {
        font-size: 0.8125rem;
        color: var(--muted-foreground);
        margin: 0.25rem 0 0;
      }

      /* ── Feedback preview card ── */
      .hw-feedback-preview {
        background-color: var(--c-blue-bg);
        border: 1px solid var(--c-blue-border);
        border-radius: 0.75rem;
        padding: 1.125rem 1.25rem;
        display: flex;
        align-items: flex-start;
        gap: 0.875rem;
        box-shadow: var(--c-shadow);
      }

      .hw-feedback-preview-icon {
        width: 2rem;
        height: 2rem;
        border-radius: 0.5rem;
        background-color: var(--primary);
        color: var(--primary-foreground);
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
        font-size: 0.8125rem;
        font-weight: 600;
        color: var(--foreground);
        margin: 0 0 0.375rem;
      }

      .hw-feedback-preview-text {
        font-size: 0.8125rem;
        line-height: 1.6;
        color: var(--foreground);
        margin: 0;
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
      }

      .hw-view-feedback-btn {
        --boxel-button-border-radius: 0.5rem;
        --boxel-button-font: 500 0.75rem -apple-system, sans-serif;
        --boxel-button-padding: 0.4375rem 0.875rem;
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
        gap: 0.5rem;
      }

      .hw-section-title {
        font-size: 0.9375rem;
        font-weight: 700;
        color: var(--foreground);
        margin: 0 0 0.25rem;
      }

      .hw-q-item {
        --boxel-button-border-radius: 0.625rem;
        --boxel-button-color: var(--card);
        --boxel-button-text-color: var(--foreground);
        --boxel-button-padding: 0;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: auto;
        --boxel-button-font: 400 0.875rem -apple-system, sans-serif;

        display: flex;
        align-items: center;
        gap: 0.75rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: 0.625rem;
        padding: 0.75rem 1rem;
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
        width: 1.875rem;
        height: 1.875rem;
        border-radius: 50%;
        background-color: var(--primary);
        color: var(--primary-foreground);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 0.8125rem;
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
        font-size: 0.875rem;
        font-weight: 600;
        color: var(--foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .hw-q-hint {
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }

      .hw-q-pts {
        font-size: 0.8125rem;
        font-weight: 600;
        color: var(--muted-foreground);
        white-space: nowrap;
        flex-shrink: 0;
      }

      .hw-q-pts.full {
        color: var(--success-ink);
      }

      .hw-q-pts.partial {
        color: var(--primary-ink);
      }

      .hw-q-pts strong {
        color: inherit;
      }

      .hw-q-arrow {
        font-size: 1.125rem;
        color: var(--subtle-foreground);
        line-height: 1;
        flex-shrink: 0;
      }

      /* ── Questions full tab ── */
      .hw-questions-full {
        display: flex;
        flex-direction: column;
        gap: 0.875rem;
      }

      .hw-q-score-strip {
        background-color: var(--primary);
        color: var(--primary-foreground);
        border-radius: 0.625rem;
        padding: 0.75rem 1.125rem;
        display: flex;
        align-items: center;
        gap: 0.875rem;
      }

      .hw-q-strip-badge {
        width: 2.5rem;
        height: 2.5rem;
        border-radius: 50%;
        background-color: var(--card);
        color: var(--primary-ink);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 1.0625rem;
        font-weight: 800;
        flex-shrink: 0;
      }

      .hw-q-strip-info {
        display: flex;
        flex-direction: column;
        gap: 1px;
      }

      .hw-q-strip-pts {
        font-size: 0.9375rem;
        font-weight: 700;
        color: var(--card-foreground);
        line-height: 1;
      }

      .hw-q-strip-pct {
        font-size: 0.75rem;
        color: color-mix(in oklch, var(--card-foreground) 70%, transparent);
        font-weight: 500;
      }

      .hw-q-strip-sep {
        width: 1px;
        height: 1.875rem;
        background-color: var(--muted);
        color: var(--muted-foreground);
        flex-shrink: 0;
      }

      .hw-q-strip-verdict {
        font-size: 0.875rem;
        color: color-mix(in oklch, var(--card-foreground) 85%, transparent);
        font-style: italic;
        margin: 0;
      }

      .hw-instructions {
        background-color: color-mix(in oklch, var(--warning) 10%, var(--card));
        border: 1px solid var(--warning);
        border-radius: 0.625rem;
        padding: 0.875rem 1rem;
      }

      .hw-instr-label {
        font-size: 0.6875rem;
        font-weight: 600;
        color: var(--warning-ink);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        margin: 0 0 0.25rem;
      }

      .hw-instr-body {
        font-size: 0.8125rem;
        color: var(--warning-ink);
        line-height: 1.6;
        margin: 0;
      }

      .hw-question-card {
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: 0.625rem;
        overflow: hidden;
        box-shadow: var(--c-shadow);
      }

      .hw-question-header {
        background-color: var(--inset);
        border-bottom: 1px solid var(--border);
        padding: 0.625rem 1rem;
        display: flex;
        align-items: center;
        gap: 0.625rem;
        color: var(--foreground);
      }

      .hw-question-title {
        flex: 1;
        font-size: 0.875rem;
        font-weight: 600;
        color: var(--foreground);
        margin: 0;
      }

      .hw-question-pts {
        font-size: 0.75rem;
        font-weight: 700;
        color: var(--muted-foreground);
        padding: 2px 0.5625rem;
        border-radius: 1.25rem;
        background-color: var(--border);
      }

      .hw-question-pts.full {
        color: var(--success-ink);
        background-color: var(--card);
      }

      .hw-question-pts.partial {
        color: var(--primary-ink);
        background-color: var(--c-blue-bg);
      }

      .hw-question-max {
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }

      .hw-question-body {
        padding: 1rem;
        min-height: 8.75rem;
      }

      .hw-q-edit {
        flex-shrink: 0;
        width: 1.5rem;
        height: 1.5rem;
        border: 1px solid var(--border);
        border-radius: 50%;
        background-color: var(--card);
        color: var(--muted-foreground);
        font-size: 0.75rem;
        line-height: 1;
        cursor: pointer;
      }
      .hw-q-edit.is-on,
      .hw-q-edit:hover {
        color: var(--primary-foreground);
        background-color: var(--primary);
        border-color: var(--primary);
      }

      .hw-q-remove {
        flex-shrink: 0;
        width: 1.5rem;
        height: 1.5rem;
        border: 1px solid var(--border);
        border-radius: 50%;
        background-color: var(--card);
        color: var(--muted-foreground);
        font-size: 0.75rem;
        line-height: 1;
        cursor: pointer;
      }
      .hw-q-remove:hover {
        color: var(--destructive-ink);
        border-color: currentColor;
      }
      .hw-q-remove.is-armed {
        width: auto;
        padding: 0 0.625rem;
        border-radius: 0.75rem;
        background-color: var(--destructive);
        border-color: var(--destructive);
        color: var(--destructive-foreground);
        font-weight: 700;
        white-space: nowrap;
      }

      .hw-q-feedback {
        border-top: 1px solid var(--border);
        background-color: var(--background);
        padding: 0.75rem 1rem;
      }
      .hw-q-feedback-label {
        display: block;
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        margin-bottom: 0.25rem;
      }
      .hw-q-feedback-text {
        margin: 0;
        font-size: 0.8125rem;
        line-height: 1.55;
        color: var(--foreground);
        white-space: pre-line;
      }

      .hw-error-banner {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        margin: 0.75rem 1rem 0;
        padding: 0.625rem 0.875rem;
        border: 1px solid var(--border);
        border-radius: 0.5rem;
        background-color: color-mix(in oklch, var(--card) 8%, var(--card));
        color: var(--foreground);
        font-size: 0.8125rem;
      }
      .hw-error-text {
        flex: 1;
      }
      .hw-error-dismiss {
        flex-shrink: 0;
        border: none;
        background-color: transparent;
        color: var(--muted-foreground);
        cursor: pointer;
        font-size: 0.8125rem;
      }

      .hw-empty-questions {
        border: 1.5px dashed var(--border);
        border-radius: 0.625rem;
        padding: 1.625rem 1.25rem;
        text-align: center;
      }
      .hw-empty-title {
        margin: 0 0 0.25rem;
        font-size: 0.875rem;
        font-weight: 700;
        color: var(--foreground);
      }
      .hw-empty-hint {
        margin: 0;
        font-size: 0.7812rem;
        color: var(--muted-foreground);
      }

      .hw-add-question {
        align-self: flex-start;
      }

      /* ── Feedback full tab ── */

      /* ── Grade notification toast ── */
      .hw-grade-toast {
        position: sticky;
        top: 0;
        z-index: 50;
        display: flex;
        align-items: center;
        gap: 0.875rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border-bottom: 1px solid var(--border);
        border-left: 4px solid var(--primary);
        padding: 0.75rem 1.25rem;
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
        width: 2.5rem;
        height: 2.5rem;
        border-radius: 50%;
        background-color: var(--primary);
        color: var(--primary-foreground);
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }

      .hw-toast-letter {
        font-size: 1.0625rem;
        font-weight: 800;
        color: var(--card-foreground);
        line-height: 1;
      }

      .hw-toast-copy {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 1px;
      }

      .hw-toast-eyebrow {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
        font-weight: 500;
        margin: 0;
      }

      .hw-toast-grade {
        font-size: 0.875rem;
        font-weight: 600;
        color: var(--foreground);
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
        padding-right: 1rem;
        z-index: 10;
        pointer-events: none;
      }

      .hw-answer-toast {
        pointer-events: all;
        margin-top: 1rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        padding: 0.875rem 1rem 0.75rem;
        display: flex;
        flex-direction: column;
        gap: 0.625rem;
        box-shadow: var(--c-shadow-md);
        max-width: 16rem;
        min-width: 12.5rem;
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
        gap: 0.625rem;
      }

      .hw-answer-toast-icon {
        font-size: 1rem;
        color: var(--primary-ink);
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
        font-size: 0.8125rem;
        font-weight: 600;
        color: var(--foreground);
        line-height: 1.2;
        margin: 0;
      }

      .hw-answer-toast-sub {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
        margin: 0;
      }

      .hw-answer-toast-close {
        flex-shrink: 0;
      }

      .hw-answer-toast-regrade {
        --boxel-button-border-radius: 0.5rem;
        --boxel-button-padding: 0.5rem 0.75rem;
        --boxel-button-min-height: auto;
        --boxel-button-min-width: 100%;
        --boxel-button-font: 600 0.75rem -apple-system, sans-serif;

        justify-content: center;
        gap: 0.375rem;
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
  get hasLinkedTheme(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  get fittedClasses(): string {
    let classes = [this.gradeClass];
    if (!this.hasLinkedTheme) classes.push('hw-default-theme');
    return classes.join(' ');
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
    <article class='hw-fitted {{this.fittedClasses}}'>

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
      .hw-default-theme {
        color: var(--card-foreground);
      }

      .hw-fitted {
        --c-blue-bg: color-mix(in oklch, var(--card) 8%, var(--card));
        --c-blue-border: color-mix(in oklch, var(--primary) 28%, var(--card));
        --c-grade: var(--primary);
        --c-shadow:
          0 1px 0.1875rem
            color-mix(in oklch, var(--shadow-color) 7%, transparent),
          0 1px 2px color-mix(in oklch, var(--shadow-color) 4%, transparent);

        width: 100%;
        height: 100%;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', sans-serif;
      }

      /* Grade accent colours */
      .hw-fitted.grade-a {
        --c-grade: var(--success);
      }
      .hw-fitted.grade-b {
        --c-grade: var(--primary);
      }
      .hw-fitted.grade-c {
        --c-grade: var(--warning);
      }
      .hw-fitted.grade-f {
        --c-grade: var(--destructive);
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
          gap: 0.375rem;
          background-color: var(--background);
          padding: 0.625rem 0.5rem;
        }
      }

      .badge-seal {
        width: 3rem;
        height: 3rem;
        border-radius: 50%;
        background-color: var(--c-grade);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: var(--c-shadow);
      }

      .badge-letter {
        font-size: 1.5rem;
        font-weight: 800;
        color: var(--card-foreground);
        line-height: 1;
      }

      .badge-book {
        color: var(--card-foreground);
      }

      .badge-title {
        font-size: 0.5625rem;
        font-weight: 600;
        color: var(--muted-foreground);
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
          gap: 0.625rem;
          padding: 0 0.875rem;
          background-color: var(--card);
          color: var(--card-foreground);
          border-left: 3px solid var(--c-grade);
        }
      }

      .strip-seal {
        flex-shrink: 0;
        width: 2rem;
        height: 2rem;
        border-radius: 50%;
        background-color: var(--c-grade);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 0.875rem;
        font-weight: 800;
        color: var(--card-foreground);
        line-height: 1;
      }

      .strip-seal.strip-pending {
        background-color: var(--border);
        color: var(--muted-foreground);
        font-size: 1rem;
      }

      .strip-title {
        flex: 1;
        font-size: 0.8125rem;
        font-weight: 600;
        color: var(--foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .strip-pct {
        flex-shrink: 0;
        font-size: 0.75rem;
        font-weight: 700;
        color: var(--c-grade);
      }

      .strip-qs {
        flex-shrink: 0;
        font-size: 0.625rem;
        font-weight: 600;
        color: var(--foreground);
        background-color: var(--inset);
        border: 1px solid var(--border);
        border-radius: 0.25rem;
        padding: 2px 0.375rem;
      }

      /* ══════════════════════════════════════
         TILE  <400 × ≥170
      ══════════════════════════════════════ */
      @container fitted-card (max-width: 399px) and (min-height: 170px) {
        .tile {
          display: flex;
          flex-direction: column;
          background-color: var(--card);
          color: var(--card-foreground);
        }
      }

      .tile-hd {
        background-color: var(--card);
        color: var(--card-foreground);
        border-bottom: 1px solid var(--border);
        padding: 0.625rem 0.8125rem;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        flex-shrink: 0;
      }

      .tile-brand-icon {
        width: 1.375rem;
        height: 1.375rem;
        border-radius: 0.3125rem;
        background-color: var(--primary);
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--primary-foreground);
        flex-shrink: 0;
      }

      .tile-title {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        flex: 1;
      }

      .tile-body {
        flex: 1;
        background-color: var(--inset);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.25rem;
        padding: 0.75rem;
        color: var(--foreground);
      }

      .tile-grade-circle {
        width: clamp(2.75rem, 12cqh, 4rem);
        height: clamp(2.75rem, 12cqh, 4rem);
        border-radius: 50%;
        background-color: var(--c-grade);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: var(--c-shadow);
      }

      .tile-grade-letter {
        font-size: clamp(1.375rem, 6cqh, 2rem);
        font-weight: 800;
        color: var(--card-foreground);
        line-height: 1;
      }

      .tile-score {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--foreground);
        margin: 0;
      }

      .tile-pct {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
        margin: 0;
      }

      .tile-pending {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.3125rem;
        color: var(--muted-foreground);
        font-size: 0.6875rem;
      }

      .tile-ft {
        background-color: var(--card);
        border-top: 1px solid var(--border);
        padding: 0.375rem 0.8125rem;
        font-size: 0.625rem;
        font-weight: 500;
        color: var(--muted-foreground);
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
          background-color: var(--card);
          color: var(--card-foreground);
        }
      }

      .card-left {
        width: 8.125rem;
        flex-shrink: 0;
        background-color: var(--inset);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.25rem;
        padding: 1.125rem 0.75rem;
        color: var(--foreground);
      }

      .card-grade-ring {
        width: clamp(2.75rem, 10cqh, 4rem);
        height: clamp(2.75rem, 10cqh, 4rem);
        border-radius: 50%;
        background-color: var(--c-grade);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: var(--c-shadow);
        margin-bottom: 0.25rem;
      }

      .card-grade-letter {
        font-size: clamp(1.375rem, 5cqh, 2rem);
        font-weight: 800;
        color: var(--card-foreground);
        line-height: 1;
      }

      .card-pct {
        font-size: 0.9375rem;
        font-weight: 700;
        color: var(--foreground);
      }

      .card-pts {
        font-size: 0.625rem;
        color: var(--muted-foreground);
        letter-spacing: 0.02em;
      }

      .card-pending-label {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
        font-style: italic;
      }

      .card-divider {
        width: 1px;
        background-color: var(--border);
        flex-shrink: 0;
        margin: 1rem 0;
      }

      .card-body {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        padding: 1rem 1.125rem;
        min-width: 0;
        justify-content: center;
      }

      .card-icon-row {
        display: flex;
        align-items: center;
        gap: 0.375rem;
        margin-bottom: 2px;
      }

      .card-brand-icon {
        width: 1.25rem;
        height: 1.25rem;
        border-radius: 0.25rem;
        background-color: var(--primary);
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--primary-foreground);
        flex-shrink: 0;
      }

      .card-eyebrow {
        font-size: 0.625rem;
        font-weight: 600;
        color: var(--muted-foreground);
        text-transform: uppercase;
        letter-spacing: 0.06em;
      }

      .card-title {
        font-size: 0.9375rem;
        font-weight: 700;
        color: var(--foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        line-height: 1.2;
        margin: 0;
      }

      .card-meta {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
        margin: 0;
      }

      .card-bar {
        margin-top: 0.5rem;
        --boxel-progress-bar-fill-color: var(--c-grade);
        --boxel-progress-bar-background-color: var(--border);
        --boxel-progress-bar-border-radius: 0.1875rem;
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
  @field gradingSkill = linksTo(() => Skill, { searchable: true });

  static isolated = HomeworkIsolated;
  static embedded = HomeworkIsolated;
  static fitted = HomeworkFitted;
}
