/* eslint-disable ember/no-tracked-properties-from-args -- answered arg seeds uncontrolled state once */
// Pretui — AgentQuestion: a question the agent is waiting on, answered in place.
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

export interface AgentQuestionSignature {
  Args: {
    question: string;
    options?: string[];
    answered?: string;
    onAnswer?: (answer: string) => void;
  };
  Element: HTMLDivElement;
}

// ASK verb: option pills + free answer; settles to a quiet answered line.
export class AgentQuestion extends Component<AgentQuestionSignature> {
  @tracked picked?: string = this.args.answered;
  settle = (value: string) => {
    this.picked = value;
    this.args.onAnswer?.(value);
  };
  onKey = (e: Event) => {
    let ev = e as KeyboardEvent;
    let input = ev.target as HTMLInputElement;
    if (ev.key === 'Enter' && input.value) {
      this.settle(input.value);
    }
  };
  <template>
    {{#if this.picked}}
      <div
        class='pretui-answered'
        data-test-pretui-agent-question
        ...attributes
      >
        <span class='pretui-answered-check'>✓</span>
        {{@question}}
        <b>{{this.picked}}</b>
      </div>
    {{else}}
      <div
        class='pretui-question'
        data-test-pretui-agent-question
        ...attributes
      >
        <div class='pretui-question-text'>{{@question}}</div>
        <div class='pretui-question-opts'>
          {{#each @options as |option|}}
            <button
              type='button'
              class='pretui-qpill'
              {{on 'click' (fn this.settle option)}}
            >{{option}}</button>
          {{/each}}
        </div>
        <input
          class='pretui-qinput'
          aria-label='Answer'
          placeholder='Or type an answer…'
          {{on 'keydown' this.onKey}}
        />
      </div>
    {{/if}}
    <style scoped>
      @layer PretComponent {
        .pretui-question {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .pretui-question-text {
          font-weight: 500;
        }
        .pretui-question-opts {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-2xs);
        }
        .pretui-qpill {
          display: inline-flex;
          align-items: center;
          height: 1.625rem;
          padding: 0
            calc(
              var(--boxel-sp-2xs) * var(--pretui-capsule-base, 1.35) +
                var(--boxel-sp-sm) * var(--pretui-radius-encroach, 0.35)
            );
          border-radius: var(--boxel-border-radius-lg);
          border: 0;
          background: var(--card);
          box-shadow: var(--pretui-shadow-control, 0 0 0 1px var(--border));
          font-family: inherit;
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
          cursor: pointer;
          color: var(--foreground);
        }
        .pretui-qpill:hover {
          background: var(--hover);
        }
        .pretui-qinput {
          display: flex;
          align-items: center;
          height: var(--boxel-form-control-height-sm);
          padding: 0 var(--boxel-sp-xs);
          border: 0;
          border-radius: var(--radius);
          font-family: inherit;
          font-size: var(--boxel-font-size-xs);
          color: var(--foreground);
          background: var(--field);
          box-shadow: 0 0 0 1px var(--input);
          width: 100%;
        }
        .pretui-qinput:focus {
          outline: none;
          box-shadow:
            0 0 0 2px var(--ring),
            var(--shadow-inset);
        }
        .pretui-answered {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .pretui-answered-check {
          color: var(--success);
        }
        .pretui-answered b {
          color: var(--foreground);
          font-weight: 500;
        }
      }
    </style>
  </template>
}
