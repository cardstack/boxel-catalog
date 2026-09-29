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
import DueDateField from '../due-date';
import CodeSnippet from '../../../components/code-snippet';
import FieldShowcase from '../../../components/field-showcase';
import FieldShowcaseCard from '../../../components/field-showcase-card';

const standardCode = `@field dueDate = contains(DueDateField);`;

class DueDateFieldSpecIsolated extends Component<typeof DueDateFieldSpec> {
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
          <@fields.upcoming />
          <@fields.upcoming @format='atom' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <@fields.overdue />
          <@fields.overdue @format='atom' />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

class DueDateFieldSpecEdit extends Component<typeof DueDateFieldSpec> {
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
          <@fields.upcoming @format='edit' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <@fields.overdue @format='edit' />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

export class DueDateFieldSpec extends Spec {
  static displayName = 'Due Date Field Spec';

  @field upcoming = contains(DueDateField);
  @field overdue = contains(DueDateField);

  static isolated = DueDateFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = DueDateFieldSpecEdit as unknown as typeof Spec.edit;
}
