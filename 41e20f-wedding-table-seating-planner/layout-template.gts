import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import LayoutIcon from '@cardstack/boxel-icons/layout-dashboard';

import { Table } from './table';
import { Fixture } from './fixture';
import LayoutPreview from './components/layout-preview';

export class LayoutTemplate extends CardDef {
  static displayName = 'Layout Template';
  static icon = LayoutIcon;

  @field name = contains(StringField);
  @field tables = containsMany(Table);
  @field fixtures = containsMany(Fixture);

  @field tableCount = contains(NumberField, {
    computeVia: function (this: LayoutTemplate) {
      return this.tables?.length ?? 0;
    },
  });

  @field seatCount = contains(NumberField, {
    computeVia: function (this: LayoutTemplate) {
      return (this.tables ?? []).reduce((n, t) => n + (t?.seatCount ?? 0), 0);
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: LayoutTemplate) {
      return this.name?.trim() || 'Untitled Template';
    },
  });

  static isolated = class Isolated extends Component<typeof LayoutTemplate> {
    <template>
      <div class='lt-iso'>
        <header class='lt-iso-head'>
          <div>
            <span class='lt-kicker'>Layout Template</span>
            <h1 class='lt-iso-title'>{{if
                @model.name
                @model.name
                'Untitled Template'
              }}</h1>
          </div>
          <div class='lt-iso-stats'>
            <span><b>{{if @model.tableCount @model.tableCount 0}}</b>
              tables</span>
            <span><b>{{if @model.seatCount @model.seatCount 0}}</b> seats</span>
          </div>
        </header>
        <div class='lt-canvas'>
          <LayoutPreview
            @tables={{@model.tables}}
            @fixtures={{@model.fixtures}}
          />
        </div>
      </div>
      <style scoped>
        .lt-iso {
          box-sizing: border-box;
          display: flex;
          flex-direction: column;
          gap: 1rem;
          width: 100%;
          height: 100%;
          min-height: 0;
          padding: 1.5rem;
          background-color: var(--card);
          color: var(--foreground);
          font-family: var(--font-sans);
        }
        .lt-iso-head {
          flex: none;
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: 1rem;
        }
        .lt-iso-title {
          font-family: var(--font-serif);
          font-size: 1.75rem;
          font-weight: 600;
          letter-spacing: -0.01em;
          margin: 0.25rem 0 0;
        }
        .lt-iso-stats {
          flex: none;
          display: flex;
          gap: 1rem;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          color: color-mix(in oklch, var(--foreground) 55%, transparent);
          white-space: nowrap;
        }
        .lt-iso-stats b {
          color: var(--accent-ink);
          font-size: 0.9375rem;
        }
        .lt-canvas {
          flex: 1;
          min-height: 0;
          border-radius: 0.875rem;
          border: 1px solid color-mix(in oklch, var(--accent) 35%, transparent);
          background: radial-gradient(
            circle at 50% 40%,
            var(--card),
            var(--muted)
          );
          padding: 1.125rem;
          overflow: hidden;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof LayoutTemplate> {
    <template>
      <div class='lt-card'>
        <div class='lt-thumb'>
          <LayoutPreview
            @tables={{@model.tables}}
            @fixtures={{@model.fixtures}}
          />
        </div>
        <div class='lt-info'>
          <span class='lt-name'>{{if
              @model.name
              @model.name
              'Untitled Template'
            }}</span>
          <span class='lt-meta'>{{if @model.tableCount @model.tableCount 0}}
            tables ·
            {{if @model.seatCount @model.seatCount 0}}
            seats</span>
        </div>
      </div>
      <style scoped>
        .lt-card {
          display: flex;
          align-items: center;
          gap: 0.6875rem;
          padding: 0.5rem 0.625rem;
          color: inherit;
          font-family: var(--font-sans);
        }
        .lt-thumb {
          flex-shrink: 0;
          width: 3.5rem;
          height: 2.625rem;
          border-radius: 0.5rem;
          border: 1px solid color-mix(in oklch, var(--accent) 35%, transparent);
          background: radial-gradient(
            circle at 50% 40%,
            var(--card),
            var(--inset)
          );
          padding: 0.25rem;
          overflow: hidden;
        }
        .lt-info {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .lt-name {
          font-family: var(--font-serif);
          font-size: 0.9375rem;
          font-weight: 600;
          letter-spacing: -0.01em;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .lt-meta {
          font-family: var(--font-sans);
          font-size: 0.6875rem;
          color: color-mix(in oklch, currentColor 55%, transparent);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof LayoutTemplate> {
    <template>
      <div class='lt-fitted'>

        <div class='badge'>
          <div class='lt-thumb'>
            <LayoutPreview
              @tables={{@model.tables}}
              @fixtures={{@model.fixtures}}
            />
          </div>
          <span class='lt-title'>{{if
              @model.name
              @model.name
              'Untitled Template'
            }}</span>
        </div>

        <div class='strip'>
          <div class='lt-thumb'>
            <LayoutPreview
              @tables={{@model.tables}}
              @fixtures={{@model.fixtures}}
            />
          </div>
          <div class='lt-info'>
            <span class='lt-title'>{{if
                @model.name
                @model.name
                'Untitled Template'
              }}</span>
            <span class='lt-meta'>{{if @model.tableCount @model.tableCount 0}}
              tables ·
              {{if @model.seatCount @model.seatCount 0}}
              seats</span>
          </div>
        </div>

        <div class='tile'>
          <div class='lt-hero'>
            <LayoutPreview
              @tables={{@model.tables}}
              @fixtures={{@model.fixtures}}
            />
          </div>
          <div class='lt-body'>
            <span class='lt-kicker'>Layout Template</span>
            <span class='lt-title'>{{if
                @model.name
                @model.name
                'Untitled Template'
              }}</span>
            <div class='lt-stats'>
              <span class='lt-stat'><b>{{if
                    @model.tableCount
                    @model.tableCount
                    0
                  }}</b>
                tables</span>
              <span class='lt-stat'><b>{{if
                    @model.seatCount
                    @model.seatCount
                    0
                  }}</b>
                seats</span>
            </div>
          </div>
        </div>

        <div class='card'>
          <div class='lt-thumb lt-thumb-lg'>
            <LayoutPreview
              @tables={{@model.tables}}
              @fixtures={{@model.fixtures}}
            />
          </div>
          <div class='lt-body'>
            <span class='lt-kicker'>Layout Template</span>
            <span class='lt-title'>{{if
                @model.name
                @model.name
                'Untitled Template'
              }}</span>
            <div class='lt-stats'>
              <span class='lt-stat'><b>{{if
                    @model.tableCount
                    @model.tableCount
                    0
                  }}</b>
                tables</span>
              <span class='lt-stat'><b>{{if
                    @model.seatCount
                    @model.seatCount
                    0
                  }}</b>
                seats</span>
            </div>
          </div>
        </div>
      </div>

      <style scoped>
        .lt-fitted {
          width: 100%;
          height: 100%;
          color: inherit;
          font-family: var(--font-sans);
        }
        .badge,
        .strip,
        .tile,
        .card {
          display: none;
          box-sizing: border-box;
          width: 100%;
          height: 100%;
          overflow: hidden;
        }
        .lt-thumb {
          flex-shrink: 0;
          width: 2.75rem;
          height: 2.125rem;
          border-radius: 0.5rem;
          border: 1px solid color-mix(in oklch, var(--accent) 35%, transparent);
          background: radial-gradient(
            circle at 50% 40%,
            var(--card),
            var(--inset)
          );
          padding: 0.25rem;
          overflow: hidden;
        }
        .lt-thumb-lg {
          width: 6.75rem;
          height: 5.125rem;
          border-radius: 0.6875rem;
          padding: 0.5rem;
        }
        .lt-title {
          font-family: var(--font-serif);
          font-weight: 600;
          letter-spacing: -0.01em;
          color: inherit;
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .lt-kicker {
          font-family: var(--font-sans);
          font-size: 0.5625rem;
          letter-spacing: 0.18em;
          text-transform: uppercase;
          color: var(--accent-ink);
        }
        .lt-info,
        .lt-body {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .lt-meta {
          font-family: var(--font-sans);
          font-size: 0.6875rem;
          color: color-mix(in oklch, currentColor 55%, transparent);
        }
        .lt-stats {
          display: flex;
          flex-wrap: wrap;
          gap: 0.25rem 0.75rem;
          margin-top: 0.25rem;
          font-family: var(--font-sans);
          font-size: 0.6875rem;
          color: color-mix(in oklch, currentColor 55%, transparent);
        }
        .lt-stat b {
          font-family: var(--font-sans);
          font-size: 0.875rem;
          font-weight: 700;
          color: var(--accent-ink);
        }
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: flex-start;
            justify-content: center;
            gap: 0.4375rem;
            padding: 0.625rem;
          }
          .badge .lt-title {
            font-size: 0.8125rem;
            white-space: normal;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            flex-direction: row;
            align-items: center;
            gap: 0.6875rem;
            padding: 0.625rem 0.8125rem;
          }
          .strip .lt-title {
            font-size: 0.9375rem;
          }
        }
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            align-items: stretch;
            gap: 0;
          }
          .lt-hero {
            flex: 1;
            min-height: 5.625rem;
            margin: 0.875rem 0.875rem 0.625rem;
            border-radius: 0.625rem;
            border: 1px solid
              color-mix(in oklch, var(--accent) 35%, transparent);
            background: radial-gradient(
              circle at 50% 40%,
              var(--card),
              var(--inset)
            );
            padding: 0.625rem;
            overflow: hidden;
          }
          .tile .lt-body {
            padding: 0 1rem 1rem;
            gap: 0.25rem;
          }
          .tile .lt-title {
            font-size: 1.125rem;
            white-space: normal;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: row;
            align-items: center;
            gap: 1rem;
            padding: 1.125rem 1.25rem;
          }
          .card .lt-title {
            font-size: 1.25rem;
          }
        }
      </style>
    </template>
  };
}
