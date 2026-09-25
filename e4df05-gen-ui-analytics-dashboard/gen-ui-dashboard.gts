import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import enumField from '@cardstack/base/enum';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { restartableTask } from 'ember-concurrency';
import { modifier } from 'ember-modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  BoxelInput,
  Button,
  IconButton,
  Pill,
} from '@cardstack/boxel-ui/components';
import { IconX } from '@cardstack/boxel-ui/icons';
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

import { ChartCard } from './chart-card';
import Tile from './components/tile';
import { Dataset, parseRows } from './dataset';
import { DimensionField, MeasureField } from './fields';
import {
  SUGGESTIONS,
  EXTRACT_PROMPT,
  WEB_MODEL,
  WEB_PROMPT,
  MAX_ROWS_JSON_BYTES,
  stripJsonFences,
  humanizeError,
  compressImage,
} from './utils/ingest';
import {
  RESIZE_DIRS,
  MIN_TILE_W,
  MIN_TILE_H,
  isChart,
  snap,
  defaultRect,
  type TileRect,
} from './utils/layout';
import { parseCsv, suggestChart } from './utils/parse-csv';

// ---------------------------------------------------------------------------
// The dashboard is a wall of LINKED CARDS. The AI answers a question by
// CREATING a ChartCard (flat, LLM-friendly fields) and linking it here —
// charts are first-class cards: openable alone, shareable across dashboards,
// and a broken one breaks only its own tile. "New customer" flows link the
// created CRM records directly; any card embeds.
// ---------------------------------------------------------------------------

// The dashboard is an app shell, so it may own a light/dark toggle: it stamps
// data-theme on its root and the linked theme's darkModeVariables take over
// for the whole wall, tiles included. The scheme lives on the card itself
// (below, `colorScheme`) rather than in browser storage — it is this
// instance's own data, so it saves with the card, follows it to any viewer,
// and can never leak into a different dashboard the way a shared storage key
// did. Unset reads as dark (the Night Wall identity's default); "light" is
// the one explicit opt-out a viewer can save. Shared by every format — a
// fitted tile and the isolated view must agree on the same instance's mode.
function resolveColorScheme(
  model:
    | {
        colorScheme?: string | null;
      }
    | null
    | undefined,
): 'light' | 'dark' {
  if ((globalThis as any).__boxelRenderContext) {
    return 'dark';
  }
  return model?.colorScheme === 'light' ? 'light' : 'dark';
}

class Isolated extends Component<typeof GenUiDashboard> {
  get colorScheme(): 'light' | 'dark' {
    return resolveColorScheme(this.args.model);
  }

  get isDark(): boolean {
    return this.colorScheme === 'dark';
  }

