import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { BarList } from '@cardstack/pretui/components/bar-list';
import { Button } from '@cardstack/pretui/components/button';
import { Chart } from '@cardstack/pretui/components/chart';
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
  <template>
    <section class='pane'>
      <div class='hero'>
        <div class='hero-metric'>
          <span class='m-label'>Monthly recurring revenue</span>
          <span class='hero-value'>{{@console.dash.mrr}}</span>
          <span class='hero-sub'>{{@console.dash.arr}} annualized</span>
        </div>
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
            @height={{180}}
          />
        </div>
      </div>
      <div class='dash-toolbar'>
        <div class='owner-select'>
          <Select
            @options={{@console.periodOptions}}
            @value={{@console.period}}
            @onValueChange={{@console.setPeriod}}
            @label='Date range'
          />
        </div>
        <label class='switch-wrap'>
          <Switch
            @checked={{@console.comparePrevious}}
            @onCheckedChange={{@console.toggleCompare}}
          />
          <span class='switch-text'>Compare to previous</span>
        </label>
      </div>
      <div class='metric-grid'>
        {{#each @console.periodMetrics as |m|}}
          <div class='metric metric-flat'>
            <span class='m-label'>{{m.label}}</span>
            <span class='m-value'>{{m.value}}</span>
            {{#if m.note}}<span class='m-note'>{{m.note}}</span>{{/if}}
          </div>
        {{/each}}
      </div>
      <div class='metric-grid'>
        {{#each @console.dash.secondary as |m|}}
          {{#if m.tab}}
            <Button
              class='metric metric-flat metric-link'
              @appearance='plain'
              {{on 'click' (fn @console.drillTo m.tab m.filter)}}
            >
              <span class='m-label'>{{m.label}}</span>
              <span class='m-value'>{{m.value}}</span>
            </Button>
          {{else}}
            <div class='metric metric-flat'>
              <span class='m-label'>{{m.label}}</span>
              <span class='m-value'>{{m.value}}</span>
            </div>
          {{/if}}
        {{/each}}
      </div>
      <div class='dash-cols'>
        <div class='panel'>
          <h3>Pipeline by stage</h3>
          <BarList
            @rows={{@console.stageBars}}
            @ranked={{false}}
            @format={{@console.chartMoney}}
            @label='Open pipeline by stage'
          />
        </div>
      </div>
    </section>
    <style scoped>
      .pane {
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }
      h2 {
        margin: 0;
        font-size: 1.0625rem;
        font-family: var(--font-sans);
      }
      .switch-wrap {
        display: flex;
        align-items: center;
        gap: 0.4375rem;
      }
      .switch-text {
        font-size: 0.8125rem;
        font-weight: 500;
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .metric-grid,
      .aging-strip {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8.5rem, 1fr));
        gap: 0.75rem;
      }
      .metric {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        padding: 0.875rem 1rem;
        background: var(--card);
      }
      .metric-flat {
        border: none;
        background: var(--muted);
      }
      .metric-link {
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        text-align: left;
        cursor: pointer;
      }
      .metric-link:hover {
        background: var(--border);
      }
      .hero {
        display: grid;
        grid-template-columns: minmax(15rem, 1fr) minmax(20rem, 2fr);
        gap: 1.5rem;
        align-items: center;
        border: 1px solid var(--border);
        border-radius: 1rem;
        background: var(--card);
        padding: 1.5rem 1.75rem;
        box-shadow: var(--shadow-xs);
      }
      .hero-metric {
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
      }
      .hero-value {
        font-size: 3rem;
        line-height: 1;
        font-weight: 700;
        font-family: var(--font-sans);
        font-variant-numeric: tabular-nums;
        color: var(--primary-ink);
      }
      .hero-sub {
        font-size: 0.875rem;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .hero-chart {
        min-width: 0;
      }
      .dash-toolbar {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex-wrap: wrap;
      }
      .m-note {
        font-size: 0.6875rem;
        font-weight: 600;
        color: var(--muted-foreground);
      }
      @media (max-width: 48rem) {
        .hero {
          grid-template-columns: 1fr;
        }
      }
      .m-label {
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--muted-foreground);
      }
      .m-value {
        font-size: 1.25rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1.1;
      }
      .dash-cols {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(20rem, 1fr));
        gap: 1rem;
      }
      .panel {
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        padding: 1rem 1.25rem;
        background: var(--card);
      }
      h3 {
        margin: 0 0 0.75rem;
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--muted-foreground);
      }
      .owner-select {
        min-width: 11rem;
      }
      .panel :deep(.boxel-card-container) {
        background: transparent;
        border-radius: 0;
      }
      .panel :deep(.boxel-card-container--boundaries) {
        box-shadow: none;
      }
      .panel .row-open + .row-open {
        border-top: 1px solid var(--border);
      }
    </style>
  </template>
}
