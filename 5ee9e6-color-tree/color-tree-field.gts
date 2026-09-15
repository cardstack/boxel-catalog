// =============================================================================
// ColorTreeField — a Munsell color pick as a field. Reach for it when a flat
// color picker is not enough: its edit format is the full 3D studio
// (ColorTreeStudio) bounded to the form, so a card author gets perceptual
// hue/value/chroma picking on any card with one `contains()`. The value is
// the picked hex plus its Munsell notation.
// =============================================================================
import {
  Component,
  FieldDef,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import ColorField from 'https://cardstack.com/base/color';
import PaletteIcon from '@cardstack/boxel-icons/palette';
import { Swatch } from '@cardstack/boxel-ui/components';
import { ColorTreeStudio } from './components/color-tree-studio';

export class ColorTreeField extends FieldDef {
  static displayName = 'Color Tree Pick';
  static icon = PaletteIcon;

  @field hex = contains(ColorField);
  @field munsell = contains(StringField);

  static edit = class Edit extends Component<typeof this> {
    onPick = (hex: string, notation: string) => {
      this.args.model.hex = hex;
      this.args.model.munsell = notation;
    };

    <template>
      <div class='ctf-edit' data-test-color-tree-field-edit>
        <ColorTreeStudio
          @compact={{true}}
          @color={{@model.hex}}
          @munsell={{@model.munsell}}
          @onPick={{this.onPick}}
        />
      </div>

      <style scoped>
        .ctf-edit {
          height: 26rem;
          border-radius: var(--radius);
          overflow: hidden;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='ctf-embedded' data-test-color-tree-field-embedded>
        {{#if @model.hex}}
          <Swatch
            class='ctf-swatch'
            @style='round'
            @color={{@model.hex}}
            @label={{@model.munsell}}
          />
        {{else}}
          <Swatch class='ctf-swatch' @style='round' @hideLabel={{true}} />
          <span class='munsell'>no chip picked yet</span>
        {{/if}}
      </div>

      <style scoped>
        .ctf-embedded {
          display: inline-flex;
          align-items: center;
          gap: calc(var(--spacing) * 2);
          font-family: var(--font-mono);
          font-size: 0.8125rem;
          letter-spacing: 0.06em;
          color: var(--foreground);
        }
        /* Swatch renders [label][value][preview]; this field reads
           [preview][hex][notation], so the preview is pulled first with
           `order` rather than re-typing the component. */
        .ctf-swatch {
          gap: calc(var(--spacing) * 2);
          --boxel-swatch-border-color: color-mix(
            in oklch,
            var(--foreground) 30%,
            transparent
          );
        }
        .ctf-swatch :deep(.boxel-swatch-preview) {
          order: -1;
          width: 1.4rem;
          height: 1.4rem;
          border-radius: 50%;
          flex-shrink: 0;
        }
        .ctf-swatch :deep(.boxel-swatch-label) {
          display: flex;
          flex-direction: row-reverse;
          align-items: center;
          gap: calc(var(--spacing) * 2);
        }
        .ctf-swatch :deep(.boxel-swatch-name) {
          color: var(--muted-foreground);
        }
        .ctf-swatch :deep(.boxel-swatch-value) {
          font: inherit;
        }
        .munsell {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='ctf-atom' data-test-color-tree-field-atom>
        {{! hideLabel: the atom shows the notation only, never the hex, so
            Swatch contributes just its preview here }}
        <Swatch
          class='ctf-atom-swatch'
          @style='round'
          @hideLabel={{true}}
          @color={{@model.hex}}
        />
        <span class='label'>{{if
            @model.munsell
            @model.munsell
            'unpicked'
          }}</span>
      </span>

      <style scoped>
        .ctf-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--spacing);
          line-height: 1;
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          letter-spacing: 0.06em;
        }
        .ctf-atom-swatch {
          --boxel-swatch-border-color: color-mix(
            in oklch,
            var(--foreground) 30%,
            transparent
          );
        }
        .ctf-atom-swatch :deep(.boxel-swatch-preview) {
          width: 0.8rem;
          height: 0.8rem;
          border-radius: 50%;
          flex-shrink: 0;
        }
        .label {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
