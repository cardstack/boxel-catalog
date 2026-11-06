import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import EmailField from '@cardstack/base/email';
import PhoneNumberField from '@cardstack/base/phone-number';
import AddressField from '@cardstack/base/address';
import BooleanField from '@cardstack/base/boolean';
import { realmURL } from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Token } from '@cardstack/pretui/components/token';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { StatusChip } from '@cardstack/pretui/components/status-chip';

import { Vendor } from './vendor';
import {
  statusField,
  statusHue,
} from '@cardstack/catalog/fields/status/status';
import { PaymentTermsField } from '../commerce/payment-terms-field';
import { LifecycleDatesField } from '@cardstack/catalog/fields/lifecycle-dates/lifecycle-dates-field';
import OnboardVendorCommand from './commands/onboard-vendor-command';
import {
  StatePill,
  stateColor,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import {
  ALERT_STYLE,
  ID_TOKEN_STYLE,
} from '@cardstack/catalog/components/pretui-helpers';

// A calendar-day comparison: a certification that expires today is still
// valid today. Compares Y/M/D locally, never via toISOString (UTC skew).
export function isPastDay(d?: Date | null): boolean {
  if (!d) {
    return false;
  }
  let now = new Date();
  let today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  return day < today;
}

function maskTail(value?: string | null): string {
  let v = (value ?? '').replace(/\s/g, '');
  if (!v.length) {
    return '';
  }
  let tail = v.slice(-4);
  return `••••${tail}`;
}

// One compliance credential with a shelf life. Expiry is the load-bearing
// fact: an expired certification makes the whole profile award-ineligible
// (see VendorProfile.complianceOk and the RFQ comparison board).
export class CertificationField extends FieldDef {
  static displayName = 'Certification';

  @field name = contains(StringField);
  @field issuer = contains(StringField);
  @field issuedOn = contains(DateField);
  @field expiresOn = contains(DateField);

  @field isExpired = contains(BooleanField, {
    computeVia: function (this: CertificationField) {
      return isPastDay(this.expiresOn);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get expiryLabel() {
      let d = this.args.model?.expiresOn;
      if (!d) {
        return 'no expiry';
      }
      return `${this.args.model?.isExpired ? 'expired' : 'expires'} ${d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`;
    }
    <template>
      <div class='cert-row'>
        <span class='cert-name'>{{@model.name}}</span>
        <span class='cert-issuer'>{{@model.issuer}}</span>
        <StatePill
          @label={{this.expiryLabel}}
          @hue={{if @model.isExpired 'red' 'green'}}
          @dot={{true}}
        />
      </div>
      <style scoped>
        .cert-row {
          display: grid;
          grid-template-columns: 1fr auto auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-4xs) 0;
          font-size: 0.875rem;
        }
        .cert-name {
          font-weight: 600;
        }
        .cert-issuer {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

// Remittance details captured at intake. The account number is stored whole
// but every read format renders only the masked tail — payment execution is
// out of scope for this block (see readMe non-goals), the number exists so
// Finance can verify the vendor record against an invoice by its last 4.
export class BankDetailsField extends FieldDef {
  static displayName = 'Bank Details';

  @field bankName = contains(StringField);
  @field accountName = contains(StringField);
  @field accountNumber = contains(StringField);
  @field routingNumber = contains(StringField);

  @field maskedAccountNumber = contains(StringField, {
    computeVia: function (this: BankDetailsField) {
      return maskTail(this.accountNumber);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='bank'>
        <span class='bank-name'>{{@model.bankName}}</span>
        <span class='account'>{{@model.accountName}}</span>
        {{#if @model.maskedAccountNumber}}
          <Token
            @value={{@model.maskedAccountNumber}}
            style={{ID_TOKEN_STYLE.xs}}
          />
        {{/if}}
      </div>
      <style scoped>
        .bank {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          align-items: center;
          font-size: 0.875rem;
        }
        .bank-name {
          font-weight: 600;
        }
        .account {
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='bank-atom'>{{@model.bankName}}
        {{@model.maskedAccountNumber}}</span>
      <style scoped>
        .bank-atom {
          font-size: 0.8125rem;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

export const VENDOR_PROFILE_STATUSES = [
  'intake',
  'under-review',
  'approved',
  'onboarded',
  'rejected',
];

export const VENDOR_PROFILE_STATUS_LABELS: Record<string, string> = {
  intake: 'Intake',
  'under-review': 'Under Review',
  approved: 'Approved',
  onboarded: 'Onboarded',
  rejected: 'Rejected',
};

export const VENDOR_PROFILE_STATUS_COLORS: Record<string, StateColor> = {
  intake: stateColor('slate'),
  'under-review': stateColor('amber'),
  approved: stateColor('blue'),
  onboarded: stateColor('green'),
  rejected: stateColor('red'),
};

// A statusField (not a plain enum) so the vetting pipeline has a real
// transition graph: the Vendor Onboarding board derives its columns from
// these options and refuses illegal drags. `approved → onboarded` is
// deliberately ABSENT — onboarding creates the active Vendor record, so it
// only happens through OnboardVendorCommand (whose direct patch is not
// graph-gated), never by dragging a card.
export const VendorProfileStatusField = statusField({
  options: [
    {
      value: 'intake',
      label: 'Intake',
      hue: 'slate',
      meaning: 'Paperwork received, nobody has looked yet',
    },
    {
      value: 'under-review',
      label: 'Under Review',
      hue: 'amber',
      meaning: 'Compliance documents being checked',
    },
    {
      value: 'approved',
      label: 'Approved',
      hue: 'blue',
      meaning: 'Cleared to onboard — run Onboard Vendor to activate',
    },
    {
      value: 'onboarded',
      label: 'Onboarded',
      hue: 'green',
      terminal: true,
      meaning: 'Active vendor record exists; invitable to RFQs',
    },
    {
      value: 'rejected',
      label: 'Rejected',
      hue: 'red',
      terminal: true,
      meaning: 'Vetting failed — reasons in notes',
    },
  ],
  transitions: {
    intake: ['under-review', 'rejected'],
    'under-review': ['approved', 'rejected', 'intake'],
    approved: ['under-review', 'rejected'],
    onboarded: [],
    rejected: ['intake'],
  },
  displayName: 'Vendor Profile Status',
});

// ── Shared derivations for every format ────────────────────────────────
function fmtDate(d?: Date | null, short = false): string {
  if (!d) {
    return '—';
  }
  return d.toLocaleDateString(
    'en-US',
    short
      ? { month: 'short', day: 'numeric' }
      : { month: 'short', day: 'numeric', year: 'numeric' },
  );
}

function phoneLabel(raw?: string | null): string {
  if (!raw) {
    return '—';
  }
  // NANP numbers read as "+1 415 555 0134"; anything else stays as entered.
  let m = /^\+?1?(\d{3})(\d{3})(\d{4})$/.exec(raw.replace(/[\s().-]/g, ''));
  return m ? `+1 ${m[1]} ${m[2]} ${m[3]}` : raw;
}

function netLabel(p?: Partial<VendorProfile> | null): string {
  let n = p?.paymentTerms?.netDays;
  return n == null ? '—' : `Net-${n}`;
}

function termsLabel(p?: Partial<VendorProfile> | null): string {
  let t = p?.paymentTerms;
  if (t?.netDays == null) {
    return '—';
  }
  return t.discountPct && t.discountDays
    ? `Net-${t.netDays}, ${t.discountPct}% / ${t.discountDays}`
    : `Net-${t.netDays}`;
}

function discountLabel(p?: Partial<VendorProfile> | null): string {
  let t = p?.paymentTerms;
  return t?.discountPct && t?.discountDays
    ? `${t.discountPct}% if paid in ${t.discountDays} days`
    : 'no early-pay discount';
}

function validCertCount(p?: Partial<VendorProfile> | null): number {
  return (p?.certifications ?? []).filter((c) => c && !c.isExpired).length;
}

function certCount(p?: Partial<VendorProfile> | null): number {
  return (p?.certifications ?? []).filter(Boolean).length;
}

function profileSub(p?: Partial<VendorProfile> | null): string {
  return [p?.serviceCategory, p?.contactName].filter(Boolean).join(' · ');
}

function statusText(p?: Partial<VendorProfile> | null): string {
  return (
    VENDOR_PROFILE_STATUS_LABELS[p?.status ?? ''] ?? 'Intake'
  ).toLowerCase();
}

function profileHue(p?: Partial<VendorProfile> | null) {
  return statusHue(VendorProfileStatusField, p?.status);
}

function detailRows(p?: Partial<VendorProfile> | null) {
  return [
    { key: 'Contact', value: p?.contactName || '—' },
    { key: 'Insurance', value: fmtDate(p?.insuranceExpiry) },
    { key: 'Certifications', value: `${validCertCount(p)} valid` },
    { key: 'Terms', value: termsLabel(p) },
    { key: 'Tax ID', value: p?.maskedTaxId || '—' },
    { key: 'Bank', value: p?.bankDetails?.bankName || '—' },
  ];
}

function insuredFact(p?: Partial<VendorProfile> | null, short = false): string {
  return p?.insuranceExpiry
    ? `Insured to ${fmtDate(p.insuranceExpiry, short)}`
    : 'Insurance not on file';
}

function addressLine(p?: Partial<VendorProfile> | null): string {
  let a = p?.address;
  if (!a) {
    return '—';
  }
  let line = [
    a.addressLine1,
    a.city,
    [a.state, a.postalCode].filter(Boolean).join(' '),
  ]
    .filter(Boolean)
    .join(', ');
  return line || '—';
}

class VendorProfileIsolated extends Component<typeof VendorProfile> {
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked message: string | undefined;

  get canOnboard() {
    return (
      this.args.model?.status === 'approved' &&
      this.args.model?.complianceOk &&
      !this.args.model?.linkedVendor
    );
  }

  onboard = async () => {
    let model = this.args.model;
    if (!model) {
      return;
    }
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.error = 'Commands are unavailable in this mode';
      return;
    }
    let realm = (model as any)?.[realmURL]?.href;
    if (!realm) {
      this.error = 'Could not determine the realm for the new vendor';
      return;
    }
    this.error = undefined;
    this.message = undefined;
    this.busy = true;
    try {
      let result = await new OnboardVendorCommand(commandContext).execute({
        profile: model,
        realm,
      } as any);
      this.message = (result as any)?.message;
    } catch (error: any) {
      this.error = error?.message ?? String(error);
    } finally {
      this.busy = false;
    }
  };

  get m() {
    return this.args.model as VendorProfile;
  }
  get certs() {
    return (this.m?.certifications ?? []).filter(Boolean).map((c) => ({
      name: c.name || 'Certification',
      meta: [
        c.issuer,
        c.issuedOn ? `issued ${fmtDate(c.issuedOn)}` : null,
        c.expiresOn ? `expires ${fmtDate(c.expiresOn)}` : null,
      ]
        .filter(Boolean)
        .join(' · '),
      expired: c.isExpired,
    }));
  }
  get contactRows() {
    let m = this.m;
    return [
      { key: 'Contact', value: m?.contactName || '—' },
      { key: 'Email', value: m?.email || '—' },
      { key: 'Phone', value: phoneLabel(m?.phone) },
      { key: 'Address', value: addressLine(m) },
    ];
  }
  get financeRows() {
    let m = this.m;
    let b = m?.bankDetails;
    let t = m?.paymentTerms;
    return [
      { key: 'Tax ID', value: m?.maskedTaxId || '—' },
      {
        key: 'Bank',
        value:
          [b?.bankName, b?.maskedAccountNumber].filter(Boolean).join(' · ') ||
          '—',
      },
      {
        key: 'Terms',
        value:
          t?.netDays == null
            ? '—'
            : [
                `Net-${t.netDays}`,
                t.discountPct && t.discountDays
                  ? `${t.discountPct}% in ${t.discountDays} days`
                  : null,
                t.method,
              ]
                .filter(Boolean)
                .join(' · '),
      },
    ];
  }
  get lifecycleRows() {
    let l = this.m?.lifecycle;
    return [
      { key: 'Created', value: fmtDate(l?.createdAt) },
      { key: 'Activated', value: fmtDate(l?.activatedAt) },
      { key: 'Last reviewed', value: fmtDate(l?.lastReviewedAt) },
    ];
  }
  get detailRows() {
    let m = this.m;
    return [
      ...detailRows(m),
      { key: 'Phone', value: phoneLabel(m?.phone) },
      { key: 'Email', value: m?.email || '—' },
    ];
  }
  get insuranceExpired() {
    return isPastDay(this.m?.insuranceExpiry);
  }
  get insuranceYear() {
    return this.m?.insuranceExpiry
      ? String(this.m.insuranceExpiry.getFullYear())
      : 'not on file';
  }
  get certsValue() {
    return `${validCertCount(this.m)} / ${certCount(this.m)}`;
  }
  get pipelineHint() {
    let a = this.m?.lifecycle?.activatedAt;
    return a ? `onboarded ${fmtDate(a)}` : statusText(this.m);
  }

  <template>
    <article class='vp'>
      <section class='card'>
        <header class='ih'>
          <Avatar
            @name={{if @model.companyName @model.companyName 'Vendor'}}
            @shape='rounded'
            @size={{22}}
          />
          <div class='id'>
            <h1>{{@model.title}}</h1>
            <span class='meta'>{{profileSub @model}}</span>
          </div>
          <div class='sts'>
            <StatusChip
              @value={{statusText @model}}
              @hue={{profileHue @model}}
              @appearance='plain'
            />
            <StatusChip
              @value={{if @model.complianceOk 'compliant' 'lapsed'}}
              @hue={{if @model.complianceOk 'green' 'red'}}
              @appearance='plain'
            />
            {{#if this.canOnboard}}
              <Button
                @variant='primary'
                @size='sm'
                @disabled={{this.busy}}
                {{on 'click' this.onboard}}
              >{{if this.busy 'Onboarding…' 'Onboard vendor'}}</Button>
            {{/if}}
          </div>
        </header>
        {{#if this.error}}
          <Alert
            @tone='danger'
            @title={{this.error}}
            style={{ALERT_STYLE.danger}}
          />
        {{/if}}
        {{#if this.message}}
          <Alert
            @tone='success'
            @title={{this.message}}
            style={{ALERT_STYLE.success}}
          />
        {{/if}}
        <div class='stats'>
          <div class='stat'>
            <span class='cap'><span
                class='dot {{if this.insuranceExpired "bad"}}'
              ></span>Insurance until</span>
            <span class='num'>{{fmtDate @model.insuranceExpiry true}}</span>
            <span class='meta'>{{this.insuranceYear}}</span>
          </div>
          <div class='stat'>
            <span class='cap'><span
                class='dot {{if @model.complianceOk "ok" "bad"}}'
              ></span>Certifications</span>
            <span class='num'>{{this.certsValue}}</span>
            <span class='meta'>valid</span>
          </div>
          <div class='stat'>
            <span class='cap'><span class='dot'></span>Payment terms</span>
            <span class='num'>{{netLabel @model}}</span>
            <span class='meta'>{{discountLabel @model}}</span>
          </div>
          <div class='stat'>
            <span class='cap'><span class='dot'></span>In pipeline</span>
            <span class='num'>{{fmtDate @model.lifecycle.createdAt true}}</span>
            <span class='meta'>{{this.pipelineHint}}</span>
          </div>
        </div>
      </section>

      <div class='grid2'>
        <div class='col'>
          <section class='card'>
            <h2>Certifications</h2>
            {{#if this.certs.length}}
              <ul class='rows'>
                {{#each this.certs as |c|}}
                  <li>
                    <span class='two'>
                      <span class='strong'>{{c.name}}</span>
                      <span class='meta'>{{c.meta}}</span>
                    </span>
                    <StatusChip
                      @value={{if c.expired 'expired' 'valid'}}
                      @hue={{if c.expired 'red' 'green'}}
                      @appearance='plain'
                    />
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class='body'>No certifications on file.</p>
            {{/if}}
          </section>
          <section class='card'>
            <h2>Notes</h2>
            <p class='body'>{{if @model.notes @model.notes '—'}}</p>
          </section>
        </div>
        <div class='col'>
          <section class='card'>
            <h2>Contact</h2>
            <KeyValue
              class='kv'
              @items={{this.contactRows}}
              @labelStyle='eyebrow'
              @divided={{true}}
            >
              <:value as |row|><span class='kvv'>{{row.value}}</span></:value>
            </KeyValue>
          </section>
          <section class='card'>
            <h2>Finance</h2>
            <KeyValue
              class='kv'
              @items={{this.financeRows}}
              @labelStyle='eyebrow'
              @divided={{true}}
            >
              <:value as |row|><span class='kvv'>{{row.value}}</span></:value>
            </KeyValue>
          </section>
          <section class='card'>
            <h2>Lifecycle</h2>
            <KeyValue
              class='kv'
              @items={{this.lifecycleRows}}
              @labelStyle='eyebrow'
              @divided={{true}}
            >
              <:value as |row|><span class='kvv'>{{row.value}}</span></:value>
            </KeyValue>
          </section>
          <section class='card'>
            <h2>Linked</h2>
            <div class='linked'>
              <span class='cap'>Vendor</span>
              {{#if @model.linkedVendor}}
                <@fields.linkedVendor
                  @format='atom'
                  @displayContainer={{false}}
                />
              {{else}}
                <span class='meta'>not onboarded yet</span>
              {{/if}}
            </div>
          </section>
          <section class='card'>
            <h2>Details</h2>
            <KeyValue
              class='kv'
              @items={{this.detailRows}}
              @labelStyle='eyebrow'
              @divided={{true}}
            >
              <:value as |row|><span class='kvv'>{{row.value}}</span></:value>
            </KeyValue>
          </section>
        </div>
      </div>
    </article>
    <style scoped>
      .vp {
        font-size: 0.75rem;
        line-height: 1.4;
        color: var(--foreground);
        --pretui-kv-label-font-size: 0.5625rem;
        --pretui-kv-label-color: var(--muted-foreground);
        --boxel-sp-xs: 0.375rem;
        --boxel-sp-lg: 0.75rem;
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        padding: 0.5rem;
        box-sizing: border-box;
        min-block-size: 100%;
        background: var(--background);
      }
      .card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        min-inline-size: 0;
      }
      .ih {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 0.75rem;
        padding: 0.625rem;
      }
      .id {
        flex: 1 1 12rem;
        min-inline-size: 0;
        display: flex;
        flex-direction: column;
      }
      h1 {
        margin: 0;
        font-family: var(--font-sans);
        font-size: 0.75rem;
        font-weight: 700;
        line-height: 1.3;
      }
      .sts {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 0.625rem;
      }
      .meta {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .strong {
        font-weight: 700;
      }
      .cap {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        font-family: var(--font-mono);
        font-size: 0.5625rem;
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .dot {
        inline-size: 0.375rem;
        block-size: 0.375rem;
        border-radius: 50%;
        background: var(--muted-foreground);
        flex: none;
      }
      .dot.ok {
        background: var(--success-ink);
      }
      .dot.bad {
        background: var(--destructive);
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        border-top: 1px solid var(--border);
        overflow: hidden;
      }
      .stat {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        padding: 0.4375rem 0.625rem;
        border-inline-start: 1px solid var(--border);
        margin-inline-start: -1px;
        min-inline-size: 0;
      }
      .num {
        font-size: 1.375rem;
        font-weight: 700;
        line-height: 1;
        font-variant-numeric: tabular-nums;
      }
      .grid2 {
        display: grid;
        grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
        gap: 0.5rem;
        align-items: start;
      }
      .col {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        min-inline-size: 0;
      }
      h2 {
        margin: 0;
        padding: 0.4375rem 0.625rem 0.3125rem;
        font-size: 0.75rem;
        font-weight: 700;
      }
      .rows {
        list-style: none;
        margin: 0;
        padding: 0 0.625rem;
      }
      .rows li {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.5rem;
        border-top: 1px solid var(--border);
      }
      .two {
        display: flex;
        flex-direction: column;
        padding-block: 0.4375rem;
        min-inline-size: 0;
      }
      .body {
        margin: 0;
        padding: 0 0.625rem 0.625rem;
        overflow-wrap: anywhere;
      }
      .kvv {
        font-size: 0.75rem;
      }
      .kv {
        padding: 0 0.625rem 0.625rem;
        overflow-wrap: anywhere;
      }
      .linked {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 0.75rem;
        min-block-size: 1.75rem;
        margin: 0 0.625rem 0.625rem;
        border-top: 1px solid var(--border);
      }
      .linked .cap {
        min-inline-size: 7.5rem;
      }
      @container (max-width: 45rem) {
        .grid2 {
          grid-template-columns: minmax(0, 1fr);
        }
        .stats {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .stat:nth-child(n + 3) {
          border-top: 1px solid var(--border);
        }
      }
    </style>
  </template>
}

// The buyer-recorded intake dossier for a would-be vendor: identity, tax and
// remittance details, and dated compliance credentials. Single-persona rule:
// there is no vendor-facing submission flow — the procurement manager
// transcribes the vendor's paperwork. OnboardVendorCommand converts an
// approved profile into an active Vendor; complianceOk is the award gate the
// RFQ comparison board reads.
export class VendorProfile extends CardDef {
  static displayName = 'Vendor Profile';
  static headerColor = '#3e4e88';

  @field companyName = contains(StringField);
  @field contactName = contains(StringField);
  @field email = contains(EmailField);
  @field phone = contains(PhoneNumberField);
  @field address = contains(AddressField);
  @field serviceCategory = contains(StringField, {
    description: 'e.g. IT Hardware, Facilities, Marketing, Logistics',
  });
  @field taxId = contains(StringField);
  @field bankDetails = contains(BankDetailsField);
  @field certifications = containsMany(CertificationField);
  @field insuranceExpiry = contains(DateField);
  @field status = contains(VendorProfileStatusField);
  @field notes = contains(TextAreaField);
  // ---- Terms, lifecycle and onboarding ---------------------------------------
  @field paymentTerms = contains(PaymentTermsField);
  @field lifecycle = contains(LifecycleDatesField);
  @field linkedVendor = linksTo(() => Vendor);

  @field maskedTaxId = contains(StringField, {
    computeVia: function (this: VendorProfile) {
      return maskTail(this.taxId);
    },
  });

  @field expiredCertificationCount = contains(StringField, {
    computeVia: function (this: VendorProfile) {
      let expired = (this.certifications ?? []).filter(
        (c) => c?.isExpired,
      ).length;
      return String(expired);
    },
  });

  // The award gate: insurance ON FILE and current, AND no expired
  // certifications. Absence is non-compliance — a profile with no insurance
  // recorded must not read as compliant (fake-vendor fraud starts with thin
  // files). The RFQ comparison board disables Award for any vendor whose
  // profile fails this.
  @field complianceOk = contains(BooleanField, {
    computeVia: function (this: VendorProfile) {
      let certsOk = (this.certifications ?? []).every((c) => !c?.isExpired);
      let insuranceOk =
        this.insuranceExpiry != null && !isPastDay(this.insuranceExpiry);
      return certsOk && insuranceOk;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: VendorProfile) {
      return this.companyName?.trim()?.length
        ? this.companyName
        : 'Untitled Vendor Profile';
    },
  });

  static isolated = VendorProfileIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <article class='emb'>
        <header>
          <div class='h1'>
            <Avatar
              @name={{if @model.companyName @model.companyName 'Vendor'}}
              @shape='rounded'
              @size={{22}}
            />
            <span class='nm'>{{@model.title}}</span>
            <StatusChip
              @value={{statusText @model}}
              @hue={{profileHue @model}}
              @appearance='plain'
            />
          </div>
          <div class='h2'>
            <span class='meta'>{{profileSub @model}}</span>
            <StatusChip
              @value={{if @model.complianceOk 'compliant' 'lapsed'}}
              @hue={{if @model.complianceOk 'green' 'red'}}
              @appearance='plain'
            />
          </div>
        </header>
        <p class='fact'>{{insuredFact @model}} · {{netLabel @model}}</p>
        <KeyValue
          class='kv'
          @items={{detailRows @model}}
          @labelStyle='eyebrow'
          @divided={{true}}
        >
          <:value as |row|><span class='kvv'>{{row.value}}</span></:value>
        </KeyValue>
        {{#if @model.linkedVendor}}
          <div class='linked'>
            <span class='cap'>Vendor</span>
            <@fields.linkedVendor @format='atom' @displayContainer={{false}} />
          </div>
        {{/if}}
      </article>
      <style scoped>
        .emb {
          font-size: 0.75rem;
          line-height: 1.4;
          color: var(--foreground);
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          --boxel-sp-xs: 0.375rem;
          --boxel-sp-lg: 0.75rem;
          padding-block-end: 0.4375rem;
        }
        header {
          padding: 0.4375rem 0.625rem;
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .h1,
        .h2 {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 0.375rem 0.5rem;
        }
        .nm {
          flex: 1 1 6rem;
          min-inline-size: 0;
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          flex: 1 1 8rem;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          margin: 0;
          padding: 0.3125rem 0.625rem;
          border-top: 1px solid var(--border);
        }
        .kv {
          padding-inline: 0.625rem;
        }
        .kvv {
          font-size: 0.75rem;
        }
        .linked {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 0.75rem;
          min-block-size: 1.75rem;
          margin-inline: 0.625rem;
          border-top: 1px solid var(--border);
        }
        .cap {
          min-inline-size: 7.5rem;
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <Avatar
          @name={{if @model.companyName @model.companyName 'Vendor'}}
          @shape='rounded'
          @size={{18}}
        />
        <span class='n'>{{@model.title}}</span>
        <StatusChip
          @value={{statusText @model}}
          @hue={{profileHue @model}}
          @appearance='plain'
        />
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-inline-size: 0;
          max-inline-size: 100%;
          font-size: 0.6875rem;
          color: var(--foreground);
        }
        .n {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          min-inline-size: 0;
        }
      </style>
    </template>
  };

  // Rows are 28px with a hairline between. The column wraps, so a row that
  // does not fit moves into a second column outside the tile and is clipped
  // whole — never a half-cut row, no thresholds to keep in sync.
  static fitted = class Fitted extends Component<typeof this> {
    get certs() {
      return (this.args.model?.certifications ?? []).filter(Boolean);
    }
    // Under 250 wide the mock shows short values and skips Certifications.
    get rows() {
      let m = this.args.model as VendorProfile;
      let short: Record<string, string> = {
        Insurance: fmtDate(m?.insuranceExpiry, true),
        Terms: netLabel(m),
      };
      return detailRows(m).map((r) => ({
        ...r,
        short: short[r.key] ?? r.value,
        wideOnly: r.key === 'Certifications',
      }));
    }
    <template>
      <div class='fit'>
        <div class='fx'>
          <div class='fr fh'>
            <Avatar
              @name={{if @model.companyName @model.companyName 'Vendor'}}
              @shape='rounded'
              @size={{20}}
            />
            <span class='nm'>{{@model.title}}</span>
            <span class='wide'><StatusChip
                @value={{statusText @model}}
                @hue={{profileHue @model}}
                @appearance='plain'
              /></span>
            <span class='narrow dot' title={{statusText @model}}><StatusChip
                @value={{statusText @model}}
                @hue={{profileHue @model}}
                @appearance='plain'
              /></span>
          </div>
          <div class='fr'>
            <span class='meta wide'>{{profileSub @model}}</span>
            <span class='meta narrow'>{{if
                @model.contactName
                @model.contactName
                @model.serviceCategory
              }}</span>
          </div>
          <div class='fr'>
            <span class='mono wide'>{{insuredFact @model}}
              ·
              {{netLabel @model}}</span>
            <span class='mono narrow'>{{insuredFact @model true}}</span>
          </div>
          <div class='fr narrow-row'>
            <StatusChip
              @value={{statusText @model}}
              @hue={{profileHue @model}}
              @appearance='plain'
            />
          </div>
          <div class='frs'>
            <div class='stat'><span class='cap'>Insured to</span><span
                class='num'
              >{{fmtDate @model.insuranceExpiry true}}</span></div>
            <div class='stat'><span class='cap'>Certs</span><span
                class='num'
              >{{validCertCount @model}} / {{certCount @model}}</span></div>
            <div class='stat'><span class='cap'>Terms</span><span
                class='num'
              >{{netLabel @model}}</span></div>
          </div>
          {{#each this.rows as |row|}}
            <div class='fr fk {{if row.wideOnly "wide-row"}}'>
              <span class='cap'>{{row.key}}</span>
              <span class='mono v wide'>{{row.value}}</span>
              <span class='mono v narrow'>{{row.short}}</span>
            </div>
          {{/each}}
          {{#if this.certs.length}}
            <div class='fr'><span class='cap'>Certifications</span></div>
            {{#each this.certs as |c|}}
              <div class='fr'>
                <span class='ln'>{{c.name}}</span>
                <StatusChip
                  @value={{if c.isExpired 'expired' 'valid'}}
                  @hue={{if c.isExpired 'red' 'green'}}
                  @appearance='plain'
                />
              </div>
            {{/each}}
          {{/if}}
        </div>
      </div>
      <style scoped>
        .fit {
          container-type: size;
          block-size: 100%;
          inline-size: 100%;
          overflow: hidden;
          font-size: 0.75rem;
          line-height: 1.3;
          color: var(--foreground);
        }
        .fx {
          display: flex;
          flex-direction: column;
          flex-wrap: wrap;
          align-content: flex-start;
          block-size: 100%;
        }
        .fr,
        .frs {
          flex: none;
          inline-size: 100%;
          box-sizing: border-box;
        }
        .fr {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          block-size: 1.75rem;
          padding-inline: 0.625rem;
          overflow: hidden;
          white-space: nowrap;
          min-inline-size: 0;
        }
        .fr + .fr,
        .fr + .frs,
        .frs + .fr {
          border-top: 1px solid var(--border);
        }
        .nm {
          flex: 1;
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 700;
        }
        .fk {
          justify-content: space-between;
          gap: 0.5rem;
        }
        .meta,
        .mono,
        .ln,
        .v {
          overflow: hidden;
          text-overflow: ellipsis;
          min-inline-size: 0;
        }
        .ln {
          flex: 1;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        .cap {
          flex: none;
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .frs {
          display: none;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          block-size: 3.5rem;
          overflow: hidden;
        }
        .stat {
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.25rem;
          padding-inline: 0.625rem;
          min-inline-size: 0;
          white-space: nowrap;
        }
        .stat + .stat {
          border-inline-start: 1px solid var(--border);
        }
        .num {
          font-size: 1.375rem;
          font-weight: 700;
          line-height: 1;
          font-variant-numeric: tabular-nums;
        }
        .wide,
        .wide-row {
          display: none;
        }
        .dot {
          flex: none;
          inline-size: 0.5rem;
          overflow: hidden;
        }
        @container (min-width: 250px) {
          .wide {
            display: inline;
          }
          .narrow,
          .narrow-row {
            display: none;
          }
          .wide-row {
            display: flex;
          }
        }
        @container (min-width: 400px) and (min-height: 250px) {
          .frs {
            display: grid;
          }
        }
        @container (max-height: 45px) {
          .fh {
            block-size: 100cqh;
          }
        }
      </style>
    </template>
  };

  // A form someone fills in during a call with the vendor — grouped by how
  // the conversation actually goes (who are you → how do we reach you → are
  // you compliant → how do we pay you), not by schema declaration order.
}
