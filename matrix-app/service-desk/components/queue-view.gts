import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { consume } from 'ember-provide-consume-context';
import { debounce } from 'lodash-es';
import { slaClock } from '../utils/sla-clock';
import { array } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Checkbox } from '@cardstack/pretui/components/checkbox';
import { Chip } from '@cardstack/pretui/components/chip';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import { CardCrudFunctionsContextName } from '@cardstack/runtime-common';
import type { CardCrudFunctions } from '@cardstack/base/card-api';

import { TransitionTicketStatusCommand } from '../commands/transition-ticket-status-command';
import { AutoAssignTicketCommand } from '../commands/auto-assign-ticket-command';
import type { CardContext } from '@cardstack/base/card-api';

import type { Ticket } from '../ticket';
import { SlaTimerBadge } from './sla-timer-badge';
import {
  ALERT_STYLE,
  COMPACT_EMPTY_STYLE,
} from '@cardstack/catalog/components/pretui-helpers';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { priorityOption } from '@cardstack/catalog/fields/priority/priority';
import { guidFor } from '@ember/object/internals';
import {
  TicketStatusField,
  TicketPriorityField,
  ticketPriorityRank,
} from '../ticket-taxonomy';
import { LENSES, matchesLens, type Lens } from '../utils/queue-lens';

interface StatCell {
  key: Lens;
  label: string;
  count: number;
  tone?: 'bad' | 'warn' | 'ok' | 'hold';
}

interface Signature {
  Args: {
    tickets: Ticket[];
    isLoading?: boolean;
    /** Realm-level failure, if the query itself could not run. */
    error?: string;
    /** Shown when the realm holds no tickets at all. */
    zeroDataMessage?: string;
    /**
     * When present the list SELECTS rather than navigates — the wide layout's
     * whole point is that choosing a ticket must not cost the reader their
     * place in the queue.
     */
    onSelect?: (ticket: Ticket) => void;
    selectedId?: string;
    /**
     * The lens, when something outside owns it — the console's rail. Passing
     * `onLens` is also what removes the built-in stat strip: two copies of the
     * same six counts on one screen is the reader's problem, not a feature.
     * Omit both and the list keeps its own strip, which is what makes this
     * component still usable on its own.
     */
    lens?: Lens;
    onLens?: (lens: Lens) => void;
    /** Restrict to one queue. Owned by the rail when the rail is present. */
    queueName?: string;
    onClearQueue?: () => void;
    onQueue?: (queueName: string | undefined) => void;
    onNew?: (event: Event) => void;
    creating?: boolean;
    /** The search term, when the console's header owns the search box. */
    search?: string;
    onClearSearch?: () => void;
    /** Needed for the bulk actions, which run real commands. */
    context?: CardContext;
  };
  Element: HTMLElement;
}

/**
 * The queue: the surface an agent lives in.
 *
 * Three decisions shape it.
 *
 *  1. **The counts ARE the filter.** A stat that only reports is a stat you
 *     read and then go looking for; making each one a lens means "1 breached"
 *     and "show me the breach" are the same gesture. It is also the densest
 *     filter control available — six numbers in one strip.
 *  2. **Rows are 46px and carry eight fields.** Density comes from packing the
 *     same height harder, never from shrinking type below readable size.
 *  3. **Three different empties.** Zero data, filtered-to-nothing, and queue-
 *     cleared need three different next actions, so they are three different
 *     screens. Collapsing them into "No results were found" tells the reader
 *     nothing about which situation they are in.
 */
const F = (...forms: [string, number][]) =>
  forms.map(([name, minWidth]) => ({ name, minWidth }));
const SEARCH_FORMS = F(['field', 12], ['field-s', 8], ['icon', 2], ['menu', 0]);
const QUEUE_FORMS = F(['chips', 24], ['menu', 0]);
const ADD_FORMS = F(['label', 8], ['icon', 2]);

