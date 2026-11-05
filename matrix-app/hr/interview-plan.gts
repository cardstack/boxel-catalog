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
import { tracked } from '@glimmer/tracking';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { Alert } from '../../ui-component/components/alert';
import { Avatar } from '../../ui-component/components/avatar';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { EmptyState } from '../../ui-component/components/empty-state';
import { FitTile } from '../../ui-component/components/fit-tile';
import { IconButton } from '../../ui-component/components/icon-button';
import { Panel } from '../../ui-component/components/panel';
import { ProgressBar } from '../../ui-component/components/progress-bar';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';

import {
  INTERVIEW_ROUND_LABELS,
  InterviewRoundField,
} from './interview-round-field';
import { Position } from './position';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import { QUIET_AVATAR_HUE } from './hr-ui';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';

// Category hues for a plan round's content (distinct from the candidate-stage
// and meeting-type maps). Kept exported for callers that colour a round.
export const INTERVIEW_ROUND_HUES: Record<string, Hue> = {
  'phone-screen': 'slate',
  technical: 'purple',
  onsite: 'blue',
  panel: 'teal',
  final: 'pink',
};

// A round's markdown is "## Section (n questions)" headings over numbered
// or bulleted questions; these read its shape for the summaries.
const HEADING_RE = /^#{1,6}\s+(.+)$/gm;
const QUESTION_RE = /^\s*(?:\d+[.)]|[-*+])\s+\S/gm;
const COUNT_NOTE_RE = /\s*\(\d+\s+questions?\)\s*$/i;

function plural(n: number, word: string): string {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

function roundLabelOf(type?: string | null): string | undefined {
  return type ? (INTERVIEW_ROUND_LABELS[type] ?? type) : undefined;
}

function sectionsOf(markdown?: string | null): string[] {
  return [...(markdown ?? '').matchAll(HEADING_RE)].map((m) =>
    m[1].replace(COUNT_NOTE_RE, '').trim(),
  );
}

function questionCountOf(markdown?: string | null): number {
  return (markdown ?? '').match(QUESTION_RE)?.length ?? 0;
}

function dateLabel(date?: Date | null, withYear = false): string | undefined {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
    return undefined;
  }
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    ...(withYear ? { year: 'numeric' } : {}),
  });
}

interface RoundSource {
  roundType?: string | null;
  questions?: string | null;
}

interface PlanSource {
  rounds?: RoundSource[] | null;
  createdDate?: Date | null;
}

// Everything the plan's formats print, read once from the model so the
// isolated, embedded, fitted and atom views can't disagree.
function planFacts(model?: PlanSource | null) {
  let rounds = (model?.rounds ?? []).map((round) => {
    let label = roundLabelOf(round?.roundType) ?? 'Untyped round';
    let questions = questionCountOf(round?.questions);
    return {
      label,
      sections: sectionsOf(round?.questions),
      questions,
      questionLine: plural(questions, 'question'),
    };
  });
  let sectionCount = rounds.reduce((n, r) => n + r.sections.length, 0);
  let questionCount = rounds.reduce((n, r) => n + r.questions, 0);
  let created = dateLabel(model?.createdDate);
  let createdFull = dateLabel(model?.createdDate, true);
  let roundLine = plural(rounds.length, 'round');
  let subline = [
    roundLine,
    sectionCount ? plural(sectionCount, 'section') : undefined,
    created ? `created ${created}` : undefined,
  ]
    .filter(Boolean)
    .join(' · ');
  // "Phone screen → technical → onsite → final", the last stop set apart
  let names = rounds.map((r, i) => (i === 0 ? r.label : r.label.toLowerCase()));
  let sequenceLast = names.length > 1 ? names[names.length - 1] : undefined;
  let sequenceHead = sequenceLast
    ? `${names.slice(0, -1).join(' → ')} → `
    : (names[0] ?? '');
  let span =
    rounds.length > 1
      ? `${rounds[0].label.toLowerCase()} to ${names[names.length - 1]}`
      : rounds[0]?.label.toLowerCase();
  let details: DescriptionsItem[] = [
    { label: 'Rounds', value: String(rounds.length), key: 'rounds' },
    ...rounds.map((r, i) => ({
      label: r.label,
      value: r.questionLine,
      key: `round-${i}`,
    })),
    ...(createdFull
      ? [{ label: 'Created', value: createdFull, key: 'created' }]
      : []),
  ];
  return {
    rounds,
    roundLine,
    sectionCount,
    questionCount,
    subline,
    sequenceHead,
    sequenceLast,
    span,
    created,
    createdYear: model?.createdDate?.getFullYear?.(),
    details,
    // the three heaviest rounds, for the fitted bars
    bars: [...rounds].sort((a, b) => b.questions - a.questions).slice(0, 3),
    maxQuestions: Math.max(1, ...rounds.map((r) => r.questions)),
  };
}

