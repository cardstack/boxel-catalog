// S07 — every exported CardDef ships isolated + embedded + fitted; FieldDefs
// should override embedded or edit (base defaults are rarely adequate for a listing).
import { staticFormats } from '../lib/gts-scan.mjs';

const FIX = 'boxel/references/design-playbook.md';

export default {
  id: 's07-formats-present',
  title: 'Required formats per definition',
  phase: 'static',
  run(ctx) {
    const findings = [];
    for (const def of ctx.kit.defs) {
      if (!def.exported) continue;
      const formats = staticFormats(def.body);
      if (def.kind === 'card') {
        for (const required of ['isolated', 'embedded', 'fitted']) {
          if (!formats[required]) {
            findings.push({
              rule: 'formats/missing-card-format',
              severity: 'error',
              file: def.file,
              loc: `class ${def.name} (line ${def.line})`,
              message: `CardDef ${def.name} has no static ${required} template — every catalog card needs isolated, embedded AND fitted`,
              suggestion: 'Utility/config cards may waive this with a reason',
              fixRef: FIX,
            });
          }
        }
      } else if (!formats.embedded && !formats.edit) {
        findings.push({
          rule: 'formats/fielddef-no-override',
          severity: 'warn',
          file: def.file,
          loc: `class ${def.name} (line ${def.line})`,
          message: `FieldDef ${def.name} overrides neither embedded nor edit — it will render with bare base defaults`,
        });
      }
    }
    return findings;
  },
};
