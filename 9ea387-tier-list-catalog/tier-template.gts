import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksToMany,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { htmlSafe } from '@ember/template';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { restartableTask } from 'ember-concurrency';

import OneShotLlmRequestCommand from '@cardstack/boxel-host/commands/one-shot-llm-request';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';

import { Tier } from './tier';
import { TierItem } from './tier-item';
import ImageSourceField from '../fields/image-source/image-source';

const byOrder = (a: { sortOrder?: number }, b: { sortOrder?: number }) =>
  (a?.sortOrder ?? 0) - (b?.sortOrder ?? 0);

function styleColor(color?: string) {
  return htmlSafe(`background: ${color ?? 'transparent'}`);
}

function styleWidth(pct: number) {
  return htmlSafe(`width: ${pct}%`);
}

type GenItem = { name: string; imageUrl?: string };

// A preview tile shown while generating: name/image come from the LLM up front;
// `saved` flips true once the backing TierItem card is persisted.
type GenTile = { name: string; imageUrl?: string; saved: boolean };

// Defensively pull a JSON array of {name, imageUrl?} out of an LLM response —
// tolerates ```json fences and leading/trailing prose around the array.
function parseGenItems(raw: string): GenItem[] {
  let text = (raw ?? '').trim();
  let fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) {
    text = fence[1].trim();
  }
  let start = text.indexOf('[');
  let end = text.lastIndexOf(']');
  if (start !== -1 && end !== -1 && end > start) {
    text = text.slice(start, end + 1);
  }
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return [];
  }
  if (!Array.isArray(data)) {
    return [];
  }
  return data
    .map((d: any) => {
      let name = typeof d?.name === 'string' ? d.name.trim() : '';
      let imageUrl =
        typeof d?.imageUrl === 'string' && d.imageUrl.trim()
          ? d.imageUrl.trim()
          : undefined;
      return { name, imageUrl };
    })
    .filter((d) => d.name);
}

class TierTemplateIsolated extends Component<typeof TierTemplate> {
  @tracked broken = new Set<string>();
  markBroken = (id: string) => {
    this.broken = new Set(this.broken).add(id);
  };
  showImg = (item: TierItem): boolean => {
    return Boolean(item.image?.resolvedUrl) && !this.broken.has(item.id);
  };

  // --- AI pool generation --------------------------------------------
  // The model decides how many items the request naturally implies ("Gen 1
  // starters" → 3, "Studio Ghibli films" → ~25). We never ask the user for a
  // number; GEN_MAX is just a safety cap so an open-ended prompt can't mint
  // hundreds of cards in one click.
  @tracked genPrompt = '';
  @tracked genPhase: 'idle' | 'thinking' | 'creating' | 'linking' | 'error' =
    'idle';
  @tracked genError = '';
  @tracked genTiles: GenTile[] = [];
  @tracked genDoneCount = 0;
  genCanceled = false;

  get genBusy(): boolean {
    return (
      this.genPhase === 'thinking' ||
      this.genPhase === 'creating' ||
      this.genPhase === 'linking'
    );
  }
  get genHasError(): boolean {
    return this.genPhase === 'error';
  }
  get genIndeterminate(): boolean {
    // Before the model returns we don't know the count — show a moving bar.
    return this.genPhase === 'thinking';
  }
  get genTotal(): number {
    return this.genTiles.length;
  }
  get genPct(): number {
    return this.genTotal
      ? Math.round((this.genDoneCount / this.genTotal) * 100)
      : 0;
  }
  get genPhaseLabel(): string {
    switch (this.genPhase) {
      case 'thinking':
        return 'Thinking up items…';
      case 'creating':
        return `Creating ${this.genDoneCount} / ${this.genTotal}…`;
      case 'linking':
        return 'Adding to the pool…';
      default:
        return '';
    }
  }
  // Placeholder shimmer tiles shown during 'thinking', before we know N.
  get thinkingSlots(): number[] {
    return [0, 1, 2, 3, 4, 5];
  }

