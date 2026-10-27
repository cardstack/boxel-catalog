import { BarList } from '../../../ui-component/components/bar-list';
import { Team } from '../../hr/team';
import { Project } from '../../projects/project';
import { Vendor } from '../../procurement/vendor';
import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { array, fn } from '@ember/helper';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import { Employee } from '../../hr/employee';
import { Candidate } from '../../hr/candidate';
import { Button } from '../../../ui-component/components/button';
import {
  DataTable,
  type DataColumn,
} from '../../../ui-component/components/data-table';
import { EmptyState } from '../../../ui-component/components/empty-state';
import { LoadingState } from '../../../ui-component/components/loading-state';
import { StatusChip } from '../../../ui-component/components/status-chip';
import {
  PageScaffold,
  PageSection,
  type PageStat,
} from '../../../ui-component/components/page-scaffold';
import { DateRangePicker } from '../../../ui-component/components/date-range-picker';
import { Application } from '../../hr/application';
import { durationInDays } from '../../hr/duration-field';
import { daysBetween, isoDay, localDay, toLocalDate } from '../dates';
import type { TrackerView } from '../talent-resource-tracker';
import { AlertPill } from '../shared';
import { UpcomingList } from '../upcoming-list';
import { CardTiles } from '../card-tiles';

type LoadRow = TrackerView['interviewerLoad'][number];
type CalRow = DashboardTab['calibration'][number];

function median(values: number[]): number {
  let sorted = [...values].sort((a, b) => a - b);
  let mid = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[mid]!
    : (sorted[mid - 1]! + sorted[mid]!) / 2;
}

interface Signature {
  Args: {
    tracker: TrackerView;
  };
}

export class DashboardTab extends GlimmerComponent<Signature> {
  // ── Dashboard "needs attention" counts ─────────────────────────────────
  get ptoAwaitingApprovalCount(): number {
    return this.args.tracker.ptoRequests.filter(
      (r) => r.status === 'in-progress',
    ).length;
  }

  get expiringContractorCount(): number {
    return this.args.tracker.contractors.filter(
      (c) =>
        c.status === 'active' &&
        c.daysRemaining != null &&
        c.daysRemaining <= 30,
    ).length;
  }

  get dashboardRangeSelected(): { start: string | null; end: string | null } {
    return {
      start: isoDay(this.args.tracker.dashboardRange.start),
      end: isoDay(this.args.tracker.dashboardRange.end),
    };
  }

  onDashboardRangeSelect = (range: {
    start: string | null;
    end: string | null;
  }) => {
    this.args.tracker.dashboardRange = {
      start: localDay(range.start),
      end: localDay(range.end),
    };
  };

  clearDashboardRange = () => {
    this.args.tracker.dashboardRange = { start: undefined, end: undefined };
    this.args.tracker.dashboardFilterOpen = false;
  };

  toggleDashboardFilter = () => {
    this.args.tracker.dashboardFilterOpen =
      !this.args.tracker.dashboardFilterOpen;
  };

  get dashboardRangeLabel(): string {
    let { start, end } = this.args.tracker.dashboardRange;
    if (!start && !end) {
      return 'All time';
    }
    let fmt = (d?: Date) =>
      d
        ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
        : '…';
    return `${fmt(start)} – ${fmt(end)}`;
  }

  // Application → Candidate has no persisted link (converting an
  // application creates an independent Candidate — see
  // ScreenApplicationCommand). Matching on email, falling back to name,
  // mirrors the only correlation that command itself establishes.
  matchedCandidateFor = (app: Application): Candidate | undefined => {
    let email = app.email?.trim().toLowerCase();
    if (email) {
      let found = this.args.tracker.candidates.find(
        (c) => c.email?.trim().toLowerCase() === email,
      );
      if (found) {
        return found;
      }
    }
    let name = app.name?.trim().toLowerCase();
    if (!name) {
      return undefined;
    }
    return this.args.tracker.candidates.find(
      (c) => c.name?.trim().toLowerCase() === name,
    );
  };

