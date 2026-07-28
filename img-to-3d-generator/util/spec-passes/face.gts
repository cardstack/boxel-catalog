// Making the face sit where a face sits.
//
// A character is judged almost entirely on its face, and the face is the one
// assembly the other passes cannot help with: every feature can be planned,
// attached, unburied and inside the silhouette while the whole cluster sits on
// the side of the head. The canonical world frame fixes the front at -Z, so
// where the face belongs is not a judgement call — it is a direction the code
// can enforce.

import { hasNeutralAncestry, halfExtents, specBox } from '../spec-geometry';

// the features that make up a face, minus ears — ears belong on the sides
export const FACE_FEATURE =
  /\b(eye|eyes|eyeball|pupil|iris|brow|eyebrow|nose|nostril|mouth|lip|lips|tongue|tooth|teeth)\b/i;
// masses that hug the skull rather than sit proud of it: a muzzle, a snout, a
// bird's bill/beak, a colour patch. These are DESIGNED to have their centre
// near the head and sit on the facial midline.
export const FACE_MASS =
  /\b(muzzle|snout|bill|beak|jaw|maw|face|mask|cheek|patch)\b/i;
// a beak/bill/snout/jaw IS an animal's nose AND mouth — so a face that has one
// already has both, and the backstop must not add a redundant nose or mouth.
const BEAK = /\b(bill|beak|snout|jaw|maw)\b/i;
const HEAD = /\b(head|skull)\b/i;
const EAR = /\bears?\b/i;

function nameOf(c: any): string {
  return `${c?.nodeId ?? ''} ${c?.partRef ?? ''} ${c?.note ?? ''}`;
}

function centreOf(box: { min: number[]; max: number[] }): number[] {
  return [0, 1, 2].map((a) => (box.min[a] + box.max[a]) / 2);
}

