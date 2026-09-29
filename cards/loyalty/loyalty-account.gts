import { htmlSafe } from '@ember/template';
import GlimmerComponent from '@glimmer/component';
import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';
import DateTimeField from 'https://cardstack.com/base/datetime';
import AwardIcon from '@cardstack/boxel-icons/award';
import ArrowsExchangeIcon from '@cardstack/boxel-icons/arrows-exchange';

import { Contact } from '@cardstack/catalog/cards/crm/contact';
import LoyaltyTierField from './loyalty-tier-field';
import MemberNumberField from './member-number-field';
import PointsBalanceField from './points-balance-field';
import { MembershipStatusField } from './membership-status-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Delta } from '@cardstack/pretui/components/delta';
import { Stat } from '@cardstack/pretui/components/stat';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Token } from '@cardstack/pretui/components/token';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import {
  formatDate,
  formatNumber,
  toDate,
} from '@cardstack/pretui/internal/reading-format';

/** `+1,200`, `-500`, `0`: the sign on earns, through the kit's own number formatter. */
function signedPoints(n: number): string {
  return formatNumber(n, undefined, { signDisplay: 'exceptZero' });
}

// Delta colours a rise with the `--success` fill and has no knob for it, so
// on the Delta element itself `--success` is re-pointed at its ink token, the
// colour a status word takes on a neutral surface. A fall reads Delta's own
// `--pretui-destructive-ink` knob.
const POINTS_INK = htmlSafe(
  '--success: var(--success-ink); --pretui-destructive-ink: var(--destructive-ink);',
);

/** A date fact as the Date field's own long preset prints it; empty when unset, so `Stat` shows its dash. */
function longDate(value?: Date | null): string {
  let date = toDate(value ?? undefined);
  return date ? formatDate(date, undefined, { dateStyle: 'long' }) : '';
}

const TRANSACTION_FACTS = [
  { key: 'Occurred', value: 'occurredAt' },
  { key: 'Expires', value: 'expiresAt' },
];

interface PointsDeltaSignature {
  Args: { amount?: number | null };
  Element: HTMLSpanElement;
}

/**
 * A signed points movement: Pret UI `Delta`, earns green and deductions red —
 * the one place every ledger view formats and colours an amount. Size comes
 * from Delta's `--text-ui-sm` knob at each call site.
 */
class PointsDelta extends GlimmerComponent<PointsDeltaSignature> {
  get value(): number {
    return this.args.amount ?? 0;
  }

  <template>
    <Delta
      @value={{this.value}}
      @format={{signedPoints}}
      style={{POINTS_INK}}
      ...attributes
    />
  </template>
}

/**
 * A membership in a loyalty program — the account that accumulates standing,
 * not the person. The person is a linked Contact; one person can hold
 * accounts in many programs, and the program's history belongs to the
 * account so it survives the person's details changing.
 *
 * `pointsBalance` and `lifetimePoints` are maintained by the program's
 * single writer — the Credit Points command — against the PointsTransaction
 * ledger. Nothing else assigns them; a consumer that wants history renders
 * the ledger, not a link array on this card.
 *
 * The neutral default tier ladder ships with the tier field; a program with
 * its own ladder redeclares `tier` with `loyaltyTierField(...)` in its
 * extending card.
 */
export class LoyaltyAccount extends CardDef {
  static displayName = 'Loyalty Account';
  static icon = AwardIcon;

