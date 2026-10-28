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
import { Employee } from '../hr/employee';
import { get } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Chip } from '../../ui-component/components/chip';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import {
  FittedExtras,
  type FittedProgress,
  type FittedStat,
} from '../procurement/vendor';

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
  let facts: KeyValueItem[] = [
    { key: 'Members', value: String(members.length) },
    { key: 'On duty', value: dutyName ?? '—' },
    { key: 'Permissions', value: String(permissions.length) },
    ...permissions.map((p) => ({ key: 'Can', value: p })),
  ];
  let progress: FittedProgress | undefined = members.length
    ? {
        label: 'On duty',
        value: dutyName ? Math.round(100 / members.length) : 0,
        valueText: `${dutyName ? 1 : 0} of ${plural(members.length, 'member')}`,
      }
    : undefined;
  return {
    name: m?.title ?? 'Role',
    memberCount: members.length,
    membersChip: plural(members.length, 'Member'),
    onDuty: Boolean(m?.onDuty),
    dutyName,
    subline: [plural(members.length, 'member'), grantPhrase(permissions[0])]
      .filter(Boolean)
      .join(' · '),
    facts,
    progress,
    permissions,
    permissionsHint: permissions.join(', '),
    // true where the member is the one on duty (the duty atom already shows them)
    dutyFlags: members.map((x) => Boolean(dutyId) && x.id === dutyId),
    memberRows: members.map((x) => ({
      name: (x.name as string | undefined) ?? 'Member',
      sub: [x.role, x.id === dutyId ? 'on duty' : undefined]
        .filter(Boolean)
        .join(' · '),
      duty: Boolean(dutyId) && x.id === dutyId,
    })),
    relations: [
      ...(m?.onDuty ? ['On duty'] : []),
      ...(members.some((x) => x.id !== dutyId) ? ['Member'] : []),
    ],
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
        <header class='emb-head'>
          <span class='mark' aria-hidden='true'>Ro</span>
          <div class='emb-id'>
            <h3 class='emb-title'>{{this.v.name}}</h3>
            <p class='emb-sub'>{{this.v.subline}}</p>
          </div>
          <span class='emb-chips'>
            <Chip
              @tone='neutral'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.membersChip}}</Chip>
            {{#if this.v.onDuty}}<Chip
                @tone='success'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >On Duty</Chip>{{/if}}
          </span>
        </header>
        {{#if this.v.dutyName}}<p class='emb-duty'>On duty:
            <b>{{this.v.dutyName}}</b></p>{{/if}}
        <KeyValue class='emb-facts' @items={{this.v.facts}} @layout='stacked' />
        <div class='emb-rels'>
          {{#if this.v.onDuty}}<span class='emb-rel'><span class='emb-rel-k'>On
                duty</span><@fields.onDuty
                @format='atom'
                @displayContainer={{false}}
              /></span>{{/if}}
          {{#each @fields.members as |Member i|}}
            {{#unless (get this.v.dutyFlags i)}}<span class='emb-rel'><span
                  class='emb-rel-k'
                >Member</span><Member
                  @format='atom'
                  @displayContainer={{false}}
                /></span>{{/unless}}
          {{/each}}
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            container-type: inline-size;
            display: grid;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
          }
          .emb-head {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .emb-id {
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
          }
          .emb-sub,
          .emb-duty {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .emb-duty b {
            font-weight: 600;
            color: var(--foreground);
          }
          .emb-chips {
            display: inline-flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-facts {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
            grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-sm);
          }
          .emb-rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            font-weight: 600;
          }
          .emb-rel-k {
            font-weight: 400;
            color: var(--muted-foreground);
          }
          @container (max-width: 25rem) {
            .emb-head {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .emb-chips {
              grid-column: 1 / -1;
            }
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get v() {
      return roleView(this.args.model);
    }
    <template>
      <span class='atom'>
        <span class='atom-mark' aria-hidden='true'>Ro</span>
        <span class='atom-name'>{{this.v.name}}</span>
        {{#if this.v.onDuty}}<Chip
            @tone='success'
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          >On Duty</Chip>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            font-size: var(--boxel-font-size-sm);
          }
          .atom-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 1.25rem;
            block-size: 1.25rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          .atom-name {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: 600;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get v() {
      return roleView(this.args.model);
    }
    <template>
      <article class='iso'>
        <header class='iso-head'>
          <span class='iso-mark' aria-hidden='true'>Ro</span>
          <div class='iso-id'>
            <h1 class='iso-title'>{{this.v.name}}</h1>
            <p class='iso-sub'>{{this.v.subline}}</p>
          </div>
          <span class='iso-chips'>
            <Chip
              @tone='neutral'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.membersChip}}</Chip>
            {{#if this.v.onDuty}}<Chip
                @tone='success'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >On Duty</Chip>{{/if}}
          </span>
        </header>
        <div class='iso-stats'>
          <Panel><Stat
              @label='Members'
              @value={{this.v.memberCount}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Permissions'
              @value={{this.v.permissions.length}}
              @hint={{this.v.permissionsHint}}
              @roll={{false}}
            /></Panel>
        </div>
        <div class='iso-grid'>
          <div class='iso-col'>
            <Panel @title='Members'>
              <ul class='iso-rows'>
                {{#each this.v.memberRows as |r|}}
                  <li class='iso-row'>
                    <span class='iso-row-id'>
                      <span class='iso-row-name'>{{r.name}}</span>
                      <span class='iso-row-sub'>{{r.sub}}</span>
                    </span>
                    <Chip
                      @tone={{if r.duty 'success' 'neutral'}}
                      @appearance='soft'
                      @shape='pill'
                      @dot={{false}}
                    >{{if r.duty 'On Duty' 'Member'}}</Chip>
                  </li>
                {{/each}}
              </ul>
            </Panel>
            {{#if this.v.permissions.length}}
              <Panel @title='Permissions'>
                <div class='iso-grants'>
                  {{#each this.v.permissions as |p|}}
                    <Chip
                      @tone='neutral'
                      @appearance='soft'
                      @shape='pill'
                      @dot={{false}}
                    >{{p}}</Chip>
                  {{/each}}
                </div>
              </Panel>
            {{/if}}
          </div>
          <div class='iso-col'>
            <Panel @title='Linked'>
              <div class='iso-links'>
                {{#if this.v.onDuty}}<span class='iso-link'><span
                      class='iso-link-k'
                    >On duty</span><span class='iso-link-v'><@fields.onDuty
                        @format='atom'
                        @displayContainer={{false}}
                      /></span></span>{{/if}}
                {{#each @fields.members as |Member i|}}
                  {{#unless (get this.v.dutyFlags i)}}<span
                      class='iso-link'
                    ><span class='iso-link-k'>Member</span><span
                        class='iso-link-v'
                      ><Member
                          @format='atom'
                          @displayContainer={{false}}
                        /></span></span>{{/unless}}
                {{/each}}
              </div>
            </Panel>
            <Panel @title='Details'>
              <KeyValue @items={{this.v.facts}} @rows='ruled' />
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .iso {
            container-type: inline-size;
            display: grid;
            gap: var(--boxel-sp);
            padding: var(--boxel-sp-lg);
          }
          .iso-head {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .iso-title {
            margin: 0;
            font-size: 1.5rem;
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary-ink);
          }
          .iso-sub {
            margin: 0;
            color: var(--muted-foreground);
          }
          .iso-chips,
          .iso-grants {
            display: inline-flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .iso-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
            gap: var(--boxel-sp);
          }
          .iso-grid {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
            gap: var(--boxel-sp);
            align-items: start;
          }
          .iso-col {
            display: grid;
            gap: var(--boxel-sp);
            min-width: 0;
          }
          .iso-rows {
            margin: 0;
            padding: 0;
            list-style: none;
            display: grid;
          }
          .iso-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            padding-block: var(--boxel-sp-xs);
            border-bottom: 1px solid var(--border);
          }
          .iso-row:last-child {
            border-bottom: 0;
          }
          .iso-row-id {
            display: grid;
            min-width: 0;
          }
          .iso-row-name {
            font-weight: 600;
          }
          .iso-row-sub {
            color: var(--muted-foreground);
          }
          .iso-links {
            display: grid;
            gap: var(--boxel-sp-xs);
          }
          .iso-link {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            padding-bottom: var(--boxel-sp-xs);
            border-bottom: 1px solid var(--border);
          }
          .iso-link-k {
            color: var(--muted-foreground);
          }
          .iso-link-v {
            display: inline-flex;
            align-items: center;
            min-width: 0;
            font-weight: 600;
          }
          .iso-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2.5rem;
            block-size: 2.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          @container (max-width: 40rem) {
            .iso-head {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .iso-chips {
              grid-column: 1 / -1;
            }
            .iso-grid {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return roleView(this.args.model);
    }
    get stats(): FittedStat[] {
      return [
        { key: 'Members', value: String(this.v.memberCount) },
        { key: 'Permissions', value: String(this.v.permissions.length) },
      ];
    }

    <template>
      <FittedExtras
        @facts={{this.v.facts}}
        @stats={{this.stats}}
        @progress={{this.v.progress}}
        @relations={{this.v.relations}}
      >
        <:default>
          <FitTile>
            <:avatar>
              {{! the record's type mark, not a person: a square, not an Avatar }}
              <span class='fit-mark' aria-hidden='true'>Ro</span>
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{this.v.name}}</span></:title>
            <:subtitle>{{this.v.subline}}</:subtitle>
            <:status>
              <Chip
                @tone='neutral'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.membersChip}}</Chip>
              {{#if this.v.onDuty}}<Chip
                  @tone='success'
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                >On Duty</Chip>{{/if}}
            </:status>
            <:fact>{{#if this.v.dutyName}}On duty:
                <b class='fit-strong'>{{this.v.dutyName}}</b>{{/if}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          <span class='fit-rel'>
            {{#if (eq label 'On duty')}}
              <@fields.onDuty @format='atom' @displayContainer={{false}} />
            {{else}}
              {{#each @fields.members as |Member i|}}
                {{#unless (get this.v.dutyFlags i)}}<Member
                    @format='atom'
                    @displayContainer={{false}}
                  />{{/unless}}
              {{/each}}
            {{/if}}
          </span>
        </:relation>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .fit-strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .fit-rel {
            display: block;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: 600;
          }
          .fit-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };
}

export default Role;
