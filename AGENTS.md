# Instructions for AI Agents

## Definitions the boxel platform tests against

Some definitions in this repo are system-level: code and tests in the boxel monorepo ([cardstack/boxel](https://github.com/cardstack/boxel)) depend on them. Boxel lists them in [`packages/catalog/test-subset.json`](https://github.com/cardstack/boxel/blob/main/packages/catalog/test-subset.json), which is the authoritative list, and tests the platform against a pinned revision of this repo. Today the list holds the operation-permission policy definitions:

- `realm-policy/realm-policy.gts`, with `RealmPolicy`, `PolicyRule` and `OperationGrant`
- `fields/policy-predicate/policy-predicate.gts`, with `PolicyPredicateField`

This repo is their only source. Boxel keeps no copy of them.

To change one of these files, or to add one:

1. **Keep it compatible with boxel `main`.** The deployed catalog realm serves this repo's `main`, running against the deployed platform. Platform code the change needs, such as a serializer, a `runtime-common` export or a base module, lands in boxel first.
2. **Name the branch after the boxel branch that pins the change.** The `Boxel Test Subset` workflow runs boxel's tests for these files whenever a PR touches one. It runs them against the boxel branch with the same name when there is one, and otherwise against boxel `main`.
3. **Only import what boxel's test stack can serve.** Each import must be one of:
   - another file in the list, which then goes in the manifest too;
   - a base module (`https://cardstack.com/base/…`);
   - `@cardstack/boxel-ui/*` or `@cardstack/boxel-icons/*`;
   - a module the boxel host shims.
4. **Re-pin boxel after this repo merges.** In the boxel PR, run `pnpm --dir packages/catalog catalog:test-subset --bump`. If no boxel PR is paired with the change, open one that only bumps the pin. Until boxel bumps, its tests keep running against the old definition, and its next PR that touches the manifest fails its pin check.

The full procedure, including how to test a change in this repo against boxel's tests before either side merges, is boxel's `catalog-test-subset` skill (`.claude/skills/catalog-test-subset/SKILL.md` in cardstack/boxel).
