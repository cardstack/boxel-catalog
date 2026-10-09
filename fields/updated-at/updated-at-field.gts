import { Component } from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import HistoryIcon from '@cardstack/boxel-icons/history';

import {
  absoluteStamp,
  relativeStamp,
} from '@cardstack/catalog/fields/created-at/created-at';

/**
 * When the record last meaningfully changed. Monotonic: rewritten forward on
 * each meaningful edit by whatever writes the record — the block renders the
 * fact, the writer owns the discipline (and decides what counts as
 * "meaningful"; an index-driven touch usually should not). The pair of this
 * and Created At is the standard record-header treatment; the atom leads with
 * recency because "how fresh is this?" is the question dense rows answer.
 */
export class UpdatedAtField extends DateTimeField {
  static displayName = 'Updated At';
  static icon = HistoryIcon;

  static embedded = class Embedded extends Component<typeof this> {
    get absolute() {
      return absoluteStamp(this.args.model);
    }
    get relative() {
      return relativeStamp(this.args.model);
    }
    <template>
      {{#if this.absolute}}
        <span class='stamp'>{{this.absolute}}
          <span class='relative'>({{this.relative}})</span></span>
      {{else}}
        <span class='unset' aria-hidden='true'>—</span><span
          class='visually-hidden'
        >Never updated</span>
      {{/if}}
      <style scoped>
        .stamp {
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
        .relative,
        .unset {
          color: var(--muted-foreground);
        }
        .visually-hidden {
          position: absolute;
          width: 1px;
          height: 1px;
          overflow: hidden;
          clip-path: inset(50%);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get absolute() {
      return absoluteStamp(this.args.model);
    }
    get relative() {
      return relativeStamp(this.args.model);
    }
    <template>
      {{#if this.relative}}
        <span
          class='stamp-atom'
          title={{this.absolute}}
        >{{this.relative}}</span>
      {{else}}
        <span class='unset' aria-hidden='true'>—</span><span
          class='visually-hidden'
        >Never updated</span>
      {{/if}}
      <style scoped>
        .stamp-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .unset {
          color: var(--muted-foreground);
        }
        .visually-hidden {
          position: absolute;
          width: 1px;
          height: 1px;
          overflow: hidden;
          clip-path: inset(50%);
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export default UpdatedAtField;
