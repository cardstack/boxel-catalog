import GlimmerComponent from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import SignatureIcon from '@cardstack/boxel-icons/signature';
import CircleCheckIcon from '@cardstack/boxel-icons/circle-check';
import CircleXIcon from '@cardstack/boxel-icons/circle-x';

import {
  type SignatureBlockField,
  type CeremonyFinding,
  SIGNATURE_BLOCK_STATUS_HUE,
  signatureBlockStatusLabel,
  sortedBlocks,
  verifyCeremony,
  ceremonyIsClean,
  ceremonyState,
} from '../signature-block-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { formatMoney } from '@cardstack/catalog/cards/commerce/line-item-totals';
import type { Hue } from '@cardstack/catalog/components/state-pill';
import { Alert } from '@cardstack/pretui/components/alert';
import { Token } from '@cardstack/pretui/components/token';
import { ALERT_STYLE, ID_TOKEN_STYLE } from '../legal-ui';

interface Signature {
  Args: {
    blocks?: SignatureBlockField[] | null;
    /** The document's value — what every authority ceiling is checked against. */
    contractValue?: number | null;
    contractCurrency?: string | null;
    /** The document's type — what every signatory's remit is checked against. */
    contractType?: string | null;
    /** Heading over the strip. Defaults to "Signature ceremony". */
    title?: string;
    /** Hide the verdict footer (for a read-only summary in a list). */
    compact?: boolean;
  };
  Element: HTMLElement;
}

interface Line {
  block: SignatureBlockField;
  order: number;
  name: string;
  title: string;
  entity: string;
  role: string;
  status: string;
  hue: Hue;
  when?: string;
  authority?: string;
  authorityOk?: boolean;
  problems: string[];
}

