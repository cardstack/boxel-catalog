// S11 — instances should carry attributes.cardInfo (even all-null) so users can
// rename/summarize/theme them through the UI later.
import { instances, attributesOf } from '../lib/json-walk.mjs';

export default {
  id: 's11-cardinfo',
  title: 'cardInfo present on instances',
  phase: 'static',
  run(ctx) {
    const findings = [];
    for (const [rel, doc] of instances(ctx)) {
      const attrs = attributesOf(doc);
      if (!('cardInfo' in attrs) || typeof attrs.cardInfo !== 'object' || attrs.cardInfo === null) {
        findings.push({
          rule: 'instance/no-cardinfo',
          severity: 'warn',
          file: rel,
          loc: 'data.attributes',
          message: 'Instance has no attributes.cardInfo object — users cannot edit name/summary/theme through the UI',
          suggestion: 'Add "cardInfo": { "name": null, "notes": null, "summary": null, "cardThumbnailURL": null }',
        });
      }
    }
    return findings;
  },
};
