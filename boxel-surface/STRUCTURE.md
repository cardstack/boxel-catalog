# boxel-surface in catalog/contents

This directory is a **realm-compatible vendor bundle** of `@cardstack/surfaces` and its
sub-packages. The Boxel realm runs in the browser — it cannot resolve npm packages at
runtime, so any package a CardDef needs must be physically present here as servable files.

---

## Directory Structure

```
boxel-surface/
  index.ts                      ← single entry point, re-exports everything
  components/                   ← @cardstack/surfaces foundation (auto-synced)
  modifiers/                    ← @cardstack/surfaces modifiers
  boxel-layout/                 ← @cardstack/boxel-layout
    index.ts
    components/
      layout.gts
  boxel-grid/                   ← @cardstack/boxel-grid (future)
    index.ts
    components/
      ...
  boxel-canvas/                 ← @cardstack/boxel-canvas (future)
    index.ts
    components/
      ...
  boxel-scene/                  ← @cardstack/boxel-scene (future)
    index.ts
    components/
      ...
```

---

## Rules

### 1. Each sub-package gets its own subdirectory
Mirror the original package name: `boxel-layout/`, `boxel-grid/`, `boxel-canvas/`, `boxel-scene/`.
Do not mix sub-package files into `components/` — that folder is foundation only.

### 2. Fix all imports inside sub-package files
Sub-package source files import from `@cardstack/surfaces`. When vendoring, change those
to relative paths pointing at the foundation:

```ts
// original (in the npm package)
import { Layout as FoundationLayout } from '@cardstack/surfaces';

// vendored (inside boxel-layout/components/layout.gts)
import { Layout as FoundationLayout } from '../../components/surface-component.gts';
```

Rule of thumb: from `boxel-<name>/components/*.gts`, foundation is always `../../components/`.

### 3. Each sub-package has its own index.ts
Keep re-exports isolated per sub-package so the main index stays clean:

```ts
// boxel-layout/index.ts
export { default as Layout } from './components/layout.gts';
export type { LayoutPreset, LayoutSignature } from './components/layout.gts';
```

### 4. Main index.ts is the only public API
All imports in CardDef files should come from `'../boxel-surface/index'`.
Never import directly from a sub-package path like `'../boxel-surface/boxel-grid/components/sheet.gts'`.

### 5. Name collisions: sub-package wins
If a sub-package exports a component with the same name as a foundation component
(e.g. both export `Layout`), the sub-package version wins in `index.ts`.
Export the foundation version under an alias like `FoundationLayout` for escape-hatch use.

---

## Adding a New Sub-Package

1. Create the subdirectory: `boxel-<name>/components/`
2. Copy the `.gts` files from `packages/boxel-surfaces/packages/boxel-<name>/src/`
3. Fix all `@cardstack/surfaces` imports → relative paths to `../../components/`
4. Create `boxel-<name>/index.ts` and re-export what users need
5. Add one export line to the bottom of `index.ts`:

```ts
// ─── boxel-grid ───────────────────────────────────────────────────
export { Grid, Sheet, ... } from './boxel-grid/index.ts';
```

---

## Current Status

| Sub-package | Status | Notes |
|---|---|---|
| `@cardstack/surfaces` (foundation) | ✅ Done | `components/` directory |
| `@cardstack/boxel-layout` | ✅ Done | `boxel-layout/` — adds `@preset` to `Layout` |
| `@cardstack/boxel-grid` | 🔜 Future | Heavy TanStack Table dependency — copy selectively |
| `@cardstack/boxel-canvas` | 🔜 Future | Heavy xyflow dependency — copy selectively |
| `@cardstack/boxel-scene` | 🔜 Future | 3D scene container |

---

## Usage in a CardDef

Always import from the single entry point:

```ts
import {
  Environment,
  Layout,        // from boxel-layout (has @preset)
  Pane,
  Form,
  FormField,
  NumberCell,
} from '../boxel-surface/index';
```

```hbs
<Environment @space={{@model}} @posture={{this.posture}}>
  <Layout @preset='page'>
    <Pane>...</Pane>
  </Layout>
</Environment>
```
