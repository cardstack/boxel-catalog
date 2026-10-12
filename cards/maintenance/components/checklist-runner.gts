import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn, concat } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { BoxelInput } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import CheckIcon from '@cardstack/boxel-icons/check';
import XIcon from '@cardstack/boxel-icons/x';
import MinusIcon from '@cardstack/boxel-icons/minus';
import CameraIcon from '@cardstack/boxel-icons/camera';
import PenIcon from '@cardstack/boxel-icons/pen';

import type { ChecklistField, ChecklistItemField } from '../checklist-field';
import { checklistStats, measureDelta } from '../utils/maintenance';

interface Signature {
  Args: {
    checklist: ChecklistField;
    /** Stamped on each item as it is resolved. */
    actorName?: string;
    /** Called after every change so the host can save the card. */
    onChange?: () => void;
    readonly?: boolean;
  };
  Element: HTMLElement;
}

type Result = 'pass' | 'fail' | 'na' | 'pending';

/**
 * The interactive executor for any Checklist: thumb-sized rows, pass / fail
 * / n/a, measure inputs with unit and tolerance (out of tolerance auto-fails
 * and says by how much), a photo slot (URL), text and signature items,
 * progress and "required remaining".
 *
 * It mutates the checklist's items in place (they are contained fields on
 * the host card) and calls `onChange` so the host decides when to save.
 * Completion maths is `checklistStats` — the same function Complete Work
 * Order uses to refuse an incomplete order, so the runner can never say
 * "done" when the command would say "not yet".
 *
 * Generic (l03): onboarding checklists, publish checklists and audit
 * procedures run through the same component.
 */
export class ChecklistRunner extends GlimmerComponent<Signature> {
  get items(): ChecklistItemField[] {
    return (this.args.checklist?.items ?? []).filter(
      Boolean,
    ) as ChecklistItemField[];
  }

  get stats() {
    return checklistStats(this.items);
  }

  get fillStyle() {
    return htmlSafe(`width: ${this.stats.completionPercent}%`);
  }

  private stamp(item: ChecklistItemField, result: Result) {
    item.result = result;
    if (result === 'pending') {
      item.completedAt = undefined as unknown as Date;
      item.completedByName = undefined as unknown as string;
    } else {
      item.completedAt = new Date();
      if (this.args.actorName) {
        item.completedByName = this.args.actorName;
      }
    }
    this.args.onChange?.();
  }

  setResult = (item: ChecklistItemField, result: Result) => {
    if (this.args.readonly) return;
    // tapping the active result again clears it
    this.stamp(item, item.result === result ? 'pending' : result);
  };

  setMeasure = (item: ChecklistItemField, raw: string) => {
    if (this.args.readonly) return;
    item.value = raw;
    if (raw === '' || raw == null) {
      this.stamp(item, 'pending');
      return;
    }
    let n = Number(raw);
    if (isNaN(n)) {
      this.stamp(item, 'pending');
      return;
    }
    let d = measureDelta(item);
    this.stamp(item, d == null || d === 0 ? 'pass' : 'fail');
  };

  setText = (item: ChecklistItemField, raw: string) => {
    if (this.args.readonly) return;
    item.value = raw;
    this.stamp(item, raw?.trim() ? 'pass' : 'pending');
  };

  setPhoto = (item: ChecklistItemField, raw: string) => {
    if (this.args.readonly) return;
    item.photoUrl = raw;
    this.stamp(item, raw?.trim() ? 'pass' : 'pending');
  };

  setNote = (item: ChecklistItemField, raw: string) => {
    if (this.args.readonly) return;
    item.note = raw;
    this.args.onChange?.();
  };

  expectation = (item: ChecklistItemField) => {
    if (item.kind !== 'measure' || item.expectedValue == null) return '';
    let tol = item.tolerance ? ` ± ${item.tolerance}` : '';
    return `${item.expectedValue}${tol} ${item.unit ?? ''}`.trim();
  };

  deltaLabel = (item: ChecklistItemField) => {
    let d = measureDelta(item);
    if (d == null || d === 0) return '';
    return `${d > 0 ? '+' : ''}${d} ${item.unit ?? ''} out of tolerance`.trim();
  };

  isKind = (item: ChecklistItemField, kind: string) => item.kind === kind;

