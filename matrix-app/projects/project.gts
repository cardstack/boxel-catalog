import {
  CardDef,
  Component,
  field,
  contains,
  getComponent,
  linksTo,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import enumField from '@cardstack/base/enum';
import FolderKanbanIcon from '@cardstack/boxel-icons/folder-kanban';
import { eq } from '@cardstack/boxel-ui/helpers';
import { concat } from '@ember/helper';
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
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import { formatDate } from '../../ui-component/internal/reading-format';

import { DurationField } from '../hr/duration-field';
import { Employee } from '../hr/employee';
import { Team } from '../hr/team';
import {
  FittedExtras,
  RecordAtom,
  RecordEmbedded,
  RecordIsolated,
  Vendor,
  mediumDate,
  orEmpty,
  type FittedStat,
} from '../procurement/vendor';
import { durationInDays } from '../hr/duration-field';
import {
  identifyCard,
  rri,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';

const MS_PER_DAY = 1000 * 60 * 60 * 24;

interface ScheduleShape {
  startDate?: Date | null;
  estimatedEffort?: { value?: number | null; unit?: string | null } | null;
}

// One derivation, shared by both formats, so isolated and fitted can never
// report different progress for the same project.
function scheduleFacts(model: ScheduleShape) {
  let start = model.startDate ? new Date(model.startDate) : undefined;
  if (start && isNaN(start.getTime())) {
    start = undefined;
  }
  let days = durationInDays(
    model.estimatedEffort?.value,
    model.estimatedEffort?.unit,
  );
  let end: Date | undefined;
  if (start && days != null && days > 0) {
    end = new Date(start.getTime() + days * MS_PER_DAY);
  }
  let pct: number | undefined;
  if (start && end) {
    let span = end.getTime() - start.getTime();
    pct = Math.max(
      0,
      Math.min(100, Math.round(((Date.now() - start.getTime()) / span) * 100)),
    );
  }
  return { start, end, days, pct };
}

export const PROJECT_STATUSES = ['planned', 'active', 'done'];

// Only active reads as "go"; planned is amber because it is not yet
// happening, and done is blue so it reads as finished rather than healthy.
export const PROJECT_STATUS_HUES: Record<string, Hue> = {
  planned: 'amber',
  active: 'green',
  done: 'blue',
};

export const PROJECT_STATUS_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(PROJECT_STATUS_HUES).map(([k, hue]) => [k, stateColor(hue)]),
  );

// Only active reads as success; planned has not started, so it stays
// neutral, and done reads as information rather than health.
export const PROJECT_STATUS_TONES: Record<string, PretuiToneArg> = {
  planned: 'neutral',
  active: 'success',
  done: 'info',
};

function statusTone(status?: string | null): PretuiToneArg {
  return (status && PROJECT_STATUS_TONES[status]) || 'neutral';
}

// Contractors link to their project, never the other way round, so a
// project finds them live. The ref is resolved beside this module rather
// than imported: contractor.gts imports this module.
function contractorRef(): ResolvedCodeRef | undefined {
  let project = identifyCard(Project);
  return project && 'module' in project
    ? {
        module: rri(new URL('../hr/contractor', project.module).href),
        name: 'Contractor',
      }
    : undefined;
}

interface ContractorLike extends CardDef {
  vendorName?: string | null;
}

function projectContractors(owner: Component<typeof Project>) {
  return owner.args.context?.getCards(
    owner,
    () => {
      let id = owner.args.model?.id;
      let on = contractorRef();
      return id && on
        ? { filter: { on, every: [{ eq: { 'project.id': id } }] } }
        : undefined;
    },
    () => {
      let url = owner.args.model?.[realmURL]?.href;
      return url ? [url] : [];
    },
    { isLive: true },
  );
}

const SHORT_DATE = { month: 'short', day: 'numeric' } as const;

function effortLabel(effort?: { value?: number | null; unit?: string | null }) {
  if (effort?.value == null || !effort.unit) {
    return undefined;
  }
  let unit = effort.value === 1 ? effort.unit.replace(/s$/, '') : effort.unit;
  return `${effort.value} ${unit}`;
}

function capitalize(value?: string | null): string | undefined {
  return value ? value[0].toUpperCase() + value.slice(1) : undefined;
}

// Every format reads the same labels, so a tile and the isolated view can
// never word the same project differently.
function projectView(m?: Partial<Project>, contractors: ContractorLike[] = []) {
  let { start, end } = scheduleFacts(m ?? {});
  let startLabel = mediumDate(start);
  let endShort = end ? formatDate(end, 'en-US', SHORT_DATE) : undefined;
  let lead = m?.lead?.name || m?.leadName || undefined;
  let team = m?.team?.name || m?.teamName || undefined;
  let vendor = m?.vendor?.name || m?.vendorName || undefined;
  let vendors = [
    ...new Set(contractors.map((c) => c.vendorName).filter(Boolean)),
  ].join(', ');
  return {
    startLabel,
    endShort,
    effort: effortLabel(m?.estimatedEffort ?? undefined),
    statusLabel: capitalize(m?.status),
    statusTone: statusTone(m?.status),
    lead,
    team,
    vendor,
    contractorCount: String(contractors.length),
    contractorVendors: vendors || undefined,
  };
}

function orDash(value?: string) {
  return value || '—';
}

export const ProjectStatusField = enumField(StringField, {
  options: PROJECT_STATUSES.map((status) => ({ value: status, label: status })),
  displayName: 'Project Status',
});

export class Project extends CardDef {
  static displayName = 'Project';
  static icon = FolderKanbanIcon;

  @field name = contains(StringField);
  @field description = contains(StringField);
  @field status = contains(ProjectStatusField);
  @field lead = linksTo(() => Employee);
  @field team = linksTo(() => Team);
  @field vendor = linksTo(() => Vendor);
  @field startDate = contains(DateField);
  @field estimatedEffort = contains(DurationField);

  // Denormalized for fitted — prerendered fitted does not resolve linksTo.
  @field leadName = contains(StringField, {
    computeVia: function (this: Project) {
      return this.lead?.name ?? '';
    },
  });

  @field teamName = contains(StringField, {
    computeVia: function (this: Project) {
      return this.team?.name ?? '';
    },
  });

  @field vendorName = contains(StringField, {
    computeVia: function (this: Project) {
      return this.vendor?.name ?? '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Project) {
      return this.name?.trim() || 'Unnamed Project';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    contractorsQuery = projectContractors(this);

    get contractors(): ContractorLike[] {
      return (this.contractorsQuery?.instances ?? []).filter(Boolean);
    }

    get v() {
      return projectView(this.args.model, this.contractors);
    }

    get statuses() {
      let current = this.args.model?.status;
      return PROJECT_STATUSES.map((status) => ({
        status,
        tone: (status === current ? 'info' : 'neutral') as PretuiToneArg,
      }));
    }

    get scheduleItems(): KeyValueItem[] {
      return [
        { key: 'Start date', value: orDash(this.v.startLabel) },
        { key: 'Estimated effort', value: orDash(this.v.effort) },
      ];
    }

    get linkedItems(): KeyValueItem[] {
      return [
        { key: 'Lead', value: '— none' },
        { key: 'Team', value: '— none' },
        { key: 'Vendor', value: '— none' },
      ];
    }

    get detailItems(): KeyValueItem[] {
      let v = this.v;
      return [
        { key: 'Start', value: orDash(v.startLabel) },
        { key: 'Effort', value: orDash(v.effort) },
        { key: 'Lead', value: orDash(v.lead) },
        { key: 'Team', value: orDash(v.team) },
        { key: 'Vendor', value: orDash(v.vendor) },
        { key: 'Contractors', value: v.contractorCount },
      ];
    }

    <template>
      <RecordIsolated @title={{@model.title}} @subtitle={{@model.description}}>
        <:avatar><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted-foreground)'
            @size={{48}}
            aria-hidden='true'
          /></:avatar>
        <:chips>
          {{#if @model.status}}
            <StatusChip @value={{@model.status}} @tone={{this.v.statusTone}} />
          {{/if}}
          {{#if this.v.effort}}
            <StatusChip @value={{this.v.effort}} @tone='info' />
          {{/if}}
        </:chips>
        <:stats>
          <Panel><Stat
              @label='Status'
              @value={{orDash this.v.statusLabel}}
              @hint={{if
                this.v.startLabel
                (concat 'starts ' this.v.startLabel)
              }}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Effort'
              @value={{orDash this.v.effort}}
              @hint='estimate'
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Contractors'
              @value={{this.contractors.length}}
              @hint={{this.v.contractorVendors}}
              @roll={{false}}
            /></Panel>
        </:stats>
        <:main>
          {{#if @model.description}}
            <Panel @title='Description'>
              <p class='iso-text'>{{@model.description}}</p>
            </Panel>
          {{/if}}
          <Panel @title='Status'>
            <div class='status-row'>
              {{#each this.statuses as |s|}}
                <StatusChip @value={{s.status}} @tone={{s.tone}} />
              {{/each}}
            </div>
          </Panel>
          <Panel @title='Schedule'>
            <KeyValue @items={{this.scheduleItems}} />
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
                {{else if (eq row.key 'Team')}}
                  {{#if @model.team}}<@fields.team
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}{{row.value}}{{/if}}
                {{else}}
                  {{#if @model.vendor}}<@fields.vendor
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}{{row.value}}{{/if}}
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
          .status-row {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    contractorsQuery = projectContractors(this);

    get contractors(): ContractorLike[] {
      return (this.contractorsQuery?.instances ?? []).filter(Boolean);
    }

    get v() {
      return projectView(this.args.model, this.contractors);
    }

    get kvItems() {
      let v = this.v;
      return [
        { label: 'Start', value: v.startLabel },
        { label: 'Effort', value: v.effort },
        { label: 'Lead', value: v.lead },
        { label: 'Team', value: v.team },
        { label: 'Vendor', value: v.vendor },
        { label: 'Contractors', value: v.contractorCount },
      ];
    }

    <template>
      <RecordEmbedded @title={{@model.title}} @subtitle={{@model.description}}>
        <:avatar><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted-foreground)'
            @size={{40}}
            aria-hidden='true'
          /></:avatar>
        <:chips>
          {{#if @model.status}}
            <StatusChip @value={{@model.status}} @tone={{this.v.statusTone}} />
          {{/if}}
          {{#if this.v.effort}}
            <StatusChip @value={{this.v.effort}} @tone='info' />
          {{/if}}
        </:chips>
        <:fact>{{#if this.v.startLabel}}Starts
            <b class='strong'>{{this.v.startLabel}}</b>{{#if this.v.endShort}}
              &middot; ends ~{{this.v.endShort}}{{/if}}{{/if}}</:fact>
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
          {{#if @model.team}}
            <span class='rel'>Team
              <@fields.team @format='atom' @displayContainer={{false}} /></span>
          {{/if}}
          {{#if @model.vendor}}
            <span class='rel'>Vendor
              <@fields.vendor
                @format='atom'
                @displayContainer={{false}}
              /></span>
          {{/if}}
          {{#each this.contractors as |contractor|}}
            {{#let (getComponent contractor) as |ContractorCard|}}
              <span class='rel'>Contractor
                <ContractorCard
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
  };

  // Atom: the project's name and its status.
  static atom = class Atom extends Component<typeof this> {
    get tone() {
      return statusTone(this.args.model?.status);
    }
    <template>
      <RecordAtom @name={{@model.title}}>
        {{#if @model.status}}
          <StatusChip @value={{@model.status}} @tone={{this.tone}} />
        {{/if}}
      </RecordAtom>
    </template>
  };

  // Attribute-first: names come from the project's own denormalized
  // attributes; the relations render the linked cards as their own atoms.
  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return projectView(this.args.model);
    }

    get facts(): KeyValueItem[] {
      let v = this.v;
      return [
        { key: 'Start', value: orDash(v.startLabel) },
        { key: 'Effort', value: orDash(v.effort) },
        { key: 'Lead', value: orDash(v.lead) },
        { key: 'Team', value: orDash(v.team) },
        { key: 'Vendor', value: orDash(v.vendor) },
      ];
    }

    get stats(): FittedStat[] {
      let v = this.v;
      return [
        { key: 'Status', value: orDash(v.statusLabel) },
        { key: 'Effort', value: orDash(v.effort) },
        { key: 'Start', value: orDash(v.startLabel) },
      ];
    }

    get relations() {
      let m = this.args.model;
      return [
        ...(m?.leadName ? ['Lead'] : []),
        ...(m?.teamName ? ['Team'] : []),
        ...(m?.vendorName ? ['Vendor'] : []),
      ];
    }

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
            <:subtitle>{{@model.description}}</:subtitle>
            <:status>
              {{#if @model.status}}
                <StatusChip
                  @value={{@model.status}}
                  @tone={{this.v.statusTone}}
                />
              {{/if}}
              {{#if this.v.effort}}
                <StatusChip @value={{this.v.effort}} @tone='info' />
              {{/if}}
            </:status>
            <:fact>{{#if this.v.startLabel}}Starts
                {{this.v.startLabel}}{{#if this.v.endShort}}
                  &middot; ends ~{{this.v.endShort}}{{/if}}{{/if}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          {{#if (eq label 'Lead')}}
            <@fields.lead @format='atom' />
          {{else if (eq label 'Team')}}
            <@fields.team @format='atom' />
          {{else}}
            <@fields.vendor @format='atom' />
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
