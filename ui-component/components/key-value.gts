// Pretui — KeyValue: read-only labeled values in a definition list.
import Component from '@glimmer/component';

export interface KeyValueItem {
  key: string;
  value: string;
}

export type KeyValueLayout = 'horizontal' | 'stacked' | 'inline';

export interface KeyValueSignature {
  Args: {
    items: KeyValueItem[];
    /** 'horizontal' (default): keys in one column, values beside them.
     *  'stacked': each key above its value. 'inline': pairs side by side,
     *  wrapping onto the next line. 'vertical' is an alias of 'stacked'. */
    layout?: KeyValueLayout | 'vertical';
    /** 'eyebrow' sets the keys in the theme's eyebrow role (uppercase,
     *  tracked out). Default 'default'. */
    labelStyle?: 'default' | 'eyebrow';
    /** 'ruled' right-aligns the values and draws a --border line between
     *  rows. Default 'plain'. Only the 'horizontal' layout takes it; the
     *  other layouts ignore it. */
    rows?: 'plain' | 'ruled';
  };
  Blocks: { value: [item: KeyValueItem] };
  Element: HTMLDListElement;
}

export class KeyValue extends Component<KeyValueSignature> {
  get layout(): KeyValueLayout {
    let { layout } = this.args;
    if (layout === 'stacked' || layout === 'vertical') {
      return 'stacked';
    }
    return layout === 'inline' ? 'inline' : 'horizontal';
  }
  get isInline(): boolean {
    return this.layout === 'inline';
  }
  get labelStyle(): 'eyebrow' | undefined {
    return this.args.labelStyle === 'eyebrow' ? 'eyebrow' : undefined;
  }
  get rows(): 'ruled' | undefined {
    return this.args.rows === 'ruled' && this.layout === 'horizontal'
      ? 'ruled'
      : undefined;
  }
  <template>
    <dl
      class='pretui-kv'
      data-layout={{this.layout}}
      data-rows={{this.rows}}
      data-label-style={{this.labelStyle}}
      data-test-pretui-kv
      ...attributes
    >
      {{#if this.isInline}}
        {{! A div per pair keeps each key on the same line as its value when the strip wraps; HTML allows a div around each dt/dd group. }}
        {{#each @items as |item|}}
          <div class='pretui-kv-pair'>
            <dt>{{item.key}}</dt>
            <dd>{{#if (has-block 'value')}}{{yield
                  item
                  to='value'
                }}{{else}}{{item.value}}{{/if}}</dd>
          </div>
        {{/each}}
      {{else}}
        {{#each @items as |item|}}
          <dt>{{item.key}}</dt>
          <dd>{{#if (has-block 'value')}}{{yield
                item
                to='value'
              }}{{else}}{{item.value}}{{/if}}</dd>
        {{/each}}
      {{/if}}
    </dl>
    <style scoped>
      @layer PretComponent {
        .pretui-kv {
          display: grid;
          grid-template-columns: max-content 1fr;
          column-gap: var(--boxel-sp-lg);
          row-gap: var(--boxel-sp-xs);
          align-content: start;
          align-items: center;
          margin: 0;
        }
        /* Keys default to the theme's ui-label role; the knobs win. */
        .pretui-kv dt {
          color: var(--pretui-kv-label-color, var(--muted-foreground));
          font-family: var(
            --pretui-kv-label-font-family,
            var(--boxel-ui-label-font-family)
          );
          font-size: var(
            --pretui-kv-label-font-size,
            var(--boxel-font-size-xs)
          );
          font-weight: var(--pretui-kv-label-font-weight, 600);
          line-height: var(
            --pretui-kv-label-line-height,
            var(--boxel-ui-label-line-height)
          );
          letter-spacing: var(--pretui-kv-label-letter-spacing, normal);
          text-transform: var(--pretui-kv-label-text-transform);
        }
        /* The theme's eyebrow role. The knobs above still win. */
        .pretui-kv[data-label-style='eyebrow'] dt {
          font-family: var(
            --pretui-kv-label-font-family,
            var(--boxel-eyebrow-font-family)
          );
          font-size: var(
            --pretui-kv-label-font-size,
            var(--boxel-font-size-xs)
          );
          font-weight: var(--pretui-kv-label-font-weight, 600);
          line-height: var(
            --pretui-kv-label-line-height,
            var(--boxel-eyebrow-line-height)
          );
          letter-spacing: var(--pretui-kv-label-letter-spacing, normal);
          text-transform: var(--pretui-kv-label-text-transform, none);
        }
        .pretui-kv dd {
          margin: 0;
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        /* ruled rows: the gap moves into the cells so the line runs
           unbroken across both columns */
        .pretui-kv[data-rows='ruled'] {
          column-gap: 0;
          row-gap: 0;
          /* stretched cells, content centred inside, so both borders of a
             row sit at the same height whatever each cell's text size */
          align-items: stretch;
        }
        .pretui-kv[data-rows='ruled'] dt,
        .pretui-kv[data-rows='ruled'] dd {
          padding-block: var(--boxel-sp-xs);
        }
        .pretui-kv[data-rows='ruled'] dt {
          display: flex;
          align-items: center;
          padding-inline-end: var(--boxel-sp-lg);
        }
        .pretui-kv[data-rows='ruled'] dd {
          justify-content: flex-end;
          text-align: end;
        }
        .pretui-kv[data-rows='ruled'] dt:nth-of-type(n + 2),
        .pretui-kv[data-rows='ruled'] dd:nth-of-type(n + 2) {
          border-block-start: 1px solid var(--border);
        }
        .pretui-kv[data-layout='stacked'] {
          grid-template-columns: minmax(0, 1fr);
          row-gap: var(--boxel-sp-6xs);
        }
        .pretui-kv[data-layout='stacked'] dt:not(:first-child) {
          margin-block-start: var(--boxel-sp-xs);
        }
        .pretui-kv[data-layout='inline'] {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
        }
        .pretui-kv-pair {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-inline-size: 0;
        }
      }
    </style>
  </template>
}
