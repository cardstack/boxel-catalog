import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import enumField from '@cardstack/base/enum';

import MultiImageSourceField from '@cardstack/catalog/fields/multi-image-source/multi-image-source';

import { VISION_MODEL_OPTIONS } from './util/llm-request';
import { StudioIsolated } from './components/studio-isolated';
import { SculptedModel } from './sculpted-model';

export class ImgTo3dStudio extends CardDef {
  static displayName = 'Img-to-3D Generator';
  static prefersWideFormat = true;

  // all reference photos in one multi-image field: the first image is the
  // primary view, the rest are side / back / detail shots — every view feeds
  // the initial generation; thickness and hidden sides come from exactly these
  @field references = contains(MultiImageSourceField);
  // The studio is a workbench, not a store of results: every generation's
  // details (code file, name, analysis, critique, score) live on the
  // SculptedModel it produced. The studio only points at creations —
  // the viewport, name and analysis are all read from the SELECTED one, so
  // selecting a history version re-attaches that version's details wholesale.
  //
  // selectedCreation = what the iframe shows (moves when you pick a history
  // version); latestCreation = the newest saved round (history walk root and
  // round counter, only advances on new generations).
  @field selectedCreation = linksTo(() => SculptedModel);
  @field latestCreation = linksTo(() => SculptedModel);
  @field llmModel = contains(
    enumField(StringField, {
      options: VISION_MODEL_OPTIONS,
      displayName: 'Vision Model',
    }),
  );
  @field title = contains(StringField, {
    computeVia: function (this: ImgTo3dStudio) {
      return (
        this.selectedCreation?.objectName ||
        this.latestCreation?.objectName ||
        'Img-to-3D Studio'
      );
    },
  });

  // The working view is its own module: the card file says what a studio IS,
  // components/studio-isolated.gts is what the isolated view DOES.
  static isolated = StudioIsolated;

  static embedded = class Embedded extends Component<typeof ImgTo3dStudio> {
    get hasLinkedTheme() {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    <template>
      <article class='tile {{unless this.hasLinkedTheme "i3d-default-theme"}}'>
        <header class='tile-header'>
          <h3 class='tile-title'>{{@model.title}}</h3>
          {{#if @model.selectedCreation.codeFile.url}}
            <p class='tile-tag'>rebuilt in code</p>
          {{/if}}
        </header>
        {{#if @model.references.primaryUrl}}
          <img
            class='tile-image'
            src={{@model.references.primaryUrl}}
            alt='Reference for {{@model.title}}'
          />
        {{/if}}
        {{#if @model.latestCreation.round}}
          <p class='tile-meta'>round {{@model.latestCreation.round}}</p>
        {{/if}}
      </article>
      <style scoped>
        .tile {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          height: 100%;
          padding: 0.875rem;
          background: var(--i3d-bg, var(--background, #0a0b10));
          color: var(--i3d-text, var(--foreground, #eef0f6));
          font-family: var(
            --i3d-font-sans,
            var(
              --font-sans,
              -apple-system,
              BlinkMacSystemFont,
              'Segoe UI',
              Roboto,
              sans-serif
            )
          );
        }
        .tile-header {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 0.5rem;
        }
        .tile-title {
          margin: 0;
          font-size: 0.9375rem;
        }
        .tile-tag {
          margin: 0;
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.625rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--i3d-accent, var(--accent, #38e8ff));
          white-space: nowrap;
        }
        .tile-image {
          flex: 1;
          min-height: 0;
          width: 100%;
          object-fit: cover;
          border-radius: 0.5rem;
          border: 1px solid var(--i3d-border, var(--border, #232838));
        }
        .tile-meta {
          margin: 0;
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.6875rem;
          color: var(--i3d-text-dim, var(--muted-foreground, #9aa0b2));
        }
        .i3d-default-theme {
          --background: #2b303d;
          --foreground: #eef0f6;
          --muted-foreground: #9aa0b2;
          --accent: #38e8ff;
          --border: #232838;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ImgTo3dStudio> {
    get hasLinkedTheme() {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    <template>
      <article class='fit {{unless this.hasLinkedTheme "i3d-default-theme"}}'>
        {{#if @model.references.primaryUrl}}
          <img class='fit-image' src={{@model.references.primaryUrl}} alt='' />
        {{/if}}
        <div class='fit-info'>
          <h3 class='fit-title'>{{@model.title}}</h3>
          <p class='fit-tag'>img → 3d</p>
        </div>
      </article>
      <style scoped>
        .fit {
          display: flex;
          align-items: flex-start;
          gap: 0.625rem;
          height: 100%;
          padding: 0.625rem;
          overflow: hidden;
          background: var(--i3d-bg, var(--background, #0a0b10));
          color: var(--i3d-text, var(--foreground, #eef0f6));
          font-family: var(
            --i3d-font-sans,
            var(
              --font-sans,
              -apple-system,
              BlinkMacSystemFont,
              'Segoe UI',
              Roboto,
              sans-serif
            )
          );
        }
        .fit-image {
          width: 3rem;
          height: 3rem;
          flex-shrink: 0;
          object-fit: cover;
          border-radius: 0.375rem;
          border: 1px solid var(--i3d-border, var(--border, #232838));
        }
        .fit-info {
          min-width: 0;
        }
        .fit-title {
          margin: 0;
          font-size: 0.8125rem;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-tag {
          margin: 0.125rem 0 0;
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.625rem;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--i3d-accent, var(--accent, #38e8ff));
        }
        .i3d-default-theme {
          --background: #2b303d;
          --foreground: #eef0f6;
          --accent: #38e8ff;
          --border: #232838;
        }
        @container fitted-card (height <= 80px) {
          .fit {
            align-items: center;
          }
          .fit-image {
            width: 2rem;
            height: 2rem;
          }
        }
      </style>
    </template>
  };
}
