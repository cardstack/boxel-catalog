import Component from '@glimmer/component';
import { htmlSafe, type SafeString } from '@ember/template';
import type { Table } from '../table';
import type { Fixture } from '../fixture';
import FixtureGlyph from './fixture-glyph';
import { seatPoints, sectionSeatPoints, type SeatPoint } from '../utils/index';

interface Signature {
  Element: SVGElement;
  Args: {
    tables?: Table[];
    fixtures?: Fixture[];
  };
}

interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface TableVM {
  shape: string;
  isRound: boolean;
  isBody: boolean;
  isCurved: boolean;
  x: number;
  y: number;
  w: number;
  h: number;
  cx: number;
  cy: number;
  rx: number;
  ry: number;
  fill: string;
  seats: { cx: number; cy: number }[];
}

interface FixtureVM {
  kind: string | null | undefined;
  color: string | null | undefined;
  pattern: string | null | undefined;
  x: number;
  y: number;
  w: number;
  h: number;
  transform: string;
}

export default class LayoutPreview extends Component<Signature> {
  private seatR = 9;

  get tables(): Table[] {
    return (this.args.tables ?? []).filter(Boolean) as Table[];
  }

  get fixtures(): Fixture[] {
    return (this.args.fixtures ?? []).filter(Boolean) as Fixture[];
  }

  get fixtureVMs(): FixtureVM[] {
    return this.fixtures.map((f) => {
      let x = f.x || 0;
      let y = f.y || 0;
      let w = f.width || 100;
      let h = f.height || 100;
      let rot = f.rotation || 0;
      return {
        kind: f.kind,
        color: f.color,
        pattern: f.pattern,
        x,
        y,
        w,
        h,
        transform: `rotate(${rot} ${x + w / 2} ${y + h / 2})`,
      };
    });
  }

  get tableVMs(): TableVM[] {
    return this.tables.map((t) => {
      let shape = t.shape || 'round';
      let style = t.seatingStyle || 'around';
      let x = t.x || 0;
      let y = t.y || 0;
      let w = t.width || 100;
      let h = t.height || 100;
      let isSection = shape === 'section';
      let count =
        shape === 'seat'
          ? 1
          : isSection
            ? Math.max(0, Math.floor(t.rows || 0)) *
              Math.max(0, Math.floor(t.cols || 0))
            : (t.seatCount ?? 8);
      let pts: SeatPoint[] = isSection
        ? sectionSeatPoints(t.rows || 0, t.cols || 0)
        : seatPoints(shape, style, count);
      let isBody = !(shape === 'seat' || isSection);
      return {
        shape,
        isRound: shape === 'round' || shape === 'oval',
        isBody,
        isCurved: shape === 'curved',
        x,
        y,
        w,
        h,
        cx: x + w / 2,
        cy: y + h / 2,
        rx: w / 2,
        ry: h / 2,
        fill: t.themeColor || 'currentColor',
        seats: pts.map((p) => ({ cx: x + p.x * w, cy: y + p.y * h })),
      };
    });
  }

  get viewBox(): string {
    let items: Box[] = [
      ...this.tables.map((t) => ({
        x: t.x || 0,
        y: t.y || 0,
        w: t.width || 100,
        h: t.height || 100,
      })),
      ...this.fixtures.map((f) => ({
        x: f.x || 0,
        y: f.y || 0,
        w: f.width || 100,
        h: f.height || 100,
      })),
    ];
    if (!items.length) return '0 0 100 100';
    let minX = Math.min(...items.map((b) => b.x));
    let minY = Math.min(...items.map((b) => b.y));
    let maxX = Math.max(...items.map((b) => b.x + b.w));
    let maxY = Math.max(...items.map((b) => b.y + b.h));
    let pad = 40;
    return `${minX - pad} ${minY - pad} ${maxX - minX + pad * 2} ${
      maxY - minY + pad * 2
    }`;
  }

  strokeStyle(color: string | null | undefined, fallback: string): SafeString {
    return htmlSafe(`stroke: ${color || fallback};`);
  }

  <template>
    <svg
      class='layout-preview'
      viewBox={{this.viewBox}}
      preserveAspectRatio='xMidYMid meet'
      xmlns='http://www.w3.org/2000/svg'
      ...attributes
    >

      {{#each this.fixtureVMs as |f|}}
        <g transform={{f.transform}} opacity='0.9'>
          <svg
            x={{f.x}}
            y={{f.y}}
            width={{f.w}}
            height={{f.h}}
            viewBox='0 0 100 100'
            preserveAspectRatio='none'
          >
            <FixtureGlyph
              @kind={{f.kind}}
              @color={{f.color}}
              @pattern={{f.pattern}}
            />
          </svg>
        </g>
      {{/each}}

      {{#each this.tableVMs as |t|}}
        {{#if t.isBody}}
          {{#if t.isRound}}
            <ellipse
              cx={{t.cx}}
              cy={{t.cy}}
              rx={{t.rx}}
              ry={{t.ry}}
              class='lp-table'
              vector-effect='non-scaling-stroke'
              style={{this.strokeStyle t.fill 'currentColor'}}
            />
          {{else if t.isCurved}}

            <svg
              x={{t.x}}
              y={{t.y}}
              width={{t.w}}
              height={{t.h}}
              viewBox='0 0 100 100'
              preserveAspectRatio='none'
            >
              <path
                d='M3 72.9 A50 50 0 0 1 97 72.9 L76.3 80.4 A28 28 0 0 0 23.7 80.4 Z'
                fill='none'
                stroke={{t.fill}}
                stroke-width='2'
                stroke-linejoin='round'
                vector-effect='non-scaling-stroke'
              />
            </svg>
          {{else}}
            <rect
              x={{t.x}}
              y={{t.y}}
              width={{t.w}}
              height={{t.h}}
              rx='6'
              class='lp-table'
              vector-effect='non-scaling-stroke'
              style={{this.strokeStyle t.fill 'currentColor'}}
            />
          {{/if}}
        {{/if}}

        {{#each t.seats as |s|}}
          <circle
            cx={{s.cx}}
            cy={{s.cy}}
            r={{this.seatR}}
            class='lp-seat'
            vector-effect='non-scaling-stroke'
          />
        {{/each}}
      {{/each}}
    </svg>

    <style scoped>
      .layout-preview {
        display: block;
        width: 100%;
        height: 100%;
        color: var(--tsp-accent, var(--accent, #c5a35c));
      }
      .lp-table {
        fill: none;
        stroke-width: 2;
      }
      .lp-seat {
        fill: none;
        stroke: color-mix(in srgb, currentColor 75%, transparent);
        stroke-width: 1.25;
      }
    </style>
  </template>
}