const TONE_BY_HUE: Record<string, PretuiToneArg> = {
  red: 'danger',
  orange: 'warning',
  amber: 'warning',
  yellow: 'warning',
  green: 'success',
  blue: 'info',
};

export class QueueView extends GlimmerComponent<Signature> {
  get lensLabel(): string {
    return (
      LENSES.find((l) => l.key === this.lens)?.label.toLowerCase() ??
      'in progress'
    );
  }

  get queues() {
    let counts = new Map<string, number>();
    for (let t of this.all) {
      if (!matchesLens(t, 'open')) continue;
      let name = t.queueName?.trim() || 'Unrouted';
      counts.set(name, (counts.get(name) ?? 0) + 1);
    }
    return [...counts.entries()]
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  }

  get queueChoices() {
    return this.queues.map((q) => ({
      label: `${q.name} (${q.count})`,
      value: q.name,
      group: 'queue',
      checked: q.name === this.args.queueName,
      onSelect: () => this.pickQueue(q.name),
    }));
  }

  get queueOptions() {
    return [
      { value: '', label: 'All queues' },
      ...this.queues.map((q) => ({
        value: q.name,
        label: `${q.name} ${q.count}`,
      })),
    ];
  }

  setQueue = (name: string) => {
    if (name) {
      this.pickQueue(name);
    } else {
      this.clearQueue();
    }
  };

  pickQueue = (name: string, _event?: Event) => {
    this.args.onQueue?.(this.args.queueName === name ? undefined : name);
  };

  clearQueue = (_event?: Event) => {
    this.args.onClearQueue?.();
  };

  priorityTone = (ticket: Ticket): PretuiToneArg =>
    TONE_BY_HUE[this.priorityHueOf(ticket)] ?? 'neutral';

  priorityText = (ticket: Ticket) => {
    return (
      priorityOption(TicketPriorityField, ticket.priority)?.label ??
      ticket.priority
    );
  };

  searchId = `${guidFor(this)}-search`;

  @consume(CardCrudFunctionsContextName)
  declare cardCrudFunctions: CardCrudFunctions | undefined;

  @tracked ownLens: Lens = 'open';
  @tracked ownSearch = '';
  @tracked priorityFilter: string | undefined;

  // The lens predicates below compute against the live clock, so this view
  // subscribes to it — otherwise the rows a lens selects would only change
  // when something else happened to be ticking.
  constructor(owner: unknown, args: Signature['Args']) {
    super(owner as never, args as never);
    slaClock.subscribe();
  }

  willDestroy() {
    super.willDestroy();
    this.setSearchNow.cancel();
    slaClock.unsubscribe();
  }

  // Controlled when the console passes them, self-owned otherwise. The getters
  // are the only place that decision is made, so nothing below has to know
  // which mode it is in.
  get lens(): Lens {
    return this.args.lens ?? this.ownLens;
  }

  get search(): string {
    return this.args.search ?? this.ownSearch;
  }

  get ownsStrip(): boolean {
    return !this.args.onLens;
  }

  get ownsSearch(): boolean {
    return this.args.search === undefined;
  }

  private setSearchNow = debounce((value: string) => {
    this.ownSearch = value;
  }, 250);

  // Debounce the assignment to tracked state, not the input's own value: the
  // field must feel immediate, it is the filtering that waits.
  setSearch = (value: string) => {
    this.setSearchNow(value);
  };

  setLens = (lens: Lens, _event?: Event) => {
    let next = this.lens === lens && lens !== 'open' ? 'open' : lens;
    if (this.args.onLens) {
      this.args.onLens(next as Lens);
      return;
    }
    this.ownLens = next as Lens;
  };

  setPriority = (priority: string | undefined, _event?: Event) => {
    this.priorityFilter =
      this.priorityFilter === priority ? undefined : priority;
  };

