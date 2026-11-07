import Component from '@glimmer/component';

interface Signature {
  Args: { title: string; subtitle?: string };
  Element: HTMLElement;
}

// Eyebrow, Anton title and one grey line: the head of every tab.
export class PageHead extends Component<Signature> {
  <template>
    <header class='head' ...attributes>
      <p class='cap'>Revenue OS · Workspace</p>
      <h1>{{@title}}</h1>
      {{#if @subtitle}}<p class='sub'>{{@subtitle}}</p>{{/if}}
    </header>
    <style scoped>
      .head {
        display: grid;
        gap: var(--boxel-sp-xxs);
      }
      .cap {
        margin: 0;
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: 0.5625rem;
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      h1 {
        margin: 0;
        font-family: var(--boxel-heading-font-family, var(--font-sans));
        font-weight: 400;
        font-size: 2.5rem;
        line-height: 1;
        text-transform: uppercase;
      }
      .sub {
        margin: 0;
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
