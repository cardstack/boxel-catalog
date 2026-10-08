import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';

import { guidFor } from '@ember/object/internals';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import { Table } from '@cardstack/pretui/components/table';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import { FieldContainer } from '@cardstack/boxel-ui/components';

export function rateAgeDays(
  asOf?: Date | null,
  now: Date = new Date(),
): number {
  if (!asOf) {
    return Number.POSITIVE_INFINITY;
  }
  return Math.floor((now.getTime() - asOf.getTime()) / 86_400_000);
}

// One dated exchange-rate row: how many units of BASE one unit of `currency`
// buys, where it came from, and when. Staleness is judged by the registry's
// own staleAfterDays — a rate is never "old" in the abstract, only older
// than this book allows.
export class RateEntryField extends FieldDef {
  static displayName = 'Rate Entry';

  @field currency = contains(StringField, {
    description: 'ISO code, e.g. EUR',
  });
  @field rate = contains(NumberField, {
    description: '1 unit of this currency = rate units of the base currency',
  });
  @field asOf = contains(DateField);
  @field source = contains(StringField, {
    description: 'e.g. ECB daily fix, treasury desk',
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='rate-row'>
        <span class='rate-cur'>{{@model.currency}}</span>
        <span class='rate-val'>{{@model.rate}}</span>
        <span class='rate-meta'>{{@model.source}}</span>
      </div>
      <style scoped>
        .rate-row {
          display: grid;
          grid-template-columns: 4rem auto 1fr;
          gap: var(--boxel-sp-sm);
          align-items: baseline;
          font-size: 0.875rem;
          padding: var(--boxel-sp-4xs) 0;
        }
        .rate-cur {
          font-weight: 700;
          font-family: var(--font-mono);
        }
        .rate-val {
          font-variant-numeric: tabular-nums;
        }
        .rate-meta {
          color: var(--muted-foreground);
          font-size: 0.8125rem;
          text-align: right;
        }
      </style>
    </template>
  };
}

// The desk's book of exchange rates: one base (booking) currency, dated
// rates per foreign currency, and a staleness policy. ResolveCurrencyCommand
// is the only reader that matters — it refuses to convert on a rate older
// than staleAfterDays rather than guessing, which is the entire point of
// keeping rates as dated data instead of calling a live API.
export class CurrencyRegistry extends CardDef {
  static displayName = 'Currency Registry';
  static headerColor = '#3e4e88';

