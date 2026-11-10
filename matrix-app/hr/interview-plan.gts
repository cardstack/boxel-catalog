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
import { eq } from '@cardstack/boxel-ui/helpers';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
import { Alert } from '@cardstack/pretui/components/alert';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { type DescriptionsItem } from '@cardstack/pretui/components/descriptions';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import {
  EmbCard,
  FitCard,
  FitRow,
  IsoHead,
  IsoPage,
  Kv,
  kv,
  Panel,
  SheetEmpty,
  SheetLine,
  StatStrip,
  type StripItem,
} from './compact-sheet';

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
          <span class='ipr-count'>{{this.questionLine}}</span>
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
          .ipr-count {
            flex: none;
            font-weight: 500;
            font-size: var(--boxel-font-size-2xs);
            font-family: var(--font-mono);
            color: var(--muted-foreground);
          }
          .ipr-title {
            font-size: var(--boxel-font-size-xs);
            font-weight: 700;
            color: var(--foreground);
          }
          .ipr-sub {
            font-size: var(--boxel-font-size-2xs);
            color: var(--muted-foreground);
            overflow-wrap: break-word;
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

  get strip(): StripItem[] {
    let f = this.facts;
    return [
      {
        label: 'Rounds',
        value: String(f.rounds.length),
        hint: f.span,
        tone: 'neutral',
      },
      {
        label: 'Questions',
        value: String(f.questionCount),
        hint: this.sectionHint,
        tone: 'info',
      },
      { label: 'Created', value: f.created ?? '—', hint: this.createdYear },
    ];
  }

  <template>
    <IsoPage>
      <:head>
        <IsoHead @title={{@model.title}} @meta={{this.facts.subline}}>
          <:mark><Avatar
              @name={{if @model.title @model.title 'Interview Plan'}}
              @hue='var(--muted)'
              @shape='rounded'
              @size={{36}}
              aria-hidden='true'
            /></:mark>
          <:stats><StatStrip @items={{this.strip}} /></:stats>
        </IsoHead>
      </:head>
      <:main>
        <Panel @title='Rounds'>
          {{#each @fields.rounds as |RoundComponent index|}}
            <SheetLine>
              <span class='idx'>{{this.indexLabel index}} ·</span>
              <span class='round-body'><RoundComponent /></span>
              <IconButton
                @label='Move round up'
                @size='xs'
                @disabled={{this.isFirst index}}
                {{on 'click' (fn this.moveRound index -1)}}
              >&uarr;</IconButton>
              <IconButton
                @label='Move round down'
                @size='xs'
                @disabled={{this.isLast index}}
                {{on 'click' (fn this.moveRound index 1)}}
              >&darr;</IconButton>
            </SheetLine>
          {{else}}
            <SheetEmpty
              @title='No rounds added yet'
              @message='Generate questions from a candidate linked to this position creates the first round.'
            />
          {{/each}}
          {{#if this.reorderError}}
            <Alert
              @tone='danger'
              style={{ALERT_STYLE.danger}}
            >{{this.reorderError}}</Alert>
          {{/if}}
        </Panel>
      </:main>
      <:aside>
        <Panel @title='Linked'>
          <Kv @items={{kv LINKED_ITEMS}}>
            <:value>{{#if @model.position}}<@fields.position
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}Not linked{{/if}}</:value>
          </Kv>
        </Panel>
        <Panel @title='Details'><Kv @items={{kv this.facts.details}} /></Panel>
      </:aside>
    </IsoPage>
    <style scoped>
      .idx {
        font-weight: 500;
        font-size: var(--boxel-font-size-2xs);
        font-family: var(--font-mono);
        color: var(--muted-foreground);
      }
      .round-body {
        flex: 1 1 12rem;
        min-width: 0;
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
    get rows() {
      return [
        { key: 'Summary', value: this.facts.subline || '—' },
        ...kv(this.facts.details),
        { key: 'Position', value: '' },
      ];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{this.facts.subline}}>
        <:mark><Avatar
            @name={{if @model.title @model.title 'Interview Plan'}}
            @hue='var(--muted)'
            @shape='rounded'
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:default>
          <Kv @items={{this.rows}}>
            <:value as |row|>{{#if (eq row.key 'Position')}}{{#if
                  @model.position
                }}<@fields.position
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}{{else}}{{row.value}}{{/if}}</:value>
          </Kv>
        </:default>
      </EmbCard>
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
    get strip(): StripItem[] {
      let f = this.facts;
      return [
        { label: 'Rounds', value: String(f.rounds.length) },
        { label: 'Questions', value: String(f.questionCount) },
        { label: 'Created', value: f.created ?? '—' },
      ];
    }
    <template>
      <FitCard @title={{@model.title}}>
        <:mark><Avatar
            @name={{if @model.title @model.title 'Interview Plan'}}
            @hue='var(--muted)'
            @shape='rounded'
            @size={{20}}
            aria-hidden='true'
          /></:mark>
        <:default>
          <FitRow @left={{true}}><span
              class='meta'
            >{{this.facts.subline}}</span></FitRow>
          <FitRow @label='Rounds'>{{this.facts.roundLine}}</FitRow>
          {{#if @model.position}}
            <FitRow @label='Position' @left={{true}}><@fields.position
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/if}}
          <StatStrip @compact={{true}} @items={{this.strip}} />
          {{#each this.facts.rounds as |r|}}
            <FitRow @label={{r.label}}><span
                class='mono'
              >{{r.questionLine}}</span></FitRow>
          {{/each}}
        </:default>
      </FitCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .mono {
          font-weight: 500;
          font-size: var(--boxel-font-size-2xs);
          font-family: var(--font-mono);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
