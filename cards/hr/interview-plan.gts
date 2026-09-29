import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import MarkdownField from 'https://cardstack.com/base/markdown';
import ListChecksIcon from '@cardstack/boxel-icons/list-checks';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { tracked } from '@glimmer/tracking';

import { InterviewRoundField } from './interview-round-field';
import { Position } from './position';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import {
  stateColor,
  stateColorOf,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { pillStyle } from './utils';

// Colocated with InterviewPlanRoundField — colors each round's pill in the
// isolated plan list and the embedded/compact previews. Distinct hues from
// CANDIDATE_STAGE_COLORS/MEETING_TYPE_COLORS (this classifies a PLAN round's
// content, not a candidate's stage or a meeting's type), but the same
// stateColor()/stateColorOf() machinery from utils/index.
// Category hues only; the status hues follow the theme's status tokens.
export const INTERVIEW_ROUND_COLORS: Record<string, StateColor> = {
  'phone-screen': stateColor('slate'),
  technical: stateColor('purple'),
  onsite: stateColor('blue'),
  panel: stateColor('teal'),
  final: stateColor('pink'),
};

function questionsPreview(markdown?: string | null): string {
  if (!markdown) {
    return '';
  }
  let plain = markdown
    .replace(/^#+\s*/gm, '')
    .replace(/[*_`]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return plain.length > 140 ? `${plain.slice(0, 140)}…` : plain;
}

// One round's worth of interview content — which stage of the loop
// (InterviewRoundField, reused from meeting.gts's Meeting.roundType so the
// same vocabulary classifies both a scheduled Meeting and a plan's round)
// paired with the markdown question set for that stage. See
// GenerateInterviewQuestionsCommand for how these get created/upserted, and
// Meeting.interviewPlanRound for how a scheduled interview looks its own
// round's questions back up here.
export class InterviewPlanRoundField extends FieldDef {
  static displayName = 'Interview Plan Round';

  @field roundType = contains(InterviewRoundField);
  @field questions = contains(MarkdownField);

  static embedded = class Embedded extends Component<typeof this> {
    get pillStyle() {
      let c = stateColorOf(INTERVIEW_ROUND_COLORS, this.args.model?.roundType);
      return pillStyle(c);
    }
    get preview(): string {
      return questionsPreview(this.args.model?.questions);
    }
    <template>
      <div class='ipr-row'>
        <div class='ipr-top'>
          {{#if @model.roundType}}
            <span class='ipr-pill' style={{this.pillStyle}}>
              <span class='ipr-dot'></span>{{@model.roundType}}
            </span>
          {{else}}
            <span class='ipr-empty'>No round type set</span>
          {{/if}}
        </div>
        {{#if @model.questions}}
          <p class='ipr-preview'>{{this.preview}}</p>
        {{else}}
          <p class='ipr-empty'>No questions written yet.</p>
        {{/if}}
      </div>
      <style scoped>
        .ipr-row {
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
        }
        .ipr-top {
          display: flex;
          align-items: center;
        }
        .ipr-pill {
          display: inline-flex;
          align-items: center;
          gap: 0.3rem;
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          padding: 0.18em 0.5em;
          border-radius: 0.1875rem;
          white-space: nowrap;
        }
        .ipr-dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
          background-color: currentColor;
          flex: none;
        }
        .ipr-preview {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
          color: var(--muted-foreground);
        }
        .ipr-empty {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

// A structured set of interview questions for one Position, organized into
// rounds (InterviewPlanRoundField). Array order IS the loop order — there is
// no separate integer `order` field, so reordering the `rounds` array (via
// the move up/down controls in the isolated view) is the only mechanism for
// resequencing the loop.
// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class InterviewPlanIsolated extends Component<typeof InterviewPlan> {
  @tracked reorderError: string | undefined;

  isFirst = (index: number): boolean => index === 0;
  isLast = (index: number): boolean => {
    let n = this.args.model?.rounds?.length ?? 0;
    return index === n - 1;
  };

  indexLabel = (index: number): number => index + 1;

  moveRound = (index: number, direction: -1 | 1) => {
    void this.moveRoundTask(index, direction);
  };

  private moveRoundTask = async (index: number, direction: -1 | 1) => {
    let model = this.args.model;
    let rounds = model?.rounds ?? [];
    let target = index + direction;
    if (!model || target < 0 || target >= rounds.length) {
      return;
    }
    let reordered = rounds.slice();
    [reordered[index], reordered[target]] = [
      reordered[target],
      reordered[index],
    ];
    model.rounds = reordered;

    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      return;
    }
    this.reorderError = undefined;
    try {
      await new SaveCardCommand(commandContext).execute({
        card: model as InterviewPlan,
      });
    } catch (error: any) {
      this.reorderError = error?.message ?? String(error);
    }
  };

  <template>
    <article class='interview-plan-isolated'>
      <header class='hero'>
        <div class='hero-text'>
          <h1>{{@model.title}}</h1>
          <p class='byline'>
            {{#if @model.createdDate}}
              created
              <@fields.createdDate />
            {{else}}
              Not yet created
            {{/if}}
            <span class='sep-dot'>&middot;</span>
            {{if @model.roundTally @model.roundTally '0'}}
            round{{unless (eq @model.roundTally '1') 's'}}
          </p>
        </div>
      </header>

      <div class='body'>
        <h2 class='panel-title'>Interview loop</h2>
        {{#if @model.rounds.length}}
          <ol class='rounds'>
            {{#each @fields.rounds as |RoundComponent index|}}
              <li class='round'>
                <span class='round-index'>{{this.indexLabel index}}</span>
                <div class='round-body'>
                  <RoundComponent />
                </div>
                <div class='round-actions'>
                  <button
                    type='button'
                    class='reorder'
                    aria-label='Move round up'
                    disabled={{this.isFirst index}}
                    {{on 'click' (fn this.moveRound index -1)}}
                  >&uarr;</button>
                  <button
                    type='button'
                    class='reorder'
                    aria-label='Move round down'
                    disabled={{this.isLast index}}
                    {{on 'click' (fn this.moveRound index 1)}}
                  >&darr;</button>
                </div>
              </li>
            {{/each}}
          </ol>
        {{else}}
          <p class='empty'>No rounds added yet. Running Generate questions from
            a candidate linked to this position will create the first round.</p>
        {{/if}}
        {{#if this.reorderError}}
          <p class='reorder-error' role='alert'>{{this.reorderError}}</p>
        {{/if}}

        <h2 class='panel-title spaced'>Position</h2>
        <dl class='facts stacked'>
          <dt>Requisition</dt>
          <dd>{{#if @model.position}}<@fields.position
                @format='atom'
                @displayContainer={{false}}
              />{{else}}&mdash; not linked{{/if}}</dd>
        </dl>
      </div>
    </article>
    <style scoped>
      .interview-plan-isolated {
        container-type: inline-size;
        container-name: iso;
        height: 100%;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        --ip-id: var(--primary);
        --ip-strong: color-mix(in oklch, var(--ip-id) 45%, var(--foreground));
      }
      .hero {
        flex: none;
        padding: var(--boxel-sp-lg);
        border-bottom: 1px solid var(--border);
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
      .body {
        padding: var(--boxel-sp-lg);
      }
      .panel-title {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        font-weight: 700;
      }
      .panel-title.spaced {
        margin-top: var(--boxel-sp-lg);
      }
      .rounds {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 0;
      }
      .round {
        display: flex;
        align-items: flex-start;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) 0;
        border-bottom: 1px solid var(--border);
      }
      .round:last-child {
        border-bottom: 0;
      }
      .round-index {
        flex: none;
        width: 1.5rem;
        height: 1.5rem;
        border-radius: 50%;
        display: grid;
        place-items: center;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        background-color: var(--ip-strong);
        color: var(--background);
      }
      .round-body {
        flex: 1;
        min-width: 0;
      }
      .round-actions {
        flex: none;
        display: flex;
        flex-direction: column;
        gap: 0.2rem;
      }
      .reorder {
        min-width: 1.75rem;
        min-height: 1.75rem;
        padding: 0.2rem 0.4rem;
        border-radius: var(--boxel-border-radius-sm);
        border: 1px solid var(--border);
        background-color: var(--card);
        color: var(--ip-strong);
        font: inherit;
        font-size: var(--boxel-font-size-sm);
        cursor: pointer;
      }
      .reorder:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: 0.125rem;
      }
      .reorder:disabled {
        opacity: 0.4;
        cursor: not-allowed;
      }
      .reorder-error {
        margin: var(--boxel-sp-xs) 0 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--destructive-ink);
      }
      .empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .facts {
        margin: 0;
        display: grid;
        grid-template-columns: 1fr;
      }
      .facts dt {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
        padding-top: 0.4rem;
      }
      .facts dd {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        overflow-wrap: anywhere;
      }
    </style>
  </template>
}

export class InterviewPlan extends CardDef {
  static displayName = 'Interview Plan';
  static icon = ListChecksIcon;

  @field position = linksTo(() => Position);
  @field rounds = containsMany(InterviewPlanRoundField);
  @field createdDate = contains(DateField);

  @field title = contains(StringField, {
    computeVia: function (this: InterviewPlan) {
      let positionTitle = this.position?.title;
      return positionTitle
        ? `Interview Plan — ${positionTitle}`
        : 'Untitled Interview Plan';
    },
  });

  @field roundTally = contains(StringField, {
    computeVia: function (this: InterviewPlan) {
      let n = this.rounds?.length ?? 0;
      return n === 0 ? '' : String(n);
    },
  });

  static isolated = InterviewPlanIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='interview-plan-embedded'>
        <span class='ipe-icon'><ListChecksIcon class='ipe-icon-svg' /></span>
        <div class='ipe-main'>
          <span class='ipe-title'>{{@model.title}}</span>
          <span class='ipe-sub'>{{if @model.roundTally @model.roundTally '0'}}
            round{{unless (eq @model.roundTally '1') 's'}}</span>
        </div>
      </div>
      <style scoped>
        .interview-plan-embedded {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.75rem;
          font-size: 0.8125rem;
        }
        .ipe-icon {
          display: inline-flex;
          width: 1.75rem;
          height: 1.75rem;
          flex-shrink: 0;
          align-items: center;
          justify-content: center;
          border-radius: 50%;
          background-color: var(--muted);
          color: var(--muted-foreground);
        }
        .ipe-icon-svg {
          width: 0.875rem;
          height: 0.875rem;
        }
        .ipe-main {
          display: flex;
          flex-direction: column;
          gap: 0.0625rem;
          min-width: 0;
          flex: 1;
        }
        .ipe-title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .ipe-sub {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='interview-plan-atom'>
        <ListChecksIcon class='interview-plan-atom-icon' />
        <span class='interview-plan-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .interview-plan-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .interview-plan-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .interview-plan-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <div class='fit-top'>
          <span class='fit-icon'><ListChecksIcon /></span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{#if @model.roundTally}}
              <span class='fit-eb'>{{@model.roundTally}}
                round{{unless (eq @model.roundTally '1') 's'}}</span>
            {{/if}}
          </div>
        </div>
      </article>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.28rem;
          padding: 0.55rem 0.6rem;
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
          --fit-name: clamp(0.6875rem, 3.2cqi, 0.9375rem);
          --fit-small: clamp(0.6875rem, 2.6cqi, 0.75rem);
        }
        .fit-top {
          display: flex;
          align-items: center;
          gap: 0.4rem;
        }
        .fit-icon {
          flex: none;
          display: inline-flex;
          width: 1.4rem;
          height: 1.4rem;
          align-items: center;
          justify-content: center;
          border-radius: 50%;
          background-color: var(--muted);
          color: var(--muted-foreground);
        }
        .fit-icon svg {
          width: 0.75rem;
          height: 0.75rem;
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
        }
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
      </style>
    </template>
  };
}
