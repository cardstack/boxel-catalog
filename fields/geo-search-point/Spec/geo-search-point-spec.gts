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
import FieldShowcase from '../../../components/field-showcase';
import FieldShowcaseCard from '../../../components/field-showcase-card';

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
    <FieldShowcase>
      <SpecHeader @model={{@model}}>
        <:title><@fields.cardTitle /></:title>
        <:description><@fields.cardDescription /></:description>
      </SpecHeader>

      <SpecReadmeSection @model={{@model}} @context={{@context}}>
        <@fields.readMe />
      </SpecReadmeSection>

      <ExamplesWithInteractive>
        {{! 1. Basic }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{basicFieldCode}} />
          <@fields.basic />
        </FieldShowcaseCard>
        {{! 2. With top search results }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{withTopResultsCode}} />
          <@fields.withTopResults />
        </FieldShowcaseCard>
        {{! 3. Top results without recent searches }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{withoutRecentSearchesCode}} />
          <@fields.withoutRecentSearches />
        </FieldShowcaseCard>
        {{! 4. Combined }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{combinedCode}} />
          <@fields.combined />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

class GeoSearchPointFieldSpecEdit extends Component<
  typeof GeoSearchPointFieldSpec
> {
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
        {{! 1. Basic }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{basicFieldCode}} />
          <@fields.basic @format='edit' />
        </FieldShowcaseCard>
        {{! 2. With top search results }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{withTopResultsCode}} />
          <@fields.withTopResults @format='edit' />
        </FieldShowcaseCard>
        {{! 3. Top results without recent searches }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{withoutRecentSearchesCode}} />
          <@fields.withoutRecentSearches @format='edit' />
        </FieldShowcaseCard>
        {{! 4. Combined }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{combinedCode}} />
          <@fields.combined @format='edit' />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
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
