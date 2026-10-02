import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { htmlSafe } from '@ember/template';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import type { StepItem } from '@cardstack/pretui/components/step-list';
import { Chip } from '@cardstack/pretui/components/chip';
import { eq } from '@cardstack/boxel-ui/helpers';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
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

// A status pill hue: one of StatePill's, or `attention` for the low / tight
// state. That state reads `--attention` everywhere it is drawn. Its bars and
// gauges need a fill that shows against their track, which `--warning`'s
// yellow does not (1.03:1 on the light track), and its quantity text reads
// `--attention-ink`, which clears 4.5:1 on a hovered row where `--warning-ink`
// does not (4.34:1). StatePill has no attention hue, so that one pill is Pret
// UI `Chip` with StatePill's own recipe (14% fill, 62% foreground ink, no dot)
// on `--attention`: 13.91:1 light, 6.38:1 dark.
export type StatusHue = Hue | 'attention';

const ATTENTION_CHIP_STYLE = htmlSafe(
  '--pretui-chip-hue: var(--attention); --pretui-chip-mix: 14%; --pretui-ink-mix: 62%; max-width: 100%',
);

function statePillHue(hue?: StatusHue): Hue | undefined {
  return hue === 'attention' ? undefined : hue;
}

interface StatusPillSignature {
  Args: {
    label?: string | null;
    hue?: StatusHue;
  };
}

/** A StatePill that also takes the `attention` hue. */
export const StatusPill: TemplateOnlyComponent<StatusPillSignature> = <template>
  {{#if (eq @hue 'attention')}}
    {{#if @label}}
      <Chip @dot={{false}} style={{ATTENTION_CHIP_STYLE}}>
        <span class='status-label'>{{@label}}</span>
      </Chip>
    {{/if}}
  {{else}}
    <StatePill @label={{@label}} @hue={{statePillHue @hue}} />
  {{/if}}
  <style scoped>
    .status-label {
      overflow: hidden;
      text-overflow: ellipsis;
    }
  </style>
</template>;

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
