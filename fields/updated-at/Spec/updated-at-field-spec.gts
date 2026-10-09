import {
  Spec,
  SpecHeader,
  SpecReadmeSection,
  ExamplesWithInteractive,
  SpecModuleSection,
} from '@cardstack/base/spec';
import { field, contains, Component } from '@cardstack/base/card-api';
import UpdatedAtField from '../updated-at-field';
import CodeSnippet from '../../../components/code-snippet';
import FieldShowcase from '../../../components/field-showcase';
import FieldShowcaseCard from '../../../components/field-showcase-card';

const standardCode = `@field createdAt = contains(UpdatedAtField);`;

class UpdatedAtFieldSpecIsolated extends Component<typeof UpdatedAtFieldSpec> {
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
          <@fields.standard @format='atom' />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

class UpdatedAtFieldSpecEdit extends Component<typeof UpdatedAtFieldSpec> {
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
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

export class UpdatedAtFieldSpec extends Spec {
  static displayName = 'Updated At Field Spec';

  @field standard = contains(UpdatedAtField);

  static isolated =
    UpdatedAtFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = UpdatedAtFieldSpecEdit as unknown as typeof Spec.edit;
}
