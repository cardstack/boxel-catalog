import { Component } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import IdIcon from '@cardstack/boxel-icons/id';
import { Token } from '@cardstack/pretui/components/token';

/**
 * The identifier a membership program prints on the card — stable, human-
 * readable, quoted over the phone. It is a label, not a key: the card's id
 * is the reference other cards link by; the member number is what the
 * member sees.
 *
 * It renders as a Pret UI `Token`, the kit's mono pill for an id, so the
 * digit groups line up in lists and read unambiguously (no 0/O squint).
 */
export default class MemberNumberField extends StringField {
  static displayName = 'Member Number';
  static icon = IdIcon;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      {{#if @model}}
        <Token class='member-number' @value={{@model}} />
      {{else}}
        <span class='no-number'>—</span>
      {{/if}}
      <style scoped>
        /* Neutral hue: a member number is an id, not a primary action. */
        .member-number {
          --pretui-token-hue: var(--muted-foreground);
        }
        .no-number {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      {{#if @model}}
        <Token class='member-number' @value={{@model}} />
      {{/if}}
      <style scoped>
        .member-number {
          --pretui-token-hue: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

/**
 * The common `PREFIX-YYYY-SEQUENCE` shape. Sequencing itself is the caller's
 * problem — a realm has no global counter, so the enrolling command decides
 * where the next number comes from (a count query, an imported roll, a
 * random block) and this only formats it consistently.
 */
export function formatMemberNumber(
  prefix: string,
  year: number,
  sequence: number,
  width = 8,
): string {
  return `${prefix}-${year}-${String(sequence).padStart(width, '0')}`;
}