  clearFilters = (_event?: Event) => {
    this.priorityFilter = undefined;
    this.ownLens = 'open';
    // Cancel the armed debounce BEFORE clearing. Pressing Clear within the
    // 250ms window otherwise lets the trailing invocation fire afterwards and
    // re-assign the term that was just cleared — the list re-filters itself
    // with no user input, which reads as the button not working.
    this.setSearchNow.cancel();
    this.ownSearch = '';
    // Clearing has to reach whoever owns each filter, or the button clears the
    // half this component holds and silently leaves the rail's half on.
    this.args.onLens?.('open');
    this.args.onClearQueue?.();
    this.args.onClearSearch?.();
  };

  open = (ticket: Ticket, _event?: Event) => {
    if (this.args.onSelect) {
      this.args.onSelect(ticket);
      return;
    }
    // No detail pane to select into (narrow layout) — fall back to pushing the
    // card onto the stack.
    if (ticket?.id) {
      this.cardCrudFunctions?.viewCard?.(new URL(ticket.id));
    }
  };

  // Without `onSelect` the list keeps its own cursor for J/K, so moving
  // through rows doesn't open each one.
  @tracked cursorId: string | undefined;

  get currentId(): string | undefined {
    return this.args.onSelect ? this.args.selectedId : this.cursorId;
  }

  isSelected = (ticket: Ticket) => ticket?.id === this.currentId;

  /**
   * J / K, because working a run of tickets is the job.
   *
   * Every action on the ticket already had a shortcut (R / N / P) while the
   * half that happens more often than any of them — moving to the next one —
   * did not, so a shift of forty tickets meant forty reaches for the mouse
   * between keyboard actions. Arrow keys are handled too: nobody reads a help
   * screen to learn that a list moves with J.
   */
  moveBy = (delta: number, list: HTMLElement | null) => {
    let rows = this.rows;
    if (!rows.length) {
      return;
    }
    let current = rows.findIndex((t) => t.id === this.currentId);
    // No selection yet: J starts at the top, K at the bottom.
    let next =
      current === -1
        ? delta > 0
          ? 0
          : rows.length - 1
        : Math.min(rows.length - 1, Math.max(0, current + delta));
    let ticket = rows[next];
    if (ticket) {
      if (this.args.onSelect) {
        this.open(ticket);
      } else {
        this.cursorId = ticket.id;
      }
      // Focus follows the cursor, so Enter or Space activates the highlighted
      // row through its own click, and the row stays on screen. Scoped to
      // this list, since another Queue View on the page renders the same ids.
      let row = list?.querySelector<HTMLElement>(
        `[data-ticket-id="${ticket.id}"]`,
      );
      row?.focus({ preventScroll: true });
      row?.scrollIntoView({ block: 'nearest' });
    }
  };

  // Typed as `Event` because that is what `on` hands a listener; the
  // narrowing happens here rather than in the signature, where it would
  // not be assignable.
  handleKey = (raw: Event) => {
    let event = raw as KeyboardEvent;
    let target = event.target as HTMLElement | null;
    // Never steal a key from someone typing — the search box is right here.
    if (
      event.metaKey ||
      event.ctrlKey ||
      event.altKey ||
      target?.tagName === 'INPUT' ||
      target?.tagName === 'TEXTAREA' ||
      target?.isContentEditable
    ) {
      return;
    }
    let list = event.currentTarget as HTMLElement | null;
    switch (event.key) {
      case 'j':
      case 'J':
      case 'ArrowDown':
        this.moveBy(1, list);
        break;
      case 'k':
      case 'K':
      case 'ArrowUp':
        this.moveBy(-1, list);
        break;
      default:
        return;
    }
    event.preventDefault();
  };

  get all(): Ticket[] {
    return (this.args.tickets ?? []).filter(Boolean);
  }

  get stats(): StatCell[] {
    return LENSES.map((spec) => ({
      key: spec.key,
      label: spec.label,
      tone: spec.tone,
      count: this.countFor(spec.key),
    }));
  }

  /**
   * Everything except the lens.
   *
   * The counts run over the same set as the list (search, priority and
   * queue applied), so "Overdue 3" never opens onto an empty list.
   * A count is a promise about what you get when you click it, and the only
   * way to keep that promise is to count the same set the click will show.
   */
  private get scoped(): Ticket[] {
    let query = this.search.trim().toLowerCase();
    return this.all.filter(
      (ticket) => this.matchesScope(ticket, query) === true,
    );
  }

