// S10 — theme-token discipline: scoped styles should use var(--*) tokens, not
// color literals. Warning severity (adjudicate: fix or waive) — data-driven
// colors in attributes are NOT flagged; only CSS inside <style scoped> blocks.
import { styleBlocks } from '../lib/gts-scan.mjs';

const COLOR_LITERAL = /#[0-9a-fA-F]{3,8}\b|(?<![-\w])(rgb|rgba|hsl|hsla|oklch)\(/g;
const FIX = 'boxel/references/theme-design-system.md';

export default {
  id: 's10-theme-vars',
  title: 'Theme tokens over color literals',
  phase: 'static',
  run(ctx) {
    const findings = [];
    for (const [rel, src] of ctx.gtsSources) {
      // Theme cards define palettes — they are the one legitimate home for literals.
      if (/theme/i.test(rel)) continue;
      const styles = styleBlocks(src).join('\n');
      const lines = styles.split('\n');
      const hits = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (!COLOR_LITERAL.test(line)) {
          COLOR_LITERAL.lastIndex = 0;
          continue;
        }
        COLOR_LITERAL.lastIndex = 0;
        // allow literals inside var() fallbacks: var(--accent, #f00)
        const stripped = line.replace(/var\([^)]*\)/g, '');
        if (COLOR_LITERAL.test(stripped)) hits.push(stripped.trim().slice(0, 60));
        COLOR_LITERAL.lastIndex = 0;
      }
      if (hits.length) {
        findings.push({
          rule: 'theme/color-literal',
          severity: 'warn',
          file: rel,
          message: `${hits.length} color literal(s) in scoped styles (e.g. \`${hits[0]}\`) — templates should reference var(--*) theme tokens so instance themes can restyle the card`,
          suggestion: 'Move colors into the Theme card cssVariables and reference tokens; waive deliberate fixed-brand colors with a reason',
          fixRef: FIX,
        });
      }
    }
    return findings;
  },
};
