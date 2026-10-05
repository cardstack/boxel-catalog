---
name: catalog-deploy
description: How a change in this repository reaches staging and production, and how to deploy it to production — staging syncs catalog main on every merge; production gets the catalog only from the "Deploy to production" workflow, run by hand (from Discord's `/deploy app:catalog` or the Actions tab) to ship catalog work ahead of boxel, or by boxel's production deploy with the catalog revision that boxel pins. Covers the check that runs before any change (a catalog pull request saying `Merges after: cardstack/boxel#N` holds the deploy until production runs #N), reading its refusal, and declaring a boxel dependency so the check can see it. Use when asked to deploy, release or ship the catalog, when a merged change isn't in production, when "Deploy to production" fails, or before merging a change that needs boxel code production doesn't run yet.
---

# Deploying the catalog

- **Staging** syncs catalog `main` on every merge (**Deploy to staging**, `.github/workflows/sync-to-workspace.yml`). Staging runs boxel `main`. To re-run a sync that failed or flaked, use `/deploy app:catalog environment:staging` in Discord.
- **Production** gets the catalog only from **Deploy to production** (`.github/workflows/deploy-production.yml`):
  - **In lockstep with boxel.** Manual Deploy [boxel] to production runs it with the catalog revision the deployed boxel pins, once before its release and once after. The run before ships what the new boxel needs; the run after ships the rest. It never moves production's catalog backwards.
  - **Ahead of boxel, by hand.** For changes that need nothing new from boxel, run `/deploy app:catalog environment:production` in Discord, which deploys `main`'s head. Add `revision:<sha>` to deploy a specific `main` commit. You can also run it from the Actions tab, with `revision` empty for `main`'s head. In Discord, the bot links the run, and when the run fails it posts the deploy's errors, including a refusal's pull requests.

Before it changes anything, the deploy checks every pull request merged since production's last catalog deploy that changes a deployed file. Dot paths, `README.md`, `AGENTS.md`, `scripts`, `tests` and the rest of `.boxelignore` aren't deployed. If one says `Merges after: cardstack/boxel#N` and production doesn't run #N yet, the deploy **refuses** and names both pull requests:

- "which production doesn't run yet": run Manual Deploy [boxel] to production. It deploys the catalog when it finishes.
- "which hasn't merged yet": merge the boxel pull request, then deploy boxel to production.

Pull requests closed without merging don't count, and a boxel pull request merged into a branch other than `main` holds until it reaches `main`. A `Merges after:` line naming a closed boxel pull request holds nothing back, and the deploy only warns about it.

## Declare what you need from boxel

The check sees a dependency only through a `Merges after: cardstack/boxel#N` line in the pull request's description. Prose doesn't count. Add the line whenever the change needs boxel code production may not run yet, even if boxel's Lint Catalog passes without it: a runtime dependency, such as a declaration option only new platform code accepts, lints clean.

The full guide is boxel's `catalog-deploy` skill (`.claude/skills/catalog-deploy/SKILL.md` in cardstack/boxel). It covers finding what production runs, running the check locally, and the lockstep job. Pairing syntax and merge order are in boxel's `catalog-pairing` skill.
