/* global realm */
// A Realm Runner script: the body of an async function, run with the
// automation surface's `realm` object. It counts the realm's cards of each
// type and writes the counts to a Markdown file in the realm. It declares its
// milestones first and marks each as it reaches it, so the automation card
// shows how long each took on the last run.

realm.progress.plan(['Find cards', 'Count by type', 'Write the report']);

realm.progress.milestone('Find cards');
const { cards } = await realm.cards.search({});

realm.progress.milestone('Count by type');
const counts = new Map();
for (const [index, card] of cards.entries()) {
  realm.progress.count(index + 1, cards.length);
  const key = `${card.type.module}#${card.type.name}`;
  counts.set(key, (counts.get(key) ?? 0) + 1);
}

const lines = [...counts.entries()]
  .sort(([a], [b]) => a.localeCompare(b))
  .map(([type, count]) => `| ${type} | ${count} |`);

realm.progress.milestone('Write the report');
await realm.fs.writeText(
  'reports/card-count.md',
  [
    '# Cards by type',
    '',
    '| Type | Cards |',
    '| --- | --- |',
    ...lines,
    '',
  ].join('\n'),
);