  // Applications grouped by their free-text `source`, with a hire
  // conversion rate per source. Sourced from `appliedDate`-filtered
  // applications so the Dashboard date range narrows this like every other
  // panel.
  get sourceEffectiveness(): Array<{
    source: string;
    applied: number;
    hired: number;
    conversionPct: number;
  }> {
    let applications = this.args.tracker.applications.filter((a) =>
      this.args.tracker.inDashboardRange(a.appliedDate),
    );
    if (!applications.length) {
      return [];
    }
    let groups = new Map<string, Application[]>();
    for (let app of applications) {
      let key = app.source?.trim() || 'Unknown';
      let list = groups.get(key);
      if (!list) {
        list = [];
        groups.set(key, list);
      }
      list.push(app);
    }
    return Array.from(groups.entries())
      .map(([source, apps]) => {
        let applied = apps.length;
        let hired = apps.filter(
          (a) => this.matchedCandidateFor(a)?.status === 'hired',
        ).length;
        let conversionPct =
          applied > 0 ? Math.round((hired / applied) * 100) : 0;
        return { source, applied, hired, conversionPct };
      })
      .sort((a, b) => b.applied - a.applied);
  }

  // Bar length is the conversion rate; the counts behind it ride in the name,
  // since a BarList value prints the number alone.
  get sourceEffectivenessChartData(): Array<{ name: string; value: number }> {
    return this.sourceEffectiveness.map((row) => ({
      name: `${row.source} · ${row.applied} applied · ${row.hired} hired`,
      value: row.conversionPct,
    }));
  }

  formatPercent = (value: number): string => `${value}%`;

  get headcount(): number {
    return this.args.tracker.employees.filter((e) => e.status !== 'offboarded')
      .length;
  }

  get openPipeline(): number {
    return this.args.tracker.candidates.filter(
      (c) => c.status !== 'hired' && c.status !== 'rejected',
    ).length;
  }

  get dashboardPipelinePreview(): {
    key: string;
    label: string;
    candidates: Candidate[];
  }[] {
    let previewStages = ['applied', 'screening', 'interviewing', 'offer'];
    return previewStages.map((stage) => ({
      key: stage,
      label: stage.charAt(0).toUpperCase() + stage.slice(1),
      candidates: this.args.tracker.candidates.filter(
        (c) => c.status === stage,
      ),
    }));
  }

  get avgTimeToHire(): string {
    let candidates = this.args.tracker.candidates.filter((c) =>
      this.args.tracker.inDashboardRange(c.decisionDate ?? c.appliedDate),
    );
    let hired = candidates.filter(
      (c) => c.status === 'hired' && c.timeToHire?.value != null,
    );
    if (!hired.length) {
      return '—';
    }
    let days = hired.map((c) =>
      durationInDays(c.timeToHire?.value, c.timeToHire?.unit),
    );
    return `${Math.round(median(days))} days`;
  }

  get needsUsCount(): number {
    return this.args.tracker.candidates.filter(
      (c) =>
        c.status !== 'hired' &&
        c.status !== 'rejected' &&
        this.args.tracker.whoseTurn(c).tone === 'red',
    ).length;
  }

  get overdueFeedbackCount(): number {
    let now = Date.now();
    return this.args.tracker.meetings.filter(
      (m) =>
        m.date &&
        toLocalDate(m.date).getTime() < now &&
        m.interviewScore == null,
    ).length;
  }

  // A simplified funnel over CURRENT candidate state (this app has no
  // stage-transition history to build a true historical cohort funnel from):
  // each stage counts candidates who have reached that stage or further,
  // excluding anyone rejected. Pass-through % is the ratio to the stage
  // before it; dwell is the average days-since-applied for whoever is
  // sitting AT that exact stage right now.
  get funnelStages(): Array<{
    key: string;
    label: string;
    count: number;
    barPct: number;
    passThroughPct: number | null;
    dwellDays: number | null;
  }> {
    let applications = this.args.tracker.applications.filter((a) =>
      this.args.tracker.inDashboardRange(a.appliedDate),
    );
    let candidates = this.args.tracker.candidates.filter((c) =>
      this.args.tracker.inDashboardRange(c.appliedDate),
    );
    let order: { key: string; label: string }[] = [
      { key: 'applied', label: 'Applied' },
      { key: 'screening', label: 'Screening' },
      { key: 'interviewing', label: 'Interviewing' },
      { key: 'offer', label: 'Offer' },
      { key: 'hired', label: 'Hired' },
    ];
    let reached = (statuses: string[]) =>
      candidates.filter((c) => statuses.includes(c.status ?? '')).length;
    let counts: Record<string, number> = {
      applied: applications.length,
      screening: candidates.length,
      interviewing: reached(['interviewing', 'offer', 'hired']),
      offer: reached(['offer', 'hired']),
      hired: reached(['hired']),
    };
    let maxCount = Math.max(1, ...Object.values(counts));
    let prev: number | null = null;
    return order.map(({ key, label }) => {
      let count = counts[key];
      let passThroughPct =
        prev != null && prev > 0 ? Math.round((count / prev) * 100) : null;
      prev = count;
      let atStage =
        key === 'applied'
          ? applications.filter((a) => a.status !== 'converted')
          : candidates.filter((c) => c.status === key);
      let days = atStage
        .map((item) =>
          item.appliedDate
            ? daysBetween(toLocalDate(item.appliedDate), new Date())
            : null,
        )
        .filter((d): d is number => d != null && d >= 0);
      let dwellDays = days.length ? Math.round(median(days)) : null;
      let barPct = Math.max(4, Math.round((count / maxCount) * 100));
      return { key, label, count, barPct, passThroughPct, dwellDays };
    });
  }

