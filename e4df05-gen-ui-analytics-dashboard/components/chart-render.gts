import GlimmerComponent from '@glimmer/component';
import Modifier, { type NamedArgs } from 'ember-modifier';
import { tracked } from '@glimmer/tracking';
import { registerDestructor } from '@ember/destroyable';

// ---------------------------------------------------------------------------
// ECharts loads once per session from the CDN as a UMD bundle. The code runs
// through new Function('module','exports', ...) — NOT eval — because eval
// mis-detects the AMD wrapper in production builds.
// ---------------------------------------------------------------------------
let echarts: any;
let echartsLoaded: Promise<void> | undefined;

function loadECharts(): Promise<void> {
  if (!echartsLoaded) {
    echartsLoaded = (async () => {
      if (!echarts?.init) {
        let response = await fetch(
          'https://cdn.jsdelivr.net/npm/echarts@5.5.0/dist/echarts.min.js',
        );
        if (!response.ok) {
          throw new Error(`could not load ECharts: ${response.status}`);
        }
        let code = await response.text();
        let echartsModule: { exports: any } = { exports: {} };
        new Function('module', 'exports', code)(
          echartsModule,
          echartsModule.exports,
        );
        echarts = echartsModule.exports;
      }
    })().catch((err) => {
      // Don't let a transient CDN failure poison the cache: a rejected promise
      // left in `echartsLoaded` would be handed to every later render, so no
      // chart would ever retry the load even once connectivity returned.
      echartsLoaded = undefined;
      throw err;
    });
  }
  return echartsLoaded;
}

interface RenderChartSignature {
  Args: {
    Named: {
      option: Record<string, any> | undefined;
      onReady?: () => void;
    };
    Positional: [];
  };
  Element: HTMLElement;
}

class RenderChart extends Modifier<RenderChartSignature> {
  chart: any;
  resizeObserver: ResizeObserver | undefined;
  element: HTMLElement | undefined;
  isDestroyed = false;

  async modify(
    element: HTMLElement,
    _positional: [],
    { option, onReady }: NamedArgs<RenderChartSignature>,
  ) {
    this.element = element;
    if (!globalThis.document || !option) {
      return;
    }
    try {
      await loadECharts();
    } catch {
      // the load is retried on the next render; leave the placeholder showing
      return;
    }
    if (this.isDestroyed || !this.element?.isConnected) {
      return;
    }
    if (!this.chart) {
      this.chart = echarts.init(this.element);
      this.resizeObserver = new ResizeObserver(() => this.chart?.resize());
      this.resizeObserver.observe(this.element);
      registerDestructor(this, () => {
        this.isDestroyed = true;
        this.resizeObserver?.disconnect();
        this.chart?.dispose();
        this.chart = undefined;
      });
    }
    // notMerge so a re-generated spec fully replaces the previous chart
    this.chart.setOption(option, { notMerge: true });
    onReady?.();
  }
}

interface ChartRenderSignature {
  Args: {
    option: Record<string, any> | undefined;
  };
  Element: HTMLElement;
}

// Renders a compiled ECharts option into a sized container. Shows a pulse
// placeholder until the library has painted the first frame.
export default class ChartRender extends GlimmerComponent<ChartRenderSignature> {
  @tracked ready = false;

  markReady = () => {
    if (!this.ready) {
      this.ready = true;
    }
  };

  <template>
    <div class='chart-shell' ...attributes>
      {{#unless this.ready}}
        <div class='chart-loading'>
          <span class='chart-loading-dot' />
          <span class='chart-loading-dot' />
          <span class='chart-loading-dot' />
        </div>
      {{/unless}}
      <div
        class='chart-canvas'
        {{RenderChart option=@option onReady=this.markReady}}
      />
    </div>
    <style scoped>
      .chart-shell {
        position: relative;
        width: 100%;
        height: 100%;
        min-height: 180px;
      }
      .chart-canvas {
        position: absolute;
        inset: 0;
      }
      .chart-loading {
        position: absolute;
        inset: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
      }
      .chart-loading-dot {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: currentColor;
        opacity: 0.35;
        animation: chart-pulse 1.2s ease-in-out infinite;
      }
      .chart-loading-dot:nth-child(2) {
        animation-delay: 0.2s;
      }
      .chart-loading-dot:nth-child(3) {
        animation-delay: 0.4s;
      }
      @keyframes chart-pulse {
        0%,
        100% {
          opacity: 0.25;
          transform: scale(0.85);
        }
        50% {
          opacity: 0.9;
          transform: scale(1);
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .chart-loading-dot {
          animation: none;
        }
      }
    </style>
  </template>
}
