import { module, test } from 'qunit';

import {
  dropHairlineParts,
  enforceAttachments,
  groundSupports,
  resolveBuriedParts,
  flagInstanceCollisions,
  repairPrimitiveConventions,
  dropUnplannedParts,
  flagOverbuiltParts,
  reconcileProportions,
  alignFaceFeatures,
  ensureFaceParts,
  seatRingCollars,
  clampInteriorCavities,
  seatRecesses,
} from './spec-passes/index';
import { seatSurfaceParts } from './surface-seat';
import {
  applySpecDiff,
  isRemovalInstruction,
  narrowRemovalTargets,
} from './spec-diff';
import { serializeSpecForPrompt } from './spec-io';
import { seedFromStrings } from './llm-request';
import { revolvedSilhouetteBbox } from './silhouette';
import { selectRecipeNames, selectRecipes } from '../prompts/recipes';
import { buildSpecSystemPrompt } from '../prompts/spec';
import { generateModelJs, specFromModelJs, GEOMETRY_CASES } from './code-export';
import { runStructurePasses } from './spec-passes/run-all';
import { PRIMITIVES } from '../fields/sculpt-spec';

function testSpec(dimensions: number[] | string = [0.015]) {
  return {
    objectName: 'Rivet regression',
    inputKind: 'object',
    objectClass: 'hard-surface',
    complexity: 'simple',
    identityFeatures: ['small rivet'],
    materials: [
      {
        materialId: 'metal',
        baseColor: '#888888',
        roughness: 0.5,
        metalness: 0.8,
      },
    ],
    components: [
      {
        nodeId: 'rivet',
        parentId: 'root',
        primitive: 'sphere',
        dimensions,
        position: [0, 0, 0],
        rotation: [0, 0, 0],
        scale: [1, 1, 1],
        materialId: 'metal',
        partRef: 'small rivet',
        textureRef: 'small rivet',
        textureUrl: 'https://example.test/rivet.webp',
        note: 'small rivet',
      },
    ],
  };
}

