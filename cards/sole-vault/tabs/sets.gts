import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { Spinner } from '@cardstack/pretui/components/spinner';
import { StatePill } from '../../../components/state-pill';
import TargetArrowIcon from '@cardstack/boxel-icons/target-arrow';
import PlusIcon from '@cardstack/boxel-icons/plus';
import type { SoleVaultView } from '../sole-vault-app';

interface Signature {
  Args: {
    tracker: SoleVaultView;
  };
}

export class SetsTab extends GlimmerComponent<Signature> {
  <template>
    <section class='pane pane--sets'>
      <div class='toolbar'>
        <div class='toolbar-left'><h2 class='pane-h'>Completion goals</h2></div>
        <div class='toolbar-right'>
          <Button
            @tone='primary'
            @appearance='accent'
            {{on 'click' @tracker.addSet}}
          >
            <PlusIcon width='16' height='16' role='presentation' />
            Add Set
          </Button>
        </div>
      </div>

      {{#if @tracker.vaultError}}
        <p class='empty' role='alert'>
          <TargetArrowIcon width='22' height='22' aria-hidden='true' />
          Goals could not load:
          {{@tracker.vaultError}}
        </p>
      {{else if @tracker.vaultLoading}}
        <p class='empty' role='status'><Spinner />Checking the goals…</p>
      {{else if @tracker.setProgress.length}}
        <ul class='ledger-list'>
          {{#each @tracker.setProgress as |row|}}
            <li class='goal'>
              {{! Native button: the row holds the set's progress meter and counts. }}
              <button
                type='button'
                class='goal-head'
                {{on 'click' (fn @tracker.open row.set)}}
              >
                {{! The set's own cover as the row anchor; the target
                glyph only stands in when no cover is recorded. }}
                {{#if row.coverUrl}}
                  <img
                    class='goal-thumb'
                    src={{row.coverUrl}}
                    alt=''
                    loading='lazy'
                  />
                {{else}}
                  <TargetArrowIcon
                    class='goal-glyph'
                    width='18'
                    height='18'
                    aria-hidden='true'
                  />
                {{/if}}
                {{! `cardTitle`, not the removed legacy `title` — the
                latter reads undefined and the goal renders nameless. }}
                <span class='goal-title'>{{row.set.cardTitle}}</span>
                {{#if row.complete}}
                  <StatePill @label='Complete' @hue='green' />
                {{/if}}
                <span class='goal-frac'>{{row.result.ownedCount}}<span
                    class='goal-frac-slash'
                  >/{{row.result.targetCount}}</span></span>
              </button>
              {{! Progress is computed here from the block's own exported
              function — the Set card never stored it. Drawn by
              boxel-ui's ProgressBar rather than a hand-rolled meter:
              it brings role='progressbar' with real
              aria-valuenow/min/max, replacing the role='img' +
              aria-label sentence this used to carry, and it owns its
              own fill width so the app stops building style strings. }}
              {{! aria-label attribute, NOT @label: ProgressBar renders
              @label as VISIBLE text inside the bar, and this meter is
              8px tall — the words shear straight across the track.
              The splatted attribute still names the progressbar for
              screen readers, which is all @label was here for.
              Rendered only while the hunt is on: at 100% the bar
              carries no information and the chip above says it. }}
              {{#unless row.complete}}
                <ProgressBar
                  class='meter'
                  @value={{row.result.percent}}
                  @max={{100}}
                  @hue='var(--primary-ink)'
                  aria-label='Set completion'
                />
                <p class='goal-sub'>{{row.result.percent}}% complete ·
                  {{row.result.missingProductIds.length}}
                  still needed</p>
              {{/unless}}
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class='empty'>
          <TargetArrowIcon width='22' height='22' aria-hidden='true' />
          No goals yet — a set is how the hunt gets tracked.
        </p>
      {{/if}}
    </section>
    <style scoped>
      .toolbar {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex-wrap: wrap;
        margin-bottom: 1rem;
      }
      .toolbar-left {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex: 1 1 auto;
        min-width: 0;
        flex-wrap: nowrap;
      }
      .toolbar-right {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex: 0 0 auto;
        margin-left: auto;
      }
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
      .wall,
      .ledger-list,
      .ledger-rows {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .ledger-list {
        display: grid;
        gap: 0.85rem;
      }
      .goal {
        background: var(--card);
        border: 1px solid var(--_hairline);
        border-top: 2px solid var(--primary);
        border-radius: 6px;
        padding: 1.1rem 1.4rem;
        display: grid;
        gap: 0.5rem;
        box-shadow: var(--shadow-xs);
        transition: box-shadow 180ms cubic-bezier(0.16, 1, 0.3, 1);
      }
      .goal:hover,
      .goal:focus-within {
        box-shadow: var(--shadow-md);
      }
      .goal-head {
        display: flex;
        align-items: center;
        gap: 0.6rem;
        background: none;
        border: 0;
        padding: 0;
        color: inherit;
        font: inherit;
        cursor: pointer;
        text-align: left;
        min-width: 0;
      }
      .goal-thumb {
        width: 48px;
        height: 48px;
        border-radius: 6px;
        object-fit: cover;
        flex: none;
      }
      .goal-glyph {
        color: var(--gold-ink, var(--primary));
        flex: none;
      }
      .goal-title {
        font-family: var(--font-serif);
        font-size: 1.125rem;
        font-weight: 700;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .goal-frac {
        margin-left: auto;
        font-family: var(--font-serif);
        font-size: 1.75rem;
        font-weight: 900;
        font-variant-numeric: tabular-nums;
        flex: none;
        color: var(--foreground);
      }
      .goal-frac-slash {
        font-size: 1.0625rem;
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .meter {
        --boxel-progress-bar-height: 5px;
        --boxel-progress-bar-border-radius: 999px;
        --boxel-progress-bar-background-color: var(--muted);
        --boxel-progress-bar-fill-color: var(--gold-ink, var(--primary));
        --boxel-progress-bar-border-color: transparent;
      }
      .goal-sub {
        margin: 0;
        font-size: 0.8125rem;
        color: var(--muted-foreground);
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
      @container vault (width < 860px) {
        .toolbar-left {
          flex-wrap: wrap;
        }
      }
    </style>
  </template>
}
