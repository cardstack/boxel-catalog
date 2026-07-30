import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from 'https://cardstack.com/base/card-api';
import { htmlSafe } from '@ember/template';

// swatch colors come from LLM output — only a validated hex may reach an
// inline style
function safeSwatchStyle(color: string) {
  let hex = /^#[0-9a-fA-F]{3,8}$/.test(color) ? color : '#8a8f9c';
  return htmlSafe(`background-color: ${hex}`);
}
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import ColorField from 'https://cardstack.com/base/color';
import enumField from 'https://cardstack.com/base/enum';

export const PRIMITIVES = [
  'group',
  'box',
  'roundedBox',
  'cylinder',
  'capsule',
  'sphere',
  'hemisphere',
  'cone',
  'torus',
  'lathe',
  'plane',
  'disc',
  'flatRing',
  'arch',
  'prism',
  'tube',
  'bone',
  'rock',
  'blob',
  'meshAsset',
  'glow',
  'roundedPlate',
  'extrudedPolygon',
  'extrudedSpline',
  'textDecal',
  'curvedDecal',
] as const;

const PrimitiveField = enumField(StringField, {
  options: [...PRIMITIVES],
  displayName: 'Primitive',
});

const ObjectClassField = enumField(StringField, {
  options: ['hard-surface', 'organic', 'hybrid'],
  displayName: 'Object Class',
});

const ComplexityField = enumField(StringField, {
  options: ['simple', 'moderate', 'complex'],
  displayName: 'Complexity',
});

// which backend the analysis recommends for this object. "primitive" is the
// only one wired today; "mesh" flags an object (a firearm, a face) the
// primitive vocabulary can only approximate, so a future mesh service can
// route it — see prompts/analyze.gts BACKEND rule.
const BuildBackendField = enumField(StringField, {
  options: ['primitive', 'mesh'],
  displayName: 'Build Backend',
});

// PBR parameters for one THREE.MeshStandardMaterial, referenced from
// component nodes by materialId.
export class MaterialSpecField extends FieldDef {
  static displayName = 'Sculpt Material';
  @field title = contains(StringField, {
    computeVia: function (this: MaterialSpecField) {
      return this.materialId || 'material';
    },
  });
  @field materialId = contains(StringField);
  @field baseColor = contains(ColorField);
  @field roughness = contains(NumberField);
  @field metalness = contains(NumberField);
  @field opacity = contains(NumberField);
  @field emissive = contains(ColorField);
  // optional MeshPhysicalMaterial extensions — either set switches the
  // interpreter from MeshStandardMaterial to MeshPhysicalMaterial
  @field clearcoat = contains(NumberField);
  @field sheen = contains(NumberField);
  // 0-1 see-through glass (window panes, bottles, lenses) — rendered with
  // refraction, unlike plain low opacity
  @field transmission = contains(NumberField);
  // optional procedural surface finish painted by the interpreter
  // (worn | brushed | hazard | tread | camo | louver | patina | knurl)
  @field finish = contains(StringField);
  // optional emissive strength 0-2 (LED strips vs faint warm glow)
  @field emissiveIntensity = contains(NumberField);
}

// One node in the model tree. Nodes form a flat list linked by parentId
// (FieldDefs cannot nest recursively); the interpreter rebuilds the tree.
// dimensions/position/rotation/scale hold JSON number arrays as strings so
// the LLM can author them directly and humans can tweak them in edit view.
export class ComponentNodeField extends FieldDef {
  static displayName = 'Sculpt Component';
  @field title = contains(StringField, {
    computeVia: function (this: ComponentNodeField) {
      let name = this.nodeId || 'node';
      return this.primitive ? `${name} · ${this.primitive}` : name;
    },
  });
  @field nodeId = contains(StringField);
  @field parentId = contains(StringField);
  @field primitive = contains(PrimitiveField);
  @field dimensions = contains(StringField);
  @field position = contains(StringField);
  @field rotation = contains(StringField);
  @field scale = contains(StringField);
  @field materialId = contains(StringField);
  // textDecal only: the label/wordmark text rendered onto the decal plane
  @field text = contains(StringField);
  // analysis partPlan name this component realizes. The draft measurement
  // pass groups components by this value and reconciles their world-space
  // bounds against the reference-image bbox for that semantic part.
  @field partRef = contains(StringField);
  // analysis partPlan name whose reference crop supplies decal artwork, plus
  // the resolved realm URL written by the studio before code export.
  @field textureRef = contains(StringField);
  @field textureUrl = contains(StringField);
  // optional repetition system (JSON string): one declared part expands into
  // N placed clones — rivet rows, wheel sets, vent slats (War-Hauler style)
  @field repeat = contains(StringField);
  // meshAsset only: URL of a .glb in the realm (hybrid pipeline — a
  // service-generated or exported mesh placed inside the procedural graph)
  @field assetUrl = contains(StringField);
  // nodeId of the part this one physically mounts on — the interpreter's
  // constraint solver pulls the part into contact with it (fixes lateral
  // disconnection that gravity snap can't reach)
  @field attachTo = contains(StringField);
  @field note = contains(StringField);
}

