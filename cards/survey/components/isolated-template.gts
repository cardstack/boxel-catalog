import { Component, realmURL } from '@cardstack/base/card-api';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { guidFor } from '@ember/object/internals';
import { eq } from '@cardstack/boxel-ui/helpers';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import type { Survey } from '../survey';
import type { SurveyQuestion } from '../survey-question';
import { SurveyResponse, SurveyAnswer } from '../survey-response';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import {
  Wizard,
  type WizardChange,
  type WizardStep,
} from '@cardstack/pretui/components/wizard';
import {
  ALERT_STYLE,
  nameProgress,
} from '@cardstack/catalog/components/pretui-helpers';
import QuestionInput from './question-input';
import SurveyResults from './survey-results';

interface PageItem {
  question: SurveyQuestion;
  index: number;
}

const PAGE_SIZE = 4;

export class SurveyIsolated extends Component<typeof Survey> {
  @tracked currentStep = 0;
  @tracked answers: Record<number, unknown> = {};
  @tracked submitted = false;
  @tracked showErrors = false;
  @tracked saving = false;
  @tracked submitNote = '';
  @tracked mode: 'fill' | 'results' = 'fill';

  get questions(): SurveyQuestion[] {
    return (this.args.model?.questions as SurveyQuestion[] | undefined) ?? [];
  }

  get surveyRealm(): string | undefined {
    let url = this.args.model?.[realmURL];
    return url ? url.href : undefined;
  }

  get resultRealms(): string[] {
    return this.surveyRealm ? [this.surveyRealm] : [];
  }

  get pages(): PageItem[][] {
    let pages: PageItem[][] = [];
    this.questions.forEach((question, index) => {
      let page = Math.floor(index / PAGE_SIZE);
      (pages[page] ??= []).push({ question, index });
    });
    return pages;
  }

  get steps(): WizardStep[] {
    let pageSteps: WizardStep[] = this.pages.map((items, i) => ({
      id: `page-${i}`,
      label: `Page ${i + 1}`,
      valid: !items.some(
        (it) => it.question.required && !this.hasAnswer(it.index),
      ),
      blockedReason: 'Answer the required questions on this page.',
    }));
    return [
      ...pageSteps,
      {
        id: 'review',
        label: 'Review',
        valid: this.allRequiredMet,
        blockedReason: 'Some required questions still need an answer.',
      },
    ];
  }

  modeOptions = [
    { value: 'fill', label: 'Fill' },
    { value: 'results', label: 'Results' },
  ];

  get progressText(): string {
    return `${this.answeredCount} of ${this.questions.length} answered`;
  }

  get isReview(): boolean {
    return this.currentStep >= this.pages.length;
  }

  get activePageItems(): PageItem[] {
    return this.pages[this.currentStep] ?? [];
  }

  get answeredCount(): number {
    return this.questions.filter((_, index) => this.hasAnswer(index)).length;
  }

  get progressPct(): number {
    let total = this.questions.length;
    if (!total) return 0;
    return Math.round((this.answeredCount / total) * 100);
  }

  get allRequiredMet(): boolean {
    return this.questions.every(
      (q, index) => !q.required || this.hasAnswer(index),
    );
  }

  hasAnswer(index: number): boolean {
    let v = this.answers[index];
    if (v == null || v === '') return false;
    if (Array.isArray(v)) return v.length > 0;
    return true;
  }

  answerFor = (index: number): unknown => {
    return this.answers[index];
  };

  isInvalid = (question: SurveyQuestion, index: number): boolean => {
    return Boolean(
      this.showErrors && question.required && !this.hasAnswer(index),
    );
  };

  errorIdFor = (index: number): string => `${guidFor(this)}-q${index}-error`;

  questionNumber = (index: number): string => {
    return `Q${index + 1} of ${this.questions.length}`;
  };

  displayAnswer = (index: number): string => {
    let v = this.answers[index];
    if (v == null || v === '') return '—';
    if (Array.isArray(v)) return v.length ? v.join(', ') : '—';
    if (typeof v === 'boolean') return v ? 'Yes' : 'No';
    if (typeof v === 'number') return `${v} / 5`;
    return String(v);
  };

