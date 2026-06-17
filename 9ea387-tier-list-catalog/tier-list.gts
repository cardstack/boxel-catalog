import {
  CardDef,
  Component,
  FieldDef,
  contains,
  containsMany,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';

import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';

import LayoutRowsIcon from '@cardstack/boxel-icons/layout-rows';

import { Tier } from './tier';
import { TierTemplate } from './tier-template';
import { TierItem } from './tier-item';

// PATTERN: hand-rolled pointer drag over horizontal tier rows.
//
// The POOL of rankable items comes from the linked TierTemplate
// (`template.items`, a linksToMany of reusable TierItem cards — can be
// hundreds/thousands). Ranking is stored HERE as `placements`, keyed by each
// item's card id, so the shared item cards are never mutated by dragging.
// Only RANKED items get a placement; unranked = no placement (kept light even
// for a 1500-item pool).

const UNRANKED = '__unranked__';
const byOrder = (a: { sortOrder?: number }, b: { sortOrder?: number }) =>
  (a?.sortOrder ?? 0) - (b?.sortOrder ?? 0);

function styleColor(color?: string) {
  return htmlSafe(`background: ${color ?? 'transparent'}`);
}
function ghostPos(x: number, y: number) {
  return htmlSafe(`left: ${x}px; top: ${y}px`);
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

export class TierList extends CardDef {
  static displayName = 'Tier List';
  static icon = LayoutRowsIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  @field template = linksTo(() => TierTemplate);
  @field tiers = containsMany(Tier); // per-list tiers; defaults from template
  @field placements = containsMany(Placement);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: TierList) {
      return (
        this.cardInfo?.name?.trim() ||
        this.title ||
        (this.template?.name ? `${this.template.name} — Tier List` : '') ||
        'Untitled Tier List'
      );
    },
  });

  static isolated = class extends Component<typeof TierList> {
    @tracked draggingId: string | null = null;
    @tracked dropTierKey: string | null = null;
    @tracked dropIndex = 0;
    @tracked ghostX = 0;
    @tracked ghostY = 0;
    @tracked ghostLabel = '';
    @tracked ghostURL = '';
    @tracked filter = '';
    @tracked broken = new Set<string>();
    boardEl: HTMLElement | null = null;

    markBroken = (id: string): void => {
      this.broken = new Set(this.broken).add(id);
    };
    showImg = (item: TierItem): boolean => {
      return Boolean(item.image?.resolvedUrl) && !this.broken.has(item.id);
    };

    get sortedTiers(): Tier[] {
      let own = (this.args.model.tiers ?? []).filter(Boolean);
      let base = own.length
        ? own
        : (this.args.model.template?.tiers ?? []).filter(Boolean);
      return [...base].sort(byOrder);
    }

    get pool(): TierItem[] {
      return (this.args.model.template?.items ?? []).filter(Boolean);
    }

    get poolById(): Map<string, TierItem> {
      return new Map(this.pool.map((i) => [i.id, i]));
    }

    get placements(): Placement[] {
      return (this.args.model.placements ?? []).filter(Boolean);
    }

    itemsForTier = (key: string | undefined): TierItem[] => {
      let map = this.poolById;
      return this.placements
        .filter((p) => (p.tierKey ?? '') === (key ?? ''))
        .sort(byOrder)
        .map((p) => map.get(p.itemId ?? ''))
        .filter(Boolean) as TierItem[];
    };

    get rankedIds(): Set<string> {
      return new Set(
        this.placements.filter((p) => p.tierKey).map((p) => p.itemId ?? ''),
      );
    }

    get unrankedItems(): TierItem[] {
      let ranked = this.rankedIds;
      let list = this.pool.filter((i) => !ranked.has(i.id));
      let q = this.filter.trim().toLowerCase();
      if (q) {
        list = list.filter((i) => (i.name ?? '').toLowerCase().includes(q));
      }
      return list;
    }

    isDragging = (item: TierItem): boolean => {
      return !!this.draggingId && item.id === this.draggingId;
    };

    // --- drag lifecycle -------------------------------------------------

    startDrag = (item: TierItem, event: PointerEvent): void => {
      event.preventDefault();
      this.boardEl =
        (event.currentTarget as HTMLElement | null)?.closest('.board') ?? null;
      this.draggingId = item.id ?? null;
      this.ghostLabel = item.name ?? '';
      this.ghostURL = this.showImg(item) ? (item.image?.resolvedUrl ?? '') : '';
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
      this.dropTierKey = null;
      this.dropIndex = 0;
    };

    // --- controls -------------------------------------------------------

    setFilter = (event: Event): void => {
      this.filter = (event.target as HTMLInputElement).value;
    };

    resetAll = (): void => {
      this.args.model.placements = [];
    };

    ensureOwnTiers = (): void => {
      if (!(this.args.model.tiers ?? []).filter(Boolean).length) {
        let base = (this.args.model.template?.tiers ?? []).filter(Boolean);
        this.args.model.tiers = base.map((t) =>
          Object.assign(new Tier(), {
            key: t.key,
            label: t.label,
            color: t.color,
            sortOrder: t.sortOrder,
          }),
        );
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

    renameTier = (tier: Tier, event: Event): void => {
      this.ensureOwnTiers();
      tier.label = (event.target as HTMLInputElement).value;
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
          <h1><@fields.cardTitle /></h1>
          <div class='controls'>
            <input
              class='ctl-input'
              aria-label='Filter unranked items'
              placeholder='Filter…'
              value={{this.filter}}
              {{on 'input' this.setFilter}}
            />
            <button type='button' class='btn' {{on 'click' this.addTier}}>
              Add tier
            </button>
            <button type='button' class='btn ghost-btn' {{on 'click' this.resetAll}}>
              Reset
            </button>
          </div>
        </header>

        {{#if this.pool.length}}
          <div class='tiers'>
            {{#each this.sortedTiers as |tier|}}
              <div class='tier-row'>
                <div class='tier-label' style={{styleColor tier.color}}>
                  <input
                    class='tier-name'
                    aria-label='Tier label'
                    value={{tier.label}}
                    {{on 'input' (fn this.renameTier tier)}}
                  />
                  <div class='tier-tools'>
                    <input
                      class='tier-color'
                      type='color'
                      aria-label='Tier color'
                      value={{tier.color}}
                      {{on 'input' (fn this.recolorTier tier)}}
                    />
                    <button
                      type='button'
                      class='tier-del'
                      {{on 'click' (fn this.removeTier tier)}}
                    >×</button>
                  </div>
                </div>
                <div
                  class='strip {{if (eq this.dropTierKey tier.key) "drop-active"}}'
                  data-droptarget
                  data-tier-key={{tier.key}}
                >
                  {{#each (this.itemsForTier tier.key) as |item|}}
                    <div
                      class='tile {{if (this.isDragging item) "is-dragging"}}'
                      data-tile
                      {{on 'pointerdown' (fn this.startDrag item)}}
                    >
                      {{#if (this.showImg item)}}
                        <img
                          src={{item.image.resolvedUrl}}
                          alt={{item.name}}
                          class='tile-img'
                          draggable='false'
                          {{on 'error' (fn this.markBroken item.id)}}
                        />
                      {{else}}
                        <span class='tile-text'>{{if item.name item.name '?'}}</span>
                      {{/if}}
                      {{#if item.name}}
                        <span class='tile-cap'>{{item.name}}</span>
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
              class='strip tray {{if (eq this.dropTierKey "__unranked__") "drop-active"}}'
              data-droptarget
              data-tier-key='__unranked__'
            >
              {{#each this.unrankedItems as |item|}}
                <div
                  class='tile {{if (this.isDragging item) "is-dragging"}}'
                  data-tile
                  {{on 'pointerdown' (fn this.startDrag item)}}
                >
                  {{#if (this.showImg item)}}
                    <img
                      src={{item.image.resolvedUrl}}
                      alt={{item.name}}
                      class='tile-img'
                      draggable='false'
                      {{on 'error' (fn this.markBroken item.id)}}
                    />
                  {{else}}
                    <span class='tile-text'>{{if item.name item.name '?'}}</span>
                  {{/if}}
                  {{#if item.name}}
                    <span class='tile-cap'>{{item.name}}</span>
                  {{/if}}
                </div>
              {{else}}
                <span class='tray-empty'>Everything is ranked. 🎉</span>
              {{/each}}
            </div>
          </div>
        {{else}}
          <div class='no-template'>
            Link a Tier Template to load items to rank.
          </div>
        {{/if}}

        {{#if this.draggingId}}
          <div class='ghost' style={{ghostPos this.ghostX this.ghostY}}>
            {{#if this.ghostURL}}
              <img src={{this.ghostURL}} alt='' class='tile-img' draggable='false' />
            {{else}}
              <span class='tile-text'>{{if this.ghostLabel this.ghostLabel '?'}}</span>
            {{/if}}
          </div>
        {{/if}}
      </section>

      <style scoped>
        .board {
          position: relative;
          height: 100%;
          min-height: 0;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          background: var(--background, #15161a);
          color: var(--foreground, #f4f5f7);
          font-family: var(--font-sans, system-ui, sans-serif);
        }
        .board-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          flex-wrap: wrap;
          gap: 0.75rem;
          padding: 0.875rem 1rem;
          border-bottom: 1px solid var(--border, #2c2e36);
          background: var(--card, #1c1e24);
        }
        h1 {
          margin: 0;
          font-size: 1.125rem;
          font-weight: 700;
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
          color: var(--foreground, #f4f5f7);
          background: var(--background, #15161a);
          border: 1px solid var(--border, #2c2e36);
          border-radius: var(--radius, 0.375rem);
        }
        .ctl-input::placeholder {
          color: var(--muted-foreground, #9aa0ad);
        }
        .btn {
          padding: 0.3125rem 0.625rem;
          font: inherit;
          font-size: 0.8125rem;
          font-weight: 600;
          cursor: pointer;
          color: var(--primary-foreground, #15161a);
          background: var(--primary, #f4f5f7);
          border: 1px solid transparent;
          border-radius: var(--radius, 0.375rem);
        }
        .btn.ghost-btn {
          color: var(--foreground, #f4f5f7);
          background: transparent;
          border-color: var(--border, #2c2e36);
        }
        .tiers {
          min-height: 0;
          overflow: auto;
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          padding: 0.5rem;
        }
        .tier-row {
          display: grid;
          grid-template-columns: 5.5rem minmax(0, 1fr);
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
          border-radius: var(--radius, 0.375rem);
          color: #111;
        }
        .tier-name {
          width: 100%;
          padding: 0.125rem 0.25rem;
          font: inherit;
          font-weight: 800;
          font-size: 1rem;
          text-align: center;
          color: #111;
          background: rgba(255, 255, 255, 0.55);
          border: none;
          border-radius: 0.25rem;
        }
        .tier-tools {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.25rem;
        }
        .tier-color {
          width: 1.5rem;
          height: 1.25rem;
          padding: 0;
          border: none;
          background: none;
          cursor: pointer;
        }
        .tier-del {
          width: 1.25rem;
          height: 1.25rem;
          line-height: 1;
          cursor: pointer;
          color: #111;
          background: rgba(255, 255, 255, 0.55);
          border: none;
          border-radius: 0.25rem;
        }
        .strip {
          display: flex;
          flex-wrap: wrap;
          align-content: flex-start;
          gap: 0.25rem;
          padding: 0.25rem;
          background: var(--card, #1c1e24);
          border: 1px solid var(--border, #2c2e36);
          border-radius: var(--radius, 0.375rem);
        }
        .strip.drop-active {
          outline: 2px dashed var(--primary, #f4f5f7);
          outline-offset: -2px;
        }
        .tray-wrap {
          border-top: 1px solid var(--border, #2c2e36);
          background: var(--card, #1c1e24);
          padding: 0.5rem;
        }
        .tray-label {
          margin: 0 0 0.375rem;
          font-size: 0.6875rem;
          font-weight: 700;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--muted-foreground, #9aa0ad);
        }
        .tray {
          min-height: 4rem;
          max-height: 40%;
          overflow: auto;
        }
        .tray-empty {
          padding: 0.75rem;
          font-size: 0.8125rem;
          color: var(--muted-foreground, #9aa0ad);
        }
        .no-template {
          display: grid;
          place-items: center;
          padding: 2rem;
          color: var(--muted-foreground, #9aa0ad);
        }
        .tile {
          position: relative;
          width: 4rem;
          height: 4rem;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: grab;
          touch-action: none;
          user-select: none;
          overflow: hidden;
          background: var(--background, #15161a);
          border: 1px solid var(--border, #2c2e36);
          border-radius: 0.25rem;
        }
        .tile.is-dragging {
          opacity: 0.3;
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
          color: #fff;
          background: rgba(0, 0, 0, 0.6);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .ghost {
          position: absolute;
          z-index: 1000;
          width: 4rem;
          height: 4rem;
          transform: translate(-50%, -50%) rotate(-3deg);
          pointer-events: none;
          overflow: hidden;
          display: flex;
          align-items: center;
          justify-content: center;
          background: var(--background, #15161a);
          border: 1px solid var(--primary, #f4f5f7);
          border-radius: 0.25rem;
          box-shadow: 0 8px 20px rgba(0, 0, 0, 0.45);
        }
      </style>
    </template>
  };

  static embedded = class extends Component<typeof TierList> {
    get sortedTiers(): Tier[] {
      let own = (this.args.model.tiers ?? []).filter(Boolean);
      let base = own.length
        ? own
        : (this.args.model.template?.tiers ?? []).filter(Boolean);
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
              <span class='emb-key' style={{styleColor t.color}}>{{t.label}}</span>
              <span class='emb-count'>{{this.countFor t.key}}</span>
            </div>
          {{/each}}
        </div>
      </div>
      <style scoped>
        .emb {
          padding: 0.75rem;
          background: var(--background, #15161a);
          color: var(--foreground, #f4f5f7);
          font-family: var(--font-sans, system-ui, sans-serif);
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
          color: #111;
          border-radius: 0.1875rem;
        }
        .emb-count {
          font-size: 0.75rem;
          color: var(--muted-foreground, #9aa0ad);
        }
      </style>
    </template>
  };

  static fitted = class extends Component<typeof TierList> {
    get sortedTiers(): Tier[] {
      let own = (this.args.model.tiers ?? []).filter(Boolean);
      let base = own.length
        ? own
        : (this.args.model.template?.tiers ?? []).filter(Boolean);
      return [...base].sort(byOrder);
    }

    get ranked(): number {
      return (this.args.model.placements ?? []).filter(
        (p) => p && p.tierKey,
      ).length;
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
            10px,
            calc(3px + 2.2cqi + 1cqb - 0.6 * var(--ar)),
            18px
          );
          --fit-meta-size: max(8px, calc(var(--type-base) / var(--type-ratio)));
          --fit-headline-size: max(
            11px,
            calc(var(--type-base) * pow(var(--type-ratio), 2))
          );
          --fit-pad: clamp(5px, calc(2px + 1.8cqi), 14px);
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          gap: 2px;
          padding: var(--fit-pad);
          box-sizing: border-box;
          overflow: hidden;
          background: var(--background, #15161a);
          color: var(--foreground, #f4f5f7);
          font-family: var(--font-sans, system-ui, sans-serif);
        }
        .r-head,
        .r-body,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .headline {
          margin: 0;
          font-size: var(--fit-headline-size, 14px);
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
          font-size: var(--fit-meta-size, 9px);
          font-weight: 800;
          text-align: center;
          color: #111;
          border-radius: 2px;
        }
        .r-meta {
          align-self: end;
          font-size: var(--fit-meta-size, 9px);
          color: var(--muted-foreground, #9aa0ad);
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

  static edit = class extends Component<typeof TierList> {
    <template>
      <div class='edit'>
        <label class='row'>
          <span class='lbl'>Title</span>
          <@fields.title />
        </label>
        <div class='row'>
          <span class='lbl'>Template</span>
          <@fields.template />
        </div>
        <p class='hint'>
          Rank items by dragging them in the isolated view. Tiers default from
          the template; edit them on the board.
        </p>
      </div>
      <style scoped>
        .edit {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          padding: 1rem;
        }
        .row {
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
        }
        .lbl {
          font-size: 0.75rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted-foreground, #9aa0ad);
        }
        .hint {
          margin: 0;
          font-size: 0.8125rem;
          color: var(--muted-foreground, #9aa0ad);
        }
      </style>
    </template>
  };
}
