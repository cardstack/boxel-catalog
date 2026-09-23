import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { hash } from '@ember/helper';

import { EditSectionNav, type NavSection } from '@cardstack/catalog/components/edit-section-nav';

interface SectionSignature {
  Args: {
    id: string;
    title: string;
    hint?: string;
    /** Column count for the fields placed directly inside. Default 1. */
    cols?: 1 | 2 | 3 | 4;
    active?: string;
  };
  Blocks: { default: [] };
  Element: HTMLElement;
}

/** One task cluster of an edit form. Fields dropped inside flow into a `cols` grid. */
export class EditSection extends GlimmerComponent<SectionSignature> {
  get isFocused() {
    return this.args.active === this.args.id;
  }
  <template>
    <section class='sect {{if this.isFocused "focused"}}' data-sect={{@id}} ...attributes>
      <h3>{{@title}}{{#if @hint}}<span class='sect-hint'>{{@hint}}</span>{{/if}}</h3>
      <div class='body cols-{{if @cols @cols 1}}'>{{yield}}</div>
    </section>
    <style scoped>
      .sect {
        --se-ink: var(--edit-section-nav-ink, var(--foreground, var(--boxel-dark)));
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
        padding: var(--boxel-sp);
        display: grid;
        gap: var(--boxel-sp-sm);
        background: var(--card, var(--boxel-light));
        transition: outline-color 160ms ease, box-shadow 160ms ease;
        outline: 2px solid transparent;
        outline-offset: 2px;
      }
      .sect.focused {
        outline-color: var(--se-ink);
        box-shadow: 0 0 0 4px color-mix(in oklab, var(--se-ink) 12%, transparent);
      }
      h3 {
        margin: 0;
        font-size: 0.8125rem;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground, var(--boxel-450));
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .sect-hint {
        text-transform: none;
        letter-spacing: normal;
        font-size: 0.75rem;
        font-weight: 400;
        font-style: italic;
      }
      .body {
        display: grid;
        gap: var(--boxel-sp-sm);
        align-items: start;
        min-width: 0;
      }
      .cols-2 {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .cols-3 {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }
      .cols-4 {
        grid-template-columns: repeat(4, minmax(0, 1fr));
      }
      @container edit (width < 640px) {
        .cols-2,
        .cols-3,
        .cols-4 {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

interface Signature {
  Args: {
    sections: NavSection[];
    /** Family ink for the rail and section halos; defaults to the theme foreground. */
    ink?: string;
    inkForeground?: string;
    ariaLabel?: string;
  };
  Blocks: {
    default: [{ Section: typeof EditSection; active: string | undefined }];
  };
  Element: HTMLElement;
}

/**
 * The grouped-edit scaffold for long edit forms: the root is the
 * scroller and the `edit` container, the shared
 * EditSectionNav sits sticky on the left, and each yielded Section carries
 * its own `data-sect` anchor, focused halo and field grid. Consumers only
 * decide the grouping — what belongs together and in what order — which is
 * the one decision a form should make per card.
 */
export class SectionedEdit extends GlimmerComponent<Signature> {
  @tracked active: string | undefined = this.args.sections[0]?.id;

  goTo = (id: string, event: Event) => {
    this.active = id;
    let root = (event.currentTarget as HTMLElement).closest('.sectioned-edit');
    root?.querySelector(`[data-sect='${id}']`)?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='sectioned-edit' ...attributes>
      <div class='edit-body'>
        <EditSectionNav
          @sections={{@sections}}
          @activeId={{this.active}}
          @onSelect={{this.goTo}}
          @ariaLabel={{@ariaLabel}}
          class='sect-nav'
        />
        <div class='sects'>
          {{yield (hash Section=(component EditSection active=this.active) active=this.active)}}
        </div>
      </div>
    </div>
    <style scoped>
      .sectioned-edit {
        container-type: inline-size;
        container-name: edit;
        height: 100%;
        overflow-y: auto;
        padding: var(--boxel-sp);
        background: var(--background, var(--boxel-light));
        color: var(--foreground, var(--boxel-dark));
      }
      .edit-body {
        display: grid;
        grid-template-columns: 9.5rem minmax(0, 1fr);
        align-items: start;
        gap: var(--boxel-sp);
      }
      .sect-nav {
        position: sticky;
        top: 0;
      }
      .sects {
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      @container edit (width < 640px) {
        .edit-body {
          grid-template-columns: 1fr;
        }
        .sect-nav {
          position: static;
          flex-direction: row;
          flex-wrap: wrap;
        }
        .sect-nav::before {
          display: none;
        }
      }
    </style>
  </template>
}

export default SectionedEdit;
