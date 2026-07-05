// D02 — realm-server lint (eslint + prettier with @cardstack/boxel rules) via
// `npx boxel lint`. Requires --realm: the card modules must already be pushed.
import { runCli } from '../lib/exec.mjs';

export default {
  id: 'd02-boxel-lint',
  title: 'Realm lint (/_lint endpoint)',
  phase: 'dynamic',
  async run(ctx) {
    if (!ctx.options.realm) {
      return [{
        rule: 'lint/no-realm',
        severity: 'warn',
        file: '.',
        message: 'D02 skipped: no --realm provided (realm lint runs against pushed modules)',
      }];
    }
    const { code, stdout, stderr } = await runCli(
      ['boxel', '-q', 'lint', '--realm', ctx.options.realm, '--json'],
      { timeoutMs: 180_000 }
    );
    let files = [];
    try {
      const parsed = JSON.parse(stdout);
      files = Array.isArray(parsed) ? parsed : parsed.files ?? parsed.results ?? [];
    } catch {
      if (code !== 0) {
        return [{
          rule: 'lint/failed',
          severity: 'error',
          file: '.',
          message: `boxel lint exited ${code}: ${(stderr || stdout).slice(0, 400)}`,
        }];
      }
      return [];
    }
    const findings = [];
    for (const f of files) {
      for (const m of f.messages ?? []) {
        findings.push({
          rule: `lint/${m.ruleId ?? 'message'}`,
          severity: m.severity === 2 || m.severity === 'error' ? 'error' : 'warn',
          file: f.filePath ?? f.path ?? '.',
          loc: m.line ? `line ${m.line}` : undefined,
          message: m.message,
        });
      }
    }
    return findings;
  },
};