// Aligns a character's facial features with the head, in three steps:
//
// 1. SIDE — the feature cluster's mean offset from the head centre says which
//    way the authored face points. The canonical frame says it points -Z, so
//    a cluster pointing anywhere else is rotated about the head's vertical
//    axis until it does. The whole cluster turns together, so eyes, nose and
//    mouth keep their arrangement — only the side of the head changes.
// 2. LANDMARKS — when the analysis measured face landmarks off the reference
//    (normalized [x,y] inside the head part's bbox), each feature's height
//    comes from its landmark and its depth is snapped onto the head's front
//    surface. Heights survive any camera angle, which is why only y and z are
//    snapped — a three-quarter view makes the landmark x unreliable.
// 3. EMBED — a muzzle / face patch bites INTO the skull (centre inside the
//    head volume) or it renders as a separate lump floating in front of the
//    face. Any face mass whose centre is outside is pulled in along its own
//    centre-line.
//
// A vertical-order violation (nose above the eyes) is reported, not repaired:
// which feature is mislabeled is a question about the photograph.
export function alignFaceFeatures(parsed: any, analysis?: any): string[] {
  let logs: string[] = [];
  let all: any[] = parsed?.components ?? [];
  let byId = new Map<string, any>(all.map((c: any) => [c?.nodeId, c]));
  let solid = (c: any) =>
    c?.nodeId &&
    c.primitive !== 'group' &&
    c.primitive !== 'glow' &&
    !c.repeat &&
    hasNeutralAncestry(c, byId);

  // the host: the largest head-named solid that is not itself a feature
  let heads = all.filter(
    (c: any) =>
      solid(c) && HEAD.test(nameOf(c)) && !FACE_FEATURE.test(nameOf(c)),
  );
  let volume = (c: any) => {
    let h = halfExtents(c);
    return h ? h[0] * h[1] * h[2] : 0;
  };
  let head = heads.sort((a: any, b: any) => volume(b) - volume(a))[0];
  if (!head) return logs;
  let headBox = specBox(head);
  let headHalf = halfExtents(head);
  if (!headBox || !headHalf) return logs;
  let headC = centreOf(headBox);

  let features = all.filter(
    (c: any) =>
      solid(c) &&
      c !== head &&
      !EAR.test(nameOf(c)) &&
      (FACE_FEATURE.test(nameOf(c)) || FACE_MASS.test(nameOf(c))),
  );
  if (!features.length) return logs;

  let boxOf = (c: any) => specBox(c);
  let moveTo = (c: any, target: number[], axes: number[]) => {
    let box = boxOf(c);
    if (!box) return;
    let cur = centreOf(box);
    let p = Array.isArray(c.position) ? c.position.map(Number) : [0, 0, 0];
    for (let a of axes) {
      p[a] = Number(((p[a] || 0) + target[a] - cur[a]).toFixed(4));
    }
    c.position = p;
  };

  // ---- 1. side: rotate the cluster onto the front (-Z) -------------------
  let meanX = 0;
  let meanZ = 0;
  let measured = 0;
  for (let c of features) {
    let box = boxOf(c);
    if (!box) continue;
    let ctr = centreOf(box);
    meanX += ctr[0] - headC[0];
    meanZ += ctr[2] - headC[2];
    measured++;
  }
  if (!measured) return logs;
  meanX /= measured;
  meanZ /= measured;
  let mag = Math.hypot(meanX, meanZ);
  // a cluster hugging the head's vertical axis has no direction to read
  if (mag > 0.15 * Math.max(headHalf[0], headHalf[2])) {
    // angle of the cluster off the -Z axis, positive toward +X
    let theta = Math.atan2(meanX, -meanZ);
    if (Math.abs(theta) > (20 * Math.PI) / 180) {
      let cos = Math.cos(theta);
      let sin = Math.sin(theta);
      for (let c of features) {
        let box = boxOf(c);
        if (!box) continue;
        let ctr = centreOf(box);
        let dx = ctr[0] - headC[0];
        let dz = ctr[2] - headC[2];
        moveTo(
          c,
          [headC[0] + dx * cos + dz * sin, 0, headC[2] - dx * sin + dz * cos],
          [0, 2],
        );
        // keep the part facing the way it now points; approximate for parts
        // that already carry pitch/roll, exact for the usual flat rotations
        let r = Array.isArray(c.rotation) ? c.rotation.map(Number) : [0, 0, 0];
        if (r[0] || r[1] || r[2]) {
          r[1] = Number(((r[1] || 0) + theta).toFixed(4));
          c.rotation = r;
        }
      }
      logs.push(
        `rotated the face cluster ${Math.round((theta * 180) / Math.PI)}° onto the front of '${head.nodeId}' — the face belongs at -Z`,
      );
    }
  }

  // ---- 2. landmarks: measured heights + front-surface depth --------------
  let planFace = (analysis?.partPlan ?? []).find(
    (p: any) =>
      p?.face?.landmarks &&
      String(p?.part ?? '')
        .trim()
        .toLowerCase() ===
        String(head.partRef ?? '')
          .trim()
          .toLowerCase(),
  )?.face;
  let landmarks = planFace?.landmarks;
  if (landmarks) {
    let headH = headBox.max[1] - headBox.min[1];
    let frontZ = (x: number, y: number, ownHalfZ: number, bite: number) => {
      let rel =
        ((x - headC[0]) / (headHalf[0] || 1)) ** 2 +
        ((y - headC[1]) / (headHalf[1] || 1)) ** 2;
      let root = Math.sqrt(Math.max(0, 1 - Math.min(rel, 0.96)));
      // centre on the surface (half proud), or bitten in for a face mass
      return headC[2] - headHalf[2] * root + bite * ownHalfZ;
    };
    let snap = (
      pattern: RegExp,
      landmark: number[] | undefined,
      label: string,
    ) => {
      if (!Array.isArray(landmark) || landmark.length < 2) return;
      let group = features
        .filter((c: any) => pattern.test(nameOf(c)))
        .sort((a: any, b: any) => volume(b) - volume(a));
      let primary = group[0];
      if (!primary) return;
      let box = boxOf(primary);
      let h = halfExtents(primary);
      if (!box || !h) return;
      let ctr = centreOf(box);
      let y = headBox.max[1] - Number(landmark[1]) * headH;
      let target = [ctr[0], y, frontZ(ctr[0], y, h[2], 0)];
      let before = [...ctr];
      moveTo(primary, target, [1, 2]);
      // whatever rides this feature moves with it (a pupil on its eye)
      let delta = [0, y - before[1], target[2] - before[2]];
      for (let c of all) {
        if (c === primary || !solid(c)) continue;
        if (
          String(c.attachTo ?? '') === String(primary.nodeId) ||
          String(c.parentId ?? '') === String(primary.nodeId)
        ) {
          let p = Array.isArray(c.position)
            ? c.position.map(Number)
            : [0, 0, 0];
          c.position = [
            p[0],
            Number((p[1] + delta[1]).toFixed(4)),
            Number((p[2] + delta[2]).toFixed(4)),
          ];
        }
      }
      logs.push(
        `snapped '${primary.nodeId}' to the measured ${label} landmark`,
      );
    };
    // eyes share one measured height; each keeps its own side of the axis
    let eyeMarks = [landmarks.leftEye, landmarks.rightEye].filter(
      (m: any) => Array.isArray(m) && m.length >= 2,
    );
    if (eyeMarks.length) {
      let v =
        eyeMarks.reduce((sum: number, m: number[]) => sum + Number(m[1]), 0) /
        eyeMarks.length;
      let eyes = features.filter((c: any) =>
        /\beyes?\b|\beyeball\b/i.test(nameOf(c)),
      );
      for (let eye of eyes) {
        let box = boxOf(eye);
        let h = halfExtents(eye);
        if (!box || !h) continue;
        let ctr = centreOf(box);
        let y = headBox.max[1] - v * headH;
        moveTo(eye, [ctr[0], y, frontZ(ctr[0], y, h[2], 0)], [1, 2]);
      }
      if (eyes.length) logs.push('snapped the eyes to the measured eye line');
    }
    snap(/\bnose|nostril\b/i, landmarks.nose, 'nose');
    snap(/\bmouth|lips?\b/i, landmarks.mouth, 'mouth');
  } else {
    // No measured landmarks — but a nose/mouth the LLM authored too DEEP still
    // reads as buried (and resolveBuriedParts used to shove it down to the
    // chin). Seat it just proud of the muzzle front at a sane height, and only
    // when it is not already clearly proud, so a good placement is left alone.
    let muzzle = all
      .filter(
        (c: any) =>
          solid(c) && FACE_MASS.test(nameOf(c)) && !FACE_FEATURE.test(nameOf(c)),
      )
      .sort((a: any, b: any) => volume(b) - volume(a))[0];
    let anchorBox = (muzzle ? boxOf(muzzle) : headBox) ?? headBox;
    let ac = centreOf(anchorBox);
    let frontZ = anchorBox.min[2];
    let anchorH = anchorBox.max[1] - anchorBox.min[1] || 1;
    let seatFront = (pattern: RegExp, yFrac: number, label: string) => {
      let primary = features
        .filter((c: any) => pattern.test(nameOf(c)))
        .sort((a: any, b: any) => volume(b) - volume(a))[0];
      if (!primary) return;
      let box = boxOf(primary);
      let h = halfExtents(primary);
      if (!box || !h) return;
      let ctr = centreOf(box);
      // front is -Z: a proud feature already sits in front of the muzzle face
      if (ctr[2] <= frontZ - 0.4 * h[2]) return;
      let y = anchorBox.max[1] - yFrac * anchorH;
      moveTo(primary, [ac[0], y, frontZ - 0.6 * h[2]], [1, 2]);
      logs.push(`seated '${primary.nodeId}' on the muzzle front (no ${label} landmark)`);
    };
    seatFront(/\bnose|nostril\b/i, 0.45, 'nose');
    seatFront(/\bmouth|lips?\b/i, 0.72, 'mouth');
  }

  // ---- 3. embed: a face mass bites into the skull -------------------------
  for (let c of features) {
    if (!FACE_MASS.test(nameOf(c)) || FACE_FEATURE.test(nameOf(c))) continue;
    let box = boxOf(c);
    let h = halfExtents(c);
    if (!box || !h) continue;
    let ctr = centreOf(box);
    let off = [0, 1, 2].map((a) => ctr[a] - headC[a]);
    let norm = Math.sqrt(
      [0, 1, 2].reduce((sum, a) => sum + (off[a] / (headHalf[a] || 1)) ** 2, 0),
    );
    let dist = Math.hypot(...off);
    if (norm <= 1 || !(dist > 0)) continue; // already biting in
    // put the centre on the head surface, then pull it in by 40% of the
    // mass's own smallest half-extent so the two volumes read as one head
    let bite = 0.4 * Math.min(...h);
    let surface = off.map((o, a) => headC[a] + o / norm);
    let unit = off.map((o) => o / dist);
    let target = [0, 1, 2].map((a) => surface[a] - unit[a] * bite);
    // a muzzle / bill / snout sits on the facial MIDLINE — snap its x to the
    // head-centre x so a bill the model authored off to one side is pulled onto
    // the face axis instead of floating beside the head
    target[0] = headC[0];
    moveTo(c, target, [0, 1, 2]);
    logs.push(
      `embedded '${c.nodeId}' into '${head.nodeId}' on the facial midline`,
    );
  }

  // ---- 4. vertical order: report only -------------------------------------
  let meanY = (pattern: RegExp) => {
    let ys = features
      .filter((c: any) => pattern.test(nameOf(c)))
      .map((c: any) => boxOf(c))
      .filter(Boolean)
      .map((b: any) => centreOf(b)[1]);
    return ys.length
      ? ys.reduce((s: number, y: number) => s + y, 0) / ys.length
      : undefined;
  };
  let eyeY = meanY(/\beyes?\b|\beyeball\b/i);
  let noseY = meanY(/\bnose|nostril\b/i);
  let mouthY = meanY(/\bmouth|lips?\b/i);
  if (eyeY !== undefined && noseY !== undefined && noseY > eyeY) {
    logs.push(
      `the nose sits ABOVE the eyes (${noseY.toFixed(2)} > ${eyeY.toFixed(2)}) — a face is a stack: eyes, then nose, then mouth`,
    );
  }
  if (noseY !== undefined && mouthY !== undefined && mouthY > noseY) {
    logs.push(
      `the mouth sits ABOVE the nose (${mouthY.toFixed(2)} > ${noseY.toFixed(2)}) — a face is a stack: eyes, then nose, then mouth`,
    );
  }
  return logs;
}

