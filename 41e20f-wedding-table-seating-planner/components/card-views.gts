import Component from '@glimmer/component';
import { htmlSafe, type SafeString } from '@ember/template';

// Fit-to-width for a single-line serif name: the print sheet is hidden on
// screen (unmeasurable), so scale by character count instead — an average
// glyph is ~0.55em wide, so capping at ~150/n cqw keeps n characters inside
// the card at any container size.
function nameSizeStyle(
  text: string | null | undefined,
  baseCqw: number,
  minPx: number,
  maxPx: number,
): SafeString {
  let n = (text ?? '').trim().length || 1;
  let cqw = Math.min(baseCqw, 150 / n);
  return htmlSafe(
    `font-size: clamp(${minPx}px, ${cqw.toFixed(2)}cqw, ${maxPx}px);`,
  );
}

// Shared visuals for the wedding stationery. Both the PlaceCard / TableCard
// card definitions AND the planner's print sheet render these, so the card and
// what gets printed stay identical (single source of truth). Sizing is driven
// by the container (container queries), so the same component looks right as a
// large isolated card, a small fitted tile, or a print-sheet cell.

interface PlaceCardSignature {
  Element: HTMLDivElement;
  Args: {
    eventTitle?: string | null;
    guestName?: string | null;
    tableName?: string | null;
    message?: string | null;
    logoUrl?: string | null;
  };
}

