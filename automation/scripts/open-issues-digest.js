/* global realm */
// A Realm Runner script: the body of an async function, run with the
// automation surface's `realm` object. It reads a repository's open issues
// through the automation's one declared outside call, groups them by label,
// and writes the digest to a Markdown file in the workspace. Its params name
// the repository card to read and the file to write.

realm.progress.plan(['Fetch open issues', 'Group by label', 'Write digest']);

// "1 label", "3 labels": a task reads as a person would write it.
const count = (n, word) => `${n} ${n === 1 ? word : `${word}s`}`;

const {
  repository = 'automation/examples/GitHubRepository/boxel',
  reportPath = 'reports/open-issues.md',
} = realm.current?.automation?.params ?? {};

realm.progress.milestone('Fetch open issues');
const { body: items } = await realm.operations.invoke(
  repository,
  'openIssues',
  {},
);
// GitHub lists pull requests as issues too; they carry a `pull_request` key.
const issues = items.filter((item) => !item.pull_request);
realm.progress.task(`Fetched ${count(issues.length, 'open issue')}`);
if (items.length > issues.length) {
  realm.progress.task(
    `Skipped ${count(items.length - issues.length, 'pull request')} GitHub listed as issues`,
  );
}

realm.progress.milestone('Group by label');
const byLabel = new Map();
for (const issue of issues) {
  const labels = issue.labels.length
    ? issue.labels.map((l) => l.name)
    : ['unlabeled'];
  for (const label of labels) {
    byLabel.set(label, [...(byLabel.get(label) ?? []), issue]);
  }
}
realm.progress.task(`Grouped the issues under ${count(byLabel.size, 'label')}`);

realm.progress.milestone('Write digest');
const sections = [...byLabel.entries()]
  .sort(([a], [b]) => a.localeCompare(b))
  .map(([label, list]) =>
    [`## ${label}`, '', ...list.map((i) => `- #${i.number} ${i.title}`)].join(
      '\n',
    ),
  );
await realm.fs.writeText(
  reportPath,
  [`# Open issues in ${repository}`, '', ...sections, ''].join('\n'),
);
realm.progress.task(`Wrote the digest to ${reportPath}`);