interface PlanChipsSignature {
  Args: { roundLine: string; department?: string | null };
}

const PlanChips: TemplateOnlyComponent<PlanChipsSignature> = <template>
  <StatusChip @value={{@roundLine}} @tone='neutral' />
  {{#if @department}}
    <StatusChip @value={{@department}} @tone='info' />
  {{/if}}
</template>;

const LINKED_ITEMS: DescriptionsItem[] = [{ label: 'Position' }];

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
    get label() {
      return roundLabelOf(this.args.model?.roundType);
    }
    get sectionLine(): string {
      return sectionsOf(this.args.model?.questions).join(' · ');
    }
    get questionLine(): string | undefined {
      let n = questionCountOf(this.args.model?.questions);
      return n ? plural(n, 'question') : undefined;
    }
    <template>
      <div class='ipr-row'>
        <div class='ipr-text'>
          <span class='ipr-title'>{{if
              this.label
              this.label
              'No round type set'
            }}</span>
          <span class='ipr-sub'>{{if
              @model.questions
              this.sectionLine
              'No questions written yet.'
            }}</span>
        </div>
        {{#if this.questionLine}}
          <StatusChip @value={{this.questionLine}} @tone='neutral' />
        {{/if}}
      </div>
      <style scoped>
        @layer PretComponent {
          .ipr-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-sm);
          }
          .ipr-text {
            display: grid;
            min-width: 0;
          }
          .ipr-title {
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            color: var(--foreground);
          }
          .ipr-sub {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            overflow-wrap: anywhere;
          }
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

  get facts() {
    return planFacts(this.args.model);
  }

  get department() {
    return this.args.model?.position?.department;
  }

  get createdYear() {
    let year = this.facts.createdYear;
    return year ? String(year) : undefined;
  }

  get sectionHint() {
    return `across ${plural(this.facts.sectionCount, 'section')}`;
  }

  <template>
    <article class='ip-iso'>
      <header class='ip-head'>
        <Avatar
          @name={{if @model.title @model.title 'Interview Plan'}}
          @hue={{QUIET_AVATAR_HUE}}
          @size={{48}}
          aria-hidden='true'
        />
        <div class='ip-id'>
          <h1>{{@model.title}}</h1>
          <p class='ip-sub'>{{this.facts.subline}}</p>
        </div>
        <div class='ip-chips'>
          <StatusChip @value={{this.facts.roundLine}} @tone='neutral' />
          {{#if this.department}}
            <StatusChip @value={{this.department}} @tone='info' />
          {{/if}}
        </div>
      </header>

      <div class='ip-stats'>
        <Stat
          @label='Rounds'
          @value={{this.facts.rounds.length}}
          @hint={{this.facts.span}}
          @roll={{false}}
        />
        <Stat
          @label='Questions'
          @value={{this.facts.questionCount}}
          @hint={{this.sectionHint}}
          @roll={{false}}
        />
        <Stat
          @label='Created'
          @value={{if this.facts.created this.facts.created '—'}}
          @hint={{this.createdYear}}
          @roll={{false}}
        />
      </div>

      <div class='ip-body'>
        <Panel @title='Rounds'>
          {{#if @model.rounds.length}}
            <ol class='rounds'>
              {{#each @fields.rounds as |RoundComponent index|}}
                <li class='round'>
                  <span class='round-index'>{{this.indexLabel index}}
                    &middot;</span>
                  <div class='round-body'>
                    <RoundComponent />
                  </div>
                  <div class='round-actions'>
                    <IconButton
                      @label='Move round up'
                      @size='s'
                      @disabled={{this.isFirst index}}
                      {{on 'click' (fn this.moveRound index -1)}}
                    >&uarr;</IconButton>
                    <IconButton
                      @label='Move round down'
                      @size='s'
                      @disabled={{this.isLast index}}
                      {{on 'click' (fn this.moveRound index 1)}}
                    >&darr;</IconButton>
                  </div>
                </li>
              {{/each}}
            </ol>
          {{else}}
            <EmptyState
              @texture={{false}}
              @title='No rounds added yet'
              @message='Running Generate questions from a candidate linked to this position will create the first round.'
            />
          {{/if}}
          {{#if this.reorderError}}
            <Alert
              class='notice'
              @tone='danger'
              style={{ALERT_STYLE.danger}}
            >{{this.reorderError}}</Alert>
          {{/if}}
        </Panel>

        <div class='ip-side'>
          <Panel @title='Linked'>
            <Descriptions @items={{LINKED_ITEMS}} @columns={{1}} @size='xl'>
              <:value>{{#if @model.position}}<@fields.position
                    @format='atom'
                  />{{else}}Not linked{{/if}}</:value>
            </Descriptions>
          </Panel>
          <Panel @title='Details'>
            <Descriptions
              @items={{this.facts.details}}
              @columns={{1}}
              @size='xl'
            />
          </Panel>
        </div>
      </div>
    </article>
    <style scoped>
      @layer PretComponent {
        .ip-iso {
          container-type: inline-size;
          height: 100%;
          overflow-y: auto;
          box-sizing: border-box;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp-lg);
          background-color: var(--canvas);
          color: var(--foreground);
        }
        .ip-head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp);
        }
        .ip-id {
          flex: 1 1 0;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          line-height: 1.25;
          color: var(--primary);
          overflow-wrap: anywhere;
        }
        .ip-sub {
          margin: var(--boxel-sp-6xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .ip-chips {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .ip-stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
          gap: var(--boxel-sp-lg);
        }
        .ip-body {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
          align-items: start;
          gap: var(--boxel-sp-lg);
        }
        .ip-side {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          min-width: 0;
        }
        @container (width < 45rem) {
          .ip-body {
            grid-template-columns: minmax(0, 1fr);
          }
        }
        .rounds {
          list-style: none;
          margin: 0;
          padding: 0;
        }
        .round {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-sm) 0;
          border-top: 1px solid var(--border);
        }
        .round:first-child {
          border-top: 0;
          padding-top: 0;
        }
        .round-index {
          flex: none;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .round-body {
          flex: 1;
          min-width: 0;
        }
        .round-actions {
          flex: none;
          align-self: center;
          display: flex;
          gap: var(--boxel-sp-4xs);
        }
        .notice {
          margin-top: var(--boxel-sp-xs);
        }
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
    get facts() {
      return planFacts(this.args.model);
    }
    <template>
      <article class='ip-emb'>
        <header class='ip-emb-head'>
          <Avatar
            @name={{if @model.title @model.title 'Interview Plan'}}
            @hue={{QUIET_AVATAR_HUE}}
            @size={{40}}
            aria-hidden='true'
          />
          <div class='ip-emb-id'>
            <h3 class='ip-emb-title'>{{@model.title}}</h3>
            <p class='ip-emb-sub'>{{this.facts.subline}}</p>
          </div>
          <div class='ip-emb-chips'>
            <StatusChip @value={{this.facts.roundLine}} @tone='neutral' />
            {{#if @model.position.department}}
              <StatusChip @value={{@model.position.department}} @tone='info' />
            {{/if}}
          </div>
        </header>
        {{#if this.facts.sequenceHead}}
          <p class='ip-emb-fact'>{{this.facts.sequenceHead}}<b
            >{{this.facts.sequenceLast}}</b></p>
        {{/if}}
        <Descriptions
          class='ip-emb-kv'
          @items={{this.facts.details}}
          @layout='vertical'
          @columns={{3}}
        />
        {{#if @model.position}}
          <p class='ip-emb-rels'>Position
            <@fields.position @format='atom' /></p>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .ip-emb {
            container-type: inline-size;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
            color: var(--foreground);
          }
          .ip-emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .ip-emb-id {
            flex: 1 1 0;
            min-width: 0;
          }
          .ip-emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.25;
            overflow-wrap: anywhere;
          }
          .ip-emb-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .ip-emb-chips {
            display: flex;
            flex-wrap: wrap;
            justify-content: flex-end;
            gap: var(--boxel-sp-4xs);
          }
          .ip-emb-fact,
          .ip-emb-rels {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .ip-emb-fact b {
            font-weight: 600;
            color: var(--foreground);
          }
          .ip-emb-kv {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
          }
          .ip-emb-rels {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          /* under 400 wide the chips drop under the name instead of cropping */
          @container (width < 25rem) {
            .ip-emb-head {
              flex-wrap: wrap;
            }
            .ip-emb-chips {
              flex-basis: 100%;
              justify-content: flex-start;
            }
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get roundLine() {
      return planFacts(this.args.model).roundLine;
    }
    <template>
      <span class='ip-atom'>
        <Avatar
          @name={{if @model.title @model.title 'Interview Plan'}}
          @hue={{QUIET_AVATAR_HUE}}
          @size={{20}}
          aria-hidden='true'
        />
        <span class='ip-atom-name'>{{@model.title}}</span>
        {{#if @model.rounds.length}}
          <StatusChip @value={{this.roundLine}} @tone='neutral' />
        {{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .ip-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .ip-atom-name {
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get facts() {
      return planFacts(this.args.model);
    }
    <template>
      {{! Under 170 tall FitTile budgets the four rows; from 170 tall the
          plan's own layout adds stats, bars and key facts by size. }}
      <div class='ipf-short'>
        <FitTile>
          <:avatar>
            <Avatar
              @name={{if @model.title @model.title 'Interview Plan'}}
              @hue={{QUIET_AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            />
          </:avatar>
          <:title><span
              class='ipf-title'
              role='heading'
              aria-level='3'
            >{{@model.title}}</span></:title>
          <:subtitle>{{this.facts.subline}}</:subtitle>
          <:status>
            <PlanChips
              @roundLine={{this.facts.roundLine}}
              @department={{@model.position.department}}
            />
          </:status>
          <:fact>{{this.facts.sequenceHead}}<b
              class='ipf-last'
            >{{this.facts.sequenceLast}}</b></:fact>
          <:relations><@fields.position @format='atom' /></:relations>
        </FitTile>
      </div>

      <article class='ipf-tall'>
        <div class='ipf-who'>
          <span class='ipf-av'>
            <Avatar
              @name={{if @model.title @model.title 'Interview Plan'}}
              @hue={{QUIET_AVATAR_HUE}}
              aria-hidden='true'
            />
          </span>
          <div class='ipf-id'>
            <div class='ipf-line1'>
              <span
                class='ipf-title'
                role='heading'
                aria-level='3'
              >{{@model.title}}</span>
              <span class='ipf-chips ipf-chips-inline'>
                <PlanChips
                  @roundLine={{this.facts.roundLine}}
                  @department={{@model.position.department}}
                />
              </span>
            </div>
            <span class='ipf-sub'>{{this.facts.subline}}</span>
          </div>
        </div>
        <span class='ipf-chips ipf-chips-row'>
          <PlanChips
            @roundLine={{this.facts.roundLine}}
            @department={{@model.position.department}}
          />
        </span>
        {{#if this.facts.sequenceHead}}
          <p class='ipf-fact'>{{this.facts.sequenceHead}}<b
              class='ipf-last'
            >{{this.facts.sequenceLast}}</b></p>
        {{/if}}
        <div class='ipf-stats'>
          <Stat @label='Rounds' @value={{this.facts.rounds.length}} />
          <Stat @label='Questions' @value={{this.facts.questionCount}} />
          <Stat
            @label='Created'
            @value={{if this.facts.created this.facts.created '—'}}
            @roll={{false}}
          />
        </div>
        <div class='ipf-bars'>
          {{#each this.facts.bars as |bar|}}
            <div class='ipf-bar'>
              <ProgressBar
                @label={{bar.label}}
                @count={{bar.questionLine}}
                @value={{bar.questions}}
                @max={{this.facts.maxQuestions}}
              />
            </div>
          {{/each}}
        </div>
        <dl class='ipf-kv'>
          {{#each this.facts.details as |item|}}
            <div class='ipf-kv-i'>
              <dt>{{item.label}}</dt>
              <dd>{{item.value}}</dd>
            </div>
          {{/each}}
        </dl>
        {{#if @model.position}}
          <p class='ipf-rel'><span
              class='ipf-k'
            >Position</span><@fields.position @format='atom' /></p>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .ipf-short {
            height: 100%;
          }
          .ipf-title {
            display: block;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .ipf-last {
            font-weight: 600;
            color: var(--foreground);
          }

          /* ── 170 tall and up ─────────────────────────────────────── */
          .ipf-tall {
            display: none;
            flex-direction: column;
            gap: var(--boxel-sp-xs);
            height: 100%;
            box-sizing: border-box;
            padding: var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.5;
            color: var(--card-foreground);
          }
          .ipf-tall > * {
            flex: none;
            min-width: 0;
          }
          .ipf-who {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
            min-width: 0;
          }
          .ipf-av {
            display: flex;
            --pretui-avatar-size: 2rem;
          }
          .ipf-id {
            flex: 1 1 auto;
            min-width: 0;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-6xs);
          }
          .ipf-line1 {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .ipf-line1 .ipf-title {
            flex: 1 1 auto;
            min-width: 7rem;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .ipf-sub,
          .ipf-fact {
            margin: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            color: var(--muted-foreground);
          }
          /* one line of chips: extras wrap out of sight whole */
          .ipf-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
            max-block-size: 1.375rem;
            overflow: hidden;
          }
          .ipf-chips-inline {
            display: none;
            flex: 0 1 auto;
          }
          .ipf-fact {
            font-variant-numeric: tabular-nums;
          }
          .ipf-stats,
          .ipf-bars,
          .ipf-kv,
          .ipf-bar,
          .ipf-kv-i {
            display: none;
          }
          .ipf-bars {
            flex-direction: column;
            gap: var(--boxel-sp-xs);
          }
          .ipf-stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--boxel-sp-sm);
          }
          .ipf-kv {
            margin: 0;
            grid-template-columns: minmax(0, 1fr);
            gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
          }
          .ipf-kv-i {
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            overflow: hidden;
            white-space: nowrap;
          }
          .ipf-kv dt {
            flex: none;
            color: var(--muted-foreground);
          }
          .ipf-kv dd {
            margin: 0;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          .ipf-rel {
            margin: 0;
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            line-height: 1.375rem;
            overflow: hidden;
            white-space: nowrap;
          }
          .ipf-k {
            flex: none;
            color: var(--muted-foreground);
          }

          @container fitted-card (height >= 170px) {
            .ipf-short {
              display: none;
            }
            .ipf-tall {
              display: flex;
            }
          }
          /* under 250 wide the avatar goes, unless the tile is tall enough
             to stack it above the title */
          @container fitted-card (width < 250px) {
            .ipf-av,
            .ipf-k {
              display: none;
            }
          }
          @container fitted-card (height >= 250px) {
            .ipf-tall {
              padding: var(--boxel-sp);
            }
            .ipf-av {
              --pretui-avatar-size: 2.5rem;
            }
            .ipf-kv {
              display: grid;
            }
            .ipf-kv-i:nth-child(-n + 1) {
              display: flex;
            }
          }
          @container fitted-card (height >= 250px) and (width < 250px) {
            .ipf-who {
              flex-direction: column;
              align-items: flex-start;
              gap: var(--boxel-sp-xs);
            }
            .ipf-id {
              width: 100%;
            }
            .ipf-av {
              display: flex;
            }
          }
          @container fitted-card (height >= 275px) {
            .ipf-kv-i:nth-child(-n + 2) {
              display: flex;
            }
          }
          @container fitted-card (height >= 275px) and (width >= 250px) {
            .ipf-kv-i:nth-child(-n + 4) {
              display: flex;
            }
          }
          /* 400 wide: state beside the title, key facts in two columns */
          @container fitted-card (width >= 400px) {
            .ipf-chips-inline {
              display: flex;
            }
            .ipf-chips-row {
              display: none;
            }
            .ipf-kv {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
            .ipf-kv-i:nth-child(-n + 2) {
              display: flex;
            }
          }
          @container fitted-card (width >= 400px) and (height < 250px) {
            .ipf-kv {
              order: 1;
            }
          }
          @container fitted-card (width >= 400px) and (height >= 275px) {
            .ipf-kv-i:nth-child(-n + 6) {
              display: flex;
            }
            .ipf-bars {
              display: flex;
            }
            .ipf-bar:nth-child(-n + 1) {
              display: block;
            }
          }
          @container fitted-card (width >= 400px) and (height >= 400px) {
            .ipf-stats {
              display: grid;
            }
            .ipf-bar:nth-child(-n + 3) {
              display: block;
            }
            .ipf-kv {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };
}
