import type { ComponentLike } from '@glint/template';
import { BarList } from '@cardstack/pretui/components/bar-list';
import { Team } from '../../hr/team';
import { Project } from '../../projects/project';
import { Vendor } from '../../procurement/vendor';
import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import { Employee } from '../../hr/employee';
import { Candidate, CandidateStatusField } from '../../hr/candidate';
import { Button } from '@cardstack/pretui/components/button';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { DateRangePicker } from '@cardstack/pretui/components/date-range-picker';
import { Application } from '../../hr/application';
import { durationInDays } from '../../hr/duration-field';
import { daysBetween, isoDay, localDay, toLocalDate } from '../dates';
import type { TrackerView } from '../talent-resource-tracker';
import {
  AlertPill,
  getComponent,
  TrackerPage,
  TrackerSection,
  TrackerEmpty,
  StatusDot,
  type TrackerStat,
} from '../shared';
import { tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Menu } from '@cardstack/pretui/components/menu';
import type { MenuSignature } from '@cardstack/pretui/components/menu';
import CalendarIcon from '@cardstack/boxel-icons/calendar';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { UpcomingList } from '../upcoming-list';

type MenuEntry = MenuSignature['Args']['items'][number];

type LoadRow = TrackerView['interviewerLoad'][number];
type CalRow = DashboardTab['calibration'][number];
interface PipeRow {
  candidate: Candidate;
  name: string;
  role: string;
  stage: string;
  days: number;
  turn: { tone: 'red' | 'amber' | 'green'; label: string };
}

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
  // the stage column renders the field's own format: dot + label
  StageAtom = CandidateStatusField.atom as unknown as ComponentLike<{
    Args: { model: string | undefined };
  }>;
  // ── Range control: the mock's 7 days / 30 days / Quarter / Custom ──────
  rangeOptions = [
    { value: '7', label: '7 days' },
    { value: '30', label: '30 days' },
    { value: '90', label: 'Quarter' },
    { value: 'custom', label: 'Custom' },
  ];
  rangeForms = [
    { name: 'segments', minWidth: 20 },
    { name: 'dropdown', minWidth: 6.5 },
    { name: 'icon', minWidth: 1.625 },
  ];
  calendarIcon = CalendarIcon;
  plusIcon = PlusIcon;
  @tracked customPicked = false;

  // which preset the current range is, matched on its length ending today
  get rangePreset(): string {
    let { start, end } = this.args.tracker.dashboardRange;
    if (this.customPicked || !start) {
      return this.customPicked ? 'custom' : '';
    }
    let days = Math.round(daysBetween(start, end ?? new Date()) ?? 0);
    return ['7', '30', '90'].find((d) => Number(d) === days) ?? 'custom';
  }
  get rangeCurrent(): string {
    return (
      this.rangeOptions.find((o) => o.value === this.rangePreset)?.label ??
      'All time'
    );
  }
  pickRange = (value: string) => {
    let t = this.args.tracker;
    if (value === 'custom') {
      this.customPicked = true;
      t.dashboardFilterOpen = true;
      return;
    }
    this.customPicked = false;
    let end = new Date();
    let start = new Date(end);
    start.setDate(end.getDate() - Number(value));
    t.dashboardRange = { start, end };
    t.dashboardFilterOpen = false;
  };
  get rangeItems(): MenuEntry[] {
    return this.rangeOptions.map((o) => ({
      kind: 'radio' as const,
      group: 'range',
      label: o.label,
      checked: this.rangePreset === o.value,
      onSelect: () => this.pickRange(o.value),
    }));
  }

  // ── Needs attention: one line when wide, one summary row when narrow ────
  @tracked alertsOpen = false;
  toggleAlerts = () => (this.alertsOpen = !this.alertsOpen);
  get attentionCount(): number {
    return this.expiringContractorCount + this.ptoAwaitingApprovalCount;
  }

  // ── Pipeline by name: columns drop by the section's width ──────────────
  @tracked pipelineWidth = 0;
  measurePipeline = modifier((el: HTMLElement) => {
    let ro = new ResizeObserver(([e]) => {
      this.pipelineWidth = e?.contentRect.width ?? 0;
    });
    ro.observe(el);
    return () => ro.disconnect();
  });
  pipelineColumns: DataColumn<PipeRow>[] = [
    { key: 'name', label: 'Candidate' },
    { key: 'role', label: 'Role' },
    { key: 'stage', label: 'Stage' },
    { key: 'days', label: 'Days', align: 'end', mono: true },
    { key: 'next', label: 'Next' },
  ];
  get pipelineVisible(): string[] {
    let w = this.pipelineWidth;
    let keys = ['name'];
    if (w >= 480) keys.push('role');
    keys.push('stage', 'days');
    if (w >= 640) keys.push('next');
    return keys;
  }
  get pipelineRows(): PipeRow[] {
    let t = this.args.tracker;
    let now = new Date();
    return t.candidates
      .filter((c) => c.status !== 'hired' && c.status !== 'rejected')
      .map((c) => ({
        candidate: c,
        name: c.name ?? '',
        role: c.appliedRole ?? '',
        stage: c.status
          ? c.status.charAt(0).toUpperCase() + c.status.slice(1)
          : '',
        days: Math.round(daysBetween(c.appliedDate, now) ?? 0),
        turn: t.whoseTurn(c),
      }))
      .sort((a, b) => b.days - a.days);
  }
  pipelineKey = (row: PipeRow) => row.candidate.id ?? row.name;
  turnTone = (tone: 'red' | 'amber' | 'green') => this.loadTone(tone);

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
  // excluding anyone rejected. Dwell is the average days-since-applied for whoever is
  // sitting AT that exact stage right now.
  get funnelStages(): Array<{
    key: string;
    label: string;
    count: number;
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
    return order.map(({ key, label }) => {
      let count = counts[key];
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
      return { key, label, count, dwellDays };
    });
  }

  // Count per stage, in stage order. Dwell time rides in the name, since a
  // BarList value prints the number alone.
  get funnelChartData(): Array<{ name: string; value: number }> {
    return this.funnelStages.map((stage) => {
      let parts = [stage.label];
      if (stage.dwellDays != null) {
        parts.push(`${stage.dwellDays} d median`);
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
    let t = this.args.tracker;
    return `${t.rangeLabel} · ${loading ? '—' : this.openPipeline} active candidates across ${loading ? '—' : t.positions.length} open roles · ${loading ? '—' : this.headcount} people.`;
  }

  // Headline numbers for the PageScaffold stat row.
  get stats(): TrackerStat[] {
    let slowest = this.slowestFunnelStage;
    let overdue = this.overdueFeedbackCount;
    return [
      {
        label: 'Offer ratio',
        dot: 'success',
        value: this.offerRatioLabel,
        hint: 'Applications per hire',
      },
      {
        label: 'Median hiring cycle',
        dot: 'info',
        value: this.avgTimeToHire,
        hint: 'Median of hires in range',
      },
      {
        label: 'Slowest stage',
        dot: 'warning',
        value: slowest ? slowest.label : '—',
        hint: slowest
          ? `${slowest.dwellDays} days median`
          : 'No active candidates',
        hintTone: slowest ? 'danger' : undefined,
      },
      {
        label: 'Needs us',
        dot: 'destructive',
        value: this.args.tracker.isLoading ? '—' : this.needsUsCount,
        hint: overdue ? `${overdue} feedback overdue` : 'Across the pipeline',
        hintTone: overdue ? 'danger' : undefined,
      },
    ];
  }

  loadKey = (row: LoadRow) => row.employee.id ?? row.employee.name ?? '';
  // both dashboard tables carry the card as row.employee

  calibrationKey = (row: CalRow) => row.employee.id ?? row.employee.name ?? '';

  loadColumns: DataColumn<LoadRow>[] = [
    { key: 'name', label: 'Interviewer' },
    { key: 'hours', label: 'Hours', align: 'end' },
    { key: 'capacity', label: 'Capacity' },
  ];
  calibrationColumns: DataColumn<CalRow>[] = [
    { key: 'name', label: 'Interviewer' },
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
    <div class='dash'>
      <TrackerPage
        @group='Hiring'
        @title='Dashboard'
        @subtitle={{this.subtitle}}
        @stats={{this.stats}}
      >
        <:actions as |bar|>
          <bar.Slot
            @id='range'
            @priority={{1}}
            @forms={{this.rangeForms}}
            as |form|
          >
            {{#if (eq form 'segments')}}
              <span class='dash-asof'>As of</span>
              <SegmentedControl
                @options={{this.rangeOptions}}
                @value={{this.rangePreset}}
                @onValueChange={{this.pickRange}}
                @label='Range'
              />
            {{else}}
              <Menu @items={{this.rangeItems}} @label='Range'>
                <:trigger as |_open toggle|>
                  {{#if (eq form 'icon')}}
                    <IconButton
                      @label='Range: {{this.rangeCurrent}}'
                      @icon={{this.calendarIcon}}
                      {{on 'click' toggle}}
                    />
                  {{else}}
                    <Button
                      type='button'
                      @size='xs'
                      @tone='neutral'
                      @appearance='outlined'
                      {{on 'click' toggle}}
                    >{{this.rangeCurrent}}</Button>
                  {{/if}}
                </:trigger>
              </Menu>
            {{/if}}
          </bar.Slot>
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
          {{#if this.attentionCount}}
            <div class='dash-attn'>
              <button
                type='button'
                class='dash-attn-short'
                aria-expanded={{if this.alertsOpen 'true' 'false'}}
                {{on 'click' this.toggleAlerts}}
              ><span
                  class='dash-dot'
                  aria-hidden='true'
                ></span>{{this.attentionCount}}
                need attention<span class='dash-attn-sum'>contracts
                  {{this.expiringContractorCount}}
                  · PTO
                  {{this.ptoAwaitingApprovalCount}}
                  ▾</span></button>
              <div
                class='dash-alerts'
                role='group'
                aria-label='Needs attention'
                data-open={{if this.alertsOpen 'true'}}
              >
                <span class='dash-cap'>Needs attention</span>
                {{#if this.expiringContractorCount}}
                  <AlertPill
                    @tone='warning'
                    @onClick={{fn @tracker.setTab 'Contractors'}}
                  >{{this.expiringContractorCount}}
                    contractor
                    {{if
                      (eq this.expiringContractorCount 1)
                      'contract ends'
                      'contracts end'
                    }}
                    within 30 days</AlertPill>
                {{/if}}
                {{#if this.ptoAwaitingApprovalCount}}
                  <AlertPill
                    @tone='danger'
                    @onClick={{fn @tracker.setTab 'PTO'}}
                  >{{this.ptoAwaitingApprovalCount}}
                    PTO
                    {{if
                      (eq this.ptoAwaitingApprovalCount 1)
                      'request'
                      'requests'
                    }}
                    awaiting approval</AlertPill>
                {{/if}}
              </div>
            </div>
          {{/if}}

          <div class='dash-grid'>
            <TrackerSection @title='Candidate pipeline' @meta='by stage'>
              <:aside>
                <Button
                  type='button'
                  @size='xs'
                  @tone='neutral'
                  @appearance='link'
                  {{on 'click' (fn @tracker.setTab 'Pipeline')}}
                >Full board</Button>
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
                      <ul class='dash-col-list'>
                        {{#each col.candidates as |c|}}
                          <li><Button
                              type='button'
                              @tone='neutral'
                              @appearance='plain'
                              @size='xs'
                              class='dash-person'
                              {{on 'click' (fn @tracker.openCard c)}}
                            >{{#let (getComponent c) as |Atom|}}{{#if
                                  Atom
                                }}<Atom
                                    @format='atom'
                                    @displayContainer={{false}}
                                  />{{/if}}{{/let}}</Button></li>
                        {{/each}}
                      </ul>
                    </section>
                  {{/each}}
                </div>
              </:default>
            </TrackerSection>
            <div class='dash-stack'>
              <TrackerSection
                @title='Funnel'
                @meta='{{this.openPipeline}} active'
                @padded={{true}}
              >
                <BarList
                  @rows={{this.funnelChartData}}
                  @ranked={{false}}
                  @label='Hiring funnel'
                />
              </TrackerSection>
              <TrackerSection @title='Interviewer load' @meta='this week'>
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
                    @flush={{true}}
                    @size='xs'
                  >
                    <:empty>{{#if @tracker.isLoading}}<LoadingState
                          @label='Loading'
                        />{{else}}<TrackerEmpty>No interviews scheduled this
                          week</TrackerEmpty>{{/if}}</:empty>
                    <:cell as |text row col|>
                      {{#if (eq col.key 'name')}}
                        <Button
                          type='button'
                          @tone='neutral'
                          @appearance='plain'
                          @size='xs'
                          class='dash-person'
                          {{on 'click' (fn @tracker.openCard row.employee)}}
                        >{{#let (getComponent row.employee) as |Atom|}}{{#if
                              Atom
                            }}<Atom
                                @format='atom'
                                @displayContainer={{false}}
                              />{{/if}}{{/let}}</Button>
                      {{else if (eq col.key 'hours')}}
                        {{row.hours}}h
                      {{else if (eq col.key 'capacity')}}
                        <StatusDot
                          @tone={{this.loadTone row.tone}}
                          @label={{this.loadLabel row.tone}}
                        />
                      {{else}}
                        {{text}}
                      {{/if}}
                    </:cell>
                  </DataTable>
                </:default>
              </TrackerSection>

            </div>
          </div>

          <div {{this.measurePipeline}}>
            <TrackerSection
              @title='Pipeline by name'
              @meta='{{this.pipelineRows.length}} active'
            >
              <:aside>
                <Button
                  type='button'
                  @size='xs'
                  @tone='neutral'
                  @appearance='link'
                  {{on 'click' (fn @tracker.setTab 'Pipeline')}}
                >Full board</Button>
              </:aside>
              <:default>
                <DataTable
                  @loading={{@tracker.isLoading}}
                  @columns={{this.pipelineColumns}}
                  @visibleColumns={{this.pipelineVisible}}
                  @rows={{this.pipelineRows}}
                  @key={{this.pipelineKey}}
                  @label='Pipeline by name'
                  @columnMenu={{false}}
                  @sortable={{false}}
                  @striped={{false}}
                  @flush={{true}}
                  @size='xs'
                >
                  <:empty>{{#if @tracker.isLoading}}<LoadingState
                        @label='Loading'
                      />{{else}}<TrackerEmpty>No active candidates</TrackerEmpty>{{/if}}</:empty>
                  <:cell as |text row col|>
                    {{#if (eq col.key 'name')}}
                      <Button
                        type='button'
                        @tone='neutral'
                        @appearance='plain'
                        @size='xs'
                        class='dash-person'
                        {{on 'click' (fn @tracker.openCard row.candidate)}}
                      >{{#let (getComponent row.candidate) as |Atom|}}{{#if
                            Atom
                          }}<Atom
                              @format='atom'
                              @displayContainer={{false}}
                            />{{/if}}{{/let}}</Button>
                    {{else if (eq col.key 'next')}}
                      <StatusDot
                        @tone={{this.turnTone row.turn.tone}}
                        @label={{row.turn.label}}
                      />
                    {{else if (eq col.key 'stage')}}
                      <this.StageAtom @model={{row.candidate.status}} />
                    {{else if (eq col.key 'role')}}
                      <span class='dash-muted'>{{text}}</span>
                    {{else}}
                      {{text}}
                    {{/if}}
                  </:cell>
                </DataTable>
              </:default>
            </TrackerSection>
          </div>

          <div class='dash-joined'>
            <TrackerSection class='dash-part' @title='Teams'>
              <:aside>
                {{#if @tracker.canCreate}}
                  <Button
                    type='button'
                    @size='xs'
                    @tone='neutral'
                    @appearance='link'
                    @loading={{@tracker.addCard.isRunning}}
                    @icon={{this.plusIcon}}
                    {{on 'click' (fn @tracker.addNew Team)}}
                  >Add team</Button>
                {{/if}}
              </:aside>
              <:default>
                {{#if @tracker.teams.length}}
                  <ul class='dash-rows'>
                    {{#each @tracker.teams as |c|}}
                      <li><Button
                          type='button'
                          @tone='neutral'
                          @appearance='plain'
                          @size='xs'
                          class='dash-person'
                          {{on 'click' (fn @tracker.openCard c)}}
                        >{{#let (getComponent c) as |Atom|}}{{#if Atom}}<Atom
                                @format='atom'
                                @displayContainer={{false}}
                              />{{/if}}{{/let}}</Button></li>
                    {{/each}}
                  </ul>
                {{else}}
                  {{#if @tracker.teamsQuery.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<TrackerEmpty>No teams yet</TrackerEmpty>{{/if}}
                {{/if}}
              </:default>
            </TrackerSection>

            <div class='dash-pair'>
              <TrackerSection class='dash-part' @title='Projects'>
                <:aside>
                  {{#if @tracker.canCreate}}
                    <Button
                      type='button'
                      @size='xs'
                      @tone='neutral'
                      @appearance='link'
                      @loading={{@tracker.addCard.isRunning}}
                      @icon={{this.plusIcon}}
                      {{on 'click' (fn @tracker.addNew Project)}}
                    >Add project</Button>
                  {{/if}}
                </:aside>
                <:default>
                  {{#if @tracker.projects.length}}
                    <ul class='dash-rows'>
                      {{#each @tracker.projects as |c|}}
                        <li><Button
                            type='button'
                            @tone='neutral'
                            @appearance='plain'
                            @size='xs'
                            class='dash-person'
                            {{on 'click' (fn @tracker.openCard c)}}
                          >{{#let (getComponent c) as |Atom|}}{{#if Atom}}<Atom
                                  @format='atom'
                                  @displayContainer={{false}}
                                />{{/if}}{{/let}}</Button></li>
                      {{/each}}
                    </ul>
                  {{else}}
                    {{#if @tracker.projectsQuery.isLoading}}<LoadingState
                        @label='Loading'
                      />{{else}}<TrackerEmpty>No projects yet</TrackerEmpty>{{/if}}
                  {{/if}}
                </:default>
              </TrackerSection>

              <TrackerSection class='dash-part' @title='Vendors'>
                <:aside>
                  {{#if @tracker.canCreate}}
                    <Button
                      type='button'
                      @size='xs'
                      @tone='neutral'
                      @appearance='link'
                      @loading={{@tracker.addCard.isRunning}}
                      @icon={{this.plusIcon}}
                      {{on 'click' (fn @tracker.addNew Vendor)}}
                    >Add vendor</Button>
                  {{/if}}
                </:aside>
                <:default>
                  {{#if @tracker.vendors.length}}
                    <ul class='dash-rows'>
                      {{#each @tracker.vendors as |c|}}
                        <li><Button
                            type='button'
                            @tone='neutral'
                            @appearance='plain'
                            @size='xs'
                            class='dash-person'
                            {{on 'click' (fn @tracker.openCard c)}}
                          >{{#let (getComponent c) as |Atom|}}{{#if Atom}}<Atom
                                  @format='atom'
                                  @displayContainer={{false}}
                                />{{/if}}{{/let}}</Button></li>
                      {{/each}}
                    </ul>
                  {{else}}
                    {{#if @tracker.vendorsQuery.isLoading}}<LoadingState
                        @label='Loading'
                      />{{else}}<TrackerEmpty>No vendors yet</TrackerEmpty>{{/if}}
                  {{/if}}
                </:default>
              </TrackerSection>
            </div>
          </div>

          <div class='dash-extra'>
            <TrackerSection
              @title='Score calibration'
              @meta='scored interviews'
            >
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
                  @flush={{true}}
                  @size='xs'
                >
                  <:empty>{{#if @tracker.isLoading}}<LoadingState
                        @label='Loading'
                      />{{else}}<TrackerEmpty>No scored interviews yet</TrackerEmpty>{{/if}}</:empty>
                  <:cell as |text row col|>
                    {{#if (eq col.key 'name')}}
                      <Button
                        type='button'
                        @tone='neutral'
                        @appearance='plain'
                        @size='xs'
                        class='dash-person'
                        {{on 'click' (fn @tracker.openCard row.employee)}}
                      >{{#let (getComponent row.employee) as |Atom|}}{{#if
                            Atom
                          }}<Atom
                              @format='atom'
                              @displayContainer={{false}}
                            />{{/if}}{{/let}}</Button>
                    {{else if (eq col.key 'avg')}}
                      <span class='dash-avg'>★{{row.avgScore}}
                        ·
                        {{row.count}}</span>
                    {{else if (eq col.key 'calibration')}}
                      <StatusDot
                        @tone={{this.calibrationTone row.tone}}
                        @label={{row.label}}
                      />
                    {{else}}
                      {{text}}
                    {{/if}}
                  </:cell>
                </DataTable>
              </:default>
            </TrackerSection>

            <TrackerSection @title='Source effectiveness' @padded={{true}}>
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
                    />{{else}}<TrackerEmpty>No applications in this range</TrackerEmpty>{{/if}}
                {{/if}}
              </:default>
            </TrackerSection>

          </div>

          <div class='dash-upcoming-flow'>
            <TrackerSection @title='Upcoming'>
              <:aside><Button
                  type='button'
                  @size='xs'
                  @tone='neutral'
                  @appearance='link'
                  {{on 'click' (fn @tracker.setTab 'Calendar')}}
                >Calendar</Button></:aside>
              <:default><UpcomingList
                  @meetings={{@tracker.meetings}}
                  @loading={{@tracker.isLoading}}
                  @onOpen={{@tracker.openCard}}
                /></:default>
            </TrackerSection>
          </div>
        </:default>
      </TrackerPage>
      <aside class='dash-dock' aria-label='Upcoming'>
        <TrackerSection @title='Upcoming' @flat={{true}}>
          <:aside><Button
              type='button'
              @size='xs'
              @tone='neutral'
              @appearance='link'
              {{on 'click' (fn @tracker.setTab 'Calendar')}}
            >Calendar</Button></:aside>
          <:default><UpcomingList
              @meetings={{@tracker.meetings}}
              @loading={{@tracker.isLoading}}
              @onOpen={{@tracker.openCard}}
            /></:default>
        </TrackerSection>
      </aside>
    </div>
    <style scoped>
      /* the page scrolls; Upcoming docks flush right (300px) when wide */
      .dash {
        display: flex;
        height: 100%;
        min-height: 0;
      }
      .dash > :first-child {
        flex: 1;
        min-width: 0;
      }
      .dash-dock {
        display: none;
        flex: none;
        inline-size: 18.75rem;
        overflow-y: auto;
        background: var(--card);
        border-left: 1px solid var(--border);
      }
      @container tracker (width >= 1320px) {
        .dash-dock {
          display: block;
        }
        .dash-upcoming-flow {
          display: none;
        }
      }
      .dash-asof {
        margin-inline-end: var(--boxel-sp-2xs);
        font: 600 calc(var(--trt-fs) * 0.75) / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      .dash-cap {
        font: 600 calc(var(--trt-fs) * 0.75) / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      /* one alerts line between two hairlines; one summary row when narrow */
      .dash-alerts {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-4xs) var(--boxel-sp-lg);
        padding: var(--trt-py) 0;
        border-block: 1px solid var(--border);
      }
      .dash-attn-short {
        display: none;
        align-items: center;
        gap: var(--boxel-sp-2xs);
        inline-size: 100%;
        block-size: 2.125rem;
        padding: 0;
        border: 0;
        border-block: 1px solid var(--border);
        background: none;
        color: var(--foreground);
        font: 700 var(--boxel-font-size-sm) var(--font-sans);
        cursor: pointer;
      }
      .dash-attn-short:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 0.125rem;
      }
      .dash-dot {
        inline-size: 0.4375rem;
        block-size: 0.4375rem;
        border-radius: 50%;
        background: var(--destructive);
      }
      .dash-attn-sum {
        margin-left: auto;
        font: 500 var(--boxel-font-size-2xs) var(--font-mono);
        color: var(--muted-foreground);
      }
      @container (width < 40rem) {
        .dash-attn-short {
          display: flex;
        }
        .dash-alerts {
          display: none;
          border-top: 0;
        }
        .dash-alerts[data-open] {
          display: flex;
        }
      }
      /* the mock's two-column grid: queue beside Funnel + Interviewer load */
      .dash-grid {
        display: grid;
        grid-template-columns: minmax(0, 1.15fr) minmax(0, 1fr);
        gap: var(--trt-gap);
        align-items: start;
      }
      .dash-stack,
      .dash-extra {
        display: grid;
        gap: var(--trt-gap);
        min-width: 0;
      }
      .dash-extra {
        grid-template-columns: repeat(auto-fit, minmax(17.5rem, 1fr));
        align-items: start;
      }
      @container (width < 52rem) {
        .dash-grid {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      /* Teams / Projects / Vendors: one card, three hairline-split parts */
      .dash-joined {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      .dash-joined .dash-pair {
        display: contents;
      }
      .dash-part {
        border: 0;
        border-radius: 0;
        border-inline-start: 1px solid var(--border);
      }
      .dash-part:first-child {
        border-inline-start: 0;
      }
      @container (width < 48rem) {
        .dash-joined {
          grid-template-columns: minmax(0, 1fr);
        }
        .dash-part {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
        .dash-part:first-child {
          border-block-start: 0;
        }
      }
      /* the name cell is the row's open control; the atom carries the look */
      .dash-person {
        --pretui-button-h: 0;
        --pretui-button-px: 0;
        --employee-atom-avatar-size: 1.25rem;
      }
      .dash-range {
        margin-bottom: var(--trt-gap);
      }
      .dash-avg {
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
      }
      .dash-meta,
      .dash-muted {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-2xs);
      }
      .dash-n {
        color: var(--muted-foreground);
        font-weight: 400;
        font-variant-numeric: tabular-nums;
      }
      .dash-board {
        display: grid;
        grid-template-columns: repeat(4, minmax(7rem, 1fr));
        overflow-x: auto;
        border-top: 1px solid var(--border);
      }
      /* flat columns split by a hairline: never rounded inside rounded */
      .dash-col {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        min-width: 0;
        padding: var(--trt-py) var(--trt-px);
        border-inline-start: 1px solid var(--border);
      }
      .dash-col:first-child {
        border-inline-start: 0;
      }
      /* the mock's joined lists: 30px rows split by hairlines */
      .dash-rows {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .dash-rows li {
        display: flex;
        align-items: center;
        min-height: 1.875rem;
        padding: 0 var(--trt-px);
        border-top: 1px solid var(--border);
        min-width: 0;
        overflow: hidden;
      }
      .dash-col-list {
        display: grid;
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .dash-col-list li {
        display: flex;
        align-items: center;
        min-height: var(--trt-rowh);
        min-width: 0;
        overflow: hidden;
      }
      .dash-col-head {
        display: flex;
        justify-content: space-between;
        margin: 0;
        font: 600 calc(var(--trt-fs) * 0.75) / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
    </style>
  </template>
}
