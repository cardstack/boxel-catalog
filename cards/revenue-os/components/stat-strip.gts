import Component from '@glimmer/component';
import { Stat } from '@cardstack/pretui/components/stat';

export interface StripStat {
  label: string;
  value: string | number;
  hint?: string;
  tone?: string;
}

interface Signature {
  Args: { stats: readonly StripStat[]; label?: string };
  Element: HTMLElement;
}

// One joined strip of Stats: hairline dividers, radius only on the outer edge.
export class StatStrip extends Component<Signature> {
  // whole-dollar headline: formatMoney carries cents, the mock does not
  show = (v: string | number) =>
    typeof v === 'string' ? v.replace(/\.00$/, '') : v;

  <template>
    <section class='strip' aria-label={{@label}} ...attributes>
      {{#each @stats as |s|}}
        <div class='cell'>
          <Stat
            @label={{s.label}}
            @value={{this.show s.value}}
            @tone={{s.tone}}
            @hint={{s.hint}}
            @roll={{false}}
          />
        </div>
      {{/each}}
    </section>
    <style scoped>
      .strip {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .cell {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        min-width: 0;
        box-shadow:
          -1px 0 0 var(--border),
          0 -1px 0 var(--border);
      }
    </style>
  </template>
}
