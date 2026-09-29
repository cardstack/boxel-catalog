import { CardDef, Component, contains, field } from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import FileTextIcon from '@cardstack/boxel-icons/file-text';

/**
 * The one artifact a design pipeline writes to before anything is built.
 *
 * Each stage owns one field and never touches another's: `spec` is what the
 * thing is (domain primer, schema, coverage matrix, content contracts, flows,
 * sample data), `designDirection` is how it should look and move, `motion` is
 * the build numbers for an arc the direction asked for. Splitting them is the
 * point — a stage replaces its own field whole, so no stage has to read the
 * whole brief back and resend it to add its part, and no stage can truncate
 * another's text by accident. The title and summary live on `cardInfo`.
 */
export class Brief extends CardDef {
  static displayName = 'Brief';
  static icon = FileTextIcon;

  @field spec = contains(MarkdownField);
  @field designDirection = contains(MarkdownField);
  @field motion = contains(MarkdownField);

  static isolated = class Isolated extends Component<typeof Brief> {
    <template>
      <article class='brief'>
        <header class='brief-header'>
          <p class='eyebrow'>Brief</p>
          <h1 class='title'>{{@model.cardTitle}}</h1>
          <p class='summary'>{{@model.cardDescription}}</p>
        </header>

        <section class='stage'>
          <h2 class='stage-title'>Spec</h2>
          {{#if @model.spec}}
            <@fields.spec />
          {{else}}
            <p class='empty'>Not written yet —
              <code>domain-interview</code>
              writes this.</p>
          {{/if}}
        </section>

        <section class='stage'>
          <h2 class='stage-title'>Design direction</h2>
          {{#if @model.designDirection}}
            <@fields.designDirection />
          {{else}}
            <p class='empty'>Not written yet —
              <code>design-direction</code>
              writes this.</p>
          {{/if}}
        </section>

        <section class='stage'>
          <h2 class='stage-title'>Motion</h2>
          {{#if @model.motion}}
            <@fields.motion />
          {{else}}
            <p class='empty'>Not needed, or not written yet —
              <code>motion-authoring</code>
              writes this only when the direction asked for an arc.</p>
          {{/if}}
        </section>
      </article>

      <style scoped>
        .brief {
          padding: var(--boxel-sp-xl);
          color: var(--foreground);
          background: var(--background);
        }
        .brief-header {
          padding-bottom: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .eyebrow {
          margin: 0;
          font: var(--boxel-font-xs);
          letter-spacing: var(--boxel-lsp-xl);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .title {
          margin: var(--boxel-sp-xxs) 0 0;
          font: var(--boxel-font-xl);
        }
        .summary {
          margin: var(--boxel-sp-sm) 0 0;
          max-width: 70ch;
          color: var(--muted-foreground);
        }
        .stage {
          padding-block: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .stage:last-child {
          border-bottom: 0;
        }
        .stage-title {
          margin: 0 0 var(--boxel-sp);
          font: var(--boxel-font-lg);
        }
        .empty {
          margin: 0;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Brief> {
    <template>
      <article class='brief-embedded'>
        <p class='eyebrow'>Brief</p>
        <h3 class='title'>{{@model.cardTitle}}</h3>
        <p class='summary'>{{@model.cardDescription}}</p>
        <ul class='stages' aria-label='Stages written'>
          <li class='stage {{if @model.spec "is-written"}}'>Spec</li>
          <li class='stage {{if @model.designDirection "is-written"}}'>
            Direction
          </li>
          <li class='stage {{if @model.motion "is-written"}}'>Motion</li>
        </ul>
      </article>

      <style scoped>
        .brief-embedded {
          padding: var(--boxel-sp);
          color: var(--foreground);
        }
        .eyebrow {
          margin: 0;
          font: var(--boxel-font-xs);
          letter-spacing: var(--boxel-lsp-xl);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .title {
          margin: var(--boxel-sp-xxxs) 0 0;
          font: var(--boxel-font);
          font-weight: 600;
        }
        .summary {
          margin: var(--boxel-sp-xxs) 0 0;
          font: var(--boxel-font-sm);
          color: var(--muted-foreground);
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .stages {
          display: flex;
          gap: var(--boxel-sp-xxs);
          margin: var(--boxel-sp-sm) 0 0;
          padding: 0;
          list-style: none;
        }
        .stage {
          padding: var(--boxel-sp-5xs) var(--boxel-sp-xxs);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          font: var(--boxel-font-xs);
          color: var(--muted-foreground);
        }
        .stage.is-written {
          border-color: var(--primary);
          background: var(--primary);
          color: var(--primary-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Brief> {
    <template>
      <div class='fit'>
        <p class='eyebrow'>Brief</p>
        <h3 class='title'>{{@model.cardTitle}}</h3>
        <p class='summary'>{{@model.cardDescription}}</p>
        <p class='stages'>
          <span class='stage {{if @model.spec "is-written"}}'>Spec</span>
          <span class='stage {{if @model.designDirection "is-written"}}'>
            Direction
          </span>
          <span class='stage {{if @model.motion "is-written"}}'>Motion</span>
        </p>
      </div>

      <style scoped>
        .fit {
          display: grid;
          grid-template-rows: auto auto minmax(0, 1fr) auto;
          gap: var(--boxel-sp-xxs);
          height: 100%;
          min-height: 0;
          padding: var(--boxel-sp-sm);
          color: var(--foreground);
        }
        .eyebrow,
        .title,
        .summary,
        .stages {
          margin: 0;
        }
        .eyebrow {
          font: var(--boxel-font-xs);
          letter-spacing: var(--boxel-lsp-xl);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .title {
          font: var(--boxel-font-sm);
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .summary {
          min-height: 0;
          font: var(--boxel-font-xs);
          color: var(--muted-foreground);
          display: -webkit-box;
          -webkit-line-clamp: 3;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .stages {
          display: flex;
          gap: var(--boxel-sp-xs);
          font: var(--boxel-font-xs);
        }
        .stage {
          color: var(--muted-foreground);
        }
        .stage.is-written {
          color: var(--foreground);
          font-weight: 600;
        }
        @container fitted-card (height < 120px) {
          .summary {
            display: none;
          }
        }
        @container fitted-card (height < 80px) {
          .fit {
            grid-template-rows: auto;
            grid-auto-flow: column;
            align-items: center;
          }
          .eyebrow,
          .stages {
            display: none;
          }
        }
        @container fitted-card (width < 200px) {
          .stages {
            display: none;
          }
        }
      </style>
    </template>
  };
}
