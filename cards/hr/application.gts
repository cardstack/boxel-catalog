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
import { htmlSafe } from '@ember/template';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import { Stat } from '@cardstack/pretui/components/stat';

import { PersonBase } from '@cardstack/catalog/cards/people/person-base';
import { Position } from '@cardstack/catalog/cards/hr/position';
import {
  StatePill,
  stateColor,
  stateColorOf,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { daysBetween } from '@cardstack/catalog/cards/hr/utils';
import {
  AVATAR_HUE,
  AttentionPill,
  QUIET_AVATAR_HUE,
  hueOf,
} from '@cardstack/catalog/cards/hr/hr-ui';
import FileDownloadLink from '@cardstack/catalog/cards/hr/components/file-download-link';

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
    get statusHue() {
      return hueOf(APPLICATION_STATUS_HUES, this.args.model?.status);
    }
    // The status ring sits on a wrapper: Avatar writes its own inline style,
    // and a caller's `style` would replace it.
    get avatarRingStyle() {
      let c = stateColorOf(APPLICATION_STATUS_COLORS, this.args.model?.status);
      return htmlSafe(`--status-ring: ${c.ring}`);
    }
    get referrerLabel(): string | undefined {
      let name = this.args.model?.referrerName;
      return name ? `referred by ${name}` : undefined;
    }
    get resumeWordCount(): number | undefined {
      let text = this.args.model?.resumeText?.trim();
      if (!text) {
        return undefined;
      }
      return text.split(/\s+/).filter(Boolean).length;
    }
    get waitLabel(): string | undefined {
      let d = daysBetween(this.args.model?.appliedDate);
      return d == null ? undefined : `${d} days in queue`;
    }

    // An application nobody has screened is the one thing this card can
    // legitimately claim needs action.
    get needsScreening(): boolean {
      let st = this.args.model?.status;
      return st === 'new' || st === 'reviewing';
    }

    <template>
      <article class='application-isolated'>
        <header class='hero'>
          <span class='avatar-ring' style={{this.avatarRingStyle}}>
            <Avatar
              @name={{if @model.name @model.name '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{52}}
              aria-hidden='true'
            />
          </span>
          <div class='hero-text'>
            <h1>{{@model.title}}</h1>
            <p class='byline'>
              {{#if @model.positionTitle}}applied for
                {{@model.positionTitle}}{{else}}No position linked{{/if}}
              {{#if @model.appliedDate}}
                <span class='sep-dot'>&middot;</span>
                <@fields.appliedDate />
              {{/if}}
            </p>
            <div class='pill-row'>
              <StatePill
                @label={{@model.status}}
                @hue={{this.statusHue}}
                @dot={{true}}
              />
              {{#if this.needsScreening}}
                <AttentionPill @label={{this.waitLabel}} />
              {{else}}
                <StatePill @label={{this.waitLabel}} />
              {{/if}}
              <StatePill @label={{this.referrerLabel}} />
            </div>
          </div>
          {{#if this.resumeWordCount}}
            <div class='hero-money'>
              <Stat
                class='money'
                @label='Resume words'
                @value={{this.resumeWordCount}}
                @roll={{false}}
              />
            </div>
          {{/if}}
        </header>

        <div class='body'>
          <div class='main'>
            <h2 class='panel-title'>Resume</h2>
            {{#if @model.resumeFile}}
              <div class='attach'>
                <FileDownloadLink @file={{@model.resumeFile}} />
              </div>
            {{else}}
              <EmptyState
                class='empty'
                @texture={{false}}
                @title='No resume file attached'
              />
            {{/if}}
            {{#if @model.resumeText}}
              <p class='prose'>{{@model.resumeText}}</p>
            {{else}}
              <EmptyState
                class='empty'
                @texture={{false}}
                @title='No resume text on file'
                @message='This is what a Screen conversion and any later AI parsing on the resulting Candidate both read.'
              />
            {{/if}}

            <h2 class='panel-title spaced'>Cover letter</h2>
            {{#if @model.coverLetterFile}}
              <div class='attach'>
                <FileDownloadLink @file={{@model.coverLetterFile}} />
              </div>
            {{else}}
              <EmptyState
                class='empty'
                @texture={{false}}
                @title='No cover letter attached'
              />
            {{/if}}
          </div>

          <aside class='side'>
            <h2 class='panel-title'>Applicant</h2>
            <dl class='stacked'>
              <dt>Email</dt>
              <dd>{{if @model.email @model.email '—'}}</dd>
              <dt>Phone</dt>
              <dd>{{#if @model.phone}}<@fields.phone
                  />{{else}}&mdash;{{/if}}</dd>
              <dt>Source</dt>
              <dd>{{if @model.source @model.source '—'}}</dd>
              <dt>Referrer</dt>
              <dd>{{if @model.referrerName @model.referrerName '—'}}</dd>
            </dl>

            <h2 class='panel-title spaced'>Requisition</h2>
            <dl class='stacked'>
              <dt>Position</dt>
              <dd>{{#if @model.position}}<@fields.position
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}&mdash;{{/if}}</dd>
              <dt>Applied</dt>
              <dd>{{#if @model.appliedDate}}<@fields.appliedDate
                  />{{else}}&mdash;{{/if}}</dd>
              <dt>In queue</dt>
              <dd>{{if this.waitLabel this.waitLabel '—'}}</dd>
            </dl>
          </aside>
        </div>
      </article>
      <style scoped>
        .application-isolated {
          container-type: inline-size;
          container-name: iso;
          height: 100%;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
        }
        .avatar-ring {
          flex: none;
          display: inline-flex;
          border-radius: 50%;
          box-shadow:
            0 0 0 0.1875rem var(--background),
            0 0 0 0.3125rem var(--status-ring);
        }
        .attach {
          font-size: var(--boxel-font-size-sm);
        }
        .hero {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .hero-text {
          flex: 1;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 750;
          letter-spacing: -0.02em;
          line-height: 1.2;
          overflow-wrap: anywhere;
        }
        .byline {
          margin: var(--boxel-sp-5xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .sep-dot {
          margin: 0 0.25rem;
        }
        .pill-row {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-5xs);
          margin-top: var(--boxel-sp-xs);
        }
        .hero-money {
          flex: none;
          text-align: right;
        }
        .money {
          --text-stat: 1.5rem;
          justify-items: end;
        }
        .body {
          display: grid;
          grid-template-columns: 1fr 17rem;
          /* Fill whatever height is left so the aside's surface reaches the
             bottom edge. Without this the grid is only as tall as its content
             and the panel stops mid-card, reading as a cut-off seam. */
          flex: 1;
          min-height: 0;
          align-content: start;
        }
        .main {
          padding: var(--boxel-sp-lg);
          min-width: 0;
        }
        .side {
          padding: var(--boxel-sp-lg);
          border-left: 1px solid var(--border);
          background-color: var(--muted);
          color: var(--foreground);
        }
        .panel-title {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
        }
        .panel-title.spaced {
          margin-top: var(--boxel-sp-lg);
        }
        .prose {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.65;
          max-width: 56ch;
          max-height: 16rem;
          overflow-y: auto;
        }
        .stacked {
          margin: 0;
          display: grid;
        }
        .stacked dt {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          padding: 0.45rem var(--boxel-sp-xs) 0 0;
        }
        .stacked dd {
          margin: 0;
          padding: 0.1rem 0 0.45rem;
          font-size: var(--boxel-font-size-sm);
          border-bottom: 1px solid var(--border);
          overflow-wrap: anywhere;
          font-variant-numeric: tabular-nums;
        }
        .empty {
          --space-9: var(--boxel-sp);
          --space-6: var(--boxel-sp);
          --text-heading: var(--boxel-font-size);
        }
        @container iso (max-width: 40rem) {
          .body {
            grid-template-columns: 1fr;
          }
          .side {
            border-left: 0;
            border-top: 1px solid var(--border);
          }
          .hero {
            flex-wrap: wrap;
          }
          .hero-money {
            text-align: left;
          }
          .money {
            justify-items: start;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get statusHue() {
      return hueOf(APPLICATION_STATUS_HUES, this.args.model?.status);
    }
    get sourceLine() {
      let source = this.args.model?.source;
      return source ? `via ${source}` : undefined;
    }
    <template>
      <div class='application-embedded'>
        <EntityDisplay
          class='entity'
          @title={{@model.title}}
          @subtitle={{this.sourceLine}}
          @center={{true}}
        >
          <:visual>
            <Avatar
              @name={{if @model.name @model.name '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{QUIET_AVATAR_HUE}}
              @size={{30}}
              aria-hidden='true'
            />
          </:visual>
        </EntityDisplay>
        <StatePill
          class='ae-status'
          @label={{@model.status}}
          @hue={{this.statusHue}}
        />
      </div>
      <style scoped>
        .application-embedded {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.75rem;
          font-size: 0.8125rem;
        }
        /* EntityDisplay's name and secondary line keep the row's sizes. */
        .entity {
          flex: 1;
          --pretui-entity-visual-size: 1.875rem;
          --text-ui-md: 0.8125rem;
          --text-ui-sm: 0.6875rem;
          --space-3: 0.625rem;
        }
        .ae-status {
          flex-shrink: 0;
          text-transform: capitalize;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='application-atom'>
        <InboxIcon class='application-atom-icon' />
        <span class='application-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .application-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .application-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .application-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get statusHue() {
      return hueOf(APPLICATION_STATUS_HUES, this.args.model?.status);
    }
    get waitLabel(): string | undefined {
      let d = daysBetween(this.args.model?.appliedDate);
      return d == null ? undefined : `${d}d waiting`;
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          <Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{26}}
            aria-hidden='true'
          />
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{! Reads the denormalized own-attribute, not position.title —
                a linksTo read here rendered "applying for " with nothing
                after it in prerendered fitted. }}
            {{#if @model.positionTitle}}
              <span class='fit-eb'>{{@model.positionTitle}}</span>
            {{/if}}
          </div>
          <StatePill
            class='fit-pill'
            @label={{@model.status}}
            @hue={{this.statusHue}}
            @dot={{true}}
          />
        </div>

        <div class='fit-mid'>
          {{#if this.waitLabel}}
            <span class='money'>{{this.waitLabel}}</span>
          {{/if}}
          {{#if @model.source}}
            <span class='fit-sub'>via {{@model.source}}</span>
          {{/if}}
        </div>

        <dl class='fit-add'>
          {{#if @model.email}}
            <div><dt>Email</dt><dd>{{@model.email}}</dd></div>
          {{/if}}
          {{#if @model.referrerName}}
            <div><dt>Ref</dt><dd>{{@model.referrerName}}</dd></div>
          {{/if}}
          {{#if @model.appliedDate}}
            <div><dt>Applied</dt><dd><@fields.appliedDate /></dd></div>
          {{/if}}
          {{#if @model.source}}
            <div><dt>Source</dt><dd>{{@model.source}}</dd></div>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        /* Four tiers, each ADDING fields. 11px floor. Status never hidden. */
        .fit {
          height: 100%;
          /* Flex, not a three-row grid: with `minmax(0, 1fr)` in the middle
             a taller bottom block squeezed the middle row and clipped its
             text. Here the middle keeps its natural height and the extras
             block is pushed to the bottom by `margin-top: auto`. */
          display: flex;
          flex-direction: column;
          gap: 0.28rem;
          padding: 0.55rem 0.6rem;
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
          --fit-name: clamp(0.6875rem, 3.2cqi, 0.9375rem);
          --fit-small: clamp(0.6875rem, 2.6cqi, 0.75rem);
        }
        .fit > * {
          min-height: 0;
          overflow: hidden;
        }
        .fit-top {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: 0.4rem;
          flex-wrap: wrap;
        }
        .fit-head {
          flex: 1;
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--fit-name);
          font-weight: 700;
          line-height: 1.25;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          display: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-pill {
          flex: none;
          align-self: flex-start;
        }
        .fit-mid {
          flex: none;
          display: none;
          flex-direction: column;
          gap: 0.0625rem;
        }
        .money {
          font-size: calc(var(--fit-name) * 1.15);
          font-weight: 800;
          letter-spacing: -0.02em;
          font-variant-numeric: tabular-nums;
        }
        .fit-sub {
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-add {
          display: none;
          margin: 0;
          margin-top: auto;
          padding-top: 0.3rem;
          border-top: 1px dashed var(--border);
          grid-template-columns: 1fr 1fr;
          gap: 0.05rem 0.5rem;
        }
        .fit-add > div {
          display: flex;
          gap: 0.25rem;
          min-width: 0;
        }
        .fit-add dt {
          flex: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
        }
        .fit-add dd {
          margin: 0;
          font-size: var(--fit-small);
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          font-variant-numeric: tabular-nums;
        }

        /* TIER 2 — add the secondary line. Container queries have no `or`,
           so this is reached either by height (tile) or width (strip). */
        @container fitted-card (height > 80px) {
          .fit-eb {
            display: block;
          }
        }
        @container fitted-card (width > 240px) {
          .fit-eb {
            display: block;
          }
        }
        /* TIER 3 — add the headline figure block. */
        @container fitted-card (height > 130px) and (width > 180px) {
          .fit-mid {
            display: flex;
          }
        }
        /* TIER 4 — width-driven extra facts, so a large tile shows more
           than a small one. */
        @container fitted-card (height > 150px) and (width > 180px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr;
          }
        }
        @container fitted-card (width > 340px) and (height > 130px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr 1fr;
          }
        }
        /* Short strip: horizontal, single-line name. */
        @container fitted-card (height <= 90px) {
          .fit {
            grid-template-rows: 1fr;
            align-content: center;
          }
          .fit-top {
            align-items: center;
            flex-wrap: nowrap;
          }
          .fit-pill {
            align-self: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        /* Smallest tier: secondary line goes, the status pill stays. */
        @container fitted-card (height <= 50px) {
          .fit-eb {
            display: none;
          }
        }
      </style>
    </template>
  };
}
