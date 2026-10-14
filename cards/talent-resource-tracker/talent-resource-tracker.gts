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
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
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
import { type CalendarEvent } from '../../components/calendar';
import { Button } from '@cardstack/pretui/components/button';
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

class Isolated extends Component<typeof TalentResourceTracker> {
  tabs = TABS;

  // Rail IA: same 13 destinations, grouped. Labels only regroup — the tab
  // keys stay identical so deep-links from dashboard chips keep working.
  // Dashboard rides in an unlabeled first group.
  get railGroups(): { label?: string; tabs: Tab[] }[] {
    return [
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

  @tracked applicationsView: 'grid' | 'strip' | 'table' = 'grid';

  @tracked offersSearch = '';

  @tracked offersView: 'grid' | 'strip' = 'grid';

  @tracked requisitionsSearch = '';

  @tracked requisitionsStatusFilter = 'all';

  @tracked requisitionsView: 'grid' | 'strip' | 'table' = 'grid';

  @tracked onboardingSearch = '';

  @tracked onboardingStatusFilter = 'all';

  @tracked onboardingView: 'grid' | 'strip' | 'table' = 'grid';

  @tracked contractorSearch = '';

  @tracked contractorStatusFilter = 'all';

  @tracked contractorsView: 'grid' | 'strip' | 'table' = 'grid';

  @tracked ptoSearch = '';

  @tracked ptoStatusFilter = 'all';

  @tracked ptoView: 'grid' | 'strip' | 'table' = 'grid';

  @tracked reviewsSearch = '';

  @tracked reviewStatusFilter = 'all';

  @tracked reviewsView: 'grid' | 'strip' | 'table' = 'grid';

  @tracked reviewMode = false;

  @tracked reviewIndex = 0;

  @tracked reviewedCount = 0;

  // Transient UI-only filter for the Dashboard tab — never persisted to the
  // model. Undefined on both ends means "show everything", exactly like
  // before this filter existed.
  @tracked dashboardRange: { start: Date | undefined; end: Date | undefined } =
    { start: undefined, end: undefined };

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
      <div class='shell'>
        <aside class='rail'>
          <div class='rail-kicker'>Personnel Registry</div>
          <h1 class='rail-title'>{{if
              @model.name
              @model.name
              'Talent & Resource Tracker'
            }}</h1>
          <div class='rail-sub'>Posted through {{this.todayLabel}}</div>
          <nav class='rail-nav'>
            <ul class='rail-list'>
              {{#each this.railGroups as |group|}}
                {{#if group.label}}
                  <li class='rail-group'>{{group.label}}</li>
                {{/if}}
                {{#each group.tabs as |tab|}}
                  <li class='rail-item'>
                    <Button
                      type='button'
                      @tone='neutral'
                      @appearance='plain'
                      class='rail-link {{if (eq tab this.activeTab) "current"}}'
                      {{on 'click' (fn this.setTab tab)}}
                    >
                      <span class='t'>{{tab}}</span>
                    </Button>
                    {{#if (eq tab 'Positions')}}
                      <ul class='rail-sublist'>
                        {{#each this.positions as |position|}}
                          <li>
                            <Button
                              type='button'
                              @tone='neutral'
                              @appearance='plain'
                              @size='s'
                              class='rail-sublink'
                              {{on 'click' (fn this.openCard position)}}
                            >{{if
                                position.title
                                position.title
                                'Untitled Position'
                              }}</Button>
                          </li>
                        {{/each}}
                      </ul>
                    {{/if}}
                  </li>
                {{/each}}
              {{/each}}
            </ul>
          </nav>
        </aside>

        <div class='page'>
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
        </div>
      </div>
    </section>
    <style scoped>
      .tracker {
        --_warn-soft: color-mix(in oklch, var(--warning) 12%, var(--card));
        container-type: inline-size;
        container-name: tracker;

        height: 100%;
        overflow: hidden;
        background: var(--muted);
        color: var(--card-foreground);

        font-family: var(--font-sans);
      }
      .shell {
        display: grid;

        grid-template-columns: 14.375rem minmax(0, 1fr);

        height: 100%;
      }
      .rail {
        background: var(--muted);
        border-right: 1px solid var(--border);
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg);

        height: 100%;
        overflow-y: auto;
        box-sizing: border-box;
      }
      @container tracker (max-width: 40rem) {
        .shell {
          grid-template-columns: minmax(0, 1fr);
          height: 100%;
          overflow-y: auto;
        }
        .rail {
          height: auto;
          overflow-y: visible;
          border-right: none;
          border-bottom: 1px solid var(--border);
        }
        .page {
          height: auto;
          overflow-y: visible;
        }
      }
      .rail-kicker {
        font-family: var(--font-mono);
        font-size: 0.625rem;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--primary-ink);
        margin-bottom: var(--boxel-sp-5xs);
      }
      .rail-title {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 1.1875rem;
        line-height: 1.25;
        letter-spacing: -0.01em;
        margin: 0 0 var(--boxel-sp-5xs);
      }
      .rail-sub {
        font-family: var(--font-mono);
        font-size: 0.6562rem;
        letter-spacing: 0.03em;
        color: var(--muted-foreground);
        margin-bottom: var(--boxel-sp-xl);
      }
      .rail-nav {
        display: flex;
        flex-direction: column;
        gap: 0.1875rem;
      }
      .rail-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 0.1875rem;
      }
      .rail-item {
        display: flex;
        flex-direction: column;
      }
      .rail-group {
        font-family: var(--font-mono);
        font-size: 0.625rem;
        font-weight: 600;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        padding: var(--boxel-sp-sm) var(--boxel-sp-xs) var(--boxel-sp-5xs)
          calc(var(--boxel-sp-xs) + 0.25rem);
      }
      .rail-sublist {
        list-style: none;
        margin: 0;
        padding: 0 0 0 var(--boxel-sp);
      }
      .rail-sublink {
        width: 100%;
        justify-content: flex-start;
      }
      .rail-link {
        position: relative;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        width: 100%;
        transition:
          color 0.15s ease-out,
          border-color 0.15s ease-out,
          background-color 0.15s ease-out;
      }
      .rail-link:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      .rail-link .t {
        font-size: 0.8125rem;
        font-weight: 500;
      }
      .rail-link.current .t {
        color: var(--primary-ink);
        font-weight: 700;
      }
      .page {
        background: var(--card);
        padding: var(--boxel-sp-xl) var(--boxel-sp-xxl, 3.5rem)
          var(--boxel-sp-xxxl, 6rem);
        min-width: 0;

        height: 100%;
        overflow-y: auto;
        box-sizing: border-box;
      }
      .rail-link:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
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
        font-family: var(--font-mono);
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

  @field title = contains(StringField, {
    computeVia: function (this: TalentResourceTracker) {
      return this.name?.trim() || 'Talent & Resource Tracker';
    },
  });

  static isolated = Isolated;

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='trt-atom'>
        <UsersRoundIcon
          class='trt-atom-icon'
          width='14'
          height='14'
          aria-hidden='true'
        />
        <span class='trt-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .trt-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
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

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <div class='fit-top'>
          <span class='glyph' aria-hidden='true'>
            <UsersRoundIcon class='glyph-svg' />
          </span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            <span class='fit-eb'>Applicant tracking &amp; people ops</span>
          </div>
        </div>

        {{! Identity only — no live counts. The collections behind the numbers
            now come from live queries in the isolated view, which a
            prerendered fitted card cannot run; the dashboard inside shows
            every metric. }}
        <p class='fit-desc'>Recruiting pipeline, directory &amp; analytics</p>
      </article>
      <style scoped>
        /* Identity tile: icon, name, subtitle, then a one-line descriptor at
           larger sizes. 0.6875rem floor. */
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
          padding: 0.55rem 0.6rem;
          overflow: hidden;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          border-left: 0.1875rem solid var(--primary);
          --trt-strong: color-mix(
            in oklch,
            var(--primary) 45%,
            var(--foreground)
          );
          --_fit-name: clamp(0.6875rem, 3.2cqi, 0.9375rem);
          --_fit-small: clamp(0.6875rem, 2.6cqi, 0.75rem);
        }
        .fit > * {
          min-height: 0;
          overflow: hidden;
        }
        .fit-top {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: 0.4rem;
          flex-wrap: wrap;
        }
        .glyph {
          flex: none;
          width: 1.6rem;
          height: 1.6rem;
          border-radius: 0.3125rem;
          display: grid;
          place-items: center;
          background: var(--trt-strong);
        }
        .glyph-svg {
          width: 62%;
          height: 62%;
          color: var(--background);
        }
        .fit-head {
          flex: 1;
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--_fit-name);
          font-weight: 700;
          line-height: 1.25;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          display: none;
          font-size: var(--_fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-desc {
          display: none;
          margin: auto 0 0;
          padding-top: 0.3rem;
          border-top: 1px dashed var(--border);
          font-size: var(--_fit-small);
          color: var(--muted-foreground);
          line-height: 1.4;
        }

        /* TIER 2 — add the subtitle. Two rules: container queries have no `or`. */
        @container fitted-card (height > 5rem) {
          .fit-eb {
            display: block;
          }
        }
        @container fitted-card (width > 15rem) {
          .fit-eb {
            display: block;
          }
        }
        /* TIER 3 — add the descriptor line. */
        @container fitted-card (height > 8.125rem) and (width > 11.25rem) {
          .fit-desc {
            display: block;
          }
        }
        /* Short strip: horizontal, descriptor drops. */
        @container fitted-card (height <= 5.625rem) {
          .fit {
            justify-content: center;
          }
          .fit-top {
            align-items: center;
            flex-wrap: nowrap;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (height <= 3.125rem) {
          .glyph {
            width: 1.25rem;
            height: 1.25rem;
          }
          .fit-eb {
            display: none;
          }
        }
      </style>
    </template>
  };
}
