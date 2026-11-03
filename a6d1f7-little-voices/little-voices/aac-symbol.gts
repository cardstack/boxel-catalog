import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import UrlField from '@cardstack/base/url';
import ImageDef from '@cardstack/base/image-file-def';
import enumField from '@cardstack/base/enum';
import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { cn, cssVar, eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { Chip } from '@cardstack/pretui/components/chip';
import MessageCircleIcon from '@cardstack/boxel-icons/message-circle';
import Volume2Icon from '@cardstack/boxel-icons/volume-2';
import { speak } from './speech';

// Modified Fitzgerald Key: the colour-coding most AAC systems share, so a
// learner who knows "green means doing words" keeps that knowledge here.
export const WORD_CLASSES = [
  { value: 'person', label: 'People', color: '#FFE36E' },
  { value: 'action', label: 'Actions (verbs)', color: '#8FDB8F' },
  { value: 'describe', label: 'Describing words', color: '#8EC5FF' },
  { value: 'thing', label: 'Things (nouns)', color: '#FFB866' },
  { value: 'social', label: 'Social words', color: '#FFA8D2' },
  { value: 'question', label: 'Questions', color: '#C9A8FF' },
  { value: 'stop', label: 'No / stop', color: '#FF8A8A' },
  { value: 'little', label: 'Little words', color: '#E4E4E4' },
];

const WordClassField = enumField(StringField, {
  options: WORD_CLASSES.map(({ value, label }) => ({ value, label })),
});

export function wordClassColor(value?: string) {
  return WORD_CLASSES.find((c) => c.value === value)?.color ?? '#E4E4E4';
}

export function wordClassLabel(value?: string) {
  return WORD_CLASSES.find((c) => c.value === value)?.label ?? 'Word';
}

export function symbolImage(symbol?: AacSymbol) {
  // A personal photo the family uploaded beats the generic pictogram.
  return symbol?.picture?.url || symbol?.pictogramURL || undefined;
}

export function symbolSpeech(symbol?: AacSymbol) {
  return symbol?.speakAs?.trim() || symbol?.label?.trim() || '';
}

interface SymbolTileSignature {
  Element: HTMLButtonElement;
  Args: {
    symbol?: AacSymbol;
    size?: 's' | 'm' | 'l';
    state?: 'active' | 'selected' | 'placed' | 'dimmed' | 'correct';
    hideLabel?: boolean;
    // Stretch to fill a grid cell instead of using a fixed size.
    fill?: boolean;
    onActivate?: (symbol: AacSymbol) => void;
  };
}

// The one tappable picture tile every AAC surface uses: picture on top, word
// below, Fitzgerald colour as the frame. Tapping speaks unless the caller
// handles activation itself.
export class SymbolTile extends GlimmerComponent<SymbolTileSignature> {
  get color() {
    return wordClassColor(this.args.symbol?.wordClass);
  }

  get image() {
    return symbolImage(this.args.symbol);
  }

  get label() {
    return this.args.symbol?.label ?? '';
  }

  activate = () => {
    const symbol = this.args.symbol;
    if (!symbol) return;
    if (this.args.onActivate) {
      this.args.onActivate(symbol);
    } else {
      speak(symbolSpeech(symbol));
    }
  };

  <template>
    <button
      type='button'
      class={{cn
        'symbol-tile'
        (concatSize @size)
        active=(eq @state 'active')
        selected=(eq @state 'selected')
        placed=(eq @state 'placed')
        dimmed=(eq @state 'dimmed')
        correct=(eq @state 'correct')
        fill=@fill
      }}
      style={{cssVar tile-color=this.color}}
      aria-label={{this.label}}
      aria-pressed={{if (eq @state 'selected') 'true'}}
      {{on 'click' this.activate}}
      ...attributes
    >
      {{#if (eq @state 'correct')}}
        <span class='badge' aria-hidden='true'>
          <svg
            width='20'
            height='20'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='4'
            stroke-linecap='round'
            stroke-linejoin='round'
          ><path d='M5 12l5 5L20 7' /></svg>
        </span>
      {{/if}}
      <span class='picture'>
        {{#if this.image}}
          <img src={{this.image}} alt='' draggable='false' />
        {{else}}
          <span class='no-picture'>{{this.label}}</span>
        {{/if}}
      </span>
      {{#unless @hideLabel}}
        <span class='word'>{{this.label}}</span>
      {{/unless}}
    </button>
    <style scoped>
      .symbol-tile {
        --tile-size: 7.5rem;
        display: grid;
        grid-template-rows: minmax(0, 1fr) auto;
        width: var(--tile-size);
        aspect-ratio: 5 / 6;
        padding: 0.35rem;
        gap: 0.2rem;
        border: 0.3rem solid var(--tile-color);
        border-radius: 1rem;
        background: var(--card, #fff);
        color: var(--card-foreground, #1d1d1b);
        font: inherit;
        cursor: pointer;
        touch-action: none;
        user-select: none;
        -webkit-user-select: none;
        transition:
          transform 140ms ease,
          box-shadow 140ms ease;
      }
      .symbol-tile.size-s {
        --tile-size: 5rem;
        border-width: 0.22rem;
        border-radius: 0.75rem;
      }
      .symbol-tile.size-l {
        --tile-size: 10rem;
      }
      .symbol-tile:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 14px rgb(0 0 0 / 12%);
      }
      .symbol-tile:focus-visible {
        outline: 3px solid var(--ring, #2b59c3);
        outline-offset: 3px;
      }
      .symbol-tile.active {
        transform: scale(1.08);
        box-shadow:
          0 0 0 0.3rem var(--tile-color),
          0 10px 22px rgb(0 0 0 / 18%);
      }
      .symbol-tile.selected {
        outline: 0.3rem solid var(--primary, #2b59c3);
        outline-offset: 0.2rem;
      }
      .symbol-tile.placed {
        cursor: default;
      }
      .symbol-tile {
        position: relative;
      }
      .symbol-tile.fill {
        --tile-size: 8rem;
        width: 100%;
        height: 100%;
        aspect-ratio: auto;
        min-height: 0;
      }
      .symbol-tile.correct {
        border-color: #2f7d3a;
        background: #e7f5e9;
        box-shadow: 0 0 0 0.3rem rgb(47 125 58 / 22%);
      }
      .badge {
        position: absolute;
        top: -0.85rem;
        right: -0.85rem;
        width: 2.6rem;
        height: 2.6rem;
        border-radius: 50%;
        background: #2f7d3a;
        color: #fff;
        border: 0.2rem solid #fff;
        display: grid;
        place-items: center;
      }
      .symbol-tile[data-dragging] {
        opacity: 0.4;
      }
      .symbol-tile.dimmed {
        opacity: 0.35;
      }
      .picture {
        position: relative;
        min-height: 0;
        overflow: hidden;
      }
      .picture img {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        object-fit: contain;
        pointer-events: none;
      }
      .picture .no-picture {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
      }
      .no-picture {
        font-size: 1.4em;
        font-weight: 800;
      }
      .word {
        font-size: calc(var(--tile-size) * 0.15);
        font-weight: 800;
        line-height: 1.1;
        text-align: center;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      @media (prefers-reduced-motion: reduce) {
        .symbol-tile {
          transition: none;
        }
      }
    </style>
  </template>
}

function concatSize(size?: string) {
  return `size-${size ?? 'm'}`;
}

class SymbolIsolated extends Component<typeof AacSymbol> {
  get symbol() {
    return this.args.model as AacSymbol;
  }
  get color() {
    return wordClassColor(this.args.model?.wordClass);
  }
  get classLabel() {
    return wordClassLabel(this.args.model?.wordClass);
  }
  say = () => {
    speak(symbolSpeech(this.args.model as AacSymbol));
  };

  <template>
    <article class='symbol-page' style={{cssVar tile-color=this.color}}>
      <SymbolTile @symbol={{this.symbol}} @size='l' />
      <div class='details'>
        <Chip @label={{this.classLabel}} class='class-chip' />
        <h1><@fields.cardTitle /></h1>
        {{#if @model.speakAs}}
          <p class='says'>Says: “{{@model.speakAs}}”</p>
        {{/if}}
        {{#if @model.alsoMatches.length}}
          <p class='matches'>Also matches:
            {{#each @model.alsoMatches as |word i|}}{{if
                i
                ', '
              }}{{word}}{{/each}}</p>
        {{/if}}
        <Button
          @tone='primary'
          @appearance='accent'
          @size='l'
          {{on 'click' this.say}}
        >
          <Volume2Icon width='20' height='20' aria-hidden='true' />
          Say it
        </Button>
        {{#unless @model.picture}}
          <p class='photo-tip'>Tip: add a real photo of the child's own
            {{@model.label}}
            in Edit → Picture. It replaces the drawing everywhere.</p>
        {{/unless}}
        {{#if @model.attribution}}
          <p class='credit'>{{@model.attribution}}</p>
        {{/if}}
      </div>
    </article>
    <style scoped>
      .symbol-page {
        --primary: #f28c28;
        --primary-foreground: #2b1406;
        --ring: #9a3412;
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 2rem;
        padding: 2rem;
        min-height: 100%;
        background: color-mix(
          in srgb,
          var(--tile-color) 18%,
          var(--background, #fffaf0)
        );
        color: var(--foreground, #1d1d1b);
      }
      .details {
        display: grid;
        gap: 0.75rem;
        justify-items: start;
      }
      h1 {
        margin: 0;
        font-size: 2.5rem;
        line-height: 1.1;
      }
      .class-chip {
        background: var(--tile-color);
        color: #1d1d1b;
      }
      .says,
      .matches {
        margin: 0;
        font-size: 1.1rem;
      }
      .photo-tip {
        margin: 0;
        max-width: 28rem;
        font-size: 0.95rem;
        color: var(--muted-foreground, #5d574e);
      }
      .credit {
        margin: 0;
        font-size: 0.75rem;
        color: var(--muted-foreground, #6b6b6b);
      }
    </style>
  </template>
}

export class AacSymbol extends CardDef {
  static displayName = 'AAC Symbol';
  static icon = MessageCircleIcon;

  @field label = contains(StringField);
  // What the voice says when it differs from the printed word ("I want").
  @field speakAs = contains(StringField);
  @field wordClass = contains(WordClassField);
  // Other spellings in a story that should show this picture ("brings").
  @field alsoMatches = containsMany(StringField);
  @field pictogramURL = contains(UrlField);
  @field picture = linksTo(() => ImageDef);
  @field attribution = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AacSymbol) {
      return (
        this.cardInfo?.name?.trim() ||
        this.label?.trim() ||
        `Untitled ${AacSymbol.displayName}`
      );
    },
  });

  static isolated = SymbolIsolated;

  static embedded = class Embedded extends Component<typeof AacSymbol> {
    get color() {
      return wordClassColor(this.args.model?.wordClass);
    }
    get image() {
      return symbolImage(this.args.model as AacSymbol);
    }
    <template>
      <div class='row' style={{cssVar tile-color=this.color}}>
        <span class='thumb'>
          {{#if this.image}}<img src={{this.image}} alt='' />{{/if}}
        </span>
        <span class='label'><@fields.cardTitle /></span>
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.5rem 0.75rem;
          border-left: 0.4rem solid var(--tile-color);
        }
        .thumb {
          width: 3rem;
          height: 3rem;
          flex: none;
        }
        .thumb img {
          width: 100%;
          height: 100%;
          object-fit: contain;
        }
        .label {
          font-size: 1.15rem;
          font-weight: 800;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof AacSymbol> {
    get color() {
      return wordClassColor(this.args.model?.wordClass);
    }
    get image() {
      return symbolImage(this.args.model as AacSymbol);
    }
    <template>
      <div class='fit' style={{cssVar tile-color=this.color}}>
        <span class='pic'>
          {{#if this.image}}<img src={{this.image}} alt='' />{{/if}}
        </span>
        <span class='word'><@fields.cardTitle /></span>
      </div>
      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: minmax(0, 1fr) auto;
          gap: 0.25rem;
          padding: 0.5rem;
          background: var(--card, #fff);
          color: var(--card-foreground, #1d1d1b);
          border-top: 0.45rem solid var(--tile-color);
          overflow: hidden;
        }
        .pic {
          display: grid;
          place-items: center;
          min-height: 0;
          overflow: hidden;
        }
        .pic img {
          max-width: 100%;
          max-height: 100%;
          object-fit: contain;
        }
        .word {
          font-weight: 800;
          text-align: center;
          font-size: 1rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        @container fitted-card (aspect-ratio > 1.6) or (height <= 80px) {
          .fit {
            grid-template-rows: none;
            grid-template-columns: auto minmax(0, 1fr);
            align-items: center;
            gap: 0.75rem;
            border-top: none;
            border-left: 0.45rem solid var(--tile-color);
            padding: 0.4rem 0.75rem 0.4rem 0.5rem;
          }
          .pic {
            height: 100%;
            aspect-ratio: 1;
          }
          .word {
            text-align: left;
            font-size: clamp(1rem, 22cqh, 2rem);
          }
        }
      </style>
    </template>
  };
}
