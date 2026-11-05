import {
  CardDef,
  Component,
  field,
  contains,
  getComponent,
  linksTo,
  linksToMany,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import UsersIcon from '@cardstack/boxel-icons/users';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '../../ui-component/components/avatar';
import { Descriptions } from '../../ui-component/components/descriptions';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';

import { EMPLOYEE_STATUS_TONES, Employee } from './employee';
import {
  identifyCard,
  rri,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import { liveCount } from './utils';
import {
  FittedExtras,
  RecordAtom,
  RecordEmbedded,
  RecordIsolated,
  orEmpty,
  type FittedStat,
} from '../procurement/vendor';

// Projects link to their team, never the other way round, so a team finds
// its projects live. The ref is resolved beside this module rather than
// imported: project.gts imports this module.
function projectRef(): ResolvedCodeRef | undefined {
  let team = identifyCard(Team);
  return team && 'module' in team
    ? {
        module: rri(new URL('../projects/project', team.module).href),
        name: 'Project',
      }
    : undefined;
}

type ProjectLike = CardDef & { title?: string | null };

function teamProjects(owner: Component<typeof Team>) {
  return owner.args.context?.getCards(
    owner,
    () => {
      let id = owner.args.model?.id;
      let on = projectRef();
      return id && on
        ? { filter: { on, every: [{ eq: { 'team.id': id } }] } }
        : undefined;
    },
    () => {
      let url = owner.args.model?.[realmURL]?.href;
      return url ? [url] : [];
    },
    { isLive: true },
  );
}

function plural(n: number, one: string, many: string) {
  return `${n} ${n === 1 ? one : many}`;
}

// The lead counts toward the team's size whether or not they are also
// listed as a member.
function teamSize(m?: Partial<Team>): number {
  let members = (m?.members ?? []).filter(Boolean);
  let lead = m?.lead;
  let leadExtra = lead && !members.some((x) => x.id === lead!.id) ? 1 : 0;
  // prerendered fitted has no resolved links, only the denormalized tally
  return members.length
    ? members.length + leadExtra
    : Number(m?.memberTally || 0) + (m?.leadName ? 1 : 0);
}

function teamView(m?: Partial<Team>, projects: ProjectLike[] = []) {
  let size = teamSize(m);
  let members = (m?.members ?? []).filter(Boolean);
  let lead = m?.lead;
  let others = members.filter((x) => x.id !== lead?.id);
  let leadName = lead?.name || m?.leadName || undefined;
  let leadRole = lead?.role || undefined;
  return {
    size,
    headcount: plural(size, 'member', 'members'),
    leadName,
    leadRole,
    others,
    memberNames: others
      .map((x) => x.name)
      .filter(Boolean)
      .join(', '),
    projectCount: projects.length
      ? plural(projects.length, 'project', 'projects')
      : undefined,
    projectNames: projects.map((p) => p.title).join(', '),
  };
}

function orDash(value?: string) {
  return value || '—';
}

function memberTone(status?: string | null) {
  return (status && EMPLOYEE_STATUS_TONES[status]) || 'neutral';
}

export class Team extends CardDef {
  static displayName = 'Team';
  static icon = UsersIcon;

  @field name = contains(StringField);
  @field mission = contains(StringField);
  @field lead = linksTo(() => Employee);
  @field members = linksToMany(() => Employee);

  @field title = contains(StringField, {
    computeVia: function (this: Team) {
      return this.name?.trim() || 'Unnamed Team';
    },
  });

  // Denormalized for fitted: prerendered fitted does not resolve linksTo,
  // so the lead's name and the member tally must exist as own attributes.
  @field leadName = contains(StringField, {
    computeVia: function (this: Team) {
      return this.lead?.name ?? '';
    },
  });

  @field memberTally = contains(StringField, {
    computeVia: function (this: Team) {
      return String(liveCount(this.members));
    },
  });

  @field headcount = contains(StringField, {
    computeVia: function (this: Team): string {
      return plural(teamSize(this), 'member', 'members');
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    projectsQuery = teamProjects(this);

    get projects(): ProjectLike[] {
      return (this.projectsQuery?.instances ?? []).filter(Boolean);
    }

    get v() {
      return teamView(this.args.model, this.projects);
    }

    get detailItems(): KeyValueItem[] {
      let v = this.v;
      return [
        { key: 'Headcount', value: v.headcount },
        { key: 'Lead', value: orDash(v.leadName) },
        { key: 'Members', value: orDash(v.memberNames) },
        { key: 'Projects', value: orDash(v.projectNames) },
      ];
    }

    <template>
      <RecordIsolated @title={{@model.title}} @subtitle={{@model.mission}}>
        <:avatar><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted-foreground)'
            @size={{48}}
            aria-hidden='true'
          /></:avatar>
        <:chips>
          <StatusChip @value={{this.v.headcount}} @tone='neutral' />
          {{#if this.v.projectCount}}
            <StatusChip @value={{this.v.projectCount}} @tone='info' />
          {{/if}}
        </:chips>
        <:stats>
          <Panel><Stat
              @label='Members'
              @value={{this.v.size}}
              @hint={{if this.v.leadName 'incl. lead'}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Projects'
              @value={{this.projects.length}}
              @hint={{this.v.projectNames}}
              @roll={{false}}
            /></Panel>
        </:stats>
        <:main>
          {{#if @model.mission}}
            <Panel @title='Mission'>
              <p class='iso-text'>{{@model.mission}}</p>
            </Panel>
          {{/if}}
          <Panel @title='Members'>
            {{#if this.v.size}}
              <ul class='members'>
                {{#if @model.lead}}
                  <li class='member'>
                    <span class='member-id'>
                      <span class='member-name'>{{@model.lead.name}}</span>
                      <span class='member-sub'>{{#if
                          @model.lead.role
                        }}{{@model.lead.role}}
                          &middot;
                        {{/if}}lead</span>
                    </span>
                    {{#if @model.lead.status}}
                      <StatusChip
                        @value={{@model.lead.status}}
                        @tone={{memberTone @model.lead.status}}
                      />
                    {{/if}}
                  </li>
                {{/if}}
                {{#each this.v.others as |member|}}
                  <li class='member'>
                    <span class='member-id'>
                      <span class='member-name'>{{member.name}}</span>
                      {{#if member.role}}
                        <span class='member-sub'>{{member.role}}</span>
                      {{/if}}
                    </span>
                    {{#if member.status}}
                      <StatusChip
                        @value={{member.status}}
                        @tone={{memberTone member.status}}
                      />
                    {{/if}}
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class='iso-text'>No members yet.</p>
            {{/if}}
          </Panel>
        </:main>
        <:side>
          <Panel @title='Linked'>
            <KeyValue @items={{this.linkedItems}}>
              <:value as |row|>
                {{#if (eq row.key 'Lead')}}
                  {{#if @model.lead}}<@fields.lead
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}{{row.value}}{{/if}}
                {{else}}
                  {{#each this.projects as |project|}}
                    {{#let (getComponent project) as |ProjectCard|}}
                      <ProjectCard @format='atom' @displayContainer={{false}} />
                    {{/let}}
                  {{else}}
                    {{row.value}}
                  {{/each}}
                {{/if}}
              </:value>
            </KeyValue>
          </Panel>
          <Panel @title='Details'>
            <KeyValue @items={{this.detailItems}} />
          </Panel>
        </:side>
      </RecordIsolated>
      <style scoped>
        @layer PretComponent {
          .iso-text {
            margin: 0;
          }
          .members {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            margin: 0;
            padding: 0;
            list-style: none;
          }
          .member {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-sm);
          }
          .member-id {
            display: flex;
            flex-direction: column;
            min-inline-size: 0;
          }
          .member-name {
            font-weight: 600;
          }
          .member-sub {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
        }
      </style>
    </template>

    get linkedItems(): KeyValueItem[] {
      return [
        { key: 'Lead', value: '— none' },
        { key: 'Project', value: '— none' },
      ];
    }
  };

  static embedded = class Embedded extends Component<typeof this> {
    projectsQuery = teamProjects(this);

    get projects(): ProjectLike[] {
      return (this.projectsQuery?.instances ?? []).filter(Boolean);
    }

    get v() {
      return teamView(this.args.model, this.projects);
    }

    get kvItems() {
      let v = this.v;
      return [
        { label: 'Headcount', value: v.headcount },
        { label: 'Lead', value: v.leadName },
        { label: 'Members', value: v.memberNames || undefined },
        { label: 'Projects', value: v.projectNames || undefined },
      ];
    }

    <template>
      <RecordEmbedded @title={{@model.title}} @subtitle={{@model.mission}}>
        <:avatar><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted-foreground)'
            @size={{40}}
            aria-hidden='true'
          /></:avatar>
        <:chips>
          <StatusChip @value={{this.v.headcount}} @tone='neutral' />
          {{#if this.v.projectCount}}
            <StatusChip @value={{this.v.projectCount}} @tone='info' />
          {{/if}}
        </:chips>
        <:fact>{{#if this.v.leadName}}Led by
            <b class='strong'>{{this.v.leadName}}</b>{{#if this.v.leadRole}}
              &middot;
              {{this.v.leadRole}}{{/if}}{{/if}}</:fact>
        <:details><Descriptions
            @items={{this.kvItems}}
            @layout='vertical'
            @columns={{3}}
          /></:details>
        <:relations>
          {{#if @model.lead}}
            <span class='rel'>Lead
              <@fields.lead @format='atom' @displayContainer={{false}} /></span>
          {{/if}}
          {{#each @fields.members as |Member index|}}
            {{#unless (this.isLead index)}}
              <span class='rel'>Member
                <Member @format='atom' @displayContainer={{false}} /></span>
            {{/unless}}
          {{/each}}
          {{#each this.projects as |project|}}
            {{#let (getComponent project) as |ProjectCard|}}
              <span class='rel'>Project
                <ProjectCard
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/let}}
          {{/each}}
        </:relations>
      </RecordEmbedded>
      <style scoped>
        @layer PretComponent {
          .strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-inline-size: 0;
            max-inline-size: 100%;
          }
        }
      </style>
    </template>

    isLead = (index: number) => {
      let member = this.args.model?.members?.[index];
      return Boolean(member && member.id === this.args.model?.lead?.id);
    };
  };

  // Atom: the team's name and its size.
  static atom = class Atom extends Component<typeof this> {
    get size() {
      return String(teamSize(this.args.model));
    }
    <template>
      <RecordAtom @name={{@model.title}}>
        <StatusChip @value={{this.size}} @tone='neutral' />
      </RecordAtom>
    </template>
  };

  // Attribute-first: the size and lead come from the team's own denormalized
  // attributes; the relations render the linked people as their own atoms.
  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return teamView(this.args.model);
    }

    get facts(): KeyValueItem[] {
      let v = this.v;
      return [
        { key: 'Headcount', value: v.headcount },
        { key: 'Lead', value: orDash(v.leadName) },
        { key: 'Members', value: orDash(v.memberNames) },
      ];
    }

    get stats(): FittedStat[] {
      let v = this.v;
      return [
        { key: 'Members', value: String(v.size) },
        { key: 'Lead', value: orDash(v.leadName) },
      ];
    }

    // 'Lead' first, then one 'Member' per member who isn't the lead
    get relations() {
      let m = this.args.model;
      let lead = m?.lead;
      let members = (m?.members ?? []).filter(Boolean);
      return [
        ...(lead ? ['Lead'] : []),
        ...members.filter((x) => x.id !== lead?.id).map(() => 'Member'),
      ];
    }

    // The member atom for relation row `index`: the rows after the lead's
    // map onto the members who aren't the lead, in order.
    isMemberRow = (memberIndex: number, row: number) => {
      let m = this.args.model;
      let lead = m?.lead;
      let members = m?.members ?? [];
      if (members[memberIndex]?.id === lead?.id) {
        return false;
      }
      let before = members
        .slice(0, memberIndex)
        .filter((x) => x && x.id !== lead?.id).length;
      return before + (lead ? 1 : 0) === row;
    };

    <template>
      <FittedExtras
        @facts={{this.facts}}
        @stats={{this.stats}}
        @relations={{this.relations}}
      >
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name={{orEmpty @model.title}}
                @hue='var(--muted-foreground)'
                @size={{32}}
                aria-hidden='true'
              />
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.title}}</span></:title>
            <:subtitle>{{@model.mission}}</:subtitle>
            <:status>
              <StatusChip @value={{this.v.headcount}} @tone='neutral' />
            </:status>
            <:fact>{{#if this.v.leadName}}Led by
                {{this.v.leadName}}{{#if this.v.leadRole}}
                  &middot;
                  {{this.v.leadRole}}{{/if}}{{/if}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label row|>
          {{#if (eq label 'Lead')}}
            <@fields.lead @format='atom' />
          {{else}}
            {{#each @fields.members as |Member memberIndex|}}
              {{#if (this.isMemberRow memberIndex row)}}
                <Member @format='atom' />
              {{/if}}
            {{/each}}
          {{/if}}
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
        }
      </style>
    </template>
  };
}
