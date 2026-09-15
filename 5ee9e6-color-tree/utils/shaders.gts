// =============================================================================
// GLSL for the color tree's four render passes:
//   VOXEL — the instanced cubes; every voxel knows three addresses (the
//           measured tree, Itten's idealized sphere, and the flattened
//           atlas page) and morphs between them in the vertex shader
//   HALO  — one soft additive point of light behind each voxel (3D only)
//   GRID  — the LINEAR SCALE page's complete conventional grid, synthetic
//           swatches at every saturation × lightness step
//   RING  — markers showing where the measured chips actually sit inside
//           that ideal field
// =============================================================================

/* ═══════════════════════════════════════════════════════════════════════════
   SHADERS — morph, slice, light
   ═══════════════════════════════════════════════════════════════════════════ */
export const VOXEL_VSH = `
attribute vec3 aTree;
attribute vec3 aSphere;
attribute vec3 aColor;
attribute float aCFrac;
attribute float aAngle;
attribute float aSeed;
attribute float aValue;
attribute float aChroma;
attribute float aEdge;
uniform float uTime, uMorph, uChart, uChroma, uContrast, uAxis, uGlow, uMini;
uniform float uSliceMode, uSlicePos, uSliceHalf, uHueCount, uCellHue, uCellVal;
uniform vec3 uCamR, uCamU, uCamF, uAnchor;
varying vec3 vColor;
varying vec3 vNormal;
varying float vPage;

float sliceGate(float angle, float value, float cfrac){
  float s = 1.0;
  if (uSliceMode > 0.5 && uSliceMode < 1.5){
    float phi = uSlicePos * 3.14159265;
    float dA = angle - phi;
    dA = abs(atan(sin(dA), cos(dA)));
    dA = min(dA, 3.14159265 - dA);      /* the leaf holds a hue and its complement */
    s = 1.0 - smoothstep(uSliceHalf * 0.55, uSliceHalf * 0.95, dA);
    s = max(s, step(cfrac, 0.001));     /* the trunk belongs to every leaf */
  } else if (uSliceMode > 1.5){
    float dv = abs(value - uSlicePos * 10.0);
    s = (1.0 - smoothstep(0.4, 0.75, dv)) * step(0.001, cfrac);
  }
  return s;
}

void main(){
  float gate = sliceGate(aAngle, aValue, aCFrac);
  /* chroma reveal: outer chips fade first as the dial closes */
  float vis = 1.0 - smoothstep(uChroma + 0.02, uChroma + 0.14, aCFrac);
  vis = max(vis, step(aCFrac, 0.001));
  /* directional pigment light keyed to the tumble axis */
  float d = cos(aAngle - uAxis);
  float lit = mix(1.0, 0.06 + 0.94 * smoothstep(0.15, 0.92, d * 0.5 + 0.5),
                  uContrast * step(0.001, aCFrac));
  /* the quiet shimmer of pigment under lamplight */
  float sh = 0.94 + 0.06 * sin(uTime * 1.4 + aSeed * 43.0);
  vColor = aColor * lit * sh * (0.9 + 0.25 * uGlow);
  vNormal = normalMatrix * normal;

  /* as the page opens, cubes outside the current cut shrink away instead
     of staying full-size in their old 3D spot — otherwise the untouched
     tree would keep floating in front of the flattened page */
  float ch = smoothstep(0.02, 1.0, uChart);
  float open2 = smoothstep(0.0, 0.35, ch);
  /* the scout miniature (uMini) shows the whole solid instead: excluded
     voxels stay at half size and dimmed, the current cut lit bright */
  float keep = mix(mix(1.0, gate, open2), mix(0.5, 1.0, gate), uMini);
  vColor *= mix(max(gate, 1.0 - open2), 1.0, uMini)
          * mix(1.0, mix(0.14, 1.0, gate) * ch, uMini);

  /* address one: the solid, tumbling */
  float edge = aEdge * vis * keep;
  vec3 posT = mix(aTree, aSphere, uMorph);
  vec3 pv = position * edge;
  vec3 cW = (modelMatrix * vec4(posT, 1.0)).xyz;
  vec3 oW = mat3(modelMatrix) * pv;

  /* address two: the printed page, hanging square to the eye. in LINEAR
     SCALE each chip glides to its true position in the linear field (its
     plain saturation) instead of its measured chroma */
  float sLin = min(1.0, aChroma / 13.0 * 1.12);
  float colU = mix(aChroma * 0.5, sLin * 8.0, uMorph);
  vec2 g;
  float cell;
  if (uSliceMode > 1.5){
    cell = uCellVal;
    float hIdx = aAngle / 6.2831853 * uHueCount;
    g = vec2((hIdx - uHueCount * 0.5 + 0.5) * cell, (colU - 4.5) * cell);
  } else {
    cell = uCellHue;
    float phi = uSlicePos * 3.14159265;
    float dA = atan(sin(aAngle - phi), cos(aAngle - phi));
    float side = step(abs(dA), 1.5707963) * 2.0 - 1.0;
    g = vec2(side * colU * cell, (aValue - 5.0) * cell);
  }
  vec3 chartC = uAnchor + uCamR * g.x + uCamU * g.y;
  /* in LINEAR SCALE each chip glides to its true saturation position —
     which sits between grid rows — then yields the square to the GRID
     pass (shrinking to zero as uMorph·ch reaches 1), leaving only its
     dark ring to mark where the measured chip stands in the ideal field */
  vec3 pvC = position * vec3(cell * 0.86, cell * 0.86, cell * 0.12) * vis
           * (1.0 - uMorph * ch);
  vec3 oC = uCamR * pvC.x + uCamU * pvC.y + uCamF * pvC.z;

  float b = ch * gate * (1.0 - uMini);
  vPage = b;
  vec3 P = mix(cW + oW, chartC + oC, b);
  gl_Position = projectionMatrix * viewMatrix * vec4(P, 1.0);
}
`;

