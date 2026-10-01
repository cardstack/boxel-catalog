import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import HashIcon from '@cardstack/boxel-icons/hash';
import { on } from '@ember/modifier';
import { BoxelInput } from '@cardstack/boxel-ui/components';
import { CopyButton } from '@cardstack/pretui/components/copy-button';
import { Token } from '@cardstack/pretui/components/token';
import { tokenStyle } from '../shared/pretui-token';

function stopPropagation(event: Event) {
  event.stopPropagation();
}

// The id is a machine value practitioners quote, so it reads as a Pret UI
// Token in the muted hue, at the size each format set it in. The embedded view
// adds a CopyButton beside it; the atom sits inline in other text and does not.
const ID_TOKEN_STYLE = {
  sm: tokenStyle('--boxel-font-size-sm', 'var(--muted-foreground)'),
  xs: tokenStyle('--boxel-font-size-xs', 'var(--muted-foreground)'),
};

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
      {{#if @model.value}}
        <span class='record-id'>
          <Token style={{ID_TOKEN_STYLE.sm}}>{{@model.value}}</Token>
          {{! The field often renders inside a clickable card; the copy must
              not also open it. Enter and Space on the button fire click. }}
          <CopyButton
            @text={{@model.value}}
            @label='Copy identifier'
            @variant='ghost'
            @size='s'
            {{on 'click' stopPropagation}}
          />
        </span>
      {{else}}
        <span class='record-id-none'>—</span>
      {{/if}}
      <style scoped>
        .record-id {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
        }
        .record-id-none {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      {{#if @model.value}}
        <Token style={{ID_TOKEN_STYLE.xs}}>{{@model.value}}</Token>
      {{else}}
        <span class='record-id-none'>—</span>
      {{/if}}
      <style scoped>
        .record-id-none {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
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
        {{#if @model.value}}
          <span><Token
              style={{ID_TOKEN_STYLE.sm}}
            >{{@model.value}}</Token></span>
        {{else}}
          <span class='minted'>not minted yet</span>
        {{/if}}
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
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
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
