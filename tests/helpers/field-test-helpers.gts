import { getService } from '@universal-ember/test-support';

import type { Loader } from '@cardstack/runtime-common';

import {
  field,
  contains,
  CardDef,
  Component,
} from '@cardstack/host/tests/helpers/base-realm';
import { renderCard } from '@cardstack/host/tests/helpers/render-component';

export type FieldFormat = 'embedded' | 'atom' | 'edit' | 'fitted';

export function getLoader(): Loader {
  return getService('loader-service').loader;
}

export async function renderField(
  FieldClass: any,
  value: unknown,
  format: FieldFormat = 'embedded',
) {
  const loader = getLoader();
  const fieldFormat = format;
  const fieldType = FieldClass;

  class TestCard extends CardDef {
    @field sample = contains(fieldType);

    static isolated = class Isolated extends Component<typeof this> {
      format: FieldFormat = fieldFormat;

      <template>
        <div data-test-field-container>
          <@fields.sample @format={{this.format}} />
        </div>
      </template>
    };
  }

  let card = new TestCard({ sample: value });
  await renderCard(loader, card, 'isolated');
}

export async function renderConfiguredField(
  FieldClass: any,
  value: unknown,
  configuration: Record<string, unknown> = {},
  fieldFormat: FieldFormat = 'embedded',
) {
  const loader = getLoader();
  const fieldType = FieldClass;

  class TestCard extends CardDef {
    @field sample = contains(fieldType, { configuration });

    static isolated = class Isolated extends Component<typeof this> {
      format: FieldFormat = fieldFormat;

      <template>
        <div data-test-field-container>
          <@fields.sample @format={{this.format}} />
        </div>
      </template>
    };
  }

  let card = new TestCard({ sample: value });
  await renderCard(loader, card, 'isolated');
}

// Build a value suitable to assign to a `contains(FieldClass)` field.
// Primitive-backed fields (e.g. NumberField subclasses) store the raw value,
// not an instance — for those, `{ value: X }` should yield `X` directly.
// Composite FieldDef / CardDef subclasses store an instance, so we forward
// the attrs to the constructor.
export function buildField<T>(
  FieldClass: new (attrs: Record<string, unknown>) => T,
  attrs: Record<string, unknown> = {},
): any {
  const keys = Object.keys(attrs);
  if (keys.length === 0) return undefined;
  if (keys.length === 1 && 'value' in attrs) return (attrs as any).value;
  return new FieldClass(attrs);
}
