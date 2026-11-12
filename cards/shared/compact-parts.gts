import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { concat } from '@ember/helper';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { Stat as PretStat } from '@cardstack/pretui/components/stat';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import type { Tone } from './compact-format';

// The status dot and stat strip the compact app and its record cards share,
// as thin adapters over Pret UI.

/** A status dot + text. */
export const Dot: TemplateOnlyComponent<{
  Args: { tone?: Tone; label?: string | number };
  Element: HTMLSpanElement;
}> = <template>
  <StatusChip
    @value={{concat @label}}
    @tone={{if @tone @tone 'neutral'}}
    @appearance='plain'
    ...attributes
  />
</template>;

export interface Stat {
  label: string;
  value: string | number;
  unit?: string;
  hint?: string;
  tone?: Tone;
  meter?: number;
}

// Pret UI has no stat group by design: a grid of Stats, one tile each.
export const StatStrip: TemplateOnlyComponent<{
  Args: { stats: Stat[]; label: string; flat?: boolean };
  Element: HTMLUListElement;
}> = <template>
  <ul
    class='ce-stats'
    data-flat={{if @flat 'true'}}
    aria-label={{@label}}
    ...attributes
  >
    {{#each @stats as |s|}}
      <li class='ce-stat'>
        <PretStat
          @label={{s.label}}
          @value={{if s.unit (concat s.value s.unit) s.value}}
          @tone={{if s.tone s.tone 'neutral'}}
          @hint={{s.hint}}
          @roll={{false}}
        />
        {{#if s.meter}}<ProgressBar
            @value={{s.meter}}
            @hue='var(--foreground)'
            aria-label={{s.label}}
          />{{/if}}
      </li>
    {{/each}}
  </ul>
  <style scoped>
    .ce-stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(9.5rem, 1fr));
      gap: 1px;
      margin: 0;
      padding: 0;
      list-style: none;
      background: var(--border);
      border: 1px solid var(--border);
      border-radius: var(--boxel-border-radius);
      overflow: hidden;
    }
    .ce-stats[data-flat='true'] {
      border: 0;
      border-radius: 0;
    }
    .ce-stat {
      min-inline-size: 0;
      padding: var(--boxel-sp-xs);
      background: var(--card);
    }
  </style>
</template>;
