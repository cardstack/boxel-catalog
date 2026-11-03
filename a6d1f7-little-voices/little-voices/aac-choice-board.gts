import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Textarea } from '@cardstack/pretui/components/textarea';
import ListChecksIcon from '@cardstack/boxel-icons/list-checks';
import Volume2Icon from '@cardstack/boxel-icons/volume-2';
import CheckIcon from '@cardstack/boxel-icons/check';
import { AacSymbol, SymbolTile, symbolImage, symbolSpeech } from './aac-symbol';
import { speak, stopSpeaking } from './speech';
import { playDing, playWrong } from './sounds';

const BLANK = '___';

// Who an activity's supports and questions are pitched at.
//   aac      — uses a communication device: big pictures, 2–3 picture choices
//   regular  — reading with picture cues: word cards, 3 choices
//   advanced — fluent reader: text only, vocabulary, rhyme, open writing
export const LEVELS = [
  { value: 'aac', label: 'AAC' },
  { value: 'regular', label: 'Regular' },
  { value: 'advanced', label: 'Advanced' },
];

export const LevelField = enumField(StringField, { options: LEVELS });

export function levelLabel(value?: string) {
  return LEVELS.find((l) => l.value === value)?.label ?? 'All levels';
}

interface PlayerSignature {
  Args: {
    board?: AacChoiceBoard;
    // Read the question aloud as soon as it appears (AAC and Regular).
    autoRead?: boolean;
    // Inside an activity the level is already chosen, so the tag is noise.
    hideLevel?: boolean;
  };
}

// A question, an optional sentence with one blank, and big choices: picture
// tiles, word buttons, or a writing box. With a right answer set, a wrong
// pick just fades out so the learner can try again — nothing is marked wrong.
export class ChoiceBoardPlayer extends GlimmerComponent<PlayerSignature> {
  @tracked picked: AacSymbol | undefined;
  @tracked pickedText: string | undefined;
  @tracked tried: string[] = [];
  @tracked written = '';

  constructor(owner: Owner, args: PlayerSignature['Args']) {
    super(owner, args);
    if (args.autoRead && args.board?.question) {
      setTimeout(() => speak(args.board?.question ?? ''), 350);
    }
  }

  get board() {
    return this.args.board;
  }

  get choices() {
    return (this.board?.choices ?? []).filter(Boolean) as AacSymbol[];
  }

  get textChoices() {
    return (this.board?.textChoices ?? []).filter(Boolean);
  }

  get isOpen() {
    return Boolean(this.board?.openEnded);
  }

  get correctSymbol() {
    return this.board?.correctChoice;
  }

  get correctText() {
    return this.board?.correctText?.trim().toLowerCase() || undefined;
  }

  get hasAnswer() {
    return Boolean(this.correctSymbol || this.correctText);
  }

  get answeredRight() {
    if (!this.hasAnswer) return false;
    if (this.picked && this.correctSymbol) {
      return this.picked.id === this.correctSymbol.id;
    }
    if (this.pickedText && this.correctText) {
      return this.pickedText.toLowerCase() === this.correctText;
    }
    return false;
  }

  get frameParts() {
    const frame = this.board?.sentenceFrame ?? '';
    const at = frame.indexOf(BLANK);
    if (at < 0) return { before: frame ? `${frame} ` : '', after: '' };
    return {
      before: frame.slice(0, at),
      after: frame.slice(at + BLANK.length),
    };
  }

  get answerWord() {
    if (this.isOpen) return this.written.trim();
    return this.picked ? symbolSpeech(this.picked) : (this.pickedText ?? '');
  }

  get pickedImage() {
    return symbolImage(this.picked);
  }

  get finishedSentence() {
    const { before, after } = this.frameParts;
    return `${before}${this.answerWord}${after}`;
  }

  get levelText() {
    return levelLabel(this.board?.level);
  }

