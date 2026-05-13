import type { MortgageCalculator } from '../mortgage-calculator';
import { Component } from 'https://cardstack.com/base/card-api';
import { formatCurrencyShort } from './utils';

export class MortgageCalculatorFitted extends Component<
  typeof MortgageCalculator
> {
  get currencyCode(): string {
    return this.args.model.currency?.code ?? 'USD';
  }
  get monthlyShort(): string {
    return formatCurrencyShort(this.args.model.monthlyTotal, this.currencyCode);
  }
  get loanShort(): string {
    return formatCurrencyShort(this.args.model.loanAmount, this.currencyCode);
  }
  get interestShort(): string {
    return formatCurrencyShort(
      this.args.model.lifetimeInterest,
      this.currencyCode,
    );
  }
  get rate(): string {
    const r = this.args.model.interestRatePercentage;
    return r != null ? `${r}%` : '—';
  }
  get term(): string {
    const t = this.args.model.loanTermYears;
    return t != null ? `${t} yr` : '—';
  }
  get down(): string {
    const d = this.args.model.downPaymentPercentage;
    return d != null ? `${d}%` : '—';
  }

  <template>
    <div class='mcf-root'>

      {{! ── BADGE  ≤150×169 — left-aligned: thumbnail | title + amount ── }}
      <div class='mcf-badge'>
        <div class='mcf-b-img'></div>
        <div class='mcf-b-body'>
          <div class='mcf-b-title'>Mortgage</div>
          <div class='mcf-b-amount'>{{this.monthlyShort}}</div>
          <div class='mcf-b-sub'>/mo · {{this.currencyCode}}</div>
        </div>
      </div>

      {{! ── STRIP  ≥151px wide, ≤169px tall ── }}
      <div class='mcf-strip'>
        <div class='mcf-s-img'></div>
        <div class='mcf-s-body'>
          <div class='mcf-s-title'>Mortgage Calculator</div>
          <div class='mcf-s-meta'>{{this.term}}
            ·
            {{this.rate}}
            ·
            {{this.down}}
            down</div>
        </div>
        <div class='mcf-s-right'>
          <div class='mcf-s-cc'>{{this.currencyCode}}</div>
          <div class='mcf-s-amount'>{{this.monthlyShort}}</div>
          <div class='mcf-s-mo'>/month</div>
        </div>
      </div>

      {{! ── TILE  ≤399px wide, ≥170px tall ── }}
      <div class='mcf-tile'>
        <div class='mcf-t-img'>
          <span class='mcf-t-cc'>{{this.currencyCode}}</span>
          <span class='mcf-t-rate'>{{this.rate}}</span>
        </div>
        <div class='mcf-t-body'>
          <div class='mcf-t-name'>Mortgage Calculator</div>
          <div class='mcf-t-label'>Monthly payment</div>
          <div class='mcf-t-amount'>{{this.monthlyShort}}</div>
          <div class='mcf-t-chips'>
            <div class='mcf-t-chip'><span>Loan</span>{{this.loanShort}}</div>
            <div class='mcf-t-chip'><span>Term</span>{{this.term}}</div>
            <div class='mcf-t-chip'><span>Down</span>{{this.down}}</div>
          </div>
        </div>
      </div>

      {{! ── CARD  ≥400px wide, ≥170px tall ── }}
      <div class='mcf-card'>
        {{! golden-ratio image: left column compact, top header when tall }}
        <div class='mcf-c-img'>
          <div class='mcf-c-img-inner'>
            <h3 class='mcf-c-title'>Mortgage Calculator</h3>
            <span class='mcf-c-pill'>{{this.currencyCode}}
              ·
              {{this.rate}}
              ·
              {{this.term}}</span>
          </div>
        </div>
        <div class='mcf-c-body'>
          <div class='mcf-c-hero'>
            <span class='mcf-c-hero-label'>Monthly payment</span>
            <span class='mcf-c-hero-val'>{{this.monthlyShort}}</span>
          </div>
          <div class='mcf-c-divider'></div>
          <div class='mcf-c-grid'>
            <div class='mcf-c-stat'>
              <span class='mcf-c-stat-label'>Loan</span>
              <span class='mcf-c-stat-val'>{{this.loanShort}}</span>
            </div>
            <div class='mcf-c-stat'>
              <span class='mcf-c-stat-label'>Interest</span>
              <span class='mcf-c-stat-val'>{{this.interestShort}}</span>
            </div>
            <div class='mcf-c-stat'>
              <span class='mcf-c-stat-label'>Down</span>
              <span class='mcf-c-stat-val'>{{this.down}}</span>
            </div>
            <div class='mcf-c-stat'>
              <span class='mcf-c-stat-label'>Term</span>
              <span class='mcf-c-stat-val'>{{this.term}}</span>
            </div>
          </div>
        </div>
      </div>

    </div>

    <style scoped>
      /* ── design tokens ── */
      .mcf-root {
        --mc-green: #059669;
        --mc-green-dark: #047857;
        --mc-green-bg: #ecfdf5;
        --mc-green-border: #6ee7b7;
        --mc-teal: #007272;
        --mc-teal-dark: #005858;
        --mc-text: #0f172a;
        --mc-text-2: #1e293b;
        --mc-muted: #64748b;
        --mc-surface: #ffffff;
        --mc-shadow:
          0 1px 3px rgba(0, 0, 0, 0.08), 0 1px 2px rgba(0, 0, 0, 0.05);
        --mc-shadow-md:
          0 4px 16px rgba(0, 0, 0, 0.1), 0 2px 4px rgba(0, 0, 0, 0.05);
        --mc-overlay: linear-gradient(
          135deg,
          rgba(255, 200, 60, 0.18) 0%,
          rgba(60, 120, 40, 0.32) 35%,
          rgba(8, 38, 18, 0.72) 70%,
          rgba(3, 18, 8, 0.9) 100%
        );
        --mc-img-url: url('https://images.pexels.com/photos/31737842/pexels-photo-31737842.jpeg?auto=compress&cs=tinysrgb&w=800');
        container-type: size;
        width: 100%;
        height: 100%;
        font-family:
          'Inter',
          -apple-system,
          BlinkMacSystemFont,
          sans-serif;
      }

      /* hide all by default */
      .mcf-badge,
      .mcf-strip,
      .mcf-tile,
      .mcf-card {
        display: none;
        width: 100%;
        height: 100%;
        box-sizing: border-box;
        overflow: hidden;
        border-radius: 0.75rem;
      }

      /* ══════════════════════════════════════
         BADGE  ≤150 × ≤169
         Left-aligned: thumbnail | title + amount + sub
      ══════════════════════════════════════ */
      @container (max-width: 150px) and (max-height: 169px) {
        .mcf-badge {
          display: flex;
          align-items: stretch;
          background: var(--mc-surface);
          border: 1px solid var(--mc-green-border);
          box-shadow: var(--mc-shadow);
        }
      }

      .mcf-b-img {
        width: 34px;
        flex-shrink: 0;
        background:
          var(--mc-overlay),
          var(--mc-img-url) center / cover no-repeat;
      }

      .mcf-b-body {
        flex: 1;
        min-width: 0;
        padding: clamp(0.25rem, 3%, 0.5rem);
        display: flex;
        flex-direction: column;
        justify-content: center;
        gap: 0.1rem;
      }

      .mcf-b-title {
        font-size: 0.5625rem;
        font-weight: 700;
        color: var(--mc-text);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .mcf-b-amount {
        font-size: 0.8125rem;
        font-weight: 800;
        color: var(--mc-teal);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        letter-spacing: -0.01em;
      }

      .mcf-b-sub {
        font-size: 0.5rem;
        font-weight: 600;
        color: var(--mc-muted);
        white-space: nowrap;
      }

      /* ══════════════════════════════════════
         STRIP  ≥151px wide, ≤169px tall
         image | title (never truncated) + meta | amount | cc pill
      ══════════════════════════════════════ */
      @container (min-width: 151px) and (max-height: 169px) {
        .mcf-strip {
          display: flex;
          align-items: stretch;
          background: var(--mc-surface);
          border: 1px solid var(--mc-green-border);
          box-shadow: var(--mc-shadow);
        }
      }

      .mcf-s-img {
        width: clamp(40px, 15%, 56px);
        flex-shrink: 0;
        background:
          var(--mc-overlay),
          var(--mc-img-url) center / cover no-repeat;
      }

      .mcf-s-body {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        padding: 0.375rem 0.5rem;
        display: flex;
        flex-direction: column;
        justify-content: center;
        gap: 0.15rem;
      }

      /* title MUST always be fully visible — no ellipsis per skill spec */
      .mcf-s-title {
        font-size: 0.75rem;
        font-weight: 700;
        color: var(--mc-text);
        white-space: nowrap;
        line-height: 1.25;
      }

      .mcf-s-meta {
        font-size: 0.5625rem;
        font-weight: 500;
        color: var(--mc-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .mcf-s-right {
        padding: 0.3rem 0.5rem 0.3rem 0.25rem;
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: flex-end;
        flex-shrink: 0;
        max-width: 44%;
        gap: 0.1rem;
      }

      .mcf-s-cc {
        font-size: 0.5rem;
        font-weight: 700;
        color: #fff;
        background: var(--mc-teal);
        border-radius: 999px;
        padding: 0.1rem 0.3rem;
        white-space: nowrap;
        line-height: 1.4;
      }

      .mcf-s-amount {
        font-size: 0.8125rem;
        font-weight: 800;
        color: var(--mc-teal);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        letter-spacing: -0.02em;
        line-height: 1.1;
      }

      .mcf-s-mo {
        font-size: 0.4375rem;
        font-weight: 600;
        color: var(--mc-muted);
        text-transform: uppercase;
        letter-spacing: 0.04em;
        line-height: 1.2;
      }

      /* ══════════════════════════════════════
         TILE  ≤399px wide, ≥170px tall
         image header | name | monthly hero | bottom chips (magnetic)
      ══════════════════════════════════════ */
      @container (max-width: 399px) and (min-height: 170px) {
        .mcf-tile {
          display: flex;
          flex-direction: column;
          background: var(--mc-surface);
          border: 1px solid var(--mc-green-border);
          box-shadow: var(--mc-shadow);
        }
      }

      .mcf-t-img {
        height: clamp(52px, 30%, 80px);
        flex-shrink: 0;
        background:
          var(--mc-overlay),
          var(--mc-img-url) center / cover no-repeat;
        display: flex;
        align-items: flex-end;
        gap: 0.375rem;
        padding: 0.375rem 0.5rem;
      }

      .mcf-t-cc {
        font-size: 0.5625rem;
        font-weight: 700;
        color: #fff;
        background: rgba(255, 255, 255, 0.18);
        border: 1px solid rgba(255, 255, 255, 0.3);
        border-radius: 999px;
        padding: 0.1rem 0.4rem;
        backdrop-filter: blur(4px);
      }

      .mcf-t-rate {
        font-size: 0.5625rem;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.8);
      }

      .mcf-t-body {
        flex: 1;
        padding: clamp(0.5rem, 4%, 0.75rem);
        display: flex;
        flex-direction: column;
        gap: 0.2rem;
        min-height: 0;
      }

      .mcf-t-name {
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--mc-text);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .mcf-t-label {
        font-size: 0.5rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.07em;
        color: var(--mc-muted);
        margin-top: 0.25rem;
      }

      .mcf-t-amount {
        font-size: clamp(1.125rem, 6cqi, 1.75rem);
        font-weight: 800;
        color: var(--mc-teal);
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        line-height: 1.1;
      }

      /* magnetic bottom */
      .mcf-t-chips {
        display: flex;
        gap: 0.25rem;
        margin-top: auto;
        padding-top: 0.375rem;
      }

      .mcf-t-chip {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        background: var(--mc-green-bg);
        border: 1px solid var(--mc-green-border);
        border-radius: 0.5rem;
        padding: 0.25rem 0.375rem;
        display: flex;
        flex-direction: column;
        gap: 0.1rem;
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--mc-text-2);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        text-overflow: ellipsis;
      }

      .mcf-t-chip span {
        font-size: 0.4375rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--mc-muted);
        white-space: nowrap;
      }

      /* ══════════════════════════════════════
         CARD  ≥400px wide, ≥170px tall
         Compact (170-299): horizontal golden-ratio split (38% img | 62% body)
         Tall (≥300): image header stacked on top
      ══════════════════════════════════════ */
      @container (min-width: 400px) and (min-height: 170px) {
        .mcf-card {
          display: flex;
          flex-direction: row;
          background: var(--mc-surface);
          border: 1px solid var(--mc-green-border);
          box-shadow: var(--mc-shadow-md);
        }
      }

      @container (min-width: 400px) and (min-height: 300px) {
        .mcf-card {
          flex-direction: column;
        }

        .mcf-c-img {
          width: 100% !important;
          height: clamp(80px, 32%, 130px) !important;
        }

        .mcf-c-body {
          width: 100% !important;
          justify-content: flex-start !important;
        }
      }

      .mcf-c-img {
        width: 38%;
        flex-shrink: 0;
        background:
          var(--mc-overlay),
          var(--mc-img-url) center / cover no-repeat;
        display: flex;
        flex-direction: column;
        justify-content: flex-end;
        padding: clamp(0.5rem, 3%, 0.875rem);
        box-sizing: border-box;
      }

      .mcf-c-img-inner {
        display: flex;
        flex-direction: column;
        gap: 0.3rem;
      }

      .mcf-c-title {
        margin: 0;
        font-size: clamp(0.75rem, 3cqi, 1rem);
        font-weight: 800;
        color: #ffffff;
        text-shadow: 0 1px 6px rgba(0, 0, 0, 0.45);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        line-height: 1.2;
      }

      .mcf-c-pill {
        font-size: 0.5rem;
        font-weight: 700;
        color: #fff;
        background: rgba(255, 255, 255, 0.16);
        border: 1px solid rgba(255, 255, 255, 0.28);
        border-radius: 999px;
        padding: 0.15rem 0.5rem;
        white-space: nowrap;
        backdrop-filter: blur(6px);
        align-self: flex-start;
      }

      .mcf-c-body {
        flex: 1;
        min-width: 0;
        padding: clamp(0.5rem, 3%, 0.875rem);
        display: flex;
        flex-direction: column;
        justify-content: center;
        gap: 0.5rem;
        box-sizing: border-box;
      }

      .mcf-c-hero {
        display: flex;
        flex-direction: column;
        gap: 0.1rem;
      }

      .mcf-c-hero-label {
        font-size: 0.5rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.07em;
        color: var(--mc-muted);
      }

      .mcf-c-hero-val {
        font-size: clamp(1rem, 4cqi, 1.625rem);
        font-weight: 800;
        color: var(--mc-teal);
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        line-height: 1.1;
      }

      .mcf-c-divider {
        height: 1px;
        background: var(--mc-green-border);
        opacity: 0.7;
      }

      .mcf-c-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 0.3rem;
      }

      .mcf-c-stat {
        display: flex;
        flex-direction: column;
        gap: 0.1rem;
        background: var(--mc-green-bg);
        border: 1px solid var(--mc-green-border);
        border-radius: 0.5rem;
        padding: 0.25rem 0.4rem;
        min-width: 0;
        overflow: hidden;
      }

      .mcf-c-stat-label {
        font-size: 0.4375rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--mc-muted);
        white-space: nowrap;
      }

      .mcf-c-stat-val {
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--mc-text-2);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      @media (prefers-reduced-motion: reduce) {
        .mcf-badge,
        .mcf-strip,
        .mcf-tile,
        .mcf-card {
          transition: none;
        }
      }
    </style>
  </template>
}
