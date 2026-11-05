import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import NumberField from '@cardstack/base/number';
import CertificateIcon from '@cardstack/boxel-icons/certificate';
import { eq } from '@cardstack/boxel-ui/helpers';
import { FitTile } from '../../ui-component/components/fit-tile';
import type { KeyValueItem } from '../../ui-component/components/key-value';
import { FittedExtras, type FittedStat } from '../procurement/vendor';
import { Alert } from '../../ui-component/components/alert';
import { Button } from '../../ui-component/components/button';
import { Input } from '../../ui-component/components/input';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import RevokeCertificateCommand from './commands/revoke-certificate-command';
import {
  statusField,
  statusHue,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { CertificateNumberField } from './certificate-number-field';
import { CertificationAuthority } from '../audit/certification-authority';
import { Enrollment } from './enrollment';
import { Employee } from '../hr/employee';
import { CertificateView } from './components/certificate-view';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';

export const CERTIFICATE_STATUSES: StatusOption[] = [
  {
    value: 'issued',
    label: 'Issued',
    hue: 'green',
    meaning: 'Valid. The verify link resolves to this record.',
  },
  {
    value: 'revoked',
    label: 'Revoked',
    hue: 'red',
    meaning: 'Withdrawn with a reason. Number is never reused.',
    terminal: true,
  },
];

export const CertificateStatusField = statusField({
  displayName: 'Certificate Status',
  options: CERTIFICATE_STATUSES,
  transitions: { issued: ['revoked'], revoked: [] },
});

class CertificateIsolated extends Component<typeof Certificate> {
  get hue() {
    return statusHue(CertificateStatusField, this.args.model?.certStatus);
  }
  @tracked reason = '';
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked notice: string | undefined;
  get canRevoke() {
    return (
      this.args.model?.certStatus !== 'revoked' &&
      !!this.args.context?.commandContext
    );
  }
  setReason = (v: string) => (this.reason = v);
  revoke = async () => {
    let ctx = this.args.context?.commandContext;
    if (!ctx) return;
    this.busy = true;
    this.error = undefined;
    this.notice = undefined;
    try {
      let res = (await new RevokeCertificateCommand(ctx).execute({
        certificate: this.args.model,
        reason: this.reason,
      } as any)) as any;
      this.notice = res?.message;
      this.reason = '';
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  copyVerify = async () => {
    let url = this.args.model?.verifyUrl;
    if (!url) return;
    try {
      await navigator.clipboard.writeText(url);
      this.notice = 'Verify link copied';
    } catch {
      this.error = 'Could not copy the verify link';
    }
  };
  get facts() {
    return certFacts(this.args.model);
  }
  <template>
    <article class='cert-page'>
      <header class='bar'>
        <span class='mark' aria-hidden='true'>Ce</span>
        <div class='bar-id'>
          <h1 class='num'>{{if @model.number @model.number 'Unnumbered'}}</h1>
          <p class='bar-sub'>{{@model.learnerName}}
            ·
            {{@model.courseTitle}}</p>
        </div>
        <div class='chips'>
          <StatePill
            @label={{@model.statusLabel}}
            @hue={{this.hue}}
            @dot={{true}}
          />
          {{#if @model.finalLetter}}<StatePill
              @label='final {{@model.finalLetter}}'
              @hue='blue'
            />{{/if}}
        </div>
        {{#if @model.verifyUrl}}<Button
            @appearance='outlined'
            @size='s'
            {{on 'click' this.copyVerify}}
          >Copy verify link</Button>{{/if}}
      </header>
      {{#if this.notice}}<Alert @tone='success'>{{this.notice}}</Alert>{{/if}}
      {{#if @model.revokedReason}}<Alert @tone='danger'>Revoked:
          {{@model.revokedReason}}</Alert>{{/if}}
      <dl class='stats'>
        <div><dt>Final grade</dt><dd>{{if
              @model.finalLetter
              @model.finalLetter
              '—'
            }}</dd></div>
        <div><dt>Credit</dt><dd>{{if @model.creditHours @model.creditHours 0}}
            h</dd></div>
        <div><dt>Issued</dt><dd>{{fmtShort @model.issuedAt}}</dd></div>
      </dl>
      <CertificateView
        @number={{@model.number}}
        @learnerName={{@model.learnerName}}
        @courseTitle={{@model.courseTitle}}
        @cohortName={{@model.cohortName}}
        @creditHours={{@model.creditHours}}
        @finalLetter={{@model.finalLetter}}
        @issuedAt={{@model.issuedAt}}
        @authorityName={{@model.authorityName}}
        @signatoryName={{@model.authority.signatoryName}}
        @signatoryTitle={{@model.authority.signatoryTitle}}
        @sealUrl={{@model.authority.seal.resolvedUrl}}
        @verificationCode={{@model.verificationCode}}
        @verifyUrl={{@model.verifyUrl}}
        @revoked={{eqRevoked @model.certStatus}}
      />
      <div class='cols'>
        <section class='panel'>
          <h2>Certificate</h2>
          <dl class='kv'>
            {{#each this.facts as |f|}}
              <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
            {{/each}}
          </dl>
        </section>
        <section class='panel'>
          <h2>Linked</h2>
          <ul class='rels'>
            {{#if @model.authority}}<li><span>Authority</span><@fields.authority
                  @format='atom'
                /></li>{{/if}}
            {{#if @model.issuedBy}}<li><span>Issued by</span><@fields.issuedBy
                  @format='atom'
                /></li>{{/if}}
            {{#if @model.enrollment}}<li><span
                >Enrollment</span><@fields.enrollment
                  @format='atom'
                /></li>{{/if}}
          </ul>
        </section>
      </div>
      {{#if this.canRevoke}}
        <section class='revoke'>
          <h2>Revoke</h2>
          <p class='revoke-hint'>Revocation keeps the number and prints the
            reason on the record. It cannot be undone.</p>
          <div class='revoke-row'>
            <Input
              @value={{this.reason}}
              @onInput={{this.setReason}}
              @placeholder='Reason (required)'
              aria-label='Revocation reason'
            />
            <Button
              class='cta'
              @tone='danger'
              @appearance='outlined'
              @busy={{this.busy}}
              @disabled={{or this.busy (not this.reason)}}
              {{on 'click' this.revoke}}
            >Revoke certificate</Button>
          </div>
          {{#if this.error}}<Alert @tone='danger'>{{this.error}}</Alert>{{/if}}
        </section>
      {{/if}}
    </article>
    <style scoped>
      @layer PretComponent {
        .cert-page {
          max-width: 60rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .bar {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-sm);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          inline-size: 3rem;
          block-size: 3rem;
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--muted);
          color: var(--primary);
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        .bar-id {
          flex: 1 1 14rem;
          min-width: 0;
        }
        .num {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          font-family: var(--font-mono);
          line-height: 1.25;
        }
        .bar-sub {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .chips {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .stats {
          margin: 0;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
          gap: var(--boxel-sp);
        }
        .stats > div {
          padding: var(--boxel-sp);
          border-radius: var(--radius);
          background: var(--card);
          box-shadow: var(--shadow-sm);
        }
        .stats dt,
        .kv dt {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .stats dd {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          color: var(--primary);
        }
        .cols {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
          gap: var(--boxel-sp-lg);
        }
        .panel,
        .revoke {
          padding: var(--boxel-sp-lg);
          border-radius: var(--radius);
          background: var(--card);
          box-shadow: var(--shadow-sm);
          min-width: 0;
        }
        .panel h2,
        .revoke h2 {
          margin: 0 0 var(--boxel-sp);
          font-size: var(--boxel-font-size);
          font-weight: 600;
        }
        .kv {
          margin: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
        }
        .kv > div {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
        }
        .kv dd {
          margin: 0;
          font-weight: 600;
          text-align: end;
          min-width: 0;
          overflow-wrap: anywhere;
        }
        .rels {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
        }
        .rels li {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          color: var(--muted-foreground);
        }
        .revoke {
          display: grid;
          gap: var(--boxel-sp-xs);
          border-inline-start: 0.25rem solid var(--destructive);
        }
        .revoke-hint {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .revoke-row {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-xs);
          align-items: center;
        }
      }
    </style>
  </template>
}

/**
 * Proof that an enrolment met the completion rule, issued under an
 * authority's name. A certificate is a RECORD: the learner's name, the
 * course title, the cohort, credit hours and final letter are snapshotted at
 * issue so a later rename or re-lettering cannot alter what was printed.
 * Revocation is a status plus a reason, never a delete — the number stays
 * burned. `verificationCode` is derived from number + issue moment.
 */
export class Certificate extends CardDef {
  static displayName = 'Certificate';
  static icon = CertificateIcon;

  @field number = contains(CertificateNumberField);
  @field enrollment = linksTo(() => Enrollment);
  @field authority = linksTo(() => CertificationAuthority);
  @field issuedBy = linksTo(() => Employee);
  @field issuedAt = contains(DateTimeField);
  @field certStatus = contains(CertificateStatusField);
  @field revokedAt = contains(DateTimeField);
  @field revokedReason = contains(StringField);

  // Snapshots written once by Issue Certificate.
  @field learnerName = contains(StringField);
  @field courseTitle = contains(StringField);
  @field cohortName = contains(StringField);
  @field creditHours = contains(NumberField);
  @field finalLetter = contains(StringField);

  @field verificationCode = contains(StringField, {
    computeVia: function (this: Certificate) {
      return verificationCode(this.number, this.issuedAt);
    },
  });
  @field verifyUrl = contains(StringField, {
    computeVia: function (this: Certificate) {
      let base = this.authority?.verificationBaseUrl;
      return base && this.number
        ? `${base}${base.endsWith('/') ? '' : '/'}${this.number}`
        : '';
    },
  });
  @field authorityName = contains(StringField, {
    computeVia: function (this: Certificate) {
      return this.authority?.name ?? '';
    },
  });
  @field statusLabel = contains(StringField, {
    computeVia: function (this: Certificate) {
      return (
        CERTIFICATE_STATUSES.find((s) => s.value === this.certStatus)?.label ??
        'Issued'
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Certificate) {
      return `${this.number ?? 'Certificate'} · ${this.learnerName ?? ''}`.trim();
    },
  });

  static isolated = CertificateIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return statusHue(CertificateStatusField, this.args.model?.certStatus);
    }
    get fact() {
      return certFact(this.args.model);
    }
    get facts() {
      return certFacts(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <span class='mark' aria-hidden='true'>Ce</span>
          <div class='emb-id'>
            <h4 class='emb-title'>{{@model.number}}</h4>
            <p class='emb-sub'>{{@model.learnerName}}
              ·
              {{@model.courseTitle}}</p>
          </div>
          <div class='emb-chips'>
            <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
            {{#if @model.finalLetter}}<StatePill
                @label='final {{@model.finalLetter}}'
                @hue='blue'
              />{{/if}}
          </div>
        </header>
        <p class='emb-fact'>{{this.fact}}</p>
        <dl class='emb-kv'>
          {{#each this.facts as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        <div class='emb-rels'>
          {{#if @model.authority}}<span class='emb-rel'>Authority
              <@fields.authority @format='atom' /></span>{{/if}}
          {{#if @model.issuedBy}}<span class='emb-rel'>Issued by
              <@fields.issuedBy @format='atom' /></span>{{/if}}
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-sm);
            font-size: var(--boxel-font-size-sm);
          }
          .emb-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2.5rem;
            block-size: 2.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          .emb-id {
            flex: 1 1 12rem;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            font-family: var(--font-mono);
          }
          .emb-sub,
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-kv {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
            margin: 0;
          }
          .emb-kv dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-kv dd {
            margin: 0;
            font-weight: 600;
            overflow-wrap: anywhere;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-rel {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
            color: var(--muted-foreground);
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return statusHue(CertificateStatusField, this.args.model?.certStatus);
    }
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Ce</span>
        <span class='atom-name'>{{if
            @model.number
            @model.number
            'Certificate'
          }}</span>
        {{#if @model.certStatus}}<span class='atom-chip'><StatePill
              @label={{@model.statusLabel}}
              @hue={{this.hue}}
            /></span>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.5rem;
            row-gap: 1.5rem;
            overflow: hidden;
            vertical-align: middle;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .mark {
            display: inline-grid;
            place-items: center;
            flex: none;
            inline-size: 1.25rem;
            block-size: 1.25rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: 0.625rem;
            font-weight: 600;
            line-height: 1;
          }
          .atom-name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            font-family: var(--font-mono);
          }
          .atom-chip {
            flex: none;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(CertificateStatusField, this.args.model?.certStatus);
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.learnerName, m?.courseTitle].filter(Boolean).join(' · ');
    }
    get fact() {
      return certFact(this.args.model);
    }
    get facts(): KeyValueItem[] {
      return certFacts(this.args.model);
    }
    get stats(): FittedStat[] {
      let m = this.args.model;
      return [
        { key: 'Final grade', value: m?.finalLetter || '—' },
        { key: 'Credit', value: m?.creditHours ? `${m.creditHours} h` : '—' },
        { key: 'Issued', value: fmtShort(m?.issuedAt) },
      ];
    }
    get relations() {
      let m = this.args.model;
      return [
        ...(m?.authority ? ['Authority'] : []),
        ...(m?.issuedBy ? ['Issued by'] : []),
        ...(m?.enrollment ? ['Enrollment'] : []),
      ];
    }
    <template>
      <FittedExtras
        @facts={{this.facts}}
        @stats={{this.stats}}
        @relations={{this.relations}}
      >
        <:default>
          <FitTile>
            <:avatar><span class='mark' aria-hidden='true'>Ce</span></:avatar>
            <:title><span class='fit-title' role='heading' aria-level='3'>{{if
                  @model.number
                  @model.number
                  'Certificate'
                }}</span></:title>
            <:subtitle>{{this.subtitle}}</:subtitle>
            <:status>
              <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
              {{#if @model.finalLetter}}<StatePill
                  @label='final {{@model.finalLetter}}'
                  @hue='blue'
                />{{/if}}
            </:status>
            <:fact>{{this.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          {{#if (eq label 'Authority')}}<@fields.authority
              @format='atom'
            />{{else if (eq label 'Issued by')}}<@fields.issuedBy
              @format='atom'
            />{{else}}<@fields.enrollment @format='atom' />{{/if}}
        </:relation>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-family: var(--font-mono);
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };
}

function certFact(m?: Partial<Certificate> | null): string {
  return [
    m?.issuedAt ? `Issued ${fmtShort(m.issuedAt)}` : '',
    m?.creditHours ? `${m.creditHours} credit hours` : '',
  ]
    .filter(Boolean)
    .join(' · ');
}

function certFacts(m?: Partial<Certificate> | null): KeyValueItem[] {
  return [
    { key: 'Learner', value: m?.learnerName || '—' },
    { key: 'Course', value: m?.courseTitle || '—' },
    { key: 'Cohort', value: m?.cohortName || '—' },
    { key: 'Final grade', value: m?.finalLetter || '—' },
    {
      key: 'Credit hours',
      value: m?.creditHours ? String(m.creditHours) : '—',
    },
    { key: 'Issued', value: fmtShort(m?.issuedAt) },
    ...(m?.verifyUrl ? [{ key: 'Verify', value: m.verifyUrl }] : []),
    ...(m?.certStatus === 'revoked'
      ? [{ key: 'Revoked', value: fmtShort(m?.revokedAt) }]
      : []),
  ];
}

function fmtShort(d?: Date | string | null): string {
  if (!d) return '—';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

/** Short, stable, human-checkable: FNV-1a over number + issue instant, base36. */
export function verificationCode(
  number?: string | null,
  issuedAt?: Date | string | null,
): string {
  if (!number) return '';
  let s = `${number}|${issuedAt ? new Date(issuedAt).toISOString() : ''}`;
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(36).toUpperCase().padStart(7, '0');
}

function eqRevoked(v?: string | null) {
  return v === 'revoked';
}
function or(...v: unknown[]) {
  return v.some(Boolean);
}
function not(v: unknown) {
  return !v;
}

export default Certificate;