  private matchesScope(ticket: Ticket, query: string): boolean {
    // Named predicates then &&, rather than one boolean expression — this is
    // where an AND/OR bug would otherwise hide.
    let priorityOk =
      !this.priorityFilter || ticket.priority === this.priorityFilter;
    let queueOk =
      !this.args.queueName ||
      (ticket.queueName?.trim() || 'Unrouted') === this.args.queueName;
    let textOk =
      !query ||
      [
        ticket.reference,
        ticket.subject,
        ticket.customerName,
        ticket.customerCompany,
        ticket.categoryName,
        ticket.queueName,
        ticket.assigneeName,
      ].some((field) => field?.toLowerCase().includes(query));
    return priorityOk && queueOk && Boolean(textOk);
  }

  private countFor(lens: Lens): number {
    return this.scoped.filter((t) => matchesLens(t, lens)).length;
  }

  get priorities() {
    return TicketPriorityField.priorityOptions;
  }

  /**
   * What P1 actually means, on hover and on focus.
   *
   * "P1" is system vocabulary. A new agent can filter by it long before they
   * can say which tickets belong in it, and the consequence — a P1 target is a
   * quarter of the standard one — is written nowhere in the interface. The
   * details popover carries both, and it opens on keyboard focus as well as
   * hover so it is not mouse-only trivia.
   */
  chipId = `qp-${guidFor(this)}`;
  @tracked hoveredPriority: string | undefined;

  anchorFor = (priority: string) => `${this.chipId}-${priority}`;

  get hoveredAnchor(): string {
    return `[data-bx-popover-anchor='${this.anchorFor(
      this.hoveredPriority ?? '',
    )}']`;
  }

  get hoveredOption() {
    return priorityOption(TicketPriorityField, this.hoveredPriority);
  }

  get hoveredFactor(): string | undefined {
    let factor = this.hoveredOption?.factor;
    if (factor == null || factor === 1) {
      return undefined;
    }
    return factor < 1
      ? `Targets shrink to ${factor * 100}% of the standard.`
      : `Targets stretch to ${factor}× the standard.`;
  }

  showPriority = (priority: string, _event?: Event) => {
    this.hoveredPriority = priority;
  };

  hidePriority = (_event?: Event) => {
    this.hoveredPriority = undefined;
  };

  get rows(): Ticket[] {
    // The lens on top of the same scope the counts use, so the two cannot
    // drift: one definition of "everything except the lens", read twice.
    //
    // ONE comparator, not two chained `.sort()` calls. A second sort re-sorts
    // from scratch and only preserves the first's order among elements it
    // considers equal — and a draft and a live ticket are never equal on
    // urgency, so chaining would have thrown the draft-first pass away
    // silently.
    return this.scoped
      .filter((ticket) => matchesLens(ticket, this.lens))
      .sort((a, b) => {
        // Drafts first, always. A ticket with no subject is one somebody
        // started and has not finished; sorting it by SLA like everything else
        // buried a brand-new ticket in the middle of the list the moment it
        // was created, or at the bottom when it had no policy at all. The one
        // row you certainly want next is the one you were just typing into.
        let draft =
          Number(Boolean(a.subject?.trim())) -
          Number(Boolean(b.subject?.trim()));
        if (draft) {
          return draft;
        }
        return (
          (a.urgencyOrder ?? Number.MAX_SAFE_INTEGER) -
            (b.urgencyOrder ?? Number.MAX_SAFE_INTEGER) ||
          ticketPriorityRank(a.priority) - ticketPriorityRank(b.priority)
        );
      });
  }

  get hasFilters(): boolean {
    return Boolean(
      this.search.trim() ||
      this.priorityFilter ||
      this.args.queueName ||
      this.lens !== 'open',
    );
  }

