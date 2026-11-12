import { CardDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import DateField from '@cardstack/base/date';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { QUERIES, cardsOf, instancesOf } from './pipeline-link';

// Prospect = belum butuh sekarang, tetap disimpan untuk ditawari nanti
const StageField = enumField(StringField, {
  options: [
    { value: 'prospect', label: 'Prospect' },
    { value: 'active', label: 'Active client' },
    { value: 'past', label: 'Past client' },
  ],
});

export const STAGE_LABELS: Record<string, string> = {
  prospect: 'Prospect',
  active: 'Active client',
  past: 'Past client',
};

// DateField: nilai JSON wajib YYYY-MM-DD
export function formatFollowUp(value: unknown) {
  if (!value) return '';
  let date = value instanceof Date ? value : new Date(String(value));
  return isNaN(date.getTime())
    ? ''
    : new Intl.DateTimeFormat('en-GB', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
      }).format(date);
}

const rupiah = (n: number | null | undefined) =>
  `Rp ${new Intl.NumberFormat('id-ID').format(n ?? 0)}`;

const initialsOf = (name: string | null | undefined) =>
  (name ?? '')
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]!.toUpperCase())
    .join('') || '?';

export class Client extends CardDef {
  static displayName = 'Client';

  @field name = contains(StringField);
  @field company = contains(StringField);
  @field phone = contains(StringField);
  @field email = contains(StringField);
  @field notes = contains(TextAreaField);
  @field stage = contains(StageField);
  @field nextFollowUp = contains(DateField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Client) {
      return (
        this.cardInfo?.name?.trim() ||
        this.name?.trim() ||
        `Untitled ${this.constructor.displayName}`
      );
    },
  });

  // Arah visual: kartu kontak dengan inisial. Palet sama dengan Pipeline.
  static embedded = class Embedded extends Component<typeof Client> {
    get initials() {
      return initialsOf(this.args.model.name);
    }

    get stageLabel() {
      return STAGE_LABELS[this.args.model.stage ?? ''] ?? '';
    }

    get followUp() {
      return formatFollowUp(this.args.model.nextFollowUp);
    }

    <template>
      <div class='contact'>
        <span class='avatar' aria-hidden='true'>{{this.initials}}</span>
        <span class='text'>
          <strong class='name'>{{@model.name}}</strong>
          {{#if @model.company}}
            <span class='meta'>{{@model.company}}</span>
          {{/if}}
          <span class='meta'>{{@model.phone}}</span>
          {{#if this.followUp}}
            <span class='meta follow'>Follow up {{this.followUp}}</span>
          {{/if}}
        </span>
        {{#if this.stageLabel}}
          <span class='stage stage--{{@model.stage}}'>{{this.stageLabel}}</span>
        {{/if}}
      </div>
      <style scoped>
        .stage {
          flex: none;
          margin-left: auto;
          padding: 2px 8px;
          border-radius: 3px;
          background: #e8e1d3;
          font-size: 0.7rem;
          font-weight: 600;
          color: #4a4f5c;
        }
        .stage--prospect {
          background: #fff4d6;
          color: #7a5b00;
        }
        .stage--active {
          background: #e0ece3;
          color: #2e6e4f;
        }
        .contact {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 12px 14px;
          color: #1d2433;
          font-family:
            Inter,
            system-ui,
            -apple-system,
            'Segoe UI',
            sans-serif;
        }
        .avatar {
          flex: none;
          display: grid;
          place-items: center;
          width: 40px;
          height: 40px;
          border-radius: 50%;
          background: #1d2433;
          color: #fff;
          font-size: 0.85rem;
          font-weight: 700;
        }
        .text {
          display: flex;
          flex-direction: column;
          min-width: 0;
        }
        .name {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.85rem;
          color: #6b6457;
        }
        .follow {
          font-weight: 600;
          color: #7a5b00;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Client> {
    get initials() {
      return initialsOf(this.args.model.name);
    }

    get stageLabel() {
      return STAGE_LABELS[this.args.model.stage ?? ''] ?? '';
    }

    get followUp() {
      return formatFollowUp(this.args.model.nextFollowUp);
    }

    // Riwayat quote: semua Quote di realm yang client-nya card ini
    quotesResource = cardsOf(this, QUERIES.quote);

    get quoteHistory() {
      let id = this.args.model.id;
      return instancesOf(this.quotesResource)
        .filter((q) => id && q.client?.id === id)
        .map((q) => ({
          id: q.id,
          card: q,
          title: q.title || 'Untitled quote',
          status: q.status || 'draft',
          total: rupiah(q.total),
        }))
        .sort((a, b) => a.title.localeCompare(b.title));
    }

    open = (card: any) => {
      (this.args as any).viewCard?.(card, 'isolated');
    };

    <template>
      <article class='page'>
        <div class='card'>
          <div class='crumb'>
            <span class='crumb-mark'>QD</span>
            <span class='crumb-brand'>Quote Desk</span>
            <span class='crumb-sep'>/</span>
            <span class='crumb-here'>Client</span>
          </div>
          <div class='head'>
            <span class='avatar' aria-hidden='true'>{{this.initials}}</span>
            <div>
              <p class='eyebrow'>Client
                {{#if this.stageLabel}}
                  <span
                    class='stage stage--{{@model.stage}}'
                  >{{this.stageLabel}}</span>
                {{/if}}
              </p>
              <h1 class='name'>{{@model.name}}</h1>
              {{#if @model.company}}
                <p class='company'>{{@model.company}}</p>
              {{/if}}
            </div>
          </div>
          <dl class='details'>
            <div class='detail'>
              <dt>Phone</dt>
              <dd>{{@model.phone}}</dd>
            </div>
            {{#if @model.email}}
              <div class='detail'>
                <dt>Email</dt>
                <dd>{{@model.email}}</dd>
              </div>
            {{/if}}
          </dl>
          {{#if this.followUp}}
            <p class='follow-box'>Next follow-up: <b>{{this.followUp}}</b></p>
          {{/if}}
          {{#if @model.notes}}
            <p class='notes'>{{@model.notes}}</p>
          {{/if}}

          <section class='history'>
            <h2 class='history-title'>Quotes</h2>
            {{#each this.quoteHistory key='id' as |q|}}
              <button
                type='button'
                class='history-row'
                {{on 'click' (fn this.open q.card)}}
              >
                <span class='history-name'>{{q.title}}</span>
                <span
                  class='history-status history-status--{{q.status}}'
                >{{q.status}}</span>
                <span class='history-total'>{{q.total}}</span>
              </button>
            {{else}}
              <p class='history-empty'>No quotes yet. Keep this client for a
                future offer.</p>
            {{/each}}
          </section>
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
        .card {
          position: relative;
          max-width: 560px;
          margin: 0 auto;
          padding: 28px 32px;
          border: 1px solid #ddd3c1;
          border-radius: 4px;
          background: #fff;
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
        .stage {
          display: inline-block;
          margin-left: 8px;
          vertical-align: middle;
          letter-spacing: 0;
          text-transform: none;
          padding: 3px 10px;
          border-radius: 3px;
          background: #e8e1d3;
          font-size: 0.75rem;
          font-weight: 600;
          color: #4a4f5c;
        }
        .stage--prospect {
          background: #fff4d6;
          color: #7a5b00;
        }
        .stage--active {
          background: #e0ece3;
          color: #2e6e4f;
        }
        .head {
          display: flex;
          align-items: center;
          gap: 18px;
          margin-bottom: 22px;
        }
        .avatar {
          flex: none;
          display: grid;
          place-items: center;
          width: 64px;
          height: 64px;
          border-radius: 50%;
          background: #1d2433;
          color: #fff;
          font-size: 1.3rem;
          font-weight: 800;
        }
        .eyebrow {
          margin: 0 0 2px;
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: #b8502a;
        }
        .name {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          margin: 0;
          font-size: 1.7rem;
          font-weight: 600;
          letter-spacing: -0.01em;
          line-height: 1.2;
        }
        .company {
          margin: 2px 0 0;
          color: #6b6457;
        }
        .details {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
          gap: 12px;
          margin: 0 0 18px;
        }
        .detail {
          padding: 12px 14px;
          border-radius: 4px;
          background: #f2ece1;
        }
        .detail dt {
          font-size: 0.75rem;
          font-weight: 600;
          color: #6b6457;
        }
        .detail dd {
          margin: 2px 0 0;
          font-weight: 600;
          word-break: break-word;
        }
        .follow-box {
          margin: 0 0 16px;
          padding: 10px 14px;
          border-radius: 4px;
          background: #fff4d6;
          color: #7a5b00;
        }
        .history {
          margin-top: 20px;
          padding-top: 16px;
          border-top: 1px solid #ddd3c1;
        }
        .history-title {
          margin: 0 0 8px;
          font-size: 0.8rem;
          font-weight: 700;
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: #6b6457;
        }
        .history-row {
          display: grid;
          grid-template-columns: minmax(0, 1fr) auto auto;
          align-items: center;
          gap: 12px;
          width: 100%;
          padding: 10px 12px;
          border: 1px solid #ddd3c1;
          border-radius: 4px;
          margin-bottom: 8px;
          background: #fff;
          color: inherit;
          font: inherit;
          text-align: left;
          cursor: pointer;
        }
        .history-row:hover {
          border-color: #b8502a;
        }
        .history-name {
          font-weight: 600;
        }
        .history-status {
          padding: 2px 8px;
          border-radius: 3px;
          background: #e8e1d3;
          font-size: 0.7rem;
          font-weight: 700;
          text-transform: uppercase;
          color: #4a4f5c;
        }
        .history-status--sent {
          background: #f6e3d9;
          color: #b8502a;
        }
        .history-status--accepted {
          background: #e0ece3;
          color: #2e6e4f;
        }
        .history-total {
          font-weight: 700;
          white-space: nowrap;
        }
        .history-empty {
          margin: 0;
          font-size: 0.85rem;
          color: #6b6457;
        }
        /* Motion: kertas & stempel */
        @media (prefers-reduced-motion: no-preference) {
          .card {
            animation: cl-rise 600ms cubic-bezier(0.2, 0.7, 0, 1) both;
          }
          .avatar {
            animation: cl-pop 600ms cubic-bezier(0.3, 1.5, 0.5, 1) 150ms both;
          }
          .follow-box {
            animation: cl-wiggle 700ms ease 700ms both;
          }
          .history-row {
            transition: transform 160ms ease;
          }
          .history-row:hover {
            transform: translateX(4px);
          }
          @keyframes cl-rise {
            from {
              opacity: 0;
              transform: translateY(14px);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes cl-pop {
            from {
              opacity: 0;
              transform: scale(0.4);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes cl-wiggle {
            0%,
            100% {
              transform: none;
            }
            25% {
              transform: rotate(-1deg);
            }
            75% {
              transform: rotate(1deg);
            }
          }
        }
        .notes {
          margin: 0;
          padding-top: 14px;
          border-top: 1px dashed #ddd3c1;
          white-space: pre-line;
          line-height: 1.6;
          color: #333;
        }
      </style>
    </template>
  };
}
