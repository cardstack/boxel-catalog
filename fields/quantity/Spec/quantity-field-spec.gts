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
import QuantityField from '../quantity';
import CodeSnippet from '../../../components/code-snippet';
import SpecContainer from '../../../components/spec-container';
import SpecExampleCard from '../../../components/spec-example-card';

const standardFieldCode = `@field standard = contains(QuantityField);`;

class QuantityFieldSpecIsolated extends Component<typeof QuantityFieldSpec> {
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

class QuantityFieldSpecEdit extends Component<typeof QuantityFieldSpec> {
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

export class QuantityFieldSpec extends Spec {
  static displayName = 'Quantity Field Spec';

  // Standard QuantityField configuration
  @field standard = contains(QuantityField);

  static isolated =
    QuantityFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = QuantityFieldSpecEdit as unknown as typeof Spec.edit;
}
