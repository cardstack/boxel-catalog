import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { BoxelSelect } from '@cardstack/boxel-ui/components';
import type { Placement } from '@floating-ui/dom';

import {
  Popover,
  type PopoverKind,
  type PopoverAnchoring,
  type PopoverSize,
  type PopoverBackdrop,
  type PopoverElevation,
  type PopoverKeyboardModel,
} from '../index.ts';
import CodeSnippet from '../../../components/code-snippet';

/**
 * A config explorer for `<Popover>`. Every exported type union is shown
 * as a `BoxelSelect` across the top, so you can mix any combination and
 * watch a live `<Popover>` preview + the generated invocation update
 * together. The preview body holds both a listbox and an editor so the
 * `PopoverKeyboardModel` select has a visible effect: 'pick' autofocuses
 * the listbox (arrow-navigable), 'edit' focuses the input.
 */
class PopoverPlaygroundIsolated extends Component<typeof PopoverPlayground> {
  kindOptions = ['details', 'preview', 'edit', 'tools'];
  anchoringOptions = ['beside', 'overlay', 'center'];
  sizeOptions = ['compact', 'comfortable', 'spacious', 'auto'];
  backdropOptions = ['none', 'tint', 'blur', 'dim'];
  elevationOptions = ['flat', 'raised', 'elevated', 'floating'];
  keyboardOptions = ['pick', 'edit'];

  @tracked kind: PopoverKind = 'edit';
  @tracked anchoring: PopoverAnchoring = 'beside';
  @tracked size: PopoverSize = 'comfortable';
  @tracked backdrop: PopoverBackdrop = 'tint';
  @tracked elevation: PopoverElevation = 'raised';
  @tracked keyboard: PopoverKeyboardModel = 'edit';

  @tracked open = false;

  // Minimal pick-list so keyboardModel='pick' has something to focus
  // and arrow-navigate (the "inner picker primitive" the popover's
  // keyboard model targets).
  pickOptions = ['Low', 'Medium', 'High', 'Urgent'];
  @tracked pickIndex = 1;

