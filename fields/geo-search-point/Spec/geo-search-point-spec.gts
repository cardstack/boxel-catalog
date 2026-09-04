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
import SpecContainer from '../../../components/spec-container';
import SpecExampleCard from '../../../components/spec-example-card';

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
    <SpecContainer>
      <SpecHeader @model={{@model}}>
        <:title><@fields.cardTitle /></:title>
        <:description><@fields.cardDescription /></:description>
      </SpecHeader>

      <SpecReadmeSection @model={{@model}} @context={{@context}}>
        <@fields.readMe />
      </SpecReadmeSection>

      <ExamplesWithInteractive>
        {{! 1. Basic }}
        <SpecExampleCard>
          <CodeSnippet @code={{basicFieldCode}} />
          <@fields.basic />
        </SpecExampleCard>
        {{! 2. With top search results }}
        <SpecExampleCard>
          <CodeSnippet @code={{withTopResultsCode}} />
          <@fields.withTopResults />
        </SpecExampleCard>
        {{! 3. Top results without recent searches }}
        <SpecExampleCard>
          <CodeSnippet @code={{withoutRecentSearchesCode}} />
          <@fields.withoutRecentSearches />
        </SpecExampleCard>
        {{! 4. Combined }}
        <SpecExampleCard>
          <CodeSnippet @code={{combinedCode}} />
          <@fields.combined />
        </SpecExampleCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </SpecContainer>
  </template>
}

class GeoSearchPointFieldSpecEdit extends Component<
  typeof GeoSearchPointFieldSpec
> {
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
        {{! 1. Basic }}
        <SpecExampleCard>
          <CodeSnippet @code={{basicFieldCode}} />
          <@fields.basic @format='edit' />
        </SpecExampleCard>
        {{! 2. With top search results }}
        <SpecExampleCard>
          <CodeSnippet @code={{withTopResultsCode}} />
          <@fields.withTopResults @format='edit' />
        </SpecExampleCard>
        {{! 3. Top results without recent searches }}
        <SpecExampleCard>
          <CodeSnippet @code={{withoutRecentSearchesCode}} />
          <@fields.withoutRecentSearches @format='edit' />
        </SpecExampleCard>
        {{! 4. Combined }}
        <SpecExampleCard>
          <CodeSnippet @code={{combinedCode}} />
          <@fields.combined @format='edit' />
        </SpecExampleCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </SpecContainer>
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
