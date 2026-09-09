import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { action } from '@ember/object';
import GlimmerComponent from '@glimmer/component';
import { Button, BoxelInput } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import type { SurveyQuestion } from '../survey-question';

// Plain inputs styled after boxel-surface cell-chrome.css; no surface Cell/context machinery, so the listing stays self-contained.

interface QuestionInputSignature {
  Args: {
    question: SurveyQuestion;
    value: unknown;
    onChange: (value: unknown) => void;
    autofocus?: boolean;
    invalid?: boolean;
  };
  Element: HTMLElement;
}

const RATING_SCALE = [1, 2, 3, 4, 5];

export default class QuestionInput extends GlimmerComponent<QuestionInputSignature> {
  get options(): string[] {
    return (this.args.question.options as string[] | undefined) ?? [];
  }

  get selectedMulti(): string[] {
    return Array.isArray(this.args.value) ? (this.args.value as string[]) : [];
  }

  get ratingValue(): number {
    return typeof this.args.value === 'number' ? this.args.value : 0;
  }

  get textValue(): string {
    return typeof this.args.value === 'string' ? this.args.value : '';
  }

  isChecked = (option: string): boolean => {
    return this.selectedMulti.includes(option);
  };

  isStarOn = (star: number): boolean => {
    return star <= this.ratingValue;
  };

  @action
  updateText(value: string) {
    this.args.onChange(value);
  }

  @action
  toggleMulti(option: string) {
    let current = this.selectedMulti;
    let next = current.includes(option)
      ? current.filter((o) => o !== option)
      : [...current, option];
    this.args.onChange(next);
  }

  @action
  setRating(value: number) {
    this.args.onChange(this.ratingValue === value ? 0 : value);
  }

