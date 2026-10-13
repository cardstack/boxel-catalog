import GlimmerComponent from '@glimmer/component';

interface Signature {
  Args: {
    number?: string | null;
    learnerName?: string | null;
    courseTitle?: string | null;
    cohortName?: string | null;
    creditHours?: number | null;
    finalLetter?: string | null;
    issuedAt?: Date | string | null;
    authorityName?: string | null;
    signatoryName?: string | null;
    signatoryTitle?: string | null;
    sealUrl?: string | null;
    verificationCode?: string | null;
    verifyUrl?: string | null;
    revoked?: boolean;
  };
  Element: HTMLElement;
}

/**
 * The printable face of a certificate. Takes plain values (the Certificate
 * card's snapshots) so a preview can be rendered BEFORE issue — Issue
 * Certificate shows exactly this with the values it is about to write.
 * Landscape 4:3, generous margins, a real print stylesheet: the page prints
 * on one sheet with no chrome. Colours come from theme tokens, so a brand
 * Theme on the authority restyles every certificate.
 */
export class CertificateView extends GlimmerComponent<Signature> {
  get issued() {
    if (!this.args.issuedAt) return '';
    return new Date(this.args.issuedAt).toLocaleDateString(undefined, {
      month: 'long',
      day: 'numeric',
      year: 'numeric',
    });
  }

