import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { htmlSafe } from '@ember/template';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import type { StepItem } from '@cardstack/pretui/components/step-list';
import type { Hue } from '@cardstack/catalog/components/state-pill';

// The Pret UI settings the fulfilment cards share, kept in one module so the
// six isolated views that show a query error, a loading list or a money figure
// all render them the same way.

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

// Pret UI `Alert` paints its tone from the fill tokens, whose text mixes fall
// under 4.5:1 on some grounds, and its info tone reads a token boxel's theme
// does not declare. Alert writes its hue as an inline style, so the override
// is inline too: the hue is the tone's `--*-ink` token, the tint is 10%, and
// the glyph disc's mark is the card colour. The body text is the ink as well,
// except for info: `--info-ink` is 4.79:1 on the dark card before any tint,
// so an info body reads `--foreground`.
function alertStyle(ink: string, body = ink) {
  return htmlSafe(
    `--pretui-alert-hue: var(${ink}); --pretui-chip-mix: 10%; --pretui-on-neutral: var(--card); color: var(${body})`,
  );
}

export const ALERT_STYLE = {
  danger: alertStyle('--destructive-ink'),
  success: alertStyle('--success-ink'),
  info: alertStyle('--info-ink', '--foreground'),
  attention: alertStyle('--attention-ink'),
};

// Stock states are statuses, so they take the status hues.
const STOCK_STATE_HUE: Record<string, Hue> = {
  out: 'red',
  low: 'amber',
  ok: 'green',
  draft: 'slate',
};

export function stockStateHue(state?: string | null): Hue {
  return STOCK_STATE_HUE[state ?? ''] ?? 'slate';
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
        gap: 0.5rem;
      }
      .loading-rows :deep(.pretui-skeleton) {
        border-radius: 0.1875rem;
        background-image: linear-gradient(
          90deg,
          color-mix(in oklch, var(--foreground) 7%, transparent) 40%,
          color-mix(in oklch, var(--foreground) 12%, transparent) 50%,
          color-mix(in oklch, var(--foreground) 7%, transparent) 60%
        );
      }
    </style>
  </template>;
