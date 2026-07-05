// D01 — glint typecheck + card-document validation via `npx boxel parse`.
// Dynamic phase only (needs the boxel-cli npm package; CI's fast job skips it).
import { runCli } from '../lib/exec.mjs';

export default {
  id: 'd01-boxel-parse',
  title: 'boxel parse (glint + document validation)',
  phase: 'dynamic',
  async run(ctx) {
    const { code, stdout, stderr } = await runCli(
      ['boxel', '-q', 'parse', '--workspace', ctx.rootDir, '--json'],
      { timeoutMs: 180_000 }
    );
    if (code === 0) return [];
    let diagnostics = [];
    try {
      const parsed = JSON.parse(stdout);
      diagnostics = parsed.diagnostics ?? parsed.messages ?? parsed.errors ?? [];
    } catch {
      return [{
        rule: 'parse/failed',
        severity: 'error',
        file: '.',
        message: `boxel parse exited ${code}: ${(stderr || stdout).slice(0, 400)}`,
      }];
    }
    return diagnostics.map((d) => ({
      rule: 'parse/diagnostic',
      severity: 'error',
      file: d.file ?? d.path ?? '.',
      loc: d.line ? `line ${d.line}` : undefined,
      message: d.message ?? JSON.stringify(d).slice(0, 300),
    }));
  },
};
