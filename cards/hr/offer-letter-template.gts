import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from 'https://cardstack.com/base/card-api';
import MarkdownField from 'https://cardstack.com/base/markdown';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import { Token } from '@cardstack/pretui/components/token';

import { tokenStyle } from '@cardstack/catalog/components/pretui-helpers';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard, Metric } from '../shared/rich-fitted-card';

// A merge field this template's body uses reads in the primary ink; one it
// does not use stays muted.
const USED_TOKEN_STYLE = tokenStyle(
  '--boxel-font-size-xs',
  'var(--primary-ink)',
);
const UNUSED_TOKEN_STYLE = tokenStyle(
  '--boxel-font-size-xs',
  'var(--muted-foreground)',
);

// The merge vocabulary GenerateOfferLetterCommand understands. Kept here —
// next to the card whose body carries the placeholders — so the template's
// legend and the command's interpolation can never drift apart.
export const MERGE_FIELDS: Array<{ token: string; source: string }> = [
  { token: '{{candidateName}}', source: "the offer's linked candidate" },
  { token: '{{jobTitle}}', source: 'offer.offeredTitle (or position title)' },
  { token: '{{salary}}', source: 'offer.salary, formatted as dollars' },
  { token: '{{startDate}}', source: 'offer.startDate' },
  { token: '{{expiresDate}}', source: 'offer.expirationDate' },
  { token: '{{companyName}}', source: 'the company name given to the command' },
];

const PLACEHOLDER_RE = /\{\{\s*([a-zA-Z][a-zA-Z0-9]*)\s*\}\}/g;

export function placeholdersIn(body?: string | null): string[] {
  if (!body) {
    return [];
  }
  let found = new Set<string>();
  for (let match of body.matchAll(PLACEHOLDER_RE)) {
    found.add(match[1]);
  }
  return [...found];
}

export class OfferLetterTemplate extends CardDef {
  static displayName = 'Offer Letter Template';
  static icon = FileTextIcon;

  @field name = contains(StringField);
  @field body = contains(MarkdownField, {
    description:
      'Letter body in markdown with merge placeholders like {{candidateName}}',
  });

  @field title = contains(StringField, {
    computeVia: function (this: OfferLetterTemplate) {
      return this.name?.trim() || 'Untitled Template';
    },
  });

