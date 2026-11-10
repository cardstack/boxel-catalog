// The Evidence register's "newest first" order: each version chain sits
// together, newest version on top, and chains are ordered by their newest
// hash date. Unhashed chains go last, keeping the order they arrived in.
interface Versioned {
  id?: string;
  hashedAt?: Date | string | null;
  supersedes?: Versioned | null;
}

function time(d: Versioned): number {
  let t = d.hashedAt ? new Date(d.hashedAt).getTime() : NaN;
  return Number.isNaN(t) ? -Infinity : t;
}

export function registerOrder<T extends Versioned>(docs: T[]): T[] {
  let byId = new Map(docs.filter((d) => d.id).map((d) => [d.id!, d]));
  let superseded = new Set(
    docs.map((d) => d.supersedes?.id).filter((id): id is string => !!id),
  );
  let chains = docs
    .filter((d) => !d.id || !superseded.has(d.id))
    .map((head) => {
      let chain: T[] = [];
      let seen = new Set<string>();
      for (
        let d: T | undefined = head;
        d && !(d.id && seen.has(d.id));
        d = d.supersedes?.id ? byId.get(d.supersedes.id) : undefined
      ) {
        if (d.id) seen.add(d.id);
        chain.push(d);
      }
      return { chain, newest: Math.max(...chain.map(time)) };
    });
  // Array.prototype.sort is stable, so ties keep the arrival order.
  chains.sort((a, b) => b.newest - a.newest);
  let out = chains.flatMap((c) => c.chain);
  // A cycle has no head; keep its documents rather than drop them.
  let placed = new Set(out);
  return [...out, ...docs.filter((d) => !placed.has(d))];
}