  <template>
    <div class='qi {{if @invalid "is-invalid"}}' ...attributes>
      {{#if (eq @question.kind 'short-text')}}
        <BoxelInput
          class='qi-input'
          @type='text'
          @value={{this.textValue}}
          placeholder='Your answer'
          autofocus={{@autofocus}}
          @onInput={{this.updateText}}
        />

      {{else if (eq @question.kind 'long-text')}}
        <BoxelInput
          class='qi-input qi-textarea'
          @type='textarea'
          rows='4'
          placeholder='Your answer'
          autofocus={{@autofocus}}
          @onInput={{this.updateText}}
          @value={{this.textValue}}
        />

      {{else if (eq @question.kind 'single-choice')}}
        <div class='qi-choices' role='radiogroup'>
          {{#each this.options as |option|}}
            <Button
              @kind='text-only'
              @size='auto'
              class='qi-choice {{if (eq @value option) "is-selected"}}'
              role='radio'
              aria-checked={{if (eq @value option) 'true' 'false'}}
              {{on 'click' (fn @onChange option)}}
            >
              <span class='qi-mark qi-mark--radio'></span>
              <span class='qi-choice-label'>{{option}}</span>
            </Button>
          {{/each}}
        </div>

      {{else if (eq @question.kind 'multi-choice')}}
        <div class='qi-choices'>
          {{#each this.options as |option|}}
            <Button
              @kind='text-only'
              @size='auto'
              class='qi-choice {{if (this.isChecked option) "is-selected"}}'
              aria-pressed={{if (this.isChecked option) 'true' 'false'}}
              {{on 'click' (fn this.toggleMulti option)}}
            >
              <span class='qi-mark qi-mark--check'></span>
              <span class='qi-choice-label'>{{option}}</span>
            </Button>
          {{/each}}
        </div>

      {{else if (eq @question.kind 'rating')}}
        <div class='qi-rating' role='radiogroup'>
          {{#each RATING_SCALE as |star|}}
            <Button
              @kind='text-only'
              @size='auto'
              class='qi-star {{if (this.isStarOn star) "is-on"}}'
              aria-label='{{star}} of 5'
              {{on 'click' (fn this.setRating star)}}
            >★</Button>
          {{/each}}
        </div>

      {{else if (eq @question.kind 'yes-no')}}
        <div class='qi-yesno'>
          <Button
            @kind='text-only'
            @size='auto'
            class='qi-toggle {{if (eq @value true) "is-selected"}}'
            {{on 'click' (fn @onChange true)}}
          >Yes</Button>
          <Button
            @kind='text-only'
            @size='auto'
            class='qi-toggle {{if (eq @value false) "is-selected"}}'
            {{on 'click' (fn @onChange false)}}
          >No</Button>
        </div>

      {{else}}
        <BoxelInput
          class='qi-input'
          @type='text'
          @value={{this.textValue}}
          placeholder='Your answer'
          @onInput={{this.updateText}}
        />
      {{/if}}
    </div>

    <style scoped>
      .qi.is-invalid .qi-input,
      .qi.is-invalid .qi-mark,
      .qi.is-invalid .qi-choice,
      .qi.is-invalid .qi-toggle {
        border-color: var(--destructive);
      }
      .qi.is-invalid .qi-star {
        color: var(--destructive-ink);
      }
      .qi-input {
        width: 100%;
        box-sizing: border-box;
        min-height: var(--boxel-form-control-height);
        padding: 0.5rem 0.75rem;
        font: inherit;
        color: var(--foreground);
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        transition:
          border-color 0.15s ease,
          box-shadow 0.15s ease;
      }
      .qi-input:focus {
        outline: 0;
        border-color: var(--primary);
        box-shadow: 0 0 0 3px
          color-mix(in oklch, var(--primary) 22%, transparent);
      }
      .qi-textarea {
        resize: vertical;
        line-height: 1.45;
      }

      .qi-choices {
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
      }
      .qi-choice {
        display: flex;
        align-items: center;
        gap: 0.6rem;
        width: 100%;
        padding: 0.55rem 0.75rem;
        font: inherit;
        text-align: start;
        color: var(--foreground);
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        cursor: pointer;
        transition:
          border-color 0.15s ease,
          background 0.15s ease;
      }
      .qi-choice:hover {
        border-color: var(--primary);
      }
      .qi-choice.is-selected {
        border-color: var(--primary);
        background-color: color-mix(in oklch, var(--primary) 10%, transparent);
      }
      .qi-mark {
        flex-shrink: 0;
        width: 1.1rem;
        height: 1.1rem;
        border: 2px solid var(--border);
        background-color: var(--card);
        color: var(--card-foreground);
        position: relative;
      }
      .qi-mark--radio {
        border-radius: 50%;
      }
      .qi-mark--check {
        border-radius: 0.3rem;
      }
      .qi-choice.is-selected .qi-mark {
        border-color: var(--primary);
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .qi-choice.is-selected .qi-mark::after {
        content: '';
        position: absolute;
        inset: 0;
        margin: auto;
      }
      .qi-choice.is-selected .qi-mark--radio::after {
        width: 0.45rem;
        height: 0.45rem;
        border-radius: 50%;
        background-color: var(--card);
        color: var(--card-foreground);
      }
      .qi-choice.is-selected .qi-mark--check::after {
        width: 0.28rem;
        height: 0.55rem;
        border: solid var(--border);
        border-width: 0 2px 2px 0;
        transform: translateY(-1px) rotate(45deg);
      }

      .qi-rating {
        display: inline-flex;
        gap: 0.25rem;
      }
      .qi-star {
        font-size: 1.6rem;
        line-height: 1;
        padding: 0.1rem;
        background: none;
        border: none;
        cursor: pointer;
        color: var(--subtle-foreground);
        transition: color 0.12s ease;
      }
      .qi-star.is-on {
        color: var(--warning-ink);
      }

      .qi-yesno {
        display: inline-flex;
        gap: 0.5rem;
      }
      .qi-toggle {
        min-width: 4.5rem;
        min-height: var(--boxel-form-control-height);
        padding-inline: 1rem;
        font: inherit;
        font-weight: 600;
        color: var(--foreground);
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        cursor: pointer;
        transition:
          border-color 0.15s ease,
          background 0.15s ease;
      }
      .qi-toggle.is-selected {
        border-color: var(--primary);
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
    </style>
  </template>
}