  <template>
    <section class='runner' aria-label='Checklist' ...attributes>
      <header class='runner-head'>
        <div class='runner-title'>{{if
            @checklist.title
            @checklist.title
            'Checklist'
          }}</div>
        <div class='runner-progress'>
          <span class='runner-count'>{{this.stats.done}}
            /
            {{this.stats.total}}</span>
          {{#if this.stats.requiredRemaining}}
            <span class='runner-req'>{{this.stats.requiredRemaining}}
              required remaining</span>
          {{else if this.stats.isComplete}}
            <span class='runner-ok'>All required steps resolved</span>
          {{/if}}
          {{#if this.stats.failedCount}}
            <span class='runner-fail'>{{this.stats.failedCount}} failed</span>
          {{/if}}
        </div>
        <div
          class='runner-bar'
          role='progressbar'
          aria-valuenow={{this.stats.completionPercent}}
          aria-valuemin='0'
          aria-valuemax='100'
        ><span class='runner-fill' style={{this.fillStyle}}></span></div>
      </header>

      <ol class='runner-items'>
        {{#each this.items as |item|}}
          <li
            class='runner-item
              {{if item.result (concat "is-" item.result) "is-pending"}}
              {{if item.isOutOfTolerance "is-oot"}}'
          >
            <div class='item-main'>
              <div class='item-label'>
                {{item.label}}
                {{#if item.required}}<span
                    class='item-req'
                    title='required'
                  >required</span>{{/if}}
              </div>

              {{#if (this.isKind item 'measure')}}
                <div class='item-measure'>
                  <BoxelInput
                    @type='number'
                    @value={{item.value}}
                    @onInput={{fn this.setMeasure item}}
                    @disabled={{@readonly}}
                    @placeholder={{this.expectation item}}
                    aria-label='{{item.label}} measurement'
                  />
                  <span class='item-unit'>{{item.unit}}</span>
                  <span class='item-exp'>expected
                    {{this.expectation item}}</span>
                  {{#if item.isOutOfTolerance}}
                    <span class='item-delta'>{{this.deltaLabel item}}</span>
                  {{/if}}
                </div>
              {{else if (this.isKind item 'text')}}
                <BoxelInput
                  @value={{item.value}}
                  @onInput={{fn this.setText item}}
                  @disabled={{@readonly}}
                  @placeholder='Type the observation'
                  aria-label='{{item.label}}'
                />
              {{else if (this.isKind item 'signature')}}
                <div class='item-sign'>
                  <PenIcon class='item-icon' />
                  <BoxelInput
                    @value={{item.value}}
                    @onInput={{fn this.setText item}}
                    @disabled={{@readonly}}
                    @placeholder='Sign with your full name'
                    aria-label='{{item.label}} signature'
                  />
                </div>
              {{else if (this.isKind item 'photo')}}
                <div class='item-photo'>
                  <CameraIcon class='item-icon' />
                  <BoxelInput
                    @type='url'
                    @value={{item.photoUrl}}
                    @onInput={{fn this.setPhoto item}}
                    @disabled={{@readonly}}
                    @placeholder='Paste the photo URL'
                    aria-label='{{item.label}} photo'
                  />
                  {{#if item.photoUrl}}
                    <img class='item-thumb' src={{item.photoUrl}} alt='' />
                  {{/if}}
                </div>
              {{/if}}

              <BoxelInput
                class='item-note'
                @value={{item.note}}
                @onInput={{fn this.setNote item}}
                @disabled={{@readonly}}
                @placeholder='Note (optional)'
                aria-label='{{item.label}} note'
              />
            </div>

            <div class='item-actions' role='group' aria-label='Result'>
              <button
                type='button'
                class='res res-pass {{if (eq item.result "pass") "active"}}'
                disabled={{@readonly}}
                aria-pressed={{if (eq item.result 'pass') 'true' 'false'}}
                title='Pass'
                aria-label='{{item.label}}: Pass'
                {{on 'click' (fn this.setResult item 'pass')}}
              ><CheckIcon /></button>
              <button
                type='button'
                class='res res-fail {{if (eq item.result "fail") "active"}}'
                disabled={{@readonly}}
                aria-pressed={{if (eq item.result 'fail') 'true' 'false'}}
                title='Fail'
                aria-label='{{item.label}}: Fail'
                {{on 'click' (fn this.setResult item 'fail')}}
              ><XIcon /></button>
              <button
                type='button'
                class='res res-na {{if (eq item.result "na") "active"}}'
                disabled={{@readonly}}
                aria-pressed={{if (eq item.result 'na') 'true' 'false'}}
                title='Not applicable'
                aria-label='{{item.label}}: Not applicable'
                {{on 'click' (fn this.setResult item 'na')}}
              ><MinusIcon /></button>
            </div>
          </li>
        {{else}}
          <li class='runner-empty'>This checklist has no steps yet.</li>
        {{/each}}
      </ol>
    </section>
    <style scoped>
      .runner {
        display: grid;
        gap: var(--boxel-sp-sm);
        container-type: inline-size;
        color: var(--foreground);
      }
      .runner-head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .runner-title {
        font-weight: 600;
        font-size: var(--boxel-font-size);
      }
      .runner-progress {
        display: flex;
        gap: var(--boxel-sp-xs);
        align-items: baseline;
        flex-wrap: wrap;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .runner-count {
        font-variant-numeric: tabular-nums;
        font-weight: 600;
        color: var(--foreground);
      }
      .runner-req {
        color: var(--foreground);
      }
      .runner-ok {
        color: var(--foreground);
        font-weight: 600;
      }
      .runner-fail {
        color: var(--destructive, var(--foreground));
        font-weight: 600;
      }
      .runner-bar {
        height: 6px;
        border-radius: 3px;
        background: var(--muted);
        overflow: hidden;
      }
      .runner-fill {
        display: block;
        height: 100%;
        background: var(--primary);
        transition: width 200ms ease;
      }
      .runner-items {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .runner-item {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        gap: var(--boxel-sp-sm);
        align-items: start;
        padding: var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        background: var(--card);
      }
      .runner-item.is-pass {
        border-color: color-mix(in oklab, var(--primary) 35%, var(--border));
        background: color-mix(in oklab, var(--primary) 5%, var(--card));
      }
      .runner-item.is-fail,
      .runner-item.is-oot {
        border-color: color-mix(
          in oklab,
          var(--destructive, var(--foreground)) 35%,
          var(--border)
        );
        background: color-mix(
          in oklab,
          var(--destructive, var(--foreground)) 5%,
          var(--card)
        );
      }
      .runner-item.is-na {
        opacity: 0.8;
      }
      .item-main {
        display: grid;
        gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .item-label {
        font-size: var(--boxel-font-size);
        font-weight: 500;
        display: flex;
        gap: var(--boxel-sp-xs);
        align-items: baseline;
        flex-wrap: wrap;
      }
      .item-req {
        font-size: var(--boxel-font-size-xs);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .item-measure {
        display: grid;
        grid-template-columns: minmax(6rem, 10rem) auto;
        gap: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        align-items: center;
      }
      .item-unit {
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .item-exp {
        grid-column: 1 / -1;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .item-delta {
        grid-column: 1 / -1;
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--destructive, var(--foreground));
      }
      .item-sign,
      .item-photo {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        gap: var(--boxel-sp-xs);
        align-items: center;
      }
      .item-icon {
        width: 1rem;
        height: 1rem;
        color: var(--muted-foreground);
      }
      .item-thumb {
        grid-column: 2;
        max-height: 7rem;
        border-radius: var(--boxel-border-radius-sm);
        object-fit: cover;
        justify-self: start;
      }
      .item-note {
        font-size: var(--boxel-font-size-xs);
      }
      .item-actions {
        display: flex;
        gap: var(--boxel-sp-4xs);
      }
      .res {
        width: 44px;
        height: 44px;
        display: grid;
        place-items: center;
        border-radius: var(--boxel-border-radius-sm);
        border: 1px solid var(--border);
        background: var(--card);
        color: var(--muted-foreground);
        cursor: pointer;
        transition:
          transform 120ms ease-out,
          background-color 120ms ease-out,
          border-color 120ms ease-out,
          color 120ms ease-out;
      }
      .res:active:not(:disabled) {
        transform: scale(0.9);
        transition-duration: 60ms;
      }
      .res-pass.active,
      .res-fail.active,
      .res-na.active {
        animation: res-pop 180ms ease-out;
      }
      @keyframes res-pop {
        0% {
          transform: scale(0.85);
        }
        60% {
          transform: scale(1.08);
        }
        100% {
          transform: scale(1);
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .res-pass.active,
        .res-fail.active,
        .res-na.active {
          animation: none;
        }
      }
      .res svg {
        width: 1.1rem;
        height: 1.1rem;
      }
      .res:hover:not(:disabled) {
        border-color: var(--foreground);
        color: var(--foreground);
      }
      .res:focus-visible {
        outline: 2px solid var(--ring, var(--primary));
        outline-offset: 2px;
      }
      .res:disabled {
        cursor: default;
        opacity: 0.6;
      }
      .res-pass.active {
        background: var(--primary);
        color: var(--primary-foreground);
        border-color: var(--primary);
      }
      .res-fail.active {
        background: var(--destructive, var(--foreground));
        color: var(--destructive-foreground, var(--background));
        border-color: var(--destructive, var(--foreground));
      }
      .res-na.active {
        background: var(--muted);
        color: var(--foreground);
      }
      .runner-empty {
        padding: var(--boxel-sp);
        text-align: center;
        color: var(--muted-foreground);
        border: 1px dashed var(--border);
        border-radius: var(--boxel-border-radius-sm);
      }
      @container (max-width: 480px) {
        .runner-item {
          grid-template-columns: 1fr;
        }
        .item-actions {
          justify-content: stretch;
        }
        .res {
          flex: 1;
          height: 48px;
        }
      }
    </style>
  </template>
}

export default ChecklistRunner;
