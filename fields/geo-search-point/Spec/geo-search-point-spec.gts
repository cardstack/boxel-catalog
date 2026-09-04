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
import GeoSearchPointField from '../geo-search-point';
import CodeSnippet from '../../../components/code-snippet';
import FieldUsageExampleContainer from '../../../components/field-usage-example-container';
import FieldExample from '../../../components/field-example';

// 1. Basic (no config)
const basicFieldCode = `@field basic = contains(GeoSearchPointField);`;

// 2. With top search results
const withTopResultsCode = `@field withTopResults = contains(GeoSearchPointField, {
  configuration: {
    options: {
      showTopSearchResults: true,
      topSearchResultsLimit: 5,
    },
  },
});`;

// 3. Top results without recent searches
const withoutRecentSearchesCode = `@field withoutRecentSearches = contains(GeoSearchPointField, {
  configuration: {
    options: {
      showTopSearchResults: true,
      topSearchResultsLimit: 5,
      showRecentSearches: false,
    },
  },
});`;

// 4. Combined: all features
const combinedCode = `@field combined = contains(GeoSearchPointField, {
  configuration: {
    options: {
      placeholder: 'Start typing an address...',
      showTopSearchResults: true,
      topSearchResultsLimit: 5,
      recentSearchesLimit: 5,
    },
  },
});`;

class GeoSearchPointFieldSpecIsolated extends Component<
  typeof GeoSearchPointFieldSpec
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
        {{! 1. Basic }}
        <FieldExample>
          <CodeSnippet @code={{basicFieldCode}} />
          <@fields.basic />
        </FieldExample>
        {{! 2. With top search results }}
        <FieldExample>
          <CodeSnippet @code={{withTopResultsCode}} />
          <@fields.withTopResults />
        </FieldExample>
        {{! 3. Top results without recent searches }}
        <FieldExample>
          <CodeSnippet @code={{withoutRecentSearchesCode}} />
          <@fields.withoutRecentSearches />
        </FieldExample>
        {{! 4. Combined }}
        <FieldExample>
          <CodeSnippet @code={{combinedCode}} />
          <@fields.combined />
        </FieldExample>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldUsageExampleContainer>
  </template>
}

class GeoSearchPointFieldSpecEdit extends Component<
  typeof GeoSearchPointFieldSpec
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
        {{! 1. Basic }}
        <FieldExample>
          <CodeSnippet @code={{basicFieldCode}} />
          <@fields.basic @format='edit' />
        </FieldExample>
        {{! 2. With top search results }}
        <FieldExample>
          <CodeSnippet @code={{withTopResultsCode}} />
          <@fields.withTopResults @format='edit' />
        </FieldExample>
        {{! 3. Top results without recent searches }}
        <FieldExample>
          <CodeSnippet @code={{withoutRecentSearchesCode}} />
          <@fields.withoutRecentSearches @format='edit' />
        </FieldExample>
        {{! 4. Combined }}
        <FieldExample>
          <CodeSnippet @code={{combinedCode}} />
          <@fields.combined @format='edit' />
        </FieldExample>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldUsageExampleContainer>
  </template>
}

export class GeoSearchPointFieldSpec extends Spec {
  static displayName = 'Geo Search Point Field Spec';

  // 1. Basic (no config)
  @field basic = contains(GeoSearchPointField);

  // 2. With top search results
  @field withTopResults = contains(GeoSearchPointField, {
    configuration: {
      options: {
        showTopSearchResults: true,
        topSearchResultsLimit: 5,
      },
    },
  });

  // 3. Top results without recent searches
  @field withoutRecentSearches = contains(GeoSearchPointField, {
    configuration: {
      options: {
        showTopSearchResults: true,
        topSearchResultsLimit: 5,
        showRecentSearches: false,
      },
    },
  });

  // 4. Combined: all features
  @field combined = contains(GeoSearchPointField, {
    configuration: {
      options: {
        placeholder: 'Start typing an address...',
        showTopSearchResults: true,
        topSearchResultsLimit: 5,
        recentSearchesLimit: 5,
      },
    },
  });

  static isolated =
    GeoSearchPointFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = GeoSearchPointFieldSpecEdit as unknown as typeof Spec.edit;
}
