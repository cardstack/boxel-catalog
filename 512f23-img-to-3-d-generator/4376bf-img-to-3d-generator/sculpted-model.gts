import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  ImageDef,
  FileDef,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import DatetimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';

import MultiImageSourceField from '@cardstack/catalog/fields/multi-image-source/multi-image-source';

import { generateViewerSrcdoc } from './util/code-export';
import { VISION_MODEL_OPTIONS } from './util/llm-request';

// One finished reconstruction: the reference it was built from, the generated
// three.js model file it produced, and its self-review. Every generation in
// the studio is saved as one of these, so each model is an independent,
// searchable, linkable card in the realm (mirroring the AiImage pattern).
//
// The model itself lives OUTSIDE the card as a realm .js file (real code,
// with the source spec embedded as a SCULPT_SPEC constant) — the card only
// links to it. Rendering goes through the shared exports/viewer.html
// harness, which any iframe can load.
export class SculptedModel extends CardDef {
  static displayName = 'Sculpted Model';

  // every reference view this build was made from — the same multi-image set
  // the studio holds, so selecting a saved round re-attaches all its views,
  // not just the primary photo
  @field references = contains(MultiImageSourceField);
  // the generated model .js — the model's stored form, with the source spec
  // riding inside it as its SCULPT_SPEC constant. A link (not a URL string) so
  // the realm serializes it relative to this card and resolves it against
  // whichever realm the card is served from; read `codeFile.url` for the
  // absolute URL the viewer harness and the file reader need.
  @field codeFile = linksTo(() => FileDef);
  @field objectName = contains(StringField);
  // backend the analysis recommended for this object ("primitive" | "mesh").
  // Provenance for a future mesh route — also lives inside `analysis`, surfaced
  // here for quick display/query. See prompts/analyze.gts BACKEND rule.
  @field buildBackend = contains(StringField);
  // stage-1 analysis JSON (object type, camera, per-part measured bboxes,
  // attachment constraints, _refSig) this build followed — kept on the
  // creation so selecting this version in the studio re-attaches its measured
  // targets and its reference signature drives the regenerate cache
  @field analysis = contains(StringField);
  @field critique = contains(StringField);
  @field score = contains(NumberField);
  // How well this round actually came out, as JSON: { residual, warnings[],
  // featureCheck{}, plannedParts, builtParts }. Every one of these was already
  // computed during the build and then thrown away with the session, which
  // left no way to tell a prompt improvement from a prompt regression —
  // keeping it on the round makes before/after a diff instead of a memory.
  @field buildMetrics = contains(StringField);
  // snapshot of the render at save time — the kept result is viewable as an
  // image (gallery tiles) without rebuilding the 3D scene
  @field renderScreenshot = linksTo(() => ImageDef);
  // history is a backward linked list: each round points at the round it
  // refined, so the studio only ever holds the latest card and older rounds
  // load on demand as you walk the chain
  @field parentCreation = linksTo(() => SculptedModel);
  // the ImgTo3dStudio card that produced this round — scopes the studio's
  // prerendered history search, which filters on `sourceStudio.id` (a link's
  // id is always in the search doc, so the hop needs no `searchable: true`).
  // A link rather than an id string so the stored form is realm-relative and
  // the listing stays portable across realms. Typed as CardDef because
  // img-to-3d-studio.gts imports this module — naming the studio class here
  // would close a module cycle — and only the link's id is ever read.
  @field sourceStudio = linksTo(() => CardDef);
  @field round = contains(NumberField);
  // bumped every time this round's .js is edited IN PLACE (the AI Refine
  // command). The studio folds it into the viewport iframe's cache-bust key,
  // so an external in-place edit forces a re-fetch of the same-url file instead
  // of showing the stale cached render.
  @field revision = contains(NumberField);
  @field modelUsed = contains(
    enumField(StringField, {
      options: VISION_MODEL_OPTIONS,
      displayName: 'Model Used',
    }),
  );
  @field createdAt = contains(DatetimeField);
  @field title = contains(StringField, {
    computeVia: function (this: SculptedModel) {
      return this.objectName || 'Sculpted Model';
    },
  });

