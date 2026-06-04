import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import ContactLinkField from './contact-link';

import {
  buildField,
  renderField,
} from '../../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | contact-link fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    const sampleContactLink = {
      label: 'Email',
      value: 'hello@example.com',
      url: 'mailto:hello@example.com',
    };

    test('contact-link field renders embedded view with url as a link', async function (assert) {
      await renderField(
        ContactLinkField,
        buildField(ContactLinkField, sampleContactLink),
      );

      assert
        .dom('[data-test-field-container] a')
        .exists('renders an anchor tag pointing to the contact url');
    });

    test('contact-link field renders atom view with url as a link', async function (assert) {
      await renderField(
        ContactLinkField,
        buildField(ContactLinkField, sampleContactLink),
        'atom',
      );

      assert
        .dom('[data-test-field-container] a')
        .exists('renders anchor in atom view');
    });

    test('contact-link field renders edit view with form controls', async function (assert) {
      await renderField(
        ContactLinkField,
        buildField(ContactLinkField, sampleContactLink),
        'edit',
      );

      assert.dom('[data-test-field-container]').exists('edit view renders');
    });

    test('contact-link field with no url renders nothing in embedded view', async function (assert) {
      await renderField(
        ContactLinkField,
        buildField(ContactLinkField, { label: 'Empty', value: '', url: '' }),
      );

      assert
        .dom('[data-test-field-container] a')
        .doesNotExist('no anchor rendered when url is empty');
    });
  });
}
