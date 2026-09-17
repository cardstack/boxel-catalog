# Promotion review brief

What a cold reviewer looks at on a Gold-Spec promotion PR. Used by the A4 review job and by a human or a local Claude Code session reviewing the same PR. One source of truth so the two cannot drift.

**The reviewer is never the author.** A session that wrote the PR has already decided every question this brief asks; re-asking them in the same context measures nothing. The 2026-08-21 retirement of the ConceptReview pipeline is the precedent: 117 of 118 reviews were agent-filed in one day and the pipeline measured nothing. Run this from a fresh session with the diff and this brief, nothing else.

## Out of scope: everything CI already owns

`scripts/check-promotion.py` runs on every PR and covers dangling imports and refs, matrix-realm leftovers, unresolved examples, instance `adoptsFrom` shape, Spec coverage, `cardInfo.name`, `cardTitle` convention, `cardDescription` presence, and the readMe length floor. Do not re-report any of those. If CI is green, treat them as settled and spend the review on what follows.

## 1. The readMe earns its place

The checks prove a readMe exists and is long enough. They cannot tell whether it is worth reading. Against the four prose traits in `spec-quality-standard.md`:

- **A copy-pasteable consumption line.** The real import path and a real snippet, not a description of one. For a command this is also its example evidence.
- **A why-this-shape rationale.** The one structural decision that makes the block right, stated as doctrine. Invoice's "overdue is derived, not stored". Loyalty Tier's "tiers are ORDERED, consumers never string-compare tier names".
- **A composition story.** What the block consumes instead of rebuilding, and what composes with it.
- **Multiple real usage ways.** Each with the actual field declaration from a real consumer.
- **A Non-goals paragraph** that defends the scope and names which sibling owns the excluded concern.

A readMe that is 400 characters of restated field list passes the floor and fails this section. Say so.

## 2. The examples are a world, not orphans

Every linked example resolves, because CI checked. Ask instead whether they show the block working: is the linked chain real, do the examples cover the states a consumer will hit (empty, overflowing, cancelled, void, missing links), and does a field Spec's `containedExamples` actually render. An example set that is three near-identical happy-path rows is a finding.

## 3. Nothing was rebuilt that the catalog already has

The closure arrives wholesale, so this is where duplication enters. Check each new module against `fields/`, `components/`, `commands/`, `packages/base` and `boxel-ui` by **kind, not name**. The precedent is Score: a self-declared copy of `fields/rating`, which was retired rather than promoted, and its consumers repointed. If a moved module duplicates something already in the catalog, the finding is "repoint at the existing one", not "rename it".

## 4. The block stays domain-neutral

The tell is the block's code naming a field, a type or a format that belongs to one app. A block that hits a decision only the domain knows should take it as an argument. Duplicate has no opinion on what a copy resets. Export has no opinion on which cells are formatted. If a promoted module hardcodes one consumer's vocabulary, it is not a shared block yet.

## 5. Placement and naming

- Is the target folder right? Fields in `fields/<name>/`, components at the root, cards in `cards/<cluster>/`, and a cluster's own commands in `cards/<cluster>/commands/`.
- Root `commands/` is in practice the listing-submission workflow namespace (`listing-create`, `process-github-event`), and it already holds plain function modules (`commands/utils.ts`, `commands/image-utils.ts`) as well. It is not a general home for helpers.
- Root `utils/` is the surface for a cross-domain pure helper — a comparator, a predicate builder. A module there is not invokable; a `Command` subclass never belongs in it.
- Is a new `cards/<cluster>/` name the one a stranger would guess, and does it match the domain rather than the app that happened to need it?
- Plain kebab folder names, no six-hex prefix. Those are minted by the listing submission workflow, which this pipeline does not run.

## 6. Changes beyond the move

The pilot's rule is that modules move verbatim apart from import rewriting. Any other edit in the diff is a deliberate change and needs a reason in the PR body. Read those edits specifically: they are where regressions enter, because they were written under type-checker pressure rather than design pressure. Hoisting a view out of a class expression is fine. Silently dropping a guard is not.

## 7. What the Gold label could not see

Gold is computed from counts. Two things it cannot check, worth one look each:

- An example link is counted after it resolves, but nobody asserted the instance is still meaningful. A Teammate deleted in a refresh leaves a resolving link to a stale world.
- Gold describes one concept, not its closure. The thin Specs written for closure modules on arrival are the weakest prose in the PR by construction. Read them, not just the headline ones.

## How to report

Post findings as PR review comments on the line they concern. Lead with the claim, then the consequence. No praise sections, no summary of what the PR does, the author knows. If nothing in sections 1 to 7 is wrong, say that in one line and approve nothing: approval and merge stay human.
