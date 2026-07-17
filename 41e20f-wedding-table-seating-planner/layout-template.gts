import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
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
          --lt-accent: var(--tsp-accent, var(--accent, #c5a35c));
          --lt-accent-deep: var(--tsp-accent-deep, #a8894f);
          --lt-paper: var(--tsp-muted, var(--muted, #f0eee7));
          box-sizing: border-box;
          display: flex;
          flex-direction: column;
          gap: 16px;
          width: 100%;
          height: 100%;
          min-height: 0;
          padding: 24px;
          background: #f7f5f0;
          color: var(--tsp-foreground, var(--foreground, #22283f));
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', system-ui, sans-serif)
          );
        }
        .lt-iso-head {
          flex: none;
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: 16px;
        }
        .lt-iso-title {
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
          font-size: 28px;
          font-weight: 600;
          letter-spacing: -0.01em;
          margin: 4px 0 0;
        }
        .lt-iso-stats {
          flex: none;
          display: flex;
          gap: 16px;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 12px;
          color: color-mix(
            in srgb,
            var(--tsp-foreground, var(--foreground, #22283f)) 55%,
            transparent
          );
          white-space: nowrap;
        }
        .lt-iso-stats b {
          color: var(--lt-accent);
          font-size: 15px;
        }
        .lt-canvas {
          flex: 1;
          min-height: 0;
          border-radius: 14px;
          border: 1px solid rgba(220, 193, 136, 0.35);
          background: radial-gradient(
            circle at 50% 40%,
            #ffffff,
            var(--lt-paper)
          );
          padding: 18px;
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
          --lt-accent: var(--tsp-accent, var(--accent, #c5a35c));
          --lt-accent-deep: #a8894f;
          display: flex;
          align-items: center;
          gap: 11px;
          padding: 8px 10px;
          color: inherit;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', system-ui, sans-serif)
          );
        }
        .lt-thumb {
          flex-shrink: 0;
          width: 56px;
          height: 42px;
          border-radius: 8px;
          border: 1px solid rgba(220, 193, 136, 0.35);
          background: radial-gradient(circle at 50% 40%, #ffffff, #f0eee7);
          padding: 4px;
          overflow: hidden;
        }
        .lt-info {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .lt-name {
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
          font-size: 15px;
          font-weight: 600;
          letter-spacing: -0.01em;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .lt-meta {
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 11px;
          color: color-mix(in srgb, currentColor 55%, transparent);
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
          --lt-accent: var(--tsp-accent, var(--accent, #c5a35c));
          --lt-accent-deep: #a8894f;
          width: 100%;
          height: 100%;
          color: inherit;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', system-ui, sans-serif)
          );
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
          width: 44px;
          height: 34px;
          border-radius: 8px;
          border: 1px solid rgba(220, 193, 136, 0.35);
          background: radial-gradient(circle at 50% 40%, #ffffff, #f0eee7);
          padding: 4px;
          overflow: hidden;
        }
        .lt-thumb-lg {
          width: 108px;
          height: 82px;
          border-radius: 11px;
          padding: 8px;
        }
        .lt-title {
          font-family: var(
            --tsp-font-serif,
            var(--font-serif, 'Cormorant Garamond', Georgia, serif)
          );
          font-weight: 600;
          letter-spacing: -0.01em;
          color: inherit;
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .lt-kicker {
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 9px;
          letter-spacing: 0.18em;
          text-transform: uppercase;
          color: var(--lt-accent-deep);
        }
        .lt-info,
        .lt-body {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .lt-meta {
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 11px;
          color: color-mix(in srgb, currentColor 55%, transparent);
        }
        .lt-stats {
          display: flex;
          flex-wrap: wrap;
          gap: 4px 12px;
          margin-top: 4px;
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 11px;
          color: color-mix(in srgb, currentColor 55%, transparent);
        }
        .lt-stat b {
          font-family: var(
            --tsp-font-sans,
            var(--font-sans, 'Jost', sans-serif)
          );
          font-size: 14px;
          font-weight: 700;
          color: var(--lt-accent-deep);
        }
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: flex-start;
            justify-content: center;
            gap: 7px;
            padding: 10px;
          }
          .badge .lt-title {
            font-size: 13px;
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
            gap: 11px;
            padding: 10px 13px;
          }
          .strip .lt-title {
            font-size: 15px;
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
            min-height: 90px;
            margin: 14px 14px 10px;
            border-radius: 10px;
            border: 1px solid rgba(220, 193, 136, 0.35);
            background: radial-gradient(circle at 50% 40%, #ffffff, #f0eee7);
            padding: 10px;
            overflow: hidden;
          }
          .tile .lt-body {
            padding: 0 16px 16px;
            gap: 4px;
          }
          .tile .lt-title {
            font-size: 18px;
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
            gap: 16px;
            padding: 18px 20px;
          }
          .card .lt-title {
            font-size: 20px;
          }
        }
      </style>
    </template>
  };
}
