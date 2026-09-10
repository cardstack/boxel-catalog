import Component from '@glimmer/component';

export interface ValidationStep {
  id: string;
  title: string;
  message: string;
  status: 'complete' | 'incomplete';
}

interface ValidationStepsSignature {
  Args: {
    steps: ValidationStep[];
    title?: string;
    description?: string;
  };
  Element: HTMLElement;
  Blocks: {
    default: [ValidationStep];
  };
}

export default class ValidationSteps extends Component<ValidationStepsSignature> {
  <template>
    <section class='validation-content' ...attributes>
      <div class='validation-chip' aria-hidden='true'>
        <svg
          class='validation-chip__svg'
          viewBox='0 0 48 48'
          fill='none'
          xmlns='http://www.w3.org/2000/svg'
        >
          {{! Outer ring }}
          <circle
            cx='24'
            cy='24'
            r='22'
            stroke='var(--accent)'
            stroke-width='1.5'
          />
          {{! Inner circle fill }}
          <circle
            cx='24'
            cy='24'
            r='17'
            fill='var(--card)'
            stroke='var(--accent)'
            stroke-width='1'
          />
          {{! Chip segments — 8 notches around the rim }}
          <rect
            x='22.5'
            y='1'
            width='3'
            height='6'
            rx='1'
            fill='var(--accent)'
          />
          <rect
            x='22.5'
            y='41'
            width='3'
            height='6'
            rx='1'
            fill='var(--accent)'
          />
          <rect
            x='1'
            y='22.5'
            width='6'
            height='3'
            rx='1'
            fill='var(--accent)'
          />
          <rect
            x='41'
            y='22.5'
            width='6'
            height='3'
            rx='1'
            fill='var(--accent)'
          />
          <rect
            x='35.2'
            y='6.1'
            width='3'
            height='6'
            rx='1'
            fill='var(--accent)'
            transform='rotate(45 35.2 6.1)'
          />
          <rect
            x='6.1'
            y='35.2'
            width='3'
            height='6'
            rx='1'
            fill='var(--accent)'
            transform='rotate(45 6.1 35.2)'
          />
          <rect
            x='6.1'
            y='6.1'
            width='6'
            height='3'
            rx='1'
            fill='var(--accent)'
            transform='rotate(45 6.1 6.1)'
          />
          <rect
            x='35.2'
            y='35.2'
            width='6'
            height='3'
            rx='1'
            fill='var(--accent)'
            transform='rotate(45 35.2 35.2)'
          />
          {{! Card suit in centre }}
          <text
            x='24'
            y='29'
            text-anchor='middle'
            font-size='16'
            fill='var(--accent)'
            font-family='Georgia, serif'
          >♠</text>
        </svg>
      </div>
      <h2>{{@title}}</h2>
      {{#if @description}}
        <p class='validation-description'>{{@description}}</p>
      {{/if}}
      <div class='validation-steps'>
        {{#each @steps as |step|}}
          <div class='validation-step {{step.status}}' data-step-id={{step.id}}>
            <strong>{{step.title}}</strong>
            {{#if (has-block)}}
              {{yield step}}
            {{else}}
              <span class='validation-step__message'>{{step.message}}</span>
            {{/if}}
          </div>
        {{/each}}
      </div>
    </section>

    {{! template-lint-disable no-whitespace-for-layout }}
    <style scoped>
      /* Classic casino validation panel
         Parent can override three surface tokens:
           --validation-content-background  (default: near-black)
           --validation-content-foreground  (default: gold)
           --validation-content-max-width   (default: 520px)
      */
      .validation-content {
        --casino-gold-border: color-mix(
          in oklch,
          var(--accent) 60%,
          transparent
        );
        --casino-gold-border-dim: color-mix(
          in oklch,
          var(--accent) 20%,
          transparent
        );
        --casino-gold-dim: color-mix(in oklch, var(--accent) 55%, transparent);
        --casino-crimson-border: color-mix(
          in oklch,
          var(--destructive) 55%,
          transparent
        );
        --casino-emerald-border: color-mix(
          in oklch,
          var(--success) 45%,
          transparent
        );
        --casino-text: var(--warning-ink);
        --casino-text-muted: color-mix(
          in oklch,
          var(--warning-ink) 55%,
          transparent
        );
        --casino-font: 'Georgia', 'Times New Roman', serif;

        background-color: var(--card);
        color: var(--accent-ink);
        max-width: var(--validation-content-max-width, 32.5rem);

        border-radius: 0.25rem;
        padding: 2rem 2rem 1.75rem;
        width: 100%;
        position: relative;
        overflow: hidden;
        font-family: var(--casino-font);

        /* Outer gold frame — two stacked borders */
        box-shadow:
          0 0 0 1px var(--shadow-color),
          0 0 0 2px var(--casino-gold-border),
          0 0 0 3px var(--shadow-color),
          0 0 0 4px color-mix(in oklch, var(--accent) 25%, transparent),
          0 1rem 3rem color-mix(in oklch, var(--shadow-color) 80%, transparent);
        border: 1px solid var(--casino-gold-border);
      }

      /* Tight diamond crosshatch */
      .validation-content::before {
        content: '';
        position: absolute;
        inset: 0;
        opacity: 0.04;
        background-image:
          repeating-linear-gradient(
            45deg,
            var(--card) 0%,
            color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
          ),
          repeating-linear-gradient(
            var(--accent) 0%,
            color-mix(in oklch, var(--accent) 84%, var(--shadow-color)) 100%
          );
        pointer-events: none;
        z-index: 0;
      }

      .validation-content > * {
        position: relative;
        z-index: 1;
      }

      .validation-chip {
        display: flex;
        justify-content: center;
        margin-bottom: 0.75rem;
      }

      .validation-chip__svg {
        width: 3rem;
        height: 3rem;
        filter: drop-shadow(
          0 0 6px color-mix(in oklch, var(--accent) 35%, transparent)
        );
      }

      /* Title with flanking suit ornaments */
      .validation-content h2 {
        margin: 0 0 0.25rem;
        text-align: center;
        font-size: 1.375rem;
        font-weight: 700;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--accent-ink);
      }

      .validation-content h2::before {
        content: '♠  ';
        font-size: 0.9em;
        opacity: 0.75;
      }

      .validation-content h2::after {
        content: '  ♠';
        font-size: 0.9em;
        opacity: 0.75;
      }

      /* Thin gold rule below title */
      .validation-content .validation-rule {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        margin: 0.5rem 0 1rem;
      }

      .validation-description {
        text-align: center;
        margin: 0 0 1.25rem;
        font-size: 0.9rem;
        line-height: 1.5;
        color: var(--casino-text-muted);
        letter-spacing: 0.01em;
      }

      .validation-steps {
        display: flex;
        flex-direction: column;
        gap: 0.625rem;
      }

      .validation-step {
        font-size: 0.9rem;
        line-height: 1.5;
        padding: 0.875rem 1rem;
        border-radius: 0.1875rem;
        background-color: var(--card);
        color: var(--casino-text);
        border: 1px solid var(--casino-gold-border-dim);
        border-top: 2px solid var(--casino-gold-dim);
        position: relative;
        overflow: hidden;
        transition: border-top-color 0.15s ease;
      }

      .validation-step:hover {
        border-top-color: var(--casino-gold-border);
      }

      .validation-step.incomplete {
        background-color: var(--card);
        border-color: var(--casino-crimson-border);
        border-top-color: var(--destructive);
        color: var(--destructive-ink);
      }

      .validation-step.complete {
        background-color: var(--card);
        border-color: var(--casino-emerald-border);
        border-top-color: var(--success);
        color: var(--casino-text);
      }

      .validation-step strong {
        display: block;
        margin: 0 0 0.3rem;
        font-weight: 700;
        font-size: 0.875rem;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--accent-ink);
      }

      .validation-step__message {
        display: block;
        font-size: 0.875rem;
      }

      .validation-step.incomplete strong {
        color: var(--destructive-ink);
      }

      .validation-step.complete strong {
        color: var(--success-ink);
      }
    </style>
    {{! template-lint-enable no-whitespace-for-layout }}
  </template>
}
