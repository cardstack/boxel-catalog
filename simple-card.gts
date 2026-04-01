// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string'; // ²
import TextAreaField from 'https://cardstack.com/base/text-area'; // ³
import DateField from 'https://cardstack.com/base/date'; // ⁴
import NotepadIcon from '@cardstack/boxel-icons/file-text'; // ⁵

export class SimpleCard extends CardDef {
  // ⁶
  static displayName = 'Simple Card';
  static icon = NotepadIcon;

  @field title = contains(StringField); // ⁷
  @field description = contains(TextAreaField); // ⁸
  @field date = contains(DateField); // ⁹

  @field cardTitle = contains(StringField, {
    // ¹⁰
    computeVia: function (this: SimpleCard) {
      return this.cardInfo?.name ?? this.title ?? 'Untitled Card';
    },
  });

  static isolated = class Isolated extends Component<typeof SimpleCard> {
    // ¹¹
    <template>
      <article class='simple-card-isolated'>
        <header class='sc-header'>
          <div class='sc-icon'>
            <svg
              width='32'
              height='32'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='1.5'
              stroke-linecap='round'
              stroke-linejoin='round'
            >
              <rect x='3' y='3' width='18' height='18' rx='2' ry='2' />
              <line x1='3' y1='9' x2='21' y2='9' />
              <line x1='9' y1='21' x2='9' y2='9' />
            </svg>
          </div>
          <div class='sc-header-text'>
            <h1 class='sc-title'>
              {{#if @model.title}}
                {{@model.title}}
              {{else}}
                <span class='sc-placeholder'>Untitled Card</span>
              {{/if}}
            </h1>
            {{#if @model.date}}
              <time class='sc-date'>
                <svg
                  width='14'
                  height='14'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <rect x='3' y='4' width='18' height='18' rx='2' ry='2' />
                  <line x1='16' y1='2' x2='16' y2='6' />
                  <line x1='8' y1='2' x2='8' y2='6' />
                  <line x1='3' y1='10' x2='21' y2='10' />
                </svg>
                <@fields.date />
              </time>
            {{/if}}
          </div>
        </header>

        <div class='sc-body'>
          {{#if @model.description}}
            <p class='sc-description'><@fields.description /></p>
          {{else}}
            <p class='sc-placeholder-text'>No description yet. Click edit to add
              one.</p>
          {{/if}}
        </div>
      </article>
      <style scoped>
        /* ¹² Isolated styles */
        .simple-card-isolated {
          container-type: inline-size;
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-xl);
          background-color: var(--background);
          color: var(--foreground);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          box-sizing: border-box;
          font-family: var(--font-sans);
        }
        .sc-header {
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp);
          padding-bottom: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .sc-icon {
          flex-shrink: 0;
          width: 52px;
          height: 52px;
          border-radius: var(--boxel-border-radius-lg);
          background-color: var(--primary);
          color: var(--primary-foreground);
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow: var(--shadow-sm);
        }
        .sc-header-text {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          flex: 1;
          min-width: 0;
        }
        .sc-title {
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          margin: 0;
          line-height: 1.2;
          letter-spacing: var(--boxel-lsp-xs);
        }
        .sc-date {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .sc-body {
          flex: 1;
        }
        .sc-description {
          font-size: var(--boxel-font-size);
          line-height: 1.6;
          color: var(--foreground);
          margin: 0;
        }
        .sc-placeholder {
          color: var(--muted-foreground);
          font-style: italic;
          font-weight: 400;
        }
        .sc-placeholder-text {
          color: var(--muted-foreground);
          font-style: italic;
          font-size: var(--boxel-font-size-sm);
          margin: 0;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof SimpleCard> {
    // ¹³
    <template>
      <div class='simple-card-embedded'>
        <div class='sce-icon'>
          <svg
            width='16'
            height='16'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
            stroke-linecap='round'
            stroke-linejoin='round'
          >
            <rect x='3' y='3' width='18' height='18' rx='2' ry='2' />
            <line x1='3' y1='9' x2='21' y2='9' />
            <line x1='9' y1='21' x2='9' y2='9' />
          </svg>
        </div>
        <div class='sce-content'>
          <h3 class='sce-title'>
            {{if @model.title @model.title 'Untitled Card'}}
          </h3>
          {{#if @model.description}}
            <p class='sce-desc'>{{@model.description}}</p>
          {{/if}}
        </div>
        {{#if @model.date}}
          <time class='sce-date'><@fields.date /></time>
        {{/if}}
      </div>
      <style scoped>
        /* ¹⁴ Embedded styles */
        .simple-card-embedded {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          background-color: var(--card);
          color: var(--card-foreground);
          border-radius: var(--boxel-border-radius);
          font-family: var(--font-sans);
        }
        .sce-icon {
          flex-shrink: 0;
          width: 32px;
          height: 32px;
          border-radius: var(--boxel-border-radius-sm);
          background-color: var(--primary);
          color: var(--primary-foreground);
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .sce-content {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 2px;
        }
        .sce-title {
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          margin: 0;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .sce-desc {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          margin: 0;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .sce-date {
          flex-shrink: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof SimpleCard> {
    // ¹⁵
    <template>
      <div class='simple-card-fitted'>
        <div class='scf-badge'>
          <div class='scf-icon'>
            <svg
              width='14'
              height='14'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
              stroke-linecap='round'
              stroke-linejoin='round'
            >
              <rect x='3' y='3' width='18' height='18' rx='2' ry='2' />
              <line x1='3' y1='9' x2='21' y2='9' />
              <line x1='9' y1='21' x2='9' y2='9' />
            </svg>
          </div>
          <span class='scf-label'>{{if @model.title @model.title 'Card'}}</span>
        </div>
        <div class='scf-strip'>
          <div class='scfs-icon'>
            <svg
              width='16'
              height='16'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
              stroke-linecap='round'
              stroke-linejoin='round'
            >
              <rect x='3' y='3' width='18' height='18' rx='2' ry='2' />
              <line x1='3' y1='9' x2='21' y2='9' />
              <line x1='9' y1='21' x2='9' y2='9' />
            </svg>
          </div>
          <div class='scfs-content'>
            <span class='scfs-title'>{{if
                @model.title
                @model.title
                'Untitled Card'
              }}</span>
            {{#if @model.date}}
              <span class='scfs-date'><@fields.date /></span>
            {{/if}}
          </div>
        </div>
        <div class='scf-tile'>
          <div class='scft-header'>
            <div class='scft-icon'>
              <svg
                width='20'
                height='20'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='1.5'
                stroke-linecap='round'
                stroke-linejoin='round'
              >
                <rect x='3' y='3' width='18' height='18' rx='2' ry='2' />
                <line x1='3' y1='9' x2='21' y2='9' />
                <line x1='9' y1='21' x2='9' y2='9' />
              </svg>
            </div>
            <span class='scft-type'>Simple Card</span>
          </div>
          <h3 class='scft-title'>{{if
              @model.title
              @model.title
              'Untitled Card'
            }}</h3>
          {{#if @model.description}}
            <p class='scft-desc'>{{@model.description}}</p>
          {{/if}}
        </div>
        <div class='scf-card'>
          <div class='scfc-top'>
            <div class='scfc-icon'>
              <svg
                width='24'
                height='24'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='1.5'
                stroke-linecap='round'
                stroke-linejoin='round'
              >
                <rect x='3' y='3' width='18' height='18' rx='2' ry='2' />
                <line x1='3' y1='9' x2='21' y2='9' />
                <line x1='9' y1='21' x2='9' y2='9' />
              </svg>
            </div>
            <span class='scfc-type'>Simple Card</span>
          </div>
          <h2 class='scfc-title'>{{if
              @model.title
              @model.title
              'Untitled Card'
            }}</h2>
          {{#if @model.description}}
            <p class='scfc-desc'>{{@model.description}}</p>
          {{/if}}
          {{#if @model.date}}
            <time class='scfc-date'><@fields.date /></time>
          {{/if}}
        </div>
      </div>
      <style scoped>
        /* ¹⁶ Fitted styles — all sub-formats hidden by default */
        .simple-card-fitted {
          width: 100%;
          height: 100%;
          overflow: hidden;
          font-family: var(--font-sans);
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .scf-badge,
        .scf-strip,
        .scf-tile,
        .scf-card {
          display: none;
        }

        /* Badge: ≤150px wide AND <170px tall */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .scf-badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 4px;
            height: 100%;
            padding: var(--boxel-sp-xs);
          }
          .scf-icon {
            width: 28px;
            height: 28px;
            border-radius: var(--boxel-border-radius-sm);
            background-color: var(--primary);
            color: var(--primary-foreground);
            display: flex;
            align-items: center;
            justify-content: center;
          }
          .scf-label {
            font-size: 0.6rem;
            font-weight: 600;
            text-align: center;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            max-width: 100%;
          }
        }

        /* Strip: >150px wide AND <170px tall */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .scf-strip {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            height: 100%;
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .scfs-icon {
            flex-shrink: 0;
            width: 28px;
            height: 28px;
            border-radius: var(--boxel-border-radius-sm);
            background-color: var(--primary);
            color: var(--primary-foreground);
            display: flex;
            align-items: center;
            justify-content: center;
          }
          .scfs-content {
            flex: 1;
            min-width: 0;
            display: flex;
            flex-direction: column;
            gap: 1px;
          }
          .scfs-title {
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .scfs-date {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
        }

        /* Tile: <400px wide AND ≥170px tall */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .scf-tile {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-xs);
            height: 100%;
            padding: var(--boxel-sp-sm);
          }
          .scft-header {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .scft-icon {
            width: 28px;
            height: 28px;
            border-radius: var(--boxel-border-radius-sm);
            background-color: var(--primary);
            color: var(--primary-foreground);
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
          }
          .scft-type {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: var(--boxel-lsp-lg);
          }
          .scft-title {
            font-size: var(--boxel-font-size);
            font-weight: 700;
            margin: 0;
            line-height: 1.2;
            overflow: hidden;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
          }
          .scft-desc {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            margin: 0;
            overflow: hidden;
            display: -webkit-box;
            -webkit-line-clamp: 3;
            -webkit-box-orient: vertical;
            flex: 1;
          }
        }

        /* Card: ≥400px wide AND ≥170px tall */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .scf-card {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            height: 100%;
            padding: var(--boxel-sp);
          }
          .scfc-top {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .scfc-icon {
            width: 36px;
            height: 36px;
            border-radius: var(--boxel-border-radius);
            background-color: var(--primary);
            color: var(--primary-foreground);
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
          }
          .scfc-type {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: var(--boxel-lsp-lg);
          }
          .scfc-title {
            font-size: var(--boxel-font-size-lg);
            font-weight: 700;
            margin: 0;
            line-height: 1.2;
          }
          .scfc-desc {
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
            margin: 0;
            flex: 1;
            overflow: hidden;
            display: -webkit-box;
            -webkit-line-clamp: 3;
            -webkit-box-orient: vertical;
          }
          .scfc-date {
            font-size: var(--boxund);
            border-top: 1px solid var(--border);
            padding-top: var(--boxel-sp-xs);
          }
        }
      </style>
    </template>
  };
}