  // Every good answer gets a ding: the right answer says "Yes!" and the
  // finished sentence; an opinion question (no wrong answer) dings too and
  // reads the child's sentence back.
  sayResult = (answer: string) => {
    const line = this.board?.sentenceFrame ? this.finishedSentence : answer;
    stopSpeaking();
    playDing().then(() => speak(this.answeredRight ? `Yes! ${line}` : line));
  };

  // Wrong answer: a gentle uh-oh, then "Try again!".
  sayTryAgain = () => {
    stopSpeaking();
    playWrong().then(() => speak('Try again!'));
  };

  askQuestion = () => {
    speak(this.board?.question ?? '');
  };

  pick = (symbol: AacSymbol) => {
    if (this.answeredRight) return;
    if (this.correctSymbol && symbol.id !== this.correctSymbol.id) {
      if (!this.tried.includes(symbol.id))
        this.tried = [...this.tried, symbol.id];
      this.sayTryAgain();
      return;
    }
    this.picked = symbol;
    this.sayResult(symbolSpeech(symbol));
  };

  pickText = (text: string) => {
    if (this.answeredRight) return;
    if (this.correctText && text.toLowerCase() !== this.correctText) {
      if (!this.tried.includes(text)) this.tried = [...this.tried, text];
      this.sayTryAgain();
      return;
    }
    this.pickedText = text;
    this.sayResult(text);
  };

  onWrite = (value: string) => {
    this.written = value;
  };

  readWriting = () => {
    speak(this.board?.sentenceFrame ? this.finishedSentence : this.written);
  };

  stateFor = (symbol: AacSymbol) => {
    if (this.tried.includes(symbol.id)) return 'dimmed';
    if (!this.picked) return undefined;
    if (this.picked !== symbol) return 'dimmed';
    return this.answeredRight ? 'correct' : 'selected';
  };

  textTried = (text: string) => this.tried.includes(text);

  textAppearance = (text: string) =>
    this.pickedText === text ? 'accent' : 'outlined';

  textTone = (text: string) => {
    if (this.pickedText !== text) return 'neutral';
    return this.answeredRight ? 'success' : 'primary';
  };

  // The chosen word paints itself (green when right, pumpkin for an
  // opinion) so it's obvious which one was picked.
  textClass = (text: string) => {
    if (this.pickedText !== text) return 'word-choice';
    return this.answeredRight
      ? 'word-choice is-right'
      : 'word-choice is-picked';
  };

  isRightText = (text: string) =>
    this.answeredRight && this.pickedText === text;

  get levelClass() {
    return `level-badge level-${this.board?.level ?? 'all'}`;
  }

