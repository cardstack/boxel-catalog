/* global realm */
// A Realm Runner script: the body of an async function, run with the
// automation surface's `realm` object. It reads a repository's open issues
// through the automation's one declared outside call, groups them by label,
// and writes the digest to a Markdown file in the workspace. Its params name
// the repository card to read and the file to write.

await realm.plan(['Fetch open issues', 'Group by label', 'Write digest']);

const {
  repository = 'automation/examples/GitHubRepository/boxel',
  reportPath = 'reports/open-issues.md',
} = realm.current?.automation?.params ?? {};

await realm.activity({ message: 'Fetching open issues', current: 1, total: 3 });
const { body: items } = await realm.operations.invoke(
  repository,
  'openIssues',
  {},
);
// GitHub lists pull requests as issues too; they carry a `pull_request` key.
const issues = items.filter((item) => !item.pull_request);

await realm.activity({ message: 'Grouping by label', current: 2, total: 3 });
const byLabel = new Map();
for (const issue of issues) {
  const labels = issue.labels.length
    ? issue.labels.map((l) => l.name)
    : ['unlabeled'];
  for (const label of labels) {
    byLabel.set(label, [...(byLabel.get(label) ?? []), issue]);
  }
}

await realm.activity({ message: 'Writing the digest', current: 3, total: 3 });
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
