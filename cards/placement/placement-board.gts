import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import { Pill } from '@cardstack/boxel-ui/components';
import { gt } from '@cardstack/boxel-ui/helpers';

import {
  PlacementZoneField,
  PlacementField,
  isDirty,
  overCapacityZones,
  placedItemIds,
  itemKey,
  sameItem,
  nextSeq,
  placementsIn,
} from '@cardstack/catalog/fields/placement/placement-vocabulary';
import {
  PlacementPalette,
  type PlacementItem,
} from '@cardstack/catalog/components/placement-palette';
import { PlacementDropZone } from './components/placement-drop-zone';

/**
 * A plan for putting things in places.
 *
 * The board holds three things: the **zones** (where things can go), the
 * **committed** arrangement (what is true now), and the **draft** (what the
 * user is proposing). Everything not yet in the draft shows in the palette.
 *
 * ### Why a draft at all
 *
 * The distinguishing move of this family, and the reason `Commit Placement`
 * is a separate command rather than a save button. Dragging a person to a
 * seat is a *proposal*: it is only real once the whole arrangement is
 * checked — no table over capacity, nobody double-seated, nobody left out.
 * A board that wrote through on every drag would make the half-finished
 * state the live one, and there is no half-finished seating plan that is
 * safe to publish.
 *
 * So the board is deliberately permissive — an over-capacity draft is
 * allowed to exist, because the user needs to *see* the conflict to resolve
 * it — and the commit gate is strict.
 *
 * ### Not a kanban
 *
 * boxel-ui's `KanbanPlane` and the catalog's `Board` own the
 * columns-of-cards case, including its drag engine. Use those when the
 * layout is N vertical lists and a move is immediate. This family exists for
 * zones laid out freely — seats at tables, slots on a shelf, rooms on a
 * floor plan — and for arrangements that stage before they land.
 *
 * Generic: the zones can be tables, shifts, shelves or interview
 * slots, and the items can be any card at all.
 */
export class PlacementBoard extends CardDef {
  static displayName = 'Placement Board';
  static icon = LayoutGridIcon;

  @field zones = containsMany(PlacementZoneField);

  @field placements = containsMany(PlacementField, {
    description: 'The committed arrangement — what is true now.',
  });

  @field draft = containsMany(PlacementField, {
    description:
      'The proposed arrangement. Commit Placement copies this over `placements`.',
  });

  // An explicit, curated pool rather than a live query: a placement board's
  // candidate set is a decision the author makes ("these 40 guests"), not a
  // filter over everything that happens to match. A board that silently
  // gained a row because someone else created a card would invalidate a plan
  // that was already half made.
  @field pool = linksToMany(() => CardDef, {
    description: 'Candidate items available to place.',
  });

  @field noun = contains(StringField, {
    description:
      'What one item is called here — "Guest", "Technician", "Box". Used in empty states and the palette heading.',
  });

  @field placedCount = contains(NumberField, {
    computeVia: function (this: PlacementBoard) {
      return placedItemIds(this.draft ?? []).size;
    },
  });

  @field unplacedCount = contains(NumberField, {
    computeVia: function (this: PlacementBoard) {
      let placed = placedItemIds(this.draft ?? []);
      return (this.pool ?? []).filter(
        (c) => c?.id && !placed.has(itemKey(c.id)),
      ).length;
    },
  });

  @field hasUncommittedChanges = contains(BooleanField, {
    computeVia: function (this: PlacementBoard) {
      return isDirty(this.placements ?? [], this.draft ?? []);
    },
  });

  @field conflictCount = contains(NumberField, {
    computeVia: function (this: PlacementBoard) {
      return overCapacityZones(this.zones ?? [], this.draft ?? []).length;
    },
  });

