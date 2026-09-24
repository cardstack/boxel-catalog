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
        gap: 0.625rem;
        flex-wrap: wrap;
      }
      .status-pill {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.25rem 0.625rem;
        border-radius: 62.4375rem;
        font:
          600 0.6875rem/1 system-ui,
          -apple-system,
          sans-serif;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        background-color: var(--inset);
        color: var(--muted-foreground);
      }
      .status-dot {
        width: 0.375rem;
        height: 0.375rem;
        border-radius: 50%;
        background-color: currentColor;
      }
      .status-pill.is-published {
        background-color: color-mix(in oklch, var(--success) 15%, transparent);
        color: var(--success-ink);
      }
      .status-pill.is-draft {
        background-color: var(--inset);
        color: var(--muted-foreground);
      }
      .publish-toggle {
        padding: 0.3125rem 0.75rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border-strong);
        border-radius: 62.4375rem;
        cursor: pointer;
        font:
          600 0.6875rem/1 system-ui,
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
        background-color: var(--card);
        color: var(--card-foreground);
        border-color: var(--border-strong);
      }
      .publish-toggle:active {
        transform: scale(0.96);
      }
      .publish-toggle--unpublish {
        background-color: transparent;
        color: var(--foreground);
      }
      .publish-toggle--unpublish:hover {
        background-color: color-mix(in oklch, var(--tooltip) 5%, transparent);
        color: var(--foreground);
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
