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
import {
  Wizard,
  type WizardChange,
  type WizardStep,
} from '@cardstack/pretui/components/wizard';
import { codeRef } from '@cardstack/runtime-common';
import { RelatedList, relatedSearch } from '../../crm/record-views';
import { questionFacts, questionSummary } from '../survey-question';
import QuestionInput from './question-input';
import SurveyResults from './survey-results';

interface PageItem {
  question: SurveyQuestion;
  index: number;
}

const PAGE_SIZE = 4;

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const moduleURL: string = import.meta.url;
const responseRef = codeRef(moduleURL, '../survey-response', 'SurveyResponse');

export class SurveyIsolated extends Component<typeof Survey> {
  @tracked currentStep = 0;
  @tracked answers: Record<number, unknown> = {};
  @tracked submitted = false;
  @tracked showErrors = false;
  @tracked saving = false;
  @tracked submitNote = '';
  @tracked mode: 'record' | 'fill' | 'results' = 'record';

  responseSearch = relatedSearch(
    this,
    this.args.context,
    () => this.args.model,
    responseRef.module,
    responseRef.name,
    'survey.id',
  );

  get responses(): any[] {
    return ((this.responseSearch?.instances ?? []) as any[]).filter(Boolean);
  }

  get responseLabel(): string {
    let n = this.responses.length;
    return `${n} ${n === 1 ? 'response' : 'responses'}`;
  }

  get facts() {
    return questionFacts(this.questions);
  }

  summaryOf = (q: SurveyQuestion) => questionSummary(q);

