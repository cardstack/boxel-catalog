import Component from '@glimmer/component';
import { eq } from '@cardstack/boxel-ui/helpers';

interface Signature {
  Element: SVGElement;
  Args: {
    kind?: string | null;
    color?: string | null;
    pattern?: string | null; // 'solid' | 'outline' | 'soft'
  };
}

export default class FixtureGlyph extends Component<Signature> {
  // Default to currentColor so the glyph follows the theme's accent (set
  // as `color:` on the svg root below); an explicit @color still wins.
  get color() {
    return this.args.color || 'currentColor';
  }

  get fill() {
    if (this.args.pattern === 'outline') return 'none';
    if (this.args.pattern === 'soft') return this.color;
    return this.color;
  }

  get fillOpacity() {
    return this.args.pattern === 'soft' ? '0.45' : '1';
  }

  get stroke() {
    return this.color;
  }

  get paperLine() {
    return 'rgba(0,0,0,0.32)';
  }

  <template>
    <svg
      class='fx-glyph'
      viewBox='0 0 100 100'
      preserveAspectRatio='none'
      xmlns='http://www.w3.org/2000/svg'
      ...attributes
    >
      <g
        fill={{this.fill}}
        fill-opacity={{this.fillOpacity}}
        stroke={{this.stroke}}
        stroke-width='2.5'
        stroke-linejoin='round'
        stroke-linecap='round'
      >

