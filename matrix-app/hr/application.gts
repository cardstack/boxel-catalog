import {
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import PhoneNumberField from '@cardstack/base/phone-number';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import { FileDef } from '@cardstack/base/file-api';
import InboxIcon from '@cardstack/boxel-icons/inbox';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '../../ui-component/components/avatar';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';

import { PersonBase } from '../people/person-base';
import { Position } from './position';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { daysBetween } from './utils';
import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
import FileDownloadLink from './components/file-download-link';

export const APPLICATION_STATUSES = [
  'new',
  'reviewing',
  'converted',
  'rejected',
];

// Colocated with Application — the hue map colours the status pill, and
// `APPLICATION_STATUS_COLORS` below gives the avatar's status ring the same
// hue. A status reads the status hues, matching Candidate's stages: "new" is
// amber like an applied candidate, "reviewing" is green like screening,
// "converted" is the green of a hire (this applicant became a Candidate), and
// "rejected" is red.
export const APPLICATION_STATUS_HUES: Record<string, Hue> = {
  new: 'amber',
  reviewing: 'green',
  converted: 'green',
  rejected: 'red',
};

export const APPLICATION_STATUS_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(APPLICATION_STATUS_HUES).map(([k, hue]) => [
      k,
      stateColor(hue),
    ]),
  );

export const ApplicationStatusField = enumField(StringField, {
  options: APPLICATION_STATUSES.map((status) => ({
    value: status,
    label: status,
  })),
  displayName: 'Application Status',
});

// The status chip's tone, shared with the Applications tab: a new
// application is neutral, one in review warning, a converted one success,
// and a rejected one neutral again (it is closed, not an alarm).
const APPLICATION_STATUS_TONES: Record<string, PretuiToneArg> = {
  new: 'neutral',
  reviewing: 'warning',
  converted: 'success',
  rejected: 'neutral',
};

export function statusTone(status?: string | null): PretuiToneArg {
  return (status && APPLICATION_STATUS_TONES[status]) || 'neutral';
}

export function statusWord(status?: string | null): string {
  return status ? status.charAt(0).toUpperCase() + status.slice(1) : '—';
}

// Where the review stands, beside the applied date.
const REVIEW_NOTES: Record<string, string> = {
  new: 'not yet reviewed',
  reviewing: 'in review',
  converted: 'converted to candidate',
  rejected: 'rejected',
};

function reviewNote(status?: string | null): string {
  return (status && REVIEW_NOTES[status]) || 'no status';
}

function subLine(m?: Partial<Application>): string {
  let parts = [
    m?.positionTitle || 'No position',
    m?.source ? `via ${m.source}` : undefined,
  ].filter(Boolean);
  return parts.join(' · ');
}

// The facts every format draws from, in the mockup's order; isolated shows
// them all, embedded the first six. The file rows read the link only, so
// they say "not attached" until the file loads.
function applicationFacts(m?: Partial<Application>): DescriptionsItem[] {
  return [
    {
      label: 'Applied',
      value: m?.appliedDate ? formatDay(m.appliedDate) : '—',
    },
    { label: 'Source', value: m?.source || '—' },
    { label: 'Position', value: m?.positionTitle || '—' },
    { label: 'Email', value: m?.email || '—' },
    { label: 'Phone', value: m?.phone || '—' },
    { label: 'Résumé', value: m?.resumeFile ? 'attached' : 'not attached' },
    {
      label: 'Cover letter',
      value: m?.coverLetterFile ? 'attached' : 'not attached',
    },
  ];
}

export class Application extends PersonBase {
  static displayName = 'Application';
  static icon = InboxIcon;

  // PersonBase already contributes name/email/photo/initials — an
  // applicant is a person, so this reuses that identity instead of
  // redeclaring it. Phone is overridden to the stricter PhoneNumberField
  // (PersonBase's own `phone` is a plain string) since that's what this
  // card always wanted.
  @field phone = contains(PhoneNumberField);
  @field position = linksTo(() => Position);
  @field positionTitle = contains(StringField, {
    description:
      "Denormalized copy of the linked position's title — fitted prerender never resolves linksTo, so fitted reads this instead of position.title",
  });
  @field source = contains(StringField, {
    description:
      'Where the application came from (LinkedIn, referral, careers page, etc.)',
  });
  @field appliedDate = contains(DateField);
  @field resumeText = contains(TextAreaField, {
    description: 'Raw resume text submitted with the application',
  });
  @field resumeFile = linksTo(FileDef, {
    searchable: true,
    description:
      'The original resume file (PDF, etc.) submitted with the application',
  });
  @field coverLetterFile = linksTo(FileDef, { searchable: true });
  @field referrerName = contains(StringField, {
    description: 'Name of the person who referred this applicant, if any',
  });
  @field status = contains(ApplicationStatusField);

