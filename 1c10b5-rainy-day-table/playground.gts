// The Playground: the box tipped out on the table with the rules switched
// off. Drag parts out of the tray, draw areas, stick notes, paste images and
// draw gesture arrows ("deal", "bet"), then ask the AI assistant to make the
// game. The sketch is saved as plain data in table units (100 wide, 62.5
// tall), so areas map straight onto a Game's layout zones.

import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import ShapesIcon from '@cardstack/boxel-icons/puzzle';
import UseAiAssistantTool from '@cardstack/boxel-host/commands/ai-assistant';
import WriteBinaryFileTool from '@cardstack/boxel-host/commands/write-binary-file';
import { GameJsonField } from './fields';
import { Game, startMatch } from './game';
import type { CompDef, Kind } from './engine';
import { Part } from './parts';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;
const W = 100;
const H = 62.5;

export type SketchItem =
  | {
      id: string;
      type: 'part';
      kind: Kind;
      label?: string;
      colour?: string;
      count?: number;
      image?: string;
      x: number;
      y: number;
      w: number;
    }
  | {
      id: string;
      type: 'note';
      text: string;
      x: number;
      y: number;
      w: number;
      h: number;
    }
  | {
      id: string;
      type: 'area';
      label?: string;
      zoneKind?: string;
      x: number;
      y: number;
      w: number;
      h: number;
    }
  | {
      id: string;
      type: 'image';
      url: string;
      caption?: string;
      file?: boolean;
      x: number;
      y: number;
      w: number;
      h: number;
    }
  | { id: string; type: 'link'; from: string; to: string; verb?: string };

type Box = Exclude<SketchItem, { type: 'link' }>;

const TRAY: {
  kind: Kind;
  label: string;
  w: number;
  def: CompDef;
  colour?: string;
}[] = [
  {
    kind: 'card',
    label: 'Card',
    w: 6.5,
    def: { id: 'tc', kind: 'card', rank: 'A', suit: 'S', look: { depth: 2 } },
  },
  {
    kind: 'die',
    label: 'Die',
    w: 5,
    def: { id: 'td', kind: 'die', look: { depth: 3 } },
  },
  {
    kind: 'chip',
    label: 'Chip',
    w: 5.5,
    def: { id: 'tch', kind: 'chip', value: 5, look: { fill: '#a8402f' } },
  },
  {
    kind: 'coin',
    label: 'Coin',
    w: 5.5,
    def: { id: 'tco', kind: 'coin', look: { fill: '#c9a24a' } },
  },
  {
    kind: 'token',
    label: 'Token',
    w: 4.5,
    def: { id: 'tt', kind: 'token', look: { shape: 'meeple', depth: 3 } },
    colour: '#c8553d',
  },
  {
    kind: 'piece',
    label: 'Piece',
    w: 4.5,
    def: {
      id: 'tp',
      kind: 'piece',
      rank: 'N',
      look: { fill: '#f4ead7', depth: 3 },
    },
  },
  {
    kind: 'tile',
    label: 'Tile',
    w: 5,
    def: {
      id: 'tti',
      kind: 'tile',
      faces: [{ label: 'A' }],
      look: { fill: '#efe2c6', depth: 2 },
    },
  },
  {
    kind: 'board',
    label: 'Board',
    w: 16,
    def: { id: 'tb', kind: 'board', look: { fill: '#e9d3ad' } },
  },
];
const ZONE_KINDS = [
  { id: 'stack', label: 'Pile' },
  { id: 'spread', label: 'Row (a hand)' },
  { id: 'grid', label: 'Grid (a board)' },
  { id: 'track', label: 'Track (a path)' },
  { id: 'pot', label: 'Loose area' },
];
const SWATCHES = [
  '#c8553d',
  '#e3a33b',
  '#5f8f4e',
  '#3f6f9f',
  '#7a5aa0',
  '#2b2420',
  '#f4ead7',
  '#8c2f39',
];
const VERBS = [
  'deal',
  'draw',
  'play',
  'discard',
  'bet',
  'move',
  'roll',
  'take',
  'pass',
];

const uid = () => Math.random().toString(36).slice(2, 8);
const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));

function partDef(it: Extract<SketchItem, { type: 'part' }>): CompDef {
  let base = TRAY.find((t) => t.kind === it.kind)?.def ?? {
    id: 'x',
    kind: it.kind,
  };
  let look = { ...(base.look ?? {}) } as any;
  if (it.colour && it.kind !== 'token') look.fill = it.colour;
  if (it.image) look.imageUrl = it.image;
  let d: CompDef = { ...base, id: it.id, name: it.label, look };
  if (it.kind === 'card' && it.label && it.label.length <= 3)
    d = { ...d, rank: it.label, suit: '' };
  if (it.kind === 'tile')
    d = { ...d, faces: [{ label: (it.label ?? '').slice(0, 2) }] };
  return d;
}