  @action
  publish() {
    this.args.model.publishedAt = new Date();
  }

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
  setMode(mode: 'record' | 'fill' | 'results') {
    this.mode = mode;
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
    {{#if (eq this.mode 'record')}}
      <article class='rec'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>Sv</span>
          <div class='id'>
            <h1 class='name'>{{@model.cardTitle}}</h1>
            <p class='meta'>{{this.facts.summary}}</p>
          </div>
          <span class='sts'>
            <span class='dot-text'><span
                class='dot {{if @model.isPublished "ok" "warn"}}'
              ></span>{{if @model.isPublished 'published' 'draft'}}</span>
            <span class='dot-text'><span
                class='dot'
              ></span>{{this.responseLabel}}</span>
          </span>
          <div class='acts'>
            <Button
              @size='s'
              @appearance='outlined'
              @tone='neutral'
              {{on 'click' (fn this.setMode 'results')}}
            >Results</Button>
            <Button
              @size='s'
              @appearance='outlined'
              @tone='neutral'
              {{on 'click' (fn this.setMode 'fill')}}
            >Take survey</Button>
            {{#unless @model.isPublished}}
              <Button
                @size='s'
                @tone='primary' @appearance='accent'
                {{on 'click' this.publish}}
              >Publish</Button>
            {{/unless}}
          </div>
        </header>
        <dl class='stats' aria-label='Key numbers'>
          <div class='stat'>
            <dt>Questions</dt>
            <dd class='num'>{{this.facts.total}}</dd>
            <dd class='sub'>{{this.facts.required}} required</dd>
          </div>
          <div class='stat'>
            <dt>Responses</dt>
            <dd class='num'>{{this.responses.length}}</dd>
            <dd class='sub'>collected</dd>
          </div>
          <div class='stat'>
            <dt>Status</dt>
            <dd class='num'>{{if @model.isPublished 'Published' 'Draft'}}</dd>
            <dd class='sub'>{{if
                @model.isPublished
                'open for answers'
                'not published'
              }}</dd>
          </div>
        </dl>
        <div class='cols'>
          <div class='main'>
            {{#if @model.description}}
              <section class='sec'>
                <h2>Description</h2>
                <div class='body'><@fields.description /></div>
              </section>
            {{/if}}
            <section class='sec'>
              <h2>Questions <span class='count'>{{this.facts.total}}</span></h2>
              <ul class='rows'>
                {{#each this.questions as |q|}}
                  <li class='row'>
                    <span class='q'>{{if
                        q.prompt
                        q.prompt
                        'Untitled question'
                      }}</span>
                    <span class='q-meta'>{{this.summaryOf q}}
                      <span class='dot-text'><span
                          class='dot {{if q.required "warn"}}'
                        ></span>{{if q.required 'required' 'optional'}}</span>
                    </span>
                  </li>
                {{else}}
                  <li class='row muted'>No questions yet</li>
                {{/each}}
              </ul>
            </section>
          </div>
          <aside class='side'>
            <section class='sec'>
              <RelatedList
                @title='Linked'
                @cards={{this.responses}}
                @empty='No responses yet'
              />
            </section>
            <section class='sec'>
              <h2>Details</h2>
              <dl class='kv'>
                <dt>Questions</dt><dd>{{this.facts.total}}</dd>
                <dt>Required</dt><dd>{{this.facts.required}}</dd>
                <dt>Responses</dt><dd>{{this.responses.length}}</dd>
                <dt>Published</dt><dd>{{#if
                    @model.publishedAt
                  }}<@fields.publishedAt />{{else}}Not yet{{/if}}</dd>
                <dt>Rating</dt><dd>{{this.facts.rating}}</dd>
                <dt>Free text</dt><dd>{{this.facts.text}}</dd>
                <dt>Choice</dt><dd>{{this.facts.choice}}</dd>
                <dt>Yes / no</dt><dd>{{this.facts.yesNo}}</dd>
              </dl>
            </section>
          </aside>
        </div>
      </article>
    {{else}}
      <section class='survey'>
        <header class='survey-header'>
          <div class='survey-head-top'>
            <h1 class='survey-title'>{{@model.cardTitle}}</h1>
            <Button
              @size='s'
              @appearance='outlined'
              @tone='neutral'
              {{on 'click' (fn this.setMode 'record')}}
            >Back to survey</Button>
          </div>
          {{#unless (eq this.mode 'results')}}
            <div class='survey-progress'>
              <ProgressBar
                class='survey-progress-bar'
                @value={{this.progressPct}}
                aria-label='Answered'
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
                        {{if
                          question.prompt
                          question.prompt
                          'Untitled question'
                        }}
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
                      <div class='survey-q-num'>{{this.questionNumber
                          item.index
                        }}</div>
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
    {{/if}}

    <style scoped>
      .rec {
        container-type: inline-size;
        margin: var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background-color: var(--card);
        color: var(--card-foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        overflow: hidden;
      }
      .head {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
      }
      .mark {
        display: inline-grid;
        place-items: center;
        flex-shrink: 0;
        width: 2rem;
        height: 2rem;
        border-radius: 0.375rem;
        background-color: var(--muted);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 700;
      }
      .id {
        flex: 1;
        min-width: 0;
      }
      .name {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .meta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .sts,
      .acts {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-shrink: 0;
      }
      .dot-text {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        font-weight: 600;
        color: var(--card-foreground);
      }
      .dot {
        width: 0.4375rem;
        height: 0.4375rem;
        border-radius: 50%;
        background-color: var(--muted-foreground);
      }
      .dot.ok {
        background-color: var(--success);
      }
      .dot.warn {
        background-color: var(--warning);
      }
      .stats {
        margin: 0;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
        border-bottom: 1px solid var(--border);
      }
      .stat {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-6xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-right: 1px solid var(--border);
        min-width: 0;
      }
      .stat dt,
      .stat dd {
        margin: 0;
      }
      .stat dt,
      .kv dt {
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .num {
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        line-height: 1.2;
        font-variant-numeric: tabular-nums;
      }
      .sub {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .cols {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      }
      .main {
        border-right: 1px solid var(--border);
      }
      @container (max-width: 44rem) {
        .cols {
          grid-template-columns: minmax(0, 1fr);
        }
        .main {
          border-right: 0;
          border-bottom: 1px solid var(--border);
        }
      }
      .sec + .sec {
        border-top: 1px solid var(--border);
      }
      .sec h2 {
        display: flex;
        justify-content: space-between;
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .count {
        font-weight: 400;
        color: var(--muted-foreground);
      }
      .body {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-top: 1px solid var(--border);
        line-height: 1.5;
      }
      .rows {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .row {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        gap: var(--boxel-sp-sm);
        align-items: center;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border-top: 1px solid var(--border);
      }
      .q-meta {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
      .muted {
        color: var(--muted-foreground);
      }
      .kv {
        display: grid;
        grid-template-columns: 8rem minmax(0, 1fr);
        margin: 0;
        padding: 0 var(--boxel-sp-sm) var(--boxel-sp-4xs);
      }
      .kv dt,
      .kv dd {
        margin: 0;
        padding: var(--boxel-sp-4xs) 0;
        border-top: 1px solid var(--border);
        min-width: 0;
      }
      .kv dt {
        align-self: stretch;
        display: flex;
        align-items: center;
      }
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
        gap: var(--boxel-sp-2xs);
      }
      .survey-head-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
      }
      .survey-title {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .survey-progress {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        margin-top: var(--boxel-sp-2xs);
      }
      .survey-progress-bar {
        flex: 1;
        min-width: 0;
      }
      .survey-progress-label {
        font-size: var(--boxel-font-size-xs);
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
        gap: var(--boxel-sp-xs);
      }
      .survey-q-num {
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--primary-ink);
      }
      .survey-q-prompt {
        padding: 0;
        font-size: var(--boxel-font-size);
        font-weight: 600;
      }
      .survey-q-req {
        color: var(--destructive-ink);
        margin-left: var(--boxel-sp-6xs);
      }
      .survey-q-help {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .survey-q-error {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--destructive-ink);
      }

      .survey-review {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .survey-review-title {
        margin: 0 0 var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size);
        font-weight: 700;
      }
      .survey-review-row {
        display: grid;
        grid-template-columns: 1fr auto auto;
        align-items: center;
        gap: var(--boxel-sp);
        width: 100%;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: 0.5rem;
        background: var(--card);
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        text-align: left;
        transition:
          border-color 0.15s ease,
          background 0.15s ease;
      }
      @media (hover: hover) {
        .survey-review-row:hover {
          border-color: var(--survey-accent);
          background: color-mix(in srgb, var(--survey-accent) 6%, transparent);
        }
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
        font-size: var(--boxel-eyebrow-font-size);
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
        gap: var(--boxel-sp-xs);
      }
      .survey-done-check {
        width: 3.5rem;
        height: 3.5rem;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: var(--boxel-font-size-xl);
        font-weight: 800;
        color: var(--success-foreground);
        background: var(--success);
        margin-bottom: var(--boxel-sp-xs);
      }
      .survey-done h2 {
        margin: 0;
      }
      .survey-done-sub {
        color: var(--muted-foreground);
      }
      .survey-done-list {
        margin: var(--boxel-sp-sm) 0 0;
        width: 100%;
        max-width: 34rem;
        display: grid;
        gap: var(--boxel-sp-2xs);
        text-align: left;
      }
      .survey-done-row {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
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
