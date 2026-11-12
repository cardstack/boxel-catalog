import GlimmerComponent from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { StringField } from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import { stateColor, type Hue } from '@cardstack/catalog/components/state-pill';

interface DotOption {
  value: string;
  label: string;
}

interface DotAtomSignature {
  Args: { model?: string | null };
}

/**
 * An enum status field whose atom and embedded formats are a 7px dot in the
 * value's hue plus its label (no pill), so a table cell can render the field's
 * own format. Options, configuration and the edit format are the enum's.
 */
export function dotEnumField(
  config: { options: DotOption[]; displayName?: string },
  hues: Record<string, Hue>,
): typeof StringField {
  let Base = enumField(StringField, config);

  class DotAtom extends GlimmerComponent<DotAtomSignature> {
    get label(): string {
      let v = this.args.model;
      if (v == null || v === '') {
        return '—';
      }
      return config.options.find((o) => o.value === v)?.label ?? String(v);
    }
    get dotStyle() {
      let hue = this.args.model ? hues[this.args.model] : undefined;
      return htmlSafe(
        `background: ${hue ? stateColor(hue).ring : 'var(--muted-foreground)'}`,
      );
    }
    <template>
      <span class='dot-enum'><span
          class='dot'
          style={{this.dotStyle}}
          aria-hidden='true'
        ></span>{{this.label}}</span>
      <style scoped>
        @layer PretComponent {
          .dot-enum {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-2xs);
            max-inline-size: 100%;
            font-weight: 600;
            white-space: nowrap;
            color: var(--foreground);
          }
          .dot {
            flex: none;
            inline-size: 0.4375rem;
            block-size: 0.4375rem;
            border-radius: 50%;
          }
        }
      </style>
    </template>
  }

  return class DotEnumField extends (Base as typeof StringField) {
    // DotAtom reads only @model; the field's format slots expect the full field args
    static atom = DotAtom as unknown as typeof StringField.atom;
    static embedded = DotAtom as unknown as typeof StringField.embedded;
  } as unknown as typeof StringField;
}

export { DotLabel } from '../shared/compact-sheet';
