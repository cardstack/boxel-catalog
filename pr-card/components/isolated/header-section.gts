import GlimmerComponent from '@glimmer/component';
import ExternalLinkIcon from '@cardstack/boxel-icons/external-link';
import CopyIcon from '@cardstack/boxel-icons/copy';
import { Button, Pill } from '@cardstack/boxel-ui/components';
import { on } from '@ember/modifier';
import type { CardOrFieldTypeIcon } from '@cardstack/base/card-api';

interface HeaderSectionSignature {
  Args: {
    title: string;
    prNumber: number | null | undefined;
    branchName: string | null | undefined;
    prUrl: string | null;
    actionLabel: string;
    actionIcon: CardOrFieldTypeIcon;
    pillColor: string;
    submittedBy: string | null | undefined;
  };
  Blocks: {
    date: [];
  };
}

export class HeaderSection extends GlimmerComponent<HeaderSectionSignature> {
  copyBranchName = async () => {
    let branchName = this.args.branchName?.trim();
    if (!branchName) {
      return;
    }
    await navigator.clipboard.writeText(branchName);
  };

  <template>
    <header class='pr-hero'>
      <h1 class='pr-title'>
        {{@title}}
        {{#if @prNumber}}
          <span class='pr-number'>#{{@prNumber}}</span>
        {{/if}}
      </h1>
      <div class='pr-meta'>
        <Pill class='pr-state-pill' @pillBackgroundColor={{@pillColor}}>
          <:iconLeft>
            <@actionIcon class='pr-state-icon' />
          </:iconLeft>
          <:default>
            <span class='pr-state-label'>{{@actionLabel}}</span>
          </:default>
        </Pill>

        {{#if @submittedBy}}
          <strong class='pr-author'>{{@submittedBy}}</strong>
        {{/if}}

        {{#if @branchName}}
          <span class='pr-branch'>
            <span class='pr-branch-label'>{{@branchName}}</span>
            <Button
              @kind='text-only'
              @size='auto'
              class='pr-branch-copy-button'
              {{on 'click' this.copyBranchName}}
              aria-label='Copy branch name'
              title='Copy branch name'
            >
              <CopyIcon class='pr-branch-copy-icon' />
            </Button>
          </span>
        {{/if}}

        {{#if (has-block 'date')}}
          <span class='pr-meta-sep'>·</span>
          <span class='pr-date'>{{yield to='date'}}</span>
        {{/if}}

        <a
          href={{@prUrl}}
          target='_blank'
          rel='noopener noreferrer'
          class='pr-github-link'
          title='Open PR on GitHub'
          aria-label='Open PR on GitHub'
        >
          <ExternalLinkIcon class='pr-github-link-icon' />
        </a>
      </div>
    </header>

    <style scoped>
      .pr-hero {
        background-color: var(--card);
        color: var(--card-foreground);
        padding: var(--boxel-sp-lg) var(--boxel-sp-xl);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        flex-shrink: 0;
        border-bottom: 1px solid var(--border-strong);
      }
      .pr-title {
        font-size: 1.4rem;
        font-weight: 600;
        margin: 0;
        line-height: 1.3;
        color: var(--card-foreground);
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .pr-number {
        font-size: 1.2rem;
        font-weight: 600;
        color: var(--subtle-foreground);
      }
      .pr-meta {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .pr-state-pill {
        --boxel-pill-border-radius: 2em;
      }
      .pr-state-icon {
        width: 0.875rem;
        height: 0.875rem;
        color: var(--card-foreground);
        flex-shrink: 0;
      }
      .pr-state-label {
        font-size: var(--boxel-font-xs);
        font-weight: 600;
        color: var(--card-foreground);
      }
      .pr-author {
        font-size: var(--boxel-font-xs);
        color: var(--card-foreground);
        font-weight: 600;
      }
      .pr-branch {
        font-size: var(--boxel-font-xs);
        color: var(--primary-ink);
        border: 1px solid var(--border-strong);
        border-radius: 62.4375rem;
        padding: 1px 0.25rem 1px 0.5rem;
        max-width: 17.5rem;
        display: inline-flex;
        align-items: center;
        gap: 0.25rem;
      }
      .pr-branch-label {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .pr-branch-copy-button {
        border: none;
        background-color: transparent;
        color: inherit;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 2px;
        border-radius: 62.4375rem;
        cursor: pointer;
        flex-shrink: 0;
      }
      .pr-branch-copy-button:hover {
        background-color: color-mix(in oklch, var(--primary) 20%, transparent);
      }
      .pr-branch-copy-icon {
        width: 0.6875rem;
        height: 0.6875rem;
      }
      .pr-date {
        font-size: var(--boxel-font-xs);
        color: var(--subtle-foreground);
      }
      .pr-meta-sep {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-xs);
      }
      .pr-github-link {
        margin-left: auto;
        color: var(--subtle-foreground);
        text-decoration: none;
        display: inline-flex;
        align-items: center;
        transition: color 0.15s ease;
      }
      .pr-github-link:hover {
        color: var(--primary-ink);
      }
      .pr-github-link-icon {
        width: 0.875rem;
        height: 0.875rem;
      }
    </style>
  </template>
}
