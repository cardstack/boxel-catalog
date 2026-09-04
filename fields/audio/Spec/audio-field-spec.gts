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
import FieldShowcase from '../../../components/field-showcase';
import FieldShowcaseCard from '../../../components/field-showcase-card';

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
          <CodeSnippet @code={{standardFieldCode}} />
          <@fields.standard />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{waveformPlayerFieldCode}} />
          <@fields.waveformPlayer />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{playlistRowFieldCode}} />
          <@fields.playlistRow />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{miniPlayerFieldCode}} />
          <@fields.miniPlayer />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{albumCoverFieldCode}} />
          <@fields.albumCover />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{withVolumeFieldCode}} />
          <@fields.withVolume />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{trimEditorFieldCode}} />
          <@fields.trimEditor />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{advancedControlsFieldCode}} />
          <@fields.advancedControls />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
  </template>
}

class AudioFieldSpecEdit extends Component<typeof AudioFieldSpec> {
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
          <CodeSnippet @code={{standardFieldCode}} />
          <@fields.standard @format='edit' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{waveformPlayerFieldCode}} />
          <@fields.waveformPlayer @format='edit' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{playlistRowFieldCode}} />
          <@fields.playlistRow @format='edit' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{miniPlayerFieldCode}} />
          <@fields.miniPlayer @format='edit' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{albumCoverFieldCode}} />
          <@fields.albumCover @format='edit' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{withVolumeFieldCode}} />
          <@fields.withVolume @format='edit' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{trimEditorFieldCode}} />
          <@fields.trimEditor @format='edit' />
        </FieldShowcaseCard>
        <FieldShowcaseCard>
          <CodeSnippet @code={{advancedControlsFieldCode}} />
          <@fields.advancedControls @format='edit' />
        </FieldShowcaseCard>
      </ExamplesWithInteractive>

      <SpecModuleSection @model={{@model}} />
    </FieldShowcase>
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
