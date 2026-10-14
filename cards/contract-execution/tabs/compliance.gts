import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { cssVar } from '@cardstack/boxel-ui/helpers';
import { CONTRACT_STATUSES } from '../../legal/contract-status';
import { riskGradeLabel } from '../../legal/contract-risk';
import { formatMoney } from '../../commerce/line-item-totals';
import { StatePill, type Hue } from '../../../components/state-pill';

import {
  personLabelOrUndefined,
  scaleBands,
  toLocalDate,
} from '../contract-execution-data';
import { NoticeTable } from './notice-table';

interface Signature {
  Args: { app: ContractExecutionView };
}

export class ComplianceTab extends GlimmerComponent<Signature> {
  get compliancePct(): number {
    let s = this.args.app.complianceScore;
    return typeof s === 'number' ? s : 0;
  }

  // ---- compliance ---------------------------------------------------------

  // ---- compliance analytics ----------------------------------------------

  /**
   * Median days from approval start to signature.
   *
   * Median, not mean: one contract that sat for nine months would drag a mean
   * far away from what a typical contract actually takes.
   */
  get medianExecutionDays(): number | undefined {
    let spans = this.args.app.contracts
      .map((c: any) => {
        let start = c.approvalChain?.startedAt;
        let end = c.signedAt;
        if (!start || !end) return undefined;
        let d =
          (toLocalDate(end).getTime() - new Date(start).getTime()) / 86_400_000;
        return d >= 0 ? Math.round(d) : undefined;
      })
      .filter((n): n is number => typeof n === 'number')
      .sort((a, b) => a - b);
    if (!spans.length) return undefined;
    let mid = Math.floor(spans.length / 2);
    return spans.length % 2
      ? spans[mid]
      : Math.round((spans[mid - 1]! + spans[mid]!) / 2);
  }

  /** Contracts grouped by the currency of their value; amounts never mix. */
  get contractsByCurrency(): Map<string, any[]> {
    let groups = new Map<string, any[]>();
    for (let c of this.args.app.contracts as any[]) {
      if (typeof c?.value?.amount !== 'number') continue;
      let code = c.value.currency?.code ?? '';
      groups.set(code, [...(groups.get(code) ?? []), c]);
    }
    return groups;
  }

  /** One total per currency, e.g. "USD 1,200.00 · EUR 500.00". */
  get portfolioValueLabel(): string {
    let parts = [...this.contractsByCurrency].map(([code, cards]) =>
      formatMoney(
        cards.reduce((n: number, c: any) => n + c.value.amount, 0),
        code || undefined,
      ),
    );
    return parts.filter(Boolean).join(' · ') || '—';
  }

  /** Names the nearest deadline rather than restating the count beside it. */
  get noticeLede(): string {
    let next = this.args.app.renewalRows[0] as any;
    if (!next) return 'Nothing to serve';
    return `${next.cardTitle} — ${next.daysToNotice}d to act`;
  }

  get deviationCount(): number {
    return this.args.app.clauseUses.filter((u: any) => u?.isDeviation).length;
  }

  get unapprovedDeviations(): number {
    return this.args.app.clauseUses.filter(
      (u: any) => u?.isDeviation && u?.deviationSeverity !== 'approved',
    ).length;
  }

  /**
   * Exposure by risk grade, weighted by VALUE rather than by count.
   *
   * Four low-value contracts at medium risk are not the same exposure as one
   * large one, and a count chart says they are.
   */
  get valueByRisk() {
    let grades = ['critical', 'high', 'medium', 'low'];
    let multi = this.contractsByCurrency.size > 1;
    let bands: any[] = [];
    // Each currency is banded and scaled on its own: a bar compares
    // amounts in one currency only.
    for (let [code, cards] of this.contractsByCurrency) {
      let rows = grades
        .map((grade) => {
          let total = cards
            .filter((c: any) => c.riskGrade === grade)
            .reduce((n: number, c: any) => n + c.value.amount, 0);
          return {
            grade,
            label: multi
              ? `${riskGradeLabel(grade)} · ${code || 'no currency'}`
              : riskGradeLabel(grade),
            count: total,
            amount: total,
            currency: code || undefined,
            hue: (grade === 'critical'
              ? 'red'
              : grade === 'high'
                ? 'orange'
                : grade === 'medium'
                  ? 'amber'
                  : 'green') as Hue,
          };
        })
        .filter((row) => row.count > 0);
      bands.push(
        ...scaleBands(rows).map((row) => ({
          ...row,
          money: formatMoney(row.amount, row.currency),
        })),
      );
    }
    return bands;
  }

