import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import { ServiceItem } from './service-item';
import { Client } from './client';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';

// Ambang approval owner
const APPROVAL_DISCOUNT_PERCENT = 10;
const APPROVAL_TOTAL = 10000000;

const rupiah = (n: number | null | undefined) =>
  `Rp ${new Intl.NumberFormat('id-ID').format(n ?? 0)}`;

// Kosong (null) dianggap draft / pending
const StatusField = enumField(StringField, {
  options: ['draft', 'sent', 'accepted'],
});
const ApprovalDecisionField = enumField(StringField, {
  options: ['pending', 'approved', 'rejected'],
});

const approvalTone = (quote: Quote) => {
  if (!quote.requiresApproval) return 'neutral';
  if (quote.approvalDecision === 'approved') return 'green';
  if (quote.approvalDecision === 'rejected') return 'red';
  return 'yellow';
};

// GUESS (PDF): buka versi cetak di tab baru lalu dialog print browser,
// staf memilih "Save as PDF". Tanpa library atau API eksternal.
const esc = (v: unknown) =>
  String(v ?? '').replace(
    /[&<>"']/g,
    (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[
        c
      ]!,
  );

function quotePrintHtml(q: any) {
  let rows = (q.lines ?? [])
    .filter(Boolean)
    .map(
      (
        l: any,
      ) => `<tr><td>${esc(l.item?.name ?? '-')}</td><td class="n">${esc(l.qty)}</td>
        <td class="n">${esc(l.item ? rupiah(l.item.price) : '-')}</td><td class="n">${esc(rupiah(l.lineTotal))}</td></tr>`,
    )
    .join('');
  let discount = (q.subtotal ?? 0) - (q.total ?? 0);
  let today = new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(new Date());
  let banner = q.canSend
    ? ''
    : '<p class="banner">Draft: pending owner approval</p>';
  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(q.title)}</title>
<style>
  body { font-family: Inter, system-ui, -apple-system, 'Segoe UI', sans-serif; color: #1d2433; margin: 48px; }
  .eyebrow { color: #b8502a; font-size: 12px; font-weight: 700; letter-spacing: .14em; text-transform: uppercase; margin: 0; }
  h1 { font-size: 28px; margin: 6px 0 4px; }
  .muted { color: #6b6457; margin: 0; }
  .banner { background: #fff4d6; color: #7a5b00; padding: 8px 12px; border-radius: 8px; }
  .party { margin: 28px 0; padding: 12px 16px; background: #f2ece1; border-radius: 8px; }
  table { width: 100%; border-collapse: collapse; margin-top: 8px; }
  th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: .06em; color: #6b6457; border-bottom: 2px solid #1d2433; padding: 8px; }
  td { padding: 10px 8px; border-bottom: 1px solid #ddd3c1; }
  .n { text-align: right; white-space: nowrap; }
  .totals { margin: 20px 0 0 auto; width: 300px; }
  .totals div { display: flex; justify-content: space-between; padding: 4px 0; }
  .grand { border-top: 1px solid #ddd3c1; margin-top: 6px; padding-top: 8px !important; font-size: 18px; font-weight: 800; }
  .foot { margin-top: 40px; font-size: 12px; color: #6b6457; }
</style></head><body>
  <p class="eyebrow">Quote</p>
  <h1>${esc(q.title)}</h1>
  <p class="muted">${esc(today)} · Status: ${esc(q.status || 'draft')}</p>
  ${banner}
  <div class="party"><div class="muted">Prepared for</div>
    <strong>${esc(q.client?.name ?? '')}</strong><div class="muted">${esc(q.client?.company ?? '')}</div></div>
  <table><thead><tr><th>Item</th><th class="n">Qty</th><th class="n">Price</th><th class="n">Amount</th></tr></thead>
    <tbody>${rows}</tbody></table>
  <div class="totals">
    <div><span>Subtotal</span><span>${esc(rupiah(q.subtotal))}</span></div>
    <div><span>Discount (${esc(q.discountPercent ?? 0)}%)</span><span>- ${esc(rupiah(discount))}</span></div>
    <div class="grand"><span>Total</span><span>${esc(rupiah(q.total))}</span></div>
  </div>
  <p class="foot">Prices come from our rate card. Generated with Quote Desk.</p>
  <script>window.onload = () => window.print();</script>
</body></html>`;
}

export class QuoteLine extends FieldDef {
  static displayName = 'Quote Line';

  @field item = linksTo(() => ServiceItem);
  @field qty = contains(NumberField);

  @field lineTotal = contains(NumberField, {
    computeVia: function (this: QuoteLine) {
      return (this.item?.price ?? 0) * (this.qty ?? 0);
    },
  });
}

export class Quote extends CardDef {
  static displayName = 'Quote';

  @field title = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Quote) {
      return (
        this.cardInfo?.name?.trim() ||
        this.title?.trim() ||
        `Untitled ${this.constructor.displayName}`
      );
    },
  });

  @field client = linksTo(() => Client);
  @field status = contains(StatusField);
  @field lines = containsMany(QuoteLine);
  @field discountPercent = contains(NumberField);

  @field subtotal = contains(NumberField, {
    computeVia: function (this: Quote) {
      let sum = 0;
      for (let line of this.lines ?? []) {
        sum += line?.lineTotal ?? 0;
      }
      return sum;
    },
  });

  @field total = contains(NumberField, {
    computeVia: function (this: Quote) {
      let subtotal = this.subtotal ?? 0;
      return subtotal - (subtotal * (this.discountPercent ?? 0)) / 100;
    },
  });

  @field approvalDecision = contains(ApprovalDecisionField);
  @field approvedBy = contains(StringField);
  @field approvalNote = contains(TextAreaField);

  @field requiresApproval = contains(BooleanField, {
    computeVia: function (this: Quote) {
      return (
        (this.discountPercent ?? 0) > APPROVAL_DISCOUNT_PERCENT ||
        (this.total ?? 0) > APPROVAL_TOTAL
      );
    },
  });

  @field approvalLabel = contains(StringField, {
    computeVia: function (this: Quote) {
      if (!this.requiresApproval) return 'No approval needed';
      if (this.approvalDecision === 'approved') {
        return `Approved by ${this.approvedBy ?? '-'}`;
      }
      if (this.approvalDecision === 'rejected') return 'Rejected';
      return 'Awaiting owner approval';
    },
  });

  @field canSend = contains(BooleanField, {
    computeVia: function (this: Quote) {
      return !this.requiresApproval || this.approvalDecision === 'approved';
    },
  });

  @field waPhone = contains(StringField, {
    computeVia: function (this: Quote) {
      let digits = (this.client?.phone ?? '').replace(/\D/g, '');
      return digits.startsWith('0') ? `62${digits.slice(1)}` : digits;
    },
  });

  @field waMessage = contains(StringField, {
    computeVia: function (this: Quote) {
      let lines = [
        `Hi ${this.client?.name ?? ''}, here is our quote for ${this.title ?? ''}:`,
      ];
      for (let line of this.lines ?? []) {
        if (line == null) continue;
        lines.push(
          `- ${line.item?.name ?? '-'} x${line.qty ?? 0} = ${rupiah(line.lineTotal)}`,
        );
      }
      if ((this.discountPercent ?? 0) > 0) {
        lines.push(`Discount ${this.discountPercent}%`);
      }
      lines.push(`Total: ${rupiah(this.total)}`);
      lines.push('Please confirm if everything looks right. Thank you.');
      return lines.join('\n');
    },
  });

  @field waLink = contains(StringField, {
    computeVia: function (this: Quote) {
      if (!this.waPhone) return '';
      return `https://wa.me/${this.waPhone}?text=${encodeURIComponent(this.waMessage ?? '')}`;
    },
  });

  // Arah visual: dokumen penawaran resmi. Palet sama dengan Pipeline.
  static embedded = class Embedded extends Component<typeof Quote> {
    rupiah = rupiah;

    get approvalTone() {
      return approvalTone(this.args.model as Quote);
    }

    <template>
      <div class='mini'>
        <div class='mini-top'>
          <span class='eyebrow'>Quote</span>
          <span class='status'>{{if @model.status @model.status 'draft'}}</span>
        </div>
        <strong class='title'>{{@model.title}}</strong>
        {{#if @model.client}}
          <span class='meta'>{{@model.client.name}}</span>
        {{/if}}
        <div class='mini-bottom'>
          <span
            class='badge badge--{{this.approvalTone}}'
          >{{@model.approvalLabel}}</span>
          <span class='total'>{{this.rupiah @model.total}}</span>
        </div>
      </div>
      <style scoped>
        .mini {
          display: flex;
          flex-direction: column;
          gap: 4px;
          padding: 14px 16px;
          color: #1d2433;
          font-family:
            Inter,
            system-ui,
            -apple-system,
            'Segoe UI',
            sans-serif;
        }
        .mini-top,
        .mini-bottom {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 8px;
        }
        .mini-bottom {
          margin-top: 6px;
        }
        .eyebrow {
          font-size: 0.65rem;
          font-weight: 700;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: #b8502a;
        }
        .status {
          font-size: 0.7rem;
          font-weight: 700;
          text-transform: uppercase;
          color: #6b6457;
        }
        .title {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          line-height: 1.3;
        }
        .meta {
          font-size: 0.85rem;
          color: #6b6457;
        }
        .total {
          font-weight: 800;
          white-space: nowrap;
        }
        .badge {
          padding: 2px 8px;
          border-radius: 3px;
          font-size: 0.7rem;
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .badge--neutral {
          background: #e8e1d3;
          color: #4a4f5c;
        }
        .badge--yellow {
          background: #fff4d6;
          color: #7a5b00;
        }
        .badge--green {
          background: #e0ece3;
          color: #2e6e4f;
        }
        .badge--red {
          background: #fde2e2;
          color: #a11d1d;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Quote> {
    @tracked pdfMessage = '';

    downloadPdf = () => {
      this.pdfMessage = '';
      let win = window.open('', '_blank');
      if (!win) {
        this.pdfMessage = 'Allow pop-ups for this site to download the PDF.';
        return;
      }
      win.document.write(quotePrintHtml(this.args.model));
      win.document.close();
    };

    rupiah = rupiah;

    get discountAmount() {
      return (this.args.model.subtotal ?? 0) - (this.args.model.total ?? 0);
    }

    get approvalTone() {
      return approvalTone(this.args.model as Quote);
    }

    get sentWithoutApproval() {
      return this.args.model.status === 'sent' && !this.args.model.canSend;
    }

    get statusKey() {
      return this.args.model.status || 'draft';
    }

    <template>
      <article class='page'>
        <div class='sheet'>
          <div class='crumb'>
            <span class='crumb-mark'>QD</span>
            <span class='crumb-brand'>Quote Desk</span>
            <span class='crumb-sep'>/</span>
            <span class='crumb-here'>Quote</span>
          </div>
          <header class='doc-head'>
            <div>
              <p class='eyebrow'>Quote</p>
              <h1 class='title'>{{@model.title}}</h1>
            </div>
            <div class='pills'>
              <span
                class='status status--{{this.statusKey}}'
              >{{this.statusKey}}</span>
              <span
                class='badge badge--{{this.approvalTone}}'
              >{{@model.approvalLabel}}</span>
            </div>
          </header>

          {{#if @model.client}}
            <div class='party'>
              <span class='label'>Prepared for</span>
              <strong class='party-name'>{{@model.client.name}}</strong>
              {{#if @model.client.company}}
                <span class='party-meta'>{{@model.client.company}}</span>
              {{/if}}
            </div>
          {{/if}}

          {{#if this.sentWithoutApproval}}
            <p class='warning'>This quote should not be sent yet, it needs owner
              approval</p>
          {{/if}}

          <table class='lines'>
            <thead>
              <tr>
                <th>Item</th>
                <th class='num'>Qty</th>
                <th class='num'>Price</th>
                <th class='num'>Amount</th>
              </tr>
            </thead>
            <tbody>
              {{#each @model.lines as |line|}}
                <tr>
                  <td class='item'>{{if line.item line.item.name '-'}}</td>
                  <td class='num'>{{line.qty}}</td>
                  <td class='num'>{{if
                      line.item
                      (this.rupiah line.item.price)
                      '-'
                    }}</td>
                  <td class='num strong'>{{this.rupiah line.lineTotal}}</td>
                </tr>
              {{/each}}
            </tbody>
          </table>

          <div class='foot'>
            <p class='source'>Prices come from the rate card. Totals are
              calculated automatically.</p>
            <dl class='summary'>
              <dt>Subtotal</dt>
              <dd>{{this.rupiah @model.subtotal}}</dd>
              <dt>Discount ({{if
                  @model.discountPercent
                  @model.discountPercent
                  0
                }}%)</dt>
              <dd>- {{this.rupiah this.discountAmount}}</dd>
              <dt class='grand'>Total</dt>
              <dd class='grand'>{{this.rupiah @model.total}}</dd>
            </dl>
          </div>

          <div class='send'>
            <button
              type='button'
              class='pdf-button'
              {{on 'click' this.downloadPdf}}
            >Download PDF</button>
            {{#if this.pdfMessage}}
              <p class='hint'>{{this.pdfMessage}}</p>
            {{/if}}
            {{#if @model.canSend}}
              {{#if @model.waLink}}
                <a
                  class='wa-button'
                  href={{@model.waLink}}
                  target='_blank'
                  rel='noopener noreferrer'
                >Send via WhatsApp</a>
              {{else}}
                <p class='hint'>Client phone number is missing</p>
              {{/if}}
            {{else}}
              <button type='button' class='wa-button' disabled>Send via WhatsApp</button>
              <p class='hint'>Needs owner approval before sending</p>
            {{/if}}
          </div>
        </div>
      </article>
      <style scoped>
        .page {
          min-height: 100%;
          padding: 40px 32px;
          background: #f2ece1;
          color: #1d2433;
          font-family:
            Inter,
            system-ui,
            -apple-system,
            'Segoe UI',
            sans-serif;
          background-image: radial-gradient(
            rgba(29, 36, 51, 0.08) 1px,
            transparent 1px
          );
          background-size: 16px 16px;
        }
        .crumb {
          display: flex;
          align-items: center;
          gap: 8px;
          margin: 0 0 20px;
          padding: 8px 12px;
          border-radius: 4px;
          background: #1d2433;
          color: #fff;
          font-size: 0.8rem;
          text-decoration: none;
        }
        .crumb-mark {
          display: grid;
          place-items: center;
          width: 22px;
          height: 22px;
          border-radius: 6px;
          background: #e7a33e;
          color: #1d2433;
          font-size: 0.65rem;
          font-weight: 900;
        }
        .crumb-brand {
          font-weight: 800;
        }
        .crumb-sep {
          opacity: 0.4;
        }
        .crumb-here {
          opacity: 0.8;
        }
        .sheet {
          max-width: 760px;
          margin: 0 auto;
          padding: 36px 40px;
          border: 1px solid #ddd3c1;
          border-radius: 4px;
          background: #fff;
          box-shadow: 0 1px 2px rgba(22, 33, 58, 0.06);
        }
        .doc-head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          flex-wrap: wrap;
          gap: 16px;
          margin-bottom: 24px;
        }
        .eyebrow {
          margin: 0 0 6px;
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: #b8502a;
        }
        .title {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          margin: 0;
          font-size: 1.9rem;
          font-weight: 600;
          letter-spacing: -0.01em;
          line-height: 1.2;
        }
        .pills {
          display: flex;
          align-items: center;
          gap: 8px;
        }
        .status {
          padding: 3px 10px;
          border-radius: 3px;
          background: #e8e1d3;
          font-size: 0.75rem;
          font-weight: 700;
          text-transform: uppercase;
          color: #4a4f5c;
        }
        .status--sent {
          background: #f6e3d9;
          color: #b8502a;
        }
        .status--accepted {
          background: #e0ece3;
          color: #2e6e4f;
        }
        .badge {
          padding: 3px 10px;
          border-radius: 3px;
          font-size: 0.75rem;
          font-weight: 600;
        }
        .badge--neutral {
          background: #e8e1d3;
          color: #4a4f5c;
        }
        .badge--yellow {
          background: #fff4d6;
          color: #7a5b00;
        }
        .badge--green {
          background: #e0ece3;
          color: #2e6e4f;
        }
        .badge--red {
          background: #fde2e2;
          color: #a11d1d;
        }
        .party {
          display: flex;
          flex-direction: column;
          margin-bottom: 24px;
          padding: 14px 16px;
          border-radius: 4px;
          background: #f2ece1;
        }
        .label {
          font-size: 0.75rem;
          font-weight: 600;
          color: #6b6457;
        }
        .party-name {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          font-size: 1.05rem;
        }
        .party-meta {
          color: #6b6457;
        }
        .warning {
          margin: 0 0 24px;
          padding: 12px 14px;
          border: 1px solid #a11d1d;
          border-radius: 4px;
          background: #fde2e2;
          color: #a11d1d;
        }
        .lines {
          width: 100%;
          border-collapse: collapse;
          margin-bottom: 20px;
        }
        .lines th {
          padding: 10px 8px;
          border-bottom: 2px solid #1d2433;
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          text-align: left;
          color: #6b6457;
        }
        .lines td {
          padding: 12px 8px;
          border-bottom: 1px solid #ddd3c1;
        }
        .lines th.num,
        .lines td.num {
          text-align: right;
          white-space: nowrap;
        }
        .item {
          font-weight: 600;
        }
        .strong {
          font-weight: 700;
        }
        .foot {
          display: flex;
          justify-content: space-between;
          align-items: flex-end;
          flex-wrap: wrap;
          gap: 20px;
        }
        .source {
          margin: 0;
          max-width: 300px;
          font-size: 0.8rem;
          color: #6b6457;
        }
        .summary {
          display: grid;
          grid-template-columns: 1fr max-content;
          gap: 8px 24px;
          min-width: 280px;
          margin: 0 0 0 auto;
          padding: 16px 18px;
          border-radius: 4px;
          background: #f2ece1;
        }
        .summary dt {
          color: #6b6457;
        }
        .summary dd {
          margin: 0;
          text-align: right;
        }
        .summary .grand {
          padding-top: 10px;
          border-top: 1px solid #ddd3c1;
          font-size: 1.2rem;
          font-weight: 800;
          color: #1d2433;
        }
        .send {
          margin-top: 28px;
          text-align: right;
        }
        .pdf-button {
          display: inline-block;
          margin-right: 10px;
          padding: 12px 20px;
          border: 1px solid #b8502a;
          border-radius: 4px;
          background: #fff;
          color: #b8502a;
          font: inherit;
          font-weight: 700;
          cursor: pointer;
        }
        .wa-button {
          display: inline-block;
          padding: 12px 20px;
          border: none;
          border-radius: 4px;
          background: #2e6e4f;
          color: #fff;
          font: inherit;
          font-weight: 700;
          text-decoration: none;
          cursor: pointer;
        }
        .wa-button:disabled {
          background: #d6d3cb;
          color: #6b6f7a;
          cursor: not-allowed;
        }
        /* Motion: kertas & stempel */
        @media (prefers-reduced-motion: no-preference) {
          .sheet {
            animation: qt-paper 700ms cubic-bezier(0.2, 0.7, 0, 1) both;
          }
          .lines tbody tr {
            animation: qt-fade 400ms ease both;
          }
          .lines tbody tr:nth-child(1) {
            animation-delay: 300ms;
          }
          .lines tbody tr:nth-child(2) {
            animation-delay: 360ms;
          }
          .lines tbody tr:nth-child(3) {
            animation-delay: 420ms;
          }
          .lines tbody tr:nth-child(4) {
            animation-delay: 480ms;
          }
          .lines tbody tr:nth-child(5) {
            animation-delay: 540ms;
          }
          .lines tbody tr:nth-child(6) {
            animation-delay: 600ms;
          }
          .lines tbody tr:nth-child(7) {
            animation-delay: 660ms;
          }
          .lines tbody tr:nth-child(8) {
            animation-delay: 720ms;
          }
          .badge--green,
          .status--accepted {
            animation: qt-stamp 520ms cubic-bezier(0.3, 1.4, 0.5, 1) 400ms both;
          }
          .summary {
            animation: qt-rise 550ms cubic-bezier(0.2, 0.7, 0, 1) 500ms both;
          }
          .wa-button:not(:disabled),
          .pdf-button {
            transition:
              transform 160ms ease,
              box-shadow 160ms ease;
          }
          .wa-button:not(:disabled):hover,
          .pdf-button:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 14px rgba(29, 36, 51, 0.15);
          }
          @keyframes qt-paper {
            from {
              opacity: 0;
              transform: translateY(28px) rotate(0.8deg);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes qt-rise {
            from {
              opacity: 0;
              transform: translateY(10px);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes qt-fade {
            from {
              opacity: 0;
            }
            to {
              opacity: 1;
            }
          }
          @keyframes qt-stamp {
            0% {
              opacity: 0;
              transform: scale(1.8) rotate(-10deg);
            }
            70% {
              opacity: 1;
              transform: scale(0.95) rotate(-1deg);
            }
            100% {
              opacity: 1;
              transform: none;
            }
          }
        }
        .hint {
          margin: 8px 0 0;
          font-size: 0.8rem;
          color: #6b6457;
        }
      </style>
    </template>
  };
}
