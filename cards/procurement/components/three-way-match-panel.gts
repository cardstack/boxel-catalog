import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Table } from '@cardstack/pretui/components/table';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { MoneyDisplay } from '@cardstack/catalog/components/money-display';
import {
  matchLines,
  openVarianceCount,
  PRICE_TOLERANCE_PCT,
  PRICE_TOLERANCE_ABS,
  type LineMatch,
} from '../three-way-match';
import ResolveVarianceCommand from '../commands/resolve-variance-command';
import ApproveInvoiceForPaymentCommand from '../../commerce/commands/approve-invoice-for-payment-command';

// The Three-Way Match Panel ⭐ — the AP control surface: what we ORDERED
// (PO lines) vs what ARRIVED (the PO's receivedQuantities) vs what the
// vendor INVOICED, per line, within tolerance. Clean lines pass silently;
// variances become work items whose resolutions are explicit, reasoned,
// and stored on the invoice. No path to payment exists around an open
// variance — the guard lives in the command, this panel just makes it
// visible. Unlike the display-only siblings, this is a WORKBENCH: it takes
// @context and runs the two commands itself, so the Invoice card mounts it
// as one section.

interface Signature {
  Args: {
    invoice: any;
    context?: any;
  };
  Element: HTMLElement;
}

export class ThreeWayMatchPanel extends GlimmerComponent<Signature> {
  @tracked busy = false;
  @tracked flash: string | undefined;
  @tracked flashKind: 'ok' | 'warn' = 'ok';
  @tracked resolvingLine: number | undefined;
  @tracked resolveAction = 'accept';
  @tracked resolveReason = '';

  get po() {
    try {
      return this.args.invoice?.purchaseOrder;
    } catch {
      return undefined;
    }
  }

  get rows(): LineMatch[] {
    let po = this.po;
    if (!po) {
      return [];
    }
    return matchLines(
      po.lineItems ?? [],
      po.receivedQuantities ?? [],
      this.args.invoice?.lineItems ?? [],
      this.args.invoice?.varianceResolutions ?? [],
    );
  }

  get openCount() {
    return openVarianceCount(this.rows);
  }

  get toleranceLabel() {
    return `tolerance ±${PRICE_TOLERANCE_PCT}% or $${PRICE_TOLERANCE_ABS}`;
  }

  get resolutions() {
    return (this.args.invoice?.varianceResolutions ?? []).filter(Boolean);
  }

  get approved() {
    return ['approved-for-payment', 'partial', 'paid'].includes(
      this.args.invoice?.status ?? '',
    );
  }

  hueFor = (state: string): 'green' | 'red' | 'amber' | 'slate' => {
    switch (state) {
      case 'clean':
        return 'green';
      case 'resolved':
        return 'amber';
      case 'qty-variance':
      case 'price-variance':
      case 'qty-and-price-variance':
      case 'not-on-po':
        return 'red';
      default:
        return 'slate';
    }
  };

  isOpen = (row: LineMatch): boolean =>
    row.state !== 'clean' && row.state !== 'resolved';

  labelFor = (row: LineMatch): string =>
    row.state === 'clean' && row.detail === 'not invoiced'
      ? 'not invoiced'
      : row.state === 'clean'
        ? 'clean'
        : row.state === 'resolved'
          ? 'resolved'
          : row.detail;

  startResolve = (line: number) => {
    this.resolvingLine = line;
    this.resolveAction = 'accept';
    this.resolveReason = '';
    this.flash = undefined;
  };

  cancelResolve = () => {
    this.resolvingLine = undefined;
  };

  setReason = (v: string) => {
    this.resolveReason = v;
  };

  setAction = (v: string) => {
    this.resolveAction = v;
  };

