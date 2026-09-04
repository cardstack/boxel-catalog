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
import SpecContainer from '../../../components/spec-container';
import SpecExampleCard from '../../../components/spec-example-card';

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
        {{! 2. With current location tracker }}
        <SpecExampleCard>
          <CodeSnippet @code={{withCurrentLocationFieldCode}} />
          <@fields.withCurrentLocation />
        </SpecExampleCard>
        {{! 3. With quick locations }}
        <SpecExampleCard>
          <CodeSnippet @code={{withQuickLocationsFieldCode}} />
          <@fields.withQuickLocations />
        </SpecExampleCard>
        {{! 4. Combined }}
        <SpecExampleCard>
          <CodeSnippet @code={{combinedFieldCode}} />
          <@fields.combined />
        </SpecExampleCard>
        {{! 5. Map picker variant }}
        <SpecExampleCard>
          <CodeSnippet @code={{mapPickerFieldCode}} />
          <@fields.mapPicker />
        </SpecExampleCard>
        {{! 6. Map picker with showCurrentLocation (using MapPickerOptions) }}
        <SpecExampleCard>
          <CodeSnippet @code={{mapPickerWithCurrentLocationFieldCode}} />
          <@fields.mapPickerWithCurrentLocation />
        </SpecExampleCard>
        {{! 7. Map picker with quickLocations (using MapPickerOptions) }}
        <SpecExampleCard>
          <CodeSnippet @code={{mapPickerWithQuickLocationsFieldCode}} />
          <@fields.mapPickerWithQuickLocations />
        </SpecExampleCard>
        {{! 8. Map picker with both addons (using MapPickerOptions) }}
        <SpecExampleCard>
          <CodeSnippet @code={{mapPickerWithAddonsFieldCode}} />
          <@fields.mapPickerWithAddons />
        </SpecExampleCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </SpecContainer>
  </template>
}

class GeoPointFieldSpecEdit extends Component<typeof GeoPointFieldSpec> {
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
        {{! 2. With current location tracker }}
        <SpecExampleCard>
          <CodeSnippet @code={{withCurrentLocationFieldCode}} />
          <@fields.withCurrentLocation @format='edit' />
        </SpecExampleCard>
        {{! 3. With quick locations }}
        <SpecExampleCard>
          <CodeSnippet @code={{withQuickLocationsFieldCode}} />
          <@fields.withQuickLocations @format='edit' />
        </SpecExampleCard>
        {{! 4. Combined }}
        <SpecExampleCard>
          <CodeSnippet @code={{combinedFieldCode}} />
          <@fields.combined @format='edit' />
        </SpecExampleCard>
        {{! 5. Map picker variant }}
        <SpecExampleCard>
          <CodeSnippet @code={{mapPickerFieldCode}} />
          <@fields.mapPicker @format='edit' />
        </SpecExampleCard>
        {{! 6. Map picker with showCurrentLocation (using MapPickerOptions) }}
        <SpecExampleCard>
          <CodeSnippet @code={{mapPickerWithCurrentLocationFieldCode}} />
          <@fields.mapPickerWithCurrentLocation @format='edit' />
        </SpecExampleCard>
        {{! 7. Map picker with quickLocations (using MapPickerOptions) }}
        <SpecExampleCard>
          <CodeSnippet @code={{mapPickerWithQuickLocationsFieldCode}} />
          <@fields.mapPickerWithQuickLocations @format='edit' />
        </SpecExampleCard>
        {{! 8. Map picker with both addons (using MapPickerOptions) }}
        <SpecExampleCard>
          <CodeSnippet @code={{mapPickerWithAddonsFieldCode}} />
          <@fields.mapPickerWithAddons @format='edit' />
        </SpecExampleCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </SpecContainer>
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
