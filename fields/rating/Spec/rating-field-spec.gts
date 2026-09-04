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
import RatingField from '../rating';
import CodeSnippet from '../../../components/code-snippet';
import SpecContainer from '../../../components/spec-container';
import SpecExampleCard from '../../../components/spec-example-card';

const standardFieldCode = `@field standard = contains(RatingField);`;

class RatingFieldSpecIsolated extends Component<typeof RatingFieldSpec> {
  <template>
    <SpecContainer>
      <SpecHeader @model={{@model}}>
        <:title><@fields.cardTitle /></:title>
        <:description><@fields.cardDescription /></:description>
      </SpecHeader>

      <SpecReadmeSection @model={{@model}} @context={{@context}}>
        <@fields.readMe />
      </SpecReadmeSection>

      <ExamplesWithInteractive>
        <SpecExampleCard>
          <CodeSnippet @code={{standardFieldCode}} />
          <@fields.standard />
        </SpecExampleCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </SpecContainer>
  </template>
}

class RatingFieldSpecEdit extends Component<typeof RatingFieldSpec> {
  <template>
    <SpecContainer>
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
        <SpecExampleCard>
          <CodeSnippet @code={{standardFieldCode}} />
          <@fields.standard @format='edit' />
        </SpecExampleCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </SpecContainer>
  </template>
}

export class RatingFieldSpec extends Spec {
  static displayName = 'Rating Field Spec';

  // Standard RatingField configuration
  @field standard = contains(RatingField);

  static isolated = RatingFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = RatingFieldSpecEdit as unknown as typeof Spec.edit;
}
