import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

import { FieldContainer } from '@cardstack/boxel-ui/components';
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
        <h2>Board settings</h2>
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
                <button
                  type='button'
                  class='echo-remove'
                  aria-label='Remove {{if echo.label echo.label "echo"}}'
                  {{on 'click' (fn this.removeEcho index)}}
                >Remove</button>
              </li>
            {{/each}}
          </ul>
        {{else}}
          <p class='empty'>No echoes accepted yet.</p>
        {{/if}}
      </div>

      <div class='ep-edit-danger'>
        <button type='button' {{on 'click' this.clearInk}}>Erase all ink</button>
        <span class='hint'>Removes every stroke and resets the view. Echoes
          stay.</span>
      </div>
    </section>

    <style scoped>
      .ep-edit {
        --paper: var(--ep-paper, #f7f4ec);
        --ink: var(--ep-ink, #2b3f8c);
        --echo: var(--ep-echo, #c33d2e);
        --chrome: var(--ep-chrome, #3a3527);
        --chrome-soft: var(--ep-chrome-soft, #6d6753);
        --edge: var(--ep-edge, #56503f);
        display: flex;
        flex-direction: column;
        gap: 18px;
        padding: 20px;
        font-family: var(--ep-font-chrome, 'IBM Plex Mono', monospace);
        color: var(--chrome);
      }
      .eyebrow {
        font-size: 9px;
        font-weight: 600;
        letter-spacing: 0.26em;
        text-transform: uppercase;
        color: var(--echo);
      }
      .ep-edit-head h2 {
        margin: 6px 0 4px;
        font-family: var(--ep-font-hand, 'Caveat', cursive);
        font-size: 30px;
        font-weight: 600;
        line-height: 1;
        color: var(--ink);
      }
      .hint {
        margin: 0;
        font-size: 10.5px;
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
        padding: 8px 12px;
        border-left: 1px solid rgba(43, 63, 140, 0.4);
      }
      .fact:first-child {
        border-left: 0;
      }
      .fact-k {
        display: block;
        font-size: 8px;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        color: var(--chrome-soft);
        margin-bottom: 3px;
      }
      .fact-v {
        font-size: 15px;
        font-weight: 600;
        color: var(--ink);
      }
      .fact-v.accent {
        color: var(--echo);
      }
      .ep-edit-echoes ul {
        list-style: none;
        margin: 8px 0 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .ep-edit-echoes li {
        display: flex;
        align-items: baseline;
        gap: 10px;
        padding: 8px 10px;
        border: 1px solid var(--edge);
        background: var(--paper);
      }
      .echo-mode {
        flex: none;
        font-size: 8px;
        font-weight: 600;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: var(--echo);
      }
      .echo-text {
        flex: 1;
        min-width: 0;
        font-family: var(--ep-font-hand, 'Caveat', cursive);
        font-size: 17px;
        color: var(--echo);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .echo-remove,
      .ep-edit-danger button {
        flex: none;
        border: 1.5px solid var(--echo);
        background: none;
        color: var(--echo);
        font: 600 9px/1 var(--ep-font-chrome, 'IBM Plex Mono', monospace);
        letter-spacing: 0.18em;
        text-transform: uppercase;
        padding: 7px 10px;
        cursor: pointer;
      }
      .empty {
        margin: 8px 0 0;
        font-size: 10.5px;
        color: var(--chrome-soft);
      }
      .ep-edit-danger {
        display: flex;
        align-items: center;
        gap: 12px;
        padding-top: 4px;
      }
    </style>
  </template>
}
