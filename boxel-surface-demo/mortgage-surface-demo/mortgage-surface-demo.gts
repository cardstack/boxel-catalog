import NumberField from 'https://cardstack.com/base/number';
import CurrencyField from 'https://cardstack.com/base/currency';
import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
// @ts-ignore — esm.run module has no type defs
import { currencyCodeSymbolMapping } from 'https://esm.run/currency-code-symbol-map';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn, concat } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import ChevronDown from '@cardstack/boxel-icons/chevron-down';
import OneShotLlmRequestCommand from '@cardstack/boxel-host/commands/one-shot-llm-request';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import {
  Environment,
  Layout,
  Pane,
  Form,
  FormField,
  FormSection,
  NumberCell,
  Grid,
  Row,
  Cell,
  Run,
  Lift,
  type LiftKind,
} from '../../boxel-surface/src/index';
import { LineChart } from './components/line-chart';
import type { AmortPoint } from './components/line-chart';
import { DonutChart } from './components/donut-chart';
import type { DonutSectionData } from './components/donut-chart';
import { formatCurrency } from './components/utils';

export class MortgageSurfaceDemo extends CardDef {
  static displayName = 'Mortgage Calculator — Surfaces';
  static prefersWideFormat = true;

  @field currency = contains(CurrencyField);
  @field homePrice = contains(NumberField);
  @field downPaymentPercentage = contains(NumberField);
  @field loanTermYears = contains(NumberField);
  @field interestRatePercentage = contains(NumberField);
  @field taxPerMonth = contains(NumberField);
  @field insurancePerMonth = contains(NumberField);
  @field hoaFeesPerMonth = contains(NumberField);

  @field downPayment = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (this.homePrice ?? 0) * ((this.downPaymentPercentage ?? 0) / 100);
    },
  });
  @field loanAmount = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (this.homePrice ?? 0) - (this.downPayment ?? 0);
    },
  });
  @field numberOfPayments = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (this.loanTermYears ?? 0) * 12;
    },
  });
  @field monthlyInterestRate = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (this.interestRatePercentage ?? 0) / 100 / 12;
    },
  });
  @field monthlyMortgagePayment = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      const r = this.monthlyInterestRate ?? 0;
      const n = this.numberOfPayments ?? 0;
      const L = this.loanAmount ?? 0;
      if (!L || !n) return 0;
      if (r === 0) return L / n;
      return L * ((r * Math.pow(1 + r, n)) / (Math.pow(1 + r, n) - 1));
    },
  });
  @field monthlyTotal = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (
        (this.monthlyMortgagePayment ?? 0) +
        (this.taxPerMonth ?? 0) +
        (this.insurancePerMonth ?? 0) +
        (this.hoaFeesPerMonth ?? 0)
      );
    },
  });
  @field lifetimeMortgagePayment = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (this.monthlyMortgagePayment ?? 0) * (this.numberOfPayments ?? 0);
    },
  });
  @field lifetimeInterest = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (this.lifetimeMortgagePayment ?? 0) - (this.loanAmount ?? 0);
    },
  });
  @field lifetimeTaxes = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (this.taxPerMonth ?? 0) * (this.numberOfPayments ?? 0);
    },
  });
  @field lifetimeInsurance = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (this.insurancePerMonth ?? 0) * (this.numberOfPayments ?? 0);
    },
  });
  @field lifetimeHoaFees = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (this.hoaFeesPerMonth ?? 0) * (this.numberOfPayments ?? 0);
    },
  });
  @field lifetimeTotal = contains(NumberField, {
    computeVia(this: MortgageSurfaceDemo) {
      return (
        (this.lifetimeMortgagePayment ?? 0) +
        (this.lifetimeTaxes ?? 0) +
        (this.lifetimeInsurance ?? 0) +
        (this.lifetimeHoaFees ?? 0)
      );
    },
  });
}

type CategoryKey = 'pi' | 'tax' | 'insurance' | 'hoa';
type StatKey =
  | 'loanAmount'
  | 'downPayment'
  | 'monthlyPayment'
  | 'totalInterest';

const FENCED_JSON_RE = new RegExp('```(?:json)?\\s*([\\s\\S]*?)```');

class MortgageSurfaceDemoIsolated extends Component<
  typeof MortgageSurfaceDemo
