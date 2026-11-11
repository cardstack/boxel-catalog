import GlimmerComponent from '@glimmer/component';
import { Select } from '@cardstack/pretui/components/select';

interface Signature {
  Args: {
    label: string;
    value?: string;
    options: string[];
    /** Shown as the placeholder when nothing is set. */
    emptyLabel?: string;
    onChange: (value: string | undefined) => Promise<void> | void;
    disabled?: boolean;
  };
  Element: HTMLElement;
}

/**
 * A closed list of values, edited in place.
 *
 * Pret UI's `Select`, not a native `<select>`. The native one was the
 * first version and the argument for it — small fixed set, nothing to search,
 * free platform behaviour — is real but it loses the thing that matters more
 * here: every other control in this console is themed through the same
 * tokens, and a native select is the one element the theme cannot reach. A
 * priority field that renders in the OS's chrome while the picker beside it
 * renders in the app's is two systems on one row.
 *
 * Pairs with `LinkPicker`, which handles the other half of the same job — the
 * fields whose value is a card rather than a word.
 */
export class EnumSelect extends GlimmerComponent<Signature> {
  get placeholder(): string {
    return this.args.emptyLabel || 'Unset';
  }

  // Select has no clear affordance, so unsetting is the list's first option.
  get options() {
    return [
      { value: '', label: this.placeholder },
      ...this.args.options.map((o) => ({ value: o, label: o })),
    ];
  }

  change = (value: string) => {
    void this.args.onChange(value || undefined);
  };

  <template>
    <div class='es' ...attributes>
      <span class='es-label' id='es-{{@label}}'>{{@label}}</span>
      <Select
        class='es-input'
        @options={{this.options}}
        @value={{@value}}
        @onValueChange={{this.change}}
        @placeholder={{this.placeholder}}
        @disabled={{@disabled}}
        @labelledBy='es-{{@label}}'
      />
    </div>

    <style scoped>
      .es {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
        min-width: 0;
      }
      .es-label {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      /* Skinned to match LinkPicker's trigger, because they sit in the same
         column doing the same job — "change this field" — and were rendering
         as two different controls: the pickers on white with a border, these
         on the component's default grey.
         Two of the three knobs this used to set do not exist:
         `--boxel-select-border` and `--boxel-select-padding` are not names
         BoxelSelect publishes (they are `-border-color` and
         `-trigger-padding`), so the intended borderless skin never applied
         and nothing said so. A knob name that resolves to nothing is silent
         by construction — check it against the component, not against
         memory. */
      .es-input {
        --boxel-select-background-color: var(--card);
        --boxel-select-border-color: var(--border);
        --boxel-select-text-color: var(--foreground);
        --boxel-select-trigger-padding: var(--boxel-sp-5xs) var(--boxel-sp-2xs);
        --boxel-form-control-border-radius: var(--boxel-border-radius-sm);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
    </style>
  </template>
}

export default EnumSelect;
