import {
  CardDef,
  Component,
  field,
  contains,
  realmURL,
  StringField,
  type Format,
  type ViewCardFn,
  type CreateCardFn,
  type CardCrudFunctions,
} from '@cardstack/base/card-api';
import { consume } from 'ember-provide-consume-context';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/pretui/helpers';
import { debounce } from 'lodash-es';
import {
  identifyCard,
  rri,
  searchEntryWireQueryFromQuery,
  CardCrudFunctionsContextName,
  type CodeRef,
  type Query,
  type Filter,
  type LooseSingleCardDocument,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import UsersRoundIcon from '@cardstack/boxel-icons/users-round';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import { Button } from '@cardstack/pretui/components/button';
import { restartableTask } from 'ember-concurrency';
import { Employee } from '../hr/employee';
import { Candidate } from '../hr/candidate';
import { Meeting } from '../hr/meeting';
import { Team } from '../hr/team';
import { Project } from '../projects/project';
import { Vendor } from '../procurement/vendor';
import { Contractor } from '../hr/contractor';
import { PtoRequest } from '../hr/pto-request';
import { PerformanceReview } from '../hr/performance-review';
import { JobRequisition } from '../hr/job-requisition';
import { OnboardingChecklist } from '../hr/onboarding-checklist';
import { type CalendarEvent } from '@cardstack/catalog/components/calendar';
import { Avatar } from '@cardstack/pretui/components/avatar';
import BriefcaseBusinessIcon from '@cardstack/boxel-icons/briefcase-business';
import CalendarIcon from '@cardstack/boxel-icons/calendar';
import CalendarDaysIcon from '@cardstack/boxel-icons/calendar-days';
import ContactIcon from '@cardstack/boxel-icons/contact';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import KanbanIcon from '@cardstack/boxel-icons/kanban';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import MailIcon from '@cardstack/boxel-icons/mail';
import NetworkIcon from '@cardstack/boxel-icons/network';
import RocketIcon from '@cardstack/boxel-icons/rocket';
import SignatureIcon from '@cardstack/boxel-icons/signature';
import StarIcon from '@cardstack/boxel-icons/star';
import UsersIcon from '@cardstack/boxel-icons/users';
import { FitTile } from '../shared/fit-tile';
import { Position } from '../hr/position';
import { Application } from '../hr/application';
import { Offer } from '../hr/offer';
import { RejectCandidateCommand } from '../hr/commands/reject-candidate-command';
import { ScheduleInterviewCommand } from '../hr/commands/schedule-interview-command';
import { RejectCandidateDialog } from '../hr/components/reject-candidate-dialog';
import { ScheduleInterviewDialog } from '../hr/components/schedule-interview-dialog';
import { durationInDays } from '../hr/duration-field';
import {
  employeeRef,
  meetingRef,
  TABS,
  type Tab,
  snapshotCandidate,
  restoreCandidate,
} from './shared';
import { DashboardTab } from './tabs/dashboard';
import { PositionsTab } from './tabs/positions';
import { ApplicationsTab } from './tabs/applications';
import { DirectoryTab } from './tabs/directory';
import { PipelineTab } from './tabs/pipeline';
import { RequisitionsTab } from './tabs/requisitions';
import { OnboardingTab } from './tabs/onboarding';
import { ContractorsTab } from './tabs/contractors';
import { PtoTab } from './tabs/pto';
import { ReviewsTab } from './tabs/reviews';
import { OffersTab } from './tabs/offers';
import { CalendarTab } from './tabs/calendar';
import { OrgChartTab } from './tabs/org-chart';
import { toLocalDate } from './dates';

const TAB_ICONS: Record<Tab, typeof UsersRoundIcon> = {
  Dashboard: LayoutGridIcon,
  Requisitions: FileTextIcon,
  Positions: BriefcaseBusinessIcon,
  Applications: MailIcon,
  Pipeline: KanbanIcon,
  Offers: SignatureIcon,
  Onboarding: RocketIcon,
  Directory: UsersIcon,
  'Org Chart': NetworkIcon,
  PTO: CalendarDaysIcon,
  Reviews: StarIcon,
  Contractors: ContactIcon,
  Calendar: CalendarIcon,
};
type NavEntry = { tab: Tab; badge?: string; icon: typeof UsersRoundIcon };

class Isolated extends Component<typeof TalentResourceTracker> {
  // in the drawer, picking a section also closes it
  pickTab = (tab: Tab, bar: { mobile: boolean; toggle: () => void }) => {
    this.setTab(tab);
    if (bar.mobile) {
      bar.toggle();
    }
  };
  clearRange = () => {
    this.dashboardRange = { start: undefined, end: undefined };
    this.dashboardCustomPicked = false;
  };

  get rangeLabel(): string {
    let { start, end } = this.dashboardRange;
    if (!start && !end) {
      return 'All time';
    }
    let fmt = (d?: Date) =>
      d
        ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
        : '…';
    return `${fmt(start)} – ${fmt(end)}`;
  }
  openRange = () => {
    this.setTab('Dashboard');
    this.dashboardFilterOpen = true;
  };

  tabs = TABS;

  // Rail IA: same 13 destinations, grouped. Labels only regroup — the tab
  // keys stay identical so deep-links from dashboard chips keep working.
  // Dashboard rides in an unlabeled first group. Each item carries its live
  // count as the sidebar badge.
  get railGroups(): {
    label?: string;
    items: NavEntry[];
  }[] {
    let groups: { label?: string; tabs: Tab[] }[] = [
      { tabs: ['Dashboard'] },
      {
        label: 'Hiring',
        tabs: [
          'Requisitions',
          'Positions',
          'Applications',
          'Pipeline',
          'Offers',
          'Onboarding',
        ],
      },
      { label: 'People', tabs: ['Directory', 'Org Chart', 'PTO', 'Reviews'] },
      { label: 'Resources', tabs: ['Contractors'] },
      { label: 'Planning', tabs: ['Calendar'] },
    ];
    return groups.map((group) => ({
      label: group.label,
      items: group.tabs.map((tab) => ({
        tab,
        badge: this.badgeFor(tab),
        icon: TAB_ICONS[tab],
      })),
    }));
  }

  // A zero count shows no badge.
  private badgeFor(tab: Tab): string | undefined {
    let count = (() => {
      switch (tab) {
        case 'Requisitions':
          return this.requisitionsQuery?.instances?.length ?? 0;
        case 'Positions':
          return this.positions.length;
        case 'Applications':
          return this.applications.length;
        case 'Pipeline':
          return this.candidates.filter(
            (c) => c.status !== 'hired' && c.status !== 'rejected',
          ).length;
        case 'Offers':
          return this.offers.length;
        case 'Onboarding':
          return (this.onboardingChecklistsQuery?.instances ?? []).filter(
            (c) => (c as OnboardingChecklist).status !== 'complete',
          ).length;
        case 'Directory':
          return this.employees.length;
        case 'PTO':
          return this.ptoRequests.filter((r) => r.status === 'in-progress')
            .length;
        case 'Reviews':
          return this.performanceReviews.length;
        case 'Contractors':
          return this.contractors.length;
        default:
          return 0;
      }
    })();
    return count ? String(count) : undefined;
  }

  @tracked activeTab: Tab = 'Dashboard';

  @tracked actionError: string | undefined;

  @tracked busyCandidateId: string | undefined;

  // The candidate currently targeted by the reject dialog. One dialog
  // instance renders near the top of the template rather than one per
  // Kanban card — see RejectCandidateDialog.
  @tracked rejectDialogCandidate: Candidate | undefined;

  @tracked busyApplicationId: string | undefined;

  @tracked directorySearch = '';

  @tracked directoryDept = 'all';

  @tracked directoryView: 'grid' | 'strip' = 'strip';

  @tracked positionsSearch = '';

  @tracked positionsView: 'grid' | 'strip' | 'table' = 'table';

  @tracked applicationsSearch = '';

  @tracked applicationsView: 'grid' | 'strip' | 'table' = 'table';

  @tracked offersSearch = '';

  @tracked offersView: 'grid' | 'strip' = 'grid';

  @tracked requisitionsSearch = '';

  @tracked requisitionsStatusFilter = 'all';

  @tracked requisitionsView: 'grid' | 'strip' | 'table' = 'table';

  @tracked onboardingSearch = '';

  @tracked onboardingStatusFilter = 'all';

  @tracked onboardingView: 'grid' | 'strip' | 'table' = 'table';

  @tracked contractorSearch = '';

  @tracked contractorStatusFilter = 'all';

  @tracked contractorsView: 'grid' | 'strip' | 'table' = 'table';

  @tracked ptoSearch = '';

  @tracked ptoStatusFilter = 'all';

  @tracked ptoView: 'grid' | 'strip' | 'table' = 'table';

  @tracked reviewsSearch = '';

  @tracked reviewStatusFilter = 'all';

  @tracked reviewsView: 'grid' | 'strip' | 'table' = 'table';

  @tracked reviewMode = false;

  @tracked reviewIndex = 0;

  @tracked reviewedCount = 0;

  // Transient UI-only filter for the Dashboard tab — never persisted to the
  // model. Undefined on both ends means "show everything", exactly like
  // before this filter existed.
  @tracked dashboardRange: { start: Date | undefined; end: Date | undefined } =
    { start: undefined, end: undefined };
  // the Dashboard range menu shows Custom while this is set
  @tracked dashboardCustomPicked = false;

  @tracked dashboardFilterOpen = false;

  debouncedSetPositionsSearch = debounce((value: string) => {
    this.positionsSearch = value;
  }, 250);

  debouncedSetApplicationsSearch = debounce((value: string) => {
    this.applicationsSearch = value;
  }, 250);

  debouncedSetOffersSearch = debounce((value: string) => {
    this.offersSearch = value;
  }, 250);

  debouncedSetRequisitionsSearch = debounce((value: string) => {
    this.requisitionsSearch = value;
  }, 250);

  debouncedSetOnboardingSearch = debounce((value: string) => {
    this.onboardingSearch = value;
  }, 250);

  debouncedSetContractorSearch = debounce((value: string) => {
    this.contractorSearch = value;
  }, 250);

  debouncedSetPtoSearch = debounce((value: string) => {
    this.ptoSearch = value;
  }, 250);

  debouncedSetReviewsSearch = debounce((value: string) => {
    this.reviewsSearch = value;
  }, 250);

  get realms(): string[] {
    let url = this.args.model[realmURL]?.href;
    return url ? [url] : [];
  }

  get employeeQuery(): Query {
    // The directory lists every Employee in the realm — the same population
    // the live `employeesQuery` feeds `departments` from — so the chip list
    // and the search results can never disagree about who's in the directory.
    let every: Filter[] = [{ type: employeeRef }];
    if (this.directorySearch) {
      every.push({ on: employeeRef, contains: { name: this.directorySearch } });
    }
    if (this.directoryDept !== 'all') {
      every.push({ on: employeeRef, eq: { department: this.directoryDept } });
    }
    return { filter: { every } };
  }

  debouncedSetDirectorySearch = debounce((value: string) => {
    this.directorySearch = value;
  }, 250);

  // Every collection is a live realm query rather than a hand-maintained
  // linksToMany on the tracker card: new cards show up here the moment they
  // index, with no "append to the tracker and save it" bookkeeping step.
  private liveQuery(cardClass: typeof CardDef) {
    return this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(cardClass);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  employeesQuery = this.liveQuery(Employee);

  candidatesQuery = this.liveQuery(Candidate);

  meetingsQuery = this.liveQuery(Meeting);

  teamsQuery = this.liveQuery(Team);

  projectsQuery = this.liveQuery(Project);

  vendorsQuery = this.liveQuery(Vendor);

  positionsQuery = this.liveQuery(Position);

  applicationsQuery = this.liveQuery(Application);

  offersQuery = this.liveQuery(Offer);

  contractorsQuery = this.liveQuery(Contractor);

  requisitionsQuery = this.liveQuery(JobRequisition);

  onboardingChecklistsQuery = this.liveQuery(OnboardingChecklist);

  ptoRequestsQuery = this.liveQuery(PtoRequest);

  reviewsQuery = this.liveQuery(PerformanceReview);

  // A count reads "—" until every query it draws on has answered, never 0.
  get isLoading(): boolean {
    return [
      this.employeesQuery,
      this.candidatesQuery,
      this.meetingsQuery,
      this.positionsQuery,
      this.applicationsQuery,
      this.offersQuery,
      this.contractorsQuery,
      this.ptoRequestsQuery,
      this.reviewsQuery,
    ].some((query) => query?.isLoading);
  }

  // ── Entry-API wire queries for the grid/strip views ─────────────────────
  // The six list tabs render their tiles through
  // `@context.searchResultsComponent`, which serves prerendered fitted HTML
  // (the default entry format) with lazy hydration and the operator-mode
  // overlay — so tiles are hover-highlightable and click-to-open without any
  // per-tile wiring here. The table/kanban/dashboard consumers keep the
  // `getCards` instance queries above; they compute over instances in JS.

  // blog-app's library free-text idiom: no text → a plain type filter;
  // text → the type AND (full-doc `matches` OR title `contains`).
  private searchTextFilter(ref: CodeRef, search: string): Filter {
    let q = search.trim();
    if (!q) {
      return { type: ref };
    }
    return {
      every: [
        { type: ref },
        {
          any: [{ matches: q }, { contains: { cardTitle: q } }],
        },
      ],
    };
  }

  get positionsSearchQuery(): SearchEntryWireQuery | undefined {
    let ref = identifyCard(Position);
    if (!ref || !this.realms.length) {
      return undefined;
    }
    return {
      ...searchEntryWireQueryFromQuery({
        filter: this.searchTextFilter(ref, this.positionsSearch),
        sort: [{ by: 'title', on: ref, direction: 'asc' }],
      }),
      realms: this.realms,
    };
  }

  get applicationsSearchQuery(): SearchEntryWireQuery | undefined {
    let ref = identifyCard(Application);
    if (!ref || !this.realms.length) {
      return undefined;
    }
    return {
      ...searchEntryWireQueryFromQuery({
        filter: this.searchTextFilter(ref, this.applicationsSearch),
        sort: [{ by: 'appliedDate', on: ref, direction: 'desc' }],
      }),
      realms: this.realms,
    };
  }

  // Offers are time-sensitive — the one expiring in 3 days matters more
  // than the one from last month, so soonest-to-expire leads (the byline
  // above the grid promises exactly this order).
  get offersSearchQuery(): SearchEntryWireQuery | undefined {
    let ref = identifyCard(Offer);
    if (!ref || !this.realms.length) {
      return undefined;
    }
    return {
      ...searchEntryWireQueryFromQuery({
        filter: this.searchTextFilter(ref, this.offersSearch),
        sort: [{ by: 'expirationDate', on: ref, direction: 'asc' }],
      }),
      realms: this.realms,
    };
  }

  get requisitionsSearchQuery(): SearchEntryWireQuery | undefined {
    let ref = identifyCard(JobRequisition);
    if (!ref || !this.realms.length) {
      return undefined;
    }
    let every: Filter[] = [this.searchTextFilter(ref, this.requisitionsSearch)];
    if (this.requisitionsStatusFilter !== 'all') {
      every.push({
        on: ref,
        eq: { status: this.requisitionsStatusFilter },
      });
    }
    return {
      ...searchEntryWireQueryFromQuery({
        filter: { every },
        sort: [{ by: 'createdDate', on: ref, direction: 'desc' }],
      }),
      realms: this.realms,
    };
  }

  // The tab's contract is ACTIVE checklists, so the unfiltered default
  // excludes `complete`; picking a status chip (including Complete)
  // overrides that default with an exact match.
  get onboardingSearchQuery(): SearchEntryWireQuery | undefined {
    let ref = identifyCard(OnboardingChecklist);
    if (!ref || !this.realms.length) {
      return undefined;
    }
    let every: Filter[] = [this.searchTextFilter(ref, this.onboardingSearch)];
    if (this.onboardingStatusFilter === 'all') {
      every.push({ on: ref, not: { eq: { status: 'complete' } } });
    } else {
      every.push({ on: ref, eq: { status: this.onboardingStatusFilter } });
    }
    return {
      ...searchEntryWireQueryFromQuery({
        filter: { every },
        sort: [{ by: 'createdDate', on: ref, direction: 'desc' }],
      }),
      realms: this.realms,
    };
  }

  get contractorsSearchQuery(): SearchEntryWireQuery | undefined {
    let ref = identifyCard(Contractor);
    if (!ref || !this.realms.length) {
      return undefined;
    }
    let every: Filter[] = [this.searchTextFilter(ref, this.contractorSearch)];
    if (this.contractorStatusFilter !== 'all') {
      every.push({
        on: ref,
        eq: { status: this.contractorStatusFilter },
      });
    }
    return {
      ...searchEntryWireQueryFromQuery({
        filter: { every },
        sort: [{ by: 'name', on: ref, direction: 'asc' }],
      }),
      realms: this.realms,
    };
  }

  // Newest requests first — the one filed this morning is the one the
  // approver is looking for.
  get ptoSearchQuery(): SearchEntryWireQuery | undefined {
    let ref = identifyCard(PtoRequest);
    if (!ref || !this.realms.length) {
      return undefined;
    }
    let every: Filter[] = [this.searchTextFilter(ref, this.ptoSearch)];
    if (this.ptoStatusFilter !== 'all') {
      every.push({ on: ref, eq: { status: this.ptoStatusFilter } });
    }
    return {
      ...searchEntryWireQueryFromQuery({
        filter: { every },
        sort: [{ by: 'requestedDate', on: ref, direction: 'desc' }],
      }),
      realms: this.realms,
    };
  }

  get reviewsSearchQuery(): SearchEntryWireQuery | undefined {
    let ref = identifyCard(PerformanceReview);
    if (!ref || !this.realms.length) {
      return undefined;
    }
    let every: Filter[] = [this.searchTextFilter(ref, this.reviewsSearch)];
    if (this.reviewStatusFilter !== 'all') {
      every.push({ on: ref, eq: { status: this.reviewStatusFilter } });
    }
    return {
      ...searchEntryWireQueryFromQuery({
        filter: { every },
        sort: [{ by: 'employeeName', on: ref, direction: 'asc' }],
      }),
      realms: this.realms,
    };
  }

  get employees(): Employee[] {
    return (this.employeesQuery?.instances ?? []) as Employee[];
  }

  get candidates(): Candidate[] {
    return (this.candidatesQuery?.instances ?? []) as Candidate[];
  }

  get meetings(): Meeting[] {
    return (this.meetingsQuery?.instances ?? []) as Meeting[];
  }

  get positions(): Position[] {
    return (this.positionsQuery?.instances ?? []) as Position[];
  }

  get teams(): Team[] {
    return (this.teamsQuery?.instances ?? []) as Team[];
  }

  get projects(): Project[] {
    return (this.projectsQuery?.instances ?? []) as Project[];
  }

  get vendors(): Vendor[] {
    return (this.vendorsQuery?.instances ?? []) as Vendor[];
  }

  get applications(): Application[] {
    return (this.applicationsQuery?.instances ?? []) as Application[];
  }

  get offers(): Offer[] {
    return (this.offersQuery?.instances ?? []) as Offer[];
  }

  get contractors(): Contractor[] {
    return (this.contractorsQuery?.instances ?? []) as Contractor[];
  }

  get ptoRequests(): PtoRequest[] {
    return (this.ptoRequestsQuery?.instances ?? []) as PtoRequest[];
  }

  get performanceReviews(): PerformanceReview[] {
    return (this.reviewsQuery?.instances ?? []) as PerformanceReview[];
  }

  isRequisitionStatus = (req: JobRequisition, status: string): boolean => {
    return (req.status ?? 'draft') === status;
  };

  // True when `date` falls inside `dashboardRange`, or when no range is set
  // (both ends undefined) — the Dashboard's unfiltered, show-everything
  // default. `end` is treated as inclusive of its whole day so picking the
  // same start/end date still matches same-day records.
  inDashboardRange = (date?: Date | string | null): boolean => {
    let { start, end } = this.dashboardRange;
    if (!start && !end) {
      return true;
    }
    if (!date) {
      return false;
    }
    let d = toLocalDate(date);
    if (isNaN(d.getTime())) {
      return false;
    }
    if (start && d < start) {
      return false;
    }
    if (end) {
      let endOfDay = toLocalDate(end);
      endOfDay.setHours(23, 59, 59, 999);
      if (d > endOfDay) {
        return false;
      }
    }
    return true;
  };

  whoseTurn = (
    candidate: Candidate,
  ): { tone: 'red' | 'amber' | 'green'; label: string } => {
    let status = candidate.status;
    // Matches on the denormalized candidateId scalar, not `m.candidate?.id`
    // — this runs once per candidate on every Dashboard render, and reading
    // the `candidate` linksTo there races the async link load the same way
    // it did for the `offer` linksTo above.
    let meetings = this.meetings.filter((m) => m.candidateId === candidate.id);
    if (status === 'applied') {
      return { tone: 'red', label: 'Needs screening' };
    }
    if (status === 'screening') {
      let hasUpcoming = meetings.some(
        (m) => m.date && toLocalDate(m.date).getTime() > Date.now(),
      );
      return hasUpcoming
        ? { tone: 'green', label: 'Interview scheduled' }
        : { tone: 'red', label: 'Needs interview scheduled' };
    }
    if (status === 'interviewing') {
      let overdue = meetings.filter(
        (m) =>
          m.date &&
          toLocalDate(m.date).getTime() < Date.now() &&
          m.interviewScore == null,
      ).length;
      if (overdue > 0) {
        return {
          tone: 'red',
          label: `${overdue} feedback${overdue > 1 ? 's' : ''} overdue`,
        };
      }
      let hasUpcoming = meetings.some(
        (m) => m.date && toLocalDate(m.date).getTime() > Date.now(),
      );
      return hasUpcoming
        ? { tone: 'green', label: 'Interview scheduled' }
        : { tone: 'amber', label: 'Awaiting next step' };
    }
    if (status === 'offer') {
      // The board only answers "whose turn is it". The offer's own
      // lifecycle — terms, dates, draft vs sent — belongs on the Offer
      // card; mirroring it here produced five labels for two situations.
      // Reads the scalar, never the linksTo: resolving a link in this
      // getter (it runs per candidate per render) races the async load
      // and trips Ember's "updated after use" assertion.
      return candidate.offerState === 'extended'
        ? { tone: 'amber', label: 'Awaiting candidate reply' }
        : { tone: 'red', label: 'Offer not sent' };
    }
    return { tone: 'green', label: status ?? '' };
  };

  // Interviewer load — sum of this-week interview meeting duration per
  // interviewer, against each employee's own capacity (falls back to 5h/wk
  // when unset).
  get interviewerLoad(): Array<{
    employee: Employee;
    hours: number;
    capacityHours: number;
    tone: 'red' | 'amber' | 'green';
  }> {
    let meetings = this.meetings.filter((m) => this.inDashboardRange(m.date));
    let now = new Date();
    let weekStart = toLocalDate(now);
    weekStart.setDate(now.getDate() - now.getDay());
    weekStart.setHours(0, 0, 0, 0);
    let weekEnd = toLocalDate(weekStart);
    weekEnd.setDate(weekStart.getDate() + 7);
    let thisWeekMeetings = meetings.filter((m) => {
      if (!m.date) return false;
      let d = toLocalDate(m.date);
      return d >= weekStart && d < weekEnd;
    });
    return this.employees
      .filter((e) => e.status !== 'offboarded')
      .map((employee) => {
        let hours = thisWeekMeetings
          .filter((m) =>
            (m.interviewers ?? []).some((i) => i?.id === employee.id),
          )
          .reduce(
            (sum, m) =>
              sum + durationInDays(m.duration?.value, m.duration?.unit) * 24,
            0,
          );
        let capacityHours = employee.weeklyInterviewCapacityHours ?? 5;
        let tone: 'red' | 'amber' | 'green' =
          hours >= capacityHours
            ? 'red'
            : hours >= capacityHours * 0.8
              ? 'amber'
              : 'green';
        return {
          employee,
          hours: Math.round(hours * 10) / 10,
          capacityHours,
          tone,
        };
      })
      .filter((row) => row.hours > 0)
      .sort((a, b) => b.hours - a.hours);
  }

  get todayLabel(): string {
    return new Date().toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  }

  canRejectAt = (index: number): boolean => {
    let status = this.candidates[index]?.status;
    return status !== 'hired' && status !== 'rejected' && status !== 'offer';
  };

  setTab = (tab: Tab) => {
    this.activeTab = tab;
  };

  get calendarEvents(): CalendarEvent[] {
    return this.meetings
      .filter((m) => m.date)
      .map((m) => ({
        id: m.id,
        title: m.title ?? 'Meeting',
        date: toLocalDate(m.date!),
        kind: m.meetingType,
      }))
      .sort((a, b) => a.date.getTime() - b.date.getTime());
  }

  // `viewCard` is a TOP-LEVEL component arg — see SignatureFor<CardT> in
  // base/card-api.gts, which declares `viewCard?: ViewCardFn` alongside
  // `model` and `fields`. It is NOT on `context`; CardContext has no `actions`
  // member at all, so `context.actions.viewCard` (as recruiting-console.gts
  // does it) resolves to undefined and silently no-ops.
  //
  // ViewCardFn takes `CardDef | URL`, and the card object is the better
  // argument: a URL makes the host fetch, which for a just-created card
  // outruns indexing and parks the stack on "Loading card…".
  openCard = (
    item: { id?: string } | undefined,
    format: Format = 'isolated',
  ) => {
    let id = item?.id;
    if (!id) {
      return;
    }
    let viewCard = (this.args as any).viewCard as ViewCardFn | undefined;
    if (!viewCard) {
      return;
    }
    // Calendar chips and org-tree rows hand over a plain view-model carrying
    // only an id, so resolve those back to the real card before navigating.
    let card = this.cardById(id);
    viewCard(card ?? new URL(id), format);
  };

  // DataTable's @onRowActivate passes (row, index); openCard's second
  // parameter is a Format, so the index must not reach it.
  openRowCard = (row: { id?: string } | undefined) => this.openCard(row);

  private cardById(id: string) {
    let pools = [
      this.candidates,
      this.employees,
      this.meetings,
      this.teams,
      this.projects,
      this.vendors,
      this.positions,
      this.applications,
      this.offers,
      this.ptoRequests,
      this.performanceReviews,
      this.contractors,
      this.requisitionsQuery?.instances ?? [],
      this.onboardingChecklistsQuery?.instances ?? [],
    ];
    for (let pool of pools) {
      let hit = (pool as any[]).find((c) => c?.id === id);
      if (hit) {
        return hit;
      }
    }
    return undefined;
  }

  // Click-to-open for the prerendered search-entry tiles, copied from base's
  // CardList (base/components/card-list.gts): consume the CardCrudFunctions
  // context and call `viewCard` with the entry's id. The entry rows render
  // with `@mode='none'` so they stay inert prerendered HTML; the wrapper div
  // carries the click affordance instead.
  @consume(CardCrudFunctionsContextName)
  declare cardCrudFunctions: CardCrudFunctions | undefined;

  viewEntry = (cardUrl: string, event?: Event) => {
    // A fitted template can carry its own controls (e.g. the Application
    // card's "Screen → Candidate" button); let those run their action
    // without also opening the card.
    if (
      event?.target instanceof Element &&
      event.target.closest('button, a, input, select, textarea')
    ) {
      return;
    }
    if (this.cardCrudFunctions?.viewCard) {
      event?.preventDefault();
      this.cardCrudFunctions.viewCard(rri(cardUrl));
    }
  };

  viewEntryOnKeydown = (cardUrl: string, event: KeyboardEvent) => {
    if (event.target !== event.currentTarget) {
      return;
    }
    if (event.key !== 'Enter' && event.key !== ' ') {
      return;
    }
    if (this.cardCrudFunctions?.viewCard) {
      event.preventDefault();
      this.cardCrudFunctions.viewCard(rri(cardUrl));
    }
  };

  // The day currently being created — the Calendar reads this to swap that
  // day's + for a spinner and disable it. Without the feedback a slow create
  // invites repeat clicks, which is how a single day ends up holding four
  // cards all named "New Meeting".
  @tracked addingMeetingOn: Date | undefined;

  // restartableTask, not a plain async function: it gives a real `isRunning`
  // state to drive the spinner, and cancels a superseded run rather than
  // letting two creates race.
  //
  // Uses the host's own createCard action (same primitive blog-app's "New
  // Post" button uses) instead of a manual SaveCardCommand-then-openCard
  // pair. createCard opens the new card in the stack itself, in edit format,
  // as ONE round trip. The Calendar picks the new meeting up through the
  // live `meetingsQuery` the moment it indexes — no linking step.
  addMeetingTask = restartableTask(async (date: Date) => {
    this.actionError = undefined;
    let createCard = (this.args as any).createCard as CreateCardFn | undefined;
    if (!createCard) {
      this.actionError = 'Commands are unavailable in this mode';
      return;
    }
    this.addingMeetingOn = date;
    try {
      let realmHref = this.args.model[realmURL]?.href;
      let realm = realmHref ? new URL(realmHref) : undefined;
      let doc: LooseSingleCardDocument = {
        data: {
          type: 'card',
          attributes: { name: 'New Meeting', date: date.toISOString() },
          meta: { adoptsFrom: meetingRef },
        },
      };
      await createCard(meetingRef, realm, {
        realmURL: realm,
        doc,
      });
    } catch (error: any) {
      this.actionError = error?.message ?? String(error);
    } finally {
      this.addingMeetingOn = undefined;
    }
  });

  // The candidate currently targeted by the schedule-interview dialog. Like
  // rejectDialogCandidate, one dialog instance renders near the top of the
  // template — and the {{#if}} wrapper means each open starts from a fresh
  // component (no stale slot/interviewer selection carried across opens).
  @tracked scheduleDialogCandidate: Candidate | undefined;

  // The last conflict (or other) error ScheduleInterviewCommand threw —
  // rendered inside the dialog with role='alert', next to the deliberate
  // "book anyway" override.
  @tracked scheduleError: string | undefined;

  closeScheduleDialog = () => {
    this.scheduleDialogCandidate = undefined;
    this.scheduleError = undefined;
  };

  confirmScheduleInterview = (opts: {
    date: Date;
    interviewers: Employee[];
    roundType: string;
    ignoreConflicts: boolean;
  }) => {
    void this.scheduleInterviewTask.perform(opts);
  };

  private scheduleInterviewTask = restartableTask(
    async (opts: {
      date: Date;
      interviewers: Employee[];
      roundType: string;
      ignoreConflicts: boolean;
    }) => {
      let candidate = this.scheduleDialogCandidate;
      if (!candidate) {
        return;
      }
      this.scheduleError = undefined;
      let commandContext = this.args.context?.commandContext;
      if (!commandContext) {
        this.scheduleError = 'Commands are unavailable in this mode';
        return;
      }
      try {
        // The command creates the Meeting (which reaches the Calendar via
        // the live meetingsQuery), advances screening → interviewing, and
        // throws a named-interviewer conflict error unless ignoreConflicts.
        await new ScheduleInterviewCommand(commandContext).execute({
          candidate,
          date: opts.date,
          interviewers: opts.interviewers,
          roundType: opts.roundType,
          ignoreConflicts: opts.ignoreConflicts,
        } as any);
        this.closeScheduleDialog();
      } catch (error: any) {
        // Keep the dialog open so the recruiter can pick another slot or
        // deliberately override.
        this.scheduleError = error?.message ?? String(error);
      }
    },
  );

  // Generic "+ Add" for every collection tab — same blog-app idiom as
  // addMeetingTask: hand the host a bare adoptsFrom doc and let createCard
  // open the new card in the stack in edit format. The live queries pick the
  // card up on index, so there is no linking step afterward.
  get canCreate(): boolean {
    return Boolean((this.args as any).createCard);
  }

  addNew = (cardClass: typeof CardDef) => {
    void this.addCard.perform(cardClass);
  };

  addCard = restartableTask(async (cardClass: typeof CardDef) => {
    this.actionError = undefined;
    let createCard = (this.args as any).createCard as CreateCardFn | undefined;
    let ref = identifyCard(cardClass);
    if (!createCard || !ref) {
      this.actionError = 'Commands are unavailable in this mode';
      return;
    }
    try {
      let realmHref = this.args.model[realmURL]?.href;
      let realm = realmHref ? new URL(realmHref) : undefined;
      let doc: LooseSingleCardDocument = {
        data: {
          type: 'card',
          meta: { adoptsFrom: ref },
        },
      };
      await createCard(ref, realm, { realmURL: realm, doc });
    } catch (error: any) {
      this.actionError = error?.message ?? String(error);
    }
  });

  closeRejectDialog = () => {
    this.rejectDialogCandidate = undefined;
  };

  get isRejectDialogOpen(): boolean {
    return Boolean(this.rejectDialogCandidate);
  }

  confirmReject = async (reason: string, note: string) => {
    let candidate = this.rejectDialogCandidate;
    this.rejectDialogCandidate = undefined;
    if (!candidate) {
      return;
    }
    await this.runCommand(candidate, async (commandContext) => {
      await new RejectCandidateCommand(commandContext).execute({
        candidate,
        reason,
        note,
      } as any);
    });
  };

  formatDate = (value: Date | string | undefined): string => {
    if (!value) {
      return '—';
    }
    let date = toLocalDate(value);
    if (isNaN(date.getTime())) {
      return '—';
    }
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
    });
  };

  async runCommand<T>(
    candidate: Candidate,
    action: (commandContext: any) => Promise<T>,
    verb?: string,
  ): Promise<T | undefined> {
    this.actionError = undefined;
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.actionError = 'Commands are unavailable in this mode';
      return undefined;
    }
    this.busyCandidateId = candidate.id;
    this.busyVerb = verb;
    // A failed command leaves the candidate as it was before the action,
    // including a board position a drag set ahead of it.
    let before = snapshotCandidate(candidate);
    try {
      return await action(commandContext);
    } catch (error: any) {
      restoreCandidate(candidate, before);
      this.actionError = error?.message ?? String(error);
      return undefined;
    } finally {
      this.busyCandidateId = undefined;
      this.busyVerb = undefined;
    }
  }

  // Which action is running, not just which candidate: a command can flip
  // the card into a new UI state mid-flight (AdvanceToOffer sets
  // offerState='draft' before its save settles), and the new state's button
  // must not claim the earlier action's progress — "Sending…" on a card whose
  // only running action is a draft creation misleads.
  @tracked busyVerb: string | undefined;

  <template>
    <RejectCandidateDialog
      @isOpen={{this.isRejectDialogOpen}}
      @candidateName={{this.rejectDialogCandidate.name}}
      @onConfirm={{this.confirmReject}}
      @onCancel={{this.closeRejectDialog}}
    />
    {{#if this.scheduleDialogCandidate}}
      <ScheduleInterviewDialog
        @candidate={{this.scheduleDialogCandidate}}
        @employees={{this.employees}}
        @meetings={{this.meetings}}
        @isRunning={{this.scheduleInterviewTask.isRunning}}
        @error={{this.scheduleError}}
        @onConfirm={{this.confirmScheduleInterview}}
        @onCancel={{this.closeScheduleDialog}}
      />
    {{/if}}
    <section class='tracker'>
      <Sidebar
        class='trt-shell'
        @label='Tracker sections'
        @collapsible='rail'
        @railBreakpoint={{1100}}
        @mobileBreakpoint={{720}}
        @bordered={{true}}
        @scroll='content'
        @resizable={{true}}
      >
        <:header as |bar|>
          {{#unless bar.collapsed}}
            <div class='trt-brand'>
              <p class='trt-cap'>Personnel registry</p>
              <p class='trt-title'>{{@model.cardTitle}}</p>
              <span class='trt-bar' aria-hidden='true'></span>
              <p class='trt-cap trt-viewing-cap'>Viewing</p>
              <div class='trt-viewing'>
                <Button
                  @variant='ghost'
                  @size='s'
                  {{on 'click' this.openRange}}
                >{{this.rangeLabel}}</Button>
                <Button
                  @variant='ghost'
                  @size='s'
                  {{on 'click' this.clearRange}}
                >Reset</Button>
              </div>
            </div>
          {{/unless}}
        </:header>
        <:nav as |bar|>
          {{#each this.railGroups as |group|}}
            <SidebarGroup @label={{group.label}} @hideLabel={{bar.collapsed}}>
              {{#each group.items as |item|}}
                <SidebarItem
                  @label={{item.tab}}
                  @badge={{unless bar.collapsed item.badge}}
                  @active={{eq item.tab this.activeTab}}
                  @collapsed={{bar.collapsed}}
                  @onClick={{fn this.pickTab item.tab bar}}
                >
                  <:icon>{{#let item.icon as |Icon|}}<Icon
                        aria-hidden='true'
                      />{{/let}}</:icon>
                </SidebarItem>
              {{/each}}
            </SidebarGroup>
          {{/each}}
          {{#if (eq this.activeTab 'Positions')}}
            {{#unless bar.collapsed}}
              <SidebarGroup @label='Open positions'>
                {{#each this.positions as |position|}}
                  <SidebarItem
                    @label={{position.cardTitle}}
                    @onClick={{fn this.openCard position}}
                  />
                {{/each}}
              </SidebarGroup>
            {{/unless}}
          {{/if}}
        </:nav>
        <:default as |bar|>
          <div class='trt-pane'>
            {{#if bar.mobile}}
              {{! under 720px the rail is a drawer; this bar opens it }}
              <header class='trt-topbar'>
                <SidebarTrigger
                  @open={{bar.open}}
                  @onToggle={{bar.toggle}}
                  @controls={{bar.controls}}
                  @label='tracker sections'
                />
                <span class='trt-topbar-who'>
                  <span class='trt-cap'>Talent tracker</span>
                  <strong>{{this.activeTab}}</strong>
                </span>
              </header>
            {{/if}}
            <main class='trt-main'>
              {{#if this.actionError}}
                <p class='error' role='alert'>{{this.actionError}}</p>
              {{/if}}

              {{#if (eq this.activeTab 'Dashboard')}}
                <DashboardTab @tracker={{this}} />
              {{/if}}

              {{#if (eq this.activeTab 'Positions')}}
                <PositionsTab @tracker={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'Applications')}}
                <ApplicationsTab @tracker={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'Directory')}}
                <DirectoryTab @tracker={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'Pipeline')}}
                <PipelineTab @tracker={{this}} />
              {{/if}}

              {{#if (eq this.activeTab 'Requisitions')}}
                <RequisitionsTab @tracker={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'Onboarding')}}
                <OnboardingTab @tracker={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'Contractors')}}
                <ContractorsTab @tracker={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'PTO')}}
                <PtoTab @tracker={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'Reviews')}}
                <ReviewsTab @tracker={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'Offers')}}
                <OffersTab @tracker={{this}} @context={{@context}} />
              {{/if}}

              {{#if (eq this.activeTab 'Calendar')}}
                <CalendarTab @tracker={{this}} />
              {{/if}}

              {{#if (eq this.activeTab 'Org Chart')}}
                <OrgChartTab @tracker={{this}} />
              {{/if}}
            </main>
          </div>
        </:default>
      </Sidebar>
    </section>
    <style scoped>
      .tracker {
        container-type: inline-size;
        container-name: tracker;

        /* the compact mock's density through the kit's knobs, set once here */
        /* the mock's Compact preset: 12px body, 26px controls, 10/7 padding */
        --control-height: 1.625rem;
        --pretui-size-m: var(--boxel-font-size-sm);
        --pretui-page-stat-border: 1px solid var(--border);
        --pretui-page-stat-shadow: none;
        --pretui-shadow-card: none;
        --pretui-panel-pad-inline: var(--boxel-sp-xs);
        --pretui-panel-pad-block: var(--boxel-sp-2xs);
        --pretui-panel-title-size: var(--boxel-font-size-sm);

        /* one scroll model: the shell fills the card and only the page column
           scrolls; position contains absolutely placed descendants, which
           otherwise overflow the card container and leave a white band */
        position: relative;
        height: 100%;
        overflow: hidden;
        background: var(--card);
        color: var(--card-foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
      }
      .tracker {
        display: flex;
        flex-direction: column;
        line-height: 1.25;
      }
      /* the mock's Compact preset; one spacing scale at every width */
      .trt-pane {
        --trt-fs: var(--boxel-font-size-xs);
        --trt-gap: var(--boxel-sp-xs);
        --trt-px: var(--boxel-sp-xs);
        --trt-py: var(--boxel-sp-2xs);
        --trt-rowh: 1.75rem;
        --trt-pad: var(--boxel-sp-lg);
        --pretui-barlist-row-height: var(--trt-rowh);
        --pretui-barlist-gap: var(--boxel-sp-6xs);
      }
      .trt-pane {
        background: var(--background);
        display: flex;
        flex-direction: column;
        block-size: 100%;
      }
      @container tracker (width < 760px) {
        .trt-pane {
          --trt-fs: calc(var(--boxel-font-size-xs) * 0.94);
          --trt-rowh: 1.625rem;
        }
      }
      .trt-brand {
        padding: 0 var(--boxel-sp-xs) var(--boxel-sp-sm);
        margin-bottom: var(--boxel-sp-2xs);
        border-bottom: 1px solid var(--sidebar-border);
      }
      .trt-cap {
        margin: 0;
        font: 600 calc(var(--boxel-font-size-xs) * 0.75) / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      .trt-title {
        margin: var(--boxel-sp-6xs) 0 0;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size);
        font-weight: 800;
        letter-spacing: -0.01em;
      }
      .trt-bar {
        display: block;
        inline-size: 2.5rem;
        block-size: 0.1875rem;
        margin-top: var(--boxel-sp-2xs);
        border-radius: var(--boxel-border-radius-xs);
        background: var(--primary);
      }
      .trt-viewing-cap {
        margin-top: var(--boxel-sp-sm);
      }
      .trt-viewing {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-2xs);
        margin-top: var(--boxel-sp-6xs);
      }
      .trt-range,
      .trt-today {
        margin: 0;
        padding: 0;
        border: 0;
        background: none;
        color: var(--primary-ink);
        font: inherit;
        font-weight: 700;
        cursor: pointer;
      }
      .trt-today {
        margin-left: auto;
        font-weight: 600;
        font-size: var(--boxel-font-size-2xs);
      }
      .trt-shell {
        block-size: 100%;
        min-block-size: 0;
        --pretui-sidebar-width: 13.5rem;
        --pretui-sidebar-rail-width: 3.5rem;
        --pretui-sidebar-bg: var(--sidebar);
        --pretui-selected: var(--sidebar-primary);
        --pretui-primary-ink: var(--sidebar-primary-foreground);
      }
      .trt-main {
        flex: 1;
        display: flex;
        flex-direction: column;
        min-width: 0;
        min-height: 0;
      }
      @keyframes tracker-tab-fade-in {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      .error {
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        border-radius: var(--radius);
        background: var(--primary-ink);
        color: var(--card);
        font-size: var(--boxel-font-size-sm);
        margin: 0 0 var(--boxel-sp);
      }
      @keyframes action-busy-pulse {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.55;
        }
      }
    </style>
  </template>
}

export type TrackerView = Isolated;

export class TalentResourceTracker extends CardDef {
  static displayName = 'Talent & Resource Tracker';
  static icon = UsersRoundIcon;
  static prefersWideFormat = true;

  // The tracker holds no collection links: every tab in the Isolated view
  // sources its cards from live realm queries, so the schema is identity only.
  @field name = contains(StringField);

  static isolated = Isolated;

  static embedded = class Embedded extends Component<
    typeof TalentResourceTracker
  > {
    <template>
      <div class='trt-emb'>
        <Avatar
          @name={{if @model.cardTitle @model.cardTitle ''}}
          @hue='var(--primary)'
          @size={{32}}
          aria-hidden='true'
        />
        <span class='trt-emb-who'>
          <strong class='trt-emb-name'>{{@model.cardTitle}}</strong>
          <span class='trt-emb-sub'>Recruiting pipeline, directory &amp;
            analytics</span>
        </span>
      </div>
      <style scoped>
        .trt-emb {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
        }
        .trt-emb-who {
          flex: 1;
          display: grid;
          min-width: 0;
        }
        .trt-emb-name,
        .trt-emb-sub {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .trt-emb-name {
          font-weight: 600;
        }
        .trt-emb-sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='trt-atom'>
        <UsersRoundIcon
          class='trt-atom-icon'
          width='14'
          height='14'
          aria-hidden='true'
        />
        <span class='trt-atom-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .trt-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          font-weight: 600;
          color: var(--foreground);
        }
        .trt-atom-icon {
          flex: none;
          color: var(--muted-foreground);
        }
        .trt-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof TalentResourceTracker> {
    <template>
      <FitTile>
        <:avatar><Avatar
            @name={{if @model.cardTitle @model.cardTitle ''}}
            @hue='var(--primary)'
            @size={{32}}
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Recruiting pipeline, directory &amp; analytics</:subtitle>
        <:fact>13 views · Dashboard, Pipeline, Directory, Org chart, PTO,
          Reviews…</:fact>
      </FitTile>
    </template>
  };
}