  @field memberNumber = contains(MemberNumberField);
  @field holder = linksTo(Contact);
  @field tier = contains(LoyaltyTierField);
  @field tierSince = contains(DateField);
  @field memberSince = contains(DateField);
  @field status = contains(MembershipStatusField);
  @field pointsBalance = contains(PointsBalanceField);
  @field lifetimePoints = contains(PointsBalanceField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: LoyaltyAccount) {
      return (
        this.holder?.name ??
        this.memberNumber ??
        `Untitled ${this.constructor.displayName}`
      );
    },
  });

  static atom = class Atom extends Component<typeof LoyaltyAccount> {
    <template>
      <span class='la-atom'>
        <AwardIcon class='la-icon' />
        <span class='la-number'>{{if
            @model.memberNumber
            @model.memberNumber
            'No member number'
          }}</span>
      </span>
      <style scoped>
        .la-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          font-size: 0.8125rem;
        }
        .la-icon {
          width: 0.875rem;
          height: 0.875rem;
          flex-shrink: 0;
          color: var(--muted-foreground);
        }
        .la-number {
          font-family: var(--font-mono);
          letter-spacing: 0.04em;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof LoyaltyAccount> {
    <template>
      <div class='la-row'>
        <div class='la-id'>
          <span class='la-name'>{{if
              @model.holder.name
              @model.holder.name
              'Unassigned account'
            }}</span>
          <span class='la-number'><@fields.memberNumber /></span>
        </div>
        <span class='la-tier'><@fields.tier /></span>
        <span class='la-balance'><@fields.pointsBalance /></span>
      </div>
      <style scoped>
        .la-row {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.875rem;
        }
        .la-id {
          min-width: 0;
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }
        .la-name {
          font-weight: 600;
          font-size: 0.875rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .la-number {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .la-tier {
          flex-shrink: 0;
        }
        /* Constant-width slot so account rows column-align in lists whether
           or not a balance exists yet. */
        .la-balance {
          width: 5.5rem;
          text-align: right;
          flex-shrink: 0;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof LoyaltyAccount> {
    <template>
      <div class='fitted'>
        <div class='top'>
          {{#if @model.memberNumber}}
            <Token class='number' @value={{@model.memberNumber}} />
          {{else}}
            <span class='number no-number'>No member number</span>
          {{/if}}
          <span class='tier line-tier'><@fields.tier @format='atom' /></span>
        </div>
        <span class='balance line-balance'><@fields.pointsBalance /></span>
        {{#if @model.memberSince}}
          <span class='meta line-since'>Member since
            <@fields.memberSince /></span>
        {{/if}}
      </div>
      <style scoped>
        .fitted {
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.25rem;
          width: 100%;
          height: 100%;
          padding: 0.625rem 0.75rem;
          box-sizing: border-box;
          overflow: hidden;
          color: var(--foreground);
        }
        .top {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          min-width: 0;
        }
        /* Pret UI Token for the id; it never wraps, so it truncates here. */
        .number {
          --pretui-token-hue: var(--muted-foreground);
          min-width: 0;
          max-width: 100%;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .no-number {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .tier {
          flex-shrink: 0;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .line-tier,
        .line-balance,
        .line-since {
          display: none;
        }
        /* Badge degradation: strip height keeps only the first line. */
        @container fitted-card (max-height: 50px) {
          .fitted {
            padding: 0.25rem 0.5rem;
            gap: 0.125rem;
          }
        }
        @container fitted-card (min-height: 65px) {
          .line-tier {
            display: inline-flex;
          }
        }
        @container fitted-card (min-height: 170px) {
          .line-balance {
            display: inline-flex;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .line-since {
            display: block;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof LoyaltyAccount> {
    private ledgerQuery: ReturnType<getCards> | undefined;

    constructor(owner: unknown, args: any) {
      super(owner as never, args as never);
      // The ledger is a query, never a link array — see the class doc.
      this.ledgerQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(PointsTransaction);
          let id = this.args.model?.id;
          return ref && id
            ? {
                filter: { on: ref, eq: { 'account.id': id } },
                sort: [{ on: ref, by: 'occurredAt', direction: 'desc' }],
                page: { size: 10 },
              }
            : undefined;
        },
        () => {
          let url = this.args.model?.[realmURL]?.href;
          return url ? [url] : [];
        },
        { isLive: true },
      );
    }

    get ledger(): PointsTransaction[] {
      return (this.ledgerQuery?.instances ?? []) as PointsTransaction[];
    }

    get ledgerLoading(): boolean {
      return Boolean(this.ledgerQuery?.isLoading);
    }

    /** A context without a query provider yields no resource; hide the panel rather than claim an empty ledger. */
    get hasLedgerQuery(): boolean {
      return Boolean(this.ledgerQuery);
    }

    // Stat takes a bare value; an empty string renders its dash.
    get pointsBalance(): number | string {
      return this.args.model?.pointsBalance ?? '';
    }

    get lifetimePoints(): number | string {
      return this.args.model?.lifetimePoints ?? '';
    }

    get memberSince(): string {
      return longDate(this.args.model?.memberSince);
    }

    get tierSince(): string {
      return longDate(this.args.model?.tierSince);
    }

    <template>
      <article class='la-page'>
        <header class='lh'>
          <div class='lh-id'>
            <p class='doc-kind'>Loyalty Account</p>
            <h1>{{if
                @model.holder.name
                @model.holder.name
                'Unassigned account'
              }}</h1>
            <p class='lh-number'><@fields.memberNumber /></p>
          </div>
          <div class='lh-standing'>
            <@fields.tier />
            {{#if @model.status}}
              <@fields.status @format='embedded' />
            {{/if}}
          </div>
        </header>
        <section class='stats'>
          <Stat
            class='stat'
            @label='Points balance'
            @value={{this.pointsBalance}}
          />
          <Stat
            class='stat'
            @label='Lifetime earned'
            @value={{this.lifetimePoints}}
          />
          <Stat
            class='stat stat-date'
            @label='Member since'
            @value={{this.memberSince}}
            @roll={{false}}
          />
          <Stat
            class='stat stat-date'
            @label='Tier since'
            @value={{this.tierSince}}
            @roll={{false}}
          />
        </section>
        {{#if this.hasLedgerQuery}}
          <section class='panel'>
            <h2>Ledger</h2>
            {{#if this.ledgerLoading}}
              <LoadingState
                class='ledger-loading'
                @label='Loading points activity'
              />
            {{else if this.ledger.length}}
              <ol class='ledger'>
                {{#each this.ledger key='id' as |transaction|}}
                  <li class='ledger-row'>
                    <PointsDelta
                      class='ledger-amount'
                      @amount={{transaction.amount}}
                    />
                    <span class='ledger-reason'>{{if
                        transaction.reason
                        transaction.reason
                        'Points adjustment'
                      }}</span>
                    <StatePill
                      class='ledger-source'
                      @label={{transaction.source}}
                    />
                    <span class='ledger-when'><FormatDate
                        @date={{transaction.occurredAt}}
                        @month='short'
                        @day='numeric'
                        @year='numeric'
                        @placeholder=''
                      /></span>
                  </li>
                {{/each}}
              </ol>
            {{else}}
              <EmptyState
                class='ledger-empty'
                @title='No points activity yet'
                @message='It starts with the first earn.'
                @texture={{false}}
              />
            {{/if}}
          </section>
        {{/if}}
        {{#if @model.holder}}
          <section class='panel'>
            <h2>Holder</h2>
            <div class='holder'><@fields.holder @format='embedded' /></div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .la-page {
          max-width: 40rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }
        .lh {
          display: flex;
          align-items: center;
          gap: 1rem;
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: 1.25rem;
        }
        .lh-id {
          flex: 1;
          min-width: 0;
        }
        .doc-kind {
          margin: 0 0 0.125rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          font-size: 1.625rem;
          line-height: 1.1;
        }
        .lh-number {
          margin: 0.25rem 0 0;
        }
        .lh-standing {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 0.375rem;
          flex-shrink: 0;
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
          gap: 0.75rem;
        }
        /* Pret UI Stat in a bordered tile; its headline size knob sets the
           tile's 18px figure and 15px date. */
        .stat {
          --text-stat: 1.125rem;
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          padding: 0.875rem 1rem;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .stat-date {
          --text-stat: 0.9375rem;
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          padding: 1rem 1.25rem;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        h2 {
          margin: 0 0 0.75rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .holder {
          border: 1px solid var(--border);
          border-radius: 0.5rem;
        }
        .ledger {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
        }
        .ledger-row {
          display: flex;
          align-items: baseline;
          gap: 0.625rem;
          padding: 0.375rem 0;
          border-bottom: 1px solid var(--border);
          font-size: 0.8125rem;
        }
        .ledger-row:last-child {
          border-bottom: none;
        }
        /* Constant-width signed column so the ledger reads as a column of
           numbers, not a ragged list. */
        .ledger-amount {
          --text-ui-sm: 0.8125rem;
          width: 4.25rem;
          text-align: right;
          flex-shrink: 0;
        }
        .ledger-reason {
          min-width: 0;
          flex: 1;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .ledger-source {
          flex-shrink: 0;
        }
        .ledger-when {
          font-size: 0.75rem;
          color: var(--muted-foreground);
          white-space: nowrap;
          flex-shrink: 0;
        }
        /* Pret UI LoadingState: its dim shimmer stop (--ink-3) falls back to
           a 2.2:1 grey, so it is pointed at the muted foreground. */
        .ledger-loading {
          --ink-3: var(--muted-foreground);
          --text-ui-md: 0.875rem;
        }
        /* Pret UI EmptyState, tuned through its spacing and title knobs to a
           compact well inside the panel. */
        .ledger-empty {
          --space-9: 1rem;
          --space-6: 1rem;
          --text-heading: var(--boxel-font-size);
        }
      </style>
    </template>
  };
}

/**
 * One movement of points, at a time, for a reason — the ledger row. The
 * ledger is the truth the balance is maintained against: an account's
 * history is a query for its transactions, never a link array on the
 * account (it grows without bound).
 *
 * `amount` is signed: earn positive, redeem/expire negative. `source` is a
 * label in the program's vocabulary (Attendance, Purchase, Survey, Manual…)
 * — free text here, constrained by the commands that write it.
 */
export class PointsTransaction extends CardDef {
  static displayName = 'Points Transaction';
  static icon = ArrowsExchangeIcon;

  @field account = linksTo(() => LoyaltyAccount);
  @field amount = contains(NumberField);
  @field reason = contains(StringField);
  @field source = contains(StringField);
  @field occurredAt = contains(DateTimeField);
  @field expiresAt = contains(DateTimeField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: PointsTransaction) {
      let amount = this.amount ?? 0;
      let signed = `${amount > 0 ? '+' : ''}${amount}`;
      return this.reason ? `${signed} — ${this.reason}` : `${signed} points`;
    },
  });

  static atom = class Atom extends Component<typeof PointsTransaction> {
    <template>
      <span class='ptx-atom'><PointsDelta @amount={{@model.amount}} />
        pts</span>
      <style scoped>
        .ptx-atom {
          --text-ui-sm: 0.75rem;
          font-variant-numeric: tabular-nums;
          font-size: 0.75rem;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof PointsTransaction> {
    <template>
      <div class='ptx'>
        <PointsDelta class='ptx-amount' @amount={{@model.amount}} />
        <div class='ptx-what'>
          <span class='ptx-reason'>{{if
              @model.reason
              @model.reason
              'Points adjustment'
            }}</span>
          <StatePill class='ptx-source' @label={{@model.source}} />
        </div>
        <span class='ptx-when'>{{#if @model.occurredAt}}<@fields.occurredAt
            />{{else}}—{{/if}}</span>
      </div>
      <style scoped>
        .ptx {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.5rem 0.875rem;
          font-size: 0.8125rem;
        }
        /* Constant-width signed column so ledger rows align. */
        .ptx-amount {
          --text-ui-sm: 0.8125rem;
          width: 4.25rem;
          text-align: right;
          flex-shrink: 0;
        }
        .ptx-what {
          min-width: 0;
          flex: 1;
          display: flex;
          align-items: baseline;
          gap: 0.5rem;
        }
        .ptx-reason {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .ptx-source {
          flex-shrink: 0;
        }
        .ptx-when {
          font-size: 0.75rem;
          color: var(--muted-foreground);
          white-space: nowrap;
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof PointsTransaction> {
    <template>
      <div class='ptx-fitted'>
        <div class='ptx-head'>
          <PointsDelta class='ptx-amount' @amount={{@model.amount}} />
          <span class='ptx-unit'>pts</span>
        </div>
        <span class='ptx-reason'>{{if
            @model.reason
            @model.reason
            'Points adjustment'
          }}</span>
        <div class='ptx-meta'>
          <StatePill @label={{@model.source}} />
          {{#if @model.occurredAt}}
            <span class='ptx-when'><@fields.occurredAt /></span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .ptx-fitted {
          height: 100%;
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.25rem;
          padding: 0.5rem 0.75rem;
          overflow: hidden;
        }
        .ptx-head {
          display: flex;
          align-items: baseline;
          gap: 0.25rem;
        }
        .ptx-amount {
          --text-ui-sm: 1.25rem;
          line-height: 1;
        }
        .ptx-unit {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .ptx-reason {
          font-size: 0.8125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .ptx-meta {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .ptx-when {
          white-space: nowrap;
        }
        @container fitted-card (max-height: 50px) {
          .ptx-fitted {
            flex-direction: row;
            align-items: center;
            gap: 0.5rem;
          }
          .ptx-amount {
            --text-ui-sm: 0.9375rem;
          }
          .ptx-meta {
            display: none;
          }
        }
        @container fitted-card (max-width: 150px) {
          .ptx-meta {
            display: none;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof PointsTransaction> {
    <template>
      <article class='ptx-page'>
        <header class='ptx-hero'>
          <PointsDelta class='ptx-amount' @amount={{@model.amount}} />
          <span class='ptx-unit'>points</span>
          <h1 class='ptx-title'>{{if
              @model.reason
              @model.reason
              'Points adjustment'
            }}</h1>
          <StatePill class='ptx-source' @label={{@model.source}} />
        </header>
        <section class='panel'>
          <h2>When</h2>
          <KeyValue class='facts' @items={{TRANSACTION_FACTS}}>
            <:value as |row|>
              {{#if (eq row.value 'occurredAt')}}
                {{#if @model.occurredAt}}<@fields.occurredAt />{{else}}—{{/if}}
              {{else if @model.expiresAt}}
                <@fields.expiresAt />
              {{else}}
                Never
              {{/if}}
            </:value>
          </KeyValue>
        </section>
        {{#if @model.account}}
          <section class='panel'>
            <h2>Account</h2>
            <div class='linked'><@fields.account @format='embedded' /></div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .ptx-page {
          display: grid;
          gap: 1rem;
          padding: 1.5rem;
          max-width: 40rem;
        }
        .ptx-hero {
          display: grid;
          grid-template-columns: auto auto;
          align-items: baseline;
          column-gap: 0.375rem;
          row-gap: 0.5rem;
        }
        .ptx-amount {
          --text-ui-sm: 2.5rem;
          line-height: 1;
        }
        .ptx-unit {
          font-size: 0.875rem;
          color: var(--muted-foreground);
        }
        .ptx-title {
          grid-column: 1 / -1;
          font-size: 1.125rem;
          font-weight: 600;
        }
        .ptx-source {
          grid-column: 1 / -1;
          justify-self: start;
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          padding: 1rem;
        }
        .panel h2 {
          margin: 0 0 0.5rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        /* Pret UI KeyValue at the panel's label and value sizes */
        .facts {
          --text-ui: 0.75rem;
          --text-ui-md: 0.875rem;
          --space-6: 1rem;
        }
        .linked {
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          overflow: hidden;
        }
      </style>
    </template>
  };
}
