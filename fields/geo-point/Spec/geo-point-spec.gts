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
import FieldShowcase from '../../../components/field-showcase';
import FieldShowcaseCard from '../../../components/field-showcase-card';

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
        {{! 2. With current location tracker }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{withCurrentLocationFieldCode}} />
          <@fields.withCurrentLocation />
        </FieldShowcaseCard>
        {{! 3. With quick locations }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{withQuickLocationsFieldCode}} />
          <@fields.withQuickLocations />
        </FieldShowcaseCard>
        {{! 4. Combined }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{combinedFieldCode}} />
          <@fields.combined />
        </FieldShowcaseCard>
        {{! 5. Map picker variant }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{mapPickerFieldCode}} />
          <@fields.mapPicker />
        </FieldShowcaseCard>
        {{! 6. Map picker with showCurrentLocation (using MapPickerOptions) }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{mapPickerWithCurrentLocationFieldCode}} />
          <@fields.mapPickerWithCurrentLocation />
        </FieldShowcaseCard>
        {{! 7. Map picker with quickLocations (using MapPickerOptions) }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{mapPickerWithQuickLocationsFieldCode}} />
          <@fields.mapPickerWithQuickLocations />
        </FieldShowcaseCard>
        {{! 8. Map picker with both addons (using MapPickerOptions) }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{mapPickerWithAddonsFieldCode}} />
          <@fields.mapPickerWithAddons />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

class GeoPointFieldSpecEdit extends Component<typeof GeoPointFieldSpec> {
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
        {{! 2. With current location tracker }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{withCurrentLocationFieldCode}} />
          <@fields.withCurrentLocation @format='edit' />
        </FieldShowcaseCard>
        {{! 3. With quick locations }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{withQuickLocationsFieldCode}} />
          <@fields.withQuickLocations @format='edit' />
        </FieldShowcaseCard>
        {{! 4. Combined }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{combinedFieldCode}} />
          <@fields.combined @format='edit' />
        </FieldShowcaseCard>
        {{! 5. Map picker variant }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{mapPickerFieldCode}} />
          <@fields.mapPicker @format='edit' />
        </FieldShowcaseCard>
        {{! 6. Map picker with showCurrentLocation (using MapPickerOptions) }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{mapPickerWithCurrentLocationFieldCode}} />
          <@fields.mapPickerWithCurrentLocation @format='edit' />
        </FieldShowcaseCard>
        {{! 7. Map picker with quickLocations (using MapPickerOptions) }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{mapPickerWithQuickLocationsFieldCode}} />
          <@fields.mapPickerWithQuickLocations @format='edit' />
        </FieldShowcaseCard>
        {{! 8. Map picker with both addons (using MapPickerOptions) }}
        <FieldShowcaseCard>
          <CodeSnippet @code={{mapPickerWithAddonsFieldCode}} />
          <@fields.mapPickerWithAddons @format='edit' />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
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
