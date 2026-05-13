import type { MortgageCalculator } from '../mortgage-calculator';
import { Component } from 'https://cardstack.com/base/card-api';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn, concat } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import OneShotLlmRequestCommand from '@cardstack/boxel-host/commands/one-shot-llm-request';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { LineChart } from './line-chart';
import type { AmortPoint } from './line-chart';
import { DonutChart } from './donut-chart';
import type { DonutSectionData } from './donut-chart';
import { formatCurrency, formatCurrencyShort } from './utils';

export class MortgageCalculatorIsolated extends Component<
  typeof MortgageCalculator
> {
  @tracked activeTab: 'breakdown' | 'timeline' = 'timeline';
  @tracked quickFillText = '';
  @tracked quickFillStatus: 'idle' | 'loading' | 'success' | 'error' = 'idle';
  @tracked quickFillError = '';
  @tracked lastSnapshot: Record<string, number> | null = null;
  @tracked quickFillOpen = true;
  @tracked debugRaw = '';

  /* amortization schedule for the line chart */
  get amortization(): AmortPoint[] {
    const { model } = this.args;
    const years = model.loanTermYears ?? 0;
    const monthlyPayment = model.monthlyMortgagePayment ?? 0;
    const monthlyRate = model.monthlyInterestRate ?? 0;
    let balance = model.loanAmount ?? 0;
    const out: AmortPoint[] = [
      {
        year: 0,
        principalPaid: 0,
        interestPaid: 0,
        totalPaid: 0,
        balance,
      },
    ];
    if (!years || !monthlyPayment || balance <= 0) return out;
    let cumPrincipal = 0;
    let cumInterest = 0;
    for (let y = 1; y <= years; y++) {
      for (let m = 0; m < 12 && balance > 0; m++) {
        const interest = balance * monthlyRate;
        let principal = monthlyPayment - interest;
        if (principal > balance) principal = balance;
        balance -= principal;
        cumPrincipal += principal;
        cumInterest += interest;
      }
      out.push({
        year: y,
        principalPaid: cumPrincipal,
        interestPaid: cumInterest,
        totalPaid: cumPrincipal + cumInterest,
        balance: Math.max(0, balance),
      });
    }
    return out;
  }

  get chartData(): DonutSectionData[] {
    let { model } = this.args;
    const total = model.monthlyTotal || 1;
    return [
      {
        value: model.monthlyMortgagePayment,
        color: 'var(--mc-green, #059669)',
        label: 'Principal & Interest',
        percent: Math.round(
          ((model.monthlyMortgagePayment ?? 0) / total) * 100,
        ),
      },
      {
        value: model.taxPerMonth,
        color: 'var(--chart-2, #589BFF)',
        label: 'Property Taxes',
        percent: Math.round(((model.taxPerMonth ?? 0) / total) * 100),
      },
      {
        value: model.insurancePerMonth,
        color: 'var(--chart-5, #ef4444)',
        label: 'Home Insurance',
        percent: Math.round(((model.insurancePerMonth ?? 0) / total) * 100),
      },
      {
        value: model.hoaFeesPerMonth,
        color: 'var(--chart-4, #f59e0b)',
        label: 'HOA Fees',
        percent: Math.round(((model.hoaFeesPerMonth ?? 0) / total) * 100),
      },
    ];
  }

  @action
  setTab(tab: 'breakdown' | 'timeline') {
    this.activeTab = tab;
  }

  @action
  updateQuickFillText(evt: Event) {
    this.quickFillText = (evt.target as HTMLTextAreaElement).value;
  }

  @action
  toggleQuickFill() {
    this.quickFillOpen = !this.quickFillOpen;
  }

  @action
  async runQuickFill() {
    const commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.quickFillStatus = 'error';
      this.quickFillError =
        'Command context unavailable — open this card in the full view rather than embedded.';
      return;
    }
    const text = this.quickFillText.trim();
    if (!text) {
      this.quickFillStatus = 'error';
      this.quickFillError = 'Paste a Zillow URL or listing description first.';
      return;
    }
    this.quickFillStatus = 'loading';
    this.quickFillError = '';
    this.debugRaw = '';
    try {
      const cc = this.currencyCode;
      const systemPrompt = `You extract structured mortgage data from real-estate listings.
INPUT: a URL or free-text description.
OUTPUT: ONE JSON object only — no prose, no markdown fences, no commentary.

The user's selected currency is ${cc}. Return ALL monetary values converted to ${cc} using your best knowledge of current exchange rates. Do not return USD values if the currency is not USD.

Required keys (all numeric except sourceNotes):
{
  "homePrice": number,              // listing price in ${cc}
  "downPaymentPercentage": number,  // default 20
  "loanTermYears": number,          // default 30
  "interestRatePercentage": number, // typical rate for the property's country, or 6.8 if unknown
  "taxPerMonth": number,            // monthly property tax in ${cc} — use listing data or estimate
  "insurancePerMonth": number,      // monthly home insurance in ${cc} — estimate if not given
  "hoaFeesPerMonth": number,        // monthly HOA in ${cc}, 0 if detached/no HOA
  "sourceNotes": string             // one short sentence noting currency used and any conversions applied
}

Use reasonable defaults whenever a value is missing. Never return null.`;
      const command = new OneShotLlmRequestCommand(commandContext);

      console.log('[QuickFill] invoking LLM with text:', text);
      const result = await command.execute({
        systemPrompt,
        userPrompt: text,
        llmModel: 'anthropic/claude-haiku-4.5',
      });

      console.log('[QuickFill] raw result:', result);
      const raw =
        (result as any)?.output ?? (result as any)?.attributes?.output ?? '';
      this.debugRaw = String(raw).slice(0, 800);

      console.log('[QuickFill] raw output:', raw);
      const parsed = this.parseLlmJson(String(raw));
      if (!parsed) {
        throw new Error(
          `Couldn't parse JSON from the response. Raw output shown below.`,
        );
      }
      console.log('[QuickFill] parsed values:', parsed);
      this.lastSnapshot = this.snapshot();
      this.applyValues(parsed);
      // Persist so any computed fields recompute and edit inputs reflect the new values
      try {
        const { model } = this.args;
        await new SaveCardCommand(commandContext).execute({
          card: model as any,
        });
      } catch (saveErr) {
        console.warn('[QuickFill] save failed (values still applied)', saveErr);
      }
      this.quickFillStatus = 'success';
    } catch (err: any) {
      console.error('[QuickFill] error', err);
      this.quickFillStatus = 'error';
      this.quickFillError = err?.message ?? 'Unknown error';
    }
  }

  @action
  undoQuickFill() {
    if (!this.lastSnapshot) return;
    this.applyValues(this.lastSnapshot);
    this.lastSnapshot = null;
    this.quickFillStatus = 'idle';
  }

  parseLlmJson(raw: string): Record<string, number> | null {
    if (!raw) return null;
    let text = raw.trim();
    const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fenced) text = fenced[1].trim();
    try {
      const obj = JSON.parse(text);
      return this.coerce(obj);
    } catch {
      const start = text.indexOf('{');
      const end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          const obj = JSON.parse(text.slice(start, end + 1));
          return this.coerce(obj);
        } catch {
          return null;
        }
      }
      return null;
    }
  }

  coerce(obj: any): Record<string, number> | null {
    if (!obj || typeof obj !== 'object') return null;
    const keys = [
      'homePrice',
      'downPaymentPercentage',
      'loanTermYears',
      'interestRatePercentage',
      'taxPerMonth',
      'insurancePerMonth',
      'hoaFeesPerMonth',
    ];
    const out: Record<string, number> = {};
    for (const k of keys) {
      const v = Number(obj[k]);
      if (Number.isFinite(v)) out[k] = v;
    }
    return Object.keys(out).length ? out : null;
  }

  snapshot(): Record<string, number> {
    const { model } = this.args;
    return {
      homePrice: model.homePrice ?? 0,
      downPaymentPercentage: model.downPaymentPercentage ?? 0,
      loanTermYears: model.loanTermYears ?? 0,
      interestRatePercentage: model.interestRatePercentage ?? 0,
      taxPerMonth: model.taxPerMonth ?? 0,
      insurancePerMonth: model.insurancePerMonth ?? 0,
      hoaFeesPerMonth: model.hoaFeesPerMonth ?? 0,
    };
  }

  applyValues(values: Record<string, number>) {
    const { model } = this.args;
    if (values.homePrice !== undefined) model.homePrice = values.homePrice;
    if (values.downPaymentPercentage !== undefined)
      model.downPaymentPercentage = values.downPaymentPercentage;
    if (values.loanTermYears !== undefined)
      model.loanTermYears = values.loanTermYears;
    if (values.interestRatePercentage !== undefined)
      model.interestRatePercentage = values.interestRatePercentage;
    if (values.taxPerMonth !== undefined)
      model.taxPerMonth = values.taxPerMonth;
    if (values.insurancePerMonth !== undefined)
      model.insurancePerMonth = values.insurancePerMonth;
    if (values.hoaFeesPerMonth !== undefined)
      model.hoaFeesPerMonth = values.hoaFeesPerMonth;
  }

  get currencyCode(): string {
    return this.args.model.currency?.code ?? 'USD';
  }

  get headerStyle() {
    return htmlSafe(
      'background: linear-gradient(135deg, rgba(255,200,60,0.18) 0%, rgba(60,120,40,0.32) 35%, rgba(8,38,18,0.72) 70%, rgba(3,18,8,0.90) 100%), url(https://images.pexels.com/photos/31737842/pexels-photo-31737842.jpeg?auto=compress&cs=tinysrgb&w=1400) center / cover no-repeat',
    );
  }

  isLoading = (): boolean => {
    return this.quickFillStatus === 'loading';
  };

  <template>
    <section class='mc-wrapper'>
      <header class='mc-header' style={{this.headerStyle}}>
        <div class='mc-title-row'>
          <h1 class='mc-title'>Mortgage Calculator</h1>
          <button
            type='button'
            class='mc-quickfill-btn'
            {{on 'click' this.toggleQuickFill}}
          >
            <svg
              width='14'
              height='14'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2.5'
              stroke-linecap='round'
              stroke-linejoin='round'
            ><path
                d='m12 3 1.9 5.8a2 2 0 0 0 1.3 1.3L21 12l-5.8 1.9a2 2 0 0 0-1.3 1.3L12 21l-1.9-5.8a2 2 0 0 0-1.3-1.3L3 12l5.8-1.9a2 2 0 0 0 1.3-1.3Z'
              /></svg>
            {{if
              this.quickFillOpen
              'Hide quick fill'
              'Quick fill from listing'
            }}
          </button>
        </div>
        {{#if this.quickFillOpen}}
          <div class='mc-quickfill'>
            <textarea
              class='mc-quickfill-input'
              placeholder='Paste a Zillow URL or listing description (e.g. "3-bed, 2-bath in Austin TX, $625k, $4,200 annual taxes")'
              value={{this.quickFillText}}
              {{on 'input' this.updateQuickFillText}}
              rows='2'
            ></textarea>
            <div class='mc-quickfill-actions'>
              <button
                type='button'
                class='mc-btn mc-btn-primary'
                disabled={{eq this.quickFillStatus 'loading'}}
                {{on 'click' this.runQuickFill}}
              >
                {{#if (eq this.quickFillStatus 'loading')}}
                  <span class='mc-spinner'></span>
                  Extracting…
                {{else}}
                  Fill from listing
                {{/if}}
              </button>
              {{#if this.lastSnapshot}}
                <button
                  type='button'
                  class='mc-btn mc-btn-ghost'
                  {{on 'click' this.undoQuickFill}}
                >Undo</button>
              {{/if}}
            </div>
            {{#if (eq this.quickFillStatus 'success')}}
              <p class='mc-quickfill-msg success'>
                <svg
                  width='13'
                  height='13'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2.5'
                  stroke-linecap='round'
                  stroke-linejoin='round'
                ><polyline points='20 6 9 17 4 12' /></svg>
                Filled! Tweak any field as needed.
              </p>
            {{/if}}
            {{#if (eq this.quickFillStatus 'error')}}
              <div class='mc-quickfill-msg error'>
                <strong>Couldn't fill.</strong>
                {{this.quickFillError}}
                {{#if this.debugRaw}}
                  <details class='mc-debug'>
                    <summary>Show raw response</summary>
                    <pre>{{this.debugRaw}}</pre>
                  </details>
                {{/if}}
              </div>
            {{/if}}
          </div>
        {{/if}}
        <div class='mc-currency-notice'>
          <svg
            width='12'
            height='12'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2.5'
            stroke-linecap='round'
            stroke-linejoin='round'
          ><circle cx='12' cy='12' r='10' /><path
              d='M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8'
            /><path d='M12 18V6' /></svg>
          All amounts are displayed in
          <strong>{{this.currencyCode}}</strong>. Quick fill results will be
          converted to this currency using estimated exchange rates.
        </div>
      </header>

      <div class='mc-body'>
        <aside class='mc-form'>
          <div class='mc-currency-row'>
            <span class='mc-currency-label'>
              <svg
                width='13'
                height='13'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2.5'
                stroke-linecap='round'
                stroke-linejoin='round'
              ><circle cx='12' cy='12' r='10' /><path
                  d='M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8'
                /><path d='M12 18V6' /></svg>
              Currency
            </span>
            <@fields.currency @format='edit' />
          </div>

          <label>Home price</label>
          <@fields.homePrice @format='edit' />

          <label>Down payment (%)</label>
          <@fields.downPaymentPercentage @format='edit' />

          <label>Loan term (years)</label>
          <@fields.loanTermYears @format='edit' />

          <label>Interest rate (%)</label>
          <@fields.interestRatePercentage @format='edit' />

          <label>Prop. tax / month</label>
          <@fields.taxPerMonth @format='edit' />

          <label>Home ins. / month</label>
          <@fields.insurancePerMonth @format='edit' />

          <label>HOA fees / month</label>
          <@fields.hoaFeesPerMonth @format='edit' />
        </aside>

        <div class='mc-results'>
          <div class='mc-summary'>
            <div class='mc-stat'>
              <span class='mc-stat-label'>Loan amount</span>
              <span class='mc-stat-value'>{{formatCurrencyShort
                  @model.loanAmount
                  this.currencyCode
                }}</span>
            </div>
            <div class='mc-stat'>
              <span class='mc-stat-label'>Down payment</span>
              <span class='mc-stat-value'>{{formatCurrencyShort
                  @model.downPayment
                  this.currencyCode
                }}</span>
            </div>
            <div class='mc-stat highlight'>
              <span class='mc-stat-label'>Monthly payment</span>
              <span class='mc-stat-value'>{{formatCurrencyShort
                  @model.monthlyTotal
                  this.currencyCode
                }}</span>
            </div>
            <div class='mc-stat'>
              <span class='mc-stat-label'>Total interest</span>
              <span class='mc-stat-value'>{{formatCurrencyShort
                  @model.lifetimeInterest
                  this.currencyCode
                }}</span>
            </div>
          </div>

          <div class='mc-table'>
            <div class='mc-table-row mc-table-head'>
              <span></span>
              <span>Monthly</span>
              <span>Lifetime</span>
            </div>
            <div class='mc-table-row featured'>
              <span>Mortgage (P&amp;I)</span>
              <span>{{formatCurrency
                  @model.monthlyMortgagePayment
                  this.currencyCode
                }}</span>
              <span>{{formatCurrency
                  @model.lifetimeMortgagePayment
                  this.currencyCode
                }}</span>
            </div>
            <div class='mc-table-row'>
              <span>Property tax</span>
              <span>{{formatCurrency
                  @model.taxPerMonth
                  this.currencyCode
                }}</span>
              <span>{{formatCurrency
                  @model.lifetimeTaxes
                  this.currencyCode
                }}</span>
            </div>
            <div class='mc-table-row'>
              <span>Home insurance</span>
              <span>{{formatCurrency
                  @model.insurancePerMonth
                  this.currencyCode
                }}</span>
              <span>{{formatCurrency
                  @model.lifetimeInsurance
                  this.currencyCode
                }}</span>
            </div>
            <div class='mc-table-row'>
              <span>HOA fees</span>
              <span>{{formatCurrency
                  @model.hoaFeesPerMonth
                  this.currencyCode
                }}</span>
              <span>{{formatCurrency
                  @model.lifetimeHoaFees
                  this.currencyCode
                }}</span>
            </div>
            <div class='mc-table-row total'>
              <span>Total out-of-pocket</span>
              <span>{{formatCurrency
                  @model.monthlyTotal
                  this.currencyCode
                }}</span>
              <span>{{formatCurrency
                  @model.lifetimeTotal
                  this.currencyCode
                }}</span>
            </div>
          </div>

          <div class='mc-charts'>
            <div class='mc-tabs' role='tablist'>
              <button
                type='button'
                role='tab'
                class={{if
                  (eq this.activeTab 'timeline')
                  'mc-tab active'
                  'mc-tab'
                }}
                {{on 'click' (fn this.setTab 'timeline')}}
              >Pay-off over time</button>
              <button
                type='button'
                role='tab'
                class={{if
                  (eq this.activeTab 'breakdown')
                  'mc-tab active'
                  'mc-tab'
                }}
                {{on 'click' (fn this.setTab 'breakdown')}}
              >Monthly breakdown</button>
            </div>

            {{#if (eq this.activeTab 'timeline')}}
              <div class='mc-chart-panel'>
                <LineChart
                  @data={{this.amortization}}
                  @height={{300}}
                  @currencyCode={{this.currencyCode}}
                />
              </div>
            {{else}}
              <div class='mc-chart-panel breakdown'>
                <DonutChart
                  @data={{this.chartData}}
                  @size={{180}}
                  @currencyCode={{this.currencyCode}}
                />
                <div class='mc-legend'>
                  {{#each this.chartData as |item|}}
                    <div class='mc-legend-row'>
                      <span
                        class='mc-legend-swatch'
                        style={{htmlSafe (concat 'background:' item.color)}}
                      ></span>
                      <span class='mc-legend-label'>{{item.label}}</span>
                      <span class='mc-legend-pct'>{{item.percent}}%</span>
                    </div>
                  {{/each}}
                </div>
              </div>
            {{/if}}
          </div>
        </div>
      </div>
    </section>

    <style scoped>
      .mc-wrapper {
        container-type: inline-size;
        margin: 0 auto;
        padding: var(--boxel-sp-lg, 1.5rem);
        background: linear-gradient(
          135deg,
          #f0fdf4 0%,
          #fafffe 40%,
          #f0fdf9 70%,
          #edfaf4 100%
        );
        background-size: 300% 300%;
        animation: mcBgDrift 12s ease-in-out infinite;
        color: var(--foreground, #111827);
        font-family: var(
          --font-sans,
          'Inter',
          -apple-system,
          BlinkMacSystemFont,
          sans-serif
        );
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp, 1rem);
        box-sizing: border-box;
        position: relative;
        overflow: hidden;
      }

      /* HEADER + QUICK FILL */
      .mc-header {
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
        padding: 2.5rem 1.5rem 2rem;
        min-height: 180px;
        justify-content: flex-end;
        border-radius: var(--boxel-border-radius-lg, 0.75rem);
        overflow: hidden;
        /* background applied via inline headerStyle getter */
        color: #ffffff;
        box-shadow:
          0 8px 32px rgba(0, 0, 0, 0.22),
          0 2px 8px rgba(0, 0, 0, 0.12);
      }
      .mc-title-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
        flex-wrap: wrap;
      }
      .mc-title {
        margin: 0;
        font-size: 1.75rem;
        font-weight: 800;
        letter-spacing: -0.02em;
        text-shadow: 0 2px 12px rgba(0, 0, 0, 0.35);
      }
      .mc-quickfill-btn {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.5rem 0.875rem;
        background: rgba(255, 255, 255, 0.18);
        color: inherit;
        border: 1px solid rgba(255, 255, 255, 0.3);
        border-radius: 999px;
        cursor: pointer;
        font-size: 0.8125rem;
        font-weight: 500;
        font-family: inherit;
        backdrop-filter: blur(8px);
        transition:
          background 0.18s ease,
          transform 0.18s ease;
      }
      .mc-quickfill-btn:hover {
        background: rgba(255, 255, 255, 0.28);
        transform: translateY(-1px);
      }
      .mc-quickfill {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .mc-quickfill-input {
        width: 100%;
        padding: 0.625rem 0.875rem;
        font-family: inherit;
        font-size: 0.875rem;
        background: rgba(255, 255, 255, 0.95);
        color: var(--foreground, #111111);
        border: none;
        border-radius: 0.5rem;
        resize: vertical;
        min-height: 2.5rem;
        box-sizing: border-box;
        outline: none;
      }
      .mc-quickfill-input:focus {
        box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.5);
      }
      .mc-quickfill-actions {
        display: flex;
        gap: 0.5rem;
        align-items: center;
      }
      .mc-quickfill-msg {
        margin: 0;
        font-size: 0.75rem;
        padding: 0.375rem 0.625rem;
        border-radius: 0.375rem;
      }
      .mc-quickfill-msg.success {
        background: rgba(48, 239, 157, 0.2);
        color: #d4ffe8;
        display: inline-flex;
        align-self: flex-start;
        align-items: flex-start;
        gap: 0.375rem;
      }
      .mc-quickfill-msg.success svg {
        flex-shrink: 0;
        margin-top: 1px;
        opacity: 0.85;
      }
      .mc-quickfill-msg.error {
        background: rgba(255, 80, 80, 0.25);
        color: #ffefef;
      }
      .mc-debug {
        margin-top: 0.5rem;
        font-size: 0.6875rem;
      }
      .mc-debug summary {
        cursor: pointer;
        opacity: 0.85;
      }
      .mc-debug pre {
        margin: 0.375rem 0 0;
        padding: 0.5rem 0.625rem;
        background: rgba(0, 0, 0, 0.35);
        color: #fff;
        border-radius: 0.375rem;
        white-space: pre-wrap;
        word-break: break-word;
        max-height: 200px;
        overflow: auto;
      }

      /* BUTTONS */
      .mc-btn {
        padding: 0.5rem 1rem;
        font-size: 0.8125rem;
        font-weight: 600;
        border-radius: 0.5rem;
        cursor: pointer;
        font-family: inherit;
        border: none;
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        transition:
          transform 0.18s ease,
          box-shadow 0.18s ease;
      }
      .mc-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }
      .mc-btn-primary {
        background: var(--card, #ffffff);
        color: var(--primary, #007272);
      }
      .mc-btn-primary:hover:not(:disabled) {
        transform: translateY(-1px);
        box-shadow: var(--shadow-sm, 0 2px 6px rgba(0, 0, 0, 0.15));
      }
      .mc-btn-ghost {
        background: transparent;
        color: inherit;
        border: 1px solid rgba(255, 255, 255, 0.4);
      }
      .mc-btn-ghost:hover {
        background: rgba(255, 255, 255, 0.12);
      }
      .mc-spinner {
        width: 12px;
        height: 12px;
        border: 2px solid currentColor;
        border-right-color: transparent;
        border-radius: 50%;
        animation: mcSpin 0.7s linear infinite;
      }
      @keyframes mcSpin {
        to {
          transform: rotate(360deg);
        }
      }

      /* ── Design tokens (bottom half) ── */
      .mc-wrapper {
        --mc-green: #059669;
        --mc-green-dark: #047857;
        --mc-green-bg: #ecfdf5;
        --mc-green-border: #6ee7b7;
        --mc-teal: #007272;
        --mc-teal-dark: #005858;
        --mc-surface: #ffffff;
        --mc-bg: #f8fafb;
        --mc-text: #0f172a;
        --mc-text-2: #1e293b;
        --mc-muted: #64748b;
        --mc-border: #e2e8f0;
        --mc-border-2: #cbd5e1;
        --mc-shadow:
          0 1px 3px rgba(0, 0, 0, 0.06), 0 1px 2px rgba(0, 0, 0, 0.04);
        --mc-shadow-md:
          0 4px 16px rgba(0, 0, 0, 0.08), 0 2px 4px rgba(0, 0, 0, 0.04);
      }

      /* CURRENCY NOTICE */
      .mc-currency-notice {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.375rem 0.75rem;
        background: rgba(255, 255, 255, 0.12);
        border: 1px solid rgba(255, 255, 255, 0.22);
        border-radius: 999px;
        font-size: 0.75rem;
        color: rgba(255, 255, 255, 0.82);
        backdrop-filter: blur(6px);
        align-self: flex-start;
      }
      .mc-currency-notice strong {
        color: #ffffff;
        font-weight: 700;
      }

      /* BODY LAYOUT */
      .mc-body {
        display: grid;
        grid-template-columns: minmax(220px, 1fr) 3fr;
        gap: 1.25rem;
        position: relative;
        z-index: 0;
      }
      /* Floating ambient blobs */
      .mc-wrapper::before {
        content: '';
        position: absolute;
        width: 420px;
        height: 420px;
        border-radius: 50%;
        background: radial-gradient(
          circle,
          rgba(5, 150, 105, 0.07) 0%,
          transparent 70%
        );
        top: 160px;
        right: -80px;
        animation: mcBlob1 9s ease-in-out infinite;
        pointer-events: none;
        z-index: 0;
      }
      .mc-wrapper::after {
        content: '';
        position: absolute;
        width: 300px;
        height: 300px;
        border-radius: 50%;
        background: radial-gradient(
          circle,
          rgba(16, 185, 129, 0.06) 0%,
          transparent 70%
        );
        bottom: 80px;
        left: -60px;
        animation: mcBlob2 11s ease-in-out infinite;
        pointer-events: none;
        z-index: 0;
      }
      @container (max-width: 720px) {
        .mc-body {
          grid-template-columns: 1fr;
        }
      }

      /* FORM */
      .mc-form {
        background: var(--mc-surface);
        border: 1px solid var(--mc-border);
        border-radius: 1rem;
        padding: 1.25rem;
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
        position: relative;
        z-index: 1;
      }
      .mc-form label {
        display: flex;
        align-items: center;
        gap: 0.375rem;
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--mc-muted);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        margin-top: 0.875rem;
        margin-bottom: 0.3rem;
      }
      .mc-form label::before {
        content: '';
        display: inline-block;
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: var(--mc-green);
        flex-shrink: 0;
      }
      .mc-form label:first-of-type {
        margin-top: 0;
      }
      .mc-form :deep(input) {
        width: 100%;
        padding: 0.5rem 0.75rem;
        background: var(--mc-green-bg);
        color: var(--mc-text);
        border: 1.5px solid var(--mc-green-border);
        border-radius: 0.625rem;
        font-size: 0.9375rem;
        font-variant-numeric: tabular-nums;
        transition:
          border-color 0.18s ease,
          background 0.18s ease,
          box-shadow 0.18s ease;
      }
      .mc-form :deep(input):focus {
        background: #ffffff;
        border-color: var(--mc-green);
        outline: none;
        box-shadow: 0 0 0 3px rgba(5, 150, 105, 0.15);
      }
      /* CURRENCY ROW (central currency picker) */
      .mc-currency-row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: 0.5rem;
        padding: 0.5rem 0.75rem 0.5rem 0.875rem;
        background: linear-gradient(
          135deg,
          var(--mc-teal) 0%,
          var(--mc-teal-dark) 100%
        );
        border-radius: 0.75rem;
        margin-bottom: 0.625rem;
        box-shadow: 0 2px 8px rgba(0, 114, 114, 0.22);
      }
      .mc-currency-label {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.07em;
        color: rgba(255, 255, 255, 0.88);
        white-space: nowrap;
        flex-shrink: 0;
      }
      /* BoxelSelect trigger inside currency row */
      .mc-currency-row :deep(.currency-field-edit) {
        background: rgba(255, 255, 255, 0.15);
        border: 1px solid rgba(255, 255, 255, 0.3);
        border-radius: 0.5rem;
        color: #ffffff;
        font-size: 0.8125rem;
        font-weight: 600;
        min-width: 100px;
      }
      .mc-currency-row :deep(.currency-field-edit:hover) {
        background: rgba(255, 255, 255, 0.22);
      }

      /* RESULTS */
      .mc-results {
        background: var(--mc-surface);
        border: 1px solid var(--mc-border);
        border-radius: 1rem;
        padding: 1.25rem;
        display: flex;
        flex-direction: column;
        gap: 1.25rem;
        box-shadow: var(--mc-shadow);
        position: relative;
        z-index: 1;
      }

      /* STAT CARDS */
      .mc-summary {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
        gap: 0.75rem;
      }
      .mc-stat {
        padding: 1rem 1rem 0.875rem;
        background: var(--mc-bg);
        border: 1px solid var(--mc-border);
        border-radius: 0.875rem;
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        border-left: 3px solid var(--mc-green-border);
        transition:
          transform 0.18s ease,
          box-shadow 0.18s ease;
      }
      .mc-stat:hover {
        transform: translateY(-2px);
        box-shadow: var(--mc-shadow-md);
      }
      .mc-stat-label {
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--mc-muted);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .mc-stat-value {
        font-size: 1.25rem;
        font-weight: 800;
        font-variant-numeric: tabular-nums;
        color: var(--mc-text);
        letter-spacing: -0.02em;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        min-width: 0;
      }
      .mc-stat.highlight {
        background: var(--mc-green);
        border-color: transparent;
        border-left-color: rgba(255, 255, 255, 0.3);
        color: #ffffff;
        box-shadow: 0 4px 20px rgba(0, 114, 114, 0.35);
      }
      .mc-stat.highlight .mc-stat-label {
        color: rgba(255, 255, 255, 0.75);
      }
      .mc-stat.highlight .mc-stat-value {
        color: #ffffff;
      }

      /* TABLE */
      .mc-table {
        border: 1px solid var(--mc-border);
        border-radius: 0.875rem;
        overflow: hidden;
        display: flex;
        flex-direction: column;
      }
      .mc-table-row {
        display: grid;
        grid-template-columns: 1.4fr 1fr 1fr;
        padding: 0.7rem 1rem;
        font-size: 0.875rem;
        align-items: center;
        font-variant-numeric: tabular-nums;
      }
      .mc-table-row + .mc-table-row {
        border-top: 1px solid var(--mc-border);
      }
      .mc-table-row span:not(:first-child) {
        text-align: right;
        font-weight: 500;
      }
      .mc-table-head {
        background: var(--mc-green-bg);
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--mc-green-dark);
      }
      .mc-table-row.featured {
        background: rgba(5, 150, 105, 0.06);
        font-weight: 600;
        color: var(--mc-text-2);
      }
      .mc-table-row.total {
        background: var(--mc-bg);
        font-weight: 800;
        border-top: 2px solid var(--mc-border-2);
        color: var(--mc-text);
      }

      /* CHARTS */
      .mc-charts {
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
      }
      .mc-tabs {
        display: inline-flex;
        padding: 4px;
        background: var(--mc-green-bg);
        border: 1px solid var(--mc-green-border);
        border-radius: 999px;
        gap: 2px;
        align-self: flex-start;
      }
      .mc-tab {
        padding: 0.375rem 1rem;
        background: transparent;
        color: var(--mc-muted);
        border: none;
        border-radius: 999px;
        cursor: pointer;
        font-size: 0.8125rem;
        font-weight: 600;
        font-family: inherit;
        transition:
          color 0.18s ease,
          background 0.18s ease,
          box-shadow 0.18s ease;
      }
      .mc-tab:hover {
        color: var(--mc-text);
      }
      .mc-tab.active {
        background: var(--mc-green);
        color: #ffffff;
        box-shadow: 0 2px 8px rgba(5, 150, 105, 0.35);
      }
      .mc-chart-panel {
        background: var(--mc-green-bg);
        border: 1px solid var(--mc-green-border);
        border-radius: 0.875rem;
        padding: 1rem;
        min-height: 320px;
        animation: mcFade 0.3s ease;
      }
      .mc-chart-panel.breakdown {
        display: grid;
        grid-template-columns: auto 1fr;
        gap: 1.75rem;
        align-items: center;
        padding: 1.5rem;
        min-height: 0;
      }
      .mc-legend {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        flex: 1;
      }
      .mc-legend-card {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 0.625rem 0.875rem;
        background: #ffffff;
        border: 1px solid var(--mc-border);
        border-radius: 0.75rem;
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
        transition:
          transform 0.15s ease,
          box-shadow 0.15s ease;
        cursor: default;
      }
      .mc-legend-card:hover {
        transform: translateX(5px);
        box-shadow: 0 3px 12px rgba(0, 0, 0, 0.1);
      }
      .mc-legend-bar {
        display: inline-block;
        width: 5px;
        height: 36px;
        border-radius: 99px;
        flex-shrink: 0;
      }
      .mc-legend-info {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 0.15rem;
      }
      .mc-legend-row {
        display: grid;
        grid-template-columns: 12px 1fr auto;
        align-items: center;
        gap: 0.5rem;
        padding: 0.5rem 0.625rem;
        border-radius: 0.625rem;
        background: #ffffff;
        border: 1px solid var(--mc-border);
        transition:
          transform 0.15s ease,
          box-shadow 0.15s ease;
        cursor: default;
      }
      .mc-legend-row:hover {
        transform: translateX(4px);
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
      }
      .mc-legend-swatch {
        width: 12px;
        height: 12px;
        border-radius: 3px;
        flex-shrink: 0;
      }
      .mc-legend-label {
        font-size: 0.8125rem;
        font-weight: 600;
        color: var(--mc-text-2);
      }
      .mc-legend-pct {
        font-size: 0.8125rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        color: var(--mc-muted);
      }
      .mc-legend-value {
        font-size: 0.75rem;
        color: var(--mc-muted);
        font-variant-numeric: tabular-nums;
      }
      .mc-legend-badge {
        font-size: 1rem;
        font-weight: 800;
        font-variant-numeric: tabular-nums;
        color: var(--mc-text);
        min-width: 2.75rem;
        text-align: right;
      }
      @keyframes mcFade {
        from {
          opacity: 0;
          transform: translateY(4px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      @keyframes mcBgDrift {
        0% {
          background-position: 0% 50%;
        }
        50% {
          background-position: 100% 50%;
        }
        100% {
          background-position: 0% 50%;
        }
      }
      @keyframes mcBlob1 {
        0%,
        100% {
          transform: translate(0, 0) scale(1);
        }
        33% {
          transform: translate(-20px, 30px) scale(1.08);
        }
        66% {
          transform: translate(15px, -15px) scale(0.94);
        }
      }
      @keyframes mcBlob2 {
        0%,
        100% {
          transform: translate(0, 0) scale(1);
        }
        40% {
          transform: translate(25px, -20px) scale(1.1);
        }
        70% {
          transform: translate(-10px, 20px) scale(0.92);
        }
      }
      @keyframes mcStatPulse {
        0%,
        100% {
          background-position: 0% 50%;
          box-shadow: 0 4px 20px rgba(0, 114, 114, 0.35);
        }
        50% {
          background-position: 100% 50%;
          box-shadow: 0 6px 28px rgba(0, 114, 114, 0.52);
        }
      }
      @keyframes mcFormGlow {
        0%,
        100% {
          box-shadow:
            0 1px 3px rgba(0, 0, 0, 0.06),
            0 0 0 0 rgba(5, 150, 105, 0);
        }
        50% {
          box-shadow:
            0 1px 3px rgba(0, 0, 0, 0.06),
            0 0 16px 2px rgba(5, 150, 105, 0.08);
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .mc-wrapper,
        .mc-wrapper::before,
        .mc-wrapper::after,
        .mc-chart-panel,
        .mc-stat,
        .mc-stat.highlight,
        .mc-form,
        .mc-quickfill-btn,
        .mc-btn-primary {
          animation: none;
          transition: none;
        }
      }
    </style>
  </template>
}