export const VOXEL_FSH = `
precision highp float;
varying vec3 vColor;
varying vec3 vNormal;
varying float vPage;
void main(){
  vec3 n = normalize(vNormal);
  float lamb = 0.72 + 0.28 * max(dot(n, normalize(vec3(0.4, 0.8, 0.6))), 0.0);
  /* zero on the open page, so the atlas shows the exact hex */
  float flat_ = mix(lamb, 1.0, vPage);
  gl_FragColor = vec4(vColor * flat_, 1.0);
}
`;

/* the halo: a soft additive breath behind every voxel, driven by the
   glow dial — pigment remembered as light */
export const HALO_VSH = `
attribute vec3 aSphere;
attribute vec3 aColor;
attribute float aCFrac;
attribute float aAngle;
attribute float aValue;
attribute float aChroma;
attribute float aEdge;
uniform float uMorph, uChart, uGlow, uChroma, uMini;
uniform float uSliceMode, uSlicePos, uSliceHalf, uHueCount, uCellHue, uCellVal;
uniform vec3 uCamR, uCamU, uAnchor;
varying vec3 vColor;
varying float vA;

float sliceGate(float angle, float value, float cfrac){
  float s = 1.0;
  if (uSliceMode > 0.5 && uSliceMode < 1.5){
    float phi = uSlicePos * 3.14159265;
    float dA = angle - phi;
    dA = abs(atan(sin(dA), cos(dA)));
    dA = min(dA, 3.14159265 - dA);
    s = 1.0 - smoothstep(uSliceHalf * 0.55, uSliceHalf * 0.95, dA);
    s = max(s, step(cfrac, 0.001));
  } else if (uSliceMode > 1.5){
    float dv = abs(value - uSlicePos * 10.0);
    s = (1.0 - smoothstep(0.4, 0.75, dv)) * step(0.001, cfrac);
  }
  return s;
}

void main(){
  float gate = sliceGate(aAngle, aValue, aCFrac);
  float vis = 1.0 - smoothstep(uChroma + 0.02, uChroma + 0.14, aCFrac);
  vis = max(vis, step(aCFrac, 0.001));
  vColor = aColor;

  /* position is aTree — halo morphs the same tree/sphere/chart addresses
     the voxel mesh does, so it never drifts from the cubes it glows behind */
  vec3 posT = mix(position, aSphere, uMorph);
  vec3 worldT = (modelMatrix * vec4(posT, 1.0)).xyz;

  float sLin = min(1.0, aChroma / 13.0 * 1.12);
  float colU = mix(aChroma * 0.5, sLin * 8.0, uMorph);
  vec2 g;
  float cell;
  if (uSliceMode > 1.5){
    cell = uCellVal;
    float hIdx = aAngle / 6.2831853 * uHueCount;
    g = vec2((hIdx - uHueCount * 0.5 + 0.5) * cell, (colU - 4.5) * cell);
  } else {
    cell = uCellHue;
    float phi = uSlicePos * 3.14159265;
    float dA = atan(sin(aAngle - phi), cos(aAngle - phi));
    float side = step(abs(dA), 1.5707963) * 2.0 - 1.0;
    g = vec2(side * colU * cell, (aValue - 5.0) * cell);
  }
  vec3 chartPos = uAnchor + uCamR * g.x + uCamU * g.y;

  float ch = smoothstep(0.02, 1.0, uChart);
  float b = ch * gate;
  vec3 P = mix(worldT, chartPos, b);

  /* the halo is a 3D-only effect — it fades out completely as the page
     opens (and stays off in the scout miniature), so a flattened chip
     never carries its own glow-dot with it */
  vA = 0.16 * uGlow * gate * vis * (1.0 - ch) * (1.0 - uMini);
  vec4 mv = viewMatrix * vec4(P, 1.0);
  gl_PointSize = aEdge * uGlow * 220.0 / max(1.0, -mv.z);
  gl_Position = projectionMatrix * mv;
}
`;

export const HALO_FSH = `
precision highp float;
varying vec3 vColor;
varying float vA;
void main(){
  vec2 d = gl_PointCoord - 0.5;
  float a = smoothstep(0.5, 0.0, length(d)) * vA;
  gl_FragColor = vec4(vColor, a);
}
`;

