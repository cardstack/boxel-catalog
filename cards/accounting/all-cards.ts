// A card's own search is capped at 100 rows a page, so a read that must see every record walks
// the pages: page 0 reports the match count, and each further page asks only once that count says
// it holds rows. Nothing reads as complete until every page it needs has answered.
export const SEARCH_PAGE = 100;
export const MAX_SEARCH_PAGES = 20;

interface PageResource {
  instances?: any[];
  isLoading?: boolean;
  errors?: unknown[];
  totalMatchCount?: number;
  meta?: { incomplete?: boolean };
}

interface CardsContext {
  getCards?: (
    parent: object,
    getQuery: () => any,
    getRealms?: () => string[] | undefined,
    opts?: { isLive?: true },
  ) => unknown;
}

// A page has answered once its own search has finished: with a count, or with an error. Until then
// it may be a page whose query was only just set, which reads as idle and empty.
const answered = (p: PageResource) =>
  p.isLoading === false &&
  (typeof p.totalMatchCount === 'number' || (p.errors ?? []).length > 0);

export class AllCards {
  private pages: (PageResource | undefined)[];
  // With a limit, only the first `limit` rows are read and `truncated` says whether more matched.
  private limit: number | undefined;

  constructor(
    context: CardsContext | undefined,
    parent: object,
    getQuery: () => any,
    getRealms?: () => string[] | undefined,
    opts?: { isLive?: true; limit?: number },
  ) {
    this.limit = opts?.limit;
    let searchOpts = opts?.isLive ? { isLive: true as const } : undefined;
    this.pages = Array.from(
      {
        length: Math.min(
          MAX_SEARCH_PAGES,
          Math.ceil((opts?.limit ?? Infinity) / SEARCH_PAGE),
        ),
      },
      (_, number) =>
        context?.getCards?.(
          parent,
          () => {
            let query = getQuery();
            if (!query) return undefined;
            if (number > 0 && number >= this.pageCount) return undefined;
            return { ...query, page: { size: SEARCH_PAGE, number } };
          },
          getRealms,
          searchOpts,
        ) as PageResource | undefined,
    );
  }

  // How many records the query matches, as the first page last answered; undefined until it has.
  get total(): number | undefined {
    let first = this.pages[0];
    return typeof first?.totalMatchCount === 'number'
      ? first.totalMatchCount
      : undefined;
  }

  private get matchedPages(): number {
    let total = this.total;
    return total === undefined ? 1 : Math.ceil(total / SEARCH_PAGE);
  }

  private get pageCount(): number {
    return Math.min(this.matchedPages, this.pages.length);
  }

  private get needed(): PageResource[] {
    return this.pages
      .slice(0, Math.max(1, this.pageCount))
      .filter((p): p is PageResource => !!p);
  }

  // More matched than any read may hold.
  get tooMany(): boolean {
    return this.limit === undefined && this.matchedPages > this.pages.length;
  }

  // More matched than the limit asked for, so only the first `limit` were read.
  get truncated(): boolean {
    return (
      this.limit !== undefined &&
      this.total !== undefined &&
      this.total > this.pages.length * SEARCH_PAGE
    );
  }

  get failed(): boolean {
    return (
      !this.pages[0] ||
      this.needed.some((p) => (p.errors ?? []).length > 0 || p.meta?.incomplete)
    );
  }

  // Not every record was read: too many matched, or a page failed.
  get incomplete(): boolean {
    return this.tooMany || this.truncated || this.failed;
  }

  get isLoading(): boolean {
    return this.total === undefined && !this.failed
      ? true
      : this.needed.some((p) => !answered(p));
  }

  // Every record, or nothing usable: false while any page is loading, failed, or over the cap.
  get isComplete(): boolean {
    return (
      this.total !== undefined &&
      !this.isLoading &&
      !this.failed &&
      !this.tooMany
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
  for (let number = 0; ; number++) {
    if (number * SEARCH_PAGE >= max) throw new Error(tooMany);
    let page = (await store.search(
      { ...query, page: { size: SEARCH_PAGE, number } },
      realms,
    )) as any[];
    out.push(...page);
    if (page.length < SEARCH_PAGE) return out;
  }
}
