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
import FieldShowcase from '../../../components/field-showcase';
import FieldShowcaseCard from '../../../components/field-showcase-card';

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
    <FieldShowcase>
      <SpecHeader @model={{@model}}>
        <:title><@fields.cardTitle /></:title>
        <:description><@fields.cardDescription /></:description>
      </SpecHeader>

      <SpecReadmeSection @model={{@model}} @context={{@context}}>
        <@fields.readMe />
      </SpecReadmeSection>

      <ExamplesWithInteractive>
        <FieldShowcaseCard>
          <CodeSnippet @code={{standardCode}} />
          <@fields.standard />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{ticketCode}} />
          <@fields.ticket />
          <@fields.ticket @format='atom' />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

class PriorityFieldSpecEdit extends Component<typeof PriorityFieldSpec> {
  <template>
    <FieldShowcase>
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
        <FieldShowcaseCard>
          <CodeSnippet @code={{standardCode}} />
          <@fields.standard @format='edit' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{ticketCode}} />
          <@fields.ticket @format='edit' />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
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