function day(d?: Date | string | null): string | undefined {
  if (!d) return undefined;
  let t = new Date(d);
  if (!Number.isFinite(t.getTime())) return undefined;
  return t.toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

/**
 * Signature Block View (SB) — the ceremony as a document reader sees it.
 *
 * One card per signature line, in signing order, each carrying the party,
 * the signer, the authority ceiling with a pass/fail mark, and what has
 * happened. Below them, one line of verdict: either "all authority checks
 * pass" or the exact reasons they do not.
 *
 * Render-only. Every check is `verifyCeremony` from signature-block-field —
 * the same function Request Signature and Execute Contract run — so what the
 * screen says and what the commands enforce cannot disagree.
 *
 * The ceremony is deliberately slow-looking: document-grade type, no motion,
 * a full-width strip rather than a toast. Signing is the one irreversible
 * moment in a contract's life and should look like it.
 */
export class SignatureBlockView extends GlimmerComponent<Signature> {
  get findings(): CeremonyFinding[] {
    return verifyCeremony(
      this.args.blocks,
      this.args.contractValue,
      this.args.contractType,
    );
  }

  get clean(): boolean {
    return this.args.blocks?.length ? ceremonyIsClean(this.findings) : false;
  }

  get state() {
    return ceremonyState(this.args.blocks);
  }

  get valueLabel(): string | undefined {
    return formatMoney(
      this.args.contractValue ?? undefined,
      this.args.contractCurrency ?? undefined,
    );
  }

  get lines(): Line[] {
    let findings = this.findings;
    return sortedBlocks(this.args.blocks).map((b) => {
      let order = b.signingOrder ?? 0;
      let problems = findings
        .filter((f) => f.order === order && f.order !== 0)
        .map((f) => f.message);
      let s = b.signatory;
      let authority = s
        ? formatMoney(
            s.signatureAuthority?.amount,
            s.signatureAuthority?.currency?.code,
          )
        : undefined;
      let authorityOk = s
        ? s.canSign(this.args.contractValue, this.args.contractType).allowed
        : undefined;
      // Read the person through the link here, in a tracked getter, rather
      // than trusting the block's computed `displayName`: a FieldDef computed
      // is evaluated before a two-hop link (block → Signatory → Employee) has
      // resolved and is not re-run when it does; a Glimmer getter is.
      let personName: string | undefined;
      try {
        personName = s?.person?.name?.trim();
      } catch {
        personName = undefined;
      }
      let external = b.signerName?.trim();
      let name =
        personName ||
        external ||
        (s ? s.signingTitle?.trim() : '') ||
        'Signer not named';
      let title =
        personName || external
          ? s?.signingTitle?.trim() || b.signerTitle?.trim() || ''
          : '';
      return {
        block: b,
        order,
        name,
        title,
        entity: b.entityName || 'Party not set',
        role: b.party?.roleLabel ?? '',
        status: b.lineStatus ?? 'pending',
        hue: SIGNATURE_BLOCK_STATUS_HUE[b.lineStatus ?? 'pending'] ?? 'slate',
        when: day(b.signedAt ?? b.requestedAt),
        authority: authority || (s ? 'no authority recorded' : undefined),
        authorityOk,
        problems,
      };
    });
  }

  get countStyle() {
    return htmlSafe(`--cy-count: ${this.lines.length}`);
  }

  get globalFindings(): CeremonyFinding[] {
    return this.findings.filter((f) => f.order === 0);
  }

  get verdict(): string {
    if (!this.args.blocks?.length)
      return 'No signature blocks yet — add the signers on the contract before requesting signatures.';
    let n = this.findings.filter((f) => f.level === 'block').length;
    if (n === 0) {
      let v = this.valueLabel;
      return v
        ? `Document value ${v} — all authority checks pass.`
        : 'All authority checks pass.';
    }
    return `${n} ${n === 1 ? 'check fails' : 'checks fail'} — the document cannot be executed until each is cleared.`;
  }

  <template>
    <section
      class='ceremony state-{{this.state}}'
      style={{this.countStyle}}
      ...attributes
    >
      <header class='cy-head'>
        <SignatureIcon class='cy-icon' role='presentation' />
        <h3 class='cy-title'>{{if @title @title 'Signature ceremony'}}</h3>
        <StatePill
          @label={{this.state}}
          @hue={{if
            (eqs this.state 'complete')
            'green'
            (if
              (eqs this.state 'declined')
              'red'
              (if (eqs this.state 'in progress') 'amber' 'slate')
            )
          }}
          @dot={{true}}
        />
      </header>

      {{#if this.lines.length}}
        <ol class='cy-lines'>
          {{#each this.lines as |l index|}}
            <li
              class='cy-line is-{{l.status}}
                {{if l.problems.length "has-problem"}}'
              style={{lineDelay index}}
            >
              <div class='cl-party'>
                <span class='cl-order'>{{l.order}}.</span>
                <span class='cl-entity'>{{l.entity}}</span>
                {{#if l.role}}<span class='cl-role'>({{l.role}})</span>{{/if}}
              </div>
              <div class='cl-card'>
                <p class='cl-signer'>
                  <span class='cl-name'>{{l.name}}</span>{{~#if l.title}}<span
                      class='cl-title'
                    >, {{l.title}}</span>{{/if}}
                </p>
                {{#if l.authority}}
                  <p class='cl-auth {{if l.authorityOk "ok" "fail"}}'>
                    {{#if l.authorityOk}}
                      <CircleCheckIcon class='cl-mark' role='presentation' />
                    {{else}}
                      <CircleXIcon class='cl-mark' role='presentation' />
                    {{/if}}
                    authority
                    {{l.authority}}
                  </p>
                {{else}}
                  <p class='cl-auth external'>counterparty signer — authority
                    not ours to check</p>
                {{/if}}
                <p class='cl-status'>
                  <StatePill
                    @label={{signatureBlockStatusLabel l.status}}
                    @hue={{l.hue}}
                    @dot={{true}}
                    @emphatic={{eqs l.status 'signed'}}
                  />
                  {{#if l.when}}<span class='cl-when'>{{l.when}}</span>{{/if}}
                </p>
                {{#if l.block.signatureRef}}
                  <Token
                    class='cl-ref'
                    @value={{l.block.signatureRef}}
                    title={{l.block.signatureRef}}
                    style={{ID_TOKEN_STYLE.xs}}
                  />
                {{/if}}
                {{#if l.problems.length}}
                  <ul class='cl-problems'>
                    {{#each l.problems as |p|}}<li>{{p}}</li>{{/each}}
                  </ul>
                {{/if}}
              </div>
            </li>
          {{/each}}
        </ol>
      {{/if}}

      {{#unless @compact}}
        {{! A standing verdict, not an interruption: role='status' keeps a
            blocked ceremony from being announced as an alert on every render. }}
        <Alert
          class='cy-foot'
          role='status'
          @tone={{if this.clean 'success' 'danger'}}
          @title={{this.verdict}}
          style={{if this.clean ALERT_STYLE.success ALERT_STYLE.danger}}
        >
          {{#if (and this.globalFindings.length this.lines.length)}}
            <ul class='cy-global'>
              {{#each this.globalFindings as |f|}}<li
                >{{f.message}}</li>{{/each}}
            </ul>
          {{/if}}
        </Alert>
      {{/unless}}
    </section>
    <style scoped>
      .ceremony {
        /* The seal is the strip's one accent: the theme's primary, as ink. */
        --cy-seal: var(--primary-ink);
        display: flex;
        flex-direction: column;
        gap: 0.9rem;
        padding: 1rem 1.1rem 0.9rem;
        border: 1px solid var(--border);
        border-top: 0.1875rem solid var(--cy-seal);
        border-radius: var(--boxel-border-radius);
        background-color: var(--card);
        color: var(--card-foreground);
        container-type: inline-size;
      }
      .cy-head {
        display: flex;
        align-items: center;
        gap: 0.6rem;
      }
      .cy-icon {
        width: 1.125rem;
        height: 1.125rem;
        color: var(--cy-seal);
        flex: none;
      }
      .cy-title {
        margin: 0;
        flex: 1;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
      }
      .cy-lines {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
        gap: 0.9rem;
      }
      .cy-line {
        display: flex;
        flex-direction: column;
        gap: 0.35rem;
        min-width: 0;
        /* Lines rise onto the page in signing order — slow and deliberate, the
           pace of a document being passed down the table. Data carries the
           urgency; motion carries only the order. */
        animation: cy-rise 520ms cubic-bezier(0.2, 0.7, 0.2, 1) both;
        animation-delay: calc(120ms + var(--cy-i, 0) * 140ms);
      }
      @keyframes cy-rise {
        from {
          opacity: 0;
          transform: translateY(0.625rem);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      .cy-foot {
        animation: cy-seal-in 420ms cubic-bezier(0.2, 0.7, 0.2, 1) both;
        animation-delay: calc(260ms + var(--cy-count, 2) * 140ms);
      }
      @keyframes cy-seal-in {
        from {
          opacity: 0;
          transform: scale(0.985);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .cy-line,
        .cy-foot {
          animation: none;
        }
      }
      .cl-party {
        display: flex;
        align-items: baseline;
        gap: 0.4rem;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .cl-order {
        font-family: var(--font-mono);
        font-weight: 700;
      }
      .cl-entity {
        font-weight: 700;
        color: var(--foreground);
      }
      .cl-role {
        text-transform: none;
        letter-spacing: 0;
      }
      .cl-card {
        display: flex;
        flex-direction: column;
        gap: 0.3rem;
        padding: 0.7rem 0.8rem;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        background-color: var(--background);
        min-height: 6.5rem;
      }
      .cy-line.is-signed .cl-card {
        border-color: color-mix(in oklch, var(--success) 45%, var(--border));
      }
      .cy-line.has-problem .cl-card {
        border-color: color-mix(
          in oklch,
          var(--destructive) 55%,
          var(--border)
        );
        background-color: color-mix(
          in oklch,
          var(--destructive) 8%,
          var(--background)
        );
      }
      .cl-signer {
        font-family: var(--boxel-heading-font-family);
        margin: 0;
        font-size: 1.05rem;
        line-height: 1.3;
      }
      .cl-name {
        font-weight: 600;
      }
      .cl-title {
        color: var(--muted-foreground);
      }
      .cl-auth {
        margin: 0;
        display: flex;
        align-items: center;
        gap: 0.3rem;
        font-size: var(--boxel-font-size-xs);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .cl-auth.ok {
        color: var(--success-ink);
      }
      .cl-auth.fail {
        color: var(--destructive-ink);
        font-weight: 600;
      }
      .cl-auth.external {
        font-style: italic;
      }
      .cl-mark {
        width: 0.8125rem;
        height: 0.8125rem;
        flex: none;
      }
      .cl-status {
        margin: 0.1rem 0 0;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      /* Doubled class so the flush margin outranks Token's own. A long
         envelope id clips with an ellipsis; the title holds the full value. */
      .cl-ref.cl-ref {
        margin-inline: 0;
        align-self: flex-start;
        max-width: 100%;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .cl-problems {
        margin: 0.2rem 0 0;
        padding-left: 1rem;
        font-size: var(--boxel-font-size-xs);
        color: var(--destructive-ink);
        line-height: 1.45;
      }
      .cy-global {
        margin: 0;
        padding-left: 1rem;
        line-height: 1.45;
      }
      @container (max-width: 420px) {
        .cy-lines {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

function eqs(a?: string | null, b?: string) {
  return a === b;
}
function and(a: unknown, b: unknown) {
  return Boolean(a) && Boolean(b);
}

/** Per-line entrance delay, so the ceremony reads in signing order. */
function lineDelay(index: number) {
  return htmlSafe(`--cy-i: ${index}`);
}

export default SignatureBlockView;
