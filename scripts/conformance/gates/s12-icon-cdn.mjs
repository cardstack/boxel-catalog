// S12 — every boxel-icons import must exist on the CDN. Phantom icons compile
// clean and 403 at render; a HEAD probe is the only proof. Skipped with --offline.
import { importDecls } from '../lib/gts-scan.mjs';

const CDN = 'https://boxel-icons.boxel.ai/@cardstack/boxel-icons/v1/icons';

export default {
  id: 's12-icon-cdn',
  title: 'boxel-icons resolve on the CDN',
  phase: 'static',
  async run(ctx) {
    const findings = [];
    if (ctx.options.offline) return findings;

    // gather icon name -> [{file, line}]
    const uses = new Map();
    for (const [rel, src] of ctx.gtsSources) {
      for (const imp of importDecls(src)) {
        const m = imp.source.match(/@cardstack\/boxel-icons\/([A-Za-z0-9-]+)$/);
        if (m && m[1] !== 'v1') {
          if (!uses.has(m[1])) uses.set(m[1], []);
          uses.get(m[1]).push({ file: rel, line: imp.line });
        }
      }
    }
    if (uses.size === 0) return findings;

    const checks = [...uses.keys()].map(async (name) => {
      try {
        const res = await fetch(`${CDN}/${name}.js`, {
          method: 'HEAD',
          signal: AbortSignal.timeout(10_000),
        });
        return [name, res.status];
      } catch (e) {
        return [name, `network: ${e.message}`];
      }
    });
    for (const [name, status] of await Promise.all(checks)) {
      if (status === 200) continue;
      for (const use of uses.get(name)) {
        findings.push({
          rule: 'icons/unresolvable',
          severity: typeof status === 'number' ? 'error' : 'warn',
          file: use.file,
          loc: `line ${use.line}`,
          message: `Icon "${name}" returned ${status} from the boxel-icons CDN — it will 403/404 at render time`,
          suggestion: `Pick a verified icon: curl -s -o /dev/null -w "%{http_code}" ${CDN}/<name>.js must print 200`,
          fixRef: 'boxel/references/icons.md',
        });
      }
    }
    return findings;
  },
};
