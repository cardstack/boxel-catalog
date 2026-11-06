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
import PencilIcon from '@cardstack/boxel-icons/pencil';
import { Employee } from '../hr/employee';
import { get } from '@ember/helper';
import { on } from '@ember/modifier';
import { Button } from '@cardstack/pretui/components/button';
import { Stat } from '@cardstack/pretui/components/stat';
import { Chip } from '@cardstack/pretui/components/chip';
import { FitTile } from '../shared/fit-tile';

function plural(n: number, word: string) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}
// "acknowledge-escalation" reads as "acknowledges escalations"
function grantPhrase(grant?: string) {
  if (!grant) return '';
  let [verb, ...rest] = grant.split('-');
  return [`${verb}s`, ...rest.map((w) => `${w}s`)].join(' ');
}

/** The strings every SupportRole format shows, read once from the model. */
function roleView(m?: Partial<Role>) {
  // a linked member can be briefly unloaded (null) while the store fetches it
  let members = (m?.members ?? []).filter(Boolean);
  let permissions = m?.permissions ?? [];
  let dutyName = m?.onDuty?.name as string | undefined;
  let dutyId = m?.onDuty?.id;
  return {
    name: m?.title ?? 'Role',
    memberCount: members.length,
    membersLabel: plural(members.length, 'member'),
    onDuty: Boolean(m?.onDuty),
    dutyName,
    subline: [plural(members.length, 'member'), grantPhrase(permissions[0])]
      .filter(Boolean)
      .join(' · '),
    facts: [
      { key: 'Members', value: String(members.length) },
      { key: 'On duty', value: dutyName ?? '—' },
      { key: 'Permissions', value: String(permissions.length) },
    ],
    permissions,
    memberNames: members
      .map((x) => x.name)
      .filter(Boolean)
      .join(', '),
    // "acknowledge-escalation, resolve-case" reads as "acknowledge + resolve"
    permissionsHint: permissions.map((p) => p.split('-')[0]).join(' + '),
    // true where the member is the one on duty (the duty atom already shows them)
    dutyFlags: members.map((x) => Boolean(dutyId) && x.id === dutyId),
    memberRows: members.map((x) => ({
      name: (x.name as string | undefined) ?? 'Member',
      sub: [x.role, x.id === dutyId ? 'on duty' : undefined]
        .filter(Boolean)
        .join(' · '),
      duty: Boolean(dutyId) && x.id === dutyId,
    })),
  };
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

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return roleView(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <span class='mark' aria-hidden='true'>Ro</span>
          <div class='t'>
            <h3 class='name'>{{this.v.name}}</h3>
            <p class='meta'>{{this.v.subline}}</p>
          </div>
        </header>
        {{#if this.v.dutyName}}<p class='fact'>On duty:
            <b>{{this.v.dutyName}}</b></p>{{/if}}
        <dl class='kv'>
          {{#each this.v.facts as |f|}}
            <div class='kv-r'><dt class='cap'>{{f.key}}</dt><dd
              >{{f.value}}</dd></div>
          {{/each}}
          {{#each this.v.permissions as |p|}}
            <div class='kv-r'><dt class='cap'>Can</dt><dd>{{p}}</dd></div>
          {{/each}}
          {{#if this.v.onDuty}}
            <div class='kv-r'><dt class='cap'>On duty</dt><dd><@fields.onDuty
                  @format='atom'
                  @displayContainer={{false}}
                /></dd></div>
          {{/if}}
          {{#each @fields.members as |Member i|}}
            {{#unless (get this.v.dutyFlags i)}}
              <div class='kv-r'><dt class='cap'>Member</dt><dd><Member
                    @format='atom'
                    @displayContainer={{false}}
                  /></dd></div>
            {{/unless}}
          {{/each}}
        </dl>
      </article>
      <style scoped>
        .emb {
          container-type: inline-size;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: 0.75rem;
          line-height: 1.4;
        }
        .eh {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
        }
        .t {
          display: grid;
          flex: 1;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: 0.8125rem;
          font-weight: 700;
        }
        .name,
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta,
        .fact {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .fact b {
          font-weight: 700;
        }
        .kv {
          margin: 0;
          padding: 0 var(--boxel-sp-xs);
        }
        .kv-r {
          display: grid;
          grid-template-columns: 6.25rem minmax(0, 1fr);
          column-gap: var(--boxel-sp-xs);
          align-items: center;
          min-block-size: 1.75rem;
          border-top: 1px solid var(--border);
        }
        .kv-r dd {
          margin: 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex: none;
          inline-size: 1.375rem;
          block-size: 1.375rem;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          color: var(--card-foreground);
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 700;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Ro</span>
        <span class='name'>{{if @model.title @model.title 'Role'}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          min-width: 0;
          max-width: 100%;
          vertical-align: middle;
          font-family: var(--font-sans);
          font-size: 0.6875rem;
          font-weight: 600;
          color: var(--card-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex: none;
          inline-size: 1.125rem;
          block-size: 1.125rem;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5rem;
          font-weight: 700;
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get v() {
      return roleView(this.args.model);
    }
    edit = () => {
      this.args.editCard?.(this.args.model as Role);
    };
    <template>
      <article class='iso'>
        <header class='ih'>
          <span class='mark' aria-hidden='true'>Ro</span>
          <div class='t'>
            <h1 class='name'>{{this.v.name}}</h1>
            <p class='meta'>{{this.v.subline}}</p>
          </div>
          <span class='sts'>
            {{#if this.v.onDuty}}<Chip
                @label='on duty'
                @tone='success'
                @appearance='plain'
              />{{/if}}
            <Chip
              @label={{this.v.membersLabel}}
              @tone='neutral'
              @appearance='plain'
            />
          </span>
          {{#if @editCard}}
            <Button
              @variant='outline'
              @size='s'
              @icon={{PencilIcon}}
              {{on 'click' this.edit}}
            >Edit</Button>
          {{/if}}
        </header>
        <div class='stats'>
          <Stat
            @label='Members'
            @tone='neutral'
            @value={{this.v.memberCount}}
            @hint={{this.v.memberNames}}
            @roll={{false}}
          />
          <Stat
            @label='Permissions'
            @tone='primary'
            @value={{this.v.permissions.length}}
            @hint={{this.v.permissionsHint}}
            @roll={{false}}
          />
          <Stat
            @label='On duty'
            @tone='success'
            @value={{if this.v.onDuty 1 0}}
            @hint={{if this.v.dutyName this.v.dutyName 'nobody on duty'}}
            @roll={{false}}
          />
        </div>
        <div class='cols'>
          <div class='main'>
            <section>
              <h2>Members</h2>
              {{#each this.v.memberRows as |r|}}
                <div class='row'>
                  <span class='row-id'>
                    <span class='row-name'>{{r.name}}</span>
                    <span class='meta'>{{if r.sub r.sub '—'}}</span>
                  </span>
                  {{#if r.duty}}<Chip
                      @label='on duty'
                      @tone='success'
                      @appearance='plain'
                    />{{else}}<Chip
                      @label='member'
                      @tone='neutral'
                      @appearance='plain'
                    />{{/if}}
                </div>
              {{else}}
                <p class='row meta'>No members yet</p>
              {{/each}}
            </section>
            {{#if this.v.permissions.length}}
              <section>
                <h2>Permissions</h2>
                {{#each this.v.permissions as |p|}}
                  <div class='row'>
                    <span class='row-id'>
                      <span class='row-name'>{{p}}</span>
                      <span class='meta'>can</span>
                    </span>
                  </div>
                {{/each}}
              </section>
            {{/if}}
          </div>
          <aside class='side'>
            <section>
              <h2>Linked</h2>
              <dl class='kv'>
                {{#if this.v.onDuty}}
                  <div class='kv-r'><dt class='cap'>On duty</dt><dd
                    ><@fields.onDuty @format='atom' /></dd></div>
                {{/if}}
                {{#each @fields.members as |Member i|}}
                  {{#unless (get this.v.dutyFlags i)}}
                    <div class='kv-r'><dt class='cap'>Member</dt><dd><Member
                          @format='atom'
                        /></dd></div>
                  {{/unless}}
                {{/each}}
              </dl>
            </section>
            <section>
              <h2>Details</h2>
              <dl class='kv'>
                {{#each this.v.facts as |f|}}
                  <div class='kv-r'><dt class='cap'>{{f.key}}</dt><dd
                    >{{f.value}}</dd></div>
                {{/each}}
                {{#each this.v.permissions as |p|}}
                  <div class='kv-r'><dt class='cap'>Can</dt><dd>{{p}}</dd></div>
                {{/each}}
              </dl>
            </section>
          </aside>
        </div>
      </article>
      <style scoped>
        .iso {
          container-type: inline-size;
          min-block-size: 100%;
          box-sizing: border-box;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: 0.75rem;
          line-height: 1.4;
          --text-stat: 1.375rem;
        }
        .ih {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          border-bottom: 1px solid var(--border);
        }
        .ih > .mark {
          inline-size: 1.75rem;
          block-size: 1.75rem;
        }
        .t {
          display: grid;
          flex: 1 1 12rem;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: 0.8125rem;
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .sts {
          display: inline-flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          font-weight: 600;
        }
        .stats {
          display: grid;
          grid-auto-flow: column;
          grid-auto-columns: minmax(0, 1fr);
          border-bottom: 1px solid var(--border);
        }
        .stats > * {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
        }
        .stats > * + * {
          border-inline-start: 1px solid var(--border);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
        }
        .main,
        .side {
          min-width: 0;
        }
        .side {
          border-inline-start: 1px solid var(--border);
        }
        section + section {
          border-top: 1px solid var(--border);
        }
        h2 {
          margin: 0;
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
          font-size: 0.75rem;
          font-weight: 700;
        }
        .row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          min-block-size: 1.75rem;
          margin: 0;
          padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .row-id {
          display: grid;
          min-width: 0;
        }
        .row-name {
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .kv {
          margin: 0;
        }
        .kv-r {
          display: grid;
          grid-template-columns: 7.5rem minmax(0, 1fr);
          column-gap: var(--boxel-sp-xs);
          align-items: center;
          min-block-size: 1.75rem;
          padding-inline: var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .kv-r dd {
          margin: 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex: none;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 700;
        }
        @container (max-width: 40rem) {
          .stats {
            grid-auto-flow: row;
          }
          .stats > * + * {
            border-inline-start: 0;
            border-top: 1px solid var(--border);
          }
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .side {
            border-inline-start: 0;
            border-top: 1px solid var(--border);
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return roleView(this.args.model);
    }
    <template>
      <FitTile>
        <:avatar>
          {{! the record's type mark, not a person: a square, not an Avatar }}
          <span class='mark' aria-hidden='true'>Ro</span>
        </:avatar>
        <:title><span
            class='ell'
            role='heading'
            aria-level='3'
          >{{this.v.name}}</span></:title>
        <:subtitle>{{this.v.subline}}</:subtitle>
        <:status>{{#if this.v.onDuty}}<Chip
              @label='on duty'
              @tone='success'
              @appearance='plain'
            />{{else}}<Chip
              @label={{this.v.membersLabel}}
              @tone='neutral'
              @appearance='plain'
            />{{/if}}</:status>
        <:fact>
          {{! rows ranked by priority; container queries drop whole rows }}
          <dl class='fr'>
            {{#if this.v.onDuty}}
              <div class='fr-r'><dt class='cap'>On duty</dt><dd><@fields.onDuty
                    @format='atom'
                    @displayContainer={{false}}
                  /></dd></div>
            {{/if}}
            <div class='fr-r'><dt class='cap'>Members</dt><dd
              >{{this.v.memberCount}}</dd></div>
            <div class='fr-r'><dt class='cap'>Permissions</dt><dd
              >{{this.v.permissions.length}}</dd></div>
            {{#each @fields.members as |Member i|}}
              {{#unless (get this.v.dutyFlags i)}}
                <div class='fr-r'><dt class='cap'>Member</dt><dd><Member
                      @format='atom'
                      @displayContainer={{false}}
                    /></dd></div>
              {{/unless}}
            {{/each}}
            {{#each this.v.permissions as |p|}}
              <div class='fr-r'><dt class='cap'>Can</dt><dd>{{p}}</dd></div>
            {{/each}}
          </dl>
        </:fact>
      </FitTile>
      <style scoped>
        .ell {
          display: block;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mark {
          display: inline-grid;
          place-items: center;
          inline-size: 1.375rem;
          block-size: 1.375rem;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          color: var(--card-foreground);
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 700;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          line-height: 1.2;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          white-space: normal;
          color: var(--muted-foreground);
        }
        .fr {
          display: grid;
          margin: 0;
          font-size: 0.75rem;
          color: var(--card-foreground);
        }
        .fr-r {
          display: grid;
          grid-template-columns: 5rem minmax(0, 1fr);
          column-gap: var(--boxel-sp-2xs);
          align-items: center;
          block-size: 1.75rem;
          border-top: 1px solid var(--border);
          overflow: hidden;
        }
        .fr-r dd {
          margin: 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .fr-r:nth-child(n + 13) {
          display: none;
        }
        @container fitted-card (width < 250px) {
          .fr-r {
            grid-template-columns: minmax(0, 1fr);
          }
          .fr-r dt {
            display: none;
          }
        }
        @container fitted-card (width >= 400px) {
          .fr-r {
            grid-template-columns: 6.75rem minmax(0, 1fr);
          }
        }
        @container fitted-card (height < 445px) and (width < 400px) {
          .fr-r:nth-child(n + 7) {
            display: none;
          }
        }
        @container fitted-card (height < 445px) and (width >= 400px) {
          .fr-r:nth-child(n + 8) {
            display: none;
          }
        }
        @container fitted-card (height < 275px) {
          .fr-r:nth-child(n + 6) {
            display: none;
          }
        }
        @container fitted-card (height < 250px) and (width < 400px) {
          .fr-r:nth-child(n + 3) {
            display: none;
          }
        }
        @container fitted-card (height < 250px) and (width >= 400px) {
          .fr-r:nth-child(n + 4) {
            display: none;
          }
        }
        @container fitted-card (height < 170px) and (width < 400px) {
          .fr {
            display: none;
          }
        }
        @container fitted-card (height < 170px) and (width >= 400px) {
          .fr-r:nth-child(n + 2) {
            display: none;
          }
        }
      </style>
    </template>
  };
}

export default Role;
