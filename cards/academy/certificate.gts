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
import {
  Button,
  BoxelInput,
  FieldContainer,
} from '@cardstack/boxel-ui/components';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import RevokeCertificateCommand from './commands/revoke-certificate-command';

import {
  statusField,
  statusHue,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { CertificateNumberField } from './certificate-number-field';
import { CertificationAuthority } from '@cardstack/catalog/cards/audit/certification-authority';
import { Enrollment } from './enrollment';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { CertificateView } from './components/certificate-view';

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
  <template>
    <article class='cert-page'>
      <header class='bar'>
        <div>
          <span class='eyebrow'>Certificate</span>
          <h1 class='num'>{{if @model.number @model.number 'Unnumbered'}}</h1>
        </div>
        <div class='bar-right'>
          <StatePill
            @label={{@model.statusLabel}}
            @hue={{this.hue}}
            @dot={{true}}
          />
          {{#if @model.revokedReason}}<span
              class='reason'
            >{{@model.revokedReason}}</span>{{/if}}
        </div>
      </header>
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
      <dl class='facts'>
        {{#if @model.issuedBy}}<div><dt>Issued by</dt><dd
            >{{@model.issuedBy.name}}</dd></div>{{/if}}
        {{#if @model.enrollment}}<div><dt>Enrollment</dt><dd><@fields.enrollment
                @format='atom'
              /></dd></div>{{/if}}
        {{#if @model.revokedAt}}<div><dt>Revoked</dt><dd>{{fmtDate
                @model.revokedAt
              }}</dd></div>{{/if}}
      </dl>
      {{#if this.canRevoke}}
        <section class='revoke'>
          <h2>Revoke</h2>
          <p class='revoke-hint'>Revocation keeps the number and prints the
            reason on the record. It cannot be undone.</p>
          <div class='revoke-row'>
            <BoxelInput
              @value={{this.reason}}
              @onInput={{this.setReason}}
              @placeholder='Reason (required)'
              aria-label='Revocation reason'
            />
            <Button
              class='cta'
              @kind='destructive'
              @loading={{this.busy}}
              @disabled={{or this.busy (not this.reason)}}
              {{on 'click' this.revoke}}
            >Revoke certificate</Button>
          </div>
          {{#if this.error}}<p
              class='act-err'
              role='alert'
            >{{this.error}}</p>{{/if}}
          {{#if this.notice}}<p
              class='act-ok'
              role='status'
            >{{this.notice}}</p>{{/if}}
        </section>
      {{/if}}
    </article>
    <style scoped>
      .cta {
        min-height: 44px;
      }
      .revoke {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp);
        border: 1px solid var(--border, var(--boxel-200));
        border-left: 4px solid var(--boxel-danger);
        border-radius: var(--radius, var(--boxel-border-radius));
        background: var(--card, var(--boxel-light));
      }
      .revoke h2 {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .revoke-hint {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .revoke-row {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: var(--boxel-sp-xs);
        align-items: center;
      }
      .act-err,
      .act-ok {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
      }
      .act-err {
        color: color-mix(
          in oklab,
          var(--boxel-danger) 55%,
          var(--card-foreground, var(--boxel-dark))
        );
      }
      .act-ok {
        color: color-mix(
          in oklab,
          var(--boxel-success) 45%,
          var(--card-foreground, var(--boxel-dark))
        );
      }
      .cert-page {
        max-width: 60rem;
        margin: 0 auto;
        container-type: inline-size;
        padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp-lg);
        color: var(--foreground, var(--boxel-dark));
        background: var(--background, var(--boxel-light));
      }
      .bar {
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: var(--boxel-sp);
      }
      .eyebrow {
        font-size: var(--boxel-font-size-xs);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .num {
        margin: 0;
        font: 700 var(--boxel-font-size-xl)
          var(--font-mono, ui-monospace, monospace);
        letter-spacing: 0.04em;
      }
      .bar-right {
        display: grid;
        justify-items: end;
        gap: var(--boxel-sp-4xs);
      }
      .reason {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .facts {
        margin: 0;
        display: flex;
        gap: var(--boxel-sp-lg);
        flex-wrap: wrap;
        font-size: var(--boxel-font-size-sm);
      }
      dt {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      dd {
        margin: 0;
        font-weight: 600;
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
    <template>
      <div class='row'>
        <span class='seal' aria-hidden='true'>{{if
            @model.finalLetter
            @model.finalLetter
            '✓'
          }}</span>
        <div class='text'>
          <span class='title'>{{@model.learnerName}}
            ·
            {{@model.courseTitle}}</span>
          <span class='sub mono'>{{@model.number}}{{#if @model.issuedAt}}
              ·
              {{fmtDate @model.issuedAt}}{{/if}}</span>
        </div>
        <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .seal {
          width: 2.25rem;
          height: 2.25rem;
          display: grid;
          place-items: center;
          border-radius: 50%;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font: 800 var(--boxel-font-size)
            var(--font-heading, var(--boxel-font-family));
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{if @model.number @model.number 'Certificate'}}</span>
      <style scoped>
        .atom {
          font-family: var(--font-mono, ui-monospace, monospace);
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.04em;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'record', label: 'Record' },
      { id: 'snapshots', label: 'Printed facts' },
      { id: 'revocation', label: 'Revocation' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Certificate sections'
        as |e|
      >
        <e.Section
          @id='record'
          @title='Record'
          @hint='normally written by Issue Certificate'
          @cols={{3}}
        >
          <FieldContainer @label='Number' @vertical={{true}}><@fields.number
            /></FieldContainer>
          <FieldContainer @label='Status' @vertical={{true}}><@fields.certStatus
            /></FieldContainer>
          <FieldContainer
            @label='Issued at'
            @vertical={{true}}
          ><@fields.issuedAt /></FieldContainer>
          <FieldContainer
            @label='Authority'
            @vertical={{true}}
          ><@fields.authority /></FieldContainer>
          <FieldContainer
            @label='Issued by'
            @vertical={{true}}
          ><@fields.issuedBy /></FieldContainer>
          <FieldContainer
            @label='Enrollment'
            @vertical={{true}}
          ><@fields.enrollment /></FieldContainer>
        </e.Section>
        <e.Section
          @id='snapshots'
          @title='Printed facts'
          @hint='snapshotted at issue; a record, not a mirror'
          @cols={{3}}
        >
          <FieldContainer
            @label='Learner name'
            @vertical={{true}}
          ><@fields.learnerName /></FieldContainer>
          <FieldContainer
            @label='Course title'
            @vertical={{true}}
          ><@fields.courseTitle /></FieldContainer>
          <FieldContainer
            @label='Cohort name'
            @vertical={{true}}
          ><@fields.cohortName /></FieldContainer>
          <FieldContainer
            @label='Credit hours'
            @vertical={{true}}
          ><@fields.creditHours /></FieldContainer>
          <FieldContainer
            @label='Final letter'
            @vertical={{true}}
          ><@fields.finalLetter /></FieldContainer>
        </e.Section>
        <e.Section
          @id='revocation'
          @title='Revocation'
          @hint='use Revoke Certificate; the number is never reused'
          @cols={{2}}
        >
          <FieldContainer
            @label='Revoked at'
            @vertical={{true}}
          ><@fields.revokedAt /></FieldContainer>
          <FieldContainer
            @label='Reason'
            @vertical={{true}}
          ><@fields.revokedReason /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(CertificateStatusField, this.args.model?.certStatus);
    }
    <template>
      <article class='fit {{if (eqRevoked @model.certStatus) "revoked"}}'>
        <div class='fit-top'>
          <span class='seal'>{{if
              @model.finalLetter
              @model.finalLetter
              '✓'
            }}</span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{if
                @model.learnerName
                @model.learnerName
                'Unnamed'
              }}</h3>
            <span class='fit-eb'>{{@model.courseTitle}}</span>
          </div>
          <span class='fit-pill'><StatePill
              @label={{@model.statusLabel}}
              @hue={{this.hue}}
            /></span>
        </div>
        <span class='fit-num'>{{@model.number}}</span>
        <dl class='fit-add'>
          <div><dt>Cohort</dt><dd>{{@model.cohortName}}</dd></div>
          <div><dt>Issued</dt><dd>{{fmtDate @model.issuedAt}}</dd></div>
          {{#if @model.creditHours}}<div><dt>Credit</dt><dd
              >{{@model.creditHours}} hrs</dd></div>{{/if}}
        </dl>
      </article>
      <style scoped>
        .fit {
          height: 100%;
          padding: var(--boxel-sp-xs);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          overflow: hidden;
          border-left: 3px solid var(--primary, var(--boxel-highlight));
        }
        .fit.revoked {
          border-left-color: var(--boxel-danger);
        }
        .fit-top {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
          min-width: 0;
        }
        .seal {
          flex: none;
          width: 2rem;
          height: 2rem;
          display: grid;
          place-items: center;
          border-radius: 50%;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font: 800 var(--boxel-font-size-sm)
            var(--font-heading, var(--boxel-font-family));
        }
        .fit-head {
          min-width: 0;
          flex: 1;
        }
        .fit-name {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          font-size: 11px;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .fit-pill {
          flex: none;
        }
        .fit-num {
          display: none;
          font: 600 var(--boxel-font-size-xs)
            var(--font-mono, ui-monospace, monospace);
          letter-spacing: 0.04em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .fit-add {
          display: none;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
        }
        .fit-add div {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          padding: 2px 0;
          border-top: 1px solid var(--border, var(--boxel-200));
        }
        dt {
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 220px) {
          .fit-pill {
            display: none;
          }
        }
        @container fitted-card (min-height: 120px) {
          .fit-num {
            display: block;
          }
        }
        @container fitted-card (width <= 120px) {
          .fit-top {
            flex-direction: column;
            align-items: flex-start;
          }
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (min-width: 250px) and (min-height: 120px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
        @container fitted-card (min-width: 150px) and (min-height: 190px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
      </style>
    </template>
  };
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

function fmtDate(d?: Date | string | null): string {
  if (!d) return '—';
  return new Date(d).toLocaleDateString(undefined, {
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  });
}

export default Certificate;
