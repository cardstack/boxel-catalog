import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import UsersIcon from '@cardstack/boxel-icons/users';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { initialsOf } from '@cardstack/catalog/cards/people/person-base';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { EditSectionNav } from '@cardstack/catalog/components/edit-section-nav';

class RoleEdit extends Component<typeof Role> {
  @tracked activeSection = 'identity';

  sections = [
    { id: 'identity', label: 'Role' },
    { id: 'grants', label: 'Members & grants' },
  ];

  goTo = (id: string, event: Event) => {
    this.activeSection = id;
    let root = (event.currentTarget as HTMLElement).closest('.role-edit');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='role-edit'>
      <div class='edit-body'>
        <EditSectionNav
          @sections={{this.sections}}
          @activeId={{this.activeSection}}
          @onSelect={{this.goTo}}
          class='sect-nav'
        />
        <div class='sects'>
          <section
            class='sect {{if (eq this.activeSection "identity") "focused"}}'
            data-sect='identity'
          >
            <h3>Role
              <span class='sect-hint'>on-duty is hand-set — the platform has no
                scheduler</span></h3>
            <FieldContainer @label='Name' @vertical={{true}}>
              <@fields.name />
            </FieldContainer>
            <FieldContainer @label='On duty' @vertical={{true}}>
              <@fields.onDuty />
            </FieldContainer>
          </section>
          <section
            class='sect {{if (eq this.activeSection "grants") "focused"}}'
            data-sect='grants'
          >
            <h3>Members & grants
              <span class='sect-hint'>grants are data read by workflow guards,
                not an ACL</span></h3>
            <FieldContainer @label='Members' @vertical={{true}}>
              <@fields.members />
            </FieldContainer>
            <FieldContainer @label='Grants' @vertical={{true}}>
              <@fields.permissions />
            </FieldContainer>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .role-edit {
        container-type: inline-size;
      }
      .edit-body {
        display: grid;
        grid-template-columns: 10rem 1fr;
        gap: var(--boxel-sp);
        align-items: start;
      }
      @container (width < 34rem) {
        .edit-body {
          grid-template-columns: 1fr;
        }
      }
      .sects {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .sect {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        border: 1px solid var(--border, var(--boxel-border-color));
        border-radius: var(--boxel-border-radius);
        background: var(--card, var(--boxel-light));
        padding: var(--boxel-sp-sm);
        scroll-margin-top: var(--boxel-sp);
      }
      .sect.focused {
        border-color: var(--primary, var(--boxel-highlight));
      }
      .sect h3 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--muted-foreground, var(--boxel-450));
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
      }
      .sect-hint {
        text-transform: none;
        letter-spacing: 0;
        font-weight: 400;
        font-style: italic;
      }
    </style>
  </template>
}

/**
 * A named duty — "L2 Support", "Ops Lead" — with its members and who is on
 * duty right now.
 *
 * TWO HONEST LIMITS, stated so consumers repeat them: `onDuty` is hand-set
 * (the platform has no scheduler, so rotation is a human act until one
 * exists), and `permissions` is DATA read by workflow guards, not an ACL —
 * realm permissions are the platform's enforcement layer, and pretending
 * otherwise would be a security claim this card cannot keep.
 */
export class Role extends CardDef {
  static displayName = 'Role';
  static icon = UsersIcon;

  @field name = contains(StringField);
  @field members = linksToMany(() => Employee);
  @field onDuty = linksTo(() => Employee);
  @field permissions = containsMany(StringField, {
    description: 'Informational grants read by guards, e.g. "close-finding".',
  });

  @field title = contains(StringField, {
    computeVia: function (this: Role) {
      return this.name ?? 'Role';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class='role-page'>
        <header>
          <h1><@fields.title /></h1>
          {{#if @model.onDuty}}
            <p class='role-duty'>On duty: <@fields.onDuty @format='atom' /></p>
          {{else}}
            <p class='role-duty role-duty-none'>No one on duty — set who answers
              before relying on this role in an escalation ladder.</p>
          {{/if}}
        </header>
        <section>
          <h2>Members</h2>
          <div class='role-members'><@fields.members @format='atom' /></div>
        </section>
        {{#if @model.permissions.length}}
          <section>
            <h2>Grants (informational)</h2>
            <div class='role-grants'>
              {{#each @model.permissions as |p|}}<code>{{p}}</code>{{/each}}
            </div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .role-page {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
        }
        .role-duty {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-sm);
        }
        .role-duty-none {
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .role-members {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .role-grants {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        code {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-xs);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius-sm);
          padding: 0.125rem 0.5rem;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get dutyInitials() {
      return initialsOf(this.args.model.onDuty?.title as string | undefined);
    }
    <template>
      <div class='role-embedded'>
        <span class='role-name'>{{@model.title}}</span>
        <span class='role-meta'>
          {{@model.members.length}}
          member(s)
          {{#if @model.onDuty}}· on duty {{this.dutyInitials}}{{/if}}
        </span>
      </div>
      <style scoped>
        .role-embedded {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
        }
        .role-name {
          font-weight: 600;
        }
        .role-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='role-atom'>{{@model.title}}</span>
      <style scoped>
        .role-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='role-fitted'>
        <UsersIcon class='role-icon' aria-hidden='true' />
        <div class='role-fitted-body'>
          <span class='role-fitted-title'>{{@model.title}}</span>
          <span class='role-fitted-meta'>{{@model.members.length}}
            member(s)</span>
          <div class='role-fitted-more'>
            {{#if @model.onDuty}}<span>on duty:
                <@fields.onDuty
                  @format='atom'
                  @displayContainer={{false}}
                /></span>{{/if}}
            {{#if @model.permissions.length}}<span>{{@model.permissions.length}}
                grant(s)</span>{{/if}}
          </div>
        </div>
      </div>
      <style scoped>
        .role-fitted {
          height: 100%;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .role-icon {
          flex: none;
          width: 1.25rem;
          height: 1.25rem;
          color: var(--primary, var(--boxel-highlight));
        }
        .role-fitted-body {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          min-width: 0;
        }
        .role-fitted-title {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .role-fitted-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .role-fitted-more {
          display: none;
        }
        @container fitted-card (height > 170px) {
          .role-fitted-more {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-5xs);
            margin-top: var(--boxel-sp-4xs);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground, var(--boxel-450));
          }
        }
        @container fitted-card (height <= 80px) {
          .role-fitted {
            align-items: center;
          }
          .role-fitted-meta {
            display: none;
          }
        }
      </style>
    </template>
  };
  static edit = RoleEdit;
}

export default Role;
