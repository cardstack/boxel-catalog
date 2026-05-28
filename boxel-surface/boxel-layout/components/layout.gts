import Component from '@glimmer/component';
import { consume } from 'ember-provide-consume-context';
import {
  InspectContextName,
  Layout as FoundationLayout,
  ModeContextName,
  type SurfaceComponentSignature as FoundationSignature,
  type FociNodePolicy,
  type Target,
} from '../../components/surface-component.gts';

export type LayoutPreset = 'bare' | 'page' | 'notebook' | 'tools';

export interface LayoutSignature {
  Args: FoundationSignature['Args'] & {
    /** Visual layout preset. `bare` keeps the foundation surface headless. */
    preset?: LayoutPreset;
  };
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class Layout extends Component<LayoutSignature> {
  @consume(InspectContextName) declare inheritedInspect: boolean | undefined;
  @consume(ModeContextName) declare inheritedMode:
    | 'use'
    | 'change'
    | 'inspect'
    | undefined;

  get preset(): LayoutPreset {
    return this.args.preset ?? 'page';
  }

  get rootClass(): string {
    return ['boxel-layout', `boxel-layout--${this.preset}`].join(' ');
  }

  get inspect(): boolean {
    const mode = this.args.mode ?? this.inheritedMode;
    return this.args.inspect ?? this.inheritedInspect ?? mode === 'inspect';
  }

  get runtimePolicy(): FociNodePolicy | undefined {
    const policy: FociNodePolicy = {
      ...(this.args.runtimePolicy ?? {}),
    };

    if (!this.inspect) {
      policy.adornments = {
        focus: 'none',
        selection: 'none',
        source: 'none',
        context: 'none',
        hover: 'none',
        inspect: 'none',
        ...(policy.adornments ?? {}),
      };
    }

    return Object.keys(policy).length > 0 ? policy : undefined;
  }

  get target(): Target | undefined {
    return this.args.target ?? (this.inspect ? undefined : 'structure');
  }

  <template>
    <FoundationLayout
      class={{this.rootClass}}
      data-bx-layout-preset={{this.preset}}
      @id={{@id}}
      @focusKey={{@focusKey}}
      @surfacePath={{@surfacePath}}
      @space={{@space}}
      @model={{@model}}
      @field={{@field}}
      @fields={{@fields}}
      @schema={{@schema}}
      @coord={{@coord}}
      @identity={{@identity}}
      @key={{@key}}
      @identityPart={{@identityPart}}
      @tag={{@tag}}
      @inline={{@inline}}
      @role={{@role}}
      @pattern={{@pattern}}
      @preset={{this.preset}}
      @aspects={{@aspects}}
      @runtimePolicy={{this.runtimePolicy}}
      @runtimeTraversal={{@runtimeTraversal}}
      @runtimeTraversalModel={{@runtimeTraversalModel}}
      @runtimeSelection={{@runtimeSelection}}
      @runtimeKeyboard={{@runtimeKeyboard}}
      @runtimeMovement={{@runtimeMovement}}
      @runtimePointer={{@runtimePointer}}
      @runtimeEdit={{@runtimeEdit}}
      @accepts={{@accepts}}
      @payloadType={{@payloadType}}
      @scope={{@scope}}
      @depth={{@depth}}
      @expanded={{@expanded}}
      @onSelect={{@onSelect}}
      @onActivate={{@onActivate}}
      @scrollOnSelect={{@scrollOnSelect}}
      @scrollTarget={{@scrollTarget}}
      @scrollAnchor={{@scrollAnchor}}
      @hoverSignal={{@hoverSignal}}
      @hoverAnchor={{@hoverAnchor}}
      @onExpand={{@onExpand}}
      @onCollapse={{@onCollapse}}
      @demo={{@demo}}
      @posture={{@posture}}
      @mode={{@mode}}
      @inspect={{@inspect}}
      @changeRoute={{@changeRoute}}
      @target={{this.target}}
      @targetScope={{@targetScope}}
      @coordinateSpace={{@coordinateSpace}}
      @at={{@at}}
      @change={{@change}}
      @lift={{@lift}}
      @liftData={{@liftData}}
      @inlineEdit={{@inlineEdit}}
      @editValue={{@editValue}}
      @editLabel={{@editLabel}}
      @editMultiline={{@editMultiline}}
      @onEditInput={{@onEditInput}}
      ...attributes
    >
      {{yield}}
    </FoundationLayout>

    <style scoped>
      :where(.boxel-layout) {
        box-sizing: border-box;
        min-width: 0;
        color: var(--boxel-layout-fg, inherit);
      }

      :where(.boxel-layout > [data-surface-component]) {
        min-width: 0;
      }

      :where(.boxel-layout--bare) {
        display: revert;
        width: revert;
        margin: revert;
        padding: revert;
      }

      :where(.boxel-layout--page) {
        display: grid;
        width: min(100%, var(--boxel-layout-max-inline-size, 72rem));
        margin-inline: auto;
        padding: var(--boxel-layout-padding, clamp(1.25rem, 4vw, 2.5rem));
        gap: var(--boxel-layout-gap, 1.5rem);
      }

      :where(.boxel-layout--page > [data-surface-component]) {
        display: grid;
        gap: var(--boxel-layout-block-gap, 0.75rem);
      }

      :where(.boxel-layout--notebook) {
        display: grid;
        width: 100%;
        padding: var(--boxel-layout-padding, 1rem);
        gap: var(--boxel-layout-gap, 0.875rem);
        background: var(--boxel-layout-bg, #f8fafc);
      }

      :where(.boxel-layout--notebook > [data-surface-component]) {
        display: grid;
        gap: var(--boxel-layout-block-gap, 0.5rem);
        padding-block: var(--boxel-layout-block-padding, 0.625rem);
        border-top: 1px solid var(--boxel-layout-divider, #e2e8f0);
      }

      :where(.boxel-layout--notebook > [data-surface-component]:first-child) {
        border-top: 0;
        padding-top: 0;
      }

      :where(.boxel-layout--tools) {
        display: grid;
        width: 100%;
        align-content: start;
        gap: var(--boxel-layout-gap, 0.625rem);
        padding: var(--boxel-layout-padding, 0.75rem);
        border: 1px solid var(--boxel-layout-border, #d1d5db);
        border-radius: var(--boxel-layout-radius, 8px);
        background: var(--boxel-layout-bg, #f9fafb);
      }

      :where(.boxel-layout--tools > [data-surface-component]) {
        display: grid;
        gap: var(--boxel-layout-block-gap, 0.375rem);
        padding-block: var(--boxel-layout-block-padding, 0.375rem);
        border-bottom: 1px solid var(--boxel-layout-divider, #e5e7eb);
      }

      :where(.boxel-layout--tools > [data-surface-component]:last-child) {
        border-bottom: 0;
        padding-bottom: 0;
      }
    </style>
  </template>
}