export class PlaceCardView extends Component<PlaceCardSignature> {
  get nameSize(): SafeString {
    return nameSizeStyle(this.args.guestName, 11, 16, 46);
  }
  <template>
    <div class='pcv' ...attributes>
      {{#if @logoUrl}}
        <img class='cv-mark' src={{@logoUrl}} alt='' aria-hidden='true' />
      {{/if}}
      {{#if @eventTitle}}
        <span class='pcv-event'>{{@eventTitle}}</span>
      {{/if}}
      <span class='pcv-name' style={{this.nameSize}}>{{if
          @guestName
          @guestName
          'Guest Name'
        }}</span>
      <span class='pcv-rule'></span>
      {{#if @tableName}}
        <span class='pcv-table'>{{@tableName}}</span>
      {{/if}}
      {{#if @message}}
        <span class='pcv-msg'>{{@message}}</span>
      {{/if}}
    </div>
    <style scoped>
      .pcv {
        container-type: inline-size;
        z-index: 0;
        --pc-paper: var(--tsp-background, var(--background, #fbf6ec));
        --pc-ink: var(--tsp-foreground, var(--foreground, #5a1a1a));
        --pc-gold: var(--tsp-accent, var(--accent, #a5854a));
        --pc-serif: var(
          --tsp-font-serif,
          var(--font-serif, 'Cormorant Garamond', Georgia, serif)
        );
        --pc-sans: var(
          --tsp-font-sans,
          var(--font-sans, 'Jost', system-ui, sans-serif)
        );
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 6px;
        width: 100%;
        height: 100%;
        padding: 8%;
        background: var(--pc-paper);
        color: var(--pc-ink);
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
        border: 1px solid var(--pc-gold);
        border-radius: 6px;
        text-align: center;
        overflow: hidden;
        position: relative;
      }
      /* Themed stationery detail: hairline inner frame + corner flourish,
         both driven by the theme accent. */
      .pcv::before {
        content: '';
        position: absolute;
        inset: 5px;
        border: 1px solid color-mix(in srgb, var(--pc-gold) 45%, transparent);
        border-radius: 4px;
        pointer-events: none;
      }
      .pcv::after {
        content: '❧';
        position: absolute;
        top: 7px;
        left: 12px;
        font-family: var(--pc-serif);
        font-size: 13px;
        line-height: 1;
        color: color-mix(in srgb, var(--pc-gold) 70%, transparent);
        pointer-events: none;
      }
      /* Event-logo watermark: faint, centered, behind the content. */
      .cv-mark {
        position: absolute;
        inset: 0;
        margin: auto;
        height: 72%;
        max-width: 60%;
        object-fit: contain;
        opacity: 0.08;
        z-index: -1;
        pointer-events: none;
      }
      .pcv-event {
        font-family: var(--pc-sans);
        font-size: clamp(8px, 2.6cqw, 12px);
        letter-spacing: 0.22em;
        text-transform: uppercase;
        color: var(--pc-gold);
      }
      .pcv-name {
        font-family: var(--pc-serif);
        font-size: clamp(20px, 11cqw, 46px);
        font-weight: 600;
        line-height: 1.05;
      }
      .pcv-rule {
        width: clamp(24px, 9cqw, 44px);
        height: 1px;
        background: var(--pc-gold);
      }
      .pcv-table {
        font-family: var(--pc-sans);
        font-size: clamp(9px, 3cqw, 13px);
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--pc-gold);
      }
      .pcv-msg {
        font-family: var(--pc-serif);
        font-size: clamp(11px, 3.6cqw, 16px);
        font-style: italic;
        opacity: 0.8;
      }
      /* Print keeps the theme's accent hue but deepens it toward the ink so
         the small-caps kicker/table label stay legible on paper. */
      @media print {
        .pcv-event,
        .pcv-table {
          color: color-mix(in srgb, var(--pc-gold) 50%, var(--pc-ink));
        }
      }
    </style>
  </template>
}

interface TableCardSignature {
  Element: HTMLDivElement;
  Args: {
    eventTitle?: string | null;
    tableName?: string | null;
    accent?: string | null;
    logoUrl?: string | null;
  };
}

export class TableCardView extends Component<TableCardSignature> {
  get nameSize(): SafeString {
    return nameSizeStyle(this.args.tableName, 10, 20, 52);
  }
  <template>
    <div class='tcv' ...attributes>
      {{#if @logoUrl}}
        <img class='cv-mark' src={{@logoUrl}} alt='' aria-hidden='true' />
      {{/if}}
      {{#if @eventTitle}}
        <span class='tcv-event'>{{@eventTitle}}</span>
      {{/if}}
      <span class='tcv-name' style={{this.nameSize}}>{{if
          @tableName
          @tableName
          'Table'
        }}</span>
      {{#if @accent}}
        <span class='tcv-accent'>{{@accent}}</span>
      {{/if}}
    </div>
    <style scoped>
      .tcv {
        container-type: inline-size;
        z-index: 0;
        --tc-paper: var(--tsp-background, var(--background, #fbf6ec));
        --tc-ink: var(--tsp-foreground, var(--foreground, #5a1a1a));
        --tc-gold: var(--tsp-accent, var(--accent, #a5854a));
        --tc-primary: var(--tsp-primary, var(--primary, #5a1a1a));
        --tc-serif: var(
          --tsp-font-serif,
          var(--font-serif, 'Cormorant Garamond', Georgia, serif)
        );
        --tc-sans: var(
          --tsp-font-sans,
          var(--font-sans, 'Jost', system-ui, sans-serif)
        );
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 8px;
        width: 100%;
        height: 100%;
        padding: 7%;
        background: var(--tc-paper);
        color: var(--tc-ink);
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
        border: 2px solid var(--tc-gold);
        border-radius: 8px;
        text-align: center;
        overflow: hidden;
        position: relative;
      }
      .tcv::before {
        content: '';
        position: absolute;
        inset: 6px;
        border: 1px solid color-mix(in srgb, var(--tc-gold) 45%, transparent);
        border-radius: 5px;
        pointer-events: none;
      }
      .tcv::after {
        content: '✦';
        position: absolute;
        bottom: 8px;
        left: 50%;
        transform: translateX(-50%);
        font-size: 10px;
        line-height: 1;
        color: color-mix(in srgb, var(--tc-primary) 70%, transparent);
        pointer-events: none;
      }
      /* Event-logo watermark: faint, centered, behind the content. */
      .cv-mark {
        position: absolute;
        inset: 0;
        margin: auto;
        height: 72%;
        max-width: 60%;
        object-fit: contain;
        opacity: 0.08;
        z-index: -1;
        pointer-events: none;
      }
      .tcv-event {
        font-family: var(--tc-sans);
        font-size: clamp(9px, 2.4cqw, 13px);
        letter-spacing: 0.26em;
        text-transform: uppercase;
        color: var(--tc-gold);
      }
      .tcv-name {
        display: flex;
        align-items: center;
        gap: 0.45em;
        max-width: 100%;
        font-family: var(--tc-serif);
        font-size: clamp(24px, 10cqw, 52px);
        font-weight: 700;
        line-height: 1;
        color: var(--tc-primary);
      }
      /* Classic stationery rules flanking the table name. */
      .tcv-name::before,
      .tcv-name::after {
        content: '';
        flex: none;
        width: 1.1em;
        height: 1px;
        background: color-mix(in srgb, var(--tc-primary) 45%, transparent);
      }
      .tcv-accent {
        font-family: var(--tc-serif);
        font-size: clamp(13px, 4cqw, 22px);
        font-style: italic;
        opacity: 0.8;
      }
      @media print {
        .tcv-event {
          color: color-mix(in srgb, var(--tc-gold) 50%, var(--tc-ink));
        }
      }
    </style>
  </template>
}