  @field title = contains(StringField, {
    computeVia: function (this: Application) {
      return this.name?.trim() || 'Unnamed Applicant';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get contactFacts(): DescriptionsItem[] {
      let m = this.args.model;
      return [
        { label: 'Email', value: m?.email || '—' },
        { label: 'Phone', value: m?.phone || '—' },
      ];
    }

    // The file rows render a download link when a file is attached.
    applicationRows: DescriptionsItem[] = [
      { label: 'Position' },
      { label: 'Source' },
      { label: 'Applied' },
      { label: 'Résumé' },
      { label: 'Cover letter' },
    ];

    get details(): DescriptionsItem[] {
      return applicationFacts(this.args.model);
    }

    get appliedValue(): string {
      let d = this.args.model?.appliedDate;
      return d ? formatDay(d) : '—';
    }

    get waitHint(): string | undefined {
      let d = daysBetween(this.args.model?.appliedDate);
      return d == null ? undefined : `${d} days in queue`;
    }

    get referrerHint(): string {
      let name = this.args.model?.referrerName;
      return name ? `referred by ${name}` : 'no referrer';
    }

    <template>
      <article class='application-isolated'>
        <header class='iso-head'>
          <Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{48}}
            aria-hidden='true'
          />
          <div class='iso-id'>
            <h1>{{@model.title}}</h1>
            <p class='iso-sub'>{{subLine @model}}</p>
          </div>
          <div class='chips'>
            {{#if @model.status}}
              <StatusChip
                @value={{statusWord @model.status}}
                @tone={{statusTone @model.status}}
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              />
            {{/if}}
            {{#if @model.source}}
              <StatusChip
                @value={{@model.source}}
                @tone='neutral'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              />
            {{/if}}
          </div>
        </header>

        <div class='stat-row'>
          <div class='stat-tile'><Stat
              @label='Status'
              @value={{statusWord @model.status}}
              @hint={{reviewNote @model.status}}
              @roll={{false}}
            /></div>
          <div class='stat-tile'><Stat
              @label='Applied'
              @value={{this.appliedValue}}
              @hint={{this.waitHint}}
              @roll={{false}}
            /></div>
          <div class='stat-tile'><Stat
              @label='Source'
              @value={{if @model.source @model.source '—'}}
              @hint={{this.referrerHint}}
              @roll={{false}}
            /></div>
        </div>

        <div class='iso-body'>
          <div class='iso-col'>
            <Panel>
              <:header><h2 class='panel-h'>Contact</h2></:header>
              <:default>
                <Descriptions
                  @items={{this.contactFacts}}
                  @columns={{1}}
                  @size='xl'
                >
                  <:value as |item|><span
                      class='v'
                    >{{item.value}}</span></:value>
                </Descriptions>
              </:default>
            </Panel>
            <Panel>
              <:header><h2 class='panel-h'>Application</h2></:header>
              <:default>
                <Descriptions
                  @items={{this.applicationRows}}
                  @columns={{1}}
                  @size='xl'
                >
                  <:value as |item|>
                    {{#if (eq item.label 'Position')}}
                      <span class='v'>{{if
                          @model.positionTitle
                          @model.positionTitle
                          '—'
                        }}</span>
                    {{else if (eq item.label 'Source')}}
                      <span class='v'>{{if
                          @model.source
                          @model.source
                          '—'
                        }}</span>
                    {{else if (eq item.label 'Applied')}}
                      <span class='v'>{{this.appliedValue}}</span>
                    {{else if (eq item.label 'Résumé')}}
                      {{#if @model.resumeFile}}
                        <FileDownloadLink @file={{@model.resumeFile}} />
                      {{else}}
                        <span class='v'>not attached</span>
                      {{/if}}
                    {{else if (eq item.label 'Cover letter')}}
                      {{#if @model.coverLetterFile}}
                        <FileDownloadLink @file={{@model.coverLetterFile}} />
                      {{else}}
                        <span class='v'>not attached</span>
                      {{/if}}
                    {{/if}}
                  </:value>
                </Descriptions>
              </:default>
            </Panel>
            {{#if @model.resumeText}}
              <Panel>
                <:header><h2 class='panel-h'>Résumé text</h2></:header>
                <:default><p class='prose'>{{@model.resumeText}}</p></:default>
              </Panel>
            {{/if}}
          </div>

          <div class='iso-col'>
            <Panel>
              <:header><h2 class='panel-h'>Linked</h2></:header>
              <:default>
                <p class='rel'><span class='k'>Position</span>{{#if
                    @model.position
                  }}<@fields.position
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}<span class='v'>none linked</span>{{/if}}</p>
              </:default>
            </Panel>
            <Panel>
              <:header><h2 class='panel-h'>Details</h2></:header>
              <:default>
                <Descriptions @items={{this.details}} @columns={{1}} @size='xl'>
                  <:value as |item|><span
                      class='v'
                    >{{item.value}}</span></:value>
                </Descriptions>
              </:default>
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .application-isolated {
            container: application-iso / inline-size;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            box-sizing: border-box;
            height: 100%;
            overflow-y: auto;
            padding: var(--boxel-sp-lg);
            background: var(--canvas);
          }
          .iso-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp);
          }
          .iso-id {
            flex: 1 1 12rem;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary-ink);
            overflow-wrap: anywhere;
          }
          .iso-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .stat-row {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
            gap: var(--boxel-sp);
          }
          .stat-tile {
            padding: var(--boxel-sp);
            border-radius: var(--boxel-border-radius);
            background-color: var(--card);
            color: var(--primary-ink);
            box-shadow: var(--shadow-md);
          }
          .iso-body {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
            align-items: start;
            gap: var(--boxel-sp-lg);
          }
          .iso-col {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            min-width: 0;
          }
          .panel-h {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
            line-height: 1.25;
          }
          .prose {
            margin: 0;
            max-height: 16rem;
            overflow-y: auto;
            font-size: var(--boxel-font-size-sm);
            line-height: 1.5;
            white-space: pre-wrap;
          }
          .rel {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-sm);
            min-width: 0;
            margin: 0;
            font-size: var(--boxel-font-size-sm);
          }
          .k {
            flex: none;
            color: var(--muted-foreground);
          }
          .v {
            font-weight: 600;
            font-variant-numeric: tabular-nums;
            overflow-wrap: anywhere;
          }
          @container application-iso (width < 45rem) {
            .iso-body {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get facts(): DescriptionsItem[] {
      return applicationFacts(this.args.model).slice(0, 6);
    }
    <template>
      <div class='application-embedded'>
        <article class='emb'>
          <header class='emb-head'>
            <Avatar
              @name={{if @model.name @model.name '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{40}}
              aria-hidden='true'
            />
            <div class='emb-id'>
              <h3 class='emb-title'>{{@model.title}}</h3>
              <p class='emb-sub'>{{subLine @model}}</p>
            </div>
            <div class='chips'>
              {{#if @model.status}}
                <StatusChip
                  @value={{statusWord @model.status}}
                  @tone={{statusTone @model.status}}
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                />
              {{/if}}
              {{#if @model.source}}
                <StatusChip
                  @value={{@model.source}}
                  @tone='neutral'
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                />
              {{/if}}
            </div>
          </header>
          {{#if @model.appliedDate}}
            <p class='emb-fact'>Applied
              <strong>{{formatDay @model.appliedDate}}</strong>
              ·
              {{reviewNote @model.status}}</p>
          {{/if}}
          <Descriptions
            class='emb-kv'
            @items={{this.facts}}
            @layout='vertical'
            @columns={{3}}
          >
            <:value as |item|><span class='v'>{{item.value}}</span></:value>
          </Descriptions>
          {{#if @model.position}}
            <p class='emb-rels'>Position
              <@fields.position
                @format='atom'
                @displayContainer={{false}}
              /></p>
          {{/if}}
        </article>
      </div>
      <style scoped>
        @layer PretComponent {
          .application-embedded {
            container-type: inline-size;
          }
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 auto;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
          }
          .emb-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            justify-content: flex-end;
            gap: var(--boxel-sp-4xs);
          }
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-fact strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .emb-kv {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
          }
          .v {
            font-weight: 600;
            font-variant-numeric: tabular-nums;
            overflow-wrap: anywhere;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs);
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          /* under 400 the chips move under the name */
          @container (width < 25rem) {
            .emb-head {
              flex-wrap: wrap;
            }
            .chips {
              flex-basis: 100%;
              justify-content: flex-start;
            }
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='application-atom'>
        <Avatar
          @name={{if @model.name @model.name '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          @size={{20}}
          aria-hidden='true'
        />
        <span class='name'>{{@model.title}}</span>
        {{#if @model.status}}
          <StatusChip
            @value={{statusWord @model.status}}
            @tone={{statusTone @model.status}}
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          />
        {{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .application-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.5;
            white-space: nowrap;
            color: var(--foreground);
          }
          .name {
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    // Each fact is its own KeyValue row, so a row that doesn't fit wraps
    // out of sight whole instead of showing half.
    get factRows(): KeyValueItem[][] {
      return applicationFacts(this.args.model).map((f) => [
        { key: f.label, value: f.value ?? '—' },
      ]);
    }

    <template>
      <div class='fit'>
        <FitTile class='tile'>
          <:avatar>
            <Avatar
              @name={{if @model.name @model.name '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            />
          </:avatar>
          <:title><span
              role='heading'
              aria-level='3'
            >{{@model.title}}</span></:title>
          {{! Reads the denormalized own-attribute, not position.title — a
              linksTo read here renders nothing in prerendered fitted. }}
          <:subtitle>{{subLine @model}}</:subtitle>
          <:status>
            {{#if @model.status}}
              <StatusChip
                @value={{statusWord @model.status}}
                @tone={{statusTone @model.status}}
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              />
            {{/if}}
            {{#if @model.source}}
              <StatusChip
                @value={{@model.source}}
                @tone='neutral'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              />
            {{/if}}
          </:status>
          <:fact>{{#if @model.appliedDate}}Applied
              <strong class='strong'>{{formatDay @model.appliedDate}}</strong>
              ·
              {{reviewNote @model.status}}{{/if}}</:fact>
        </FitTile>
        {{! Relations, then the key facts: shown from 170 tall, and the
            relation line on a 400-wide strip. }}
        <div class='more'>
          {{#if @model.position}}
            <p class='rel'><span class='k'>Position</span><@fields.position
                @format='atom'
              /></p>
          {{/if}}
          {{#each this.factRows as |row|}}
            <KeyValue class='kv' @items={{row}} />
          {{/each}}
        </div>
      </div>
      <style scoped>
        @layer PretComponent, PretComposite;
        /* FitTile sizes to its rows here, so the extra rows below it get the
           rest of the card */
        @layer PretComposite {
          .tile {
            flex: none;
            block-size: auto;
          }
        }
        @layer PretComponent {
          .fit {
            display: flex;
            flex-direction: column;
            block-size: 100%;
            overflow: hidden;
          }
          .strong {
            font-weight: 600;
            color: var(--foreground);
          }
          /* a column that wraps: a row past the bottom moves to a second
             column outside the card, whole */
          .more {
            display: none;
            flex: 1 1 0;
            flex-flow: column wrap;
            align-content: flex-start;
            row-gap: var(--boxel-sp-4xs);
            column-gap: var(--boxel-sp-sm);
            min-block-size: 0;
            padding: 0 var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.5;
          }
          .rel,
          .kv {
            inline-size: 100%;
          }
          .rel {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-inline-size: 0;
            margin: 0;
            overflow: hidden;
            white-space: nowrap;
          }
          .k {
            flex: none;
            color: var(--muted-foreground);
          }
          @container fitted-card (height >= 170px) {
            .more {
              display: flex;
            }
          }
          @container fitted-card (105px <= height < 170px) and (width >= 400px) {
            .more {
              display: flex;
            }
          }
        }
      </style>
    </template>
  };
}
