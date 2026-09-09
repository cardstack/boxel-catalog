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
import PriorityField, { priorityField } from '../priority';
import CodeSnippet from '../../../components/code-snippet';

const standardCode = `@field priority = contains(PriorityField);`;

const ticketCode = `const TicketPriorityField = priorityField({
  displayName: 'Ticket Priority',
  options: [
    { value: 'P1', hue: 'red', factor: 0.25 },
    { value: 'P2', hue: 'orange', factor: 0.5 },
    { value: 'P3', hue: 'amber', factor: 1 },
    { value: 'P4', hue: 'slate', factor: 2 },
  ],
});

@field priority = contains(TicketPriorityField);`;

export const TicketPriorityField = priorityField({
  displayName: 'Ticket Priority',
  options: [
    { value: 'P1', hue: 'red', factor: 0.25 },
    { value: 'P2', hue: 'orange', factor: 0.5 },
    { value: 'P3', hue: 'amber', factor: 1 },
    { value: 'P4', hue: 'slate', factor: 2 },
  ],
});

class PriorityFieldSpecIsolated extends Component<typeof PriorityFieldSpec> {
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
          <CodeSnippet @code={{ticketCode}} />
          <@fields.ticket />
          <@fields.ticket @format='atom' />
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

class PriorityFieldSpecEdit extends Component<typeof PriorityFieldSpec> {
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
          <CodeSnippet @code={{ticketCode}} />
          <@fields.ticket @format='edit' />
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

export class PriorityFieldSpec extends Spec {
  static displayName = 'Priority Field Spec';

  @field standard = contains(PriorityField);
  @field ticket = contains(TicketPriorityField);

  static isolated =
    PriorityFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = PriorityFieldSpecEdit as unknown as typeof Spec.edit;
}
