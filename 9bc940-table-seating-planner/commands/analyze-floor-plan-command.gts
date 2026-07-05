import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { Command } from '@cardstack/runtime-common';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  let binary = '';
  let bytes = new Uint8Array(buffer);
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

async function toDataUrl(url: string): Promise<string> {
  if (url.startsWith('data:image/')) return url;
  let res = await fetch(url);
  if (!res.ok)
    throw new Error(`Failed to fetch image: ${res.statusText} (${url})`);
  let contentType = res.headers.get('content-type') ?? 'image/jpeg';
  let b64 = arrayBufferToBase64(await res.arrayBuffer());
  return `data:${contentType};base64,${b64}`;
}

class AnalyzeInput extends CardDef {
  @field imageUrl = contains(StringField); // data: URL of the plan image
  @field planRect = contains(StringField); // JSON {x,y,w,h} in canvas units
  @field instruction = contains(StringField);
  @field llmModel = contains(StringField);
}
class AnalyzeResult extends CardDef {
  @field output = contains(StringField);
}

export class AnalyzeFloorPlanCommand extends Command<
  typeof AnalyzeInput,
  typeof AnalyzeResult
> {
  static actionVerb = 'Analyze';
  static displayName = 'Analyze Floor Plan';

  async getInputType() {
    return AnalyzeInput;
  }

  protected async run(input: AnalyzeInput): Promise<AnalyzeResult> {
    if (!input.imageUrl) throw new Error('imageUrl is required');
    let rect = { x: 0, y: 0, w: 800, h: 600 };
    try {
      rect = { ...rect, ...JSON.parse(input.planRect || '{}') };
    } catch {}

    let prompt = `You are an expert venue floor-plan analyst. Your job is to read the attached floor-plan drawing and reproduce it FAITHFULLY — the output should look like the same room, element for element. Treat this as tracing the plan, not inventing a new one.

== HOW TO READ POSITION ==
A fine red REFERENCE GRID (20 columns x 20 rows) is drawn over the image. The red numbers along the TOP edge are canvas X coordinates; the numbers down the LEFT edge are canvas Y coordinates. The whole plan occupies x=${rect.x}, y=${rect.y}, width=${rect.w}, height=${rect.h}.
For EACH element, work out its box precisely from the grid:
- Find the grid line nearest each of its four sides and read the X/Y numbers there; interpolate between lines for a closer value. "x","y" = the TOP-LEFT corner; "width" = right minus left; "height" = bottom minus top.
- Then VERIFY: picture the box you are about to output drawn back onto this grid. It must cover the SAME grid cells as the real shape in the drawing. If your box would sit higher/lower/left/right of the drawn shape, or be bigger/smaller, adjust the numbers until it lands exactly on top of it.
- Position accuracy matters as much as shape: a table drawn spanning x=120..480 must come back as x≈120, width≈360 — not centred or rounded to a tidy number. Match the drawing, do not normalise.

== WHAT COUNTS AS A TABLE (READ THIS FIRST) ==
A shape is a TABLE only if it has CHAIRS drawn beside it or surrounding it — the chairs look like small squares or little rounded seat glyphs lined up along the shape's edges or ringed around it. The chairs are the decisive clue.
- A shape ringed or flanked by these chair marks IS a table. Count the chair marks to set "seatCount", and read the shape from the central body (the part the chairs sit against), NOT the chairs.
- A shape with NO chairs around it is NOT a table — it is decoration or a fixture (stage, dance floor, bar, plant, cake, arch, red carpet, etc.). Output it under "fixtures", never under "tables". (EXCEPTION: a repeating field of parallel rows — see SEATING SECTIONS below — IS guest seating, even when individual chairs are too faint to make out. Do not omit it.)
- Never output a chairless shape as a table, and never output a chair-ringed shape as a fixture.
- SEATING SECTIONS (blocks / rows of chairs with NO table) — THE MOST COMMONLY MISSED ELEMENT, READ CAREFULLY. Many plans fill the main floor with a REPEATING PATTERN of parallel bars / stripes / rows / bands — evenly spaced light or outlined rectangles marching across the room. THAT REPEATING PATTERN IS GUEST SEATING (theatre / banquet / ceremony rows), NOT the floor, NOT a red carpet, and NOT one big rectangle. You MUST reproduce it:
  * Do NOT drop it just because you cannot resolve each individual chair — the repeating bars ARE the rows of seats.
  * Do NOT merge the whole field into a single big "rect" or a single fixture. That is the #1 mistake.
  * Represent each contiguous block of rows as ONE "shape":"section" element. Set "rows" = how many parallel bars/rows you count in that block, and "cols" = roughly how many seats sit along each row (estimate from the row's length; a typical row holds 6–20). "x","y","width","height" = the bounding box of the whole block.
  * If an aisle/gap splits the rows into a left group and a right group, output TWO sections (one per side); if it is one solid field of rows, output ONE section.
  * Count the bars carefully: if you see 6 stripes, that block has "rows":6.
- STANDALONE SEATS (a lone chair, NO table). A single free-standing labelled chair (e.g. "Bridesmaid", "Best Man") that is not part of a grid is its OWN seat: output it under "tables" with "shape":"seat","seatCount":1. A cluster of chairs pulled up to a shared body is still a normal table (read its body shape); a grid of aisle-facing chairs is a "section" (above); only a lone chair becomes a "seat".
- DECORATIVE OUTLINES (shapes with NO chairs) — MATCH THE DRAWN SHAPE, do not force a curve. A plain outline shape sitting on the plan with no chairs is decoration/architecture, not a table. Output it as a FIXTURE whose kind matches how it is drawn: a rectangle or square outline → "rect-decor"; a circle / round / ring outline → "round-decor"; a curved arc / crescent hugging a corner or wall → "curved-wall". Do NOT drop it, do NOT output it as a table, and do NOT turn a straight-edged rectangle into a "curved-wall". Only call a curved shape a TABLE (shape "curved") when chairs are clearly drawn against its concave side.

== WORK SYSTEMATICALLY ==
1. First scan the entire image and COUNT every table (every chair-ringed shape) AND every seating area (every field of repeating parallel rows → one or two "section" elements). Do not stop early, do not summarise, do not merge two tables into one, and NEVER skip the rows of seating that fill the main floor. If the plan shows 8 tables, return exactly 8. If it shows a block of 6 seating rows, return a section with rows:6. If it shows 4 curved seating arcs, return 4.
2. For each item, note WHERE it sits relative to the room (top edge / bottom edge / left side / right side / centre / a specific corner) and reproduce that same relative position. A table drawn in the top-left of the plan must come back in the top-left of the canvas. Preserve the overall arrangement (e.g. a ring of perimeter tables around a central dance floor stays a ring around the centre).
3. Reproduce ORIENTATION + SCALE. A long table running horizontally (along the top/bottom) → width > height. A long table running vertically (along the left/right side) → height > width. Round tables → width ≈ height. Keep each element's relative SIZE faithful: a big head table stays big, a small cocktail round stays small — set "width"/"height" to its true drawn footprint.
4. Reproduce ROTATION. If a shape is drawn at an angle (tilted / diagonal — its long axis is NOT horizontal or vertical), estimate its angle and return it as "rotation" in degrees, 0–359, measured CLOCKWISE from upright. A shape drawn straight (axis-aligned) is rotation 0. This applies to tables AND fixtures.
5. Read SEATING from WHERE THE CHAIRS ARE DRAWN, and set "seatCount" to HOW MANY chairs are drawn. Look at each table's four edges and decide which edges have chairs against them, then return "seatingStyle":
   - "around" — chairs ring the whole table (all sides). Typical for round, oval, and square tables, and for rectangles with chairs on every edge.
   - "opposite" — chairs on the TWO LONG sides only, with the short ends bare. The classic long banquet table. This is by the table's own long axis: a tall vertical banquet has chairs on its LEFT and RIGHT and is still "opposite"; a wide horizontal banquet has chairs on its TOP and BOTTOM and is also "opposite".
   - "top" / "bottom" / "left" / "right" — chairs on ONE side only (head table against a wall, a bar-style counter). Use the side as drawn in the image.
   Then COUNT the chairs and put the total in "seatCount" — e.g. a long table with 6 chairs down each side is "seatingStyle":"opposite","seatCount":12. Do not guess a round number; count what is drawn. If a shape you are outputting as a table has NO chairs drawn against it (e.g. a bare curved lounge body), set "seatCount":0 — do NOT invent chairs to fill it.
6. FIND THE STAGE (so seating can face it). If there are any seating sections, decide which end of the room is the FRONT — where the stage / altar / platform / head table is. The seating faces the stage. Clues, in order:
   (a) A drawn stage / platform / raised deck / head table → that is the front; seating faces it.
   (b) The ceremony ARCH is the ENTRANCE, NOT the stage. It sits at the BACK of the seating (behind the guests). So when an arch is the only landmark, the stage is at the OPPOSITE end from the arch, and the seating faces AWAY from the arch.
   (c) The RED-CARPET / aisle runner runs from the entrance (arch end) to the stage; the stage is the far end of the runner AWAY from the arch. Seating faces along the aisle toward that far end.
   (d) If nothing else, use the open end the rows of chairs are oriented toward.
   Note which edge (top / right / bottom / left of the plan) the stage sits on; you will use it to set each section's "rotation" (see ELEMENT MAPPING). All sections face the same stage.

== ELEMENT MAPPING ==
- tables (chair-ringed shapes, seating sections, plus standalone seats): "shape" ("round" | "oval" | "rect" | "square" | "curved" | "section" | "seat"). For "shape":"section" (a grid of aisle-facing chairs, no table body) also return "rows" (how many rows deep, front→back) and "cols" (chairs per row) — the app draws the whole chair grid from these; "x","y","width","height" = the block's bounding box. FACE THE SEATING AT THE STAGE via "rotation": the app treats the section's FRONT edge (row 1, the row nearest the stage) as the side guests look toward, and marks it with a ▲. Work out where the stage / altar / head of the room is (see WORK SYSTEMATICALLY point 6), then set "rotation" so the front points at it — stage at TOP of plan → rotation 0; stage at RIGHT → 90; stage at BOTTOM → 180; stage at LEFT → 270. Every seating section faces the SAME stage, so they usually share one rotation. For a "section" ALSO read the SEAT NUMBERING when the chairs are drawn with numbers: follow the numbers 1, 2, 3… across the block and return "seatOrder" as one of "lr-tb" (numbers run across each row left→right, top row first — the default), "rl-tb" (across each row right→left), "lr-bt" (across rows left→right but starting from the BOTTOM row), "snake" (each row alternates direction, 1..6 then 12..7), "col-lr" (numbers run DOWN each column, columns left→right), "col-rl" (down each column, columns right→left). Read the direction in the block's own drawn orientation. If the chairs are unnumbered, omit "seatOrder". "seatingStyle" ("around" | "opposite" | "top" | "bottom" | "left" | "right" — read from where the chairs sit, see point 5), "seatCount" (the number of chairs actually drawn), "x", "y", "width", "height", "rotation" (degrees 0–359 clockwise, 0 if upright), "name" (e.g. "Table 1"). Match the drawn shape exactly: long banquet rectangle → "rect" with width much larger than height (e.g. 360 x 70); small circle → "round" with a square box; a curved/arc/crescent seating table → "curved" (wide and shallow) ONLY when chairs are drawn against its concave side (a bare corner arc with no chairs is a decorative wall — omit it, never output it as a curved table). A "curved" table is almost always drawn at an angle following the room's edge, so estimate and return its real "rotation" rather than leaving it at 0. "width"/"height" = the SOLID INNER TABLE BODY only — the surface people sit at. The chair marks are drawn OUTSIDE that body, ringing its edge; do NOT include the chair ring in the size and never pad the table to fit chairs (the app draws its own seats around the footprint). For a standalone seat use "shape":"seat","seatCount":1,"seatingStyle":"around" with a small square box (~46 x 46) centred on the drawn chair, and a "name" like "Bridesmaid", "Best Man", or "Seat 1"; "x","y" = the chair's top-left.
- fixtures (chairless shapes — only what is clearly drawn): "kind" one of "stage" | "dance-floor" | "bar" | "arch" | "red-carpet" | "plant" | "cake" | "curved-wall" | "rect-decor" | "round-decor", plus "x","y","width","height","rotation" (degrees 0–359 clockwise, 0 if upright). Map by appearance: a checkerboard/parquet square in the middle → "dance-floor"; a raised platform → "stage"; a long counter → "bar"; a single archway → "arch"; an aisle runner → "red-carpet"; greenery → "plant"; a bare corner arc / curved divider → "curved-wall"; a plain rectangle/square outline → "rect-decor"; a plain circle/ring outline → "round-decor". (Curved SEATING with chairs is a TABLE with shape "curved", NOT a fixture.)
  POSITION FIXTURES CAREFULLY — they anchor the room, so getting them wrong throws the whole layout off:
  - "arch": the ENTRANCE, at the BACK of the seating — the end the chairs face AWAY from (opposite the stage), centred on the aisle, NOT off to one side. Put its x centred on the aisle, its y at the entrance end (behind the guests).
  - "red-carpet": the aisle runner runs the FULL length from the arch/entrance end toward the stage (between the two seating blocks). Make it long and thin along the aisle — its "height" (or "width" if the aisle is horizontal) should span almost the whole run, not a short stub. Centre it in the gap between the left and right seating sections.
  - Read every fixture's box off the grid the same way as tables (top-left corner + width/height); do not shrink a long runner to a tidy small box.

== RULES ==
- Mirror the plan's shapes, counts, positions, orientation and relative scale as closely as the grid allows.
- Keep every element inside the plan rectangle; do not let tables overlap each other.
- For "seatCount", COUNT the individual chair marks actually drawn around that table — that real count is the answer, and it may be 0 for a table body drawn with no chairs. Only fall back to estimating from the table's size when the chairs are too faint or crowded to count one by one. ALWAYS prioritise correct shape/proportion/position over exact seat count.
- Only include elements that are actually drawn — never invent furniture that isn't there, and never drop one that is.

OUTPUT ONE JSON object only — no prose, no markdown fences:
{"tables":[{"name":"Table 1","shape":"rect","seatingStyle":"opposite","seatCount":14,"x":240,"y":20,"width":360,"height":70,"rotation":0},{"name":"Left Seating","shape":"section","rows":6,"cols":5,"seatCount":30,"seatOrder":"lr-tb","x":180,"y":180,"width":180,"height":260,"rotation":180},{"name":"Right Seating","shape":"section","rows":6,"cols":5,"seatCount":30,"seatOrder":"rl-tb","x":460,"y":180,"width":180,"height":260,"rotation":180}],"fixtures":[{"kind":"arch","x":390,"y":30,"width":180,"height":110,"rotation":0},{"kind":"red-carpet","x":405,"y":150,"width":90,"height":320,"rotation":0}],"summary":"one short sentence describing the room"}${
      input.instruction
        ? `\n\nPlanner note (honour this too): ${input.instruction}`
        : ''
    }`;

    let imageUrl = await toDataUrl(input.imageUrl);

    let result = await new SendRequestViaProxyCommand(
      this.commandContext,
    ).execute({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'POST',
      requestBody: JSON.stringify({
        model: input.llmModel || 'anthropic/claude-opus-4.8',
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: prompt },
              { type: 'image_url', image_url: { url: imageUrl } },
            ],
          },
        ],
      }),
    });

    if (!result.response.ok) {
      let errBody = '';
      try {
        errBody = await result.response.text();
      } catch {}
      throw new Error(
        `OpenRouter error ${result.response.status}: ${
          errBody || result.response.statusText
        }`,
      );
    }

    let data = await result.response.json();
    let message = data.choices?.[0]?.message;
    let text =
      typeof message?.content === 'string'
        ? message.content
        : Array.isArray(message?.content)
          ? (message.content as any[])
              .filter((p) => p.type === 'text')
              .map((p) => p.text)
              .join('\n')
          : '';

    return new AnalyzeResult({ output: text });
  }
}
