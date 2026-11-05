// Pretui — FilterSet: a saved set of filters over a resource.
import Component from '@glimmer/component';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { Button } from './button';
import { IconButton } from './icon-button';
import { Tooltip } from './tooltip';
import { Token } from './token';
import {
  AddIcon,
  FunnelIcon,
  PencilIcon,
  RemoveIcon,
  conditionSummary,
  conditionToBxl,
} from '../internal/forms-expression';
import type {
  ExpressionCondition,
  ExpressionLogic,
  ExpressionOperator,
  ExpressionResource,
} from '../internal/forms-expression';

// ── FilterSet ────────────────────────────────────────────────────────────

interface FilterEntry {
  id: string;
  number: number;
  summary: string;
  joiner?: string;
  active: boolean;
  incomplete: boolean;
  editLabel: string;
  removeLabel: string;
}

export interface FilterSetSignature {
  Args: {
    /** Rows to summarise. Read-only here — editing happens elsewhere. */
    conditions: ExpressionCondition[];
    /** Joiner shown between entries. Default `all`. */
    logic?: ExpressionLogic;
    /** Custom-logic string, echoed verbatim when `@logic` is `custom`. */
    customLogic?: string;
    /** Resource catalogue, so summaries read with field LABELS not paths. */
    resources?: ExpressionResource[];
    /** Operator catalogue fallback. */
    operators?: ExpressionOperator[];
    /** Heading. Default `Conditions`. */
    title?: string;
    /** Highlighted row — the one open in the editor beside this list. */
    activeId?: string;
    /** Shows an edit control per row when supplied. */
    onEdit?: (id: string) => void;
    /** Shows a remove control per row when supplied. */
    onRemove?: (id: string) => void;
    /** Shows the add button when supplied. */
    onAdd?: () => void;
  };
  Blocks: { footer: [] };
  Element: HTMLElement;
}

/**
 * The narrow, read-only face of the same model — SLDS's `filters/` variant
 * (`slds-filters`, `slds-filters__item`), the sidebar you get beside a list
 * view where each condition collapses to one line of prose.
 *
 * Better than the inspiration: SLDS's filter item is a `<div>` with a click
 * handler and the joiner ("AND") is a decorative `<strong>` that assistive
 * tech reads as a stray word between two items. Here every entry is a real
 * list item, the joiner is `aria-hidden` chrome with the relationship carried
 * by the list's accessible name instead, and the edit control is the button —
 * so the summary can be truncated without stealing the click target.
 *
 * Dropped: the `slds-is-new` / `slds-is-locked` item states, and the nested
 * `slds-filters__group` — this list is flat for the same reason the builder
 * is.
 */
export class FilterSet extends Component<FilterSetSignature> {
  get logic(): ExpressionLogic {
    return this.args.logic ?? 'all';
  }
  get title() {
    return this.args.title ?? 'Conditions';
  }
  get joinerWord() {
    return this.logic === 'any' ? 'OR' : 'AND';
  }
  get isCustom() {
    return this.logic === 'custom';
  }
  get isAlways() {
    return this.logic === 'always';
  }
  get listLabel() {
    let count = this.args.conditions.length;
    if (this.isCustom) {
      return `${this.title}, ${count} in total, combined by custom logic ${this.args.customLogic ?? ''}`;
    }
    if (this.isAlways) {
      return `${this.title}, always true`;
    }
    return `${this.title}, ${count} in total, ${this.logic === 'any' ? 'any' : 'all'} must be met`;
  }
  get entries(): FilterEntry[] {
    return this.args.conditions.map((condition, index) => {
      let summary = conditionSummary(
        condition,
        this.args.resources ?? [],
        this.args.operators,
      );
      return {
        id: condition.id,
        number: index + 1,
        summary,
        joiner: index === 0 ? undefined : this.joinerWord,
        active: this.args.activeId === condition.id,
        incomplete:
          conditionToBxl(
            condition,
            this.args.resources ?? [],
            this.args.operators,
          ) === '',
        editLabel: `Edit condition ${index + 1}, ${summary}`,
        removeLabel: `Remove condition ${index + 1}, ${summary}`,
      };
    });
  }

  <template>
    <section class='pretui-filterset' data-test-pretui-filter-set ...attributes>
      <header class='fs-head'>
        <FunnelIcon class='fs-icon' />
        <h3 class='fs-title'>{{this.title}}</h3>
      </header>

