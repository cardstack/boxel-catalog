import { Component, realmURL, type CardDef } from '@cardstack/base/card-api';
import {
  identifyCard,
  type getCards,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Table } from '@cardstack/pretui/components/table';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
} from '@cardstack/pretui/components/sidebar';
import PlusIcon from '@cardstack/boxel-icons/plus';
import LayoutIcon from '@cardstack/boxel-icons/layout-dashboard';
import UsersIcon from '@cardstack/boxel-icons/users';
import CalendarIcon from '@cardstack/boxel-icons/calendar';
import ListIcon from '@cardstack/boxel-icons/list-checks';
import ChevronLeftIcon from '@cardstack/boxel-icons/chevron-left';
import ChevronRightIcon from '@cardstack/boxel-icons/chevron-right';

import { Booking } from '../events/booking';
import ConfirmBookingCommand from '../events/confirm-booking';
import { Survey } from '../survey/survey';
import { SurveyResponse } from '../survey/survey-response';
import { PointsTransaction } from '../loyalty/loyalty-account';
import { tierOption } from '../loyalty/loyalty-tier-field';
import { Member, MemberTierField } from './member';
import { Match } from './match';
import RecordAttendanceCommand from './commands/record-attendance-command';
import type { ClubMembership } from './club-membership';

type TabId = 'dashboard' | 'members' | 'fixtures' | 'operations';
type Tone = 'neutral' | 'ok' | 'warn' | 'bad' | 'info';

const TABS: Record<TabId, { label: string; sub: string; noun: string }> = {
  dashboard: {
    label: 'Dashboard',
    sub: 'Membership, loyalty points and match-day ticketing for the season',
    noun: 'bookings',
  },
  members: {
    label: 'Members',
    sub: 'The ledger of members, their tiers and loyalty balances',
    noun: 'name, number, tier',
  },
  fixtures: {
    label: 'Fixtures',
    sub: 'The season calendar and what each fixture has sold',
    noun: 'fixtures',
  },
  operations: {
    label: 'Operations',
    sub: 'Every booking, its payment state, and match-day surveys',
    noun: 'bookings',
  },
};

// Highest rung first, from the member ladder's own rank order.
const TIERS = MemberTierField.tierOptions.map((o) => o.value).reverse();
const TIER_TONE: Record<string, Tone> = { Gold: 'info', Legend: 'info' };
const EXPIRY_WINDOW_DAYS = 120;
const DAY_MS = 24 * 60 * 60 * 1000;
const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const SEARCH_FORMS = [
  { name: 'full', minWidth: 14 },
  { name: 'menu', minWidth: 0 },
];
const FILTER_FORMS = [
  { name: 'full', minWidth: 12 },
  { name: 'menu', minWidth: 0 },
];
const PRIMARY_FORMS = [{ name: 'full', minWidth: 9 }];

const num = (n: number) => new Intl.NumberFormat('en-GB').format(n);
const plural = (n: number, one: string, many = `${one}s`) =>
  `${n} ${n === 1 ? one : many}`;
const MONTHS = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const fmt = (
  at: string | Date | undefined,
  opts: Intl.DateTimeFormatOptions,
) => (at ? new Date(at).toLocaleDateString('en-GB', opts) : '—');
const dayMonth = (at?: string | Date) =>
  at ? `${new Date(at).getDate()} ${MONTHS[new Date(at).getMonth()]}` : '—';
const dayMonthYear = (at?: string | Date) =>
  at ? `${dayMonth(at)} ${new Date(at).getFullYear()}` : '—';
