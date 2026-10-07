import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import UserCheckIcon from '@cardstack/boxel-icons/user-check';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';

import { relativeStamp } from '@cardstack/catalog/fields/created-at/created-at';

// Pret UI Avatar hashes a hue from the name when none is given, which would
// colour owners arbitrarily. The muted hue keeps the neutral initials the
// field has always shown.
const OWNER_AVATAR_HUE = 'var(--muted-foreground)';

export const OWNERSHIP_HOW = [
  'assigned',
  'claimed',
  'round-robin',
  'escalation',
] as const;

export const OwnershipHowField = enumField(StringField, {
  displayName: 'Ownership Provenance',
  options: OWNERSHIP_HOW as unknown as string[],
});

/**
 * Who is accountable for a record RIGHT NOW, since when, and how they got it.
 *
 * The owner is stored as card id plus display name rather than a link, so a
 * list row renders without loading the owner card and the one-hop trail stays
 * readable after that card changes. One writer — the consumer's assign
 * action — resolves and stamps both. One hop of trail lives here
 * (`previousOwnerName`); the full history is the record's timeline.
 *
 * Generic on purpose: a Case, an Invoice and a plain demo card all carry the
 * same shape.
 */
export class RecordOwnerField extends FieldDef {
  static displayName = 'Record Owner';
  static icon = UserCheckIcon;

  @field ownerId = contains(StringField, {
    description: 'Card id of the owner. Written by the assign action.',
  });
  @field ownerName = contains(StringField);
  @field teamName = contains(StringField, {
    description: 'The owning queue/team, for display.',
  });
  @field since = contains(DateTimeField);
  @field how = contains(OwnershipHowField);
  @field previousOwnerName = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: RecordOwnerField) {
      if (!this.ownerName) return 'Unassigned';
      return this.how ? `${this.ownerName} · via ${this.how}` : this.ownerName;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get sinceLabel() {
      return relativeStamp(this.args.model.since ?? undefined);
    }
    <template>
      {{#if @model.ownerName}}
        {{! Pret UI EntityDisplay with an Avatar in its visual slot. The name
            is EntityDisplay's title, so the Avatar is hidden from assistive
            tech rather than announcing the name twice. }}
        <EntityDisplay
          class='owner'
          @title={{@model.ownerName}}
          @center={{true}}
        >
          <:visual>
            <Avatar
              @name={{@model.ownerName}}
              @hue={{OWNER_AVATAR_HUE}}
              @size={{28}}
              aria-hidden='true'
            />
          </:visual>
          <:meta>
            {{#if this.sinceLabel}}since {{this.sinceLabel}}{{/if}}
            {{#if @model.how}}· via {{@model.how}}{{/if}}
          </:meta>
        </EntityDisplay>
      {{else}}
        <span class='owner-none'>Unassigned</span>
      {{/if}}
      <style scoped>
        /* EntityDisplay's visual slot sized to the 28px Avatar, and its title
           and meta at the field's own sizes. */
        .owner {
          --pretui-entity-visual-size: 1.75rem;
          --space-3: var(--boxel-sp-xs);
          --text-ui-md: var(--boxel-font-size-sm);
          --text-ui-sm: var(--boxel-font-size-xs);
        }
        .owner-none {
          font-style: italic;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='owner-atom'>{{if
          @model.ownerName
          @model.ownerName
          'Unassigned'
        }}</span>
      <style scoped>
        .owner-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      {{! Ownership is written by the app's assign action so provenance and
          the trail stay truthful; edit shows the facts, not inputs. }}
      <div class='owner-edit'>
        <span class='owner-current'>{{if
            @model.ownerName
            @model.ownerName
            'Unassigned'
          }}</span>
        {{#if @model.how}}
          <span class='owner-how'>via {{@model.how}}</span>
        {{/if}}
        {{#if @model.previousOwnerName}}
          <span class='owner-prev'>previously
            {{@model.previousOwnerName}}</span>
        {{/if}}
        <p class='owner-note'>Change ownership with the app's assign action so
          the change is attributed and the trail records it.</p>
      </div>
      <style scoped>
        .owner-edit {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-sm);
        }
        .owner-current {
          font-weight: 500;
        }
        .owner-how,
        .owner-prev {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .owner-note {
          margin: var(--boxel-sp-3xs) 0 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export default RecordOwnerField;
