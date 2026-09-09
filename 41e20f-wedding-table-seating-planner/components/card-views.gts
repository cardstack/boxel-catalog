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
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.375rem;
        width: 100%;
        height: 100%;
        padding: 8%;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
        border: 1px solid var(--accent);
        border-radius: 0.375rem;
        text-align: center;
        overflow: hidden;
        position: relative;
      }
      /* Themed stationery detail: hairline inner frame + corner flourish,
         both driven by the theme accent. */
      .pcv::before {
        content: '';
        position: absolute;
        inset: 0.3125rem;
        border: 1px solid color-mix(in oklch, var(--accent) 45%, transparent);
        border-radius: 0.25rem;
        pointer-events: none;
      }
      .pcv::after {
        content: '❧';
        position: absolute;
        top: 0.4375rem;
        left: 0.75rem;
        font-family: var(--font-serif);
        font-size: 0.8125rem;
        line-height: 1;
        color: color-mix(in oklch, var(--accent-ink) 70%, transparent);
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
        font-family: var(--font-sans);
        font-size: clamp(0.5rem, 2.6cqw, 0.75rem);
        letter-spacing: 0.22em;
        text-transform: uppercase;
        color: var(--accent-ink);
      }
      .pcv-name {
        font-family: var(--font-serif);
        font-size: clamp(1.25rem, 11cqw, 2.875rem);
        font-weight: 600;
        line-height: 1.05;
      }
      .pcv-rule {
        width: clamp(1.5rem, 9cqw, 2.75rem);
        height: 1px;
        background-color: var(--accent);
        color: var(--accent-foreground);
      }
      .pcv-table {
        font-family: var(--font-sans);
        font-size: clamp(0.5625rem, 3cqw, 0.8125rem);
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--accent-ink);
      }
      .pcv-msg {
        font-family: var(--font-serif);
        font-size: clamp(0.6875rem, 3.6cqw, 1rem);
        font-style: italic;
        opacity: 0.8;
      }
      /* Print keeps the theme's accent hue but deepens it toward the ink so
         the small-caps kicker/table label stay legible on paper. */
      @media print {
        .pcv-event,
        .pcv-table {
          color: color-mix(in oklch, var(--accent-ink) 50%, var(--foreground));
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
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.5rem;
        width: 100%;
        height: 100%;
        padding: 7%;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
        border: 2px solid var(--accent);
        border-radius: 0.5rem;
        text-align: center;
        overflow: hidden;
        position: relative;
      }
      .tcv::before {
        content: '';
        position: absolute;
        inset: 0.375rem;
        border: 1px solid color-mix(in oklch, var(--accent) 45%, transparent);
        border-radius: 0.3125rem;
        pointer-events: none;
      }
      .tcv::after {
        content: '✦';
        position: absolute;
        bottom: 0.5rem;
        left: 50%;
        transform: translateX(-50%);
        font-size: 0.625rem;
        line-height: 1;
        color: color-mix(in oklch, var(--primary-ink) 70%, transparent);
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
        font-family: var(--font-sans);
        font-size: clamp(0.5625rem, 2.4cqw, 0.8125rem);
        letter-spacing: 0.26em;
        text-transform: uppercase;
        color: var(--accent-ink);
      }
      .tcv-name {
        display: flex;
        align-items: center;
        gap: 0.45em;
        max-width: 100%;
        font-family: var(--font-serif);
        font-size: clamp(1.5rem, 10cqw, 3.25rem);
        font-weight: 700;
        line-height: 1;
        color: var(--primary-ink);
      }
      /* Classic stationery rules flanking the table name. */
      .tcv-name::before,
      .tcv-name::after {
        content: '';
        flex: none;
        width: 1.1em;
        height: 1px;
        background-color: color-mix(in oklch, var(--primary) 45%, transparent);
      }
      .tcv-accent {
        font-family: var(--font-serif);
        font-size: clamp(0.8125rem, 4cqw, 1.375rem);
        font-style: italic;
        opacity: 0.8;
      }
      @media print {
        .tcv-event {
          color: color-mix(in oklch, var(--accent-ink) 50%, var(--foreground));
        }
      }
    </style>
  </template>
}
