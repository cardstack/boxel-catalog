import GlimmerComponent from '@glimmer/component';
import {
  BarList,
  type BarListItem,
} from '@cardstack/pretui/components/bar-list';
import type { ContractExecutionView } from '../contract-execution-app';
import { CONTRACT_STATUSES } from '../../legal/contract-status';
import { riskGradeLabel } from '../../legal/contract-risk';
import { formatMoney } from '../../commerce/line-item-totals';
import { personLabelOrUndefined, scaleBands } from '../contract-execution-data';
import {
  compactMoney,
  hueTone,
  riskTone,
  toLocalDate,
} from '../../shared/compact-format';
import { Block, CeTable, StatStrip, toneHue, type Stat } from '../components';
import { NOTICE_COLUMNS } from './renewals';

interface Signature {
  Args: { app: ContractExecutionView };
}

class ComplianceData extends GlimmerComponent<Signature> {
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
            tone: riskTone(grade),
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
      tone: hueTone(o.hue),
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
}

// The tab's four headline numbers, drawn under the desk strip by the shell.
export class ComplianceStats extends ComplianceData {
  get stats(): Stat[] {
    let median = this.medianExecutionDays;
    let next = this.args.app.nearestNotice;
    return [
      {
        label: 'Median execution time',
        value: median ?? '—',
        unit: median !== undefined ? 'd' : undefined,
        sub: 'Approval start to signature',
      },
      {
        label: 'Obligations met',
        value: this.args.app.complianceLabel,
        meter: this.compliancePct || undefined,
      },
      {
        label: 'Clause deviations',
        value: this.deviationCount,
        sub: `${this.unapprovedDeviations} unapproved`,
        tone: this.unapprovedDeviations ? 'danger' : 'neutral',
      },
      {
        label: 'Notice inside 90 days',
        value: this.args.app.noticeSoonCount,
        sub: next !== undefined ? `nearest in ${next} days` : 'none due',
      },
    ];
  }

  <template>
    <StatStrip @stats={{this.stats}} @label='Compliance summary' />
  </template>
}

export class ComplianceTab extends ComplianceData {
  noticeColumns = NOTICE_COLUMNS;

  get stageRows(): BarListItem[] {
    return this.statusBands.map((b) => ({
      name: b.label,
      value: b.count,
      hue: toneHue(b.tone),
    }));
  }

  // One list per currency: a bar compares amounts in one currency only.
  get riskGroups() {
    let groups = new Map<string, BarListItem[]>();
    for (let b of this.valueByRisk as any[]) {
      let code = b.currency ?? '';
      groups.set(code, [
        ...(groups.get(code) ?? []),
        { name: b.label, value: b.amount, hue: toneHue(b.tone) },
      ]);
    }
    return [...groups].map(([code, rows]) => ({
      rows,
      format: (v: number) =>
        code ? compactMoney(v, code) : formatMoney(v, undefined),
    }));
  }

  get contractRows(): BarListItem[] {
    return this.complianceByContract.map((r) => ({
      name: r.label,
      value: r.count,
      hue: toneHue('neutral', r.count < 100),
    }));
  }

  get trendRows(): BarListItem[] {
    return this.complianceTrend.map((m) => ({ name: m.label, value: m.pct }));
  }

  get stepRows(): BarListItem[] {
    return this.timeByStep.map((r) => ({
      name: r.label,
      value: r.count,
      hue: toneHue('neutral', r.isWorst),
    }));
  }

  formatPercent = (v: number) => `${v}%`;
  formatDays = (v: number) => `${v}d`;

  <template>
    <div class='cp-grid'>
      <Block
        @title='By lifecycle stage'
        @count='{{@app.contracts.length}} contracts'
      >
        <BarList
          @rows={{this.stageRows}}
          @ranked={{false}}
          @label='Contracts by stage'
        />
        <p class='cp-foot'>Bars scale to the largest band, so an even split
          reads as even rather than as four invisible slivers.</p>
      </Block>
      <Block
        @title='Portfolio value by risk grade'
        @count={{this.portfolioValueLabel}}
      >
        {{#each this.riskGroups as |g|}}
          <BarList
            @rows={{g.rows}}
            @ranked={{false}}
            @format={{g.format}}
            @label='Value by risk grade'
          />
        {{/each}}
        <p class='cp-foot'>Weighted by value, not by count — four low-value
          contracts are not the same exposure as one large one.</p>
      </Block>
      <Block @title='By contract' @count='worst first'>
        {{#if this.contractRows.length}}
          <BarList
            @rows={{this.contractRows}}
            @ranked={{false}}
            @max={{100}}
            @format={{this.formatPercent}}
            @label='Obligations met by contract'
          />
        {{/if}}
        <p class='cp-foot'>A contract with nothing owed is left out rather than
          shown at 0% — no obligations is not the same as failing them.</p>
      </Block>
      <Block @title='Trend' @count='last 6 months'>
        {{#if this.trendHasData}}
          <BarList
            @rows={{this.trendRows}}
            @ranked={{false}}
            @max={{100}}
            @format={{this.formatPercent}}
            @label='Obligations met per month'
          />
        {{/if}}
        <p class='cp-foot'>Share of obligations due that month that were closed,
          derived from completion dates.</p>
      </Block>
      <Block @title='Time per approval step' @count='median days'>
        {{#if this.stepRows.length}}
          <BarList
            @rows={{this.stepRows}}
            @ranked={{false}}
            @format={{this.formatDays}}
            @label='Median days per approver'
          />
        {{/if}}
        <p class='cp-foot'>Red marks the slowest step — where intervening pays.</p>
      </Block>
    </div>
    <Block
      @title='Notice deadlines inside 90 days'
      @count={{@app.renewalRows.length}}
    >
      {{#if @app.renewalRows.length}}
        <CeTable
          @label='Notice deadlines inside 90 days'
          @columns={{this.noticeColumns}}
          @rows={{@app.renewalRows}}
          @onOpen={{@app.openInWorkspace}}
        />
      {{else}}
        <p class='cp-foot'>No notice window closes in the next 90 days.</p>
      {{/if}}
    </Block>
    <style scoped>
      .cp-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .cp-foot {
        margin: 0;
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
