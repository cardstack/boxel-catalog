import { markDefinition } from '@cardstack/base/mark-definition';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import { dotEnumField } from '../hr/dot-enum-field';
import FolderKanbanIcon from '@cardstack/boxel-icons/folder-kanban';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import {
  EmbCard,
  IsoHead,
  IsoPage,
  Kv,
  Panel,
  SheetLine,
  StatStrip,
  type StripItem,
} from '../shared/compact-sheet';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { formatDate } from '@cardstack/pretui/internal/reading-format';

import { DurationField } from '../hr/duration-field';
import { Employee } from '../hr/employee';
import { Team } from '../hr/team';
import { RecordAtom, Vendor, mediumDate } from '../procurement/vendor';
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

export const ProjectStatusField = markDefinition(
  dotEnumField(
    {
      options: PROJECT_STATUSES.map((status) => ({
        value: status,
        label: status,
      })),
      displayName: 'Project Status',
    },
    PROJECT_STATUS_HUES,
  ),
);

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

    get strip(): StripItem[] {
      let v = this.v;
      return [
        {
          label: 'Status',
          value: v.statusLabel,
          hint: v.startLabel ? 'starts ' + v.startLabel : undefined,
        },
        { label: 'Effort', value: v.effort, hint: 'estimate', tone: 'info' },
        {
          label: 'Contractors',
          value: String(this.contractors.length),
          hint: v.contractorVendors,
          tone: 'success',
        },
      ];
    }

    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.title}} @meta={{@model.description}}>
            <:mark><Avatar
                @name={{if @model.title @model.title ''}}
                @hue='var(--muted)'
                @shape='rounded'
                @size={{36}}
                aria-hidden='true'
              /></:mark>
            <:aside>{{#if @model.status}}<@fields.status
                  @format='atom'
                  @displayContainer={{false}}
                />{{/if}}</:aside>
            <:stats><StatStrip @items={{this.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          {{#if @model.description}}
            <Panel @title='Description'><SheetLine
              >{{@model.description}}</SheetLine></Panel>
          {{/if}}
          <Panel @title='Status'>
            <SheetLine>
              {{#each this.statuses as |s|}}
                <span
                  class='step'
                  data-on={{if (eq s.tone 'info') 'true'}}
                >{{s.status}}</span>
              {{/each}}
            </SheetLine>
          </Panel>
          <Panel @title='Schedule'><Kv @items={{this.scheduleItems}} /></Panel>
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
                {{else if (eq row.key 'Team')}}
                  {{#if @model.team}}<@fields.team
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}{{row.value}}{{/if}}
                {{else if (eq row.key 'Vendor')}}
                  {{#if @model.vendor}}<@fields.vendor
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}{{row.value}}{{/if}}
                {{else}}{{row.value}}{{/if}}
              </:value>
            </Kv>
          </Panel>
          <Panel @title='Details'><Kv @items={{this.detailItems}} /></Panel>
        </:aside>
      </IsoPage>
      <style scoped>
        .step {
          color: var(--muted-foreground);
        }
        .step[data-on] {
          font-weight: 700;
          color: var(--foreground);
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

    get rows() {
      return [
        ...this.kvItems.map((i: { label: string; value?: string }) => ({
          key: i.label,
          value: i.value ?? '—',
        })),
      ];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{@model.description}}>
        <:mark><Avatar
            @name={{if @model.title @model.title ''}}
            @hue='var(--muted)'
            @shape='rounded'
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:aside>
        <:default>
          <Kv @items={{this.rows}}>
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
              {{else if (eq row.key 'Vendor')}}
                {{#if @model.vendor}}<@fields.vendor
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}{{row.value}}{{/if}}
              {{else}}{{row.value}}{{/if}}
            </:value>
          </Kv>
        </:default>
      </EmbCard>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template><RecordAtom @name={{@model.title}} /></template>
  };

  // Attribute-first: names come from the project's own denormalized
  // attributes; the relations render the linked cards as their own atoms.
  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return projectView(this.args.model);
    }

    get leadStat(): StripItem | undefined {
      return this.strip[0];
    }

    get strip(): StripItem[] {
      let v = this.v;
      return [
        { label: 'Effort', value: v.effort ?? '—' },
        { label: 'Status', value: v.statusLabel ?? '—' },
      ];
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name={{if @model.title @model.title ''}}
            @hue='var(--muted)'
            @shape='rounded'
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.title}}</:title>
        <:status>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:status>
        <:subtitle><span class='meta'>{{@model.description}}</span></:subtitle>
        <:metric>{{#if this.leadStat}}<Metric
              @value={{this.leadStat.value}}
              @label={{this.leadStat.label}}
            />{{/if}}</:metric>
        <:details>
          {{#if @model.description}}{{/if}}
          <Detail @label='Effort'>{{orDash this.v.effort}}</Detail>
          <Detail @label='Starts'><span class='mono'>{{orDash
                this.v.startLabel
              }}</span></Detail>
          <Detail @label='Lead'>{{orDash this.v.lead}}</Detail>
          <Detail @label='Team'>{{orDash this.v.team}}</Detail>

          <Detail @label='Vendor'>{{orDash this.v.vendor}}</Detail>
        </:details>
      </RichFittedCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
          color: var(--muted-foreground);
        }
        .fit-strip {
          border-top: 1px solid var(--border);
        }
        @container fitted-card (width < 25rem) {
          .fit-strip :deep(.strip-cell:nth-child(3)) {
            display: none;
          }
        }
        @container fitted-card (width < 15.625rem) or (height < 15.625rem) {
          .fit-strip {
            display: none;
          }
        }
      </style>
    </template>
  };
}
