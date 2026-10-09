import { CardDef, Component, contains, field } from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import {
  StepList,
  type StepItem,
} from '@cardstack/pretui/components/step-list';

import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';

// Each stage writes independently, so a stage's state is whether its field
// is written, not its position in the list.
function stagesOf(model: {
  spec?: string | null;
  designDirection?: string | null;
  motion?: string | null;
}): StepItem[] {
  return [
    { label: 'Spec', written: model.spec },
    { label: 'Direction', written: model.designDirection },
    { label: 'Motion', written: model.motion },
  ].map(({ label, written }) => ({
    label,
    state: written ? 'complete' : 'upcoming',
  }));
}

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
            <EmptyState
              @title='Not written yet'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            ><code>domain-interview</code> writes this.</EmptyState>
          {{/if}}
        </section>

        <section class='stage'>
          <h2 class='stage-title'>Design direction</h2>
          {{#if @model.designDirection}}
            <@fields.designDirection />
          {{else}}
            <EmptyState
              @title='Not written yet'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            ><code>design-direction</code> writes this.</EmptyState>
          {{/if}}
        </section>

        <section class='stage'>
          <h2 class='stage-title'>Motion</h2>
          {{#if @model.motion}}
            <@fields.motion />
          {{else}}
            <EmptyState
              @title='Not needed, or not written yet'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            ><code>motion-authoring</code>
              writes this only when the direction asked for an arc.</EmptyState>
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
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
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
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Brief> {
    get stages() {
      return stagesOf(this.args.model ?? {});
    }

    <template>
      <article class='brief-embedded'>
        <p class='eyebrow'>Brief</p>
        <h3 class='title'>{{@model.cardTitle}}</h3>
        <p class='summary'>{{@model.cardDescription}}</p>
        <StepList
          class='stages'
          @steps={{this.stages}}
          @variant='track'
          @label='Stages written'
          @announce={{false}}
        />
      </article>

      <style scoped>
        .brief-embedded {
          padding: var(--boxel-sp);
          color: var(--foreground);
        }
        .eyebrow {
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
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
          margin-top: var(--boxel-sp-sm);
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
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
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
        @container fitted-card (height < 7.5rem) {
          .summary {
            display: none;
          }
        }
        @container fitted-card (height < 5rem) {
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
        @container fitted-card (width < 12.5rem) {
          .stages {
            display: none;
          }
        }
      </style>
    </template>
  };
}
