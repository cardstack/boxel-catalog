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
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: var(--boxel-font-size-2xs);
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      h1 {
        font-family: var(--boxel-heading-font-family, var(--font-sans));
        font-weight: 400;
        font-size: var(--boxel-font-size-2xl);
        line-height: 1;
        text-transform: uppercase;
      }
      .sub {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
