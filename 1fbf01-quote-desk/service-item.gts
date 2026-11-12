import { CardDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';

export class ServiceItem extends CardDef {
  static displayName = 'Service Item';

  @field name = contains(StringField);
  @field unit = contains(StringField);
  @field price = contains(NumberField);
  @field description = contains(TextAreaField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ServiceItem) {
      return (
        this.cardInfo?.name?.trim() ||
        this.name?.trim() ||
        `Untitled ${this.constructor.displayName}`
      );
    },
  });

  @field priceLabel = contains(StringField, {
    computeVia: function (this: ServiceItem) {
      if (this.price == null) return '-';
      let amount = `Rp ${new Intl.NumberFormat('id-ID').format(this.price)}`;
      return this.unit ? `${amount} / ${this.unit}` : amount;
    },
  });

  // Arah visual: label harga (rate card). Palet sama dengan Pipeline.
  static embedded = class Embedded extends Component<typeof ServiceItem> {
    <template>
      <div class='tag'>
        <span class='tag-dot' aria-hidden='true'></span>
        <span class='tag-name'>{{@model.name}}</span>
        <span class='tag-price'>{{@model.priceLabel}}</span>
      </div>
      <style scoped>
        .tag {
          display: flex;
          align-items: center;
          gap: 10px;
          padding: 12px 14px;
          color: #1d2433;
          font-family:
            Inter,
            system-ui,
            -apple-system,
            'Segoe UI',
            sans-serif;
        }
        .tag-dot {
          flex: none;
          width: 10px;
          height: 10px;
          border-radius: 50%;
          background: #b8502a;
        }
        .tag-name {
          flex: 1;
          min-width: 0;
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .tag-price {
          flex: none;
          font-size: 0.85rem;
          font-weight: 600;
          color: #6b6457;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof ServiceItem> {
    get amount() {
      let price = this.args.model.price;
      return price == null
        ? '-'
        : `Rp ${new Intl.NumberFormat('id-ID').format(price)}`;
    }

    <template>
      <article class='page'>
        <div class='ticket'>
          <div class='crumb'>
            <span class='crumb-mark'>QD</span>
            <span class='crumb-brand'>Quote Desk</span>
            <span class='crumb-sep'>/</span>
            <span class='crumb-here'>Rate card</span>
          </div>
          <p class='eyebrow'>Rate card</p>
          <h1 class='name'>{{@model.name}}</h1>
          <div class='price-box'>
            <span class='amount'>{{this.amount}}</span>
            {{#if @model.unit}}
              <span class='unit'>per {{@model.unit}}</span>
            {{/if}}
          </div>
          {{#if @model.description}}
            <p class='description'>{{@model.description}}</p>
          {{/if}}
          <p class='note'>This is the only place this price lives. Quotes read
            it from here; the AI never sets prices.</p>
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
        .ticket {
          max-width: 560px;
          margin: 0 auto;
          padding: 28px 32px;
          border: 1px solid #ddd3c1;
          border-radius: 4px;
          background: #fff;
        }
        .eyebrow {
          margin: 0 0 6px;
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
          margin: 0 0 18px;
          font-size: 1.9rem;
          font-weight: 600;
          letter-spacing: -0.01em;
          line-height: 1.2;
        }
        .price-box {
          display: flex;
          align-items: baseline;
          flex-wrap: wrap;
          gap: 10px;
          margin-bottom: 20px;
          padding: 16px 18px;
          border-radius: 4px;
          background: #f6e3d9;
        }
        .amount {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          font-size: 2rem;
          font-weight: 600;
          color: #b8502a;
        }
        .unit {
          font-weight: 600;
          color: #6b6457;
        }
        .description {
          margin: 0 0 16px;
          white-space: pre-line;
          line-height: 1.6;
          color: #333;
        }
        /* Motion: kertas & stempel */
        @media (prefers-reduced-motion: no-preference) {
          .ticket {
            animation: si-hang 900ms cubic-bezier(0.2, 0.7, 0, 1) both;
            transform-origin: top center;
          }
          .price-box {
            animation: si-glow 700ms ease 700ms both;
          }
          @keyframes si-hang {
            0% {
              opacity: 0;
              transform: translateY(-20px) rotate(-5deg);
            }
            55% {
              opacity: 1;
              transform: rotate(2deg);
            }
            80% {
              transform: rotate(-0.8deg);
            }
            100% {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes si-glow {
            0% {
              box-shadow: 0 0 0 0 rgba(184, 80, 42, 0.35);
            }
            100% {
              box-shadow: 0 0 0 14px rgba(184, 80, 42, 0);
            }
          }
        }
        .note {
          margin: 0;
          padding-top: 14px;
          border-top: 1px dashed #ddd3c1;
          font-size: 0.8rem;
          color: #6b6457;
        }
      </style>
    </template>
  };
}
