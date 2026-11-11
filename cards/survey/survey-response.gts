import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';
import { FitTile } from '../shared/fit-tile';
import { Survey } from './survey';

// The facts every format reads off the answers: the first 1–5 answer is the
// rating, the first yes/no answer is the "would you come again" signal.
function responseFacts(r?: SurveyResponse | null) {
  let answers = (r?.answers ?? []).filter(Boolean);
  let ratingRe = /^([1-5])(\s*\/\s*5)?$/;
  let rating = answers.find((a) => ratingRe.test((a.response ?? '').trim()));
  let yesNo = answers.find((a) =>
    /^(yes|no)$/i.test((a.response ?? '').trim()),
  );
  let n = answers.length;
  let count = `${n} ${n === 1 ? 'answer' : 'answers'}`;
  let score = rating ? `${ratingRe.exec(rating.response!.trim())![1]} / 5` : '';
  let asked = r?.survey?.questions?.length;
  return {
    answers,
    count,
    total: n,
    score,
    yesNo,
    asked: asked ? `of ${asked} questions` : 'submitted',
    summary: score ? `${count} · rated ${score}` : count,
  };
}

export class SurveyAnswer extends FieldDef {
  static displayName = 'Survey Answer';
  @field prompt = contains(StringField);
  @field response = contains(StringField);
}

export class SurveyResponse extends CardDef {
  static displayName = 'Survey Response';
  static icon = ClipboardCheckIcon;

  // The live link is what consumers query on (`survey.id`). surveyId and
  // surveyTitle are snapshots written on submit, for reading a response whose
  // survey can't be loaded.
  @field survey = linksTo(() => Survey, { searchable: true });
  @field surveyId = contains(StringField);
  @field surveyTitle = contains(StringField);
  @field answers = containsMany(SurveyAnswer);

  @field title = contains(StringField, {
    computeVia: function (this: SurveyResponse) {
      let name = this.survey?.title ?? this.surveyTitle;
      return name ? `Response: ${name}` : 'Survey Response';
    },
  });

  static atom = class Atom extends Component<typeof SurveyResponse> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Rs</span>
        <span class='name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          max-width: 100%;
          min-width: 0;
          font-size: var(--boxel-font-size-xs);
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
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
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

  static embedded = class Embedded extends Component<typeof SurveyResponse> {
    get facts() {
      return responseFacts(this.args.model as SurveyResponse);
    }
    <template>
      <article class='emb'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>Rs</span>
          <div class='id'>
            <h3 class='name'>{{@model.title}}</h3>
            <p class='meta'>{{this.facts.summary}}</p>
          </div>
          {{#if this.facts.score}}
            <span class='dot-text'><span
                class='dot ok'
              ></span>{{this.facts.score}}</span>
          {{/if}}
        </header>
        <dl class='kv'>
          {{#each this.facts.answers as |a|}}
            <dt>{{a.prompt}}</dt><dd>{{if a.response a.response '—'}}</dd>
          {{/each}}
          {{#if @model.survey}}
            <dt>Survey</dt><dd><@fields.survey
                @format='atom'
                @displayContainer={{false}}
              /></dd>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        .emb {
          font-size: var(--boxel-font-size-xs);
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
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
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
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
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
        .kv {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
          column-gap: var(--boxel-sp-sm);
          margin: 0;
          padding: 0 var(--boxel-sp-sm) var(--boxel-sp-4xs);
          border-top: 1px solid var(--border);
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-4xs) 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .kv > :nth-child(n + 3) {
          border-top: 1px solid var(--border);
        }
        .kv dt {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof SurveyResponse> {
    get facts() {
      return responseFacts(this.args.model as SurveyResponse);
    }
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>Rs</span></:avatar>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{this.facts.count}}</:subtitle>
        <:status><span class='dot-text'><span
              class='dot {{if this.facts.score "ok"}}'
            ></span>{{if
              this.facts.score
              this.facts.score
              this.facts.count
            }}</span></:status>
        <:fact>{{this.facts.summary}}</:fact>
        <:relations>{{#if @model.survey}}<@fields.survey
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
      <style scoped>
        .mark {
          display: inline-grid;
          place-items: center;
          width: 1.5rem;
          height: 1.5rem;
          border-radius: 0.25rem;
          background-color: var(--muted);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .dot-text {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          white-space: nowrap;
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
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof SurveyResponse> {
    get facts() {
      return responseFacts(this.args.model as SurveyResponse);
    }
    <template>
      <article class='rec'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>Rs</span>
          <div class='id'>
            <h1 class='name'>{{@model.title}}</h1>
            <p class='meta'>{{this.facts.summary}}</p>
          </div>
          <span class='sts'>
            {{#if this.facts.score}}
              <span class='dot-text'><span
                  class='dot ok'
                ></span>{{this.facts.score}}</span>
            {{/if}}
            <span class='dot-text'><span
                class='dot'
              ></span>{{this.facts.count}}</span>
          </span>
        </header>
        <dl class='stats' aria-label='Key numbers'>
          <div class='stat'>
            <dt>Rating</dt>
            <dd class='num'>{{if this.facts.score this.facts.score '—'}}</dd>
            <dd class='sub'>overall</dd>
          </div>
          <div class='stat'>
            <dt>Answers</dt>
            <dd class='num'>{{this.facts.total}}</dd>
            <dd class='sub'>{{this.facts.asked}}</dd>
          </div>
          {{#if this.facts.yesNo}}
            <div class='stat'>
              <dt>Yes / no</dt>
              <dd class='num'>{{this.facts.yesNo.response}}</dd>
              <dd class='sub'>{{this.facts.yesNo.prompt}}</dd>
            </div>
          {{/if}}
        </dl>
        <div class='cols'>
          <section class='main'>
            <h2>Answers <span class='count'>{{this.facts.total}}</span></h2>
            <ul class='rows'>
              {{#each this.facts.answers as |a|}}
                <li class='row'>
                  <span>{{if a.prompt a.prompt 'Question'}}</span>
                  <span class='ans'>{{if a.response a.response '—'}}</span>
                </li>
              {{else}}
                <li class='row muted'>No answers</li>
              {{/each}}
            </ul>
          </section>
          <aside class='side'>
            <section class='sec'>
              <h2>Linked</h2>
              <dl class='kv'>
                <dt>Survey</dt>
                <dd>{{#if @model.survey}}<@fields.survey
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}{{if
                      @model.surveyTitle
                      @model.surveyTitle
                      '—'
                    }}{{/if}}</dd>
              </dl>
            </section>
            <section class='sec'>
              <h2>Details</h2>
              <dl class='kv'>
                <dt>Rating</dt><dd>{{if
                    this.facts.score
                    this.facts.score
                    '—'
                  }}</dd>
                <dt>Answers</dt><dd>{{this.facts.total}}</dd>
                <dt>Survey</dt><dd>{{if
                    @model.surveyTitle
                    @model.surveyTitle
                    '—'
                  }}</dd>
              </dl>
            </section>
          </aside>
        </div>
      </article>
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
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .sts {
          display: flex;
          gap: var(--boxel-sp-xs);
        }
        .dot-text {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          font-weight: 600;
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
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
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
        h2 {
          display: flex;
          justify-content: space-between;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .count,
        .muted {
          font-weight: 400;
          color: var(--muted-foreground);
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
          padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
        }
        .ans {
          font-weight: 600;
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
          display: flex;
          align-items: center;
        }
      </style>
    </template>
  };
}
