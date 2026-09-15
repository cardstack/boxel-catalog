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
import { swatchStyle } from './utils/munsell';
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
          border-radius: var(--radius, 0.5rem);
          overflow: hidden;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='ctf-embedded' data-test-color-tree-field-embedded>
        <span class='swatch' style={{swatchStyle @model.hex}}></span>
        {{#if @model.hex}}
          <span class='hex'>{{@model.hex}}</span>
          <span class='munsell'>{{@model.munsell}}</span>
        {{else}}
          <span class='munsell'>no chip picked yet</span>
        {{/if}}
      </div>

      <style scoped>
        .ctf-embedded {
          display: inline-flex;
          align-items: center;
          gap: calc(var(--spacing, 0.25rem) * 2);
          font-family: var(--font-mono, ui-monospace, 'SF Mono', monospace);
          font-size: 0.8125rem;
          letter-spacing: 0.06em;
          color: var(--foreground, #0f172a);
        }
        .swatch {
          width: 1.4rem;
          height: 1.4rem;
          border-radius: 50%;
          border: 1px solid
            color-mix(in srgb, var(--foreground, #0f172a) 30%, transparent);
          flex-shrink: 0;
        }
        .munsell {
          color: var(--muted-foreground, #64748b);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='ctf-atom' data-test-color-tree-field-atom>
        <span class='swatch' style={{swatchStyle @model.hex}}></span>
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
          gap: calc(var(--spacing, 0.25rem) * 1);
          line-height: 1;
          font-family: var(--font-mono, ui-monospace, 'SF Mono', monospace);
          font-size: 0.6875rem;
          letter-spacing: 0.06em;
        }
        .swatch {
          width: 0.8rem;
          height: 0.8rem;
          border-radius: 50%;
          border: 1px solid
            color-mix(in srgb, var(--foreground, #0f172a) 30%, transparent);
          flex-shrink: 0;
        }
        .label {
          color: var(--muted-foreground, #64748b);
        }
      </style>
    </template>
  };
}
