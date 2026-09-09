import GlimmerComponent from '@glimmer/component';

interface Step {
  n: string;
  title: string;
  body: string;
}

const STEPS: Step[] = [
  {
    n: '01',
    title: 'Browse',
    body: 'Find a card, field, app, or theme the community already built.',
  },
  {
    n: '02',
    title: 'Remix',
    body: 'Fork the full source into your realm in one click — no setup.',
  },
  {
    n: '03',
    title: 'Make it yours',
    body: 'Edit anything in code or edit mode. It runs entirely in your realm.',
  },
  {
    n: '04',
    title: 'Ship',
    body: 'Point it at your own data and go. Share it back when it is good.',
  },
];

export default class StorefrontHowItWorks extends GlimmerComponent {
  steps = STEPS;

  get walkthroughGifUrl() {
    // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
    return new URL('../assets/remix-walkthrough.gif', import.meta.url).href;
  }

  <template>
    <section
      class='how'
      data-catalog-howitworks
      data-test-storefront-howitworks
    >
      <div class='how-inner'>
        <div class='how-head'>
          <div class='eyebrow'>How remixing works</div>
          <h2 class='how-title'>From someone else's work to
            <span class='accent'>yours</span>
            — in four steps.</h2>
        </div>

        <div class='how-body'>
          <div class='how-visual'>
            <div class='chrome'>
              <span class='chrome-dot red'></span>
              <span class='chrome-dot amber'></span>
              <span class='chrome-dot green'></span>
              <span class='chrome-label'>remix · demo</span>
            </div>
            <div class='visual-slot'>
              <img
                src={{this.walkthroughGifUrl}}
                alt='A screencast of remixing a card: browse, fork, edit, ship.'
                class='visual-gif'
              />
            </div>
          </div>

          <ol class='steps'>
            {{#each this.steps as |step|}}
              <li class='step'>
                <span class='step-n'>{{step.n}}</span>
                <div class='step-text'>
                  <span class='step-title'>{{step.title}}</span>
                  <p class='step-body'>{{step.body}}</p>
                </div>
              </li>
            {{/each}}
          </ol>
        </div>
      </div>
    </section>

    <style scoped>
      .how {
        border-top: 1px solid var(--border);
        border-bottom: 1px solid var(--border);
        background-color: color-mix(
          in oklch,
          var(--background) 94%,
          var(--card)
        );
      }
      .how-inner {
        max-width: 80rem;
        margin: 0 auto;
        padding: 3.5rem 2rem;
      }
      .eyebrow {
        font: 600 0.6875rem/1 var(--font-mono);
        letter-spacing: 0.16em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        margin-bottom: 0.75rem;
      }
      .how-title {
        margin: 0 0 2rem;
        max-width: 34rem;
        font: 700 2rem/1.1 var(--font-sans);
        letter-spacing: -0.03em;
        color: var(--foreground);
      }
      .accent {
        /* Text reads better a shade dimmer than the true, neon --primary
           brand color (#00ffba) — that hue is reserved for button fills. */
        color: var(--success-ink);
      }
      .how-body {
        display: grid;
        grid-template-columns: 1.1fr 1fr;
        gap: 2.5rem;
        align-items: center;
      }
      .how-visual {
        background-color: var(--card);
        color: var(--card-foreground);
        border-radius: 1rem;
        overflow: hidden;
        box-shadow: var(--shadow-md);
      }
      .chrome {
        display: flex;
        align-items: center;
        gap: 0.4375rem;
        padding: 0.75rem 0.875rem;
        border-bottom: 1px solid var(--border);
      }
      .chrome-dot {
        width: 0.625rem;
        height: 0.625rem;
        border-radius: 50%;
      }
      .chrome-dot.red {
        background-color: var(--destructive);
        color: var(--destructive-foreground);
      }
      .chrome-dot.amber {
        background-color: var(--warning);
        color: var(--warning-foreground);
      }
      .chrome-dot.green {
        background-color: var(--success);
        color: var(--success-foreground);
      }
      .chrome-label {
        margin-left: 0.5rem;
        font: 500 0.6875rem/1 var(--font-mono);
        color: var(--muted-foreground);
      }
      .visual-slot {
        aspect-ratio: 16 / 10;
        overflow: hidden;
        background-color: var(--muted);
        color: var(--muted-foreground);
      }
      .visual-gif {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .steps {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 1.25rem;
      }
      .step {
        display: flex;
        gap: 1rem;
        align-items: flex-start;
      }
      .step-n {
        flex-shrink: 0;
        font: 700 0.875rem/1.6 var(--font-mono);
        color: var(--success-ink);
      }
      .step-title {
        font: 700 1.0625rem/1.2 var(--font-sans);
        color: var(--foreground);
      }
      .step-body {
        margin: 0.25rem 0 0;
        font: 400 0.875rem/1.5 var(--font-sans);
        color: var(--muted-foreground);
      }

      @container (max-width: 56rem) {
        .how-body {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}