  @action toggleColorScheme() {
    if (this.args.model) {
      this.args.model.colorScheme = this.isDark ? 'light' : 'dark';
    }
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

  // the prompt is a form: Enter and the send button both submit it
  @action onPromptSubmit(event: Event) {
    event.preventDefault();
    if (this.promptDraft.trim() && !this.isAsking) {
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

  // ⌘Z / ⇧⌘Z undo this wall's layout changes, but only while the viewer is
  // working in this dashboard: the last pointer press or the focus is inside
  // it, and focus is not in something with its own undo (a field, a
  // contenteditable). Another card in the stack keeps its own ⌘Z.
  shortcuts = modifier((element: HTMLElement) => {
    let engaged = false;
    let onPointerDown = (e: PointerEvent) => {
      engaged = element.contains(e.target as Node);
    };
    let onKey = (e: KeyboardEvent) => {
      let el = document.activeElement as HTMLElement | null;
      if (
        el &&
        (/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) || el.isContentEditable)
      ) {
        return;
      }
      let focusInside = Boolean(
        el && el !== document.body && element.contains(el),
      );
      if (!focusInside && !engaged) {
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
    window.addEventListener('pointerdown', onPointerDown, true);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('pointerdown', onPointerDown, true);
      window.removeEventListener('keydown', onKey);
    };
  });

  // which tile is mid-drag (drives the lifted visual)
  @tracked movingIndex: number | undefined;

  // removing a card is destructive — the x asks once, then removes on the
  // second click; doing nothing for a beat cancels the request
  @tracked confirmRemoveIndex: number | undefined;

  @action requestRemove(index: number, card: any) {
    if (this.confirmRemoveIndex === index) {
      this.confirmRemoveIndex = undefined;
      this.unlinkCard(index, card);
      return;
    }
    this.confirmRemoveIndex = index;
    setTimeout(() => {
      if (this.confirmRemoveIndex === index) {
        this.confirmRemoveIndex = undefined;
      }
    }, 3500);
  }

  // `index` indexes the FILTERED `this.cards` that the template iterates, so it
  // only drives the layout key and the confirm state. The splice has to work off
  // the card's own position in the raw `model.cards`: the two diverge the moment
  // an unresolved link leaves a null in the list, and indexing the raw array by
  // a filtered index would silently remove a different tile.
  @action unlinkCard(index: number, card: any) {
    let removed = card ?? this.cards[index];
    if (!removed) {
      return;
    }
    let key = this.layoutKey(removed, index);
    // outside a drag the geometry lives in storedLayout (persistLayout clears
    // liveLayout), so read both or undo would restore the tile to a default
    // slot on top of another one
    let entry = this.liveLayout?.[key] ?? this.storedLayout[key];
    let restoreAt = (this.args.model?.cards ?? []).indexOf(removed);
    if (restoreAt === -1) {
      return;
    }
    let doRemove = () => {
      let cards = [...(this.args.model?.cards ?? [])];
      let at = cards.indexOf(removed);
      if (at === -1) {
        return;
      }
      cards.splice(at, 1);
      (this.args.model as any).cards = cards;
      this.dataPreviewIndex = undefined;
    };
    doRemove();
    this.confirmRemoveIndex = undefined;
    this.pushUndo(() => {
      let cards = [...(this.args.model?.cards ?? [])];
      cards.splice(Math.min(restoreAt, cards.length), 0, removed);
      (this.args.model as any).cards = cards;
      if (entry) {
        this.restoreEntry(key, entry);
      }
    }, doRemove);
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
  // Canvas layout (Figma-style free placement, always snapped to the grid)
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
    return entry ?? defaultRect(index);
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
      let x = Math.max(0, snap(e.clientX - boardRect.left - offsetX));
      let y = Math.max(0, snap(e.clientY - boardRect.top - offsetY));
      this.liveLayout = { ...this.liveLayout, [key]: { ...base, x, y } };
    };
    // pointercancel (the browser taking a touch over for scrolling) ends the
    // gesture exactly like pointerup; without it the listeners stay bound and
    // the next touch anywhere teleports the tile
    let onUp = () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      window.removeEventListener('pointercancel', onUp);
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
    window.addEventListener('pointercancel', onUp);
  }

  // drag-resize from any edge or corner (Figma-style 8 handles): pixel-based,
  // snapped to the grid, persisted in the dashboard's layoutJson. One save on
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
    const MIN_W = MIN_TILE_W;
    const MIN_H = MIN_TILE_H;
    (event.target as HTMLElement).setPointerCapture?.(event.pointerId);

    let onMove = (e: PointerEvent) => {
      let dx = e.clientX - startX;
      let dy = e.clientY - startY;
      let { x, y, w, h } = base;
      if (dir.includes('e')) {
        w = Math.max(MIN_W, snap(base.w + dx));
      }
      if (dir.includes('w')) {
        let maxX = base.x + base.w - MIN_W;
        x = Math.min(maxX, Math.max(0, snap(base.x + dx)));
        w = base.w + (base.x - x);
      }
      if (dir.includes('s')) {
        h = Math.max(MIN_H, snap(base.h + dy));
      }
      if (dir.includes('n')) {
        let maxY = base.y + base.h - MIN_H;
        y = Math.min(maxY, Math.max(0, snap(base.y + dy)));
        h = base.h + (base.y - y);
      }
      this.liveLayout = { ...this.liveLayout, [key]: { x, y, w, h } };
    };
    let onUp = () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      window.removeEventListener('pointercancel', onUp);
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
    window.addEventListener('pointercancel', onUp);
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

  // Dropped originals are kept in this module's own `sources/` directory, so the
  // write path is derived from `import.meta.url` (the same way the skill lookup
  // below resolves) rather than hardcoded — the listing directory and the realm
  // prefix both change on install.
  sourcePathFor(slug: string, realm: string): string {
    // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
    let dir = new URL('./sources/', import.meta.url).href;
    let base = realm.endsWith('/') ? realm : `${realm}/`;
    let relative = dir.startsWith(base) ? dir.slice(base.length) : 'sources/';
    return `${relative}${slug}`;
  }

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
          path: this.sourcePathFor(slug, realm),
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
    let chartKind = suggested.chartKind ?? 'bar';
    // Nothing in the prompt guarantees the model names an x or a y.field, and
    // a chart minted without them fails validateChartSpec and renders its
    // fix-list over good data. Fall back to the first non-numeric column (or
    // the first column) for x, and to counting rows when no measure is named.
    let columns: { name: string; type?: string }[] = Array.isArray(
      extracted.columns,
    )
      ? extracted.columns
      : [];
    let fallbackX =
      columns.find((c) => c.type !== 'number')?.name ?? columns[0]?.name;
    let measurePath: string | undefined = suggested.y?.field;
    let chart = new ChartCard({
      title: chartTitle,
      chartKind,
      dataset,
      dimension: new DimensionField({
        path: suggested.x ?? (chartKind === 'kpi' ? undefined : fallbackX),
        bucket: suggested.xBucket ?? 'none',
      }),
      measure: new MeasureField({
        path: measurePath,
        aggregate: measurePath ? (suggested.y?.aggregate ?? 'sum') : 'count',
      }),
      span: 2,
    });
    (chart as any).cardInfo.name = chartTitle;
    await new SaveCardCommand(commandContext).execute({
      card: chart,
      realm,
    });

    // append to the RAW list, not the filtered `this.cards`: writing the
    // filtered array back would drop any unresolved links the wall still holds
    (this.args.model as any).cards = [...(this.args.model?.cards ?? []), chart];
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
    <main
      class='dashboard {{if this.isDragging "dragging"}}'
      data-theme={{this.colorScheme}}
      aria-label={{if @model.title @model.title 'Gen UI Analytics'}}
      {{this.shortcuts}}
      {{on 'dragenter' this.onDragEnter}}
      {{on 'dragover' this.onDragOver}}
      {{on 'dragleave' this.onDragLeave}}
      {{on 'drop' this.onDrop}}
    >
      {{#if this.isDragging}}
        <div class='drop-veil'>Drop a screenshot or CSV — I'll chart it</div>
      {{/if}}
      <div class='banners' aria-live='polite'>
        {{#if this.extractDataset.isRunning}}
          <p class='extract-banner working'>Reading the table out of your file{{this.extractProgress}}…</p>
        {{/if}}
        {{#if this.webAsk.isRunning}}
          <p class='extract-banner working'>Searching the live web for current
            figures…</p>
        {{/if}}
        {{#if this.extractError}}
          <div class='extract-banner error' role='alert'>
            <span>{{this.extractError}}</span>
            <IconButton
              class='banner-dismiss'
              @icon={{IconX}}
              @width='12'
              @height='12'
              @size='extra-small'
              aria-label='Dismiss error'
              {{on 'click' this.dismissError}}
            />
          </div>
        {{/if}}
        {{#if this.extractNotice}}
          <div class='extract-banner notice'>
            <span>{{this.extractNotice}}</span>
            <IconButton
              class='banner-dismiss'
              @icon={{IconX}}
              @width='12'
              @height='12'
              @size='extra-small'
              aria-label='Dismiss notice'
              {{on 'click' this.dismissNotice}}
            />
          </div>
        {{/if}}
      </div>
      {{#if this.cards.length}}
        <header class='dashboard-header'>
          <div class='heading'>
            <h1>{{if @model.title @model.title 'Gen UI Analytics'}}</h1>
            <p class='tagline'>Ask for a view — the dashboard builds itself.</p>
          </div>
          <form class='prompt-bar' {{on 'submit' this.onPromptSubmit}}>
            <BoxelInput
              class='prompt-input'
              @value={{this.promptDraft}}
              placeholder='Ask anything about your data…'
              aria-label='Ask the AI to build a view'
              {{on 'input' this.updateDraft}}
            />
            <Button
              class='live-toggle'
              @kind={{if this.useLiveWeb 'secondary' 'muted'}}
              @size='small'
              title='Answer from live web search with cited sources'
              aria-pressed='{{this.useLiveWeb}}'
              {{on 'click' this.toggleLiveWeb}}
            >
              Live web
            </Button>
            <Button
              class='prompt-send'
              type='submit'
              @kind='primary'
              @size='small'
              @disabled={{this.askDisabled}}
              title={{this.askTitle}}
            >
              {{this.askLabel}}
            </Button>
            <IconButton
              class='scheme-toggle'
              @icon={{if this.isDark SunIcon MoonIcon}}
              @width='16'
              @height='16'
              @round={{true}}
              aria-label={{if
                this.isDark
                'Switch to light mode'
                'Switch to dark mode'
              }}
              title={{if
                this.isDark
                'Switch to light mode'
                'Switch to dark mode'
              }}
              {{on 'click' this.toggleColorScheme}}
            />
          </form>
        </header>

        <div class='canvas-wrap'>
          <div class='gd-history' role='toolbar' aria-label='Layout history'>
            <IconButton
              class='gd-hist-btn'
              @icon={{ArrowBackUpIcon}}
              @width='15'
              @height='15'
              @round={{true}}
              @disabled={{eq this.undoDepth 0}}
              title='Undo (⌘Z)'
              aria-label='Undo'
              {{on 'click' this.undo}}
            />
            <span class='gd-hist-div' aria-hidden='true'></span>
            <IconButton
              class='gd-hist-btn'
              @icon={{ArrowForwardUpIcon}}
              @width='15'
              @height='15'
              @round={{true}}
              @disabled={{eq this.redoDepth 0}}
              title='Redo (⇧⌘Z)'
              aria-label='Redo'
              {{on 'click' this.redo}}
            />
          </div>
          <div class='canvas-scroll'>
            <ul class='canvas-board' style={{this.boardStyle}}>
              {{#each this.cards as |card index|}}
                {{! long-press anywhere on the tile lifts it (Figma-style) }}
                {{! template-lint-disable no-pointer-down-event-binding }}
                <li
                  class='tile
                    {{if (eq this.resizingIndex index) "resizing"}}
                    {{if (eq this.movingIndex index) "lifting"}}'
                  style={{this.tileStyleFor card index}}
                  data-test-tile={{index}}
                  {{on 'pointerdown' (fn this.armTilePress card index)}}
                >
                  <div
                    class='tile-toolbar'
                    role='toolbar'
                    aria-label='Tile actions'
                  >
                    {{#if (isChart card)}}
                      <Button
                        class='tool'
                        @kind='text-only'
                        @size='extra-small'
                        aria-pressed={{if
                          (eq this.dataPreviewIndex index)
                          'true'
                          'false'
                        }}
                        title='Preview the data behind this chart'
                        {{on 'click' (fn this.toggleDataPreview index)}}
                      >Data</Button>
                    {{/if}}
                    <Button
                      class='tool'
                      @kind='text-only'
                      @size='extra-small'
                      title='Open in its own stack'
                      aria-label='Open in its own stack'
                      {{on 'click' (fn this.openCard card)}}
                    >⤢</Button>
                    <Button
                      class='tool remove'
                      @kind={{if
                        (eq this.confirmRemoveIndex index)
                        'destructive'
                        'text-only'
                      }}
                      @size='extra-small'
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
                      {{on 'click' (fn this.requestRemove index card)}}
                    >{{if
                        (eq this.confirmRemoveIndex index)
                        'Remove?'
                        '×'
                      }}</Button>
                  </div>
                  {{#if (eq this.dataPreviewIndex index)}}
                    <section
                      class='data-preview'
                      aria-label='Data behind this chart'
                    >
                      <div class='data-preview-head'>
                        <h2>{{if
                            card.dataset.title
                            card.dataset.title
                            'Dataset'
                          }}</h2>
                        <p
                          class='data-preview-note'
                        >{{card.dataset.sourceNote}}</p>
                      </div>
                      <div class='data-preview-scroll'>
                        <table>
                          <thead>
                            <tr>
                              {{#each (this.previewColumns card) as |col|}}
                                <th scope='col'>{{col}}</th>
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
                          @kind='secondary'
                          @size='extra-small'
                          {{on 'click' (fn this.openDataset card)}}
                        >Open full dataset ⤢</Button>
                        <Button
                          @kind='text-only'
                          @size='extra-small'
                          {{on 'click' (fn this.toggleDataPreview index)}}
                        >Close</Button>
                      </div>
                    </section>
                  {{/if}}
                  <Tile @card={{card}} />
                  {{#each RESIZE_DIRS as |dir|}}
                    {{! Resize handles stay native buttons: they are invisible
                        edge/corner hit zones that start a drag on pointerdown,
                        not controls BoxelUI has a component for. }}
                    {{! template-lint-disable no-pointer-down-event-binding }}
                    <button
                      class='rz rz-{{dir}}'
                      type='button'
                      aria-label='Resize tile ({{dir}})'
                      {{on 'pointerdown' (fn this.startResize card index dir)}}
                    ></button>
                  {{/each}}
                </li>
              {{/each}}
            </ul>
          </div>
        </div>
        <p class='page-hint grid-hint'>Ask another question, or drop a
          screenshot / CSV to add more data</p>
      {{else}}
        <div class='hero'>
          <IconButton
            class='scheme-toggle hero-scheme-toggle'
            @icon={{if this.isDark SunIcon MoonIcon}}
            @width='16'
            @height='16'
            @round={{true}}
            aria-label={{if
              this.isDark
              'Switch to light mode'
              'Switch to dark mode'
            }}
            title={{if
              this.isDark
              'Switch to light mode'
              'Switch to dark mode'
            }}
            {{on 'click' this.toggleColorScheme}}
          />
          <h1 class='hero-title'>{{if
              @model.title
              @model.title
              'Gen UI Analytics'
            }}</h1>
          <p class='hero-tagline'>Ask a question in plain English — get the
            chart that answers it.</p>
          <form class='hero-prompt' {{on 'submit' this.onPromptSubmit}}>
            <BoxelInput
              class='hero-input'
              @value={{this.promptDraft}}
              placeholder='Ask anything about your data…'
              aria-label='Ask the AI to build a view'
              {{on 'input' this.updateDraft}}
            />
            <Button
              class='live-toggle'
              @kind={{if this.useLiveWeb 'secondary' 'muted'}}
              title='Answer from live web search with cited sources'
              aria-pressed='{{this.useLiveWeb}}'
              {{on 'click' this.toggleLiveWeb}}
            >
              Live web
            </Button>
            <Button
              class='hero-send'
              type='submit'
              @kind='primary'
              @disabled={{this.askDisabled}}
              title={{this.askTitle}}
            >
              {{this.askLabel}}
            </Button>
          </form>
          <ul class='suggestions' aria-label='Example questions'>
            {{#each SUGGESTIONS as |suggestion|}}
              <li>
                <Pill
                  @kind='button'
                  @variant='muted'
                  class='suggestion'
                  {{on 'click' (fn this.suggest suggestion)}}
                >
                  {{suggestion}}
                </Pill>
              </li>
            {{/each}}
          </ul>
          <p class='page-hint'>…or drop a screenshot / CSV with data in it</p>
        </div>
      {{/if}}
    </main>
    <style scoped>
      /* The wall reads only contract tokens: its colours come from the linked
         theme (Night Wall), light or dark per the data-theme on the root. */
      .dashboard {
        position: relative;
        height: 100%;
        display: flex;
        flex-direction: column;
        overflow: auto;
        background-color: var(--canvas);
        color: var(--foreground);
        padding: clamp(1rem, 3cqi, 2rem);
        container-type: inline-size;
      }
      /* with a populated wall the section itself never scrolls — the canvas
         viewport does, and the header stays put (Figma-style) */
      .dashboard:has(.canvas-wrap) {
        overflow: hidden;
      }
      .dashboard.dragging {
        outline: 2px dashed var(--ring);
        outline-offset: -0.5rem;
      }
      .drop-veil {
        position: absolute;
        inset: var(--boxel-sp-sm);
        z-index: 5;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: var(--boxel-border-radius-lg);
        background-color: var(--overlay);
        color: var(--tooltip-foreground);
        border: 2px dashed var(--ring);
        font-weight: 550;
        pointer-events: none;
      }
      .banners:empty {
        display: none;
      }
      .extract-banner {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        margin: 0 0 var(--boxel-sp-sm);
        border-radius: var(--boxel-border-radius);
        background-color: var(--card);
        color: var(--muted-foreground);
        border: 1px solid var(--border);
        font-size: var(--boxel-font-size-sm);
      }
      .extract-banner.working {
        animation: extract-pulse 1.4s ease-in-out infinite;
      }
      .extract-banner.notice {
        color: var(--warning-ink);
        border-color: color-mix(in oklch, var(--warning) 35%, transparent);
      }
      .extract-banner.error {
        color: var(--destructive-ink);
        border-color: color-mix(in oklch, var(--destructive) 40%, transparent);
      }
      .banner-dismiss {
        flex-shrink: 0;
        --boxel-icon-button-color: currentColor;
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
        .extract-banner.working {
          animation: none;
        }
      }
      .dashboard-header {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp);
        align-items: flex-end;
        justify-content: space-between;
        margin-bottom: var(--boxel-sp-lg);
      }
      .heading h1 {
        margin: 0;
        font-size: clamp(1.25rem, 2.5cqi, 1.75rem);
        letter-spacing: -0.01em;
      }
      .tagline {
        margin: var(--boxel-sp-4xs) 0 0;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .prompt-bar {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex: 1;
        min-width: 16.25rem;
        max-width: 35rem;
        margin: 0;
      }
      .prompt-input {
        flex: 1;
      }
      .prompt-send,
      .live-toggle {
        flex-shrink: 0;
        white-space: nowrap;
      }
      .scheme-toggle {
        flex-shrink: 0;
        border: 1px solid var(--border);
        --boxel-icon-button-width: 2.125rem;
        --boxel-icon-button-height: 2.125rem;
        --boxel-icon-button-color: var(--muted-foreground);
      }
      .scheme-toggle:hover {
        --boxel-icon-button-color: var(--foreground);
        border-color: var(--ring);
      }
      .hero-scheme-toggle {
        position: absolute;
        top: var(--boxel-sp);
        right: var(--boxel-sp);
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
        border-radius: var(--boxel-border-radius-lg);
      }
      .canvas-board {
        position: relative;
        min-height: 100%;
        margin: 0;
        padding: 0;
        list-style: none;
        border-radius: var(--boxel-border-radius-lg);
        border: 1px dashed var(--border);
        background-color: var(--inset);
        /* the 16px dot grid the tiles snap to; the grid is layout geometry,
           so it stays in px with the tile rects */
        background-image: radial-gradient(
          circle,
          var(--border-strong) 1px,
          transparent 1px
        );
        background-size: 16px 16px;
      }
      .gd-history {
        position: absolute;
        top: var(--boxel-sp-sm);
        right: var(--boxel-sp-sm);
        z-index: 6;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-6xs);
        padding: var(--boxel-sp-5xs);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-2xl);
        background-color: var(--popover);
        color: var(--popover-foreground);
        box-shadow: var(--shadow-lg);
      }
      .gd-hist-btn {
        --boxel-icon-button-width: 2rem;
        --boxel-icon-button-height: 2rem;
        --boxel-icon-button-color: var(--popover-foreground);
      }
      .gd-hist-btn:hover:not(:disabled) {
        background-color: var(--hover);
      }
      .gd-hist-btn:disabled {
        --boxel-icon-button-color: var(--muted-foreground);
        opacity: 0.4;
      }
      .gd-hist-div {
        width: 1px;
        height: 1rem;
        background-color: var(--border);
      }
      .tile {
        position: absolute;
        margin: 0;
        overflow: hidden;
        border-radius: var(--boxel-border-radius-lg);
        border: 1px solid var(--border);
        background-color: var(--card);
        color: var(--card-foreground);
        box-shadow: var(--shadow-sm);
      }
      .tile:hover {
        outline: 1px solid var(--ring);
        outline-offset: 1px;
      }
      .tile.lifting,
      .tile.lifting * {
        cursor: grabbing !important;
      }
      .tile.lifting {
        box-shadow: var(--shadow-xl);
        outline: 1px solid var(--ring);
        user-select: none;
        /* while lifted, the pointer belongs to the drag, not page scroll */
        touch-action: none;
      }
      .tile-toolbar {
        position: absolute;
        top: var(--boxel-sp-xs);
        right: var(--boxel-sp-xs);
        z-index: 3;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp-6xs);
        border-radius: var(--boxel-border-radius-2xl);
        background-color: var(--popover);
        color: var(--popover-foreground);
        border: 1px solid var(--border);
        opacity: 0;
        transition: opacity 0.15s ease;
      }
      .tile:hover .tile-toolbar,
      .tile:focus-within .tile-toolbar {
        opacity: 1;
      }
      .tool {
        --boxel-button-min-width: 0;
        --boxel-button-min-height: 1.5rem;
        --boxel-button-padding: 0 var(--boxel-sp-xs);
        --boxel-button-border-radius: var(--boxel-border-radius-2xl);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      /* 8 resize handles: 4 edge strips + 4 corner squares. Invisible hit
         zones; the corners show a dot on tile hover. */
      .rz {
        position: absolute;
        z-index: 3;
        background-color: transparent;
        border: none;
        padding: 0;
        touch-action: none;
      }
      .rz-n,
      .rz-s {
        left: var(--boxel-sp-sm);
        right: var(--boxel-sp-sm);
        height: 0.5rem;
        cursor: ns-resize;
      }
      .rz-e,
      .rz-w {
        top: var(--boxel-sp-sm);
        bottom: var(--boxel-sp-sm);
        width: 0.5rem;
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
        width: 0.875rem;
        height: 0.875rem;
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
        inset: var(--boxel-sp-6xs);
        border-radius: var(--boxel-border-radius-2xs);
        background-color: var(--primary);
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
        border-color: var(--ring);
        box-shadow: 0 0 0 1px var(--ring);
        transition: none;
        user-select: none;
      }
      .data-preview {
        position: absolute;
        inset: var(--boxel-sp-xs);
        z-index: 2;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm);
        border-radius: var(--boxel-border-radius);
        background-color: var(--popover);
        color: var(--popover-foreground);
        border: 1px solid var(--border);
        box-shadow: var(--shadow-md);
      }
      .data-preview-head {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-6xs);
        padding-right: 8.75rem;
      }
      .data-preview-head h2 {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .data-preview-note {
        margin: 0;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-2xs);
      }
      .data-preview-scroll {
        flex: 1;
        overflow: auto;
        border-radius: var(--boxel-border-radius-sm);
        border: 1px solid var(--border);
      }
      .data-preview table {
        border-collapse: collapse;
        width: 100%;
        font-size: var(--boxel-font-size-xs);
      }
      .data-preview th,
      .data-preview td {
        text-align: left;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
      }
      .data-preview th {
        position: sticky;
        top: 0;
        background-color: var(--muted);
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-2xs);
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      .data-preview-foot {
        display: flex;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      .hero {
        position: relative;
        min-height: calc(100% - 2rem);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        text-align: center;
        padding-bottom: 8vh;
      }
      .hero-title {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: clamp(1.75rem, 5cqi, 2.75rem);
        letter-spacing: -0.02em;
        font-weight: 650;
      }
      .hero-tagline {
        margin: 0 0 var(--boxel-sp-xl);
        color: var(--muted-foreground);
      }
      .hero-prompt {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        width: min(45rem, 92%);
        max-width: 100%;
        margin: 0 0 var(--boxel-sp-xl);
      }
      .hero-input {
        flex: 1;
        min-width: 0;
        --boxel-input-height: 3.25rem;
        --boxel-form-control-border-radius: var(--boxel-border-radius-2xl);
        box-shadow: var(--shadow-md);
      }
      .hero-send {
        flex-shrink: 0;
        white-space: nowrap;
      }
      .page-hint {
        position: absolute;
        left: 0;
        right: 0;
        bottom: var(--boxel-sp-lg);
        margin: 0;
        text-align: center;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
        pointer-events: none;
      }
      .grid-hint {
        position: static;
        padding: var(--boxel-sp-lg) 0 var(--boxel-sp-5xs);
      }
      .suggestions {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
        justify-content: center;
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .suggestion {
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}

const ColorSchemeField = enumField(StringField, {
  options: ['light', 'dark'],
  displayName: 'Color Scheme',
});

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
  // This instance's own light/dark choice — unset reads as dark (see
  // Isolated.colorScheme below). Per-instance by construction: it is a field
  // on the card, not a shared key, so two dashboards can never collide.
  @field colorScheme = contains(ColorSchemeField);

  static isolated = Isolated;

  // "Night Wall" fitted: a miniature of the dashboard itself — dotted
  // canvas, glyph tiles, real card count in the KPI tile
  static fitted = class Fitted extends Component<typeof GenUiDashboard> {
    get cardCount(): number {
      return this.args.model?.cards?.length ?? 0;
    }
    get colorScheme(): 'light' | 'dark' {
      return resolveColorScheme(this.args.model);
    }
    <template>
      <article class='fit' data-theme={{this.colorScheme}}>
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
        .fit {
          /* pow() type hierarchy (container-query-fitted-layout.md) */
          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --type-ratio: 1.25;
          --type-base: clamp(
            0.625rem,
            calc(0.1875rem + 2.2cqi + 1cqb - 0.6 * var(--ar)),
            1.125rem
          );
          --fit-meta-size: max(
            0.5rem,
            calc(var(--type-base) / var(--type-ratio))
          );
          --fit-eyebrow-size: max(
            0.4375rem,
            calc(var(--type-base) / pow(var(--type-ratio), 2))
          );
          --fit-headline-size: max(
            0.6875rem,
            calc(var(--type-base) * pow(var(--type-ratio), 1.5))
          );
          --fit-kpi-size: max(
            0.8125rem,
            calc(var(--type-base) * pow(var(--type-ratio), 2.5))
          );
          --fit-pad: clamp(0.375rem, calc(0.125rem + 2cqi), 1rem);
          --fit-gap: clamp(0.1875rem, calc(0.0625rem + 1.2cqi), 0.625rem);

          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'wall' 'meta';
          gap: var(--fit-gap);
          padding: var(--fit-pad);
          background-color: var(--canvas);
          color: var(--foreground);
          background-image: radial-gradient(var(--border) 1px, transparent 1px);
          background-size: 0.875rem 0.875rem;
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
          color: var(--primary-ink);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .title {
          margin: var(--boxel-sp-6xs) 0 0;
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
          background-color: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-sm);
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
          color: var(--muted-foreground);
          margin-top: var(--boxel-sp-6xs);
        }
        .bars {
          display: flex;
          align-items: flex-end;
          gap: var(--boxel-sp-6xs);
          height: 100%;
        }
        .bars i {
          flex: 1;
          border-radius: var(--boxel-border-radius-2xs);
          background-color: var(--chart-1);
        }
        .bars .b1 {
          height: 85%;
        }
        .bars .b2 {
          height: 55%;
          background-color: var(--chart-2);
        }
        .bars .b3 {
          height: 32%;
        }
        .bars .b4 {
          height: 68%;
          background-color: var(--chart-3);
        }
        .t-line polyline {
          stroke: var(--chart-2);
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
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .ask {
          color: var(--primary-ink);
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
            grid-template-columns: minmax(3.5rem, 18cqw) minmax(0, 1fr);
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
          padding: var(--boxel-sp-sm) var(--boxel-sp);
        }
        .dash-embedded h3 {
          margin: 0 0 var(--boxel-sp-5xs);
        }
        .dash-embedded p {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
