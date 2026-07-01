import GlimmerComponent from '@glimmer/component';
import { resource, use } from 'ember-resources';
import { TrackedObject } from 'tracked-built-ins';

import { loadCardDef, type Loader } from '@cardstack/runtime-common';
import {
  getFields,
  type BaseDef,
  type BaseDefConstructor,
  type Field,
} from 'https://cardstack.com/base/card-api';
import type { Spec } from 'https://cardstack.com/base/spec';

interface FieldRow {
  name: string;
  typeLabel: string;
}

interface Signature {
  Args: {
    spec: Spec;
  };
  Element: HTMLElement;
}

// Modules served through the realm Loader get `import.meta.loader` set on
// them (see the same trick in base/spec.gts), so this only works for a
// module actually loaded through a realm — never in a plain unit test.
function myLoader(): Loader {
  // @ts-ignore
  return (import.meta as any).loader;
}

function typeLabel(field: Field<BaseDefConstructor>): string {
  let cardName = field.card?.displayName ?? 'Card';
  return field.fieldType === 'containsMany' || field.fieldType === 'linksToMany'
    ? `${cardName}[]`
    : cardName;
}

export default class SpecFieldsGrid extends GlimmerComponent<Signature> {
  @use private cardDefState = resource(() => {
    let state = new TrackedObject<{ value: typeof BaseDef | undefined }>({
      value: undefined,
    });
    let spec = this.args.spec;
    if (!spec?.ref || !spec?.id) {
      return state;
    }
    (async () => {
      try {
        state.value = await loadCardDef(spec.ref, {
          loader: myLoader(),
          relativeTo: spec.id,
        });
      } catch {
        state.value = undefined;
      }
    })();
    return state;
  });

  get fields(): FieldRow[] {
    let cardDef = this.cardDefState.value;
    if (!cardDef) {
      return [];
    }
    return Object.entries(getFields(cardDef, { includeComputeds: false }))
      .filter(([name]) => name !== 'id')
      .map(([name, field]) => ({ name, typeLabel: typeLabel(field) }));
  }

  <template>
    {{#if this.fields.length}}
      <div class='fields-grid' data-test-spec-fields-grid={{@spec.id}}>
        {{#each this.fields as |row|}}
          <div class='field-row'>
            <span class='field-name'>{{row.name}}</span>
            <span class='field-type'>{{row.typeLabel}}</span>
          </div>
        {{/each}}
      </div>
    {{/if}}

    <style scoped>
      .fields-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(11rem, 1fr));
        gap: 0.5rem;
      }
      .field-row {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 0.5rem;
        padding: 0.5rem 0.75rem;
        border: 1px solid var(--border, #e7e3d8);
        border-radius: 0.5rem;
        background: var(--card, #fff);
      }
      .field-name {
        font: 600 0.8125rem/1.3 var(--font-mono, 'IBM Plex Mono', monospace);
        color: var(--foreground, #16161c);
      }
      .field-type {
        font: 500 0.75rem/1.3 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #8a8578);
        white-space: nowrap;
      }
    </style>
  </template>
}
