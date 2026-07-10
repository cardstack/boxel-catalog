import { Component } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { eq } from '@cardstack/boxel-ui/helpers';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

// A framing option. Each carries a preview rectangle (proportioned to the
// ratio, centered in a 22×22 box) rendered by the custom edit template.
interface AspectOption {
  value: string;
  label: string;
  orientation: string;
  rw: number;
  rh: number;
  rx: number;
  ry: number;
}

const AR_VIEWBOX = 22;
const AR_MAX = 18; // largest shape dimension inside the box
const round2 = (n: number) => Math.round(n * 100) / 100;

export const ASPECT_RATIO_OPTIONS: AspectOption[] = [
  { value: '1:1', label: '1:1', orientation: 'Square', w: 1, h: 1 },
  { value: '16:9', label: '16:9', orientation: 'Landscape', w: 16, h: 9 },
  { value: '9:16', label: '9:16', orientation: 'Portrait', w: 9, h: 16 },
  { value: '4:3', label: '4:3', orientation: 'Landscape', w: 4, h: 3 },
  { value: '3:4', label: '3:4', orientation: 'Portrait', w: 3, h: 4 },
  { value: '3:2', label: '3:2', orientation: 'Landscape', w: 3, h: 2 },
  { value: '2:3', label: '2:3', orientation: 'Portrait', w: 2, h: 3 },
  { value: '21:9', label: '21:9', orientation: 'Ultrawide', w: 21, h: 9 },
].map(({ value, label, orientation, w, h }) => {
  let rw = w >= h ? AR_MAX : (AR_MAX * w) / h;
  let rh = h >= w ? AR_MAX : (AR_MAX * h) / w;
  return {
    value,
    label,
    orientation,
    rw: round2(rw),
    rh: round2(rh),
    rx: round2(AR_VIEWBOX / 2 - rw / 2),
    ry: round2(AR_VIEWBOX / 2 - rh / 2),
  };
});

// A string field whose value is an aspect-ratio token (e.g. '16:9'). The custom
// edit template renders a compact grid of tiles — each a transparent square box
// holding an SVG rectangle proportioned to the ratio, with the ratio label
// beneath — instead of a plain dropdown.
export default class AspectRatioField extends StringField {
  static displayName = 'Aspect Ratio';

  static edit = class Edit extends Component<typeof AspectRatioField> {
    options = ASPECT_RATIO_OPTIONS;

    <template>
      <div class='ar-grid' data-test-aspect-ratio>
        {{#each this.options as |opt|}}
          <button
            type='button'
            class='ar-tile {{if (eq @model opt.value) "selected"}}'
            title='{{opt.orientation}} · {{opt.label}}'
            {{on 'click' (fn @set opt.value)}}
            data-test-aspect-ratio-option={{opt.value}}
          >
            <span class='ar-box'>
              <svg viewBox='0 0 22 22' class='ar-svg' aria-hidden='true'>
                <rect
                  x={{opt.rx}}
                  y={{opt.ry}}
                  width={{opt.rw}}
                  height={{opt.rh}}
                  rx='1.5'
                />
              </svg>
            </span>
            <span class='ar-label'>{{opt.label}}</span>
          </button>
        {{/each}}
      </div>

      <style scoped>
        .ar-grid {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: var(--boxel-sp-xxs);
        }
        .ar-tile {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.125rem;
          padding: var(--boxel-sp-xxs);
          border: 1px solid var(--boxel-200);
          border-radius: var(--boxel-border-radius-sm);
          background: transparent;
          color: var(--boxel-450);
          font: inherit;
          cursor: pointer;
          transition:
            border-color 0.12s ease,
            color 0.12s ease;
        }
        .ar-tile:hover {
          border-color: var(--boxel-highlight);
        }
        .ar-tile.selected {
          border-color: var(--boxel-highlight);
          color: var(--boxel-dark);
          box-shadow: 0 0 0 0.0625rem var(--boxel-highlight);
        }
        .ar-box {
          width: 1.5rem;
          height: 1.5rem;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .ar-svg {
          width: 100%;
          height: 100%;
        }
        .ar-svg rect {
          fill: none;
          stroke: currentColor;
          stroke-width: 1.5;
        }
        .ar-tile.selected .ar-svg rect {
          fill: color-mix(in srgb, var(--boxel-highlight) 25%, transparent);
        }
        .ar-label {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
        }
      </style>
    </template>
  };
}
