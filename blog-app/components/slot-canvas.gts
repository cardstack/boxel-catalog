import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import type Owner from '@ember/owner';
import { eq } from '@cardstack/boxel-ui/helpers';

interface Sig {
  Args: {
    initialOrder: string[];
    canEdit: boolean;
  };
  Blocks: {
    slot: [slotName: string];
  };
  Element: HTMLDivElement;
}

export class SlotCanvas extends Component<Sig> {
  @tracked slotOrder: string[];
  @tracked draggingSlot: string | null = null;
  @tracked dragOverSlot: string | null = null;

  constructor(owner: Owner, args: Sig['Args']) {
    super(owner, args);
    this.slotOrder = [...args.initialOrder];
  }

  @action onDragStart(slotName: string, event: Event) {
    this.draggingSlot = slotName;
    (event as DragEvent).dataTransfer?.setData('text/plain', slotName);
  }

  @action onDragOver(slotName: string, event: Event) {
    event.preventDefault();
    this.dragOverSlot = slotName;
  }

  @action onDrop(targetSlot: string, event: Event) {
    event.preventDefault();
    if (!this.draggingSlot || this.draggingSlot === targetSlot) return;
    const order = [...this.slotOrder];
    const fromIdx = order.indexOf(this.draggingSlot);
    const toIdx = order.indexOf(targetSlot);
    order.splice(fromIdx, 1);
    order.splice(toIdx, 0, this.draggingSlot);
    this.slotOrder = order;
    this.draggingSlot = null;
    this.dragOverSlot = null;
  }

  @action onDragEnd() {
    this.draggingSlot = null;
    this.dragOverSlot = null;
  }

  <template>
    <div class='slot-canvas' ...attributes>
      {{#each this.slotOrder as |slotName|}}
        <div
          class='slot
            {{if (eq this.dragOverSlot slotName) "drag-over"}}
            {{if (eq this.draggingSlot slotName) "dragging"}}'
          data-slot={{slotName}}
          draggable={{if @canEdit 'true' 'false'}}
          {{on 'dragstart' (fn this.onDragStart slotName)}}
          {{on 'dragover' (fn this.onDragOver slotName)}}
          {{on 'drop' (fn this.onDrop slotName)}}
          {{on 'dragend' this.onDragEnd}}
        >
          {{#if @canEdit}}
            <span class='drag-handle' aria-hidden='true'>⠿</span>
          {{/if}}
          {{yield slotName to='slot'}}
        </div>
      {{/each}}
    </div>
    <style scoped>
      .slot-canvas {
        position: relative;
      }
      .slot {
        position: relative;
      }
      .drag-handle {
        position: absolute;
        left: -28px;
        top: 8px;
        opacity: 0;
        cursor: grab;
        color: var(--boxel-400);
        font-size: 1.1rem;
        user-select: none;
        line-height: 1;
      }
      .slot:hover .drag-handle {
        opacity: 1;
      }
      .slot.drag-over {
        outline: 2px dashed var(--boxel-highlight, #7b61ff);
        border-radius: var(--boxel-border-radius-sm);
      }
      .slot.dragging {
        opacity: 0.4;
      }
    </style>
  </template>
}
