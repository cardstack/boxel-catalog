import type { TemplateOnlyComponent } from '@ember/component/template-only';
import type { DescriptionsItem } from '@cardstack/pretui/components/descriptions';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import Component from '@glimmer/component';
import { hash } from '@ember/helper';
import { on } from '@ember/modifier';
import type { ComponentLike } from '@glint/template';
import { Button } from '@cardstack/pretui/components/button';
import {
  LayoutControl,
  type LayoutControlSlotSignature,
} from '@cardstack/pretui/components/layout-control';

// The compact isolated layout the talent cards share: a dense header (a
// 32px mark, the name at 17px 800, one muted meta line), then ONE outer card
// whose sections are flat hairline lists with mono caps labels, and
// key/value rows 28px tall with a fixed 120px mono caps key column.

interface SheetSignature {
  Args: { title?: string | null; meta?: string | null };
  Blocks: { mark: []; aside: []; default: [] };
  Element: HTMLElement;
}

export const Sheet: TemplateOnlyComponent<SheetSignature> = <template>
  <article class='sheet' ...attributes>
    <header class='sheet-head'>
      {{#if (has-block 'mark')}}<span class='sheet-mark'>{{yield
            to='mark'
          }}</span>{{/if}}
      <div class='sheet-id'>
        <h1 class='sheet-title'>{{@title}}</h1>
        {{#if @meta}}<p class='sheet-meta'>{{@meta}}</p>{{/if}}
      </div>
      {{#if (has-block 'aside')}}<div class='sheet-aside'>{{yield
            to='aside'
          }}</div>{{/if}}
    </header>
    <div class='sheet-card'>{{yield}}</div>
  </article>
  <style scoped>
    @layer PretComponent {
      .sheet {
        /* actions inside are 26px: one primary Button, the rest text links */
        --pretui-button-h: 1.625rem;
        --pretui-button-radius: 0.375rem;
        container: sheet / inline-size;
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        box-sizing: border-box;
        min-height: 100%;
        padding: 0.875rem;
        background: var(--canvas, var(--background));
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.35;
      }
      .sheet-head {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        min-width: 0;
      }
      .sheet-mark {
        --pretui-avatar-size: 2rem;
        --position-mark-size: 2rem;
        --meeting-mark-size: 2rem;
        --pto-mark-size: 2rem;
        --review-mark-size: 2rem;
        --review-mark-font-size: 0.5625rem;
        --pto-mark-font-size: 0.5625rem;
        --meeting-mark-font-size: 0.5625rem;
        flex: none;
        display: inline-flex;
      }
      .sheet-id {
        flex: 1 1 auto;
        min-width: 0;
      }
      .sheet-title {
        margin: 0;
        overflow: hidden;
        font-family: var(--font-sans);
        font-size: 1.0625rem;
        font-weight: 800;
        line-height: 1.25;
        letter-spacing: -0.01em;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sheet-meta {
        margin: 0;
        overflow: hidden;
        color: var(--muted-foreground);
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sheet-aside {
        flex: none;
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.5rem;
      }
      /* the one outer card; sections inside are flat */
      .sheet-card {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        background: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      @container sheet (width >= 52rem) {
        .sheet-card {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
    }
  </style>
</template>;

interface SectionSignature {
  Args: { label: string; wide?: boolean };
  Blocks: { default: []; aside: [] };
  Element: HTMLElement;
}

/** A flat section: a mono caps label row, then its content, split from the
 *  previous section by a hairline. `@wide` spans both columns. */
export const SheetSection: TemplateOnlyComponent<SectionSignature> = <template>
  <section class='sheet-section' data-wide={{if @wide 'true'}} ...attributes>
    <div class='sheet-section-head'>
      <h2 class='sheet-label'>{{@label}}</h2>
      {{#if (has-block 'aside')}}<span class='sheet-section-aside'>{{yield
            to='aside'
          }}</span>{{/if}}
    </div>
    {{yield}}
  </section>
  <style scoped>
    @layer PretComponent {
      .sheet-section {
        min-width: 0;
        border-top: 1px solid var(--border);
        margin-top: -1px;
        border-inline-end: 1px solid var(--border);
        margin-inline-end: -1px;
      }
      .sheet-section[data-wide] {
        grid-column: 1 / -1;
      }
      .sheet-section-head {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        min-height: 1.75rem;
        padding: 0 0.625rem;
      }
      .sheet-label {
        margin: 0;
        font: 600 0.5625rem / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      .sheet-section-aside {
        margin-left: auto;
      }
    }
  </style>
</template>;

// Descriptions items ({ label }) and KeyValue items ({ key }) both render.
type SheetItem = (DescriptionsItem | KeyValueItem) & {
  label?: string;
  key?: string;
  value?: unknown;
};

interface RowsSignature {
  Args: { items: SheetItem[] };
  Blocks: { value: [any] };
  Element: HTMLDListElement;
}

/** Key/value rows: 28px, a 120px mono caps key, a 12px value. A value
 *  that holds an atom wraps under the key instead of being cut. */
export const SheetRows: TemplateOnlyComponent<RowsSignature> = <template>
  <dl class='sheet-rows' ...attributes>
    {{#each @items as |item|}}
      <div class='sheet-row'>
        <dt class='sheet-key'>{{if item.label item.label item.key}}</dt>
        <dd class='sheet-value'>{{#if (has-block 'value')}}{{yield
              item
              to='value'
            }}{{else}}{{item.value}}{{/if}}</dd>
      </div>
    {{/each}}
  </dl>
  <style scoped>
    @layer PretComponent {
      .sheet-rows {
        margin: 0;
      }
      .sheet-row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        column-gap: 0.625rem;
        min-height: 1.75rem;
        padding: 0 0.625rem;
        border-top: 1px solid var(--border);
      }
      .sheet-key {
        flex: none;
        inline-size: 7.5rem;
        font: 600 0.5625rem / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      .sheet-value {
        flex: 1 1 8rem;
        min-width: 0;
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        overflow-wrap: anywhere;
      }
    }
  </style>
</template>;

interface LineSignature {
  Blocks: { default: [] };
  Element: HTMLElement;
}

/** One 28px hairline line inside a section (a list item, a note, a link). */
export const SheetLine: TemplateOnlyComponent<LineSignature> = <template>
  <div class='sheet-line' ...attributes>{{yield}}</div>
  <style scoped>
    @layer PretComponent {
      .sheet-line {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.25rem 0.625rem;
        min-height: 1.75rem;
        padding: 0.25rem 0.625rem;
        box-sizing: border-box;
        border-top: 1px solid var(--border);
        font-size: var(--boxel-font-size-xs);
      }
    }
  </style>
</template>;

interface StatSignature {
  Args: { label: string; value?: unknown; hint?: string | null };
  Element: HTMLElement;
}

/** A headline number as one key/value row: key, value, muted hint. */
export const SheetStat: TemplateOnlyComponent<StatSignature> = <template>
  <div class='sheet-stat' ...attributes>
    <span class='sheet-stat-key'>{{@label}}</span>
    <span class='sheet-stat-value'>{{if @value @value '—'}}</span>
    {{#if @hint}}<span class='sheet-stat-hint'>{{@hint}}</span>{{/if}}
  </div>
  <style scoped>
    @layer PretComponent {
      .sheet-stat {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        column-gap: 0.625rem;
        min-height: 1.75rem;
        padding: 0 0.625rem;
        border-top: 1px solid var(--border);
        font-size: var(--boxel-font-size-xs);
      }
      .sheet-stat-key {
        flex: none;
        inline-size: 7.5rem;
        font: 600 0.5625rem / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      .sheet-stat-value {
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }
      .sheet-stat-hint {
        color: var(--muted-foreground);
      }
    }
  </style>
</template>;

interface EmptySignature {
  Args: { title?: string; message?: string };
  Element: HTMLElement;
}

/** An empty note as one muted hairline line, never a grey well. */
export const SheetEmpty: TemplateOnlyComponent<EmptySignature> = <template>
  <p class='sheet-empty' ...attributes>{{@title}}{{#if @message}}
      <span class='sheet-empty-msg'>{{@message}}</span>{{/if}}</p>
  <style scoped>
    @layer PretComponent {
      .sheet-empty {
        margin: 0;
        padding: 0.375rem 0.625rem;
        border-top: 1px solid var(--border);
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
      }
      .sheet-empty-msg {
        color: var(--subtle-foreground);
      }
    }
  </style>
</template>;

// ── The kit's card layout (matrix-compact-kit cards/*.html) ──────────────
// Isolated: IsoHead (mark, name, meta, status; optional StatStrip) above an
// IsoGrid of Panels with a docked aside. Embedded: EmbCard. Fitted: FitCard
// with FitRows. Rows are 28px with one hairline; labels are 9px mono caps.

interface HeadActionSignature {
  Args: {
    slot: ComponentLike<LayoutControlSlotSignature>;
    id: string;
    label: string;
    primary?: boolean;
    loading?: boolean;
    disabled?: boolean;
    onClick: () => void;
  };
}

/** One header action: a Pret UI Button in its own LayoutControl slot. */
export class HeadAction extends Component<HeadActionSignature> {
  forms = [{ name: 'label', minWidth: 6 }];
  <template>
    <@slot @id={{@id}} @forms={{this.forms}} @label={{@label}} @pinned={{true}}>
      <Button
        type='button'
        @size='xs'
        @tone={{if @primary 'primary' 'neutral'}}
        @appearance={{if @primary 'accent' 'outlined'}}
        @loading={{@loading}}
        @disabled={{@disabled}}
        {{on 'click' @onClick}}
      >{{@label}}</Button>
    </@slot>
  </template>
}

export interface HeadActions {
  Action: ComponentLike<{ Args: Omit<HeadActionSignature['Args'], 'slot'> }>;
}

interface IsoHeadSignature {
  Args: { title?: string | null; meta?: string | null };
  Blocks: { mark: []; aside: []; stats: []; actions: [HeadActions] };
  Element: HTMLElement;
}

export const IsoHead: TemplateOnlyComponent<IsoHeadSignature> = <template>
  <header class='ih-card' ...attributes>
    <div class='ih'>
      {{#if (has-block 'mark')}}<span class='ih-mark'>{{yield
            to='mark'
          }}</span>{{/if}}
      <div class='ih-t'>
        <h1 class='ih-title'>{{@title}}</h1>
        {{#if @meta}}<p class='ih-meta'>{{@meta}}</p>{{/if}}
      </div>
      {{#if (has-block 'aside')}}<div class='ih-aside'>{{yield
            to='aside'
          }}</div>{{/if}}
      {{#if (has-block 'actions')}}
        <LayoutControl
          class='ih-actions'
          @label='{{@title}} actions'
          @controlHeight='1.625rem'
          as |lc|
        >{{yield
            (hash Action=(component HeadAction slot=lc.Slot))
            to='actions'
          }}</LayoutControl>
      {{/if}}
    </div>
    {{#if (has-block 'stats')}}<div class='ih-stats'>{{yield
          to='stats'
        }}</div>{{/if}}
  </header>
  <style scoped>
    @layer PretComponent {
      .ih-card {
        background: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        min-width: 0;
      }
      .ih {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.375rem 0.75rem;
        padding: 0.75rem 0.625rem;
      }
      .ih-mark {
        --pretui-avatar-size: 2.25rem;
        --position-mark-size: 2.25rem;
        --meeting-mark-size: 2.25rem;
        --pto-mark-size: 2.25rem;
        --review-mark-size: 2.25rem;
        --review-mark-font-size: 0.5625rem;
        --pto-mark-font-size: 0.5625rem;
        --meeting-mark-font-size: 0.5625rem;
        flex: none;
        display: inline-flex;
      }
      .ih-t {
        flex: 1 1 10rem;
        min-width: 0;
      }
      .ih-title {
        margin: 0;
        font-family: var(--font-sans);
        font-size: 0.75rem;
        font-weight: 700;
        line-height: 1.35;
        overflow-wrap: anywhere;
      }
      .ih-meta {
        margin: 0;
        font-size: 0.6875rem;
        color: var(--muted-foreground);
        overflow-wrap: anywhere;
      }
      .ih-aside {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.5rem;
        font-size: 0.75rem;
      }
      .ih-stats {
        border-top: 1px solid var(--border);
      }
      .ih-actions {
        flex: 0 1 auto;
        min-width: 0;
      }
    }
  </style>
</template>;

export interface StripItem {
  label: string;
  value?: string | null;
  hint?: string | null;
  tone?: 'success' | 'info' | 'warning' | 'danger' | 'neutral';
}

interface StatStripSignature {
  Args: { items: StripItem[]; compact?: boolean };
  Element: HTMLElement;
}

/** The kit's joined stat strip: Pret UI Stat cells split by hairlines. */
export const StatStrip: TemplateOnlyComponent<StatStripSignature> = <template>
  <div class='strip' data-compact={{if @compact 'true'}} ...attributes>
    {{#each @items as |s|}}
      <Stat
        class='strip-cell'
        @label={{s.label}}
        @value={{if s.value s.value '—'}}
        @hint={{s.hint}}
        @tone={{s.tone}}
        @roll={{false}}
      />
    {{/each}}
  </div>
  <style scoped>
    /* cells sit on a hairline-coloured grid: the 1px gaps are the rules,
       so wrapped rows keep their borders without per-cell math */
    .strip {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(8.5rem, 1fr));
      overflow: hidden;
    }
    /* fitted tiles are narrow: two numbers side by side from 250 wide */
    .strip[data-compact] {
      grid-template-columns: repeat(auto-fit, minmax(5rem, 1fr));
      inline-size: 100%;
      flex: none;
      border-top: 1px solid var(--border);
    }
    /* fitted: two stats under 400 wide, three at 400; none where the
       numbers can't sit side by side */
    @container fitted-card (width < 400px) {
      .strip[data-compact] > .strip-cell:nth-child(n + 3) {
        display: none;
      }
    }
    @container fitted-card (width < 250px) or (height < 250px) {
      .strip[data-compact] {
        display: none;
      }
    }
    /* rules on each cell's leading and top edge; the strip clips the ones
       on its outer edge, so a short last row leaves no grey gap */
    .strip-cell {
      --pretui-stat-line: 1;
      padding: 0.4375rem 0.625rem;
      min-width: 0;
      box-shadow:
        -1px 0 0 var(--border),
        0 -1px 0 var(--border);
    }
    /* shortcut: Pret UI Stat has no label/value/hint type knobs, so the kit's mono caps label, 22px 700 value and 11px hint are set here; drop once Stat exposes them. */
    .strip-cell :deep(.pretui-stat-label) {
      font: 600 0.5625rem / 1.3 var(--font-mono);
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--subtle-foreground);
    }
    .strip-cell :deep(.pretui-stat-value) {
      font: 700 1.375rem / 1 var(--font-sans);
      font-variant-numeric: tabular-nums;
      overflow-wrap: break-word;
    }
    .strip-cell :deep(.pretui-stat-hint) {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
  </style>
</template>;

interface IsoPageSignature {
  Blocks: { head: []; main: []; aside: [] };
  Element: HTMLElement;
}

/** The isolated page: head card, then 2fr main column and a docked aside
 *  (one column under 42rem). The page scrolls; nothing inside clips. */
export const IsoPage: TemplateOnlyComponent<IsoPageSignature> = <template>
  <article class='iso' ...attributes>
    {{yield to='head'}}
    <div class='iso-grid'>
      <div class='iso-col'>{{yield to='main'}}</div>
      {{#if (has-block 'aside')}}<aside class='iso-aside'>{{yield
            to='aside'
          }}</aside>{{/if}}
    </div>
  </article>
  <style scoped>
    @layer PretComponent {
      .iso {
        container: iso / inline-size;
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        box-sizing: border-box;
        min-height: 100%;
        padding: 0.875rem;
        background: var(--canvas, var(--background));
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: 0.75rem;
        line-height: 1.35;
      }
      .iso-grid {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: 0.5rem;
      }
      /* the main column is ONE card; its sections are flat inside it */
      .iso-col {
        display: flex;
        flex-direction: column;
        min-width: 0;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      .iso-aside {
        min-width: 0;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      @container iso (width >= 42rem) {
        .iso-grid {
          grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
          align-items: start;
        }
        /* docked flush: one hairline on its leading edge */
        .iso-aside {
          border-width: 0 0 0 1px;
          border-radius: 0;
          background: var(--card);
        }
      }
    }
  </style>
</template>;

interface PanelSignature {
  Args: { title?: string; meta?: string | null };
  Blocks: { default: []; aside: [] };
  Element: HTMLElement;
}

/** A section: 12px 800 heading line, then flat rows. Inside the aside it is
 *  borderless (the aside is the card). */
export const Panel: TemplateOnlyComponent<PanelSignature> = <template>
  <section class='panel' ...attributes>
    {{#if @title}}
      <div class='sh'>
        <h2>{{@title}}</h2>
        {{#if @meta}}<span class='sh-meta'>{{@meta}}</span>{{/if}}
        {{#if (has-block 'aside')}}<span class='sh-aside'>{{yield
              to='aside'
            }}</span>{{/if}}
      </div>
    {{/if}}
    <div class='panel-body'>{{yield}}</div>
  </section>
  <style scoped>
    @layer PretComponent {
      .panel {
        min-width: 0;
        background: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .iso-col .panel,
      .iso-aside .panel,
      .panel.flat {
        border: 0;
        border-radius: 0;
        background: none;
      }
      .iso-col .panel + .panel,
      .iso-aside .panel + .panel {
        border-top: 1px solid var(--border);
      }
      .sh {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        gap: 0.5rem;
        padding: 0.4375rem 0.625rem 0.3125rem;
      }
      .sh h2 {
        margin: 0;
        font-size: 0.75rem;
        font-weight: 800;
      }
      .sh-meta {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .sh-aside {
        margin-left: auto;
        font-size: 0.6875rem;
      }
      /* wide rows scroll sideways instead of being cut */
      .panel-body {
        overflow-x: auto;
      }
    }
  </style>
</template>;

interface KvSignature {
  Args: { items: { key: string; value?: string | null }[] };
  Blocks: { value: [any] };
  Element: HTMLDListElement;
}

const kvItems = (items: KvSignature['Args']['items']) =>
  items.map((i) => ({ ...i, value: i.value ?? '' }));

/** Ruled key/value rows: Pret UI KeyValue, divided, mono caps keys. */
export const Kv: TemplateOnlyComponent<KvSignature> = <template>
  <KeyValue
    class='kv'
    @items={{kvItems @items}}
    @divided={{true}}
    ...attributes
  >
    <:value as |item|><span class='kv-v'>{{#if (has-block 'value')}}{{yield
            item
            to='value'
          }}{{else}}{{if item.value item.value '—'}}{{/if}}</span></:value>
  </KeyValue>
  <style scoped>
    .kv {
      --pretui-kv-label-font-family: var(--font-mono);
      --pretui-kv-label-font-size: 0.5625rem;
      --pretui-kv-label-font-weight: 600;
      --pretui-kv-label-line-height: 1.3;
      --pretui-kv-label-letter-spacing: 0.13em;
      --pretui-kv-label-text-transform: uppercase;
      --pretui-kv-label-color: var(--subtle-foreground);
      --boxel-sp-lg: 0.75rem;
      --boxel-sp-xs: 0.375rem;
      margin: 0;
      padding-inline: 0.625rem;
      border-top: 1px solid var(--border);
      font-size: 0.75rem;
      overflow-wrap: anywhere;
    }
    /* a value holding atoms wraps them instead of running past the edge */
    .kv-v {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.25rem;
      min-width: 0;
    }
  </style>
</template>;

interface EmbCardSignature {
  Args: { title?: string | null; meta?: string | null };
  Blocks: { mark: []; aside: []; default: [] };
  Element: HTMLElement;
}

/** Embedded: one header line, then ruled rows. */
export const EmbCard: TemplateOnlyComponent<EmbCardSignature> = <template>
  <article class='emb' ...attributes>
    <header class='eh'>
      {{#if (has-block 'mark')}}<span class='eh-mark'>{{yield
            to='mark'
          }}</span>{{/if}}
      <span class='eh-t'>
        <strong class='eh-title'>{{@title}}</strong>
        {{#if @meta}}<span class='eh-meta'>{{@meta}}</span>{{/if}}
      </span>
      {{#if (has-block 'aside')}}<span class='eh-aside'>{{yield
            to='aside'
          }}</span>{{/if}}
    </header>
    {{yield}}
  </article>
  <style scoped>
    @layer PretComponent {
      .emb {
        container-type: inline-size;
        min-width: 0;
        font-family: var(--font-sans);
        font-size: 0.75rem;
        line-height: 1.35;
        color: var(--card-foreground);
      }
      .eh {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        padding: 0.4375rem 0.625rem;
        min-width: 0;
      }
      .eh-mark {
        --pretui-avatar-size: 1.5rem;
        --position-mark-size: 1.5rem;
        --meeting-mark-size: 1.5rem;
        --pto-mark-size: 1.5rem;
        --review-mark-size: 1.5rem;
        --review-mark-font-size: 0.5625rem;
        --pto-mark-font-size: 0.5625rem;
        --meeting-mark-font-size: 0.5625rem;
        flex: none;
        display: inline-flex;
      }
      .eh-t {
        flex: 1;
        min-width: 0;
      }
      .eh-title,
      .eh-meta {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .eh-title {
        font-weight: 700;
      }
      .eh-meta {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .eh-aside {
        flex: none;
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
      }
    }
  </style>
</template>;

interface FitCardSignature {
  Args: { title?: string | null };
  Blocks: { mark: []; status: []; default: [] };
  Element: HTMLElement;
}

/** Fitted: a 30px head (mark, name, status at 250+ wide), then 28px rows.
 *  The body is a wrapping column: a row that does not fit wraps into a
 *  second column outside the tile, so a row is shown whole or not at all. */
export const FitCard: TemplateOnlyComponent<FitCardSignature> = <template>
  <article class='fx' ...attributes>
    <header class='fh'>
      {{#if (has-block 'mark')}}<span class='fh-mark'>{{yield
            to='mark'
          }}</span>{{/if}}
      <strong class='fh-n'>{{@title}}</strong>
      {{#if (has-block 'status')}}<span class='fh-st'>{{yield
            to='status'
          }}</span>{{/if}}
    </header>
    <div class='fx-body'>
      {{! a first line never wraps its first item; this empty one takes that
        place so a too-tall row wraps out of sight instead of being cut }}
      <span class='fx-first' aria-hidden='true'></span>
      {{#if (has-block 'status')}}<div class='fr fr-st'>{{yield
            to='status'
          }}</div>{{/if}}
      {{yield}}
    </div>
  </article>
  <style scoped>
    @layer PretComponent {
      .fx {
        display: flex;
        flex-direction: column;
        block-size: 100%;
        overflow: hidden;
        font-family: var(--font-sans);
        font-size: 0.75rem;
        line-height: 1.35;
        color: var(--card-foreground);
      }
      .fh {
        flex: none;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        block-size: 1.875rem;
        padding: 0 0.625rem;
        min-width: 0;
      }
      .fh-mark {
        --pretui-avatar-size: 1.25rem;
        --position-mark-size: 1.25rem;
        --meeting-mark-size: 1.25rem;
        --pto-mark-size: 1.25rem;
        --review-mark-size: 1.25rem;
        --review-mark-font-size: 0.5625rem;
        --pto-mark-font-size: 0.5625rem;
        --meeting-mark-font-size: 0.5625rem;
        flex: none;
        display: inline-flex;
      }
      .fh-n {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-weight: 700;
      }
      .fh-st {
        flex: none;
        display: none;
      }
      .fx-body {
        flex: 1;
        min-height: 0;
        display: flex;
        flex-flow: column wrap;
        align-content: flex-start;
        overflow: hidden;
      }
      .fx-first {
        block-size: 0;
      }
      .fr-st {
        inline-size: 100%;
        flex: none;
        display: flex;
        align-items: center;
        box-sizing: border-box;
        block-size: 1.75rem;
        padding: 0 0.625rem;
        border-top: 1px solid var(--border);
        overflow: hidden;
      }
      @container fitted-card (width >= 250px) {
        .fh-st {
          display: inline-flex;
        }
        .fr-st {
          display: none;
        }
      }
    }
  </style>
</template>;

interface FitRowSignature {
  Args: { label?: string; left?: boolean };
  Blocks: { default: [] };
  Element: HTMLElement;
}

/** One fitted row: mono caps label and a right-aligned value; under 250
 *  wide the label drops and the value reads left. */
export const FitRow: TemplateOnlyComponent<FitRowSignature> = <template>
  <div class='fr' data-left={{if @left 'true'}} ...attributes>
    {{#if @label}}<span class='fr-k'>{{@label}}</span>{{/if}}
    <span class='fr-v'>{{yield}}</span>
  </div>
  <style scoped>
    @layer PretComponent {
      .fr {
        inline-size: 100%;
        flex: none;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        box-sizing: border-box;
        block-size: 1.75rem;
        padding: 0 0.625rem;
        border-top: 1px solid var(--border);
        min-width: 0;
        overflow: hidden;
        white-space: nowrap;
      }
      .fr-k {
        flex: none;
        font: 600 0.5625rem / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      .fr-v {
        flex: 1;
        min-width: 0;
        display: flex;
        justify-content: flex-end;
        align-items: center;
        gap: 0.375rem;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .fr[data-left] .fr-v {
        justify-content: flex-start;
      }
      @container fitted-card (width < 250px) {
        .fr-k {
          display: none;
        }
        .fr-v {
          justify-content: flex-start;
        }
      }
    }
  </style>
</template>;

/** Descriptions-style items ({ label, value }) as KeyValue rows. */
export function kv(items: SheetItem[]): { key: string; value: string }[] {
  return items.map((i) => ({
    key: String(i.label ?? i.key ?? ''),
    value: i.value == null || i.value === '' ? '—' : String(i.value),
  }));
}
