import { module, test } from 'qunit';

import {
  applySpecDiff,
  dropHairlineParts,
  groundSupports,
  resolveBuriedParts,
  flagInstanceCollisions,
  repairPrimitiveConventions,
  dropUnplannedParts,
  flagOverbuiltParts,
  reconcileProportions,
  seedFromStrings,
  serializeSpecForPrompt,
} from './generation';
import { generateModelJs, specFromModelJs } from './code-export';

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
  });
}
