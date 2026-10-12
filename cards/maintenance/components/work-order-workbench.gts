import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import { StatePill } from '@cardstack/catalog/components/state-pill';

import { ChecklistRunner } from './checklist-runner';
import { formatMoneyDisplay } from '@cardstack/catalog/components/money-display';
import { formatHours } from '../utils/maintenance';
import { LabourEntryField } from '../labour-entry-field';
import { PartUsageField } from '../part-usage-field';
import type { WorkOrder } from '../work-order';
import type { Asset } from '../asset';
import type { SparePart } from '../spare-part';
import { WO_STATUS_HUE, HOLD_REASONS } from '../maintenance-vocabulary';

interface Signature {
  Args: {
    workOrder: WorkOrder;
    asset?: Asset;
    parts: SparePart[];
    onStart?: () => void;
    onHold?: (reason: string) => void;
    onResume?: () => void;
    onComplete?: () => void;
    /** Called after any in-place edit to checklist/labour/parts, so the host can save. */
    onChange?: () => void;
    /** A refused action's message (e.g. Complete Work Order's checklist gate) — cleared on the next attempt. */
    errorMessage?: string;
    readonly?: boolean;
  };
  Element: HTMLElement;
}

/**
 * The operator's single-work-order execution surface: identity + status
 * header, the checklist to run, labour and parts logged as the job goes,
 * downtime at a glance, and the action buttons for the job's own state
 * machine. This component owns no Command — every action is a callback the
 * app shell wires to the real Command (Raise/Start/Hold/Resume/Complete),
 * so this stays reusable for any job-execution UI, not just maintenance.
 */
export class WorkOrderWorkbench extends GlimmerComponent<Signature> {
  @tracked holdReason: string = HOLD_REASONS[0];
  @tracked newWorkerName = '';
  @tracked newHours = '';
  @tracked newPartId = '';
  @tracked newQuantity = '1';

  get wo() {
    return this.args.workOrder;
  }

  get statusHue() {
    return WO_STATUS_HUE[this.wo.status ?? ''] ?? 'slate';
  }

  get labour(): LabourEntryField[] {
    return (this.wo.labour ?? []).filter(Boolean) as LabourEntryField[];
  }
  get parts(): PartUsageField[] {
    return (this.wo.parts ?? []).filter(Boolean) as PartUsageField[];
  }

  setHoldReason = (ev: Event) => {
    this.holdReason = (ev.target as HTMLSelectElement).value;
  };
  hold = () => this.args.onHold?.(this.holdReason);
  start = () => this.args.onStart?.();
  resume = () => this.args.onResume?.();
  complete = () => this.args.onComplete?.();

  setNewWorkerName = (v: string) => (this.newWorkerName = v);
  setNewHours = (v: string) => (this.newHours = v);

  addLabour = () => {
    let hours = Number(this.newHours);
    if (!this.newWorkerName.trim() || !Number.isFinite(hours) || hours <= 0)
      return;
    let entry = new LabourEntryField({
      workerName: this.newWorkerName.trim(),
      hours,
    });
    this.wo.labour = [...this.labour, entry];
    this.newWorkerName = '';
    this.newHours = '';
    this.args.onChange?.();
  };

  setNewPartId = (ev: Event) => {
    this.newPartId = (ev.target as HTMLSelectElement).value;
  };
  setNewQuantity = (v: string) => (this.newQuantity = v);

  addPart = () => {
    let part = (this.args.parts ?? []).find((p) => p.id === this.newPartId);
    let quantity = Number(this.newQuantity);
    if (!part || !Number.isFinite(quantity) || quantity <= 0) return;
    let usage = new PartUsageField({
      partId: part.id,
      partNumber: part.partNumber,
      partName: part.name,
      quantity,
      unitCost: part.unitCost,
      fromStock: true,
    });
    this.wo.parts = [...this.parts, usage];
    this.newPartId = '';
    this.newQuantity = '1';
    this.args.onChange?.();
  };

  get downtimeSummary() {
    let d = this.wo.downtime;
    if (!d?.startedAt) return undefined;
    return `${d.planned ? 'Planned' : 'Unplanned'} downtime — ${formatHours(d.hours)}${d.isOpen ? ' (open)' : ''}`;
  }

  get canStart() {
    return this.wo.status === 'scheduled' || this.wo.status === 'approved';
  }
  get canHold() {
    return this.wo.status === 'in-progress';
  }
  get canResume() {
    return this.wo.status === 'on-hold';
  }
  get canComplete() {
    return this.wo.status === 'in-progress';
  }

