// Compact fitted shell shared by Deal, Invoice and Proposal (Revenue OS).
// Rows are budgeted per fitted size: the rows box is rounded DOWN to a whole
// number of rows, so a row is either fully shown or not at all.
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';

export interface CompactTag {
  label: string;
  tone?: 'neutral' | 'primary' | 'info' | 'success' | 'warning' | 'danger';
}

interface FittedSig {
  Args: {
    mark: string;
    title?: string;
    sub?: string;
    fact?: string;
    big?: string;
    bigLabel?: string;
    tags?: CompactTag[];
  };
  Element: HTMLElement;
  Blocks: { rows: [] };
}

export const CompactFitted: TemplateOnlyComponent<FittedSig> = <template>
  <article class='cf' ...attributes>
    <div class='cf-t'>
      <Avatar @name={{@mark}} @shape='square' @size={{20}} />
      <span class='cf-n'>{{@title}}</span>
      <span class='cf-st'>
        {{#each @tags as |t|}}
          <Chip
            class='cf-tag'
            @label={{t.label}}
            @tone={{t.tone}}
            @appearance='plain'
          />
        {{/each}}
      </span>
    </div>
    <p class='cf-sub'>{{@sub}}</p>
    <span class='cf-s2'>
      {{#each @tags as |t i|}}{{#if (isFirst i)}}<Chip
            @label={{t.label}}
            @tone={{t.tone}}
            @appearance='plain'
          />{{/if}}{{/each}}
    </span>
    <p class='cf-fact'>{{@fact}}</p>
    {{#if @big}}
      <p class='cf-big'><b>{{@big}}</b><span>{{@bigLabel}}</span></p>
    {{/if}}
    <div class='cf-rows'>{{yield to='rows'}}</div>
  </article>
  <style scoped>
    @layer PretComponent {
      .cf {
        --cf-row: 1.5rem;
        --cf-used: 1rem;
        display: flex;
        flex-direction: column;
        box-sizing: border-box;
        block-size: 100%;
        padding: 0.5rem;
        overflow: hidden;
        font-size: 0.75rem;
        line-height: 1.25;
        color: var(--card-foreground);
      }
      .cf > * {
        flex: none;
        min-inline-size: 0;
        margin: 0;
      }
      .cf-t {
        display: flex;
        align-items: center;
        gap: 0.375rem;
        block-size: 1.5rem;
      }
      .cf-n {
        flex: 1 1 0;
        min-inline-size: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-weight: 700;
      }
      .cf-st {
        flex: none;
        display: flex;
        gap: 0.5rem;
      }
      .cf-sub,
      .cf-fact {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        color: var(--muted-foreground);
      }
      .cf-sub {
        block-size: 1rem;
        line-height: 1rem;
        font-size: 0.6875rem;
      }
      .cf-fact {
        block-size: 1.25rem;
        line-height: 1.25rem;
        color: var(--foreground);
      }
      .cf-s2 {
        display: none;
        block-size: 1.25rem;
        align-items: center;
      }
      .cf-big {
        display: none;
        block-size: 1.75rem;
        align-items: baseline;
        gap: 0.375rem;
        overflow: hidden;
        white-space: nowrap;
      }
      .cf-big b {
        font-size: 1.375rem;
        line-height: 1.75rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }
      .cf-big span {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      /* Whole rows only: the rows box takes whatever height is left, the grid
         makes one track per full row that fits, and any further row lands in
         a zero-height implicit track, so nothing is ever half cut. */
      .cf-rows {
        display: none;
        flex: 1 1 0;
        min-block-size: 0;
        grid-template-rows: repeat(auto-fill, var(--cf-row));
        grid-auto-rows: 0;
        overflow: hidden;
      }

      /* status chips: none under 65 tall; inline from 250 wide */
      .cf-st {
        display: none;
      }
      @container fitted-card (width >= 250px) and (height >= 40px) {
        .cf-st .cf-tag + .cf-tag {
          display: none;
        }
        .cf-st {
          display: flex;
        }
      }
      @container fitted-card (width >= 400px) {
        .cf-st .cf-tag + .cf-tag {
          display: inline-flex;
        }
      }
      /* under 65 tall only the title line */
      @container fitted-card (height < 65px) {
        .cf-sub,
        .cf-fact {
          display: none;
        }
      }
      @container fitted-card (height >= 65px) and (height < 105px) {
        .cf-fact {
          display: none;
        }
      }
      @container fitted-card (height < 105px) {
        .cf-sub {
          display: block;
        }
      }
      @container fitted-card (height < 65px) {
        .cf-sub {
          display: none;
        }
      }
      /* narrow and tall enough: the status moves to its own line */
      @container fitted-card (width < 250px) and (height >= 105px) {
        .cf-s2 {
          display: flex;
        }
      }
      @container fitted-card (height >= 170px) {
        .cf-big {
          display: flex;
        }
        .cf-rows {
          display: grid;
        }
        .cf {
          --cf-used: 6.5rem;
        }
      }
      @container fitted-card (height >= 170px) and (width < 250px) {
        .cf {
          --cf-used: 7.75rem;
        }
      }
    }
  </style>
</template>;

function isFirst(i: number) {
  return i === 0;
}

interface RowSig {
  Args: { k: string; v?: string };
  Element: HTMLElement;
  Blocks: { default: [] };
}

export const CompactRow: TemplateOnlyComponent<RowSig> = <template>
  <div class='cr' ...attributes>
    <span class='cr-k'>{{@k}}</span>
    <span class='cr-v'>{{#if @v}}{{@v}}{{else}}{{yield}}{{/if}}</span>
  </div>
  <style scoped>
    @layer PretComponent {
      .cr {
        flex: none;
        box-sizing: border-box;
        block-size: 100%;
        min-block-size: 0;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.5rem;
        border-block-start: 1px solid var(--border);
        overflow: hidden;
      }
      .cr-k {
        flex: none;
        font-family: var(--font-mono);
        font-size: 0.5625rem;
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .cr-v {
        min-inline-size: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        text-align: end;
        font-variant-numeric: tabular-nums;
      }
    }
  </style>
</template>;

export function fmtDate(d?: Date | string | null, year = true): string {
  if (!d) return '';
  let date = d instanceof Date ? d : new Date(d);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: year ? 'numeric' : undefined,
    timeZone: 'UTC',
  }).format(date);
}