      {{#if this.isCustom}}
        <p class='fs-custom'>
          <span class='pretui-sr'>Custom logic:</span>
          <Token @value={{@customLogic}} />
        </p>
      {{/if}}

      {{#if this.isAlways}}
        <p class='fs-always'>No conditions — this always applies.</p>
      {{else}}
        {{! role restates list semantics that list-style: none strips in Safari }}
        {{! template-lint-disable no-redundant-role }}
        <ol class='fs-list' role='list' aria-label={{this.listLabel}}>
          {{#each this.entries key='id' as |entry|}}
            <li
              class='fs-item'
              data-active={{if entry.active 'true'}}
              data-incomplete={{if entry.incomplete 'true'}}
            >
              {{#if entry.joiner}}
                <span
                  class='fs-joiner'
                  aria-hidden='true'
                >{{entry.joiner}}</span>
              {{/if}}
              <span class='fs-num' aria-hidden='true'>{{entry.number}}</span>
              <span
                class='fs-summary'
                title={{entry.summary}}
              >{{entry.summary}}</span>
              <span class='fs-tools'>
                {{#if @onEdit}}
                  <Tooltip @content={{entry.summary}} @side='left'>
                    <IconButton
                      @label={{entry.editLabel}}
                      @variant='ghost'
                      {{on 'click' (fn @onEdit entry.id)}}
                      data-test-pretui-filter-edit={{entry.number}}
                    ><PencilIcon class='fs-icon' /></IconButton>
                  </Tooltip>
                {{/if}}
                {{#if @onRemove}}
                  <IconButton
                    @label={{entry.removeLabel}}
                    @variant='ghost'
                    {{on 'click' (fn @onRemove entry.id)}}
                    data-test-pretui-filter-remove={{entry.number}}
                  ><RemoveIcon class='fs-icon' /></IconButton>
                {{/if}}
              </span>
            </li>
          {{/each}}
        </ol>
      {{/if}}

      {{#if @onAdd}}
        <div class='fs-foot'>
          <Button
            @variant='secondary'
            {{on 'click' @onAdd}}
            data-test-pretui-filter-add
          >
            <AddIcon class='fs-icon' />Add condition
          </Button>
          {{yield to='footer'}}
        </div>
      {{else if (has-block 'footer')}}
        <div class='fs-foot'>{{yield to='footer'}}</div>
      {{/if}}

    </section>
    <style scoped>
      @layer PretComponent {
        .pretui-filterset {
          container-type: inline-size;
          display: block;
          color: var(--foreground);
          font-size: var(--boxel-font-size-xs);
        }
        .pretui-sr {
          position: absolute;
          width: 1px;
          height: 1px;
          overflow: hidden;
          clip: rect(0 0 0 0);
          white-space: nowrap;
        }
        .fs-head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          margin-bottom: var(--boxel-sp-xs);
        }
        .fs-title {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        .fs-icon {
          --icon-color: currentColor;
          width: 0.8125rem;
          height: 0.8125rem;
          flex: none;
        }
        .fs-custom {
          margin: 0 0 var(--boxel-sp-xs);
        }
        .fs-always {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .fs-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .fs-item {
          position: relative;
          display: grid;
          grid-template-columns: auto minmax(0, 1fr) auto;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          padding: var(--boxel-sp-2xs) var(--boxel-sp-2xs) var(--boxel-sp-2xs)
            var(--boxel-sp-xs);
          border-radius: var(--radius);
          background: var(--card);
          box-shadow: 0 0 0 1px var(--border);
        }
        .fs-item:hover {
          background: var(--hover);
        }
        .fs-item[data-active='true'] {
          box-shadow: 0 0 0 1px var(--primary);
        }
        .fs-item[data-incomplete='true'] .fs-summary {
          color: var(--muted-foreground);
          font-style: italic;
        }
        .fs-joiner {
          position: absolute;
          top: calc(var(--boxel-sp-xs) * -1);
          left: var(--boxel-sp-xs);
          padding: 0 var(--boxel-sp-4xs);
          border-radius: var(--boxel-border-radius-xs);
          background: var(--card);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          color: var(--muted-foreground);
        }
        .fs-num {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        .fs-summary {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .fs-tools {
          display: flex;
          gap: var(--boxel-sp-6xs);
        }
        .fs-foot {
          margin-top: var(--boxel-sp-xs);
          display: flex;
          gap: var(--boxel-sp-2xs);
        }
        @container (max-width: 18rem) {
          .fs-summary {
            white-space: normal;
          }
        }
      }
    </style>
  </template>
}
