// D03 — Gate A: the realm server actually evaluates each definition module.
// `cardOrThunk was undefined` here means a bad import or unresolved cycle that
// lint and typecheck cannot see.
import { runCli } from '../lib/exec.mjs';

export default {
  id: 'd03-module-load',
  title: 'Module-load probe (Gate A)',
  phase: 'dynamic',
  async run(ctx) {
    if (!ctx.options.realm) {
      return [{ rule: 'gate-a/no-realm', severity: 'warn', file: '.', message: 'D03 skipped: no --realm provided' }];
    }
    const realm = ctx.options.realm.endsWith('/') ? ctx.options.realm : `${ctx.options.realm}/`;
    const findings = [];
    for (const def of ctx.kit.defs) {
      if (!def.exported || def.kind !== 'card') continue;
      const moduleUrl = `${realm}${def.file.replace(/\.(gts|gjs)$/, '')}`;
      const input = JSON.stringify({ codeRef: { module: moduleUrl, name: def.name } });
      const { code, stdout, stderr } = await runCli(
        [
          'boxel', '-q', 'run-command',
          '@cardstack/boxel-host/commands/get-card-type-schema/default',
          '--realm', realm, '--input', input, '--json',
        ],
        { timeoutMs: 60_000 }
      );
      const out = stdout + stderr;
      if (code !== 0 || !/"status"\s*:\s*"ready"|schema/i.test(out)) {
        findings.push({
          rule: 'gate-a/module-load-failed',
          severity: 'error',
          file: def.file,
          loc: `class ${def.name}`,
          message: `Module-load probe failed for ${def.name}: ${out.slice(0, 300)}`,
          suggestion: '"cardOrThunk was undefined" → bad import (named vs default) or missing thunk on a cyclic relationship',
          fixRef: 'boxel/references/common-imports.md',
        });
      }
    }
    return findings;
  },
};
