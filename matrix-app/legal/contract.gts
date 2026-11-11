import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
  realmURL,
} from '@cardstack/base/card-api';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { concat, fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { and, eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { codeRef, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import StringField from '@cardstack/base/string';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import UrlField from '@cardstack/base/url';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import MarkdownField from '@cardstack/base/markdown';
import ContractIcon from '@cardstack/boxel-icons/contract';
import Theme from '@cardstack/base/theme';
import { Account } from '../crm/account';
import { Opportunity } from '../crm/opportunity';
import { formatMoney } from '../commerce/line-item-totals';
import { Employee } from '../hr/employee';
import { ApprovalChainField } from '../hr/approval-chain-field';
import { ContractStatusField, contractStatusLabel } from './contract-status';
import { RiskRatingField, riskGradeLabel } from './contract-risk';
import { LegalPartyRoleField } from './legal-party-role-field';
import { SignatureBlockField } from './signature-block-field';
import {
  EffectivePeriodField,
  daysUntil,
  toDate,
} from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { GoverningLawField } from './governing-law-field';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';

import { ContractTypeField, contractTypeLabel } from './contract-type';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;

/**
 * Query refs for the two cards that link UP to this one.
 *
 * Built with `codeRef` rather than `identifyCard(ContractClause)` because
 * importing those classes here is a STATIC module-level cycle: evaluating
 * contract.gts immediately evaluates contract-clause.gts, which re-enters
 * contract.gts before `Contract` is defined. The child's `linksTo(() =>
 * Contract)` thunk does not save it — the thunk defers the FIELD reference, not
 * the module evaluation. That is the "cardOrThunk was undefined" failure.
 *
 * `codeRef` resolves './contract-clause' against this module's own URL, so the
 * query gets a real ref with no import edge at all.
 */
const CONTRACT_CLAUSE_REF = codeRef(
  here,
  './contract-clause',
  'ContractClause',
);
const OBLIGATION_REF = codeRef(here, './obligation', 'Obligation');

/**
 * `YYYY-MM-DD` built from local calendar parts.
 *
 * Not `toISOString()`: a notice deadline is a calendar day, and
 * `new Date('2026-10-13').toISOString()` yields the 12th anywhere east of UTC.
 * A notice served one day late is a renewal nobody chose.
 */
function calendarDay(d: Date): string {
  let m = `${d.getMonth() + 1}`.padStart(2, '0');
  let day = `${d.getDate()}`.padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

/**
 * What the e-signature provider last told us.
 *
 * A closed set: the values arrive from the provider, and naming them here
 * means the card knows what it is allowed to be told.
 */
export const SignatureStatusField = markDefinition(
  enumField(StringField, {
    options: [
      { value: 'not_sent', label: 'Not sent' },
      { value: 'pending', label: 'Out for signature' },
      { value: 'signed', label: 'Signed' },
      { value: 'declined', label: 'Declined' },
      { value: 'voided', label: 'Voided' },
    ],
    displayName: 'Signature Status',
  }),
);

/** The status's hue from the contract lifecycle table; slate when unknown. */

// ---- Display helpers shared by the four formats ------------------------------

/** "May 15", or "May 15, 2027" with the year; '' for no or a bad date. */
function shortDate(v: unknown, withYear = false): string {
  let d = toDate(v as any);
  if (!d) return '';
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    ...(withYear ? { year: 'numeric' } : {}),
  });
}
function yearOf(v: unknown): string {
  let d = toDate(v as any);
  return d ? `${d.getFullYear()}` : '';
}
/** "$5,880": the stat strip's whole-unit figure. */
function moneyShort(m: any): string {
  let amount = m?.value?.amount;
  if (typeof amount !== 'number') return '';
  try {
    return amount.toLocaleString('en-US', {
      style: 'currency',
      currency: m?.value?.currency?.code || 'USD',
      maximumFractionDigits: 0,
    });
  } catch {
    return `${amount}`;
  }
}
/** "MSA-2026-0117 · Customer · Acme Industries". */
function contractMeta(m: any): string {
  return [
    m?.contractNumber,
    contractTypeLabel(m?.contractType),
    m?.account?.cardTitle,
  ]
    .filter(Boolean)
    .join(' · ');
}
function statusTone(status?: string | null): string {
  switch (status) {
    case 'signed':
    case 'active':
      return 'ok';
    case 'terminated':
    case 'expired':
      return 'bad';
    default:
      return 'info';
  }
}
const inc = (i: number) => i + 1;
/** First present value: boxel-ui's `or` returns a boolean, not the value. */
function pick<T>(...xs: T[]) {
  return xs.find((x) => x !== undefined && x !== null && x !== '');
}
/** The terms as one plain paragraph: the compact view drops markdown headings. */
function plainTerms(md?: string | null): string {
  return (md ?? '')
    .split('\n')
    .filter((l) => l.trim() && !l.trim().startsWith('#'))
    .join(' ');
}

class ContractIsolated extends Component<typeof Contract> {
  // Clauses and obligations link UP to their contract; there is no link array
  // on this card to read back (see the note on the field list). So the detail
  // page asks the realm the reverse question instead.
  private clauseQuery: ReturnType<getCards> | undefined;
  private obligationQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let byContract = (ref: any) => () => {
      let id = this.args.model?.id;
      if (!id) return undefined;
      return { filter: { on: ref, every: [{ eq: { 'contract.id': id } }] } };
    };
    this.clauseQuery = this.args.context?.getCards(
      this,
      byContract(CONTRACT_CLAUSE_REF),
      () => this.realms,
      { isLive: true },
    );
    this.obligationQuery = this.args.context?.getCards(
      this,
      byContract(OBLIGATION_REF),
      () => this.realms,
      { isLive: true },
    );
  }

  private get realms(): string[] | undefined {
    let url = (this.args.model as any)?.[realmURL];
    return url ? [url.href] : undefined;
  }

  get clauses(): any[] {
    return ((this.clauseQuery as any)?.instances ?? []).filter(Boolean);
  }
  get obligations(): any[] {
    return ((this.obligationQuery as any)?.instances ?? []).filter(Boolean);
  }

  // A live query resolving after first paint is how a card comes to assert
  // "no clauses" about data it has not received yet. Guarded on emptiness too,
  // so a background refresh of a populated list does not flash a skeleton.
  // A contract the CRM created has no clauses or obligations and never will,
  // so it must not flash "Loading clauses and obligations…" on every page
  // view. The CLM markers are what say this contract is managed here and is
  // therefore worth waiting on.
  get hasEffectivePeriod(): boolean {
    let p = this.args.model?.effectivePeriod;
    return Boolean(p?.effectiveDate || p?.endDate);
  }

  get isClmManaged(): boolean {
    let m = this.args.model;
    return Boolean(
      m?.contractNumber || m?.riskGrade || m?.approvalChain?.steps?.length,
    );
  }

  get isLoadingLinked() {
    let c = this.clauseQuery as any;
    let o = this.obligationQuery as any;
    return (
      (Boolean(c?.isLoading) || Boolean(o?.isLoading)) &&
      !this.clauses.length &&
      !this.obligations.length
    );
  }

  // Without reading `errors` a failed query is indistinguishable from an empty
  // realm, and the section would claim "there are none" when the truth is
  // "we could not look".
  get queryFailed(): boolean {
    let e1 = (this.clauseQuery as any)?.errors as any[] | undefined;
    let e2 = (this.obligationQuery as any)?.errors as any[] | undefined;
    return Boolean(e1?.length || e2?.length);
  }

  get deviations(): any[] {
    return this.clauses.filter((c) => c.isDeviation);
  }
  get deviationLabel(): string {
    let n = this.deviations.length;
    return `${n} deviation${n === 1 ? '' : 's'}`;
  }
  get overdue(): any[] {
    return this.obligations.filter((o) => o.status === 'overdue');
  }
  get overdueLabel(): string {
    return `${this.overdue.length} overdue`;
  }

  @action openCard(card: any) {
    (this.args as any).viewCard?.(card, 'isolated');
  }

  get valueDisplay() {
    return formatMoney(
      this.args.model?.value?.amount,
      this.args.model?.value?.currency?.code,
    );
  }
  get riskRows() {
    return (this.args.model?.risk?.criteria ?? [])
      .filter((c: any) => c?.name)
      .map((c: any) => {
        let s = typeof c.score === 'number' ? c.score : 0;
        return {
          name: c.name,
          score: typeof c.score === 'number' ? c.score : '—',
          style: htmlSafe(`--fill: ${Math.max(0, Math.min(5, s)) * 20}%`),
        };
      });
  }
  get steps() {
    return (this.args.model?.approvalChain?.steps ?? []).filter(Boolean);
  }
  get approvalSummary(): string {
    let s = this.steps;
    if (!s.length) return '';
    let done = s.filter((x: any) => x.decision === 'approved').length;
    return `${done} of ${s.length} approved`;
  }
  get firstSignatory(): any {
    return (this.args.model?.signatureBlocks ?? []).find(
      (b: any) => b?.signatory,
    )?.signatory;
  }
  get termRange(): string {
    let m = this.args.model;
    let a = shortDate(m?.startDate, true);
    let b = shortDate(m?.endDate, true);
    return a || b ? `${a || '—'} – ${b || '—'}` : '';
  }
  <template>
    <article class='contract-page'>
      <header class='ch'>
        <span class='mark' aria-hidden='true'>Ct</span>
        <div class='ch-id'>
          <h1>{{@model.cardTitle}}</h1>
          <p class='meta'>{{contractMeta @model}}</p>
        </div>
        <ul class='ch-state'>
          {{#if @model.status}}
            <li
              class='dot'
              data-tone={{statusTone @model.status}}
            >{{contractStatusLabel @model.status}}</li>
          {{/if}}
          {{#if @model.riskGrade}}
            <li class='dot' data-tone='warn'>{{@model.riskGrade}} risk</li>
          {{/if}}
          {{#if @model.autoRenews}}
            <li class='dot'>auto-renews</li>
          {{/if}}
        </ul>
      </header>

      <section class='stats' aria-label='Key numbers'>
        <div class='stat'>
          <span class='cap dot' data-tone='ok'>Value</span>
          <strong>{{pick (moneyShort @model) '—'}}</strong>
          <span class='sub'>{{if @model.value.amount 'per year' ''}}</span>
        </div>
        <div class='stat'>
          <span class='cap dot' data-tone='info'>Notice by</span>
          <strong>{{pick (shortDate @model.noticeBy) '—'}}</strong>
          <span class='sub'>{{yearOf @model.noticeBy}}{{#if
              @model.daysToNotice
            }} · {{@model.daysToNotice}} days left{{/if}}</span>
        </div>
        <div class='stat'>
          <span class='cap dot' data-tone='warn'>Risk</span>
          <strong>{{if
              @model.risk.score
              (concat @model.risk.score ' / 100')
              '—'
            }}</strong>
          <span class='sub'>{{riskGradeLabel @model.riskGrade}}
            ·
            {{this.riskRows.length}}
            criteria</span>
        </div>
        <div class='stat'>
          <span class='cap dot' data-tone='ok'>Signed</span>
          <strong>{{pick (shortDate @model.signedAt) '—'}}</strong>
          <span class='sub'>{{yearOf @model.signedAt}}{{#if
              @model.signatureProvider
            }} · {{@model.signatureProvider}}{{/if}}</span>
        </div>
      </section>

      <div class='cols'>
        <div class='col'>
          {{#if @model.terms}}
            <section class='blk'>
              <h2>Terms</h2>
              <p class='terms'>{{plainTerms @model.terms}}</p>
            </section>
          {{/if}}

          {{#if this.steps.length}}
            <section class='blk'>
              <h2>Approval chain</h2>
              <ol class='rows'>
                {{#each this.steps as |s i|}}
                  <li class='row'>
                    <span class='num'>{{inc i}}</span>
                    <strong>{{pick s.approver.cardTitle 'Unassigned'}}</strong>
                    <span class='muted'>{{shortDate
                        (pick s.decidedAt s.openedAt)
                        true
                      }}{{#if s.comment}} · {{s.comment}}{{/if}}
                      {{s.decision}}</span>
                  </li>
                {{/each}}
              </ol>
            </section>
          {{/if}}

          {{#if this.riskRows.length}}
            <section class='blk'>
              <h2>Risk scorecard</h2>
              <ul class='rows'>
                {{#each this.riskRows as |r|}}
                  <li class='row risk'>
                    <span>{{r.name}}</span>
                    <span class='bar' style={{r.style}}></span>
                    <span class='mono'>{{r.score}} / 5</span>
                  </li>
                {{/each}}
              </ul>
            </section>
          {{/if}}

          {{#if @model.signatureBlocks.length}}
            <section class='blk'>
              <h2>Signature blocks</h2>
              <ul class='rows'>
                {{#each @model.signatureBlocks as |b|}}
                  <li class='row sig'>
                    <div>
                      <strong>{{b.signingOrder}}
                        ·
                        {{pick
                          b.signerName
                          b.signatory.cardTitle
                          'Signer'
                        }}{{#if b.signerTitle}},
                          {{b.signerTitle}}{{/if}}</strong>
                      <span class='muted'>{{b.party.definedTerm}}{{#if
                          b.party.entity.cardTitle
                        }} · {{b.party.entity.cardTitle}}{{/if}}{{#if
                          b.signedAt
                        }} · {{shortDate b.signedAt true}}{{/if}}</span>
                    </div>
                    <span
                      class='dot'
                      data-tone={{if (eq b.lineStatus 'signed') 'ok'}}
                    >{{b.lineStatus}}</span>
                  </li>
                {{/each}}
              </ul>
            </section>
          {{/if}}

          {{#if @model.governingLaw.jurisdiction}}
            <section class='blk'>
              <h2>Governing law</h2>
              <dl class='kv'>
                <dt>Jurisdiction</dt><dd
                >{{@model.governingLaw.jurisdiction}}</dd>
                <dt>Venue</dt><dd>{{pick @model.governingLaw.venue '—'}}</dd>
              </dl>
            </section>
          {{/if}}

          {{#if this.queryFailed}}
            <Alert
              @tone='danger'
              @title="Could not load this contract's clauses and obligations"
              style={{ALERT_STYLE.danger}}
            >
              <:default>This is a failed lookup, not an empty record — reload
                before concluding there are none.</:default>
            </Alert>
          {{/if}}
        </div>

        <div class='col'>
          <section class='blk'>
            <h2>Linked</h2>
            <dl class='kv'>
              <dt>Owner</dt>
              <dd>{{#if @model.owner}}<@fields.owner
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</dd>
              <dt>Account</dt>
              <dd>{{#if @model.account}}<@fields.account
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</dd>
              {{#if @model.deal}}
                <dt>Deal</dt>
                <dd><@fields.deal
                    @format='atom'
                    @displayContainer={{false}}
                  /></dd>
              {{/if}}
              <dt>Signatory</dt>
              <dd>{{pick this.firstSignatory.cardTitle '—'}}</dd>
              {{#if (and this.isClmManaged this.isLoadingLinked)}}
                <dt>Clauses</dt>
                <dd class='muted' role='status'>Loading…</dd>
              {{/if}}
              {{#each this.deviations as |c|}}
                <dt>Deviation</dt>
                <dd><button
                    type='button'
                    class='link'
                    {{on 'click' (fn this.openCard c)}}
                  >{{c.cardTitle}}</button></dd>
              {{/each}}
              {{#each this.obligations as |o|}}
                <dt>Obligation</dt>
                <dd><button
                    type='button'
                    class='link'
                    {{on 'click' (fn this.openCard o)}}
                  >{{o.cardTitle}}</button></dd>
              {{/each}}
            </dl>
          </section>

          <section class='blk'>
            <h2>Details</h2>
            <dl class='kv'>
              <dt>Value</dt><dd>{{pick this.valueDisplay '—'}}</dd>
              <dt>Term</dt><dd>{{pick this.termRange '—'}}</dd>
              <dt>Notice</dt><dd class='mono'>{{if
                  @model.renewalNoticeDays
                  (concat @model.renewalNoticeDays ' days')
                  '—'
                }}</dd>
              <dt>Risk</dt><dd>{{pick @model.risk.summary '—'}}</dd>
              <dt>Signed</dt><dd class='mono'>{{pick
                  (shortDate @model.signedAt true)
                  '—'
                }}</dd>
              <dt>Provider</dt><dd>{{pick @model.signatureProvider '—'}}</dd>
              <dt>Governing law</dt><dd>{{pick
                  @model.governingLaw.jurisdiction
                  '—'
                }}</dd>
              <dt>Approval</dt><dd>{{pick this.approvalSummary '—'}}</dd>
            </dl>
          </section>
        </div>
      </div>
    </article>
    <style scoped>
      .contract-page {
        container-type: inline-size;
        container-name: contract-page;
        font-family: var(--font-sans);
        font-size: 0.75rem;
        color: var(--foreground);
        padding: 1rem;
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .ch,
      .stats,
      .blk {
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius, 0.5rem);
      }
      .ch {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 0.625rem 0.625rem;
        flex-wrap: wrap;
      }
      .ch {
        border-bottom-left-radius: 0;
        border-bottom-right-radius: 0;
      }
      .stats {
        margin-top: -0.5rem;
        border-top-left-radius: 0;
        border-top-right-radius: 0;
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        overflow: hidden;
      }
      .mark {
        flex: none;
        display: inline-grid;
        place-items: center;
        inline-size: 2rem;
        block-size: 2rem;
        border: 1px solid var(--border);
        border-radius: 0.25rem;
        background-color: var(--muted);
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-weight: 600;
      }
      .ch-id {
        flex: 1;
        min-width: 10rem;
      }
      h1 {
        margin: 0;
        font-family: var(--font-sans);
        font-size: 0.8125rem;
        font-weight: 700;
      }
      .meta,
      .muted,
      .sub {
        margin: 0;
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .ch-state {
        display: flex;
        gap: 0.75rem;
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .dot {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        white-space: nowrap;
        text-transform: lowercase;
      }
      .dot::before {
        content: '';
        inline-size: 0.4375rem;
        block-size: 0.4375rem;
        border-radius: 50%;
        background-color: var(--muted-foreground);
      }
      .dot[data-tone='ok']::before {
        background-color: var(--success);
      }
      .dot[data-tone='warn']::before {
        background-color: var(--warning);
      }
      .dot[data-tone='info']::before {
        background-color: var(--info);
      }
      .dot[data-tone='bad']::before {
        background-color: var(--destructive);
      }
      .stat {
        display: flex;
        flex-direction: column;
        gap: 0.125rem;
        padding: 0.5rem 0.625rem;
        border-right: 1px solid var(--border);
        border-bottom: 1px solid var(--border);
        margin: 0 -1px -1px 0;
      }
      .stat strong {
        font-size: 1.375rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1.2;
      }
      .cap,
      dt {
        font-family: var(--font-mono);
        font-size: 0.5625rem;
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .cols {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        gap: 0.5rem;
        align-items: start;
      }
      .col {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        min-width: 0;
      }
      .blk {
        padding: 0.4375rem 0.625rem;
      }
      h2 {
        margin: 0 0 0.25rem;
        padding-bottom: 0.25rem;
        border-bottom: 1px solid var(--border);
        font-size: 0.75rem;
        font-weight: 700;
      }
      .terms {
        margin: 0.25rem 0;
        font-size: 0.75rem;
        line-height: 1.5;
      }
      .rows {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .row {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        min-block-size: 1.75rem;
        border-top: 1px solid var(--border);
      }
      .row:first-child {
        border-top: 0;
      }
      .row.risk {
        display: grid;
        grid-template-columns: 7rem 1fr auto;
      }
      .row.sig {
        justify-content: space-between;
        padding-block: 0.25rem;
      }
      .row.sig div {
        display: flex;
        flex-direction: column;
      }
      .num,
      .mono {
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-variant-numeric: tabular-nums;
      }
      .bar {
        block-size: 0.1875rem;
        border-radius: 0.125rem;
        background:
          linear-gradient(var(--foreground), var(--foreground)) 0 0 /
            var(--fill) 100% no-repeat,
          var(--muted);
      }
      .kv {
        display: grid;
        grid-template-columns: 8rem minmax(0, 1fr);
        margin: 0;
      }
      .kv dt,
      .kv dd {
        margin: 0;
        display: flex;
        align-items: center;
        min-block-size: 1.75rem;
        border-top: 1px solid var(--border);
        min-width: 0;
      }
      .kv dt:first-of-type,
      .kv dt:first-of-type + dd {
        border-top: 0;
      }
      .link {
        all: unset;
        cursor: pointer;
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .link:hover,
      .link:focus-visible {
        text-decoration: underline;
      }
      @container contract-page (width < 44rem) {
        .cols {
          grid-template-columns: minmax(0, 1fr);
        }
        .stats {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
    </style>
  </template>
}

export class Contract extends CardDef {
  static displayName = 'Contract';
  static icon = ContractIcon;

  @field title = contains(StringField);
  @field account = linksTo(Account);

  // Theme inheritance. CardDef's default computes this from cardInfo.theme alone,
  // so a contract opened from the app lands in a NEW stack with no theme at all —
  // the DOM cascade the app relied on does not cross a stack boundary. Falling back
  // to the account's own cardTheme makes the link a data-model edge instead, which
  // does. And because Account computes its cardTheme the same way, the chain keeps
  // walking upward on its own.
  @field cardTheme = linksTo(() => Theme, {
    computeVia: function (this: Contract) {
      return this.cardInfo?.theme ?? this.account?.cardTheme;
    },
  });
  // Typed against Opportunity so a Deal — or any future subtype — is
  // assignable.
  @field deal = linksTo(Opportunity);
  @field status = contains(ContractStatusField);
  @field startDate = contains(DateField);
  @field endDate = contains(DateField);
  @field value = contains(AmountWithCurrency);
  // The event fact behind "signed": a date that is written once, so the
  // signature survives a later status change and can be reported on.
  @field signedAt = contains(DateField);

  /**
   * The contract's own text, so search reaches INSIDE the agreement rather than
   * only across its fields.
   *
   * The realm indexes field values into `search_doc`, so putting the body in a
   * field is what makes "indemnity" findable at all — a PDF at `documentUrl`
   * is opaque to the index. Populated by paste or by extraction; nothing here
   * parses the PDF, and pretending otherwise would be the interesting lie.
   */
  @field fullText = contains(MarkdownField);

  /**
   * E-SIGNATURE STATE — what the provider last reported for the whole
   * contract. Request Signature is the send path: it stamps these and marks
   * one signature line `requested`; the provider's own delivery is outside
   * the card. The per-line truth is `signatureBlocks[].lineStatus`; these three
   * summarise it for list views and for contracts with no signature page.
   *
   * Deliberately no "Send for signature" button on the card itself. A control
   * that looks like it dispatches a signing request and does not is worse than
   * no control, because the failure is silent and only discovered when nobody
   * signs.
   */
  /**
   * Drives the spec's data-sensitivity approval rule:
   *
   *     IF data_handling = "Sensitive PII" THEN [Legal] -> [Security] -> [DPO]
   *
   * A boolean rather than a category, because the routing question is binary:
   * either the DPO must see it or they must not. Grading sensitivity finer
   * would invite rules that disagree about where the line sits.
   */
  @field handlesSensitiveData = contains(BooleanField);

  @field signatureStatus = contains(SignatureStatusField);
  @field signatureRequestedAt = contains(DateField);
  @field signatureProvider = contains(StringField);
  @field executedCopyUrl = contains(UrlField);
  @field terms = contains(MarkdownField);
  // Where the executed copy lives. Most teams sign in DocuSign or similar, so
  // the record points at the artifact rather than trying to hold it.
  @field documentUrl = contains(UrlField);

  @field isSigned = contains(BooleanField, {
    computeVia: function (this: Contract) {
      return Boolean(this.signedAt);
    },
  });

  @field daysToExpiry = contains(NumberField, {
    computeVia: function (this: Contract) {
      if (!this.endDate || this.status === 'terminated') return 0;
      let days = Math.ceil(
        (new Date(this.endDate).getTime() - Date.now()) / 86400000,
      );
      return days > 0 ? days : 0;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Contract) {
      return this.title?.trim()?.length
        ? this.title
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  // ---- Lifecycle -----------------------------------------------------------
  // Every field below is optional and every derived value is `computeVia`, so
  // a contract carrying only the core fields still deserializes.

  @field contractNumber = contains(StringField);
  @field contractType = contains(ContractTypeField);
  /** Internal owner — who answers for this contract. */
  @field owner = linksTo(() => Employee);

  @field autoRenews = contains(BooleanField);
  @field renewalNoticeDays = contains(NumberField);

  @field risk = contains(RiskRatingField);
  @field approvalChain = contains(ApprovalChainField);

  // NO `clauses` / `obligations` link arrays here, deliberately.
  //
  // ContractClause and Obligation each link UP to their contract, and the app
  // reads them back with a live query filtered on that link. Two reasons:
  // obligations are unbounded and reporting-flavoured, which must be a query rather than a link array on the hot
  // parent card; and a back-link here would put Contract in an import cycle
  // with both modules, which fails to load ("cardOrThunk was undefined").
  /** Set on an amendment; the lineage is walked from here to the root. */
  @field parentContract = linksTo(() => Contract);

  // ---- Parties, signatures and term ------------------------------------------
  // Every field below is optional, so a contract without a signature page or
  // a structured term still reads correctly.
  //
  // Who is bound, in what capacity — the clauses' "Supplier" and "Customer".
  @field parties = containsMany(LegalPartyRoleField);
  // The signature ceremony: one line per signer, in signing order. Written by
  // Request Signature (status → requested) and read by Verify Signature and
  // Execute Contract, which refuse while any line is unsigned or out of
  // authority. Nothing here is a contract status — that stays on `status`.
  @field signatureBlocks = containsMany(SignatureBlockField);
  // Obligations window with the notice deadline computed. The flat
  // startDate/endDate/autoRenews/renewalNoticeDays hold the same facts; when
  // this is set, it is the one that is read.
  @field effectivePeriod = contains(EffectivePeriodField);
  @field governingLaw = contains(GoverningLawField);

  @field termMonths = contains(NumberField, {
    computeVia: function (this: Contract) {
      if (!this.startDate || !this.endDate) return undefined;
      let a = new Date(this.startDate);
      let b = new Date(this.endDate);
      if (!Number.isFinite(a.getTime()) || !Number.isFinite(b.getTime())) {
        return undefined;
      }
      let months =
        (b.getFullYear() - a.getFullYear()) * 12 +
        (b.getMonth() - a.getMonth());
      return months > 0 ? months : undefined;
    },
  });

  /**
   * The date notice must be served by to stop an auto-renewal.
   *
   * This is the date the app exists to surface: the expiry is common
   * knowledge, the notice deadline is the one that quietly passes.
   */
  @field noticeBy = contains(StringField, {
    computeVia: function (this: Contract) {
      // The structured Effective Period, when set, is the source of
      // truth for the deadline; otherwise the flat fields below are.
      let p = this.effectivePeriod;
      if (p?.endDate && p.autoRenews) {
        let d = p.noticeDeadline;
        let day = toDate(d);
        if (day) return calendarDay(day);
      }
      if (!this.endDate || !this.autoRenews) return undefined;
      let days = this.renewalNoticeDays;
      if (typeof days !== 'number' || !Number.isFinite(days)) return undefined;
      let end = toDate(this.endDate);
      if (!end) return undefined;
      return calendarDay(
        new Date(end.getFullYear(), end.getMonth(), end.getDate() - days),
      );
    },
  });

  @field daysToNotice = contains(NumberField, {
    computeVia: function (this: Contract) {
      return daysUntil(this.noticeBy);
    },
  });

  /**
   * Mirrors `risk.grade` onto the card.
   *
   * A nested field is not directly filterable, and the repository has to answer
   * "show me the critical contracts" — so the grade is lifted to a real indexed
   * field. It stays computed, so it cannot disagree with the scorecard it came
   * from.
   */
  @field riskGrade = contains(StringField, {
    computeVia: function (this: Contract) {
      return this.risk?.grade;
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: Contract) {
      return [
        contractTypeLabel(this.contractType),
        contractStatusLabel(this.status),
      ]
        .filter(Boolean)
        .join(' \u00b7 ');
    },
  });

  static atom = class Atom extends Component<typeof Contract> {
    <template>
      <span class='contract-atom'>
        <span class='mark' aria-hidden='true'>Ct</span>
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .contract-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-width: 0;
          max-width: 100%;
          font-size: 0.75rem;
          font-weight: 600;
          color: var(--foreground);
        }
        .mark {
          flex: none;
          display: inline-grid;
          place-items: center;
          inline-size: 1.125rem;
          block-size: 1.125rem;
          border: 1px solid var(--border);
          border-radius: 0.25rem;
          background-color: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem;
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Contract> {
    get valueDisplay() {
      return formatMoney(
        this.args.model?.value?.amount,
        this.args.model?.value?.currency?.code,
      );
    }
    get termRange(): string {
      let m = this.args.model;
      let a = shortDate(m?.startDate, true);
      let b = shortDate(m?.endDate, true);
      return a || b ? `${a || '—'} – ${b || '—'}` : '';
    }
    <template>
      <article class='ce'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>Ct</span>
          <div class='id'>
            <strong class='name'>{{@model.cardTitle}}</strong>
            <span class='muted ell'>{{contractMeta @model}}</span>
          </div>
          {{#if @model.status}}
            <span
              class='dot'
              data-tone={{statusTone @model.status}}
            >{{contractStatusLabel @model.status}}</span>
          {{/if}}
        </header>
        {{#if @model.noticeBy}}
          <p class='muted fact'>Notice by
            <b>{{shortDate @model.noticeBy true}}</b>{{#if @model.daysToNotice}}
              ·
              {{@model.daysToNotice}}
              days left{{/if}}</p>
        {{/if}}
        <dl class='kv'>
          <dt>Value</dt><dd>{{pick this.valueDisplay '—'}}</dd>
          <dt>Term</dt><dd>{{pick this.termRange '—'}}</dd>
          <dt>Notice</dt><dd class='mono'>{{if
              @model.renewalNoticeDays
              (concat @model.renewalNoticeDays ' days')
              '—'
            }}</dd>
          <dt>Risk</dt><dd>{{pick @model.risk.summary '—'}}</dd>
          <dt>Signed</dt><dd class='mono'>{{pick
              (shortDate @model.signedAt true)
              '—'
            }}</dd>
          <dt>Provider</dt><dd>{{pick @model.signatureProvider '—'}}</dd>
          <dt>Owner</dt><dd>{{#if @model.owner}}<@fields.owner
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</dd>
        </dl>
      </article>
      <style scoped>
        .ce {
          padding: 0.4375rem 0.625rem;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          color: var(--foreground);
        }
        .head {
          display: flex;
          align-items: flex-start;
          gap: 0.5rem;
        }
        .mark {
          flex: none;
          display: inline-grid;
          place-items: center;
          inline-size: 1.5rem;
          block-size: 1.5rem;
          border: 1px solid var(--border);
          border-radius: 0.25rem;
          background-color: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.625rem;
          font-weight: 600;
        }
        .id {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
        }
        .name,
        .ell {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .name {
          font-weight: 700;
        }
        .muted {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          margin: 0.375rem 0;
        }
        .fact b {
          color: var(--foreground);
        }
        .dot {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          white-space: nowrap;
          text-transform: lowercase;
        }
        .dot::before {
          content: '';
          inline-size: 0.4375rem;
          block-size: 0.4375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
        .dot[data-tone='ok']::before {
          background-color: var(--success);
        }
        .dot[data-tone='bad']::before {
          background-color: var(--destructive);
        }
        .kv {
          display: grid;
          grid-template-columns: 7.5rem minmax(0, 1fr);
          margin: 0;
        }
        dt,
        dd {
          margin: 0;
          display: flex;
          align-items: center;
          min-block-size: 1.75rem;
          border-top: 1px solid var(--border);
          min-width: 0;
        }
        dt {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
        }
        @container (width < 22rem) {
          .kv {
            grid-template-columns: 6rem minmax(0, 1fr);
          }
        }
      </style>
    </template>
  };

  // Rows in priority order; container queries drop whole rows as the tile
  // shrinks (identity → status → key fact → state → linked → numbers).
  static fitted = class Fitted extends Component<typeof Contract> {
    get valueDisplay() {
      return formatMoney(
        this.args.model?.value?.amount,
        this.args.model?.value?.currency?.code,
      );
    }
    <template>
      <article class='cf'>
        <div class='r head'>
          <span class='mark' aria-hidden='true'>Ct</span>
          <strong class='name'>{{@model.cardTitle}}</strong>
          {{#if @model.status}}
            <span
              class='dot st-inline'
              data-tone={{statusTone @model.status}}
            >{{contractStatusLabel @model.status}}</span>
          {{/if}}
        </div>
        <div class='r meta'>{{contractMeta @model}}</div>
        {{#if @model.status}}
          <div class='r st-row'><span
              class='dot'
              data-tone={{statusTone @model.status}}
            >{{contractStatusLabel @model.status}}</span></div>
        {{/if}}
        {{#if @model.noticeBy}}
          <div class='r fact'>Notice by
            {{shortDate @model.noticeBy true}}{{#if @model.daysToNotice}}
              ·
              {{@model.daysToNotice}}
              days left{{/if}}</div>
        {{/if}}
        <div class='r flags'>
          {{#if @model.riskGrade}}
            <span class='dot' data-tone='warn'>{{@model.riskGrade}} risk</span>
          {{/if}}
          {{#if @model.autoRenews}}<span
              class='dot renews'
            >auto-renews</span>{{/if}}
        </div>
        {{#if @model.owner}}
          <div class='r kv owner'><span class='cap'>Owner</span><@fields.owner
              @format='atom'
              @displayContainer={{false}}
            /></div>
        {{/if}}
        <div class='r kv val'><span class='cap'>Value</span><span>{{pick
              this.valueDisplay
              '—'
            }}</span></div>
        <div class='r kv term'><span class='cap'>Signed</span><span
            class='mono'
          >{{pick (shortDate @model.signedAt true) '—'}}</span></div>
        <div class='r kv prov'><span class='cap'>Provider</span><span>{{pick
              @model.signatureProvider
              '—'
            }}</span></div>
      </article>
      <style scoped>
        .cf {
          block-size: 100%;
          box-sizing: border-box;
          overflow: hidden;
          display: flex;
          flex-direction: column;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          color: var(--foreground);
        }
        .r {
          flex: none;
          display: flex;
          align-items: center;
          gap: 0.5rem;
          min-block-size: 1.75rem;
          padding-inline: 0.625rem;
          border-top: 1px solid var(--border);
          min-width: 0;
          overflow: hidden;
          white-space: nowrap;
        }
        .head {
          border-top: 0;
          min-block-size: 2.375rem;
        }
        .mark {
          flex: none;
          display: inline-grid;
          place-items: center;
          inline-size: 1.25rem;
          block-size: 1.25rem;
          border: 1px solid var(--border);
          border-radius: 0.25rem;
          background-color: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
        }
        .name {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 700;
        }
        .meta,
        .fact {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          text-overflow: ellipsis;
          display: block;
          line-height: 1.75rem;
        }
        .kv {
          justify-content: space-between;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
        }
        .dot {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          white-space: nowrap;
          text-transform: lowercase;
        }
        .dot::before {
          content: '';
          flex: none;
          inline-size: 0.4375rem;
          block-size: 0.4375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
        .dot[data-tone='ok']::before {
          background-color: var(--success);
        }
        .dot[data-tone='warn']::before {
          background-color: var(--warning);
        }
        .dot[data-tone='bad']::before {
          background-color: var(--destructive);
        }

        /* Narrow (< 250): status gets its own row; wide: beside the title. */
        .st-inline {
          display: none;
        }
        @container fitted-card (min-width: 250px) {
          .st-inline {
            display: inline-flex;
          }
          .st-row {
            display: none;
          }
        }
        /* Height budget: hide whole rows from the bottom up. */
        @container fitted-card (max-height: 64px) {
          .r:not(.head) {
            display: none;
          }
          .head {
            block-size: 100%;
          }
        }
        @container fitted-card (max-height: 104px) {
          .st-row,
          .fact {
            display: none;
          }
        }
        @container fitted-card (max-height: 169px) {
          .flags,
          .owner {
            display: none;
          }
        }
        @container fitted-card (max-height: 274px) {
          .val,
          .term,
          .prov {
            display: none;
          }
        }
        @container fitted-card (min-height: 275px) and (max-height: 400px) {
          .prov {
            display: none;
          }
        }
        @container fitted-card (max-width: 249px) and (max-height: 274px) {
          .owner {
            display: none;
          }
        }
        @container fitted-card (max-width: 249px) and (min-height: 250px) {
          .owner {
            display: flex;
          }
        }
        @container fitted-card (max-width: 249px) {
          .renews {
            display: none;
          }
        }
      </style>
    </template>
  };

  static isolated = ContractIsolated;
}
