// S02 — every .json parses and has JSON:API card document shape.
import { isInstancePath } from '../lib/json-walk.mjs';

export default {
  id: 's02-json-validity',
  title: 'JSON parse + card document shape',
  phase: 'static',
  run(ctx) {
    const findings = [];
    for (const [rel, entry] of ctx.jsonDocs) {
      if (!isInstancePath(rel)) continue;
      if (entry.error) {
        findings.push({
          rule: 'json/unparseable',
          severity: 'error',
          file: rel,
          message: `Invalid JSON: ${entry.error}`,
        });
        continue;
      }
      const d = entry.doc?.data;
      if (!d || typeof d !== 'object') {
        findings.push({
          rule: 'json/no-data',
          severity: 'error',
          file: rel,
          message: 'Document has no data member — not a JSON:API card document',
        });
        continue;
      }
      if (d.type !== 'card') {
        findings.push({
          rule: 'json/wrong-type',
          severity: 'error',
          file: rel,
          loc: 'data.type',
          message: `data.type is ${JSON.stringify(d.type)} — must be "card"`,
        });
      }
      const adopts = d.meta?.adoptsFrom;
      if (!adopts || typeof adopts.module !== 'string' || typeof adopts.name !== 'string') {
        findings.push({
          rule: 'json/no-adopts-from',
          severity: 'error',
          file: rel,
          loc: 'data.meta.adoptsFrom',
          message: 'meta.adoptsFrom must have string module and name — the host cannot load this instance',
        });
      }
    }
    return findings;
  },
};