  setGenPrompt = (event: Event): void => {
    this.genPrompt = (event.target as HTMLInputElement).value;
  };
  runGenerate = (): void => {
    this.generateTask.perform();
  };
  // Cooperative cancel: reset the visible state immediately for instant
  // feedback; the running task checks `genCanceled` at each await boundary
  // and stops (still linking any cards it already created, so none orphan).
  cancelGenerate = (): void => {
    this.genCanceled = true;
    this.genPhase = 'idle';
    this.genTiles = [];
    this.genDoneCount = 0;
  };

  generateTask = restartableTask(async () => {
    this.genCanceled = false;
    this.genError = '';
    this.genTiles = [];
    this.genDoneCount = 0;
    let cx = this.args.context?.commandContext;
    let realm = (this.args.model as any)?.[realmURL]?.href;
    let prompt = this.genPrompt.trim();
    if (!cx || !realm) {
      this.genPhase = 'error';
      this.genError = 'No command context or realm available in this view.';
      return;
    }
    if (!prompt) {
      this.genPhase = 'error';
      this.genError = 'Describe the pool you want first.';
      return;
    }
    this.genPhase = 'thinking';
    try {
      let GEN_MAX = 50;
      let systemPrompt =
        'You generate items for a tier-list pool. Output ONLY a JSON array ' +
        '(no markdown, no prose) of objects with keys "name" (string, ' +
        'required) and "imageUrl" (string, optional). Include "imageUrl" ' +
        'ONLY when you are confident it is a real, stable, directly-loadable ' +
        'public image URL (e.g. a Wikimedia upload URL); otherwise omit it. ' +
        'Return the COMPLETE natural set the request implies — do not pad or ' +
        'truncate to a round number. If the request is open-ended or could ' +
        'be very large, return the ~20 most representative items. Never ' +
        `return more than ${GEN_MAX} items.`;

      let llm = new OneShotLlmRequestCommand(cx);
      let result = await llm.execute({
        systemPrompt,
        userPrompt: prompt,
        llmModel: 'anthropic/claude-haiku-4.5',
      });
      if (this.genCanceled) {
        return;
      }
      let output =
        (result as any)?.output ?? (result as any)?.attributes?.output ?? '';
      let entries = parseGenItems(String(output)).slice(0, GEN_MAX);
      if (!entries.length) {
        throw new Error('The model returned no usable items. Try rewording.');
      }

      // Reveal every item as a skeleton tile up front; fill each in as it saves.
      this.genTiles = entries.map((e) => ({
        name: e.name,
        imageUrl: e.imageUrl,
        saved: false,
      }));
      this.genPhase = 'creating';

      let made: TierItem[] = [];
      for (let i = 0; i < entries.length; i++) {
        if (this.genCanceled) {
          break;
        }
        let entry = entries[i];
        let item = new TierItem({
          name: entry.name,
          image: entry.imageUrl
            ? new ImageSourceField({ url: entry.imageUrl, sourceMode: 'url' })
            : undefined,
        });
        await new SaveCardCommand(cx).execute({ card: item, realm });
        made.push(item);
        if (this.genCanceled) {
          break;
        }
        this.genTiles = this.genTiles.map((t, idx) =>
          idx === i ? { ...t, saved: true } : t,
        );
        this.genDoneCount = i + 1;
      }

      // Link whatever was created — even on cancel — so no card is orphaned.
      if (made.length) {
        if (!this.genCanceled) {
          this.genPhase = 'linking';
        }
        this.args.model.items = [
          ...(this.args.model.items ?? []).filter(Boolean),
          ...made,
        ];
        await new SaveCardCommand(cx).execute({
          card: this.args.model as any,
          realm,
        });
      }

      if (!this.genCanceled) {
        this.genPrompt = '';
      }
      this.genPhase = 'idle';
      this.genTiles = [];
      this.genDoneCount = 0;
    } catch (err: any) {
      if (this.genCanceled) {
        this.genPhase = 'idle';
        this.genTiles = [];
        this.genDoneCount = 0;
        return;
      }
      this.genPhase = 'error';
      this.genError = err?.message ?? 'Generation failed.';
      this.genTiles = [];
      this.genDoneCount = 0;
    }
  });