  <template>
    <section
      class='cert {{if @revoked "revoked"}}'
      aria-label='Certificate'
      ...attributes
    >
      <div class='frame'>
        <header class='head'>
          {{#if @sealUrl}}
            <img class='seal' src={{@sealUrl}} alt='' />
          {{else}}
            <span class='seal seal-empty' aria-hidden='true'>{{initial
                @authorityName
              }}</span>
          {{/if}}
          <span class='authority'>{{if
              @authorityName
              @authorityName
              'Certification authority'
            }}</span>
        </header>

        <p class='certifies'>This certifies that</p>
        <h2 class='name'>{{if @learnerName @learnerName 'Learner name'}}</h2>
        <p class='completed'>has successfully completed</p>
        <h3 class='course'>{{if @courseTitle @courseTitle 'Course title'}}</h3>
        <p class='detail'>
          {{#if @cohortName}}{{@cohortName}}{{/if}}
          {{#if @creditHours}}<span class='sep'>·</span>{{@creditHours}}
            credit hours{{/if}}
          {{#if @finalLetter}}<span class='sep'>·</span>Final grade
            {{@finalLetter}}{{/if}}
        </p>

        <footer class='foot'>
          <div class='sig'>
            <span class='sig-line'>{{if
                @signatoryName
                @signatoryName
                '—'
              }}</span>
            <span class='sig-title'>{{if
                @signatoryTitle
                @signatoryTitle
                'Signatory'
              }}</span>
          </div>
          <div class='meta'>
            <span class='num'>{{if @number @number 'UNNUMBERED'}}</span>
            <span class='date'>{{if
                this.issued
                this.issued
                'Not yet issued'
              }}</span>
            {{#if @verificationCode}}
              <span class='verify'>Verify
                {{#if @verifyUrl}}<a
                    href={{@verifyUrl}}
                    target='_blank'
                    rel='noopener noreferrer'
                  >{{@verificationCode}}</a>{{else}}{{@verificationCode}}{{/if}}
              </span>
            {{/if}}
          </div>
        </footer>
        {{#if @revoked}}<span
            class='stamp'
            aria-hidden='true'
          >Revoked</span>{{/if}}
      </div>
    </section>
    <style scoped>
      .cert {
        --cert-ink: var(--foreground);
        --cert-accent: var(--primary);
        --cert-paper: var(--card);
        --cert-rule: color-mix(
          in oklab,
          var(--cert-accent) 40%,
          var(--cert-paper)
        );
        container-type: inline-size;
        color: var(--cert-ink);
      }
      .frame {
        position: relative;
        aspect-ratio: 4 / 3;
        padding: clamp(1rem, 6cqi, 3rem);
        display: grid;
        grid-template-rows: auto 1fr auto auto auto auto 1fr auto;
        align-items: center;
        justify-items: center;
        text-align: center;
        background: var(--cert-paper);
        border: 1px solid var(--cert-rule);
        outline: 0.375rem solid var(--cert-paper);
        outline-offset: -12px;
        box-shadow: inset 0 0 0 0.4375rem var(--cert-rule);
        overflow: hidden;
      }
      .head {
        display: grid;
        justify-items: center;
        gap: var(--boxel-sp-xs);
      }
      .seal {
        width: clamp(2.5rem, 9cqi, 5rem);
        height: clamp(2.5rem, 9cqi, 5rem);
        border-radius: 50%;
        object-fit: cover;
      }
      .seal-empty {
        display: grid;
        place-items: center;
        background: color-mix(
          in oklab,
          var(--cert-accent) 14%,
          var(--cert-paper)
        );
        font-size: clamp(1rem, 4cqi, 2rem);
        font-weight: 700;
      }
      .authority {
        font-size: clamp(0.6rem, 2cqi, 0.85rem);
        text-transform: uppercase;
        letter-spacing: 0.18em;
        color: var(--muted-foreground);
      }
      .certifies,
      .completed {
        margin: 0;
        font-size: clamp(0.65rem, 2.2cqi, 0.95rem);
        color: var(--muted-foreground);
        font-style: italic;
      }
      .name {
        margin: 0;
        font-size: clamp(1.4rem, 7cqi, 3rem);
        font-weight: 700;
        line-height: 1.1;
        letter-spacing: -0.01em;
        padding-bottom: 0.15em;
        border-bottom: 2px solid var(--cert-rule);
      }
      .course {
        margin: 0;
        font-size: clamp(0.9rem, 3.6cqi, 1.5rem);
        font-weight: 600;
        line-height: 1.2;
        color: var(--primary-ink);
      }
      .detail {
        margin: 0;
        font-size: clamp(0.6rem, 2cqi, 0.9rem);
        color: var(--muted-foreground);
      }
      .sep {
        margin: 0 0.4em;
      }
      .foot {
        width: 100%;
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: var(--boxel-sp);
        text-align: start;
      }
      .sig {
        display: grid;
      }
      .sig-line {
        font-size: clamp(0.8rem, 2.6cqi, 1.1rem);
        font-weight: 500;
        padding-bottom: 0.125rem;
        border-bottom: 1px solid var(--cert-ink);
        min-width: 10ch;
      }
      .sig-title {
        font-size: clamp(0.55rem, 1.8cqi, 0.75rem);
        color: var(--muted-foreground);
      }
      .meta {
        display: grid;
        justify-items: end;
        gap: 0.125rem;
        text-align: end;
        font-size: clamp(0.55rem, 1.8cqi, 0.75rem);
        color: var(--muted-foreground);
      }
      .num {
        font-size: clamp(0.65rem, 2.2cqi, 0.9rem);
        font-weight: 600;
        font-family: var(--font-mono);
        letter-spacing: 0.06em;
        color: var(--cert-ink);
      }
      .verify a {
        color: var(--cert-accent);
        font-family: var(--font-mono);
        text-decoration: none;
      }
      .stamp {
        position: absolute;
        inset: 50% auto auto 50%;
        transform: translate(-50%, -50%) rotate(-18deg);
        padding: 0.2em 0.8em;
        border: 0.25rem solid var(--destructive);
        border-radius: 0.5rem;
        color: var(--destructive-ink);
        font-size: clamp(1.5rem, 9cqi, 4rem);
        font-weight: 800;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        opacity: 0.85;
      }
      .revoked .name,
      .revoked .course {
        opacity: 0.55;
      }
      @media print {
        .cert {
          break-inside: avoid;
        }
        .frame {
          box-shadow: inset 0 0 0 0.4375rem var(--cert-rule);
          -webkit-print-color-adjust: exact;
          print-color-adjust: exact;
        }
      }
    </style>
  </template>
}

function initial(name?: string | null) {
  return (name?.trim()?.[0] ?? 'A').toUpperCase();
}

export default CertificateView;