const time = (at: string | Date | undefined) =>
  at
    ? new Date(at).toLocaleTimeString('en-GB', {
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
const sameDay = (a: Date, b: Date) =>
  a.getFullYear() === b.getFullYear() &&
  a.getMonth() === b.getMonth() &&
  a.getDate() === b.getDate();
const fixtureName = (m?: Match) => m?.opponent?.trim() || m?.cardTitle || '—';
const holderName = (b: Booking) => b.holder?.cardTitle ?? '—';
const memberName = (m: Member) => m.holder?.cardTitle ?? m.cardTitle ?? '—';

interface StatTile {
  label: string;
  value: string;
  hint: string;
  tone: Tone;
}
interface Attention {
  id: string;
  text: string;
  tone: Tone;
  go: () => void;
}
interface CalendarDay {
  key: string;
  day: number;
  label: string;
  outside: boolean;
  matches: Match[];
}

export class ClubConsole extends Component<typeof ClubMembership> {
  @tracked activeTab: TabId = 'dashboard';
  @tracked searchText = '';
  @tracked bookingFilter = 'all';
  @tracked fixtureFilter = 'all';
  @tracked selectedMemberId: string | undefined;
  @tracked monthOffset = 0;
  @tracked actionProblem: string | undefined;
  @tracked busyId: string | undefined;
  @tracked lastAward: string | undefined;

  private memberQuery: ReturnType<getCards> | undefined;
  private matchQuery: ReturnType<getCards> | undefined;
  private bookingQuery: ReturnType<getCards> | undefined;
  private transactionQuery: ReturnType<getCards> | undefined;
  private surveyQuery: ReturnType<getCards> | undefined;
  private responseQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let realms = () => (this.realm ? [this.realm] : []);
    let query = (cardClass: typeof CardDef) =>
      this.args.context?.getCards(
        this,
        () => {
          if (!this.isInteractive) {
            return undefined;
          }
          let ref = identifyCard(cardClass);
          return ref ? { filter: { type: ref } } : undefined;
        },
        realms,
        { isLive: true },
      );
    this.memberQuery = query(Member);
    this.matchQuery = query(Match);
    this.bookingQuery = query(Booking);
    this.transactionQuery = query(PointsTransaction);
    this.surveyQuery = query(Survey);
    this.responseQuery = query(SurveyResponse);
  }

  get realm(): string | undefined {
    return this.args.model?.[realmURL]?.href;
  }

  // Prerender gets the static shell only; live queries need a viewer.
  get isInteractive(): boolean {
    return Boolean(this.args.viewCard);
  }

  get isLoading(): boolean {
    return [
      this.memberQuery,
      this.matchQuery,
      this.bookingQuery,
      this.transactionQuery,
      this.surveyQuery,
      this.responseQuery,
    ].some((q) => Boolean(q?.isLoading));
  }

  private all<T>(q: ReturnType<getCards> | undefined): T[] {
    return ((q?.instances ?? []) as T[]).filter(Boolean);
  }

  get members(): Member[] {
    return this.all<Member>(this.memberQuery).sort(
      (a, b) =>
        TIERS.indexOf(a.tier ?? '') - TIERS.indexOf(b.tier ?? '') ||
        new Date(a.memberSince ?? 0).getTime() -
          new Date(b.memberSince ?? 0).getTime(),
    );
  }
  get matches(): Match[] {
    return this.all<Match>(this.matchQuery).sort(
      (a, b) =>
        new Date(a.startsAt ?? 0).getTime() -
        new Date(b.startsAt ?? 0).getTime(),
    );
  }
  // The realm holds bookings for other events too; the club counts only its fixtures'.
  get bookings(): Booking[] {
    let fixtures = new Set(this.matches.map((m) => m.id));
    return this.all<Booking>(this.bookingQuery)
      .filter((b) => b.event?.id && fixtures.has(b.event.id))
      .sort((a, b) => (b.reference ?? '').localeCompare(a.reference ?? ''));
  }
  get transactions(): PointsTransaction[] {
    return this.all<PointsTransaction>(this.transactionQuery);
  }
  get surveys(): Survey[] {
    return this.all<Survey>(this.surveyQuery);
  }
  get responses(): SurveyResponse[] {
    return this.all<SurveyResponse>(this.responseQuery);
  }

  // ---- tabs + toolbar -----------------------------------------------------

  get tab() {
    return TABS[this.activeTab];
  }
  get eyebrow() {
    return 'Membership & Ticketing · Club';
  }

  get navItems() {
    return [
      {
        key: 'members' as TabId,
        label: 'Members',
        icon: UsersIcon,
        badge: String(this.members.length),
      },
      {
        key: 'fixtures' as TabId,
        label: 'Fixtures',
        icon: CalendarIcon,
        badge: String(this.matches.length),
      },
      {
        key: 'operations' as TabId,
        label: 'Operations',
        icon: ListIcon,
        badge: String(this.bookings.length),
      },
    ].map((i) => ({ ...i, active: i.key === this.activeTab }));
  }

  setTab = (id: TabId) => {
    this.activeTab = id;
    this.searchText = '';
  };
  setSearch = (value: string) => {
    this.searchText = value;
  };
  setFilter = (value: string) => {
    if (this.activeTab === 'fixtures') {
      this.fixtureFilter = value;
    } else {
      this.bookingFilter = value;
    }
  };

  get filterValue() {
    return this.activeTab === 'fixtures'
      ? this.fixtureFilter
      : this.bookingFilter;
  }

  get filterOptions() {
    if (this.activeTab === 'fixtures') {
      return [
        { value: 'all', label: 'All' },
        { value: 'Home', label: 'Home' },
        { value: 'Away', label: 'Away' },
      ];
    }
    if (this.activeTab === 'members') {
      return [];
    }
    return [
      { value: 'all', label: 'All' },
      { value: 'unpaid', label: `Unpaid ${this.unpaid.length}` },
    ];
  }

  get filterMenuItems() {
    return this.filterOptions.map((o) => ({
      label: o.label,
      value: o.value,
      group: 'filter',
      checked: o.value === this.filterValue,
      onSelect: () => this.setFilter(o.value),
    }));
  }

  get primary(): { label: string; run: () => void } {
    switch (this.activeTab) {
      case 'fixtures':
        return { label: 'New match', run: () => this.createOf(Match) };
      case 'operations':
        return { label: 'New booking', run: () => this.createOf(Booking) };
      default:
        return { label: 'New member', run: () => this.createOf(Member) };
    }
  }
  runPrimary = () => this.primary.run();
  newBooking = () => this.createOf(Booking);

  private matchesSearch(text: string) {
    let q = this.searchText.trim().toLowerCase();
    return !q || text.toLowerCase().includes(q);
  }

  // ---- bookings -----------------------------------------------------------

  get unpaid(): Booking[] {
    return this.bookings.filter((b) => b.paymentStatus !== 'Paid');
  }

  get visibleBookings(): Booking[] {
    let rows = this.bookingFilter === 'unpaid' ? this.unpaid : this.bookings;
    return rows.filter((b) =>
      this.matchesSearch(
        `${b.reference} ${holderName(b)} ${b.event?.cardTitle ?? ''}`,
      ),
    );
  }

  fixtureTag = (b: Booking) => {
    let m = b.event as Match | undefined;
    return m?.competition === 'Cup' ? 'Cup' : (m?.homeAway ?? '');
  };
  fixtureName = fixtureName;
  bookingFixture = (b: Booking) => fixtureName(b.event as Match | undefined);
  homeAway = (b: Booking) => (b.event as Match | undefined)?.homeAway ?? '—';
  get showsBookings() {
    return this.activeTab === 'dashboard' || this.activeTab === 'operations';
  }
  paymentTone = (b: Booking): Tone =>
    b.paymentStatus === 'Paid' ? 'ok' : 'warn';

  // ---- dashboard ----------------------------------------------------------

  get pointsLiability(): number {
    return this.members.reduce((sum, m) => sum + (m.pointsBalance ?? 0), 0);
  }

  // Checked-in over booked, for fixtures already played.
  get attendanceRate(): string {
    let now = Date.now();
    let played = this.bookings.filter(
      (b) =>
        b.event?.startsAt &&
        new Date(b.event.startsAt).getTime() < now &&
        b.rsvp !== 'Declined',
    );
    if (!played.length) {
      return '—';
    }
    let attended = played.filter((b) => b.checkedInAt).length;
    return `${Math.round((attended / played.length) * 100)}%`;
  }

  get stats(): StatTile[] {
    return [
      {
        label: 'Members',
        value: String(this.members.length),
        hint: 'across all tiers',
        tone: 'info',
      },
      {
        label: 'Points liability',
        value: num(this.pointsLiability),
        hint: 'redeemable balance',
        tone: 'neutral',
      },
      {
        label: 'Bookings',
        value: String(this.bookings.length),
        hint: 'all fixtures',
        tone: 'info',
      },
      {
        label: 'Unpaid',
        value: String(this.unpaid.length),
        hint: 'need chasing',
        tone: this.unpaid.length ? 'warn' : 'ok',
      },
      {
        label: 'Attendance',
        value: this.attendanceRate,
        hint: 'of played bookings',
        tone: 'ok',
      },
      {
        label: 'Survey responses',
        value: String(this.responses.length),
        hint: 'from match-day surveys',
        tone: 'neutral',
      },
    ];
  }

  // Positive grants that lapse inside the window, per account.
  expiringFor(accountId?: string): { points: number; on: Date } | undefined {
    let now = Date.now();
    let horizon = now + EXPIRY_WINDOW_DAYS * DAY_MS;
    let rows = this.transactions.filter((t) => {
      if ((accountId && t.account?.id !== accountId) || !t.expiresAt) {
        return false;
      }
      let at = new Date(t.expiresAt).getTime();
      return (t.amount ?? 0) > 0 && at > now && at <= horizon;
    });
    if (!rows.length) {
      return undefined;
    }
    return {
      points: rows.reduce((sum, t) => sum + (t.amount ?? 0), 0),
      on: new Date(
        Math.min(...rows.map((t) => new Date(t.expiresAt!).getTime())),
      ),
    };
  }

  get attention(): Attention[] {
    let out: Attention[] = [];
    if (this.unpaid.length) {
      out.push({
        id: 'unpaid',
        text: `${plural(this.unpaid.length, 'booking')} unpaid`,
        tone: 'bad',
        go: () => {
          this.bookingFilter = 'unpaid';
          this.setTab('operations');
        },
      });
    }
    let expiring = this.expiringFor();
    if (expiring) {
      out.push({
        id: 'expiring',
        text: `${num(expiring.points)} points expire ${dayMonth(expiring.on)}`,
        tone: 'warn',
        go: () => this.setTab('members'),
      });
    }
    return out;
  }

  get nextMatch(): Match | undefined {
    let now = Date.now();
    return (
      this.matches.find(
        (m) => m.startsAt && new Date(m.startsAt).getTime() > now,
      ) ??
      this.matches.find((m) => m.status === 'Scheduled') ??
      this.matches[this.matches.length - 1]
    );
  }

  bookedFor = (match: Match): number =>
    (match.ticketsSold ?? 0) +
    this.bookings
      .filter((b) => b.event?.id === match.id)
      .reduce((sum, b) => sum + (b.quantity ?? 1), 0);

  bookedPct = (match: Match): number => {
    let total = match.capacity?.total;
    return total ? Math.min(100, (this.bookedFor(match) / total) * 100) : 0;
  };

  matchWhen = (match?: Match) =>
    match?.startsAt
      ? `${fmt(match.startsAt, { weekday: 'short' })} ${dayMonth(match.startsAt)}, ${time(match.startsAt)}`
      : '—';

  get tierRows() {
    return TIERS.map((tier) => ({
      tier,
      count: this.members.filter((m) => m.tier === tier).length,
    }))
      .filter((r) => r.count > 0)
      .sort((a, b) => b.count - a.count);
  }

  // ---- members ------------------------------------------------------------

  get visibleMembers(): Member[] {
    return this.members.filter((m) =>
      this.matchesSearch(`${memberName(m)} ${m.memberNumber} ${m.tier}`),
    );
  }

  get selectedMember(): Member | undefined {
    return (
      this.members.find((m) => m.id === this.selectedMemberId) ??
      this.visibleMembers[0]
    );
  }

  pickMember = (member: Member) => {
    this.selectedMemberId = member.id;
    this.lastAward = undefined;
  };

  memberName = memberName;
  memberStatusTone = (status?: string | null): Tone =>
    status === 'Active' ? 'ok' : status === 'Lapsed' ? 'warn' : 'neutral';
  tierTone = (tier?: string): Tone => TIER_TONE[tier ?? ''] ?? 'neutral';

  get selectedTierMeaning(): string | undefined {
    let t = tierOption(MemberTierField, this.selectedMember?.tier);
    if (!t) {
      return undefined;
    }
    let rate = t.multiplier ? ` · earns ${t.multiplier}× points` : '';
    return `${t.meaning ?? t.value}${rate}. Legend is invitation only.`;
  }

  get selectedStats(): StatTile[] {
    let m = this.selectedMember;
    if (!m) {
      return [];
    }
    return [
      {
        label: 'Tier',
        value: m.tier ?? '—',
        hint: m.tierSince ? `since ${dayMonthYear(m.tierSince)}` : '—',
        tone: this.tierTone(m.tier),
      },
      {
        label: 'Points balance',
        value: num(m.pointsBalance ?? 0),
        hint: 'redeemable',
        tone: 'neutral',
      },
      {
        label: 'Lifetime points',
        value: num(m.lifetimePoints ?? 0),
        hint: 'earned',
        tone: 'neutral',
      },
      {
        label: 'Member since',
        value: m.memberSince
          ? String(new Date(m.memberSince).getFullYear())
          : '—',
        hint: dayMonthYear(m.memberSince),
        tone: 'neutral',
      },
    ];
  }

  get selectedExpiring() {
    if (!this.selectedMember?.id) {
      return '';
    }
    let e = this.expiringFor(this.selectedMember.id);
    return e ? `${num(e.points)} points expire on ${dayMonthYear(e.on)}` : '';
  }

  get selectedActivity(): PointsTransaction[] {
    let id = this.selectedMember?.id;
    return this.transactions
      .filter((t) => id && t.account?.id === id)
      .sort(
        (a, b) =>
          new Date(b.occurredAt ?? 0).getTime() -
          new Date(a.occurredAt ?? 0).getTime(),
      )
      .slice(0, 8);
  }

  get selectedBookings(): Booking[] {
    let holder = this.selectedMember?.holder?.id;
    return holder ? this.bookings.filter((b) => b.holder?.id === holder) : [];
  }

  signed = (n?: number) => `${(n ?? 0) > 0 ? '+' : ''}${num(n ?? 0)}`;
  amountTone = (n?: number) => ((n ?? 0) < 0 ? 'bad' : 'ok');
  dayMonth = dayMonth;
  dayMonthYear = dayMonthYear;
  tickets = (b: Booking) => plural(b.quantity ?? 1, 'ticket');

  needsConfirm = (b: Booking) =>
    !b.checkedInAt && b.rsvp !== 'Going' && b.rsvp !== 'Declined';
  canCheckIn = (b: Booking) => !b.checkedInAt && b.rsvp !== 'Declined';

  confirm = async (booking: Booking) => {
    let context = this.args.context?.commandContext;
    if (!context || !this.realm) {
      this.actionProblem = 'This console is not ready to confirm bookings.';
      return;
    }
    await this.run(booking.id, () =>
      new ConfirmBookingCommand(context!).execute({
        booking,
        realm: this.realm!,
      }),
    );
  };

  checkIn = async (booking: Booking) => {
    let member = this.selectedMember;
    let context = this.args.context?.commandContext;
    if (!member || !context || !this.realm) {
      this.actionProblem = 'This console is not ready to record attendance.';
      return;
    }
    await this.run(booking.id, async () => {
      let result = await new RecordAttendanceCommand(context!).execute({
        booking,
        member,
        realm: this.realm!,
      });
      if (result?.pointsAwarded) {
        this.lastAward = `+${num(result.pointsAwarded)} points for ${memberName(member)}`;
      }
    });
  };

  private async run(id: string, work: () => Promise<unknown>) {
    this.busyId = id;
    this.actionProblem = undefined;
    try {
      await work();
    } catch (error: any) {
      this.actionProblem = error?.message ?? String(error);
    } finally {
      this.busyId = undefined;
    }
  }

  // ---- fixtures -----------------------------------------------------------

  get visibleMatches(): Match[] {
    return this.matches.filter(
      (m) =>
        (this.fixtureFilter === 'all' || m.homeAway === this.fixtureFilter) &&
        this.matchesSearch(`${m.cardTitle} ${m.competition} ${m.homeAway}`),
    );
  }

  private get baseMonth(): Date {
    let at = this.nextMatch?.startsAt
      ? new Date(this.nextMatch.startsAt)
      : new Date();
    return new Date(at.getFullYear(), at.getMonth() + this.monthOffset, 1);
  }

  get monthLabel(): string {
    return this.baseMonth.toLocaleDateString('en-GB', {
      month: 'long',
      year: 'numeric',
    });
  }

  // Monday-first weeks covering the month.
  get calendarWeeks(): CalendarDay[][] {
    let first = this.baseMonth;
    let start = new Date(first);
    start.setDate(1 - ((first.getDay() + 6) % 7));
    let weeks: CalendarDay[][] = [];
    let cursor = new Date(start);
    do {
      let week: CalendarDay[] = [];
      for (let i = 0; i < 7; i++) {
        let day = new Date(cursor);
        week.push({
          key: day.toISOString(),
          day: day.getDate(),
          label: day.toLocaleDateString('en-GB', { dateStyle: 'full' }),
          outside: day.getMonth() !== first.getMonth(),
          matches: this.visibleMatches.filter(
            (m) => m.startsAt && sameDay(new Date(m.startsAt), day),
          ),
        });
        cursor.setDate(cursor.getDate() + 1);
      }
      weeks.push(week);
    } while (cursor.getMonth() === first.getMonth());
    return weeks;
  }

  weekdays = WEEKDAYS;
  prevMonth = () => this.monthOffset--;
  nextMonth = () => this.monthOffset++;
  kindTone = (m: Match): Tone => (m.homeAway === 'Away' ? 'warn' : 'info');
  statusTone = (m: Match): Tone =>
    m.status === 'Completed'
      ? 'ok'
      : m.status === 'Cancelled'
        ? 'bad'
        : 'neutral';
  booked = (m: Match) => num(this.bookedFor(m));
  soldOf = (m: Match) =>
    `${num(m.ticketsSold ?? 0)} / ${num(m.capacity?.total ?? 0)} tickets`;
  soldPct = (m: Match) =>
    m.capacity?.total
      ? Math.min(100, ((m.ticketsSold ?? 0) / m.capacity.total) * 100)
      : 0;

  // ---- operations ---------------------------------------------------------

  responsesFor = (survey: Survey) =>
    plural(
      this.responses.filter((r) => r.survey?.id === survey.id).length,
      'response',
    );

  // ---- shared -------------------------------------------------------------

  open = (card: CardDef | undefined) => {
    if (card) {
      this.args.viewCard?.(card, 'isolated');
    }
  };

  private async createOf(cardClass: typeof CardDef) {
    let ref = identifyCard(cardClass) as ResolvedCodeRef | undefined;
    if (!ref || !this.args.createCard || !this.realm) {
      this.actionProblem =
        'Save this console in a realm before creating records from it.';
      return;
    }
    this.actionProblem = undefined;
    try {
      await this.args.createCard(ref, undefined, {
        realmURL: new URL(this.realm),
      });
    } catch (error: any) {
      this.actionProblem = error?.message ?? String(error);
    }
  }

  SEARCH_FORMS = SEARCH_FORMS;
  FILTER_FORMS = FILTER_FORMS;
  PRIMARY_FORMS = PRIMARY_FORMS;
  PlusIcon = PlusIcon;

  <template>
    <div class='app'>
      {{#if this.isInteractive}}
        <Sidebar
          class='shell'
          @label='Club Membership'
          @collapsible='rail'
          @railBreakpoint={{1100}}
          @mobileBreakpoint={{720}}
          @bordered={{true}}
          @scroll='content'
          @resizable={{true}}
        >
          <:header as |bar|>
            <div class='brand'>
              <span class='brand-mark' aria-hidden='true'>NF</span>
              {{#unless bar.collapsed}}
                <span class='brand-name'>{{if
                    @model.clubName
                    @model.clubName
                    'Club Membership'
                  }}<small>Membership &amp; Ticketing</small></span>
              {{/unless}}
            </div>
          </:header>
          <:nav as |bar|>
            <SidebarGroup @label='Overview' @hideLabel={{true}}>
              <SidebarItem
                @label='Dashboard'
                @active={{eq this.activeTab 'dashboard'}}
                @collapsed={{bar.collapsed}}
                @onClick={{fn this.setTab 'dashboard'}}
              >
                <:icon><LayoutIcon aria-hidden='true' /></:icon>
              </SidebarItem>
            </SidebarGroup>
            <SidebarGroup @label='Club' @hideLabel={{bar.collapsed}}>
              {{#each this.navItems key='key' as |item|}}
                <SidebarItem
                  @label={{item.label}}
                  @badge={{unless bar.collapsed item.badge}}
                  @active={{item.active}}
                  @collapsed={{bar.collapsed}}
                  @onClick={{fn this.setTab item.key}}
                >
                  <:icon><item.icon aria-hidden='true' /></:icon>
                </SidebarItem>
              {{/each}}
            </SidebarGroup>
          </:nav>
          <:default>
            <main class='main'>
              <header class='head'>
                <p class='cap'>{{this.eyebrow}}</p>
                <h1>{{this.tab.label}}</h1>
                <p class='meta'>{{this.tab.sub}}</p>
              </header>

              <LayoutControl @label='{{this.tab.label}} toolbar' as |lc|>
                <lc.Slot
                  @id='search'
                  @priority={{2}}
                  @forms={{this.SEARCH_FORMS}}
                  @label='Search'
                >
                  <label class='search'>
                    <VisuallyHidden>Search {{this.tab.noun}}</VisuallyHidden>
                    <SearchInput
                      @placeholder='Search {{this.tab.noun}}…'
                      @value={{this.searchText}}
                      @onInput={{this.setSearch}}
                    />
                  </label>
                </lc.Slot>
                {{#if this.filterOptions.length}}
                  <lc.Slot
                    @id='filter'
                    @priority={{1}}
                    @forms={{this.FILTER_FORMS}}
                    @label='Filter'
                    @menuItems={{this.filterMenuItems}}
                  >
                    <SegmentedControl
                      @label='Filter'
                      @options={{this.filterOptions}}
                      @value={{this.filterValue}}
                      @onValueChange={{this.setFilter}}
                    />
                  </lc.Slot>
                {{/if}}
                <span class='grow'></span>
                <lc.Slot
                  @id='add'
                  @priority={{0}}
                  @pinned={{true}}
                  @forms={{this.PRIMARY_FORMS}}
                  @label={{this.primary.label}}
                >
                  <Button
                    @icon={{this.PlusIcon}}
                    {{on 'click' this.runPrimary}}
                  >{{this.primary.label}}</Button>
                </lc.Slot>
              </LayoutControl>

              {{#if this.actionProblem}}
                <Alert @tone='danger'>{{this.actionProblem}}</Alert>
              {{/if}}

              {{#if (eq this.activeTab 'dashboard')}}
                <section class='strip n6' aria-label='Key numbers'>
                  {{#each this.stats as |s|}}
                    <div class='stat'>
                      <span class='st'><span class='dot {{s.tone}}'></span><span
                          class='cap'
                        >{{s.label}}</span></span>
                      <span class='num'>{{s.value}}</span>
                      <span class='meta'>{{s.hint}}</span>
                    </div>
                  {{/each}}
                </section>

                {{#if this.attention.length}}
                  <section class='block' aria-labelledby='h-attn'>
                    <div class='sh'>
                      <h2 id='h-attn'>Needs attention</h2>
                      <span class='meta'>{{this.attention.length}}</span>
                    </div>
                    <ul class='ul'>
                      {{#each this.attention key='id' as |a|}}
                        <li class='row'>
                          <span class='st strong'><span
                              class='dot {{a.tone}}'
                            ></span>{{a.text}}</span>
                          <Button
                            class='end-auto'
                            @appearance='plain'
                            @size='s'
                            {{on 'click' a.go}}
                          >Review</Button>
                        </li>
                      {{/each}}
                    </ul>
                  </section>
                {{/if}}

              {{else if (eq this.activeTab 'members')}}
                <div class='cols members'>
                  <section class='block' aria-labelledby='h-members'>
                    <div class='sh'>
                      <h2 id='h-members'>Members</h2>
                      <span class='meta'>{{this.visibleMembers.length}}</span>
                    </div>
                    {{#if this.visibleMembers.length}}
                      <ul class='ul'>
                        {{#each this.visibleMembers key='id' as |m|}}
                          <li>
                            <button
                              type='button'
                              class='open row member-row'
                              aria-pressed={{if
                                (eq m.id this.selectedMember.id)
                                'true'
                                'false'
                              }}
                              {{on 'click' (fn this.pickMember m)}}
                            >
                              <span class='who'><Avatar
                                  @name={{this.memberName m}}
                                  @size={{16}}
                                /><span class='nm'>{{this.memberName
                                    m
                                  }}</span></span>
                              <span class='mono meta'>{{m.memberNumber}}</span>
                              <span class='st strong'><span
                                  class='dot {{this.tierTone m.tier}}'
                                ></span>{{m.tier}}</span>
                            </button>
                          </li>
                        {{/each}}
                      </ul>
                    {{else}}
                      <div class='es'><EmptyState
                          @size='s'
                          @title={{if
                            this.isLoading
                            'Loading…'
                            (if
                              this.searchText
                              'No matching members'
                              'No members yet'
                            )
                          }}
                        /></div>
                    {{/if}}
                  </section>

                  {{#if this.selectedMember}}
                    <div class='detail'>
                      <section class='block' aria-labelledby='h-member'>
                        <div class='sh'>
                          <span class='who'><Avatar
                              @name={{this.memberName this.selectedMember}}
                              @size={{20}}
                            /><span class='stack'>
                              <h2 id='h-member'>{{this.memberName
                                  this.selectedMember
                                }}</h2>
                              <span
                                class='mono meta'
                              >{{this.selectedMember.memberNumber}}</span>
                            </span></span>
                          <span class='st strong end-auto'><span
                              class='dot
                                {{this.memberStatusTone
                                  this.selectedMember.status
                                }}'
                            ></span>{{this.selectedMember.status}}</span>
                          <Button
                            @appearance='plain'
                            @size='s'
                            {{on 'click' (fn this.open this.selectedMember)}}
                          >Open card</Button>
                        </div>
                        <div class='strip inner n4'>
                          {{#each this.selectedStats as |s|}}
                            <div class='stat'>
                              <span class='st'><span
                                  class='dot {{s.tone}}'
                                ></span><span
                                  class='cap'
                                >{{s.label}}</span></span>
                              <span class='num'>{{s.value}}</span>
                              <span class='meta'>{{s.hint}}</span>
                            </div>
                          {{/each}}
                        </div>
                        {{#if this.selectedTierMeaning}}
                          <p class='row'>{{this.selectedTierMeaning}}</p>
                        {{/if}}
                        <div class='row'>
                          {{#if this.lastAward}}
                            <span class='st strong' role='status'><span
                                class='dot ok'
                              ></span>{{this.lastAward}}</span>
                          {{else if this.selectedExpiring}}
                            <span class='st strong'><span
                                class='dot warn'
                              ></span>{{this.selectedExpiring}}</span>
                          {{/if}}
                          <Button
                            class='end-auto'
                            @icon={{this.PlusIcon}}
                            @size='s'
                            {{on 'click' this.newBooking}}
                          >New booking</Button>
                        </div>
                      </section>

                      <section class='block' aria-labelledby='h-activity'>
                        <div class='sh'>
                          <h2 id='h-activity'>Recent activity</h2>
                          <span class='meta'>Points ledger</span>
                        </div>
                        {{#if this.selectedActivity.length}}
                          <ul class='ul'>
                            {{#each this.selectedActivity key='id' as |t|}}
                              <li class='row'>
                                <span
                                  class='mono when-l meta'
                                >{{this.dayMonthYear t.occurredAt}}</span>
                                <button
                                  type='button'
                                  class='open'
                                  {{on 'click' (fn this.open t)}}
                                ><span class='nm'>{{t.reason}}</span>
                                  <span class='meta'>·
                                    {{t.source}}</span></button>
                                <span
                                  class='mono end-auto amount
                                    {{this.amountTone t.amount}}'
                                >{{this.signed t.amount}}</span>
                              </li>
                            {{/each}}
                          </ul>
                        {{else}}
                          <div class='es'><EmptyState
                              @size='s'
                              @title='No points activity yet'
                            /></div>
                        {{/if}}
                      </section>

                      <section class='block' aria-labelledby='h-mbook'>
                        <div class='sh'>
                          <h2 id='h-mbook'>Bookings</h2>
                          <span
                            class='meta'
                          >{{this.selectedBookings.length}}</span>
                        </div>
                        {{#if this.selectedBookings.length}}
                          <ul class='ul'>
                            {{#each this.selectedBookings key='id' as |b|}}
                              <li class='row'>
                                <span class='mono when meta'>{{this.dayMonth
                                    b.event.startsAt
                                  }}</span>
                                <button
                                  type='button'
                                  class='open'
                                  {{on 'click' (fn this.open b)}}
                                ><span class='nm'>{{this.bookingFixture
                                      b
                                    }}</span>
                                  <span class='meta'>{{b.reference}}
                                    ·
                                    {{this.homeAway b}}
                                    ·
                                    {{this.tickets b}}</span></button>
                                <span class='end-auto'>
                                  {{#if b.checkedInAt}}
                                    <span class='st strong'><span
                                        class='dot ok'
                                      ></span>Attended</span>
                                  {{else if (this.needsConfirm b)}}
                                    <Button
                                      @appearance='outlined'
                                      @size='s'
                                      @busy={{eq this.busyId b.id}}
                                      {{on 'click' (fn this.confirm b)}}
                                    >Confirm</Button>
                                  {{else if (this.canCheckIn b)}}
                                    <Button
                                      @appearance='outlined'
                                      @size='s'
                                      @busy={{eq this.busyId b.id}}
                                      {{on 'click' (fn this.checkIn b)}}
                                    >Check in</Button>
                                  {{else}}
                                    <span class='st'><span
                                        class='dot'
                                      ></span>Declined</span>
                                  {{/if}}
                                </span>
                              </li>
                            {{/each}}
                          </ul>
                        {{else}}
                          <div class='es'><EmptyState
                              @size='s'
                              @title='No bookings for this member yet'
                            /></div>
                        {{/if}}
                      </section>
                    </div>
                  {{/if}}
                </div>
              {{else if (eq this.activeTab 'fixtures')}}
                <section class='block' aria-labelledby='h-month'>
                  <div class='sh'>
                    <h2 id='h-month'>{{this.monthLabel}}</h2>
                    <span class='st end-auto'><span
                        class='dot info'
                      ></span>Home</span>
                    <span class='st'><span class='dot warn'></span>Away</span>
                    <IconButton
                      @label='Previous month'
                      @icon={{ChevronLeftIcon}}
                      @appearance='outlined'
                      @size='s'
                      {{on 'click' this.prevMonth}}
                    />
                    <IconButton
                      @label='Next month'
                      @icon={{ChevronRightIcon}}
                      @appearance='outlined'
                      @size='s'
                      {{on 'click' this.nextMonth}}
                    />
                  </div>
                  <div class='tw cal-wrap'>
                    <table class='cal' aria-labelledby='h-month'>
                      <thead>
                        <tr>
                          {{#each this.weekdays as |d|}}
                            <th scope='col'>{{d}}</th>
                          {{/each}}
                        </tr>
                      </thead>
                      <tbody>
                        {{#each this.calendarWeeks as |week|}}
                          <tr>
                            {{#each week key='key' as |d|}}
                              <td class={{if d.outside 'outside'}}>
                                <span
                                  class='mono'
                                  aria-hidden='true'
                                >{{d.day}}</span><VisuallyHidden
                                >{{d.label}}</VisuallyHidden>
                                {{#each d.matches key='id' as |m|}}
                                  <button
                                    type='button'
                                    class='open st cal-ev'
                                    {{on 'click' (fn this.open m)}}
                                  ><span
                                      class='dot {{this.kindTone m}}'
                                    ></span><span class='nm'>{{this.fixtureName
                                        m
                                      }}</span></button>
                                {{/each}}
                              </td>
                            {{/each}}
                          </tr>
                        {{/each}}
                      </tbody>
                    </table>
                  </div>
                </section>

                <section class='block' aria-labelledby='h-fixtures'>
                  <div class='sh'>
                    <h2 id='h-fixtures'>Fixture list</h2>
                    <span class='meta'>{{plural
                        this.visibleMatches.length
                        'match'
                        'matches'
                      }}</span>
                  </div>
                  {{#if this.visibleMatches.length}}
                    <div class='tw'>
                      <Table @labelledBy='h-fixtures' @framed={{false}}>
                        <:head>
                          <tr>
                            <th scope='col' class='wide'>Fixture</th>
                            <th scope='col'>Kick-off</th>
                            <th scope='col'>Competition</th>
                            <th scope='col'>Venue</th>
                            <th scope='col' class='end'>Booked</th>
                            <th scope='col'>Status</th>
                          </tr>
                        </:head>
                        <:body>
                          {{#each this.visibleMatches key='id' as |m|}}
                            <tr>
                              <th scope='row' class='rh'>
                                <button
                                  type='button'
                                  class='open nm'
                                  {{on 'click' (fn this.open m)}}
                                >{{this.fixtureName m}}</button>
                              </th>
                              <td class='mono'>{{this.dayMonth m.startsAt}}</td>
                              <td>{{m.competition}}</td>
                              <td>{{m.homeAway}}</td>
                              <td class='end'><span class='booked'><span
                                    class='mono'
                                  >{{this.booked m}}</span><ProgressBar
                                    aria-label='{{this.fixtureName m}} booked'
                                    @value={{this.bookedPct m}}
                                    @max={{100}}
                                  /></span></td>
                              <td><span class='st strong'><span
                                    class='dot {{this.statusTone m}}'
                                  ></span>{{m.status}}</span></td>
                            </tr>
                          {{/each}}
                        </:body>
                      </Table>
                    </div>
                  {{else}}
                    <div class='es'><EmptyState
                        @size='s'
                        @title={{if this.isLoading 'Loading…' 'No fixtures'}}
                      /></div>
                  {{/if}}
                </section>
              {{/if}}
              {{#if this.showsBookings}}
                <div class='cols'>
                  {{#let 'h-bookings' as |hid|}}
                    <section class='block' aria-labelledby={{hid}}>
                      <div class='sh'>
                        <h2 id={{hid}}>Bookings</h2>
                        <span
                          class='meta'
                        >{{this.visibleBookings.length}}</span>
                      </div>
                      {{#if this.visibleBookings.length}}
                        <div class='tw'>
                          <Table @labelledBy={{hid}} @framed={{false}}>
                            <:head>
                              <tr>
                                <th scope='col'>Reference</th>
                                <th scope='col'>Holder</th>
                                <th scope='col'>Fixture</th>
                                <th scope='col' class='end'>Qty</th>
                                <th scope='col'>RSVP</th>
                                <th scope='col'>Payment</th>
                              </tr>
                            </:head>
                            <:body>
                              {{#each this.visibleBookings key='id' as |b|}}
                                <tr>
                                  <th scope='row' class='rh mono-cell'>
                                    <button
                                      type='button'
                                      class='open mono'
                                      {{on 'click' (fn this.open b)}}
                                    >{{b.reference}}</button>
                                  </th>
                                  <td><span class='who'><Avatar
                                        @name={{holderName b}}
                                        @size={{16}}
                                      /><span class='nm'>{{holderName
                                          b
                                        }}</span></span></td>
                                  <td><span class='nm'>{{this.bookingFixture
                                        b
                                      }}</span>
                                    <span class='meta'>·
                                      {{this.fixtureTag b}}</span></td>
                                  <td class='end'>{{b.quantity}}</td>
                                  <td>{{if b.rsvp b.rsvp '—'}}</td>
                                  <td><span class='st strong'><span
                                        class='dot {{this.paymentTone b}}'
                                      ></span>{{b.paymentStatus}}</span></td>
                                </tr>
                              {{/each}}
                            </:body>
                          </Table>
                        </div>
                      {{else}}
                        <div class='es'><EmptyState
                            @size='s'
                            @title={{if
                              this.isLoading
                              'Loading…'
                              (if
                                (eq this.bookingFilter 'unpaid')
                                'Nothing unpaid. The books are clean.'
                                'No bookings yet'
                              )
                            }}
                          /></div>
                      {{/if}}
                    </section>
                  {{/let}}
                  <aside class='side'>
                    {{#if (eq this.activeTab 'operations')}}
                      <section
                        class='block grow-block'
                        aria-labelledby='h-surveys'
                      >
                        <div class='sh'>
                          <h2 id='h-surveys'>Match-day surveys</h2>
                          <span class='meta'>{{this.surveys.length}}</span>
                        </div>
                        {{#if this.surveys.length}}
                          <ul class='ul'>
                            {{#each this.surveys key='id' as |s|}}
                              <li class='row'>
                                <button
                                  type='button'
                                  class='open nm'
                                  {{on 'click' (fn this.open s)}}
                                >{{s.cardTitle}}</button>
                                <span class='meta end-auto'>{{this.responsesFor
                                    s
                                  }}</span>
                              </li>
                            {{/each}}
                          </ul>
                        {{else}}
                          <div class='es'><EmptyState
                              @size='s'
                              @title={{if
                                this.isLoading
                                'Loading…'
                                'No surveys yet'
                              }}
                            /></div>
                        {{/if}}
                      </section>
                    {{else}}

                      <section class='block' aria-labelledby='h-next'>
                        <div class='sh'>
                          <h2 id='h-next'>Next fixture</h2>
                          {{#if this.nextMatch}}
                            <span class='st'><span
                                class='dot {{this.statusTone this.nextMatch}}'
                              ></span>{{this.nextMatch.status}}</span>
                          {{/if}}
                        </div>
                        {{#if this.nextMatch}}
                          <div class='row fixture'>
                            <span class='mono when'>{{this.dayMonth
                                this.nextMatch.startsAt
                              }}</span>
                            <span class='stack'>
                              <span class='nm'>{{this.fixtureName
                                  this.nextMatch
                                }}</span>
                              <span class='meta'>{{this.nextMatch.competition}}
                                ·
                                {{this.nextMatch.homeAway}}
                                ·
                                {{this.matchWhen this.nextMatch}}</span>
                            </span>
                          </div>
                          <div class='row sold'>
                            <span class='strong'>Ground sold</span>
                            <span class='mono end-auto'>{{this.soldOf
                                this.nextMatch
                              }}</span>
                            <ProgressBar
                              class='full'
                              aria-label='Ground sold'
                              @value={{this.soldPct this.nextMatch}}
                              @max={{100}}
                            />
                          </div>
                          <div class='pad'>
                            <Button
                              @appearance='outlined'
                              @size='s'
                              {{on 'click' (fn this.open this.nextMatch)}}
                            >Open fixture</Button>
                          </div>
                        {{else}}
                          <div class='es'><EmptyState
                              @size='s'
                              @title='No upcoming fixture'
                            /></div>
                        {{/if}}
                      </section>
                      <section
                        class='block grow-block'
                        aria-labelledby='h-tier'
                      >
                        <div class='sh'>
                          <h2 id='h-tier'>Membership by tier</h2>
                          <span class='meta'>{{plural
                              this.members.length
                              'member'
                            }}</span>
                        </div>
                        <ul class='ul'>
                          {{#each this.tierRows key='tier' as |r|}}
                            <li class='row tier-row'>
                              <span class='strong'>{{r.tier}}</span>
                              <ProgressBar
                                aria-label='{{r.tier}} members'
                                @value={{r.count}}
                                @max={{this.members.length}}
                              />
                              <span class='mono end'>{{r.count}}</span>
                            </li>
                          {{/each}}
                        </ul>
                      </section>

                    {{/if}}
                  </aside>
                </div>
              {{/if}}
            </main>
          </:default>
        </Sidebar>
      {{else}}
        <EmptyState
          @size='s'
          @title='Club Membership'
          @message='Open the app to manage members, fixtures and match-day bookings.'
        />
      {{/if}}
    </div>
    <style scoped>
      .app {
        container-type: inline-size;
        display: flex;
        block-size: 100%;
        min-block-size: 0;
        overflow: hidden;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.35;
        --control-height: 1.625rem;
        /* shortcut: Pret UI parts ignore --control-height until CS-14733 merges, then drop the two lines below. */
        --pretui-button-h: 1.625rem;
        --pretui-seg-h: 1.625rem;
      }
      .shell {
        flex: 1;
        block-size: 100%;
        min-block-size: 0;
      }
      .main {
        box-sizing: border-box;
        min-inline-size: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      p {
        margin: 0;
      }
      .cap,
      th {
        margin: 0;
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: 0.5625rem;
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .head {
        display: grid;
        gap: var(--boxel-sp-5xs);
      }
      h1 {
        margin: 0;
        font-family: var(--font-heading);
        font-weight: 400;
        font-size: 2.5rem;
        line-height: 1;
        text-transform: uppercase;
      }
      h2 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .meta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
      }
      .grow {
        flex: 1;
      }
      .strong {
        font-weight: 600;
      }
      .end-auto {
        margin-inline-start: auto;
        white-space: nowrap;
      }
      .stack {
        display: grid;
        min-inline-size: 0;
      }
      .search {
        display: block;
        min-inline-size: 14rem;
      }

      /* sidebar brand */
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
      }
      .brand-mark {
        display: inline-grid;
        place-items: center;
        flex: none;
        inline-size: 1.5rem;
        block-size: 1.5rem;
        border-radius: var(--radius);
        background: var(--muted);
        color: var(--foreground);
        font-family: var(--font-mono);
        font-size: 0.5625rem;
        font-weight: 700;
      }
      .brand-name {
        display: grid;
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      .brand-name small {
        font-family: var(--font-mono);
        font-size: 0.5625rem;
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }

      /* status: dot + text */
      .st {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xxxs);
        white-space: nowrap;
      }
      .dot {
        flex: none;
        inline-size: 0.4375rem;
        block-size: 0.4375rem;
        border-radius: 50%;
        background: var(--muted-foreground);
      }
      .dot.ok {
        background: var(--success);
      }
      .dot.warn {
        background: var(--warning);
      }
      .dot.bad {
        background: var(--destructive);
      }
      .dot.info {
        background: var(--info);
      }
      .amount.ok {
        color: var(--success);
      }
      .amount.bad {
        color: var(--destructive);
      }

      /* blocks: radius only on the outer card, flat inside */
      .block,
      .strip {
        background: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      .sh {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        min-block-size: 1.75rem;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .ul {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        box-sizing: border-box;
        min-block-size: 1.75rem;
        padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .ul > li:last-child > .row,
      .ul > .row:last-child {
        border-block-end: none;
      }
      .pad,
      .es {
        padding: var(--boxel-sp-xs);
      }
      .open {
        all: unset;
        cursor: pointer;
        min-inline-size: 0;
        max-inline-size: 100%;
      }
      .open:focus-visible {
        outline: 2px solid var(--ring);
      }
      .open:hover .nm,
      .open.nm:hover,
      .open.mono:hover {
        text-decoration: underline;
      }
      .who {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        min-inline-size: 0;
      }
      .nm {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-weight: 600;
      }
      .when {
        flex: none;
        inline-size: 3rem;
      }
      .when-l {
        flex: none;
        inline-size: 5.5rem;
      }

      /* stat strip: joined tiles, every tile draws its own dividers */
      .strip {
        display: grid;
        grid-template-columns: repeat(6, minmax(0, 1fr));
      }
      .strip.n4 {
        grid-template-columns: repeat(4, minmax(0, 1fr));
      }
      .strip.inner {
        border: none;
        border-radius: 0;
        border-block-end: 1px solid var(--border);
      }
      .stat {
        display: grid;
        gap: var(--boxel-sp-5xs);
        min-inline-size: 0;
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      .num {
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1;
      }

      /* two columns: main + docked side */
      .cols {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 17.5rem;
        gap: var(--boxel-sp-xs);
        align-items: stretch;
      }
      .cols.members {
        grid-template-columns: 20rem minmax(0, 1fr);
        align-items: start;
      }
      .side {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
      }
      .grow-block {
        flex: 1;
      }
      .detail {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
      }
      .member-row {
        box-sizing: border-box;
        min-block-size: 1.75rem;
        padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
        align-items: center;
        gap: var(--boxel-sp-xs);
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto 4rem;
        inline-size: 100%;
      }
      .member-row[aria-pressed='true'] {
        background: var(--muted);
      }
      .member-row .st {
        justify-self: end;
      }
      .fixture {
        align-items: flex-start;
      }
      .sold {
        flex-wrap: wrap;
      }
      .full {
        flex-basis: 100%;
      }
      .tier-row {
        display: grid;
        grid-template-columns: 4rem minmax(0, 1fr) 1.5rem;
      }
      .end {
        text-align: end;
      }

      /* tables: 28px rows, mono caps head, hairlines */
      .tw {
        overflow-x: auto;
        padding-inline: var(--boxel-sp-xs);
        --pretui-table-head-height: 1.5rem;
        --inset: var(--card);
        --stripe: transparent;
      }
      th,
      td {
        padding-block: 0;
        text-align: start;
        white-space: nowrap;
        vertical-align: middle;
      }
      th.end,
      td.end {
        text-align: end;
      }
      td,
      th.rh {
        block-size: 1.75rem;
      }
      th.rh {
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0;
        text-transform: none;
        color: var(--foreground);
      }
      th.mono-cell {
        color: var(--muted-foreground);
      }
      th.wide {
        inline-size: 50%;
      }
      td.mono,
      td.end {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
      }
      .booked {
        display: inline-grid;
        grid-template-columns: auto 3.5rem;
        align-items: center;
        gap: var(--boxel-sp-xxs);
      }

      /* month calendar */
      .cal-wrap {
        padding-inline: 0;
      }
      .cal {
        inline-size: 100%;
        border-collapse: collapse;
        table-layout: fixed;
      }
      .cal th {
        block-size: 1.5rem;
        padding-inline: var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .cal td {
        block-size: 4.25rem;
        vertical-align: top;
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
        border-inline-start: 1px solid var(--border);
        white-space: normal;
      }
      .cal td:first-child {
        border-inline-start: none;
      }
      .cal tr:last-child td {
        border-block-end: none;
      }
      .cal td.outside .mono {
        color: var(--muted-foreground);
      }
      .cal td > .mono {
        display: block;
        font-weight: 600;
      }
      .cal-ev {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxxs);
        margin-block-start: var(--boxel-sp-xxs);
      }

      @container (max-width: 60rem) {
        .strip {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
        .cols,
        .cols.members {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      @container (max-width: 40rem) {
        .strip,
        .strip.n4 {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .search {
          min-inline-size: 0;
        }
        .cal td {
          block-size: 3rem;
        }
      }
    </style>
  </template>
}