  @field baseCurrency = contains(StringField, {
    description: 'ISO code the books are kept in, e.g. USD',
  });
  @field rates = containsMany(RateEntryField);
  @field staleAfterDays = contains(NumberField, {
    description: 'Rates older than this refuse to resolve',
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: CurrencyRegistry) {
      let base = this.baseCurrency?.trim()?.toUpperCase();
      return base ? `Currency Registry (${base} base)` : 'Currency Registry';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    captionId = `${guidFor(this)}-rates`;

    get rows() {
      let staleAfter = this.args.model?.staleAfterDays ?? 30;
      return (this.args.model?.rates ?? []).filter(Boolean).map((r) => {
        let age = rateAgeDays(r.asOf);
        return {
          rate: r,
          ageLabel: Number.isFinite(age) ? `${age} d` : '—',
          stale: age > staleAfter,
          asOfLabel: r.asOf ? formatDay(r.asOf) : 'undated',
        };
      });
    }
    get base() {
      return this.args.model?.baseCurrency?.toUpperCase() ?? 'USD';
    }
    <template>
      <article class='registry'>
        <header class='head'>
          <p class='kicker'>Currency Registry</p>
          <h1>{{this.base}}
            base ·
            {{@model.staleAfterDays}}-day staleness policy</h1>
        </header>
        <section class='panel'>
          <h2 id={{this.captionId}}>Rates · 1 unit → {{this.base}}</h2>
          {{#if this.rows.length}}
            <Table @labelledBy={{this.captionId}}>
              <:head>
                <tr>
                  <th scope='col'>Currency</th>
                  <th scope='col' class='num'>Rate</th>
                  <th scope='col'>As of</th>
                  <th scope='col' class='num'>Age</th>
                  <th scope='col'>Source</th>
                  <th scope='col'>Resolve Currency</th>
                </tr>
              </:head>
              <:body>
                {{#each this.rows as |row|}}
                  <tr class={{if row.stale 'stale'}}>
                    <th scope='row' class='cur'>{{row.rate.currency}}</th>
                    <td class='num'><FormatNumber
                        @value={{row.rate.rate}}
                        @maximumFractionDigits={{6}}
                      /></td>
                    <td>{{row.asOfLabel}}</td>
                    <td class='num'>{{row.ageLabel}}</td>
                    <td class='source'>{{row.rate.source}}</td>
                    <td>
                      <StatePill
                        @label={{if row.stale 'stale, will refuse' 'usable'}}
                        @hue={{if row.stale 'red' 'green'}}
                        @dot={{true}}
                      />
                    </td>
                  </tr>
                {{/each}}
              </:body>
            </Table>
          {{else}}
            <EmptyState
              @title='No rates recorded'
              @message='Resolve Currency refuses every conversion until the book has rows.'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            />
          {{/if}}
        </section>
      </article>
      <style scoped>
        .registry {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          background: var(--background);
          color: var(--foreground);
          display: grid;
          gap: var(--boxel-sp);
        }
        .head {
          border-bottom: 1px solid var(--border);
          padding-bottom: var(--boxel-sp);
        }
        .kicker,
        h2 {
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-5xs) 0 0;
          font-size: 1.375rem;
        }
        .panel {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .num {
          text-align: end;
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
        .cur {
          font-family: var(--font-mono);
          font-weight: 700;
        }
        .source {
          color: var(--muted-foreground);
        }
        .stale .cur {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get count() {
      return (this.args.model?.rates ?? []).length;
    }
    <template>
      <div class='row'>
        <span class='name'>{{@model.cardTitle}}</span>
        <span class='meta'>{{this.count}}
          rates ·
          {{@model.staleAfterDays}}d policy</span>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
        }
        .meta {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: 0.8125rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get count() {
      return (this.args.model?.rates ?? []).length;
    }
    <template>
      <div class='fit'>
        <span class='fit-name'>{{@model.cardTitle}}</span>
        <span class='fit-sub'>{{this.count}}
          rates ·
          {{@model.staleAfterDays}}d staleness</span>
      </div>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-name {
          font-weight: 700;
          font-size: 0.9375rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .fit-sub {
          font-size: 0.75rem;
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
        @container fitted-card (height <= 65px) {
          .fit {
            flex-direction: row;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
        }
      </style>
    </template>
  };

  // The book's policy first (base currency + how old a rate may be), then
  // the rate rows themselves. Two sections, no rail. Computed cardTitle is
  // excluded.
  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Registry identity' },
      { id: 'rates', label: 'Rates' },
    ];

    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Currency Registry sections'
        as |e|
      >
        <e.Section @id='identity' @title='Registry identity'>
          <div class='row'>
            <FieldContainer @label='Base currency (ISO)' @vertical={{true}}>
              <@fields.baseCurrency />
            </FieldContainer>
            <FieldContainer @label='Stale after (days)' @vertical={{true}}>
              <@fields.staleAfterDays />
            </FieldContainer>
          </div>
        </e.Section>
        <e.Section
          @id='rates'
          @title='Rates'
          @hint='rates older than the staleness policy make Resolve Currency refuse to convert'
        >
          <FieldContainer
            @label='Dated rates (1 unit → base)'
            @vertical={{true}}
          >
            <@fields.rates />
          </FieldContainer>
        </e.Section>
      </SectionedEdit>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: var(--boxel-sp-sm);
          align-items: start;
        }
        @container (width < 40rem) {
          .row,
          .row[class*='cols-'] {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };
}
