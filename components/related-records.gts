import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { gt } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';

import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { StatePill } from '@cardstack/catalog/components/state-pill';

import type { CardDef } from '@cardstack/base/card-api';

/**
 * One record related to the subject, and why.
 *
 * `relationship` is the load-bearing field. A flat list of linked cards tells
 * a reader *that* things are connected; it never tells them *how*, which is
 * the only thing that makes the list actionable.
 */
export interface RelatedRecord {
  card: CardDef;
  // The edge, in the subject's own words: "raised by", "blocks", "invoiced
  // on", "duplicate of". Read from the subject outward, so the group heading
  // completes the sentence "this record is …".
  relationship: string;
  // Optional secondary line — a date, a status, whatever makes this row
  // distinguishable from its siblings.
  detail?: string;
  // Marks an edge the reader usually needs first. At most a couple per group.
  emphasis?: boolean;
}

interface RelatedRecordsSignature {
  Args: {
    records: RelatedRecord[];
    heading?: string;
    // Show only this many per group before a "+N more" toggle. Default 5.
    perGroup?: number;
    onOpen?: (card: CardDef) => void;
    emptyLabel?: string;
  };
  Element: HTMLElement;
}

const DEFAULT_PER_GROUP = 5;

/**
 * What else is connected to this record, grouped by how.
 *
 * ### Grouping by relationship is the whole design
 *
 * The default way to build this is one list of linked cards. That list
 * answers "what is connected" and leaves the reader to work out *why* from
 * the card titles — which they cannot, because a Work Order linked to an
 * Asset could be its history, its open work, or the job that damaged it.
 *
 * Grouping by the edge turns the component from a list into an answer:
 * *"this record is **blocked by** two things and **invoiced on** one"*.
 *
 * ### Group order is first-seen, not alphabetical
 *
 * The host supplies the records, and the order it supplies them in usually
 * encodes importance — blockers before history. Sorting alphabetically would
 * destroy that and put "attachments" above "blocked by".
 *
 * ### Counts live on the group heading, not on a summary line
 *
 * A separate "12 related records" line makes the reader hold a number while
 * scanning for the one that matters. Per-group counts are read where they
 * are used.
 *
 * ### Truncation is per group, and reversible in place
 *
 * A group past `perGroup` collapses with a toggle rather than scrolling, so a
 * record with forty attachments does not bury the two blockers underneath it.
 */
export class RelatedRecords extends GlimmerComponent<RelatedRecordsSignature> {
  @tracked expanded: string[] = [];

  get groups(): { name: string; rows: RelatedRecord[] }[] {
    let order: string[] = [];
    let buckets = new Map<string, RelatedRecord[]>();
    for (let r of this.args.records ?? []) {
      if (!r?.card) {
        continue;
      }
      let name = r.relationship?.trim() || 'Related';
      if (!buckets.has(name)) {
        buckets.set(name, []);
        order.push(name);
      }
      buckets.get(name)!.push(r);
    }
    // Emphasised rows rise within their group, so the edge the reader needs
    // first is not the one hidden behind the "+N more" toggle.
    return order.map((name) => ({
      name,
      rows: buckets
        .get(name)!
        .slice()
        .sort(
          (a, b) => Number(Boolean(b.emphasis)) - Number(Boolean(a.emphasis)),
        ),
    }));
  }

  get isEmpty(): boolean {
    return this.groups.length === 0;
  }

  get perGroup(): number {
    return this.args.perGroup ?? DEFAULT_PER_GROUP;
  }

  visible = (group: {
    name: string;
    rows: RelatedRecord[];
  }): RelatedRecord[] => {
    if (this.expanded.includes(group.name)) {
      return group.rows;
    }
    return group.rows.slice(0, this.perGroup);
  };

  hiddenCount = (group: { name: string; rows: RelatedRecord[] }): number => {
    if (this.expanded.includes(group.name)) {
      return 0;
    }
    return Math.max(0, group.rows.length - this.perGroup);
  };

  isExpanded = (group: { name: string; rows: RelatedRecord[] }): boolean =>
    this.expanded.includes(group.name);

