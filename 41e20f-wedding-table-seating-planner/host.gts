import {
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import CrownIcon from '@cardstack/boxel-icons/crown';

import { Person } from './person';
import { initialsOf } from './utils/index';

export class Host extends Person {
  static displayName = 'Host';
  static icon = CrownIcon;

  @field role = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    get initials() {
      return initialsOf(this.args.model?.fullName);
    }
    <template>
      <div class='h-row'>
        {{#if @model.photoURL}}
          <img class='h-avatar' src={{@model.photoURL}} alt='' />
        {{else}}
          <span class='h-avatar h-initials'>{{this.initials}}</span>
        {{/if}}
        <span class='h-main'>
          <span class='h-name'>{{if
              @model.fullName
              @model.fullName
              'Unnamed Host'
            }}</span>
          {{#if @model.role}}
            <span class='h-role'>{{@model.role}}</span>
          {{/if}}
        </span>
        <span class='h-badge'>✦ Host</span>
      </div>
      <style scoped>
        .h-row {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 9px 12px;
          border: 1px solid rgba(220, 193, 136, 0.55);
          border-radius: 11px;
          background: var(--background, #ffffff);
          font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
          color: var(--foreground, #22283f);
        }
        .h-avatar {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          flex: none;
          object-fit: cover;
        }
        .h-initials {
          display: flex;
          align-items: center;
          justify-content: center;
          font:
            600 13px 'Cormorant Garamond',
            serif;
          color: var(--ink, #22283f);
          background: linear-gradient(135deg, #f0dca4, var(--gold, #c5a35c));
        }
        .h-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 3px;
        }
        .h-name {
          font-size: 14px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .h-role {
          font:
            10px 'Jost',
            monospace;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground, #a5919c);
        }
        .h-badge {
          flex: none;
          font:
            600 8.5px 'Jost',
            monospace;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--ink, #22283f);
          background: var(--gold, #c5a35c);
          border-radius: 4px;
          padding: 3px 7px;
        }
      </style>
    </template>
  };
}
