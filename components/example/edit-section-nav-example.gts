import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import ListNumbersIcon from '@cardstack/boxel-icons/list-numbers';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';

import { EditSectionNav, type NavSection } from '../edit-section-nav';

export class EditSectionExample extends FieldDef {
  static displayName = 'Edit Section Example';

  @field sectionId = contains(StringField);
  @field label = contains(StringField);
  @field body = contains(TextAreaField);
}

class EditSectionNavExampleIsolated extends Component<
  typeof EditSectionNavExample
> {
  @tracked activeId: string | undefined;

  get sections(): NavSection[] {
    return (this.args.model?.sections ?? [])
      .filter((s) => s?.sectionId && s?.label)
      .map((s) => ({ id: s.sectionId!, label: s.label! }));
  }

  get currentId() {
    return this.activeId ?? this.sections[0]?.id;
  }

  // The consumer owns the active state and the scroll; the rail only reports
  // which stop was chosen.
  select = (id: string, event: Event) => {
    this.activeId = id;
    let root = (event.target as HTMLElement).closest('.nav-example');
    root
      ?.querySelector(`[data-section='${id}']`)
      ?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  };

  <template>
    <div class='nav-example'>
      <EditSectionNav
        class='rail'
        @sections={{this.sections}}
        @activeId={{this.currentId}}
        @onSelect={{this.select}}
        @ariaLabel='Contract sections'
      />
      <div class='form'>
        {{#each @model.sections as |section|}}
          <section
            class='section
              {{if (eq section.sectionId this.currentId) "active"}}'
            data-section={{section.sectionId}}
          >
            <h3>{{section.label}}</h3>
            <p>{{section.body}}</p>
          </section>
        {{/each}}
      </div>
    </div>
    <style scoped>
      .nav-example {
        display: grid;
        grid-template-columns: 9.5rem 1fr;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp);
        max-height: 32rem;
        overflow: auto;
      }
      .rail {
        position: sticky;
        top: 0;
        align-self: start;
      }
      .form {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .section {
        padding: var(--boxel-sp-sm);
        border-radius: var(--boxel-border-radius);
        outline: 1px solid var(--border, var(--boxel-200));
      }
      .section.active {
        outline: 2px solid var(--foreground, var(--boxel-dark));
      }
      h3 {
        margin: 0 0 var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-sm);
      }
      p {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground, var(--boxel-450));
      }
    </style>
  </template>
}

/**
 * A long edit form with five sections and the rail beside it. Choosing a stop
 * lights it, outlines the matching section and scrolls it into view.
 */
export class EditSectionNavExample extends CardDef {
  static displayName = 'Edit Section Nav Example';
  static icon = ListNumbersIcon;

  @field sections = containsMany(EditSectionExample);

  static isolated = EditSectionNavExampleIsolated;
}
