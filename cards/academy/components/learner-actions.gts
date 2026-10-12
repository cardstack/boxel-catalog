import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import {
  Button,
  BoxelInput,
  BoxelSelect,
} from '@cardstack/boxel-ui/components';

import SubmitAssignmentCommand from '../commands/submit-assignment-command';
import { QuizRunner } from './quiz-runner';
import {
  dueWindowState,
  dueWindowLabel,
} from '@cardstack/catalog/fields/due-window/due-window-field';
import { Submission } from '../submission';
import { QuizAttempt } from '../quiz-attempt';

interface Signature {
  Args: {
    enrollment: any;
    context?: any;
  };
  Element: HTMLElement;
}

/**
 * The learner's side of an enrolment: hand work in and sit quizzes. Only
 * released modules' assignments and quizzes are offered — the same release
 * events the timeline draws — so a learner cannot submit into a module the
 * instructor has not opened. Both writes go through their commands and the
 * refusal text (closed drop box, no attempts left) is shown as returned.
 */
export class LearnerActions extends GlimmerComponent<Signature> {
  @tracked assignment: any | undefined;
  @tracked text = '';
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked notice: string | undefined;
  @tracked openQuizId: string | undefined;
  private submissionsQ: ReturnType<getCards> | undefined;
  private attemptsQ: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    let ctx = this.args.context;
    if (!ctx?.getCards) return;
    // Captured once + lazy-cached thunks (see cohort-workspace for why).
    let eid = this.args.enrollment?.id as string | undefined;
    let url = this.args.enrollment?.[realmURL];
    let realmList = url ? [url.href] : undefined;
    let realms = () => realmList;
    let lazy = (cls: any) => () => {
      let ref = identifyCard(cls);
      return ref && eid
        ? { filter: { on: ref, eq: { 'enrollment.id': eid } } }
        : undefined;
    };
    this.submissionsQ = ctx.getCards(this, lazy(Submission), realms, {
      isLive: true,
    });
    this.attemptsQ = ctx.getCards(this, lazy(QuizAttempt), realms, {
      isLive: true,
    });
    void this.submissionsQ?.instances;
    void this.attemptsQ?.instances;
  }

  get priorSubmissions(): any[] {
    return ((this.submissionsQ?.instances ?? []) as any[]).filter(Boolean);
  }
  get priorAttempts(): any[] {
    return ((this.attemptsQ?.instances ?? []) as any[]).filter(Boolean);
  }
  attemptsUsedFor = (quiz: any) =>
    this.priorAttempts.filter((a) => a.quiz?.id === quiz.id).length;

  get cohort() {
    return this.args.enrollment?.cohort;
  }
  get releasedModules(): any[] {
    let released = new Set(
      ((this.cohort?.releases ?? []) as any[])
        .map((r) => r?.module?.id)
        .filter(Boolean),
    );
    return ((this.cohort?.course?.modules ?? []) as any[]).filter(
      (m) => m && released.has(m.id),
    );
  }
  get assignments(): any[] {
    return this.releasedModules.flatMap((m) =>
      (m.assignments ?? []).filter(Boolean),
    );
  }
  get quizzes(): any[] {
    return this.releasedModules.flatMap((m) =>
      (m.quizzes ?? []).filter(Boolean),
    );
  }
  get isActive() {
    return this.args.enrollment?.enrollmentStatus === 'active';
  }
  get realm() {
    return this.args.enrollment?.[realmURL]?.href;
  }

  pick = (a: any) => (this.assignment = a);
  setText = (v: string) => (this.text = v);
  toggleQuiz = (q: any) =>
    (this.openQuizId = this.openQuizId === q.id ? undefined : q.id);
  isOpen = (q: any) => this.openQuizId === q.id;
  label = (a: any) =>
    `${a.code ? a.code + ' · ' : ''}${a.title ?? a.cardTitle} — ${dueWindowLabel(dueWindowState(a.dueWindow))}`;

  submit = async () => {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      this.error = 'Commands are unavailable in this mode';
      return;
    }
    if (!this.assignment) {
      this.error = 'Pick an assignment first';
      return;
    }
    this.busy = true;
    this.error = undefined;
    this.notice = undefined;
    try {
      let res = (await new SubmitAssignmentCommand(ctx).execute({
        enrollment: this.args.enrollment,
        assignment: this.assignment,
        text: this.text || undefined,
        priorSubmissions: this.priorSubmissions,
        realm: this.realm,
      } as any)) as any;
      this.notice = res?.message;
      this.text = '';
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  <template>
    <div class='la' ...attributes>
      <section class='panel'>
        <h2>Hand in work</h2>
        {{#if this.isActive}}
          {{#if this.assignments.length}}
            <BoxelSelect
              @options={{this.assignments}}
              @selected={{this.assignment}}
              @onChange={{this.pick}}
              @placeholder='Choose an assignment'
              as |a|
            >{{this.label a}}</BoxelSelect>
            <BoxelInput
              @type='textarea'
              @value={{this.text}}
              @onInput={{this.setText}}
              @placeholder='Your answer (markdown). Attach files on the submission afterwards.'
            />
            <div class='row'>
              <Button
                class='cta'
                @kind='primary'
                @loading={{this.busy}}
                @disabled={{or this.busy (not this.assignment)}}
                {{on 'click' this.submit}}
              >Submit</Button>
              {{#if this.error}}<span
                  class='err'
                  role='alert'
                >{{this.error}}</span>{{/if}}
              {{#if this.notice}}<span
                  class='ok'
                  role='status'
                >{{this.notice}}</span>{{/if}}
            </div>
          {{else}}
            <p class='muted'>No assignments released yet.</p>
          {{/if}}
        {{else}}
          <p class='muted'>Only active enrolments can hand in work.</p>
        {{/if}}
      </section>

      <section class='panel'>
        <h2>Quizzes</h2>
        {{#if this.quizzes.length}}
          <ul class='quizzes'>
            {{#each this.quizzes as |q|}}
              <li>
                <button
                  type='button'
                  class='q-head'
                  aria-expanded={{if (this.isOpen q) 'true' 'false'}}
                  {{on 'click' (fn this.toggleQuiz q)}}
                >
                  <span class='q-title'>{{q.cardTitle}}</span>
                  <span class='q-meta'>{{q.questionCount}}
                    questions · pass
                    {{if q.passMarkPct q.passMarkPct 0}}%</span>
                  <span class='chev'>{{if (this.isOpen q) '−' '+'}}</span>
                </button>
                {{#if (this.isOpen q)}}
                  <div class='q-body'><QuizRunner
                      @quiz={{q}}
                      @enrollment={{@enrollment}}
                      @context={{@context}}
                      @attemptsUsed={{this.attemptsUsedFor q}}
                      @priorAttempts={{this.priorAttempts}}
                    /></div>
                {{/if}}
              </li>
            {{/each}}
          </ul>
        {{else}}
          <p class='muted'>No quizzes released yet.</p>
        {{/if}}
      </section>
    </div>
    <style scoped>
      .cta {
        min-height: 44px;
      }
      .la {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: var(--boxel-sp-sm);
        color: var(--foreground, var(--boxel-dark));
      }
      .panel {
        display: grid;
        gap: var(--boxel-sp-xs);
        align-content: start;
        padding: var(--boxel-sp);
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
        background: var(--card, var(--boxel-light));
      }
      h2 {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .row {
        display: flex;
        gap: var(--boxel-sp-sm);
        align-items: center;
        flex-wrap: wrap;
      }
      .muted {
        margin: 0;
        color: var(--muted-foreground, var(--boxel-450));
        font-size: var(--boxel-font-size-sm);
      }
      .err {
        font-size: var(--boxel-font-size-sm);
        color: color-mix(
          in oklab,
          var(--boxel-danger) 55%,
          var(--card-foreground, var(--boxel-dark))
        );
      }
      .ok {
        font-size: var(--boxel-font-size-sm);
        color: color-mix(
          in oklab,
          var(--boxel-success) 45%,
          var(--card-foreground, var(--boxel-dark))
        );
      }
      .quizzes {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .q-head {
        width: 100%;
        display: grid;
        grid-template-columns: 1fr auto auto;
        gap: var(--boxel-sp-xs);
        align-items: center;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius-sm));
        background: var(--muted, var(--boxel-100));
        color: inherit;
        font: inherit;
        text-align: start;
        cursor: pointer;
      }
      .q-head:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: 2px;
      }
      .q-title {
        font-weight: 600;
      }
      .q-meta,
      .chev {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .q-body {
        padding: var(--boxel-sp-sm) 0 0;
      }
      @container (width <= 700px) {
        .la {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

function or(...v: unknown[]) {
  return v.some(Boolean);
}
function not(v: unknown) {
  return !v;
}

export default LearnerActions;
