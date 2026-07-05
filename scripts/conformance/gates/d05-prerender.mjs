// D05 — prerender smoke: the realm's search-prerendered endpoint returns
// rendered HTML (not error payloads) for embedded/fitted/atom of each example.
export default {
  id: 'd05-prerender',
  title: 'Prerender formats render clean',
  phase: 'dynamic',
  async run(ctx) {
    if (!ctx.options.realm) {
      return [{ rule: 'prerender/no-realm', severity: 'warn', file: '.', message: 'D05 skipped: no --realm provided' }];
    }
    const realm = ctx.options.realm.endsWith('/') ? ctx.options.realm : `${ctx.options.realm}/`;
    const findings = [];
    for (const def of ctx.kit.defs) {
      if (!def.exported || def.kind !== 'card') continue;
      const moduleUrl = `${realm}${def.file.replace(/\.(gts|gjs)$/, '')}`;
      for (const format of ['embedded', 'fitted', 'atom']) {
        const url = new URL(`${realm}_search-prerendered`);
        url.searchParams.set('prerenderedHtmlFormat', format);
        url.searchParams.set('filter', JSON.stringify({ type: { module: moduleUrl, name: def.name } }));
        try {
          const res = await fetch(url, {
            headers: { Accept: 'application/vnd.card+json' },
            signal: AbortSignal.timeout(30_000),
          });
          const body = await res.text();
          if (!res.ok) {
            findings.push({
              rule: 'prerender/http-error',
              severity: 'error',
              file: def.file,
              loc: `${def.name} @${format}`,
              message: `Prerender query returned HTTP ${res.status} for ${format}`,
            });
            continue;
          }
          if (/"error"|render error|Encountered error rendering/i.test(body)) {
            findings.push({
              rule: 'prerender/render-error',
              severity: 'error',
              file: def.file,
              loc: `${def.name} @${format}`,
              message: `Prerendered ${format} contains an error payload — the template throws at render time`,
              suggestion: 'Check defensive guards on linksTo/linksToMany traversals and date values',
              fixRef: 'boxel/references/defensive-programming.md',
            });
          }
        } catch (e) {
          findings.push({
            rule: 'prerender/unreachable',
            severity: 'warn',
            file: def.file,
            loc: `${def.name} @${format}`,
            message: `Prerender endpoint unreachable: ${e.message}`,
          });
        }
      }
    }
    return findings;
  },
};
