import {
  FieldDef,
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import ColorField from 'https://cardstack.com/base/color';
import { htmlSafe } from '@ember/template';

import LayoutRowsIcon from '@cardstack/boxel-icons/layout-rows';

// A single tier band: a stable key, a display label, a band color, and an
// order. Used by TierList for its tier rows.
export class Tier extends FieldDef {
  static displayName = 'Tier';
  static icon = LayoutRowsIcon;

  @field key = contains(StringField);
  @field label = contains(StringField);
  @field color = contains(ColorField);
  @field sortOrder = contains(NumberField);

  static embedded = class extends Component<typeof Tier> {
    get style() {
      return htmlSafe(`background: ${this.args.model.color ?? 'transparent'}`);
    }

    <template>
      <span class='tier-chip' style={{this.style}}>{{@model.label}}</span>
      <style scoped>
        .tier-chip {
          display: inline-flex;
          align-items: center;
          padding: 0.125rem 0.5rem;
          border-radius: 0.25rem;
          font-weight: 700;
          color: #111;
        }
      </style>
    </template>
  };
}
