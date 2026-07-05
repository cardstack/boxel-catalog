// S06 — DateField vs DateTimeField schema↔instance contract. Ported from
// instance-correctness-scan.py rule 3. A mismatch passes lint, writes, indexes —
// then crashes at render with RangeError: Invalid time value.
import { instances, attributesOf, resolveRelative } from '../lib/json-walk.mjs';
import { dateFieldMap } from '../lib/gts-scan.mjs';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const DATETIME_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?(\.\d{1,3})?(Z|[+-]\d{2}:?\d{2})?$/;
const FIX = 'boxel/references/base-field-catalog.md';

export default {
  id: 's06-date-shape',
  title: 'DateField / DateTimeField value shapes',
  phase: 'static',
  run(ctx) {
    // field-type maps per module rel path (without extension)
    const maps = new Map();
    for (const [rel, src] of ctx.gtsSources) {
      maps.set(rel.replace(/\.(gts|gjs)$/, ''), dateFieldMap(src));
    }

    const findings = [];
    for (const [rel, doc] of instances(ctx)) {
      const mod = doc?.data?.meta?.adoptsFrom?.module;
      if (typeof mod !== 'string' || !mod.startsWith('.')) continue;
      const resolved = resolveRelative(rel, mod);
      const fieldMap = maps.get(resolved);
      if (!fieldMap) continue;
      const attrs = attributesOf(doc);
      for (const [fname, ftype] of Object.entries(fieldMap)) {
        const v = attrs[fname];
        if (typeof v !== 'string' || v === '') continue;
        if (ftype === 'DateField' && !DATE_RE.test(v)) {
          findings.push({
            rule: 'date/datefield-shape',
            severity: 'error',
            file: rel,
            loc: `data.attributes.${fname}`,
            message: `${fname}=${JSON.stringify(v)} but the schema declares contains(DateField) — value must be YYYY-MM-DD with no T`,
            suggestion: 'Either reformat the value or switch the field to DateTimeField if time-of-day matters',
            fixRef: FIX,
          });
        } else if (ftype === 'DateTimeField' && !DATETIME_RE.test(v)) {
          findings.push({
            rule: 'date/datetimefield-shape',
            severity: 'error',
            file: rel,
            loc: `data.attributes.${fname}`,
            message: `${fname}=${JSON.stringify(v)} but the schema declares contains(DateTimeField) — value must be an ISO datetime containing T`,
            suggestion: 'Either reformat the value or switch the field to DateField if time-of-day is meaningless',
            fixRef: FIX,
          });
        }
      }
    }
    return findings;
  },
};