  <template>
    <section class='board'>
      <header class='question'>
        <IconButton
          @label='Read the question'
          @tone='primary'
          @appearance='filled'
          @size='l'
          @shape='pill'
          {{on 'click' this.askQuestion}}
        >
          <Volume2Icon width='22' height='22' aria-hidden='true' />
        </IconButton>
        <h3>{{@board.question}}</h3>
        {{#if @board.level}}
          {{#unless @hideLevel}}
            <span class={{this.levelClass}}>{{this.levelText}}</span>
          {{/unless}}
        {{/if}}
      </header>

      {{#if @board.sentenceFrame}}
        <p class='sentence' aria-live='polite'>
          <span>{{this.frameParts.before}}</span>
          <span class='blank {{if this.answerWord "filled"}}'>
            {{#if this.pickedImage}}
              <img src={{this.pickedImage}} alt='' />
            {{/if}}
            <span class='blank-word'>{{if
                this.answerWord
                this.answerWord
                ' '
              }}</span>
          </span>
          <span>{{this.frameParts.after}}</span>
        </p>
      {{/if}}

      {{#if this.choices.length}}
        <div class='choices' role='group' aria-label={{@board.question}}>
          {{#each this.choices as |choice|}}
            <SymbolTile
              @symbol={{choice}}
              @size='l'
              @state={{this.stateFor choice}}
              @onActivate={{this.pick}}
            />
          {{/each}}
        </div>
      {{/if}}

      {{#if this.textChoices.length}}
        <div class='word-choices' role='group' aria-label={{@board.question}}>
          {{#each this.textChoices as |text|}}
            <Button
              @size='xl'
              @appearance={{this.textAppearance text}}
              @tone={{this.textTone text}}
              @disabled={{this.textTried text}}
              class={{this.textClass text}}
              {{on 'click' (fn this.pickText text)}}
            >
              {{#if (this.isRightText text)}}
                <CheckIcon width='22' height='22' aria-hidden='true' />
              {{/if}}
              {{text}}
            </Button>
          {{/each}}
        </div>
      {{/if}}

      {{#if this.isOpen}}
        <div class='writing'>
          <Textarea
            @value={{this.written}}
            @onInput={{this.onWrite}}
            @placeholder='Write your answer here…'
            aria-label={{@board.question}}
            class='writing-box'
          />
          <Button
            @tone='primary'
            @appearance='outlined'
            @size='l'
            {{on 'click' this.readWriting}}
          >
            <Volume2Icon width='18' height='18' aria-hidden='true' />
            Read my answer
          </Button>
          <p class='note'>There's no wrong answer — share it with a grown-up!</p>
        </div>
      {{/if}}

      {{#if this.answeredRight}}
        <p class='right' role='status'>
          <CheckIcon width='26' height='26' aria-hidden='true' />
          Yes! That's right.
        </p>
      {{/if}}

      {{#unless this.choices.length}}
        {{#unless this.textChoices.length}}
          {{#unless this.isOpen}}
            <p class='empty'>Add picture choices, word choices, or make this an
              open question.</p>
          {{/unless}}
        {{/unless}}
      {{/unless}}
    </section>
    <style scoped>
      .board {
        --primary: #f28c28;
        --primary-foreground: #2b1406;
        --success: #2f7d3a;
        --success-foreground: #ffffff;
        --ring: #9a3412;
        display: grid;
        gap: 1rem;
        padding: 1.25rem;
        border-radius: 1.25rem;
        background: var(--card, #fff);
        color: var(--card-foreground, #1d1d1b);
      }
      .question {
        display: flex;
        align-items: center;
        gap: 0.75rem;
      }
      h3 {
        margin: 0;
        flex: 1;
        font-size: 1.6rem;
        line-height: 1.2;
      }
      .level-chip {
        flex: none;
      }
      .sentence {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.4rem;
        margin: 0;
        font-size: 1.8rem;
        font-weight: 800;
      }
      .blank {
        display: inline-grid;
        justify-items: center;
        min-width: 5.5rem;
        padding: 0.25rem 0.5rem;
        border: 3px dashed var(--border, #c9c2b3);
        border-radius: 0.75rem;
      }
      .blank.filled {
        border-style: solid;
        border-color: var(--primary, #2b59c3);
      }
      .blank img {
        height: 3.5rem;
        object-fit: contain;
      }
      .blank-word {
        min-height: 1.3em;
      }
      .choices,
      .word-choices {
        display: flex;
        flex-wrap: wrap;
        gap: 1rem;
      }
      .word-choices {
        --pretui-size-xl: 1.5rem;
      }
      .level-badge {
        flex: none;
        padding: 0.3rem 0.8rem;
        border-radius: 999px;
        font-size: 0.95rem;
        font-weight: 700;
      }
      .level-aac {
        background: #fde7c8;
        color: #7a3a06;
      }
      .level-regular {
        background: #dcebff;
        color: #1d4a85;
      }
      .level-advanced {
        background: #e9ddff;
        color: #4b2a8a;
      }
      .word-choice.is-right {
        --pretui-button-bg: #2f7d3a;
        --pretui-button-fg: #ffffff;
        background: #2f7d3a;
        color: #ffffff;
        border-color: #2f7d3a;
      }
      .word-choice.is-picked {
        --pretui-button-bg: #f28c28;
        --pretui-button-fg: #2b1406;
        background: #f28c28;
        color: #2b1406;
        border-color: #f28c28;
      }
      .word-choice {
        --pretui-button-min-w: 8rem;
        font-weight: 700;
      }
      .writing {
        display: grid;
        gap: 0.75rem;
        justify-items: start;
      }
      .writing-box {
        width: 100%;
        font-size: 1.25rem;
      }
      .note,
      .empty {
        margin: 0;
        color: var(--muted-foreground, #6b6b6b);
      }
      .right {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        margin: 0;
        font-size: 1.4rem;
        font-weight: 800;
        color: var(--success, #2e9d4f);
      }
    </style>
  </template>
}

export class AacChoiceBoard extends CardDef {
  static displayName = 'AAC Question';
  static icon = ListChecksIcon;

  @field question = contains(StringField);
  // Which level sees this question in an activity; empty means every level.
  @field level = contains(LevelField);
  // Use ___ where the chosen word goes: "Pick a ___ pumpkin!"
  @field sentenceFrame = contains(StringField);
  // Picture choices (best for AAC and Regular).
  @field choices = linksToMany(() => AacSymbol);
  // Word choices with no pictures (best for Regular and Advanced).
  @field textChoices = containsMany(StringField);
  // Set one of these for a question with a right answer; leave both empty
  // for an opinion question ("What color is your pumpkin?").
  @field correctChoice = linksTo(() => AacSymbol);
  @field correctText = contains(StringField);
  // A writing box instead of choices, for open-ended thinking questions.
  @field openEnded = contains(BooleanField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AacChoiceBoard) {
      return (
        this.cardInfo?.name?.trim() ||
        this.question?.trim() ||
        `Untitled ${AacChoiceBoard.displayName}`
      );
    },
  });

  static isolated = class Isolated extends Component<typeof AacChoiceBoard> {
    get board() {
      return this.args.model as AacChoiceBoard;
    }
    <template>
      <div class='page'>
        <ChoiceBoardPlayer @board={{this.board}} />
      </div>
      <style scoped>
        .page {
          min-height: 100%;
          padding: 1.5rem;
          background: var(--background, #fffaf0);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof AacChoiceBoard> {
    get board() {
      return this.args.model as AacChoiceBoard;
    }
    <template><ChoiceBoardPlayer @board={{this.board}} /></template>
  };

  static fitted = class Fitted extends Component<typeof AacChoiceBoard> {
    get images() {
      return (this.args.model?.choices ?? [])
        .filter(Boolean)
        .slice(0, 3)
        .map((c) => symbolImage(c as AacSymbol))
        .filter(Boolean);
    }
    get words() {
      return (this.args.model?.textChoices ?? []).slice(0, 3).join(' · ');
    }
    get levelText() {
      return levelLabel(this.args.model?.level);
    }
    <template>
      <div class='fit'>
        <div class='pics'>
          {{#each this.images as |src|}}<img src={{src}} alt='' />{{else}}
            <span class='words'>{{this.words}}</span>
          {{/each}}
        </div>
        <div class='title'><@fields.cardTitle /></div>
        <div class='lvl'>{{this.levelText}}</div>
      </div>
      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: minmax(0, 1fr) auto auto;
          gap: 0.3rem;
          padding: 0.6rem;
          background: var(--card, #fff);
          color: var(--card-foreground, #1d1d1b);
          overflow: hidden;
        }
        .pics {
          display: flex;
          gap: 0.35rem;
          min-height: 0;
          align-items: center;
          justify-content: center;
          overflow: hidden;
        }
        .pics img {
          min-width: 0;
          height: 100%;
          object-fit: contain;
        }
        .words {
          font-weight: 800;
          text-align: center;
          overflow: hidden;
        }
        .title {
          font-weight: 800;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .lvl {
          font-size: 0.75rem;
          font-weight: 700;
          color: var(--muted-foreground, #6b6b6b);
        }
        @container fitted-card (height <= 80px) {
          .fit {
            grid-template-rows: none;
            grid-template-columns: auto minmax(0, 1fr);
            align-items: center;
          }
          .pics {
            height: 2.25rem;
          }
          .lvl {
            display: none;
          }
        }
      </style>
    </template>
  };
}