  get isZeroData(): boolean {
    return this.all.length === 0;
  }

  /**
   * Skeletons are for a list that has nothing to show, not for one that is
   * refreshing.
   *
   * A live query reports `isLoading` on every REVALIDATION, not just the
   * first fetch — and saving any ticket reindexes it, which invalidates the
   * query. So linking a customer on one ticket threw away all six rows and
   * replaced them with grey bars for a second, as if the queue had emptied.
   * The rows on screen were still correct the whole time.
   *
   * Show what we have and mark it busy; only fall back to skeletons when
   * there is genuinely nothing behind them.
   */
  get showSkeleton(): boolean {
    return Boolean(this.args.isLoading) && this.all.length === 0;
  }

  get isRefreshing(): boolean {
    return Boolean(this.args.isLoading) && this.all.length > 0;
  }

  // ── Bulk actions ────────────────────────────────────────────────────────
  //
  // A shift ends with a dozen resolved tickets to close and a handful of
  // unclaimed ones to route. One at a time that is a dozen open-read-close
  // round trips through the detail pane, for an action that needs no reading
  // at all. The spec asks for exactly this (SERVICEDESK-SPEC.md:223).

  @tracked selected = new Set<string>();
  @tracked bulkBusy: string | undefined;
  @tracked bulkProblem: string | undefined;

  get selectedTickets(): Ticket[] {
    return this.rows.filter((t) => t.id && this.selected.has(t.id));
  }

  get hasSelection(): boolean {
    return this.selectedTickets.length > 0;
  }

  get allSelected(): boolean {
    return (
      this.rows.length > 0 && this.selectedTickets.length === this.rows.length
    );
  }

  isPicked = (ticket: Ticket) =>
    Boolean(ticket.id && this.selected.has(ticket.id));

  togglePick = (ticket: Ticket) => {
    if (!ticket.id) {
      return;
    }
    // A new Set each time — mutating in place does not invalidate the getter.
    let next = new Set(this.selected);
    if (next.has(ticket.id)) {
      next.delete(ticket.id);
    } else {
      next.add(ticket.id);
    }
    this.selected = next;
  };

  toggleAll = (_event?: Event) => {
    this.selected = this.allSelected
      ? new Set()
      : new Set(this.rows.map((t) => t.id).filter(Boolean) as string[]);
  };

  clearSelection = (_event?: Event) => {
    this.selected = new Set();
    this.bulkProblem = undefined;
  };

  private get commandContext() {
    return this.args.context?.commandContext;
  }

  /**
   * Runs the same commands the single-ticket path runs — no bulk variant.
   *
   * Sequential, not parallel: each transition writes and reindexes, and a
   * dozen concurrent writes to the same realm is how the last one wins.
   * Failures are collected rather than thrown, because "three of twelve
   * could not close" is the useful answer; aborting on the first leaves the
   * user unable to tell which ones went through.
   */
  private async runBulk(label: string, run: (t: Ticket) => Promise<unknown>) {
    if (!this.commandContext) {
      this.bulkProblem = 'Actions are unavailable in this view.';
      return;
    }
    let targets = this.selectedTickets;
    this.bulkBusy = label;
    this.bulkProblem = undefined;
    let failed: string[] = [];
    for (let ticket of targets) {
      try {
        await run(ticket);
      } catch (error: any) {
        failed.push(`${ticket.reference || ticket.subject || 'a ticket'}`);
      }
    }
    this.bulkBusy = undefined;
    this.selected = new Set();
    if (failed.length) {
      this.bulkProblem = `${targets.length - failed.length} of ${
        targets.length
      } done. Not ${label.toLowerCase()}: ${failed.join(', ')}.`;
    }
  }

  bulkClose = async (_event?: Event) => {
    await this.runBulk('Closed', (ticket) =>
      new TransitionTicketStatusCommand(this.commandContext!).execute({
        ticket,
        toStatus: 'Closed',
      } as any),
    );
  };

