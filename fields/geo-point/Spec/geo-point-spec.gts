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
import GeoPointField from '../geo-point';
import CodeSnippet from '../../../components/code-snippet';
import FieldUsageExampleContainer from '../../../components/field-usage-example-container';
import FieldExample from '../../../components/field-example';

// 1. Basic standard (no config needed)
const basicFieldCode = `@field basic = contains(GeoPointField);`;

// 2. With current location tracker
const withCurrentLocationFieldCode = `@field withCurrentLocation = contains(GeoPointField, {
  configuration: {
    options: {
      showCurrentLocation: true,
    },
  },
});`;

// 3. With quick locations
const withQuickLocationsFieldCode = `@field withQuickLocations = contains(GeoPointField, {
  configuration: {
    options: {
      quickLocations: ['London', 'Paris', 'Tokyo', 'New York'],
    },
  },
});`;

// 4. Combined: current location + quick locations
const combinedFieldCode = `@field combined = contains(GeoPointField, {
  configuration: {
    options: {
      showCurrentLocation: true,
      quickLocations: ['London', 'Paris', 'Tokyo', 'New York'],
    },
  },
});`;

// 5. Map picker variant (no options)
const mapPickerFieldCode = `@field mapPicker = contains(GeoPointField, {
  configuration: {
    variant: 'map-picker',
  },
});`;

// 6. Map picker with showCurrentLocation (MapPickerOptions)
const mapPickerWithCurrentLocationFieldCode = `@field mapPickerWithCurrentLocation = contains(GeoPointField, {
  configuration: {
    variant: 'map-picker',
    options: {
      mapHeight: '300px',
      showCurrentLocation: true,
    },
  },
});`;

// 7. Map picker with quickLocations (MapPickerOptions)
const mapPickerWithQuickLocationsFieldCode = `@field mapPickerWithQuickLocations = contains(GeoPointField, {
  configuration: {
    variant: 'map-picker',
    options: {
      mapHeight: '300px',
      quickLocations: ['London', 'Paris', 'Tokyo', 'New York'],
    },
  },
});`;

// 8. Map picker with both addons + map options (MapPickerOptions)
const mapPickerWithAddonsFieldCode = `@field mapPickerWithAddons = contains(GeoPointField, {
  configuration: {
    variant: 'map-picker',
    options: {
      tileserverUrl: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      mapHeight: '300px',
      showCurrentLocation: true,
      quickLocations: ['London', 'Paris', 'Tokyo', 'New York'],
    },
  },
});`;

class GeoPointFieldSpecIsolated extends Component<typeof GeoPointFieldSpec> {
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
        {{! 2. With current location tracker }}
        <FieldExample>
          <CodeSnippet @code={{withCurrentLocationFieldCode}} />
          <@fields.withCurrentLocation />
        </FieldExample>
        {{! 3. With quick locations }}
        <FieldExample>
          <CodeSnippet @code={{withQuickLocationsFieldCode}} />
          <@fields.withQuickLocations />
        </FieldExample>
        {{! 4. Combined }}
        <FieldExample>
          <CodeSnippet @code={{combinedFieldCode}} />
          <@fields.combined />
        </FieldExample>
        {{! 5. Map picker variant }}
        <FieldExample>
          <CodeSnippet @code={{mapPickerFieldCode}} />
          <@fields.mapPicker />
        </FieldExample>
        {{! 6. Map picker with showCurrentLocation (using MapPickerOptions) }}
        <FieldExample>
          <CodeSnippet @code={{mapPickerWithCurrentLocationFieldCode}} />
          <@fields.mapPickerWithCurrentLocation />
        </FieldExample>
        {{! 7. Map picker with quickLocations (using MapPickerOptions) }}
        <FieldExample>
          <CodeSnippet @code={{mapPickerWithQuickLocationsFieldCode}} />
          <@fields.mapPickerWithQuickLocations />
        </FieldExample>
        {{! 8. Map picker with both addons (using MapPickerOptions) }}
        <FieldExample>
          <CodeSnippet @code={{mapPickerWithAddonsFieldCode}} />
          <@fields.mapPickerWithAddons />
        </FieldExample>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldUsageExampleContainer>
  </template>
}

