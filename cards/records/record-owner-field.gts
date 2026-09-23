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

import { initialsOf } from '@cardstack/catalog/cards/people/person-base';
import { relativeStamp } from '@cardstack/catalog/fields/created-at/created-at';

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
 * A FieldDef cannot carry `linksTo`, so ownership stores the owner's card id
 * plus display name; the Assign Owner command — the single writer of this
 * field — resolves and stamps both. One hop of trail lives here
 * (`previousOwnerName`); the full history is the record's timeline.
 *
 * Generic on purpose: a Case, an Invoice and a plain demo card all carry the
 * same shape.
 */
export class RecordOwnerField extends FieldDef {
  static displayName = 'Record Owner';
  static icon = UserCheckIcon;

  @field ownerId = contains(StringField, {
    description: 'Card id of the owning Employee. Written by Assign Owner.',
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
    get initials() {
      return initialsOf(this.args.model.ownerName);
    }
    <template>
      <div class='owner'>
        {{#if @model.ownerName}}
          <span class='owner-avatar' aria-hidden='true'>{{this.initials}}</span>
          <span class='owner-body'>
            <span class='owner-name'>{{@model.ownerName}}</span>
            <span class='owner-meta'>
              {{#if this.sinceLabel}}since {{this.sinceLabel}}{{/if}}
              {{#if @model.how}}· via {{@model.how}}{{/if}}
            </span>
          </span>
        {{else}}
          <span class='owner-none'>Unassigned</span>
        {{/if}}
      </div>
      <style scoped>
        .owner {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .owner-avatar {
          flex: none;
          width: 1.75rem;
          height: 1.75rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          background: var(--muted, var(--boxel-200));
          color: var(--muted-foreground, var(--boxel-500));
        }
        .owner-body {
          display: flex;
          flex-direction: column;
          min-width: 0;
        }
        .owner-name {
          font-weight: 500;
          color: var(--foreground, var(--boxel-dark));
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .owner-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .owner-none {
          font-style: italic;
          color: var(--muted-foreground, var(--boxel-450));
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
          color: var(--foreground, var(--boxel-dark));
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      {{! Ownership is written by the Assign Owner command so provenance and
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
        <p class='owner-note'>Change ownership with the Assign Owner action so
          the change is attributed and the trail records it.</p>
      </div>
      <style scoped>
        .owner-edit {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-sm);
        }
        .owner-current {
          font-weight: 500;
        }
        .owner-how,
        .owner-prev {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .owner-note {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

export default RecordOwnerField;
