/* global realm */
// A Realm Runner script: the body of an async function, run with the
// automation surface's `realm` object. It counts the realm's cards of each
// type and writes the counts to a Markdown file in the realm. It declares its
// milestones first and marks each as it reaches it, so the automation card
// shows how long each took on the last run.

// The most cards one search answers with. A search answers one page of
// cards, so the script reads the workspace a page at a time until no more
// cards match.
const PAGE_SIZE = 100;

realm.progress.plan(['Count cards by type', 'Write the report']);

realm.progress.milestone('Count cards by type');
const counts = new Map();
let counted = 0;
// Where the next page starts. A page starts at `number * size`, so `size`
// always divides it.
let start = 0;
let size = PAGE_SIZE;
for (;;) {
  let page;
  try {
    page = await realm.cards.search({
      page: { number: start / size, size },
    });
  } catch (error) {
    // A search refuses a page whose cards together are too large to return,
    // and names the page size that fits. Ask again from the same card with
    // that size, or the next smaller one that divides `start`.
    const fits = Number(/page\.size (\d+) or less/.exec(error.message)?.[1]);
    if (!fits) {
      throw error;
    }
    size = fits;
    while (start % size !== 0) {
      size--;
    }
    continue;
  }
  const { cards, total, truncated } = page;
  for (const card of cards) {
    const key = `${card.type.module}#${card.type.name}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  counted += cards.length;
  // One count a page keeps a large workspace well under a run's limit on
  // progress calls. Cards saved while the script reads can move the total,
  // and a count may never pass its total.
  realm.progress.count(counted, Math.max(total, counted));
  start += size;
  // The total bounds the pages too, so a search that keeps answering empty
  // pages still ends.
  if (!truncated || start >= total) {
    break;
  }
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
