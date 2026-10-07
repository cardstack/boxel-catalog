import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { PlacementBoard } from '../placement-board';
import {
  PlacementField,
  overCapacityZones,
  placedItemIds,
  isDirty,
  itemKey,
} from '@cardstack/catalog/fields/placement/placement-vocabulary';

export class CommitPlacementInput extends CardDef {
  @field board = linksTo(() => PlacementBoard, { searchable: true });
  @field allowOverCapacity = contains(BooleanField, {
    description:
      'Commit even when a zone exceeds its capacity. The override is recorded in the result message, never silently.',
  });
  @field committedByName = contains(StringField);
}

export class CommitPlacementResult extends CardDef {
  @field placedCount = contains(NumberField);
  @field addedCount = contains(NumberField);
  @field movedCount = contains(NumberField);
  @field removedCount = contains(NumberField);
  @field message = contains(StringField);
}

/**
 * Promote a Placement Board's draft to its committed arrangement.
 *
 * This is the single writer for `placements`. The board's UI only ever
 * touches `draft`; nothing else in the family writes the committed field.
 * That is what makes a half-finished plan safe to leave open — the live
 * arrangement cannot drift while someone is still dragging.
 *
 * ### The gate
 *
 * Refuses when any zone is over capacity, unless `allowOverCapacity` is set.
 * The override exists because real arrangements do get squeezed (one extra
 * chair at the family table), but it is opt-in and it is written into the
 * result message, so a commit that broke a stated ceiling is never silent.
 *
 * Refuses a no-op commit rather than writing an identical array and bumping
 * the instance's index generation for nothing.
 */
export class CommitPlacementCommand extends Command<
  typeof CommitPlacementInput,
  typeof CommitPlacementResult
> {
  static actionVerb = 'Commit';
  static displayName = 'Commit Placement';

  async getInputType() {
    return CommitPlacementInput;
  }

  protected async run(
    input: CommitPlacementInput,
  ): Promise<CommitPlacementResult> {
    let board = input.board;
    if (!board) {
      throw new Error('board is required');
    }

    let committed = board.placements ?? [];
    let draft = board.draft ?? [];

    if (!isDirty(committed, draft)) {
      throw new Error(
        'Refused: the draft matches the committed arrangement — nothing to commit.',
      );
    }

    // The arrangement must be one: each item once, in a zone that exists. A
    // duplicate would also count twice toward capacity.
    let zoneKeys = new Set((board.zones ?? []).map((z) => z?.key));
    let seen = new Set<string>();
    for (let p of draft) {
      let key = itemKey(p?.itemId);
      if (!key) {
        continue;
      }
      if (seen.has(key)) {
        throw new Error(`Refused: ${key} is placed more than once.`);
      }
      seen.add(key);
      if (!zoneKeys.has(p.zoneKey)) {
        throw new Error(
          `Refused: ${key} is placed in "${p.zoneKey ?? ''}", which is not a zone on this board.`,
        );
      }
    }

    let conflicts = overCapacityZones(board.zones ?? [], draft);
    if (conflicts.length > 0 && !input.allowOverCapacity) {
      let detail = conflicts
        .map((c) => `${c.key} (${c.count}/${c.capacity})`)
        .join(', ');
      throw new Error(
        `Refused: ${conflicts.length} zone(s) over capacity — ${detail}. Resolve them, or re-run with allowOverCapacity.`,
      );
    }

    // Movement stats, computed before the write so the message describes the
    // change rather than the end state — "12 placed" tells you nothing about
    // what this commit did.
    let byItem = (rows: PlacementField[]) =>
      new Map(
        rows
          .filter((p) => itemKey(p?.itemId))
          .map((p) => [itemKey(p.itemId), p.zoneKey ?? '']),
      );
    let before = byItem(committed);
    let after = byItem(draft);

    let addedCount = 0;
    let movedCount = 0;
    for (let [itemId, zoneKey] of after) {
      if (!before.has(itemId)) {
        addedCount++;
      } else if (before.get(itemId) !== zoneKey) {
        movedCount++;
      }
    }
    let removedCount = 0;
    for (let itemId of before.keys()) {
      if (!after.has(itemId)) {
        removedCount++;
      }
    }

    // Fresh rows, not shared ones: a later edit to a draft row must not
    // change what was committed, or `hasUncommittedChanges` would stay false.
    board.placements = draft.map(
      (p) =>
        new PlacementField({
          itemId: p.itemId,
          zoneKey: p.zoneKey,
          seq: p.seq,
          placedAt: p.placedAt,
          note: p.note,
        }),
    );

    await new SaveCardCommand(this.commandContext).execute({
      card: board,
    } as any);

    let placedCount = placedItemIds(draft).size;
    let who = input.committedByName ? ` by ${input.committedByName}` : '';
    let override =
      conflicts.length > 0
        ? ` Committed over capacity in ${conflicts.length} zone(s) under an explicit override.`
        : '';

    return new CommitPlacementResult({
      placedCount,
      addedCount,
      movedCount,
      removedCount,
      message: `Placement committed${who}: ${addedCount} added, ${movedCount} moved, ${removedCount} removed, ${placedCount} placed in total.${override}`,
    });
  }
}

export default CommitPlacementCommand;
