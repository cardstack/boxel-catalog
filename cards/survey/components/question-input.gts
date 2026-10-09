import { fn } from '@ember/helper';
import { action } from '@ember/object';
import GlimmerComponent from '@glimmer/component';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Checkbox } from '@cardstack/pretui/components/checkbox';
import { Input } from '@cardstack/pretui/components/input';
import { RadioGroup } from '@cardstack/pretui/components/radio-group';
import { Rating } from '@cardstack/pretui/components/rating';
import { Textarea } from '@cardstack/pretui/components/textarea';
import type { SurveyQuestion } from '../survey-question';

interface QuestionInputSignature {
  Args: {
    question: SurveyQuestion;
    value: unknown;
    onChange: (value: unknown) => void;
    invalid?: boolean;
    /** Id of the caller's error message, read out with an invalid answer. */
    errorId?: string;
  };
  Element: HTMLElement;
}

const YES_NO = [
  { value: 'yes', label: 'Yes' },
  { value: 'no', label: 'No' },
];

export default class QuestionInput extends GlimmerComponent<QuestionInputSignature> {
  get options(): string[] {
    return (this.args.question.options as string[] | undefined) ?? [];
  }

  get choiceOptions() {
    return this.options.map((option) => ({ value: option, label: option }));
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

  get choiceValue(): string | undefined {
    return typeof this.args.value === 'string' ? this.args.value : undefined;
  }

  get yesNoValue(): string | undefined {
    return this.args.value === true
      ? 'yes'
      : this.args.value === false
        ? 'no'
        : undefined;
  }

  get label(): string {
    return this.args.question.prompt || 'Your answer';
  }

  isChecked = (option: string): boolean => {
    return this.selectedMulti.includes(option);
  };

  @action
  toggleMulti(option: string, checked: boolean) {
    let current = this.selectedMulti.filter((o) => o !== option);
    this.args.onChange(checked ? [...current, option] : current);
  }

  @action
  setYesNo(value: string) {
    this.args.onChange(value === 'yes');
  }

  @action
  setRating(value: number) {
    this.args.onChange(value || undefined);
  }

  <template>
    <div class='qi' ...attributes>
      {{#if (eq @question.kind 'long-text')}}
        <Textarea
          @value={{this.textValue}}
          @placeholder='Your answer'
          @invalid={{@invalid}}
          @onInput={{@onChange}}
          aria-label={{this.label}}
          aria-describedby={{if @invalid @errorId}}
        />

      {{else if (eq @question.kind 'single-choice')}}
        <RadioGroup
          class='qi-choices'
          @options={{this.choiceOptions}}
          @value={{this.choiceValue}}
          @onValueChange={{@onChange}}
          aria-label={{this.label}}
          aria-invalid={{if @invalid 'true'}}
          aria-describedby={{if @invalid @errorId}}
        />

      {{else if (eq @question.kind 'multi-choice')}}
        <div
          class='qi-choices'
          role='group'
          aria-label={{this.label}}
          aria-invalid={{if @invalid 'true'}}
          aria-describedby={{if @invalid @errorId}}
        >
          {{#each this.options as |option|}}
            <Checkbox
              @label={{option}}
              @checked={{this.isChecked option}}
              @onCheckedChange={{fn this.toggleMulti option}}
            />
          {{/each}}
        </div>

      {{else if (eq @question.kind 'rating')}}
        <Rating
          @value={{this.ratingValue}}
          @max={{5}}
          @label={{this.label}}
          @onValueChange={{this.setRating}}
          aria-invalid={{if @invalid 'true'}}
          aria-describedby={{if @invalid @errorId}}
        />

      {{else if (eq @question.kind 'yes-no')}}
        <RadioGroup
          class='qi-choices qi-yesno'
          @options={{YES_NO}}
          @value={{this.yesNoValue}}
          @onValueChange={{this.setYesNo}}
          aria-label={{this.label}}
          aria-invalid={{if @invalid 'true'}}
          aria-describedby={{if @invalid @errorId}}
        />

      {{else}}
        <Input
          @value={{this.textValue}}
          @placeholder='Your answer'
          @invalid={{@invalid}}
          @onInput={{@onChange}}
          aria-label={{this.label}}
          aria-describedby={{if @invalid @errorId}}
        />
      {{/if}}
    </div>

    <style scoped>
      .qi-choices {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .qi-yesno {
        grid-auto-flow: column;
        justify-content: start;
        gap: var(--boxel-sp);
      }
    </style>
  </template>
}
