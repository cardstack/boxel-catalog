#!/usr/bin/env node
// Harness self-test:
//   1. the broken fixture FAILS with every seeded finding present
//   2. the known-good exemplar (d29736-tier-list) PASSES
//   3. reports are structurally valid per report-schema.json's required keys
// Run: node scripts/conformance/selftest.mjs   (exit 0 = harness healthy)
import { spawnSync } from 'node:child_process';
import { readFileSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const RUN = join(HERE, 'run.mjs');

let failures = 0;
const check = (label, ok, detail = '') => {
  console.log(`  ${ok ? '✓' : '✗'} ${label}${ok || !detail ? '' : ` — ${detail}`}`);
  if (!ok) failures++;
};

function runHarness(dir, out) {
  const res = spawnSync('node', [RUN, dir, '--phase', 'static', '--offline', '--json', out], {
    cwd: REPO,
    encoding: 'utf8',
  });
  let report = null;
  try {
    report = JSON.parse(readFileSync(out, 'utf8'));
  } catch { /* asserted below */ }
  return { code: res.status, report, stderr: res.stderr };
}

function rulesIn(report) {
  return new Set(report.gates.flatMap((g) => g.findings.map((f) => f.rule)));
}

function structurallyValid(report) {
  return (
    report &&
    typeof report.harnessVersion === 'string' &&
    ['static', 'full'].includes(report.phase) &&
    ['pass', 'fail'].includes(report.summary?.result) &&
    Array.isArray(report.gates) &&
    report.gates.every(
      (g) =>
        typeof g.id === 'string' &&
        ['pass', 'warn', 'fail', 'harness-error'].includes(g.status) &&
        Array.isArray(g.findings) &&
        g.findings.every((f) => f.rule && f.severity && f.file && f.message)
    )
  );
}

console.log('\nbroken fixture (must fail with all seeded findings):');
const brokenOut = join(HERE, 'fixtures', '.selftest-broken-report.json');
const broken = runHarness(join(HERE, 'fixtures', 'broken-listing'), brokenOut);
check('exit code 1', broken.code === 1, `got ${broken.code} ${broken.stderr?.slice(0, 200) ?? ''}`);
check('report structurally valid', structurallyValid(broken.report));
if (broken.report) {
  const rules = rulesIn(broken.report);
  for (const expected of [
    'instance/linksToMany-array',      // S03 seed: speakers array shape
    'instance/external-url-in-link',   // S03 seed: unsplash jpg in links.self
    'refs/dev-realm-leftover',         // S05 seed: user-realm URL in venue link
    'date/datefield-shape',            // S06 seed: ISO datetime in a DateField
    'media/data-uri',                  // S04 seed: base64 poster
    'links/bare-kit-internal',         // S09 seed: linksTo(Venue) without thunk
    'slop/default-gradient',           // S14 seed: 667eea/764ba2 gradient
    'slop/templated-sample-data',      // S14 seed: title "Item 1"
    'structure/no-thumbnail',          // S01 seed: null cardThumbnail
    'structure/no-screenshot',         // S01 seed: no images.N
    'structure/missing-spec',          // S01 seed: no Spec/ at all
    'fitted/no-container-query',       // S08 seed: Event fitted without @container
  ]) {
    check(`finds ${expected}`, rules.has(expected));
  }
}

console.log('\nknown-good exemplar d29736-tier-list (must pass):');
const goodOut = join(HERE, 'fixtures', '.selftest-good-report.json');
const good = runHarness(join(REPO, 'd29736-tier-list'), goodOut);
check('exit code 0', good.code === 0, `got ${good.code} ${good.stderr?.slice(0, 200) ?? ''}`);
check('report structurally valid', structurallyValid(good.report));
check('zero errors', good.report?.summary.errors === 0, `got ${good.report?.summary.errors}`);

for (const f of [brokenOut, goodOut]) rmSync(f, { force: true });

console.log(failures === 0 ? '\n✓ selftest passed\n' : `\n✗ selftest: ${failures} failure(s)\n`);
process.exit(failures === 0 ? 0 : 1);
