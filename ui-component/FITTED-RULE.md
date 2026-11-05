# Fitted rule: what fits in a fitted card, and how parts shrink

A card's fitted view is its delegated rendering inside someone else's layout: a board lane, a grid, a picker. Its job is to show as much useful information as the size allows, and never a half-cut line. This rule makes that arithmetic instead of taste, using the IMS ruler (2 / 4 / 8 / 12 / 16 / 24, type 15 / 13 / 12 at line-height 1.5).

## 1. Offer content in priority order

Every fitted view hands its content to `FitTile` in this order, and FitTile drops rows from the bottom as the size shrinks:

| Priority | Row | Content | Type |
|---|---|---|---|
| 1 | who | avatar (32), title, subtitle | title 15/600 · subtitle 13 |
| 2 | state | status chips, most important first | chip 12/600 |
| 3 | fact | the one fact that explains the state (what blocks it, the next step, the date that matters) | 12 |
| 4 | relations | linked cards in their **atom** format, one line | 13 |

A fitted view never invents a fifth row. More detail belongs in embedded or isolated.

## 2. The budget per size: pack, don't just drop

The goal is the most information each size can hold, not the safest subset. Short sizes switch to compact type, tighten line gaps and spend width (state beside the title) before they drop a row. The avatar is decoration, so it goes first.

Row heights. Normal type: title 22.5 · subline 19.5 · state 22 · fact 18 · relations 22, rows 8 apart (subline 2 under the title). Compact type (under 170 tall): title 19.5 · subline 18 · state 18 · fact 18 · relations 22, rows 4 apart. Relations keep 22 as headroom: a field's atom sits in Boxel's inline wrapper (a text line), so Chip aligns to the line top rather than the baseline, which would leave descender space under it and outgrow the row.

| Size | Lines (inside the padding) | Fits |
|---|---|---|
| 250 × 170 (regular-tile) | avatar · title / subline / state / fact / relations | 130 of 146 |
| 150 × 170 (small-tile) | same, no avatar | 130 of 146 |
| 400 × 105 (triple-wide-strip) | avatar · title + state / subline / fact / relations | 87.5 of 89 |
| 250 × 105 (triple-strip) | avatar · title / subline / state / fact | 83.5 of 89 |
| 150 × 105 (large-badge) | title / subline / state / fact | 83.5 of 89 |
| 400 × 65 (double-wide-strip) | title + state / subline | 39.5 of 49 |
| 250 × 65 (double-strip) | title + state / subline | 39.5 of 49 |
| 150 × 65 (medium-badge) | title / subline | 39.5 of 49 |
| 250 × 40 (single-strip) | title + state | 19.5 of 24 |
| 150 × 40 (small-badge) | title | 19.5 of 24 |

Width rules: under 250 the avatar drops; under 105 tall the avatar always drops (its width goes to state); state shares the title row from 400 wide, and at every width under 105 tall except under 250. The title column always keeps at least 7rem.

**No crop, at three levels.** A row that doesn't fit is not rendered. Chips and atoms past the end of their line wrap out of sight whole. A single item still too wide ellipsizes ("● Under Re…"); Chip keeps its label in its own box for this.

A part can't style a caller's children: scoped CSS puts its scope on the last part of a selector, so `.row > *` only matches the part's own elements. Budget decisions are made per row, and per-item behaviour (ellipsis, compacting) lives in the item's own component.

## 3. When a part is too big for a small card

Decision ladder, in this order:

1. **Reassign token values** when only size differs and the result stays on the ruler and above the floor. Chip under 170 tall drops its block padding (22 → 18 high).
2. **Change the form** when shrinking would cross a floor: text below 12px, or a frame that costs more width than it carries. Chip under 65 tall or 150 wide drops its pill and becomes dot + text.
3. **A size or config arg** only when the caller knows the context statically and it isn't a fitted card (for example an `@size` on a toolbar control). Inside fitted cards, parts read the `fitted-card` container themselves, so card authors never pass density.

Floors: text 12px, line-height 1.5, hit areas aren't needed (a fitted card is one target), avatar 24 minimum (hidden rather than smaller).

## 4. Atoms inside fitted

- A relationship shows as the linked card's own **atom** (`<@fields.x @format='atom' />`), never a copied name string, so the linked card stays the one place that decides how it reads.
- An atom must fit one 20px line: name plus at most one chip, no padding of its own.
- A `containsMany` field can have an atom too (Certification → its name as a chip, danger once expired).

## 5. Weaknesses this rule exposed (Vendor Onboarding pilot)

| Weakness | Fix |
|---|---|
| boxel-ui `FittedCard` hides meta, footer and badges under 170 tall, so a 105px board tile could show no state at all | `FitTile` budgets rows instead of hiding whole regions |
| Chip had one size, too tall for strips | Chip compacts itself inside small fitted cards (token step, then form step) |
| Board tiles were `triple-strip` (105 tall), room for who + state only | Vetting board uses `regular-tile` (250 × 170), where all four rows fit |
| Certification had no atom, so a profile couldn't show its credentials compactly | `CertificationField.atom` |
| Remaining: Avatar has no fitted-aware size; Token, Badge and Delta don't compact yet | next pass |
