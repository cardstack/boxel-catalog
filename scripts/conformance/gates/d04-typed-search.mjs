// D04 — Gate B: typed-search count in the realm equals the on-disk instance
// count per CardDef. `boxel search` is the truth source — lint passing while
// the index is empty has happened repeatedly.
import { runCli } from '../lib/exec.mjs';

export default {
  id: 'd04-typed-search',
  title: 'Typed-search counts (Gate B)',
  phase: 'dynamic',
  async run(ctx) {
    if (!ctx.options.realm) {
      return [{ rule: 'gate-b/no-realm', severity: 'warn', file: '.', message: 'D04 skipped: no --realm provided' }];
    }
    const realm = ctx.options.realm.endsWith('/') ? ctx.options.realm : `${ctx.options.realm}/`;
    const findings = [];
    for (const def of ctx.kit.defs) {
      if (!def.exported || def.kind !== 'card') continue;
      // instances adopting this def: <DefName>/*.json convention
      const expected = ctx.files.filter((f) => new RegExp(`(^|/)${def.name}/[^/]+\\.json$`).test(f)).length;
      if (expected === 0) continue;
      const moduleUrl = `${realm}${def.file.replace(/\.(gts|gjs)$/, '')}`;
      const query = JSON.stringify({ filter: { type: { module: moduleUrl, name: def.name } } });
      const { stdout } = await runCli(
        ['boxel', '-q', 'search', '--realm', realm, '--query', query, '--json'],
        { timeoutMs: 60_000 }
      );
      let count = null;
      try {
        const parsed = JSON.parse(stdout);
        count = Array.isArray(parsed) ? parsed.length : (parsed.results?.length ?? parsed.data?.length ?? null);
      } catch { /* fall through */ }
      if (count === null || count < expected) {
        findings.push({
          rule: 'gate-b/count-mismatch',
          severity: 'error',
          file: def.file,
          loc: `class ${def.name}`,
          message: `Typed search found ${count ?? 'unparseable'} indexed ${def.name} instance(s), expected ${expected} — instances exist on disk but are not indexed`,
          suggestion: 'Check for a bricking instance (S03 classes) or an indexing job that was silently dropped; re-push per-file',
          fixRef: 'boxel-environment/references/indexing-operations.md',
        });
      }
    }
    return findings;
  },
};
