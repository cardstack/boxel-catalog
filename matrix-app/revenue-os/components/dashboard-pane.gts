import Component from '@glimmer/component';
import { BarList } from '@cardstack/pretui/components/bar-list';
import { Chart } from '@cardstack/pretui/components/chart';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { Stat } from '@cardstack/pretui/components/stat';
import { PageHead } from './page-head';
import { StatStrip } from './stat-strip';
import { Select } from '@cardstack/pretui/components/select';
import { Switch } from '@cardstack/pretui/components/switch';
import type { RevenueOsConsole } from '../revenue-os';

interface Signature {
  Args: {
    console: RevenueOsConsole;
  };
}

// The Dashboard tab: MRR and its trend, the headline metrics, and open
// pipeline by stage.
export class DashboardPane extends Component<Signature> {
  FORMS = [
    { name: 'full', minWidth: 11 },
    { name: 'menu', minWidth: 0 },
  ];
  TONES = ['success', 'warning', 'success'];

  get periodStats() {
    return this.args.console.periodMetrics.map((m, i) => ({
      label: m.label,
      value: m.value.startsWith('no closed') ? '—' : m.value,
      hint: m.value.startsWith('no closed') ? 'no closed deals yet' : m.note,
      tone: this.TONES[i],
    }));
  }

  get secondaryStats() {
    let tones = ['info', 'neutral', 'danger'];
    return this.args.console.dash.secondary.map((m, i) => ({
      label: m.label,
      value: m.value,
      tone: tones[i],
    }));
  }

  <template>
    <section class='pane'>
      <PageHead @title='Dashboard' />
      {{#if @console.queriesSettled}}
        <div class='block hero'>
          <Stat
            class='hero-stat'
            @label='Monthly recurring revenue'
            @tone='neutral'
            @value={{@console.dash.mrr}}
            @hint='{{@console.dash.arr}} annualized'
            @roll={{false}}
          />
          <div class='hero-chart'>
            <Chart
              @mark='line'
              @rows={{@console.mrrTrend}}
              @x='label'
              @y='value'
              @xType='point'
              @xLabel='Month'
              @yLabel='MRR'
              @label='Monthly recurring revenue, last eight months'
              @height={{150}}
            />
          </div>
        </div>
        <LayoutControl @label='Dashboard filters' as |lc|>
          <lc.Slot
            @id='range'
            @priority={{1}}
            @forms={{this.FORMS}}
            @label='Date range'
          >
            <Select
              @options={{@console.periodOptions}}
              @value={{@console.period}}
              @onValueChange={{@console.setPeriod}}
              @label='Date range'
            />
          </lc.Slot>
          <lc.Slot
            @id='compare'
            @priority={{0}}
            @forms={{this.FORMS}}
            @label='Compare'
          >
            <label class='switch-wrap'>
              <Switch
                @checked={{@console.comparePrevious}}
                @onCheckedChange={{@console.toggleCompare}}
              />
              <span class='switch-text'>Compare to previous</span>
            </label>
          </lc.Slot>
        </LayoutControl>
        <div class='block'>
          <h2>This period</h2>
          <StatStrip
            @stats={{this.periodStats}}
            @label='This period'
            class='flat'
          />
          <StatStrip
            @stats={{this.secondaryStats}}
            @label='Pipeline and balances'
            class='flat'
          />
        </div>
        <div class='block'>
          <h2>Pipeline by stage</h2>
          <div class='body'>
            <BarList
              @rows={{@console.stageBars}}
              @ranked={{false}}
              @format={{@console.chartMoney}}
              @label='Open pipeline by stage'
            />
          </div>
        </div>
      {{else}}
        <p class='loading' role='status'>Loading the dashboard…</p>
      {{/if}}
    </section>
    <style scoped>
      .pane {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
      }
      .block {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .hero {
        display: grid;
        grid-template-columns: minmax(12rem, 15rem) 1fr;
      }
      .hero-stat {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .hero-chart {
        min-width: 0;
        box-shadow: -1px 0 0 var(--border);
      }
      h2 {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-size: 0.75rem;
        font-weight: 700;
      }
      .body {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .flat {
        border: 0;
        border-radius: 0;
      }
      .switch-wrap {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .switch-text {
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .loading {
        margin: 0;
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
