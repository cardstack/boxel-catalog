import {
  Spec,
  SpecHeader,
  SpecReadmeSection,
  ExamplesWithInteractive,
  SpecModuleSection,
} from '@cardstack/base/spec';
import { field, contains, Component } from '@cardstack/base/card-api';
import CountField from '../count-field';
import CodeSnippet from '../../../components/code-snippet';
import FieldShowcase from '../../../components/field-showcase';
import FieldShowcaseCard from '../../../components/field-showcase-card';

const standardCode = `@field ticketsSold = contains(CountField);`;

class CountFieldSpecIsolated extends Component<typeof CountFieldSpec> {
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

class CountFieldSpecEdit extends Component<typeof CountFieldSpec> {
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

export class CountFieldSpec extends Spec {
  static displayName = 'Count Field Spec';

  @field standard = contains(CountField);

  static isolated = CountFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = CountFieldSpecEdit as unknown as typeof Spec.edit;
}
