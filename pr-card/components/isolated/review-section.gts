import GlimmerComponent from '@glimmer/component';
import ExternalLinkIcon from '@cardstack/boxel-icons/external-link';
import type { ReviewState } from '../../utils';

// ── Sub-components ──────────────────────────────────────────────────────

interface ReviewStateBadgeSignature {
  Args: {
    state: ReviewState;
    reviewerName: string | null;
  };
}

class ReviewStateBadge extends GlimmerComponent<ReviewStateBadgeSignature> {
  get stateClass() {
    if (this.args.state === 'changes_requested')
      return 'review-state-badge--changes';
    if (this.args.state === 'approved') return 'review-state-badge--approved';
    if (this.args.state === 'unknown') return 'review-state-badge--pending';
    return '';
  }

  get label() {
    if (this.args.state === 'changes_requested') return 'Changes Requested';
    if (this.args.state === 'approved') return 'Approved';
    if (this.args.state === 'unknown') return 'Pending Review';
    return '';
  }

  get hasState() {
    return (
      this.args.state === 'changes_requested' ||
      this.args.state === 'approved' ||
      this.args.state === 'unknown'
    );
  }

  <template>
    {{#if this.hasState}}
      <span class='review-state-badge {{this.stateClass}}'>{{this.label}}{{#if
          @reviewerName
        }} by {{@reviewerName}}{{/if}}</span>
    {{/if}}

    <style scoped>
      .review-state-badge {
        display: inline-flex;
        align-self: center;
        font-size: 0.6875rem;
        font-weight: 600;
        border-radius: 2em;
        padding: 2px 0.625rem;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        flex-shrink: 0;
      }
      .review-state-badge--changes {
        background-color: color-mix(
          in oklch,
          var(--destructive) 10%,
          var(--card)
        );
        color: var(--destructive-ink);
        border: 1px solid
          color-mix(in oklch, var(--destructive) 30%, var(--card));
      }
      .review-state-badge--approved {
        background-color: color-mix(in oklch, var(--chart-1) 10%, var(--card));
        color: var(--chart-1);
        border: 1px solid color-mix(in oklch, var(--chart-1) 35%, var(--card));
      }
      .review-state-badge--pending {
        background-color: color-mix(in oklch, var(--warning) 10%, var(--card));
        color: var(--warning-ink);
        border: 1px solid color-mix(in oklch, var(--warning) 30%, var(--card));
      }
    </style>
  </template>
}

// ── Main Section ────────────────────────────────────────────────────────

interface ReviewSectionSignature {
  Args: {
    reviewState: ReviewState;
    reviewerName: string | null;
    comment: string;
    reviewUrl: string | undefined;
    hasReview: boolean;
  };
}

export class ReviewSection extends GlimmerComponent<ReviewSectionSignature> {
  get reviewItemStateClass() {
    if (this.args.reviewState === 'changes_requested') {
      return 'review-item--changes';
    }
    if (this.args.reviewState === 'approved') {
      return 'review-item--approved';
    }
    if (this.args.reviewState === 'unknown') {
      return 'review-item--pending';
    }
    return '';
  }

  <template>
    <div class='review-section'>
      <div class='review-heading-row'>
        <h2 class='section-heading'>Reviews</h2>
        <ReviewStateBadge
          @state={{@reviewState}}
          @reviewerName={{@reviewerName}}
        />
      </div>

      {{#if @hasReview}}
        <ul class='review-list'>
          <li class='review-item {{this.reviewItemStateClass}}'>
            <div class='review-item-header'>
              <span class='review-author'>{{@reviewerName}}</span>
              {{#if @reviewUrl}}
                <a
                  href={{@reviewUrl}}
                  target='_blank'
                  rel='noopener noreferrer'
                  class='review-github-link'
                  title='View review on GitHub'
                  aria-label='View review on GitHub'
                >
                  <ExternalLinkIcon class='review-github-link-icon' />
                </a>
              {{/if}}
            </div>
            <blockquote class='review-comment'>{{@comment}}</blockquote>
          </li>
        </ul>
      {{else}}
        <div class='empty-state {{this.reviewItemStateClass}}'>
          <span class='empty-state-icon' aria-hidden='true'>
            <span class='empty-state-dot'></span>
          </span>
          <span class='empty-state-text'>-</span>
        </div>
      {{/if}}
    </div>

    <style scoped>
      .review-section {
        flex: 1;
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        overflow-y: auto;
      }
      .section-heading {
        font-size: 0.625rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--foreground);
        margin: 0;
      }
      .review-heading-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      .review-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
      }
      .review-item {
        background-color: var(--muted);
        color: var(--muted-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .review-item-header {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .review-author {
        font-size: var(--boxel-font-sm);
        font-weight: 500;
        color: var(--foreground);
      }
      .review-github-link {
        margin-left: auto;
        color: var(--muted-foreground);
        text-decoration: none;
        display: inline-flex;
        align-items: center;
        transition: color 0.15s ease;
        flex-shrink: 0;
      }
      .review-github-link:hover {
        color: var(--primary-ink);
      }
      .review-github-link-icon {
        width: 0.8125rem;
        height: 0.8125rem;
      }
      .review-comment {
        margin-block: 0;
        margin-inline: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-size: var(--boxel-font-sm);
        color: var(--card-foreground);
        border-left: 3px solid var(--border);
        font-style: normal;
        line-height: 1.6;
        background-color: var(--card);
        border-radius: 0 var(--radius) var(--radius) 0;
        transition:
          border-left-color 0.15s ease,
          background 0.15s ease;
        cursor: default;
        white-space: pre-line;
        overflow-wrap: anywhere;
      }
      .review-comment:hover {
        border-left-color: var(--destructive);
        background-color: color-mix(
          in oklch,
          var(--destructive) 5%,
          var(--card)
        );
      }
      .empty-state {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        background-color: var(--muted);
        color: var(--muted-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .empty-state-icon {
        width: 0.8125rem;
        height: 0.8125rem;
        border-radius: 50%;
        border: 2px solid var(--chart-4);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }
      .empty-state-dot {
        width: 0.25rem;
        height: 0.25rem;
        border-radius: 50%;
        background-color: var(--chart-4);
      }
      .empty-state-text {
        font-size: var(--boxel-font-xs);
        color: var(--muted-foreground);
      }
      .review-item--changes {
        background-color: color-mix(in oklch, var(--card) 10%, var(--card));
        border-color: color-mix(in oklch, var(--border) 30%, var(--card));
      }
      .review-item--approved {
        background-color: color-mix(in oklch, var(--chart-1) 10%, var(--card));
        border-color: color-mix(in oklch, var(--chart-1) 35%, var(--card));
      }
      .review-item--pending {
        background-color: color-mix(in oklch, var(--card) 8%, var(--card));
        border-color: color-mix(in oklch, var(--border) 25%, var(--card));
      }
      .review-item--pending .empty-state-text {
        color: var(--warning-ink);
        font-weight: 600;
      }
    </style>
  </template>
}
