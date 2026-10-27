// Pretui — Board: a kanban plane, a thin wrap of boxel-ui KanbanPlane.
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { KanbanPlane as BoxelKanbanPlane } from '@cardstack/boxel-ui/components';
import type {
  KanbanColumnConfig,
  KanbanPlacement,
} from '@cardstack/boxel-ui/components';
import type { FittedFormatId } from '@cardstack/boxel-ui/helpers';

// ── Board — WRAPS boxel-ui ───────────────────────────────────────────────
// boxel-ui's KanbanPlane — the newer of its two kanbans, chosen per the
// matrix ("adopt the newer pure-fn placement engine"): an internally
// owned drag manager over pure placement functions, configurable columns
// (KanbanColumnConfig: key/label/color/wipLimit/collapsed/sortOrder),
// card placements as data (KanbanPlacement: columnId/index/sortOrder), a
// hidden-columns tray, and per-lane add-card affordances. The consumer
// renders cards through <:card>/<:ghost> blocks and owns all state —
// every interaction arrives as a callback. The wrapper routes the engine's
// --boxel-kanban-* channel onto the theme contract tokens. Column config UI
// (KanbanColumnConfigSidebar) is a separate boxel-ui component, not part of
// this wrap.
//
// NOT GENERIC, deliberately — the one collection in the kit that keeps a
// closed row type, and the reason is worth writing down. A KanbanPlacement is
// `{ columnId, index, sortOrder }`: a POSITION, not a record. The card
// payload never passes through the board at all — the consumer looks it up by
// `placement.index` — and boxel-ui's pure placement engine both clones
// (`placements.map((p) => ({ ...p }))`) and MANUFACTURES placements
// (`autoPlaceKanban`), so a `T extends KanbanPlacement` yielded from <:card>
// would be a cast the engine is under no obligation to honour. Typing a lie
// is worse than typing a position. Grid/Feed/Masonry are generic because
// their items are the caller's own rows, passed straight through.

export interface BoardSignature {
  Args: {
    columns: KanbanColumnConfig[];
    placements: KanbanPlacement[];
    /** accessible board label */
    boardLabel?: string;
    /** fitted format id for card sizing — 'regular-tile' by default */
    cardSize?: FittedFormatId;
    /** move empty columns into the hidden-columns tray */
    hideEmpty?: boolean;
    onChange?: (placements: KanbanPlacement[]) => void;
    onSelect?: (index: number | null) => void;
    onOpen?: (index: number) => void;
    onAddCard?: (columnKey: string | null) => void;
    onToggleCollapsed?: (column: KanbanColumnConfig | null) => void;
  };
  Blocks: {
    card: [KanbanPlacement];
    ghost: [number];
  };
  Element: HTMLDivElement;
}

export const Board: TemplateOnlyComponent<BoardSignature> = <template>
  <div class='pretui-board' data-test-pretui-board ...attributes>
    <BoxelKanbanPlane
      @boardLabel={{@boardLabel}}
      @columns={{@columns}}
      @placements={{@placements}}
      @cardSize={{@cardSize}}
      @hideEmpty={{@hideEmpty}}
      @onChange={{@onChange}}
      @onSelect={{@onSelect}}
      @onOpen={{@onOpen}}
      @onAddCard={{@onAddCard}}
      @onToggleCollapsed={{@onToggleCollapsed}}
    >
      <:card as |placement|>
        {{yield placement to='card'}}
      </:card>
      <:ghost as |dragIndex|>
        {{yield dragIndex to='ghost'}}
      </:ghost>
    </BoxelKanbanPlane>
  </div>
  <style scoped>
    @layer PretComponent {
      /* The plane fills its host, so the wrapping context needs a height.
         Channel values read the theme contract tokens directly. */
      .pretui-board {
        height: 100%;
        min-height: 0;
        font-size: var(--boxel-font-size-xs);
        letter-spacing: normal;
        color: var(--foreground);
        --boxel-kanban-fg: var(--foreground);
        --boxel-kanban-card-bg: var(--card);
        --boxel-kanban-card-fg: var(--card-foreground);
        --boxel-kanban-col-bg: var(--inset);
        --boxel-kanban-col-fg: var(--foreground);
        --boxel-kanban-ring: var(--ring);
        --boxel-kanban-primary: var(--primary);
        --boxel-kanban-primary-fg: var(--primary-foreground);
        --boxel-kanban-destructive: var(--destructive);
        --boxel-kanban-destructive-fg: var(--destructive-foreground);
        --boxel-kanban-muted-fg: var(--muted-foreground);
        --boxel-kanban-radius: var(--radius);
        --boxel-kanban-border: var(--border);
        --boxel-kanban-bg: transparent;
        /* the board sits flush with its section; lanes one --boxel-sp-sm apart */
        --boxel-kanban-padding: 0;
        --boxel-kanban-gap: var(--boxel-sp-sm);
      }
    }
  </style>
</template>;
