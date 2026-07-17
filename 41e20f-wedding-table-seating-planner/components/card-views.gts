import Component from '@glimmer/component';

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
  };
}

export class PlaceCardView extends Component<PlaceCardSignature> {
  <template>
    <div class='pcv' ...attributes>
      {{#if @eventTitle}}
        <span class='pcv-event'>{{@eventTitle}}</span>
      {{/if}}
      <span class='pcv-name'>{{if @guestName @guestName 'Guest Name'}}</span>
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
        border: 1px solid var(--pc-gold);
        border-radius: 6px;
        text-align: center;
        overflow: hidden;
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
    </style>
  </template>
}

interface TableCardSignature {
  Element: HTMLDivElement;
  Args: {
    eventTitle?: string | null;
    tableName?: string | null;
    accent?: string | null;
  };
}

export class TableCardView extends Component<TableCardSignature> {
  <template>
    <div class='tcv' ...attributes>
      {{#if @eventTitle}}
        <span class='tcv-event'>{{@eventTitle}}</span>
      {{/if}}
      <span class='tcv-name'>{{if @tableName @tableName 'Table'}}</span>
      {{#if @accent}}
        <span class='tcv-accent'>{{@accent}}</span>
      {{/if}}
    </div>
    <style scoped>
      .tcv {
        container-type: inline-size;
        --tc-paper: var(--tsp-background, var(--background, #fbf6ec));
        --tc-ink: var(--tsp-foreground, var(--foreground, #5a1a1a));
        --tc-gold: var(--tsp-accent, var(--accent, #a5854a));
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
        border: 2px solid var(--tc-gold);
        border-radius: 8px;
        text-align: center;
        overflow: hidden;
      }
      .tcv-event {
        font-family: var(--tc-sans);
        font-size: clamp(9px, 2.4cqw, 13px);
        letter-spacing: 0.26em;
        text-transform: uppercase;
        color: var(--tc-gold);
      }
      .tcv-name {
        font-family: var(--tc-serif);
        font-size: clamp(28px, 14cqw, 72px);
        font-weight: 700;
        line-height: 1;
      }
      .tcv-accent {
        font-family: var(--tc-serif);
        font-size: clamp(13px, 4cqw, 22px);
        font-style: italic;
        opacity: 0.8;
      }
    </style>
  </template>
}
