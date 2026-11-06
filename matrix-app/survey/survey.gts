import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import ClipboardListIcon from '@cardstack/boxel-icons/clipboard-list';
import { SurveyQuestion, questionFacts } from './survey-question';
import { SurveyIsolated } from './components/isolated-template';
import { SurveyFitted } from './components/fitted-template';

export class Survey extends CardDef {
  static displayName = 'Survey';
  static icon = ClipboardListIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  @field description = contains(MarkdownField);
  @field questions = containsMany(SurveyQuestion);

  @field questionCount = contains(NumberField, {
    computeVia: function (this: Survey) {
      return this.questions?.length ?? 0;
    },
  });

  // Event fact, not a flag: PublishSurveyCommand writes this once and it is
  // monotonic — `isPublished` derives from it, so the boolean can never
  // drift from the event that made it true.
  @field publishedAt = contains(DateTimeField);

  @field isPublished = contains(BooleanField, {
    computeVia: function (this: Survey) {
      return Boolean(this.publishedAt);
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Survey) {
      return this.cardInfo?.name ?? this.title ?? 'Survey';
    },
  });

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Sv</span>
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          max-width: 100%;
          min-width: 0;
          font-size: 0.75rem;
          color: var(--card-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex-shrink: 0;
          width: 1.125rem;
          height: 1.125rem;
          border-radius: 0.25rem;
          background-color: var(--muted);
          font-size: 0.5625rem;
          font-weight: 700;
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get facts() {
      return questionFacts(this.args.model?.questions as SurveyQuestion[]);
    }
    <template>
      <article class='emb'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>Sv</span>
          <div class='id'>
            <h3 class='name'>{{@model.cardTitle}}</h3>
            <p class='meta'>{{this.facts.summary}}</p>
          </div>
          <span class='dot-text'><span
              class='dot {{if @model.isPublished "ok" "warn"}}'
            ></span>{{if @model.isPublished 'published' 'draft'}}</span>
        </header>
        <dl class='kv'>
          <dt>Questions</dt><dd>{{this.facts.total}}</dd>
          <dt>Required</dt><dd>{{this.facts.required}}</dd>
          <dt>Published</dt><dd>{{#if @model.publishedAt}}<@fields.publishedAt
              />{{else}}Not yet{{/if}}</dd>
          <dt>Rating</dt><dd>{{this.facts.rating}}</dd>
          <dt>Choice</dt><dd>{{this.facts.choice}}</dd>
        </dl>
      </article>
      <style scoped>
        .emb {
          font-size: 0.75rem;
          color: var(--card-foreground);
        }
        .head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex-shrink: 0;
          width: 1.5rem;
          height: 1.5rem;
          border-radius: 0.25rem;
          background-color: var(--muted);
          font-size: 0.625rem;
          font-weight: 700;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        .name,
        .meta {
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .name {
          font-size: 0.75rem;
          font-weight: 700;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .dot-text {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          flex-shrink: 0;
          font-weight: 600;
        }
        .dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
        .dot.ok {
          background-color: var(--success);
        }
        .dot.warn {
          background-color: var(--warning);
        }
        .kv {
          display: grid;
          grid-template-columns: 6rem minmax(0, 1fr);
          margin: 0;
          padding: 0 var(--boxel-sp-sm) var(--boxel-sp-4xs);
          border-top: 1px solid var(--border);
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-4xs) 0;
          min-width: 0;
        }
        .kv > :nth-child(n + 3) {
          border-top: 1px solid var(--border);
        }
        .kv dt {
          align-self: center;
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

Survey.isolated = SurveyIsolated;
Survey.fitted = SurveyFitted;
