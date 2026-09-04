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
import AudioField from '../audio';
import CodeSnippet from '../../../components/code-snippet';
import FieldUsageExampleContainer from '../../../components/field-usage-example-container';
import FieldExample from '../../../components/field-example';

const standardFieldCode = `@field standard = contains(AudioField);`;
const waveformPlayerFieldCode = `@field waveformPlayer = contains(AudioField, {
  configuration: {
    presentation: 'waveform-player',
  },
});`;
const playlistRowFieldCode = `@field playlistRow = contains(AudioField, {
  configuration: {
    presentation: 'playlist-row',
  },
});`;
const miniPlayerFieldCode = `@field miniPlayer = contains(AudioField, {
  configuration: {
    presentation: 'mini-player',
  },
});`;
const albumCoverFieldCode = `@field albumCover = contains(AudioField, {
  configuration: {
    presentation: 'album-cover',
  },
});`;
const withVolumeFieldCode = `@field withVolume = contains(AudioField, {
  configuration: {
    options: {
      showVolume: true,
    },
  },
});`;
const trimEditorFieldCode = `@field trimEditor = contains(AudioField, {
  configuration: {
    presentation: 'trim-editor',
  },
});`;
const advancedControlsFieldCode = `@field advancedControls = contains(AudioField, {
  configuration: {
    options: {
      showVolume: true,
      showSpeedControl: true,
      showLoopControl: true,
    },
  },
});`;

class AudioFieldSpecIsolated extends Component<typeof AudioFieldSpec> {
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
        <FieldExample>
          <CodeSnippet @code={{standardFieldCode}} />
          <@fields.standard />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{waveformPlayerFieldCode}} />
          <@fields.waveformPlayer />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{playlistRowFieldCode}} />
          <@fields.playlistRow />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{miniPlayerFieldCode}} />
          <@fields.miniPlayer />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{albumCoverFieldCode}} />
          <@fields.albumCover />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{withVolumeFieldCode}} />
          <@fields.withVolume />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{trimEditorFieldCode}} />
          <@fields.trimEditor />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{advancedControlsFieldCode}} />
          <@fields.advancedControls />
        </FieldExample>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldUsageExampleContainer>
  </template>
}

class AudioFieldSpecEdit extends Component<typeof AudioFieldSpec> {
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
        <FieldExample>
          <CodeSnippet @code={{standardFieldCode}} />
          <@fields.standard @format='edit' />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{waveformPlayerFieldCode}} />
          <@fields.waveformPlayer @format='edit' />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{playlistRowFieldCode}} />
          <@fields.playlistRow @format='edit' />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{miniPlayerFieldCode}} />
          <@fields.miniPlayer @format='edit' />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{albumCoverFieldCode}} />
          <@fields.albumCover @format='edit' />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{withVolumeFieldCode}} />
          <@fields.withVolume @format='edit' />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{trimEditorFieldCode}} />
          <@fields.trimEditor @format='edit' />
        </FieldExample>
        <FieldExample>
          <CodeSnippet @code={{advancedControlsFieldCode}} />
          <@fields.advancedControls @format='edit' />
        </FieldExample>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldUsageExampleContainer>
  </template>
}

export class AudioFieldSpec extends Spec {
  static displayName = 'Audio Field Spec';

  // Standard AudioField - default inline player
  @field standard = contains(AudioField, { searchable: 'file' });

  // Waveform player - SoundCloud-style waveform visualization
  @field waveformPlayer = contains(AudioField, {
    configuration: {
      presentation: 'waveform-player',
    },

    searchable: 'file',
  });

  // Playlist row - Spotify-style playlist row
  @field playlistRow = contains(AudioField, {
    configuration: {
      presentation: 'playlist-row',
    },

    searchable: 'file',
  });

  // Mini player - Podcast-style mini player
  @field miniPlayer = contains(AudioField, {
    configuration: {
      presentation: 'mini-player',
    },

    searchable: 'file',
  });

  // Album cover - Album cover presentation
  @field albumCover = contains(AudioField, {
    configuration: {
      presentation: 'album-cover',
    },

    searchable: 'file',
  });

  // With volume control
  @field withVolume = contains(AudioField, {
    configuration: {
      options: {
        showVolume: true,
      },
    },

    searchable: 'file',
  });

  // Trim editor - Audio trimming interface
  @field trimEditor = contains(AudioField, {
    configuration: {
      presentation: 'trim-editor',
    },

    searchable: 'file',
  });

  // Advanced controls - Volume, speed, and loop controls
  @field advancedControls = contains(AudioField, {
    configuration: {
      options: {
        showVolume: true,
        showSpeedControl: true,
        showLoopControl: true,
      },
    },

    searchable: 'file',
  });

  static isolated = AudioFieldSpecIsolated as unknown as typeof Spec.isolated;
  static edit = AudioFieldSpecEdit as unknown as typeof Spec.edit;
}
