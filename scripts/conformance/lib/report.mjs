// Findings aggregation, waiver application, human + JSON output.

/** finding: { rule, severity: 'error'|'warn'|'info', file, loc?, message, suggestion?, fixRef? } */
export function makeFinding(f) {
  return { severity: 'warn', ...f };
}

/**
 * Minimal YAML subset parser for waiver files — a list of flat maps:
 *   waivers:
 *     - rule: reuse/hand-rolled-button
 *       file: recipe-box.gts
 *       reason: "custom pressed-state animation"
 * Also accepts a bare top-level list (no `waivers:` key). Nothing else.
 */
export function parseWaivers(text) {
  const waivers = [];
  let current = null;
  for (const raw of text.split('\n')) {
    const line = raw.replace(/#.*$/, '').trimEnd();
    if (!line.trim() || /^waivers\s*:\s*$/.test(line.trim())) continue;
    const item = line.match(/^\s*-\s+(\w+)\s*:\s*(.+)$/);
    const cont = line.match(/^\s+(\w+)\s*:\s*(.+)$/);
    if (item) {
      current = {};
      waivers.push(current);
      current[item[1]] = unquote(item[2]);
    } else if (cont && current) {
      current[cont[1]] = unquote(cont[2]);
    }
  }
  return waivers.filter((w) => w.rule);
}

function unquote(s) {
  const t = s.trim();
  if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
    return t.slice(1, -1);
  }
  return t;
}

/** Mark findings matched by a waiver (rule required; file optional = waives all files). */
export function applyWaivers(findings, waivers) {
  for (const f of findings) {
    const w = waivers.find(
      (w) => w.rule === f.rule && (!w.file || w.file === f.file)
    );
    if (w) {
      f.waived = true;
      f.waivedReason = w.reason ?? '';
    }
  }
  return findings;
}

export function buildReport({ listingDir, phase, gateResults, harnessVersion }) {
  const all = gateResults.flatMap((g) => g.findings);
  const active = all.filter((f) => !f.waived);
  const errors = active.filter((f) => f.severity === 'error').length;
  const warnings = active.filter((f) => f.severity === 'warn').length;
  const waived = all.filter((f) => f.waived).length;
  return {
    harnessVersion,
    listingDir,
    phase,
    summary: {
      result: errors > 0 ? 'fail' : 'pass',
      errors,
      warnings,
      waived,
    },
    gates: gateResults.map((g) => ({
      id: g.id,
      title: g.title,
      status: g.error
        ? 'harness-error'
        : g.findings.some((f) => !f.waived && f.severity === 'error')
          ? 'fail'
          : g.findings.some((f) => !f.waived)
            ? 'warn'
            : 'pass',
      durationMs: g.durationMs,
      ...(g.error ? { error: g.error } : {}),
      findings: g.findings,
    })),
  };
}

const ICONS = { pass: '✓', warn: '△', fail: '✗', 'harness-error': '!' };

export function printHuman(report, out = console) {
  out.log(`\nConformance — ${report.listingDir} (phase: ${report.phase})\n`);
  for (const gate of report.gates) {
    out.log(`  ${ICONS[gate.status] ?? '?'} ${gate.id}  ${gate.title}  (${gate.durationMs}ms)`);
    for (const f of gate.findings) {
      const tag = f.waived ? 'waived' : f.severity;
      out.log(`      [${tag}] ${f.file}${f.loc ? ` :: ${f.loc}` : ''}`);
      out.log(`        ${f.message}`);
      if (f.suggestion && !f.waived) out.log(`        → ${f.suggestion}`);
      if (f.waived) out.log(`        (waived: ${f.waivedReason})`);
    }
    if (gate.error) out.log(`      harness error: ${gate.error}`);
  }
  const s = report.summary;
  out.log(
    `\n  ${s.result === 'pass' ? '✓ PASS' : '✗ FAIL'} — ${s.errors} error(s), ${s.warnings} warning(s), ${s.waived} waived\n`
  );
}
