// S08 — fitted templates must use container queries (the CQ .cq→.fit discipline);
// the parent owns the cell size, so fixed root heights are suspect.
import { staticFormats, styleBlocks } from '../lib/gts-scan.mjs';

const FIX = 'boxel/references/container-query-fitted-layout.md';

export default {
  id: 's08-fitted-cq',
  title: 'Container-query fitted layouts',
  phase: 'static',
  run(ctx) {
    const findings = [];
    for (const def of ctx.kit.defs) {
      if (def.kind !== 'card' || !def.exported) continue;
      const fitted = staticFormats(def.body).fitted;
      if (!fitted) continue; // S07's problem
      const styles = styleBlocks(fitted).join('\n');
      if (!styles.includes('@container')) {
        // warn, not error: trivially-scaling fitted layouts (e.g. a full-bleed
        // image tile) are legitimately CQ-free; the factory adjudicates.
        findings.push({
          rule: 'fitted/no-container-query',
          severity: 'warn',
          file: def.file,
          loc: `class ${def.name} static fitted`,
          message: `${def.name}'s fitted template has no @container queries — fitted cells range from 100px badges to 800px tiles and one fixed layout cannot serve them`,
          suggestion: 'Use the two-element .cq → .fit structure with container-query sub-formats',
          fixRef: FIX,
        });
      }
      const fixedRoot = styles.match(/^\s*(height|width)\s*:\s*\d{2,}px/m);
      if (fixedRoot) {
        findings.push({
          rule: 'fitted/fixed-dimension',
          severity: 'warn',
          file: def.file,
          loc: `class ${def.name} static fitted`,
          message: `Fitted styles set a fixed ${fixedRoot[1]} in px — the parent owns the cell size; fixed dimensions overflow or underfill`,
          fixRef: FIX,
        });
      }
    }
    return findings;
  },
};
