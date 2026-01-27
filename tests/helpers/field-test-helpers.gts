import { getService } from '@universal-ember/test-support';

import type { Loader } from '@cardstack/runtime-common/loader';

import { field, contains, CardDef, Component } from './base-realm';
import { CatalogImageField, MultipleImageField } from './catalog-realm';
import { renderCard } from './render-component';

export type FieldFormat = 'embedded' | 'atom' | 'edit' | 'fitted';

/**
 * Gets the loader from the loader service.
 */
export function getLoader(): Loader {
  return getService('loader-service').loader;
}

/**
 * Renders a field with a given value in the specified format.
 * This creates a temporary TestCard with the field and renders it.
 *
 * @param FieldClass - The field class to render
 * @param value - The value to set on the field
 * @param format - The format to render (embedded, atom, edit, fitted)
 */
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

/**
 * Renders a field with configuration options.
 * This creates a temporary TestCard with the configured field and renders it.
 *
 * @param FieldClass - The field class to render
 * @param value - The value to set on the field
 * @param configuration - Configuration object with presentation and other options
 * @param fieldFormat - The format to render ('embedded', 'atom', 'edit', 'fitted')
 */
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

/**
 * Creates a new instance of a field class with the given attributes.
 *
 * @param FieldClass - The field class to instantiate
 * @param attrs - Attributes to pass to the field constructor
 * @returns A new instance of the field
 */
export function buildField<T>(
  FieldClass: new (attrs: Record<string, unknown>) => T,
  attrs: Record<string, unknown> = {},
): T {
  return new FieldClass(attrs);
}

/**
 * Creates an ImageField instance from raw data.
 * If the value has url or uploadUrl, creates a populated instance, otherwise empty.
 *
 * @param value - Raw image data with optional url/uploadUrl/imageUrl properties
 * @returns A CatalogImageField instance
 */
export function buildImageField(value: Record<string, unknown> = {}) {
  if (value.url || value.uploadUrl || value.imageUrl) {
    return new CatalogImageField(value);
  }
  return new CatalogImageField();
}

/**
 * Creates a MultipleImageField instance from raw data with nested images.
 *
 * @param value - Raw data with optional images array
 * @returns A MultipleImageField instance with nested CatalogImageField instances
 */
export function buildMultipleImageField(
  value: { images?: Record<string, unknown>[] } = {},
) {
  const multipleImageField = new MultipleImageField();
  if (value.images && Array.isArray(value.images)) {
    multipleImageField.images = value.images.map(
      (img) => new CatalogImageField(img),
    );
  }
  return multipleImageField;
}