  get sortedTiers(): Tier[] {
    return [...(this.args.model.tiers ?? [])].filter(Boolean).sort(byOrder);
  }

  get poolItems(): TierItem[] {
    return (this.args.model.items ?? []).filter(Boolean);
  }

  get count(): number {
    return this.poolItems.length;
  }

  <template>
    <section class='tpl'>
      <header class='tpl-head'>
        <h1><@fields.cardTitle /></h1>
        <p class='count'>{{this.count}} items</p>
      </header>

      <div class='gen'>
        <input
          class='gen-input'
          aria-label='Describe the pool to generate with AI'
          placeholder='Describe a pool — e.g. “Studio Ghibli films”'
          value={{this.genPrompt}}
          disabled={{this.genBusy}}
          {{on 'input' this.setGenPrompt}}
        />
        {{#if this.genBusy}}
          <button
            type='button'
            class='gen-btn gen-cancel'
            {{on 'click' this.cancelGenerate}}
          >
            Cancel
          </button>
        {{else}}
          <button
            type='button'
            class='gen-btn'
            {{on 'click' this.runGenerate}}
          >
            Generate with AI
          </button>
        {{/if}}
      </div>

      {{#if this.genBusy}}
        <div class='gen-progress' role='status' aria-live='polite'>
          <span
            class='bar {{if this.genIndeterminate "bar--indeterminate"}}'
          ><span class='bar-fill' style={{styleWidth this.genPct}}></span></span>
          <span class='gen-note'>{{this.genPhaseLabel}}</span>
        </div>
      {{else if this.genHasError}}
        <div class='gen-progress'>
          <span class='gen-err'>{{this.genError}}</span>
        </div>
      {{/if}}

      <div class='tiers'>
        {{#each this.sortedTiers as |tier|}}
          <span class='band' style={{styleColor tier.color}}>{{tier.label}}</span>
        {{/each}}
      </div>

      <div class='pool'>
        {{#if this.genBusy}}
          {{#if this.genTiles.length}}
            {{#each this.genTiles as |g|}}
              <div class='tile tile--gen {{unless g.saved "tile--pending"}}'>
                {{#if g.imageUrl}}
                  <img src={{g.imageUrl}} alt={{g.name}} class='tile-img' />
                {{else}}
                  <span class='tile-text'>{{g.name}}</span>
                {{/if}}
                <span class='tile-cap'>{{g.name}}</span>
                {{#unless g.saved}}<span class='tile-shimmer'></span>{{/unless}}
              </div>
            {{/each}}
          {{else}}
            {{#each this.thinkingSlots as |slot|}}
              <div class='tile tile--skel' data-slot={{slot}}>
                <span class='tile-shimmer'></span>
              </div>
            {{/each}}
          {{/if}}
        {{/if}}
        {{#each this.poolItems as |item|}}
          <div class='tile'>
            {{#if (this.showImg item)}}
              <img
                src={{item.image.resolvedUrl}}
                alt={{item.name}}
                class='tile-img'
                {{on 'error' (fn this.markBroken item.id)}}
              />
            {{else}}
              <span class='tile-text'>{{if item.name item.name '?'}}</span>
            {{/if}}
            {{#if item.name}}<span class='tile-cap'>{{item.name}}</span>{{/if}}
          </div>
        {{else}}
          {{#unless this.genBusy}}
            <p class='empty'>No items yet. Add TierItem cards to build the
              pool.</p>
          {{/unless}}
        {{/each}}
      </div>
    </section>
    <style scoped>
      .tpl {
        height: 100%;
        min-height: 0;
        display: grid;
        grid-template-rows: auto auto auto minmax(0, 1fr);
        background: var(--background, #15161a);
        color: var(--foreground, #f4f5f7);
        font-family: var(--font-sans, system-ui, sans-serif);
      }
      .gen {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 0.375rem;
        padding: 0.5rem 1rem;
        border-bottom: 1px solid var(--border, #2c2e36);
      }
      .gen-input {
        flex: 1 1 14rem;
        min-width: 0;
        padding: 0.3125rem 0.5rem;
        font: inherit;
        font-size: 0.8125rem;
        color: var(--foreground, #f4f5f7);
        background: var(--background, #15161a);
        border: 1px solid var(--border, #2c2e36);
        border-radius: var(--radius, 0.375rem);
      }
      .gen-input::placeholder {
        color: var(--muted-foreground, #9aa0ad);
      }
      .gen-input:disabled {
        opacity: 0.6;
        cursor: default;
      }
      .gen-btn {
        padding: 0.3125rem 0.75rem;
        font: inherit;
        font-size: 0.8125rem;
        font-weight: 600;
        cursor: pointer;
        color: var(--primary-foreground, #15161a);
        background: var(--primary, #f4f5f7);
        border: 1px solid transparent;
        border-radius: var(--radius, 0.375rem);
      }
      .gen-btn:disabled {
        cursor: default;
        opacity: 0.6;
      }
      .gen-cancel {
        color: var(--foreground, #f4f5f7);
        background: transparent;
        border-color: var(--border, #2c2e36);
      }
      .gen-progress {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        padding: 0.375rem 1rem 0.5rem;
      }
      .bar {
        position: relative;
        flex: 1 1 auto;
        height: 6px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--border, #2c2e36);
      }
      .bar-fill {
        display: block;
        height: 100%;
        border-radius: inherit;
        background: var(--primary, #f4f5f7);
        transition: width 0.3s ease;
      }
      .bar--indeterminate {
        background: linear-gradient(
          90deg,
          var(--border, #2c2e36) 0%,
          var(--primary, #f4f5f7) 50%,
          var(--border, #2c2e36) 100%
        );
        background-size: 200% 100%;
        animation: tier-indeterminate 1.1s linear infinite;
      }
      .bar--indeterminate .bar-fill {
        display: none;
      }
      .gen-note {
        font-size: 0.75rem;
        color: var(--muted-foreground, #9aa0ad);
      }
      .gen-err {
        font-size: 0.75rem;
        color: var(--destructive, #e5484d);
      }
      .tpl-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 1rem;
        padding: 0.875rem 1rem;
        border-bottom: 1px solid var(--border, #2c2e36);
        background: var(--card, #1c1e24);
      }
      h1 {
        margin: 0;
        font-size: 1.125rem;
      }
      .count {
        margin: 0;
        font-size: 0.8125rem;
        color: var(--muted-foreground, #9aa0ad);
      }
      .tiers {
        display: flex;
        flex-wrap: wrap;
        gap: 0.25rem;
        padding: 0.5rem 1rem;
      }
      .band {
        min-width: 2rem;
        padding: 0.125rem 0.5rem;
        font-weight: 800;
        text-align: center;
        color: #111;
        border-radius: 0.25rem;
      }
      .pool {
        min-height: 0;
        overflow: auto;
        display: flex;
        flex-wrap: wrap;
        align-content: flex-start;
        gap: 0.375rem;
        padding: 0.75rem 1rem;
      }
      .tile {
        position: relative;
        width: 4rem;
        height: 4rem;
        display: flex;
        align-items: center;
        justify-content: center;
        overflow: hidden;
        background: var(--card, #1c1e24);
        border: 1px solid var(--border, #2c2e36);
        border-radius: 0.25rem;
      }
      .tile-img {
        width: 100%;
        height: 100%;
        object-fit: contain;
      }
      .tile-text {
        padding: 0.25rem;
        font-size: 0.75rem;
        font-weight: 600;
        text-align: center;
      }
      .tile-cap {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        padding: 0.0625rem 0.125rem;
        font-size: 0.5625rem;
        text-align: center;
        color: #fff;
        background: rgba(0, 0, 0, 0.6);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .empty {
        color: var(--muted-foreground, #9aa0ad);
      }
      .tile--pending {
        opacity: 0.6;
      }
      .tile--gen {
        transition: opacity 0.3s ease;
      }
      .tile-shimmer {
        position: absolute;
        inset: 0;
        overflow: hidden;
        pointer-events: none;
      }
      .tile-shimmer::after {
        content: '';
        position: absolute;
        inset: 0;
        transform: translateX(-100%);
        background: linear-gradient(
          90deg,
          transparent,
          rgba(255, 255, 255, 0.14),
          transparent
        );
        animation: tier-shimmer 1.2s ease-in-out infinite;
      }
      @keyframes tier-shimmer {
        100% {
          transform: translateX(100%);
        }
      }
      @keyframes tier-indeterminate {
        0% {
          background-position: 200% 0;
        }
        100% {
          background-position: -200% 0;
        }
      }
    </style>
  </template>
}

// A reusable POOL: the set of items to rank (e.g. "All Pokémon", "Gen 1
// Starters") plus the default tier bands a new TierList inherits. Define once,
// rank many times. Items are linked (linksToMany) so a single TierItem can
// belong to many templates and a pool can grow to hundreds/thousands.
export class TierTemplate extends CardDef {
  static displayName = 'Tier Template';
  static icon = LayoutGridIcon;
  static prefersWideFormat = true;

  @field name = contains(StringField);
  @field items = linksToMany(() => TierItem);
  @field tiers = containsMany(Tier);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: TierTemplate) {
      return this.cardInfo?.name?.trim() || this.name || 'Untitled Template';
    },
  });

  static isolated = TierTemplateIsolated;

  static embedded = class extends Component<typeof TierTemplate> {
    get count(): number {
      return (this.args.model.items ?? []).filter(Boolean).length;
    }

    <template>
      <div class='emb'>
        <h3><@fields.cardTitle /></h3>
        <span class='count'>{{this.count}} items</span>
      </div>
      <style scoped>
        .emb {
          display: flex;
          align-items: baseline;
          gap: 0.5rem;
          padding: 0.5rem 0.75rem;
          background: var(--background, #15161a);
          color: var(--foreground, #f4f5f7);
          font-family: var(--font-sans, system-ui, sans-serif);
        }
        h3 {
          margin: 0;
          font-size: 1rem;
        }
        .count {
          font-size: 0.8125rem;
          color: var(--muted-foreground, #9aa0ad);
        }
      </style>
    </template>
  };

  static fitted = class extends Component<typeof TierTemplate> {
    get count(): number {
      return (this.args.model.items ?? []).filter(Boolean).length;
    }

    <template>
      <div class='cq'>
        <article class='fit'>
          <span class='label'><@fields.cardTitle /></span>
          <span class='count'>{{this.count}} items</span>
        </article>
      </div>
      <style scoped>
        .cq {
          container-type: size;
          container-name: card;
          width: 100%;
          height: 100%;
          overflow: hidden;
        }
        .fit {
          --type-base: clamp(10px, calc(3px + 2.2cqi + 1cqb), 18px);
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: minmax(0, 1fr) auto;
          gap: 2px;
          padding: 6px;
          box-sizing: border-box;
          overflow: hidden;
          background: var(--background, #15161a);
          color: var(--foreground, #f4f5f7);
          font-family: var(--font-sans, system-ui, sans-serif);
        }
        .label {
          font-size: var(--type-base, 14px);
          font-weight: 700;
          overflow: hidden;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
        }
        .count {
          align-self: end;
          font-size: max(8px, calc(var(--type-base) * 0.7));
          color: var(--muted-foreground, #9aa0ad);
        }
      </style>
    </template>
  };

  static atom = class extends Component<typeof TierTemplate> {
    <template>
      <span><@fields.cardTitle /></span>
    </template>
  };
}