export function runTests() {
  module('Unit | img-to-3d generation', function () {
    test('one-value dimensions survive prompt serialization and refinement', function (assert) {
      let direct = serializeSpecForPrompt(testSpec());
      assert.deepEqual(
        direct.components[0].dimensions,
        [0.015],
        'an existing array remains an array',
      );

      let stringEncoded = serializeSpecForPrompt(testSpec('[0.015]'));
      assert.deepEqual(
        stringEncoded.components[0].dimensions,
        [0.015],
        'a card-field JSON string is decoded into an array',
      );

      let refined = applySpecDiff(testSpec(), {
        score: 80,
        changed: [
          {
            nodeId: 'rivet',
            primitive: 'box',
            dimensions: [5, 5, 5],
            scale: [1.1, 1.1, 1.1],
          },
        ],
        removedNodeIds: ['rivet'],
        materialsChanged: [],
      });
      assert.strictEqual(
        refined.components[0].primitive,
        'sphere',
        'refine cannot change a primitive',
      );
      assert.deepEqual(
        refined.components[0].dimensions,
        [0.015],
        'refine cannot change the sphere radius',
      );
      assert.deepEqual(
        refined.components[0].scale,
        [1.1, 1.1, 1.1],
        'placement changes are still applied',
      );
      assert.strictEqual(
        refined.components.length,
        1,
        'refine cannot delete an existing component',
      );
    });

    test('generated model source preserves measurement and texture metadata', function (assert) {
      let roundTripped = specFromModelJs(generateModelJs(testSpec()));
      assert.deepEqual(
        roundTripped?.components[0].dimensions,
        [0.015],
        'the generated source keeps one-value dimensions',
      );
      assert.strictEqual(
        roundTripped?.components[0].partRef,
        'small rivet',
        'partRef survives the generated source round trip',
      );
      assert.strictEqual(
        roundTripped?.components[0].textureUrl,
        'https://example.test/rivet.webp',
        'the resolved texture URL survives the generated source round trip',
      );
    });

    test('measured reconciliation updates mapped component scale and position', function (assert) {
      let parsed = {
        components: [
          {
            nodeId: 'body',
            primitive: 'box',
            dimensions: [10, 10, 1],
            position: [5, 5, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'body',
          },
          {
            nodeId: 'detail',
            primitive: 'box',
            dimensions: [1, 1, 1],
            position: [0, 0, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'detail',
          },
        ],
      };
      let result = reconcileProportions(
        parsed,
        {
          camera: { azimuthDeg: 0, elevationDeg: 0 },
          partPlan: [
            {
              part: 'body',
              bbox: { left: 0, top: 0, width: 1, height: 1 },
            },
            {
              part: 'detail',
              bbox: { left: 0.6, top: 0.2, width: 0.3, height: 0.4 },
            },
          ],
        },
        {
          whole: { min: [0, 0, 0], max: [10, 10, 1] },
          parts: [
            { name: 'body', min: [0, 0, 0], max: [10, 10, 1] },
            { name: 'detail', min: [0, 0, 0], max: [1, 1, 1] },
          ],
        },
      );

      assert.true(
        result.logs.some((line) => line.includes("reconciled 'detail'")),
        'the mapped detail is reconciled',
      );
      assert.deepEqual(
        parsed.components[1].scale,
        [2.5, 2.5, 2.5],
        'the detail is scaled toward its measured target bbox',
      );
      assert.notDeepEqual(
        parsed.components[1].position,
        [0, 0, 0],
        'the detail is recentered toward its measured target bbox',
      );
    });

    test('components the analysis never planned are dropped with their children', function (assert) {
      let parsed = {
        components: [
          { nodeId: 'root', primitive: 'group' },
          {
            nodeId: 'body',
            parentId: 'root',
            primitive: 'lathe',
            partRef: 'glass body',
          },
          // punctuation and wording drift must NOT cost a real part
          {
            nodeId: 'cap',
            parentId: 'root',
            primitive: 'cylinder',
            partRef: 'screw-cap',
          },
          // invented: the reference has no mould seam
          {
            nodeId: 'body-seam',
            parentId: 'root',
            primitive: 'tube',
            partRef: 'mould seam',
          },
          // invented, and something hangs off it
          {
            nodeId: 'neck-collar',
            parentId: 'root',
            primitive: 'torus',
            partRef: 'seam ring',
          },
          {
            nodeId: 'collar-rib',
            parentId: 'neck-collar',
            primitive: 'torus',
            partRef: 'seam ring',
          },
          // no partRef at all
          { nodeId: 'mystery', parentId: 'root', primitive: 'box' },
          // the one allowed unplanned part
          {
            nodeId: 'ground-shadow',
            parentId: 'root',
            primitive: 'disc',
          },
        ],
      };
      let logs = dropUnplannedParts(parsed, {
        partPlan: [{ part: 'glass body' }, { part: 'screwcap' }],
      });
      assert.deepEqual(
        parsed.components.map((c: any) => c.nodeId),
        ['root', 'body', 'cap', 'ground-shadow'],
        'only planned parts, groups and the ground shadow survive',
      );
      assert.true(
        logs.some((line) => line.includes("dropped 'collar-rib'")),
        'a child of a dropped part is dropped too',
      );

      let untouched = { components: [{ nodeId: 'a', primitive: 'box' }] };
      assert.deepEqual(
        dropUnplannedParts(untouched, { partPlan: [] }),
        [],
        'with no plan to check against the gate stays shut',
      );
      assert.strictEqual(
        untouched.components.length,
        1,
        'a plan-less spec keeps every component',
      );
    });

    test('copies that eat into each other are reported, spaced ones are not', function (assert) {
      // the real case: 1.10-wide wheels on an 0.85 axle spacing
      let logs = flagInstanceCollisions({
        components: [
          {
            nodeId: 'wheel-row',
            primitive: 'cylinder',
            dimensions: [0.55, 0.55, 0.32, 24],
            position: [0.68, 0.55, -0.85],
            scale: [1, 1, 1],
            repeat: { count: 3, mode: 'linear', offset: [0, 0, 0.85] },
          },
          // authored one by one, so no repeat check would see them
          {
            nodeId: 'front-wheel',
            primitive: 'cylinder',
            dimensions: [0.55, 0.55, 0.32, 24],
            position: [-0.68, 0.55, -0.85],
            scale: [1, 1, 1],
          },
          {
            nodeId: 'mid-wheel',
            primitive: 'cylinder',
            dimensions: [0.55, 0.55, 0.32, 24],
            position: [-0.68, 0.55, 0],
            scale: [1, 1, 1],
          },
          // a properly spaced row must stay quiet
          {
            nodeId: 'rivets',
            primitive: 'sphere',
            dimensions: [0.02],
            position: [0, 1, 0],
            scale: [1, 1, 1],
            repeat: { count: 8, mode: 'linear', offset: [0.12, 0, 0] },
          },
        ],
      });
      assert.true(
        logs.some(
          (l) => l.includes("'wheel-row'") && l.includes('overlap by 0.25'),
        ),
        'a repeat step shorter than the part is reported with the overlap',
      );
      assert.true(
        logs.some(
          (l) => l.includes("'front-wheel'") && l.includes("'mid-wheel'"),
        ),
        'individually authored copies of one feature are caught too',
      );
      assert.false(
        logs.some((l) => l.includes("'rivets'")),
        'a well-spaced rivet row is not reported',
      );
    });

    test("a tube's position is zeroed because its points already place it", function (assert) {
      let spec = {
        components: [
          {
            nodeId: 'exhaust',
            primitive: 'tube',
            dimensions: [0.06, -0.5, 1.55, -0.4, -0.5, 1.6, 0.2],
            position: [0, -1.2602, 0],
          },
          {
            nodeId: 'hull',
            primitive: 'box',
            dimensions: [1, 1, 2],
            position: [0, 1, 0],
          },
        ],
      };
      let logs = repairPrimitiveConventions(spec);
      assert.deepEqual(
        spec.components[0].position,
        [0, 0, 0],
        'the double offset is removed',
      );
      assert.deepEqual(
        spec.components[1].position,
        [0, 1, 0],
        'other primitives keep their position',
      );
      assert.strictEqual(logs.length, 1, 'the repair is reported once');
    });

    test('repeated reconcile rounds cannot compound a part into a wafer', function (assert) {
      let spec = {
        components: [
          {
            nodeId: 'platform',
            primitive: 'box',
            dimensions: [1, 0.12, 0.7],
            position: [0, 2, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'platform',
          },
          {
            nodeId: 'rail',
            primitive: 'box',
            dimensions: [1, 0.4, 0.06],
            position: [0, 2.2, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'railing',
          },
        ],
      };
      // a bbox that keeps asking for a big shrink, run as five refine rounds
      let analysis = {
        camera: { azimuthDeg: 0, elevationDeg: 0 },
        partPlan: [
          {
            part: 'platform',
            bbox: { left: 0, top: 0.5, width: 1, height: 0.5 },
          },
          {
            part: 'railing',
            bbox: { left: 0, top: 0, width: 1, height: 0.02 },
          },
        ],
      };
      let measured = {
        whole: { min: [0, 0, 0], max: [1, 1, 1] },
        parts: [
          { name: 'platform', min: [0, 0, 0], max: [1, 0.5, 0.7] },
          { name: 'rail', min: [0, 0.5, 0], max: [1, 1, 0.06] },
        ],
      };
      let lastLogs: string[] = [];
      for (let round = 0; round < 5; round++) {
        lastLogs = reconcileProportions(spec, analysis, measured).logs;
      }
      assert.strictEqual(
        spec.components[1].scale[1],
        0.4,
        'five rounds hold at the floor instead of multiplying to 0.4^5',
      );
      assert.true(
        lastLogs.some((line) => line.includes('compounding')),
        'the held clamp is reported',
      );
    });

    test('a mirrored pair on one host is recentred, pieces on two hosts are not', function (assert) {
      let pair = (host: string) => ({
        components: [
          {
            nodeId: 'host',
            primitive: 'sphere',
            dimensions: [1],
            position: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'host',
          },
          {
            nodeId: 'left',
            primitive: 'sphere',
            dimensions: [0.1],
            position: [-0.5, 0, 1],
            scale: [1, 1, 1],
            partRef: 'eyes',
            attachTo: 'host',
          },
          {
            nodeId: 'right',
            primitive: 'sphere',
            dimensions: [0.1],
            position: [0.5, 0, 1],
            scale: [1, 1, 1],
            partRef: 'eyes',
            attachTo: host,
          },
        ],
      });
      let analysis = {
        camera: { azimuthDeg: 0, elevationDeg: 0 },
        partPlan: [
          { part: 'host', bbox: { left: 0, top: 0, width: 1, height: 1 } },
          // the plan measures the eyes near the TOP of the object; both specs
          // build them at mid-height, so a correction is owed
          {
            part: 'eyes',
            bbox: { left: 0.2, top: 0.1, width: 0.6, height: 0.1 },
          },
        ],
      };
      let measured = {
        whole: { min: [-1, -1, -1], max: [1, 1, 1] },
        parts: [
          { name: 'host', min: [-1, -1, -1], max: [1, 1, 1] },
          { name: 'left', min: [-0.6, -0.1, 0.9], max: [-0.4, 0.1, 1.1] },
          { name: 'right', min: [0.4, -0.1, 0.9], max: [0.6, 0.1, 1.1] },
        ],
      };
      let shared = pair('host');
      let split = pair('other-host');
      let sharedLogs = reconcileProportions(shared, analysis, measured).logs;
      let splitLogs = reconcileProportions(split, analysis, measured).logs;

      assert.true(
        shared.components[1].position[1] > 0,
        'two eyes on one host move together to the height the plan measured',
      );
      assert.false(
        sharedLogs.some((line) => line.includes('separate pieces')),
        'a mirrored pair is not treated as unplaceable',
      );
      assert.strictEqual(
        split.components[1].position[1],
        0,
        'pieces naming different hosts keep their authored placement',
      );
      assert.true(
        splitLogs.some((line) => line.includes('separate pieces')),
        'and the withheld move is reported',
      );
    });

    test('a part buried in its own declared support is left to the seater', function (assert) {
      let buried = (attachTo: string | undefined) => ({
        components: [
          {
            nodeId: 'muzzle',
            primitive: 'sphere',
            dimensions: [1],
            position: [0, 0, 0],
            scale: [1, 1, 1],
          },
          {
            nodeId: 'eye',
            primitive: 'sphere',
            dimensions: [0.1],
            position: [0, 0, 0.85],
            scale: [1, 1, 1],
            attachTo,
          },
        ],
      });
      let declared = buried('muzzle');
      let undeclared = buried(undefined);
      resolveBuriedParts(declared);
      let logs = resolveBuriedParts(undeclared);

      assert.deepEqual(
        declared.components[1].position,
        [0, 0, 0.85],
        'this pass leaves a declared joint alone — its cheapest box exit is not always a visible one',
      );
      assert.true(
        logs.some((line) => line.includes("pushed 'eye'")),
        'burial in a part the spec never claimed to mount on is still handled here',
      );
    });

    test('a part swallowed by its neighbour is reported, a seated one is not', function (assert) {
      let logs = resolveBuriedParts({
        components: [
          {
            nodeId: 'storey',
            primitive: 'box',
            dimensions: [2, 1, 2],
            position: [0, 1.5, 0],
            scale: [1, 1, 1],
          },
          // a hip roof seated on the same support as the storey above it, so it
          // ends up inside that storey and never renders
          {
            nodeId: 'lower-roof',
            primitive: 'cone',
            dimensions: [1.3, 0.8, 4],
            position: [0, 1.5, 0],
            scale: [1, 1, 1],
          },
          // resting ON the storey: overlapping by the mandated 0.03 but not buried
          {
            nodeId: 'rail',
            primitive: 'box',
            dimensions: [1.5, 0.1, 0.1],
            position: [0, 2.02, 0],
            scale: [1, 1, 1],
          },
          // a window is MEANT to sit inside its wall — plates are exempt
          {
            nodeId: 'window',
            primitive: 'box',
            dimensions: [0.6, 0.5, 0.02],
            position: [0, 1.5, 0.99],
            scale: [1, 1, 1],
          },
        ],
      });
      assert.strictEqual(logs.length, 1, 'exactly one part is acted on');
      assert.true(
        logs[0].includes("'lower-roof'") && logs[0].includes("'storey'"),
        'the buried roof is named along with what swallowed it',
      );
    });

    test('wheels placed above the hull are mirrored underneath it', function (assert) {
      // the real failure: the analysis wrote "wheels rests-on main hull body",
      // inverting which part carries which, and the spec obeyed
      let spec = {
        components: [
          {
            nodeId: 'main-hull-body',
            primitive: 'box',
            dimensions: [1.6, 0.9, 2],
            position: [0, 0.45, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'main hull body',
          },
          {
            nodeId: 'wheel-left',
            primitive: 'cylinder',
            dimensions: [0.5, 0.5, 0.45, 24],
            position: [-0.95, 1.095, -0.75],
            rotation: [0, 0, 1.5708],
            scale: [1, 1, 1],
            partRef: 'wheels',
          },
        ],
      };
      let logs = groundSupports(spec);
      let wheel = spec.components[1];
      assert.strictEqual(
        wheel.position[1],
        -0.195,
        'the wheel is reflected to the far side of the hull centre, keeping its distance',
      );
      assert.true(
        logs.some((l) => l.includes("mirrored 'wheel-left'")),
        'the correction is reported',
      );
      // …and the rotation-aware extents are what make it land right: read as an
      // unrotated cylinder the wheel would be 0.45 tall instead of 1.0
      assert.true(
        wheel.position[1] - 0.5 < 0,
        'the wheel now reaches below the hull, so the truck stands on it',
      );

      // an object with no support-shaped parts is left completely alone
      let bottle = {
        components: [
          {
            nodeId: 'body',
            primitive: 'lathe',
            dimensions: [0, 0, 0.35, 2.5],
            position: [0, 1, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'bottle body',
          },
          {
            nodeId: 'cap',
            primitive: 'cylinder',
            dimensions: [0.16, 0.16, 0.3],
            position: [0, 2.5, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'screwcap',
          },
        ],
      };
      assert.deepEqual(
        groundSupports(bottle),
        [],
        'a bottle has no supports to ground, so nothing is touched',
      );
      assert.deepEqual(
        bottle.components[1].position,
        [0, 2.5, 0],
        'and its cap stays on top where it belongs',
      );
    });

    test('a buried part is pushed out through the nearest face', function (assert) {
      let spec = {
        components: [
          {
            nodeId: 'ram-plate',
            primitive: 'box',
            dimensions: [1, 0.75, 0.55],
            position: [0, 0.475, -1.525],
            scale: [1, 1, 1],
          },
          // a headlight modelled entirely inside the plate: invisible
          {
            nodeId: 'headlight',
            primitive: 'sphere',
            dimensions: [0.06],
            position: [-0.35, 0.65, -1.6],
            scale: [1, 1, 1],
          },
          // and one so deep inside a big body that moving it would be a guess
          {
            nodeId: 'hull',
            primitive: 'box',
            dimensions: [4, 4, 4],
            position: [10, 2, 0],
            scale: [1, 1, 1],
          },
          {
            nodeId: 'core',
            primitive: 'sphere',
            dimensions: [0.2],
            position: [10, 2, 0],
            scale: [1, 1, 1],
          },
        ],
      };
      let logs = resolveBuriedParts(spec);
      let light = spec.components[1];
      assert.true(
        logs.some((l) => l.includes("pushed 'headlight'")),
        'the shallow case is repaired',
      );
      // the exit chosen is the CHEAPEST one, not necessarily the one a modeller
      // would pick: this light sits near the plate's left edge, so it leaves
      // through the side rather than the front. The guarantee is visibility,
      // and refine or a lasso edit can still choose a nicer face.
      assert.strictEqual(
        light.position[0],
        -0.53,
        'it now protrudes through the nearest face, keeping a 0.03 overlap',
      );
      assert.deepEqual(
        [light.position[1], light.position[2]],
        [0.65, -1.6],
        'only the chosen axis moves',
      );
      assert.true(
        logs.some(
          (l) => l.includes("'core'") && l.includes('too deep in to move'),
        ),
        'a part at the centre of a large body is reported, not shoved',
      );
      assert.deepEqual(
        spec.components[3].position,
        [10, 2, 0],
        'and it is left exactly where it was',
      );
    });

    test('attachment lines seat a part on its support without re-centring a deliberate offset', function (assert) {
      let spec = {
        components: [
          {
            nodeId: 'wall',
            primitive: 'box',
            dimensions: [3.4, 1.1, 2.6],
            position: [0, 0.34, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'ground floor block',
          },
          // a hip roof sunk half a unit INTO the storey below
          {
            nodeId: 'roof',
            primitive: 'cone',
            dimensions: [2, 0.9, 4],
            position: [0, 1.23, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'lower hipped roof',
          },
          // an upper storey deliberately set back over an L-shaped plan
          {
            nodeId: 'wing',
            primitive: 'box',
            dimensions: [1, 1, 1],
            position: [1.4, 0.6, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'second floor block',
          },
        ],
      };
      let logs = enforceAttachments(spec, {
        attachments: [
          'lower hipped roof centered-above ground floor block',
          'second floor block centered-above ground floor block',
        ],
      });
      let roof = spec.components[1];
      let wing = spec.components[2];
      // the roof's base half-height is 0.45, so sitting on a wall whose top is
      // 0.89 puts its centre at 0.89 - 0.03 + 0.45
      assert.strictEqual(
        roof.position[1],
        1.31,
        'the roof is seated on the storey with a 0.03 overlap',
      );
      assert.deepEqual(
        [roof.position[0], roof.position[2]],
        [0, 0],
        'an already-centred roof stays centred',
      );
      assert.strictEqual(
        wing.position[0],
        1.4,
        'a wing offset well off centre keeps its offset',
      );
      assert.true(
        logs.some((line) => line.includes('looks deliberate')),
        'the kept offset is reported rather than silently overridden',
      );
    });

    test('an aerial reference reconciles sizes but not vertical placement', function (assert) {
      // at 40° elevation a part further BACK simply appears higher up, so a
      // vertical move derived from the image bbox pushes parts apart by their
      // depth — this is what stacked a house into floating slabs
      let build = () => ({
        components: [
          {
            nodeId: 'body',
            primitive: 'box',
            dimensions: [10, 10, 1],
            position: [5, 5, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'body',
          },
          {
            nodeId: 'detail',
            primitive: 'box',
            dimensions: [1, 1, 1],
            position: [0, 0, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            partRef: 'detail',
          },
        ],
      });
      let plan = [
        { part: 'body', bbox: { left: 0, top: 0, width: 1, height: 1 } },
        {
          part: 'detail',
          bbox: { left: 0.6, top: 0.2, width: 0.3, height: 0.4 },
        },
      ];
      let measured = {
        whole: { min: [0, 0, 0], max: [10, 10, 1] },
        parts: [
          { name: 'body', min: [0, 0, 0], max: [10, 10, 1] },
          { name: 'detail', min: [0, 0, 0], max: [1, 1, 1] },
        ],
      };

      let eyeLevel = build();
      reconcileProportions(
        eyeLevel,
        { camera: { azimuthDeg: 0, elevationDeg: 10 }, partPlan: plan },
        measured,
      );
      let aerial = build();
      let result = reconcileProportions(
        aerial,
        { camera: { azimuthDeg: 0, elevationDeg: 40 }, partPlan: plan },
        measured,
      );

      assert.deepEqual(
        aerial.components[1].scale,
        eyeLevel.components[1].scale,
        'the size still reconciles from an aerial view',
      );
      assert.notDeepEqual(
        eyeLevel.components[1].position,
        aerial.components[1].position,
        'the two cameras do not place the part identically',
      );
      assert.true(
        Math.abs(aerial.components[1].position[1]) <
          Math.abs(eyeLevel.components[1].position[1]),
        'the aerial pass withholds the vertical move the eye-level pass applies',
      );
      assert.true(
        result.logs.some((line) => line.includes('above eye level')),
        'the withheld reconciliation is reported',
      );
    });

    test('hairline solids are dropped whatever their partRef claims', function (assert) {
      // the exact evasion seen in the wild: the same two mould-seam tubes were
      // rejected as partRef 'mold seam' one round and accepted as partRef
      // 'bottle body' the next, so this gate reads dimensions, not names
      let parsed = {
        components: [
          { nodeId: 'root', primitive: 'group' },
          {
            nodeId: 'body',
            parentId: 'root',
            primitive: 'lathe',
            dimensions: [0, 0, 0.35, 2.5],
            partRef: 'bottle body',
          },
          {
            nodeId: 'body-seam',
            parentId: 'root',
            primitive: 'tube',
            dimensions: [0.008, -0.41, 0.05, 0, -0.3, 1.9, 0],
            partRef: 'bottle body',
          },
          {
            nodeId: 'knurl',
            parentId: 'root',
            primitive: 'box',
            dimensions: [0.012, 0.28, 0.01],
            partRef: 'screwcap',
          },
          {
            nodeId: 'perforation',
            parentId: 'root',
            primitive: 'torus',
            dimensions: [0.163, 0.006],
            partRef: 'screwcap',
          },
          {
            nodeId: 'knurl-child',
            parentId: 'knurl',
            primitive: 'box',
            dimensions: [0.2, 0.2, 0.2],
            partRef: 'screwcap',
          },
          // a real cap band: thin, but not hairline
          {
            nodeId: 'cap-band',
            parentId: 'root',
            primitive: 'torus',
            dimensions: [0.163, 0.012],
            partRef: 'screwcap',
          },
        ],
      };
      let logs = dropHairlineParts(parsed);
      assert.deepEqual(
        parsed.components.map((c: any) => c.nodeId),
        ['root', 'body', 'cap-band'],
        'wires go, the real band and the body stay',
      );
      assert.true(
        logs.some((line) => line.includes("dropped 'knurl-child'")),
        'a child of a dropped hairline part goes with it',
      );
      assert.true(
        logs.some((line) => line.includes('tube radius 0.008')),
        'the log states the measurement that condemned the part',
      );
    });

    test('padding hidden under one planned part name is reported, chains are not', function (assert) {
      // the real failure: a screwcap the plan calls ONE revolved part, built as
      // body + top + skirt + perforation ring + rib band + knurl ridges + text
      let padded = {
        components: [
          { nodeId: 'cap-group', primitive: 'group', partRef: 'screwcap' },
          { nodeId: 'cap-body', primitive: 'cylinder', partRef: 'screwcap' },
          { nodeId: 'cap-top', primitive: 'disc', partRef: 'screwcap' },
          { nodeId: 'cap-skirt', primitive: 'cylinder', partRef: 'screwcap' },
          { nodeId: 'cap-perf', primitive: 'torus', partRef: 'screwcap' },
          { nodeId: 'cap-rib', primitive: 'torus', partRef: 'screwcap' },
          { nodeId: 'cap-ridges', primitive: 'box', partRef: 'screwcap' },
          { nodeId: 'cap-text', primitive: 'curvedDecal', partRef: 'screwcap' },
          { nodeId: 'body', primitive: 'lathe', partRef: 'bottle body' },
          { nodeId: 'ground-shadow', primitive: 'disc' },
        ],
      };
      let logs = flagOverbuiltParts(padded, {
        partPlan: [
          { part: 'screwcap', approach: 'revolved' },
          { part: 'bottle body', approach: 'revolved' },
        ],
      });
      assert.strictEqual(logs.length, 1, 'only the padded part is reported');
      assert.true(
        logs[0].includes("'screwcap'") && logs[0].includes('7 components'),
        'the report names the part and counts its components, ignoring groups',
      );
      assert.strictEqual(
        padded.components.length,
        10,
        'reporting never deletes — which component is the invented one is unknowable',
      );

      // a chain approach IS many overlapping volumes, so it must stay quiet
      let chain = {
        components: Array.from({ length: 8 }, (_unused, i) => ({
          nodeId: `upper-${i}`,
          primitive: 'sphere',
          partRef: 'shoe upper',
        })),
      };
      assert.deepEqual(
        flagOverbuiltParts(chain, {
          partPlan: [{ part: 'shoe upper', approach: 'curved-chain' }],
        }),
        [],
        'an eight-sphere curved chain is not padding',
      );
    });

    test('the reference seed is stable per image set and distinct across sets', function (assert) {
      let one = ['https://realm/bottle.webp'];
      assert.strictEqual(
        seedFromStrings(one),
        seedFromStrings(['https://realm/bottle.webp']),
        'the same reference set always yields the same seed',
      );
      assert.notStrictEqual(
        seedFromStrings(one),
        seedFromStrings([...one, 'https://realm/side.webp']),
        'adding a view yields a different seed',
      );
      assert.notStrictEqual(
        seedFromStrings(['ab', 'c']),
        seedFromStrings(['a', 'bc']),
        'the separator keeps split boundaries from colliding',
      );
      let seed = seedFromStrings(one);
      assert.true(
        Number.isInteger(seed) && seed >= 0 && seed < 2 ** 31,
        'the seed is a positive integer providers accept',
      );
    });

    // The traced silhouette is not just one part's profile — it also becomes
    // the envelope every solid part is clamped into, so tracing the wrong
    // region displaces the whole build rather than spoiling one component.
    module('surface seating', function () {
      // enough of three.js for the seater, which only ever asks for world
      // boxes and vector arithmetic. Parts are spheres of the given radius,
      // all root-parented, so local coordinates are world coordinates.
      function stubScene(parts: { id: string; at: number[]; r: number[] }[]): {
        THREE: any;
        objects: Map<string, any>;
        at: (id: string) => number[];
      } {
        class V3 {
          x: number;
          y: number;
          z: number;
          constructor(x = 0, y = 0, z = 0) {
            this.x = x;
            this.y = y;
            this.z = z;
          }
          clone() {
            return new V3(this.x, this.y, this.z);
          }
          set(x: number, y: number, z: number) {
            this.x = x;
            this.y = y;
            this.z = z;
            return this;
          }
          copy(v: any) {
            return this.set(v.x, v.y, v.z);
          }
          add(v: any) {
            return this.set(this.x + v.x, this.y + v.y, this.z + v.z);
          }
          sub(v: any) {
            return this.set(this.x - v.x, this.y - v.y, this.z - v.z);
          }
          addScaledVector(v: any, s: number) {
            return this.set(
              this.x + v.x * s,
              this.y + v.y * s,
              this.z + v.z * s,
            );
          }
          divideScalar(s: number) {
            return this.set(this.x / s, this.y / s, this.z / s);
          }
          multiplyScalar(s: number) {
            return this.set(this.x * s, this.y * s, this.z * s);
          }
          dot(v: any) {
            return this.x * v.x + this.y * v.y + this.z * v.z;
          }
          lengthSq() {
            return this.dot(this);
          }
          length() {
            return Math.sqrt(this.lengthSq());
          }
          normalize() {
            return this.divideScalar(this.length() || 1);
          }
        }
        class Box3 {
          obj: any;
          setFromObject(obj: any) {
            this.obj = obj;
            return this;
          }
          isEmpty() {
            return !this.obj;
          }
          getCenter() {
            return this.obj.position.clone();
          }
          getSize() {
            let r = this.obj.radii;
            return new V3(r[0] * 2, r[1] * 2, r[2] * 2);
          }
        }
        let objects = new Map<string, any>();
        for (let part of parts) {
          objects.set(part.id, {
            radii: part.r,
            position: new V3(part.at[0], part.at[1], part.at[2]),
            parent: undefined,
            getWorldPosition() {
              return this.position.clone();
            },
            updateWorldMatrix() {},
          });
        }
        return {
          THREE: { Vector3: V3, Box3 },
          objects,
          at: (id: string) => {
            let p = objects.get(id).position;
            return [p.x, p.y, p.z];
          },
        };
      }

      test('a feature behind the mask it is mounted on is moved to the exposed side', function (assert) {
        // the Mickey case: the muzzle hangs off the front (+z) of the skull,
        // and the eyes were authored BEHIND the muzzle's centre, so every box
        // test called them attached while they rendered inside the head
        let scene = stubScene([
          { id: 'skull', at: [0, 1.7, 0], r: [0.56, 0.43, 0.54] },
          { id: 'muzzle', at: [0, 1.54, 0.66], r: [0.4, 0.29, 0.22] },
          { id: 'eye', at: [0.18, 1.42, 0.42], r: [0.09, 0.16, 0.09] },
        ]);
        let logs = seatSurfaceParts(scene.THREE, scene.objects, [
          { id: 'muzzle', to: 'skull' },
          { id: 'eye', to: 'muzzle' },
        ]);

        assert.true(
          scene.at('eye')[2] > scene.at('muzzle')[2],
          'the eye ends up in front of the muzzle it sits on',
        );
        assert.true(
          logs.some((line) => line.includes("seated 'eye'")),
          'and the correction is reported',
        );
        assert.deepEqual(
          scene.at('muzzle'),
          [0, 1.54, 0.66],
          'the muzzle itself already straddles the skull and is left alone',
        );
      });

      test('a feature carried by a moved host keeps its offset', function (assert) {
        let scene = stubScene([
          { id: 'skull', at: [0, 0, 0], r: [1, 1, 1] },
          { id: 'eye', at: [0, 0, -0.4], r: [0.2, 0.2, 0.2] },
          { id: 'pupil', at: [0, 0, -0.5], r: [0.08, 0.08, 0.08] },
        ]);
        // there is no grandhost above the skull, so the eye is simply buried
        seatSurfaceParts(scene.THREE, scene.objects, [
          { id: 'eye', to: 'skull' },
          { id: 'pupil', to: 'eye' },
        ]);

        assert.true(
          scene.at('eye')[2] < -1,
          'the buried eye surfaces along its own offset, which points at -z',
        );
        assert.true(
          scene.at('pupil')[2] < scene.at('eye')[2],
          'and the pupil travels with it instead of being left in the skull',
        );
      });

      test('an elongated limb is not seated on its support', function (assert) {
        let scene = stubScene([
          { id: 'torso', at: [0, 1.2, 0], r: [0.31, 0.22, 0.31] },
          { id: 'arm', at: [0.5, 1.05, 0.05], r: [0.07, 0.32, 0.07] },
        ]);
        seatSurfaceParts(scene.THREE, scene.objects, [
          { id: 'arm', to: 'torso' },
        ]);

        assert.deepEqual(
          scene.at('arm'),
          [0.5, 1.05, 0.05],
          'an ellipsoid centred on a limb is nowhere near the shoulder it hangs from, so the seater declines',
        );
      });
    });

    module('revolved silhouette gate', function () {
      let box = (left: number, top: number, width: number, height: number) => ({
        left,
        top,
        width,
        height,
      });

      test('a bottle traces the union of its stacked parts', function (assert) {
        let { bbox, skipped } = revolvedSilhouetteBbox([
          {
            part: 'body',
            approach: 'revolved',
            bbox: box(0.3, 0.35, 0.4, 0.6),
          },
          {
            part: 'neck',
            approach: 'revolved',
            bbox: box(0.42, 0.12, 0.16, 0.25),
          },
          {
            part: 'label',
            approach: 'wrap-decal',
            bbox: box(0.32, 0.5, 0.36, 0.3),
          },
        ]);
        assert.strictEqual(skipped, undefined, 'it traces');
        assert.strictEqual(bbox?.left, 0.3, 'union spans the widest part');
        assert.strictEqual(bbox?.top, 0.12, 'and reaches the neck top');
      });

      test('a machine with round parts at both ends is not one silhouette', function (assert) {
        // the Thompson: drum magazine under the middle, barrel out to the right
        let { bbox, skipped } = revolvedSilhouetteBbox([
          {
            part: 'drum magazine',
            approach: 'revolved',
            bbox: box(0.3, 0.45, 0.14, 0.3),
          },
          {
            part: 'barrel',
            approach: 'revolved',
            bbox: box(0.62, 0.3, 0.34, 0.06),
          },
          { part: 'stock', approach: 'boxy', bbox: box(0.02, 0.4, 0.3, 0.3) },
        ]);
        assert.strictEqual(bbox, undefined, 'nothing is traced');
        assert.strictEqual(skipped, 'revolved parts are not on one axis');
      });

      test('a lone round component does not speak for the whole object', function (assert) {
        // passes the axis test trivially — there is nothing to disagree with
        let { bbox, skipped } = revolvedSilhouetteBbox([
          {
            part: 'drum magazine',
            approach: 'revolved',
            bbox: box(0.3, 0.45, 0.14, 0.3),
          },
          {
            part: 'receiver',
            approach: 'boxy',
            bbox: box(0.25, 0.35, 0.45, 0.2),
          },
          { part: 'stock', approach: 'boxy', bbox: box(0.02, 0.4, 0.3, 0.3) },
        ]);
        assert.strictEqual(bbox, undefined, 'nothing is traced');
        assert.strictEqual(
          skipped,
          'revolved parts are a detail, not the body',
        );
      });

      test('a plan with no revolved parts asks for no trace', function (assert) {
        assert.strictEqual(
          revolvedSilhouetteBbox([
            { part: 'body', approach: 'boxy', bbox: box(0.1, 0.1, 0.8, 0.8) },
          ]).skipped,
          'no revolved parts',
        );
        assert.strictEqual(
          revolvedSilhouetteBbox([]).skipped,
          'no revolved parts',
          'and an empty plan does not throw',
        );
      });
    });

    // Build directives ship per object, so the selector decides what the model
    // is told. Getting it wrong is silent: an over-broad trigger wastes the
    // model's attention, a missed one drops a rule that was there to prevent a
    // known failure.
    module('build directive selection', function () {
      let analysis = (partPlan: any[], extra: any = {}) => ({
        objectType: 'thing',
        objectClass: 'hard-surface',
        partPlan,
        ...extra,
      });

      test('a revolved vessel takes the lathe directives, not a building’s', function (assert) {
        let names = selectRecipeNames(
          analysis(
            [
              { part: 'bottle body', approach: 'revolved' },
              { part: 'front label', approach: 'wrap-decal' },
            ],
            { objectType: 'wine bottle' },
          ),
        );
        assert.true(names.includes('revolved'), 'lathe tracing is sent');
        assert.true(names.includes('wrapDecal'), 'the wrap directive is sent');
        assert.false(
          names.includes('architectural'),
          'a bottle is not told about roof skirts',
        );
        assert.false(names.includes('vehicle'), 'nor about flank panels');
      });

      test('a house takes the architectural directives and not the lathe ones', function (assert) {
        let names = selectRecipeNames(
          analysis(
            [
              { part: 'lower storey', approach: 'boxy' },
              { part: 'upper roof', approach: 'boxy' },
            ],
            { objectType: 'two-storey house' },
          ),
        );
        assert.true(names.includes('architectural'), 'the skirt rule is sent');
        assert.false(
          names.includes('revolved'),
          'a house is not told how to trace a lathe profile',
        );
      });

      test('a plan with a face takes the character directives', function (assert) {
        let names = selectRecipeNames(
          analysis(
            [
              { part: 'head', approach: 'rounded-shell' },
              { part: 'muzzle', approach: 'rounded-shell' },
              { part: 'eyes', approach: 'rounded-shell' },
              { part: 'nose', approach: 'rounded-shell' },
            ],
            { objectType: 'cartoon mascot', objectClass: 'organic' },
          ),
        );
        assert.true(
          names.includes('character'),
          'the face-layout rules are sent',
        );
      });

      test('a head-shaped word alone is not a face', function (assert) {
        let names = selectRecipeNames(
          analysis(
            [
              { part: 'cylinder head', approach: 'boxy' },
              { part: 'torso panel', approach: 'boxy' },
            ],
            { objectType: 'engine block' },
          ),
        );
        assert.false(
          names.includes('character'),
          'an engine head earns no eye-placement rules',
        );
      });

      test('a knife handle takes the contoured-grip directive', function (assert) {
        let names = selectRecipeNames(
          analysis(
            [
              { part: 'blade', approach: 'boxy' },
              { part: 'handle scale', approach: 'boxy' },
            ],
            { objectType: 'folding knife' },
          ),
        );
        assert.true(
          names.includes('grip'),
          'the extrudedSpline handle rule is sent',
        );
      });

      test('an object with no handle-family part gets no grip directive', function (assert) {
        let names = selectRecipeNames(
          analysis(
            [{ part: 'body', approach: 'boxy' }],
            { objectType: 'toaster' },
          ),
        );
        assert.false(
          names.includes('grip'),
          'a toaster is not told how to shape a handle',
        );
      });

      test('artwork is keyed on the bbox the plan actually measured', function (assert) {
        let withArt = selectRecipeNames(
          analysis([
            { part: 'placard', approach: 'boxy', artwork: { left: 0.1 } },
          ]),
        );
        let without = selectRecipeNames(
          analysis([{ part: 'placard', approach: 'boxy' }]),
        );
        assert.true(withArt.includes('artwork'), 'a measured crop asks for it');
        assert.false(
          without.includes('artwork'),
          'a plain painted surface does not',
        );
      });

      test('a vehicle earns the flank and repeat directives', function (assert) {
        let names = selectRecipeNames(
          analysis(
            [
              { part: 'hull', approach: 'boxy' },
              { part: 'wheels', approach: 'boxy', details: 'six in two rows' },
              {
                part: 'side armour',
                approach: 'boxy',
                surface: 'matte, worn paint',
              },
            ],
            { objectType: 'armoured truck' },
          ),
        );
        assert.true(names.includes('vehicle'), 'flank panels');
        assert.true(names.includes('machineDetail'), 'wheel repeats');
        assert.true(names.includes('finishes'), 'worn is a real finish here');
      });

      test('an object matching no keyword still receives its approach directives', function (assert) {
        // the "novel object" case — nothing in the name matches any category,
        // but approach is a required enum, so guidance never drops to nothing
        let names = selectRecipeNames(
          analysis(
            [
              { part: 'resonator gourd', approach: 'rounded-shell' },
              { part: 'neck', approach: 'curved-chain' },
            ],
            { objectType: 'sitar', objectClass: 'hybrid' },
          ),
        );
        assert.true(names.length > 0, 'the set is never empty');
        assert.true(names.includes('roundedShell'), 'shells');
        assert.true(names.includes('organic'), 'hybrid takes the chain rules');
      });

      test('stage 1 can nominate a directive no keyword would have matched', function (assert) {
        // the object is a lantern; nothing in the part names says "wall" or
        // "roof", but the analysis has seen the photo and knows its glass
        // panes are mounted flat on faces
        let names = selectRecipeNames(
          analysis(
            [
              { part: 'body cage', approach: 'boxy' },
              { part: 'glass pane', approach: 'boxy' },
            ],
            { objectType: 'storm lantern', directives: ['architectural'] },
          ),
        );
        assert.true(
          names.includes('architectural'),
          'the nomination is honoured',
        );
        assert.true(names.includes('boxy'), 'and the structural picks stand');
      });

      test('a nominated name that does not exist is dropped, not sent empty', function (assert) {
        let names = selectRecipeNames(
          analysis([{ part: 'body', approach: 'boxy' }], {
            directives: ['architectural', 'sculpture', ''],
          }),
        );
        assert.deepEqual(
          names.filter((n) => !['architectural', 'boxy'].includes(n)),
          [],
          'only real block names survive',
        );
        assert.false(
          selectRecipes(
            analysis([{ part: 'body', approach: 'boxy' }], {
              directives: ['nonsense'],
            }),
          ).includes('undefined'),
          'no undefined text reaches the prompt',
        );
      });

      test('the contract block is byte-identical whatever the object', function (assert) {
        let bottle = buildSpecSystemPrompt(
          analysis([{ part: 'body', approach: 'revolved' }]),
        );
        let house = buildSpecSystemPrompt(
          analysis([{ part: 'roof', approach: 'boxy' }]),
        );
        assert.strictEqual(
          bottle[0],
          house[0],
          'block 0 never varies, so the prompt cache still hits',
        );
        assert.notStrictEqual(
          bottle[1],
          house[1],
          'block 1 carries what differs',
        );
      });

      test('no analysis degrades to the contract alone', function (assert) {
        assert.strictEqual(
          buildSpecSystemPrompt(undefined).length,
          1,
          'the contract is self-contained',
        );
        assert.strictEqual(
          selectRecipes(undefined),
          '',
          'and selects nothing rather than throwing',
        );
      });
    });

    module('pipeline integrity', function () {
      // guards interpreter/codegen drift: every SOLID primitive must have a
      // codegen geometry case, or the saved .js renders it differently from the
      // live preview. The five listed here carry their geometry outside the
      // GEOMETRY_CASES switch (group has none; decals/glow/meshAsset emit their
      // own way), so they are the only allowed absences.
      test('every solid primitive has a codegen geometry case', function (assert) {
        let special = new Set([
          'group',
          'meshAsset',
          'glow',
          'textDecal',
          'curvedDecal',
        ]);
        let missing = PRIMITIVES.filter(
          (p) => !special.has(p) && !GEOMETRY_CASES[p],
        );
        assert.deepEqual(
          missing,
          [],
          `these primitives have no codegen case: ${missing.join(', ')}`,
        );
      });

      // the whole ordered pass chain over one composite spec — the interactions
      // that unit-testing each pass in isolation cannot catch (a burial push
      // undoing a face seat, etc.). A character with NO eyes and a mouth buried
      // in the muzzle: after the chain, eyes exist and the mouth sits proud.
      test('runStructurePasses composes without a part fighting another', function (assert) {
        let mat = (id: string, c: string) => ({
          materialId: id,
          baseColor: c,
          roughness: 0.4,
          metalness: 0,
        });
        let spec = {
          objectName: 'mascot',
          inputKind: 'object',
          objectClass: 'organic',
          complexity: 'moderate',
          identityFeatures: ['round head'],
          materials: [mat('m-black', '#111111'), mat('m-skin', '#f0c9a6')],
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'head',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.4],
              position: [0, 2, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm-black',
              partRef: 'head',
              note: 'head',
            },
            {
              nodeId: 'ear-left',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.2],
              position: [-0.3, 2.4, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm-black',
              partRef: 'left ear',
              note: 'ear',
            },
            {
              nodeId: 'muzzle',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.25],
              position: [0, 1.9, -0.2],
              rotation: [0, 0, 0],
              scale: [1.2, 1, 1.1],
              materialId: 'm-skin',
              partRef: 'muzzle',
              note: 'muzzle',
            },
            {
              nodeId: 'mouth',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.05],
              position: [0, 1.85, -0.18],
              rotation: [0, 0, 0],
              scale: [2, 0.55, 0.7],
              materialId: 'm-black',
              partRef: 'mouth',
              note: 'mouth',
            },
          ],
        };
        // no partPlan → dropUnplannedParts is a no-op; character directive lets
        // ensureFaceParts fire
        let logs = runStructurePasses(spec, { directives: ['character'] });
        let ids = spec.components.map((c: any) => c.nodeId);
        assert.ok(
          ids.includes('left-eye') && ids.includes('right-eye'),
          'the missing eyes were synthesized by the chain',
        );
        let mouth = spec.components.find((c: any) => c.nodeId === 'mouth')!;
        assert.ok(
          mouth.position[2] < -0.475,
          `the buried mouth was seated proud of the muzzle front, not pushed down (z=${mouth.position[2]})`,
        );
        assert.ok(Array.isArray(logs), 'the chain returns its log lines');
      });

      test('codegen forces a dark, low-transmission glass to real see-through glass', function (assert) {
        let spec = {
          objectName: 'window test',
          inputKind: 'object',
          objectClass: 'hard-surface',
          complexity: 'simple',
          identityFeatures: [],
          materials: [
            {
              materialId: 'm-glass',
              baseColor: '#2a2a2a',
              roughness: 0.15,
              metalness: 0,
              transmission: 0.25,
            },
          ],
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'pane',
              parentId: 'root',
              primitive: 'roundedBox',
              dimensions: [0.5, 0.4, 0.05],
              position: [0, 1, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm-glass',
              partRef: 'window',
              note: 'window',
            },
          ],
        };
        let js = generateModelJs(spec, {});
        assert.ok(
          /transmission:\s*0\.9/.test(js),
          'transmission raised toward see-through',
        );
        assert.notOk(
          js.includes("'#2a2a2a'"),
          'the dark glass tint was neutralised (no opaque black pane)',
        );
      });

      test('clampInteriorCavities fits an oversized interior inside its shell', function (assert) {
        let spec = {
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'cab-body',
              parentId: 'root',
              primitive: 'roundedBox',
              dimensions: [1, 1, 1, 0.05, 0.02],
              position: [0, 1, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              partRef: 'cab',
              note: 'hollow cab body',
            },
            {
              nodeId: 'cab-interior',
              parentId: 'root',
              primitive: 'box',
              // bigger than the shell AND off-centre — pokes through the walls
              dimensions: [1.2, 1.2, 1.2],
              position: [0.3, 1, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              attachTo: 'cab-body',
              partRef: 'interior',
              note: 'dark interior seen through windows',
            },
          ],
        };
        let logs = clampInteriorCavities(spec);
        let interior = spec.components.find(
          (c: any) => c.nodeId === 'cab-interior',
        )!;
        assert.ok(
          interior.scale[0] < 1 &&
            interior.scale[1] < 1 &&
            interior.scale[2] < 1,
          'the interior was shrunk below the shell on every axis',
        );
        assert.ok(
          Math.abs(interior.position[0]) < 0.001 &&
            Math.abs(interior.position[1] - 1) < 0.001,
          'and recentred on the shell',
        );
        assert.ok(logs.length >= 1, 'it reported the fit');
      });

      test('seatRecesses sinks an inset feature below the host surface', function (assert) {
        let spec = {
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'body',
              parentId: 'root',
              primitive: 'box',
              dimensions: [1, 1, 1],
              position: [0, 1, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              partRef: 'body',
              note: 'body',
            },
            {
              nodeId: 'grille-recess',
              parentId: 'root',
              primitive: 'box',
              dimensions: [0.3, 0.3, 0.2],
              // protruding past the body's +Z face (0.5) — should be sunk in
              position: [0, 1, 0.6],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              inset: true,
              attachTo: 'body',
              partRef: 'grille',
              note: 'recessed grille',
            },
          ],
        };
        let logs = seatRecesses(spec);
        let recess = spec.components.find(
          (c: any) => c.nodeId === 'grille-recess',
        )!;
        // outer face = centre z + half-depth (0.1); must sit below the body
        // surface (z = 0.5)
        assert.ok(
          recess.position[2] + 0.1 < 0.5,
          `the recess outer face was sunk below the surface (z=${recess.position[2]})`,
        );
        assert.ok(logs.length >= 1, 'and it reported the recess');
      });

      test('flagInstanceCollisions widens a fused linear wheel repeat', function (assert) {
        let spec = {
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'wheel',
              parentId: 'root',
              primitive: 'cylinder',
              dimensions: [0.38, 0.38, 0.28, 24],
              position: [0, 0.38, 0],
              rotation: [0, 0, 1.5708],
              scale: [1, 1, 1],
              // step 0.5 < tire diameter 0.76 → tires fuse into a track
              repeat: { count: 4, mode: 'linear', offset: [0, 0, 0.5] },
            },
          ],
        };
        let logs = flagInstanceCollisions(spec);
        let rep = spec.components.find((c: any) => c.nodeId === 'wheel')!
          .repeat as any;
        assert.ok(
          Math.abs(rep.offset[2]) >= 0.75,
          `repeat step widened to >= the tire diameter, got ${rep.offset[2]}`,
        );
        assert.ok(
          logs.some((l) => l.includes('stop fusing')),
          'and it reported the repair',
        );
      });
    });

    module('face alignment', function () {
      // a head with its whole face cluster authored on the +X SIDE of the
      // skull — the Mickey failure: recognizable parts, all in the wrong place
      function sideFacedCharacter() {
        let mat = {
          materialId: 'm',
          baseColor: '#000000',
          roughness: 0.5,
          metalness: 0,
        };
        let feature = (nodeId: string, partRef: string, pos: number[]) => ({
          nodeId,
          parentId: 'root',
          primitive: 'sphere',
          dimensions: [0.12],
          position: pos,
          rotation: [0, 0, 0],
          scale: [1, 1, 1],
          materialId: 'm',
          attachTo: 'head',
          partRef,
          note: partRef,
        });
        return {
          objectName: 'mascot',
          inputKind: 'object',
          objectClass: 'organic',
          complexity: 'moderate',
          identityFeatures: ['round black head'],
          materials: [mat],
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'head',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [1],
              position: [0, 2, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm',
              partRef: 'head',
              note: 'head',
            },
            // the whole cluster lives at +X (side of the head), not -Z (front)
            feature('eye-l', 'left eye', [0.7, 2.2, 0.2]),
            feature('eye-r', 'right eye', [0.7, 2.2, -0.2]),
            feature('nose', 'nose', [0.95, 2.0, 0]),
            feature('mouth', 'mouth', [0.9, 1.75, 0]),
          ],
        };
      }

      test('a face authored on the side of the skull is rotated to the front (-Z)', function (assert) {
        let spec = sideFacedCharacter();
        let logs = alignFaceFeatures(spec, undefined);
        let byId = (id: string) =>
          spec.components.find((c: any) => c.nodeId === id)!;
        // every feature's centre now sits in front of the head centre (-Z),
        // not out to its side (+X)
        for (let id of ['eye-l', 'eye-r', 'nose', 'mouth']) {
          let c: any = byId(id);
          assert.ok(
            c.position[2] < -0.2,
            `${id} moved to the front (-Z), got z=${c.position[2]}`,
          );
          assert.ok(
            Math.abs(c.position[0]) < 0.3,
            `${id} no longer juts out the side (+X), got x=${c.position[0]}`,
          );
        }
        assert.ok(
          logs.some((l) => l.includes('rotated the face cluster')),
          'and it reported the rotation',
        );
      });

      test('measured landmarks snap eyes/nose/mouth to their heights on the front', function (assert) {
        let spec = sideFacedCharacter();
        let analysis = {
          partPlan: [
            {
              part: 'head',
              face: {
                landmarks: {
                  leftEye: [0.35, 0.35],
                  rightEye: [0.65, 0.35],
                  nose: [0.5, 0.55],
                  mouth: [0.5, 0.72],
                },
              },
            },
          ],
        };
        alignFaceFeatures(spec, analysis);
        let y = (id: string) =>
          spec.components.find((c: any) => c.nodeId === id)!.position[1];
        // the head spans y in [1,3] (radius 1 at y=2), so the landmark heights
        // map top→bottom: eyes above nose above mouth, and strictly ordered
        assert.ok(y('eye-l') > y('nose'), 'eyes land above the nose');
        assert.ok(y('nose') > y('mouth'), 'nose lands above the mouth');
      });

      test('a nose above the eyes is reported, not silently kept', function (assert) {
        let spec = sideFacedCharacter();
        // author the nose ABOVE the eye line
        spec.components.find((c: any) => c.nodeId === 'nose')!.position = [
          0.95, 2.6, 0,
        ];
        let logs = alignFaceFeatures(spec, undefined);
        assert.ok(
          logs.some((l) => l.includes('nose sits ABOVE the eyes')),
          'the stack-order violation is surfaced',
        );
      });

      test('a plain object with no face parts is left untouched', function (assert) {
        let spec = testSpec();
        let before = JSON.stringify(spec);
        let logs = alignFaceFeatures(spec, undefined);
        assert.strictEqual(logs.length, 0, 'nothing to report');
        assert.strictEqual(
          JSON.stringify(spec),
          before,
          'and the spec is unchanged',
        );
      });
    });

    module('facial feature seating', function () {
      // a mouth authored deep inside the muzzle — the "dropped to the chin" bug
      function muzzleWithBuriedMouth() {
        let mat = (id: string, c: string) => ({
          materialId: id,
          baseColor: c,
          roughness: 0.4,
          metalness: 0,
        });
        return {
          objectName: 'mascot',
          inputKind: 'object',
          objectClass: 'organic',
          complexity: 'moderate',
          identityFeatures: ['round head'],
          materials: [mat('m-black', '#111111'), mat('m-skin', '#f0c9a6'), mat('m-red', '#7a1f1f')],
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'head',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.4],
              position: [0, 2, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm-black',
              partRef: 'head',
              note: 'head',
            },
            {
              nodeId: 'ear-left',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.2],
              position: [-0.3, 2.4, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm-black',
              partRef: 'left ear',
              note: 'ear',
            },
            {
              nodeId: 'muzzle',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.25],
              position: [0, 1.9, -0.2],
              rotation: [0, 0, 0],
              scale: [1.2, 1, 1.1],
              materialId: 'm-skin',
              partRef: 'muzzle',
              note: 'muzzle',
            },
            {
              nodeId: 'mouth',
              parentId: 'root',
              primitive: 'sphere',
              // sits behind the muzzle front (buried), the failure state
              dimensions: [0.05],
              position: [0, 1.85, -0.18],
              rotation: [0, 0, 0],
              scale: [2, 0.5, 0.7],
              materialId: 'm-red',
              partRef: 'mouth',
              note: 'mouth',
            },
          ],
        };
      }

      test('resolveBuriedParts leaves a facial feature alone', function (assert) {
        let spec = muzzleWithBuriedMouth();
        let before = spec.components.find((c: any) => c.nodeId === 'mouth')!
          .position.slice();
        let logs = resolveBuriedParts(spec);
        let after = spec.components.find((c: any) => c.nodeId === 'mouth')!
          .position;
        assert.deepEqual(after, before, 'the mouth was not shoved by the burial pass');
        assert.notOk(
          logs.some((l) => l.includes("'mouth'")),
          'and it is not reported as buried',
        );
      });

      test('alignFaceFeatures seats a buried mouth proud of the muzzle front', function (assert) {
        let spec = muzzleWithBuriedMouth();
        alignFaceFeatures(spec, undefined);
        let mouth = spec.components.find((c: any) => c.nodeId === 'mouth')!;
        // muzzle front is at z = -0.2 - 0.25*1.1 = -0.475; the mouth should now
        // sit in front of that (more negative z)
        assert.ok(
          mouth.position[2] < -0.475,
          `mouth pulled proud of the muzzle front, got z=${mouth.position[2]}`,
        );
      });
    });

    module('face part backstop', function () {
      // a character (head + ear + muzzle) the LLM shipped with NO eyes/mouth
      function facelessCharacter() {
        return {
          objectName: 'mascot',
          inputKind: 'object',
          objectClass: 'organic',
          complexity: 'moderate',
          identityFeatures: ['round head'],
          materials: [
            { materialId: 'm-black', baseColor: '#111111', roughness: 0.4, metalness: 0 },
            { materialId: 'm-skin', baseColor: '#f0c9a6', roughness: 0.5, metalness: 0 },
          ],
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'head',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.4],
              position: [0, 2, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm-black',
              partRef: 'head',
              note: 'head',
            },
            {
              nodeId: 'ear-left',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.2],
              position: [-0.3, 2.4, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm-black',
              partRef: 'left ear',
              note: 'ear',
            },
            {
              nodeId: 'muzzle',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [0.25],
              position: [0, 1.9, -0.2],
              rotation: [0, 0, 0],
              scale: [1.2, 1, 1.1],
              materialId: 'm-skin',
              partRef: 'muzzle',
              note: 'muzzle',
            },
          ],
        };
      }
      let names = (spec: any) => spec.components.map((c: any) => c.nodeId);

      test('a face with no eyes/mouth gets them synthesized', function (assert) {
        let spec = facelessCharacter();
        let logs = ensureFaceParts(spec, undefined);
        let ids = names(spec);
        for (let need of [
          'left-eye',
          'right-eye',
          'left-pupil',
          'right-pupil',
          'nose',
          'mouth',
        ]) {
          assert.ok(ids.includes(need), `synthesized ${need}`);
        }
        assert.ok(logs.length >= 6, 'and it reported each addition');
        // eyes sit on the FRONT (-Z) of the head, not behind it
        let eye = spec.components.find((c: any) => c.nodeId === 'left-eye');
        assert.ok(eye.position[2] < 0, 'the eye is on the front face');
      });

      test('running twice adds nothing the second time (idempotent)', function (assert) {
        let spec = facelessCharacter();
        ensureFaceParts(spec, undefined);
        let count = spec.components.length;
        let logs = ensureFaceParts(spec, undefined);
        assert.strictEqual(logs.length, 0, 'no second-pass additions');
        assert.strictEqual(
          spec.components.length,
          count,
          'the part count is unchanged',
        );
      });

      test('a non-character is left untouched', function (assert) {
        let spec = {
          materials: [],
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'body',
              parentId: 'root',
              primitive: 'sphere',
              dimensions: [1],
              position: [0, 1, 0],
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              partRef: 'body',
              note: 'body',
            },
          ],
        };
        let logs = ensureFaceParts(spec, undefined);
        assert.strictEqual(logs.length, 0, 'nothing added to a plain object');
      });
    });

    module('ring collar seating', function () {
      // a barrel pointing FORWARD (-Z): a cylinder rotated [-90°,0,0] takes its
      // local +Y axis onto -Z. Its muzzle collar should wrap it (hole along Z),
      // but the model authored an upright hoop (rotation [0,0,0] is already the
      // wrap orientation for a Z barrel) offset sideways and forward off-axis.
      function barrelWithStrayCollar() {
        let mat = {
          materialId: 'm',
          baseColor: '#888888',
          roughness: 0.4,
          metalness: 0.9,
        };
        return {
          objectName: 'barrel',
          inputKind: 'object',
          objectClass: 'hard-surface',
          complexity: 'simple',
          identityFeatures: ['barrel'],
          materials: [mat],
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'barrel',
              parentId: 'root',
              primitive: 'cylinder',
              dimensions: [0.1, 0.1, 1.5],
              position: [0, 0, 0],
              rotation: [-1.5708, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm',
              partRef: 'barrel',
              note: 'barrel',
            },
            {
              nodeId: 'collar',
              parentId: 'root',
              primitive: 'torus',
              dimensions: [0.4, 0.05],
              // off the barrel axis (x, y) and standing at the muzzle (z=-0.7)
              position: [0.3, -0.25, -0.7],
              rotation: [1.2, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm',
              attachTo: 'barrel',
              partRef: 'muzzle collar',
              note: 'muzzle collar',
            },
          ],
        };
      }

      test('a stray collar is centred on the barrel axis and oriented to wrap it', function (assert) {
        let spec = barrelWithStrayCollar();
        let logs = seatRingCollars(spec);
        let collar: any = spec.components.find(
          (c: any) => c.nodeId === 'collar',
        );
        // centred: the two off-axis (x,y) match the barrel; z (along the barrel)
        // is kept so the collar stays at the muzzle
        assert.strictEqual(collar.position[0], 0, 'x snapped to the barrel axis');
        assert.strictEqual(collar.position[1], 0, 'y snapped to the barrel axis');
        assert.strictEqual(collar.position[2], -0.7, 'z along the barrel is kept');
        // oriented to wrap a Z-axis barrel: hole along Z ⇒ rotation [0,0,0]
        assert.deepEqual(
          collar.rotation,
          [0, 0, 0],
          'the hole now faces along the barrel',
        );
        // hole hugs the barrel radius: torus radius = hostR(0.1) + tube(0.05) + skin
        assert.ok(
          Math.abs(collar.dimensions[0] - 0.16) < 0.001,
          `radius fitted to the barrel, got ${collar.dimensions[0]}`,
        );
        assert.ok(logs.length >= 1, 'and it reported what it did');
      });

      test('a torus with no cylinder host is left untouched', function (assert) {
        let spec = barrelWithStrayCollar();
        // re-point the collar at nothing barrel-like
        spec.components.find((c: any) => c.nodeId === 'collar')!.attachTo =
          'root';
        let before = JSON.stringify(spec);
        let logs = seatRingCollars(spec);
        assert.strictEqual(logs.length, 0, 'nothing to seat');
        assert.strictEqual(JSON.stringify(spec), before, 'spec unchanged');
      });
    });

    module('lasso removal narrowing', function () {
      // the lasso over a blade sticker reports BOTH the decal and the blade
      // behind it — "remove sticker" must not take the blade
      let bladeAndSticker = [
        { nodeId: 'blade', primitive: 'extrudedSpline', partRef: 'blade' },
        {
          nodeId: 'logo',
          primitive: 'textDecal',
          partRef: 'brand sticker',
          note: 'sticker',
        },
      ];

      test('a named removal drops the lasso spillover', function (assert) {
        let kept = narrowRemovalTargets(
          bladeAndSticker,
          ['logo', 'blade'],
          'remove sticker',
        );
        assert.deepEqual(kept, ['logo'], 'only the sticker is removed');
      });

      test('a sticker/label word narrows to the decal even when its name differs', function (assert) {
        // instruction says "label", the part is named "brand sticker" — the
        // decal-primitive fallback still catches it, and not the solid blade
        let kept = narrowRemovalTargets(
          bladeAndSticker,
          ['logo', 'blade'],
          'delete the label',
        );
        assert.deepEqual(kept, ['logo'], 'the decal is the only match');
      });

      test('a generic removal keeps the whole selection', function (assert) {
        let kept = narrowRemovalTargets(
          bladeAndSticker,
          ['logo', 'blade'],
          'remove this',
        );
        assert.deepEqual(
          kept,
          ['logo', 'blade'],
          'with no noun, the lasso stands',
        );
      });

      test('never widens: an unmatched noun leaves the selection as-is', function (assert) {
        let kept = narrowRemovalTargets(
          bladeAndSticker,
          ['blade'],
          'remove sticker',
        );
        assert.deepEqual(
          kept,
          ['blade'],
          'a single-part lasso is returned unchanged',
        );
      });

      test('isRemovalInstruction recognises the delete verbs', function (assert) {
        assert.true(isRemovalInstruction('remove the pin'));
        assert.true(isRemovalInstruction('Delete sticker'));
        assert.false(isRemovalInstruction('make the label smaller'));
      });
    });

    module('bone primitive', function () {
      function boneSpec(position: number[]) {
        return {
          objectName: 'arm',
          inputKind: 'object',
          objectClass: 'organic',
          complexity: 'simple',
          identityFeatures: ['arm'],
          materials: [
            { materialId: 'm', baseColor: '#222222', roughness: 0.4, metalness: 0 },
          ],
          components: [
            { nodeId: 'root', primitive: 'group', position: [0, 0, 0] },
            {
              nodeId: 'upper-arm',
              parentId: 'root',
              primitive: 'bone',
              // [radius, x0,y0,z0, x1,y1,z1] — endpoints place it
              dimensions: [0.05, -0.3, 1, 0, -0.5, 0.6, 0.1],
              position,
              rotation: [0, 0, 0],
              scale: [1, 1, 1],
              materialId: 'm',
              partRef: 'arm',
              note: 'upper arm',
            },
          ],
        };
      }

      test("a bone's stray position is zeroed — its endpoints place it", function (assert) {
        let spec = boneSpec([0.4, 0.4, 0.4]);
        let logs = repairPrimitiveConventions(spec);
        let bone: any = spec.components.find((c: any) => c.nodeId === 'upper-arm');
        assert.deepEqual(bone.position, [0, 0, 0], 'position reset to origin');
        assert.ok(
          logs.some((l) => l.includes("bone's points already place it")),
          'and it reported the fix',
        );
      });

      test('a bone already at the origin is left untouched', function (assert) {
        let spec = boneSpec([0, 0, 0]);
        let logs = repairPrimitiveConventions(spec);
        assert.strictEqual(logs.length, 0, 'nothing to fix');
      });

      test('codegen emits a CapsuleGeometry for a bone', function (assert) {
        let js = generateModelJs(boneSpec([0, 0, 0]), {});
        assert.ok(js.includes("case 'bone'"), 'the bone case is emitted');
        assert.ok(
          js.includes('CapsuleGeometry') && js.includes('setFromUnitVectors'),
          'and it builds an auto-oriented capsule',
        );
      });
    });
  });
}
