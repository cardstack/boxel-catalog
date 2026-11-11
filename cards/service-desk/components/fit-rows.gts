import type { TemplateOnlyComponent } from '@ember/component/template-only';
import type { KeyValueItem } from '@cardstack/pretui/components/key-value';

interface TypeMarkSignature {
  Args: { label: string; size?: 'sm' };
}
// the record's type mark, not a person: a square, not an Avatar
export const TypeMark: TemplateOnlyComponent<TypeMarkSignature> = <template>
  <span
    class='case-mark'
    data-size={{@size}}
    aria-hidden='true'
  >{{@label}}</span>
  <style scoped>
    @layer PretComponent {
      .case-mark {
        display: inline-grid;
        flex: none;
        place-items: center;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border-radius: var(--radius);
        background: var(--muted);
        color: var(--card-foreground);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      .case-mark[data-size='sm'] {
        inline-size: 1.25rem;
        block-size: 1.25rem;
      }
    }
  </style>
</template>;

interface FitRowsSignature {
  Args: { items: KeyValueItem[] };
  Blocks: { tile: []; row: [item: KeyValueItem] };
}
// The fitted layout the service-desk records share: the FitTile on top, then
// ruled key-value rows ranked by priority; a row that doesn't fit drops whole.
export const FitRows: TemplateOnlyComponent<FitRowsSignature> = <template>
  <div class='fit'>
    <div class='fit-tile'>{{yield to='tile'}}</div>
    <dl class='fit-rows'>
      {{#each @items as |item|}}
        <div class='fit-row'>
          <dt>{{item.key}}</dt>
          <dd>{{yield item to='row'}}</dd>
        </div>
      {{/each}}
    </dl>
  </div>
  <style scoped>
    @layer PretComponent {
      .fit {
        display: flex;
        flex-direction: column;
        block-size: 100%;
        overflow: hidden;
        background: var(--card);
        color: var(--card-foreground);
      }
      .fit-tile {
        flex: none;
      }
      /* a column of whole rows: a row that doesn't fit wraps into the
         next column, which starts past the right edge, so it is never
         half-cut */
      .fit-rows {
        flex: 1 1 0;
        min-block-size: 0;
        display: flex;
        flex-direction: column;
        flex-wrap: wrap;
        align-content: flex-start;
        column-gap: var(--boxel-sp-xl);
        margin: 0;
        margin-block-start: calc(-1 * var(--boxel-sp-xs));
        padding: 0 var(--boxel-sp-sm);
        overflow: hidden;
        font-size: var(--boxel-font-size-xs);
      }
      .fit-row {
        box-sizing: border-box;
        display: grid;
        grid-template-columns: 5rem minmax(0, 1fr);
        align-items: center;
        gap: var(--boxel-sp-xs);
        inline-size: 100%;
        block-size: 1.75rem;
        border-top: 1px solid var(--border);
        white-space: nowrap;
      }
      .fit-row dt {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs, var(--boxel-font-size-xs));
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .fit-row dd {
        display: flex;
        align-items: center;
        min-inline-size: 0;
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      @container fitted-card (width >= 400px) {
        .fit-row {
          grid-template-columns: 7rem minmax(0, 1fr);
        }
      }
      /* under 250 wide the value needs the line, its label goes */
      @container fitted-card (width < 250px) {
        .fit-row {
          grid-template-columns: minmax(0, 1fr);
        }
        .fit-row dt {
          display: none;
        }
      }
      /* the tile's own lines fill short tiles: no rows */
      @container fitted-card (height < 105px) {
        .fit-rows {
          display: none;
        }
      }
      @container fitted-card (height < 170px) and (width < 400px) {
        .fit-rows {
          display: none;
        }
      }
    }
  </style>
</template>;

export const lowercase = (value?: string | null) => (value ?? '').toLowerCase();
