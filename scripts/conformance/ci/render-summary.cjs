// Renders conformance report JSONs into (a) a PR comment or (b) the pinned
// nightly-sweep issue. Invoked by actions/github-script from conformance.yaml.
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const PR_MARKER = '<!-- listing-conformance-report -->';
const SWEEP_TITLE = 'Catalog conformance sweep';

function loadReports(reportsDir) {
  if (!fs.existsSync(reportsDir)) return [];
  return fs
    .readdirSync(reportsDir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(fs.readFileSync(path.join(reportsDir, f), 'utf8')));
}

function statusEmoji(r) {
  if (r.summary.result === 'fail') return '❌';
  if (r.summary.warnings > 0) return '⚠️';
  return '✅';
}

function detailsFor(r, { maxFindings = 30 } = {}) {
  const rows = [];
  for (const gate of r.gates) {
    for (const f of gate.findings) {
      if (f.waived) continue;
      rows.push(
        `| ${f.severity === 'error' ? '🔴' : f.severity === 'warn' ? '🟡' : 'ℹ️'} \`${f.rule}\` | \`${f.file}\` | ${f.message.replace(/\|/g, '\\|').slice(0, 140)} |`
      );
    }
  }
  if (rows.length === 0) return '';
  const shown = rows.slice(0, maxFindings);
  const more = rows.length > shown.length ? `\n\n…and ${rows.length - shown.length} more (see artifact).` : '';
  return [
    '<details><summary>Findings</summary>',
    '',
    '| | rule | file | message |'.replace('| |', '| sev |'),
    '|---|---|---|---|',
    ...shown,
    more,
    '</details>',
  ].join('\n');
}

function renderBody(reports, heading) {
  const lines = [
    heading,
    '',
    '| listing | result | errors | warnings | waived |',
    '|---|---|---|---|---|',
  ];
  for (const r of reports.sort((a, b) => a.listingDir.localeCompare(b.listingDir))) {
    lines.push(
      `| \`${r.listingDir}\` | ${statusEmoji(r)} ${r.summary.result} | ${r.summary.errors} | ${r.summary.warnings} | ${r.summary.waived} |`
    );
  }
  lines.push('');
  for (const r of reports) {
    if (r.summary.errors + r.summary.warnings > 0) {
      lines.push(`### \`${r.listingDir}\``, detailsFor(r), '');
    }
  }
  lines.push('', `_harness ${reports[0]?.harnessVersion ?? '?'} · [gate docs](../blob/main/scripts/conformance/README.md)_`);
  return lines.join('\n');
}

module.exports = async function render({ github, context, reportsDir, mode }) {
  const reports = loadReports(reportsDir);
  if (reports.length === 0) return;

  if (mode === 'pr') {
    const body = `${PR_MARKER}\n${renderBody(reports, '## Listing conformance')}`;
    const { owner, repo } = context.repo;
    const issue_number = context.issue.number;
    const comments = await github.rest.issues.listComments({ owner, repo, issue_number, per_page: 100 });
    const mine = comments.data.find((c) => c.body?.includes(PR_MARKER));
    if (mine) {
      await github.rest.issues.updateComment({ owner, repo, comment_id: mine.id, body });
    } else {
      await github.rest.issues.createComment({ owner, repo, issue_number, body });
    }
    return;
  }

  // ---- sweep mode: create/update/close the single pinned issue
  const { owner, repo } = context.repo;
  const failing = reports.filter((r) => r.summary.result === 'fail');
  const body = renderBody(
    reports,
    `## Nightly conformance sweep — ${failing.length}/${reports.length} listing(s) failing`
  );
  const open = await github.rest.issues.listForRepo({ owner, repo, state: 'open', per_page: 100 });
  const existing = open.data.find((i) => i.title === SWEEP_TITLE);
  if (failing.length === 0) {
    if (existing) {
      await github.rest.issues.createComment({
        owner, repo, issue_number: existing.number,
        body: 'Sweep is clean — closing. 🎉',
      });
      await github.rest.issues.update({ owner, repo, issue_number: existing.number, state: 'closed' });
    }
    return;
  }
  if (existing) {
    await github.rest.issues.update({ owner, repo, issue_number: existing.number, body });
  } else {
    await github.rest.issues.create({ owner, repo, title: SWEEP_TITLE, body });
  }
};
