import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import HashIcon from '@cardstack/boxel-icons/hash';
import { BoxelInput } from '@cardstack/boxel-ui/components';

/**
 * The human-readable handle of a record: "CASE-2026-0142".
 *
 * Practitioners quote these on calls, so the contract is strict: minted once
 * at create time by the creating command, unique per desk, NEVER edited and
 * NEVER recycled. The pattern travels with the value so a reader can tell how
 * it was formed without opening the desk's App Configuration.
 *
 * Generic on purpose — nothing here names a support concept. An invoice desk
 * or an asset register mints through the same field.
 */
export class RecordIdentifierField extends FieldDef {
  static displayName = 'Record Identifier';
  static icon = HashIcon;

  @field value = contains(StringField, {
    description: 'The minted identifier, e.g. CASE-2026-0142. Never edited.',
  });
  @field pattern = contains(StringField, {
    description: 'The pattern it was minted from, e.g. CASE-{yyyy}-{seq4}.',
  });
  @field issuedAt = contains(DateTimeField);

  @field title = contains(StringField, {
    computeVia: function (this: RecordIdentifierField) {
      return this.value ?? '—';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <code class='record-id'>{{if @model.value @model.value '—'}}</code>
      <style scoped>
        .record-id {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-sm);
          font-weight: 500;
          color: var(--foreground, var(--boxel-dark));
          letter-spacing: 0.02em;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <code class='record-id-atom'>{{if @model.value @model.value '—'}}</code>
      <style scoped>
        .record-id-atom {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    setPattern = (value: string) => {
      this.args.model.pattern = value || undefined;
    };

    <template>
      {{! Ids are minted by commands; edit shows the value read-only and lets
          the pattern be corrected only while no value has been minted yet. }}
      <div class='id-edit'>
        <code class='minted'>{{if
            @model.value
            @model.value
            'not minted yet'
          }}</code>
        {{#unless @model.value}}
          <BoxelInput
            @value={{@model.pattern}}
            @onInput={{this.setPattern}}
            @placeholder='CASE-(yyyy)-(seq4)'
          />
        {{/unless}}
      </div>
      <style scoped>
        .id-edit {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .minted {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

/**
 * Mint an identifier from a pattern and a sequence number.
 * `{yyyy}` → the mint year; `{seqN}` → the sequence zero-padded to N digits.
 * The SEQUENCE is the caller's job (the creating command owns the counter);
 * this is pure string work so every desk mints the same way.
 */
export function mintIdentifier(
  pattern: string | undefined,
  seq: number,
  now: Date = new Date(),
): string {
  let p = pattern?.trim() || 'REC-{yyyy}-{seq4}';
  return p
    .replace('{yyyy}', String(now.getFullYear()))
    .replace(/\{seq(\d)\}/, (_m, n) => String(seq).padStart(Number(n), '0'));
}

export function isValidIdentifierPattern(pattern?: string | null): boolean {
  if (!pattern) return false;
  return pattern.includes('{yyyy}') && /\{seq\d\}/.test(pattern);
}

export default RecordIdentifierField;
