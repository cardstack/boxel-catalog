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
import FieldShowcase from '../../../components/field-showcase';
import FieldShowcaseCard from '../../../components/field-showcase-card';

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
          <CodeSnippet @code={{lifecycleCode}} />
          <@fields.lifecycle />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

class StatusFieldSpecEdit extends Component<typeof StatusFieldSpec> {
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
          <CodeSnippet @code={{lifecycleCode}} />
          <@fields.lifecycle @format='edit' />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

export class StatusFieldSpec extends Spec {
  static displayName = 'Status Field Spec';

  @field standard = contains(StatusField);
  @field lifecycle = contains(TicketStatusField);

  static isolated = StatusFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = StatusFieldSpecEdit as unknown as typeof Spec.edit;
}