  /**
   * Median days each approval step is held.
   *
   * NOT the artifact's "time in stage" — that needs a stage-transition history
   * the realm does not record, and inventing one would put a fabricated number
   * on a compliance screen. This answers the same question ("where does it
   * stall") from `openedAt`/`decidedAt`, which are real.
   */
  get timeByStep() {
    let byRole = new Map<string, number[]>();
    for (let c of this.args.app.contracts as any[]) {
      for (let st of c.approvalChain?.steps ?? []) {
        if (!st?.openedAt) continue;
        let end = st.decidedAt ? new Date(st.decidedAt).getTime() : Date.now();
        let days = Math.round(
          (end - new Date(st.openedAt).getTime()) / 86_400_000,
        );
        if (days < 0) continue;
        let key = personLabelOrUndefined(st.approver) || 'Unassigned';
        byRole.set(key, [...(byRole.get(key) ?? []), days]);
      }
    }
    let rows = [...byRole.entries()].map(([label, ds]) => {
      let sorted = ds.sort((a, b) => a - b);
      let mid = Math.floor(sorted.length / 2);
      let median =
        sorted.length % 2
          ? sorted[mid]!
          : Math.round((sorted[mid - 1]! + sorted[mid]!) / 2);
      return { label, count: median };
    });
    let worst = Math.max(0, ...rows.map((r) => r.count));
    return scaleBands(rows).map((r) => ({
      ...r,
      // the slowest step is where intervening pays — mark it, don't make the
      // reader compare four numbers to find it
      isWorst: r.count === worst && worst > 0,
    }));
  }

  /**
   * Compliance by contract — which agreements are actually carrying the risk.
   *
   * The portfolio score says 50%; it does not say WHICH contract is failing,
   * which is the only version of the number anyone can act on.
   */
  get complianceByContract() {
    let rows = this.args.app.contracts
      .map((c: any) => {
        let obs = this.args.app.obligationsAll.filter(
          (o: any) => o?.contract?.id === c.id,
        );
        let open = obs.filter((o: any) => o.status !== 'closed');
        let met = open.filter(
          (o: any) => o.status === 'on_track' || o.status === 'due_soon',
        );
        return {
          id: c.id,
          label: c.cardTitle ?? c.contractNumber ?? 'Untitled',
          total: open.length,
          met: met.length,
          count: open.length ? Math.round((met.length / open.length) * 100) : 0,
          overdue: open.length - met.length,
        };
      })
      // A contract with no obligations has no compliance to report — showing
      // it at 0% would read as failing when nothing is owed.
      .filter((r) => r.total > 0)
      .sort((a, b) => a.count - b.count);
    return scaleBands(rows).map((r) => ({ ...r, pct: r.count }));
  }

  /** True when no month in the window had anything due — say so, don't draw a flat line at zero. */
  get trendHasData(): boolean {
    return this.complianceTrend.some((m) => m.n > 0);
  }

  get statusBands() {
    let rows = CONTRACT_STATUSES.map((o) => ({
      value: o.value,
      label: o.label ?? o.value,
      hue: (o.hue ?? 'slate') as Hue,
      count: this.args.app.contracts.filter((c) => c.status === o.value).length,
    })).filter((b) => b.count);
    return scaleBands(rows);
  }