/* the linear field, and the marks. In LINEAR SCALE the page becomes a
   complete conventional grid: even saturation steps across, even
   lightness steps down, every cell filled — synthetic swatches, not
   voxels. Rings then mark where the measured chips actually sit inside
   that ideal field: the perceptual palette is a selection, not a grid. */
export const GRID_VSH = `
attribute vec3 aCol;
uniform float uChart, uMorph, uScale, uSliceMode, uCellHue, uCellVal, uMini;
uniform vec3 uCamR, uCamU, uAnchor;
varying vec3 vC;
void main(){
  float cell = uSliceMode > 1.5 ? uCellVal : uCellHue;
  float lin = uMorph * uMorph * (3.0 - 2.0 * uMorph);
  float ch = smoothstep(0.02, 1.0, uChart);
  float vis = ch * lin;
  vC = aCol;
  vec3 P = uAnchor + uCamR * (position.x * cell) + uCamU * (position.y * cell);
  vec4 mv = viewMatrix * vec4(P, 1.0);
  gl_Position = projectionMatrix * mv;
  /* gate visibility here, not with a fragment-shader discard — combining
     discard with reading the vC varying left the whole pass invisible on
     this driver, so an all-or-nothing point size sidesteps it entirely.
     the page never appears in the scout miniature (uMini). */
  gl_PointSize = (vis < 0.5 || uMini > 0.5)
    ? 0.0
    : min(cell * 0.86 * uScale / max(-mv.z, 0.5), 200.0);
}
`;
export const GRID_FSH = `
precision highp float;
varying vec3 vC;
void main(){
  vec2 p = gl_PointCoord * 2.0 - 1.0;
  float mq = max(abs(p.x), abs(p.y));
  /* the outer 8% of the sprite is the gap between cells — cut it with
     alpha rather than discard (discard + a color varying breaks this
     pass on some drivers), so the rim never shows as a dark border */
  float inside = 1.0 - step(0.92, mq);
  float edge = 1.0 - smoothstep(0.78, 0.92, mq) * 0.4;
  gl_FragColor = vec4(vC * edge, inside);
}
`;

export const RING_VSH = `
attribute vec3 aSphere;
attribute float aCFrac;
attribute float aAngle;
attribute float aValue;
attribute float aChroma;
uniform float uChart, uMorph, uScale, uMini;
uniform float uSliceMode, uSlicePos, uSliceHalf, uHueCount, uCellHue, uCellVal;
uniform vec3 uCamR, uCamU, uAnchor;
varying float vA;

float sliceGate(float angle, float value, float cfrac){
  float s = 1.0;
  if (uSliceMode > 0.5 && uSliceMode < 1.5){
    float phi = uSlicePos * 3.14159265;
    float dA = angle - phi;
    dA = abs(atan(sin(dA), cos(dA)));
    dA = min(dA, 3.14159265 - dA);
    s = 1.0 - smoothstep(uSliceHalf * 0.55, uSliceHalf * 0.95, dA);
    s = max(s, step(cfrac, 0.001));
  } else if (uSliceMode > 1.5){
    float dv = abs(value - uSlicePos * 10.0);
    s = (1.0 - smoothstep(0.4, 0.75, dv)) * step(0.001, cfrac);
  }
  return s;
}

void main(){
  float sIn = sliceGate(aAngle, aValue, aCFrac);
  float lin = uMorph * uMorph * (3.0 - 2.0 * uMorph);
  float s = min(1.0, aChroma / 13.0 * 1.12);
  float cell;
  vec2 g;
  if (uSliceMode > 1.5){
    cell = uCellVal;
    float hIdx = aAngle / 6.2831853 * uHueCount;
    g = vec2(hIdx - uHueCount * 0.5 + 0.5, s * 8.0 - 4.5);
  } else {
    cell = uCellHue;
    float phi = uSlicePos * 3.14159265;
    float dA = atan(sin(aAngle - phi), cos(aAngle - phi));
    float side = step(abs(dA), 1.5707963) * 2.0 - 1.0;
    g = vec2(side * s * 8.0, aValue - 5.0);
  }
  float ch = smoothstep(0.02, 1.0, uChart);
  vA = ch * lin * sIn * (1.0 - uMini);
  vec3 P = uAnchor + uCamR * (g.x * cell) + uCamU * (g.y * cell);
  vec4 mv = viewMatrix * vec4(P, 1.0);
  gl_Position = projectionMatrix * mv;
  gl_PointSize = min(cell * 1.05 * uScale / max(-mv.z, 0.5), 220.0) * step(0.01, vA);
}
`;
export const RING_FSH = `
precision highp float;
varying float vA;
void main(){
  if (vA < 0.02) discard;
  vec2 p = gl_PointCoord * 2.0 - 1.0;
  float d = length(p);
  float core = 1.0 - smoothstep(0.13, 0.22, d);
  float shad = (1.0 - smoothstep(0.16, 0.58, d)) * 0.45;
  float a = max(core, shad) * vA;
  if (a < 0.01) discard;
  vec3 col = mix(vec3(0.02, 0.03, 0.05), vec3(0.97, 0.98, 1.0), core);
  gl_FragColor = vec4(col, a);
}
`;