  bulkResolve = async (_event?: Event) => {
    await this.runBulk('Resolved', (ticket) =>
      new TransitionTicketStatusCommand(this.commandContext!).execute({
        ticket,
        toStatus: 'Resolved',
      } as any),
    );
  };

  /**
   * There is deliberately NO bulk delete here.
   *
   * `cardCrudFunctions.deleteCard` is typed `(cardOrId) => Promise<void>`,
   * which reads as "deletes the card". It does not: the host implementation
   * only records the card as the pending deletion target and opens its OWN
   * confirmation modal, then resolves. So a loop over N tickets overwrites
   * that single target N times, shows one modal, and deletes exactly one —
   * while every iteration resolves successfully, so nothing reports a
   * failure. That is what "delete 2, one disappears" was.
   *
   * There is no API a card can call to delete more than one record: the
   * atomic-operations tool declares a `remove` op type but no handler
   * implements it. Rather than ship a control that can only ever do a
   * fraction of what its label says, the action is not offered. Deleting is
   * one ticket at a time, from the workspace, where the host's own confirm is
   * the second step.
   *
   * If this becomes a real requirement it needs a platform change, not a
   * workaround here.
   */
  bulkAssign = async (_event?: Event) => {
    await this.runBulk('Assigned', (ticket) =>
      new AutoAssignTicketCommand(this.commandContext!).execute({
        ticket,
      } as any),
    );
  };

  hueOf = (ticket: Ticket) => statusHue(TicketStatusField, ticket.status);

  priorityHueOf = (ticket: Ticket) =>
    priorityOption(TicketPriorityField, ticket.priority)?.hue ?? 'slate';

  // Split across two lines rather than one long one: at a fixed 400px the
  // whole point is that every field stays inside one glance, and a single
  // joined string just truncates.
  contextOf = (ticket: Ticket) =>
    [ticket.customerName, ticket.customerCompany].filter(Boolean).join(' · ');

  secondaryOf = (ticket: Ticket) =>
    [
      ticket.categoryName,
      ticket.queueName,
      ticket.assigneeName,
      ticket.ageLabel,
    ]
      .filter(Boolean)
      .join(' · ');

  <template>
    <section
      class='qv'
      aria-label='Ticket queue'
      tabindex='-1'
      {{on 'keydown' this.handleKey}}
      ...attributes
    >
      <header class='qv-head'>
        <h2>Tickets · {{this.lensLabel}}</h2>
        <span class='mono'>{{this.rows.length}} rows</span>
      </header>

