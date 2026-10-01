# boxel-catalog

Content for the Boxel catalog workspace, synced to staging and production realms via GitHub Actions.

## How a change reaches each environment

- **Staging** syncs `main` on every merge (`sync-to-workspace.yml`). Staging runs boxel `main`.
- **Production** gets the catalog only from the **Deploy catalog to production** workflow (`deploy-production.yml`):
  - **In lockstep with boxel.** Boxel's production deploy (Manual Deploy [boxel]) finishes by deploying the catalog revision it pins in `packages/catalog/test-subset.json`. It does nothing when production's catalog is already at or past that revision.
  - **Ahead of boxel.** Run it by hand from the Actions tab to deploy `main`, for changes that need nothing new from boxel.

Before it changes anything, the deploy checks each pull request merged since production's last catalog deploy. When one says `Merges after: cardstack/boxel#N` and production doesn't run #N yet, the deploy refuses and names both pull requests. Declare that line on any change that needs boxel code. The `catalog-deploy` skill (`.claude/skills/catalog-deploy/SKILL.md`) has the details.
