import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

import { Button, FieldContainer } from '@cardstack/boxel-ui/components';
import { Component } from '@cardstack/base/card-api';

import { parseInk } from '../utils/index';
import type { EchoPad } from '../echo-pad';

// The default edit form would expose inkJson / viewportJson as raw textareas —
// hostile to edit and easy to corrupt. This form offers only what a person
// would sensibly change, and summarizes the machine-owned state read-only.
export class EchoPadEdit extends Component<typeof EchoPad> {
  get strokeCount(): number {
    return parseInk(this.args.model?.inkJson).strokes.length;
  }

  get echoes() {
    return (this.args.model?.echoes ?? []).filter(Boolean);
  }

  removeEcho = (index: number) => {
    let model = this.args.model;
    if (!model) {
      return;
    }
    model.echoes = this.echoes.filter((_, i) => i !== index);
  };

  clearInk = () => {
    let model = this.args.model;
    if (!model) {
      return;
    }
    model.inkJson = '';
    model.viewportJson = '';
  };

  <template>
    <section class='ep-edit'>
      <header class='ep-edit-head'>
        <span class='eyebrow'>Echo Pad</span>
        <h3>Board settings</h3>
        <p class='hint'>Drawing happens on the board itself — open it to write,
          circle ink and echo.</p>
      </header>

      <FieldContainer @label='Board name' @vertical={{true}}>
        <@fields.boardName />
      </FieldContainer>

      <div class='ep-edit-facts'>
        <div class='fact'>
          <span class='fact-k'>Ink strokes</span>
          <span class='fact-v'>{{this.strokeCount}}</span>
        </div>
        <div class='fact'>
          <span class='fact-k'>Accepted echoes</span>
          <span class='fact-v accent'>{{this.echoes.length}}</span>
        </div>
      </div>

      <div class='ep-edit-echoes'>
        <span class='eyebrow'>Echoes</span>
        {{#if this.echoes.length}}
          <ul>
            {{#each this.echoes as |echo index|}}
              <li>
                <span class='echo-mode'>{{if echo.mode echo.mode 'echo'}}</span>
                <span class='echo-text'>{{if
                    echo.content
                    echo.content
                    '—'
                  }}</span>
                <Button
                  @kind='text-only'
                  @size='small'
                  class='echo-remove'
                  aria-label='Remove {{if echo.label echo.label "echo"}}'
                  {{on 'click' (fn this.removeEcho index)}}
                >Remove</Button>
              </li>
            {{/each}}
          </ul>
        {{else}}
          <p class='empty'>No echoes accepted yet.</p>
        {{/if}}
      </div>

      <div class='ep-edit-danger'>
        <Button
          @kind='text-only'
          @size='small'
          class='clear-ink-btn'
          {{on 'click' this.clearInk}}
        >Erase all ink</Button>
        <span class='hint'>Removes every stroke and resets the view. Echoes
          stay.</span>
      </div>
    </section>

    <style scoped>
      .ep-edit {
        /* Board palette. Glimmer scopes <style> per component, so this block
           is necessarily duplicated in isolated.gts, edit.gts and BOTH
           components in formats.gts (Embedded + Fitted) — 4 copies. Change
           one, change all four, or the formats drift apart. */
        --paper: var(--background);
        --ink: var(--chart-4);
        --echo: var(--chart-1);
        --chrome: var(--foreground);
        --chrome-soft: var(--muted-foreground);
        --edge: var(--border);
        --font-chrome: var(--font-mono);
        --font-hand: 'Caveat', cursive;
        display: flex;
        flex-direction: column;
        gap: 1.125rem;
        padding: 1.25rem;
        font-family: var(--font-chrome);
        color: var(--chrome);
      }
      .eyebrow {
        font-size: 0.5625rem;
        font-weight: 600;
        letter-spacing: 0.26em;
        text-transform: uppercase;
        color: var(--echo);
      }
      .ep-edit-head h3 {
        margin: 0.375rem 0 0.25rem;
        font-family: var(--font-hand);
        font-size: 1.875rem;
        font-weight: 600;
        line-height: 1;
        color: var(--ink);
      }
      .hint {
        margin: 0;
        font-size: 0.65625rem;
        line-height: 1.6;
        color: var(--chrome-soft);
      }
      .ep-edit-facts {
        display: flex;
        gap: 0;
        border: 1.5px solid var(--ink);
      }
      .fact {
        flex: 1;
        padding: 0.5rem 0.75rem;
        border-left: 1px solid color-mix(in oklch, var(--ink) 40%, transparent);
      }
      .fact:first-child {
        border-left: 0;
      }
      .fact-k {
        display: block;
        font-size: 0.5rem;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        color: var(--chrome-soft);
        margin-bottom: 0.1875rem;
      }
      .fact-v {
        font-size: 0.9375rem;
        font-weight: 600;
        color: var(--ink);
      }
      .fact-v.accent {
        color: var(--echo);
      }
      .ep-edit-echoes ul {
        list-style: none;
        margin: 0.5rem 0 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
      }
      .ep-edit-echoes li {
        display: flex;
        align-items: baseline;
        gap: 0.625rem;
        padding: 0.5rem 0.625rem;
        border: 1px solid var(--edge);
        background-color: var(--paper);
      }
      .echo-mode {
        flex: none;
        font-size: 0.5rem;
        font-weight: 600;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: var(--echo);
      }
      .echo-text {
        flex: 1;
        min-width: 0;
        font-family: var(--font-hand);
        font-size: 1.0625rem;
        color: var(--echo);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .ep-edit-echoes li .echo-remove,
      .ep-edit-danger .clear-ink-btn {
        flex: none;
        border: 1.5px solid var(--echo);
        background-color: transparent;
        color: var(--echo);
        font-weight: 600;
        font-size: 0.5625rem;
        line-height: 1;
        font-family: var(--font-chrome);
        letter-spacing: 0.18em;
        text-transform: uppercase;
        padding: 0.4375rem 0.625rem;
        cursor: pointer;
      }
      .empty {
        margin: 0.5rem 0 0;
        font-size: 0.65625rem;
        color: var(--chrome-soft);
      }
      .ep-edit-danger {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding-top: 0.25rem;
      }
    </style>
  </template>
}
