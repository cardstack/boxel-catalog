import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';

import { RfqToPaymentConsole } from './rfq-to-payment-console';

// RFQ-to-Payment App — the buyer's Procure-to-Pay console. Composes the
// procurement blocks UNCHANGED: live-queries every stage of the chain,
// narrates it as a flow rail (Requisitions → RFQs → Approvals → Receiving)
// whose stations click through to pre-filtered lists, renders budgets
// through ProcurementBudget's own embedded format (the dual-segment
// commitment bar), and keeps every status transition on its owning command —
// no drag-to-approve here, deliberately. Prerender gets a static shell.
export class RfqToPaymentApp extends CardDef {
  static displayName = 'RFQ to Payment';
  static headerColor = '#3e4e88';
  static prefersWideFormat = true;

  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'RFQ to Payment';
    },
  });

  static isolated = RfqToPaymentConsole;

  // Identity-bearing fitted — same command-band world as its sibling app,
  // with the P2P rail as the family glyph. Static (prerender-safe), anchor
  // typographic, type scale capped against cqb so no quantum can shear.
  static fitted = class Fitted extends Component<typeof RfqToPaymentApp> {
    <template>
      <div class='fit'>
        <span class='eyebrow'>Procurement</span>
        <span class='name'>RFQ to Payment</span>
        <span class='sub'>requisition → quote → approve → receive</span>
        <div class='rail-glyph' aria-hidden='true'>
          <i class='lit'></i><span></span><i></i><span></span><i></i><span
          ></span><i></i>
        </div>
      </div>
      <style scoped>
        .fit {
          /* two-scope chain, --boxel-* terminal, no literals */
          --fit-bg: var(--procurement-ink, var(--primary, var(--boxel-dark)));
          --fit-fg: var(
            --procurement-ink-fg,
            var(--primary-foreground, var(--boxel-light))
          );
          --fit-grid: color-mix(in oklch, var(--fit-fg) 7%, transparent);
          --type-base: clamp(10px, min(calc(3px + 2.1cqi + 1cqb), 10cqb), 17px);
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, auto) auto 1fr;
          align-content: start;
          gap: calc(var(--type-base) * 0.25);
          padding: calc(var(--type-base) * 0.8);
          overflow: hidden;
          background:
            linear-gradient(var(--fit-grid) 1px, transparent 1px),
            linear-gradient(90deg, var(--fit-grid) 1px, transparent 1px),
            linear-gradient(
              120deg,
              color-mix(in oklch, var(--fit-bg) 96%, var(--boxel-dark)),
              var(--fit-bg)
            );
          background-size:
            22px 22px,
            22px 22px,
            100% 100%;
          color: var(--fit-fg);
          font-family: var(--font-sans, inherit);
        }
        .eyebrow {
          font-size: max(calc(var(--type-base) * 0.62), 8px);
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: color-mix(in oklch, var(--fit-fg) 62%, transparent);
          line-height: 1.2;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .name {
          font-size: calc(var(--type-base) * 1.5);
          font-weight: 700;
          letter-spacing: -0.015em;
          line-height: 1.15;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .sub {
          font-size: max(calc(var(--type-base) * 0.72), 9px);
          color: color-mix(in oklch, var(--fit-fg) 70%, transparent);
          line-height: 1.3;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .rail-glyph {
          align-self: end;
          display: flex;
          align-items: center;
          gap: 4px;
        }
        .rail-glyph i {
          width: 13%;
          max-width: 30px;
          height: 7px;
          border-radius: 3px;
          border: 1px solid color-mix(in oklch, var(--fit-fg) 40%, transparent);
          background: color-mix(in oklch, var(--fit-fg) 12%, transparent);
          flex: 0 1 auto;
        }
        .rail-glyph i.lit {
          background: var(--fit-fg);
          border-color: var(--fit-fg);
        }
        .rail-glyph span {
          width: 8px;
          height: 1px;
          background: color-mix(in oklch, var(--fit-fg) 30%, transparent);
          flex: 0 0 auto;
        }
        @container fitted-card (height <= 105px) {
          .sub,
          .rail-glyph {
            display: none;
          }
        }
        @container fitted-card (height <= 65px) {
          .fit {
            grid-template-rows: 1fr;
            align-items: center;
          }
          .eyebrow {
            display: none;
          }
          .name {
            -webkit-line-clamp: 1;
          }
        }
      </style>
    </template>
  };
}