  static isolated = class Isolated extends Component<typeof SculptedModel> {
    get hasLinkedTheme() {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    // the viewer harness renders the model's .js file, inlined via srcdoc
    // (external sites embed the same harness by its viewer.html URL)
    get viewerSrcdoc() {
      let codeFileUrl = this.args.model?.codeFile?.url;
      if (!codeFileUrl) return undefined;
      return generateViewerSrcdoc(codeFileUrl);
    }
    <template>
      <article
        class='sculpted {{unless this.hasLinkedTheme "i3d-default-theme"}}'
      >
        <header class='sculpted-header'>
          <h1 class='sculpted-title'>{{@model.title}}</h1>
          {{#if @model.score}}
            <p class='sculpted-score'>score {{@model.score}}</p>
          {{/if}}
        </header>
        <main class='sculpted-viewport' aria-label='3D model viewport'>
          {{#if this.viewerSrcdoc}}
            <iframe
              class='sculpted-frame'
              title='3D model viewer'
              srcdoc={{this.viewerSrcdoc}}
            ></iframe>
          {{else}}
            <p class='sculpted-missing'>no model file on this round</p>
          {{/if}}
        </main>
        {{#if @model.critique}}
          <footer class='sculpted-footer'>
            <p class='sculpted-critique'>{{@model.critique}}</p>
          </footer>
        {{/if}}
      </article>
      <style scoped>
        .sculpted {
          --i3d-bg: var(--background, #0a0b10);
          --i3d-text: var(--foreground, #eef0f6);
          --i3d-border: var(--border, #232838);
          --i3d-text-dim: var(--muted-foreground, #9aa0b2);
          --i3d-accent: var(--accent, #38e8ff);
          --i3d-font-mono: var(--font-mono, ui-monospace, Menlo, monospace);
          --i3d-font-sans: var(
            --font-sans,
            -apple-system,
            BlinkMacSystemFont,
            'Segoe UI',
            Roboto,
            sans-serif
          );
          display: flex;
          flex-direction: column;
          height: 100dvh;
          max-height: 100%;
          min-height: 0;
          background: var(--i3d-bg);
          color: var(--i3d-text);
          font-family: var(--i3d-font-sans);
        }
        .sculpted-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 0.75rem 1.25rem;
          border-bottom: 1px solid var(--i3d-border);
        }
        .sculpted-title {
          margin: 0;
          font-size: 1rem;
        }
        .sculpted-score {
          margin: 0;
          font-family: var(--i3d-font-mono);
          font-size: 0.6875rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--i3d-accent);
        }
        .sculpted-viewport {
          flex: 1;
          min-height: 0;
          position: relative;
        }
        .sculpted-frame {
          display: block;
          width: 100%;
          height: 100%;
          border: 0;
        }
        .sculpted-missing {
          display: grid;
          place-items: center;
          height: 100%;
          margin: 0;
          font-family: var(--i3d-font-mono);
          font-size: 0.75rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--i3d-text-dim);
        }
        .sculpted-footer {
          padding: 0.625rem 1.25rem;
          border-top: 1px solid var(--i3d-border);
        }
        .sculpted-critique {
          margin: 0;
          font-size: 0.8125rem;
          color: var(--i3d-text-dim);
        }
        .i3d-default-theme {
          --background: #2b303d;
          --card: #14161e;
          --border: #232838;
          --foreground: #eef0f6;
          --muted-foreground: #9aa0b2;
          --accent: #38e8ff;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof SculptedModel> {
    get hasLinkedTheme() {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    <template>
      <article class='tile {{unless this.hasLinkedTheme "i3d-default-theme"}}'>
        <header class='tile-header'>
          <h3 class='tile-title'>{{@model.title}}</h3>
          {{#if @model.score}}
            <p class='tile-score'>score {{@model.score}}</p>
          {{/if}}
        </header>
        {{#if @model.renderScreenshot.url}}
          <img
            class='tile-image'
            src={{@model.renderScreenshot.url}}
            alt='Render of {{@model.title}}'
          />
        {{else if @model.references.primaryUrl}}
          <img
            class='tile-image'
            src={{@model.references.primaryUrl}}
            alt='Reference for {{@model.title}}'
          />
        {{/if}}
        {{#if @model.modelUsed}}
          <p class='tile-meta'>{{@model.modelUsed}}</p>
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
        .tile-score {
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
          /* renders are deep-space screenshots — contain on the same dark
             ground shows the whole model instead of a blown-up crop */
          object-fit: contain;
          background: var(--i3d-bg, var(--background, #0a0b10));
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
          --card: #14161e;
          --border: #232838;
          --foreground: #eef0f6;
          --muted-foreground: #9aa0b2;
          --accent: #38e8ff;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof SculptedModel> {
    get hasLinkedTheme() {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    // baked into the prerendered tile so the studio's history strip can show
    // when each round was made without loading the card
    get createdLabel() {
      let d = this.args.model?.createdAt;
      if (!d) return undefined;
      return new Date(d).toLocaleString(undefined, {
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });
    }
    <template>
      <article class='fit {{unless this.hasLinkedTheme "i3d-default-theme"}}'>
        {{#if @model.renderScreenshot.url}}
          <img class='fit-image' src={{@model.renderScreenshot.url}} alt='' />
        {{else if @model.references.primaryUrl}}
          <img class='fit-image' src={{@model.references.primaryUrl}} alt='' />
        {{/if}}
        <div class='fit-info'>
          <h3 class='fit-title'>{{@model.title}}</h3>
          <p class='fit-tag'>
            {{#if @model.round}}round {{@model.round}}{{else}}sculpted{{/if}}
          </p>
          {{#if this.createdLabel}}
            <p class='fit-time'>{{this.createdLabel}}</p>
          {{/if}}
        </div>
      </article>
      <style scoped>
        .fit {
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-xs, 0.625rem);
          height: 100%;
          padding: var(--boxel-sp-xs, 0.625rem);
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
          /* deep-space screenshot — contain shows the whole model */
          object-fit: contain;
          background: var(--i3d-bg, var(--background, #0a0b10));
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
        .fit-time {
          margin: 0.125rem 0 0;
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.625rem;
          white-space: nowrap;
          color: var(--i3d-text-dim, var(--muted-foreground, #9aa0b2));
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
        /* tall tiles (root grid cards): render on top, info strip below */
        @container fitted-card (height > 170px) {
          .fit {
            flex-direction: column;
            align-items: stretch;
            gap: var(--boxel-sp-xxs, 0.375rem);
          }
          .fit-image {
            width: 100%;
            height: auto;
            flex: 1;
            min-height: 0;
          }
          .fit-info {
            flex-shrink: 0;
          }
        }
        .i3d-default-theme {
          --background: #2b303d;
          --card: #14161e;
          --border: #232838;
          --foreground: #eef0f6;
          --muted-foreground: #9aa0b2;
          --accent: #38e8ff;
        }
      </style>
    </template>
  };
}