  <template>
    <div class='wb' ...attributes>
      <header class='wb-head'>
        <div class='wb-id'>
          <code>{{this.wo.identifier.value}}</code>
          <span class='wb-title'>{{this.wo.title}}</span>
        </div>
        <div class='wb-pills'>
          <StatePill
            @label={{this.wo.status}}
            @hue={{this.statusHue}}
            @dot={{true}}
          />
          {{#if this.wo.priority}}<StatePill
              @label={{this.wo.priority}}
              @hue='slate'
            />{{/if}}
          {{#if this.wo.isOverdue}}<StatePill
              @label='Overdue'
              @hue='orange'
              @emphatic={{true}}
            />{{/if}}
        </div>
        {{#if @asset}}
          <p class='wb-sub'>{{@asset.tag}}
            ·
            {{@asset.name}}
            ·
            {{@asset.locationName}}</p>
        {{/if}}
      </header>

      {{#unless @readonly}}
        {{! Large buttons: a technician taps these on a phone, so they keep
            the 44px touch minimum. }}
        <div class='wb-actions'>
          {{#if this.canStart}}
            <Button
              @tone='primary'
              @appearance='accent'
              @size='l'
              {{on 'click' this.start}}
            >Start</Button>
          {{/if}}
          {{#if this.canHold}}
            <select
              class='hold-select'
              aria-label='Hold reason'
              {{on 'change' this.setHoldReason}}
            >
              {{#each HOLD_REASONS as |r|}}
                <option
                  value={{r}}
                  selected={{eq this.holdReason r}}
                >{{r}}</option>
              {{/each}}
            </select>
            <Button
              @appearance='outlined'
              @size='l'
              {{on 'click' this.hold}}
            >Hold</Button>
          {{/if}}
          {{#if this.canResume}}
            <Button
              @appearance='outlined'
              @size='l'
              {{on 'click' this.resume}}
            >Resume</Button>
          {{/if}}
          {{#if this.canComplete}}
            <Button
              @tone='primary'
              @appearance='accent'
              @size='l'
              {{on 'click' this.complete}}
            >Complete</Button>
          {{/if}}
        </div>
        {{#if @errorMessage}}
          <Alert class='wb-error' @tone='danger' role='alert'>
            {{@errorMessage}}
          </Alert>
        {{/if}}
      {{/unless}}

      {{#if this.wo.checklist}}
        <section class='wb-section'>
          <h3>Checklist</h3>
          <ChecklistRunner
            @checklist={{this.wo.checklist}}
            @onChange={{@onChange}}
            @readonly={{@readonly}}
          />
        </section>
      {{/if}}

      <section class='wb-section'>
        <h3>Labour</h3>
        <ul class='line-list'>
          {{#each this.labour as |l|}}
            <li class='line'>
              <span class='line-name'>{{l.workerName}}</span>
              <span class='line-detail'>{{formatHours l.effectiveHours}}</span>
              <span class='line-cost'>{{formatMoneyDisplay
                  l.rate.amount
                  l.rate.currency.code
                }}</span>
            </li>
          {{else}}
            <li class='line-empty'>No labour logged yet.</li>
          {{/each}}
        </ul>
        {{#unless @readonly}}
          <div class='line-add'>
            <Input
              @value={{this.newWorkerName}}
              @onInput={{this.setNewWorkerName}}
              @placeholder='Worker name'
            />
            <Input
              @value={{this.newHours}}
              @onInput={{this.setNewHours}}
              @placeholder='Hours'
            />
            <Button
              @appearance='outlined'
              @size='l'
              {{on 'click' this.addLabour}}
            >Add</Button>
          </div>
        {{/unless}}
      </section>

      <section class='wb-section'>
        <h3>Parts</h3>
        <ul class='line-list'>
          {{#each this.parts as |p|}}
            <li class='line'>
              <span class='line-name'>{{p.partNumber}} — {{p.partName}}</span>
              <span class='line-detail'>×{{p.quantity}}</span>
              <span class='line-cost'>{{formatMoneyDisplay
                  p.unitCost.amount
                  p.unitCost.currency.code
                }}</span>
            </li>
          {{else}}
            <li class='line-empty'>No parts used yet.</li>
          {{/each}}
        </ul>
        {{#unless @readonly}}
          <div class='line-add'>
            <select aria-label='Part' {{on 'change' this.setNewPartId}}>
              <option value=''>Select a part…</option>
              {{#each @parts as |p|}}
                <option value={{p.id}}>{{p.partNumber}} — {{p.name}}</option>
              {{/each}}
            </select>
            <Input
              @value={{this.newQuantity}}
              @onInput={{this.setNewQuantity}}
              @placeholder='Qty'
            />
            <Button
              @appearance='outlined'
              @size='l'
              {{on 'click' this.addPart}}
            >Add</Button>
          </div>
        {{/unless}}
      </section>

      {{#if this.downtimeSummary}}
        <section class='wb-section'>
          <h3>Downtime</h3>
          <p class='downtime-line'>{{this.downtimeSummary}}</p>
        </section>
      {{/if}}
    </div>
    <style scoped>
      .wb {
        container-type: inline-size;
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-lg);
        background: var(--card);
        box-shadow: var(--shadow-sm);
        color: var(--foreground);
      }
      .wb-head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .wb-id {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
      }
      .wb-id code {
        font-family: var(
          --boxel-monospace-font-family,
          ui-monospace,
          monospace
        );
        color: var(--muted-foreground);
      }
      .wb-title {
        font-size: var(--boxel-font-size-lg);
        font-weight: 600;
      }
      .wb-pills {
        display: flex;
        gap: var(--boxel-sp-4xs);
      }
      .wb-sub {
        margin: 0;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .wb-actions {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .wb-error {
        margin-top: var(--boxel-sp-xs);
      }
      .hold-select {
        min-height: 2.75rem;
        padding: 0 var(--boxel-sp-xs);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        background: var(--card);
        color: var(--foreground);
      }
      .wb-section {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        background: color-mix(in oklch, var(--foreground) 1.5%, var(--card));
      }
      .wb-section h3 {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      .line-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .line {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        background: var(--card);
      }
      .line-name {
        flex: 1;
        min-width: 0;
      }
      .line-detail,
      .line-cost {
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .line-empty {
        color: var(--muted-foreground);
        font-style: italic;
        font-size: var(--boxel-font-size-sm);
      }
      .line-add {
        display: flex;
        gap: var(--boxel-sp-4xs);
        align-items: center;
      }
      .line-add select {
        min-height: 2.75rem;
        padding: 0 var(--boxel-sp-xs);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        background: var(--card);
        color: var(--foreground);
      }
      .downtime-line {
        margin: 0;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}

export default WorkOrderWorkbench;
