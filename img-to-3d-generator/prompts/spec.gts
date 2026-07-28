// Stage 2 of the pipeline: turn the analysis plan into a primitive tree.

import { SPEC_JSON_SHAPE } from './spec-shape';
import { selectRecipes } from './recipes';

// Block 1 of the system prompt: identical for every object, every call. Kept
// its own constant because that is exactly what makes it cacheable upstream —
// see systemMessage() in util/llm-request.gts.
export const SPEC_SYSTEM_PROMPT = `You are a 3D reconstruction engine. You receive one or MORE reference views of the same object and rebuild it as a procedural Three.js primitive tree. Respond with ONLY a JSON object — no markdown fences, no prose.

${SPEC_JSON_SHAPE}`;

// The system prompt as content blocks: the invariant contract first, then only
// the craft rules this object's own analysis asks for. Two blocks rather than
// one concatenated string so the invariant half stays byte-identical across
// objects and keeps its cache hit.
//
// With no analysis (or an analysis with no partPlan) this degrades to the
// contract alone, which is self-contained — it carries the schema, the
// primitive semantics, the world frame and every universal rule.
export function buildSpecSystemPrompt(analysis: any): string[] {
  let recipes = selectRecipes(analysis);
  return recipes
    ? [
        SPEC_SYSTEM_PROMPT,
        `Build directives for THIS object, selected from its analysis. They are as binding as the rules above.\n\n${recipes}`,
      ]
    : [SPEC_SYSTEM_PROMPT];
}
