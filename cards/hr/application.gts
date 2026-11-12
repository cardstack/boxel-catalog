import { markDefinition } from '@cardstack/base/mark-definition';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';
import { tracked } from '@glimmer/tracking';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Alert } from '@cardstack/pretui/components/alert';
import { ScreenApplicationCommand } from './commands/screen-application-command';
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
import { dotEnumField } from './dot-enum-field';
import { FileDef } from '@cardstack/base/file-api';
import InboxIcon from '@cardstack/boxel-icons/inbox';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { type DescriptionsItem } from '@cardstack/pretui/components/descriptions';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';

import { PersonBase } from '../people/person-base';
import { Position } from './position';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { daysBetween } from './utils';
import {
  ALERT_STYLE,
  AVATAR_HUE,
} from '@cardstack/catalog/components/pretui-helpers';
import FileDownloadLink from './components/file-download-link';
import {
  EmbCard,
  IsoHead,
  IsoPage,
  Kv,
  kv,
  Panel,
  SheetLine,
  StatStrip,
  type StripItem,
} from '../shared/compact-sheet';

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

export const ApplicationStatusField = markDefinition(
  dotEnumField(
    {
      options: APPLICATION_STATUSES.map((status) => ({
        value: status,
        label: status,
      })),
      displayName: 'Application Status',
    },
    APPLICATION_STATUS_HUES,
  ),
);

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

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class ApplicationIsolated extends Component<typeof Application> {
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

  get strip(): StripItem[] {
    let m = this.args.model;
    return [
      {
        label: 'Status',
        value: statusWord(m?.status),
        hint: reviewNote(m?.status),
        tone: 'info',
      },
      { label: 'Applied', value: this.appliedValue, hint: this.waitHint },
      {
        label: 'Source',
        value: m?.source || '—',
        hint: this.referrerHint,
      },
    ];
  }
  linked = [{ key: 'Position', value: '' }];

  @tracked busy: 'convert' | 'reject' | undefined;
  @tracked actionError: string | undefined;

  get canAct(): boolean {
    let status = this.args.model?.status;
    return status !== 'converted' && status !== 'rejected';
  }

  convert = () => this.act('convert');
  reject = () => this.act('reject');

  private async act(kind: 'convert' | 'reject') {
    let ctx = this.args.context?.commandContext;
    let model = this.args.model as Application | undefined;
    if (!ctx || !model) {
      this.actionError = 'Commands are unavailable in this mode';
      return;
    }
    this.busy = kind;
    this.actionError = undefined;
    try {
      if (kind === 'convert') {
        await new ScreenApplicationCommand(ctx).execute({
          application: model,
        });
      } else {
        model.status = 'rejected';
        await new SaveCardCommand(ctx).execute({ card: model });
      }
    } catch (e: any) {
      this.actionError = e?.message ?? String(e);
    } finally {
      this.busy = undefined;
    }
  }
  applicationKv = [
    { key: 'Position', value: '' },
    { key: 'Source', value: '' },
    { key: 'Applied', value: '' },
    { key: 'Résumé', value: '' },
    { key: 'Cover letter', value: '' },
  ];

  <template>
    <IsoPage>
      <:head>
        <IsoHead @title={{@model.title}} @meta={{subLine @model}}>
          <:mark><Avatar
              @name={{if @model.name @model.name '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{36}}
              aria-hidden='true'
            /></:mark>
          <:aside>{{#if @model.status}}<@fields.status
                @format='atom'
                @displayContainer={{false}}
              />{{/if}}</:aside>
          <:actions as |bar|>{{#if this.canAct}}
              <bar.Action
                @id='convert'
                @label='Convert to candidate'
                @primary={{true}}
                @loading={{eq this.busy 'convert'}}
                @onClick={{this.convert}}
              />
              <bar.Action
                @id='reject'
                @label='Reject'
                @loading={{eq this.busy 'reject'}}
                @onClick={{this.reject}}
              />
            {{/if}}</:actions>
          <:stats><StatStrip @items={{this.strip}} /></:stats>
        </IsoHead>
        {{#if this.actionError}}<Alert
            @tone='danger'
            style={{ALERT_STYLE.danger}}
          >{{this.actionError}}</Alert>{{/if}}
      </:head>
      <:main>
        <Panel @title='Contact'><Kv @items={{kv this.contactFacts}} /></Panel>
        <Panel @title='Application'>
          <Kv @items={{this.applicationKv}}>
            <:value as |item|>
              {{#if (eq item.key 'Position')}}
                {{if @model.positionTitle @model.positionTitle '—'}}
              {{else if (eq item.key 'Source')}}
                {{if @model.source @model.source '—'}}
              {{else if (eq item.key 'Applied')}}
                {{this.appliedValue}}
              {{else if (eq item.key 'Résumé')}}
                {{#if @model.resumeFile}}
                  <FileDownloadLink @file={{@model.resumeFile}} />
                {{else}}not attached{{/if}}
              {{else if (eq item.key 'Cover letter')}}
                {{#if @model.coverLetterFile}}
                  <FileDownloadLink @file={{@model.coverLetterFile}} />
                {{else}}not attached{{/if}}
              {{/if}}
            </:value>
          </Kv>
        </Panel>
        {{#if @model.resumeText}}
          <Panel @title='Résumé text'><SheetLine><span
                class='prose'
              >{{@model.resumeText}}</span></SheetLine></Panel>
        {{/if}}
      </:main>
      <:aside>
        <Panel @title='Linked'>
          <Kv @items={{this.linked}}>
            <:value>{{#if @model.position}}<@fields.position
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}none linked{{/if}}</:value>
          </Kv>
        </Panel>
        <Panel @title='Details'><Kv @items={{kv this.details}} /></Panel>
      </:aside>
    </IsoPage>
    <style scoped>
      .prose {
        white-space: pre-line;
      }
    </style>
  </template>
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

  static isolated = ApplicationIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get rows() {
      return [
        ...kv(applicationFacts(this.args.model).slice(0, 6)),
        { key: 'Position link', value: '' },
      ];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{subLine @model}}>
        <:mark><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:aside>
        <:default>
          <Kv @items={{this.rows}}>
            <:value as |item|>{{#if (eq item.key 'Position link')}}{{#if
                  @model.position
                }}<@fields.position
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}{{else}}{{item.value}}{{/if}}</:value>
          </Kv>
        </:default>
      </EmbCard>
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
      </span>
      <style scoped>
        @layer PretComponent {
          .application-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-2xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1;
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
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.title}}</:title>
        <:status>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:status>
        <:subtitle><span class='meta'>{{subLine @model}}</span></:subtitle>
        <:details>

          <Detail @label='Applied'><span class='mono'>{{if
                @model.appliedDate
                (formatDay @model.appliedDate)
                '—'
              }}</span></Detail>
          <Detail @label='Source'>{{if
              @model.source
              @model.source
              '—'
            }}</Detail>
          {{#if @model.position}}
            <Detail @label='Position'><@fields.position
                @format='atom'
                @displayContainer={{false}}
              /></Detail>
          {{/if}}
          <Detail @label='Email'><span
              class='mono'
            >{{@model.email}}</span></Detail>
          <Detail @label='Phone'><span
              class='mono'
            >{{@model.phone}}</span></Detail>
          <Detail @label='Résumé'>{{if
              @model.resumeFile
              'attached'
              'not attached'
            }}</Detail>
          <Detail @label='Cover letter'>{{if
              @model.coverLetterFile
              'attached'
              'not attached'
            }}</Detail>
        </:details>
      </RichFittedCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .mono {
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 500;
          font-size: var(--boxel-font-size-2xs);
          font-family: var(--font-mono);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
