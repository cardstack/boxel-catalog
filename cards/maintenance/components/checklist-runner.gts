import GlimmerComponent from '@glimmer/component';
import { fn, concat } from '@ember/helper';
import { on } from '@ember/modifier';
import { htmlSafe } from '@ember/template';
import { Input } from '@cardstack/pretui/components/input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Button } from '@cardstack/pretui/components/button';
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

const RESULT_OPTIONS = [
  { value: 'pass', label: 'Pass' },
  { value: 'fail', label: 'Fail' },
  { value: 'na', label: 'N/A' },
];

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
 * Generic: onboarding checklists, publish checklists and audit
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

  setResult = (item: ChecklistItemField, result: string) => {
    if (this.args.readonly) return;
    this.stamp(item, result as Result);
  };

  // A pending item selects no segment.
  resultValue = (item: ChecklistItemField): string =>
    item.result === 'pending' ? '' : (item.result ?? '');

  // A segmented control can't deselect its active segment, so a mis-tapped
  // result is cleared back to unanswered here.
  canClear = (item: ChecklistItemField): boolean =>
    !this.args.readonly && Boolean(item.result) && item.result !== 'pending';

  clearResult = (item: ChecklistItemField) => {
    if (this.args.readonly) return;
    this.stamp(item, 'pending');
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
                  <Input
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
                <Input
                  @value={{item.value}}
                  @onInput={{fn this.setText item}}
                  @disabled={{@readonly}}
                  @placeholder='Type the observation'
                  aria-label='{{item.label}}'
                />
              {{else if (this.isKind item 'signature')}}
                <div class='item-sign'>
                  <PenIcon class='item-icon' />
                  <Input
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
                  <Input
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

              <Input
                class='item-note'
                @value={{item.note}}
                @onInput={{fn this.setNote item}}
                @disabled={{@readonly}}
                @placeholder='Note (optional)'
                aria-label='{{item.label}} note'
              />
            </div>

            <div class='item-actions'>
              <SegmentedControl
                @options={{RESULT_OPTIONS}}
                @value={{this.resultValue item}}
                @onValueChange={{fn this.setResult item}}
                @label={{concat item.label ' result'}}
                @disabled={{@readonly}}
              />
              {{#if (this.canClear item)}}
                <Button
                  @appearance='plain'
                  @size='xs'
                  aria-label={{concat 'Clear the ' item.label ' result'}}
                  {{on 'click' (fn this.clearResult item)}}
                >Clear</Button>
              {{/if}}
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
        color: var(--destructive-ink);
        font-weight: 600;
      }
      .runner-bar {
        height: 0.375rem;
        border-radius: 0.1875rem;
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
          var(--destructive) 35%,
          var(--border)
        );
        background: color-mix(in oklab, var(--destructive) 5%, var(--card));
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
        color: var(--destructive-ink);
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
        justify-self: end;
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-2xs);
      }
      .runner-empty {
        padding: var(--boxel-sp);
        text-align: center;
        color: var(--muted-foreground);
        border: 1px dashed var(--border);
        border-radius: var(--boxel-border-radius-sm);
      }
      @container (max-width: 30rem) {
        .runner-item {
          grid-template-columns: 1fr;
        }
        .item-actions {
          justify-self: stretch;
        }
      }
    </style>
  </template>
}

export default ChecklistRunner;
