import { markDefinition } from '@cardstack/base/mark-definition';
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
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';

import RevokeCertificateCommand from './commands/revoke-certificate-command';

import {
  statusField,
  statusHue,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';
import { CertificateNumberField } from './certificate-number-field';
import { CertificationAuthority } from '../audit/certification-authority';
import { Enrollment } from './enrollment';
import { Employee } from '../hr/employee';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { RichFittedCard } from '../shared/rich-fitted-card';
import {
  AtomChip,
  Dot,
  Embed,
  Kv,
  Mark,
  Section,
  Sheet,
  Stat,
} from './components/record-sheet';
import { IsoFrame } from '../shared/compact-sheet';

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

export const CertificateStatusField = markDefinition(
  statusField({
    displayName: 'Certificate Status',
    options: CERTIFICATE_STATUSES,
    transitions: { issued: ['revoked'], revoked: [] },
  }),
);

class CertificateIsolated extends Component<typeof Certificate> {
  @tracked reason = '';
  @tracked busy = false;
  @tracked revoking = false;
  @tracked error: string | undefined;
  @tracked notice: string | undefined;
  get hue() {
    return statusHue(CertificateStatusField, this.args.model?.certStatus);
  }
  get canRevoke() {
    return (
      this.args.model?.certStatus !== 'revoked' &&
      !!this.args.context?.commandContext
    );
  }
  get issuedYear() {
    let d = this.args.model?.issuedAt;
    return d ? String(toDate(d)!.getFullYear()) : '';
  }
  setReason = (v: string) => (this.reason = v);
  toggleRevoke = () => (this.revoking = !this.revoking);
  copyVerify = async () => {
    let url = this.args.model?.verifyUrl;
    if (!url) return;
    try {
      await navigator.clipboard.writeText(url);
      this.notice = 'Verify link copied.';
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    }
  };
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
      this.revoking = false;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  <template>
    <IsoFrame>
      <Sheet
        @mark='Ce'
        @title={{if @model.number @model.number 'Unnumbered'}}
        @meta={{headline @model}}
      >
        <:status>
          <Dot @hue={{this.hue}}>{{lower @model.statusLabel}}</Dot>
          {{#if @model.finalLetter}}<Dot @hue='blue'>final
              {{@model.finalLetter}}</Dot>{{/if}}
        </:status>
        <:actions>
          {{#if @model.verifyUrl}}
            <Button
              @size='s'
              @tone='primary'
              @appearance='accent'
              {{on 'click' this.copyVerify}}
            >Copy verify link</Button>
          {{/if}}
          {{#if this.canRevoke}}
            <Button
              @size='s'
              @tone='neutral'
              @appearance='outlined'
              {{on 'click' this.toggleRevoke}}
            >Revoke</Button>
          {{/if}}
        </:actions>
        <:stats>
          <Stat
            @label='Final grade'
            @value={{@model.finalLetter}}
            @sub='final letter'
          />
          <Stat
            @label='Credit'
            @value={{hours @model.creditHours}}
            @sub={{@model.cohortName}}
          />
          <Stat
            @label='Issued'
            @value={{fmtShort @model.issuedAt}}
            @sub={{this.issuedYear}}
          />
        </:stats>
        <:main>
          {{#if this.revoking}}
            <Section @title='Revoke'>
              <div class='revoke'>
                <p class='hint'>Revocation keeps the number and prints the
                  reason on the record. It cannot be undone.</p>
                <div class='revoke-row'>
                  <Input
                    @value={{this.reason}}
                    @onInput={{this.setReason}}
                    @placeholder='Reason (required)'
                    aria-label='Revocation reason'
                  />
                  <Button
                    @size='s'
                    @tone='danger'
                    @appearance='accent'
                    @busy={{this.busy}}
                    @disabled={{or this.busy (not this.reason)}}
                    {{on 'click' this.revoke}}
                  >Revoke certificate</Button>
                </div>
              </div>
            </Section>
          {{/if}}
          {{#if this.error}}<div class='alert'><Alert
                @tone='danger'
              >{{this.error}}</Alert></div>{{/if}}
          {{#if this.notice}}<div class='alert'><Alert
                @tone='success'
              >{{this.notice}}</Alert></div>{{/if}}
          <Section @title='Certificate'>
            <Kv @label='Number' @mono={{true}}>{{dash @model.number}}</Kv>
            <Kv @label='Learner'>{{dash @model.learnerName}}</Kv>
            <Kv @label='Course'>{{dash @model.courseTitle}}</Kv>
            <Kv @label='Cohort'>{{dash @model.cohortName}}</Kv>
            <Kv @label='Final grade'>{{dash @model.finalLetter}}</Kv>
            <Kv @label='Credit hours' @mono={{true}}>{{dash
                @model.creditHours
              }}</Kv>
          </Section>
          <Section @title='Verification'>
            <Kv @label='Verify URL'>{{dash @model.verifyUrl}}</Kv>
            <Kv @label='Code' @mono={{true}}>{{dash
                @model.verificationCode
              }}</Kv>
            <Kv @label='Signatory'>{{signatory @model.authority}}</Kv>
            <Kv @label='Status'><Dot @hue={{this.hue}}>{{lower
                  @model.statusLabel
                }}</Dot></Kv>
            {{#if @model.revokedReason}}
              <Kv @label='Reason'>{{@model.revokedReason}}</Kv>
            {{/if}}
          </Section>
        </:main>
        <:side>
          <Section @title='Linked'>
            <Kv @label='Authority'>{{#if @model.authority}}<@fields.authority
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</Kv>
            <Kv @label='Issued by'>{{#if @model.issuedBy}}<@fields.issuedBy
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</Kv>
            {{#if @model.enrollment}}
              <Kv @label='Enrollment'><@fields.enrollment
                  @format='atom'
                  @displayContainer={{false}}
                /></Kv>
            {{/if}}
          </Section>
          <Section @title='Details'>
            <Kv @label='Learner'>{{dash @model.learnerName}}</Kv>
            <Kv @label='Course'>{{dash @model.courseTitle}}</Kv>
            <Kv @label='Cohort'>{{dash @model.cohortName}}</Kv>
            <Kv @label='Final'>{{dash @model.finalLetter}}</Kv>
            <Kv @label='Credit' @mono={{true}}>{{hoursLong
                @model.creditHours
              }}</Kv>
            <Kv @label='Issued' @mono={{true}}>{{fmtDate @model.issuedAt}}</Kv>
            <Kv @label='Revoked' @mono={{true}}>{{fmtDate
                @model.revokedAt
              }}</Kv>
          </Section>
        </:side>
      </Sheet>
    </IsoFrame>
    <style scoped>
      .revoke {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: 0 var(--boxel-sp-sm) var(--boxel-sp-xs);
      }
      .hint {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .revoke-row {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        gap: var(--boxel-sp-xs);
        align-items: center;
      }
      .alert {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm) 0;
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
      <Embed
        @mark='Ce'
        @title={{if @model.number @model.number 'Certificate'}}
        @meta={{headline @model}}
      >
        <:status>
          <Dot @hue={{this.hue}}>{{lower @model.statusLabel}}</Dot>
          {{#if @model.finalLetter}}<Dot @hue='blue'>final
              {{@model.finalLetter}}</Dot>{{/if}}
        </:status>
        <:fact>Issued
          <strong>{{fmtDate @model.issuedAt}}</strong>
          ·
          {{creditLine @model.creditHours}}</:fact>
        <:default>
          <Kv @label='Learner'>{{dash @model.learnerName}}</Kv>
          <Kv @label='Course'>{{dash @model.courseTitle}}</Kv>
          <Kv @label='Cohort'>{{dash @model.cohortName}}</Kv>
          <Kv @label='Final'>{{dash @model.finalLetter}}</Kv>
          <Kv @label='Credit' @mono={{true}}>{{hoursLong
              @model.creditHours
            }}</Kv>
          <Kv @label='Issued' @mono={{true}}>{{fmtDate @model.issuedAt}}</Kv>
          <Kv @label='Authority'>{{#if @model.authority}}<@fields.authority
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
          <Kv @label='Issued by'>{{#if @model.issuedBy}}<@fields.issuedBy
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
        </:default>
      </Embed>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return statusHue(CertificateStatusField, this.args.model?.certStatus);
    }
    <template>
      <AtomChip
        @mark='Ce'
        @title={{if @model.number @model.number 'Certificate'}}
      ><Dot @hue={{this.hue}}>{{lower @model.statusLabel}}</Dot></AtomChip>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(CertificateStatusField, this.args.model?.certStatus);
    }
    <template>
      <RichFittedCard>
        <:avatar><Mark @text='Ce' /></:avatar>
        <:title>{{if @model.number @model.number 'Certificate'}}</:title>
        <:subtitle>{{headline @model}}</:subtitle>
        <:status><Dot @hue={{this.hue}}>{{lower
              @model.statusLabel
            }}</Dot></:status>
        <:fact>Issued
          {{fmtDate @model.issuedAt}}
          ·
          {{creditLine @model.creditHours}}</:fact>
        <:relations>{{#if @model.authority}}<@fields.authority
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}{{#if @model.issuedBy}}<@fields.issuedBy
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </RichFittedCard>
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

function or(...v: unknown[]) {
  return v.some(Boolean);
}
function not(v: unknown) {
  return !v;
}

function fmtDate(d?: Date | string | null): string {
  if (!d) return '—';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}
function fmtShort(d?: Date | string | null): string {
  if (!d) return '';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  });
}
function headline(m?: Partial<Certificate> | null): string {
  return [m?.learnerName, m?.courseTitle].filter(Boolean).join(' · ');
}
function signatory(a?: CertificationAuthority | null): string {
  let parts = [a?.signatoryName, a?.signatoryTitle].filter(Boolean);
  return parts.length ? parts.join(', ') : '—';
}
function hours(n?: number | null): string {
  return n == null ? '' : `${n} h`;
}
function hoursLong(n?: number | null): string {
  return n == null ? '—' : `${n} ${n === 1 ? 'hour' : 'hours'}`;
}
function creditLine(n?: number | null): string {
  return n == null ? '' : `${n} credit ${n === 1 ? 'hour' : 'hours'}`;
}
function dash(v: unknown): string {
  return v == null || v === '' ? '—' : String(v);
}
function lower(v?: string | null) {
  return (v ?? '').toLowerCase();
}

export default Certificate;
