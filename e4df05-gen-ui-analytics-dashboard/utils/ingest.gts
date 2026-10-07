// Prompts and helpers for turning a dropped file or a live-web question into
// a Dataset: the LLM contract, response cleanup, error wording and the image
// downscale that keeps a screenshot under the proxy's body limit.

export const SUGGESTIONS = [
  'How have Tesla and BYD deliveries trended over the last five years?',
  'What share of the global EV market do Tesla, BYD and the rest hold?',
  'Compare Tesla and BYD sales in 2025',
];

export const EXTRACT_PROMPT = `You read tables out of images (screenshots, whiteboard photos, paper reports) or raw CSV/JSON text. Extract the tabular data and answer with ONE JSON object only — no prose, no markdown fences:
{
  "title": "<short name for this dataset>",
  "columns": [{ "name": "<column>", "type": "string|number|date" }],
  "rows": [{ "<column>": <value> }],
  "suggestedChart": {
    "chartKind": "line|bar|stacked-bar|pie|donut|scatter|kpi",
    "x": "<dimension column>",
    "xBucket": "none|month|quarter|year",
    "y": { "field": "<numeric column>", "aggregate": "sum|count|avg" },
    "title": "<chart title>"
  }
}
Rules: numeric columns come back as numbers (strip currency symbols and thousands separators); dates as ISO strings; keep column names short, no spaces preferred (camelCase). Pick the suggestedChart per: time series → line, category comparison → bar, part-of-whole (≤6 cats) → pie/donut, single figure → kpi. If the x column is already an aggregated label (e.g. "Q2 2025"), use xBucket "none".`;

// live-web questions go to a search-grounded model (Perplexity Sonar): it
// searches the web at answer time and cites its sources, so the dataset is
// current instead of model-memory
export const WEB_MODEL = 'perplexity/sonar';

export const WEB_PROMPT = `You answer data questions using CURRENT web information. Search for the latest figures, then answer with ONE JSON object only — no prose, no markdown fences:
{
  "title": "<short name for this dataset>",
  "columns": [{ "name": "<column>", "type": "string|number|date" }],
  "rows": [{ "<column>": <value> }],
  "suggestedChart": {
    "chartKind": "line|bar|stacked-bar|pie|donut|scatter|kpi",
    "x": "<dimension column>",
    "xBucket": "none|month|quarter|year",
    "y": { "field": "<numeric column>", "aggregate": "sum|count|avg" },
    "title": "<chart title>"
  },
  "sources": ["<url>", "<url>"]
}
Rules: numeric columns come back as numbers (strip currency symbols and thousands separators); dates as ISO strings; keep column names short, camelCase. sources lists the actual web pages the figures came from. Pick the suggestedChart per: time series → line, category comparison → bar, part-of-whole (≤6 cats) → pie/donut, single figure → kpi. If the x column is already an aggregated label (e.g. "Q2 2025"), use xBucket "none".

QUESTION: `;

export function stripJsonFences(text: string): string {
  return text
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/, '');
}

// realm cards cap at 512KB; leave room for columns/meta around the rows
export const MAX_ROWS_JSON_BYTES = 380_000;

// error objects often arrive as a JSON blob with a stack — pull out the one
// human sentence and drop the rest
export function humanizeError(e: any): string {
  let msg: string = e?.message ?? String(e);
  if (msg.includes('exceeds maximum allowed size')) {
    return 'the extracted table is too large for one card — try a smaller file';
  }
  let jsonStart = msg.indexOf('{');
  if (jsonStart !== -1) {
    try {
      let parsed = JSON.parse(msg.slice(jsonStart));
      msg = parsed.title ?? parsed.message ?? msg.slice(0, jsonStart).trim();
      if (msg.includes('exceeds maximum allowed size')) {
        return 'the extracted table is too large for one card — try a smaller file';
      }
    } catch {
      msg = msg.slice(0, jsonStart).trim() || msg;
    }
  }
  return msg.length > 180 ? `${msg.slice(0, 180)}…` : msg;
}

export const MAX_IMAGE_DIM = 1600;

export async function compressImage(file: File): Promise<string> {
  let bitmap = await createImageBitmap(file);
  try {
    let scale = Math.min(
      1,
      MAX_IMAGE_DIM / Math.max(bitmap.width, bitmap.height),
    );
    let canvas = document.createElement('canvas');
    canvas.width = Math.round(bitmap.width * scale);
    canvas.height = Math.round(bitmap.height * scale);
    let ctx = canvas.getContext('2d');
    if (!ctx) {
      throw new Error('Could not read the image');
    }
    // JPEG has no alpha: paint white under transparent PNGs so they stay
    // readable (a pixel fill in the upload, not a themed colour)
    ctx.fillStyle = 'white';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL('image/jpeg', 0.82);
  } finally {
    bitmap.close();
  }
}
