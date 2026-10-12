import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Input } from '@cardstack/pretui/components/input';

export interface QuestionValue {
  selectedKeys: string[];
  text?: string;
}

interface Option {
  label?: string;
  value?: string;
  key?: string;
  isCorrect?: boolean;
  feedback?: string;
}

interface Question {
  prompt?: string;
  kind?: string;
  options?: Option[];
  points?: number;
  explanation?: string;
}

interface Signature {
  Args: {
    question: Question;
    index: number;
    value?: QuestionValue;
    onChange: (value: QuestionValue) => void;
    disabled?: boolean;
    /** After submission: reveal correct options and the explanation. */
    reveal?: boolean;
    /** Unique id for the input group; defaults to the index. */
    groupId?: string;
  };
  Element: HTMLElement;
}

/**
 * One quiz question with the right control for its kind, one value out.
 * Single choice and true/false are radio groups; multiple choice is a
 * checkbox group; short text is a text field. It reads Choice Option fields
 * and never scores; the quiz scores with `scoreAnswer`. After submission,
 * `@reveal` marks each option correct or wrong.
 *
 * The survey's Question Input is a different component: it reads the survey's
 * question model (rating scales, matrix rows) and has no answer key.
 */
export class QuizQuestionInput extends GlimmerComponent<Signature> {
  get value(): QuestionValue {
    return this.args.value ?? { selectedKeys: [] };
  }

  get kind() {
    return this.args.question?.kind ?? 'single';
  }

  get isMulti() {
    return this.kind === 'multiple';
  }

  get isText() {
    return this.kind === 'short_text';
  }

  get name() {
    return `q-${this.args.groupId ?? this.args.index}`;
  }

  get options(): {
    key: string;
    label: string;
    isCorrect?: boolean;
    feedback?: string;
  }[] {
    let opts = (this.args.question?.options ?? []).filter(
      (o) => o && (o.label || o.value),
    );
    if (this.kind === 'true_false' && !opts.length) {
      return [
        { key: 'true', label: 'True' },
        { key: 'false', label: 'False' },
      ];
    }
    return opts.map((o) => ({
      key: (o.key || o.value || o.label || '').toLowerCase(),
      label: o.label ?? o.value ?? '',
      isCorrect: o.isCorrect,
      feedback: o.feedback,
    }));
  }

  isChecked = (key: string) => this.value.selectedKeys.includes(key);

  pick = (key: string) => {
    if (this.args.disabled) return;
    if (this.isMulti) {
      let set = new Set(this.value.selectedKeys);
      if (set.has(key)) set.delete(key);
      else set.add(key);
      this.args.onChange({ ...this.value, selectedKeys: [...set] });
    } else {
      this.args.onChange({ ...this.value, selectedKeys: [key] });
    }
  };

  setText = (text: string) => {
    if (this.args.disabled) return;
    this.args.onChange({ ...this.value, text });
  };

  optionClass = (o: { key: string; isCorrect?: boolean }) => {
    let chosen = this.isChecked(o.key);
    if (!this.args.reveal) return chosen ? 'chosen' : '';
    if (o.isCorrect) return 'correct';
    if (chosen) return 'wrong';
    return '';
  };

  <template>
    <fieldset class='qi' disabled={{@disabled}} ...attributes>
      <legend class='qi-legend'>
        <span class='qi-n'>{{inc @index}}</span>
        <span class='qi-prompt'>{{stripMd @question.prompt}}</span>
        <span class='qi-pts'>{{if @question.points @question.points 1}}
          pt{{if (isPlural @question.points) 's'}}</span>
      </legend>

      {{#if this.isText}}
        <div class='qi-text'>
          <Input
            @value={{this.value.text}}
            @onInput={{this.setText}}
            @disabled={{@disabled}}
            @placeholder='Type your answer'
            aria-label='Answer to question {{inc @index}}'
          />
        </div>
      {{else}}
        <ul
          class='qi-opts {{if this.isMulti "multi"}}'
          role={{if this.isMulti 'group' 'radiogroup'}}
        >
          {{#each this.options as |o|}}
            <li class='qi-opt {{this.optionClass o}}'>
              <label>
                <input
                  type={{if this.isMulti 'checkbox' 'radio'}}
                  name={{this.name}}
                  value={{o.key}}
                  checked={{this.isChecked o.key}}
                  disabled={{@disabled}}
                  {{on 'change' (fn this.pick o.key)}}
                />
                <span class='qi-label'>{{o.label}}</span>
                {{#if @reveal}}
                  {{#if o.isCorrect}}<span
                      class='qi-tag ok'
                    >correct</span>{{/if}}
                  {{#if (and (this.isChecked o.key) (not o.isCorrect))}}<span
                      class='qi-tag no'
                    >your answer</span>{{/if}}
                {{/if}}
              </label>
              {{#if (and @reveal o.feedback (this.isChecked o.key))}}
                <p class='qi-fb'>{{o.feedback}}</p>
              {{/if}}
            </li>
          {{/each}}
        </ul>
        {{#if this.isMulti}}<p class='qi-hint'>Select all that apply.</p>{{/if}}
      {{/if}}

      {{#if (and @reveal @question.explanation)}}
        <p class='qi-expl'>{{stripMd @question.explanation}}</p>
      {{/if}}
    </fieldset>
    <style scoped>
      .qi {
        margin: 0;
        padding: 0;
        border: 0;
        min-width: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
        color: var(--foreground);
      }
      .qi-legend {
        display: grid;
        grid-template-columns: auto 1fr auto;
        gap: var(--boxel-sp-xs);
        align-items: baseline;
        padding: 0;
        margin-bottom: var(--boxel-sp-xs);
        width: 100%;
      }
      .qi-n {
        width: 1.5rem;
        height: 1.5rem;
        display: grid;
        place-items: center;
        border-radius: 50%;
        background: color-mix(in oklab, var(--primary) 14%, var(--card));
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .qi-prompt {
        font-weight: 600;
        line-height: 1.4;
      }
      .qi-pts {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .qi-opts {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .qi-opt label {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        cursor: pointer;
        transition:
          border-color 120ms ease,
          background 120ms ease;
      }
      .qi:disabled .qi-opt label {
        cursor: default;
      }
      .qi-opt label:hover {
        border-color: var(--primary);
      }
      .qi-opt input {
        accent-color: var(--primary);
        margin: 0;
      }
      .qi-opt input:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .qi-opt.chosen label {
        border-color: var(--primary);
        background: color-mix(in oklab, var(--primary) 8%, var(--card));
      }
      .qi-opt.correct label {
        border-color: var(--success);
        background: color-mix(in oklab, var(--success) 10%, var(--card));
      }
      .qi-opt.wrong label {
        border-color: var(--destructive);
        background: color-mix(in oklab, var(--destructive) 8%, var(--card));
      }
      .qi-label {
        flex: 1;
      }
      .qi-tag {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .qi-tag.ok {
        color: var(--success-ink);
      }
      .qi-tag.no {
        color: var(--destructive-ink);
      }
      .qi-fb,
      .qi-hint,
      .qi-expl {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .qi-fb {
        padding-left: var(--boxel-sp-sm);
      }
      .qi-expl {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-left: 0.1875rem solid var(--border);
      }
    </style>
  </template>
}

function inc(i: number) {
  return i + 1;
}

function isPlural(n?: number | null) {
  return n != null && n !== 1;
}

function stripMd(s?: string | null) {
  return (s ?? '').replace(/[#*_>`]/g, '');
}

function and(...args: unknown[]) {
  return args.every(Boolean);
}

function not(v: unknown) {
  return !v;
}

export default QuizQuestionInput;
