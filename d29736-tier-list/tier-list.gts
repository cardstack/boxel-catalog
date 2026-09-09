import {
  CardDef,
  Component,
  FieldDef,
  contains,
  containsMany,
  field,
  getComponent,
  linksToMany,
  realmURL,
} from '@cardstack/base/card-api';
import type { PartialBaseInstanceType } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';

import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { Button, BoxelInput } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { restartableTask } from 'ember-concurrency';

import OneShotLlmRequestCommand from '@cardstack/boxel-host/commands/one-shot-llm-request';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import FindImageCommand from '../commands/find-image';
import EnsureImageDefCommand from '../commands/ensure-image-def-exist';

import LayoutRowsIcon from '@cardstack/boxel-icons/layout-rows';

import { Tier } from './tier';
import { TierItem } from './tier-item';

// PATTERN: hand-rolled pointer drag over horizontal tier rows.
//
// The POOL of rankable items lives on this card (`items`, a linksToMany of ANY
// CardDef — a TierItem, or any other card type). Each item renders via its own
// `fitted` view, so the board works for movies, products, blog posts, whatever.
// "Generate with AI" mints simple TierItem cards into the pool. Ranking is
// stored as `placements`, keyed by each item's card id, so the item cards are
// never mutated by dragging. Only RANKED items get a placement; unranked = no
// placement (kept light even for a 1500-item pool).
//
// The board is a single shared component (TierBoard) used by two formats:
//   • isolated (list view) — read-only tiers, drag-to-rank only.
//   • edit — the same board, extended with tier editing, AI generation, and a
//     per-tile remove button. Configure here; rank in the list view.

const UNRANKED = '__unranked__';
const byOrder = (a: { sortOrder?: number }, b: { sortOrder?: number }) =>
  (a?.sortOrder ?? 0) - (b?.sortOrder ?? 0);

// Standard tier bands a brand-new list starts with (no template to inherit
// from anymore). Editing on the board promotes these to the list's own tiers.
const DEFAULT_TIERS: Array<{
  key: string;
  label: string;
  color: string;
  sortOrder: number;
}> = [
  { key: 'S', label: 'S', color: '#ff7f7f', sortOrder: 0 },
  { key: 'A', label: 'A', color: '#ffbf7f', sortOrder: 1 },
  { key: 'B', label: 'B', color: '#ffdf80', sortOrder: 2 },
  { key: 'C', label: 'C', color: '#ffff7f', sortOrder: 3 },
  { key: 'D', label: 'D', color: '#bfff7f', sortOrder: 4 },
  { key: 'F', label: 'F', color: '#7fbfff', sortOrder: 5 },
];

function defaultTiers(): Tier[] {
  return DEFAULT_TIERS.map((t) => Object.assign(new Tier(), t));
}

// A best-effort display string for filtering arbitrary cards by name. Falls
// back through the common title sources (incl. cardInfo.name) so cards that
// don't expose `title`/`name`/`cardTitle` still match. String() guards against
// a non-string field surfacing as "[object Object]".
function itemLabel(card: any): string {
  return String(
    card?.title ?? card?.cardTitle ?? card?.name ?? card?.cardInfo?.name ?? '',
  );
}