  toggle = (name: string) => {
    this.expanded = this.expanded.includes(name)
      ? this.expanded.filter((n) => n !== name)
      : [...this.expanded, name];
  };

  titleOf = (r: RelatedRecord): string => {
    let c = r.card as any;
    return c?.cardTitle || c?.cardInfo?.name || 'Untitled';
  };

  open = (card: CardDef) => {
    this.args.onOpen?.(card);
  };

  <template>
    <section
      class='related'
      aria-label={{if @heading @heading 'Related records'}}
      ...attributes
    >
      <h3 class='related-title'>{{if @heading @heading 'Related'}}</h3>

      {{#if this.isEmpty}}
        <EmptyState
          @title={{if
            @emptyLabel
            @emptyLabel
            'Nothing is linked to this record yet'
          }}
          @texture={{false}}
          style={{COMPACT_EMPTY_STYLE}}
        />
      {{else}}
        {{#each this.groups key='name' as |group|}}
          <div class='group'>
            <h4 class='group-name'>
              {{group.name}}
              <StatePill @label='{{group.rows.length}}' @hue='slate' />
            </h4>
            <ul class='rows'>
              {{! keyed by card id — relationship is identical for every row in a
                group, so keying on it would collide and Glimmer would rebuild
                every row on any re-render }}
              {{#each (this.visible group) key='card.id' as |row|}}
                <li class='row {{if row.emphasis "emph"}}'>
                  {{#if @onOpen}}
                    <button
                      type='button'
                      class='open'
                      {{on 'click' (fn this.open row.card)}}
                    >
                      <span class='t'>{{this.titleOf row}}</span>
                      {{#if row.detail}}
                        <span class='d'>{{row.detail}}</span>
                      {{/if}}
                    </button>
                  {{else}}
                    <span class='open static'>
                      <span class='t'>{{this.titleOf row}}</span>
                      {{#if row.detail}}
                        <span class='d'>{{row.detail}}</span>
                      {{/if}}
                    </span>
                  {{/if}}
                </li>
              {{/each}}
            </ul>
            {{#if (gt (this.hiddenCount group) 0)}}
              <Button
                @appearance='link'
                @size='s'
                class='more'
                {{on 'click' (fn this.toggle group.name)}}
              >+{{this.hiddenCount group}} more</Button>
            {{else if (this.isExpanded group)}}
              <Button
                @appearance='link'
                @size='s'
                class='more'
                {{on 'click' (fn this.toggle group.name)}}
              >Show less</Button>
            {{/if}}
          </div>
        {{/each}}
      {{/if}}
    </section>

    <style scoped>
      .related {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        min-width: 0;
        padding: var(--boxel-sp);
        background: var(--background);
        color: var(--foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .related-title {
        margin: 0;
        font: 600 var(--boxel-font-xs);
        text-transform: uppercase;
        letter-spacing: var(--boxel-lsp-lg);
        color: var(--muted-foreground);
      }
      .group + .group {
        margin-top: var(--boxel-sp-xs);
      }
      .group-name {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        margin: 0 0 var(--boxel-sp-xxxs);
        font: 600 var(--boxel-font-sm);
      }
      .rows {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 1px;
      }
      .open {
        width: 100%;
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xxs);
        padding: var(--boxel-sp-xxxs) var(--boxel-sp-xxs);
        text-align: left;
        font: var(--boxel-font-sm);
        color: inherit;
        background: none;
        border: 0;
        border-radius: var(--radius-sm);
        cursor: pointer;
      }
      .open:not(.static):hover {
        background: var(--muted);
      }
      .open.static {
        cursor: default;
      }
      .open:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -2px;
      }
      /* Emphasis is weight, not a badge: a badge column would be mostly
         empty, and weight reads at a glance without costing width. */
      .row.emph .t {
        font-weight: 600;
      }
      .t {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .d {
        flex: none;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .more {
        align-self: flex-start;
      }
      /* Narrow: the detail line goes rather than wrapping each row to two
         lines, which would halve how many relationships fit on screen. */
      @container (width < 320px) {
        .d {
          display: none;
        }
      }
    </style>
  </template>
}

export default RelatedRecords;
