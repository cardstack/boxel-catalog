import {
  CardDef,
  Component,
  contains,
  field,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import StackIcon from '@cardstack/boxel-icons/stack';

import {
  EditSectionNav,
  type NavSection,
} from '../components/edit-section-nav';
import {
  CardFormats,
  DemoShell,
  SourceLink,
  cardInstancePath,
  cardSourcePath,
  scrollToSection,
} from './demo-parts';

interface CardEntry {
  id: string;
  card: CardDef;
  title: string;
  type: string;
  instancePath: string;
  sourcePath: string;
}

class GoldSpecCardGroupIsolated extends Component<typeof GoldSpecCardGroup> {
  @tracked active: string | undefined;

  get entries(): CardEntry[] {
    return (this.args.model.cards ?? []).filter(Boolean).map((card, i) => ({
      id: `card-${i}`,
      card,
      title: card.cardTitle ?? '',
      type: (card.constructor as typeof CardDef).displayName,
      instancePath: cardInstancePath(card),
      sourcePath: cardSourcePath(card),
    }));
  }

  get title(): string {
    return this.args.model.cardTitle ?? '';
  }

  get sections(): NavSection[] {
    return this.entries.map((e) => ({ id: e.id, label: e.type }));
  }

  get activeId(): string | undefined {
    return this.active ?? this.entries[0]?.id;
  }

  goTo = (id: string, event: Event) => {
    this.active = id;
    scrollToSection(id, event);
  };

  <template>
    <DemoShell
      @eyebrow='Gold Spec Demo · Cards'
      @title={{this.title}}
      @intro='One example of each card in this cluster, fitted at four sizes, embedded, atom and isolated. Each card shows its instance and its source file; click either to open it in code mode.'
    >
      <:nav>
        <div class='nav-group'>
          <span class='group-label'>Cards</span>
          <EditSectionNav
            @sections={{this.sections}}
            @activeId={{this.activeId}}
            @onSelect={{this.goTo}}
            @ariaLabel='Cards'
          />
        </div>
      </:nav>
      <:default>
        {{#each this.entries as |entry|}}
          <section
            class='block {{if (eq this.activeId entry.id) "is-active"}}'
            data-sect={{entry.id}}
            aria-labelledby='{{entry.id}}-heading'
          >
            <div class='card-head'>
              <h2 id='{{entry.id}}-heading'>{{entry.title}}</h2>
              <span class='card-type'>{{entry.type}}</span>
            </div>
            <dl class='paths'>
              <dt>Instance</dt>
              <dd><SourceLink
                  @path={{entry.instancePath}}
                  @context={{@context}}
                /></dd>
              <dt>Source</dt>
              <dd><SourceLink
                  @path={{entry.sourcePath}}
                  @context={{@context}}
                /></dd>
            </dl>
            <CardFormats @card={{entry.card}} />
          </section>
        {{/each}}
      </:default>
    </DemoShell>
    <style scoped>
      .card-head {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
      }
      .card-type {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .paths {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        align-items: baseline;
        gap: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        margin: 0;
      }
      .paths dt {
        font-size: var(--boxel-caption-font-size);
        line-height: var(--boxel-caption-line-height);
        color: var(--muted-foreground);
      }
      .paths dd {
        margin: 0;
        min-width: 0;
      }
    </style>
  </template>
}

/**
 * One cluster of cards for the Gold Spec Demo, such as CRM: a title and links
 * to one existing example of each card in the cluster. It is its own page, so
 * a cluster never touches the fields-and-components demo: adding one is a new
 * instance of this card, with no code change. The linked cards are shared
 * examples, so this page only renders them.
 */
export class GoldSpecCardGroup extends CardDef {
  static displayName = 'Gold Spec Card Group';
  static icon = StackIcon;

  @field title = contains(StringField);
  @field cards = linksToMany(CardDef);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: GoldSpecCardGroup) {
      return this.title?.trim()?.length
        ? this.title
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static isolated = GoldSpecCardGroupIsolated;
}

export default GoldSpecCardGroup;
