// S03 — realm-bricking relationship shapes. Ported from
// boxel-workspaces .claude/skills/boxel/scripts/instance-correctness-scan.py (rules 1-2).
import { instances, relationshipsOf } from '../lib/json-walk.mjs';

const NONCARD_EXTS = ['.jpg', '.jpeg', '.webp', '.gif', '.pdf', '.mp3', '.mp4', '.wav', '.zip'];
const NONCARD_HOSTS = ['images.unsplash.com', 'images.', 'cdn.', 'img.', 's3.amazonaws.com'];
const FIX = 'boxel/references/base-field-catalog.md';

export default {
  id: 's03-instance-shape',
  title: 'Relationship shapes (realm-bricking classes)',
  phase: 'static',
  run(ctx) {
    const findings = [];
    for (const [rel, doc] of instances(ctx)) {
      const rels = relationshipsOf(doc);
      for (const [key, val] of Object.entries(rels)) {
        if (!val || typeof val !== 'object') continue;
        const self = val.links?.self;

        // Rule 1: linksToMany serialized as an array under one key
        if (Array.isArray(self)) {
          findings.push({
            rule: 'instance/linksToMany-array',
            severity: 'error',
            file: rel,
            loc: `data.relationships["${key}"].links.self`,
            message: 'linksToMany serialized as an array under links.self; the host rejects this as "not a card resource document"',
            suggestion: `Use indexed top-level keys instead: "${key}.0", "${key}.1", …`,
            fixRef: FIX,
          });
          continue;
        }
        if (typeof self !== 'string' || !self.startsWith('http')) continue;

        // Rule 2: external non-card URL in a relationship link — bricks indexing
        const low = self.toLowerCase().split('?')[0];
        const extHit = NONCARD_EXTS.some((e) => low.endsWith(e));
        const hostHit = NONCARD_HOSTS.some((h) => low.includes(h));
        // .png/.svg are allowed only as RELATIVE realm-file links (ImageDef files);
        // over http they are still non-card fetches.
        const imgHit = /\.(png|svg)$/.test(low);
        if (extHit || hostHit || imgHit) {
          findings.push({
            rule: 'instance/external-url-in-link',
            severity: 'error',
            file: rel,
            loc: `data.relationships["${key}"].links.self`,
            message: `External non-card URL in relationship link (${self.slice(0, 60)}…) — the indexer fetches it expecting a card, JSON.parse fails on binary, and the whole indexing batch rolls back`,
            suggestion: 'Store external URLs in an attributes UrlField (heroImageURL pattern) and keep links.self for card identifiers only',
            fixRef: FIX,
          });
        }
      }
    }
    return findings;
  },
};