  @field isCommittable = contains(BooleanField, {
    computeVia: function (this: PlacementBoard) {
      return (
        isDirty(this.placements ?? [], this.draft ?? []) &&
        overCapacityZones(this.zones ?? [], this.draft ?? []).length === 0
      );
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get items(): PlacementItem[] {
      return (this.args.model.pool ?? [])
        .filter((c) => c?.id)
        .map((c) => ({
          id: c.id!,
          // `cardTitle`, not `title`: CardDef has no `title` field — the
          // display name is computed from `cardInfo.name`, and reading the
          // old name silently yields undefined, so every chip renders
          // "Untitled" with no error anywhere.
          title: c.cardTitle || c.cardInfo?.name || 'Untitled',
          detail: c.cardInfo?.summary ?? undefined,
        }));
    }

    itemFor = (itemId: string): PlacementItem | undefined => {
      return this.items.find((i) => sameItem(i.id, itemId));
    };

    // Clicking a chip — in the rail or in a zone — opens the real card.
    // `viewCard` is a top-level component arg, not `context.actions`: the
    // latter is not present in every format the board renders in.
    openItem = (item: PlacementItem) => {
      let card = (this.args.model.pool ?? []).find((c) =>
        sameItem(c?.id, item.id),
      );
      if (card) {
        this.args.viewCard?.(card, 'isolated');
      }
    };

    // ── Draft mutation ──────────────────────────────────────────────────
    // Every handler writes a NEW array onto `draft` rather than mutating the
    // existing one in place: a containsMany only re-renders (and only
    // serializes) when the field is reassigned, so an in-place `push` would
    // update the data and leave the screen stale.
    //
    // All of these touch `draft` and never `placements`. The committed field
    // has exactly one writer — CommitPlacementCommand — which is what makes
    // it safe to leave a half-finished plan open.

    get draft(): PlacementField[] {
      return this.args.model.draft ?? [];
    }

    // Drop an item into a zone. An item lives in at most one zone, so this
    // removes any existing placement first — that is what makes a drag
    // between zones a *move* rather than a copy, with no separate "remove
    // from the old zone" step for the user to forget.
    place = (itemId: string, zoneKey: string) => {
      let key = itemKey(itemId);
      let rest = this.draft.filter((p) => itemKey(p.itemId) !== key);
      this.args.model.draft = [
        ...rest,
        new PlacementField({
          itemId: key,
          zoneKey,
          seq: nextSeq(zoneKey, rest),
          placedAt: new Date(),
        }),
      ];
    };

    // Dropped ON another placement: land immediately before it. Sequences are
    // renumbered densely from 0 across the whole target zone afterwards, so
    // repeated reorders cannot drift into fractional or colliding values.
    reorder = (itemId: string, beforeItemId: string, zoneKey: string) => {
      let key = itemKey(itemId);
      let beforeKey = itemKey(beforeItemId);
      if (key === beforeKey) {
        return;
      }
      let others = this.draft.filter((p) => itemKey(p.itemId) !== key);
      let zoneRows = placementsIn(zoneKey, others);
      let index = zoneRows.findIndex((p) => itemKey(p.itemId) === beforeKey);
      if (index === -1) {
        this.place(itemId, zoneKey);
        return;
      }
      let moved = new PlacementField({
        itemId: key,
        zoneKey,
        seq: 0,
        placedAt: new Date(),
      });
      zoneRows.splice(index, 0, moved);
      let renumbered = zoneRows.map(
        (p, i) =>
          new PlacementField({
            itemId: itemKey(p.itemId),
            zoneKey,
            seq: i,
            placedAt: p.placedAt,
            note: p.note,
          }),
      );
      let elsewhere = others.filter((p) => p.zoneKey !== zoneKey);
      this.args.model.draft = [...elsewhere, ...renumbered];
    };

    // Back to the palette. Deliberately does not renumber what is left: the
    // remaining sequences stay strictly increasing, which is all the sort
    // needs, and leaving them alone keeps the diff the commit reports small.
    unplace = (itemId: string) => {
      let key = itemKey(itemId);
      this.args.model.draft = this.draft.filter(
        (p) => itemKey(p.itemId) !== key,
      );
    };

    get statusLabel(): string {
      let n = this.args.model.conflictCount ?? 0;
      if (n > 0) {
        return `${n} zone${n === 1 ? '' : 's'} over capacity`;
      }
      if (this.args.model.hasUncommittedChanges) {
        return 'Uncommitted changes';
      }
      return 'Committed';
    }

    <template>
      <main class='board'>
        <header class='board-head'>
          <div class='board-heading'>
            <h1 class='board-title'><@fields.cardTitle /></h1>
            <p class='board-sub'>
              {{@model.placedCount}}
              placed ·
              {{@model.unplacedCount}}
              to go
            </p>
          </div>
          <Pill
            class='board-status
              {{if (gt @model.conflictCount 0) "conflict"}}
              {{if @model.hasUncommittedChanges "dirty"}}'
          >{{this.statusLabel}}</Pill>
        </header>

        <div class='board-body'>
          <PlacementPalette
            class='board-rail'
            @items={{this.items}}
            @placements={{this.draft}}
            @searchable={{true}}
            @heading={{if @model.noun @model.noun 'To place'}}
            @onSelect={{this.openItem}}
          />

          <div class='zone-grid'>
            {{#each @model.zones key='key' as |zone|}}
              <PlacementDropZone
                @zone={{zone}}
                @placements={{this.draft}}
                @itemFor={{this.itemFor}}
                @onDropItem={{this.place}}
                @onReorder={{this.reorder}}
                @onRemove={{this.unplace}}
                @onSelect={{this.openItem}}
              />
            {{/each}}
          </div>
        </div>
      </main>

      <style scoped>
        .board {
          container-type: inline-size;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          min-height: 100%;
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
        }
        .board-head {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: var(--boxel-sp);
          flex-wrap: wrap;
        }
        .board-title {
          margin: 0;
          font: 700 var(--boxel-font-lg);
          letter-spacing: var(--boxel-lsp-xs);
        }
        .board-sub {
          margin: var(--boxel-sp-xxxs) 0 0;
          font: var(--boxel-font-sm);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .board-status.dirty {
          --pill-background-color: color-mix(
            in oklch,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
        }
        .board-status.conflict {
          --pill-background-color: color-mix(
            in oklch,
            var(--destructive, var(--boxel-danger)) 14%,
            var(--card, var(--boxel-light))
          );
          --pill-font-color: var(--destructive, var(--boxel-danger));
        }
        .board-body {
          display: grid;
          grid-template-columns: minmax(180px, 240px) 1fr;
          gap: var(--boxel-sp);
          align-items: start;
        }
        .board-rail {
          position: sticky;
          top: var(--boxel-sp);
        }
        .zone-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
          gap: var(--boxel-sp-sm);
        }
        /* The rail goes on top rather than shrinking: a search box and a
           list of names below ~180px stops being usable, and a horizontal
           rail reads fine when the zones own the rest of the height. */
        @container (width < 640px) {
          .board-body {
            grid-template-columns: 1fr;
          }
          .board-rail {
            position: static;
          }
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    // A board has five distinct editing jobs and they are not interchangeable:
    // naming it, declaring where things can go, choosing who is in play, and
    // the two arrangement arrays. Without a rail the form is one long scroll
    // of containsMany editors and the author loses their place after every
    // row they add.
    sections = [
      { id: 'board', label: 'Board' },
      { id: 'zones', label: 'Zones' },
      { id: 'pool', label: 'Pool' },
      { id: 'draft', label: 'Draft' },
      { id: 'committed', label: 'Committed' },
    ];

    <template>
      <form class='edit' aria-label='Edit placement board'>
        <nav class='rail' aria-label='Form sections'>
          <ul>
            {{#each this.sections key='id' as |s|}}
              <li><a href='#pb-{{s.id}}'>{{s.label}}</a></li>
            {{/each}}
          </ul>
        </nav>

        <div class='panes'>
          <section id='pb-board' aria-label='Board'>
            <h3>Board</h3>
            <label class='f'>
              <span>Item noun</span>
              <@fields.noun />
              <small>What one item is called here — “Guest”, “Technician”,
                “Box”. Used as the palette heading and in empty states.</small>
            </label>
          </section>

          <section id='pb-zones' aria-label='Zones'>
            <h3>Zones</h3>
            <p class='hint'>Where things can go.
              <strong>`key` is permanent</strong>
              — placements point at it, so renaming one orphans every placement
              that used it. Change `label` instead. Leave `capacity` blank for
              unlimited.</p>
            <@fields.zones />
          </section>

          <section id='pb-pool' aria-label='Pool'>
            <h3>Pool</h3>
            <p class='hint'>The candidates. A curated set, not a live query: a
              board that silently gained a row would invalidate a plan that was
              already half made.</p>
            <@fields.pool />
          </section>

          <section id='pb-draft' aria-label='Draft'>
            <h3>Draft
              <span class='badge'>{{@model.placedCount}}
                placed ·
                {{@model.unplacedCount}}
                to go</span>
            </h3>
            <p class='hint'>The proposed arrangement. Normally you edit this by
              dragging on the board, not here — this form is for bulk fixes and
              for seeding a board from an import.</p>
            <@fields.draft />
          </section>

          <section id='pb-committed' aria-label='Committed'>
            <h3>Committed
              {{#if @model.hasUncommittedChanges}}
                <span class='badge warn'>differs from draft</span>
              {{/if}}
            </h3>
            <p class='hint'><strong>Commit Placement is the single writer for
                this field.</strong>
              Editing it by hand bypasses the capacity gate and the movement
              record. Do it only to repair a board, never as the normal way to
              publish an arrangement.</p>
            <@fields.placements />
          </section>
        </div>
      </form>

      <style scoped>
        .edit {
          container-type: inline-size;
          display: grid;
          grid-template-columns: 140px 1fr;
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp-lg);
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
        }
        .rail {
          position: sticky;
          top: var(--boxel-sp);
          align-self: start;
        }
        .rail ul {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
          gap: 2px;
        }
        .rail a {
          display: block;
          padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
          font: 500 var(--boxel-font-sm);
          color: var(--muted-foreground, var(--boxel-450));
          text-decoration: none;
          border-left: 2px solid transparent;
          border-radius: var(--radius-sm, var(--boxel-border-radius-sm));
        }
        .rail a:hover,
        .rail a:focus-visible {
          color: var(--foreground, var(--boxel-dark));
          background: var(--muted, var(--boxel-100));
          border-left-color: var(--primary, var(--boxel-highlight));
        }
        .panes {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          min-width: 0;
        }
        .panes section {
          scroll-margin-top: var(--boxel-sp);
        }
        .panes h3 {
          margin: 0 0 var(--boxel-sp-xxs);
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          font: 600 var(--boxel-font);
        }
        .badge {
          font: var(--boxel-font-xs);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .badge.warn {
          color: var(--primary, var(--boxel-highlight));
          font-weight: 600;
        }
        .hint,
        .f small {
          margin: 0 0 var(--boxel-sp-xs);
          font: var(--boxel-font-xs);
          line-height: 1.5;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .f {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xxxs);
          max-width: 28rem;
        }
        .f > span {
          font: 500 var(--boxel-font-sm);
        }
        /* The rail becomes a horizontal strip rather than shrinking: five
           labels stacked in a 60px column are unreadable. */
        @container (width < 560px) {
          .edit {
            grid-template-columns: 1fr;
          }
          .rail {
            position: static;
          }
          .rail ul {
            flex-direction: row;
            flex-wrap: wrap;
          }
          .rail a {
            border-left: 0;
            border-bottom: 2px solid transparent;
          }
          .rail a:hover,
          .rail a:focus-visible {
            border-bottom-color: var(--primary, var(--boxel-highlight));
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <article class='board-embedded'>
        <h3 class='t'><@fields.cardTitle /></h3>
        <p class='m'>
          {{@model.placedCount}}
          placed ·
          {{@model.unplacedCount}}
          to go
          {{#if (gt @model.conflictCount 0)}}
            <span class='c'>· {{@model.conflictCount}} over capacity</span>
          {{/if}}
        </p>
      </article>
      <style scoped>
        .board-embedded {
          padding: var(--boxel-sp-xs);
          color: var(--foreground, var(--boxel-dark));
        }
        .t {
          margin: 0;
          font: 600 var(--boxel-font-sm);
        }
        .m {
          margin: 2px 0 0;
          font: var(--boxel-font-xs);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .c {
          color: var(--destructive, var(--boxel-danger));
          font-weight: 600;
        }
      </style>
    </template>
  };
}

export default PlacementBoard;
