import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { restartableTask } from 'ember-concurrency';
import { modifier } from 'ember-modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { BoxelInput, Button } from '@cardstack/boxel-ui/components';
import { htmlSafe } from '@ember/template';
import type { SafeString } from '@ember/template';
import UseAiAssistantCommand from '@cardstack/boxel-host/commands/ai-assistant';
import ShowCardCommand from '@cardstack/boxel-host/commands/show-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';
import WriteBinaryFileCommand from '@cardstack/boxel-host/commands/write-binary-file';
import LayoutDashboardIcon from '@cardstack/boxel-icons/layout-dashboard';
import SunIcon from '@cardstack/boxel-icons/sun';
import MoonIcon from '@cardstack/boxel-icons/moon';
import ArrowBackUpIcon from '@cardstack/boxel-icons/arrow-back-up';
import ArrowForwardUpIcon from '@cardstack/boxel-icons/arrow-forward-up';
import type { BaseDef, BoxComponent } from '@cardstack/base/card-api';

import { ChartCard, DimensionField, MeasureField } from './chart-card';
import { Dataset, parseRows } from './dataset';
import { parseCsv, suggestChart } from './utils/parse-csv';

// ---------------------------------------------------------------------------
// The dashboard is a wall of LINKED CARDS. The AI answers a question by
// CREATING a ChartCard (flat, LLM-friendly fields) and linking it here —
// charts are first-class cards: openable alone, shareable across dashboards,
// and a broken one breaks only its own tile. "New customer" flows link the
// created CRM records directly; any card embeds.
// ---------------------------------------------------------------------------

function getComponent(
  cardOrField: BaseDef | undefined | null,
): BoxComponent | undefined {
  if (!cardOrField) {
    return;
  }
  let constructor = cardOrField.constructor as typeof BaseDef | undefined;
  if (typeof constructor?.getComponent !== 'function') {
    return;
  }
  return constructor.getComponent(cardOrField);
}

const RESIZE_DIRS = ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'];

interface TileRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

// resize/data controls only make sense on our own ChartCards; any other
// linked card is just rendered
function isChart(card: any): boolean {
  return typeof card?.chartKind === 'string';
}

const SUGGESTIONS = [
  'How have Tesla and BYD deliveries trended over the last five years?',
  'What share of the global EV market do Tesla, BYD and the rest hold?',
  'Compare Tesla and BYD sales in 2025',
];

const EXTRACT_PROMPT = `You read tables out of images (screenshots, whiteboard photos, paper reports) or raw CSV/JSON text. Extract the tabular data and answer with ONE JSON object only — no prose, no markdown fences:
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
const WEB_MODEL = 'perplexity/sonar';

const WEB_PROMPT = `You answer data questions using CURRENT web information. Search for the latest figures, then answer with ONE JSON object only — no prose, no markdown fences:
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

function stripJsonFences(text: string): string {
  return text
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/, '');
}

// realm cards cap at 512KB; leave room for columns/meta around the rows
const MAX_ROWS_JSON_BYTES = 380_000;

// error objects often arrive as a JSON blob with a stack — pull out the one
// human sentence and drop the rest
function humanizeError(e: any): string {
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

const MAX_IMAGE_DIM = 1600;

async function compressImage(file: File): Promise<string> {
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
    // white backdrop so transparent PNGs stay readable as JPEG
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL('image/jpeg', 0.82);
  } finally {
    bitmap.close();
  }
}

interface TileSignature {
  Args: {
    card: any;
  };
  Element: HTMLElement;
}

// one dashboard tile: renders the linked card's embedded format
class Tile extends GlimmerComponent<TileSignature> {
  get component(): BoxComponent | undefined {
    return getComponent(this.args.card);
  }

