import { on } from '@ember/modifier';
import { action } from '@ember/object';
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { type CardContext } from '@cardstack/base/card-api';
import { Button, FieldContainer } from '@cardstack/boxel-ui/components';
import { formatDatetime, toISOString } from '../blog-defaults';
import type { BlogPost } from '../blog-post';

interface CardAdminViewSignature {
  Args: {
    cardId: string;
    context?: CardContext<BlogPost>;
  };
  Element: HTMLElement;
}
export class BlogAdminData extends GlimmerComponent<CardAdminViewSignature> {
  <template>
    {{#if this.resource.cardError}}
      Error: Could not load additional info
    {{else if this.resource.card}}
      <div class='blog-admin' ...attributes>
        {{#let this.resource.card as |card|}}
          <FieldContainer
            class='admin-data'
            @label='Publish Date'
            @vertical={{true}}
          >
            {{#if card.publishDate}}
              <time datetime={{toISOString card.publishDate}}>
                {{this.formattedDate card.publishDate}}
              </time>
            {{else}}
              N/A
            {{/if}}
          </FieldContainer>
          <FieldContainer
            class='admin-data'
            @label='Last Updated'
            @vertical={{true}}
          >
            {{#if card.lastUpdated}}
              <time datetime={{toISOString card.lastUpdated}}>
                {{this.formattedDate card.lastUpdated}}
              </time>
            {{else}}
              N/A
            {{/if}}
          </FieldContainer>
          <FieldContainer
            class='admin-data'
            @label='Word Count'
            @vertical={{true}}
          >
            {{if card.wordCount card.wordCount 0}}
          </FieldContainer>
          <FieldContainer class='admin-data' @label='Author' @vertical={{true}}>
            {{this.authorLabel}}
          </FieldContainer>
          <FieldContainer class='admin-data' @label='Status' @vertical={{true}}>
            <div class='status-row'>
              <span class='status-pill {{this.statusModifier}}'>
                <span class='status-dot' aria-hidden='true'></span>
                {{card.status}}
              </span>
              <Button
                @size='auto'
                @kind='text-only'
                class='publish-toggle
                  {{if card.published "publish-toggle--unpublish"}}'
                {{on 'click' this.togglePublished}}
              >
                {{if card.published 'Unpublish' 'Publish'}}
              </Button>
            </div>
          </FieldContainer>
        {{/let}}
      </div>
    {{/if}}
    <style scoped>
      .blog-admin {
        display: inline-flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .admin-data {
        --boxel-label-font: 600 var(--boxel-font-sm);
      }
      .status-row {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }
      .status-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 4px 10px;
        border-radius: 999px;
        font:
          600 11px/1 system-ui,
          -apple-system,
          sans-serif;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        background: #e5e7eb;
        color: #4b5563;
      }
      .status-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: currentColor;
      }
      .status-pill.is-published {
        background: rgba(34, 197, 94, 0.15);
        color: #15803d;
      }
      .status-pill.is-draft {
        background: #e5e7eb;
        color: #4b5563;
      }
      .publish-toggle {
        padding: 5px 12px;
        background: #2c2c2c;
        color: white;
        border: 1px solid #2c2c2c;
        border-radius: 999px;
        cursor: pointer;
        font:
          600 11px/1 system-ui,
          -apple-system,
          sans-serif;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        transition:
          background-color 0.15s,
          color 0.15s,
          transform 0.1s;
      }
      .publish-toggle:hover {
        background: #1a1a1a;
        border-color: #1a1a1a;
      }
      .publish-toggle:active {
        transform: scale(0.96);
      }
      .publish-toggle--unpublish {
        background: transparent;
        color: #2c2c2c;
      }
      .publish-toggle--unpublish:hover {
        background: rgba(0, 0, 0, 0.05);
        color: #1a1a1a;
      }
    </style>
  </template>

  @tracked resource = this.args.context
    ? this.args.context.getCard(this, () => this.args.cardId)
    : undefined;

  formattedDate = (datetime: Date) => {
    return formatDatetime(datetime, {
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour12: true,
      hour: 'numeric',
      minute: '2-digit',
    });
  };

  get authorLabel() {
    const card = this.resource?.card as any;
    if (!card) return 'N/A';
    return card.formattedAuthors ?? 'N/A';
  }

  get statusModifier() {
    const status = (this.resource?.card as any)?.status;
    return status === 'Published' ? 'is-published' : 'is-draft';
  }

  @action togglePublished() {
    const card = this.resource?.card as any;
    if (!card) return;
    card.published = !card.published;
    (this.args.context as any)?.actions?.saveCard?.(card);
  }
}
