import type { TemplateOnlyComponent } from '@ember/component/template-only';
import {
  CardDef,
  Component,
  contains,
  field,
  getComponent,
  linksTo,
  realmURL,
} from '@cardstack/base/card-api';
import {
  getField,
  identifyCard,
  type getCards,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import DateTimeField from '@cardstack/base/datetime';
import AwardIcon from '@cardstack/boxel-icons/award';
import ArrowsExchangeIcon from '@cardstack/boxel-icons/arrows-exchange';
import { Avatar } from '@cardstack/pretui/components/avatar';

import { Contact } from '../crm/contact';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import LoyaltyTierField, { type TierOption } from './loyalty-tier-field';
import MemberNumberField from './member-number-field';
import PointsBalanceField from './points-balance-field';
import { MembershipStatusField } from './membership-status-field';
import { IsoFrame } from '../shared/compact-sheet';

const NUM = new Intl.NumberFormat();
const SIGNED = new Intl.NumberFormat(undefined, { signDisplay: 'exceptZero' });
const DAY = new Intl.DateTimeFormat(undefined, {
  day: 'numeric',
  month: 'short',
  year: 'numeric',
});
const DAY_MONTH = new Intl.DateTimeFormat(undefined, {
  day: 'numeric',
  month: 'short',
});
const WHEN = new Intl.DateTimeFormat(undefined, {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

function asDate(value?: Date | string | null): Date | undefined {
  let d = value ? new Date(value) : undefined;
  return d && !Number.isNaN(d.getTime()) ? d : undefined;
}

function num(n?: number | null): string {
  return n == null ? '—' : NUM.format(n);
}
function signed(n?: number | null): string {
  return SIGNED.format(n ?? 0);
}
function day(d?: Date | string | null): string {
  let v = asDate(d);
  return v ? DAY.format(v) : '—';
}
function dayMonth(d?: Date | string | null): string {
  let v = asDate(d);
  return v ? DAY_MONTH.format(v) : '';
}
function when(d?: Date | string | null): string {
  let v = asDate(d);
  return v ? WHEN.format(v) : '—';
}
function year(d?: Date | string | null): string {
  return asDate(d)?.getFullYear().toString() ?? '';
}
function sign(n?: number | null): string {
  return (n ?? 0) < 0 ? 'neg' : 'pos';
}

/** The dot colour for a membership standing. */
function statusTone(status?: string | null): string {
  return status === 'Active' ? 'success' : status ? 'warning' : 'muted';
}

/** "NBF-2019-00002214 · member since 2019" */
function accountMeta(m?: LoyaltyAccount): string {
  let since = year(m?.memberSince);
  return [m?.memberNumber, since && `member since ${since}`]
    .filter(Boolean)
    .join(' · ');
}

function holderName(m?: LoyaltyAccount): string {
  return m?.holder?.name || m?.memberNumber || 'Unassigned account';
}

function reasonOf(t?: { reason?: string | null }): string {
  return t?.reason || 'Points adjustment';
}

/** "Survey · Sun 19 Apr 2026, 10:05" */
function txMeta(t?: {
  source?: string | null;
  occurredAt?: Date | null;
}): string {
  return [t?.source, t?.occurredAt ? when(t.occurredAt) : '']
    .filter(Boolean)
    .join(' · ');
}

/** The ladder the account's own `tier` field declares (a club redeclares it). */
function tierOptions(m?: LoyaltyAccount): TierOption[] {
  if (!m) return [];
  let cls = getField(m, 'tier')?.card as unknown as
    | { tierOptions?: TierOption[] }
    | undefined;
  return cls?.tierOptions ?? [];
}

function tierLine(m?: LoyaltyAccount): string {
  let opt = tierOptions(m).find((o) => o.value === m?.tier);
  if (!m?.tier) return '—';
  return opt?.multiplier ? `${m.tier} · ${opt.multiplier}× points` : m.tier;
}

/** A status as dot + text: the one state treatment every format uses. */
const DotText: TemplateOnlyComponent<{
  Args: { label?: string | null; tone?: string };
}> = <template>
  {{#if @label}}
    <span class='dot-text'><span
        class='dot'
        data-tone={{@tone}}
      ></span>{{@label}}</span>
  {{/if}}
  <style scoped>
    .dot-text {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-4xs);
      font-weight: 600;
      white-space: nowrap;
    }
    .dot {
      flex-shrink: 0;
      width: 0.4375rem;
      height: 0.4375rem;
      border-radius: 50%;
      background-color: var(--muted-foreground);
    }
    .dot[data-tone='primary'] {
      background-color: var(--primary);
    }
    .dot[data-tone='success'] {
      background-color: var(--success);
    }
    .dot[data-tone='warning'] {
      background-color: var(--warning);
    }
    .dot[data-tone='destructive'] {
      background-color: var(--destructive);
    }
  </style>
</template>;

/** The ledger mark: a muted square holding the transaction icon. */
const TxMark: TemplateOnlyComponent<{ Args: { size?: 'sm' | 'lg' } }> =
  <template>
    <span class='tx-mark' data-size={{@size}} aria-hidden='true'>
      <ArrowsExchangeIcon width='0.75rem' height='0.75rem' />
    </span>
    <style scoped>
      .tx-mark {
        display: inline-grid;
        place-items: center;
        flex-shrink: 0;
        width: 1.125rem;
        height: 1.125rem;
        border-radius: 0.25rem;
        background-color: var(--muted);
        color: var(--muted-foreground);
      }
      .tx-mark[data-size='lg'] {
        width: 1.75rem;
        height: 1.75rem;
        border-radius: 0.375rem;
      }
    </style>
  </template>;

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

  /**
   * A program whose holders book things (a club's match bookings) names the
   * booking card here; the isolated view then lists the holder's bookings.
   * The card must link its holder as `holder`.
   */
  static bookingRef: ResolvedCodeRef | undefined;

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
    get name() {
      return holderName(this.args.model as LoyaltyAccount);
    }
    <template>
      <span class='atom'>
        <Avatar @name={{this.name}} @size={{16}} />
        <span class='name'>{{this.name}}</span>
        {{#if @model.tier}}<span class='tier'>{{@model.tier}}</span>{{/if}}
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-3xs);
          max-width: 100%;
          min-width: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--card-foreground);
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-weight: 600;
        }
        .tier {
          flex-shrink: 0;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof LoyaltyAccount> {
    get model() {
      return this.args.model as LoyaltyAccount;
    }
    get name() {
      return holderName(this.model);
    }
    get meta() {
      return accountMeta(this.model);
    }
    get tierLine() {
      return tierLine(this.model);
    }
    <template>
      <article class='emb'>
        <header class='head'>
          <Avatar @name={{this.name}} @size={{24}} />
          <div class='id'>
            <p class='name'>{{this.name}}</p>
            {{#if this.meta}}<p class='meta'>{{this.meta}}</p>{{/if}}
          </div>
          <div class='tags'>
            <DotText @label={{@model.tier}} @tone='primary' />
            <DotText
              @label={{@model.status}}
              @tone={{statusTone @model.status}}
            />
          </div>
        </header>
        <dl class='kv'>
          <dt>Points balance</dt><dd class='num'>{{num
              @model.pointsBalance
            }}</dd>
          <dt>Lifetime points</dt><dd class='num'>{{num
              @model.lifetimePoints
            }}</dd>
          <dt>Tier</dt><dd>{{this.tierLine}}</dd>
          <dt>Tier since</dt><dd>{{day @model.tierSince}}</dd>
          <dt>Member since</dt><dd>{{day @model.memberSince}}</dd>
          <dt>Status</dt><dd>{{if @model.status @model.status '—'}}</dd>
          {{#if @model.holder}}
            <dt>Holder</dt><dd><@fields.holder
                @format='atom'
                @displayContainer={{false}}
              /></dd>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        .emb {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-3xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        .name,
        .meta {
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .name {
          font-weight: 700;
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .tags {
          display: flex;
          flex-shrink: 0;
          gap: var(--boxel-sp-xs);
        }
        .kv {
          display: grid;
          grid-template-columns: 7rem minmax(0, 1fr);
          margin: 0;
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-3xs) 0;
          border-top: 1px solid var(--border);
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .kv dt {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          align-self: center;
        }
        .num {
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof LoyaltyAccount> {
    get model() {
      return this.args.model as LoyaltyAccount;
    }
    get name() {
      return holderName(this.model);
    }
    get meta() {
      return accountMeta(this.model);
    }
    get fact() {
      let m = this.model;
      return `${num(m?.pointsBalance)} pts · ${num(m?.lifetimePoints)} lifetime`;
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar @name={{this.name}} /></:avatar>
        <:title>{{this.name}}</:title>
        <:subtitle>{{this.meta}}</:subtitle>
        <:status>
          <DotText @label={{@model.tier}} @tone='primary' />
          <DotText
            @label={{@model.status}}
            @tone={{statusTone @model.status}}
          />
        </:status>
        <:fact>{{this.fact}}</:fact>
        <:metric><Metric
            @value={{num @model.pointsBalance}}
            @label='Balance'
          /></:metric>
        <:details>
          {{#if @model.tier}}<Detail
              @label='Tier'
              @value={{tierLine this.model}}
            />{{/if}}
          {{#if @model.tierSince}}<Detail
              @label='Tier since'
              @value={{day @model.tierSince}}
            />{{/if}}
          {{#if @model.memberSince}}<Detail
              @label='Member since'
              @value={{day @model.memberSince}}
            />{{/if}}
        </:details>
        <:relations>{{#if @model.holder}}<@fields.holder
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </RichFittedCard>
    </template>
  };

  static isolated = class Isolated extends Component<typeof LoyaltyAccount> {
    private ledgerQuery: ReturnType<getCards> | undefined;
    // Unpaged, so the Expiring total covers every transaction, not the ten shown.
    private expiringQuery: ReturnType<getCards> | undefined;
    private bookingQuery: ReturnType<getCards> | undefined;

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
        () => this.realms,
        { isLive: true },
      );
      this.expiringQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(PointsTransaction);
          let id = this.args.model?.id;
          return ref && id
            ? { filter: { on: ref, eq: { 'account.id': id } } }
            : undefined;
        },
        () => this.realms,
        { isLive: true },
      );
      this.bookingQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = (this.args.model?.constructor as typeof LoyaltyAccount)
            ?.bookingRef;
          let holder = this.args.model?.holder?.id;
          return ref && holder
            ? { filter: { on: ref, eq: { 'holder.id': holder } } }
            : undefined;
        },
        () => this.realms,
        { isLive: true },
      );
    }

    get realms(): string[] {
      let url = this.args.model?.[realmURL]?.href;
      return url ? [url] : [];
    }

    get model() {
      return this.args.model as LoyaltyAccount;
    }
    get name() {
      return holderName(this.model);
    }
    get meta() {
      return accountMeta(this.model);
    }
    get tierLine() {
      return tierLine(this.model);
    }

    get ledger(): PointsTransaction[] {
      return (this.ledgerQuery?.instances ?? []) as PointsTransaction[];
    }

    get bookings(): CardDef[] {
      return (this.bookingQuery?.instances ?? []) as CardDef[];
    }

    get hasBookings(): boolean {
      return Boolean(
        (this.model?.constructor as typeof LoyaltyAccount)?.bookingRef,
      );
    }

    get ladder() {
      return tierOptions(this.model).map((o) => ({
        ...o,
        current: o.value === this.model?.tier,
      }));
    }

    /** Earned points that still carry an expiry ahead: "25 pts · 31 Oct". */
    get expiring(): string {
      let now = Date.now();
      let open = (
        (this.expiringQuery?.instances ?? []) as PointsTransaction[]
      ).filter(
        (t) =>
          (t.amount ?? 0) > 0 && (asDate(t.expiresAt)?.getTime() ?? 0) > now,
      );
      if (!open.length) return '—';
      let total = open.reduce((a, t) => a + (t.amount ?? 0), 0);
      let soonest = open
        .map((t) => asDate(t.expiresAt)!)
        .sort((a, b) => +a - +b)[0];
      return `${num(total)} pts · ${dayMonth(soonest)}`;
    }

    <template>
      <IsoFrame>
        <article class='page'>
          <header class='head'>
            <Avatar @name={{this.name}} @size={{28}} />
            <div class='id'>
              <h1 class='name'>{{this.name}}</h1>
              {{#if this.meta}}<p class='meta'>{{this.meta}}</p>{{/if}}
            </div>
            <div class='tags'>
              <DotText @label={{@model.tier}} @tone='primary' />
              <DotText
                @label={{@model.status}}
                @tone={{statusTone @model.status}}
              />
            </div>
          </header>

          <dl class='stats' aria-label='Key numbers'>
            <div class='stat'>
              <dt class='label'>Balance</dt>
              <dd class='value'>{{num @model.pointsBalance}}</dd>
              <dd class='sub'>redeemable points</dd>
            </div>
            <div class='stat'>
              <dt class='label'>Lifetime</dt>
              <dd class='value'>{{num @model.lifetimePoints}}</dd>
              <dd class='sub'>points earned</dd>
            </div>
            <div class='stat'>
              <dt class='label'>Tier</dt>
              <dd class='value'>{{if @model.tier @model.tier '—'}}</dd>
              <dd class='sub'>since {{day @model.tierSince}}</dd>
            </div>
            {{#if this.hasBookings}}
              <div class='stat'>
                <dt class='label'>Bookings</dt>
                <dd class='value'>{{this.bookings.length}}</dd>
                <dd class='sub'>for this holder</dd>
              </div>
            {{/if}}
          </dl>

          <div class='cols'>
            <div class='main'>
              <section class='sec'>
                <h2>Recent activity</h2>
                {{#if this.ledger.length}}
                  <ul class='rows'>
                    {{#each this.ledger key='id' as |t|}}
                      <li class='row'>
                        <span class='date'>{{day t.occurredAt}}</span>
                        <span class='what'><strong>{{reasonOf t}}</strong>
                          <span class='muted'>{{#if t.source}}·
                              {{t.source}}{{/if}}{{#if t.expiresAt}}
                              · expires
                              {{dayMonth t.expiresAt}}{{/if}}</span></span>
                        <span class='amt {{sign t.amount}}'>{{signed
                            t.amount
                          }}</span>
                      </li>
                    {{/each}}
                  </ul>
                {{else}}
                  <p class='empty'>No points activity yet</p>
                {{/if}}
              </section>
              {{#if this.ladder.length}}
                <section class='sec'>
                  <h2>Tier ladder</h2>
                  <dl class='kv'>
                    {{#each this.ladder as |o|}}
                      <dt>{{o.value}}{{if o.current ' (current)'}}</dt>
                      <dd>{{if o.meaning o.meaning '—'}}{{#if o.multiplier}}
                          ·
                          {{o.multiplier}}×{{/if}}</dd>
                    {{/each}}
                  </dl>
                </section>
              {{/if}}
            </div>

            <aside class='side'>
              <section class='sec'>
                <h2>Linked</h2>
                <dl class='kv'>
                  <dt>Holder</dt>
                  <dd>{{#if @model.holder}}<@fields.holder
                        @format='atom'
                        @displayContainer={{false}}
                      />{{else}}—{{/if}}</dd>
                  {{#each this.bookings as |b|}}
                    <dt>Booking</dt>
                    <dd>{{#let (getComponent b) as |B|}}<B
                          @format='atom'
                          @displayContainer={{false}}
                        />{{/let}}</dd>
                  {{/each}}
                </dl>
              </section>
              <section class='sec'>
                <h2>Details</h2>
                <dl class='kv'>
                  <dt>Points balance</dt><dd class='num'>{{num
                      @model.pointsBalance
                    }}</dd>
                  <dt>Lifetime points</dt><dd class='num'>{{num
                      @model.lifetimePoints
                    }}</dd>
                  <dt>Tier</dt><dd>{{this.tierLine}}</dd>
                  <dt>Tier since</dt><dd>{{day @model.tierSince}}</dd>
                  <dt>Member since</dt><dd>{{day @model.memberSince}}</dd>
                  <dt>Status</dt><dd>{{if @model.status @model.status '—'}}</dd>
                  <dt>Expiring</dt><dd>{{this.expiring}}</dd>
                  <dt>Member no.</dt><dd class='mono'>{{if
                      @model.memberNumber
                      @model.memberNumber
                      '—'
                    }}</dd>
                </dl>
              </section>
            </aside>
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .page {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background-color: var(--card);
          color: var(--card-foreground);
          font-size: var(--boxel-font-size-xs);
          overflow: hidden;
        }
        .head {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-sm);
          border-bottom: 1px solid var(--border);
        }
        .id {
          flex: 1 1 10rem;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .tags {
          display: flex;
          gap: var(--boxel-sp-sm);
          margin-left: auto;
        }
        .stats {
          margin: 0;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
          border-bottom: 1px solid var(--border);
          overflow: hidden;
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          margin: 0 -1px -1px 0;
          border-right: 1px solid var(--border);
          border-bottom: 1px solid var(--border);
          min-width: 0;
        }
        .stat dt,
        .stat dd {
          margin: 0;
        }
        .label,
        .kv dt {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .value {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          line-height: 1.2;
          font-variant-numeric: tabular-nums;
        }
        .sub,
        .muted,
        .empty {
          color: var(--muted-foreground);
        }
        .sub {
          font-size: var(--boxel-font-size-2xs);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        }
        .main {
          border-right: 1px solid var(--border);
        }
        @container (max-width: 44rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .main {
            border-right: 0;
            border-bottom: 1px solid var(--border);
          }
        }
        .sec + .sec {
          border-top: 1px solid var(--border);
        }
        h2 {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .rows {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-3xs) var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
        }
        .date {
          flex-shrink: 0;
          width: 6rem;
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .what {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .amt {
          flex-shrink: 0;
          font-family: var(--font-mono);
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .pos {
          color: var(--success-ink);
        }
        .neg {
          color: var(--destructive-ink);
        }
        .empty {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
        }
        .kv {
          display: grid;
          grid-template-columns: 8rem minmax(0, 1fr);
          margin: 0;
          padding: 0 var(--boxel-sp-sm) var(--boxel-sp-3xs);
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-3xs) 0;
          border-top: 1px solid var(--border);
          min-width: 0;
          display: flex;
          align-items: center;
          flex-wrap: wrap;
        }
        .num {
          font-variant-numeric: tabular-nums;
        }
        .mono {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
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
      <span class='atom'>
        <TxMark />
        <span class='name'>{{reasonOf @model}}</span>
        <span class='amt {{sign @model.amount}}'>{{signed @model.amount}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-3xs);
          max-width: 100%;
          min-width: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--card-foreground);
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-weight: 600;
        }
        .amt {
          flex-shrink: 0;
          font-family: var(--font-mono);
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .pos {
          color: var(--success-ink);
        }
        .neg {
          color: var(--destructive-ink);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof PointsTransaction> {
    <template>
      <article class='emb'>
        <header class='head'>
          <TxMark @size='lg' />
          <div class='id'>
            <p class='name'>{{reasonOf @model}}</p>
            <p class='meta'>{{txMeta @model}}</p>
          </div>
          <div class='amount'>
            <span class='amt {{sign @model.amount}}'>{{signed @model.amount}}
              pts</span>
            {{#if @model.expiresAt}}<span class='meta'>expires
                {{dayMonth @model.expiresAt}}</span>{{/if}}
          </div>
        </header>
        <dl class='kv'>
          <dt>Amount</dt><dd class='num'>{{signed @model.amount}}</dd>
          <dt>Source</dt><dd>{{if @model.source @model.source '—'}}</dd>
          <dt>Occurred</dt><dd>{{day @model.occurredAt}}</dd>
          <dt>Expires</dt><dd>{{if
              @model.expiresAt
              (day @model.expiresAt)
              'Never'
            }}</dd>
          {{#if @model.account}}
            <dt>Account</dt><dd><@fields.account
                @format='atom'
                @displayContainer={{false}}
              /></dd>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        .emb {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-3xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        .name,
        .meta {
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .name {
          font-weight: 700;
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .amount {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          flex-shrink: 0;
        }
        .amt {
          font-family: var(--font-mono);
          font-weight: 700;
          white-space: nowrap;
        }
        .pos {
          color: var(--success-ink);
        }
        .neg {
          color: var(--destructive-ink);
        }
        .kv {
          display: grid;
          grid-template-columns: 7rem minmax(0, 1fr);
          margin: 0;
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-3xs) 0;
          border-top: 1px solid var(--border);
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .kv dt {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          align-self: center;
        }
        .num {
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof PointsTransaction> {
    get fact() {
      let m = this.args.model as PointsTransaction;
      let who = m?.account?.holder?.name;
      return `${signed(m?.amount)} points${who ? ` to ${who}` : ''}`;
    }
    <template>
      <RichFittedCard>
        <:avatar><TxMark @size='lg' /></:avatar>
        <:title>{{reasonOf @model}}</:title>
        <:subtitle>{{txMeta @model}}</:subtitle>
        <:status><span class='amt {{sign @model.amount}}'>{{signed
              @model.amount
            }}
            pts</span></:status>
        <:fact>{{this.fact}}</:fact>
        <:relations>{{#if @model.account}}<@fields.account
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </RichFittedCard>
      <style scoped>
        .amt {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          font-weight: 700;
          white-space: nowrap;
        }
        .pos {
          color: var(--success-ink);
        }
        .neg {
          color: var(--destructive-ink);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof PointsTransaction> {
    private ledgerQuery: ReturnType<getCards> | undefined;

    constructor(owner: unknown, args: any) {
      super(owner as never, args as never);
      this.ledgerQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(PointsTransaction);
          let account = this.args.model?.account?.id;
          return ref && account
            ? {
                filter: { on: ref, eq: { 'account.id': account } },
                sort: [{ on: ref, by: 'occurredAt', direction: 'desc' }],
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

    get model() {
      return this.args.model as PointsTransaction;
    }

    get ledger(): PointsTransaction[] {
      return (this.ledgerQuery?.instances ?? []) as PointsTransaction[];
    }

    get sameAccount(): PointsTransaction[] {
      return this.ledger.filter((t) => t.id !== this.model?.id).slice(0, 5);
    }

    get amountHint(): string {
      return (this.model?.amount ?? 0) < 0
        ? 'points debited'
        : 'points credited';
    }

    /** The account balance once this movement landed: today's balance less every later movement. */
    get balanceAfter(): string {
      let balance = this.model?.account?.pointsBalance;
      let at = asDate(this.model?.occurredAt)?.getTime();
      if (balance == null || at == null || !this.ledger.length) return '—';
      let later = this.ledger
        .filter((t) => (asDate(t.occurredAt)?.getTime() ?? 0) > at)
        .reduce((a, t) => a + (t.amount ?? 0), 0);
      return num(balance - later);
    }

    <template>
      <IsoFrame>
        <article class='page'>
          <header class='head'>
            <TxMark @size='lg' />
            <div class='id'>
              <h1 class='name'>{{reasonOf @model}}</h1>
              <p class='meta'>{{txMeta @model}}</p>
            </div>
            <div class='tags'>
              <span class='amt {{sign @model.amount}}'>{{signed @model.amount}}
                pts</span>
              {{#if @model.expiresAt}}<DotText
                  @label={{dayMonth @model.expiresAt}}
                  @tone='warning'
                />{{/if}}
            </div>
          </header>

          <dl class='stats' aria-label='Key numbers'>
            <div class='stat'>
              <dt class='label'>Amount</dt>
              <dd class='value {{sign @model.amount}}'>{{signed
                  @model.amount
                }}</dd>
              <dd class='sub'>{{this.amountHint}}</dd>
            </div>
            <div class='stat'>
              <dt class='label'>Source</dt>
              <dd class='value'>{{if @model.source @model.source '—'}}</dd>
              <dd class='sub'>{{reasonOf @model}}</dd>
            </div>
            <div class='stat'>
              <dt class='label'>Expires</dt>
              <dd class='value'>{{if
                  @model.expiresAt
                  (dayMonth @model.expiresAt)
                  'Never'
                }}</dd>
              <dd class='sub'>{{if
                  @model.expiresAt
                  (when @model.expiresAt)
                  'no expiry'
                }}</dd>
            </div>
          </dl>

          <div class='cols'>
            <div class='main'>
              <section class='sec'>
                <h2>Transaction</h2>
                <dl class='kv'>
                  <dt>Reason</dt><dd>{{reasonOf @model}}</dd>
                  <dt>Source</dt><dd>{{if @model.source @model.source '—'}}</dd>
                  <dt>Amount</dt><dd class='num'>{{signed @model.amount}}
                    points</dd>
                  <dt>Occurred</dt><dd>{{when @model.occurredAt}}</dd>
                  <dt>Expires</dt><dd>{{if
                      @model.expiresAt
                      (when @model.expiresAt)
                      'Never'
                    }}</dd>
                </dl>
              </section>
              {{#if this.sameAccount.length}}
                <section class='sec'>
                  <h2>Same account</h2>
                  <ul class='rows'>
                    {{#each this.sameAccount key='id' as |t|}}
                      <li class='row'>
                        <span class='date'>{{day t.occurredAt}}</span>
                        <span class='what'><strong>{{reasonOf t}}</strong>
                          {{#if t.source}}<span class='muted'>·
                              {{t.source}}</span>{{/if}}</span>
                        <span class='amt {{sign t.amount}}'>{{signed
                            t.amount
                          }}</span>
                      </li>
                    {{/each}}
                  </ul>
                </section>
              {{/if}}
            </div>

            <aside class='side'>
              <section class='sec'>
                <h2>Linked</h2>
                <dl class='kv'>
                  <dt>Account</dt>
                  <dd>{{#if @model.account}}<@fields.account
                        @format='atom'
                        @displayContainer={{false}}
                      />{{else}}—{{/if}}</dd>
                </dl>
              </section>
              <section class='sec'>
                <h2>Details</h2>
                <dl class='kv'>
                  <dt>Amount</dt><dd class='num'>{{signed @model.amount}}</dd>
                  <dt>Source</dt><dd>{{if @model.source @model.source '—'}}</dd>
                  <dt>Occurred</dt><dd>{{day @model.occurredAt}}</dd>
                  <dt>Expires</dt><dd>{{if
                      @model.expiresAt
                      (day @model.expiresAt)
                      'Never'
                    }}</dd>
                  <dt>Account</dt><dd>{{if
                      @model.account.holder.name
                      @model.account.holder.name
                      '—'
                    }}</dd>
                  <dt>Balance after</dt><dd
                    class='num'
                  >{{this.balanceAfter}}</dd>
                </dl>
              </section>
            </aside>
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .page {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background-color: var(--card);
          color: var(--card-foreground);
          font-size: var(--boxel-font-size-xs);
          overflow: hidden;
        }
        .head {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-sm);
          border-bottom: 1px solid var(--border);
        }
        .id {
          flex: 1 1 10rem;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .tags {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          margin-left: auto;
        }
        .stats {
          margin: 0;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
          border-bottom: 1px solid var(--border);
          overflow: hidden;
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          margin: 0 -1px -1px 0;
          border-right: 1px solid var(--border);
          border-bottom: 1px solid var(--border);
          min-width: 0;
        }
        .stat dt,
        .stat dd {
          margin: 0;
        }
        .label,
        .kv dt {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .value {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          line-height: 1.2;
          font-variant-numeric: tabular-nums;
        }
        .sub,
        .muted {
          color: var(--muted-foreground);
        }
        .sub {
          font-size: var(--boxel-font-size-2xs);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        }
        .main {
          border-right: 1px solid var(--border);
        }
        @container (max-width: 44rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .main {
            border-right: 0;
            border-bottom: 1px solid var(--border);
          }
        }
        .sec + .sec {
          border-top: 1px solid var(--border);
        }
        h2 {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .rows {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-3xs) var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
        }
        .date {
          flex-shrink: 0;
          width: 6rem;
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .what {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .amt {
          flex-shrink: 0;
          font-family: var(--font-mono);
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
        .pos {
          color: var(--success-ink);
        }
        .neg {
          color: var(--destructive-ink);
        }
        .kv {
          display: grid;
          grid-template-columns: 8rem minmax(0, 1fr);
          margin: 0;
          padding: 0 var(--boxel-sp-sm) var(--boxel-sp-3xs);
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-3xs) 0;
          border-top: 1px solid var(--border);
          min-width: 0;
          display: flex;
          align-items: center;
          flex-wrap: wrap;
        }
        .num {
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}
