# Listing conformance harness

Machine-checkable quality gates for catalog listing packages. Run it on any
top-level listing directory (one containing a `<Type>Listing/*.json`):

```
node scripts/conformance/run.mjs <listing-dir> \
  [--phase static|full]     # default static; full adds boxel-cli / realm gates
  [--realm <url>]           # dev realm for the dynamic gates (D02-D05)
  [--json <out.json>]       # report path (default <dir>/.conformance-report.json, gitignored)
  [--waivers <file.yaml>]   # default <dir>/.conformance-waivers.yaml
  [--offline]               # skip the icon-CDN network gate (S12)
```

Exit codes: `0` pass (warnings allowed) · `1` errors found · `2` harness fault.

## Phases

- **Static (S01–S14)** — pure Node 20 stdlib, no install, <15s. Runs in CI
  (`.github/workflows/conformance.yaml`) on changed listing dirs in PRs and in
  a nightly sweep over the whole catalog. The only network call is S12 (icon
  CDN HEAD), skippable with `--offline`.
- **Dynamic (D01–D05)** — local/pre-PR only: `npx boxel parse`, realm `/_lint`,
  module-load probe (Gate A), typed-search counts (Gate B), prerender smoke.
  Needs `@cardstack/boxel-cli` ≥0.4 and (for D02–D05) `--realm`.

## Severities

- **error** — realm-bricking / render-crashing / structurally broken. Blocks.
- **warn** — quality rules (theme tokens, reuse, slop signals). Warnings never
  fail the run, but the card factory's conform step requires each one to be
  **fixed or waived with a reason** — adjudicated, never silently ignored.
- **info** — advisory (e.g. a similar listing already exists).

## Waivers

`<listing-dir>/.conformance-waivers.yaml` travels with the PR (it is excluded
from realm sync via `.boxelignore`):

```yaml
waivers:
  - rule: reuse/hand-rolled-button
    file: piano.gts
    reason: "Piano-key buttons need custom pressed-state animation; Button's chrome fights it"
```

`file` is optional (omit to waive the rule package-wide). Reviewers see the
justification in the diff; CI applies the same waivers the local run used.

## Report

`--json` emits a machine-readable report (schema: `report-schema.json`). Each
finding carries `rule`, `severity`, `file`, `loc`, `message`, `suggestion`, and
`fixRef` (a pointer into the card-factory skill tree), so an agent can consume
the report as a fix-list.

## Extending

One module per gate in `gates/`, uniform interface `{ id, title, phase, run(ctx) }`
returning findings. Shared scanning helpers live in `lib/` (`gts-scan.mjs` is a
regex/brace scanner, deliberately not a parser — anything subtler belongs in
glint/eslint via `ci-lint.yaml`). Reuse/slop rule tables live in `rules/`.
Self-test: `node scripts/conformance/selftest.mjs`.
