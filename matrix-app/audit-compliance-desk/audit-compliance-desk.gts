import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';

import { Document } from '../audit/document';
import { CertificationAuthority } from '../audit/certification-authority';
import { FitTile } from '../shared/fit-tile';
import { AuditComplianceDeskIsolated } from './desk';

function initials(name?: string | null) {
  return (name ?? 'Audit Compliance')
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0])
    .join('')
    .toUpperCase();
}

/**
 * The compliance manager's desk: the live evidence register and the shared
 * audit vocabularies. It composes the audit blocks and owns only its chrome.
 * Programme, fieldwork and report arrive with their blocks; the side panel
 * says so rather than showing empty tabs.
 */
function counts(docs?: Document[] | null) {
  let all = (docs ?? []).filter(Boolean);
  let hashed = all.filter((d) => (d.contentHash ?? '').trim()).length;
  return {
    total: all.length,
    hashed,
    unhashed: all.length - hashed,
    superseding: all.filter((d) => d.supersedes).length,
    usable: all.length ? Math.round((hashed / all.length) * 100) : 0,
  };
}

export class AuditComplianceDesk extends CardDef {
  static displayName = 'Audit & Compliance Desk';
  static icon = ClipboardCheckIcon;
  static prefersWideFormat = true;

  @field organisation = contains(StringField);
  @field authority = linksTo(() => CertificationAuthority);
  // Query-backed so the embedded and fitted views can count without a live host.
  @field documents = linksToMany(() => Document, {
    query: { page: { size: 200 } },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AuditComplianceDesk) {
      return this.organisation
        ? `${this.organisation} — Audit & Compliance`
        : 'Audit & Compliance Desk';
    },
  });

  static isolated = AuditComplianceDeskIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get c() {
      return counts(this.args.model.documents);
    }
    <template>
      <article class='emb'>
        <header>
          <span class='mark' aria-hidden='true'>{{initials
              @model.organisation
            }}</span>
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>Evidence register and audit vocabulary</p>
          </div>
        </header>
        <p class='line'>{{this.c.usable}}% of documents usable as evidence</p>
        <dl class='kv'>
          <dt>State</dt>
          <dd class='state'><span class='dot'>{{this.c.total}}
              documents</span>{{#if this.c.unhashed}}<span
                class='dot warn'
              >{{this.c.unhashed}} unhashed</span>{{/if}}</dd>
          <dt>Organisation</dt>
          <dd>{{if @model.organisation @model.organisation '—'}}</dd>
          <dt>Documents</dt>
          <dd>{{this.c.total}}</dd>
          <dt>Hashed</dt>
          <dd>{{this.c.hashed}}</dd>
          <dt>Not yet hashed</dt>
          <dd>{{this.c.unhashed}}</dd>
          <dt>Superseding</dt>
          <dd>{{this.c.superseding}}</dd>
          <dt>Tabs</dt>
          <dd>Evidence · Vocabulary</dd>
          <dt>Authority</dt>
          <dd>{{#if @model.authority}}<@fields.authority
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</dd>
        </dl>
      </article>
      <style scoped>
        .emb {
          display: grid;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-family: var(--font-sans);
          font-size: 0.75rem;
          line-height: 1.4;
          background: var(--card);
          color: var(--card-foreground);
        }
        header {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
        }
        .mark {
          display: grid;
          place-items: center;
          flex: none;
          inline-size: 1.5rem;
          block-size: 1.5rem;
          border-radius: var(--radius);
          background: var(--muted);
          font: 600 0.5625rem/1 var(--font-mono);
        }
        .id {
          min-inline-size: 0;
        }
        h3 {
          margin: 0;
          font-size: 0.8125rem;
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .kv {
          display: grid;
          grid-template-columns: 8rem minmax(0, 1fr);
          margin: 0;
        }
        dt,
        dd {
          margin: 0;
          padding: var(--boxel-sp-4xs) 0;
          border-block-start: 1px solid var(--border);
        }
        dt {
          font: 600 0.5625rem/1.8 var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        dd {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          min-inline-size: 0;
        }
        .line {
          margin: 0;
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .state {
          font-weight: 600;
        }
        .dot::before {
          content: '';
          display: inline-block;
          inline-size: 0.4375rem;
          block-size: 0.4375rem;
          margin-inline-end: var(--boxel-sp-5xs);
          border-radius: 50%;
          background: var(--muted-foreground);
        }
        .warn::before {
          background: var(--warning);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'><span class='mark' aria-hidden='true'>{{initials
            @model.organisation
          }}</span><span class='name'>{{@model.cardTitle}}</span></span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          max-inline-size: 100%;
          font-size: 0.75rem;
          font-weight: 600;
        }
        .mark {
          flex: none;
          padding: 0 var(--boxel-sp-5xs);
          border-radius: var(--radius);
          background: var(--muted);
          font: 600 0.5625rem/1.6 var(--font-mono);
        }
        .name {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get c() {
      return counts(this.args.model.documents);
    }
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>{{initials
              @model.organisation
            }}</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Evidence register and audit vocabulary</:subtitle>
        <:fact>{{this.c.total}}
          documents ·
          {{this.c.unhashed}}
          unhashed ·
          {{this.c.usable}}% usable</:fact>
        <:relations>{{#if @model.authority}}<@fields.authority
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
      <style scoped>
        .mark {
          display: inline-grid;
          place-items: center;
          inline-size: 2rem;
          block-size: 2rem;
          border-radius: var(--radius);
          background: var(--muted);
          font: 600 0.625rem/1 var(--font-mono);
        }
      </style>
    </template>
  };
}

export default AuditComplianceDesk;
