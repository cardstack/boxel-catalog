// S14 — deterministic AI-slop tells. Warnings only; the design jury (D06, run
// by the factory's conform command) is the judgment layer — this gate catches
// what regex can catch. Every finding must be fixed or waived with a reason.
import { instances, attributesOf, walkStrings } from '../lib/json-walk.mjs';
import { styleBlocks, templateBlocks } from '../lib/gts-scan.mjs';

const FIX = 'catalog-card-factory/references/taste-rubric.md';

// the canonical "AI gradient" purple/indigo family
const SLOP_HEXES = /#(667eea|764ba2|8b5cf6|a855f7|7c3aed|6366f1|4f46e5|9333ea|7e22ce)\b/i;
// NOTE: bare "placeholder" is NOT matched — placeholder= is a legitimate HTML
// attribute; only placeholder-as-content counts (see TEMPLATED_SAMPLE).
const PLACEHOLDER_COPY = /\b(lorem ipsum|john doe|jane doe|my awesome|acme corp|description (goes )?here|insert \w+ here|your \w+ here)\b/i;
const TEMPLATED_SAMPLE = /^(placeholder|(item|card|entry|thing|test|sample|example)\s*#?\d+)$/i;
const EMOJI = /\p{Extended_Pictographic}/gu;
const GENERIC_FONT_STACK = /font-family\s*:\s*['"]?(inter|roboto|arial|helvetica)\b(?![^;]*var\()/i;

export default {
  id: 's14-slop-signals',
  title: 'AI-slop tells',
  phase: 'static',
  run(ctx) {
    const findings = [];

    for (const [rel, src] of ctx.gtsSources) {
      const styles = styleBlocks(src).join('\n');
      const templates = templateBlocks(src).join('\n');

      if (/linear-gradient/i.test(styles) && SLOP_HEXES.test(styles)) {
        findings.push({
          rule: 'slop/default-gradient',
          severity: 'warn',
          file: rel,
          message: 'The default purple/indigo AI gradient — the single most recognizable slop tell',
          suggestion: 'Derive colors from the brief\'s aesthetic anchor instead',
          fixRef: FIX,
        });
      }
      const emoji = templates.match(EMOJI) ?? [];
      if (new Set(emoji).size >= 5) {
        findings.push({
          rule: 'slop/emoji-as-icons',
          severity: 'warn',
          file: rel,
          message: `${new Set(emoji).size} distinct emoji in templates — emoji-as-iconography reads as unfinished`,
          suggestion: 'Use @cardstack/boxel-icons (CDN-verified) or in-world typographic marks',
          fixRef: FIX,
        });
      }
      if (PLACEHOLDER_COPY.test(templates)) {
        findings.push({
          rule: 'slop/placeholder-copy',
          severity: 'warn',
          file: rel,
          message: `Placeholder copy in template (${templates.match(PLACEHOLDER_COPY)[0]})`,
          suggestion: 'Every string a user sees should be in-world for the brief',
          fixRef: FIX,
        });
      }
      if (GENERIC_FONT_STACK.test(styles)) {
        findings.push({
          rule: 'slop/generic-font-stack',
          severity: 'warn',
          file: rel,
          message: `Hard-coded generic font stack (${styles.match(GENERIC_FONT_STACK)[0].slice(0, 40)}) — typography should come from the theme`,
          suggestion: 'Use var(--font-family, …) tokens; pick display faces from the brief vocabulary',
          fixRef: FIX,
        });
      }
    }

    // sample-data blandness in instances
    for (const [rel, doc] of instances(ctx)) {
      if (/(^|\/)(Spec|[A-Za-z]+Listing)\//.test(rel)) continue;
      walkStrings(attributesOf(doc), (path, str) => {
        if (TEMPLATED_SAMPLE.test(str.trim())) {
          findings.push({
            rule: 'slop/templated-sample-data',
            severity: 'warn',
            file: rel,
            loc: path,
            message: `Templated sample value ${JSON.stringify(str)} — example instances must be in-world for the brief (real names, real register)`,
            fixRef: FIX,
          });
        } else if (PLACEHOLDER_COPY.test(str)) {
          findings.push({
            rule: 'slop/placeholder-copy',
            severity: 'warn',
            file: rel,
            loc: path,
            message: `Placeholder copy in sample data (${str.match(PLACEHOLDER_COPY)[0]})`,
            fixRef: FIX,
          });
        }
      });
    }

    return findings;
  },
};