        {{#if (eq @kind 'plant')}}

          <circle cx='50' cy='50' r='47' fill='none' />
          <ellipse cx='50' cy='24' rx='9' ry='22' transform='rotate(0 50 50)' />
          <ellipse
            cx='50'
            cy='24'
            rx='9'
            ry='22'
            transform='rotate(60 50 50)'
          />
          <ellipse
            cx='50'
            cy='24'
            rx='9'
            ry='22'
            transform='rotate(120 50 50)'
          />
          <ellipse
            cx='50'
            cy='24'
            rx='9'
            ry='22'
            transform='rotate(180 50 50)'
          />
          <ellipse
            cx='50'
            cy='24'
            rx='9'
            ry='22'
            transform='rotate(240 50 50)'
          />
          <ellipse
            cx='50'
            cy='24'
            rx='9'
            ry='22'
            transform='rotate(300 50 50)'
          />
          <circle cx='50' cy='50' r='8' fill={{this.color}} />
        {{else if (eq @kind 'tree')}}

          <path
            d='M50 4
               C64 4 72 12 78 20 C90 26 96 36 94 50
               C96 64 90 76 78 82 C70 92 60 96 50 96
               C38 96 28 90 22 82 C10 76 4 64 6 50
               C4 36 10 26 22 20 C28 10 38 4 50 4 Z'
            fill='none'
          />
          <line x1='50' y1='50' x2='50' y2='12' />
          <line x1='50' y1='50' x2='83' y2='31' />
          <line x1='50' y1='50' x2='83' y2='69' />
          <line x1='50' y1='50' x2='50' y2='88' />
          <line x1='50' y1='50' x2='17' y2='69' />
          <line x1='50' y1='50' x2='17' y2='31' />
          <circle cx='50' cy='50' r='7' fill={{this.color}} />
        {{else if (eq @kind 'balloon')}}

          <circle cx='8' cy='87' r='8' />
          <circle cx='17' cy='75' r='6.5' />
          <circle cx='27' cy='65' r='8' />
          <circle cx='38' cy='58' r='6.5' />
          <circle cx='50' cy='55' r='8' />
          <circle cx='62' cy='58' r='6.5' />
          <circle cx='73' cy='65' r='8' />
          <circle cx='83' cy='75' r='6.5' />
          <circle cx='92' cy='87' r='8' />
        {{else if (eq @kind 'stage')}}

          <rect x='4' y='4' width='92' height='66' rx='5' />
          <rect x='11' y='11' width='78' height='52' rx='3' fill='none' />
          <rect x='34' y='70' width='32' height='9' rx='2' fill='none' />
          <rect x='38' y='79' width='24' height='9' rx='2' fill='none' />
          <rect x='42' y='88' width='16' height='8' rx='2' fill='none' />
        {{else if (eq @kind 'red-carpet')}}

          <rect x='4' y='3' width='92' height='94' />
          <line x1='26' y1='3' x2='26' y2='97' stroke={{this.paperLine}} />
          <line x1='74' y1='3' x2='74' y2='97' stroke={{this.paperLine}} />
        {{else if (eq @kind 'dance-floor')}}

          <rect x='8' y='8' width='84' height='84' rx='3' fill='none' />
          <rect x='8' y='8' width='28' height='28' />
          <rect x='64' y='8' width='28' height='28' />
          <rect x='36' y='36' width='28' height='28' />
          <rect x='8' y='64' width='28' height='28' />
          <rect x='64' y='64' width='28' height='28' />
        {{else if (eq @kind 'arch')}}

          <path d='M22 56 Q50 32 78 56 L78 66 Q50 42 22 66 Z' fill='none' />
          <circle cx='15' cy='62' r='9' />
          <circle cx='15' cy='62' r='3.5' fill={{this.color}} />
          <circle cx='85' cy='62' r='9' />
          <circle cx='85' cy='62' r='3.5' fill={{this.color}} />
        {{else if (eq @kind 'projector')}}

          <rect x='30' y='58' width='40' height='36' rx='5' />
          <circle cx='50' cy='58' r='7' fill='none' />
          <path
            d='M50 51 L12 6 M50 51 L88 6'
            fill='none'
            stroke-dasharray='5 5'
          />
          <line x1='16' y1='10' x2='84' y2='10' stroke-dasharray='5 5' />
        {{else if (eq @kind 'cake')}}

          <circle cx='50' cy='50' r='47' />
          <circle
            cx='50'
            cy='50'
            r='31'
            fill='none'
            stroke={{this.paperLine}}
          />
          <circle
            cx='50'
            cy='50'
            r='16'
            fill='none'
            stroke={{this.paperLine}}
          />
          <circle cx='50' cy='50' r='4' fill={{this.paperLine}} />
        {{else if (eq @kind 'bar')}}

          <rect x='4' y='20' width='92' height='34' rx='5' />
          <circle cx='20' cy='82' r='8' fill='none' />
          <circle cx='50' cy='82' r='8' fill='none' />
          <circle cx='80' cy='82' r='8' fill='none' />
        {{else if (eq @kind 'curved-wall')}}

          <path
            d='M4 96 A92 92 0 0 1 96 4 L96 16 A80 80 0 0 0 16 96 Z'
            fill='none'
          />
        {{else if (eq @kind 'rect-decor')}}

          <rect x='5' y='5' width='90' height='90' rx='4' fill='none' />
        {{else if (eq @kind 'round-decor')}}

          <circle cx='50' cy='50' r='46' fill='none' />
        {{else if (eq @kind 'circle-cluster')}}

          <circle cx='47' cy='54' r='26' fill='none' />
          <circle cx='77' cy='25' r='15' fill='none' />
          <circle cx='22' cy='64' r='11' fill='none' />
          <circle cx='40' cy='84' r='8' fill='none' />
        {{else}}
          <rect
            x='10'
            y='10'
            width='80'
            height='80'
            rx='8'
            fill='none'
            stroke-dasharray='6 6'
          />
        {{/if}}
      </g>
    </svg>
    <style scoped>
      .fx-glyph {
        width: 100%;
        height: 100%;
        display: block;
        overflow: visible;
        pointer-events: none;
        color: var(--tsp-accent, var(--accent, #c5a35c));
      }
      .fx-glyph path,
      .fx-glyph rect,
      .fx-glyph circle,
      .fx-glyph ellipse,
      .fx-glyph line {
        vector-effect: non-scaling-stroke;
      }
    </style>
  </template>
}
