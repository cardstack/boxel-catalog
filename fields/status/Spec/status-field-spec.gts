import {
  Spec,
  SpecHeader,
  SpecReadmeSection,
  ExamplesWithInteractive,
  SpecModuleSection,
} from 'https://cardstack.com/base/spec';
import {
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StatusField, { statusField } from '../status';
import CodeSnippet from '../../../components/code-snippet';

const standardCode = `@field status = contains(StatusField);`;

const lifecycleCode = `const TicketStatusField = statusField({
  displayName: 'Ticket Status',
  options: [
    { value: 'Open', hue: 'teal' },
    { value: 'Pending', hue: 'amber', holds: true },
    { value: 'Resolved', hue: 'green', terminal: true },
  ],
  transitions: {
    Open: ['Pending', 'Resolved'],
    Pending: ['Open', 'Resolved'],
    Resolved: ['Open'],
  },
});

@field status = contains(TicketStatusField);`;

export const TicketStatusField = statusField({
  displayName: 'Ticket Status',
  options: [
    { value: 'Open', hue: 'teal' },
    { value: 'Pending', hue: 'amber', holds: true },
    { value: 'Resolved', hue: 'green', terminal: true },
  ],
  transitions: {
    Open: ['Pending', 'Resolved'],
    Pending: ['Open', 'Resolved'],
    Resolved: ['Open'],
  },
});

class StatusFieldSpecIsolated extends Component<typeof StatusFieldSpec> {
  <template>
    <article class='container'>
      <SpecHeader @model={{@model}}>
        <:title><@fields.cardTitle /></:title>
        <:description><@fields.cardDescription /></:description>
      </SpecHeader>

      <SpecReadmeSection @model={{@model}} @context={{@context}}>
        <@fields.readMe />
      </SpecReadmeSection>

      <ExamplesWithInteractive>
        <article class='example-card'>
          <CodeSnippet @code={{standardCode}} />
          <@fields.standard />
        </article>
        <article class='example-card'>
          <CodeSnippet @code={{lifecycleCode}} />
          <@fields.lifecycle />
        </article>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </article>
    <style scoped>
      .container {
        --boxel-spec-background-color: #ebeaed;
        --boxel-spec-code-ref-background-color: #e2e2e2;
        --boxel-spec-code-ref-text-color: #646464;
        height: 100%;
        min-height: max-content;
        padding: var(--boxel-sp);
        background-color: var(--boxel-spec-background-color);
      }
      .example-card {
        border: var(--boxel-border);
        border-radius: var(--boxel-border-radius);
        background-color: var(--boxel-100);
        padding: var(--boxel-sp-xs);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}

class StatusFieldSpecEdit extends Component<typeof StatusFieldSpec> {
  <template>
    <article class='container'>
      <SpecHeader @model={{@model}} @isEditMode={{true}}>
        <:title><@fields.cardTitle /></:title>
        <:description><@fields.cardDescription /></:description>
      </SpecHeader>

      <SpecReadmeSection
        @model={{@model}}
        @context={{@context}}
        @isEditMode={{@canEdit}}
      >
        <@fields.readMe />
      </SpecReadmeSection>

      <ExamplesWithInteractive>
        <article class='example-card'>
          <CodeSnippet @code={{standardCode}} />
          <@fields.standard @format='edit' />
        </article>
        <article class='example-card'>
          <CodeSnippet @code={{lifecycleCode}} />
          <@fields.lifecycle @format='edit' />
        </article>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </article>
    <style scoped>
      .container {
        --boxel-spec-background-color: #ebeaed;
        --boxel-spec-code-ref-background-color: #e2e2e2;
        --boxel-spec-code-ref-text-color: #646464;
        height: 100%;
        min-height: max-content;
        padding: var(--boxel-sp);
        background-color: var(--boxel-spec-background-color);
      }
      .example-card {
        border: var(--boxel-border);
        border-radius: var(--boxel-border-radius);
        background-color: var(--boxel-100);
        padding: var(--boxel-sp-xs);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}

export class StatusFieldSpec extends Spec {
  static displayName = 'Status Field Spec';

  @field standard = contains(StatusField);
  @field lifecycle = contains(TicketStatusField);

  static isolated = StatusFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = StatusFieldSpecEdit as unknown as typeof Spec.edit;
}
