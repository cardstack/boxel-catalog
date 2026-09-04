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
import RecurringPatternField from '../recurring-pattern';
import CodeSnippet from '../../../components/code-snippet';
import FieldUsageExampleContainer from '../../../components/field-usage-example-container';
import FieldExample from '../../../components/field-example';

const standardFieldCode = `@field standard = contains(RecurringPatternField);`;

class RecurringPatternFieldSpecIsolated extends Component<
  typeof RecurringPatternFieldSpec
> {
  <template>
    <FieldUsageExampleContainer>
      <SpecHeader @model={{@model}}>
        <:title><@fields.cardTitle /></:title>
        <:description><@fields.cardDescription /></:description>
      </SpecHeader>

      <SpecReadmeSection @model={{@model}} @context={{@context}}>
        <@fields.readMe />
      </SpecReadmeSection>

      <ExamplesWithInteractive>
        <FieldExample>
          <CodeSnippet @code={{standardFieldCode}} />
          <@fields.standard />
        </FieldExample>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldUsageExampleContainer>
  </template>
}

class RecurringPatternFieldSpecEdit extends Component<
  typeof RecurringPatternFieldSpec
> {
  <template>
    <FieldUsageExampleContainer>
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
        <FieldExample>
          <CodeSnippet @code={{standardFieldCode}} />
          <@fields.standard @format='edit' />
        </FieldExample>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldUsageExampleContainer>
  </template>
}

export class RecurringPatternFieldSpec extends Spec {
  static displayName = 'Recurring Pattern Field Spec';

  // Standard RecurringPatternField configuration
  @field standard = contains(RecurringPatternField);

  static isolated =
    RecurringPatternFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = RecurringPatternFieldSpecEdit as unknown as typeof Spec.edit;
}
