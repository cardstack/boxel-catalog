# Catalog Live Tests

Live tests run inside Headless Chrome against the **real** catalog realm
(`https://localhost:4201/catalog/` by default). Each `.test.gts` file lives in
the realm and is discovered at runtime via the realm's `_mtimes` endpoint —
files exporting a `runTests()` function are loaded by the host's
[`live-test.js`](../../../host/tests/live-test.js) loader and their QUnit
modules are registered.

## Directory layout

```
tests/
├── helpers/
│   ├── field-test-helpers.gts   — renderField / renderConfiguredField / buildField
│   └── test-fixtures.ts         — fixture card source strings + makeMockCatalogContents
└── live/
    ├── catalog-app/             — listing flows: create / install / remix / use, commands, browse
    └── fields/                  — per-field render tests + base-realm field spec sanity check
```

## How to run

From the repo root:

```bash
# Terminal 1 — bring up base + catalog realms, matrix, smtp
cd packages/realm-server && pnpm start:all

# Terminal 2 — run the live tests
cd packages/host && pnpm test:live
```

To run only a subset interactively in a browser:

```
https://localhost:4200/tests/index.html?liveTest=true&realmURL=https%3A%2F%2Flocalhost%3A4201%2Fcatalog%2F&filter=Live%20%7C%20slider
```

The `filter=` value matches against module names (e.g. `Live | slider fields`).

## Naming conventions

QUnit-module prefixes follow Ember's standard `setupXxxTest` → category mapping
so junit reports stay readable across the wider repo:

| Sub-directory        | Ember setup              | Module prefix       | Test type meaning                                  |
| -------------------- | ------------------------ | ------------------- | -------------------------------------------------- |
| `tests/live/fields/` | `setupRenderingTest`     | `Rendering \| …`    | Renders a single field component                   |
| `tests/live/catalog-app/` | `setupApplicationTest` | `Acceptance \| Catalog \| …` | Full user flow against the running app           |

| Item               | Pattern                                    | Example                                   |
| ------------------ | ------------------------------------------ | ----------------------------------------- |
| Field test file    | `<field-kebab>-fields.test.gts`            | `slider-fields.test.gts`                  |
| Field module       | `Rendering \| <field-kebab> fields`        | `Rendering \| qr-code fields`             |
| Field test name    | `<field-kebab> field <action> <details>`   | `qr-code field renders embedded view with data` |
| App module         | `Acceptance \| Catalog \| <feature>`       | `Acceptance \| Catalog \| catalog app - listing create` |

Field-name kebab-casing is mandatory inside module and test names — never use
spaces (`discrete-range`, not `discrete range`).

## Test-coverage strategy (per field)

For each `FieldDef`, focus on **the views that actually matter for a field**.
A field's job is to let users enter data and to display that data inside a
parent card — so:

| View          | Importance for fields | Test policy                                       |
| ------------- | --------------------- | ------------------------------------------------- |
| **embedded**  | 🟢 Core               | **Always** test: happy path + empty state         |
| **edit**      | 🟡 Conditional        | Test **only if** the field defines `static edit`  |
| **atom**      | 🟡 Conditional        | Test **only if** atom has branching/fallback logic worth verifying |
| **fitted**    | 🔴 Rare for fields    | Skip unless the field genuinely defines `static fitted` |

### Why atom is usually skipped

Atoms are the compact inline representation typically shown when a *Card* is
referenced from another card (e.g. via `linksTo`). Plain fields are rarely
referenced this way, so an atom test that only asserts "the atom renders" adds
noise without catching real regressions. We keep an atom test only when the
atom template has its own logic — for example:

- `audio` → `"Untitled Audio"` fallback when title is missing
- `contact-link` → `{{#if @model.url}}` branch (renders nothing without a url)
- `featured-image` → `{{#if @model.imageUrl}}` branch
- `file-content` → `"Untitled"` filename fallback
- `leaflet-map-config` → `"Default map settings"` vs `"Custom tileserver: …"` branch

### Why fields without `static edit` skip the edit test

When a field omits `static edit`, the framework falls back to rendering each
sub-field individually. That fallback isn't the field's own UI, so asserting
on it doesn't test anything the field author wrote. Fields currently in this
category: `file-content`, `leaflet-map-config-field`, `qr-code`.

### Empty-state coverage is non-negotiable

Every field test must exercise the case where the model has no data
(`buildField(F, {})`). This catches the most common production crash:
`Cannot read properties of undefined`. Fields whose templates read
`this.args.model.foo` directly need a defensive `?? {}` in their getters —
the empty-state test surfaces that need.

## Helpers

### `buildField(FieldClass, attrs)`

Returns a value suitable to assign to a `contains(FieldClass)` field on a
synthetic `TestCard`:

- `attrs = {}` → `undefined` (no value at all)
- `attrs = { value: X }` and only one key → `X` (raw value for primitive fields
  backed by `NumberField`, etc. — `SliderField`, `RatingField`, `QuantityField`)
- otherwise → `new FieldClass(attrs)` (composite `FieldDef` instance)

### `renderField(FieldClass, value, format = 'embedded')`

Builds a one-off `TestCard` with `@field sample = contains(FieldClass)`, sets
`sample = value`, and renders the card in the chosen format. The card is
wrapped in `<div data-test-field-container>`, so `[data-test-field-container]`
is **always** present — use it for "did anything render?" assertions, but
prefer field-specific selectors when the test should actually catch
regressions.

### `renderConfiguredField(FieldClass, value, configuration, format)`

Same as `renderField` but also passes `configuration` to the `contains()`
options — used for tests that exercise field-specific config (e.g.
`{ min: 0, max: 100 }` on slider/quantity, `{ maxRating: 10 }` on rating).

## When the realm needs a restart

After adding or moving `.test.gts` files, the realm-server has to re-index
before `_mtimes` returns the new file list. If a newly-added test isn't
showing up in the runner, restart `pnpm start:all` in `packages/realm-server/`.

## CI

`.github/workflows/ci-host.yaml` runs `pnpm test:live` against this realm as
the `live-test` job (`needs: test-web-assets`). The path-filter on that
workflow does **not** include `packages/catalog/contents/**`, so edits in
this directory alone don't trigger CI — they're exercised by any host /
catalog-realm / runtime-common change, and by every push to `main`.
