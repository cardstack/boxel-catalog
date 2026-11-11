import { module, test } from 'qunit';

import { registerOrder } from './register-order';

function doc(id: string, hashedAt: string | null, supersedes?: any) {
  return { id, hashedAt, supersedes };
}

export function runTests() {
  module('Unit | audit register order', function () {
    test('a chain sits together, newest version first', function (assert) {
      let v1 = doc('v1', null);
      let v2 = doc('v2', '2026-08-20', v1);
      let q3 = doc('q3', '2026-09-30');
      let soc = doc('soc', null);
      let order = registerOrder([v1, soc, q3, v2]).map((d) => d.id);
      assert.deepEqual(order, ['q3', 'v2', 'v1', 'soc']);
    });

    test('two documents superseding the same one list it once', function (assert) {
      let v1 = doc('v1', null);
      let v2a = doc('v2a', '2026-08-20', v1);
      let v2b = doc('v2b', '2026-08-25', v1);
      let order = registerOrder([v1, v2a, v2b]).map((d) => d.id);
      assert.deepEqual(order, ['v2b', 'v2a', 'v1']);
    });

    test('a supersedes cycle keeps every document', function (assert) {
      let a: any = doc('a', '2026-01-01');
      let b: any = doc('b', '2026-02-01', a);
      a.supersedes = b;
      assert.strictEqual(registerOrder([a, b]).length, 2);
    });
  });
}
