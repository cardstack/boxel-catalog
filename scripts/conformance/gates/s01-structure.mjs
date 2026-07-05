// S01 — listing dir anatomy: one listing JSON, spec coverage, examples, imagery.
import { relationshipsOf, resolveRelative } from '../lib/json-walk.mjs';

const FIX = 'catalog-card-factory/references/packaging.md';

export default {
  id: 's01-structure',
  title: 'Listing directory anatomy',
  phase: 'static',
  run(ctx) {
    const findings = [];
    const listingPaths = ctx.files.filter((f) => /(^|\/)[A-Za-z]+Listing\/[^/]+\.json$/.test(f));

    if (listingPaths.length === 0) {
      findings.push({
        rule: 'structure/no-listing',
        severity: 'error',
        file: '.',
        message: 'No <Type>Listing/*.json found — a listing package must contain exactly one listing instance',
        fixRef: FIX,
      });
      return findings;
    }
    if (listingPaths.length > 1) {
      findings.push({
        rule: 'structure/multiple-listings',
        severity: 'error',
        file: listingPaths[1],
        message: `Found ${listingPaths.length} listing instances (${listingPaths.join(', ')}) — a listing package must contain exactly one`,
        fixRef: FIX,
      });
    }

    const listingPath = listingPaths[0];
    const listing = ctx.jsonDocs.get(listingPath)?.doc;
    if (!listing) return findings; // unparseable — S02 reports it
    const listingType = listing?.data?.meta?.adoptsFrom?.name ?? 'CardListing';
    const rels = relationshipsOf(listing);
    const isVisual = listingType === 'CardListing' || listingType === 'AppListing';

    // linked-file existence for relative listing relationships
    const relEntries = Object.entries(rels)
      .map(([k, v]) => [k, v?.links?.self])
      .filter(([, link]) => typeof link === 'string' && link.startsWith('.'));
    for (const [key, link] of relEntries) {
      const resolved = resolveRelative(listingPath, link);
      const exists = ctx.files.some((f) => f === resolved || f === `${resolved}.json` || f.startsWith(`${resolved}.`));
      if (!exists && !resolved.startsWith('..')) {
        findings.push({
          rule: 'structure/broken-relationship',
          severity: 'error',
          file: listingPath,
          loc: `data.relationships["${key}"]`,
          message: `Relationship points at ${link} but no such file exists in the package`,
          fixRef: FIX,
        });
      }
    }

    // examples (visual listings must ship at least one)
    const hasExample = Object.keys(rels).some((k) => /^examples\.\d+$/.test(k) && rels[k]?.links?.self);
    if (isVisual && !hasExample) {
      findings.push({
        rule: 'structure/no-example',
        severity: 'error',
        file: listingPath,
        message: `${listingType} has no examples.N relationships — ship at least one live example instance`,
        suggestion: 'Link example instances so the catalog can preview the card with real data',
        fixRef: FIX,
      });
    }

    // thumbnail
    const thumb = rels['cardInfo.cardThumbnail']?.links?.self;
    if (!thumb) {
      findings.push({
        rule: 'structure/no-thumbnail',
        severity: 'error',
        file: listingPath,
        loc: 'data.relationships["cardInfo.cardThumbnail"]',
        message: 'Listing has no thumbnail (cardInfo.cardThumbnail is null)',
        fixRef: FIX,
      });
    }

    // screenshots (visual listings)
    const hasScreenshot = Object.keys(rels).some((k) => /^images\.\d+$/.test(k) && rels[k]?.links?.self);
    if (isVisual && !hasScreenshot) {
      findings.push({
        rule: 'structure/no-screenshot',
        severity: 'error',
        file: listingPath,
        message: `${listingType} has no images.N screenshot relationships`,
        fixRef: FIX,
      });
    }

    // name + summary present
    const attrs = listing?.data?.attributes ?? {};
    if (!attrs.name) {
      findings.push({
        rule: 'structure/no-name',
        severity: 'error',
        file: listingPath,
        message: 'Listing has no name attribute',
      });
    }
    if (!attrs.summary) {
      findings.push({
        rule: 'structure/no-summary',
        severity: 'warn',
        file: listingPath,
        message: 'Listing has no summary — the catalog page will be blank',
      });
    }

    // Spec coverage: every module with an exported card/field def should have a local Spec
    const specRefs = new Set();
    for (const [rel, entry] of ctx.jsonDocs) {
      if (!/(^|\/)Spec\/[^/]+\.json$/.test(rel) || !entry.doc) continue;
      const mod = entry.doc?.data?.attributes?.ref?.module;
      if (typeof mod === 'string') specRefs.add(resolveRelative(rel, mod));
    }
    const defModules = new Set(
      ctx.kit.defs.filter((d) => d.exported).map((d) => d.file.replace(/\.(gts|gjs)$/, ''))
    );
    for (const mod of defModules) {
      if (!specRefs.has(mod)) {
        findings.push({
          rule: 'structure/missing-spec',
          severity: 'error',
          file: `${mod}.gts`,
          message: `Module exports a CardDef/FieldDef but has no Spec/*.json with ref.module pointing at it`,
          suggestion: 'Every definition module ships a Spec so the catalog can install and document it',
          fixRef: FIX,
        });
      }
    }

    return findings;
  },
};
