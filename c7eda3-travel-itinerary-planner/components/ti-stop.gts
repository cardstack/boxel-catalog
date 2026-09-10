import type { ItineraryStop } from '../travel-itinerary';
import { Component } from '@cardstack/base/card-api';
import { categoryStyle, formatCost } from '../utils/index';

export class ItineraryStopEmbedded extends Component<typeof ItineraryStop> {
  get timeRange() {
    let start = this.args.model?.startTime?.value?.trim();
    let end = this.args.model?.endTime?.value?.trim();
    if (start && end) return `${start} – ${end}`;
    return start || end || '';
  }

  get locationLabel() {
    let loc = this.args.model?.location;
    if (!loc) return null;
    if (loc.searchKey && loc.searchKey.trim() !== '') return loc.searchKey;
    if (loc.lat != null && loc.lon != null) return `${loc.lat}, ${loc.lon}`;
    return null;
  }

  <template>
    <div class='stop' style={{categoryStyle @model.category}}>
      <div class='stop-head'>
        <span class='stop-dot'></span>
        <span class='stop-name'>{{if
            this.locationLabel
            this.locationLabel
            'Untitled stop'
          }}</span>
      </div>
      <div class='stop-meta'>
        {{#if @model.day}}
          <span class='stop-day'>Day {{@model.day}}</span>
        {{/if}}
        {{#if this.timeRange}}
          <span class='stop-time'>{{this.timeRange}}</span>
        {{/if}}
        {{#if @model.category}}
          <span class='stop-cat'>{{@model.category}}</span>
        {{/if}}
        {{#if @model.estimatedCost}}
          <span class='stop-cost'>{{formatCost @model.estimatedCost}}</span>
        {{/if}}
      </div>
      {{#if this.locationLabel}}
        <span class='stop-addr'>{{this.locationLabel}}</span>
      {{/if}}
    </div>
    <style scoped>
      .stop {
        --stop-color: var(--primary);
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        border-left: 3px solid var(--stop-color);
        padding-left: var(--boxel-sp-xs);
      }
      .stop-head {
        display: flex;
        align-items: center;
        gap: 0.375rem;
      }
      .stop-dot {
        width: 0.5625rem;
        height: 0.5625rem;
        border-radius: 50%;
        background-color: var(--stop-color);
        flex-shrink: 0;
      }
      .stop-name {
        font-weight: 600;
        font-size: var(--boxel-font-size-sm);
      }
      .stop-meta {
        display: flex;
        flex-wrap: wrap;
        gap: 0.375rem;
        align-items: center;
      }
      .stop-day,
      .stop-time {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        color: color-mix(
          in oklch,
          var(--stop-color) 62%,
          var(--foreground) 38%
        );
      }
      .stop-cost {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        color: var(--foreground);
        background-color: var(--muted);
        border-radius: 62.4375rem;
        padding: 1px 0.5rem;
      }
      .stop-cat {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .stop-addr {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