  // Count per stage, in stage order. Pass-through and dwell time ride in the
  // name, since a BarList value prints the number alone.
  get funnelChartData(): Array<{ name: string; value: number }> {
    return this.funnelStages.map((stage) => {
      let parts = [stage.label];
      if (stage.passThroughPct != null) {
        parts.push(`${stage.passThroughPct}% pass-through`);
      }
      if (stage.dwellDays != null) {
        parts.push(`${stage.dwellDays}d median`);
      }
      return { name: parts.join(' · '), value: stage.count };
    });
  }

  get slowestFunnelStage(): { label: string; dwellDays: number } | undefined {
    let candidates = this.funnelStages.filter(
      (s) => s.dwellDays != null && s.key !== 'hired',
    );
    if (!candidates.length) {
      return undefined;
    }
    let slowest = candidates.reduce((a, b) =>
      (b.dwellDays as number) > (a.dwellDays as number) ? b : a,
    );
    return { label: slowest.label, dwellDays: slowest.dwellDays as number };
  }

  get offerRatioLabel(): string {
    let applied = this.args.tracker.applications.filter((a) =>
      this.args.tracker.inDashboardRange(a.appliedDate),
    ).length;
    let hired = this.funnelStages.find((s) => s.key === 'hired')?.count ?? 0;
    if (!applied || !hired) {
      return '—';
    }
    return `${Math.round(applied / hired)}:1`;
  }

