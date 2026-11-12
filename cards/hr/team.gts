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
import type { ComponentLike } from '@glint/template';
import UsersIcon from '@cardstack/boxel-icons/users';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';

import { Employee, EmployeeStatusField } from './employee';
import {
  identifyCard,
  rri,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import { liveCount } from './utils';
import { RecordAtom, orEmpty } from '../procurement/vendor';
import {
  EmbCard,
  FitCard,
  FitRow,
  IsoHead,
  IsoPage,
  Kv,
  Panel,
  SheetLine,
  StatStrip,
  type StripItem,
} from './compact-sheet';

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
    // a member's status renders the Employee field's own dot format
    StatusAtom = EmployeeStatusField.atom as unknown as ComponentLike<{
      Args: { model?: string | null };
    }>;
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

    get sizeLabel(): string {
      return String(this.v.size);
    }

    get strip(): StripItem[] {
      let v = this.v;
      return [
        {
          label: 'Members',
          value: String(v.size),
          hint: v.leadName ? 'incl. lead' : undefined,
          tone: 'success',
        },
        {
          label: 'Projects',
          value: String(this.projects.length),
          hint: v.projectNames || undefined,
          tone: 'info',
        },
      ];
    }

    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.title}} @meta={{@model.mission}}>
            <:mark><Avatar
                @name={{orEmpty @model.title}}
                @hue='var(--muted)'
                @shape='rounded'
                @size={{36}}
                aria-hidden='true'
              /></:mark>
            <:stats><StatStrip @items={{this.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          {{#if @model.mission}}
            <Panel @title='Mission'><SheetLine
              >{{@model.mission}}</SheetLine></Panel>
          {{/if}}
          <Panel @title='Members' @meta={{this.sizeLabel}}>
            {{#if @model.lead}}
              <SheetLine>
                <@fields.lead @format='atom' @displayContainer={{false}} />
                <span class='sub'>{{#if @model.lead.role}}{{@model.lead.role}}
                    ·
                  {{/if}}lead</span>
                {{#if @model.lead.status}}<this.StatusAtom
                    @model={{@model.lead.status}}
                  />{{/if}}
              </SheetLine>
            {{/if}}
            {{#each this.v.others as |member|}}
              <SheetLine>
                {{#let (getComponent member) as |MemberCard|}}<MemberCard
                    @format='atom'
                    @displayContainer={{false}}
                  />{{/let}}
                <span class='sub'>{{member.role}}</span>
                {{#if member.status}}<this.StatusAtom
                    @model={{member.status}}
                  />{{/if}}
              </SheetLine>
            {{else}}
              {{#unless @model.lead}}<SheetLine><span class='sub'>No members
                    yet.</span></SheetLine>{{/unless}}
            {{/each}}
          </Panel>
        </:main>
        <:aside>
          <Panel @title='Linked'>
            <Kv @items={{this.linkedItems}}>
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
            </Kv>
          </Panel>
          <Panel @title='Details'><Kv @items={{this.detailItems}} /></Panel>
        </:aside>
      </IsoPage>
      <style scoped>
        .sub {
          flex: 1 1 6rem;
          min-width: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
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

    // `atom` marks a row whose value is a linked card: the lead, one row
    // per other member, one per project
    get rows() {
      let v = this.v;
      let ledBy = [v.leadName, v.leadRole].filter(Boolean).join(' · ');
      return [
        { key: 'Led by', value: orDash(ledBy) },
        { key: 'Headcount', value: v.headcount },
        { key: 'Lead', value: orDash(v.leadName) },
        { key: 'Members', value: orDash(v.memberNames) },
        { key: 'Projects', value: orDash(v.projectNames) },
        ...(this.args.model?.lead
          ? [{ key: 'Lead', value: '', atom: this.args.model.lead }]
          : []),
        ...v.others.map((x) => ({ key: 'Member', value: '', atom: x })),
        ...this.projects.map((x) => ({ key: 'Project', value: '', atom: x })),
      ];
    }

    <template>
      <EmbCard @title={{@model.title}} @meta={{@model.mission}}>
        <:mark><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted)'
            @shape='rounded'
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:default>
          <Kv @items={{this.rows}}>
            <:value as |row|>{{#if row.atom}}{{#let
                  (getComponent row.atom)
                  as |Linked|
                }}<Linked
                    @format='atom'
                    @displayContainer={{false}}
                  />{{/let}}{{else}}{{row.value}}{{/if}}</:value>
          </Kv>
        </:default>
      </EmbCard>
    </template>
  };

  // Atom: the team's name and its size.
  static atom = class Atom extends Component<typeof this> {
    get size() {
      return String(teamSize(this.args.model));
    }
    <template><RecordAtom @name={{@model.title}} /></template>
  };

  // Attribute-first: the size and lead come from the team's own denormalized
  // attributes; the relations render the linked people as their own atoms.
  static fitted = class Fitted extends Component<typeof this> {
    projectsQuery = teamProjects(this);

    get projects(): ProjectLike[] {
      return (this.projectsQuery?.instances ?? []).filter(Boolean);
    }

    get v() {
      return teamView(this.args.model, this.projects);
    }

    get strip(): StripItem[] {
      return [
        { label: 'Members', value: String(this.v.size) },
        { label: 'Projects', value: String(this.projects.length) },
      ];
    }

    <template>
      <FitCard @title={{@model.title}}>
        <:mark><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted)'
            @shape='rounded'
            @size={{20}}
            aria-hidden='true'
          /></:mark>
        <:default>
          <FitRow @label='Headcount'><span
              class='mono'
            >{{this.v.headcount}}</span></FitRow>
          {{#if @model.mission}}<FitRow @left={{true}}><span
                class='meta'
              >{{@model.mission}}</span></FitRow>{{/if}}
          {{#if @model.lead}}
            <FitRow @label='Lead' @left={{true}}><@fields.lead
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{else if this.v.leadName}}
            <FitRow @label='Lead'>{{this.v.leadName}}</FitRow>
          {{/if}}
          <FitRow @label='Projects'><span
              class='mono'
            >{{this.projects.length}}</span></FitRow>
          <StatStrip @compact={{true}} @items={{this.strip}} />
          {{#each @fields.members as |Member memberIndex|}}
            {{#unless (this.isLeadAt memberIndex)}}
              <FitRow @label='Member' @left={{true}}><Member
                  @format='atom'
                  @displayContainer={{false}}
                /></FitRow>
            {{/unless}}
          {{/each}}
          {{#each this.projects as |project|}}
            {{#let (getComponent project) as |ProjectCard|}}
              <FitRow @label='Project' @left={{true}}><ProjectCard
                  @format='atom'
                  @displayContainer={{false}}
                /></FitRow>
            {{/let}}
          {{/each}}
        </:default>
      </FitCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .mono {
          font: 500 0.6875rem var(--font-mono);
          color: var(--muted-foreground);
        }
      </style>
    </template>

    isLeadAt = (index: number) => {
      let member = this.args.model?.members?.[index];
      return Boolean(member && member.id === this.args.model?.lead?.id);
    };
  };
}
