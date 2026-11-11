/* global realm */
// A Realm Runner script: the body of an async function, run with the
// automation surface's `realm` object. It counts the realm's cards of each
// type and writes the counts to a Markdown file in the realm.

await realm.activity({ message: 'Finding cards', current: 1, total: 3 });
const { cards } = await realm.cards.search({});

await realm.activity({ message: 'Counting by type', current: 2, total: 3 });
const counts = new Map();
for (const card of cards) {
  const key = `${card.type.module}#${card.type.name}`;
  counts.set(key, (counts.get(key) ?? 0) + 1);
}

const lines = [...counts.entries()]
  .sort(([a], [b]) => a.localeCompare(b))
  .map(([type, count]) => `| ${type} | ${count} |`);

await realm.activity({ message: 'Writing the report', current: 3, total: 3 });
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