  private pageOf(index: number): number {
    return Math.floor(index / PAGE_SIZE);
  }

  private firstUnmetPage(): number | null {
    let q = this.questions.findIndex(
      (question, index) => question.required && !this.hasAnswer(index),
    );
    return q === -1 ? null : this.pageOf(q);
  }

  @action
  setAnswer(index: number, value: unknown) {
    this.answers = { ...this.answers, [index]: value };
  }

  @action
  setMode(mode: string) {
    this.mode = mode === 'results' ? 'results' : 'fill';
  }

  @action
  onStepChange(index: number, _change: WizardChange) {
    this.goToStep(index);
  }

  // A refused move is where the inline "required" messages appear. On the
  // review step, the first page with an unanswered required question opens.
  @action
  onRefused() {
    this.showErrors = true;
    if (this.isReview) {
      let page = this.firstUnmetPage();
      if (page != null) this.currentStep = page;
    }
  }

  @action
  goToStep(index: number) {
    this.submitted = false;
    this.showErrors = false;
    this.currentStep = index;
  }

  @action
  editAnswer(index: number) {
    this.goToStep(this.pageOf(index));
  }

  // Enter goes through the Wizard's own Next, so its gate and its record of
  // the furthest page reached stay the only ones.
  @action
  onKeydown(advance: () => void, event: Event) {
    let ke = event as KeyboardEvent;
    let target = event.target as HTMLElement;
    if (ke.key !== 'Enter' || target.tagName === 'TEXTAREA') return;
    event.preventDefault();
    advance();
  }

  @action
  async submit() {
    if (!this.allRequiredMet) {
      this.showErrors = true;
      let page = this.firstUnmetPage();
      if (page != null) this.currentStep = page;
      return;
    }

    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.submitNote =
        'Open this survey in the full app to save responses. Your answers are shown below.';
      this.submitted = true;
      return;
    }

    let realm = this.surveyRealm;
    if (!realm) {
      this.submitNote =
        'This survey has not been saved yet, so responses cannot be collected. Your answers are shown below.';
      this.submitted = true;
      return;
    }