// Guaranteeing a face HAS a face.
//
// alignFaceFeatures can only move parts that exist; it cannot conjure an eye
// the plan never listed. But the LLM routinely ships a character with no eyes,
// no mouth, or a muzzle collapsed to one flat disc — and dropUnplannedParts
// then guarantees nothing downstream can add them back. So for anything that
// reads as a face, this synthesises the missing core features (two eyes, two
// pupils, a nose, a mouth) directly from the head/muzzle geometry, the same way
// the hand-authored reference model hard-codes them. Additive and idempotent:
// a feature that already exists (under any of its names) is left alone, so a
// re-run or a well-built face is untouched. Placed at the front (-Z) with no
// attachTo, so alignFaceFeatures/landmarks can still refine them afterwards.
function luminance(hex: string): number {
  let m = /^#?([0-9a-f]{6})$/i.exec(String(hex ?? '').trim());
  if (!m) return 0.5;
  let n = parseInt(m[1], 16);
  return (
    (0.2126 * ((n >> 16) & 255) +
      0.7152 * ((n >> 8) & 255) +
      0.0722 * (n & 255)) /
    255
  );
}

export function ensureFaceParts(parsed: any, analysis?: any): string[] {
  let logs: string[] = [];
  let all: any[] = parsed?.components ?? [];
  if (!all.length) return logs;
  let byId = new Map<string, any>(all.map((c: any) => [c?.nodeId, c]));
  let solid = (c: any) =>
    c?.nodeId &&
    c.primitive !== 'group' &&
    c.primitive !== 'glow' &&
    hasNeutralAncestry(c, byId);

  // only run on something that reads as a face: a head plus either ears, a
  // muzzle/face mass, or a character directive from stage 1
  let heads = all.filter(
    (c: any) =>
      solid(c) && HEAD.test(nameOf(c)) && !FACE_FEATURE.test(nameOf(c)),
  );
  let volume = (c: any) => {
    let h = halfExtents(c);
    return h ? h[0] * h[1] * h[2] : 0;
  };
  let head = heads.sort((a: any, b: any) => volume(b) - volume(a))[0];
  if (!head) return logs;
  let hasEar = all.some((c: any) => solid(c) && EAR.test(nameOf(c)));
  let hasMass = all.some(
    (c: any) =>
      solid(c) && FACE_MASS.test(nameOf(c)) && !FACE_FEATURE.test(nameOf(c)),
  );
  let isCharacter =
    Array.isArray(analysis?.directives) &&
    analysis.directives.map(String).includes('character');
  if (!hasEar && !hasMass && !isCharacter) return logs;

  let headBox = specBox(head);
  let headHalf = halfExtents(head);
  if (!headBox || !headHalf) return logs;
  let hc = centreOf(headBox);
  let u = Math.max(headHalf[0], headHalf[1], headHalf[2]) || 0.3;

  // anchor nose/mouth to the muzzle front when there is one, else the head
  let mass = all
    .filter(
      (c: any) =>
        solid(c) && FACE_MASS.test(nameOf(c)) && !FACE_FEATURE.test(nameOf(c)),
    )
    .sort((a: any, b: any) => volume(b) - volume(a))[0];
  let massBox = mass ? specBox(mass) : undefined;
  let anchor = massBox ?? headBox;
  let ac = centreOf(anchor);
  let frontZ = anchor.min[2]; // most-forward (-Z) face of the anchor

  let has = (re: RegExp) =>
    all.some((c: any) => solid(c) && re.test(nameOf(c)));

  // resolve (or create) a material near a target colour
  let materials: any[] = (parsed.materials = parsed.materials ?? []);
  let materialFor = (want: 'white' | 'black' | 'red', id: string) => {
    let hit = materials.find((m: any) => {
      let l = luminance(m?.baseColor);
      if (want === 'white') return l > 0.75;
      if (want === 'black') return l < 0.14;
      let hex = String(m?.baseColor ?? '');
      return /^#?[cdef][0-9a-f]/i.test(hex.replace('#', '')) && l < 0.5; // reddish
    });
    if (hit) return hit.materialId;
    let color =
      want === 'white' ? '#ffffff' : want === 'black' ? '#0a0a0a' : '#7a1f1f';
    materials.push({
      materialId: id,
      baseColor: color,
      roughness: want === 'black' ? 0.2 : 0.35,
      metalness: 0,
    });
    return id;
  };

  let add = (
    nodeId: string,
    dims: number[],
    pos: number[],
    scale: number[],
    mat: string,
    partRef: string,
  ) => {
    all.push({
      nodeId,
      parentId: 'root',
      primitive: 'sphere',
      dimensions: dims,
      position: pos.map((n) => Number(n.toFixed(4))),
      rotation: [0, 0, 0],
      scale,
      materialId: mat,
      partRef,
      note: partRef,
    });
    logs.push(`added a missing '${partRef}' — a face must have one`);
  };

  // eyes: tall white ellipsoids on the upper front, close to the axis
  if (!has(/\beyes?\b|\beyeball\b/i)) {
    let white = materialFor('white', 'm-eyewhite');
    let black = materialFor('black', 'm-pupil');
    let eyeY = hc[1] + 0.32 * headHalf[1];
    let eyeZ = hc[2] - 0.82 * headHalf[2];
    let eyeX = 0.34 * headHalf[0];
    let r = 0.34 * u;
    for (let s of [-1, 1]) {
      add(
        s < 0 ? 'left-eye' : 'right-eye',
        [r],
        [hc[0] + s * eyeX, eyeY, eyeZ],
        [0.62, 1.2, 0.5],
        white,
        s < 0 ? 'left eye' : 'right eye',
      );
    }
    // pupils ride the eyes, a hair further out and up
    if (!has(/\bpupils?\b|\biris\b/i)) {
      let pr = 0.15 * u;
      for (let s of [-1, 1]) {
        add(
          s < 0 ? 'left-pupil' : 'right-pupil',
          [pr],
          [hc[0] + s * eyeX * 0.9, eyeY + 0.02 * u, eyeZ - 0.06 * u],
          [0.7, 1.35, 0.7],
          black,
          s < 0 ? 'left pupil' : 'right pupil',
        );
      }
    }
  }

  // nose: black button at the muzzle front — but a beak/bill/snout already IS
  // the nose, so skip when the face has one (a duck must not grow a second nose)
  if (!has(/\bnose|nostril\b/i) && !has(BEAK)) {
    let black = materialFor('black', 'm-nose');
    add(
      'nose',
      [0.22 * u],
      [ac[0], ac[1] + 0.05 * u, frontZ - 0.12 * u],
      [1.3, 1.0, 1.2],
      black,
      'nose',
    );
  }

  // mouth: a wide dark smile below the nose — again, a beak IS the mouth, so
  // skip it when a beak/bill/snout is present
  if (!has(/\bmouth|lips?\b/i) && !has(BEAK)) {
    let red = materialFor('red', 'm-mouth');
    add(
      'mouth',
      [0.16 * u],
      [
        ac[0],
        ac[1] - 0.45 * (massBox ? halfExtents(mass)![1] : headHalf[1]),
        frontZ - 0.02 * u,
      ],
      [2.0, 0.55, 0.7],
      red,
      'mouth',
    );
  }

  return logs;
}