// A Game laid out as a sketch: its areas, one part per kind of definition,
// its rules as a note, and its gestures as arrows.
export function sketchFromGame(g: Game): SketchItem[] {
  let data = g.toData();
  let aspect = data.layout.aspect ?? 1.6;
  let sy = H / (100 / aspect);
  let items: SketchItem[] = [];
  let areaIds = new Map<string, string>();
  for (let z of data.layout.zones) {
    if (z.hidden || z.x === undefined) continue;
    let id = `a-${uid()}`;
    areaIds.set(z.id, id);
    items.push({
      id,
      type: 'area',
      label: z.label || z.id,
      zoneKind: z.kind,
      x: z.x!,
      y: z.y! * sy,
      w: z.w!,
      h: (z.h ?? 10) * sy,
    });
  }
  let groups = new Map<
    string,
    { def: CompDef; count: number; kinds: number }
  >();
  for (let d of data.components) {
    let key = d.kind === 'card' || d.kind === 'piece' ? d.kind : d.id;
    let gr = groups.get(key) ?? { def: d, count: 0, kinds: 0 };
    gr.count += d.quantity ?? 1;
    gr.kinds++;
    groups.set(key, gr);
  }
  let col = 0;
  for (let gr of groups.values()) {
    if (gr.def.kind === 'board') continue;
    let zone = data.layout.zones.find(
      (z) => z.id === gr.def.startZone && !z.hidden && z.x !== undefined,
    );
    let x = zone ? zone.x! + 1 : 2 + col * 8;
    let y = zone ? zone.y! * sy + 2 : H - 9;
    if (!zone) col++;
    let label =
      gr.kinds > 1 ? `${gr.kinds} kinds` : (gr.def.name ?? gr.def.kind);
    items.push({
      id: `p-${uid()}`,
      type: 'part',
      kind: gr.def.kind,
      label,
      count: gr.count,
      colour: gr.def.look?.fill,
      x,
      y,
      w: TRAY.find((t) => t.kind === gr.def.kind)?.w ?? 5,
    });
  }
  if (g.rulesText) {
    // put the rules where they cover the fewest areas
    let boxes = items.filter(
      (i): i is Box => i.type === 'area' || i.type === 'part',
    );
    let spots = [
      { x: 78, y: 2 },
      { x: 2, y: 2 },
      { x: 78, y: 38 },
      { x: 2, y: 38 },
      { x: 40, y: 40 },
    ];
    let cover = (sx: number, sy: number) =>
      boxes.reduce((n, b) => {
        let bh = 'h' in b ? b.h : b.w * 1.4;
        let ox = Math.max(0, Math.min(sx + 20, b.x + b.w) - Math.max(sx, b.x));
        let oy = Math.max(0, Math.min(sy + 22, b.y + bh) - Math.max(sy, b.y));
        return n + ox * oy;
      }, 0);
    let best = spots.sort((a, b) => cover(a.x, a.y) - cover(b.x, b.y))[0];
    items.push({
      id: `n-${uid()}`,
      type: 'note',
      text: g.rulesText.replace(/[*_`]/g, '').slice(0, 400),
      x: best.x,
      y: best.y,
      w: 20,
      h: 22,
    });
  }
  for (let a of data.ruleset.actions ?? []) {
    let gst = a.gesture ?? (a.clickZone ? { click: a.clickZone } : undefined);
    if (gst?.click && areaIds.has(gst.click))
      items.push({
        id: `l-${uid()}`,
        type: 'link',
        from: areaIds.get(gst.click)!,
        to: areaIds.get(gst.click)!,
        verb: a.id,
      });
    let d = gst?.drag;
    if (d?.from && areaIds.has(d.from) && areaIds.has(d.to))
      items.push({
        id: `l-${uid()}`,
        type: 'link',
        from: areaIds.get(d.from)!,
        to: areaIds.get(d.to)!,
        verb: a.id,
      });
    let chip = items.find(
      (i) => i.type === 'part' && (i.kind === 'chip' || i.kind === 'coin'),
    );
    if (
      d?.chips &&
      chip &&
      areaIds.has(d.to) &&
      !items.some(
        (i) => i.type === 'link' && i.from === chip.id && i.verb === a.id,
      )
    ) {
      items.push({
        id: `l-${uid()}`,
        type: 'link',
        from: chip.id,
        to: areaIds.get(d.to)!,
        verb: a.id,
      });
    }
  }
  return items;
}

class PlaygroundIsolated extends Component<typeof Playground> {
  @tracked items: SketchItem[] = [];
  @tracked selected: string | null = null;
  @tracked linking: string | null | 'armed' = null;
  @tracked imageUrl = '';
  @tracked asking = false;
  @tracked askError = '';
  @tracked fromBox = '';
  loadedFor: unknown = null;
  canvasEl: HTMLElement | null = null;

  get model() {
    return this.args.model as unknown as Playground;
  }
  syncItems = modifier(() => {
    if (this.loadedFor === this.model) return;
    this.loadedFor = this.model;
    let raw = (this.model.items as any) ?? [];
    Promise.resolve().then(() => (this.items = Array.isArray(raw) ? raw : []));
  });
  registerCanvas = modifier((el: HTMLElement) => {
    this.canvasEl = el;
    return () => (this.canvasEl = null);
  });
  save(next: SketchItem[]) {
    this.items = next;
    this.model.items = next as any;
  }

  // ─── geometry ─────────────────────────────────────────────────────────
  toUnits(clientX: number, clientY: number) {
    let r = this.canvasEl!.getBoundingClientRect();
    return {
      x: ((clientX - r.left) / r.width) * W,
      y: ((clientY - r.top) / r.height) * H,
    };
  }
  boxStyle(it: Box) {
    let h = 'h' in it ? `height:${(it.h / H) * 100}%;` : '';
    return htmlSafe(
      `left:${it.x}%; top:${(it.y / H) * 100}%; width:${it.w}%; ${h}`,
    );
  }
  get boxes() {
    return this.items
      .filter((i): i is Box => i.type !== 'link')
      .map((it) => ({
        id: it.id,
        it: it as any,
        style: this.boxStyle(it),
        def: (it.type === 'part' ? partDef(it) : undefined) as CompDef,
        sel: this.selected === it.id,
        taps: this.items
          .filter(
            (l) => l.type === 'link' && l.from === it.id && l.to === it.id,
          )
          .map((l: any) => ({
            id: l.id,
            verb: l.verb || '?',
            sel: this.selected === l.id,
          })),
        linkFrom: this.linking === it.id,
        z:
          it.type === 'area'
            ? 1
            : it.type === 'image'
              ? 2
              : it.type === 'note'
                ? 4
                : 3,
      }))
      .sort((a, b) => a.z - b.z);
  }
  centre(id: string) {
    let it = this.items.find((i) => i.id === id) as Box | undefined;
    if (!it) return null;
    let h = 'h' in it ? it.h : it.w * 1.2;
    return { x: it.x + it.w / 2, y: it.y + h / 2 };
  }
  get arrows() {
    return this.items
      .filter(
        (l): l is Extract<SketchItem, { type: 'link' }> =>
          l.type === 'link' && l.from !== l.to,
      )
      .map((l) => {
        let a = this.centre(l.from);
        let b = this.centre(l.to);
        if (!a || !b) return null;
        let mx = (a.x + b.x) / 2;
        let my = (a.y + b.y) / 2 - 3;
        return {
          l,
          d: `M${a.x} ${a.y} Q${mx} ${my} ${b.x} ${b.y}`,
          lx: mx,
          ly: my + 1.5,
          sel: this.selected === l.id,
          labelStyle: htmlSafe(`left:${mx}%; top:${((my + 1.5) / H) * 100}%`),
        };
      })
      .filter(Boolean) as any[];
  }
  get selectedItem(): any {
    return this.items.find((i) => i.id === this.selected) ?? null;
  }

  // ─── adding ───────────────────────────────────────────────────────────
  cascade = 0;
  nextSpot(w: number, h = w) {
    this.cascade = (this.cascade + 1) % 6;
    return {
      x: clamp(W / 2 - w / 2 + this.cascade * 2.5, 0, W - w),
      y: clamp(H / 2 - h / 2 + this.cascade * 2, 0, H - h),
    };
  }
  add(item: SketchItem) {
    this.save([...this.items, item]);
    this.selected = item.id;
  }
  addPart = (kind: Kind) => {
    let t = TRAY.find((x) => x.kind === kind)!;
    this.add({
      id: `p-${uid()}`,
      type: 'part',
      kind,
      label: '',
      count: 1,
      colour: t.colour,
      ...this.nextSpot(t.w),
      w: t.w,
    });
  };
  addNote = () =>
    this.add({
      id: `n-${uid()}`,
      type: 'note',
      text: '',
      ...this.nextSpot(16, 12),
      w: 16,
      h: 12,
    });
  addArea = () =>
    this.add({
      id: `a-${uid()}`,
      type: 'area',
      label: 'Area',
      zoneKind: 'pot',
      ...this.nextSpot(24, 16),
      w: 24,
      h: 16,
    });
  setImageUrl = (e: Event) =>
    (this.imageUrl = (e.target as HTMLInputElement).value);
  addImage = (e: Event) => {
    e.preventDefault();
    let url = this.imageUrl.trim();
    if (!/^https?:\/\//.test(url)) return;
    this.imageUrl = '';
    this.add({
      id: `i-${uid()}`,
      type: 'image',
      url,
      caption: '',
      ...this.nextSpot(18, 14),
      w: 18,
      h: 14,
    });
  };

  // ─── images: paste (⌘V), upload or drop; saved as files in the workspace ─
  @tracked uploading = 0;
  @tracked imageError = '';
  @tracked srcs: Record<string, string> = {}; // item id or file url → displayable src
  fileInput: HTMLInputElement | null = null;
  registerFileInput = modifier((el: HTMLInputElement) => {
    this.fileInput = el;
    return () => (this.fileInput = null);
  });
  pickFile = () => this.fileInput?.click();
  fileChosen = (e: Event) => {
    let input = e.target as HTMLInputElement;
    for (let f of Array.from(input.files ?? []))
      if (f.type.startsWith('image/')) this.ingest(f);
    input.value = '';
  };
  get toolCtx() {
    return (
      (this.args.context as any)?.toolContext ??
      (this.args.context as any)?.commandContext
    );
  }
  async ingest(file: Blob, at?: { x: number; y: number }) {
    this.imageError = '';
    let id = `i-${uid()}`;
    let local = URL.createObjectURL(file);
    let size = await imageSize(local);
    let w = 18;
    let h = clamp(w * (size.h / size.w), 6, 40); // x and y units are the same size on screen
    let spot = at
      ? { x: clamp(at.x - w / 2, 0, W - w), y: clamp(at.y - h / 2, 0, H - h) }
      : this.nextSpot(w, h);
    this.srcs = { ...this.srcs, [id]: local };
    this.add({
      id,
      type: 'image',
      url: '',
      caption: '',
      file: true,
      ...spot,
      w,
      h,
    });
    let ctx = this.toolCtx;
    if (!ctx) {
      this.imageError =
        "Images can't be saved from this view. Open the Playground from the workspace.";
      return;
    }
    this.uploading++;
    try {
      let { base64, type, ext } = await toUpload(file);
      let res = await new WriteBinaryFileTool(ctx).execute({
        realm: this.model[realmURL]?.href,
        path: `Playground/images/${(this.model.title || 'sketch').toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${uid()}.${ext}`,
        base64Content: base64,
        contentType: type,
        useNonConflictingFilename: true,
      } as any);
      let url = (res as any).fileIdentifier as string;
      this.srcs = { ...this.srcs, [url]: local };
      this.save(
        this.items.map((i) =>
          i.id === id ? ({ ...i, url } as SketchItem) : i,
        ),
      );
    } catch (e: any) {
      this.imageError = `The image couldn't be saved (${e?.message ?? e}).`;
    } finally {
      this.uploading--;
    }
  }
  // the host's session covers workspace files, so a saved image's URL shows
  // directly; the local copy stands in while it uploads
  srcFor = (it: any) => this.srcs[it.id] ?? it.url ?? '';
  pasteHandler = (e: ClipboardEvent) => {
    let files = Array.from(e.clipboardData?.files ?? []).filter((f) =>
      f.type.startsWith('image/'),
    );
    let inField = (e.target as HTMLElement)?.closest?.(
      'input, textarea, [contenteditable]',
    );
    if (files.length) {
      e.preventDefault();
      files.forEach((f) => this.ingest(f));
      return;
    }
    if (inField) return;
    let text = e.clipboardData?.getData('text')?.trim() ?? '';
    if (/^https?:\/\/\S+$/i.test(text)) {
      e.preventDefault();
      this.add({
        id: `i-${uid()}`,
        type: 'image',
        url: text,
        caption: '',
        ...this.nextSpot(18, 14),
        w: 18,
        h: 14,
      });
    }
  };
  listenPaste = modifier((el: HTMLElement) => {
    let h = (e: ClipboardEvent) => {
      // only while this Playground is the thing in focus (or nothing is)
      let a = document.activeElement;
      if (a && a !== document.body && !el.contains(a)) return;
      this.pasteHandler(e);
    };
    document.addEventListener('paste', h);
    return () => document.removeEventListener('paste', h);
  });
  dragOver = (e: Event) => e.preventDefault();
  dropFiles = (ev: Event) => {
    let e = ev as DragEvent;
    let files = Array.from(e.dataTransfer?.files ?? []).filter((f) =>
      f.type.startsWith('image/'),
    );
    if (!files.length || !this.canvasEl) return;
    e.preventDefault();
    let p = this.toUnits(e.clientX, e.clientY);
    files.forEach((f, i) => this.ingest(f, { x: p.x + i * 3, y: p.y + i * 3 }));
  };
  armLink = () => {
    this.linking = this.linking ? null : 'armed';
    this.selected = null;
  };

  // ─── pointer: move, resize, link ──────────────────────────────────────
  drag: {
    id: string;
    mode: 'move' | 'size';
    x0: number;
    y0: number;
    ox: number;
    oy: number;
    ow: number;
    oh: number;
    moved: boolean;
  } | null = null;
  @tracked live: {
    id: string;
    x: number;
    y: number;
    w: number;
    h: number;
  } | null = null;

  itemDown = (id: string, ev: Event) => {
    let e = ev as PointerEvent;
    e.stopPropagation();
    if (this.linking) {
      if (this.linking === 'armed') this.linking = id;
      else {
        let link: SketchItem = {
          id: `l-${uid()}`,
          type: 'link',
          from: this.linking,
          to: id,
          verb: this.linking === id ? 'tap' : 'move',
        };
        this.linking = null;
        this.add(link);
      }
      return;
    }
    this.startDrag(id, 'move', e);
  };
  sizeDown = (id: string, ev: Event) => {
    let e = ev as PointerEvent;
    e.stopPropagation();
    this.startDrag(id, 'size', e);
  };
  startDrag(id: string, mode: 'move' | 'size', e: PointerEvent) {
    let it = this.items.find((i) => i.id === id) as Box | undefined;
    if (!it || !this.canvasEl) return;
    (e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId);
    let p = this.toUnits(e.clientX, e.clientY);
    this.selected = id;
    this.drag = {
      id,
      mode,
      x0: p.x,
      y0: p.y,
      ox: it.x,
      oy: it.y,
      ow: it.w,
      oh: 'h' in it ? it.h : 0,
      moved: false,
    };
  }
  canvasMove = (ev: Event) => {
    let d = this.drag;
    if (!d) return;
    let e = ev as PointerEvent;
    let p = this.toUnits(e.clientX, e.clientY);
    let dx = p.x - d.x0;
    let dy = p.y - d.y0;
    if (!d.moved && Math.hypot(dx, dy) < 0.6) return;
    d.moved = true;
    if (d.mode === 'move')
      this.live = {
        id: d.id,
        x: clamp(d.ox + dx, -2, W - 2),
        y: clamp(d.oy + dy, -2, H - 2),
        w: d.ow,
        h: d.oh,
      };
    else
      this.live = {
        id: d.id,
        x: d.ox,
        y: d.oy,
        w: clamp(d.ow + dx, 3, W - d.ox),
        h: clamp(d.oh + dy, 3, H - d.oy),
      };
  };
  canvasUp = () => {
    let d = this.drag;
    this.drag = null;
    let l = this.live;
    this.live = null;
    if (!d || !d.moved || !l) return;
    this.save(
      this.items.map((i) => {
        if (i.id !== l.id || i.type === 'link') return i;
        let next: any = { ...i, x: round(l.x), y: round(l.y), w: round(l.w) };
        if ('h' in i) next.h = round(l.h);
        return next;
      }),
    );
  };
  canvasDown = (ev: Event) => {
    if ((ev.target as HTMLElement).closest('.item, .verb, .tap')) return;
    this.selected = null;
    if (this.linking && this.linking !== 'armed') this.linking = 'armed';
  };
  liveStyle(b: { it: Box; style: any }) {
    let l = this.live;
    if (!l || l.id !== b.it.id) return b.style;
    let h = 'h' in b.it ? `height:${(l.h / H) * 100}%;` : '';
    return htmlSafe(
      `left:${l.x}%; top:${(l.y / H) * 100}%; width:${l.w}%; ${h}`,
    );
  }
  styleFor = (b: any) => this.liveStyle(b);
  selectLink = (id: string, ev: Event) => {
    ev.stopPropagation();
    this.selected = id;
  };

  // ─── inspector ────────────────────────────────────────────────────────
  patch(changes: Record<string, any>) {
    let id = this.selected;
    this.save(
      this.items.map((i) =>
        i.id === id ? ({ ...i, ...changes } as SketchItem) : i,
      ),
    );
  }
  setText = (key: string, ev: Event) =>
    this.patch({ [key]: (ev.target as HTMLInputElement).value });
  setNumber = (key: string, ev: Event) =>
    this.patch({
      [key]: Math.max(
        1,
        Math.round(Number((ev.target as HTMLInputElement).value) || 1),
      ),
    });
  setValue = (key: string, value: any) => this.patch({ [key]: value });
  remove = () => {
    let id = this.selected;
    this.selected = null;
    this.save(
      this.items.filter(
        (i) =>
          i.id !== id && !(i.type === 'link' && (i.from === id || i.to === id)),
      ),
    );
  };
  duplicate = () => {
    let it = this.selectedItem;
    if (!it || it.type === 'link') return;
    this.add({
      ...it,
      id: `${it.id[0]}-${uid()}`,
      x: clamp(it.x + 3, 0, W - it.w),
      y: clamp(it.y + 3, 0, H - 4),
    } as SketchItem);
  };
  keys = modifier((el: HTMLElement) => {
    let h = (e: KeyboardEvent) => {
      if (
        (e.target as HTMLElement)?.closest(
          'input, textarea, select, [contenteditable]',
        )
      )
        return;
      if ((e.key === 'Delete' || e.key === 'Backspace') && this.selected) {
        e.preventDefault();
        this.remove();
      }
      if (e.key === 'Escape') {
        this.selected = null;
        this.linking = null;
      }
    };
    el.addEventListener('keydown', h);
    return () => el.removeEventListener('keydown', h);
  });

  // ─── title, ask, start from a box ─────────────────────────────────────
  setTitle = (e: Event) =>
    (this.model.title = (e.target as HTMLInputElement).value);
  setAsk = (e: Event) =>
    (this.model.ask = (e.target as HTMLTextAreaElement).value);
  get realms() {
    let r = this.model[realmURL];
    return r ? [r.href] : [];
  }
  gamesQuery = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: { module: new URL('./game', here).href, name: 'Game' },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  get boxGames() {
    return ((this.gamesQuery?.instances ?? []) as unknown as Game[]).filter(
      (g) => !(this.model.drafts ?? []).some((d) => d.id === g.id),
    );
  }
  pickBox = (e: Event) =>
    (this.fromBox = (e.target as HTMLSelectElement).value);
  layOut = () => {
    let g = this.boxGames.find((x) => x.id === this.fromBox);
    if (!g) return;
    this.save([...this.items, ...sketchFromGame(g)]);
    this.selected = null;
  };
  @tracked draftPick = '';
  pickDraft = (e: Event) =>
    (this.draftPick = (e.target as HTMLSelectElement).value);
  addDraft = () => {
    let g = this.boxGames.find((x) => x.id === this.draftPick);
    if (!g) return;
    this.model.drafts = [...(this.model.drafts ?? []), g];
    this.draftPick = '';
  };
  clearAll = () => {
    this.save([]);
    this.selected = null;
  };

  // ─── make this game ───────────────────────────────────────────────────
  get prompt() {
    let m = this.model;
    let counts = this.items.reduce(
      (acc: Record<string, number>, i) => (
        (acc[i.type] = (acc[i.type] ?? 0) + 1),
        acc
      ),
      {},
    );
    let what = Object.entries(counts)
      .map(([k, n]) => `${n} ${k}${n === 1 ? '' : 's'}`)
      .join(', ');
    return [
      `Make my Playground sketch "${m.title || 'Untitled'}" into a playable game for the Rainy Day Table.`,
      m.ask ? `What I want: ${m.ask}` : '',
      `The sketch (attached, in its "items" field) has ${what || 'nothing yet'}.`,
      'Follow the "Rainy Day Table: game authoring" skill, section "From a Playground": areas become zones in the same places, parts ×count become components with that many copies, notes are the rules, arrows are gestures, and every image is art to use (look at each one first: a character becomes the portrait of its seat, a card face becomes card art). Write a new Game card and a policy Opponent, check the Health check passes, then link the Game into this Playground\'s drafts.',
    ]
      .filter(Boolean)
      .join('\n\n');
  }
  makeGame = async () => {
    this.askError = '';
    let ctx =
      (this.args.context as any)?.toolContext ??
      (this.args.context as any)?.commandContext;
    if (!ctx) {
      this.askError =
        'The AI assistant is not available here. Copy the prompt below into the assistant instead.';
      return;
    }
    this.asking = true;
    try {
      let skills = [new URL('./Skill/game-authoring', here).href];
      let index = await skillsIndexFor(this.model[realmURL]);
      if (index) skills.unshift(index);
      await new UseAiAssistantTool(ctx).execute({
        roomId: 'new',
        roomName: `Make a game: ${this.model.title || 'Playground'}`,
        openRoom: true,
        attachedCardIds: [this.model.id],
        attachedFileIdentifiers: this.items
          .filter((i: any) => i.type === 'image' && i.file && i.url)
          .map((i: any) => i.url),
        skillCardIds: skills,
        prompt: this.prompt,
      } as any);
    } catch (e: any) {
      this.askError = `Couldn't open the assistant (${e?.message ?? e}). Copy the prompt below into it instead.`;
    } finally {
      this.asking = false;
    }
  };
  playDraft = async (g: Game) => {
    try {
      await startMatch(g, {
        createCard: this.args.createCard as any,
        viewCard: this.args.viewCard as any,
        context: this.args.context,
      });
    } catch (e: any) {
      this.askError = `Couldn't start a match: ${e.message}`;
    }
  };
  openCard = (g: Game) => this.args.viewCard?.(g, 'isolated');

  <template>
    <div
      class='pg'
      tabindex='0'
      {{this.keys}}
      {{this.syncItems}}
      {{this.listenPaste}}
    >
      <header class='top'>
        <div class='titles'>
          <p class='eyebrow'>Rainy Day Table · Playground</p>
          <input
            class='title'
            aria-label='Game name'
            placeholder='Name your game'
            value={{@model.title}}
            {{on 'change' this.setTitle}}
          />
          <textarea
            class='ask'
            aria-label='What should it be?'
            rows='2'
            placeholder='Say what you want, e.g. "a push-your-luck card game for two, first to 30 wins"'
            {{on 'change' this.setAsk}}
          >{{@model.ask}}</textarea>
        </div>
        <div class='make'>
          <button
            type='button'
            class='primary big'
            disabled={{this.asking}}
            {{on 'click' this.makeGame}}
          >{{if this.asking 'Opening the assistant…' 'Make this game'}}</button>
          <p class='make-sub'>Opens the AI assistant with this sketch attached
            and the authoring skill loaded.</p>
        </div>
      </header>
      {{#if this.askError}}
        <div class='ask-err' role='alert'>
          <p>{{this.askError}}</p>
          <pre>{{this.prompt}}</pre>
        </div>
      {{/if}}

      <div class='body'>
        <aside class='tray' aria-label='Parts tray'>
          <p class='tray-h'>Parts</p>
          <div class='tray-grid'>
            {{#each TRAY as |t|}}
              <button
                type='button'
                class='tray-item'
                title='Add a {{t.label}}'
                {{on 'click' (fn this.addPart t.kind)}}
              >
                <span class='tray-part'><Part
                    @def={{t.def}}
                    @colour={{t.colour}}
                    @cardLook={{BACK}}
                  /></span>
                <span>{{t.label}}</span>
              </button>
            {{/each}}
          </div>
          <p class='tray-h'>Sketch</p>
          <button type='button' class='tool' {{on 'click' this.addArea}}>▭ Area</button>
          <button type='button' class='tool' {{on 'click' this.addNote}}>✎ Note</button>
          <button
            type='button'
            class='tool {{if this.linking "on"}}'
            aria-pressed={{if this.linking 'true' 'false'}}
            {{on 'click' this.armLink}}
          >↝ Gesture</button>
          {{#if this.linking}}
            <p class='tray-tip'>{{if
                (eq this.linking 'armed')
                'Click where it starts.'
                'Now click where it goes, or the same thing again for a tap.'
              }}</p>
          {{/if}}
          <button type='button' class='tool' {{on 'click' this.pickFile}}>＋
            Image</button>
          <input
            class='file'
            type='file'
            accept='image/*'
            multiple
            aria-label='Upload images'
            {{this.registerFileInput}}
            {{on 'change' this.fileChosen}}
          />
          <p class='tray-tip quiet'>Or paste one anywhere (⌘V), or drop it on
            the table.{{#if this.uploading}} Saving…{{/if}}</p>
          {{#if this.imageError}}<p
              class='tray-tip err'
            >{{this.imageError}}</p>{{/if}}
          <form class='img-form' {{on 'submit' this.addImage}}>
            <input
              aria-label='Image link'
              placeholder='…or an image link'
              value={{this.imageUrl}}
              {{on 'input' this.setImageUrl}}
            />
          </form>
        </aside>

        <div class='stage'>
          <div
            class='canvas {{if this.linking "linking"}}'
            role='application'
            aria-label='Sketch canvas'
            {{this.registerCanvas}}
            {{on 'pointermove' this.canvasMove}}
            {{on 'pointerup' this.canvasUp}}
            {{on 'dragover' this.dragOver}}
            {{on 'drop' this.dropFiles}}
            {{grab this.canvasDown}}
          >
            {{#unless this.items.length}}
              <div class='empty'>
                <p><b>Tip the box out.</b>
                  Add parts from the tray, draw areas for where things go, write
                  the rules on notes, and draw gestures ("deal", "bet") between
                  areas.</p>
                <p>Or start from an existing game below and remix it.</p>
              </div>
            {{/unless}}
            {{#each this.boxes key='id' as |b|}}
              <div
                class='item t-{{b.it.type}}
                  {{if b.sel "sel"}}
                  {{if b.linkFrom "link-from"}}'
                style={{this.styleFor b}}
                {{grab (fn this.itemDown b.it.id)}}
              >
                {{#if (eq b.it.type 'part')}}
                  <span class='part'><Part
                      @def={{b.def}}
                      @colour={{b.it.colour}}
                      @cardLook={{BACK}}
                    /></span>
                  {{#if b.it.label}}<span
                      class='plabel'
                    >{{b.it.label}}</span>{{/if}}
                  {{#if (gt1 b.it.count)}}<span
                      class='count'
                    >×{{b.it.count}}</span>{{/if}}
                {{else if (eq b.it.type 'note')}}
                  <p class='note-text'>{{if
                      b.it.text
                      b.it.text
                      'Write a rule…'
                    }}</p>
                {{else if (eq b.it.type 'area')}}
                  <span class='alabel'>{{b.it.label}}
                    <i>{{kindLabel b.it.zoneKind}}</i></span>
                {{else if (eq b.it.type 'image')}}
                  {{#let (this.srcFor b.it) as |src|}}
                    {{#if src}}<img
                        src={{src}}
                        alt={{if b.it.caption b.it.caption 'Reference image'}}
                        draggable='false'
                      />{{else}}<span class='img-wait'>Loading image…</span>{{/if}}
                  {{/let}}
                  {{#if b.it.caption}}<span
                      class='caption'
                    >{{b.it.caption}}</span>{{/if}}
                {{/if}}
                {{#each b.taps as |t|}}
                  <button
                    type='button'
                    class='tap {{if t.sel "sel"}}'
                    {{on 'click' (fn this.selectLink t.id)}}
                  >👆 {{t.verb}}</button>
                {{/each}}
                {{#if
                  (or
                    (eq b.it.type 'area')
                    (eq b.it.type 'note')
                    (eq b.it.type 'image')
                    (eq b.it.type 'part')
                  )
                }}
                  {{#if b.sel}}<span
                      class='size'
                      aria-hidden='true'
                      {{grab (fn this.sizeDown b.it.id)}}
                    ></span>{{/if}}
                {{/if}}
              </div>
            {{/each}}
            <svg
              class='arrows'
              viewBox='0 0 100 62.5'
              preserveAspectRatio='none'
              aria-hidden='true'
            >
              <defs><marker
                  id='pg-head'
                  viewBox='0 0 10 10'
                  refX='8'
                  refY='5'
                  markerWidth='5'
                  markerHeight='5'
                  orient='auto-start-reverse'
                ><path d='M0 0L10 5L0 10z' fill='#ffd27a' /></marker></defs>
              {{#each this.arrows as |a|}}
                <path
                  d={{a.d}}
                  class='arrow {{if a.sel "sel"}}'
                  marker-end='url(#pg-head)'
                  vector-effect='non-scaling-stroke'
                />
              {{/each}}
            </svg>
            {{#each this.arrows as |a|}}
              <button
                type='button'
                class='verb {{if a.sel "sel"}}'
                style={{a.labelStyle}}
                {{on 'click' (fn this.selectLink a.l.id)}}
              >{{if a.l.verb a.l.verb '?'}}</button>
            {{/each}}
          </div>

          <div class='under'>
            <div class='from-box'>
              <label for='pg-box'>Start from a box</label>
              <select id='pg-box' {{on 'change' this.pickBox}}>
                <option value=''>Choose a game…</option>
                {{#each this.boxGames as |g|}}<option
                    value={{g.id}}
                  >{{g.title}}</option>{{/each}}
              </select>
              <button
                type='button'
                class='ghost'
                disabled={{if this.fromBox false true}}
                {{on 'click' this.layOut}}
              >Lay it out</button>
              {{#if this.items.length}}<button
                  type='button'
                  class='ghost quiet'
                  {{on 'click' this.clearAll}}
                >Clear the table</button>{{/if}}
            </div>
            <div class='from-box'>
              <label for='pg-draft'>Add a draft</label>
              <select id='pg-draft' {{on 'change' this.pickDraft}}>
                <option value=''>Choose a game the assistant made…</option>
                {{#each this.boxGames as |g|}}<option
                    value={{g.id}}
                  >{{g.title}}</option>{{/each}}
              </select>
              <button
                type='button'
                class='ghost'
                disabled={{if this.draftPick false true}}
                {{on 'click' this.addDraft}}
              >Add</button>
            </div>
          </div>
        </div>

        <aside class='inspector' aria-label='Inspector'>
          {{#let this.selectedItem as |s|}}
            {{#if s}}
              {{#if (eq s.type 'part')}}
                <p class='insp-h'>{{s.kind}}</p>
                <label>Name<input
                    value={{s.label}}
                    placeholder='e.g. Ace, Gold coin'
                    {{on 'change' (fn this.setText 'label')}}
                  /></label>
                <label>How many<input
                    type='number'
                    min='1'
                    value={{s.count}}
                    {{on 'change' (fn this.setNumber 'count')}}
                  /></label>
                <span class='lbl'>Colour</span>
                <div class='swatches'>
                  {{#each SWATCHES as |c|}}
                    <button
                      type='button'
                      class='sw {{if (eq s.colour c) "on"}}'
                      style={{swatch c}}
                      aria-label='Colour {{c}}'
                      {{on 'click' (fn this.setValue 'colour' c)}}
                    ></button>
                  {{/each}}
                </div>
                <label>Image link (art)<input
                    value={{s.image}}
                    placeholder='https://…'
                    {{on 'change' (fn this.setText 'image')}}
                  /></label>
              {{else if (eq s.type 'note')}}
                <p class='insp-h'>Note</p>
                <label>Rule or idea<textarea
                    rows='6'
                    {{on 'change' (fn this.setText 'text')}}
                  >{{s.text}}</textarea></label>
              {{else if (eq s.type 'area')}}
                <p class='insp-h'>Area</p>
                <label>Name<input
                    value={{s.label}}
                    placeholder='e.g. Your hand, Draw pile'
                    {{on 'change' (fn this.setText 'label')}}
                  /></label>
                <span class='lbl'>What it is</span>
                <div class='kinds'>
                  {{#each ZONE_KINDS as |k|}}
                    <button
                      type='button'
                      class='chip {{if (eq s.zoneKind k.id) "on"}}'
                      {{on 'click' (fn this.setValue 'zoneKind' k.id)}}
                    >{{k.label}}</button>
                  {{/each}}
                </div>
              {{else if (eq s.type 'image')}}
                <p class='insp-h'>Image</p>
                <label>Caption<input
                    value={{s.caption}}
                    placeholder='What is this for?'
                    {{on 'change' (fn this.setText 'caption')}}
                  /></label>
                <label>Link<input
                    value={{s.url}}
                    {{on 'change' (fn this.setText 'url')}}
                  /></label>
              {{else if (eq s.type 'link')}}
                <p class='insp-h'>Gesture</p>
                <label>Verb<input
                    value={{s.verb}}
                    placeholder='deal, bet, discard…'
                    {{on 'change' (fn this.setText 'verb')}}
                  /></label>
                <div class='kinds'>
                  {{#each VERBS as |v|}}
                    <button
                      type='button'
                      class='chip {{if (eq s.verb v) "on"}}'
                      {{on 'click' (fn this.setValue 'verb' v)}}
                    >{{v}}</button>
                  {{/each}}
                </div>
                <p class='insp-tip'>{{if
                    (eq s.from s.to)
                    'A tap: clicking this does the verb.'
                    'A drag: moving a part from the start to the end does the verb.'
                  }}</p>
              {{/if}}
              <div class='insp-actions'>
                {{#unless (eq s.type 'link')}}<button
                    type='button'
                    class='ghost'
                    {{on 'click' this.duplicate}}
                  >Duplicate</button>{{/unless}}
                <button
                  type='button'
                  class='ghost danger'
                  {{on 'click' this.remove}}
                >Delete</button>
              </div>
            {{else}}
              <p class='insp-h'>How it works</p>
              <ol class='how'>
                <li>Put parts on the table. Set how many of each.</li>
                <li>Draw
                  <b>areas</b>
                  where things live: a deck, your hand, the pot.</li>
                <li>Write the rules on <b>notes</b>, in your own words.</li>
                <li>Draw
                  <b>gestures</b>: an arrow from deck to hand called "draw", or
                  a tap on the dice called "roll".</li>
                <li>Press
                  <b>Make this game</b>. The draft appears below; play it,
                  adjust, ask again.</li>
              </ol>
            {{/if}}
          {{/let}}
        </aside>
      </div>

      <section class='drafts'>
        <h2>Drafts</h2>
        {{#if @model.drafts.length}}
          <div class='draft-row'>
            {{#each @model.drafts as |g|}}
              <div class='draft'>
                <button
                  type='button'
                  class='draft-open'
                  {{on 'click' (fn this.openCard g)}}
                >
                  <span class='draft-sw' style={{swatch g.tableColour}}></span>
                  <b>{{g.title}}</b>
                  <small>{{g.summary}}</small>
                </button>
                <button
                  type='button'
                  class='primary'
                  {{on 'click' (fn this.playDraft g)}}
                >Play</button>
              </div>
            {{/each}}
          </div>
        {{else}}
          <p class='muted'>None yet. When the assistant makes your game, it
            links the draft here.</p>
        {{/if}}
      </section>
    </div>
    <style scoped>
      .pg {
        min-height: 100%;
        background: #f4ecdd;
        color: #2b231b;
        font-family:
          ui-rounded, 'SF Pro Rounded', 'Nunito', system-ui, sans-serif;
        padding: 1.1rem clamp(0.75rem, 2cqw, 1.5rem) 2rem;
        container-type: inline-size;
        outline: none;
      }
      .top {
        display: flex;
        gap: 1.25rem;
        align-items: flex-end;
        justify-content: space-between;
        flex-wrap: wrap;
      }
      .titles {
        flex: 1 1 26rem;
        min-width: 0;
      }
      .eyebrow {
        margin: 0;
        font-size: 0.72rem;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: #8a7355;
      }
      .title {
        width: 100%;
        border: 0;
        background: transparent;
        font:
          700 2rem/1.15 'Iowan Old Style',
          Palatino,
          Georgia,
          serif;
        color: inherit;
        padding: 0.1rem 0;
        border-bottom: 1px dashed transparent;
      }
      .title:hover,
      .title:focus {
        border-bottom-color: #cdb995;
        outline: none;
      }
      .ask {
        width: 100%;
        margin-top: 0.35rem;
        border: 1px solid #ddcdae;
        border-radius: 0.6rem;
        background: #fbf6ec;
        font: inherit;
        font-size: 0.95rem;
        padding: 0.5rem 0.7rem;
        resize: vertical;
      }
      .make {
        text-align: right;
        max-width: 16rem;
      }
      .make-sub {
        margin: 0.35rem 0 0;
        font-size: 0.78rem;
        color: #8a7a66;
      }
      .ask-err {
        margin-top: 0.75rem;
        background: #fbe9d4;
        border-radius: 0.6rem;
        padding: 0.6rem 0.8rem;
        font-size: 0.85rem;
      }
      .ask-err pre {
        white-space: pre-wrap;
        font-size: 0.78rem;
        background: #fffaf0;
        padding: 0.5rem;
        border-radius: 0.4rem;
        user-select: all;
      }
      .body {
        display: grid;
        grid-template-columns: 9.5rem 1fr 14rem;
        gap: 0.9rem;
        margin-top: 1rem;
        align-items: start;
      }
      .tray,
      .inspector {
        background: #fbf6ec;
        border-radius: 0.8rem;
        padding: 0.75rem;
        box-shadow: 0 1px 0 #e4d6bb;
      }
      .tray-h,
      .insp-h {
        margin: 0.1rem 0 0.5rem;
        font-size: 0.72rem;
        letter-spacing: 0.09em;
        text-transform: uppercase;
        color: #8a7355;
      }
      .tray-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 0.35rem;
        margin-bottom: 0.9rem;
      }
      .tray-item {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.2rem;
        padding: 0.45rem 0.2rem 0.35rem;
        border: 0;
        border-radius: 0.55rem;
        background: #2f6b4f;
        color: #f6ecd8;
        font: inherit;
        font-size: 0.72rem;
        cursor: pointer;
      }
      .tray-item:hover {
        background: #377b5b;
      }
      .tray-part {
        width: 1.9rem;
        height: 2.3rem;
        display: grid;
        place-items: center;
      }
      .tool {
        display: block;
        width: 100%;
        margin-bottom: 0.35rem;
        text-align: left;
        font: inherit;
        font-size: 0.88rem;
        font-weight: 650;
        padding: 0.4rem 0.6rem;
        border-radius: 0.5rem;
        border: 1px solid #ddcdae;
        background: #fffaf0;
        color: #4b3a26;
        cursor: pointer;
      }
      .tool.on {
        background: #f4c35a;
        border-color: #d9a73e;
      }
      .tray-tip {
        font-size: 0.78rem;
        color: #8a5a12;
        margin: 0 0 0.5rem;
      }
      .file {
        position: absolute;
        width: 1px;
        height: 1px;
        opacity: 0;
        pointer-events: none;
      }
      .tray-tip.quiet {
        color: #8a7a66;
      }
      .tray-tip.err {
        color: #8a2a20;
      }
      .img-wait {
        display: grid;
        place-items: center;
        height: 100%;
        font-size: max(10px, 1.1cqw);
        color: #fff6dc;
        background: rgba(0, 0, 0, 0.15);
        border-radius: 0.5cqw;
      }
      .under .from-box + .from-box {
        margin-top: 0.5rem;
      }
      .img-form input {
        width: 100%;
        font: inherit;
        font-size: 0.8rem;
        padding: 0.35rem 0.45rem;
        border: 1px solid #ddcdae;
        border-radius: 0.4rem;
        margin: 0.4rem 0 0.35rem;
        box-sizing: border-box;
      }
      .stage {
        min-width: 0;
      }
      .canvas {
        position: relative;
        aspect-ratio: 1.6;
        border-radius: 1rem;
        background-color: #2f6b4f;
        background-image:
          radial-gradient(
            ellipse at 30% 15%,
            rgba(255, 255, 255, 0.13),
            transparent 60%
          ),
          radial-gradient(
            circle,
            rgba(255, 255, 255, 0.07) 1px,
            transparent 1.4px
          );
        background-size:
          100% 100%,
          5% 8%;
        box-shadow:
          inset 0 0 0 4px rgba(0, 0, 0, 0.18),
          inset 0 8px 22px rgba(0, 0, 0, 0.25);
        overflow: hidden;
        touch-action: none;
        user-select: none;
        container-type: inline-size;
      }
      .canvas.linking {
        cursor: crosshair;
      }
      .empty {
        position: absolute;
        inset: 18% 18%;
        display: grid;
        place-content: center;
        text-align: center;
        color: rgba(255, 246, 220, 0.82);
        line-height: 1.5;
        font-size: max(12px, 1.6cqw);
        pointer-events: none;
      }
      .item {
        position: absolute;
        cursor: grab;
      }
      .item.sel {
        outline: 2px solid #ffd27a;
        outline-offset: 3px;
        border-radius: 0.4rem;
      }
      .item.link-from {
        outline: 2px dashed #ffd27a;
        outline-offset: 3px;
      }
      .t-part {
        display: flex;
        flex-direction: column;
        align-items: center;
      }
      .part {
        width: 100%;
      }
      .plabel {
        margin-top: 0.2cqw;
        font-size: max(10px, 1.2cqw);
        font-weight: 700;
        color: #fff6dc;
        text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
        white-space: nowrap;
      }
      .count {
        position: absolute;
        top: -0.8cqw;
        right: -1.4cqw;
        background: #f4c35a;
        color: #2b1d0c;
        font-weight: 800;
        font-size: max(10px, 1.2cqw);
        padding: 0.05em 0.45em;
        border-radius: 99px;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
      }
      .t-note {
        background: #fff1a8;
        color: #3a3020;
        padding: 0.7cqw 0.9cqw;
        box-shadow: 0.3cqw 0.6cqw 1cqw rgba(0, 0, 0, 0.28);
        rotate: -1.2deg;
        overflow: hidden;
      }
      .note-text {
        margin: 0;
        font-size: max(10px, 1.25cqw);
        line-height: 1.4;
        white-space: pre-wrap;
      }
      .t-area {
        border: 0.25cqw dashed rgba(255, 246, 220, 0.55);
        border-radius: 1cqw;
        background: rgba(255, 255, 255, 0.04);
      }
      .alabel {
        position: absolute;
        left: 0.7cqw;
        top: 0.5cqw;
        font-size: max(10px, 1.25cqw);
        font-weight: 700;
        color: rgba(255, 246, 220, 0.9);
      }
      .alabel i {
        font-style: normal;
        font-weight: 500;
        opacity: 0.7;
      }
      .t-image img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        border-radius: 0.5cqw;
        box-shadow: 0 0.5cqw 1cqw rgba(0, 0, 0, 0.3);
        border: 0.5cqw solid #fffaf0;
        box-sizing: border-box;
      }
      .caption {
        position: absolute;
        left: 0;
        right: 0;
        bottom: -2.4cqw;
        text-align: center;
        font-size: max(10px, 1.1cqw);
        color: #fff6dc;
      }
      .tap {
        position: absolute;
        right: -1.2cqw;
        top: -1.4cqw;
        z-index: 3;
        white-space: nowrap;
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
        border: 0;
        border-radius: 99px;
        background: #ffd27a;
        color: #2b1d0c;
        font: inherit;
        font-weight: 750;
        font-size: max(10px, 1.15cqw);
        padding: 0.1em 0.6em;
        cursor: pointer;
      }
      .tap + .tap {
        top: 1.4cqw;
      }
      .tap.sel,
      .verb.sel {
        outline: 2px solid #fff;
      }
      .size {
        position: absolute;
        right: -0.8cqw;
        bottom: -0.8cqw;
        width: 1.6cqw;
        height: 1.6cqw;
        min-width: 10px;
        min-height: 10px;
        background: #ffd27a;
        border-radius: 3px;
        cursor: nwse-resize;
      }
      .arrows {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        pointer-events: none;
        z-index: 5;
      }
      .arrow {
        fill: none;
        stroke: #ffd27a;
        stroke-width: 3;
        stroke-dasharray: 7 5;
        opacity: 0.9;
      }
      .arrow.sel {
        stroke: #fff;
      }
      .verb {
        position: absolute;
        translate: -50% -50%;
        z-index: 6;
        border: 0;
        border-radius: 99px;
        background: #ffd27a;
        color: #2b1d0c;
        font: inherit;
        font-weight: 750;
        font-size: max(10px, 1.2cqw);
        padding: 0.1em 0.65em;
        cursor: pointer;
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
      }
      .under {
        margin-top: 0.7rem;
      }
      .from-box {
        display: flex;
        gap: 0.5rem;
        align-items: center;
        flex-wrap: wrap;
        font-size: 0.88rem;
      }
      .from-box label {
        font-weight: 650;
        color: #6b5a45;
      }
      .from-box select {
        font: inherit;
        padding: 0.35rem 0.5rem;
        border-radius: 0.45rem;
        border: 1px solid #ddcdae;
        background: #fffaf0;
      }
      .inspector label {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        font-size: 0.8rem;
        font-weight: 650;
        color: #6b5a45;
        margin-bottom: 0.65rem;
      }
      .inspector input,
      .inspector textarea {
        font: inherit;
        font-size: 0.9rem;
        font-weight: 400;
        padding: 0.4rem 0.5rem;
        border: 1px solid #ddcdae;
        border-radius: 0.45rem;
        background: #fffaf0;
        color: #2b231b;
      }
      .lbl {
        display: block;
        font-size: 0.8rem;
        font-weight: 650;
        color: #6b5a45;
        margin-bottom: 0.3rem;
      }
      .swatches,
      .kinds {
        display: flex;
        flex-wrap: wrap;
        gap: 0.3rem;
        margin-bottom: 0.7rem;
      }
      .sw {
        width: 1.5rem;
        height: 1.5rem;
        border-radius: 50%;
        border: 2px solid #fffaf0;
        box-shadow: 0 0 0 1px #ddcdae;
        cursor: pointer;
      }
      .sw.on {
        box-shadow: 0 0 0 2px #2b231b;
      }
      .chip {
        font: inherit;
        font-size: 0.8rem;
        padding: 0.2rem 0.55rem;
        border-radius: 99px;
        border: 1px solid #ddcdae;
        background: #fffaf0;
        cursor: pointer;
      }
      .chip.on {
        background: #f4c35a;
        border-color: #d9a73e;
      }
      .insp-tip {
        font-size: 0.8rem;
        color: #7a6a55;
      }
      .insp-actions {
        display: flex;
        gap: 0.4rem;
        margin-top: 0.3rem;
      }
      .how {
        padding-left: 1.1rem;
        margin: 0;
        font-size: 0.85rem;
        line-height: 1.5;
        color: #4b3a26;
      }
      .how li {
        margin-bottom: 0.35rem;
      }
      .primary,
      .ghost {
        font: inherit;
        font-weight: 700;
        border-radius: 99px;
        padding: 0.45rem 1rem;
        cursor: pointer;
      }
      .primary {
        border: 0;
        background: #f4c35a;
        color: #2b1d0c;
        box-shadow: 0 3px 0 #b88a2c;
      }
      .primary.big {
        font-size: 1.05rem;
        padding: 0.75rem 1.6rem;
      }
      .primary:hover {
        background: #f7cd6f;
      }
      .primary:disabled {
        opacity: 0.7;
        cursor: progress;
      }
      .ghost {
        border: 1.5px solid #cdb995;
        background: transparent;
        color: #4b3a26;
        font-size: 0.85rem;
      }
      .ghost:disabled {
        opacity: 0.45;
      }
      .ghost.quiet {
        border-color: transparent;
        color: #8a7a66;
      }
      .ghost.danger {
        color: #8a2a20;
        border-color: #e2b8ae;
      }
      button:focus-visible,
      input:focus-visible,
      textarea:focus-visible,
      select:focus-visible {
        outline: 2px solid #c58b2a;
        outline-offset: 2px;
      }
      .drafts {
        margin-top: 1.5rem;
      }
      .drafts h2 {
        font-size: 0.75rem;
        letter-spacing: 0.09em;
        text-transform: uppercase;
        color: #8a7355;
        margin: 0 0 0.6rem;
      }
      .draft-row {
        display: flex;
        gap: 0.75rem;
        flex-wrap: wrap;
      }
      .draft {
        display: flex;
        align-items: center;
        gap: 0.6rem;
        background: #fbf6ec;
        border-radius: 0.8rem;
        padding: 0.5rem 0.6rem 0.5rem 0.5rem;
        box-shadow: 0 1px 0 #e4d6bb;
      }
      .draft-open {
        display: grid;
        grid-template-columns: auto 1fr;
        grid-template-rows: auto auto;
        column-gap: 0.5rem;
        border: 0;
        background: none;
        font: inherit;
        text-align: left;
        cursor: pointer;
        max-width: 18rem;
      }
      .draft-sw {
        grid-row: span 2;
        width: 2.2rem;
        height: 2.2rem;
        border-radius: 0.4rem;
        box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.15);
      }
      .draft-open small {
        color: #7a6a55;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .muted {
        color: #8a7a66;
        font-size: 0.9rem;
      }
      @container (width < 900px) {
        .body {
          grid-template-columns: 1fr;
        }
        .tray {
          display: flex;
          flex-wrap: wrap;
          gap: 0.35rem;
          align-items: center;
        }
        .tray-h {
          width: 100%;
          margin: 0.2rem 0 0;
        }
        .tray-grid {
          grid-template-columns: repeat(8, minmax(3.2rem, 1fr));
          width: 100%;
          margin-bottom: 0.3rem;
        }
        .tool {
          width: auto;
          margin: 0;
        }
        .img-form {
          display: flex;
          gap: 0.35rem;
          align-items: center;
          flex: 1 1 14rem;
        }
        .img-form input {
          margin: 0;
        }
        .make {
          text-align: left;
          max-width: none;
        }
      }
      @container (width < 520px) {
        .tray-grid {
          grid-template-columns: repeat(4, 1fr);
        }
      }
    </style>
  </template>
}

export class Playground extends CardDef {
  static displayName = 'Playground';
  static icon = ShapesIcon;
  @field title = contains(StringField);
  @field ask = contains(StringField);
  @field items = contains(GameJsonField); // the sketch: SketchItem[]
  @field drafts = linksToMany(() => Game);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Playground) {
      return this.title ? `Playground · ${this.title}` : 'Playground';
    },
  });
  static isolated = PlaygroundIsolated;
  static fitted = class Fitted extends Component<typeof this> {
    get count() {
      let items = ((this.args.model as any).items ?? []) as SketchItem[];
      return items.filter((i) => i.type !== 'link').length;
    }
    <template>
      <div class='f'>
        <span class='e'>Playground</span>
        <b>{{if @model.title @model.title 'Untitled sketch'}}</b>
        <small>{{this.count}}
          things on the table ·
          {{if @model.drafts.length @model.drafts.length 0}}
          drafts</small>
      </div>
      <style scoped>
        .f {
          height: 100%;
          display: flex;
          flex-direction: column;
          justify-content: flex-end;
          padding: 0.7rem 0.8rem;
          box-sizing: border-box;
          background:
            radial-gradient(
                circle,
                rgba(255, 255, 255, 0.08) 1px,
                transparent 1.4px
              )
              0 0 / 14px 14px,
            #2f6b4f;
          color: #fff8ea;
          font-family: ui-rounded, system-ui, sans-serif;
        }
        .e {
          font-size: 0.65rem;
          letter-spacing: 0.1em;
          text-transform: uppercase;
          opacity: 0.75;
        }
        b {
          font:
            700 1.05rem 'Iowan Old Style',
            Georgia,
            serif;
        }
        small {
          opacity: 0.8;
        }
      </style>
    </template>
  };
}

const BACK = { backPattern: 'lattice', backColour: '#8c2f39', depth: 2 };
// A room made through UseAiAssistantTool only gets the skills we pass; the
// panel's own "new chat" adds the Boxel Skills Index (how to create and patch
// cards) by default. Pass it too, from this server's skills realm.
async function skillsIndexFor(realm?: URL) {
  if (!realm) return null;
  let url = new URL('/skills/index.md', realm.origin).href;
  try {
    let r = await fetch(url, { method: 'HEAD' });
    return r.ok ? url : null;
  } catch {
    return null;
  }
}
function imageSize(src: string): Promise<{ w: number; h: number }> {
  return new Promise((res) => {
    let img = new Image();
    img.onload = () =>
      res({ w: img.naturalWidth || 4, h: img.naturalHeight || 3 });
    img.onerror = () => res({ w: 4, h: 3 });
    img.src = src;
  });
}
// Downscale big pictures (phone photos) so the workspace and the AI stay light.
async function toUpload(
  file: Blob,
): Promise<{ base64: string; type: string; ext: string }> {
  let bmp = await createImageBitmap(file);
  let scale = Math.min(1, 1600 / Math.max(bmp.width, bmp.height));
  let keepPng =
    file.type === 'image/png' && file.size < 1_500_000 && scale === 1;
  let blob: Blob = file;
  if (!keepPng) {
    let c = document.createElement('canvas');
    c.width = Math.round(bmp.width * scale);
    c.height = Math.round(bmp.height * scale);
    c.getContext('2d')!.drawImage(bmp, 0, 0, c.width, c.height);
    blob = await new Promise<Blob>((r) =>
      c.toBlob((b) => r(b!), 'image/jpeg', 0.86),
    );
  }
  let buf = new Uint8Array(await blob.arrayBuffer());
  let bin = '';
  for (let i = 0; i < buf.length; i += 0x8000)
    bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return {
    base64: btoa(bin),
    type: keepPng ? 'image/png' : 'image/jpeg',
    ext: keepPng ? 'png' : 'jpg',
  };
}
function round(n: number) {
  return Math.round(n * 10) / 10;
}
function gt1(n?: number) {
  return (n ?? 1) > 1;
}
function kindLabel(k?: string) {
  return ZONE_KINDS.find((z) => z.id === k)?.label.toLowerCase() ?? '';
}
function swatch(c?: string) {
  return htmlSafe(`background:${c ?? '#b9a685'}`);
}
const grab = modifier((el: HTMLElement, [handler]: [(e: Event) => void]) => {
  el.addEventListener('pointerdown', handler);
  return () => el.removeEventListener('pointerdown', handler);
});
