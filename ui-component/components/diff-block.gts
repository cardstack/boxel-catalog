// Pretui — DiffBlock: a before/after change rendered as a line diff.
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

export interface DiffLine {
  op?: 'add' | 'del';
  text: string;
}

export interface DiffBlockSignature {
  Args: { lines: DiffLine[]; receipt?: string; maxLines?: number };
  Element: HTMLDivElement;
}

// Staged change with an immutable receipt line; long diffs collapse.
export class DiffBlock extends Component<DiffBlockSignature> {
  @tracked collapsed = true;
  get maxLines() {
    return this.args.maxLines ?? 8;
  }
  get overflows() {
    return this.args.lines.length > this.maxLines;
  }
  get shown() {
    return this.collapsed && this.overflows
      ? this.args.lines.slice(0, this.maxLines)
      : this.args.lines;
  }
  get toggleLabel() {
    return this.collapsed
      ? `… ${this.args.lines.length - this.maxLines} more lines`
      : 'collapse';
  }
  prefix = (line: DiffLine) =>
    line.op === 'add' ? '+ ' : line.op === 'del' ? '- ' : '  ';
  toggle = () => {
    this.collapsed = !this.collapsed;
  };
  <template>
    <div class='pretui-diff' data-test-pretui-diff-block ...attributes>
      {{#each this.shown as |line|}}
        <div class='pretui-diff-line' data-op={{line.op}}>{{this.prefix
            line
          }}{{line.text}}</div>
      {{/each}}
      {{#if this.overflows}}
        <button
          type='button'
          class='pretui-diff-line pretui-diff-toggle'
          {{on 'click' this.toggle}}
        >{{this.toggleLabel}}</button>
      {{/if}}
      {{#if @receipt}}<div class='pretui-diff-receipt'>{{@receipt}}</div>{{/if}}
    </div>
    <style scoped>
      @layer PretComponent {
        .pretui-diff {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.7;
          background: var(--inset);
          border-radius: var(--boxel-border-radius-sm);
          box-shadow: 0 0 0 1px var(--border);
          overflow: hidden;
        }
        .pretui-diff-line {
          padding: 0 var(--boxel-sp-xs);
          white-space: pre;
        }
        .pretui-diff-line[data-op='add'] {
          background: color-mix(in oklch, var(--success) 12%, transparent);
          color: color-mix(in oklch, var(--foreground) 30%, var(--success));
        }
        .pretui-diff-line[data-op='del'] {
          background: color-mix(in oklch, var(--destructive) 10%, transparent);
          color: color-mix(in oklch, var(--foreground) 30%, var(--destructive));
        }
        .pretui-diff-toggle {
          display: block;
          width: 100%;
          text-align: left;
          border: 0;
          background: none;
          font-family: inherit;
          color: var(--pretui-primary-ink, var(--primary));
          cursor: pointer;
        }
        .pretui-diff-receipt {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-2xs);
          color: var(--subtle-foreground);
          box-shadow: 0 -1px 0 var(--border);
        }
      }
    </style>
  </template>
}
