// S04 — no inline media/binary payloads in card JSON attributes.
import { instances, attributesOf, walkStrings } from '../lib/json-walk.mjs';

const BASE64_BLOB = /^[A-Za-z0-9+/]{512,}={0,2}$/;

export default {
  id: 's04-no-inline-media',
  title: 'No inline media / base64 in JSON attributes',
  phase: 'static',
  run(ctx) {
    const findings = [];
    for (const [rel, doc] of instances(ctx)) {
      walkStrings(attributesOf(doc), (path, str) => {
        if (str.startsWith('data:') && str.includes(';base64,')) {
          findings.push({
            rule: 'media/data-uri',
            severity: 'error',
            file: rel,
            loc: path,
            message: `data: URI embedded in attributes (${str.slice(0, 40)}…) — media must be a realm file linked via FileDef/ImageDef`,
            suggestion: 'Write the bytes with WriteBinaryFileCommand and linksTo the file instead',
          });
        } else if (str.length >= 512 && BASE64_BLOB.test(str.replace(/\s/g, ''))) {
          findings.push({
            rule: 'media/base64-blob',
            severity: 'error',
            file: rel,
            loc: path,
            message: `Attribute contains a ${str.length}-char base64-looking blob — inline binary is forbidden in card JSON`,
            suggestion: 'Store as a realm file and link it (FileDef/ImageDef/PngDef)',
          });
        }
      });
    }
    return findings;
  },
};