> {
  @tracked activeTab: 'breakdown' | 'timeline' = 'timeline';

  @tracked currencyLiftKind: LiftKind | null = null;

  // Cross-highlight state for the monthly breakdown. The three views
  // (Grid row, DonutChart segment, legend row) all call setHover with
  // the same CategoryKey, and each binds data-active to drive its own
  // CSS. Mirrors the "same-cell-three-hosts" coordination pattern —
  // lifted tracked state on the parent, multiple views subscribe.
  @tracked hoveredCategory: CategoryKey | null = null;

  // Stat-card preview lift — one Lift instance, anchor switches with
  // `hoveredStat`. Hover-driven, so it never traps focus.
  @tracked hoveredStat: StatKey | null = null;
  @tracked chartToolsOpen = false; // attached + tools
  @tracked scenarioOpen = false; // plane + scrim + modal
  @tracked scenarioRate = 0;
  @tracked scenarioTerm = 0;

  // AI Quick Fill — extracts mortgage data from a pasted listing.
  @tracked quickFillText = '';
  @tracked quickFillStatus: 'idle' | 'loading' | 'success' | 'error' = 'idle';
  @tracked quickFillError = '';
  @tracked lastSnapshot: Record<string, number> | null = null;
  @tracked quickFillOpen = true;
  @tracked debugRaw = '';

  get headerStyle() {
    return htmlSafe(
      'background: linear-gradient(135deg, rgba(255,200,60,0.18) 0%, rgba(60,120,40,0.32) 35%, rgba(8,38,18,0.72) 70%, rgba(3,18,8,0.90) 100%), url(https://images.pexels.com/photos/31737842/pexels-photo-31737842.jpeg?auto=compress&cs=tinysrgb&w=1400) center / cover no-repeat',
    );
  }

  @action updateQuickFillText(evt: Event) {
    this.quickFillText = (evt.target as HTMLTextAreaElement).value;
  }

  @action toggleQuickFill() {
    this.quickFillOpen = !this.quickFillOpen;
  }

  @action async runQuickFill() {
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
      const result = await command.execute({
        systemPrompt,
        userPrompt: text,
        llmModel: 'anthropic/claude-haiku-4.5',
      });
      const raw =
        (result as any)?.output ?? (result as any)?.attributes?.output ?? '';
      this.debugRaw = String(raw).slice(0, 800);
      const parsed = this.parseLlmJson(String(raw));
      if (!parsed) {
        throw new Error(
          `Couldn't parse JSON from the response. Raw output shown below.`,
        );
      }
      this.lastSnapshot = this.snapshot();
      this.applyValues(parsed);
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
      this.quickFillStatus = 'error';
      this.quickFillError = err?.message ?? 'Unknown error';
    }
  }

  @action undoQuickFill() {
    if (!this.lastSnapshot) return;
    this.applyValues(this.lastSnapshot);
    this.lastSnapshot = null;
    this.quickFillStatus = 'idle';
  }

  parseLlmJson(raw: string): Record<string, number> | null {
    if (!raw) return null;
    let text = raw.trim();
    const fenced = text.match(FENCED_JSON_RE);
    if (fenced) text = fenced[1].trim();
    try {
      return this.coerce(JSON.parse(text));
    } catch {
      const start = text.indexOf('{');
      const end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          return this.coerce(JSON.parse(text.slice(start, end + 1)));
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

  get currencySymbol(): string {
    return (currencyCodeSymbolMapping as Record<string, string>)[
      this.currencyCode
    ];
  }

  @action openCurrencyLift() {
    this.currencyLiftKind = 'edit';
  }
  @action dismissCurrencyLift() {
    this.currencyLiftKind = null;
  }
  @action escalateCurrencyLift(next: LiftKind) {
    this.currencyLiftKind = next;
  }

  currencyEscalation: LiftKind[] = ['details', 'edit'];

  // Stat-card hover preview — mouseenter sets the key, mouseleave clears.
  @action openStatPreview(key: StatKey) {
    this.hoveredStat = key;
  }
  @action closeStatPreview() {
    this.hoveredStat = null;
  }

  isStatActive = (k: StatKey): boolean => this.hoveredStat === k;

  get statAnchorSelector(): string {
    return `[data-lift-anchor=mcs-stat-${this.hoveredStat}]`;
  }

  get downPaymentRatio(): number {
    return this.args.model.downPaymentPercentage ?? 0;
  }

  get interestShareOfTotalMortgage(): number {
    const total = this.args.model.lifetimeMortgagePayment ?? 0;
    if (!total) return 0;
    return Math.round(((this.args.model.lifetimeInterest ?? 0) / total) * 100);
  }

  // Chart tools menu (tools lift).
  @action openChartTools() {
    this.chartToolsOpen = true;
  }
  @action closeChartTools() {
    this.chartToolsOpen = false;
  }
  @action exportCsv() {
    const cc = this.currencyCode;
    const rows: (string | number)[][] = [
      ['Category', 'Monthly', 'Lifetime'],
      [
        'Mortgage (P&I)',
        this.args.model.monthlyMortgagePayment ?? 0,
        this.args.model.lifetimeMortgagePayment ?? 0,
      ],
      [
        'Property tax',
        this.args.model.taxPerMonth ?? 0,
        this.args.model.lifetimeTaxes ?? 0,
      ],
      [
        'Home insurance',
        this.args.model.insurancePerMonth ?? 0,
        this.args.model.lifetimeInsurance ?? 0,
      ],
      [
        'HOA fees',
        this.args.model.hoaFeesPerMonth ?? 0,
        this.args.model.lifetimeHoaFees ?? 0,
      ],
      [
        'Total',
        this.args.model.monthlyTotal ?? 0,
        this.args.model.lifetimeTotal ?? 0,
      ],
    ];
    const escape = (cell: string | number): string => {
      const s = String(cell);
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const csv = rows.map((r) => r.map(escape).join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `mortgage-breakdown-${cc}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    this.closeChartTools();
  }
  @action printSummary() {
    // Triggers the browser's native print dialog; users can save as PDF.
    // The whole document prints — for a per-card print sheet you'd
    // render a print-only stylesheet inside this component.
    this.closeChartTools();
    window.print();
  }

  // Scenario modal (plane + scrim).
  @action openScenario() {
    this.scenarioRate = this.args.model.interestRatePercentage ?? 0;
    this.scenarioTerm = this.args.model.loanTermYears ?? 0;
    this.scenarioOpen = true;
  }
  @action closeScenario() {
    this.scenarioOpen = false;
  }
  @action setScenarioRate(val: string) {
    const v = parseFloat(val);
    if (Number.isFinite(v)) this.scenarioRate = v;
  }
  @action setScenarioTerm(val: string) {
    const v = parseFloat(val);
    if (Number.isFinite(v)) this.scenarioTerm = v;
  }
  @action applyScenario() {
    this.args.model.interestRatePercentage = this.scenarioRate;
    this.args.model.loanTermYears = this.scenarioTerm;
    this.scenarioOpen = false;
  }

  get scenarioMonthly(): number {
    const L = this.args.model.loanAmount ?? 0;
    const n = this.scenarioTerm * 12;
    const r = this.scenarioRate / 100 / 12;
    if (!L || !n) return 0;
    if (r === 0) return L / n;
    return L * ((r * Math.pow(1 + r, n)) / (Math.pow(1 + r, n) - 1));
  }

  get amortization(): AmortPoint[] {
    const { model } = this.args;
    const years = model.loanTermYears ?? 0;
    const monthlyPayment = model.monthlyMortgagePayment ?? 0;
    const monthlyRate = model.monthlyInterestRate ?? 0;
    let balance = model.loanAmount ?? 0;
    const out: AmortPoint[] = [
      { year: 0, principalPaid: 0, interestPaid: 0, totalPaid: 0, balance },
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

  get chartData(): (DonutSectionData & { key: CategoryKey })[] {
    const { model } = this.args;
    const total = model.monthlyTotal || 1;
    return [
      {
        key: 'pi',
        value: model.monthlyMortgagePayment,
        color: 'var(--mc-green, #059669)',
        label: 'Principal & Interest',
        percent: Math.round(
          ((model.monthlyMortgagePayment ?? 0) / total) * 100,
        ),
      },
      {
        key: 'tax',
        value: model.taxPerMonth,
        color: 'var(--chart-2, #589BFF)',
        label: 'Property Taxes',
        percent: Math.round(((model.taxPerMonth ?? 0) / total) * 100),
      },
      {
        key: 'insurance',
        value: model.insurancePerMonth,
        color: 'var(--chart-5, #ef4444)',
        label: 'Home Insurance',
        percent: Math.round(((model.insurancePerMonth ?? 0) / total) * 100),
      },
      {
        key: 'hoa',
        value: model.hoaFeesPerMonth,
        color: 'var(--chart-4, #f59e0b)',
        label: 'HOA Fees',
        percent: Math.round(((model.hoaFeesPerMonth ?? 0) / total) * 100),
      },
    ];
  }

  @action setTab(tab: 'breakdown' | 'timeline') {
    this.activeTab = tab;
  }

  // Cross-highlight helper — three views read the same hovered state.
  isActive = (k: CategoryKey): boolean => this.hoveredCategory === k;

  @action setHoverCategory(k: string | null) {
    this.hoveredCategory = k as CategoryKey | null;
  }

  @action setHomePrice(val: string) {
    const n = parseFloat(val);
    if (Number.isFinite(n)) this.args.model.homePrice = n;
  }

  @action setDownPaymentPercentage(val: string) {
    const n = parseFloat(val);
    if (Number.isFinite(n)) this.args.model.downPaymentPercentage = n;
  }

  @action setLoanTermYears(val: string) {
    const n = parseFloat(val);
    if (Number.isFinite(n)) this.args.model.loanTermYears = n;
  }

  @action setInterestRatePercentage(val: string) {
    const n = parseFloat(val);
    if (Number.isFinite(n)) this.args.model.interestRatePercentage = n;
  }

  @action setTaxPerMonth(val: string) {
    const n = parseFloat(val);
    if (Number.isFinite(n)) this.args.model.taxPerMonth = n;
  }

  @action setInsurancePerMonth(val: string) {
    const n = parseFloat(val);
    if (Number.isFinite(n)) this.args.model.insurancePerMonth = n;
  }

  @action setHoaFeesPerMonth(val: string) {
    const n = parseFloat(val);
    if (Number.isFinite(n)) this.args.model.hoaFeesPerMonth = n;
  }

  <template>
    <div class='mcs-wrapper'>
      <header class='mcs-header' style={{this.headerStyle}}>
        <div class='mcs-title-row'>
          <h1 class='mcs-title'>Mortgage Calculator</h1>
          <button
            type='button'
            class='mcs-quickfill-btn'
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
          <div class='mcs-quickfill'>
            <textarea
              class='mcs-quickfill-input'
              placeholder='Paste a Zillow URL or listing description (e.g. "3-bed, 2-bath in Austin TX, $625k, $4,200 annual taxes")'
              value={{this.quickFillText}}
              {{on 'input' this.updateQuickFillText}}
              rows='2'
            ></textarea>
            <div class='mcs-quickfill-actions'>
              <button
                type='button'
                class='mcs-qf-btn mcs-qf-btn--primary'
                disabled={{eq this.quickFillStatus 'loading'}}
                {{on 'click' this.runQuickFill}}
              >
                {{#if (eq this.quickFillStatus 'loading')}}
                  <span class='mcs-spinner'></span>
                  Extracting…
                {{else}}
                  Fill from listing
                {{/if}}
              </button>
              {{#if this.lastSnapshot}}
                <button
                  type='button'
                  class='mcs-qf-btn mcs-qf-btn--ghost'
                  {{on 'click' this.undoQuickFill}}
                >Undo</button>
              {{/if}}
            </div>
            {{#if (eq this.quickFillStatus 'success')}}
              <p class='mcs-quickfill-msg mcs-quickfill-msg--success'>
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
              <div class='mcs-quickfill-msg mcs-quickfill-msg--error'>
                <strong>Couldn't fill.</strong>
                {{this.quickFillError}}
                {{#if this.debugRaw}}
                  <details class='mcs-debug'>
                    <summary>Show raw response</summary>
                    <pre>{{this.debugRaw}}</pre>
                  </details>
                {{/if}}
              </div>
            {{/if}}
          </div>
        {{/if}}
        <div class='mcs-currency-notice'>
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

      <Environment @space='mcs-demo' @posture='use'>
        <Layout @space='mcs-dashboard' @preset='bare' class='mcs-layout'>
          <Pane @coord='sidebar' class='mcs-pane'>
            <Form
              @mode='edit'
              @layout='horizontal'
              @density='compact'
              class='mcs-form'
            >
              <FormSection @heading='Currency'>
                <Cell
                  class='mcs-currency-trigger'
                  data-lift-anchor='mcs-currency'
                  data-active={{if this.currencyLiftKind 'true' 'false'}}
                  {{on 'click' this.openCurrencyLift}}
                >
                  <Run @key='symbol' class='mcs-currency-symbol'>
                    {{this.currencySymbol}}
                  </Run>
                  <Run @key='code' class='mcs-currency-code'>
                    {{this.currencyCode}}
                  </Run>
                  <ChevronDown
                    class='mcs-currency-caret'
                    width='16'
                    height='16'
                    aria-hidden='true'
                  />
                </Cell>
              </FormSection>

              <FormSection @heading='Property'>
                <FormField @label='Home price'>
                  <NumberCell
                    @value={{@model.homePrice}}
                    @min={{0}}
                    @step={{1000}}
                    @onInput={{this.setHomePrice}}
                  />
                </FormField>
                <FormField @label='Down payment %'>
                  <NumberCell
                    @value={{@model.downPaymentPercentage}}
                    @min={{0}}
                    @max={{100}}
                    @step={{0.5}}
                    @onInput={{this.setDownPaymentPercentage}}
                  />
                </FormField>
              </FormSection>

              <FormSection @heading='Loan'>
                <FormField @label='Term (years)'>
                  <NumberCell
                    @value={{@model.loanTermYears}}
                    @min={{1}}
                    @max={{50}}
                    @step={{1}}
                    @onInput={{this.setLoanTermYears}}
                  />
                </FormField>
                <FormField @label='Interest rate %'>
                  <NumberCell
                    @value={{@model.interestRatePercentage}}
                    @min={{0}}
                    @max={{30}}
                    @step={{0.01}}
                    @onInput={{this.setInterestRatePercentage}}
                  />
                </FormField>
              </FormSection>

              <FormSection @heading='Monthly costs'>
                <FormField @label='Property tax'>
                  <NumberCell
                    @value={{@model.taxPerMonth}}
                    @min={{0}}
                    @step={{10}}
                    @onInput={{this.setTaxPerMonth}}
                  />
                </FormField>
                <FormField @label='Home insurance'>
                  <NumberCell
                    @value={{@model.insurancePerMonth}}
                    @min={{0}}
                    @step={{10}}
                    @onInput={{this.setInsurancePerMonth}}
                  />
                </FormField>
                <FormField @label='HOA fees'>
                  <NumberCell
                    @value={{@model.hoaFeesPerMonth}}
                    @min={{0}}
                    @step={{10}}
                    @onInput={{this.setHoaFeesPerMonth}}
                  />
                </FormField>
              </FormSection>
            </Form>
          </Pane>

          <Pane @coord='body' class='mcs-main'>
            <div class='mcs-summary'>
              <div
                class='mcs-stat'
                data-lift-anchor='mcs-stat-loanAmount'
                data-active={{if
                  (this.isStatActive 'loanAmount')
                  'true'
                  'false'
                }}
                {{on 'mouseenter' (fn this.openStatPreview 'loanAmount')}}
                {{on 'mouseleave' this.closeStatPreview}}
              >
                <span class='mcs-stat-label'>Loan amount</span>
                <span class='mcs-stat-value'>{{formatCurrency
                    @model.loanAmount
                    this.currencyCode
                  }}</span>
              </div>
              <div
                class='mcs-stat'
                data-lift-anchor='mcs-stat-downPayment'
                data-active={{if
                  (this.isStatActive 'downPayment')
                  'true'
                  'false'
                }}
                {{on 'mouseenter' (fn this.openStatPreview 'downPayment')}}
                {{on 'mouseleave' this.closeStatPreview}}
              >
                <span class='mcs-stat-label'>Down payment</span>
                <span class='mcs-stat-value'>{{formatCurrency
                    @model.downPayment
                    this.currencyCode
                  }}</span>
              </div>
              <div
                class='mcs-stat mcs-stat--highlight'
                data-lift-anchor='mcs-stat-monthlyPayment'
                data-active={{if
                  (this.isStatActive 'monthlyPayment')
                  'true'
                  'false'
                }}
                {{on 'mouseenter' (fn this.openStatPreview 'monthlyPayment')}}
                {{on 'mouseleave' this.closeStatPreview}}
              >
                <span class='mcs-stat-label'>Monthly payment</span>
                <span class='mcs-stat-value'>{{formatCurrency
                    @model.monthlyTotal
                    this.currencyCode
                  }}</span>
              </div>
              <div
                class='mcs-stat'
                data-lift-anchor='mcs-stat-totalInterest'
                data-active={{if
                  (this.isStatActive 'totalInterest')
                  'true'
                  'false'
                }}
                {{on 'mouseenter' (fn this.openStatPreview 'totalInterest')}}
                {{on 'mouseleave' this.closeStatPreview}}
              >
                <span class='mcs-stat-label'>Total interest</span>
                <span class='mcs-stat-value'>{{formatCurrency
                    @model.lifetimeInterest
                    this.currencyCode
                  }}</span>
              </div>
            </div>

            <Grid class='mcs-table' role='table'>
              <div class='mcs-table-row mcs-table-head' role='row'>
                <span role='columnheader'></span>
                <span role='columnheader'>Monthly</span>
                <span role='columnheader'>Lifetime</span>
              </div>
              <Row
                @space='mortgage-pi'
                class='mcs-table-row mcs-table-row--featured'
                role='row'
                data-active={{if (this.isActive 'pi') 'true' 'false'}}
                {{on 'mouseenter' (fn this.setHoverCategory 'pi')}}
                {{on 'mouseleave' (fn this.setHoverCategory null)}}
              >
                <Cell @key='label' class='mcs-table-cell' role='cell'><Run
                    @key='label'
                  >Mortgage (P&amp;I)</Run></Cell>
                <Cell @key='monthly' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.monthlyMortgagePayment
                      this.currencyCode
                    }}</Run></Cell>
                <Cell @key='lifetime' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.lifetimeMortgagePayment
                      this.currencyCode
                    }}</Run></Cell>
              </Row>
              <Row
                @space='mortgage-tax'
                class='mcs-table-row'
                role='row'
                data-active={{if (this.isActive 'tax') 'true' 'false'}}
                {{on 'mouseenter' (fn this.setHoverCategory 'tax')}}
                {{on 'mouseleave' (fn this.setHoverCategory null)}}
              >
                <Cell @key='label' class='mcs-table-cell' role='cell'><Run
                    @key='label'
                  >Property tax</Run></Cell>
                <Cell @key='monthly' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.taxPerMonth
                      this.currencyCode
                    }}</Run></Cell>
                <Cell @key='lifetime' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.lifetimeTaxes
                      this.currencyCode
                    }}</Run></Cell>
              </Row>
              <Row
                @space='mortgage-insurance'
                class='mcs-table-row'
                role='row'
                data-active={{if (this.isActive 'insurance') 'true' 'false'}}
                {{on 'mouseenter' (fn this.setHoverCategory 'insurance')}}
                {{on 'mouseleave' (fn this.setHoverCategory null)}}
              >
                <Cell @key='label' class='mcs-table-cell' role='cell'><Run
                    @key='label'
                  >Home insurance</Run></Cell>
                <Cell @key='monthly' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.insurancePerMonth
                      this.currencyCode
                    }}</Run></Cell>
                <Cell @key='lifetime' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.lifetimeInsurance
                      this.currencyCode
                    }}</Run></Cell>
              </Row>
              <Row
                @space='mortgage-hoa'
                class='mcs-table-row'
                role='row'
                data-active={{if (this.isActive 'hoa') 'true' 'false'}}
                {{on 'mouseenter' (fn this.setHoverCategory 'hoa')}}
                {{on 'mouseleave' (fn this.setHoverCategory null)}}
              >
                <Cell @key='label' class='mcs-table-cell' role='cell'><Run
                    @key='label'
                  >HOA fees</Run></Cell>
                <Cell @key='monthly' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.hoaFeesPerMonth
                      this.currencyCode
                    }}</Run></Cell>
                <Cell @key='lifetime' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.lifetimeHoaFees
                      this.currencyCode
                    }}</Run></Cell>
              </Row>
              <Row
                @space='mortgage-total'
                class='mcs-table-row mcs-table-row--total'
                role='row'
              >
                <Cell @key='label' class='mcs-table-cell' role='cell'><Run
                    @key='label'
                  >Total out-of-pocket</Run></Cell>
                <Cell @key='monthly' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.monthlyTotal
                      this.currencyCode
                    }}</Run></Cell>
                <Cell @key='lifetime' class='mcs-table-cell' role='cell'><Run
                    @key='value'
                  >{{formatCurrency
                      @model.lifetimeTotal
                      this.currencyCode
                    }}</Run></Cell>
              </Row>
            </Grid>

            <div class='mcs-charts'>
              <div class='mcs-charts-header'>
                <div class='mcs-tabs' role='tablist'>
                  <button
                    type='button'
                    role='tab'
                    class={{if
                      (eq this.activeTab 'timeline')
                      'mcs-tab mcs-tab--active'
                      'mcs-tab'
                    }}
                    {{on 'click' (fn this.setTab 'timeline')}}
                  >Pay-off over time</button>
                  <button
                    type='button'
                    role='tab'
                    class={{if
                      (eq this.activeTab 'breakdown')
                      'mcs-tab mcs-tab--active'
                      'mcs-tab'
                    }}
                    {{on 'click' (fn this.setTab 'breakdown')}}
                  >Monthly breakdown</button>
                </div>
                <div class='mcs-charts-actions'>
                  <button
                    type='button'
                    class='mcs-icon-btn'
                    data-lift-anchor='mcs-chart-tools'
                    aria-label='Chart tools'
                    {{on 'click' this.openChartTools}}
                  >⋯</button>
                  <button
                    type='button'
                    class='mcs-action-btn'
                    data-lift-anchor='mcs-scenario'
                    {{on 'click' this.openScenario}}
                  >Run scenario…</button>
                </div>
              </div>

              {{#if (eq this.activeTab 'timeline')}}
                <div class='mcs-chart-panel'>
                  <LineChart
                    @data={{this.amortization}}
                    @height={{300}}
                    @currencyCode={{this.currencyCode}}
                  />
                </div>
              {{else}}
                <div class='mcs-chart-panel mcs-chart-panel--breakdown'>
                  <DonutChart
                    @data={{this.chartData}}
                    @size={{180}}
                    @currencyCode={{this.currencyCode}}
                    @onHover={{this.setHoverCategory}}
                  />
                  <div class='mcs-legend'>
                    {{#each this.chartData as |item|}}
                      <div
                        class='mcs-legend-row'
                        data-category={{item.key}}
                        data-active={{if
                          (this.isActive item.key)
                          'true'
                          'false'
                        }}
                        {{on 'mouseenter' (fn this.setHoverCategory item.key)}}
                        {{on 'mouseleave' (fn this.setHoverCategory null)}}
                      >
                        <span
                          class='mcs-legend-swatch'
                          style={{htmlSafe (concat 'background:' item.color)}}
                        ></span>
                        <span class='mcs-legend-label'>{{item.label}}</span>
                        <span class='mcs-legend-pct'>{{item.percent}}%</span>
                      </div>
                    {{/each}}
                  </div>
                </div>
              {{/if}}
            </div>
          </Pane>

        </Layout>

        {{#if this.currencyLiftKind}}
          <Lift
            @anchor='[data-lift-anchor=mcs-currency]'
            @open={{true}}
            @kind={{this.currencyLiftKind}}
            @canEscalateTo={{this.currencyEscalation}}
            @onEscalate={{this.escalateCurrencyLift}}
            @onDismiss={{this.dismissCurrencyLift}}
            as |kind|
          >
            {{#if (eq kind 'details')}}
              <div class='mcs-lift-body'>
                <div class='mcs-lift-title'>Currency</div>
                <div class='mcs-lift-row'>
                  <span>Code</span>
                  <strong>{{this.currencyCode}}</strong>
                </div>
                <div class='mcs-lift-row'>
                  <span>Symbol</span>
                  <strong>{{this.currencySymbol}}</strong>
                </div>
                <div class='mcs-lift-hint'>Click ✎ to change</div>
              </div>
            {{else if (eq kind 'edit')}}
              <div class='mcs-lift-shell'>
                <div class='mcs-lift-body mcs-lift-body--edit'>
                  <@fields.currency @format='edit' />
                </div>
              </div>
            {{/if}}
          </Lift>
        {{/if}}

        {{#if this.hoveredStat}}
          <Lift
            @anchor={{this.statAnchorSelector}}
            @open={{true}}
            @kind='preview'
            @placementMode='attached'
            @placement='bottom-start'
            @size='auto'
            @backdrop='none'
            @elevation='raised'
            @autoFocus={{false}}
            @onDismiss={{this.closeStatPreview}}
          >
            <div
              class='mcs-stat-preview'
              {{on 'mouseenter' (fn this.openStatPreview this.hoveredStat)}}
              {{on 'mouseleave' this.closeStatPreview}}
            >
              {{#if (eq this.hoveredStat 'loanAmount')}}
                <div class='mcs-stat-preview__head'>
                  <span class='mcs-stat-preview__eyebrow'>Loan amount</span>
                  <strong class='mcs-stat-preview__value'>{{formatCurrency
                      @model.loanAmount
                      this.currencyCode
                    }}</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>Home price</span>
                  <strong>{{formatCurrency
                      @model.homePrice
                      this.currencyCode
                    }}</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>− Down payment</span>
                  <strong>{{formatCurrency
                      @model.downPayment
                      this.currencyCode
                    }}</strong>
                </div>
              {{else if (eq this.hoveredStat 'downPayment')}}
                <div class='mcs-stat-preview__head'>
                  <span class='mcs-stat-preview__eyebrow'>Down payment</span>
                  <strong class='mcs-stat-preview__value'>{{formatCurrency
                      @model.downPayment
                      this.currencyCode
                    }}</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>Share of home price</span>
                  <strong>{{this.downPaymentRatio}}%</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>Home price</span>
                  <strong>{{formatCurrency
                      @model.homePrice
                      this.currencyCode
                    }}</strong>
                </div>
              {{else if (eq this.hoveredStat 'monthlyPayment')}}
                <div class='mcs-stat-preview__head'>
                  <span class='mcs-stat-preview__eyebrow'>Monthly payment</span>
                  <strong class='mcs-stat-preview__value'>{{formatCurrency
                      @model.monthlyTotal
                      this.currencyCode
                    }}</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>Principal &amp; Interest</span>
                  <strong>{{formatCurrency
                      @model.monthlyMortgagePayment
                      this.currencyCode
                    }}</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>Property tax</span>
                  <strong>{{formatCurrency
                      @model.taxPerMonth
                      this.currencyCode
                    }}</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>Home insurance</span>
                  <strong>{{formatCurrency
                      @model.insurancePerMonth
                      this.currencyCode
                    }}</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>HOA</span>
                  <strong>{{formatCurrency
                      @model.hoaFeesPerMonth
                      this.currencyCode
                    }}</strong>
                </div>
              {{else if (eq this.hoveredStat 'totalInterest')}}
                <div class='mcs-stat-preview__head'>
                  <span class='mcs-stat-preview__eyebrow'>Total interest</span>
                  <strong class='mcs-stat-preview__value'>{{formatCurrency
                      @model.lifetimeInterest
                      this.currencyCode
                    }}</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>Share of mortgage paid</span>
                  <strong>{{this.interestShareOfTotalMortgage}}%</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>Lifetime mortgage</span>
                  <strong>{{formatCurrency
                      @model.lifetimeMortgagePayment
                      this.currencyCode
                    }}</strong>
                </div>
                <div class='mcs-stat-preview__row'>
                  <span>Loan amount</span>
                  <strong>{{formatCurrency
                      @model.loanAmount
                      this.currencyCode
                    }}</strong>
                </div>
              {{/if}}
            </div>
          </Lift>
        {{/if}}

        {{#if this.chartToolsOpen}}
          <Lift
            @anchor='[data-lift-anchor=mcs-chart-tools]'
            @open={{true}}
            @kind='tools'
            @placementMode='attached'
            @placement='bottom-end'
            @size='compact'
            @backdrop='none'
            @elevation='flat'
            @onDismiss={{this.closeChartTools}}
          >
            <menu class='mcs-tools-menu'>
              <button type='button' {{on 'click' this.exportCsv}}>
                Export CSV
              </button>
              <button type='button' {{on 'click' this.printSummary}}>
                Print summary
              </button>
            </menu>
          </Lift>
        {{/if}}

        {{#if this.scenarioOpen}}
          <Lift
            @anchor='[data-lift-anchor=mcs-scenario]'
            @open={{true}}
            @kind='edit'
            @placementMode='plane'
            @size='spacious'
            @backdrop='scrim'
            @elevation='modal'
            @keyboardModel='compose'
            @onDismiss={{this.closeScenario}}
          >
            <div class='mcs-lift-shell'>
              <div class='mcs-scenario'>
                <header class='mcs-scenario__header'>
                  <h3>Run scenario</h3>
                  <p>Try a different rate or term without committing.</p>
                </header>
                <Form
                  @mode='edit'
                  @layout='vertical'
                  @columns={{2}}
                  class='mcs-scenario__form'
                >
                  <FormField @label='Interest rate (%)'>
                    <NumberCell
                      @value={{this.scenarioRate}}
                      @step={{0.01}}
                      @onInput={{this.setScenarioRate}}
                    />
                  </FormField>
                  <FormField @label='Term (years)'>
                    <NumberCell
                      @value={{this.scenarioTerm}}
                      @step={{1}}
                      @min={{1}}
                      @max={{50}}
                      @onInput={{this.setScenarioTerm}}
                    />
                  </FormField>
                </Form>
                <div class='mcs-scenario__compare'>
                  <div>
                    <span>Current P&amp;I</span>
                    <strong>{{formatCurrency
                        @model.monthlyMortgagePayment
                        this.currencyCode
                      }}</strong>
                  </div>
                  <div>
                    <span>Scenario P&amp;I</span>
                    <strong>{{formatCurrency
                        this.scenarioMonthly
                        this.currencyCode
                      }}</strong>
                  </div>
                </div>
                <footer class='mcs-scenario__footer'>
                  <button
                    type='button'
                    class='mcs-btn'
                    {{on 'click' this.closeScenario}}
                  >Cancel</button>
                  <button
                    type='button'
                    class='mcs-btn mcs-btn--primary'
                    {{on 'click' this.applyScenario}}
                  >Apply</button>
                </footer>
              </div>
            </div>
          </Lift>
        {{/if}}
      </Environment>
    </div>

    <style scoped>
      .mcs-lift-shell {
        display: contents;

        --mc-green-50: #f0fdf4;
        --mc-green-100: #dcfce7;
        --mc-green-200: #bbf7d0;
        --mc-green-300: #86efac;
        --mc-green-400: #4ade80;
        --mc-green-500: #16a34a;
        --mc-green-600: #15803d;
        --mc-green-700: #166534;
        --mc-green-800: #14532d;
        --mc-green-900: #0a2e17;

        --mc-green: var(--mc-green-600);
        --mc-green-dark: var(--mc-green-700);
        --mc-green-bg: var(--mc-green-50);
        --mc-green-border: var(--mc-green-200);
        --mc-green-ring: rgba(22, 163, 74, 0.18);

        --mc-surface: #ffffff;
        --mc-bg: #f6faf7;
        --mc-text: #0f1c14;
        --mc-text-2: #1f2e25;
        --mc-muted: #5e6b62;
        --mc-border: #e3ebe5;
        --mc-border-2: #cdd9d0;

        --mc-shadow-sm: 0 1px 2px rgba(15, 28, 20, 0.05);
        --mc-shadow-md:
          0 4px 16px rgba(15, 28, 20, 0.08), 0 2px 4px rgba(15, 28, 20, 0.04);
        --mc-shadow-lg:
          0 20px 48px rgba(21, 128, 61, 0.22), 0 4px 12px rgba(15, 28, 20, 0.08);
        --mc-radius-sm: 8px;
        --mc-radius-md: 12px;
        --mc-radius-lg: 16px;
      }

      /* ── AI Quick Fill header ── */
      .mcs-header {
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
        padding: 2.5rem 1.5rem 2rem;
        min-height: 180px;
        justify-content: flex-end;
        border-radius: 12px;
        overflow: hidden;
        margin-bottom: 20px;
        color: #fff;
        box-shadow:
          0 8px 32px rgba(0, 0, 0, 0.22),
          0 2px 8px rgba(0, 0, 0, 0.12);
      }
      .mcs-title-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
        flex-wrap: wrap;
      }
      .mcs-title {
        margin: 0;
        font-size: 1.75rem;
        font-weight: 800;
        letter-spacing: -0.02em;
        text-shadow: 0 2px 12px rgba(0, 0, 0, 0.35);
      }
      .mcs-quickfill-btn {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.5rem 0.875rem;
        background: rgba(255, 255, 255, 0.18);
        color: inherit;
        border: 1px solid rgba(255, 255, 255, 0.3);
        border-radius: 999px;
        cursor: pointer;
        font: 500 0.8125rem var(--boxel-font-family, sans-serif);
        backdrop-filter: blur(8px);
        transition:
          background 0.18s ease,
          transform 0.18s ease;
      }
      .mcs-quickfill-btn:hover {
        background: rgba(255, 255, 255, 0.28);
        transform: translateY(-1px);
      }
      .mcs-quickfill {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .mcs-quickfill-input {
        width: 100%;
        padding: 0.625rem 0.875rem;
        font-family: inherit;
        font-size: 0.875rem;
        background: rgba(255, 255, 255, 0.95);
        color: #111;
        border: none;
        border-radius: 8px;
        resize: vertical;
        min-height: 2.5rem;
        box-sizing: border-box;
        outline: none;
      }
      .mcs-quickfill-input:focus {
        box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.5);
      }
      .mcs-quickfill-actions {
        display: flex;
        gap: 0.5rem;
        align-items: center;
      }
      .mcs-qf-btn {
        padding: 0.5rem 1rem;
        font: 600 0.8125rem var(--boxel-font-family, sans-serif);
        border-radius: 8px;
        cursor: pointer;
        border: none;
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        transition:
          transform 0.18s ease,
          box-shadow 0.18s ease;
      }
      .mcs-qf-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }
      .mcs-qf-btn--primary {
        background: #fff;
        color: #007272;
      }
      .mcs-qf-btn--primary:hover:not(:disabled) {
        transform: translateY(-1px);
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.15);
      }
      .mcs-qf-btn--ghost {
        background: transparent;
        color: inherit;
        border: 1px solid rgba(255, 255, 255, 0.4);
      }
      .mcs-qf-btn--ghost:hover {
        background: rgba(255, 255, 255, 0.12);
      }
      .mcs-spinner {
        width: 12px;
        height: 12px;
        border: 2px solid currentColor;
        border-right-color: transparent;
        border-radius: 50%;
        animation: mcsSpin 0.7s linear infinite;
      }
      @keyframes mcsSpin {
        to {
          transform: rotate(360deg);
        }
      }
      .mcs-quickfill-msg {
        margin: 0;
        font-size: 0.75rem;
        padding: 0.375rem 0.625rem;
        border-radius: 6px;
      }
      .mcs-quickfill-msg--success {
        background: rgba(48, 239, 157, 0.2);
        color: #d4ffe8;
        display: inline-flex;
        align-self: flex-start;
        align-items: flex-start;
        gap: 0.375rem;
      }
      .mcs-quickfill-msg--success svg {
        flex-shrink: 0;
        margin-top: 1px;
        opacity: 0.85;
      }
      .mcs-quickfill-msg--error {
        background: rgba(255, 80, 80, 0.25);
        color: #ffefef;
      }
      .mcs-debug {
        margin-top: 0.5rem;
        font-size: 0.6875rem;
      }
      .mcs-debug summary {
        cursor: pointer;
        opacity: 0.85;
      }
      .mcs-debug pre {
        margin: 0.375rem 0 0;
        padding: 0.5rem 0.625rem;
        background: rgba(0, 0, 0, 0.35);
        color: #fff;
        border-radius: 6px;
        white-space: pre-wrap;
        word-break: break-word;
        max-height: 200px;
        overflow: auto;
      }
      .mcs-currency-notice {
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
      .mcs-currency-notice strong {
        color: #fff;
        font-weight: 700;
      }

      .mcs-wrapper {
        /* ── Forest green palette (50 → 900) ── */
        --mc-green-50: #f0fdf4;
        --mc-green-100: #dcfce7;
        --mc-green-200: #bbf7d0;
        --mc-green-300: #86efac;
        --mc-green-400: #4ade80;
        --mc-green-500: #16a34a;
        --mc-green-600: #15803d;
        --mc-green-700: #166534;
        --mc-green-800: #14532d;
        --mc-green-900: #0a2e17;

        /* Aliases used across the dashboard */
        --mc-green: var(--mc-green-600);
        --mc-green-dark: var(--mc-green-700);
        --mc-green-bg: var(--mc-green-50);
        --mc-green-border: var(--mc-green-200);
        --mc-green-ring: rgba(22, 163, 74, 0.18);

        /* Neutrals */
        --mc-surface: #ffffff;
        --mc-bg: #f6faf7;
        --mc-text: #0f1c14;
        --mc-text-2: #1f2e25;
        --mc-muted: #5e6b62;
        --mc-border: #e3ebe5;
        --mc-border-2: #cdd9d0;

        /* Elevation + shape */
        --mc-shadow-sm: 0 1px 2px rgba(15, 28, 20, 0.05);
        --mc-shadow-md:
          0 4px 16px rgba(15, 28, 20, 0.08), 0 2px 4px rgba(15, 28, 20, 0.04);
        --mc-shadow-lg:
          0 20px 48px rgba(21, 128, 61, 0.22), 0 4px 12px rgba(15, 28, 20, 0.08);
        --mc-radius-sm: 8px;
        --mc-radius-md: 12px;
        --mc-radius-lg: 16px;

        container-type: inline-size;
        background: var(--mc-bg);
        padding: var(--boxel-sp-xl, 24px);
        height: 100%;
        box-sizing: border-box;
        overflow-y: auto;
        font-family: var(--boxel-font-family, sans-serif);
        color: var(--mc-text);
      }

      /* ── Surfaces layout ── */
      .mcs-layout {
        display: grid;
        grid-template-columns: 260px 1fr;
        gap: 20px;
        align-items: start;
      }
      @container (max-width: 700px) {
        .mcs-layout {
          grid-template-columns: 1fr;
        }
      }

      /* Pane wraps a single <Form>. Override Form's gap/padding vars so the
         sidebar fits the calculator's tighter rhythm. */
      .mcs-pane {
        --bx-form-padding: var(--boxel-sp);
        --bx-form-gap: var(--boxel-sp);
        background: var(--mc-surface);
        border: 1px solid var(--mc-border);
        border-radius: 12px;
        overflow: hidden;
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
      }
      /* ── Main content ── */
      .mcs-main {
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      /* stat cards */
      .mcs-summary {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
        gap: 12px;
      }
      .mcs-stat {
        padding: 14px;
        background: var(--mc-surface);
        border: 1px solid var(--mc-border);
        border-radius: 12px;
        border-left: 3px solid var(--mc-green-border);
        display: flex;
        flex-direction: column;
        gap: 4px;
        cursor: default;
        transition:
          border-color 120ms,
          box-shadow 120ms;
      }
      /* Hover-active state — applies to every stat card now that all
         four anchor a preview lift. The highlighted card keeps its
         green glow override below. */
      .mcs-stat[data-active='true'] {
        border-color: var(--mc-green);
        box-shadow: 0 0 0 3px rgba(5, 150, 105, 0.12);
      }
      .mcs-stat--highlight {
        background: var(--mc-green);
        border-color: transparent;
        border-left-color: rgba(255, 255, 255, 0.3);
        box-shadow: 0 4px 20px rgba(0, 114, 114, 0.35);
      }
      .mcs-stat-label {
        font: 700 11px var(--boxel-font-family, sans-serif);
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--mc-muted);
      }
      .mcs-stat--highlight .mcs-stat-label {
        color: rgba(255, 255, 255, 0.75);
      }
      .mcs-stat-value {
        font-size: 20px;
        font-weight: 800;
        font-variant-numeric: tabular-nums;
        color: var(--mc-text);
        letter-spacing: -0.02em;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .mcs-stat--highlight .mcs-stat-value {
        color: #fff;
      }

      /* breakdown table */
      .mcs-table {
        background: var(--mc-surface);
        border: 1px solid var(--mc-border);
        border-radius: 12px;
        overflow: hidden;
        display: flex;
        flex-direction: column;
      }
      .mcs-table-row {
        display: grid;
        grid-template-columns: 1.4fr 1fr 1fr;
        padding: 10px 16px;
        font-size: 14px;
        align-items: center;
        font-variant-numeric: tabular-nums;
      }
      .mcs-table-row + .mcs-table-row {
        border-top: 1px solid var(--mc-border);
      }
      .mcs-table-row span:not(:first-child),
      .mcs-table-cell:not(:first-child) {
        text-align: right;
        font-weight: 500;
      }
      .mcs-table-head {
        background: var(--mc-green-bg);
        font: 700 11px var(--boxel-font-family, sans-serif);
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--mc-green-dark);
      }
      .mcs-table-row--featured {
        background: rgba(5, 150, 105, 0.06);
        font-weight: 600;
        color: var(--mc-text-2);
      }
      .mcs-table-row--total {
        background: var(--mc-bg);
        font-weight: 800;
        border-top: 2px solid var(--mc-border-2) !important;
        color: var(--mc-text);
      }

      /* Cross-highlight on category rows (skip the total — it has no
         category key, so its data-attrs stay 'false'). Hover paints
         a light tint; selected paints a stronger tint + green inset. */
      .mcs-table-row[data-active='true']:not(.mcs-table-row--total) {
        background: color-mix(in srgb, var(--mc-green) 8%, transparent);
        cursor: pointer;
      }
      /* featured (P&I) row keeps its faint base tint; on active that
         merges with the active tint — explicit override prevents the
         two greens stacking into something too saturated. */
      .mcs-table-row--featured[data-active='true'] {
        background: color-mix(in srgb, var(--mc-green) 10%, transparent);
      }

      /* charts panel */
      .mcs-charts {
        background: var(--mc-surface);
        border: 1px solid var(--mc-border);
        border-radius: 12px;
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .mcs-tabs {
        display: inline-flex;
        padding: 4px;
        background: var(--mc-green-bg);
        border: 1px solid var(--mc-green-border);
        border-radius: 999px;
        gap: 2px;
      }
      .mcs-tab {
        padding: 6px 16px;
        background: transparent;
        color: var(--mc-muted);
        border: none;
        border-radius: 999px;
        cursor: pointer;
        font: 600 13px var(--boxel-font-family, sans-serif);
        transition:
          color 0.18s,
          background 0.18s;
      }
      .mcs-tab--active {
        background: var(--mc-green);
        color: #fff;
        box-shadow: 0 2px 8px rgba(5, 150, 105, 0.35);
      }
      .mcs-chart-panel {
        background: var(--mc-green-bg);
        border: 1px solid var(--mc-green-border);
        border-radius: 12px;
        padding: 16px;
        min-height: 300px;
      }
      .mcs-chart-panel--breakdown {
        display: grid;
        grid-template-columns: auto 1fr;
        gap: 28px;
        align-items: center;
        min-height: 0;
      }
      .mcs-legend {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .mcs-legend-row {
        display: grid;
        grid-template-columns: 12px 1fr auto;
        align-items: center;
        gap: 8px;
        padding: 8px 10px;
        background: #fff;
        border: 1px solid var(--mc-border);
        border-radius: 8px;
        cursor: pointer;
        transition:
          background 120ms,
          border-color 120ms,
          box-shadow 120ms;
      }
      .mcs-legend-row[data-active='true'] {
        border-color: var(--mc-green);
        background: var(--mc-green-bg);
      }
      .mcs-legend-swatch {
        width: 12px;
        height: 12px;
        border-radius: 3px;
        flex-shrink: 0;
      }
      .mcs-legend-label {
        font: 600 13px var(--boxel-font-family, sans-serif);
        color: var(--mc-text-2);
      }
      .mcs-legend-pct {
        font: 700 13px var(--boxel-monospace-font-family, monospace);
        color: var(--mc-muted);
        font-variant-numeric: tabular-nums;
      }

      /* Currency trigger — a polished "badge" tile. Symbol sits in a
         circular forest-green chip; code is the dominant text. Looks
         like a designed component rather than a raw input. */
      .mcs-currency-trigger {
        display: flex;
        align-items: center;
        gap: 0;
        padding: 8px 14px;
        background: var(--mc-surface);
        border: 1.5px solid var(--mc-green-border);
        border-radius: var(--mc-radius-md);
        cursor: pointer;
        min-height: 44px;
        width: fit-content;
        font-family: var(--boxel-font-family, sans-serif);
        box-shadow: var(--mc-shadow-sm);
        transition:
          border-color 0.18s ease,
          background 0.18s ease,
          box-shadow 0.18s ease,
          transform 0.12s ease;
      }
      /* Cell wraps its yield in <span class='bx-cell__content'> which is
         display:block by default — force inline-flex so symbol + code +
         caret all sit on one row. */
      .mcs-currency-trigger :deep(.bx-cell__content) {
        display: flex;
        align-items: center;
        gap: 10px;
        white-space: nowrap;
        width: auto;
      }
      .mcs-currency-symbol {
        display: inline-grid;
        place-items: center;
        width: 28px;
        height: 28px;
        border-radius: 50%;
        background: var(--mc-green);
        color: #fff;
        font: 800 14px var(--boxel-font-family, sans-serif);
        line-height: 1;
        box-shadow: 0 2px 6px var(--mc-green-ring);
      }
      .mcs-currency-code {
        font: 700 14px var(--boxel-font-family, sans-serif);
        color: var(--mc-text);
        letter-spacing: 0.06em;
      }
      .mcs-currency-caret {
        color: var(--mc-green-dark);
        flex-shrink: 0;
        transition: transform 0.2s ease;
      }
      .mcs-currency-trigger[data-active='true'] .mcs-currency-caret {
        transform: rotate(180deg);
      }

      /* ── Lift body — self-contained card chrome that masks any
         default Lift surface (cream/parchment, etc.) ── */
      .mcs-lift-body {
        display: flex;
        flex-direction: column;
        gap: 10px;
        padding: 16px 18px;
        min-width: 260px;
        font: 500 13px var(--boxel-font-family, sans-serif);
        color: var(--mc-text);
        background: var(--mc-surface);
        border: 1px solid var(--mc-green-border);
        border-radius: var(--mc-radius-md);
        box-shadow: var(--mc-shadow-lg);
        font-variant-numeric: tabular-nums;
      }
      .mcs-lift-body--edit {
        padding: 16px 18px;
        min-width: 280px;
      }
      .mcs-lift-title {
        font: 800 11px var(--boxel-font-family, sans-serif);
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--mc-green-dark);
      }
      .mcs-lift-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 12px;
        padding: 6px 0;
        font: 500 13px var(--boxel-font-family, sans-serif);
      }
      .mcs-lift-row + .mcs-lift-row {
        border-top: 1px dashed var(--mc-border);
      }
      .mcs-lift-row span {
        color: var(--mc-muted);
      }
      .mcs-lift-row strong {
        color: var(--mc-text);
        font-weight: 800;
        letter-spacing: 0.02em;
      }
      .mcs-lift-hint {
        font: 500 11px var(--boxel-font-family, sans-serif);
        color: var(--mc-muted);
        font-style: italic;
        padding-top: 4px;
        border-top: 1px solid var(--mc-border);
      }

      /* Highlighted (monthly) card gets a brighter ring on active. */
      .mcs-stat--highlight[data-active='true'] {
        border-color: transparent;
        box-shadow:
          0 4px 20px rgba(0, 114, 114, 0.35),
          0 0 0 3px rgba(255, 255, 255, 0.5);
      }

      /* Charts header — tabs on the left, actions on the right */
      .mcs-charts-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
      }
      .mcs-charts-actions {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .mcs-icon-btn {
        width: 32px;
        height: 32px;
        border-radius: 8px;
        border: 1px solid var(--mc-border);
        background: var(--mc-surface);
        color: var(--mc-muted);
        cursor: pointer;
        font-size: 16px;
        line-height: 1;
      }
      .mcs-icon-btn:hover {
        border-color: var(--mc-green-border);
        color: var(--mc-text);
      }
      .mcs-action-btn {
        padding: 8px 14px;
        border-radius: 999px;
        border: 1px solid var(--mc-green);
        background: var(--mc-green);
        color: #fff;
        font: 600 13px var(--boxel-font-family, sans-serif);
        cursor: pointer;
      }
      .mcs-action-btn:hover {
        background: var(--mc-green-dark);
      }

      /* ── Stat preview (attached lift body for all 4 cards) ── */
      .mcs-stat-preview {
        display: flex;
        flex-direction: column;
        gap: 6px;
        padding: 14px 16px;
        min-width: 240px;
        font: 500 13px var(--boxel-font-family, sans-serif);
        color: var(--mc-text);
        font-variant-numeric: tabular-nums;
      }
      .mcs-stat-preview__head {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding-bottom: 8px;
        margin-bottom: 4px;
        border-bottom: 1px solid var(--mc-border);
      }
      .mcs-stat-preview__eyebrow {
        font: 700 11px var(--boxel-font-family, sans-serif);
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--mc-muted);
      }
      .mcs-stat-preview__value {
        font: 800 20px var(--boxel-font-family, sans-serif);
        letter-spacing: -0.02em;
        color: var(--mc-text);
      }
      .mcs-stat-preview__row {
        display: flex;
        justify-content: space-between;
        gap: 16px;
      }
      .mcs-stat-preview__row span {
        color: var(--mc-muted);
      }

      /* ── Tools menu (dark — kind='tools' provides colors) ── */
      .mcs-tools-menu {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding: 4px;
        margin: 0;
        list-style: none;
      }
      .mcs-tools-menu button {
        text-align: left;
        padding: 8px 12px;
        background: transparent;
        border: none;
        color: inherit;
        font: 500 13px var(--boxel-font-family, sans-serif);
        border-radius: 4px;
        cursor: pointer;
      }
      .mcs-tools-menu button:hover {
        background: rgba(255, 255, 255, 0.08);
      }

      /* ── Scenario modal ──
         Self-contained card stacked on top of the Lift plane, so the
         modal owns its full visual treatment (no parchment / cream
         lift defaults leaking through). */
      .mcs-scenario {
        position: relative;
        display: flex;
        flex-direction: column;
        gap: 20px;
        padding: 28px 28px 22px;
        min-width: 440px;
        background: var(--mc-surface);
        border: 1px solid var(--mc-green-border);
        border-radius: var(--mc-radius-lg);
        box-shadow: var(--mc-shadow-lg);
        font-family: var(--boxel-font-family, sans-serif);
        color: var(--mc-text);
        overflow: hidden;
      }
      /* Decorative top accent band — instant forest identity, no yellow. */
      .mcs-scenario::before {
        content: '';
        position: absolute;
        inset: 0 0 auto 0;
        height: 4px;
        background: linear-gradient(
          90deg,
          var(--mc-green-700) 0%,
          var(--mc-green-500) 50%,
          var(--mc-green-300) 100%
        );
      }
      .mcs-scenario__header {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }
      .mcs-scenario__header h3 {
        margin: 0;
        font: 800 19px var(--boxel-font-family, sans-serif);
        letter-spacing: -0.015em;
        color: var(--mc-green-800);
      }
      .mcs-scenario__header p {
        margin: 0;
        font: 500 13px var(--boxel-font-family, sans-serif);
        color: var(--mc-muted);
        line-height: 1.45;
      }
      .mcs-scenario__form {
        --bx-form-padding: 0;
        --bx-form-gap: 14px;
        background: transparent;
      }
      .mcs-scenario__compare {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 0;
        padding: 0;
        background: var(--mc-green-50);
        border: 1px solid var(--mc-green-border);
        border-radius: var(--mc-radius-md);
        overflow: hidden;
      }
      .mcs-scenario__compare > div {
        display: flex;
        flex-direction: column;
        gap: 6px;
        padding: 14px 18px;
      }
      .mcs-scenario__compare > div + div {
        border-left: 1px solid var(--mc-green-border);
        background: linear-gradient(
          180deg,
          var(--mc-green-100) 0%,
          var(--mc-green-50) 100%
        );
      }
      .mcs-scenario__compare span {
        font: 800 10px var(--boxel-font-family, sans-serif);
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--mc-green-dark);
      }
      .mcs-scenario__compare strong {
        font: 800 22px var(--boxel-font-family, sans-serif);
        letter-spacing: -0.02em;
        color: var(--mc-text);
        font-variant-numeric: tabular-nums;
        line-height: 1.15;
      }
      .mcs-scenario__compare > div + div strong {
        color: var(--mc-green-700);
      }
      .mcs-scenario__footer {
        display: flex;
        justify-content: flex-end;
        align-items: center;
        gap: 10px;
        padding-top: 4px;
      }
      /* Buttons mirror .mcs-action-btn (the "Run scenario…" trigger
         on the dashboard): green pill, white text, same padding +
         font. Cancel is the inverted tonal: white pill, green text,
         green border — same shape and weight so the pair reads as
         designed. */
      /* Hard-coded color fallbacks alongside vars — the modal portals
         to document.body so token cascade can be fragile. Fallback
         values match the .mcs-lift-shell tokens. */
      .mcs-btn {
        padding: 8px 18px;
        border-radius: 999px;
        border: 1.5px solid var(--mc-green, #15803d);
        background: #fff;
        color: var(--mc-green-dark, #166534);
        font: 600 13px var(--boxel-font-family, sans-serif);
        letter-spacing: 0.01em;
        cursor: pointer;
        transition:
          background 0.18s ease,
          border-color 0.18s ease,
          color 0.18s ease,
          transform 0.12s ease,
          box-shadow 0.18s ease;
      }
      .mcs-btn:hover {
        background: var(--mc-green-50, #f0fdf4);
        border-color: var(--mc-green-dark, #166534);
        color: var(--mc-green-800, #14532d);
      }
      .mcs-btn--primary {
        background: var(--mc-green, #15803d);
        border-color: var(--mc-green, #15803d);
        color: #fff;
        box-shadow: 0 2px 8px rgba(22, 163, 74, 0.18);
      }
      .mcs-btn--primary:hover {
        background: var(--mc-green-dark, #166534);
        border-color: var(--mc-green-dark, #166534);
        color: #fff;
        transform: translateY(-1px);
        box-shadow: 0 6px 16px rgba(22, 163, 74, 0.18);
      }
      .mcs-btn:focus-visible {
        outline: none;
        box-shadow: 0 0 0 3px rgba(22, 163, 74, 0.18);
      }
      .mcs-btn:active {
        transform: translateY(0);
      }
    </style>
  </template>
}

MortgageSurfaceDemo.isolated = MortgageSurfaceDemoIsolated;
