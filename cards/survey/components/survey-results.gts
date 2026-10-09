import GlimmerComponent from '@glimmer/component';
import { type CardContext } from '@cardstack/base/card-api';
import { codeRef, type Query } from '@cardstack/runtime-common';
import { eq } from '@cardstack/boxel-ui/helpers';
import { BarList } from '@cardstack/pretui/components/bar-list';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Stat } from '@cardstack/pretui/components/stat';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import type { SurveyQuestion } from '../survey-question';

/* @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS */
const here: string = import.meta.url;
const surveyResponseRef = codeRef(here, '../survey-response', 'SurveyResponse');

interface AnswerLike {
  prompt?: string;
  response?: string;
}
interface ResponseLike {
  surveyId?: string;
  answers?: AnswerLike[];
}
interface OptionTally {
  label: string;
  count: number;
  pct: number;
}
interface Aggregate {
  prompt: string;
  kind: string;
  count: number;
  options: OptionTally[];
  average: number | null;
  texts: string[];
}

interface SurveyResultsSignature {
  Args: {
    surveyId: string | undefined;
    questions: SurveyQuestion[];
    realms: string[];
    context?: CardContext;
  };
  Element: HTMLElement;
}

export default class SurveyResults extends GlimmerComponent<SurveyResultsSignature> {
  get query(): Query {
    return {
      filter: {
        on: surveyResponseRef,
        eq: { 'survey.id': this.args.surveyId ?? '__no_survey__' },
      },
    };
  }

  search = this.args.context?.getCards(
    this,
    () => this.query,
    () => this.args.realms,
    { isLive: true },
  );

  get responses(): ResponseLike[] {
    return (this.search?.instances ?? []) as unknown as ResponseLike[];
  }

  get isLoading(): boolean {
    return Boolean(this.search?.isLoading);
  }

  get count(): number {
    return this.responses.length;
  }

  private valuesFor(prompt: string): string[] {
    let out: string[] = [];
    for (let r of this.responses) {
      let answer = (r.answers ?? []).find((a) => a.prompt === prompt);
      let v = answer?.response;
      if (v != null && v !== '' && v !== '—') out.push(v);
    }
    return out;
  }

  private tally(values: string[]): OptionTally[] {
    let total = values.length;
    let counts = new Map<string, number>();
    for (let v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
    return Array.from(counts.entries())
      .sort((a, b) => b[1] - a[1])
      .map(([label, count]) => ({
        label,
        count,
        pct: total ? Math.round((count / total) * 100) : 0,
      }));
  }

  get aggregates(): Aggregate[] {
    return this.args.questions.map((q) => {
      let prompt = q.prompt ?? '';
      let kind = q.kind ?? 'short-text';
      let values = this.valuesFor(prompt);
      let agg: Aggregate = {
        prompt,
        kind,
        count: values.length,
        options: [],
        average: null,
        texts: [],
      };

      if (kind === 'single-choice' || kind === 'yes-no') {
        agg.options = this.tally(values);
      } else if (kind === 'multi-choice') {
        // A response stores the picks joined by ", ". Matching the question's
        // own options keeps an option whose text has a comma in one piece.
        let known = ((q.options ?? []) as string[]).filter(Boolean);
        let expanded = values.flatMap((v) => {
          let padded = `, ${v}, `;
          let picked = known.filter((o) => padded.includes(`, ${o}, `));
          return picked.length
            ? picked
            : v
                .split(',')
                .map((s) => s.trim())
                .filter(Boolean);
        });
        agg.options = this.tally(expanded);
      } else if (kind === 'rating') {
        let nums = values
          .map((v) => parseInt(v, 10))
          .filter((n) => Number.isFinite(n));
        agg.average = nums.length
          ? Math.round((nums.reduce((a, b) => a + b, 0) / nums.length) * 10) /
            10
          : null;
        agg.options = [1, 2, 3, 4, 5].map((star) => {
          let count = nums.filter((n) => n === star).length;
          return {
            label: `${star}★`,
            count,
            pct: nums.length ? Math.round((count / nums.length) * 100) : 0,
          };
        });
      } else {
        agg.texts = values;
      }
      return agg;
    });
  }

  hasOptions = (agg: Aggregate): boolean => agg.options.length > 0;
  isText = (agg: Aggregate): boolean =>
    agg.kind === 'short-text' || agg.kind === 'long-text';

  barRows = (agg: Aggregate) =>
    agg.options.map((o) => ({ name: o.label, value: o.count }));

  // Bars measure the share of people who answered the question, so choice
  // bars across questions are comparable.
  barMax = (agg: Aggregate): number => Math.max(agg.count, 1);

  isRating = (agg: Aggregate): boolean => agg.kind === 'rating';

  <template>
    <div class='results' ...attributes>
      {{! Fed from a live query, so the digits do not roll. }}
      <Stat
        class='results-count'
        @label={{if this.isLoading 'Responses · updating' 'Responses'}}
        @value={{this.count}}
        @roll={{false}}
      />

      {{#if this.count}}
        <div class='results-list'>
          {{#each this.aggregates as |agg|}}
            <section class='agg'>
              <h3 class='agg-prompt'>{{if
                  agg.prompt
                  agg.prompt
                  'Untitled question'
                }}</h3>
              <p class='agg-meta'>
                {{agg.count}}
                answered
                {{#if (eq agg.kind 'rating')}}
                  {{#if agg.average}}· avg {{agg.average}} / 5{{/if}}
                {{/if}}
              </p>

              {{#if (this.isText agg)}}
                {{#if agg.texts.length}}
                  <ul class='agg-texts'>
                    {{#each agg.texts as |t|}}
                      <li>{{t}}</li>
                    {{/each}}
                  </ul>
                {{else}}
                  <p class='agg-empty'>No answers yet.</p>
                {{/if}}
              {{else if (this.hasOptions agg)}}
                <BarList
                  @rows={{this.barRows agg}}
                  @max={{this.barMax agg}}
                  @ranked={{if (this.isRating agg) false true}}
                  @label={{agg.prompt}}
                />
              {{else}}
                <p class='agg-empty'>No answers yet.</p>
              {{/if}}
            </section>
          {{/each}}
        </div>
      {{else}}
        <EmptyState
          @title='No responses yet'
          @message='Responses submitted to this survey appear here.'
          @texture={{false}}
          style={{COMPACT_EMPTY_STYLE}}
        />
      {{/if}}
    </div>

    <style scoped>
      .results {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        font-family: var(--font-sans);
        color: var(--foreground);
      }
      .results-list {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .agg {
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        background: var(--card);
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .agg-prompt {
        margin: 0;
        font-size: 1rem;
        font-weight: 700;
      }
      .agg-meta {
        margin: 0;
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .agg-texts {
        margin: 0;
        padding-left: 1.1rem;
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        font-size: 0.875rem;
      }
      .agg-texts li {
        color: var(--foreground);
      }
      .agg-empty {
        margin: 0;
        font-size: 0.8125rem;
        color: var(--muted-foreground);
        font-style: italic;
      }
    </style>
  </template>
}