  @action onPickKeydown(event: Event): void {
    const e = event as KeyboardEvent;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      this.pickIndex = Math.min(
        this.pickOptions.length - 1,
        this.pickIndex + 1,
      );
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      this.pickIndex = Math.max(0, this.pickIndex - 1);
    } else if (e.key === 'Home') {
      e.preventDefault();
      this.pickIndex = 0;
    } else if (e.key === 'End') {
      e.preventDefault();
      this.pickIndex = this.pickOptions.length - 1;
    }
  }

  @action onPickClick(index: number): void {
    this.pickIndex = index;
  }

  // ── extra knobs beyond the 6 type unions: the beside-positioning
  // args (@placement / @offset / @arrow) ──
  @tracked placement: Placement = 'bottom-start';
  @tracked offset = 8;
  @tracked arrowOn = false;

  placementOptions: Placement[] = [
    'top',
    'top-start',
    'top-end',
    'bottom',
    'bottom-start',
    'bottom-end',
    'left',
    'left-start',
    'left-end',
    'right',
    'right-start',
    'right-end',
  ];
  offsetOptions = ['0', '4', '8', '12', '16', '24'];
  arrowOptions = ['off', 'on'];

  get offsetStr(): string {
    return String(this.offset);
  }

  get arrowChoice(): string {
    return this.arrowOn ? 'on' : 'off';
  }

  @action setPlacement(value: Placement): void {
    this.placement = value;
  }

  @action setOffset(value: string): void {
    this.offset = Number(value);
  }

  @action setArrow(value: string): void {
    this.arrowOn = value === 'on';
  }

  /** Generated invocation reflecting every current selection. */
  get previewCode(): string {
    const lines = [
      `<Popover`,
      `  @anchor='[data-anchor=preview]'`,
      `  @open={{this.open}}`,
      `  @kind='${this.kind}'`,
      `  @anchoring='${this.anchoring}'`,
    ];
    // @placement / @offset / @arrow only apply to beside.
    if (this.anchoring === 'beside') {
      lines.push(`  @placement='${this.placement}'`);
      lines.push(`  @offset={{${this.offset}}}`);
      if (this.arrowOn) lines.push(`  @arrow={{true}}`);
    }
    lines.push(`  @size='${this.size}'`);
    lines.push(`  @backdrop='${this.backdrop}'`);
    lines.push(`  @elevation='${this.elevation}'`);
    lines.push(`  @keyboardModel='${this.keyboard}'`);
    lines.push(`  @onDismiss={{this.close}}`);
    lines.push(`>`, `  …your content…`, `</Popover>`);
    return lines.join('\n');
  }

  @action setKind(value: PopoverKind): void {
    this.kind = value;
  }

  @action setAnchoring(value: PopoverAnchoring): void {
    this.anchoring = value;
  }

  @action setSize(value: PopoverSize): void {
    this.size = value;
  }

  @action setBackdrop(value: PopoverBackdrop): void {
    this.backdrop = value;
  }

  @action setElevation(value: PopoverElevation): void {
    this.elevation = value;
  }

  @action setKeyboard(value: PopoverKeyboardModel): void {
    this.keyboard = value;
  }

  @action openPreview(): void {
    this.open = true;
  }

  @action close(): void {
    this.open = false;
  }

  <template>
    <div class='pp'>
      <div class='pp-section'>Type axes</div>
      <div class='pp-axes'>
        <div class='pp-axis'>
          <span class='pp-label'>PopoverKind</span>
          <BoxelSelect
            @options={{this.kindOptions}}
            @selected={{this.kind}}
            @onChange={{this.setKind}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <code class='pp-typeline'>details | preview | edit | tools</code>
        </div>
        <div class='pp-axis'>
          <span class='pp-label'>PopoverAnchoring</span>
          <BoxelSelect
            @options={{this.anchoringOptions}}
            @selected={{this.anchoring}}
            @onChange={{this.setAnchoring}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <code class='pp-typeline'>beside | overlay | center</code>
        </div>
        <div class='pp-axis'>
          <span class='pp-label'>PopoverSize</span>
          <BoxelSelect
            @options={{this.sizeOptions}}
            @selected={{this.size}}
            @onChange={{this.setSize}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <code class='pp-typeline'>compact | comfortable | spacious | auto</code>
        </div>
        <div class='pp-axis'>
          <span class='pp-label'>PopoverBackdrop</span>
          <BoxelSelect
            @options={{this.backdropOptions}}
            @selected={{this.backdrop}}
            @onChange={{this.setBackdrop}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <code class='pp-typeline'>none | tint | blur | dim</code>
        </div>
        <div class='pp-axis'>
          <span class='pp-label'>PopoverElevation</span>
          <BoxelSelect
            @options={{this.elevationOptions}}
            @selected={{this.elevation}}
            @onChange={{this.setElevation}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <code class='pp-typeline'>flat | raised | elevated | floating</code>
        </div>
        <div class='pp-axis'>
          <span class='pp-label'>PopoverKeyboardModel</span>
          <BoxelSelect
            @options={{this.keyboardOptions}}
            @selected={{this.keyboard}}
            @onChange={{this.setKeyboard}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <code class='pp-typeline'>pick | edit</code>
        </div>
      </div>

      <div class='pp-section'>Positioning &amp; behavior</div>
      <div class='pp-axes'>
        <div class='pp-axis'>
          <span class='pp-label'>@placement</span>
          <BoxelSelect
            @options={{this.placementOptions}}
            @selected={{this.placement}}
            @onChange={{this.setPlacement}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <code class='pp-typeline'>Floating UI side · beside only</code>
        </div>
        <div class='pp-axis'>
          <span class='pp-label'>@offset</span>
          <BoxelSelect
            @options={{this.offsetOptions}}
            @selected={{this.offsetStr}}
            @onChange={{this.setOffset}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}px
          </BoxelSelect>
          <code class='pp-typeline'>anchor gap · beside only</code>
        </div>
        <div class='pp-axis'>
          <span class='pp-label'>@arrow</span>
          <BoxelSelect
            @options={{this.arrowOptions}}
            @selected={{this.arrowChoice}}
            @onChange={{this.setArrow}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <code class='pp-typeline'>caret · beside only</code>
        </div>
      </div>

      <div class='pp-section'>Live preview</div>
      <div class='pp-preview'>
        {{! Hover is just a DOM event the host wires — no state machine
            needed for a single anchor. mouseenter opens; click is kept
            for touch devices that have no hover. Closing is handled by
            the popover's own Esc / outside-click via @onDismiss. }}
        <button
          type='button'
          class='pp-open'
          data-anchor='pp-preview'
          {{on 'mouseenter' this.openPreview}}
          {{on 'click' this.openPreview}}
        >
          Hover to preview ▾
        </button>

        {{#if this.open}}
          <Popover
            @anchor='[data-anchor=pp-preview]'
            @open={{true}}
            @kind={{this.kind}}
            @anchoring={{this.anchoring}}
            @placement={{this.placement}}
            @offset={{this.offset}}
            @arrow={{this.arrowOn}}
            @size={{this.size}}
            @backdrop={{this.backdrop}}
            @elevation={{this.elevation}}
            @keyboardModel={{this.keyboard}}
            @onDismiss={{this.close}}
            as |kind|
          >
            <div class='pp-body'>
              <div class='pp-eyebrow'>{{kind}}</div>
              <div class='pp-config'>
                {{this.anchoring}}
                ·
                {{this.size}}
                ·
                {{this.backdrop}}
                ·
                {{this.elevation}}
              </div>

              {{! The body carries BOTH a listbox and an editor. On open
                  the popover autofocuses the one its keyboardModel
                  names: 'pick' → the listbox (↑/↓ navigate), the
                  'edit' model → the text input. Switch the
                  PopoverKeyboardModel select and reopen to feel it. }}
              <div class='pp-pickwrap'>
                <span class='pp-cap'>keyboardModel='pick' focuses this:</span>
                <ul
                  class='pp-listbox'
                  role='listbox'
                  tabindex='0'
                  aria-label='Priority'
                  {{on 'keydown' this.onPickKeydown}}
                >
                  {{#each this.pickOptions as |option index|}}
                    <li
                      role='option'
                      class='pp-option'
                      aria-selected='{{if
                        (eq index this.pickIndex)
                        "true"
                        "false"
                      }}'
                      {{on 'click' (fn this.onPickClick index)}}
                    >{{option}}</li>
                  {{/each}}
                </ul>
              </div>

              <div class='pp-pickwrap'>
                <span class='pp-cap'>the edit-* models focus this:</span>
                <input class='pp-input' placeholder='Editable body…' />
              </div>
            </div>
          </Popover>
        {{/if}}
      </div>

      <div class='pp-section'>Generated code</div>
      <CodeSnippet @code={{this.previewCode}} />

      <div class='pp-section'>Other API args (set in code, not shown above)</div>
      <div class='pp-args'>
        <div class='pp-arg'>
          <code>@anchor</code>
          <span><em>string</em>
            (required) — CSS selector that resolves the source element.</span>
        </div>
        <div class='pp-arg'>
          <code>@open</code>
          <span><em>boolean</em>
            (required) — mounts the popover when true.</span>
        </div>
        <div class='pp-arg'>
          <code>@onDismiss</code>
          <span><em>fn</em>
            — fires on Esc / outside-click; the host sets open to false.</span>
        </div>
        <div class='pp-arg'>
          <code>@canEscalateTo</code>
          <span><em>PopoverKind[]</em>
            — kinds the corner ✎/ⓘ glyph can escalate to.</span>
        </div>
        <div class='pp-arg'>
          <code>@onEscalate</code>
          <span><em>fn(next)</em>
            — fired when the escalation glyph is clicked.</span>
        </div>
        <div class='pp-arg'>
          <code>@autoFocus</code>
          <span><em>boolean</em>
            — override the per-kind autofocus default (off for details).</span>
        </div>
        <div class='pp-arg'>
          <code>@focusToken</code>
          <span><em>string | number</em>
            — stable token so autofocus runs once per open, not on every
            re-render.</span>
        </div>
        <div class='pp-arg'>
          <code>@relativeScale</code>
          <span><em>number</em>
            — damped scale multiplier for zoomable canvas hosts (ignored for
            plane).</span>
        </div>
        <div class='pp-arg'>
          <code>@layerTier</code>
          /
          <code>@zIndex</code>
          <span><em>SurfaceLayerTier / number</em>
            — override the auto z-index layer.</span>
        </div>
        <div class='pp-arg'>
          <code>@role</code>
          <span><em>string</em>
            — ARIA role override (default tooltip for details, else dialog).</span>
        </div>
        <div class='pp-arg'>
          <code>@label</code>
          /
          <code>@labelledby</code>
          /
          <code>@describedby</code>
          <span><em>string</em>
            — ARIA labeling (aria-label / aria-labelledby / aria-describedby).</span>
        </div>
      </div>
    </div>

    <style scoped>
      .pp {
        display: grid;
        gap: 16px;
        padding: 24px;
        max-width: 760px;
        font:
          14px/1.4 system-ui,
          sans-serif;
      }
      .pp-section {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: #6b7280;
      }
      .pp-axes {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
        gap: 12px;
      }
      .pp-axis {
        display: grid;
        gap: 6px;
        align-content: start;
      }
      .pp-label {
        font-size: 11px;
        font-weight: 600;
        color: #4338ca;
      }
      .pp-typeline {
        font-family: ui-monospace, monospace;
        font-size: 10px;
        color: #9ca3af;
        white-space: normal;
        word-break: break-word;
      }
      .pp-preview {
        padding-top: 4px;
      }
      .pp-open {
        padding: 6px 12px;
        border: 1px solid #d1d5db;
        border-radius: 6px;
        background: #fff;
        cursor: pointer;
        font: inherit;
      }
      .pp-open:hover {
        background: #f9fafb;
      }
      .pp-body {
        padding: 10px 12px;
        display: grid;
        gap: 6px;
      }
      .pp-eyebrow {
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: #6b7280;
      }
      .pp-config {
        font-size: 12px;
        color: #374151;
      }
      .pp-input {
        padding: 6px 8px;
        border: 1px solid #d1d5db;
        border-radius: 4px;
        font: inherit;
        width: 100%;
      }
      .pp-pickwrap {
        display: grid;
        gap: 4px;
      }
      .pp-cap {
        font-size: 10px;
        color: #9ca3af;
      }
      .pp-listbox {
        list-style: none;
        margin: 0;
        padding: 4px;
        display: grid;
        gap: 2px;
        border: 1px solid #d1d5db;
        border-radius: 6px;
      }
      .pp-listbox:focus-visible {
        outline: 2px solid #4f46e5;
        outline-offset: 1px;
      }
      .pp-option {
        padding: 4px 8px;
        border-radius: 4px;
        cursor: pointer;
      }
      .pp-option[aria-selected='true'] {
        background: #eef2ff;
        color: #4338ca;
        font-weight: 600;
      }
      .pp-args {
        margin: 0;
        display: grid;
        gap: 8px;
      }
      .pp-arg {
        display: grid;
        grid-template-columns: 200px 1fr;
        gap: 12px;
        align-items: baseline;
        font-size: 12px;
      }
      .pp-arg code {
        font-family: ui-monospace, monospace;
        font-size: 11px;
        color: #4338ca;
      }
      .pp-arg span {
        color: #4b5563;
      }
      .pp-arg em {
        font-style: normal;
        font-family: ui-monospace, monospace;
        color: #6b7280;
      }
      @media (max-width: 520px) {
        .pp-arg {
          grid-template-columns: 1fr;
          gap: 2px;
        }
      }
    </style>
  </template>
}

export class PopoverPlayground extends CardDef {
  static displayName = 'Popover Playground';

  @field title = contains(StringField);

  static isolated = PopoverPlaygroundIsolated;
}
