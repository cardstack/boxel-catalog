import { tracked } from '@glimmer/tracking';
import { isDestroyed, isDestroying } from '@ember/destroyable';

// A card's own search is capped at 100 rows a page, so a read that must see every record walks
// the pages: page 0, created with the read, reports the match count, and once it has, the further
// pages that count calls for are created after the render that finds them missing, each asking for
// its own fixed page. No page's search reads another page's state. Nothing reads as complete until
// every page it needs has answered.
export const SEARCH_PAGE = 100;
export const MAX_SEARCH_PAGES = 20;

// What getCards answers with: its rows, whether a search is running, and the paging metadata.
interface PageResource {
  instances?: any[];
  isLoading?: boolean;
  meta?: { page?: { total?: number }; incomplete?: boolean };
}

interface CardsContext {
  getCards?: (
    parent: object,
    getQuery: () => any,
    getRealms?: () => string[] | undefined,
    opts?: { isLive?: true },
  ) => unknown;
}

const totalOf = (p: PageResource | undefined) => {
  let total = p?.meta?.page?.total;
  return typeof total === 'number' ? total : undefined;
};
// A failed search marks its result incomplete, and so does a realm it couldn't search.
const failedPage = (p: PageResource) => !!p.meta?.incomplete;
// A page has answered once its search has finished: with a count, or as failed.
const answered = (p: PageResource) =>
  p.isLoading === false && (totalOf(p) !== undefined || failedPage(p));

export class AllCards {
  @tracked private pages: (PageResource | undefined)[];
  // With a limit, only the first `limit` rows are read and `truncated` says whether more matched.
  private limit: number | undefined;
  private maxPages: number;
  private makePage: (number: number) => PageResource | undefined;
  private parent: object;
  private growing = false;

  constructor(
    context: CardsContext | undefined,
    parent: object,
    getQuery: () => any,
    getRealms?: () => string[] | undefined,
    opts?: { isLive?: true; limit?: number },
  ) {
    this.limit = opts?.limit;
    this.parent = parent;
    this.maxPages = Math.min(
      MAX_SEARCH_PAGES,
      Math.ceil((opts?.limit ?? Infinity) / SEARCH_PAGE),
    );
    let searchOpts = opts?.isLive ? { isLive: true as const } : undefined;
    this.makePage = (number) =>
      context?.getCards?.(
        parent,
        () => {
          let query = getQuery();
          return query
            ? { ...query, page: { size: SEARCH_PAGE, number } }
            : undefined;
        },
        getRealms,
        searchOpts,
      ) as PageResource | undefined;
    this.pages = [this.makePage(0)];
  }

  // Creates the pages the count calls for, after the render that found them missing.
  private grow(wanted: number) {
    if (this.growing || wanted <= this.pages.length) return;
    this.growing = true;
    Promise.resolve().then(() => {
      this.growing = false;
      // The component holding the read may have gone since the render that asked.
      if (isDestroying(this.parent) || isDestroyed(this.parent)) return;
      let target = Math.min(this.wantedPages, this.maxPages);
      if (target <= this.pages.length) return;
      let pages = [...this.pages];
      while (pages.length < target) pages.push(this.makePage(pages.length));
      this.pages = pages;
    });
  }

  // How many records the query matches, as the first page last answered; undefined until it has.
  get total(): number | undefined {
    let first = this.pages[0];
    return first && !failedPage(first) ? totalOf(first) : undefined;
  }

  private get matchedPages(): number {
    let total = this.total;
    return total === undefined ? 1 : Math.ceil(total / SEARCH_PAGE);
  }

  // The pages the count calls for, up to what a read may hold.
  private get wantedPages(): number {
    return Math.max(1, Math.min(this.matchedPages, this.maxPages));
  }

  // The pages the count calls for that exist so far; any still missing are created after this render.
  private get needed(): PageResource[] {
    let wanted = this.wantedPages;
    if (this.pages.length < wanted) this.grow(wanted);
    return this.pages.slice(0, wanted).filter((p): p is PageResource => !!p);
  }

  // More matched than any read may hold.
  get tooMany(): boolean {
    return this.limit === undefined && this.matchedPages > this.maxPages;
  }

  // More matched than the limit asked for, so only the first `limit` were read.
  get truncated(): boolean {
    return (
      this.limit !== undefined &&
      this.total !== undefined &&
      this.total > this.maxPages * SEARCH_PAGE
    );
  }

  get failed(): boolean {
    return !this.pages[0] || this.needed.some(failedPage);
  }

  // Not every record was read: too many matched, or a page failed.
  get incomplete(): boolean {
    return this.tooMany || this.truncated || this.failed;
  }

  get isLoading(): boolean {
    return this.total === undefined && !this.failed
      ? true
      : this.needed.some((p) => !answered(p)) ||
          this.pages.length < this.wantedPages;
  }

  // Every record, or nothing usable: false while any page is loading, failed, or over the cap.
  get isComplete(): boolean {
    return (
      this.total !== undefined &&
      !this.isLoading &&
      !this.failed &&
      !this.tooMany &&
      !this.truncated
    );
  }

  get errors(): string[] {
    if (this.tooMany)
      return [
        `There are more than ${MAX_SEARCH_PAGES * SEARCH_PAGE} records to read.`,
      ];
    return this.failed ? ['The records could not all be read.'] : [];
  }

  get instances(): any[] {
    let seen = new Set<string>();
    let out: any[] = [];
    for (let page of this.needed)
      for (let card of page.instances ?? []) {
        let id = card?.id;
        if (id && seen.has(id)) continue;
        if (id) seen.add(id);
        out.push(card);
      }
    return out;
  }
}

interface CardStore {
  search(query: any, realms?: string[]): Promise<unknown[]>;
}

// The imperative read: every page of `query`, or a throw when more than `max` match.
export async function searchAll(
  store: CardStore,
  query: Record<string, unknown>,
  realms: string[] | undefined,
  max = MAX_SEARCH_PAGES * SEARCH_PAGE,
  tooMany = `More than ${max} records match, more than the desk reads at once.`,
): Promise<any[]> {
  let out: any[] = [];
  // A page can come back short when a row on it fails to load, so only an empty page ends the walk.
  for (let number = 0; ; number++) {
    let page = (await store.search(
      { ...query, page: { size: SEARCH_PAGE, number } },
      realms,
    )) as any[];
    if (!page.length) return out;
    out.push(...page);
    if (out.length > max) throw new Error(tooMany);
  }
}