  <template>
    {{#if this.component}}
      {{#let this.component as |CardComponent|}}
        <CardComponent @format='embedded' />
      {{/let}}
    {{/if}}
  </template>
}

class Isolated extends Component<typeof GenUiDashboard> {
  get hasLinkedTheme(): boolean {
    return Boolean(this.args.model?.cardInfo?.theme);
  }

  // night/light toggle, ai-image-generator pattern: data-theme drives the
  // pin class variant; a linked theme ignores it (dark comes from .dark)
  @tracked colorScheme: 'light' | 'dark' = 'dark';

  @action toggleColorScheme() {
    this.colorScheme = this.colorScheme === 'dark' ? 'light' : 'dark';
  }
  @tracked promptDraft = '';
  @tracked isDragging = false;
  @tracked extractError: string | undefined;
  // when on, questions skip the assistant and go straight to a search-grounded
  // model — the dataset is built from live web results with cited sources
  @tracked useLiveWeb = false;

  get realm(): string | undefined {
    return this.args.model?.[realmURL]?.href;
  }

  get cards(): any[] {
    return (this.args.model?.cards ?? []).filter(Boolean);
  }

  get isAsking(): boolean {
    return this.askAi.isRunning || this.webAsk.isRunning;
  }

  get askLabel(): string {
    if (this.webAsk.isRunning) {
      return 'Searching…';
    }
    if (this.askAi.isRunning) {
      return 'Opening…';
    }
    return this.useLiveWeb ? 'Search web' : 'Ask AI';
  }

  @action updateDraft(event: Event) {
    this.promptDraft = (event.target as HTMLInputElement).value;
  }

  @action onPromptKeydown(event: Event) {
    if ((event as KeyboardEvent).key === 'Enter' && this.promptDraft.trim()) {
      this.ask(this.promptDraft.trim());
    }
  }

  @action suggest(prompt: string) {
    if (prompt?.trim()) {
      this.ask(prompt.trim());
    }
  }

  @action ask(prompt: string) {
    if (this.useLiveWeb) {
      this.webAsk.perform(prompt);
    } else {
      this.askAi.perform(prompt);
    }
  }

  // empty prompt = nothing to ask; the button says why on hover
  get askDisabled(): boolean {
    return this.isAsking || !this.promptDraft.trim();
  }

  get askTitle(): string {
    if (!this.promptDraft.trim()) {
      return 'Type a question first';
    }
    return this.useLiveWeb
      ? 'Search the live web with cited sources'
      : 'Ask the AI assistant';
  }

  @action toggleLiveWeb() {
    this.useLiveWeb = !this.useLiveWeb;
  }

  @action dismissError() {
    this.extractError = undefined;
  }

  @action dismissNotice() {
    this.extractNotice = undefined;
  }

  // command-pattern history (TSP pattern): each canvas mutation pushes an
  // undo/redo closure pair; a new action clears the redo branch
  private undoStack: { u: () => void; r: () => void }[] = [];
  private redoStack: { u: () => void; r: () => void }[] = [];
  @tracked undoDepth = 0;
  @tracked redoDepth = 0;

  private pushUndo(u: () => void, r: () => void) {
    this.undoStack.push({ u, r });
    this.redoStack = [];
    this.undoDepth = this.undoStack.length;
    this.redoDepth = 0;
  }

  undo = () => {
    let e = this.undoStack.pop();
    if (!e) {
      return;
    }
    e.u();
    this.redoStack.push(e);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
  };

  redo = () => {
    let e = this.redoStack.pop();
    if (!e) {
      return;
    }
    e.r();
    this.undoStack.push(e);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
  };

  private restoreEntry(key: string, entry: TileRect | undefined) {
    let next = { ...this.liveLayout };
    if (entry) {
      next[key] = entry;
    } else {
      delete next[key];
    }
    this.liveLayout = next;
    this.persistLayout();
  }

  shortcuts = modifier(() => {
    let onKey = (e: KeyboardEvent) => {
      let el = document.activeElement as HTMLElement | null;
      if (el && /^(INPUT|TEXTAREA)$/.test(el.tagName)) {
        return;
      }
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        if (e.shiftKey) {
          this.redo();
        } else {
          this.undo();
        }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  // which tile is mid-drag (drives the lifted visual)
  @tracked movingIndex: number | undefined;

  // removing a card is destructive — the x asks once, then removes on the
  // second click; doing nothing for a beat cancels the request
  @tracked confirmRemoveIndex: number | undefined;

  @action requestRemove(index: number) {
    if (this.confirmRemoveIndex === index) {
      this.confirmRemoveIndex = undefined;
      this.unlinkCard(index);
      return;
    }
    this.confirmRemoveIndex = index;
    setTimeout(() => {
      if (this.confirmRemoveIndex === index) {
        this.confirmRemoveIndex = undefined;
      }
    }, 3500);
  }

  @action unlinkCard(index: number) {
    let removed = this.args.model?.cards?.[index];
    let key = removed ? this.layoutKey(removed, index) : undefined;
    let entry = key ? this.liveLayout?.[key] : undefined;
    let doRemove = () => {
      let cards = [...(this.args.model?.cards ?? [])];
      let at = removed ? cards.indexOf(removed) : index;
      cards.splice(at === -1 ? index : at, 1);
      (this.args.model as any).cards = cards;
      this.dataPreviewIndex = undefined;
    };
    doRemove();
    this.confirmRemoveIndex = undefined;
    if (removed) {
      this.pushUndo(() => {
        let cards = [...(this.args.model?.cards ?? [])];
        cards.splice(Math.min(index, cards.length), 0, removed);
        (this.args.model as any).cards = cards;
        if (key && entry) {
          this.restoreEntry(key, entry);
        }
      }, doRemove);
    }
  }

  // which tile is showing its in-tile dataset preview panel
  @tracked dataPreviewIndex: number | undefined;

  @action toggleDataPreview(index: number) {
    this.dataPreviewIndex = this.dataPreviewIndex === index ? undefined : index;
  }

  // show-card caps at one companion stack: it opens into the right stack,
  // creating it only if the dashboard is alone — never a third column
  async showInRightStack(cardId: string | undefined) {
    let commandContext = this.args.context?.commandContext;
    if (!cardId || !commandContext) {
      return;
    }
    await new ShowCardCommand(commandContext).execute({
      cardId,
      format: 'isolated',
    });
  }

  @action openCard(card: any) {
    this.showInRightStack(card?.id);
  }

  @action openDataset(card: any) {
    this.showInRightStack(card?.dataset?.id);
  }

  // ------------------------------------------------------------------
  // Canvas layout (Figma-style free placement, always snapped to 16px)
  // ------------------------------------------------------------------

  // during a drag/resize the pending geometry lives here (one autosave on
  // release, not one per pointermove)
  @tracked liveLayout: Record<string, TileRect> | undefined;
  @tracked resizingIndex: number | undefined;

  get storedLayout(): Record<string, TileRect> {
    try {
      let parsed = JSON.parse((this.args.model as any)?.layoutJson || '{}');
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
      return {};
    }
  }

  // keyed by the card id's last path segment: filenames survive a catalog
  // install (the realm prefix changes, the slug doesn't), so shipped example
  // layouts keep working
  layoutKey(card: any, index: number): string {
    let slug = card?.id?.split('/').pop();
    return slug || `i${index}`;
  }

  entryFor(card: any, index: number): TileRect {
    let key = this.layoutKey(card, index);
    let entry = this.liveLayout?.[key] ?? this.storedLayout[key];
    if (entry) {
      return entry;
    }
    // unplaced card (e.g. AI just linked one): flow into a 2-per-row default
    return {
      x: 16 + (index % 2) * 452,
      y: 16 + Math.floor(index / 2) * 356,
      w: 436,
      h: 340,
    };
  }

  tileStyleFor = (card: any, index: number): SafeString => {
    let { x, y, w, h } = this.entryFor(card, index);
    return htmlSafe(`left:${x}px;top:${y}px;width:${w}px;height:${h}px;`);
  };

  get boardStyle(): SafeString {
    let bottom = 0;
    let right = 0;
    this.cards.forEach((card, i) => {
      let { x, y, w, h } = this.entryFor(card, i);
      bottom = Math.max(bottom, y + h);
      right = Math.max(right, x + w);
    });
    return htmlSafe(
      `min-height:${bottom + 160}px; min-width:${right + 160}px;`,
    );
  }

  snap(value: number): number {
    return Math.round(value / 16) * 16;
  }

  persistLayout() {
    // bake every card's current entry (defaults included) so nothing jumps
    // on reload
    let baked: Record<string, TileRect> = {};
    this.cards.forEach((card, i) => {
      baked[this.layoutKey(card, i)] = this.entryFor(card, i);
    });
    (this.args.model as any).layoutJson = JSON.stringify(baked);
    this.liveLayout = undefined;
  }

  // Figma-style: long-press anywhere on a tile lifts it for dragging. A
  // quick tap, a press on inner controls, or >6px of early movement all
  // fall through to the card's own interactions.
  @action armTilePress(card: any, index: number, rawEvent: Event) {
    let event = rawEvent as PointerEvent;
    if (event.button !== 0) {
      return;
    }
    let target = event.target as HTMLElement;
    if (
      target.closest(
        'button, a, input, textarea, select, .rz, .tile-toolbar, .data-preview',
      )
    ) {
      return;
    }
    let tile = event.currentTarget as HTMLElement;
    let startX = event.clientX;
    let startY = event.clientY;
    let timer: ReturnType<typeof setTimeout>;
    let cancel = () => {
      clearTimeout(timer);
      tile.removeEventListener('pointermove', onEarlyMove);
      tile.removeEventListener('pointerup', cancel);
      tile.removeEventListener('pointercancel', cancel);
    };
    let onEarlyMove = (e: PointerEvent) => {
      if (Math.hypot(e.clientX - startX, e.clientY - startY) > 6) {
        cancel();
      }
    };
    timer = setTimeout(() => {
      cancel();
      this.beginMove(card, index, tile, startX, startY);
    }, 300);
    tile.addEventListener('pointermove', onEarlyMove);
    tile.addEventListener('pointerup', cancel);
    tile.addEventListener('pointercancel', cancel);
  }

  beginMove(
    card: any,
    index: number,
    tile: HTMLElement,
    clientX: number,
    clientY: number,
  ) {
    let board = tile.parentElement as HTMLElement | null;
    if (!board) {
      return;
    }
    this.resizingIndex = index;
    this.movingIndex = index;
    let boardRect = board.getBoundingClientRect();
    let tileRect = tile.getBoundingClientRect();
    let offsetX = clientX - tileRect.left;
    let offsetY = clientY - tileRect.top;
    let key = this.layoutKey(card, index);
    let base = this.entryFor(card, index);

    // a click fired at the end of a drag would activate whatever inner
    // element the pointer happens to be over — swallow that one click
    let suppressClick = (e: Event) => {
      e.preventDefault();
      e.stopPropagation();
    };
    tile.addEventListener('click', suppressClick, true);

    let onMove = (e: PointerEvent) => {
      let x = Math.max(0, this.snap(e.clientX - boardRect.left - offsetX));
      let y = Math.max(0, this.snap(e.clientY - boardRect.top - offsetY));
      this.liveLayout = { ...this.liveLayout, [key]: { ...base, x, y } };
    };
    let onUp = () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      this.movingIndex = undefined;
      setTimeout(
        () => tile.removeEventListener('click', suppressClick, true),
        0,
      );
      this.resizingIndex = undefined;
      let after = this.liveLayout?.[key];
      if (after && (after.x !== base.x || after.y !== base.y)) {
        this.pushUndo(
          () => this.restoreEntry(key, base),
          () => this.restoreEntry(key, after),
        );
      }
      this.persistLayout();
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
  }

  // drag-resize from any edge or corner (Figma-style 8 handles): pixel-based,
  // snapped to 16px, persisted in the dashboard's layoutJson. One save on
  // release. West/north drags move the origin while keeping the opposite
  // edge pinned.
  @action startResize(card: any, index: number, dir: string, rawEvent: Event) {
    let event = rawEvent as PointerEvent;
    event.preventDefault();
    event.stopPropagation();
    this.resizingIndex = index;
    let startX = event.clientX;
    let startY = event.clientY;
    let key = this.layoutKey(card, index);
    let base = this.entryFor(card, index);
    const MIN_W = 240;
    const MIN_H = 180;

    let onMove = (e: PointerEvent) => {
      let dx = e.clientX - startX;
      let dy = e.clientY - startY;
      let { x, y, w, h } = base;
      if (dir.includes('e')) {
        w = Math.max(MIN_W, this.snap(base.w + dx));
      }
      if (dir.includes('w')) {
        let maxX = base.x + base.w - MIN_W;
        x = Math.min(maxX, Math.max(0, this.snap(base.x + dx)));
        w = base.w + (base.x - x);
      }
      if (dir.includes('s')) {
        h = Math.max(MIN_H, this.snap(base.h + dy));
      }
      if (dir.includes('n')) {
        let maxY = base.y + base.h - MIN_H;
        y = Math.min(maxY, Math.max(0, this.snap(base.y + dy)));
        h = base.h + (base.y - y);
      }
      this.liveLayout = { ...this.liveLayout, [key]: { x, y, w, h } };
    };
    let onUp = () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      this.resizingIndex = undefined;
      let after = this.liveLayout?.[key];
      if (
        after &&
        (after.w !== base.w ||
          after.h !== base.h ||
          after.x !== base.x ||
          after.y !== base.y)
      ) {
        this.pushUndo(
          () => this.restoreEntry(key, base),
          () => this.restoreEntry(key, after),
        );
      }
      this.persistLayout();
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
  }

  previewRows = (card: any): any[] =>
    parseRows(card?.dataset?.rowsJson).slice(0, 8);

  previewColumns = (card: any): string[] => {
    let rows = parseRows(card?.dataset?.rowsJson);
    return rows.length ? Object.keys(rows[0]) : [];
  };

  cell = (row: any, key: string): string => {
    let value = row?.[key];
    return value == null ? '' : String(value);
  };

  // depth counter: dragleave fires on every child boundary crossing, so a
  // plain boolean flickers. Only depth 0 -> 1 and back changes the veil.
  dragDepth = 0;

  @action onDragEnter(event: Event) {
    event.preventDefault();
    this.dragDepth++;
    this.isDragging = true;
  }

  @action onDragOver(event: Event) {
    event.preventDefault();
  }

  @action onDragLeave(event: Event) {
    event.preventDefault();
    this.dragDepth = Math.max(0, this.dragDepth - 1);
    if (this.dragDepth === 0) {
      this.isDragging = false;
    }
  }

  @action onDrop(event: Event) {
    event.preventDefault();
    this.dragDepth = 0;
    this.isDragging = false;
    let files = [...((event as DragEvent).dataTransfer?.files ?? [])];
    if (files.length) {
      this.extractDataset.perform(files);
    }
  }

  async extractWithLlm(
    commandContext: any,
    content: { type: string; [k: string]: any }[],
    model = 'anthropic/claude-sonnet-4.6',
  ): Promise<any> {
    let result = await new SendRequestViaProxyCommand(commandContext).execute({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'POST',
      requestBody: JSON.stringify({
        model,
        messages: [{ role: 'user', content }],
      }),
    });
    if (!result.response.ok) {
      throw new Error(`extraction failed (${result.response.status})`);
    }
    let data = await result.response.json();
    let message = data.choices?.[0]?.message;
    let text =
      typeof message?.content === 'string'
        ? message.content
        : ((message?.content ?? []) as any[])
            .filter((p) => p.type === 'text')
            .map((p) => p.text)
            .join('\n');
    return JSON.parse(stripJsonFences(text));
  }

  @tracked extractProgress = '';

  // drop images (screenshots / whiteboard photos) or CSVs — several at once:
  // CSVs parse locally in an instant; images go through vision. Each file
  // lands in its own Dataset card with its own ChartCard, all linked here.
  @tracked extractNotice: string | undefined;

  extractDataset = restartableTask(async (files: File[]) => {
    this.extractError = undefined;
    this.extractNotice = undefined;
    let errors: string[] = [];
    for (let i = 0; i < files.length; i++) {
      this.extractProgress =
        files.length > 1 ? ` (${i + 1} of ${files.length})` : '';
      try {
        await this.extractOneFile(files[i]);
      } catch (e: any) {
        errors.push(`${files[i].name}: ${humanizeError(e)}`);
      }
    }
    this.extractProgress = '';
    if (errors.length) {
      this.extractError = errors.join(' · ');
    }
  });

  async extractOneFile(file: File) {
    let commandContext = this.args.context?.commandContext;
    let realm = this.realm;
    if (!commandContext || !realm) {
      return;
    }
    {
      let baseName = file.name.replace(/\.[a-z0-9]+$/i, '') || file.name;
      let extracted: any;

      if (!file.type.startsWith('image/')) {
        // structured text never goes through the LLM: parse locally —
        // instant, no token cost, no row limit
        let text = await file.text();
        let parsed = parseCsv(text);
        if (parsed) {
          extracted = {
            title: baseName,
            columns: parsed.columns,
            rows: parsed.rows,
            suggestedChart: suggestChart(parsed, baseName),
          };
        } else if (text.length > 30000) {
          throw new Error(
            'that file is too large to extract with AI — save it as a CSV and drop it again',
          );
        } else {
          extracted = await this.extractWithLlm(commandContext, [
            {
              type: 'text',
              text: `${EXTRACT_PROMPT}\n\nDATA:\n${text}`,
            },
          ]);
        }
      } else {
        // retina screenshots are several MB; the proxy rejects oversized
        // bodies, so downscale to <=1600px JPEG before sending
        let dataUrl = await compressImage(file);
        extracted = await this.extractWithLlm(commandContext, [
          { type: 'text', text: EXTRACT_PROMPT },
          { type: 'image_url', image_url: { url: dataUrl } },
        ]);
      }

      if (!Array.isArray(extracted.rows) || !extracted.rows.length) {
        throw new Error('no table found in that file');
      }

      // provenance: keep the original file in the realm so the extraction
      // can be checked against it (and re-run later)
      let sourceFileUrl = '';
      try {
        let base64 = await new Promise<string>((resolve, reject) => {
          let reader = new FileReader();
          reader.onload = () =>
            resolve(String(reader.result).split(',')[1] ?? '');
          reader.onerror = () => reject(new Error('unreadable file'));
          reader.readAsDataURL(file);
        });
        let slug =
          file.name
            .toLowerCase()
            .replace(/[^a-z0-9.]+/g, '-')
            .replace(/^-+|-+$/g, '') || 'dropped-data';
        let res = await new WriteBinaryFileCommand(commandContext).execute({
          path: `8d24c1-gen-ui-analytics/sources/${slug}`,
          realm,
          base64Content: base64,
          contentType: file.type || 'application/octet-stream',
          useNonConflictingFilename: true,
        });
        sourceFileUrl = (res as any)?.fileIdentifier ?? '';
      } catch {
        // provenance is best-effort; extraction proceeds without it
      }

      await this.mintDatasetAndChart(extracted, {
        fallbackTitle: file.name,
        sourceNoteBase: `extracted from ${file.name}`,
        sourceFileUrl,
      });
    }
  }

  // shared tail of both ingestion paths: cap rows to the card budget (never
  // silently), save a Dataset + ChartCard pair, and link the chart here
  async mintDatasetAndChart(
    extracted: any,
    opts: {
      fallbackTitle: string;
      sourceNoteBase: string;
      sourceFileUrl: string;
    },
  ) {
    let commandContext = this.args.context?.commandContext;
    let realm = this.realm;
    if (!commandContext || !realm) {
      return;
    }
    let rows: any[] = extracted.rows;
    let totalRows = rows.length;
    let rowsJson = JSON.stringify(rows);
    while (rowsJson.length > MAX_ROWS_JSON_BYTES && rows.length > 25) {
      rows = rows.slice(
        0,
        Math.max(
          25,
          Math.floor((rows.length * MAX_ROWS_JSON_BYTES) / rowsJson.length),
        ),
      );
      rowsJson = JSON.stringify(rows);
    }
    let sourceNote =
      rows.length < totalRows
        ? `${opts.sourceNoteBase} — kept first ${rows.length} of ${totalRows} rows (card size limit)`
        : opts.sourceNoteBase;
    if (rows.length < totalRows) {
      this.extractNotice = `${opts.fallbackTitle}: kept first ${rows.length} of ${totalRows} rows (card size limit)`;
    }

    let datasetTitle = extracted.title || opts.fallbackTitle;
    let dataset = new Dataset({
      title: datasetTitle,
      columnsJson: JSON.stringify(extracted.columns ?? []),
      rowsJson,
      sourceNote,
      sourceFileUrl: opts.sourceFileUrl,
    });
    (dataset as any).cardInfo.name = datasetTitle;
    await new SaveCardCommand(commandContext).execute({
      card: dataset,
      realm,
    });

    let suggested = extracted.suggestedChart ?? {};
    let chartTitle = suggested.title ?? extracted.title ?? opts.fallbackTitle;
    let chart = new ChartCard({
      title: chartTitle,
      chartKind: suggested.chartKind ?? 'bar',
      dataset,
      dimension: new DimensionField({
        path: suggested.x,
        bucket: suggested.xBucket ?? 'none',
      }),
      measure: new MeasureField({
        path: suggested.y?.field,
        aggregate: suggested.y?.aggregate ?? 'sum',
      }),
      span: 2,
    });
    (chart as any).cardInfo.name = chartTitle;
    await new SaveCardCommand(commandContext).execute({
      card: chart,
      realm,
    });

    (this.args.model as any).cards = [...this.cards, chart];
  }

  // live-web path: the question goes to a search-grounded model that returns
  // current figures with source URLs; the result lands as a Dataset (linked to
  // its first cited page) plus a ChartCard — no assistant round-trip
  webAsk = restartableTask(async (prompt: string) => {
    let commandContext = this.args.context?.commandContext;
    if (!commandContext || !this.realm) {
      return;
    }
    this.extractError = undefined;
    this.extractNotice = undefined;
    this.extractProgress = '';
    try {
      let extracted = await this.extractWithLlm(
        commandContext,
        [{ type: 'text', text: `${WEB_PROMPT}${prompt}` }],
        WEB_MODEL,
      );
      if (!Array.isArray(extracted.rows) || !extracted.rows.length) {
        throw new Error('the web search returned no usable figures');
      }
      let sources: string[] = Array.isArray(extracted.sources)
        ? extracted.sources.filter((s: any) => typeof s === 'string' && s)
        : [];
      let today = new Date().toISOString().slice(0, 10);
      await this.mintDatasetAndChart(extracted, {
        fallbackTitle: prompt,
        sourceNoteBase: `web-sourced ${today} via ${WEB_MODEL}${
          sources.length ? ` — ${sources.length} source(s)` : ''
        }`,
        sourceFileUrl: sources[0] ?? '',
      });
      this.promptDraft = '';
    } catch (e: any) {
      this.extractError = humanizeError(e);
    }
  });

  askAi = restartableTask(async (prompt: string) => {
    let model = this.args.model;
    let commandContext = this.args.context?.commandContext;
    if (!model?.id || !commandContext) {
      return;
    }
    // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
    let skillCardId = new URL('./Skill/gen-ui-analyst', import.meta.url).href;
    await new UseAiAssistantCommand(commandContext).execute({
      roomId: 'new',
      roomName: `Dashboard: ${model.title || 'Gen UI Analytics'}`,
      openRoom: true,
      llmMode: 'act',
      skillCardIds: [skillCardId],
      attachedCards: [model as CardDef],
      openCardIds: [model.id],
      prompt,
    });
    this.promptDraft = '';
  });

  <template>
    <section
      class='dashboard
        {{if this.isDragging "dragging"}}
        {{unless this.hasLinkedTheme "gu-default-theme"}}'
      data-theme={{this.colorScheme}}
      {{this.shortcuts}}
      {{on 'dragenter' this.onDragEnter}}
      {{on 'dragover' this.onDragOver}}
      {{on 'dragleave' this.onDragLeave}}
      {{on 'drop' this.onDrop}}
    >
      {{#if this.isDragging}}
        <div class='drop-veil'>Drop a screenshot or CSV — I'll chart it</div>
      {{/if}}
      {{#if this.extractDataset.isRunning}}
        <div class='extract-banner'>Reading the table out of your file{{this.extractProgress}}…</div>
      {{/if}}
      {{#if this.webAsk.isRunning}}
        <div class='extract-banner'>Searching the live web for current figures…</div>
      {{/if}}
      {{#if this.extractError}}
        <div class='extract-banner error'>
          <span>{{this.extractError}}</span>
          <button
            class='banner-dismiss'
            type='button'
            aria-label='Dismiss error'
            {{on 'click' this.dismissError}}
          >×</button>
        </div>
      {{/if}}
      {{#if this.extractNotice}}
        <div class='extract-banner notice'>
          <span>{{this.extractNotice}}</span>
          <button
            class='banner-dismiss'
            type='button'
            aria-label='Dismiss notice'
            {{on 'click' this.dismissNotice}}
          >×</button>
        </div>
      {{/if}}
      {{#if this.cards.length}}
        <header class='dashboard-header'>
          <div class='heading'>
            <h1>{{if @model.title @model.title 'Gen UI Analytics'}}</h1>
            <p class='tagline'>Ask for a view — the dashboard builds itself.</p>
          </div>
          <div class='prompt-bar'>
            <BoxelInput
              class='prompt-input'
              @value={{this.promptDraft}}
              placeholder='Ask anything about your data…'
              aria-label='Ask the AI to build a view'
              {{on 'input' this.updateDraft}}
              {{on 'keydown' this.onPromptKeydown}}
            />
            <Button
              class='live-toggle {{if this.useLiveWeb "on"}}'
              @kind='secondary'
              title='Answer from live web search with cited sources'
              aria-pressed='{{this.useLiveWeb}}'
              {{on 'click' this.toggleLiveWeb}}
            >
              Live web
            </Button>
            <Button
              class='prompt-send'
              @kind='primary'
              @disabled={{this.askDisabled}}
              title={{this.askTitle}}
              {{on 'click' (fn this.suggest this.promptDraft)}}
            >
              {{this.askLabel}}
            </Button>
            <button
              type='button'
              class='scheme-toggle'
              aria-label={{if
                (eq this.colorScheme 'dark')
                'Switch to light mode'
                'Switch to dark mode'
              }}
              title={{if
                (eq this.colorScheme 'dark')
                'Switch to light mode'
                'Switch to dark mode'
              }}
              {{on 'click' this.toggleColorScheme}}
            >
              {{#if (eq this.colorScheme 'dark')}}
                <SunIcon width='16' height='16' />
              {{else}}
                <MoonIcon width='16' height='16' />
              {{/if}}
            </button>
          </div>
        </header>

        <div class='canvas-wrap'>
          <div class='gd-history'>
            <button
              type='button'
              class='gd-hist-btn'
              title='Undo (⌘Z)'
              aria-label='Undo'
              disabled={{eq this.undoDepth 0}}
              {{on 'click' this.undo}}
            ><ArrowBackUpIcon width='15' height='15' /></button>
            <span class='gd-hist-div'></span>
            <button
              type='button'
              class='gd-hist-btn'
              title='Redo (⇧⌘Z)'
              aria-label='Redo'
              disabled={{eq this.redoDepth 0}}
              {{on 'click' this.redo}}
            ><ArrowForwardUpIcon width='15' height='15' /></button>
          </div>
          <div class='canvas-scroll'>
            <div class='canvas-board' style={{this.boardStyle}}>
              {{#each this.cards as |card index|}}
                {{! long-press anywhere on the tile lifts it (Figma-style) }}
                {{! template-lint-disable no-pointer-down-event-binding }}
                <article
                  class='tile canvas-tile
                    {{if (eq this.resizingIndex index) "resizing"}}
                    {{if (eq this.movingIndex index) "lifting"}}'
                  style={{this.tileStyleFor card index}}
                  data-test-tile={{index}}
                  {{on 'pointerdown' (fn this.armTilePress card index)}}
                >
                  <div class='tile-toolbar'>
                    {{#if (isChart card)}}
                      <button
                        class='tool'
                        type='button'
                        title='Preview the data behind this chart'
                        {{on 'click' (fn this.toggleDataPreview index)}}
                      >Data</button>
                    {{/if}}
                    <button
                      class='tool'
                      type='button'
                      title='Open in its own stack'
                      {{on 'click' (fn this.openCard card)}}
                    >⤢</button>
                    <button
                      class='tool remove
                        {{if (eq this.confirmRemoveIndex index) "confirming"}}'
                      type='button'
                      aria-label={{if
                        (eq this.confirmRemoveIndex index)
                        'Click again to remove'
                        'Remove from dashboard'
                      }}
                      title={{if
                        (eq this.confirmRemoveIndex index)
                        'Click again to remove'
                        'Remove from dashboard'
                      }}
                      {{on 'click' (fn this.requestRemove index)}}
                    >{{if
                        (eq this.confirmRemoveIndex index)
                        'Remove?'
                        '×'
                      }}</button>
                  </div>
                  {{#if (eq this.dataPreviewIndex index)}}
                    <div class='data-preview'>
                      <div class='data-preview-head'>
                        <strong>{{if
                            card.dataset.title
                            card.dataset.title
                            'Dataset'
                          }}</strong>
                        <span
                          class='data-preview-note'
                        >{{card.dataset.sourceNote}}</span>
                      </div>
                      <div class='data-preview-scroll'>
                        <table>
                          <thead>
                            <tr>
                              {{#each (this.previewColumns card) as |col|}}
                                <th>{{col}}</th>
                              {{/each}}
                            </tr>
                          </thead>
                          <tbody>
                            {{#each (this.previewRows card) as |row|}}
                              <tr>
                                {{#each (this.previewColumns card) as |col|}}
                                  <td>{{this.cell row col}}</td>
                                {{/each}}
                              </tr>
                            {{/each}}
                          </tbody>
                        </table>
                      </div>
                      <div class='data-preview-foot'>
                        <Button
                          class='preview-open'
                          @kind='secondary'
                          {{on 'click' (fn this.openDataset card)}}
                        >Open full dataset ⤢</Button>
                        <Button
                          class='preview-close'
                          @kind='text-only'
                          {{on 'click' (fn this.toggleDataPreview index)}}
                        >Close</Button>
                      </div>
                    </div>
                  {{/if}}
                  <Tile @card={{card}} />
                  {{#each RESIZE_DIRS as |dir|}}
                    {{! a drag interaction must start on pointerdown }}
                    {{! template-lint-disable no-pointer-down-event-binding }}
                    <button
                      class='rz rz-{{dir}}'
                      type='button'
                      aria-label='Resize tile ({{dir}})'
                      {{on 'pointerdown' (fn this.startResize card index dir)}}
                    ></button>
                  {{/each}}
                </article>
              {{/each}}
            </div>
          </div>
        </div>
      {{else}}
        <div class='hero'>
          <h1 class='hero-title'>{{if
              @model.title
              @model.title
              'Gen UI Analytics'
            }}</h1>
          <p class='hero-tagline'>Ask a question in plain English — get the
            chart that answers it.</p>
          <div class='hero-prompt'>
            <BoxelInput
              class='hero-input'
              @value={{this.promptDraft}}
              placeholder='Ask anything about your data…'
              aria-label='Ask the AI to build a view'
              {{on 'input' this.updateDraft}}
              {{on 'keydown' this.onPromptKeydown}}
            />
            <Button
              class='live-toggle hero-live-toggle {{if this.useLiveWeb "on"}}'
              @kind='secondary'
              title='Answer from live web search with cited sources'
              aria-pressed='{{this.useLiveWeb}}'
              {{on 'click' this.toggleLiveWeb}}
            >
              Live web
            </Button>
            <Button
              class='hero-send'
              @kind='primary'
              @disabled={{this.askDisabled}}
              title={{this.askTitle}}
              {{on 'click' (fn this.suggest this.promptDraft)}}
            >
              {{this.askLabel}}
            </Button>
          </div>
          <button
            type='button'
            class='scheme-toggle hero-scheme-toggle'
            aria-label={{if
              (eq this.colorScheme 'dark')
              'Switch to light mode'
              'Switch to dark mode'
            }}
            title={{if
              (eq this.colorScheme 'dark')
              'Switch to light mode'
              'Switch to dark mode'
            }}
            {{on 'click' this.toggleColorScheme}}
          >
            {{#if (eq this.colorScheme 'dark')}}
              <SunIcon width='16' height='16' />
            {{else}}
              <MoonIcon width='16' height='16' />
            {{/if}}
          </button>
          <div class='suggestions'>
            {{#each SUGGESTIONS as |suggestion|}}
              <Button
                class='suggestion'
                @kind='text-only'
                {{on 'click' (fn this.suggest suggestion)}}
              >
                {{suggestion}}
              </Button>
            {{/each}}
          </div>
          <p class='page-hint'>…or drop a screenshot / CSV with data in it</p>
        </div>
      {{/if}}
      {{#if this.cards.length}}
        <p class='page-hint grid-hint'>Ask another question, or drop a
          screenshot / CSV to add more data</p>
      {{/if}}
    </section>
    <style scoped>
      /* ai-image-generator pin pattern (boxel-theming-ui rule 4): dark is
         the identity default; the scheme toggle stamps data-theme and the
         [data-theme='light'] variant below flips the semantic set. A linked
         theme removes the pin, so the toggle is inert there by design. */
      .gu-default-theme {
        --background: #0f1217;
        --foreground: #e8ecf1;
        --card: #171c24;
        --card-foreground: #e8ecf1;
        --primary: #5b8ff9;
        --primary-foreground: #0f1217;
        --secondary: #7ed9a6;
        --secondary-foreground: #0f1217;
        --accent: #f2cf7e;
        --accent-foreground: #0f1217;
        --muted: #1c2330;
        --muted-foreground: #93a0b4;
        --destructive: #c25668;
        --destructive-foreground: #0f1217;
        --border: rgba(255, 255, 255, 0.09);
        --input: rgba(255, 255, 255, 0.09);
        --ring: #5b8ff9;
      }
      .gu-default-theme[data-theme='light'] {
        --background: #f2f5f9;
        --foreground: #1c2733;
        --card: #ffffff;
        --card-foreground: #1c2733;
        --primary: #3b6fe0;
        --primary-foreground: #f5f8ff;
        --secondary: #1a7f4e;
        --secondary-foreground: #f2fbf6;
        --accent: #b3690f;
        --accent-foreground: #fff8ec;
        --muted: #e7ecf2;
        --muted-foreground: #5a6878;
        --destructive: #b3403a;
        --destructive-foreground: #fff5f4;
        --border: rgba(15, 23, 42, 0.12);
        --input: rgba(15, 23, 42, 0.12);
        --ring: #3b6fe0;
        --gd-dot: rgba(15, 23, 42, 0.08);
      }
      .scheme-toggle {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 34px;
        height: 34px;
        flex-shrink: 0;
        border: 1px solid var(--gd-border);
        border-radius: 999px;
        background: transparent;
        color: var(--gd-muted);
        cursor: pointer;
      }
      .scheme-toggle:hover {
        color: var(--gd-accent);
        border-color: var(--gd-accent);
      }

      .dashboard {
        --gd-bg: var(--gen-ui-bg, var(--background, #0f1217));
        --gd-surface: var(--gen-ui-surface, var(--card, #171c24));
        --gd-border: var(
          --gen-ui-border,
          var(--border, rgba(255, 255, 255, 0.08))
        );
        --gd-text: var(--gen-ui-ink, var(--foreground, #e8ecf1));
        --gd-muted: var(--gen-ui-muted, var(--muted-foreground, #93a0b4));
        --gd-accent: var(--gen-ui-accent, var(--primary, #5b8ff9));
        --gd-accent-text: var(
          --gen-ui-accent-fg,
          var(--primary-foreground, #0b1020)
        );
        --gd-radius: var(--gen-ui-radius, var(--radius, 12px));
        --gd-danger: var(--gen-ui-danger, var(--destructive, #c25668));
        --gd-dot: rgba(255, 255, 255, 0.07);
        position: relative;
        height: 100%;
        display: flex;
        flex-direction: column;
        overflow: auto;
        background: var(--gd-bg);
        color: var(--gd-text);
        padding: clamp(16px, 3cqi, 32px);
        container-type: inline-size;
        font-family: var(--font-sans, ui-sans-serif, system-ui, sans-serif);
      }
      /* with a populated wall the section itself never scrolls — the canvas
         viewport does, and the header stays put (Figma-style) */
      .dashboard:has(.canvas-wrap) {
        overflow: hidden;
      }
      .canvas-wrap {
        position: relative;
        flex: 1;
        min-height: 0;
        display: flex;
      }
      .canvas-scroll {
        flex: 1;
        min-width: 0;
        overflow: auto;
        border-radius: var(--gd-radius);
      }
      .dashboard.dragging {
        outline: 2px dashed var(--gd-accent);
        outline-offset: -8px;
      }
      .drop-veil {
        position: absolute;
        inset: 12px;
        z-index: 5;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: var(--gd-radius);
        background: color-mix(
          in srgb,
          var(--gd-accent) 14%,
          rgba(15, 18, 23, 0.85)
        );
        border: 2px dashed var(--gd-accent);
        font-size: 1rem;
        font-weight: 550;
        pointer-events: none;
      }
      .extract-banner {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 10px 14px;
        margin-bottom: 12px;
        border-radius: var(--gd-radius);
        background: var(--gd-surface);
        border: 1px solid var(--gd-border);
        font-size: 0.8125rem;
        color: var(--gd-muted);
        animation: extract-pulse 1.4s ease-in-out infinite;
      }
      .banner-dismiss {
        flex-shrink: 0;
        background: none;
        border: none;
        color: inherit;
        font-size: 1.05rem;
        line-height: 1;
        cursor: pointer;
        padding: 2px 6px;
        border-radius: 6px;
        opacity: 0.7;
      }
      .banner-dismiss:hover {
        opacity: 1;
        background: var(--gd-border);
      }
      .extract-banner.notice {
        animation: none;
        color: #f2cf7e;
        border-color: rgba(242, 207, 126, 0.35);
      }
      .extract-banner.error {
        animation: none;
        color: #ff9a9a;
        border-color: rgba(255, 120, 120, 0.4);
      }
      @keyframes extract-pulse {
        0%,
        100% {
          opacity: 0.6;
        }
        50% {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .extract-banner {
          animation: none;
        }
      }
      .dashboard-header {
        display: flex;
        flex-wrap: wrap;
        gap: 16px;
        align-items: flex-end;
        justify-content: space-between;
        margin-bottom: 20px;
      }
      .heading h1 {
        margin: 0;
        font-size: clamp(1.25rem, 2.5cqi, 1.75rem);
        letter-spacing: -0.01em;
      }
      .tagline {
        margin: 4px 0 0;
        color: var(--gd-muted);
        font-size: 0.8125rem;
      }
      .prompt-bar {
        display: flex;
        gap: 8px;
        flex: 1;
        min-width: 260px;
        max-width: 560px;
      }
      .prompt-input {
        flex: 1;
        background: var(--gd-surface);
        border: 1px solid var(--gd-border);
        border-radius: var(--gd-radius);
        color: var(--gd-text);
        padding: 10px 14px;
        font-size: 0.875rem;
      }
      .prompt-input::placeholder {
        color: var(--gd-muted);
      }
      .prompt-send {
        flex-shrink: 0;
        --boxel-button-primary-background: var(--gd-accent);
        --boxel-button-primary-foreground: var(--gd-accent-text);
        --boxel-button-primary-active-background: var(--gd-accent);
        --boxel-button-padding: 10px 18px;
        --boxel-button-min-height: 0;
        --boxel-button-border-radius: var(--gd-radius);
        --boxel-button-border: none;
        font-weight: 600;
        font-size: 0.875rem;
        white-space: nowrap;
      }
      .prompt-send:disabled {
        --boxel-button-disabled-background: var(--gd-accent);
        --boxel-button-disabled-foreground: var(--gd-accent-text);
        opacity: 0.6;
        pointer-events: auto;
        cursor: not-allowed;
      }
      .live-toggle {
        flex-shrink: 0;
        --boxel-button-secondary-background: transparent;
        --boxel-button-secondary-foreground: var(--gd-muted);
        --boxel-button-secondary-border: var(--gd-border);
        --boxel-button-padding: 8px 14px;
        --boxel-button-min-height: 0;
        --boxel-button-border-radius: 999px;
        font-size: 0.8125rem;
        font-weight: 550;
        white-space: nowrap;
      }
      .live-toggle:hover {
        --boxel-button-secondary-border: var(--gd-accent);
      }
      .live-toggle.on {
        --boxel-button-secondary-foreground: var(--gd-accent);
        --boxel-button-secondary-border: var(--gd-accent);
        --boxel-button-secondary-background: color-mix(
          in srgb,
          var(--gd-accent) 14%,
          transparent
        );
      }
      .hero-scheme-toggle {
        position: absolute;
        top: 18px;
        right: 18px;
      }
      .canvas-board {
        position: relative;
        min-height: 100%;
        border-radius: var(--gd-radius);
        border: 1px dashed var(--gd-border);
        background-image: radial-gradient(
          circle,
          var(--gd-dot) 1px,
          transparent 1px
        );
        background-size: 16px 16px;
      }
      .gd-history {
        position: absolute;
        top: 12px;
        right: 12px;
        z-index: 6;
        display: flex;
        align-items: center;
        gap: 2px;
        padding: 4px;
        border: 1px solid var(--gd-border);
        border-radius: 999px;
        background: color-mix(in srgb, var(--gd-surface) 88%, transparent);
        backdrop-filter: blur(6px);
        box-shadow:
          0 10px 28px rgba(0, 0, 0, 0.45),
          0 2px 6px rgba(0, 0, 0, 0.3);
      }
      .gd-hist-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 32px;
        height: 32px;
        border: none;
        border-radius: 999px;
        background: transparent;
        color: var(--gd-text);
        cursor: pointer;
      }
      .gd-hist-btn:hover:not(:disabled) {
        color: var(--gd-accent);
        background: color-mix(in srgb, var(--gd-accent) 14%, transparent);
      }
      .gd-hist-btn:disabled {
        color: var(--gd-muted);
        opacity: 0.4;
        cursor: default;
      }
      .gd-hist-div {
        width: 1px;
        height: 16px;
        background: var(--gd-border);
      }
      .tile.canvas-tile:hover {
        outline: 1px solid color-mix(in srgb, var(--gd-accent) 55%, transparent);
        outline-offset: 1px;
      }
      .tile.lifting,
      .tile.lifting * {
        cursor: grabbing !important;
      }
      .tile.lifting {
        cursor: grabbing;
        box-shadow: 0 18px 44px rgba(0, 0, 0, 0.55);
        outline: 1px solid var(--gd-accent);
        user-select: none;
      }
      .tile.canvas-tile {
        position: absolute;
        margin: 0;
      }
      .tile-toolbar {
        position: absolute;
        top: 8px;
        right: 8px;
        z-index: 3;
        display: flex;
        align-items: center;
        gap: 4px;
        padding: 3px;
        border-radius: 999px;
        background: color-mix(in srgb, var(--gd-bg) 80%, transparent);
        border: 1px solid var(--gd-border);
        backdrop-filter: blur(6px);
        opacity: 0;
        transition: opacity 0.15s ease;
      }
      .tile:hover .tile-toolbar,
      .tile:focus-within .tile-toolbar {
        opacity: 1;
      }
      .tool {
        background: none;
        border: none;
        color: var(--gd-muted);
        font-size: 0.72rem;
        font-weight: 600;
        line-height: 1;
        cursor: pointer;
        padding: 5px 8px;
        border-radius: 999px;
      }
      .tool:hover {
        background: var(--gd-border);
        color: var(--gd-text);
      }
      .tool.active {
        background: color-mix(in srgb, var(--gd-accent) 22%, transparent);
        color: var(--gd-accent);
      }
      .tool.remove:hover {
        color: #ff9a9a;
      }
      .tool.remove.confirming,
      .tool.remove.confirming:hover {
        background: var(--gd-danger, #c25668);
        border-color: var(--gd-danger, #c25668);
        color: var(--destructive-foreground, #0f1217);
        font-weight: 650;
      }
      /* 8 resize handles: 4 edge strips + 4 corner squares. Invisible hit
         zones; the corners show a dot on tile hover. */
      .rz {
        position: absolute;
        z-index: 3;
        background: none;
        border: none;
        padding: 0;
        touch-action: none;
      }
      .rz-n,
      .rz-s {
        left: 12px;
        right: 12px;
        height: 8px;
        cursor: ns-resize;
      }
      .rz-e,
      .rz-w {
        top: 12px;
        bottom: 12px;
        width: 8px;
        cursor: ew-resize;
      }
      .rz-n {
        top: 0;
      }
      .rz-s {
        bottom: 0;
      }
      .rz-e {
        right: 0;
      }
      .rz-w {
        left: 0;
      }
      .rz-ne,
      .rz-nw,
      .rz-se,
      .rz-sw {
        width: 14px;
        height: 14px;
      }
      .rz-ne {
        top: 0;
        right: 0;
        cursor: nesw-resize;
      }
      .rz-nw {
        top: 0;
        left: 0;
        cursor: nwse-resize;
      }
      .rz-se {
        bottom: 0;
        right: 0;
        cursor: nwse-resize;
      }
      .rz-sw {
        bottom: 0;
        left: 0;
        cursor: nesw-resize;
      }
      .rz-ne::after,
      .rz-nw::after,
      .rz-se::after,
      .rz-sw::after {
        content: '';
        position: absolute;
        inset: 3px;
        border-radius: 3px;
        background: var(--gd-accent);
        opacity: 0;
        transition: opacity 0.15s ease;
      }
      .tile:hover .rz-ne::after,
      .tile:hover .rz-nw::after,
      .tile:hover .rz-se::after,
      .tile:hover .rz-sw::after,
      .tile.resizing .rz::after {
        opacity: 0.7;
      }
      .tile.resizing {
        border-color: var(--gd-accent);
        box-shadow: 0 0 0 1px var(--gd-accent);
        transition: none;
        user-select: none;
      }
      .data-preview {
        position: absolute;
        inset: 8px;
        z-index: 2;
        display: flex;
        flex-direction: column;
        border-radius: calc(var(--gd-radius) - 4px);
        background: color-mix(in srgb, var(--gd-bg) 92%, transparent);
        border: 1px solid var(--gd-border);
        backdrop-filter: blur(4px);
        padding: 12px;
        gap: 8px;
      }
      .data-preview-head {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding-right: 140px;
        font-size: 0.8125rem;
      }
      .data-preview-note {
        color: var(--gd-muted);
        font-size: 0.6875rem;
      }
      .data-preview-scroll {
        flex: 1;
        overflow: auto;
        border-radius: 8px;
        border: 1px solid var(--gd-border);
      }
      .data-preview table {
        border-collapse: collapse;
        width: 100%;
        font-size: 0.75rem;
      }
      .data-preview th,
      .data-preview td {
        text-align: left;
        padding: 5px 10px;
        border-bottom: 1px solid var(--gd-border);
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
      }
      .data-preview th {
        position: sticky;
        top: 0;
        background: var(--gd-surface);
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: var(--gd-muted);
      }
      .data-preview-foot {
        display: flex;
        justify-content: space-between;
        gap: 8px;
      }
      .preview-open,
      .preview-close {
        background: none;
        border: 1px solid var(--gd-border);
        border-radius: 999px;
        color: var(--gd-text);
        font-size: 0.75rem;
        padding: 6px 12px;
        cursor: pointer;
      }
      .preview-open:hover {
        border-color: var(--gd-accent);
        color: var(--gd-accent);
      }
      .preview-close:hover {
        background: var(--gd-border);
      }
      .hero {
        min-height: calc(100% - 32px);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        text-align: center;
        gap: 0;
        padding-bottom: 8vh;
      }
      .hero-title {
        margin: 0 0 8px;
        font-size: clamp(1.75rem, 5cqi, 2.75rem);
        letter-spacing: -0.02em;
        font-weight: 650;
      }
      .hero-tagline {
        margin: 0 0 32px;
        color: var(--gd-muted);
        font-size: 0.9375rem;
      }
      .hero-prompt {
        display: flex;
        align-items: center;
        gap: 10px;
        width: min(720px, 92%);
        max-width: 100%;
        margin-bottom: 26px;
      }
      .hero-prompt > :first-child {
        flex: 1;
        min-width: 0;
      }
      .hero-input {
        flex: 1;
        background: var(--gd-surface);
        border: 1px solid var(--gd-border);
        border-radius: 999px;
        color: var(--gd-text);
        padding: 16px 24px;
        font-size: 1rem;
        box-shadow: 0 8px 28px rgba(0, 0, 0, 0.35);
      }
      .hero-input::placeholder {
        color: var(--gd-muted);
      }
      .hero-input:focus {
        outline: none;
        border-color: var(--gd-accent);
      }
      .hero-send {
        flex-shrink: 0;
        /* re-skin through the component's own knobs — the app defines
           --boxel-button-primary-* globally, so plain background/color
           declarations lose to kind-primary (boxel-theming-ui rule 2) */
        --boxel-button-primary-background: var(--gd-accent);
        --boxel-button-primary-foreground: var(--gd-accent-text);
        --boxel-button-primary-active-background: var(--gd-accent);
        --boxel-button-padding: 16px 28px;
        --boxel-button-min-height: 0;
        --boxel-button-border-radius: 999px;
        --boxel-button-border: none;
        font-weight: 600;
        font-size: 1rem;
        white-space: nowrap;
      }
      .hero-send:disabled {
        --boxel-button-disabled-background: var(--gd-accent);
        --boxel-button-disabled-foreground: var(--gd-accent-text);
        opacity: 0.6;
        pointer-events: auto;
        cursor: not-allowed;
      }
      .page-hint {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 20px;
        margin: 0;
        text-align: center;
        color: var(--gd-muted);
        font-size: 0.8125rem;
        pointer-events: none;
      }
      .grid-hint {
        position: static;
        padding: 20px 0 4px;
      }
      .suggestions {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        justify-content: center;
      }
      .suggestion {
        background: var(--gd-surface);
        color: var(--gd-text);
        border: 1px solid var(--gd-border);
        border-radius: 999px;
        padding: 8px 16px;
        font-size: 0.8125rem;
        cursor: pointer;
      }
      .suggestion:hover {
        border-color: var(--gd-accent);
      }
    </style>
  </template>
}

export class GenUiDashboard extends CardDef {
  static displayName = 'Gen UI Dashboard';
  static icon = LayoutDashboardIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  // any card can live on the wall: ChartCards, CRM records, Datasets…
  @field cards = linksToMany(CardDef);
  // Figma-style free placement — positions live in layoutJson on THIS
  // dashboard, so the same chart can sit differently on different walls
  @field layoutJson = contains(StringField); // {[cardId]: {x,y,w,h}}

  static isolated = Isolated;

  // hand-rolled "Night Wall" fitted: a miniature of the dashboard itself —
  // dark canvas, glyph tiles, real card count in the KPI tile
  static fitted = class Fitted extends Component<typeof GenUiDashboard> {
    get hasLinkedTheme(): boolean {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    get cardCount(): number {
      return this.args.model?.cards?.length ?? 0;
    }
    <template>
      <article class='fit {{unless this.hasLinkedTheme "gu-default-theme"}}'>
        <div class='r-head'>
          <p class='eyebrow'>Gen UI Dashboard</p>
          <h3 class='title'>{{if @model.title @model.title 'My Analytics'}}</h3>
        </div>
        <div class='r-wall'>
          <div class='tile t-kpi'>
            <span class='kpi'>{{this.cardCount}}</span>
            <span class='kpi-l'>cards</span>
          </div>
          <div class='tile t-bars'>
            <div class='bars'>
              <i class='b1'></i><i class='b2'></i><i class='b3'></i><i
                class='b4'
              ></i>
            </div>
          </div>
          <div class='tile t-line'>
            <svg
              viewBox='0 0 60 40'
              preserveAspectRatio='none'
              aria-hidden='true'
            >
              <polyline
                points='3,34 18,24 33,18 48,20 57,8'
                fill='none'
                stroke-width='3'
                stroke-linecap='round'
                stroke-linejoin='round'
                vector-effect='non-scaling-stroke'
              />
            </svg>
          </div>
        </div>
        <div class='r-meta'>
          <span class='count'>{{this.cardCount}} cards on the wall</span>
          <span class='ask'>Ask AI ↗</span>
        </div>
      </article>
      <style scoped>
        .gu-default-theme {
          --background: #0f1217;
          --foreground: #e8ecf1;
          --card: #171c24;
          --card-foreground: #e8ecf1;
          --primary: #5b8ff9;
          --primary-foreground: #0f1217;
          --secondary: #7ed9a6;
          --secondary-foreground: #0f1217;
          --accent: #f2cf7e;
          --accent-foreground: #0f1217;
          --muted: #1c2330;
          --muted-foreground: #93a0b4;
          --destructive: #c25668;
          --destructive-foreground: #0f1217;
          --border: rgba(255, 255, 255, 0.09);
          --input: rgba(255, 255, 255, 0.09);
          --ring: #5b8ff9;
        }
        .fit {
          /* Night Wall palette — same identity as the isolated canvas */
          --gu-bg: var(--gen-ui-bg, var(--background, #0f1217));
          --gu-surface: var(--gen-ui-surface, var(--card, #171c24));
          --gu-border: var(
            --gen-ui-border,
            var(--border, rgba(255, 255, 255, 0.09))
          );
          --gu-text: var(--gen-ui-ink, var(--foreground, #e8ecf1));
          --gu-muted: var(--gen-ui-muted, var(--muted-foreground, #93a0b4));
          --gu-accent: var(--gen-ui-accent, var(--primary, #5b8ff9));
          --gu-green: var(--gen-ui-green, var(--secondary, #7ed9a6));
          --gu-amber: var(--gen-ui-amber, var(--accent, #f2cf7e));

          /* pow() type hierarchy (container-query-fitted-layout.md) */
          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --type-ratio: 1.25;
          --type-base: clamp(
            10px,
            calc(3px + 2.2cqi + 1cqb - 0.6 * var(--ar)),
            18px
          );
          --fit-meta-size: max(8px, calc(var(--type-base) / var(--type-ratio)));
          --fit-eyebrow-size: max(
            7px,
            calc(var(--type-base) / pow(var(--type-ratio), 2))
          );
          --fit-headline-size: max(
            11px,
            calc(var(--type-base) * pow(var(--type-ratio), 1.5))
          );
          --fit-kpi-size: max(
            13px,
            calc(var(--type-base) * pow(var(--type-ratio), 2.5))
          );
          --fit-pad: clamp(6px, calc(2px + 2cqi), 16px);
          --fit-gap: clamp(3px, calc(1px + 1.2cqi), 10px);

          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'wall' 'meta';
          gap: var(--fit-gap);
          padding: var(--fit-pad);
          background:
            radial-gradient(rgba(255, 255, 255, 0.06) 1px, transparent 1px) 0
              0 / 14px 14px,
            var(--gu-bg);
          color: var(--gu-text);
        }
        .r-head,
        .r-wall,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .r-head {
          grid-area: head;
        }
        .eyebrow {
          margin: 0;
          font-size: var(--fit-eyebrow-size);
          font-weight: 700;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: var(--gu-accent);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .title {
          margin: 2px 0 0;
          font-size: var(--fit-headline-size);
          font-weight: 700;
          letter-spacing: -0.015em;
          line-height: 1.15;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }
        .r-wall {
          grid-area: wall;
          display: grid;
          grid-template-columns: 1.2fr 1fr 1fr;
          gap: calc(var(--fit-gap) * 0.8);
        }
        .tile {
          background: var(--gu-surface);
          border: 1px solid var(--gu-border);
          border-radius: 6px;
          padding: calc(var(--fit-pad) * 0.5);
          display: flex;
          flex-direction: column;
          justify-content: flex-end;
          overflow: hidden;
          min-height: 0;
        }
        .kpi {
          font-size: var(--fit-kpi-size);
          font-weight: 750;
          line-height: 1;
          font-variant-numeric: tabular-nums;
        }
        .kpi-l {
          font-size: var(--fit-eyebrow-size);
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--gu-muted);
          margin-top: 2px;
        }
        .bars {
          display: flex;
          align-items: flex-end;
          gap: 3px;
          height: 100%;
        }
        .bars i {
          flex: 1;
          border-radius: 2px;
          background: var(--gu-accent);
        }
        .bars .b1 {
          height: 85%;
        }
        .bars .b2 {
          height: 55%;
          background: var(--gu-green);
        }
        .bars .b3 {
          height: 32%;
        }
        .bars .b4 {
          height: 68%;
          background: var(--gu-amber);
        }
        .t-line polyline {
          stroke: var(--gu-green);
        }
        .t-line svg {
          width: 100%;
          height: 100%;
        }
        .r-meta {
          grid-area: meta;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--fit-gap);
          font-size: var(--fit-meta-size);
          color: var(--gu-muted);
          white-space: nowrap;
        }
        .ask {
          color: var(--gu-accent);
          font-weight: 650;
        }

        /* h40: head only, single line */
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: 1fr;
            grid-template-areas: 'head';
            gap: 0;
          }
          .r-wall,
          .r-meta {
            display: none;
          }
          .r-head {
            display: flex;
            align-items: center;
            gap: var(--fit-gap);
          }
          .eyebrow {
            display: none;
          }
          .title {
            margin: 0;
            -webkit-line-clamp: 1;
          }
        }
        /* h65: head + meta */
        @container fitted-card (50px < height <= 80px) {
          .fit {
            grid-template-rows: minmax(0, 1fr) auto;
            grid-template-areas: 'head' 'meta';
          }
          .r-wall {
            display: none;
          }
          .title {
            -webkit-line-clamp: 1;
          }
          .ask {
            display: none;
          }
        }
        /* h105: stacked, thin wall */
        @container fitted-card (80px < height <= 130px) {
          .title {
            -webkit-line-clamp: 1;
          }
          .kpi-l,
          .ask {
            display: none;
          }
        }
        /* wide strips (h65/h105 at width > 260px): wall becomes a left sidebar */
        @container fitted-card (width > 260px) and (50px < height <= 130px) {
          .fit {
            grid-template-columns: minmax(56px, 18cqw) minmax(0, 1fr);
            grid-template-rows: minmax(0, 1fr) auto;
            grid-template-areas: 'wall head' 'wall meta';
            column-gap: calc(var(--fit-gap) * 1.5);
          }
          .r-wall {
            display: grid;
            grid-template-columns: 1fr 1fr;
          }
          .t-line {
            display: none;
          }
          .kpi-l {
            display: none;
          }
        }
        /* narrow: two tiles only, hide the ask affordance */
        @container fitted-card (width <= 250px) {
          .r-wall {
            grid-template-columns: 1.3fr 1fr;
          }
          .t-line {
            display: none;
          }
          .ask {
            display: none;
          }
        }
        /* tiny width: single line meta only */
        @container fitted-card (width <= 150px) {
          .r-wall {
            grid-template-columns: 1fr;
          }
          .t-bars {
            display: none;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof GenUiDashboard> {
    <template>
      <div class='dash-embedded'>
        <h3><@fields.title /></h3>
        <p>{{if @model.cards.length @model.cards.length 0}} cards</p>
      </div>
      <style scoped>
        .dash-embedded {
          padding: 12px 16px;
        }
        .dash-embedded h3 {
          margin: 0 0 4px;
          font-size: 1rem;
        }
        .dash-embedded p {
          margin: 0;
          font-size: 0.8125rem;
          opacity: 0.6;
        }
      </style>
    </template>
  };
}