    this.saving = true;
    this.submitNote = '';
    try {
      let answers = this.questions.map(
        (q, index) =>
          new SurveyAnswer({
            prompt: q.prompt ?? `Question ${index + 1}`,
            response: this.displayAnswer(index),
          }),
      );
      let response = new SurveyResponse({
        surveyId: this.args.model.id,
        surveyTitle: this.args.model.title ?? 'Survey',
        answers,
      });
      response.survey = this.args.model as unknown as Survey;
      await new SaveCardCommand(commandContext).execute({
        card: response,
        realm,
      });
    } catch (err) {
      this.submitNote = `Your answers are shown below, but the response couldn't be saved (${
        (err as Error)?.message ?? 'unknown error'
      }). If this is someone else's survey, you may not have write access to its workspace.`;
    } finally {
      this.saving = false;
      this.submitted = true;
    }
  }

  @action
  restart() {
    this.answers = {};
    this.currentStep = 0;
    this.submitted = false;
    this.showErrors = false;
    this.submitNote = '';
  }

  <template>
    <section class='survey'>
      <header class='survey-header'>
        <div class='survey-head-top'>
          <p class='survey-eyebrow'>Survey</p>
          <SegmentedControl
            @options={{this.modeOptions}}
            @value={{this.mode}}
            @onValueChange={{this.setMode}}
            @label='View'
          />
        </div>
        <h1 class='survey-title'>
          {{if @model.title @model.title 'Untitled survey'}}
        </h1>
        {{#if @model.description}}
          <div class='survey-desc'><@fields.description /></div>
        {{/if}}
        {{#unless (eq this.mode 'results')}}
          <div class='survey-progress'>
            <ProgressBar
              class='survey-progress-bar'
              @value={{this.progressPct}}
              {{nameProgress 'Answered' this.progressText}}
            />
            <span class='survey-progress-label'>{{this.progressText}}</span>
          </div>
        {{/unless}}
      </header>

      {{#if (eq this.mode 'results')}}
        <SurveyResults
          @surveyId={{@model.id}}
          @questions={{this.questions}}
          @realms={{this.resultRealms}}
          @context={{@context}}
        />
      {{else if this.submitted}}
        <div class='survey-done'>
          <div class='survey-done-check'>✓</div>
          <h2>Thanks for completing the survey!</h2>
          <p class='survey-done-sub'>You answered
            {{this.answeredCount}}
            of
            {{this.questions.length}}
            questions.</p>
          {{#if this.submitNote}}
            <Alert
              class='survey-done-note'
              @tone='warning'
              @title='Not saved'
              style={{ALERT_STYLE.attention}}
            >{{this.submitNote}}</Alert>
          {{/if}}
          <dl class='survey-done-list'>
            {{#each this.questions as |question index|}}
              <div class='survey-done-row'>
                <dt>{{if
                    question.prompt
                    question.prompt
                    'Untitled question'
                  }}</dt>
                <dd>{{this.displayAnswer index}}</dd>
              </div>
            {{/each}}
          </dl>
          <Button
            @tone='neutral'
            @appearance='outlined'
            {{on 'click' this.restart}}
          >Start over</Button>
        </div>
      {{else}}
        <Wizard
          @steps={{this.steps}}
          @activeIndex={{this.currentStep}}
          @onStepChange={{this.onStepChange}}
          @onRefused={{this.onRefused}}
          @onComplete={{this.submit}}
          @busy={{this.saving}}
          @hideTitle={{true}}
          @label='Survey pages'
          @completeLabel='Submit'
        >
          <:step as |_step _index api|>
            {{#if this.isReview}}
              <div class='survey-review'>
                <h2 class='survey-review-title'>Review your answers</h2>
                {{#unless this.allRequiredMet}}
                  <Alert
                    @tone='warning'
                    @title='Some required questions still need an answer'
                    style={{ALERT_STYLE.attention}}
                  />
                {{/unless}}
                {{#each this.questions as |question index|}}
                  <button
                    type='button'
                    class='survey-review-row
                      {{if (this.isInvalid question index) "is-invalid"}}'
                    {{on 'click' (fn this.editAnswer index)}}
                  >
                    <span class='survey-review-q'>
                      {{if question.prompt question.prompt 'Untitled question'}}
                      {{#if question.required}}<span
                          class='survey-q-req'
                        >*</span>{{/if}}
                    </span>
                    <span class='survey-review-a'>{{this.displayAnswer
                        index
                      }}</span>
                    <span class='survey-review-edit'>Edit</span>
                  </button>
                {{/each}}
              </div>
            {{else}}
              {{! Delegated keydown: the handler only reads Enter bubbling up
                from the focusable inputs inside; the div itself is never a
                tab stop. }}
              {{! template-lint-disable no-invalid-interactive }}
              <div
                class='survey-questions'
                {{on 'keydown' (fn this.onKeydown api.next)}}
              >
                {{#each this.activePageItems as |item|}}
                  <fieldset class='survey-question'>
                    <div class='survey-q-num'>{{this.questionNumber
                        item.index
                      }}</div>
                    <legend class='survey-q-prompt'>
                      {{if
                        item.question.prompt
                        item.question.prompt
                        'Untitled question'
                      }}
                      {{#if item.question.required}}<span
                          class='survey-q-req'
                        >*</span>{{/if}}
                    </legend>
                    {{#if item.question.helpText}}
                      <p class='survey-q-help'>{{item.question.helpText}}</p>
                    {{/if}}
                    <QuestionInput
                      @question={{item.question}}
                      @value={{this.answerFor item.index}}
                      @onChange={{fn this.setAnswer item.index}}
                      @errorId={{this.errorIdFor item.index}}
                      @invalid={{this.isInvalid item.question item.index}}
                    />
                    {{#if (this.isInvalid item.question item.index)}}
                      <p
                        class='survey-q-error'
                        id={{this.errorIdFor item.index}}
                      >This question is required.</p>
                    {{/if}}
                  </fieldset>
                {{/each}}
              </div>
            {{/if}}
          </:step>
        </Wizard>
      {{/if}}
    </section>

    <style scoped>
      .survey {
        --survey-accent: var(--primary);
        container-type: inline-size;
        max-width: 52rem;
        margin: 0 auto;
        padding: var(--boxel-sp-lg);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-lg);
        color: var(--foreground);
        font-family: var(--font-sans);
      }
      .survey-header {
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
      }
      .survey-head-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
      }
      .survey-eyebrow {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        margin: 0;
        color: var(--primary-ink);
      }
      .survey-title {
        margin: 0;
        font-size: 1.6rem;
        font-weight: 800;
        letter-spacing: -0.02em;
      }
      .survey-desc {
        color: var(--muted-foreground);
        font-size: 0.95rem;
      }
      .survey-progress {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        margin-top: 0.4rem;
      }
      .survey-progress-bar {
        flex: 1;
        min-width: 0;
      }
      .survey-progress-label {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--muted-foreground);
        white-space: nowrap;
      }

      .survey-questions {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .survey-question {
        margin: 0;
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        background: var(--card);
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .survey-q-num {
        font-size: 0.625rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--primary-ink);
      }
      .survey-q-prompt {
        padding: 0;
        font-size: 1rem;
        font-weight: 600;
      }
      .survey-q-req {
        color: var(--destructive-ink);
        margin-left: 0.15rem;
      }
      .survey-q-help {
        margin: 0;
        font-size: 0.8125rem;
        color: var(--muted-foreground);
      }
      .survey-q-error {
        margin: 0;
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--destructive-ink);
      }

      .survey-review {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .survey-review-title {
        margin: 0 0 0.25rem;
        font-size: 1.1rem;
        font-weight: 700;
      }
      .survey-review-row {
        display: grid;
        grid-template-columns: 1fr auto auto;
        align-items: center;
        gap: var(--boxel-sp);
        width: 100%;
        padding: 0.6rem 0.75rem;
        border: 1px solid var(--border);
        border-radius: 0.5rem;
        background: var(--card);
        font: inherit;
        text-align: left;
        cursor: pointer;
        transition:
          border-color 0.15s ease,
          background 0.15s ease;
      }
      .survey-review-row:hover {
        border-color: var(--survey-accent);
        background: color-mix(in srgb, var(--survey-accent) 6%, transparent);
      }
      .survey-review-row.is-invalid {
        border-color: var(--destructive);
      }
      .survey-review-q {
        font-weight: 600;
        min-width: 0;
      }
      .survey-review-a {
        color: var(--primary-ink);
        font-weight: 600;
        text-align: right;
      }
      .survey-review-edit {
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }

      .survey-done {
        text-align: center;
        padding: var(--boxel-sp-xl) var(--boxel-sp);
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.5rem;
      }
      .survey-done-check {
        width: 3.5rem;
        height: 3.5rem;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 1.75rem;
        font-weight: 800;
        color: var(--success-foreground);
        background: var(--success);
        margin-bottom: 0.5rem;
      }
      .survey-done h2 {
        margin: 0;
      }
      .survey-done-sub {
        margin: 0;
        color: var(--muted-foreground);
      }
      .survey-done-list {
        margin: 0.75rem 0 0;
        width: 100%;
        max-width: 34rem;
        display: grid;
        gap: 0.4rem;
        text-align: left;
      }
      .survey-done-row {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: var(--boxel-sp);
        padding: 0.5rem 0.75rem;
        border: 1px solid var(--border);
        border-radius: 0.5rem;
      }
      .survey-done-row dt {
        font-weight: 600;
        min-width: 0;
      }
      .survey-done-row dd {
        margin: 0;
        font-weight: 600;
        color: var(--primary-ink);
        text-align: right;
      }
    </style>
  </template>
}