      <div class='qtools'>
        <LayoutControl
          @label='Ticket filters'
          @controlHeight='1.625rem'
          as |lc|
        >
          <lc.Slot
            @id='search'
            @priority={{1}}
            @forms={{SEARCH_FORMS}}
            @label='Search'
          >
            <div class='sbox'><SearchInput
                class='qsearch'
                @controlId={{this.searchId}}
                @value={{this.search}}
                @onInput={{this.setSearch}}
                @placeholder='Subject, customer, company'
              /></div>
          </lc.Slot>
          <lc.Slot
            @id='queues'
            @priority={{2}}
            @forms={{QUEUE_FORMS}}
            @label='Queue'
            @menuItems={{this.queueChoices}}
          >
            <SegmentedControl
              @label='Filter by queue'
              @options={{this.queueOptions}}
              @value={{if @queueName @queueName ''}}
              @onValueChange={{this.setQueue}}
            />
          </lc.Slot>
          {{#if @onNew}}
            <lc.Slot
              @id='new'
              @priority={{0}}
              @pinned={{true}}
              @forms={{ADD_FORMS}}
              @label='New ticket'
            >
              <Button
                @icon={{PlusIcon}}
                @tone='primary'
                @appearance='accent'
                @size='s'
                @busy={{@creating}}
                {{on 'click' @onNew}}
              >
                New ticket
              </Button>
            </lc.Slot>
          {{/if}}
        </LayoutControl>
      </div>

      {{#if @error}}
        <Alert
          @tone='danger'
          @title='The queue could not load'
          style={{ALERT_STYLE.danger}}
        >{{@error}}</Alert>

      {{else if this.showSkeleton}}
        <ul class='rows' aria-busy='true' aria-label='Loading tickets'>
          {{#each (array 1 2 3 4 5) as |placeholder|}}
            <li class='row-wrap' data-key={{placeholder}}>
              <Skeleton @width='100%' @height='0.6rem' />
            </li>
          {{/each}}
        </ul>

      {{else if this.isZeroData}}
        <EmptyState
          @title='No tickets yet'
          @message={{if
            @zeroDataMessage
            @zeroDataMessage
            'The first message written to the support address lands here. You can also raise one by hand.'
          }}
          @texture={{false}}
          style={{COMPACT_EMPTY_STYLE}}
        />

      {{else if this.rows.length}}
        {{#if this.hasSelection}}
          <div class='bulk' role='group' aria-label='Bulk actions'>
            <span class='bulk-n'>{{this.selectedTickets.length}} selected</span>
            <Button
              @tone='neutral'
              @appearance='outlined'
              @size='xs'
              @busy={{if (eq this.bulkBusy 'Assigned') true false}}
              @disabled={{if this.bulkBusy true false}}
              {{on 'click' this.bulkAssign}}
            >Auto-assign</Button>
            <Button
              @tone='neutral'
              @appearance='outlined'
              @size='xs'
              @busy={{if (eq this.bulkBusy 'Resolved') true false}}
              @disabled={{if this.bulkBusy true false}}
              {{on 'click' this.bulkResolve}}
            >Resolve</Button>
            <Button
              @tone='neutral'
              @appearance='outlined'
              @size='xs'
              @busy={{if (eq this.bulkBusy 'Closed') true false}}
              @disabled={{if this.bulkBusy true false}}
              {{on 'click' this.bulkClose}}
            >Close</Button>
            <span class='bulk-grow'></span>
            <Button
              @tone='neutral'
              @appearance='plain'
              @size='xs'
              {{on 'click' this.clearSelection}}
            >Clear</Button>
          </div>
        {{/if}}
        {{#if this.bulkProblem}}
          <p class='bulk-bad' role='alert'>{{this.bulkProblem}}</p>
        {{/if}}
        <div class='cols cap' aria-hidden='true'>
          <span></span><span>Ticket</span><span>Customer</span><span
            class='hide-s'
          >Priority</span><span class='hide-s'>Queue</span><span
            class='right'
          >Time left</span>
        </div>
        <ul
          class='rows {{if this.isRefreshing "rows-busy"}}'
          aria-busy={{if this.isRefreshing 'true' 'false'}}
        >
          {{#each this.rows key='id' as |ticket|}}
            <li class='row-wrap {{if (this.isSelected ticket) "row-on"}}'>
              <Checkbox
                class='pick'
                @checked={{this.isPicked ticket}}
                @onCheckedChange={{fn this.togglePick ticket}}
              ><span class='sr-only'>Select {{ticket.subject}}</span></Checkbox>
              <button
                type='button'
                class='row'
                data-ticket-id={{ticket.id}}
                aria-current={{if (this.isSelected ticket) 'true' 'false'}}
                {{on 'click' (fn this.open ticket)}}
              >
                <span class='c-ticket'>
                  <span class='mono dim'>{{ticket.reference}}</span>
                  <b class='ell'>{{ticket.subject}}</b>
                </span>
                <span class='c-cust'>
                  {{#if ticket.customerName}}
                    <Avatar @name={{ticket.customerName}} @size={{18}} />
                  {{/if}}
                  <b class='ell name'>{{ticket.customerName}}</b>
                  <span class='dim ell hide-m'>{{ticket.customerCompany}}</span>
                </span>
                <span class='c-pri hide-s'>
                  <Chip
                    @appearance='plain'
                    @tone={{this.priorityTone ticket}}
                  >{{this.priorityText ticket}}</Chip>
                </span>
                <span class='c-queue ell hide-s'>{{ticket.queueName}}</span>
                <span class='c-time'>
                  <SlaTimerBadge
                    @facts={{ticket.governingTimer}}
                    @live={{true}}
                    @plain={{true}}
                  />
                </span>
              </button>
            </li>
          {{/each}}
        </ul>
        <p class='count mono'>{{this.rows.length}}
          shown ·
          {{this.all.length}}
          in the realm · J / K to move</p>

      {{else}}
        {{#if this.hasFilters}}
          <EmptyState
            @title='Nothing matches these filters'
            @texture={{false}}
            style={{COMPACT_EMPTY_STYLE}}
          >
            <:default>There are
              {{this.all.length}}
              tickets in the realm. Widen the filter to see them.</:default>
            <:action>
              <Button
                @tone='neutral'
                @appearance='outlined'
                @size='xs'
                {{on 'click' this.clearFilters}}
              >Clear filters</Button>
            </:action>
          </EmptyState>
        {{else}}
          <EmptyState
            @title='This queue is clear'
            @message='Nothing is waiting.'
            @texture={{false}}
            style={{COMPACT_EMPTY_STYLE}}
          />
        {{/if}}
      {{/if}}
    </section>

    <style scoped>
      .qv {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        color: var(--foreground);
      }
      .qv-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs) 0;
      }
      h2 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
      }
      .dim {
        color: var(--muted-foreground);
      }
      .cap {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .ell {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .right {
        text-align: end;
      }
      .sbox {
        inline-size: 16rem;
        max-inline-size: 100%;
      }
      .qtools {
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
      }
      .cols,
      .row-wrap {
        display: grid;
        grid-template-columns:
          1.75rem minmax(0, 2.2fr) minmax(0, 1.6fr)
          7rem 7rem 6rem;
        align-items: center;
        column-gap: var(--boxel-sp-xs);
      }
      .cols {
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs) var(--boxel-sp-4xs) 0;
        border-block-start: 1px solid var(--border);
        border-block-end: 1px solid var(--border);
      }
      .rows {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .row-wrap {
        block-size: 1.75rem;
        border-block-end: 1px solid var(--border);
      }
      .row-wrap:hover,
      .row-on {
        background: var(--muted);
      }
      .pick {
        display: grid;
        place-items: center;
      }
      .row {
        all: unset;
        cursor: pointer;
        display: grid;
        grid-column: 2 / -1;
        grid-template-columns: subgrid;
        align-items: center;
        column-gap: var(--boxel-sp-xs);
        block-size: 100%;
        min-width: 0;
        padding-inline-end: var(--boxel-sp-xs);
      }
      .row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -2px;
      }
      .c-ticket,
      .c-cust {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-2xs);
        min-width: 0;
      }
      .c-cust .name {
        flex: 0 1 auto;
      }
      .c-cust .dim {
        flex: 1 1 0;
      }
      .c-ticket b {
        font-weight: 700;
      }
      .c-time {
        display: flex;
        justify-content: flex-end;
      }
      .bulk {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-2xs);
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        border-block-start: 1px solid var(--border);
      }
      .bulk-grow {
        flex: 1;
      }
      .bulk-n {
        font-weight: 600;
      }
      .bulk-bad {
        margin: 0;
        padding: 0 var(--boxel-sp-xs);
        color: var(--destructive-ink);
      }
      .count {
        margin: 0;
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
      .rows-busy {
        opacity: 0.6;
      }
      .sr-only {
        position: absolute;
        inline-size: 1px;
        block-size: 1px;
        overflow: hidden;
        clip-path: inset(50%);
      }
      @container (width <= 44rem) {
        .cols,
        .row-wrap {
          grid-template-columns: 1.75rem minmax(0, 1.6fr) minmax(0, 1fr) 5.5rem;
        }
        .hide-s {
          display: none;
        }
      }
      @container (width <= 30rem) {
        .hide-m {
          display: none;
        }
      }
    </style>
  </template>
}

export default QueueView;
