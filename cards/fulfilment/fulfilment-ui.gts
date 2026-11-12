import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { htmlSafe } from '@ember/template';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import type { StepItem } from '@cardstack/pretui/components/step-list';
import { money } from './fulfilment-format';

// The Pret UI settings the fulfilment cards share, kept in one module so the
// six isolated views that show a loading list, a money figure or a stock or
// capacity pill all render them the same way. The settings every cluster
// shares live in `components/pretui-helpers`.

interface MoneySignature {
  Args: {
    amount?: number | null;
    /** ISO 4217 code; GBP when absent, as `money` defaults. */
    code?: string | null;
  };
  Element: HTMLSpanElement;
}

function present(value: number | null | undefined) {
  return value ?? undefined;
}

/**
 * A money figure in a template, through Pret UI `FormatNumber` with the same
 * options `money` uses: the runtime default locale, the currency style and a
 * GBP default. An absent amount shows FormatNumber's `—`, as `money` does.
 */
export const Money: TemplateOnlyComponent<MoneySignature> = <template>
  <FormatNumber
    @value={{present @amount}}
    @style='currency'
    @currency={{if @code @code 'GBP'}}
    ...attributes
  />
</template>;

/** Stat prints a string verbatim, and an empty one as its dash. */
export function amountText(amount?: number | null, code?: string | null) {
  return amount ? money(amount, code ?? undefined) : '';
}

/**
 * A lifecycle as Pret UI `StepList` steps. Stages before the reached one are
 * complete, the reached one is current, and reaching the final stage completes
 * the whole run. An off-path status (reached < 0) leaves every stage upcoming,
 * because the package or order has not progressed along the path.
 */
export function lifecycleSteps(
  pipeline: string[],
  labelOf: (value: string) => string,
  reached: number,
): StepItem[] {
  let last = pipeline.length - 1;
  return pipeline.map((value, i) => ({
    label: labelOf(value),
    state:
      reached < 0 || i > reached
        ? 'upcoming'
        : i < reached || reached === last
          ? 'complete'
          : 'current',
  }));
}

interface LoadingRowsSignature {
  Element: HTMLDivElement;
}

/**
 * Three Pret UI `Skeleton` lines holding the height a query's rows will take.
 * Skeleton's own shimmer runs between `--inset` and `--hover`, which sit
 * within a shade of the 3% section panel these rows load inside, so the lines
 * are tinted from `--foreground` instead, the same 7% the rows drew before.
 */
export const LoadingRows: TemplateOnlyComponent<LoadingRowsSignature> =
  <template>
    <div class='loading-rows' aria-busy='true' ...attributes>
      <Skeleton @height='0.875rem' />
      <Skeleton @height='0.875rem' />
      <Skeleton @height='0.875rem' />
    </div>
    <style scoped>
      .loading-rows {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>;

interface CompoundAtomSignature {
  Args: {
    /** two-letter type mark, used when there is no image */
    mark?: string;
    /** image shown in place of the mark */
    src?: string | null;
    name?: string | null;
    /** short state after the dot ("shipped", "92% full") */
    meta?: string | null;
    /** dot colour, a theme token such as `var(--success)` */
    hue?: string | null;
  };
  Element: HTMLSpanElement;
}

function hueStyle(hue?: string | null) {
  return htmlSafe(`--ca-hue: ${hue || 'var(--muted-foreground)'}`);
}

/**
 * The atom the fulfilment cards share: a type mark (or image), the name, and
 * a dot with a short state, on one line. The name ellipsizes first.
 */
export const CompoundAtom: TemplateOnlyComponent<CompoundAtomSignature> =
  <template>
    <span class='ca' ...attributes>
      {{#if @src}}
        <Avatar
          @name={{if @name @name ''}}
          @src={{@src}}
          @shape='square'
          @size={{16}}
        />
      {{else}}
        <span class='ca-mark' aria-hidden='true'>{{@mark}}</span>
      {{/if}}
      <span class='ca-name'>{{if @name @name '—'}}</span>
      {{#if @meta}}
        <span class='ca-meta' style={{hueStyle @hue}}><span
            class='ca-dot'
          ></span>{{@meta}}</span>
      {{/if}}
    </span>
    <style scoped>
      .ca {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-2xs);
        max-width: 100%;
        min-width: 0;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.4;
        vertical-align: middle;
      }
      .ca-mark {
        display: inline-grid;
        flex-shrink: 0;
        place-items: center;
        width: 1rem;
        height: 1rem;
        border-radius: calc(var(--radius) * 0.5);
        background-color: var(--muted);
        color: var(--foreground);
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 700;
      }
      .ca-name {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-weight: 600;
      }
      .ca-meta {
        display: inline-flex;
        flex-shrink: 0;
        align-items: center;
        gap: var(--boxel-sp-3xs);
        color: var(--foreground);
        white-space: nowrap;
      }
      .ca-dot {
        width: 0.4375rem;
        height: 0.4375rem;
        border-radius: 50%;
        background-color: var(--ca-hue);
      }
    </style>
  </template>;