  // Denormalized for fitted — a cheap own attribute the tile reads instead
  // of re-scanning the body at render time.
  @field placeholderTally = contains(StringField, {
    computeVia: function (this: OfferLetterTemplate) {
      let n = placeholdersIn(this.body).length;
      return n === 0 ? '' : String(n);
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get usedPlaceholders(): string[] {
      return placeholdersIn(this.args.model?.body);
    }

    get mergeFields() {
      let used = new Set(this.usedPlaceholders);
      return MERGE_FIELDS.map((f) => {
        let isUsed = used.has(f.token.replace(/[{}]/g, ''));
        return {
          ...f,
          used: isUsed,
          tokenStyle: isUsed ? USED_TOKEN_STYLE : UNUSED_TOKEN_STYLE,
        };
      });
    }

    <template>
      <IsoFrame>
        <article class='template-isolated'>
          <header class='hero'>
            <span class='avatar' aria-hidden='true'><FileTextIcon
                class='avatar-icon'
              /></span>
            <div class='hero-text'>
              <h1>{{@model.title}}</h1>
              <p class='byline'>Offer letter template
                {{#if @model.placeholderTally}}
                  <span class='sep-dot'>&middot;</span>
                  {{@model.placeholderTally}}
                  merge fields
                {{/if}}
              </p>
            </div>
          </header>

          <div class='body'>
            <div class='main'>
              <h2 class='panel-title'>Letter body</h2>
              {{#if @model.body}}
                <div class='letter'>
                  <@fields.body />
                </div>
              {{else}}
                <EmptyState
                  @size='s'
                  @texture={{false}}
                  @title='No body yet'
                  @message='Write the letter in markdown and drop in merge placeholders from the legend.'
                />
              {{/if}}
            </div>

            <aside class='side'>
              <h2 class='panel-title'>Merge fields</h2>
              <p class='side-note'>Generate Offer Letter replaces these with the
                offer's real values. Fields marked in use appear in this
                template's body.</p>
              <ul class='legend'>
                {{#each this.mergeFields as |f|}}
                  <li class='legend-row'>
                    <Token
                      class='legend-token'
                      @value={{f.token}}
                      style={{f.tokenStyle}}
                    />
                    <span class='legend-src'>{{f.source}}</span>
                  </li>
                {{/each}}
              </ul>
            </aside>
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .template-isolated {
          container-type: inline-size;
          container-name: iso;
          height: 100%;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          --tpl-strong: color-mix(
            in oklch,
            var(--primary) 45%,
            var(--foreground)
          );
          background: var(--card);
          color: var(--card-foreground);
        }
        .hero {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .avatar {
          flex: none;
          width: 3.25rem;
          height: 3.25rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          background-color: var(--tpl-strong);
          color: var(--background);
        }
        .avatar-icon {
          width: 1.5rem;
          height: 1.5rem;
        }
        .hero-text {
          flex: 1;
          min-width: 0;
        }
        h1 {
          font-size: var(--boxel-font-size-xl);
          font-weight: 750;
          letter-spacing: -0.02em;
          line-height: 1.2;
          overflow-wrap: break-word;
        }
        .byline {
          margin: var(--boxel-sp-5xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .sep-dot {
          margin: 0 var(--boxel-sp-4xs);
        }
        .body {
          display: grid;
          grid-template-columns: 1fr 17rem;
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
        .letter {
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-sm);
          padding: var(--boxel-sp);
          background-color: var(--card);
          color: var(--card-foreground);
          font-size: var(--boxel-font-size-sm);
          line-height: 1.65;
          max-width: 62ch;
        }
        .side-note {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.5;
          color: var(--muted-foreground);
        }
        .legend {
          list-style: none;
          margin: 0;
          padding: 0;
        }
        .legend-row {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-3xs);
          padding: var(--boxel-sp-2xs) 0;
          border-bottom: 1px solid var(--border);
        }
        .legend-row:last-child {
          border-bottom: 0;
        }
        .legend-row .legend-token {
          align-self: flex-start;
          margin-inline: 0;
        }
        .legend-src {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        @container iso (max-width: 40rem) {
          .body {
            grid-template-columns: 1fr;
          }
          .side {
            border-left: 0;
            border-top: 1px solid var(--border);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get fieldLine() {
      let n = this.args.model?.placeholderTally;
      return n ? `${n} merge fields` : undefined;
    }
    <template>
      <div class='template-embedded'>
        <EntityDisplay
          class='entity'
          @variant='thumbnail'
          @title={{@model.title}}
          @subtitle={{this.fieldLine}}
          @center={{true}}
        >
          <:visual><FileTextIcon class='entity-icon' /></:visual>
        </EntityDisplay>
      </div>
      <style scoped>
        .template-embedded {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
        }
        /* EntityDisplay's thumbnail dress holds the type icon; the name and
           secondary line keep the row's sizes. */
        .entity {
          flex: 1;
          --pretui-entity-visual-size: 1.75rem;
        }
        .entity-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='template-atom'>
        <FileTextIcon class='template-atom-icon' />
        <span class='template-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .template-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
          color: var(--foreground);
        }
        .template-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .template-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    // First ~30 words of the body with markdown syntax stripped — an own
    // attribute derivation, no link reads in this prerendered format.
    get bodyPreview(): string | undefined {
      let body = this.args.model?.body;
      if (!body) {
        return undefined;
      }
      let plain = body
        .replace(/[#*_>`]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
      return plain.length > 160 ? `${plain.slice(0, 160)}…` : plain;
    }

    // the merge-field count rides on the subtitle, so strips under 170 tall show it
    get subtitle() {
      let n = this.args.model?.placeholderTally;
      return n
        ? `Offer letter template · ${n} merge fields`
        : 'Offer letter template';
    }

    <template>
      <RichFittedCard>
        <:avatar><FileTextIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{this.subtitle}}</:subtitle>
        <:fact>{{this.bodyPreview}}</:fact>
        <:metric>{{#if @model.placeholderTally}}<Metric
              @value={{@model.placeholderTally}}
              @label='Merge fields'
            />{{/if}}</:metric>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
