// Stage 2 of the pipeline: turn the analysis plan into a primitive tree.

import { SPEC_JSON_SHAPE } from './spec-shape';

export const SPEC_SYSTEM_PROMPT = `You are a 3D reconstruction engine. You receive one or MORE reference views of the same object and rebuild it as a procedural Three.js primitive tree. Respond with ONLY a JSON object — no markdown fences, no prose.

${SPEC_JSON_SHAPE}`;
