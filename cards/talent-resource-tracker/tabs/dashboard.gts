import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import { htmlSafe } from '@ember/template';
import { Employee } from '../../hr/employee';
import { Candidate } from '../../hr/candidate';
import { Team } from '../../hr/team';
import { Project, PROJECT_STATUS_COLORS } from '../../projects/project';
import { Vendor } from '../../procurement/vendor';
import { BarList } from '@cardstack/pretui/components/bar-list';
import { Button } from '@cardstack/pretui/components/button';
import { DateRangePicker } from '@cardstack/pretui/components/date-range-picker';
import { Application } from '../../hr/application';
import { durationInDays } from '../../hr/duration-field';
import { daysBetween, isoDay, localDay, toLocalDate } from '../dates';
import { stateColorOf } from '../../../components/state-pill';
import type { TrackerView } from '../talent-resource-tracker';

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

  get openReqs(): number {
    return this.args.tracker.positions.filter((p) => p.status === 'open')
      .length;
  }

  get dashboardPipelinePreview(): {
    key: string;
    label: string;
    candidates: Candidate[];
  }[] {
    let previewStages = ['applied', 'screening', 'interviewing', 'offer'];
    return previewStages.map((stage) => ({
      key: stage,
      label: stage,
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

  projectDotStyle = (status?: string | null) => {
    let color = stateColorOf(PROJECT_STATUS_COLORS, status);
    return htmlSafe(`background: ${color.ring};`);
  };

  get upcomingMeetings(): Array<{
    id?: string;
    title: string;
    day: string;
    month: string;
    timeLabel: string;
  }> {
    let now = new Date();
    return this.args.tracker.calendarEvents
      .filter((event) => event.date.getTime() >= now.getTime())
      .slice(0, 5)
      .map((event) => ({
        id: event.id,
        title: event.title,
        day: String(event.date.getDate()),
        month: event.date
          .toLocaleDateString('en-US', { month: 'short' })
          .toUpperCase(),
        timeLabel: event.date.toLocaleTimeString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
        }),
      }));
  }

  <template>
    <div class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Dashboard</h2>
          <p class='byline'>{{@tracker.todayLabel}}
            ·
            {{if @tracker.isLoading '—' this.headcount}}
            people,
            {{this.openReqs}}
            open roles</p>
        </div>
      </div>

      <div class='dashboard-filters'>
        <Button
          type='button'
          @tone='primary'
          @appearance='accent'
          class='btn-review'
          aria-expanded='{{@tracker.dashboardFilterOpen}}'
          {{on 'click' this.toggleDashboardFilter}}
        >Filter: {{this.dashboardRangeLabel}}</Button>
        {{#if @tracker.dashboardRange.start}}
          <Button
            type='button'
            @appearance='link'
            class='board-link'
            {{on 'click' this.clearDashboardRange}}
          >Clear</Button>
        {{/if}}
        {{#if @tracker.dashboardFilterOpen}}
          <div class='dashboard-range-popover'>
            <DateRangePicker
              @value={{this.dashboardRangeSelected}}
              @onValueChange={{this.onDashboardRangeSelect}}
            />
          </div>
        {{/if}}
      </div>

      <div class='dashboard-top'>
        <div class='dashboard-left'>
          <div class='stats-row'>
            <div class='stat-card hero'>
              <div class='stat-label'>Offer Ratio</div>
              <div class='stat-value'>{{this.offerRatioLabel}}</div>
              <div class='stat-trend'>Applications per hire</div>
            </div>
            <div class='stat-card'>
              <div class='stat-label'>Median Hiring Cycle</div>
              <div class='stat-value'>{{this.avgTimeToHire}}</div>
              <div class='stat-trend'>Median of hires in range</div>
            </div>
            <div class='stat-card'>
              <div class='stat-label'>Slowest Stage</div>
              {{#if this.slowestFunnelStage}}
                <div class='stat-value stat-value-sm'>
                  {{this.slowestFunnelStage.label}}
                </div>
                <div class='stat-trend stat-trend-bad'>
                  {{this.slowestFunnelStage.dwellDays}}
                  days median
                </div>
              {{else}}
                <div class='stat-value'>—</div>
                <div class='stat-trend'>No active candidates</div>
              {{/if}}
            </div>
            <div class='stat-card'>
              <div class='stat-label'>Needs Us</div>
              <div class='stat-value'>{{if
                  @tracker.isLoading
                  '—'
                  this.needsUsCount
                }}</div>
              {{#if this.overdueFeedbackCount}}
                <div class='stat-trend stat-trend-bad'>
                  {{this.overdueFeedbackCount}}
                  feedback overdue
                </div>
              {{else}}
                <div class='stat-trend'>Across the pipeline</div>
              {{/if}}
            </div>
          </div>

          {{#if
            (or this.expiringContractorCount this.ptoAwaitingApprovalCount)
          }}
            <div class='attn-row' role='group' aria-label='Needs attention'>
              {{#if this.expiringContractorCount}}
                <Button
                  type='button'
                  @tone='neutral'
                  @appearance='plain'
                  class='attn-chip attn-amber'
                  {{on 'click' (fn @tracker.setTab 'Contractors')}}
                >{{this.expiringContractorCount}}
                  contractor
                  {{if
                    (eq this.expiringContractorCount 1)
                    'contract'
                    'contracts'
                  }}
                  ending ≤30d →</Button>
              {{/if}}
              {{#if this.ptoAwaitingApprovalCount}}
                <Button
                  type='button'
                  @tone='neutral'
                  @appearance='plain'
                  class='attn-chip attn-red'
                  {{on 'click' (fn @tracker.setTab 'PTO')}}
                >{{this.ptoAwaitingApprovalCount}}
                  PTO
                  {{if
                    (eq this.ptoAwaitingApprovalCount 1)
                    'request'
                    'requests'
                  }}
                  awaiting approval →</Button>
              {{/if}}
            </div>
          {{/if}}

          <div class='board-head'>
            <h2>Candidate Pipeline</h2>
            <Button
              type='button'
              @appearance='link'
              class='board-link'
              {{on 'click' (fn @tracker.setTab 'Pipeline')}}
            >View full board →</Button>
          </div>
          <div class='board-preview'>
            {{#each this.dashboardPipelinePreview as |col|}}
              <div class='pcol'>
                <div class='pcol-head'>
                  <span>{{col.label}}</span>
                  <span class='pcol-count'>{{if
                      @tracker.isLoading
                      '—'
                      col.candidates.length
                    }}</span>
                </div>
                {{#each col.candidates as |candidate|}}
                  <Button
                    @tone='neutral'
                    @appearance='filled'
                    class='kcard'
                    {{on 'click' (fn @tracker.openCard candidate)}}
                  >
                    <span class='kavatar'>{{candidate.initials}}</span>
                    <span class='kmeta'>
                      <span class='kname'>{{candidate.name}}</span>
                      <span class='krole'>{{candidate.appliedRole}}</span>
                    </span>
                  </Button>
                {{/each}}
              </div>
            {{/each}}
          </div>
        </div>

        <div class='chart-card'>
          <div class='chart-card-head'>
            <span class='chart-title'>Funnel</span>
            <span class='chart-total'>{{this.openPipeline}}
              active</span>
          </div>
          <BarList
            @rows={{this.funnelChartData}}
            @ranked={{false}}
            @label='Hiring funnel'
          />
        </div>
      </div>

      <div class='chart-card source-effectiveness-card'>
        <div class='chart-card-head'>
          <span class='chart-title'>Source Effectiveness</span>
          <span class='chart-total'>{{if
              @tracker.isLoading
              '—'
              this.sourceEffectiveness.length
            }}
            sources</span>
        </div>
        {{#if this.sourceEffectiveness.length}}
          <BarList
            @rows={{this.sourceEffectivenessChartData}}
            @format={{this.formatPercent}}
            @label='Source effectiveness'
          />
        {{else}}
          <p class='empty-note' role='status'>No applications in this range</p>
        {{/if}}
      </div>

      <div class='ops-row'>
        <div class='ops-col'>
          <div class='col-h'>Interviewer Load · This Week</div>
          {{#if @tracker.interviewerLoad.length}}
            <table class='data-table'>
              <tbody>
                {{#each @tracker.interviewerLoad as |row|}}
                  <tr>
                    <td>{{row.employee.name}}</td>
                    <td class='num'>{{row.hours}}h</td>
                    <td>
                      <span class='status-pill pill-{{row.tone}}'>
                        {{if
                          (eq row.tone 'red')
                          'Over capacity'
                          (if (eq row.tone 'amber') 'Near capacity' 'Has room')
                        }}
                      </span>
                    </td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          {{else}}
            <p class='empty-note' role='status'>No interviews scheduled this
              week</p>
          {{/if}}
        </div>
        <div class='ops-col'>
          <div class='col-h'>Score Calibration · Scored Interviews</div>
          {{#if this.calibration.length}}
            <table class='data-table'>
              <tbody>
                {{#each this.calibration as |row|}}
                  <tr>
                    <td>{{row.employee.name}}</td>
                    <td class='num'>★{{row.avgScore}}
                      avg ·
                      {{row.count}}</td>
                    <td>
                      <span class='status-pill pill-{{row.tone}}'>
                        {{row.label}}
                      </span>
                    </td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          {{else}}
            <p class='empty-note' role='status'>No scored interviews yet</p>
          {{/if}}
        </div>
      </div>

      <div class='upcoming-card'>
        <div class='board-head'>
          <h2>Upcoming</h2>
          <Button
            type='button'
            @appearance='link'
            class='board-link'
            {{on 'click' (fn @tracker.setTab 'Calendar')}}
          >Open calendar →</Button>
        </div>
        {{#if this.upcomingMeetings.length}}
          <div class='upcoming-list'>
            {{#each this.upcomingMeetings as |meeting|}}
              <Button
                @tone='neutral'
                @appearance='filled'
                class='upcoming-row'
                {{on 'click' (fn @tracker.openCard meeting)}}
              >
                <span class='upcoming-date'>
                  <span class='upcoming-day'>{{meeting.day}}</span>
                  <span class='upcoming-month'>{{meeting.month}}</span>
                </span>
                <span class='upcoming-info'>
                  <span class='upcoming-title'>{{meeting.title}}</span>
                  <span class='upcoming-time'>{{meeting.timeLabel}}</span>
                </span>
              </Button>
            {{/each}}
          </div>
        {{else}}
          <p class='empty-note' role='status'>Nothing scheduled</p>
        {{/if}}
      </div>

      <div class='accounts'>
        <section class='account-col'>
          <div class='account-col-head'>
            <h2>Teams</h2>
            {{#if @tracker.canCreate}}
              <Button
                type='button'
                @tone='primary'
                @appearance='accent'
                class='btn-review'
                @loading={{@tracker.addCard.isRunning}}
                {{on 'click' (fn @tracker.addNew Team)}}
              >+ Add</Button>
            {{/if}}
          </div>
          {{#if @tracker.teams.length}}
            <ul class='account-list'>
              {{#each @tracker.teams as |team|}}
                <li>
                  <Button
                    @tone='neutral'
                    @appearance='plain'
                    class='account-row'
                    {{on 'click' (fn @tracker.openCard team)}}
                  >
                    <span class='account-name'>{{team.title}}</span>
                    <span class='account-meta'>{{team.headcount}}</span>
                  </Button>
                </li>
              {{/each}}
            </ul>
          {{else if @tracker.teamsQuery.isLoading}}
            <p class='empty-note' role='status'>Loading…</p>
          {{else}}
            <p class='empty-note' role='status'>No teams yet</p>
          {{/if}}
        </section>
        <section class='account-col'>
          <div class='account-col-head'>
            <h2>Projects</h2>
            {{#if @tracker.canCreate}}
              <Button
                type='button'
                @tone='primary'
                @appearance='accent'
                class='btn-review'
                @loading={{@tracker.addCard.isRunning}}
                {{on 'click' (fn @tracker.addNew Project)}}
              >+ Add</Button>
            {{/if}}
          </div>
          {{#if @tracker.projects.length}}
            <ul class='account-list'>
              {{#each @tracker.projects as |project|}}
                <li>
                  <Button
                    @tone='neutral'
                    @appearance='plain'
                    class='account-row'
                    {{on 'click' (fn @tracker.openCard project)}}
                  >
                    <span
                      class='dot'
                      style={{this.projectDotStyle project.status}}
                    ></span>
                    <span class='account-name'>{{project.title}}</span>
                    <span class='account-meta'>{{project.status}}</span>
                  </Button>
                </li>
              {{/each}}
            </ul>
          {{else if @tracker.projectsQuery.isLoading}}
            <p class='empty-note' role='status'>Loading…</p>
          {{else}}
            <p class='empty-note' role='status'>No projects yet</p>
          {{/if}}
        </section>
        <section class='account-col'>
          <div class='account-col-head'>
            <h2>Vendors</h2>
            {{#if @tracker.canCreate}}
              <Button
                type='button'
                @tone='primary'
                @appearance='accent'
                class='btn-review'
                @loading={{@tracker.addCard.isRunning}}
                {{on 'click' (fn @tracker.addNew Vendor)}}
              >+ Add</Button>
            {{/if}}
          </div>
          {{#if @tracker.vendors.length}}
            <ul class='account-list'>
              {{#each @tracker.vendors as |vendor|}}
                <li>
                  <Button
                    @tone='neutral'
                    @appearance='plain'
                    class='account-row'
                    {{on 'click' (fn @tracker.openCard vendor)}}
                  >
                    <span class='account-name'>{{vendor.title}}</span>
                    <span class='account-meta'>{{vendor.serviceCategory}}</span>
                  </Button>
                </li>
              {{/each}}
            </ul>
          {{else if @tracker.vendorsQuery.isLoading}}
            <p class='empty-note' role='status'>Loading…</p>
          {{else}}
            <p class='empty-note' role='status'>No vendors yet</p>
          {{/if}}
        </section>
      </div>
    </div>
    <style scoped>
      .sec-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp);
        padding-bottom: var(--boxel-sp);
        border-bottom: 0.125rem solid var(--card-foreground);
        margin: 0 0 var(--boxel-sp-lg);
      }
      .sec-head .htext {
        margin-right: auto;
      }
      .sec-head .htext h2 {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 1.25rem;
        margin: 0 0 0.1875rem;
      }
      .sec-head .htext .byline {
        font-family: var(--font-mono);
        font-size: 0.7188rem;
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0;
      }
      .attn-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
        margin-bottom: var(--boxel-sp);
      }
      .attn-chip {
        letter-spacing: 0.02em;
        cursor: pointer;
        min-height: 0;
      }
      .attn-amber {
        color: color-mix(in oklch, var(--warning) 38%, var(--card-foreground));
      }
      .attn-red {
        color: color-mix(
          in oklch,
          var(--destructive) 38%,
          var(--card-foreground)
        );
      }
      .account-row:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      .tab-section {
        animation: tracker-tab-fade-in 0.2s ease-out;
      }
      @keyframes tracker-tab-fade-in {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .tab-section {
          animation: none;
        }
      }
      .dashboard-top {
        display: grid;
        grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
        gap: var(--boxel-sp);
        margin-bottom: var(--boxel-sp-lg);
        align-items: start;
      }
      @container tracker (max-width: 48rem) {
        .dashboard-top {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      .dashboard-left {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-lg);
        min-height: 100%;
      }
      .stats-row {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8.75rem, 1fr));
        gap: var(--boxel-sp);
      }
      .stat-card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        box-shadow: var(--shadow-xs);
      }
      .stat-card.hero {
        background: var(--primary);
        border-color: var(--primary);
        color: var(--primary-foreground);
      }
      .stat-card.hero .stat-label,
      .stat-card.hero .stat-value,
      .stat-card.hero .stat-trend {
        color: var(--primary-foreground);
      }
      .stat-card.hero .stat-label,
      .stat-card.hero .stat-trend {
        opacity: 0.8;
      }
      .stat-label {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .stat-value {
        margin-top: var(--boxel-sp-4xs);
        font-family: var(--font-sans);
        font-size: 1.75rem;
        font-weight: 800;
        letter-spacing: -0.02em;
        line-height: 1;
        font-variant-numeric: tabular-nums;
        color: var(--card-foreground);
      }
      .stat-trend {
        margin-top: var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        color: var(--success-ink);
      }
      .chart-card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        box-shadow: var(--shadow-xs);
      }
      .chart-card-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        margin-bottom: var(--boxel-sp-xs);
      }
      .chart-title {
        font-size: var(--boxel-font-size-sm);
        font-weight: 700;
      }
      .chart-total {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .stat-value-sm {
        font-size: 1.1rem;
      }
      .stat-trend-bad {
        color: color-mix(
          in oklch,
          var(--destructive) 38%,
          var(--card-foreground)
        );
      }
      .dashboard-filters {
        position: relative;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        margin-bottom: var(--boxel-sp);
      }
      .dashboard-range-popover {
        position: absolute;
        top: calc(100% + var(--boxel-sp-4xs));
        left: 0;
        z-index: 2;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        box-shadow: var(--shadow-lg);
        padding: var(--boxel-sp);
      }
      .source-effectiveness-card {
        margin-bottom: var(--boxel-sp-lg);
      }
      .ops-row {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(16.25rem, 1fr));
        gap: var(--boxel-sp);
        margin-bottom: var(--boxel-sp-lg);
      }
      .ops-col {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        box-shadow: var(--shadow-xs);
      }
      .ops-col .col-h {
        font-size: var(--boxel-font-size-sm);
        font-weight: 700;
        margin-bottom: var(--boxel-sp-xs);
      }
      .ops-col .data-table {
        margin-top: 0;
      }
      .board-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        margin: 0 0 var(--boxel-sp);
      }
      .board-head h2 {
        margin: 0;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size);
        font-weight: 700;
      }
      .board-preview {
        display: flex;
        gap: var(--boxel-sp);
        overflow-x: auto;
        padding-bottom: var(--boxel-sp-4xs);
      }
      .pcol {
        display: flex;
        flex-direction: column;
        flex: 1 0 11.25rem;
        min-width: 11.25rem;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm);
        border-radius: 0.85rem;
        background: var(--muted);
      }
      .pcol-head {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        color: var(--muted-foreground);
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      .pcol-count {
        background: var(--card);
        border-radius: 62.4375rem;
        padding: 0.05rem 0.5rem;
        font-weight: 700;
      }
      .kcard {
        width: 100%;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        color: inherit;
        cursor: pointer;
        text-align: left;
      }
      .kavatar {
        width: 1.9rem;
        height: 1.9rem;
        border-radius: 50%;
        background: var(--primary-ink);
        color: var(--card);
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: 700;
        font-size: 0.72rem;
        flex: none;
      }
      .kmeta {
        display: flex;
        flex-direction: column;
        min-width: 0;
      }
      .kname {
        font-weight: 700;
        font-size: var(--boxel-font-size-sm);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .krole {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .upcoming-card {
        margin-top: var(--boxel-sp-lg);
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: 1.25rem;
        background: var(--card);
        box-shadow: var(--shadow-xs);
      }
      .upcoming-list {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(13.75rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .upcoming-row {
        width: 100%;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        color: inherit;
        cursor: pointer;
        text-align: left;
      }
      .upcoming-date {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        width: 2.5rem;
        height: 2.5rem;
        flex: none;
        border-radius: 0.5rem;
        background: var(--card);
        border: 1px solid var(--border);
      }
      .upcoming-day {
        font-weight: 700;
        font-size: var(--boxel-font-size-sm);
        line-height: 1;
      }
      .upcoming-month {
        font-size: 0.5625rem;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: var(--muted-foreground);
      }
      .upcoming-info {
        display: flex;
        flex-direction: column;
        min-width: 0;
      }
      .upcoming-title {
        font-weight: 700;
        font-size: var(--boxel-font-size-sm);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .upcoming-time {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .accounts {
        margin-top: var(--boxel-sp-xl);
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(12.5rem, 1fr));
        gap: var(--boxel-sp-lg);
      }
      .account-col h2 {
        font-family: var(--font-sans);
        font-size: 0.875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.03em;
        margin: 0 0 var(--boxel-sp-xs);
        padding-bottom: var(--boxel-sp-5xs);
        border-bottom: 1px solid var(--card-foreground);
      }
      .account-col-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        border-bottom: 1px solid var(--card-foreground);
        margin-bottom: var(--boxel-sp-xs);
      }
      .account-col-head h2 {
        border-bottom: none;
        margin-bottom: 0;
      }
      .account-col-head .btn-review {
        margin-bottom: var(--boxel-sp-5xs);
      }
      .account-list {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .account-list li {
        border-bottom: 1px dotted var(--border);
      }
      .account-list li:last-child {
        border-bottom: none;
      }
      .account-row {
        width: 100%;
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        color: inherit;
        cursor: pointer;
        text-align: left;
        transition: color 0.15s ease-out;
      }
      .account-row:hover {
        color: var(--primary-ink);
      }
      .dot {
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
        flex: none;
        margin-top: 0.3rem;
      }
      .account-name {
        font-weight: 600;
        font-size: var(--boxel-font-size-sm);
      }
      .account-meta {
        font-family: var(--font-mono);
        font-size: 0.6562rem;
        color: var(--muted-foreground);
        margin-left: auto;
        white-space: nowrap;
        text-transform: capitalize;
      }
      .empty-note {
        margin: var(--boxel-sp-xs) 0 0;
        font-family: var(--font-mono);
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .data-table {
        width: 100%;
        border-collapse: collapse;
        font-size: var(--boxel-font-size-sm);
      }
      .data-table th {
        text-align: left;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: var(--muted-foreground);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
      }
      .data-table td {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
      }
      .data-table tbody tr:last-child td {
        border-bottom: none;
      }
      .data-table tbody tr:hover {
        background: var(--muted);
      }
      .status-pill {
        display: inline-block;
        padding: 0.125rem 0.5rem;
        border-radius: 62.4375rem;
        font-size: 0.6875rem;
        text-transform: capitalize;
        white-space: nowrap;
      }
      .sec-head {
        flex: none;
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
