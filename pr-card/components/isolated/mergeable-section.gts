import GlimmerComponent from '@glimmer/component';
import TriangleAlertIcon from '@cardstack/boxel-icons/triangle-alert';
import CircleCheckIcon from '@cardstack/boxel-icons/circle-check';

interface MergeableSectionSignature {
  Args: {
    isMergeable: boolean;
    isClosedOrMerged: boolean;
    blockReasons: string[];
  };
}

export class MergeableSection extends GlimmerComponent<MergeableSectionSignature> {
  <template>
    {{#unless @isClosedOrMerged}}
      {{#if @isMergeable}}
        <div class='mergeable-banner mergeable-banner--ok'>
          <span class='mergeable-icon-wrap mergeable-icon-wrap--ok'>
            <CircleCheckIcon class='mergeable-icon' />
          </span>
          <div class='mergeable-content'>
            <span class='mergeable-title'>Ready to merge</span>
            <span class='mergeable-subtitle'>All merge requirements have been
              met</span>
          </div>
        </div>
      {{else}}
        <div class='mergeable-banner mergeable-banner--blocked'>
          <span class='mergeable-icon-wrap mergeable-icon-wrap--blocked'>
            <TriangleAlertIcon class='mergeable-icon' />
          </span>
          <div class='mergeable-content'>
            <span class='mergeable-title'>Merging is blocked</span>
            {{#each @blockReasons as |reason|}}
              <span class='mergeable-reason'>{{reason}}</span>
            {{/each}}
          </div>
        </div>
      {{/if}}
    {{/unless}}

    <style scoped>
      .mergeable-banner {
        display: flex;
        align-items: flex-start;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp-sm) var(--boxel-sp-lg);
        border-top: 1px solid var(--border);
        border-bottom: 1px solid var(--border);
      }
      .mergeable-banner--blocked {
        background-color: color-mix(in oklch, var(--card) 5%, var(--card));
      }
      .mergeable-banner--ok {
        background-color: color-mix(in oklch, var(--chart-1) 5%, var(--card));
      }
      .mergeable-icon-wrap {
        width: 2rem;
        height: 2rem;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }
      .mergeable-icon-wrap--blocked {
        background-color: var(--destructive);
        color: var(--destructive-foreground);
      }
      .mergeable-icon-wrap--ok {
        background-color: var(--chart-1);
      }
      .mergeable-icon {
        width: 1rem;
        height: 1rem;
        color: var(--card-foreground);
      }
      .mergeable-content {
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
      }
      .mergeable-title {
        font-size: var(--boxel-font-sm);
        font-weight: 700;
        color: var(--foreground);
        line-height: 1.4;
      }
      .mergeable-reason,
      .mergeable-subtitle {
        font-size: var(--boxel-font-sm);
        color: var(--muted-foreground);
        line-height: 1.5;
      }
    </style>
  </template>
}
