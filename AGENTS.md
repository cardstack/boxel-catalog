# Instructions for AI Agents

## Definitions the boxel platform tests against

Some definitions in this repo are system-level: code and tests in the boxel monorepo ([cardstack/boxel](https://github.com/cardstack/boxel)) depend on them. Boxel lists them in [`packages/catalog/test-subset.json`](https://github.com/cardstack/boxel/blob/main/packages/catalog/test-subset.json) and tests the platform against a pinned revision of this repo. This repo is their only source. Boxel keeps no copy of them.

**Before changing or moving a file, check whether its path is in that manifest's `files` list.** The manifest is the only complete list. It grows as boxel adds definitions, so don't rely on memory or on the examples here. Examples are the operation-permission policy definitions:

- `realm-policy/realm-policy.gts`, with `RealmPolicy`, `PolicyRule` and `OperationGrant`
- `fields/policy-predicate/policy-predicate.gts`, with `PolicyPredicateField`

To change a file the manifest lists, or to add one:

1. **Keep it compatible with boxel `main`.** The deployed catalog realm serves this repo's `main`, running against the deployed platform. Platform code the change needs, such as a serializer, a `runtime-common` export or a base module, lands in boxel first.
2. **Name the branch after the boxel branch that pins the change, and push that boxel branch first.** The `Boxel Test Subset` workflow runs boxel's tests for these files whenever a PR touches one. When it runs, it reads the manifest from the boxel branch with the same name, and from boxel `main` when there is no such branch. So when you add a file, push the boxel branch with its manifest entry before you push this branch or open the PR. Otherwise the workflow reads boxel `main`'s manifest, which doesn't list the new file, and passes without running any test. If it already ran, re-run it once the boxel branch exists.
3. **Only import what boxel's test stack can serve.** Each import must be one of:
   - another file in the list, which then goes in the manifest too;
   - a base module (`https://cardstack.com/base/…`);
   - `@cardstack/boxel-ui/*` or `@cardstack/boxel-icons/*`;
   - a module the boxel host shims.
4. **Re-pin boxel after this repo merges.** In the boxel PR, run `pnpm --dir packages/catalog catalog:test-subset --bump`. If no boxel PR is paired with the change, open one that only bumps the pin. Until boxel bumps, its tests keep running against the old definition, and its next PR that touches the manifest fails its pin check.

The full procedure, including how to test a change in this repo against boxel's tests before either side merges, is boxel's `catalog-test-subset` skill (`.claude/skills/catalog-test-subset/SKILL.md` in cardstack/boxel).

## Fixing this repo for a boxel change that breaks it

Boxel pins a revision of this repo in `packages/catalog/test-subset.json`, and production deploys that boxel with this whole repo at the pinned revision, not only the files the manifest lists. So boxel's Lint Catalog lints the whole repo at the pin against every boxel change, and a boxel change that breaks a file here can't merge while it still pins a revision that has the broken file.

When a boxel change breaks this repo, such as a renamed host tool or a tightened type, the fix here and the boxel change are a pair, and the boxel PR merges first:

1. Pair the two PRs in both descriptions: this PR says `Merges after: cardstack/boxel#N`, and the boxel PR says `Merges before: cardstack/boxel-catalog#M`.
2. The boxel PR pins this PR's head. Re-pin it whenever this PR gets new commits. Boxel's Catalog Test Subset check accepts that pin only while this PR is open, ready for review and approved, and neither PR is stacked.
3. Once this PR is approved, re-run the boxel PR's Lint Catalog and Catalog Test Subset checks. Approving a PR here doesn't re-run them.
4. Merge the boxel PR, then this PR right after it, **with a merge commit**. A squash or a rebase leaves the pinned commit off `main`, and production's deploy of the pin then refuses.

Boxel's `catalog-pairing` skill (`.claude/skills/catalog-pairing/SKILL.md` in cardstack/boxel) has the full procedure and how to read each check's failure.

## How a change reaches staging and production

Staging syncs `main` on every merge. Production gets the catalog only from the **Deploy to production** workflow. Boxel's production deploy runs it with the catalog revision boxel pins, before and after its release, and anyone can run it by hand to ship `main` ahead of boxel. It refuses while a pull request it would deploy says `Merges after: cardstack/boxel#N` and production doesn't run #N yet. So when a change needs boxel code, declare that line even if no check requires it. The `catalog-deploy` skill (`.claude/skills/catalog-deploy/SKILL.md`) covers deploying and reading a refusal.
