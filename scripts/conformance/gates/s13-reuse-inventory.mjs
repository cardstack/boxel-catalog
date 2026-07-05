// S13 — reuse inventory: hand-rolled UI that duplicates boxel-ui components,
// FieldDefs that duplicate base fields, and near-duplicate catalog fields/listings.
// ALL findings are warnings — the factory's conform step requires each to be
// fixed or waived with a reason. The report also carries an inventory block so
// reuse trends are measurable across cards.
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { reuseRules } from '../rules/reuse-rules.mjs';
import { staticFormats, templateBlocks, styleBlocks, importDecls } from '../lib/gts-scan.mjs';

function loadJson(url) {
  return JSON.parse(readFileSync(new URL(url, import.meta.url), 'utf8'));
}

export default {
  id: 's13-reuse-inventory',
  title: 'Component / field / listing reuse',
  phase: 'static',
  run(ctx) {
    const findings = [];
    const baseFields = loadJson('../rules/base-field-manifest.json').fields;
    const uiManifest = loadJson('../rules/boxel-ui-manifest.json');

    // ---- hand-rolled UI detectors, per definition per format
    for (const def of ctx.kit.defs) {
      const formats = staticFormats(def.body);
      for (const [format, span] of Object.entries(formats)) {
        const template = templateBlocks(span).join('\n');
        const styles = styleBlocks(span).join('\n');
        if (!template && !styles) continue;
        for (const rule of reuseRules) {
          if (rule.formats && !rule.formats.includes(format)) continue;
          if (rule.detect({ template, styles })) {
            findings.push({
              rule: rule.id,
              severity: 'warn',
              file: def.file,
              loc: `class ${def.name} static ${format}`,
              message: rule.message,
              suggestion: rule.suggestion,
              fixRef: 'boxel-ui-guidelines',
            });
          }
        }
      }
    }

    // ---- duplicate-base-field: local FieldDef re-implementing a base field
    for (const def of ctx.kit.defs) {
      if (def.kind !== 'field') continue;
      const hit = baseFields.find((f) => new RegExp(f.namePattern, 'i').test(def.name));
      if (hit && def.name !== hit.name) {
        findings.push({
          rule: 'reuse/duplicate-base-field',
          severity: 'warn',
          file: def.file,
          loc: `class ${def.name} (line ${def.line})`,
          message: `FieldDef ${def.name} looks like a re-implementation of the base ${hit.name}`,
          suggestion: `Import the default export of ${hit.module} instead (or waive if genuinely different semantics)`,
          fixRef: 'boxel/references/base-field-catalog.md',
        });
      }
    }

    // ---- duplicate-catalog-field: matched against the repo's shared fields/ inventory
    const repoRoot = ctx.repoRoot;
    const fieldsDir = join(repoRoot, 'fields');
    if (existsSync(fieldsDir)) {
      const catalogFields = readdirSync(fieldsDir, { withFileTypes: true })
        .filter((d) => d.isDirectory())
        .map((d) => d.name); // e.g. "rating"
      for (const def of ctx.kit.defs) {
        if (def.kind !== 'field') continue;
        const stem = def.name.replace(/Field$/, '').toLowerCase();
        const hit = catalogFields.find((f) => f.replace(/-/g, '') === stem);
        // skip when the def under scan IS that catalog field package
        if (hit && !ctx.listingDirName.includes(hit)) {
          findings.push({
            rule: 'reuse/duplicate-catalog-field',
            severity: 'warn',
            file: def.file,
            loc: `class ${def.name} (line ${def.line})`,
            message: `FieldDef ${def.name} duplicates the existing catalog field package fields/${hit}`,
            suggestion: `Depend on fields/${hit} instead of re-implementing it`,
          });
        }
      }
    }

    // ---- duplicate-catalog-card: fuzzy listing-title match (info only)
    const myName = ctx.listing?.doc?.data?.attributes?.name;
    if (myName && existsSync(repoRoot)) {
      const mine = norm(myName);
      for (const dirent of readdirSync(repoRoot, { withFileTypes: true })) {
        if (!dirent.isDirectory() || dirent.name === ctx.listingDirName) continue;
        for (const sub of ['CardListing', 'AppListing', 'FieldListing', 'SkillListing', 'ThemeListing', 'ComponentListing']) {
          const dir = join(repoRoot, dirent.name, sub);
          if (!existsSync(dir)) continue;
          for (const f of readdirSync(dir)) {
            try {
              const name = JSON.parse(readFileSync(join(dir, f), 'utf8'))?.data?.attributes?.name;
              if (name && similar(mine, norm(name))) {
                findings.push({
                  rule: 'reuse/duplicate-catalog-card',
                  severity: 'info',
                  file: ctx.listing.path,
                  message: `A similar listing already exists: ${dirent.name} ("${name}")`,
                  suggestion: 'Confirm this listing is differentiated, or extend the existing one',
                });
              }
            } catch { /* unparseable sibling — not this gate's problem */ }
          }
        }
      }
    }

    // ---- inventory block (attached to the gate result by run.mjs via findings meta)
    const uiImports = new Set();
    for (const src of ctx.gtsSources.values()) {
      for (const imp of importDecls(src)) {
        if (imp.source.startsWith(uiManifest.importPath)) {
          for (const name of imp.clause.replace(/[{}]/g, '').split(',')) {
            const n = name.trim().split(/\s+as\s+/)[0];
            if (n) uiImports.add(n);
          }
        }
      }
    }
    ctx.inventory = {
      boxelUiComponentsUsed: [...uiImports].sort(),
      handRolledFindings: findings.filter((f) => f.rule.startsWith('reuse/hand-rolled')).length,
    };

    return findings;
  },
};

function norm(s) {
  return s.toLowerCase().replace(/[^a-z0-9]/g, '');
}
// crude similarity: containment or Levenshtein <= 2 on normalized names
function similar(a, b) {
  if (a === b) return true;
  if (a.length > 5 && b.length > 5 && (a.includes(b) || b.includes(a))) return true;
  if (Math.abs(a.length - b.length) > 2) return false;
  return levenshtein(a, b) <= 2;
}
function levenshtein(a, b) {
  const dp = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 0; j <= b.length; j++) dp[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)
      );
    }
  }
  return dp[a.length][b.length];
}
