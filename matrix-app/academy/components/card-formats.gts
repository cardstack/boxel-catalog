// Shared atom + embedded shells for the Academy cards, so every card reads
// the same: a type mark, a name that ellipsizes, chips that wrap clipped
// instead of half-cut (atom); a header, a key/value grid and a relations row
// (embedded). Fitted uses FitTile + FittedExtras directly in each card.
import Component from '@glimmer/component';
import { Avatar } from '../../../ui-component/components/avatar';

export interface FormatFact {
  key: string;
  value: string;
}

interface AtomSignature {
  Args: { mark: string; name?: string };
  Blocks: { default: [] };
  Element: HTMLSpanElement;
}

export class AcademyAtom extends Component<AtomSignature> {
  <template>
    <span class='ac-atom' ...attributes>
      <Avatar
        @name={{@mark}}
        @hue='var(--muted-foreground)'
        @size={{20}}
        aria-hidden='true'
      />
      <span class='ac-atom-name'>{{@name}}</span>
      <span class='ac-atom-chip'>{{yield}}</span>
    </span>
    <style scoped>
      @layer PretComponent {
        .ac-atom {
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
        .ac-atom-name {
          flex: 1 1 4rem;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .ac-atom-chip {
          flex: none;
        }
        .ac-atom-chip:empty {
          display: none;
        }
      }
    </style>
  </template>
}

interface EmbeddedSignature {
  Args: {
    mark: string;
    title?: string;
    subtitle?: string;
    facts?: FormatFact[];
  };
  Blocks: { chips: []; relations: [] };
  Element: HTMLElement;
}

export class AcademyEmbedded extends Component<EmbeddedSignature> {
  <template>
    <article class='ac-emb' ...attributes>
      <header class='ac-emb-head'>
        <Avatar
          @name={{@mark}}
          @hue='var(--muted-foreground)'
          @size={{40}}
          aria-hidden='true'
        />
        <div class='ac-emb-id'>
          <h4 class='ac-emb-title'>{{@title}}</h4>
          {{#if @subtitle}}<p class='ac-emb-sub'>{{@subtitle}}</p>{{/if}}
        </div>
        <div class='ac-emb-chips'>{{yield to='chips'}}</div>
      </header>
      {{#if @facts.length}}
        <dl class='ac-emb-kv'>
          {{#each @facts as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
      {{/if}}
      <div class='ac-emb-rels'>{{yield to='relations'}}</div>
    </article>
    <style scoped>
      @layer PretComponent {
        .ac-emb {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .ac-emb-head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .ac-emb-id {
          flex: 1 1 12rem;
          min-width: 0;
        }
        .ac-emb-title {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        .ac-emb-sub {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .ac-emb-chips {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .ac-emb-kv {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          margin: 0;
        }
        .ac-emb-kv dt {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .ac-emb-kv dd {
          margin: 0;
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .ac-emb-rels {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          color: var(--muted-foreground);
        }
        .ac-emb-rels:empty {
          display: none;
        }
      }
    </style>
  </template>
}

interface IsolatedSignature {
  Args: { mark: string; title?: string; subtitle?: string };
  Blocks: { chips: []; stats: []; main: []; side: [] };
  Element: HTMLElement;
}

// Isolated shell: header (mark, title, subtitle, chips), a stat row, then a
// wide main column beside a narrow side column. Same sizes in every card.
export class AcademyIsolated extends Component<IsolatedSignature> {
  <template>
    <article class='ac-iso' ...attributes>
      <header class='ac-iso-head'>
        <Avatar
          @name={{@mark}}
          @hue='var(--muted-foreground)'
          @size={{48}}
          aria-hidden='true'
        />
        <div class='ac-iso-id'>
          <h1>{{@title}}</h1>
          {{#if @subtitle}}<p class='ac-iso-sub'>{{@subtitle}}</p>{{/if}}
        </div>
        <div class='ac-iso-chips'>{{yield to='chips'}}</div>
      </header>
      <div class='ac-iso-stats'>{{yield to='stats'}}</div>
      <div class='ac-iso-body'>
        <div class='ac-iso-col'>{{yield to='main'}}</div>
        <div class='ac-iso-col'>{{yield to='side'}}</div>
      </div>
    </article>
    <style scoped>
      @layer PretComponent {
        .ac-iso {
          max-width: 60rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .ac-iso-head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp);
        }
        .ac-iso-id {
          flex: 1 1 14rem;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 600;
          line-height: 1.25;
        }
        .ac-iso-sub {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .ac-iso-chips {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .ac-iso-stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
          gap: var(--boxel-sp);
        }
        .ac-iso-stats:empty {
          display: none;
        }
        .ac-iso-body {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(16rem, 1fr);
          gap: var(--boxel-sp-lg);
          align-items: start;
        }
        .ac-iso-col {
          display: grid;
          gap: var(--boxel-sp-lg);
          min-width: 0;
        }
        @container (width <= 43.75rem) {
          .ac-iso-body {
            grid-template-columns: minmax(0, 1fr);
          }
        }
      }
    </style>
  </template>
}

interface PanelSignature {
  Args: { title: string };
  Blocks: { default: [] };
  Element: HTMLElement;
}

export class AcademyPanel extends Component<PanelSignature> {
  <template>
    <section class='ac-panel' ...attributes>
      <h2>{{@title}}</h2>
      {{yield}}
    </section>
    <style scoped>
      @layer PretComponent {
        .ac-panel {
          padding: var(--boxel-sp-lg);
          border-radius: var(--radius);
          background: var(--card);
          box-shadow: var(--shadow-sm);
          line-height: 1.6;
          min-width: 0;
        }
        h2 {
          margin: 0 0 var(--boxel-sp);
          font-size: var(--boxel-font-size);
          font-weight: 600;
        }
      }
    </style>
  </template>
}

interface RelsSignature {
  Blocks: { default: [] };
  Element: HTMLDListElement;
}

// A "Linked" list: each AcademyRel is a label plus the linked card's atom.
export class AcademyRels extends Component<RelsSignature> {
  <template>
    <dl class='ac-rels' ...attributes>{{yield}}</dl>
    <style scoped>
      @layer PretComponent {
        .ac-rels {
          margin: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
        }
      }
    </style>
  </template>
}

interface RelSignature {
  Args: { label: string };
  Blocks: { default: [] };
  Element: HTMLDivElement;
}

export class AcademyRel extends Component<RelSignature> {
  <template>
    <div class='ac-rel' ...attributes>
      <dt>{{@label}}</dt>
      <dd>{{yield}}</dd>
    </div>
    <style scoped>
      @layer PretComponent {
        .ac-rel {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        dt {
          min-width: 5.5rem;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        dd {
          margin: 0;
          min-width: 0;
        }
      }
    </style>
  </template>
}