  // Calibration — average score an interviewer gives, and how it compares
  // to the app-wide average across everyone else's scored interviews. This
  // surfaces systematically loose or harsh graders, not just busy ones.
  get calibration(): Array<{
    employee: Employee;
    avgScore: number;
    count: number;
    tone: 'amber' | 'green';
    label: string;
  }> {
    let meetings = this.args.tracker.meetings.filter((m) =>
      this.args.tracker.inDashboardRange(m.date),
    );
    let scored = meetings.filter((m) => m.interviewScore != null);
    let overallAvg =
      scored.reduce((sum, m) => sum + (m.interviewScore ?? 0), 0) /
      (scored.length || 1);
    return this.args.tracker.employees
      .filter((e) => e.status !== 'offboarded')
      .map((employee) => {
        let given = scored.filter((m) =>
          (m.interviewers ?? []).some((i) => i?.id === employee.id),
        );
        if (!given.length) {
          return undefined;
        }
        let avgScore =
          given.reduce((sum, m) => sum + (m.interviewScore ?? 0), 0) /
          given.length;
        let delta = avgScore - overallAvg;
        let tone: 'amber' | 'green' =
          Math.abs(delta) >= 0.8 ? 'amber' : 'green';
        let label =
          delta >= 0.8
            ? 'Runs loose'
            : delta <= -0.8
              ? 'Runs harsh'
              : 'On benchmark';
        return { employee, avgScore, count: given.length, tone, label, delta };
      })
      .filter((row): row is NonNullable<typeof row> => Boolean(row))
      .sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta));
  }

  get subtitle(): string {
    let loading = this.args.tracker.isLoading;
    return `Posted through ${this.args.tracker.todayLabel} · ${loading ? '—' : this.headcount} people`;
  }

  // Headline numbers for the PageScaffold stat row.
  get stats(): PageStat[] {
    let slowest = this.slowestFunnelStage;
    let overdue = this.overdueFeedbackCount;
    return [
      {
        label: 'Offer ratio',
        value: this.offerRatioLabel,
        hint: 'Applications per hire',
      },
      {
        label: 'Median hiring cycle',
        value: this.avgTimeToHire,
        hint: 'Median of hires in range',
      },
      {
        label: 'Slowest stage',
        value: slowest ? slowest.label : '—',
        hint: slowest
          ? `${slowest.dwellDays} days median`
          : 'No active candidates',
        hintTone: slowest ? 'danger' : undefined,
      },
      {
        label: 'Needs us',
        value: this.args.tracker.isLoading ? '—' : this.needsUsCount,
        hint: overdue ? `${overdue} feedback overdue` : 'Across the pipeline',
        hintTone: overdue ? 'danger' : undefined,
      },
    ];
  }

  loadKey = (row: LoadRow) => row.employee.id ?? row.employee.name ?? '';
  calibrationKey = (row: CalRow) => row.employee.id ?? row.employee.name ?? '';

  loadColumns: DataColumn<LoadRow>[] = [
    { key: 'name', label: 'Interviewer', width: '14rem' },
    { key: 'hours', label: 'Hours', align: 'end' },
    { key: 'capacity', label: 'Capacity' },
  ];
  calibrationColumns: DataColumn<CalRow>[] = [
    { key: 'name', label: 'Interviewer', width: '14rem' },
    { key: 'avg', label: 'Avg · n', align: 'end' },
    { key: 'calibration', label: 'Calibration' },
  ];

  loadTone = (
    tone: 'red' | 'amber' | 'green',
  ): 'danger' | 'warning' | 'success' =>
    tone === 'red' ? 'danger' : tone === 'amber' ? 'warning' : 'success';
  loadLabel = (tone: 'red' | 'amber' | 'green'): string =>
    tone === 'red'
      ? 'Over capacity'
      : tone === 'amber'
        ? 'Near capacity'
        : 'Has room';
  calibrationTone = (tone: 'amber' | 'green'): 'warning' | 'success' =>
    tone === 'amber' ? 'warning' : 'success';

  <template>
    <PageScaffold
      @title='Dashboard'
      @subtitle={{this.subtitle}}
      @stats={{this.stats}}
    >
      <:actions>
        {{#if @tracker.dashboardRange.start}}
          <Button
            type='button'
            @tone='neutral'
            @appearance='link'
            {{on 'click' this.clearDashboardRange}}
          >Clear</Button>
        {{/if}}
        <Button
          type='button'
          @tone='primary'
          @appearance='accent'
          @shape='pill'
          aria-expanded={{if @tracker.dashboardFilterOpen 'true' 'false'}}
          {{on 'click' this.toggleDashboardFilter}}
        >Filter: {{this.dashboardRangeLabel}}</Button>
      </:actions>
      <:alerts>
        {{#if @tracker.dashboardFilterOpen}}
          <div class='dash-range'>
            <DateRangePicker
              @value={{this.dashboardRangeSelected}}
              @onValueChange={{this.onDashboardRangeSelect}}
            />
          </div>
        {{/if}}
      </:alerts>
      <:default>
        {{#if (or this.expiringContractorCount this.ptoAwaitingApprovalCount)}}
          <div class='dash-alerts' role='group' aria-label='Needs attention'>
            {{#if this.expiringContractorCount}}
              <AlertPill
                @tone='warning'
                @onClick={{fn @tracker.setTab 'Contractors'}}
              >{{this.expiringContractorCount}}
                contractor
                {{if
                  (eq this.expiringContractorCount 1)
                  'contract'
                  'contracts'
                }}
                ending ≤30d →</AlertPill>
            {{/if}}
            {{#if this.ptoAwaitingApprovalCount}}
              <AlertPill
                @tone='danger'
                @onClick={{fn @tracker.setTab 'PTO'}}
              >{{this.ptoAwaitingApprovalCount}}
                PTO
                {{if (eq this.ptoAwaitingApprovalCount 1) 'request' 'requests'}}
                awaiting approval →</AlertPill>
            {{/if}}
          </div>
        {{/if}}
        <div class='dash-main'>
          <PageSection class='dash-panel' @title='Candidate pipeline'>
            <:aside>
              <Button
                type='button'
                @tone='neutral'
                @appearance='link'
                {{on 'click' (fn @tracker.setTab 'Pipeline')}}
              >View full board →</Button>
            </:aside>
            <:default>
              <div class='dash-board'>
                {{#each this.dashboardPipelinePreview as |col|}}
                  <section class='dash-col' aria-label={{col.label}}>
                    <h3 class='dash-col-head'>
                      <span>{{col.label}}</span>
                      <span class='dash-n'>{{if
                          @tracker.isLoading
                          '—'
                          col.candidates.length
                        }}</span>
                    </h3>
                    <CardTiles
                      @cards={{col.candidates}}
                      @size='double-strip'
                      @list={{true}}
                      @onOpen={{@tracker.openCard}}
                    />
                  </section>
                {{/each}}
              </div>
            </:default>
          </PageSection>

          <PageSection class='dash-panel' @title='Funnel'>
            <:aside>
              <span class='dash-meta'>{{this.openPipeline}} active</span>
            </:aside>
            <:default>
              <BarList
                @rows={{this.funnelChartData}}
                @ranked={{false}}
                @label='Hiring funnel'
              />
            </:default>
          </PageSection>
        </div>

        <div class='dash-ops'>
          <PageSection class='dash-panel' @title='Interviewer load'>
            <:aside>
              <span class='dash-meta'>This week</span>
            </:aside>
            <:default>
              <DataTable
                @loading={{@tracker.isLoading}}
                @columns={{this.loadColumns}}
                @rows={{@tracker.interviewerLoad}}
                @key={{this.loadKey}}
                @label='Interviewer load this week'
                @columnMenu={{false}}
                @sortable={{false}}
                @striped={{false}}
              >
                <:empty>{{#if @tracker.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No interviews scheduled this week'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'name')}}
                    <CardTiles
                      @cards={{array row.employee}}
                      @size='single-strip'
                      @list={{true}}
                      @onOpen={{@tracker.openCard}}
                    />
                  {{else if (eq col.key 'hours')}}
                    {{row.hours}}h
                  {{else if (eq col.key 'capacity')}}
                    <StatusChip
                      @value={{this.loadLabel row.tone}}
                      @tone={{this.loadTone row.tone}}
                    />
                  {{else}}
                    {{text}}
                  {{/if}}
                </:cell>
              </DataTable>
            </:default>
          </PageSection>

          <PageSection class='dash-panel' @title='Score calibration'>
            <:aside>
              <span class='dash-meta'>Scored interviews</span>
            </:aside>
            <:default>
              <DataTable
                @loading={{@tracker.isLoading}}
                @columns={{this.calibrationColumns}}
                @rows={{this.calibration}}
                @key={{this.calibrationKey}}
                @label='Score calibration'
                @columnMenu={{false}}
                @sortable={{false}}
                @striped={{false}}
              >
                <:empty>{{#if @tracker.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No scored interviews yet'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'name')}}
                    <CardTiles
                      @cards={{array row.employee}}
                      @size='single-strip'
                      @list={{true}}
                      @onOpen={{@tracker.openCard}}
                    />
                  {{else if (eq col.key 'avg')}}
                    ★{{row.avgScore}}
                    ·
                    {{row.count}}
                  {{else if (eq col.key 'calibration')}}
                    <StatusChip
                      @value={{row.label}}
                      @tone={{this.calibrationTone row.tone}}
                    />
                  {{else}}
                    {{text}}
                  {{/if}}
                </:cell>
              </DataTable>
            </:default>
          </PageSection>

          <PageSection class='dash-panel' @title='Upcoming'>
            <:aside>
              <Button
                type='button'
                @tone='neutral'
                @appearance='link'
                {{on 'click' (fn @tracker.setTab 'Calendar')}}
              >Open calendar →</Button>
            </:aside>
            <:default>
              <UpcomingList
                @meetings={{@tracker.meetings}}
                @loading={{@tracker.isLoading}}
                @onOpen={{@tracker.openCard}}
              />
            </:default>
          </PageSection>
        </div>

        <PageSection class='dash-panel' @title='Source effectiveness'>
          <:aside>
            <span class='dash-meta'>{{if
                @tracker.isLoading
                '—'
                this.sourceEffectiveness.length
              }}
              sources</span>
          </:aside>
          <:default>
            {{#if this.sourceEffectiveness.length}}
              <BarList
                @rows={{this.sourceEffectivenessChartData}}
                @format={{this.formatPercent}}
                @label='Source effectiveness'
              />
            {{else}}
              {{#if @tracker.isLoading}}<LoadingState
                  @label='Loading'
                />{{else}}<EmptyState
                  @size='s'
                  @texture={{false}}
                  @title='No applications in this range'
                />{{/if}}
            {{/if}}
          </:default>
        </PageSection>

        <PageSection class='dash-panel' @title='Teams'>
          <:aside>
            {{#if @tracker.canCreate}}
              <Button
                type='button'
                @tone='neutral'
                @appearance='outlined'
                @size='s'
                @shape='pill'
                @loading={{@tracker.addCard.isRunning}}
                {{on 'click' (fn @tracker.addNew Team)}}
              >+ Add team</Button>
            {{/if}}
          </:aside>
          <:default>
            {{#if @tracker.teams.length}}
              <CardTiles
                @cards={{@tracker.teams}}
                @size='double-strip'
                @onOpen={{@tracker.openCard}}
              />
            {{else}}
              {{#if @tracker.teamsQuery.isLoading}}<LoadingState
                  @label='Loading'
                />{{else}}<EmptyState
                  @size='s'
                  @texture={{false}}
                  @title='No teams yet'
                />{{/if}}
            {{/if}}
          </:default>
        </PageSection>

        <div class='dash-pair'>
          <PageSection class='dash-panel' @title='Projects'>
            <:aside>
              {{#if @tracker.canCreate}}
                <Button
                  type='button'
                  @tone='neutral'
                  @appearance='outlined'
                  @size='s'
                  @shape='pill'
                  @loading={{@tracker.addCard.isRunning}}
                  {{on 'click' (fn @tracker.addNew Project)}}
                >+ Add project</Button>
              {{/if}}
            </:aside>
            <:default>
              {{#if @tracker.projects.length}}
                <CardTiles
                  @cards={{@tracker.projects}}
                  @size='single-strip'
                  @list={{true}}
                  @onOpen={{@tracker.openCard}}
                />
              {{else}}
                {{#if @tracker.projectsQuery.isLoading}}<LoadingState
                    @label='Loading'
                  />{{else}}<EmptyState
                    @size='s'
                    @texture={{false}}
                    @title='No projects yet'
                  />{{/if}}
              {{/if}}
            </:default>
          </PageSection>

          <PageSection class='dash-panel' @title='Vendors'>
            <:aside>
              {{#if @tracker.canCreate}}
                <Button
                  type='button'
                  @tone='neutral'
                  @appearance='outlined'
                  @size='s'
                  @shape='pill'
                  @loading={{@tracker.addCard.isRunning}}
                  {{on 'click' (fn @tracker.addNew Vendor)}}
                >+ Add vendor</Button>
              {{/if}}
            </:aside>
            <:default>
              {{#if @tracker.vendors.length}}
                <CardTiles
                  @cards={{@tracker.vendors}}
                  @size='single-strip'
                  @list={{true}}
                  @onOpen={{@tracker.openCard}}
                />
              {{else}}
                {{#if @tracker.vendorsQuery.isLoading}}<LoadingState
                    @label='Loading'
                  />{{else}}<EmptyState
                    @size='s'
                    @texture={{false}}
                    @title='No vendors yet'
                  />{{/if}}
              {{/if}}
            </:default>
          </PageSection>
        </div>
      </:default>
    </PageScaffold>
    <style scoped>
      .dash-alerts {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      /* every section is an IMS panel: white, soft shadow, no border */
      .dash-panel {
        padding: var(--boxel-sp-lg);
        border-radius: var(--radius);
        background: var(--card);
        box-shadow: var(--shadow-md);
      }
      .dash-range {
        margin-bottom: var(--boxel-sp-sm);
      }
      .dash-meta {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
        font-weight: 400;
        font-variant-numeric: tabular-nums;
      }
      .dash-n {
        color: var(--muted-foreground);
        font-weight: 400;
        font-variant-numeric: tabular-nums;
      }
      .dash-board {
        display: grid;
        grid-template-columns: repeat(4, minmax(9rem, 1fr));
        gap: var(--boxel-sp-sm);
        overflow-x: auto;
      }
      .dash-col {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-width: 0;
        padding: var(--boxel-sp-sm);
        border-radius: var(--radius);
        background-color: var(--muted);
      }
      .dash-col-head {
        display: flex;
        justify-content: space-between;
        margin: 0;
        padding: 0 var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      /* the mockup's grids: board 2.2fr beside the funnel, then
         auto-fit rows of panels */
      .dash-main,
      .dash-ops,
      .dash-pair {
        display: grid;
        gap: var(--boxel-sp-lg);
      }
      .dash-main {
        grid-template-columns: minmax(0, 2.2fr) minmax(16.25rem, 1fr);
      }
      .dash-ops,
      .dash-pair {
        grid-template-columns: repeat(auto-fit, minmax(17.5rem, 1fr));
      }
      @container tracker (max-width: 60rem) {
        .dash-main {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    </style>
  </template>
}
