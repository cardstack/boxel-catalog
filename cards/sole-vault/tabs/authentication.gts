import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Spinner } from '@cardstack/pretui/components/spinner';
import { StatePill } from '../../../components/state-pill';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';
import type { SoleVaultView } from '../sole-vault-app';

interface Signature {
  Args: {
    tracker: SoleVaultView;
  };
}

export class AuthenticationTab extends GlimmerComponent<Signature> {
  <template>
    <section class='pane pane--auth'>
      <h2 class='pane-h'>Authentication queue</h2>
      {{#if @tracker.vaultError}}
        <p class='empty' role='alert'>
          <ShieldCheckIcon width='22' height='22' aria-hidden='true' />
          The queue could not load:
          {{@tracker.vaultError}}
        </p>
      {{else if @tracker.vaultLoading}}
        <p class='empty' role='status'><Spinner />Fetching the queue…</p>
      {{else if @tracker.authRows.length}}
        {{! A wall of certificate plaques, not rows: each record IS a
        certificate, so it renders as one — the submitted photo,
        the verdict, and the mono certificate number a collector
        quotes into a dispute. The record still awaiting a verdict
        sorts first and wears the gold top rule unfinished (dashed):
        the vault's mark for "in the authenticator's hands". }}
        <div class='cert-wall'>
          {{#each @tracker.authRows as |a|}}
            {{! Native button: each certificate shows the item, verdict and date. }}
            <button
              type='button'
              class='cert {{if a.pending "cert--pending"}}'
              {{on 'click' (fn @tracker.open a.card)}}
            >
              {{#if a.photoUrl}}
                <img
                  class='cert-photo'
                  src={{a.photoUrl}}
                  alt=''
                  loading='lazy'
                />
              {{else}}
                <span class='cert-photo cert-photo--glyph'>
                  <ShieldCheckIcon width='28' height='28' aria-hidden='true' />
                </span>
              {{/if}}
              <span class='cert-body'>
                {{#if a.outcomeLabel}}
                  <StatePill @label={{a.outcomeLabel}} @hue={{a.outcomeHue}} />
                {{/if}}
                {{! The certificate number is the artifact — it gets the
                display treatment. A pending check has none yet and
                says so rather than sitting blank. }}
                {{#if a.certificateId}}
                  <span class='cert-no'>{{a.certificateId}}</span>
                {{else}}
                  <span class='cert-no cert-no--none'>awaiting verdict</span>
                {{/if}}
                <span class='cert-item'>{{a.itemTitle}}</span>
              </span>
              <span class='cert-foot'>
                {{#if a.service}}<span
                    class='cert-svc'
                  >{{a.service}}</span>{{/if}}
                {{#if a.turnaroundDays}}<span
                    class='cert-turn'
                  >{{a.turnaroundDays}}</span>{{/if}}
              </span>
            </button>
          {{/each}}
        </div>
      {{else}}
        <p class='empty'>
          <ShieldCheckIcon width='22' height='22' aria-hidden='true' />
          No legit checks recorded.
        </p>
      {{/if}}
    </section>
    <style scoped>
      .pane {
        animation: stage-enter 240ms cubic-bezier(0.16, 1, 0.3, 1) both;
      }
      @media (prefers-reduced-motion: reduce) {
        .pane {
          animation: none;
        }
      }
      .pane-h {
        margin: 0;
        font-family: var(--font-serif);
        font-size: 1.625rem;
        font-weight: 700;
        letter-spacing: -0.01em;
      }
      @media (prefers-reduced-motion: reduce) {
        .cert {
          transition: none;
        }
        .cert:hover,
        .cert:focus-visible {
          transform: none;
        }
      }
      .cert-wall {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
        gap: 1.25rem;
      }
      .cert {
        position: relative;
        display: flex;
        flex-direction: column;
        text-align: left;
        padding: 0;
        background: var(--card);
        border: 1px solid var(--_hairline);
        border-top: 3px solid var(--primary);
        border-radius: 6px;
        color: inherit;
        font: inherit;
        cursor: pointer;
        overflow: hidden;
        box-shadow: var(--shadow-xs);
        transition:
          transform 180ms cubic-bezier(0.16, 1, 0.3, 1),
          box-shadow 180ms cubic-bezier(0.16, 1, 0.3, 1);
      }
      .cert:hover,
      .cert:focus-visible {
        transform: translateY(-0.1875rem);
        box-shadow: var(--shadow-lg);
      }
      .cert:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
      }
      @media (prefers-reduced-motion: reduce) {
        .cert {
          transition: none;
        }
        .cert:hover,
        .cert:focus-visible {
          transform: none;
        }
      }
      .cert--pending {
        border-top-style: dashed;
      }
      .cert-photo {
        width: 100%;
        aspect-ratio: 4 / 3;
        object-fit: cover;
        display: block;
      }
      .cert-photo--glyph {
        display: grid;
        place-items: center;
        background: var(--muted);
        color: var(--muted-foreground);
      }
      .cert-body {
        display: grid;
        justify-items: start;
        gap: 0.4rem;
        padding: 0.85rem 1rem 0.6rem;
      }
      .cert-no {
        font-family: var(--font-mono);
        font-size: 1.0625rem;
        font-weight: 600;
        letter-spacing: 0.02em;
        color: var(--foreground);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
      }
      .cert-no--none {
        font-style: italic;
        font-weight: 400;
        color: var(--muted-foreground);
      }
      .cert-item {
        font-size: 0.875rem;
        line-height: 1.35;
        color: var(--muted-foreground);
      }
      .cert-foot {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 0.75rem;
        margin-top: auto;
        padding: 0.6rem 1rem 0.85rem;
        border-top: 1px solid var(--_hairline);
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .cert-svc {
        font-weight: 600;
        color: var(--foreground);
      }
      .empty {
        margin: 0;
        display: flex;
        align-items: center;
        gap: 0.6rem;
        padding: 2rem;
        background: var(--card);
        border: 1px solid var(--_hairline);
        border-radius: 6px;
        color: var(--muted-foreground);
        font-size: 0.9375rem;
        box-shadow: var(--shadow-xs);
      }
    </style>
  </template>
}