function styleColor(color?: string) {
  return htmlSafe(`background: ${color ?? 'transparent'}`);
}
function styleWidth(pct: number) {
  return htmlSafe(`width: ${pct}%`);
}
function ghostPos(x: number, y: number) {
  return htmlSafe(`left: ${x}px; top: ${y}px`);
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

export class Placement extends FieldDef {
  static displayName = 'Placement';

  @field itemId = contains(StringField);
  @field tierKey = contains(StringField);
  @field sortOrder = contains(NumberField);

  static embedded = class extends Component<typeof Placement> {
    <template>
      <span>{{@model.itemId}} → {{@model.tierKey}} #{{@model.sortOrder}}</span>
    </template>
  };
}

interface TierBoardSignature {
  Args: {
    // The boxed model a format component passes down — its fields are optional
    // on the box, so use the framework's partial type (not the strict
    // `TierList`, which would mismatch on required vs. optional fields) while
    // keeping `tiers`/`items`/`placements` typed for the callbacks below.
    model: PartialBaseInstanceType<typeof TierList>;
    fields: any;
    context: any;
    // When true (edit view): tier editing, AI generation, and per-tile remove
    // are shown. When false (list view): read-only tiers, drag-to-rank only.
    editing: boolean;
  };
  Element: HTMLElement;
}

class TierBoard extends GlimmerComponent<TierBoardSignature> {
  @tracked draggingId: string | null = null;
  @tracked draggingItem: CardDef | null = null;
  @tracked dropTierKey: string | null = null;
  @tracked dropIndex = 0;
  @tracked ghostX = 0;
  @tracked ghostY = 0;
  @tracked filter = '';
  boardEl: HTMLElement | null = null;

  get editing(): boolean {
    return Boolean(this.args.editing);
  }

  // --- AI pool generation (edit view only) ---------------------------
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

  setGenPrompt = (value: string): void => {
    this.genPrompt = value;
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

  // Best-effort: find a real image for the item (verifying the LLM's URL, then
  // scraping, then Wikipedia/search), persist it as an ImageDef, and link it by
  // id. Linking by id keeps the item store-backed — no fabricated data model.
  attachItemImage = async (
    cx: any,
    realm: string,
    item: TierItem,
    entry: GenItem,
  ): Promise<void> => {
    if (!item.id || (!entry.imageUrl && !entry.name)) {
      return;
    }
    try {
      let found = await new FindImageCommand(cx).execute({
        sourceUrl: entry.imageUrl,
        fallbackSearchText: entry.name,
        preferLogo: true,
      });
      if (!found.found || !found.imageUrl) {
        return;
      }
      let ensured = await new EnsureImageDefCommand(cx).execute({
        imageUrl: found.imageUrl,
        targetRealmUrl: realm,
      });
      await new PatchCardInstanceCommand(cx, { cardType: TierItem }).execute({
        cardId: item.id,
        patch: {
          relationships: {
            'image.file': { links: { self: ensured.imageDefId } },
          },
        },
      });
    } catch {
      // Best-effort — a resolution/persist/patch failure just leaves this
      // item without an image; it shouldn't abort the whole generate run.
    }
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
        'required) and "imageUrl" (string, optional). For "imageUrl" prefer a ' +
        'canonical logo CDN when one applies — ' +
        '"https://cdn.jsdelivr.net/gh/devicons/devicon/icons/<slug>/<slug>-original.svg" ' +
        'or "https://cdn.simpleicons.org/<slug>" — otherwise a real, stable, ' +
        'directly-loadable public image URL; omit it if unsure. ' +
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
      let seenNames = new Set<string>();
      let entries = parseGenItems(String(output))
        .filter((entry) => {
          let key = entry.name.trim().toLowerCase();
          if (!key || seenNames.has(key)) {
            return false;
          }
          seenNames.add(key);
          return true;
        })
        .slice(0, GEN_MAX);
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
        let item = new TierItem({ name: entry.name });
        await new SaveCardCommand(cx).execute({ card: item, realm });
        await this.attachItemImage(cx, realm, item, entry);
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

  // --- pool + tiers ---------------------------------------------------

  get sortedTiers(): Tier[] {
    let own = (this.args.model.tiers ?? []).filter(Boolean);
    let base = own.length ? own : defaultTiers();
    return [...base].sort(byOrder);
  }

  get pool(): CardDef[] {
    return (this.args.model.items ?? []).filter(Boolean);
  }

  get poolById(): Map<string, CardDef> {
    return new Map(this.pool.map((i) => [i.id, i]));
  }

  get placements(): Placement[] {
    return (this.args.model.placements ?? []).filter(Boolean);
  }

  itemsForTier = (key: string | undefined): CardDef[] => {
    let map = this.poolById;
    return this.placements
      .filter((p) => (p.tierKey ?? '') === (key ?? ''))
      .sort(byOrder)
      .map((p) => map.get(p.itemId ?? ''))
      .filter(Boolean) as CardDef[];
  };

  get rankedIds(): Set<string> {
    return new Set(
      this.placements.filter((p) => p.tierKey).map((p) => p.itemId ?? ''),
    );
  }

  get unrankedItems(): CardDef[] {
    let ranked = this.rankedIds;
    let list = this.pool.filter((i) => !ranked.has(i.id));
    // Only apply the filter while its input is actually shown, so a stale value
    // can't silently hide items once the pool shrinks below the threshold.
    let q = this.showFilter ? this.filter.trim().toLowerCase() : '';
    if (q) {
      list = list.filter((i) => itemLabel(i).toLowerCase().includes(q));
    }
    return list;
  }

  isDragging = (item: CardDef): boolean => {
    return !!this.draggingId && item.id === this.draggingId;
  };

  // Swallow pointerdown on in-tile controls (e.g. remove) so they don't kick
  // off a drag.
  stopEvent = (event: Event): void => {
    event.stopPropagation();
  };

  removeItem = (item: CardDef): void => {
    let id = item.id;
    this.args.model.items = (this.args.model.items ?? []).filter(
      (i) => i && i.id !== id,
    );
    this.args.model.placements = (this.args.model.placements ?? []).filter(
      (p) => p && p.itemId !== id,
    );
  };

  // --- drag lifecycle -------------------------------------------------

  startDrag = (item: CardDef, event: PointerEvent): void => {
    event.preventDefault();
    this.boardEl =
      (event.currentTarget as HTMLElement | null)?.closest('.board') ?? null;
    this.draggingId = item.id ?? null;
    this.draggingItem = item;
    this.positionGhost(event);
    let existing = this.placements.find((p) => p.itemId === item.id);
    this.dropTierKey = existing?.tierKey ? existing.tierKey : UNRANKED;
    this.dropIndex = 0;
    window.addEventListener('pointermove', this.onPointerMove);
    window.addEventListener('pointerup', this.onPointerUp);
  };

  positionGhost = (event: PointerEvent): void => {
    let rect = this.boardEl?.getBoundingClientRect();
    this.ghostX = event.clientX - (rect?.left ?? 0);
    this.ghostY = event.clientY - (rect?.top ?? 0);
  };

  onPointerMove = (event: PointerEvent): void => {
    this.positionGhost(event);
    let el = document.elementFromPoint(event.clientX, event.clientY);
    let zone = el?.closest('[data-droptarget]') as HTMLElement | null;
    if (!zone) {
      return;
    }
    this.dropTierKey = zone.getAttribute('data-tier-key');
    let tiles = Array.from(zone.querySelectorAll('[data-tile]'));
    let idx = tiles.length;
    for (let i = 0; i < tiles.length; i++) {
      let r = tiles[i].getBoundingClientRect();
      if (event.clientX < r.left + r.width / 2) {
        idx = i;
        break;
      }
    }
    this.dropIndex = idx;
  };

  onPointerUp = (): void => {
    window.removeEventListener('pointermove', this.onPointerMove);
    window.removeEventListener('pointerup', this.onPointerUp);
    let id = this.draggingId;
    if (id) {
      let targetKey = this.dropTierKey === UNRANKED ? null : this.dropTierKey;
      let placements = [...(this.args.model.placements ?? [])].filter(Boolean);
      if (targetKey == null) {
        // dragged to the tray → unrank (drop its placement)
        placements = placements.filter((p) => p.itemId !== id);
      } else {
        let dragged = placements.find((p) => p.itemId === id);
        if (!dragged) {
          dragged = Object.assign(new Placement(), {
            itemId: id,
            tierKey: targetKey,
            sortOrder: 0,
          });
          placements.push(dragged);
        } else {
          dragged.tierKey = targetKey;
        }
        let group = placements
          .filter((p) => p !== dragged && (p.tierKey ?? '') === targetKey)
          .sort(byOrder);
        let insertAt = Math.max(0, Math.min(this.dropIndex, group.length));
        group.splice(insertAt, 0, dragged);
        group.forEach((p, i) => {
          p.sortOrder = i;
        });
      }
      this.args.model.placements = placements;
    }
    this.draggingId = null;
    this.draggingItem = null;
    this.dropTierKey = null;
    this.dropIndex = 0;
  };

  // --- controls -------------------------------------------------------

  get titleValue(): string {
    return this.args.model.title ?? '';
  }
  setTitle = (value: string): void => {
    this.args.model.title = value;
  };

  // The name filter only earns its place once the pool is big enough to scan.
  get showFilter(): boolean {
    return this.pool.length > 20;
  }

  setFilter = (value: string): void => {
    this.filter = value;
  };

  resetAll = (): void => {
    this.args.model.placements = [];
  };

  ensureOwnTiers = (): void => {
    if (!(this.args.model.tiers ?? []).filter(Boolean).length) {
      this.args.model.tiers = defaultTiers();
    }
  };

  addTier = (): void => {
    this.ensureOwnTiers();
    let tiers = (this.args.model.tiers ?? []).filter(Boolean);
    let t = Object.assign(new Tier(), {
      key: `tier-${tiers.length}-${tiers.reduce((m, x) => Math.max(m, x.sortOrder ?? 0), 0) + 1}`,
      label: 'New',
      color: '#c9ccd4',
      sortOrder: tiers.length,
    });
    this.args.model.tiers = [...tiers, t];
  };

  removeTier = (tier: Tier): void => {
    this.ensureOwnTiers();
    let key = tier.key;
    this.args.model.tiers = (this.args.model.tiers ?? []).filter(
      (t) => t && t.key !== key,
    );
    this.args.model.placements = (this.args.model.placements ?? []).filter(
      (p) => p && p.tierKey !== key,
    );
  };

  renameTier = (tier: Tier, value: string): void => {
    this.ensureOwnTiers();
    tier.label = value;
    this.args.model.tiers = [...(this.args.model.tiers ?? [])];
  };

  recolorTier = (tier: Tier, event: Event): void => {
    this.ensureOwnTiers();
    tier.color = (event.target as HTMLInputElement).value;
    this.args.model.tiers = [...(this.args.model.tiers ?? [])];
  };

  willDestroy(): void {
    super.willDestroy();
    window.removeEventListener('pointermove', this.onPointerMove);
    window.removeEventListener('pointerup', this.onPointerUp);
  }

  <template>
    {{! template-lint-disable no-pointer-down-event-binding }}
    <section class='board'>
      <header class='board-head'>
        {{#if this.editing}}
          <div class='title-edit'>
            <label class='title-label'>Name</label>
            <BoxelInput
              class='title-input'
              aria-label='Tier list name'
              placeholder='Name this tier list…'
              @value={{this.titleValue}}
              @onInput={{this.setTitle}}
            />
          </div>
        {{else}}
          <h1><@fields.cardTitle /></h1>
        {{/if}}
        <div class='controls'>
          {{#if this.showFilter}}
            <BoxelInput
              class='ctl-input'
              aria-label='Filter unranked items'
              placeholder='Filter…'
              @value={{this.filter}}
              @onInput={{this.setFilter}}
            />
          {{/if}}
          {{#if this.editing}}
            <Button
              @kind='text-only'
              @size='auto'
              class='btn'
              {{on 'click' this.addTier}}
            >
              Add tier
            </Button>
          {{/if}}
          <Button
            @kind='text-only'
            @size='auto'
            class='btn ghost-btn'
            {{on 'click' this.resetAll}}
          >
            Reset
          </Button>
        </div>
      </header>

      {{#if this.editing}}
        <div class='gen'>
          <BoxelInput
            class='gen-input'
            aria-label='Describe the pool to generate with AI'
            placeholder='Describe a pool — e.g. “Studio Ghibli films”'
            @value={{this.genPrompt}}
            @disabled={{this.genBusy}}
            @onInput={{this.setGenPrompt}}
          />
          {{#if this.genBusy}}
            <Button
              @kind='text-only'
              @size='auto'
              class='gen-btn gen-cancel'
              {{on 'click' this.cancelGenerate}}
            >
              Cancel
            </Button>
          {{else}}
            <Button
              @kind='text-only'
              @size='auto'
              class='gen-btn'
              {{on 'click' this.runGenerate}}
            >
              Generate with AI
            </Button>
          {{/if}}
          {{! The linksToMany editor's "Add" button opens the card chooser (any
              card type). We hide its re-rendered list of links via CSS since the
              pool already shows in the tray below. }}
          <div class='add-card'>
            <@fields.items />
          </div>
        </div>

        {{#if this.genBusy}}
          <div class='gen-progress' role='status' aria-live='polite'>
            <span
              class='bar {{if this.genIndeterminate "bar--indeterminate"}}'
            ><span
                class='bar-fill'
                style={{styleWidth this.genPct}}
              ></span></span>
            <span class='gen-note'>{{this.genPhaseLabel}}</span>
          </div>
          <div class='gen-preview'>
            {{#if this.genTiles.length}}
              {{#each this.genTiles as |g|}}
                <div class='tile tile--gen {{unless g.saved "tile--pending"}}'>
                  {{#if g.imageUrl}}
                    <img src={{g.imageUrl}} alt={{g.name}} class='tile-img' />
                  {{else}}
                    <span class='tile-text'>{{g.name}}</span>
                  {{/if}}
                  <span class='tile-cap'>{{g.name}}</span>
                  {{#unless g.saved}}<span
                      class='tile-shimmer'
                    ></span>{{/unless}}
                </div>
              {{/each}}
            {{else}}
              {{#each this.thinkingSlots as |slot|}}
                <div class='tile tile--skel' data-slot={{slot}}>
                  <span class='tile-shimmer'></span>
                </div>
              {{/each}}
            {{/if}}
          </div>
        {{else if this.genHasError}}
          <div class='gen-progress'>
            <span class='gen-err'>{{this.genError}}</span>
          </div>
        {{/if}}
      {{/if}}

      {{#if this.pool.length}}
        <div class='tiers'>
          {{#each this.sortedTiers as |tier|}}
            <div class='tier-row'>
              <div class='tier-label' style={{styleColor tier.color}}>
                {{#if this.editing}}
                  <BoxelInput
                    class='tier-name'
                    aria-label='Tier label'
                    @value={{tier.label}}
                    @onInput={{fn this.renameTier tier}}
                  />
                  <div class='tier-tools'>
                    <input
                      class='tier-color'
                      type='color'
                      aria-label='Tier color'
                      value={{tier.color}}
                      {{on 'input' (fn this.recolorTier tier)}}
                    />
                    <Button
                      @kind='text-only'
                      @size='auto'
                      class='tier-del'
                      {{on 'click' (fn this.removeTier tier)}}
                    >×</Button>
                  </div>
                {{else}}
                  <span class='tier-name-ro'>{{tier.label}}</span>
                {{/if}}
              </div>
              <div
                class='strip
                  {{if (eq this.dropTierKey tier.key) "drop-active"}}'
                data-droptarget
                data-tier-key={{tier.key}}
              >
                {{#each (this.itemsForTier tier.key) as |item|}}
                  <div
                    class='tile {{if (this.isDragging item) "is-dragging"}}'
                    data-tile
                    {{on 'pointerdown' (fn this.startDrag item)}}
                  >
                    <div class='tile-card'>
                      {{#let (getComponent item) as |Card|}}
                        <Card @format='fitted' @displayContainer={{false}} />
                      {{/let}}
                    </div>
                    {{#if this.editing}}
                      <Button
                        @kind='text-only'
                        @size='auto'
                        class='tile-remove'
                        aria-label='Remove from pool'
                        {{on 'pointerdown' this.stopEvent}}
                        {{on 'click' (fn this.removeItem item)}}
                      >×</Button>
                    {{/if}}
                  </div>
                {{/each}}
              </div>
            </div>
          {{/each}}
        </div>

        <div class='tray-wrap'>
          <div class='tray-label'>Unranked ({{this.unrankedItems.length}})</div>
          <div
            class='strip tray
              {{if (eq this.dropTierKey "__unranked__") "drop-active"}}'
            data-droptarget
            data-tier-key='__unranked__'
          >
            {{#each this.unrankedItems as |item|}}
              <div
                class='tile {{if (this.isDragging item) "is-dragging"}}'
                data-tile
                {{on 'pointerdown' (fn this.startDrag item)}}
              >
                <div class='tile-card'>
                  {{#let (getComponent item) as |Card|}}
                    <Card @format='fitted' @displayContainer={{false}} />
                  {{/let}}
                </div>
                {{#if this.editing}}
                  <Button
                    @kind='text-only'
                    @size='auto'
                    class='tile-remove'
                    aria-label='Remove from pool'
                    {{on 'pointerdown' this.stopEvent}}
                    {{on 'click' (fn this.removeItem item)}}
                  >×</Button>
                {{/if}}
              </div>
            {{else}}
              <span class='tray-empty'>Everything is ranked. 🎉</span>
            {{/each}}
          </div>
        </div>
      {{else}}
        {{#unless this.genBusy}}
          <div class='no-items'>
            {{#if this.editing}}
              No items yet — generate a pool above, or link existing cards in
              the Items field below.
            {{else}}
              No items yet — open edit mode to generate or add items.
            {{/if}}
          </div>
        {{/unless}}
      {{/if}}

      {{#if this.draggingItem}}
        <div class='ghost' style={{ghostPos this.ghostX this.ghostY}}>
          {{#let (getComponent this.draggingItem) as |Card|}}
            <Card @format='fitted' @displayContainer={{false}} />
          {{/let}}
        </div>
      {{/if}}
    </section>

    <style scoped>
      /* The board grows to its content and is scrolled by its host (see
         .board-host / .edit-host). It does NOT cap the tiers/tray in internal
         scrollers — that was stranding the tray below the fold. min-height:100%
         keeps it filling a tall pane; height:auto lets it grow past it. */
      .board {
        position: relative;
        min-height: 100%;
        display: flex;
        flex-direction: column;
      }
      .gen {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 0.375rem;
        padding: 0.5rem 1rem;
        border-bottom: 1px solid var(--border);
      }
      .gen-input {
        flex: 1 1 14rem;
        min-width: 0;
        padding: 0.3125rem 0.5rem;
        font: inherit;
        font-size: 0.8125rem;
        color: var(--foreground);
        background-color: var(--background);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .gen-input::placeholder {
        color: var(--muted-foreground);
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
        color: var(--primary-foreground);
        background-color: var(--primary);
        border: 1px solid transparent;
        border-radius: var(--radius);
      }
      .gen-btn:disabled {
        cursor: default;
        opacity: 0.6;
      }
      .gen-cancel {
        color: var(--foreground);
        background-color: transparent;
        border-color: var(--border);
      }
      /* "Add a card" = the linksToMany editor's Add button only; the editor's
         re-rendered list of links is hidden since the pool shows in the tray. */
      .add-card {
        display: inline-flex;
        align-items: center;
      }
      .add-card :deep(.links-to-many-editor .list),
      .add-card :deep(.boxel-pills .item-pill) {
        display: none;
      }
      .add-card :deep(.add-new),
      .add-card :deep(.compact-add-new) {
        margin: 0;
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
        height: 0.375rem;
        border-radius: 62.4375rem;
        overflow: hidden;
        background-color: var(--border);
      }
      .bar-fill {
        display: block;
        height: 100%;
        border-radius: inherit;
        background-color: var(--primary);
        color: var(--primary-foreground);
        transition: width 0.3s ease;
      }
      .bar--indeterminate {
        background: linear-gradient(
          90deg,
          var(--border) 0%,
          var(--primary) 50%,
          var(--border) 100%
        );
        background-size: 200% 100%;
        animation: tier-indeterminate 1.1s linear infinite;
      }
      .bar--indeterminate .bar-fill {
        display: none;
      }
      .gen-note {
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .gen-err {
        font-size: 0.75rem;
        color: var(--destructive-ink);
      }
      .gen-preview {
        display: flex;
        flex-wrap: wrap;
        gap: 0.375rem;
        padding: 0 1rem 0.5rem;
      }
      .board-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: 0.75rem;
        padding: 0.875rem 1rem;
        border-bottom: 1px solid var(--border);
        background-color: var(--card);
        color: var(--card-foreground);
      }
      h1 {
        margin: 0;
        font-size: 1.125rem;
        font-weight: 700;
      }
      .title-edit {
        display: flex;
        flex-direction: column;
        gap: 0.1875rem;
        flex: 1 1 16rem;
        min-width: 12rem;
      }
      .title-label {
        font-size: 0.625rem;
        font-weight: 700;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .title-input {
        width: 100%;
        padding: 0.375rem 0.5rem;
        font: inherit;
        font-size: 1.0625rem;
        font-weight: 700;
        color: var(--foreground);
        background-color: var(--background);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .title-input::placeholder {
        color: var(--muted-foreground);
      }
      .controls {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 0.375rem;
      }
      .ctl-input {
        padding: 0.3125rem 0.5rem;
        font: inherit;
        font-size: 0.8125rem;
        color: var(--foreground);
        background-color: var(--background);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .ctl-input::placeholder {
        color: var(--muted-foreground);
      }
      .btn {
        padding: 0.3125rem 0.625rem;
        font: inherit;
        font-size: 0.8125rem;
        font-weight: 600;
        cursor: pointer;
        color: var(--primary-foreground);
        background-color: var(--primary);
        border: 1px solid transparent;
        border-radius: var(--radius);
      }
      .btn.ghost-btn {
        color: var(--foreground);
        background-color: transparent;
        border-color: var(--border);
      }
      .tiers {
        flex: 0 0 auto;
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        padding: 0.5rem;
      }
      .tier-row {
        display: grid;
        grid-template-columns: 6rem minmax(0, 1fr);
        gap: 0.25rem;
        min-height: 4.5rem;
      }
      .tier-label {
        display: flex;
        flex-direction: column;
        align-items: stretch;
        justify-content: center;
        gap: 0.25rem;
        padding: 0.375rem;
        border-radius: var(--radius);
        color: var(--foreground);
      }
      .tier-name {
        width: 100%;
        padding: 0.1875rem 0.25rem;
        font: inherit;
        font-weight: 800;
        font-size: 1rem;
        text-align: center;
        color: var(--foreground);
        /* near-opaque so the input reads clearly over any band color */
        background-color: color-mix(in oklch, var(--card) 92%, transparent);
        border: 1px solid
          color-mix(in oklch, var(--foreground) 25%, transparent);
        border-radius: 0.25rem;
      }
      .tier-name-ro {
        font-weight: 800;
        font-size: 1.125rem;
        text-align: center;
        color: var(--foreground);
      }
      .tier-tools {
        display: flex;
        align-items: stretch;
        gap: 0.25rem;
      }
      /* The color picker is the easiest control to miss — give it a clear,
         wide swatch with a visible frame instead of a tiny chip. */
      .tier-color {
        flex: 1 1 auto;
        height: 1.5rem;
        padding: 0;
        background-color: color-mix(in oklch, var(--card) 92%, transparent);
        border: 1px solid
          color-mix(in oklch, var(--foreground) 35%, transparent);
        border-radius: 0.25rem;
        cursor: pointer;
      }
      .tier-color::-webkit-color-swatch-wrapper {
        padding: 2px;
      }
      .tier-color::-webkit-color-swatch {
        border: none;
        border-radius: 0.125rem;
      }
      .tier-del {
        flex: 0 0 auto;
        width: 1.5rem;
        height: 1.5rem;
        line-height: 1;
        font-size: 1rem;
        cursor: pointer;
        color: var(--foreground);
        background-color: color-mix(in oklch, var(--card) 92%, transparent);
        border: 1px solid
          color-mix(in oklch, var(--foreground) 25%, transparent);
        border-radius: 0.25rem;
      }
      .strip {
        display: flex;
        flex-wrap: wrap;
        align-content: flex-start;
        gap: 0.25rem;
        padding: 0.25rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .strip.drop-active {
        outline: 2px dashed var(--primary);
        outline-offset: -2px;
      }
      /* Pin the unranked tray to the bottom of the scroll host so it stays a
         visible drop target while the tiers scroll above it. margin-top:auto
         pushes it to the bottom when the content is shorter than the host. */
      .tray-wrap {
        position: sticky;
        bottom: 0;
        z-index: 2;
        margin-top: auto;
        border-top: 1px solid var(--border);
        background-color: var(--card);
        color: var(--card-foreground);
        padding: 0.5rem;
      }
      .tray-label {
        margin: 0 0 0.375rem;
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .tray {
        min-height: 4rem;
        max-height: 16rem;
        overflow: auto;
      }
      .tray-empty {
        padding: 0.75rem;
        font-size: 0.8125rem;
        color: var(--muted-foreground);
      }
      .no-items {
        flex: 1 1 auto;
        display: grid;
        place-items: center;
        padding: 2rem;
        text-align: center;
        color: var(--muted-foreground);
      }
      .tile {
        position: relative;
        width: 4.5rem;
        height: 4.5rem;
        display: flex;
        align-items: center;
        justify-content: center;
        cursor: grab;
        touch-action: none;
        user-select: none;
        overflow: hidden;
        background-color: var(--background);
        border: 1px solid var(--border);
        border-radius: 0.25rem;
      }
      .tile.is-dragging {
        opacity: 0.3;
      }
      /* The linked card renders its own fitted view; keep it non-interactive
         so the whole tile is the drag handle. */
      .tile-card {
        width: 100%;
        height: 100%;
        overflow: hidden;
        pointer-events: none;
      }
      .tile-remove {
        position: absolute;
        top: 1px;
        right: 1px;
        width: 1rem;
        height: 1rem;
        line-height: 1;
        display: flex;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        color: var(--card-foreground);
        background-color: color-mix(in oklch, var(--card) 60%, transparent);
        border: none;
        border-radius: 0.25rem;
      }
      .tile-img {
        width: 100%;
        height: 100%;
        object-fit: contain;
        pointer-events: none;
      }
      .tile-text {
        padding: 0.25rem;
        font-size: 0.75rem;
        font-weight: 600;
        text-align: center;
        line-height: 1.1;
        overflow: hidden;
      }
      .tile-cap {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        padding: 0.0625rem 0.125rem;
        font-size: 0.5625rem;
        text-align: center;
        color: var(--card-foreground);
        background-color: color-mix(in oklch, var(--card) 60%, transparent);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .tile--gen {
        cursor: default;
        transition: opacity 0.3s ease;
      }
      .tile--skel {
        cursor: default;
        opacity: 0.6;
      }
      /* Don't dim the image itself — a dark logo (Next.js, GitHub…) at 60%
         opacity on a dark tile nearly disappears, reading as broken. The
         shimmer sweep already signals "in progress"; dim just the caption. */
      .tile--pending {
        cursor: default;
      }
      .tile--pending .tile-cap {
        opacity: 0.7;
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
          color-mix(in oklch, var(--card) 14%, transparent),
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
      .ghost {
        position: absolute;
        z-index: 1000;
        width: 4.5rem;
        height: 4.5rem;
        transform: translate(-50%, -50%) rotate(-3deg);
        pointer-events: none;
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        background-color: var(--background);
        border: 1px solid var(--primary);
        border-radius: 0.25rem;
        box-shadow: 0 8px 20px
          color-mix(in oklch, var(--foreground) 45%, transparent);
      }
    </style>
  </template>
}

export class TierList extends CardDef {
  static displayName = 'Tier List';
  static icon = LayoutRowsIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  // The pool can hold ANY card; each renders via its own fitted view.
  @field items = linksToMany(() => CardDef);
  @field tiers = containsMany(Tier); // tier bands; defaults to DEFAULT_TIERS
  @field placements = containsMany(Placement);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: TierList) {
      // Prefer the editable `title` so renaming in edit view is reflected.
      return (
        this.title?.trim() ||
        this.cardInfo?.name?.trim() ||
        'Untitled Tier List'
      );
    },
  });

  // List view: read-only tiers, drag-to-rank only.
  static isolated = class extends Component<typeof TierList> {
    <template>
      <div class='board-host'>
        <TierBoard
          @model={{@model}}
          @fields={{@fields}}
          @context={{@context}}
          @editing={{false}}
        />
      </div>
      <style scoped>
        /* Bound the board to the pane and let it scroll here, so the tray is
           always reachable instead of stranded below the fold. */
        .board-host {
          height: 100%;
          min-height: 0;
          overflow-y: auto;
        }
      </style>
    </template>
  };

  static embedded = class extends Component<typeof TierList> {
    get sortedTiers(): Tier[] {
      let own = (this.args.model.tiers ?? []).filter(Boolean);
      let base = own.length ? own : defaultTiers();
      return [...base].sort(byOrder);
    }

    countFor = (key: string | undefined): number => {
      return (this.args.model.placements ?? []).filter(
        (p) => p && (p.tierKey ?? '') === (key ?? ''),
      ).length;
    };

    <template>
      <div class='emb'>
        <h3><@fields.cardTitle /></h3>
        <div class='emb-rows'>
          {{#each this.sortedTiers as |t|}}
            <div class='emb-row'>
              <span
                class='emb-key'
                style={{styleColor t.color}}
              >{{t.label}}</span>
              <span class='emb-count'>{{this.countFor t.key}}</span>
            </div>
          {{/each}}
        </div>
      </div>
      <style scoped>
        .emb {
          padding: 0.75rem;
        }
        h3 {
          margin: 0 0 0.5rem;
          font-size: 1rem;
        }
        .emb-rows {
          display: flex;
          flex-direction: column;
          gap: 0.1875rem;
        }
        .emb-row {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .emb-key {
          min-width: 2.5rem;
          padding: 0.0625rem 0.375rem;
          font-weight: 800;
          font-size: 0.8125rem;
          text-align: center;
          color: var(--foreground);
          border-radius: 0.1875rem;
        }
        .emb-count {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class extends Component<typeof TierList> {
    get sortedTiers(): Tier[] {
      let own = (this.args.model.tiers ?? []).filter(Boolean);
      let base = own.length ? own : defaultTiers();
      return [...base].sort(byOrder);
    }

    get ranked(): number {
      return (this.args.model.placements ?? []).filter((p) => p && p.tierKey)
        .length;
    }

    <template>
      <div class='cq'>
        <article class='fit'>
          <div class='r-head'>
            <h3 class='headline'><@fields.cardTitle /></h3>
          </div>
          <div class='r-body'>
            <div class='swatches'>
              {{#each this.sortedTiers as |t|}}
                <span class='sw' style={{styleColor t.color}}>{{t.label}}</span>
              {{/each}}
            </div>
          </div>
          <div class='r-meta'>
            <span>{{this.ranked}} ranked</span>
          </div>
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
          --type-ratio: 1.25;
          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --type-base: clamp(
            0.625rem,
            calc(0.1875rem + 2.2cqi + 1cqb - 0.6 * var(--ar)),
            1.125rem
          );
          --fit-meta-size: max(
            0.5rem,
            calc(var(--type-base) / var(--type-ratio))
          );
          --fit-headline-size: max(
            0.6875rem,
            calc(var(--type-base) * pow(var(--type-ratio), 2))
          );
          --fit-pad: clamp(0.3125rem, calc(2px + 1.8cqi), 0.875rem);
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          gap: 2px;
          padding: var(--fit-pad);
          box-sizing: border-box;
          overflow: hidden;
        }
        .r-head,
        .r-body,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .headline {
          margin: 0;
          font-size: var(--fit-headline-size);
          line-height: 1.18;
          font-weight: 700;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }
        .swatches {
          display: flex;
          flex-wrap: wrap;
          gap: 2px;
          align-content: flex-start;
        }
        .sw {
          min-width: 1.25rem;
          padding: 0 0.25rem;
          font-size: var(--fit-meta-size);
          font-weight: 800;
          text-align: center;
          color: var(--foreground);
          border-radius: 2px;
        }
        .r-meta {
          align-self: end;
          font-size: var(--fit-meta-size);
          color: var(--muted-foreground);
        }
        @container card (height <= 80px) {
          .r-body {
            display: none;
          }
        }
      </style>
    </template>
  };

  static atom = class extends Component<typeof TierList> {
    <template>
      <span class='atom'><@fields.cardTitle /></span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          font-weight: 600;
        }
      </style>
    </template>
  };

  // Edit view: the same board, extended with tier editing, AI generation, an
  // "Add a card" button (in the toolbar), and per-tile remove. Configure here;
  // rank in the list view.
  static edit = class extends Component<typeof TierList> {
    <template>
      <div class='edit-host'>
        <TierBoard
          @model={{@model}}
          @fields={{@fields}}
          @context={{@context}}
          @editing={{true}}
        />
      </div>
      <style scoped>
        /* The edit view is one scrolling document. A rem floor keeps the board
           usable even if the surrounding pane reports no fixed height. */
        .edit-host {
          height: 100%;
          min-height: 30rem;
          overflow-y: auto;
        }
      </style>
    </template>
  };
}