class GeoPointFieldSpecEdit extends Component<typeof GeoPointFieldSpec> {
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
        {{! 2. With current location tracker }}
        <FieldExample>
          <CodeSnippet @code={{withCurrentLocationFieldCode}} />
          <@fields.withCurrentLocation @format='edit' />
        </FieldExample>
        {{! 3. With quick locations }}
        <FieldExample>
          <CodeSnippet @code={{withQuickLocationsFieldCode}} />
          <@fields.withQuickLocations @format='edit' />
        </FieldExample>
        {{! 4. Combined }}
        <FieldExample>
          <CodeSnippet @code={{combinedFieldCode}} />
          <@fields.combined @format='edit' />
        </FieldExample>
        {{! 5. Map picker variant }}
        <FieldExample>
          <CodeSnippet @code={{mapPickerFieldCode}} />
          <@fields.mapPicker @format='edit' />
        </FieldExample>
        {{! 6. Map picker with showCurrentLocation (using MapPickerOptions) }}
        <FieldExample>
          <CodeSnippet @code={{mapPickerWithCurrentLocationFieldCode}} />
          <@fields.mapPickerWithCurrentLocation @format='edit' />
        </FieldExample>
        {{! 7. Map picker with quickLocations (using MapPickerOptions) }}
        <FieldExample>
          <CodeSnippet @code={{mapPickerWithQuickLocationsFieldCode}} />
          <@fields.mapPickerWithQuickLocations @format='edit' />
        </FieldExample>
        {{! 8. Map picker with both addons (using MapPickerOptions) }}
        <FieldExample>
          <CodeSnippet @code={{mapPickerWithAddonsFieldCode}} />
          <@fields.mapPickerWithAddons @format='edit' />
        </FieldExample>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldUsageExampleContainer>
  </template>
}

export class GeoPointFieldSpec extends Spec {
  static displayName = 'Geo Point Field Spec';

  // 1. Basic standard (no config)
  @field basic = contains(GeoPointField);

  // 2. With current location tracker
  @field withCurrentLocation = contains(GeoPointField, {
    configuration: {
      options: {
        showCurrentLocation: true,
      },
    },
  });

  // 3. With quick locations
  @field withQuickLocations = contains(GeoPointField, {
    configuration: {
      options: {
        quickLocations: ['London', 'Paris', 'Tokyo', 'New York'],
      },
    },
  });

  // 4. Combined: current location + quick locations
  @field combined = contains(GeoPointField, {
    configuration: {
      options: {
        showCurrentLocation: true,
        quickLocations: ['London', 'Paris', 'Tokyo', 'New York'],
      },
    },
  });

  // 5. Map picker variant (no options)
  @field mapPicker = contains(GeoPointField, {
    configuration: {
      variant: 'map-picker',
    },
  });

  // 6. Map picker with showCurrentLocation (using MapPickerOptions)
  @field mapPickerWithCurrentLocation = contains(GeoPointField, {
    configuration: {
      variant: 'map-picker',
      options: {
        mapHeight: '300px',
        showCurrentLocation: true,
      },
    },
  });

  // 7. Map picker with quickLocations (using MapPickerOptions)
  @field mapPickerWithQuickLocations = contains(GeoPointField, {
    configuration: {
      variant: 'map-picker',
      options: {
        mapHeight: '300px',
        quickLocations: ['London', 'Paris', 'Tokyo', 'New York'],
      },
    },
  });

  // 8. Map picker with both addons + map options (using MapPickerOptions)
  @field mapPickerWithAddons = contains(GeoPointField, {
    configuration: {
      variant: 'map-picker',
      options: {
        tileserverUrl:
          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
        mapHeight: '300px',
        showCurrentLocation: true,
        quickLocations: ['London', 'Paris', 'Tokyo', 'New York'],
      },
    },
  });

  static isolated =
    GeoPointFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = GeoPointFieldSpecEdit as unknown as typeof Spec.edit;
}
