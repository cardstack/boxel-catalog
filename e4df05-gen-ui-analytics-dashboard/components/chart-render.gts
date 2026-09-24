import GlimmerComponent from '@glimmer/component';
import Modifier, { type NamedArgs } from 'ember-modifier';
import { tracked } from '@glimmer/tracking';
import { registerDestructor } from '@ember/destroyable';

import {
  compileToECharts,
  type AggregatedData,
  type ChartSpec,
  type ChartTheme,
} from '../utils/chart-spec';

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

// ECharts paints to a canvas, which cannot read CSS custom properties, so the
// theme's tokens are resolved here, off the chart element itself. A probe
// element turns whatever the token holds (a hex, oklch(), color-mix()) into
// the rgb() string canvas understands.
const PALETTE_TOKENS = [1, 2, 3, 4, 5, 6, 7].map((n) => `--chart-${n}`);

function resolveColor(element: HTMLElement, token: string): string {
  let probe = document.createElement('span');
  probe.style.display = 'none';
  probe.style.color = `var(${token})`;
  element.appendChild(probe);
  let color = getComputedStyle(probe).color;
  probe.remove();
  return color;
}

function readChartTheme(element: HTMLElement): ChartTheme {
  return {
    palette: PALETTE_TOKENS.map((token) => resolveColor(element, token)),
    ink: resolveColor(element, '--foreground'),
    muted: resolveColor(element, '--muted-foreground'),
    border: resolveColor(element, '--border'),
    fontFamily: getComputedStyle(element).fontFamily,
  };
}

interface RenderChartSignature {
  Args: {
    Named: {
      spec: ChartSpec | undefined;
      data: AggregatedData | undefined;
      onReady?: () => void;
    };
    Positional: [];
  };
  Element: HTMLElement;
}

class RenderChart extends Modifier<RenderChartSignature> {
  chart: any;
  resizeObserver: ResizeObserver | undefined;
  schemeObserver: MutationObserver | undefined;
  element: HTMLElement | undefined;
  spec: ChartSpec | undefined;
  data: AggregatedData | undefined;
  isDestroyed = false;

  paint() {
    if (!this.chart || !this.element || !this.spec || !this.data) {
      return;
    }
    // notMerge so a re-generated spec fully replaces the previous chart
    this.chart.setOption(
      compileToECharts(this.spec, this.data, readChartTheme(this.element)),
      { notMerge: true },
    );
  }

  async modify(
    element: HTMLElement,
    _positional: [],
    { spec, data, onReady }: NamedArgs<RenderChartSignature>,
  ) {
    this.element = element;
    this.spec = spec;
    this.data = data;
    if (!globalThis.document || !spec || !data) {
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
      // a light/dark switch above the chart changes every token it painted
      // with; repaint when the nearest scheme wrapper flips
      let schemeRoot = this.element.closest('[data-theme]');
      if (schemeRoot) {
        this.schemeObserver = new MutationObserver(() => this.paint());
        this.schemeObserver.observe(schemeRoot, {
          attributes: true,
          attributeFilter: ['data-theme'],
        });
      }
      registerDestructor(this, () => {
        this.isDestroyed = true;
        this.resizeObserver?.disconnect();
        this.schemeObserver?.disconnect();
        this.chart?.dispose();
        this.chart = undefined;
      });
    }
    this.paint();
    onReady?.();
  }
}

interface ChartRenderSignature {
  Args: {
    spec: ChartSpec | undefined;
    data: AggregatedData | undefined;
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
        {{RenderChart spec=@spec data=@data onReady=this.markReady}}
      />
    </div>
    <style scoped>
      .chart-shell {
        position: relative;
        width: 100%;
        height: 100%;
        min-height: 11.25rem;
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
        gap: var(--boxel-sp-2xs);
      }
      .chart-loading-dot {
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
        background-color: var(--muted-foreground);
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
