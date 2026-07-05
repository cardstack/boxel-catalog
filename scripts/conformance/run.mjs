#!/usr/bin/env node
// Catalog listing conformance harness.
//
//   node scripts/conformance/run.mjs <listing-dir> [--phase static|full]
//     [--realm <url>] [--json <out.json>] [--waivers <file.yaml>] [--offline]
//
// Exit codes: 0 = pass (warnings allowed), 1 = errors found, 2 = harness fault.
//
// Static phase is stdlib-only and runs identically in CI (conformance.yaml)
// and locally. Full phase adds the dynamic gates (boxel-cli + realm endpoints)
// and is the factory's pre-PR gate.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadListingDir } from './lib/json-walk.mjs';
import { indexKit } from './lib/gts-scan.mjs';
import { parseWaivers, applyWaivers, buildReport, printHuman } from './lib/report.mjs';

const HARNESS_VERSION = '1.0.0';
const HERE = dirname(fileURLToPath(import.meta.url));

const STATIC_GATES = [
  's01-structure', 's02-json-validity', 's03-instance-shape', 's04-no-inline-media',
  's05-relative-refs', 's06-date-shape', 's07-formats-present', 's08-fitted-cq',
  's09-thunk-links', 's10-theme-vars', 's11-cardinfo', 's12-icon-cdn',
  's13-reuse-inventory', 's14-slop-signals',
];
const DYNAMIC_GATES = [
  'd01-boxel-parse', 'd02-boxel-lint', 'd03-module-load', 'd04-typed-search', 'd05-prerender',
];

function parseArgs(argv) {
  const args = { phase: 'static', offline: false, positional: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--phase') args.phase = argv[++i];
    else if (a === '--realm') args.realm = argv[++i];
    else if (a === '--json') args.json = argv[++i];
    else if (a === '--waivers') args.waivers = argv[++i];
    else if (a === '--offline') args.offline = true;
    else if (a === '--help' || a === '-h') args.help = true;
    else args.positional.push(a);
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || args.positional.length !== 1) {
    console.log('Usage: node scripts/conformance/run.mjs <listing-dir> [--phase static|full] [--realm <url>] [--json <out.json>] [--waivers <file.yaml>] [--offline]');
    process.exit(args.help ? 0 : 2);
  }
  if (!['static', 'full'].includes(args.phase)) {
    console.error(`Unknown phase: ${args.phase}`);
    process.exit(2);
  }
  const rootDir = resolve(args.positional[0]);
  if (!existsSync(rootDir)) {
    console.error(`No such directory: ${rootDir}`);
    process.exit(2);
  }

  // ---- build shared context
  const ctx = loadListingDir(rootDir);
  ctx.kit = indexKit(ctx.gtsSources);
  ctx.options = { realm: args.realm, offline: args.offline };
  ctx.listingDirName = basename(rootDir);
  ctx.repoRoot = resolve(HERE, '..', '..');
  const listingPath = ctx.files.find((f) => /(^|\/)[A-Za-z]+Listing\/[^/]+\.json$/.test(f));
  ctx.listing = listingPath ? { path: listingPath, doc: ctx.jsonDocs.get(listingPath)?.doc } : null;

  // ---- waivers (explicit path, or the dir's own .conformance-waivers.yaml)
  let waivers = [];
  const waiverPath = args.waivers ?? join(rootDir, '.conformance-waivers.yaml');
  if (existsSync(waiverPath)) {
    waivers = parseWaivers(readFileSync(waiverPath, 'utf8'));
  }

  // ---- run gates
  const gateIds = args.phase === 'full' ? [...STATIC_GATES, ...DYNAMIC_GATES] : STATIC_GATES;
  const gateResults = [];
  for (const id of gateIds) {
    const started = Date.now();
    let findings = [];
    let error;
    try {
      const mod = (await import(`./gates/${id}.mjs`)).default;
      findings = (await mod.run(ctx)) ?? [];
    } catch (e) {
      error = `${e.message}\n${(e.stack ?? '').split('\n')[1] ?? ''}`.trim();
    }
    applyWaivers(findings, waivers);
    gateResults.push({
      id,
      title: titleOf(id),
      findings,
      error,
      durationMs: Date.now() - started,
    });
  }

  const report = buildReport({
    listingDir: ctx.listingDirName,
    phase: args.phase,
    gateResults,
    harnessVersion: HARNESS_VERSION,
  });
  if (ctx.inventory) report.inventory = ctx.inventory;

  printHuman(report);
  const jsonPath = args.json ?? join(rootDir, '.conformance-report.json');
  writeFileSync(jsonPath, JSON.stringify(report, null, 2));
  console.log(`  report: ${jsonPath}`);

  if (gateResults.some((g) => g.error)) process.exit(2);
  process.exit(report.summary.result === 'pass' ? 0 : 1);
}

const TITLES = {
  's01-structure': 'Listing directory anatomy',
  's02-json-validity': 'JSON parse + card document shape',
  's03-instance-shape': 'Relationship shapes (realm-bricking classes)',
  's04-no-inline-media': 'No inline media / base64 in JSON attributes',
  's05-relative-refs': 'Reference hygiene',
  's06-date-shape': 'DateField / DateTimeField value shapes',
  's07-formats-present': 'Required formats per definition',
  's08-fitted-cq': 'Container-query fitted layouts',
  's09-thunk-links': 'Thunk-wrapped kit-internal relationships',
  's10-theme-vars': 'Theme tokens over color literals',
  's11-cardinfo': 'cardInfo present on instances',
  's12-icon-cdn': 'boxel-icons resolve on the CDN',
  's13-reuse-inventory': 'Component / field / listing reuse',
  's14-slop-signals': 'AI-slop tells',
  'd01-boxel-parse': 'boxel parse (glint + document validation)',
  'd02-boxel-lint': 'Realm lint (/_lint endpoint)',
  'd03-module-load': 'Module-load probe (Gate A)',
  'd04-typed-search': 'Typed-search counts (Gate B)',
  'd05-prerender': 'Prerender formats render clean',
};
function titleOf(id) {
  return TITLES[id] ?? id;
}

main().catch((e) => {
  console.error(`harness fault: ${e.stack ?? e}`);
  process.exit(2);
});
