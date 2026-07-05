// S09 — kit-internal linksTo/linksToMany targets must be thunk-wrapped:
// `linksTo(() => Task)`. The bare form fails at runtime with
// "cardOrThunk was undefined" on module cycles — invisible to lint and TS.
import { fieldDecls } from '../lib/gts-scan.mjs';

export default {
  id: 's09-thunk-links',
  title: 'Thunk-wrapped kit-internal relationships',
  phase: 'static',
  run(ctx) {
    const findings = [];
    const localClasses = new Set(ctx.kit.classIndex.keys());
    for (const [rel, src] of ctx.gtsSources) {
      for (const decl of fieldDecls(src)) {
        if (decl.kind !== 'linksTo' && decl.kind !== 'linksToMany') continue;
        if (decl.thunk || !decl.target) continue;
        if (localClasses.has(decl.target)) {
          findings.push({
            rule: 'links/bare-kit-internal',
            severity: 'error',
            file: rel,
            loc: `line ${decl.line}`,
            message: `@field ${decl.name} = ${decl.kind}(${decl.target}) references a kit-internal class without a thunk — module cycles make this fail at runtime with "cardOrThunk was undefined"`,
            suggestion: `Write ${decl.kind}(() => ${decl.target})`,
          });
        }
      }
    }
    return findings;
  },
};