  submitResolve = async () => {
    let ctx = this.args.context?.commandContext;
    if (!ctx || this.resolvingLine == null) {
      return;
    }
    this.busy = true;
    this.flash = undefined;
    try {
      let result = await new ResolveVarianceCommand(ctx).execute({
        invoice: this.args.invoice,
        lineNumber: this.resolvingLine,
        action: this.resolveAction,
        reason: this.resolveReason,
      } as any);
      this.flashKind = 'ok';
      this.flash = (result as any)?.message;
      this.resolvingLine = undefined;
    } catch (e: any) {
      this.flashKind = 'warn';
      this.flash = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  approveForPayment = async () => {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      return;
    }
    this.busy = true;
    this.flash = undefined;
    try {
      let result = await new ApproveInvoiceForPaymentCommand(ctx).execute({
        invoice: this.args.invoice,
      } as any);
      this.flashKind = 'ok';
      this.flash = (result as any)?.message;
    } catch (e: any) {
      this.flashKind = 'warn';
      this.flash = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  <template>
    <div class='match-panel' ...attributes>
      <div class='strip'>
        <StatePill
          @label={{if
            this.openCount
            'EXCEPTION — payment blocked'
            (if this.approved 'APPROVED FOR PAYMENT' 'MATCH CLEAN')
          }}
          @hue={{if this.openCount 'red' 'green'}}
          @emphatic={{true}}
        />
        <span class='strip-note'>{{this.openCount}}
          open ·
          {{this.toleranceLabel}}</span>
        {{#unless this.approved}}
          <Button
            @variant='primary'
            @size='s'
            @busy={{if this.openCount false this.busy}}
            @disabled={{if this.openCount true this.busy}}
            class='approve-btn'
            {{on 'click' this.approveForPayment}}
          >
            {{if this.openCount 'Blocked' 'Approve for payment'}}
          </Button>
        {{/unless}}
      </div>

      {{#if this.flash}}
        {{#if (eq this.flashKind 'ok')}}
          <Alert
            @tone='success'
            role='status'
            style={{ALERT_STYLE.success}}
          >{{this.flash}}</Alert>
        {{else}}
          <Alert
            @tone='warning'
            style={{ALERT_STYLE.attention}}
          >{{this.flash}}</Alert>
        {{/if}}
      {{/if}}

      <Table class='match-table' @label='Three-way match by line'>
        <:head>
          <tr>
            <th scope='col'>Line</th>
            <th scope='col'>PO line</th>
            <th scope='col' class='num'>Received</th>
            <th scope='col' class='num'>Invoiced</th>
            <th scope='col' class='num'>Variance</th>
            <th scope='col'>Match</th>
          </tr>
        </:head>
        <:body>
          {{#each this.rows as |row|}}
            <tr class={{if (this.isOpen row) 'open-row'}}>
              <td class='desc'>{{row.lineNumber}} · {{row.description}}</td>
              <td>{{if row.poQty row.poQty '—'}}
                {{#if row.poUnitPrice}}×
                  <MoneyDisplay
                    @amount={{row.poUnitPrice}}
                    @currency='USD'
                  />{{/if}}</td>
              <td class='num'>{{if
                  row.receivedQty
                  row.receivedQty
                  (if row.poQty '0' '—')
                }}</td>
              <td class='num'>{{if row.invQty row.invQty '—'}}
                {{#if row.invUnitPrice}}×
                  <MoneyDisplay
                    @amount={{row.invUnitPrice}}
                    @currency='USD'
                  />{{/if}}</td>
              <td class='num'>
                {{#if row.varianceAmount}}
                  <MoneyDisplay
                    @amount={{row.varianceAmount}}
                    @currency='USD'
                  />
                {{else}}
                  —
                {{/if}}
              </td>
              <td>
                <div class='match-cell'>
                  <StatePill
                    @label={{this.labelFor row}}
                    @hue={{this.hueFor row.state}}
                    @dot={{true}}
                  />
                  {{#if (this.isOpen row)}}
                    <Button
                      @variant='link'
                      @size='xs'
                      aria-label='Resolve line {{row.lineNumber}}'
                      {{on 'click' (fn this.startResolve row.lineNumber)}}
                    >Resolve</Button>
                  {{/if}}
                </div>
              </td>
            </tr>
          {{/each}}
        </:body>
      </Table>

      {{#if this.resolvingLine}}
        <div class='resolve-form'>
          <span class='rf-title'>Resolve line {{this.resolvingLine}}</span>
          <div class='rf-actions'>
            <SegmentedControl
              @options={{this.actionOptions}}
              @value={{this.resolveAction}}
              @onValueChange={{this.setAction}}
              @label='Resolution'
            />
          </div>
          <Input
            @value={{this.resolveReason}}
            @onInput={{this.setReason}}
            @placeholder='Reason (required — this is the audit line)'
            aria-label='Reason'
          />
          <div class='rf-buttons'>
            <Button
              @variant='primary'
              @size='s'
              @busy={{this.busy}}
              @disabled={{this.busy}}
              {{on 'click' this.submitResolve}}
            >Record resolution</Button>
            <Button
              @variant='secondary'
              @size='s'
              {{on 'click' this.cancelResolve}}
            >Cancel</Button>
          </div>
        </div>
      {{/if}}

      {{#if this.resolutions.length}}
        <div class='res-history'>
          <span class='rh-title'>Resolution history</span>
          {{#each this.resolutions as |r|}}
            <div class='rh-row'>line
              {{r.lineNumber}}
              —
              {{r.action}}:
              {{r.reason}}</div>
          {{/each}}
        </div>
      {{/if}}
    </div>
    <style scoped>
      .match-panel {
        --panel-ink: var(--procurement-ink, var(--primary));
        display: grid;
        gap: var(--boxel-sp-sm);
        font-size: var(--boxel-font-size-sm);
      }
      .strip {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        flex-wrap: wrap;
      }
      .strip-note {
        color: var(--muted-foreground);
        font-size: 0.8125rem;
        font-variant-numeric: tabular-nums;
      }
      .approve-btn {
        margin-left: auto;
      }
      th.num,
      td.num {
        text-align: right;
        font-variant-numeric: tabular-nums;
      }
      td {
        vertical-align: middle;
      }
      .desc {
        font-weight: 600;
      }
      .open-row td {
        background-color: color-mix(
          in oklab,
          var(--destructive) 6%,
          var(--card)
        );
      }
      .match-cell {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .resolve-form {
        border: 1px solid var(--border);
        border-left: 0.1875rem solid var(--panel-ink);
        border-radius: var(--radius);
        padding: var(--boxel-sp-sm);
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .rf-actions {
        display: flex;
      }
      .rf-title {
        font-weight: 700;
        font-size: 0.8125rem;
      }
      .rf-buttons {
        display: flex;
        gap: var(--boxel-sp-xs);
      }
      .res-history {
        border-top: 1px dashed var(--border);
        padding-top: var(--boxel-sp-xs);
        display: grid;
        gap: 0.125rem;
      }
      .rh-title {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .rh-row {
        font-size: 0.8125rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>

  actionOptions = [
    { value: 'accept', label: 'Accept with reason' },
    { value: 'short-pay', label: 'Short-pay' },
    { value: 'reject-line', label: 'Reject line' },
  ];
}
