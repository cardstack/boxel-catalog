import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import { previewPaths, unitOf } from './preview-paths.mjs';

const FILES = {
  'cards/shop/cart.gts':
    "import { Line } from './line';\nimport { money } from '../../components/money';",
  'cards/shop/line.gts':
    "const skill = new URL('../../Skill/pricing', import.meta.url);",
  'cards/shop/Cart/one.json':
    '{"meta":{"adoptsFrom":{"module":"../cart","name":"Cart"}}}',
  'cards/other/thing.gts': '',
  'components/money.gts': "import { round } from '../utils/round';",
  'utils/round.js': '',
  'Skill/pricing.json': '{}',
  'Spec/cart.json':
    '{"data":{"relationships":{"linkedExamples.0":{"links":{"self":"../cards/shop/Cart/one"}}}}}',
  'Spec/other.json': '{}',
  'tests/cart.test.gts': '',
  'README.md': '',
};

function inFixture(fn) {
  let root = mkdtempSync(join(tmpdir(), 'preview-paths-'));
  for (let [path, body] of Object.entries(FILES)) {
    mkdirSync(join(root, dirname(path)), { recursive: true });
    writeFileSync(join(root, path), body);
  }
  let cwd = process.cwd();
  process.chdir(root);
  try {
    return fn();
  } finally {
    process.chdir(cwd);
  }
}

test('a cluster is pushed whole, with what it reaches by import, URL and .js', () => {
  assert.deepEqual(
    inFixture(() => previewPaths(['cards/shop/cart.gts'])),
    [
      'Skill/pricing.json',
      'cards/shop/Cart/one.json',
      'cards/shop/cart.gts',
      'cards/shop/line.gts',
      'components/money.gts',
      'utils/round.js',
    ],
  );
});

test("a type folder's file goes alone, with what its JSON references reach", () => {
  let paths = inFixture(() => previewPaths(['Spec/cart.json']));
  assert.ok(paths.includes('Spec/cart.json'));
  assert.ok(paths.includes('cards/shop/Cart/one.json'));
  assert.ok(paths.includes('cards/shop/cart.gts'));
  assert.ok(!paths.includes('Spec/other.json'));
  assert.ok(!paths.includes('cards/other/thing.gts'));
});

test('skipped and deleted files give no preview', () => {
  assert.deepEqual(
    inFixture(() =>
      previewPaths([
        'tests/cart.test.gts',
        'README.md',
        '.github/workflows/x.yml',
        'cards/gone/deleted.gts',
      ]),
    ),
    [],
  );
});

test('units', () => {
  assert.equal(unitOf('cards/shop/deep/x.gts'), 'cards/shop');
  assert.equal(unitOf('Spec/a.json'), 'Spec/a.json');
  assert.equal(unitOf('catalog-app/x/y.gts'), 'catalog-app');
  assert.equal(unitOf('realm.json'), null);
  assert.equal(unitOf('scripts/a.mjs'), null);
});
