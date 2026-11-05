import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import GavelIcon from '@cardstack/boxel-icons/gavel';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { htmlSafe } from '@ember/template';
import { Chip } from '@cardstack/pretui/components/chip';
import type { KeyValueItem } from '@cardstack/pretui/components/key-value';
import { LegalFacts } from './legal-ui';

// The neutral chip recipe StatePill uses for slate (14% fill, 62% foreground
// ink). StatePill takes a label only, and this chip leads with the gavel icon,
// so it sets the same knobs on Pret UI `Chip` directly.
const CHIP_STYLE = htmlSafe(
  '--pretui-chip-hue: var(--muted-foreground); --pretui-chip-mix: 14%; --pretui-ink-mix: 62%; max-width: 100%',
);

/**
 * Governing Law (GL) — which law reads the contract, and where a dispute is
 * heard.
 *
 * Two different questions that get conflated on a term sheet: the governing
 * law says whose rules apply to the words; the venue says whose court you sit
 * in. "English law, Singapore arbitration" is a perfectly ordinary pairing,
 * which is why they are two fields rather than one.
 *
 * Deliberately a plain string pair rather than a Country link: jurisdictions
 * are sub-national ("Delaware", "England & Wales", "New South Wales") and
 * venues are often institutions ("ICC Paris", "SIAC") rather than places.
 */
export function governingLawLabel(
  jurisdiction?: string | null,
  venue?: string | null,
): string {
  let j = jurisdiction?.trim();
  let v = venue?.trim();
  if (j && v) return `${j} / ${v}`;
  return j || v || '—';
}

export class GoverningLawField extends FieldDef {
  static displayName = 'Governing Law';
  static icon = GavelIcon;

  /** Whose law reads the words — "Germany", "Delaware", "England & Wales". */
  @field jurisdiction = contains(StringField);
  /** Where a dispute is heard — a court seat or an arbitral institution. */
  @field venue = contains(StringField);
  /** Escalation ladder, arbitration rules, language of proceedings. */
  @field notes = contains(TextAreaField);

  @field label = contains(StringField, {
    computeVia: function (this: GoverningLawField) {
      return governingLawLabel(this.jurisdiction, this.venue);
    },
  });

  static atom = class Atom extends Component<typeof this> {
    <template>
      <Chip
        class='gl-chip'
        @dot={{false}}
        style={{CHIP_STYLE}}
        title={{@model.notes}}
      >
        <GavelIcon class='gl-icon' role='presentation' />
        <span class='gl-text'>{{@model.label}}</span>
      </Chip>
      <style scoped>
        .gl-chip {
          min-width: 0;
        }
        .gl-icon {
          width: 0.75rem;
          height: 0.75rem;
          flex: none;
        }
        .gl-text {
          overflow: hidden;
          text-overflow: ellipsis;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Governing law', value: m?.jurisdiction || '—' },
        { key: 'Venue', value: m?.venue || '—' },
      ];
    }
    <template>
      <div class='gl'>
        <GavelIcon class='gl-icon' role='presentation' />
        <div class='gl-body'>
          <LegalFacts @items={{this.facts}} />
          {{#if @model.notes}}
            <p class='gl-notes'>{{@model.notes}}</p>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .gl {
          display: flex;
          gap: 0.6rem;
          align-items: flex-start;
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
        .gl-icon {
          width: 1.125rem;
          height: 1.125rem;
          flex: none;
          margin-top: 0.1rem;
          color: var(--muted-foreground);
        }
        .gl-body {
          min-width: 0;
          flex: 1;
        }
        .gl-notes {
          margin: 0.4rem 0 0;
          color: var(--muted-foreground);
          line-height: 1.5;
          white-space: pre-line;
        }
      </style>
    </template>
  };
}

/** Edit — the two questions side by side, notes below; computed `label` hidden. */
GoverningLawField.edit = class Edit extends Component<
  typeof GoverningLawField
> {
  <template>
    <div class='gl-edit'>
      <FieldContainer
        @label='Governing law (whose law reads the words)'
        @vertical={{true}}
      >
        <@fields.jurisdiction />
      </FieldContainer>
      <FieldContainer
        @label='Venue (where a dispute is heard)'
        @vertical={{true}}
      >
        <@fields.venue />
      </FieldContainer>
      <FieldContainer
        @label='Dispute procedure, rules, language'
        @vertical={{true}}
      >
        <@fields.notes />
      </FieldContainer>
    </div>
    <style scoped>
      .gl-edit {
        container-type: inline-size;
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        align-items: start;
      }
      .gl-edit > :last-child {
        grid-column: 1 / -1;
      }
      @container (max-width: 420px) {
        .gl-edit {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
};

export default GoverningLawField;