  /**
   * Compliance trend, from the obligations' own completion dates.
   *
   * Six months back, each point = share of obligations due in that month that
   * were closed. Derived, not stored: the realm keeps no snapshot history, and
   * a fabricated series on a compliance screen is worse than no series.
   */
  get complianceTrend() {
    let now = new Date();
    let months: { label: string; pct: number; n: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      let start = new Date(now.getFullYear(), now.getMonth() - i, 1);
      let end = new Date(now.getFullYear(), now.getMonth() - i + 1, 1);
      let due = this.args.app.obligationsAll.filter((o: any) => {
        let d = o?.nextDueDate ? toLocalDate(o.nextDueDate) : null;
        return d && d >= start && d < end;
      });
      let done = due.filter((o: any) => o?.closedAt);
      months.push({
        label: start.toLocaleString(undefined, { month: 'short' }),
        pct: due.length ? Math.round((done.length / due.length) * 100) : 0,
        n: due.length,
      });
    }
    return months;
  }

  <template>
    <section class='cx-sec' aria-label='Compliance'>
      <div class='cx-kpis'>
        <div class='cx-kpi'>
          <p class='cx-kpi-l'>Median execution time</p>
          {{#if this.medianExecutionDays}}
            <p class='cx-kpi-v'>{{this.medianExecutionDays}}<span
                class='cx-kpi-u'
              >d</span></p>
            <p class='cx-kpi-d'>Approval start to signature</p>
          {{else}}
            <p class='cx-kpi-v is-none'>—</p>
            <p class='cx-kpi-d'>No contract yet has both an approval start and a
              signature date</p>
          {{/if}}
        </div>

        <div class='cx-kpi'>
          <p class='cx-kpi-l'>Obligations met</p>
          <p class='cx-kpi-v'>{{@app.complianceLabel}}</p>
          <ProgressBar
            class='cx-meter'
            @value={{this.compliancePct}}
            @max={{100}}
            @hue='var(--primary)'
            aria-label='Share of open obligations being met'
          />
        </div>

        <div class='cx-kpi'>
          <p class='cx-kpi-l'>Clause deviations</p>
          <p
            class='cx-kpi-v {{if this.unapprovedDeviations "is-alarm"}}'
          >{{this.deviationCount}}</p>
          <p class='cx-kpi-d'>{{this.unapprovedDeviations}}
            unapproved</p>
        </div>

        <div class='cx-kpi'>
          <p class='cx-kpi-l'>Notice inside 90 days</p>
          <p class='cx-kpi-v'>{{@app.noticeSoonCount}}</p>
          <p class='cx-kpi-d'>{{this.noticeLede}}</p>
        </div>
      </div>

      <div class='cx-charts'>
        <section class='cx-chart' aria-label='Contracts by lifecycle stage'>
          <h2 class='cx-h'>By lifecycle stage
            <span class='cx-h-sub'>{{@app.contracts.length}}
              contracts</span></h2>
          {{#each this.statusBands as |b|}}
            <div class='cx-band'>
              <StatePill @label={{b.label}} @hue={{b.hue}} @dot={{true}} />
              <span class='cx-bar' aria-hidden='true'><span
                  class='cx-bar-fill cx-hue-{{b.hue}}'
                  style={{cssVar _cx-pct=b.pct}}
                ></span></span>
              <span class='cx-num'>{{b.count}}</span>
            </div>
          {{else}}
            <p class='cx-empty'>No contracts yet.</p>
          {{/each}}
          <p class='cx-chart-note'>Bars scale to the largest band, so an even
            split reads as even rather than as four invisible slivers.</p>
        </section>

        <section class='cx-chart' aria-label='Portfolio value by risk grade'>
          <h2 class='cx-h'>Portfolio value by risk grade
            <span class='cx-h-sub'>{{this.portfolioValueLabel}}</span></h2>
          {{#each this.valueByRisk as |b|}}
            <div class='cx-band'>
              <StatePill @label={{b.label}} @hue={{b.hue}} @dot={{true}} />
              <span class='cx-bar' aria-hidden='true'><span
                  class='cx-bar-fill cx-hue-{{b.hue}}'
                  style={{cssVar _cx-pct=b.pct}}
                ></span></span>
              <span class='cx-num is-money'>{{b.money}}</span>
            </div>
          {{else}}
            <p class='cx-empty'>No contract carries both a risk grade and a
              value.</p>
          {{/each}}
          <p class='cx-chart-note'>Weighted by value, not by count — four
            low-value contracts are not the same exposure as one large one.</p>
        </section>

        <section class='cx-chart' aria-label='Compliance by contract'>
          <h2 class='cx-h'>By contract
            <span class='cx-h-sub'>worst first</span></h2>
          {{#each this.complianceByContract as |b|}}
            <div class='cx-band'>
              <span class='cx-band-l'>{{b.label}}</span>
              <span class='cx-bar' aria-hidden='true'><span
                  class='cx-bar-fill
                    {{if b.overdue "cx-hue-red" "cx-hue-green"}}'
                  style={{cssVar _cx-pct=b.pct}}
                ></span></span>
              <span class='cx-num'>{{b.count}}%</span>
            </div>
          {{else}}
            <p class='cx-empty'>No contract has an open obligation yet.</p>
          {{/each}}
          <p class='cx-chart-note'>A contract with nothing owed is left out
            rather than shown at 0% — no obligations is not the same as failing
            them.</p>
        </section>

        <section class='cx-chart' aria-label='Compliance trend'>
          <h2 class='cx-h'>Trend
            <span class='cx-h-sub'>last 6 months</span></h2>
          {{#if this.trendHasData}}
            {{#each this.complianceTrend as |m|}}
              <div class='cx-band'>
                <span class='cx-band-l'>{{m.label}}</span>
                <span class='cx-bar' aria-hidden='true'><span
                    class='cx-bar-fill cx-hue-accent'
                    style={{cssVar _cx-pct=m.pct}}
                  ></span></span>
                <span class='cx-num'>{{if m.n m.pct '—'}}</span>
              </div>
            {{/each}}
            <p class='cx-chart-note'>Share of obligations due that month that
              were closed. Derived from completion dates — the realm stores no
              snapshots, and a fabricated series on a compliance screen is worse
              than none.</p>
          {{else}}
            <p class='cx-empty'>Nothing fell due in the last six months, so
              there is no trend to draw yet.</p>
          {{/if}}
        </section>

        <section
          class='cx-chart'
          aria-label='Median days held per approval step'
        >
          <h2 class='cx-h'>Time per approval step
            <span class='cx-h-sub'>median days</span></h2>
          {{#each this.timeByStep as |b|}}
            <div class='cx-band'>
              <span class='cx-band-l'>{{b.label}}</span>
              <span class='cx-bar' aria-hidden='true'><span
                  class='cx-bar-fill
                    {{if b.isWorst "cx-hue-red" "cx-hue-accent"}}'
                  style={{cssVar _cx-pct=b.pct}}
                ></span></span>
              <span class='cx-num'>{{b.count}}d</span>
            </div>
          {{else}}
            <p class='cx-empty'>No approval step has been opened yet.</p>
          {{/each}}
          <p class='cx-chart-note'><span class='cx-swatch cx-hue-red'></span>
            Slowest step — where intervening pays.</p>
        </section>
      </div>

      <h2 class='cx-h'>Notice deadlines inside 90 days
        <span class='cx-h-sub'>{{@app.noticeSoonCount}}</span></h2>
      <NoticeTable @app={{@app}} />
    </section>

    <style scoped>
      .cx-sec {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .cx-h {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-2xs);
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .cx-num {
        font-variant-numeric: tabular-nums;
        font-weight: 600;
      }
      .cx-empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .cx-kpi {
        outline: 1px solid var(--border);
        outline-offset: -0.5px;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        background: var(--background);
        min-width: 0;
      }
      .cx-kpi-l {
        margin: 0;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .cx-kpi-v {
        margin: var(--boxel-sp-4xs) 0 0;
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        font-size: 1.9rem;
        font-weight: 650;
        line-height: 1.1;
        letter-spacing: -0.02em;
      }
      .cx-kpi-v.is-alarm {
        color: var(--destructive-ink);
      }
      .cx-kpi-v.is-none {
        color: var(--muted-foreground);
      }
      .cx-kpi-u {
        font-size: 0.95rem;
        font-weight: 500;
        color: var(--muted-foreground);
      }
      .cx-kpi-d {
        margin: var(--boxel-sp-5xs) 0 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        line-height: 1.4;
      }

      .cx-charts {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(17rem, 1fr));
        /* Each tile draws its own rule, so a short last row leaves no
           rule-coloured gap behind it. */
        gap: 0;
        margin-bottom: var(--boxel-sp);
      }
      .cx-chart {
        background: var(--background);
        padding: var(--boxel-sp-xs) var(--boxel-sp) var(--boxel-sp);
        min-width: 0;
      }
      .cx-h-sub {
        margin-left: var(--boxel-sp-2xs);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 400;
        color: var(--muted-foreground);
      }
      .cx-chart-note {
        margin: var(--boxel-sp-xs) 0 0;
        font-size: var(--boxel-font-size-xs);
        line-height: 1.45;
        color: var(--muted-foreground);
      }
      .cx-band-l {
        font-size: var(--boxel-font-size-sm);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .cx-swatch {
        display: inline-block;
        width: 0.5625rem;
        height: 0.5625rem;
        border-radius: var(--boxel-border-radius-xs);
        margin-right: var(--boxel-sp-3xs);
        background: var(--_cx-band-hue);
      }
      .cx-hue-accent {
        --_cx-band-hue: var(--primary);
      }
      .cx-num.is-money {
        white-space: nowrap;
      }
      .cx-kpis {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
        gap: 0.0625rem;
        background: var(--border);
        border-block: 1px solid var(--border);
        margin-bottom: var(--boxel-sp);
      }
      .cx-kpis > .cx-kpi:first-child {
        padding-left: 0;
      }
      .cx-charts > .cx-chart:first-child {
        padding-left: 0;
      }
      .cx-kpi {
        background: var(--background);
        padding: var(--boxel-sp-xs) var(--boxel-sp);
      }
      .cx-kpi.is-alarm {
        --stat-value-color: var(--destructive-ink);
        color: var(--destructive-ink);
      }
      .cx-meter {
        max-width: var(--_cx-measure);
      }
      .cx-band {
        display: grid;
        grid-template-columns: minmax(0, 11rem) minmax(2rem, 1fr) auto;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-5xs) 0;
        max-width: var(--_cx-measure);
      }
      .cx-bar {
        display: block;
        height: 0.5rem;
        border-radius: 999px;
        background: color-mix(in oklch, currentColor 8%, transparent);
        overflow: hidden;
      }
      .cx-bar-fill {
        display: block;
        height: 100%;
        width: max(0.375rem, calc(var(--_cx-pct) * 1%));
        border-radius: inherit;
        background: var(--_cx-band-hue);
      }
      .cx-hue-red {
        --_cx-band-hue: var(--destructive);
      }
      .cx-hue-orange {
        --_cx-band-hue: var(--warning);
      }
      .cx-hue-amber {
        --_cx-band-hue: var(--attention);
      }
      .cx-hue-green {
        --_cx-band-hue: var(--success);
      }
      .cx-hue-blue {
        --_cx-band-hue: var(--chart-1);
      }
      .cx-hue-slate {
        --_cx-band-hue: var(--muted-foreground);
      }
      .cx-hue-purple {
        --_cx-band-hue: var(--chart-4);
      }
      .cx-hue-teal {
        --_cx-band-hue: var(--chart-2);
      }
      .cx-band .cx-num {
        text-align: right;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        min-width: 2.5rem;
      }
    </style>
  </template>
}