const InputKindField = enumField(StringField, {
  options: ['object', 'flat-graphic'],
  displayName: 'Input Kind',
});

export class SculptSpecField extends FieldDef {
  static displayName = 'Sculpt Spec';
  @field objectName = contains(StringField);
  @field inputKind = contains(InputKindField);
  // 3-5 identity-defining features the refine loop must verify one by one —
  // a pass is not accepted while any of these still fails (img2threejs's
  // per-feature gate: a good global score cannot excuse a wrong feature)
  @field identityFeatures = containsMany(StringField);
  @field objectClass = contains(ObjectClassField);
  @field buildBackend = contains(BuildBackendField);
  @field complexity = contains(ComplexityField);
  @field components = containsMany(ComponentNodeField);
  @field materials = containsMany(MaterialSpecField);

  static embedded = class Embedded extends Component<typeof SculptSpecField> {
    get partCount() {
      return this.args.model?.components?.length ?? 0;
    }
    get materialSwatches() {
      return (this.args.model?.materials ?? [])
        .map((m: any) => ({
          id: m?.materialId ?? '',
          style: safeSwatchStyle(m?.baseColor || '#8a8f9c'),
        }))
        .slice(0, 8);
    }
    <template>
      <div class='spec'>
        <header class='spec-head'>
          <h4 class='spec-name'>{{if
              @model.objectName
              @model.objectName
              'untitled spec'
            }}</h4>
          <span class='spec-count'>{{this.partCount}} parts</span>
        </header>
        <ul class='spec-chips'>
          {{#if @model.objectClass}}<li>{{@model.objectClass}}</li>{{/if}}
          {{#if @model.buildBackend}}<li>{{@model.buildBackend}}</li>{{/if}}
          {{#if @model.complexity}}<li>{{@model.complexity}}</li>{{/if}}
          {{#if @model.inputKind}}<li>{{@model.inputKind}}</li>{{/if}}
        </ul>
        {{#if this.materialSwatches.length}}
          <ul class='spec-swatches' aria-label='Materials'>
            {{#each this.materialSwatches as |swatch|}}
              <li
                class='swatch'
                title={{swatch.id}}
                style={{swatch.style}}
              ></li>
            {{/each}}
          </ul>
        {{/if}}
        {{#if @model.identityFeatures.length}}
          <ul class='spec-features'>
            {{#each @model.identityFeatures as |feature|}}
              <li>{{feature}}</li>
            {{/each}}
          </ul>
        {{/if}}
      </div>
      <style scoped>
        .spec {
          display: flex;
          flex-direction: column;
          gap: 0.45rem;
          padding: 0.7rem 0.85rem;
          border: 1px solid var(--i3d-border, var(--border, #232838));
          border-radius: 0.6rem;
          background: var(--i3d-surface, var(--card, #14161e));
          color: var(--i3d-text, var(--foreground, #eef0f6));
          font-family: var(
            --i3d-font-sans,
            var(--font-sans, -apple-system, BlinkMacSystemFont, sans-serif)
          );
        }
        .spec-head {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 0.5rem;
        }
        .spec-name {
          margin: 0;
          font-size: 0.9rem;
        }
        .spec-count {
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.65rem;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--i3d-accent, var(--accent, #38e8ff));
          white-space: nowrap;
        }
        .spec-chips {
          display: flex;
          flex-wrap: wrap;
          gap: 0.3rem;
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .spec-chips li {
          padding: 0.1rem 0.5rem;
          border: 1px solid var(--i3d-border, var(--border, #232838));
          border-radius: 999px;
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.62rem;
          color: var(--i3d-text-dim, var(--muted-foreground, #9aa0b2));
        }
        .spec-swatches {
          display: flex;
          gap: 0.3rem;
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .swatch {
          width: 0.95rem;
          height: 0.95rem;
          border-radius: 50%;
          border: 1px solid var(--i3d-border, var(--border, #232838));
        }
        .spec-features {
          margin: 0;
          padding-left: 1rem;
          font-size: 0.72rem;
          line-height: 1.5;
          color: var(--i3d-text-dim, var(--muted-foreground, #9aa0b2));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof SculptSpecField> {
    get partCount() {
      return this.args.model?.components?.length ?? 0;
    }
    <template>
      <span class='spec-atom'>{{if @model.objectName @model.objectName 'spec'}}
        ·
        {{this.partCount}}
        parts</span>
      <style scoped>
        .spec-atom {
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.75rem;
        }
      </style>
    </template>
  };
}
