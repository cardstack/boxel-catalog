import Component from '@glimmer/component';

export type AccessoryKind = 'label' | 'description' | 'status';
export type AccessoryPosition =
  | 'block-start'
  | 'block-end'
  | 'inline-start'
  | 'inline-end';
export type AccessoryTone = 'neutral' | 'info' | 'success' | 'warn' | 'danger';

export interface AccessorySignature {
  Args: {
    id?: string;
    kind?: AccessoryKind;
    labelFor?: string;
    position?: AccessoryPosition;
    tone?: AccessoryTone;
    decorative?: boolean;
  };
  Blocks: {
    default: [];
  };
  Element: HTMLSpanElement;
}

export interface AccessoryAliasSignature {
  Args: {
    id?: string;
    for?: string;
    labelFor?: string;
    position?: AccessoryPosition;
    tone?: AccessoryTone;
    decorative?: boolean;
  };
  Blocks: {
    default: [];
  };
  Element: HTMLSpanElement;
}

export class Accessory extends Component<AccessorySignature> {
  get kind(): AccessoryKind {
    return this.args.kind ?? 'label';
  }

  get position(): AccessoryPosition {
    return this.args.position ?? 'block-start';
  }

  get tone(): AccessoryTone {
    return this.args.tone ?? 'neutral';
  }

  get id(): string | undefined {
    return this.args.id ?? this.generatedId;
  }

  get generatedId(): string | undefined {
    if (!this.args.labelFor) return undefined;
    return `${this.args.labelFor}-${this.kind}`;
  }

  get role(): string | undefined {
    if (this.kind === 'status') return 'status';
    return undefined;
  }

  get ariaLive(): string | undefined {
    if (this.kind === 'status') return 'polite';
    return undefined;
  }

  get ariaHidden(): string | undefined {
    if (this.args.decorative) return 'true';
    return undefined;
  }

  <template>
    <span
      id={{this.id}}
      class='surface-accessory'
      data-surface-accessory={{this.kind}}
      data-surface-accessory-position={{this.position}}
      data-surface-accessory-tone={{this.tone}}
      data-label-for={{@labelFor}}
      role={{this.role}}
      aria-live={{this.ariaLive}}
      aria-hidden={{this.ariaHidden}}
      ...attributes
    >
      {{yield}}
    </span>
  </template>
}

abstract class SurfaceAccessoryAlias extends Component<AccessoryAliasSignature> {
  abstract get kind(): AccessoryKind;

  get labelFor(): string | undefined {
    return this.args.for ?? this.args.labelFor;
  }

  <template>
    <Accessory
      @id={{@id}}
      @kind={{this.kind}}
      @labelFor={{this.labelFor}}
      @position={{@position}}
      @tone={{@tone}}
      @decorative={{@decorative}}
      ...attributes
    >
      {{yield}}
    </Accessory>
  </template>
}

export class CueLabel extends SurfaceAccessoryAlias {
  get kind(): AccessoryKind {
    return 'label';
  }
}

export class CueDescription extends SurfaceAccessoryAlias {
  get kind(): AccessoryKind {
    return 'description';
  }
}

export class CueStatus extends SurfaceAccessoryAlias {
  get kind(): AccessoryKind {
    return 'status';
  }
}
