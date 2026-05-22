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

export function buildField<T>(
  FieldClass: new (attrs: Record<string, unknown>) => T,
  attrs: Record<string, unknown> = {},
): T {
  return new FieldClass(attrs);
}
