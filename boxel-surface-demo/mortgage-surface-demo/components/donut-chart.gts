import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { formatCurrency, svgPieStartAngle } from './utils';

/* ---------- DONUT CHART (monthly breakdown) ---------- */

interface DonutSectionSignature {
  Element: SVGGElement;
  Args: {
    fill: string;
    size: number;
    value: number | undefined;
    total: number;
    startAngle: number;
  };
}

class DonutSection extends GlimmerComponent<DonutSectionSignature> {
  get halfWidth() {
    return this.args.size / 2;
  }
  get radius() {
    return this.halfWidth;
  }
  get startX() {
    return (
      this.halfWidth +
      this.radius * Math.cos(this.args.startAngle * (Math.PI / 180))
    );
  }
  get startY() {
    return (
      this.halfWidth +
      this.radius * Math.sin(this.args.startAngle * (Math.PI / 180))
    );
  }
  get angle() {
    if (!this.args.total) return 0;
    const angle = ((this.args.value || 0) / this.args.total) * 360;
    return angle < 359.99 ? angle : 359.99;
  }
  get endAngle() {
    return this.angle + this.args.startAngle;
  }
  get largeArcFlag() {
    return this.angle > 180 ? 1 : 0;
  }
  get sweepFlag() {
    return this.args.startAngle < this.endAngle ? 1 : 0;
  }
  get endX() {
    return (
      this.halfWidth + this.radius * Math.cos(this.endAngle * (Math.PI / 180))
    );
  }
  get endY() {
    return (
      this.halfWidth + this.radius * Math.sin(this.endAngle * (Math.PI / 180))
    );
  }
  <template>
    <g fill={{@fill}} ...attributes>
      <path
        d='
          M {{this.halfWidth}} {{this.halfWidth}}
          L {{this.startX}} {{this.startY}}
          A {{this.radius}} {{this.radius}} 0 {{this.largeArcFlag}} {{this.sweepFlag}} {{this.endX}} {{this.endY}}
          Z
        '
      ></path>
    </g>
  </template>
}

export interface DonutSectionData {
  key?: string;
  class?: string;
  color: string;
  value: number | undefined;
  label: string;
  percent: number | undefined;
}

interface DonutChartSignature {
  Element: HTMLDivElement;
  Args: {
    data: DonutSectionData[];
    size: number;
    currencyCode?: string;
    onHover?: (key: string | null) => void;
  };
}

export class DonutChart extends GlimmerComponent<DonutChartSignature> {
  get viewBox() {
    const { size } = this.args;
    return `0 0 ${size} ${size}`;
  }
  get total() {
    const { data } = this.args;
    return data.reduce((sum, item) => sum + (item.value || 0), 0);
  }
  get center() {
    return this.args.size / 2;
  }
  get holeRadius() {
    return this.args.size * 0.36;
  }
  get centerLabelY() {
    return this.center - 10;
  }
  get centerValueY() {
    return this.center + 12;
  }
  noopHover = (_key: string | null): void => {};
  get hoverHandler() {
    return this.args.onHover ?? this.noopHover;
  }
  <template>
    <div class='dc-wrap'>
      <svg
        class='dc-svg'
        width={{@size}}
        height={{@size}}
        viewBox={{this.viewBox}}
        preserveAspectRatio='xMinYMin'
      >
        {{#each @data as |item index|}}
          <DonutSection
            class={{item.class}}
            data-segment-key={{item.key}}
            {{on 'mouseenter' (fn this.hoverHandler item.key)}}
            {{on 'mouseleave' (fn this.hoverHandler null)}}
            @fill={{item.color}}
            @size={{@size}}
            @value={{item.value}}
            @total={{this.total}}
            @startAngle={{svgPieStartAngle
              data=@data
              index=index
              total=this.total
              start=-90
            }}
          />
        {{/each}}
        {{#if (eq this.total 0)}}
          <circle
            cx={{this.center}}
            cy={{this.center}}
            r={{this.center}}
            fill='#d1fae5'
          />
        {{/if}}
        <circle
          cx={{this.center}}
          cy={{this.center}}
          r={{this.holeRadius}}
          fill='#ffffff'
        />
        <text
          x={{this.center}}
          y={{this.centerLabelY}}
          text-anchor='middle'
          font-size='9'
          font-weight='700'
          fill='#94a3b8'
          font-family='inherit'
          letter-spacing='0.08em'
        >MONTHLY</text>
        <text
          x={{this.center}}
          y={{this.centerValueY}}
          text-anchor='middle'
          font-size='14'
          font-weight='800'
          fill='#0f172a'
          font-family='inherit'
        >{{formatCurrency this.total @currencyCode}}</text>
      </svg>
    </div>
    <style scoped>
      .dc-wrap {
        display: inline-flex;
        border-radius: 50%;
        animation: dcEnter 0.9s cubic-bezier(0.34, 1.56, 0.64, 1) both;
        transition:
          filter 0.3s ease,
          transform 0.3s ease;
      }
      .dc-wrap:hover {
        filter: drop-shadow(0 6px 18px rgba(0, 0, 0, 0.18));
        transform: scale(1.03);
      }
      .dc-svg {
        animation: dcSpin 1.1s cubic-bezier(0.22, 1, 0.36, 1) both;
        transform-origin: center;
        transform-box: fill-box;
        overflow: visible;
      }
      @keyframes dcEnter {
        from {
          opacity: 0;
          transform: scale(0.7);
        }
        to {
          opacity: 1;
          transform: scale(1);
        }
      }
      @keyframes dcSpin {
        from {
          transform: rotate(-200deg);
        }
        to {
          transform: rotate(0deg);
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .dc-wrap,
        .dc-svg {
          animation: none;
          transition: none;
        }
      }
    </style>
  </template>
}
