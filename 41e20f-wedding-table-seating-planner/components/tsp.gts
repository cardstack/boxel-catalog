import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';
import { computePosition, offset, flip, shift } from '@floating-ui/dom';
import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Component, ImageDef } from 'https://cardstack.com/base/card-api';
import {
  realmURL,
  identifyCard,
  chooseCard,
  chooseFile,
  baseCardRef,
} from '@cardstack/runtime-common';
import WriteBinaryFileCommand from '@cardstack/boxel-host/commands/write-binary-file';
import UseAiAssistantCommand from '@cardstack/boxel-host/commands/ai-assistant';
import { AnalyzeFloorPlanCommand } from '../commands/analyze-floor-plan-command';
import {
  InvitationPosterCommand,
  POSTER_ASPECTS,
} from '../commands/invitation-poster-command';
import { debounce } from 'lodash-es';
import type { TableSeatingPlanner } from '../table-seating-planner';
import { Guest } from '../guest';
import { Host } from '../host';
import { Table } from '../table';
import { Fixture } from '../fixture';
import { LayoutTemplate } from '../layout-template';
import FixtureGlyph from './fixture-glyph';
import LayoutPreview from './layout-preview';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import SeatingPlanPopover from './seating-plan-popover';
import PencilIcon from '@cardstack/boxel-icons/pencil';
import XIcon from '@cardstack/boxel-icons/x';
import LockIcon from '@cardstack/boxel-icons/lock';
import LockOpenIcon from '@cardstack/boxel-icons/lock-open';
import TrashIcon from '@cardstack/boxel-icons/trash';
import CopyIcon from '@cardstack/boxel-icons/copy';
import StarIcon from '@cardstack/boxel-icons/star';
import DownloadIcon from '@cardstack/boxel-icons/download';
import SearchIcon from '@cardstack/boxel-icons/search';
import CameraIcon from '@cardstack/boxel-icons/camera';
import ArrowsMoveIcon from '@cardstack/boxel-icons/arrows-move';
import TemplateIcon from '@cardstack/boxel-icons/template';
import RefreshIcon from '@cardstack/boxel-icons/refresh';
import {
  FIXTURE_KINDS,
  FIXTURE_KIND_LABELS,
  FIXTURE_DEFAULTS,
  TABLE_SHAPES,
  TABLE_SHAPE_LABELS,
  SEATING_STYLES,
  seatPoints,
  sectionSeatPoints,
  sectionSize,
  initialsOf,
  shortTableLabel,
  SEAT_ORDERS,
  FOCAL_FIXTURE_KINDS,
  GUEST_CATEGORIES,
  categoryLabel,
  categoryColor,
  type SeatOrder,
} from '../utils/index';
const FLOOR_PLAN_DIR = 'FloorPlan/';
const POSTER_DIR = 'InvitationPoster';
interface SeatVM {
  index: number;
  leftPct: string;
  topPct: string;
  filled: boolean;
  label: string;
  photoURL: string;
  color: string;
  isDrop: boolean;
  guest: Guest | null;
}
interface TableVM {
  id: string;
  model: Table;
  wrapStyle: string;
  surfaceClass: string;
  short: string;
  name: string;
  seats: SeatVM[];
  selected: boolean;
  targeting: boolean;
  vip: boolean;
  rank: number;
  pinned: boolean;
  curved: boolean;
  isSeat: boolean;
  isSection: boolean;
}
interface FixtureVM {
  id: string;
  model: Fixture;
  wrapStyle: string;
  selected: boolean;
  targeting: boolean;
  label: string;
  fill: string;
}
interface TableClip {
  name: Table['name'];
  shape: Table['shape'];
  seatCount: Table['seatCount'];
  seatingStyle: Table['seatingStyle'];
  rows: Table['rows'];
  cols: Table['cols'];
  seatOrder: Table['seatOrder'];
  x: number;
  y: number;
  width: Table['width'];
  height: Table['height'];
  rotation: Table['rotation'];
  themeColor: Table['themeColor'];
  vip: Table['vip'];
  note: Table['note'];
  reservedCategories: string[];
}
interface FixtureClip {
  label: Fixture['label'];
  kind: Fixture['kind'];
  pattern: Fixture['pattern'];
  x: number;
  y: number;
  width: Fixture['width'];
  height: Fixture['height'];
  rotation: Fixture['rotation'];
  color: Fixture['color'];
}
type ClipItem =
  | { kind: 'table'; data: TableClip }
  | { kind: 'fixture'; data: FixtureClip };
type DragMode =
  | 'none'
  | 'table'
  | 'fixture'
  | 'pan'
  | 'guest'
  | 'resize'
  | 'rotate'
  | 'floorplan'
  | 'marquee'
  | 'move';

// A linked theme's variables, returned as an inline-style declaration string to
// apply on the planner root. Empty when no theme is linked — in which case every
// `var(--token, fallback)` in the scoped styles simply uses its fallback. Only
// the light `:root` block is read, and it is applied inline on the element, so
// the theme can never leak onto sibling cards or the surrounding listing.
function buildThemeVars(theme: any): string {
  let css = theme?.cssVariables;
  if (!css) return '';
  let m = String(css).match(/:root\s*\{([\s\S]*?)\}/);
  if (!m) return '';
  return m[1]
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

export class TableSeatingPlannerIsolated extends Component<
  typeof TableSeatingPlanner
> {
  @tracked view: 'plan' | 'invites' = 'plan';
  @tracked inviteSearch = '';
  get isPlan() {
    return this.view === 'plan';
  }
  get isInvites() {
    return this.view === 'invites';
  }
  setView = (v: 'plan' | 'invites') => {
    this.view = v;
  };
  @tracked aiStatus: 'idle' | 'loading' = 'idle';
  @tracked selectedKeys: string[] = [];
  @tracked floorSelected = false;
  @tracked clipboard: ClipItem[] = [];
  private pasteSeq = 0;
  @tracked marquee: { x: number; y: number; w: number; h: number } | null =
    null;
  @tracked marqueeHitKeys: string[] = [];
  @tracked spaceDown = false;
  @tracked search = '';
  @tracked activeCatId: string | null = null;
  @tracked addMenuOpen = false;
  @tracked zoom = 1;
  @tracked panX = 60;
  @tracked panY = 40;
  @tracked draggingGuest: Guest | null = null;
  @tracked draggingGuestId: string | null = null;
  @tracked ghostX = 0;
  @tracked ghostY = 0;
  @tracked dropTableKey: string | null = null;
  @tracked dropSeatIndex = -1;
  @tracked hoverGuest: Guest | null = null;
  @tracked hoverX = 0;
  @tracked hoverY = 0;
  private dragMode: DragMode = 'none';
  private dragId: string | null = null;
  private startPX = 0;
  private startPY = 0;
  private origX = 0;
  private origY = 0;
  private resizeKind: 'table' | 'fixture' | 'floorplan' = 'fixture';
  private resizeEdge = 'se';
  private origW = 0;
  private origH = 0;
  private dragRot = 0;
  private dragTarget: Table | Fixture | null = null;
  private dragSet: { el: Table | Fixture; ox: number; oy: number }[] = [];
  private dragFloor = false;
  private floorOX = 0;
  private floorOY = 0;
  private mStartX = 0;
  private mStartY = 0;
  private rotEl: Table | Fixture | null = null;
  private rotCx = 0;
  private rotCy = 0;
  private rotStart = 0;
  private rotOrig = 0;
  @tracked private liveMove: {
    keys: string[];
    dx: number;
    dy: number;
    floor: boolean;
  } | null = null;
  @tracked private liveSize: {
    key: string;
    w: number;
    h: number;
    dx: number;
    dy: number;
  } | null = null;
  @tracked private liveRotate: { key: string; deg: number } | null = null;
  @tracked private liveColor: { key: string; color: string } | null = null;
  @tracked private liveOpacity: number | null = null;
  private effX(el: Table | Fixture): number {
    let base = el.x || 0;
    let lm = this.liveMove;
    if (lm && lm.keys.includes(keyOf(el))) base += lm.dx;
    let ls = this.liveSize;
    if (ls && ls.key === keyOf(el)) base += ls.dx;
    return base;
  }
  private effY(el: Table | Fixture): number {
    let base = el.y || 0;
    let lm = this.liveMove;
    if (lm && lm.keys.includes(keyOf(el))) base += lm.dy;
    let ls = this.liveSize;
    if (ls && ls.key === keyOf(el)) base += ls.dy;
    return base;
  }
  private effW(el: Table | Fixture, fallback: number): number {
    let ls = this.liveSize;
    return ls && ls.key === keyOf(el) ? ls.w : el.width || fallback;
  }
  private effH(el: Table | Fixture, fallback: number): number {
    let ls = this.liveSize;
    return ls && ls.key === keyOf(el) ? ls.h : el.height || fallback;
  }
  private effRot(el: Table | Fixture): number {
    let lr = this.liveRotate;
    return lr && lr.key === keyOf(el) ? lr.deg : el.rotation || 0;
  }
  private effColor(el: Table | Fixture, current: string): string {
    let lc = this.liveColor;
    return lc && lc.key === keyOf(el) ? lc.color : current;
  }
  private get effFloorX(): number {
    let base = this.args.model?.floorPlanX || 0;
    let lm = this.liveMove;
    return lm?.floor ? base + lm.dx : base;
  }
  private get effFloorY(): number {
    let base = this.args.model?.floorPlanY || 0;
    let lm = this.liveMove;
    return lm?.floor ? base + lm.dy : base;
  }
  private get effFloorW(): number {
    let ls = this.liveSize;
    return ls && ls.key === '__floor__'
      ? ls.w
      : this.args.model?.floorPlanWidth || 800;
  }
  private get effFloorH(): number {
    let ls = this.liveSize;
    return ls && ls.key === '__floor__'
      ? ls.h
      : this.args.model?.floorPlanHeight || 600;
  }
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
    if (!e) return;
    e.u();
    this.redoStack.push(e);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
  };
  redo = () => {
    let e = this.redoStack.pop();
    if (!e) return;
    e.r();
    this.undoStack.push(e);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
  };
  positionTip = modifier((el: HTMLElement, [x, y]: [number, number]) => {
    let reference = {
      getBoundingClientRect: () => ({
        x,
        y,
        top: y,
        left: x,
        right: x,
        bottom: y,
        width: 0,
        height: 0,
      }),
    };
    computePosition(reference as any, el, {
      strategy: 'fixed',
      placement: 'top-start',
      middleware: [offset(14), flip({ padding: 10 }), shift({ padding: 10 })],
    }).then(({ x: left, y: top }) => {
      el.style.left = `${left}px`;
      el.style.top = `${top}px`;
    });
  });
  keyboard = modifier(() => {
    let onKey = (e: KeyboardEvent) => {
      let el = e.target as HTMLElement | null;
      let typing = !!el && /^(INPUT|TEXTAREA)$/.test(el.tagName);
      if (e.code === 'Space' && !typing) {
        this.spaceDown = true;
        if (!e.repeat) e.preventDefault();
        return;
      }
      if (typing) return;
      let mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        if (e.shiftKey) this.redo();
        else this.undo();
        return;
      }
      if (mod && e.key.toLowerCase() === 'c') {
        if (this.copySelection()) e.preventDefault();
        return;
      }
      if (mod && e.key.toLowerCase() === 'x') {
        if (this.selCount) {
          e.preventDefault();
          this.cutSelection();
        }
        return;
      }
      if (mod && e.key.toLowerCase() === 'v') {
        if (this.clipboard.length) {
          e.preventDefault();
          this.pasteClipboard();
        }
        return;
      }
      if (mod && e.key.toLowerCase() === 'd') {
        if (this.selCount) {
          e.preventDefault();
          this.duplicateSelection();
        }
        return;
      }
      if ((e.key === 'Delete' || e.key === 'Backspace') && this.selCount) {
        e.preventDefault();
        this.confirmDeleteSelected();
        return;
      }
      if (e.key.startsWith('Arrow') && this.selCount) {
        e.preventDefault();
        let step = e.shiftKey ? 20 : 4;
        let dx =
          e.key === 'ArrowLeft' ? -step : e.key === 'ArrowRight' ? step : 0;
        let dy = e.key === 'ArrowUp' ? -step : e.key === 'ArrowDown' ? step : 0;
        if (dx || dy) this.nudgeSelected(dx, dy);
        return;
      }
    };
    let onUp = (e: KeyboardEvent) => {
      if (e.code === 'Space') this.spaceDown = false;
    };
    window.addEventListener('keydown', onKey);
    window.addEventListener('keyup', onUp);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('keyup', onUp);
    };
  });
  private slotsOf(t: Table): number[] {
    let n = (t.seatedGuests ?? []).length;
    let slots = (t.seatSlots ?? []) as number[];
    if (slots.length === n) return [...slots];
    return Array.from({ length: n }, (_, i) => i);
  }
  private snapshotSeats(): Map<Table, { guests: Guest[]; slots: number[] }> {
    let m = new Map<Table, { guests: Guest[]; slots: number[] }>();
    for (let t of this.tables)
      m.set(t, {
        guests: [...((t.seatedGuests ?? []) as Guest[])],
        slots: this.slotsOf(t),
      });
    return m;
  }
  private restoreSeats(snap: Map<Table, { guests: Guest[]; slots: number[] }>) {
    for (let [t, s] of snap) {
      t.seatedGuests = [...s.guests];
      t.seatSlots = [...s.slots];
    }
  }
  private recordSeatChange(mutate: () => void) {
    let before = this.snapshotSeats();
    mutate();
    let after = this.snapshotSeats();
    this.pushUndo(
      () => this.restoreSeats(before),
      () => this.restoreSeats(after),
    );
  }
  private recordSet<T>(setter: (v: T) => void, before: T, after: T) {
    if (before === after) return;
    setter(after);
    this.pushUndo(
      () => setter(before),
      () => setter(after),
    );
  }
  get plan() {
    return this.args.model;
  }
  get guests(): Guest[] {
    return ((this.args.model?.guests ?? []) as Guest[]).filter(Boolean);
  }
  get tables(): Table[] {
    return ((this.args.model?.tables ?? []) as Table[]).filter(Boolean);
  }
  get fixtures(): Fixture[] {
    return ((this.args.model?.fixtures ?? []) as Fixture[]).filter(Boolean);
  }
  private get focalCentre(): { x: number; y: number } {
    let centre = (el: {
      x?: number;
      y?: number;
      width?: number;
      height?: number;
    }) => ({
      x: (el.x || 0) + (el.width || 0) / 2,
      y: (el.y || 0) + (el.height || 0) / 2,
    });
    let focal: Fixture | undefined;
    for (let kind of FOCAL_FIXTURE_KINDS) {
      focal = this.fixtures.find((f) => f.kind === kind);
      if (focal) break;
    }
    let front =
      focal ??
      this.tables.find((t) => t.vip) ??
      [...this.tables].sort((a, b) => (a.y || 0) - (b.y || 0))[0];
    return front ? centre(front) : { x: 0, y: 0 };
  }
  get tableRank(): Map<Table, number> {
    let c = this.focalCentre;
    let distOf = (t: Table) =>
      Math.hypot(
        (t.x || 0) + (t.width || 0) / 2 - c.x,
        (t.y || 0) + (t.height || 0) / 2 - c.y,
      );
    let n = this.tables.length;
    let slots: (Table | undefined)[] = new Array(n).fill(undefined);
    let placeAt = (t: Table, idx: number) => {
      let i = Math.min(Math.max(idx, 0), Math.max(0, n - 1));
      while (i < n && slots[i]) i++;
      if (i >= n) i = slots.findIndex((s) => !s);
      if (i >= 0) slots[i] = t;
    };
    let pinned = this.tables
      .filter((t) => (t.rank || 0) >= 1)
      .sort((a, b) => (a.rank || 0) - (b.rank || 0) || distOf(a) - distOf(b));
    let pinnedSet = new Set(pinned);
    for (let t of pinned) placeAt(t, (t.rank || 1) - 1);
    let auto = this.tables
      .filter((t) => !pinnedSet.has(t))
      .sort(
        (a, b) =>
          (a.vip === b.vip ? 0 : a.vip ? -1 : 1) || distOf(a) - distOf(b),
      );
    let ai = 0;
    for (let i = 0; i < n; i++) if (!slots[i]) slots[i] = auto[ai++];
    let map = new Map<Table, number>();
    slots.forEach((t, i) => {
      if (t) map.set(t, i + 1);
    });
    return map;
  }
  get fixtureKinds() {
    return FIXTURE_KINDS;
  }
  get tableShapes() {
    return TABLE_SHAPES;
  }
  get seatingStyles() {
    return SEATING_STYLES;
  }
  // The linked theme (cardInfo.theme) as inline vars applied on the planner
  // root — affects this card's subtree only, never the surrounding listing.
  get themeVars() {
    return htmlSafe(buildThemeVars((this.args.model as any)?.cardInfo?.theme));
  }
  get eventLogoURL(): string {
    return (this.args.model as any)?.eventLogo?.resolvedUrl ?? '';
  }
  get eventInitials(): string {
    let t = (this.args.model?.eventTitle ?? '').trim();
    if (!t) return '';
    let words = t.split(/\s+/).filter(Boolean);
    let letters = words
      .slice(0, 2)
      .map((w) => w[0])
      .join('');
    return (letters || t.slice(0, 2)).toUpperCase();
  }
  get seatedGuestIds(): Set<string> {
    let s = new Set<string>();
    for (let t of this.tables) {
      for (let g of t.seatedGuests ?? []) {
        if (g) s.add(keyOf(g));
      }
    }
    return s;
  }
  get allRosterSeated(): boolean {
    return (
      this.guests.length > 0 &&
      this.guests.every((g) => this.seatedGuestSet.has(g as Guest))
    );
  }
  get totalGuests() {
    try {
      return this.guests.length;
    } catch {
      return 0;
    }
  }
  get seatedCount() {
    return this.seatedGuestIds.size;
  }
  get pct() {
    let total = this.totalGuests || 1;
    return `${Math.round((this.seatedCount / total) * 100)}%`;
  }
  get tableCount() {
    return this.tables.length;
  }
  get tableVMs(): TableVM[] {
    let rankMap = this.tableRank;
    return this.tables.map((t) => {
      let w = this.effW(t, 150);
      let h = this.effH(t, 150);
      let shape = t.shape || 'round';
      let style = t.seatingStyle || 'around';
      let isSection = shape === 'section';
      let count =
        shape === 'seat'
          ? 1
          : isSection
            ? Math.max(0, Math.floor(t.rows || 0)) *
              Math.max(0, Math.floor(t.cols || 0))
            : (t.seatCount ?? 8);
      let pts = isSection
        ? sectionSeatPoints(
            t.rows || 0,
            t.cols || 0,
            (t.seatOrder as SeatOrder) || 'lr-tb',
          )
        : seatPoints(shape, style, count);
      let seatedRaw = (t.seatedGuests ?? []) as Guest[];
      let slots = this.slotsOf(t);
      let bySlot = new Map<number, Guest>();
      seatedRaw.forEach((g, k) => {
        if (g) bySlot.set(slots[k], g);
      });
      let tk = keyOf(t);
      let dropping = !!this.draggingGuest && this.dropTableKey === tk;
      let seats: SeatVM[] = pts.map((p, i) => {
        let g = bySlot.get(i);
        return {
          index: i,
          leftPct: `${p.x * 100}%`,
          topPct: `${p.y * 100}%`,
          filled: !!g,
          label: g ? initialsOf(g.fullName) : `${i + 1}`,
          photoURL: (g as any)?.photoURL || '',
          color: g?.category
            ? categoryColor(g.category)
            : 'var(--acc, #c5a35c)',
          isDrop: dropping && this.dropSeatIndex === i,
          guest: g ?? null,
        };
      });
      let surfaceClass = `t-surface shape-${shape}`;
      let rotRad = (this.effRot(t) * Math.PI) / 180;
      let halfH =
        (Math.abs(w * Math.sin(rotRad)) + Math.abs(h * Math.cos(rotRad))) / 2;
      return {
        id: keyOf(t),
        model: t,
        wrapStyle: `position:absolute;left:0;top:0;transform:translate(${this.effX(
          t,
        )}px,${this.effY(t)}px) rotate(${this.effRot(
          t,
        )}deg);width:${w}px;height:${h}px;z-index:${
          t.z || 2
        };--rot:${this.effRot(t)}deg;--halfh:${halfH}px;`,
        surfaceClass,
        short: shortTableLabel(t.name),
        name: t.name || 'Table',
        seats,
        selected: this.isSelected(keyOf(t)),
        targeting: this.marqueeHitKeys.includes(keyOf(t)),
        vip: !!t.vip,
        rank: rankMap.get(t) ?? 0,
        pinned: (t.rank || 0) >= 1,
        curved: shape === 'curved',
        isSeat: shape === 'seat',
        isSection,
      };
    });
  }
  get fixtureVMs(): FixtureVM[] {
    return this.fixtures.map((f) => {
      let w = this.effW(f, 100);
      let h = this.effH(f, 100);
      return {
        id: keyOf(f),
        model: f,
        wrapStyle: `position:absolute;left:0;top:0;transform:translate(${this.effX(
          f,
        )}px,${this.effY(f)}px) rotate(${this.effRot(
          f,
        )}deg);width:${w}px;height:${h}px;z-index:${f.z || 1};`,
        selected: this.isSelected(keyOf(f)),
        targeting: this.marqueeHitKeys.includes(keyOf(f)),
        label: f.title,
        fill: this.effColor(f, f.color || '#c5a35c'),
      };
    });
  }
  get worldStyle() {
    return `position:absolute;inset:0;transform-origin:0 0;transform:translate(${this.panX}px,${this.panY}px) scale(${this.zoom});`;
  }
  get zoomPct() {
    return `${Math.round(this.zoom * 100)}%`;
  }
  get zoomAtMin() {
    return this.zoom <= 0.4;
  }
  get zoomAtMax() {
    return this.zoom >= 2.5;
  }
  get selectedTable(): Table | null {
    if (this.selectedKeys.length !== 1) return null;
    return this.tables.find((t) => keyOf(t) === this.selectedKeys[0]) ?? null;
  }
  get selectedFixture(): Fixture | null {
    if (this.selectedKeys.length !== 1) return null;
    return this.fixtures.find((f) => keyOf(f) === this.selectedKeys[0]) ?? null;
  }
  get selectedTables(): Table[] {
    return this.tables.filter((t) => this.isSelected(keyOf(t)));
  }
  get selectedFixtures(): Fixture[] {
    return this.fixtures.filter((f) => this.isSelected(keyOf(f)));
  }
  get selectionHasTables() {
    return this.selectedTables.length > 0;
  }
  get selectionShape(): string {
    let tables = this.selectedTables;
    if (!tables.length) return '';
    let first = tables[0].shape;
    return tables.every((t) => t.shape === first) ? (first ?? '') : '';
  }
  get selectedTableVM(): TableVM | null {
    let t = this.selectedTable;
    if (!t) return null;
    let tk = keyOf(t);
    return this.tableVMs.find((vm) => vm.id === tk) ?? null;
  }
  get inspTableBoxStyle(): ReturnType<typeof htmlSafe> {
    let t = this.selectedTable;
    if (!t) return htmlSafe('');
    let w = this.effW(t, 150);
    let h = this.effH(t, 150);
    let scale = this.inspTableScale(t, w, h);
    let rot = this.effRot(t);
    return htmlSafe(
      `width:${Math.round(w * scale)}px;height:${Math.round(
        h * scale,
      )}px;transform:rotate(${rot}deg)`,
    );
  }
  private inspTableScale(t: Table, w: number, h: number): number {
    let scale = 190 / Math.max(w, h);
    let pitch = 40;
    if (t.shape === 'section') {
      let rows = Math.max(1, Math.floor(t.rows || 0));
      let cols = Math.max(1, Math.floor(t.cols || 0));
      scale = Math.max(scale, (pitch * cols) / w, (pitch * rows) / h);
    } else {
      let count = t.shape === 'seat' ? 1 : (t.seatCount ?? 8);
      let pts = seatPoints(
        t.shape || 'round',
        t.seatingStyle || 'around',
        count,
      );
      let minDist = Infinity;
      for (let i = 0; i < pts.length; i++) {
        for (let j = i + 1; j < pts.length; j++) {
          let dx = (pts[i].x - pts[j].x) * w;
          let dy = (pts[i].y - pts[j].y) * h;
          minDist = Math.min(minDist, Math.hypot(dx, dy));
        }
      }
      if (Number.isFinite(minDist) && minDist > 0) {
        scale = Math.max(scale, pitch / minDist);
      }
    }
    return scale;
  }
  get inspTableReserveStyle(): ReturnType<typeof htmlSafe> {
    let t = this.selectedTable;
    if (!t) return htmlSafe('');
    let scale = this.inspTableScale(t, this.effW(t, 150), this.effH(t, 150));
    let w = this.effW(t, 150) * scale;
    let h = this.effH(t, 150) * scale;
    let rad = (this.effRot(t) * Math.PI) / 180;
    let bw = Math.abs(w * Math.cos(rad)) + Math.abs(h * Math.sin(rad));
    let bh = Math.abs(w * Math.sin(rad)) + Math.abs(h * Math.cos(rad));
    return htmlSafe(
      `width:${Math.round(bw) + 56}px;height:${Math.round(bh) + 56}px`,
    );
  }
  get catChips() {
    return GUEST_CATEGORIES.filter((c) =>
      this.guests.some((g) => g.category === c.value),
    ).map((c) => ({
      id: c.value,
      name: c.label,
      color: c.color,
      countSeated: this.guests.filter((g) => g.category === c.value).length,
    }));
  }
  onSearch = (e: Event) => {
    this.search = (e.target as HTMLInputElement).value;
  };
  private commitEventTitle = debounce((v: string) => {
    if (!this.args.model) {
      return;
    }
    this.args.model.eventTitle = v;
    if (this.args.model.cardInfo) {
      this.args.model.cardInfo.name = v;
    }
  }, 300);
  private commitVenue = debounce((v: string) => {
    this.args.model.venue = v;
  }, 300);
  private commitTableName = debounce((t: Table, v: string) => {
    t.name = v;
  }, 300);
  private commitFixtureLabel = debounce((f: Fixture, v: string) => {
    f.label = v;
  }, 300);
  private commitInviteMessage = debounce((v: string) => {
    this.args.model.invitationMessage = v;
  }, 300);
  override willDestroy() {
    this.commitEventTitle.flush();
    this.commitVenue.flush();
    this.commitTableName.flush();
    this.commitFixtureLabel.flush();
    this.commitInviteMessage.flush();
    this.commitFloorUnderlay.flush();
    super.willDestroy();
  }
  setEventTitle = (e: Event) => {
    this.commitEventTitle((e.target as HTMLInputElement).value);
  };
  setVenue = (e: Event) => {
    this.commitVenue((e.target as HTMLInputElement).value);
  };
  setCat = (id: string | null) => {
    this.activeCatId = id;
  };
  isSelected = (key: string) => this.selectedKeys.includes(key);
  private selectOnly(key: string) {
    this.selectedKeys = [key];
    this.floorSelected = false;
  }
  toggleSel = (key: string) => {
    this.selectedKeys = this.isSelected(key)
      ? this.selectedKeys.filter((k) => k !== key)
      : [...this.selectedKeys, key];
  };
  selectTable = (id: string) => this.selectOnly(id);
  selectFixture = (id: string) => this.selectOnly(id);
  deselect = () => {
    this.selectedKeys = [];
    this.floorSelected = false;
    this.popoverTableKey = null;
  };
  get multiSelected() {
    return this.selectedKeys.length > 1;
  }
  get selCount() {
    return this.selectedKeys.length + (this.floorSelected ? 1 : 0);
  }
  get selectedGeometry(): Array<Table | Fixture> {
    return [...this.selectedTables, ...this.selectedFixtures];
  }
  get canAlign(): boolean {
    return this.selectedGeometry.length >= 2;
  }
  alignSelected = (edge: string) => {
    let els = this.selectedGeometry;
    if (els.length < 2) return;
    let boxes = els.map((e) => ({
      e,
      w: e.width || 100,
      h: e.height || 100,
    }));
    let minX = Math.min(...els.map((e) => e.x || 0));
    let maxR = Math.max(...els.map((e) => (e.x || 0) + (e.width || 100)));
    let minY = Math.min(...els.map((e) => e.y || 0));
    let maxB = Math.max(...els.map((e) => (e.y || 0) + (e.height || 100)));
    let cX = (minX + maxR) / 2;
    let cY = (minY + maxB) / 2;
    let before = els.map((e) => ({ e, x: e.x, y: e.y }));
    let apply = () => {
      for (let b of boxes) {
        if (edge === 'left') b.e.x = minX;
        else if (edge === 'right') b.e.x = maxR - b.w;
        else if (edge === 'hcenter') b.e.x = cX - b.w / 2;
        else if (edge === 'top') b.e.y = minY;
        else if (edge === 'bottom') b.e.y = maxB - b.h;
        else if (edge === 'vcenter') b.e.y = cY - b.h / 2;
      }
    };
    apply();
    this.pushUndo(() => {
      for (let s of before) {
        s.e.x = s.x;
        s.e.y = s.y;
      }
    }, apply);
  };
  get canDistribute(): boolean {
    return this.selectedGeometry.length >= 3;
  }
  distributeSelected = (axis: 'h' | 'v') => {
    let els = this.selectedGeometry;
    if (els.length < 3) return;
    let horiz = axis === 'h';
    let sizeOf = (e: Table | Fixture) => (horiz ? e.width : e.height) || 100;
    let posOf = (e: Table | Fixture) => (horiz ? e.x : e.y) || 0;
    let sorted = [...els].sort((a, b) => posOf(a) - posOf(b));
    let first = sorted[0];
    let last = sorted[sorted.length - 1];
    let span = posOf(last) + sizeOf(last) - posOf(first);
    let occupied = sorted.reduce((sum, e) => sum + sizeOf(e), 0);
    let gap = (span - occupied) / (sorted.length - 1);
    let before = els.map((e) => ({ e, x: e.x, y: e.y }));
    let apply = () => {
      let cursor = posOf(first);
      for (let e of sorted) {
        if (horiz) e.x = cursor;
        else e.y = cursor;
        cursor += sizeOf(e) + gap;
      }
    };
    apply();
    this.pushUndo(() => {
      for (let s of before) {
        s.e.x = s.x;
        s.e.y = s.y;
      }
    }, apply);
  };
  @tracked popoverTableKey: string | null = null;
  get tablePopoverAnchor() {
    return `[data-tedit='${this.popoverTableKey}']`;
  }
  openTablePopover = (key: string, e: PointerEvent) => {
    e.stopPropagation();
    e.preventDefault();
    this.selectTable(key);
    this.popoverTableKey = key;
  };
  closeTablePopover = () => {
    this.popoverTableKey = null;
  };
  popoverDuplicate = () => {
    this.duplicateTable();
    this.closeTablePopover();
  };
  popoverDelete = () => {
    this.requestDelete(
      'Delete this table?',
      `“${this.selectedTable?.name || 'Table'}” will be removed and its guests unseated. You can undo afterwards.`,
      () => {
        this.removeTable();
        this.closeTablePopover();
      },
    );
  };
  @tracked pendingDelete: {
    title: string;
    detail: string;
    run: () => void;
  } | null = null;
  requestDelete = (title: string, detail: string, run: () => void) => {
    this.pendingDelete = { title, detail, run };
  };
  cancelDelete = () => {
    this.pendingDelete = null;
  };
  confirmDelete = () => {
    let p = this.pendingDelete;
    this.pendingDelete = null;
    p?.run();
  };
  confirmDeleteTable = () => {
    this.requestDelete(
      'Delete this table?',
      `“${this.selectedTable?.name || 'Table'}” will be removed and its guests unseated. You can undo afterwards.`,
      () => this.removeTable(),
    );
  };
  confirmDeleteFixture = () => {
    this.requestDelete(
      'Delete this element?',
      `“${this.selectedFixture?.label || 'Element'}” will be removed from the canvas. You can undo afterwards.`,
      () => this.removeFixture(),
    );
  };
  confirmDeleteSelected = () => {
    this.requestDelete(
      `Delete ${this.selCount} selected?`,
      'The selected tables and elements will be removed and their guests unseated. You can undo afterwards.',
      () => this.deleteSelected(),
    );
  };
  confirmRemoveGuest = (g: Guest) => {
    this.requestDelete(
      'Remove this guest?',
      `${g.fullName || 'This guest'} (and any companions) will leave the roster and their seats. The Guest card itself is not deleted.`,
      () => this.removeGuest(g),
    );
  };
  unlockElement = (kind: 'table' | 'fixture', id: string) => {
    let el =
      kind === 'table'
        ? this.tables.find((t) => keyOf(t) === id)
        : this.fixtures.find((f) => keyOf(f) === id);
    if (!el || !el.locked) return;
    this.recordSet((v) => (el!.locked = v), true, false);
  };
  stopProp = (e: Event) => {
    e.stopPropagation();
  };
  scrollToolbar = (evt: Event) => {
    let e = evt as WheelEvent;
    let el = e.currentTarget as HTMLElement;
    if (el.scrollWidth <= el.clientWidth) return; // nothing to scroll
    e.preventDefault();
    e.stopPropagation();
    let delta = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
    el.scrollLeft += delta;
  };
  private worldCenter() {
    return {
      x: (300 - this.panX) / this.zoom,
      y: (220 - this.panY) / this.zoom,
    };
  }
  addSeat = () => {
    this.addMenuOpen = false;
    let { x, y } = this.worldCenter();
    let n = this.tables.filter((t) => t.shape === 'seat').length + 1;
    let t = new Table({
      name: `Seat ${n}`,
      shape: 'seat',
      seatCount: 1,
      seatingStyle: 'around',
      x,
      y,
      width: 46,
      height: 46,
      rotation: 0,
      z: this.nextZ(),
    });
    this.args.model.tables = [...this.tables, t];
    this.selectTable(keyOf(t));
    this.pushUndo(
      () => {
        this.args.model.tables = this.tables.filter((x) => x !== t);
        this.deselect();
      },
      () => {
        this.args.model.tables = [...this.tables, t];
      },
    );
  };
  addSection = () => {
    this.addMenuOpen = false;
    let { x, y } = this.worldCenter();
    let rows = 5;
    let cols = 6;
    let n = this.tables.filter((t) => t.shape === 'section').length + 1;
    let size = sectionSize(rows, cols);
    let t = new Table({
      name: `Seating ${n}`,
      shape: 'section',
      rows,
      cols,
      seatCount: rows * cols,
      seatingStyle: 'around',
      x,
      y,
      width: size.w,
      height: size.h,
      rotation: 0,
      z: this.nextZ(),
    });
    this.args.model.tables = [...this.tables, t];
    this.selectTable(keyOf(t));
    this.pushUndo(
      () => {
        this.args.model.tables = this.tables.filter((x) => x !== t);
        this.deselect();
      },
      () => {
        this.args.model.tables = [...this.tables, t];
      },
    );
  };
  addTableShape = (shape: string) => {
    this.addMenuOpen = false;
    let { x, y } = this.worldCenter();
    let n = this.tables.filter((t) => t.shape === shape).length + 1;
    let w = 150;
    let h = 150;
    let seatCount = 8;
    let style = 'around';
    if (shape === 'oval') {
      w = 210;
      h = 130;
      seatCount = 10;
    } else if (shape === 'rect') {
      w = 220;
      h = 110;
      seatCount = 8;
    } else if (shape === 'square') {
      w = 150;
      h = 150;
      seatCount = 8;
    } else if (shape === 'curved') {
      w = 220;
      h = 120;
      seatCount = 6;
    }
    let label = TABLE_SHAPE_LABELS[shape] ?? 'Table';
    let t = new Table({
      name: `${label} ${n}`,
      shape,
      seatCount,
      seatingStyle: style,
      x,
      y,
      width: w,
      height: h,
      rotation: 0,
      z: this.nextZ(),
    });
    this.args.model.tables = [...this.tables, t];
    this.selectTable(keyOf(t));
    this.pushUndo(
      () => {
        this.args.model.tables = this.tables.filter((x) => x !== t);
        this.deselect();
      },
      () => {
        this.args.model.tables = [...this.tables, t];
      },
    );
  };
  @tracked addBranch: string | null = null;
  private branchTimer: ReturnType<typeof setTimeout> | null = null;
  openBranch = (name: string) => {
    if (this.branchTimer) clearTimeout(this.branchTimer);
    this.addBranch = name;
  };
  scheduleCloseBranch = () => {
    if (this.branchTimer) clearTimeout(this.branchTimer);
    this.branchTimer = setTimeout(() => (this.addBranch = null), 220);
  };
  toggleAddMenu = () => {
    this.addMenuOpen = !this.addMenuOpen;
    this.addBranch = null;
    this.templateMenuOpen = false;
  };
  closeAddMenu = () => {
    this.addMenuOpen = false;
    this.addBranch = null;
  };
  @tracked templateMenuOpen = false;
  toggleTemplateMenu = () => {
    this.templateMenuOpen = !this.templateMenuOpen;
    this.addMenuOpen = false;
    this.addBranch = null;
    if (this.templateMenuOpen) this.loadTemplates();
  };
  closeTemplateMenu = () => {
    this.templateMenuOpen = false;
    this.previewTplKey = null;
  };
  addFixture = (kind: string) => {
    this.addMenuOpen = false;
    let { x, y } = this.worldCenter();
    let d = FIXTURE_DEFAULTS[kind] ?? {
      width: 120,
      height: 120,
      color: '#c5a35c',
    };
    let f = new Fixture({
      label: FIXTURE_KINDS.find((k) => k.value === kind)?.label ?? 'Fixture',
      kind,
      pattern: 'outline',
      x,
      y,
      width: d.width,
      height: d.height,
      rotation: 0,
      color: d.color,
      z: this.nextZ(),
    });
    this.args.model.fixtures = [...this.fixtures, f];
    this.selectFixture(keyOf(f));
    this.recordAddFixture(f);
  };
  private recordAddFixture(f: Fixture) {
    this.pushUndo(
      () => {
        this.args.model.fixtures = this.fixtures.filter((x) => x !== f);
        this.deselect();
      },
      () => {
        this.args.model.fixtures = [...this.fixtures, f];
      },
    );
  }
  renameTable = (e: Event) => {
    let t = this.selectedTable;
    if (t) this.commitTableName(t, (e.target as HTMLInputElement).value);
  };
  setShape = (shape: string) => {
    let t = this.selectedTable;
    if (!t) return;
    let b = {
      s: t.shape,
      w: t.width,
      h: t.height,
      r: t.rows,
      c: t.cols,
      n: t.seatCount,
    };
    t.shape = shape;
    if (shape === 'section') {
      let rows = t.rows || 5;
      let cols = t.cols || 6;
      t.rows = rows;
      t.cols = cols;
      t.seatCount = rows * cols;
      let size = sectionSize(rows, cols);
      t.width = size.w;
      t.height = size.h;
    } else if (shape === 'rect' || shape === 'oval') {
      t.width = Math.max(t.width || 150, 220);
      t.height = 120;
    } else if (shape === 'curved') {
      t.width = Math.max(t.width || 150, 260);
      t.height = 120;
    } else {
      t.height = t.width || 150;
    }
    let a = {
      s: t.shape,
      w: t.width,
      h: t.height,
      r: t.rows,
      c: t.cols,
      n: t.seatCount,
    };
    this.pushUndo(
      () => {
        t!.shape = b.s;
        t!.width = b.w;
        t!.height = b.h;
        t!.rows = b.r;
        t!.cols = b.c;
        t!.seatCount = b.n;
      },
      () => {
        t!.shape = a.s;
        t!.width = a.w;
        t!.height = a.h;
        t!.rows = a.r;
        t!.cols = a.c;
        t!.seatCount = a.n;
      },
    );
  };
  private bumpSection = (dRows: number, dCols: number) => {
    let t = this.selectedTable;
    if (!t) return;
    let br = t.rows || 0;
    let bc = t.cols || 0;
    let bn = t.seatCount || 0;
    let rows = Math.max(1, br + dRows);
    let cols = Math.max(1, bc + dCols);
    if (rows === br && cols === bc) return;
    let apply = () => {
      t!.rows = rows;
      t!.cols = cols;
      t!.seatCount = rows * cols;
    };
    apply();
    this.pushUndo(() => {
      t!.rows = br;
      t!.cols = bc;
      t!.seatCount = bn;
    }, apply);
  };
  incRows = () => this.bumpSection(1, 0);
  decRows = () => this.bumpSection(-1, 0);
  incCols = () => this.bumpSection(0, 1);
  decCols = () => this.bumpSection(0, -1);
  setFacing = (deg: number) => {
    let t = this.selectedTable;
    if (!t) return;
    this.recordSet((v) => (t!.rotation = v), t.rotation || 0, deg);
  };
  facingIs = (deg: number): boolean =>
    (this.selectedTable?.rotation || 0) === deg;
  seatOrders = SEAT_ORDERS;
  setSeatOrder = (order: SeatOrder) => {
    let t = this.selectedTable;
    if (!t) return;
    this.recordSet(
      (v) => (t!.seatOrder = v),
      (t.seatOrder as SeatOrder) || 'lr-tb',
      order,
    );
  };
  seatOrderIs = (order: SeatOrder): boolean =>
    ((this.selectedTable?.seatOrder as SeatOrder) || 'lr-tb') === order;
  setSeatingStyle = (style: string) => {
    let t = this.selectedTable;
    if (!t) return;
    this.recordSet((v) => (t!.seatingStyle = v), t.seatingStyle, style);
  };
  seatingStyleIs = (style: string): boolean =>
    (this.selectedTable?.seatingStyle || 'around') === style;
  get showSeatingStyle(): boolean {
    let s = this.selectedTable?.shape;
    return s === 'rect' || s === 'oval';
  }
  setSelectionColor = (color: string) => {
    let tables = this.selectedTables;
    let fixtures = this.selectedFixtures;
    if (!tables.length && !fixtures.length) return;
    let prevT = tables.map((t) => t.themeColor);
    let prevF = fixtures.map((f) => f.color);
    let apply = () => {
      tables.forEach((t) => (t.themeColor = color));
      fixtures.forEach((f) => (f.color = color));
    };
    apply();
    this.pushUndo(() => {
      tables.forEach((t, i) => (t.themeColor = prevT[i]));
      fixtures.forEach((f, i) => (f.color = prevF[i]));
    }, apply);
  };
  selectionColorCommit = (e: Event) => {
    this.setSelectionColor((e.target as HTMLInputElement).value);
  };
  get selectionColorValue(): string {
    let t = this.selectedTables[0];
    if (t?.themeColor) return t.themeColor;
    let f = this.selectedFixtures[0];
    return f?.color || '#c5a35c';
  }
  clearSelectionSeats = () => {
    let tables = this.selectedTables.filter(
      (t) => (t.seatedGuests ?? []).length,
    );
    if (!tables.length) return;
    this.recordSeatChange(() => {
      tables.forEach((t) => {
        t.seatedGuests = [];
        t.seatSlots = [];
      });
    });
  };
  get selectionHasSeated(): boolean {
    return this.selectedTables.some((t) => (t.seatedGuests ?? []).length > 0);
  }
  setSelectionShape = (shape: string) => {
    let tables = this.selectedTables;
    if (!tables.length) return;
    let prev = tables.map((t) => ({ s: t.shape, w: t.width, h: t.height }));
    let apply = () => {
      tables.forEach((t) => {
        t.shape = shape;
        if (shape === 'rect' || shape === 'oval') {
          t.width = Math.max(t.width || 150, 220);
          t.height = 120;
        } else if (shape === 'curved') {
          t.width = Math.max(t.width || 150, 260);
          t.height = 120;
        } else {
          t.height = t.width || 150;
        }
      });
    };
    apply();
    this.pushUndo(() => {
      tables.forEach((t, i) => {
        t.shape = prev[i].s;
        t.width = prev[i].w;
        t.height = prev[i].h;
      });
    }, apply);
  };
  incSeats = () => {
    let t = this.selectedTable;
    if (!t) return;
    let b = t.seatCount || 0;
    this.recordSet((v) => (t!.seatCount = v), b, b + 1);
  };
  decSeats = () => {
    let t = this.selectedTable;
    if (!t) return;
    let b = t.seatCount || 0;
    if (b <= 0) return;
    this.recordSet((v) => (t!.seatCount = v), b, b - 1);
  };
  seatsInput = (e: Event) => {
    let t = this.selectedTable;
    let el = e.target as HTMLInputElement;
    if (!t) return;
    let b = t.seatCount || 0;
    let raw = parseInt(el.value, 10);
    let next = Number.isFinite(raw) ? Math.min(Math.max(raw, 0), 99) : b;
    el.value = String(next);
    if (next !== b) this.recordSet((v) => (t!.seatCount = v), b, next);
  };
  rowsInput = (e: Event) => this.gridInput(e, 'rows');
  colsInput = (e: Event) => this.gridInput(e, 'cols');
  private gridInput = (e: Event, axis: 'rows' | 'cols') => {
    let t = this.selectedTable;
    let el = e.target as HTMLInputElement;
    if (!t) return;
    let cur = (axis === 'rows' ? t.rows : t.cols) || 0;
    let raw = parseInt(el.value, 10);
    let next = Number.isFinite(raw)
      ? Math.min(Math.max(raw, 1), 60)
      : Math.max(1, cur);
    el.value = String(next);
    this.bumpSection(
      axis === 'rows' ? next - cur : 0,
      axis === 'cols' ? next - cur : 0,
    );
  };
  toggleVip = () => {
    let t = this.selectedTable;
    if (!t) return;
    this.recordSet((v) => (t!.vip = v), !!t.vip, !t.vip);
  };
  setTableRank = (raw: number) => {
    let t = this.selectedTable;
    if (!t) return;
    let n = this.tables.length;
    let next =
      Number.isFinite(raw) && raw >= 1 ? Math.min(Math.floor(raw), n) : 0;
    this.recordSet((v) => (t!.rank = v), t.rank || 0, next);
  };
  pinTableRankInput = (e: Event) => {
    let val = parseInt((e.target as HTMLInputElement).value, 10);
    this.setTableRank(val);
  };
  clearTableRank = () => this.setTableRank(0);
  get selectedTablePinned(): boolean {
    let r = this.selectedTable?.rank;
    return !!r && r >= 1;
  }
  get selectedTableRank(): number {
    let t = this.selectedTable;
    return t ? (this.tableRank.get(t) ?? 0) : 0;
  }
  get hasFloorPlan(): boolean {
    return !!this.args.model?.floorPlanURL;
  }
  @tracked private floorImgBroken = false;
  @tracked private floorImgRetry = 0;
  private get floorPlanSrc(): string | undefined {
    let url = this.args.model?.floorPlanURL;
    if (!url || !this.floorImgRetry) return url;
    return `${url}${url.includes('?') ? '&' : '?'}retry=${this.floorImgRetry}`;
  }
  onFloorImgError = () => {
    this.floorImgBroken = true;
  };
  onFloorImgLoad = () => {
    this.floorImgBroken = false;
  };
  refreshFloorImg = () => {
    this.floorImgBroken = false;
    this.floorImgRetry++;
  };
  private screenBox(t: Table): {
    cx: number;
    cy: number;
    w: number;
    h: number;
  } {
    let w = t.width || 0;
    let h = t.height || 0;
    let rot = (((t.rotation || 0) % 180) + 180) % 180 !== 0;
    return {
      cx: (t.x || 0) + w / 2,
      cy: (t.y || 0) + h / 2,
      w: rot ? h : w,
      h: rot ? w : h,
    };
  }
  private sectionsNeedFit(): boolean {
    let m = this.args.model;
    let px = m?.floorPlanX || 0;
    let py = m?.floorPlanY || 0;
    let pw = m?.floorPlanWidth || 0;
    let ph = m?.floorPlanHeight || 0;
    if (!pw || !ph) return false;
    let secs = this.tables.filter((t) => t.shape === 'section');
    let boxes = secs.map((t) => this.screenBox(t));
    for (let b of boxes) {
      if (
        b.cx - b.w / 2 < px ||
        b.cx + b.w / 2 > px + pw ||
        b.cy - b.h / 2 < py ||
        b.cy + b.h / 2 > py + ph
      )
        return true;
    }
    for (let i = 0; i < boxes.length; i++)
      for (let j = i + 1; j < boxes.length; j++) {
        let a = boxes[i];
        let c = boxes[j];
        if (
          Math.abs(a.cx - c.cx) < (a.w + c.w) / 2 - 1 &&
          Math.abs(a.cy - c.cy) < (a.h + c.h) / 2 - 1
        )
          return true;
      }
    return false;
  }
  private captureSections(secs: Table[]) {
    return secs.map((t) => ({
      t,
      w: t.width || 0,
      h: t.height || 0,
      x: t.x || 0,
      y: t.y || 0,
      rows: t.rows || 0,
      cols: t.cols || 0,
      seatCount: t.seatCount || 0,
      guests: [...((t.seatedGuests ?? []) as Guest[])],
      slots: this.slotsOf(t),
    }));
  }
  private restoreSections(
    snap: ReturnType<TableSeatingPlannerIsolated['captureSections']>,
  ) {
    for (let s of snap) {
      s.t.width = s.w;
      s.t.height = s.h;
      s.t.x = s.x;
      s.t.y = s.y;
      s.t.rows = s.rows;
      s.t.cols = s.cols;
      s.t.seatCount = s.seatCount;
      s.t.seatedGuests = [...s.guests];
      s.t.seatSlots = [...s.slots];
    }
  }
  private layoutSeatingSections(silent = false): boolean {
    let m = this.args.model;
    let px = m?.floorPlanX || 0;
    let py = m?.floorPlanY || 0;
    let pw = m?.floorPlanWidth || 0;
    let ph = m?.floorPlanHeight || 0;
    if (!pw || !ph) {
      if (!silent) this.showToast('Add a floor-plan image first');
      return false;
    }
    let sections = this.tables.filter((t) => t.shape === 'section');
    if (!sections.length) {
      if (!silent) this.showToast('No seating sections to fit');
      return false;
    }
    const SEAT = 34; // per-chair spacing; matches sectionSize()
    let rotated = (t: Table) => (((t.rotation || 0) % 180) + 180) % 180 !== 0;
    let margin = 0.06;
    let ax = px + pw * margin;
    let ay = py + ph * margin;
    let aw = pw * (1 - 2 * margin);
    let ah = ph * (1 - 2 * margin);
    let gap = Math.min(24, ah * 0.05);
    let before = this.captureSections(sections);
    let entries = sections
      .map((t) => ({ t, box: this.screenBox(t) }))
      .sort((a, b) => a.box.cx - b.box.cx || a.box.cy - b.box.cy);
    let columns: (typeof entries)[] = [];
    for (let e of entries) {
      let col = columns.find((c) =>
        c.some((o) => {
          let overlap =
            Math.min(o.box.cx + o.box.w / 2, e.box.cx + e.box.w / 2) -
            Math.max(o.box.cx - o.box.w / 2, e.box.cx - e.box.w / 2);
          return overlap > Math.min(o.box.w, e.box.w) / 2;
        }),
      );
      if (col) col.push(e);
      else columns.push([e]);
    }
    let colCx = columns.map(
      (c) => c.reduce((s, e) => s + e.box.cx, 0) / c.length,
    );
    let bounds = columns.map((_, i) => ({
      left: i === 0 ? ax : (colCx[i - 1] + colCx[i]) / 2,
      right: i === columns.length - 1 ? ax + aw : (colCx[i] + colCx[i + 1]) / 2,
    }));
    for (let ci = 0; ci < columns.length; ci++) {
      let { left, right } = bounds[ci];
      let colW = Math.max(SEAT, right - left);
      let ordered = [...columns[ci]].sort(
        (a, b) => a.box.cy - b.box.cy || a.box.cx - b.box.cx,
      );
      let plan = ordered.map(({ t, box }) => {
        let rot = rotated(t);
        let snug = sectionSize(t.rows || 0, t.cols || 0);
        let snugH = rot ? snug.w : snug.h;
        let w = Math.min(Math.max(box.w, rot ? snug.h : snug.w), colW);
        let h = Math.max(box.h, snugH);
        return { t, box, rot, w, h, snugH };
      });
      let gaps = gap * (plan.length - 1);
      let totalH = plan.reduce((s, p) => s + p.h, 0) + gaps;
      if (totalH > ah) {
        let snugTotal = plan.reduce((s, p) => s + p.snugH, 0);
        let slack = totalH - gaps - snugTotal;
        if (snugTotal + gaps <= ah && slack > 0) {
          let keep = (ah - gaps - snugTotal) / slack;
          for (let p of plan) p.h = p.snugH + (p.h - p.snugH) * keep;
        } else {
          let scale = (ah - gaps) / Math.max(1, totalH - gaps);
          for (let p of plan) p.h = Math.max(SEAT, p.h * scale);
        }
      }
      let remaining = plan.reduce((s, p) => s + p.h, 0) + gaps;
      let cursorY = ay;
      for (let p of plan) {
        let { t, box, rot, w, h } = p;
        let top = Math.min(
          Math.max(box.cy - h / 2, cursorY),
          ay + ah - remaining,
        );
        let cx = Math.min(Math.max(box.cx, left + w / 2), right - w / 2);
        let ew = rot ? h : w;
        let eh = rot ? w : h;
        t.width = Math.round(ew);
        t.height = Math.round(eh);
        t.x = Math.round(cx - ew / 2);
        t.y = Math.round(top + h / 2 - eh / 2);
        cursorY = top + h + gap;
        remaining -= h + gap;
      }
    }
    let after = this.captureSections(sections);
    this.pushUndo(
      () => this.restoreSections(before),
      () => this.restoreSections(after),
    );
    if (!silent) this.showToast('Fitted seating to floor plan');
    return true;
  }
  grabRotate = (kind: 'table' | 'fixture', id: string, evt: Event) => {
    let e = evt as PointerEvent;
    e.stopPropagation();
    e.preventDefault();
    let m =
      kind === 'table'
        ? this.tables.find((x) => keyOf(x) === id)
        : this.fixtures.find((x) => keyOf(x) === id);
    if (!m || m.locked) return;
    this.selectOnly(id);
    let rect = this.canvasEl?.getBoundingClientRect();
    this.rotCx =
      (rect?.left ?? 0) +
      this.panX +
      ((m.x || 0) + (m.width || 0) / 2) * this.zoom;
    this.rotCy =
      (rect?.top ?? 0) +
      this.panY +
      ((m.y || 0) + (m.height || 0) / 2) * this.zoom;
    this.dragMode = 'rotate';
    this.rotEl = m;
    this.rotStart = Math.atan2(e.clientY - this.rotCy, e.clientX - this.rotCx);
    this.rotOrig = m.rotation || 0;
    this.attachDragListeners();
  };
  themeSwatches = [
    { value: '#141b33', label: 'Navy' },
    { value: '#c5a35c', label: 'Gold' },
    { value: '#fdfaf2', label: 'Cream' },
  ];
  fixtureColorIs = (v: string): boolean =>
    (this.selectedFixture?.color || '#c5a35c').toLowerCase() ===
    v.toLowerCase();
  clearSeats = () => {
    let t = this.selectedTable;
    if (t && (t.seatedGuests ?? []).length)
      this.recordSeatChange(() => {
        t!.seatedGuests = [];
        t!.seatSlots = [];
      });
  };
  duplicateTable = () => {
    let t = this.selectedTable;
    if (!t) return;
    let copy = new Table({
      name: `${t.name} (copy)`,
      shape: t.shape,
      seatCount: t.seatCount,
      seatingStyle: t.seatingStyle,
      rows: t.rows,
      cols: t.cols,
      seatOrder: t.seatOrder,
      x: (t.x || 0) + 40,
      y: (t.y || 0) + 40,
      width: t.width,
      height: t.height,
      rotation: t.rotation,
      themeColor: t.themeColor,
      vip: t.vip,
      note: t.note,
      reservedCategories: [...(t.reservedCategories ?? [])],
      z: this.nextZ(),
    });
    this.args.model.tables = [...this.tables, copy];
    this.selectTable(keyOf(copy));
    this.pushUndo(
      () => {
        this.args.model.tables = this.tables.filter((x) => x !== copy);
        this.deselect();
      },
      () => {
        this.args.model.tables = [...this.tables, copy];
      },
    );
  };
  removeTable = () => {
    let t = this.selectedTable;
    if (!t) return;
    let idx = this.tables.indexOf(t);
    this.args.model.tables = this.tables.filter((x) => x !== t);
    this.deselect();
    this.pushUndo(
      () => {
        let arr = [...this.tables];
        arr.splice(idx, 0, t!);
        this.args.model.tables = arr;
      },
      () => {
        this.args.model.tables = this.tables.filter((x) => x !== t);
      },
    );
  };
  setFxColor = (color: string) => {
    let f = this.selectedFixture;
    if (!f) return;
    this.recordSet((v) => (f!.color = v), f.color, color);
  };
  fxColorInput = (e: Event) => {
    let f = this.selectedFixture;
    if (!f) return;
    this.liveColor = {
      key: keyOf(f),
      color: (e.target as HTMLInputElement).value,
    };
  };
  fxColorCommit = (e: Event) => {
    this.liveColor = null;
    this.setFxColor((e.target as HTMLInputElement).value);
  };
  get selectedFxFill() {
    let f = this.selectedFixture;
    return f ? this.effColor(f, f.color || '#c5a35c') : '#c5a35c';
  }
  get selectedFxArtStyle() {
    let f = this.selectedFixture;
    let w = f ? Math.max(1, this.effW(f, f.width || 100)) : 1;
    let h = f ? Math.max(1, this.effH(f, f.height || 100)) : 1;
    return htmlSafe(
      w >= h
        ? `aspect-ratio: ${w} / ${h}; width: min(100%, 220px);`
        : `aspect-ratio: ${w} / ${h}; height: 220px;`,
    );
  }
  renameFixture = (e: Event) => {
    let f = this.selectedFixture;
    if (f) this.commitFixtureLabel(f, (e.target as HTMLInputElement).value);
  };
  duplicateFixture = () => {
    let f = this.selectedFixture;
    if (!f) return;
    let copy = new Fixture({
      label: `${f.label} (copy)`,
      kind: f.kind,
      pattern: f.pattern,
      x: (f.x || 0) + 30,
      y: (f.y || 0) + 30,
      width: f.width,
      height: f.height,
      rotation: f.rotation,
      color: f.color,
      z: this.nextZ(),
    });
    this.args.model.fixtures = [...this.fixtures, copy];
    this.selectFixture(keyOf(copy));
    this.recordAddFixture(copy);
  };
  removeFixture = () => {
    let f = this.selectedFixture;
    if (!f) return;
    let idx = this.fixtures.indexOf(f);
    this.args.model.fixtures = this.fixtures.filter((x) => x !== f);
    this.deselect();
    this.pushUndo(
      () => {
        let arr = [...this.fixtures];
        arr.splice(idx, 0, f!);
        this.args.model.fixtures = arr;
      },
      () => {
        this.args.model.fixtures = this.fixtures.filter((x) => x !== f);
      },
    );
  };
  zoomIn = () => {
    this.userMovedView = true;
    this.zoom = Math.min(2.5, this.zoom + 0.1);
  };
  zoomOut = () => {
    this.userMovedView = true;
    this.zoom = Math.max(0.4, this.zoom - 0.1);
  };
  resetZoom = () => {
    this.userMovedView = true;
    this.zoom = 1;
    this.panX = 60;
    this.panY = 40;
  };
  private canvasEl: HTMLElement | null = null;
  private userMovedView = false;
  registerCanvas = modifier((el: Element) => {
    this.canvasEl = el as HTMLElement;
    let canvas = el as HTMLElement;
    let autoFit = () => {
      if (this.userMovedView) return;
      let sized = canvas.clientWidth > 50 && canvas.clientHeight > 50;
      let hasContent =
        this.tables.length > 0 || this.fixtures.length > 0 || this.hasFloorPlan;
      if (sized && hasContent) this.applyFit();
    };
    let rafId = 0;
    let tries = 0;
    let attempt = () => {
      if (this.userMovedView) return;
      autoFit();
      let hasContent =
        this.tables.length > 0 || this.fixtures.length > 0 || this.hasFloorPlan;
      if (!hasContent && tries++ < 1800) rafId = setTimeout(attempt, 16) as any;
    };
    rafId = setTimeout(attempt, 16) as any;
    let ro = new ResizeObserver(autoFit);
    ro.observe(canvas);
    return () => {
      clearTimeout(rafId);
      ro.disconnect();
    };
  });
  fitView = () => {
    this.userMovedView = true;
    this.applyFit();
  };
  private applyFit = () => {
    let el = this.canvasEl;
    let items: Array<Table | Fixture> = [...this.tables, ...this.fixtures];
    if (!el || (!items.length && !this.hasFloorPlan)) {
      this.resetZoom();
      return;
    }
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (let it of items) {
      let x = it.x || 0;
      let y = it.y || 0;
      let w = it.width || 100;
      let h = it.height || 100;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x + w);
      maxY = Math.max(maxY, y + h);
    }
    if (this.hasFloorPlan) {
      let m = this.args.model;
      let x = m.floorPlanX || 0;
      let y = m.floorPlanY || 0;
      let w = m.floorPlanWidth || 800;
      let h = m.floorPlanHeight || 600;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x + w);
      maxY = Math.max(maxY, y + h);
    }
    let pad = 90; // room for seat chips + name tags around the bounds
    let bw = maxX - minX + pad * 2;
    let bh = maxY - minY + pad * 2;
    let cw = el.clientWidth || 1;
    let ch = el.clientHeight || 1;
    let z = Math.min(2.5, Math.max(0.4, Math.min(cw / bw, ch / bh)));
    let cx = (minX + maxX) / 2;
    let cy = (minY + maxY) / 2;
    this.zoom = z;
    this.panX = cw / 2 - cx * z;
    this.panY = ch / 2 - cy * z;
  };
  onWheel = (evt: Event) => {
    let e = evt as WheelEvent;
    e.preventDefault();
    this.userMovedView = true;
    let next = this.zoom - Math.sign(e.deltaY) * 0.08;
    this.zoom = Math.min(2.5, Math.max(0.4, next));
  };
  onCanvasDown = (evt: Event) => {
    let e = evt as PointerEvent;
    let target = e.target as HTMLElement;
    if (target.closest('[data-table]') || target.closest('[data-fixture]'))
      return;
    this.addMenuOpen = false;
    this.popoverTableKey = null;
    if (this.spaceDown || e.button === 1) {
      this.userMovedView = true;
      this.dragMode = 'pan';
      this.startPX = e.clientX;
      this.startPY = e.clientY;
      this.origX = this.panX;
      this.origY = this.panY;
      this.attachDragListeners();
      return;
    }
    if (!e.shiftKey) this.deselect();
    let rect = this.canvasEl?.getBoundingClientRect();
    this.mStartX = e.clientX - (rect?.left ?? 0);
    this.mStartY = e.clientY - (rect?.top ?? 0);
    this.dragMode = 'marquee';
    this.marquee = { x: this.mStartX, y: this.mStartY, w: 0, h: 0 };
    this.startPX = e.clientX;
    this.startPY = e.clientY;
    this.attachDragListeners();
  };
  private beginMove(e: PointerEvent) {
    this.dragMode = 'move';
    this.startPX = e.clientX;
    this.startPY = e.clientY;
    this.dragSet = [];
    for (let t of this.tables)
      if (this.isSelected(keyOf(t)) && !t.locked)
        this.dragSet.push({ el: t, ox: t.x || 0, oy: t.y || 0 });
    for (let f of this.fixtures)
      if (this.isSelected(keyOf(f)) && !f.locked)
        this.dragSet.push({ el: f, ox: f.x || 0, oy: f.y || 0 });
    this.dragFloor = this.floorSelected;
    this.floorOX = this.args.model?.floorPlanX || 0;
    this.floorOY = this.args.model?.floorPlanY || 0;
    this.attachDragListeners();
  }
  grabTable = (id: string, e: PointerEvent) => {
    e.stopPropagation();
    let t = this.tables.find((x) => keyOf(x) === id);
    if (!t) return;
    if (e.shiftKey) {
      this.toggleSel(id);
      return;
    }
    if (!this.isSelected(id)) this.selectOnly(id);
    if (t.locked) return;
    this.beginMove(e);
  };
  grabFixture = (id: string, e: PointerEvent) => {
    e.stopPropagation();
    let f = this.fixtures.find((x) => keyOf(x) === id);
    if (!f) return;
    if (e.shiftKey) {
      this.toggleSel(id);
      return;
    }
    if (!this.isSelected(id)) this.selectOnly(id);
    if (f.locked) return;
    this.beginMove(e);
  };
  grabResize = (
    kind: 'table' | 'fixture',
    id: string,
    edge: string,
    evt: Event,
  ) => {
    let e = evt as PointerEvent;
    e.stopPropagation();
    e.preventDefault();
    let m =
      kind === 'table'
        ? this.tables.find((x) => keyOf(x) === id)
        : this.fixtures.find((x) => keyOf(x) === id);
    if (!m || m.locked) return;
    if (kind === 'table') this.selectTable(id);
    else this.selectFixture(id);
    this.dragMode = 'resize';
    this.resizeKind = kind;
    this.dragId = id;
    this.dragTarget = m;
    this.resizeEdge = edge;
    this.startPX = e.clientX;
    this.startPY = e.clientY;
    this.origW = m.width || 100;
    this.origH = m.height || 100;
    this.dragRot = m.rotation || 0;
    this.attachDragListeners();
  };
  private attachDragListeners() {
    document.addEventListener('pointermove', this.onDragMove);
    document.addEventListener('pointerup', this.onDragUp);
  }
  private detachDragListeners() {
    document.removeEventListener('pointermove', this.onDragMove);
    document.removeEventListener('pointerup', this.onDragUp);
  }
  onDragMove = (e: PointerEvent) => {
    if (this.dragMode === 'pan') {
      this.panX = this.origX + (e.clientX - this.startPX);
      this.panY = this.origY + (e.clientY - this.startPY);
      return;
    }
    if (this.dragMode === 'floorplan') {
      let dx = (e.clientX - this.startPX) / this.zoom;
      let dy = (e.clientY - this.startPY) / this.zoom;
      this.liveMove = {
        keys: [],
        dx: Math.round(dx),
        dy: Math.round(dy),
        floor: true,
      };
      return;
    }
    if (this.dragMode === 'rotate') {
      if (!this.rotEl) return;
      let a = Math.atan2(e.clientY - this.rotCy, e.clientX - this.rotCx);
      let deg = this.rotOrig + ((a - this.rotStart) * 180) / Math.PI;
      deg = ((deg % 360) + 360) % 360;
      if (e.shiftKey) deg = Math.round(deg / 15) * 15; // snap with Shift
      this.liveRotate = { key: keyOf(this.rotEl), deg: Math.round(deg) };
      return;
    }
    if (this.dragMode === 'resize') {
      let dxs = (e.clientX - this.startPX) / this.zoom;
      let dys = (e.clientY - this.startPY) / this.zoom;
      let rad = (-this.dragRot * Math.PI) / 180;
      let lx = dxs * Math.cos(rad) - dys * Math.sin(rad);
      let ly = dxs * Math.sin(rad) + dys * Math.cos(rad);
      let isFloor = this.resizeKind === 'floorplan';
      let min = isFloor ? 60 : 30;
      let edge = this.resizeEdge;
      let w = this.origW;
      let h = this.origH;
      let dx = 0;
      let dy = 0;
      if (isFloor) {
        w = Math.max(min, Math.round(this.origW + lx));
        h = Math.max(min, Math.round(this.origH + ly));
      } else {
        if (edge.includes('e')) w = Math.max(min, Math.round(this.origW + lx));
        if (edge.includes('w')) w = Math.max(min, Math.round(this.origW - lx));
        if (edge.includes('s')) h = Math.max(min, Math.round(this.origH + ly));
        if (edge.includes('n')) h = Math.max(min, Math.round(this.origH - ly));
        if (e.shiftKey && this.origW > 0 && this.origH > 0) {
          let aspect = this.origW / this.origH;
          let hasX = edge.includes('e') || edge.includes('w');
          let hasY = edge.includes('n') || edge.includes('s');
          let driveByWidth = hasX && hasY ? Math.abs(lx) >= Math.abs(ly) : hasX;
          if (driveByWidth) h = Math.max(min, Math.round(w / aspect));
          else w = Math.max(min, Math.round(h * aspect));
        }
        let kx = edge.includes('e') ? -0.5 : edge.includes('w') ? 0.5 : 0;
        let ky = edge.includes('s') ? -0.5 : edge.includes('n') ? 0.5 : 0;
        let dW = this.origW - w;
        let dH = this.origH - h;
        let th = (this.dragRot * Math.PI) / 180;
        let c = Math.cos(th);
        let s = Math.sin(th);
        let ox = kx * dW;
        let oy = ky * dH;
        dx = dW / 2 + (ox * c - oy * s);
        dy = dH / 2 + (ox * s + oy * c);
      }
      let key = isFloor ? '__floor__' : this.dragId;
      if (key) this.liveSize = { key, w, h, dx, dy };
      return;
    }
    if (this.dragMode === 'marquee') {
      let rect = this.canvasEl?.getBoundingClientRect();
      let cx = e.clientX - (rect?.left ?? 0);
      let cy = e.clientY - (rect?.top ?? 0);
      this.marquee = {
        x: Math.min(this.mStartX, cx),
        y: Math.min(this.mStartY, cy),
        w: Math.abs(cx - this.mStartX),
        h: Math.abs(cy - this.mStartY),
      };
      this.marqueeHitKeys = this.hitsInMarquee();
      return;
    }
    if (this.dragMode === 'move') {
      let dx = Math.round((e.clientX - this.startPX) / this.zoom);
      let dy = Math.round((e.clientY - this.startPY) / this.zoom);
      this.liveMove = {
        keys: this.dragSet.map((it) => keyOf(it.el)),
        dx,
        dy,
        floor: this.dragFloor,
      };
      return;
    }
  };
  onDragUp = () => {
    let mode = this.dragMode;
    if (mode === 'move') {
      let dx = this.liveMove?.dx ?? 0;
      let dy = this.liveMove?.dy ?? 0;
      for (let it of this.dragSet) {
        it.el.x = it.ox + dx;
        it.el.y = it.oy + dy;
      }
      let m = this.args.model;
      if (this.dragFloor) {
        m.floorPlanX = this.floorOX + dx;
        m.floorPlanY = this.floorOY + dy;
      }
      let snap = this.dragSet.map((it) => ({
        el: it.el,
        bx: it.ox,
        by: it.oy,
        ax: it.el.x || 0,
        ay: it.el.y || 0,
      }));
      let floor = this.dragFloor
        ? {
            bx: this.floorOX,
            by: this.floorOY,
            ax: m.floorPlanX || 0,
            ay: m.floorPlanY || 0,
          }
        : null;
      let changed =
        snap.some((s) => s.bx !== s.ax || s.by !== s.ay) ||
        (floor && (floor.bx !== floor.ax || floor.by !== floor.ay));
      if (changed) {
        this.pushUndo(
          () => {
            for (let s of snap) {
              s.el.x = s.bx;
              s.el.y = s.by;
            }
            if (floor) {
              m.floorPlanX = floor.bx;
              m.floorPlanY = floor.by;
            }
          },
          () => {
            for (let s of snap) {
              s.el.x = s.ax;
              s.el.y = s.ay;
            }
            if (floor) {
              m.floorPlanX = floor.ax;
              m.floorPlanY = floor.ay;
            }
          },
        );
      }
    } else if (mode === 'marquee') {
      this.commitMarquee();
    } else if (mode === 'rotate') {
      let el = this.rotEl;
      if (el) {
        if (this.liveRotate && this.liveRotate.key === keyOf(el)) {
          el.rotation = this.liveRotate.deg;
        }
        let b = this.rotOrig;
        let a = el.rotation || 0;
        if (b !== a) {
          let m = el;
          this.pushUndo(
            () => {
              m.rotation = b;
            },
            () => {
              m.rotation = a;
            },
          );
        }
      }
    } else if (mode === 'resize') {
      let ls = this.liveSize;
      if (this.resizeKind === 'floorplan') {
        let fp = this.args.model;
        let bw = this.origW;
        let bh = this.origH;
        let aw = ls ? ls.w : fp.floorPlanWidth || 0;
        let ah = ls ? ls.h : fp.floorPlanHeight || 0;
        if (ls) {
          fp.floorPlanWidth = aw;
          fp.floorPlanHeight = ah;
        }
        if (bw !== aw || bh !== ah) {
          this.pushUndo(
            () => {
              fp.floorPlanWidth = bw;
              fp.floorPlanHeight = bh;
            },
            () => {
              fp.floorPlanWidth = aw;
              fp.floorPlanHeight = ah;
            },
          );
        }
      } else {
        let target = this.dragTarget;
        if (target && ls && ls.key === keyOf(target)) {
          let bw = this.origW;
          let bh = this.origH;
          let bx = target.x || 0;
          let by = target.y || 0;
          let aw = ls.w;
          let ah = ls.h;
          let nx = bx + ls.dx;
          let ny = by + ls.dy;
          target.width = aw;
          target.height = ah;
          target.x = nx;
          target.y = ny;
          if (bw !== aw || bh !== ah || bx !== nx || by !== ny) {
            let mt = target;
            this.pushUndo(
              () => {
                mt.width = bw;
                mt.height = bh;
                mt.x = bx;
                mt.y = by;
              },
              () => {
                mt.width = aw;
                mt.height = ah;
                mt.x = nx;
                mt.y = ny;
              },
            );
          }
        }
      }
    }
    this.dragMode = 'none';
    this.dragId = null;
    this.dragTarget = null;
    this.dragSet = [];
    this.dragFloor = false;
    this.rotEl = null;
    this.marquee = null;
    this.marqueeHitKeys = [];
    this.liveMove = null;
    this.liveSize = null;
    this.liveRotate = null;
    this.detachDragListeners();
  };
  private hitsInMarquee(): string[] {
    let mq = this.marquee;
    if (!mq) return [];
    let x1 = (mq.x - this.panX) / this.zoom;
    let y1 = (mq.y - this.panY) / this.zoom;
    let x2 = (mq.x + mq.w - this.panX) / this.zoom;
    let y2 = (mq.y + mq.h - this.panY) / this.zoom;
    let hit = (ex: number, ey: number, ew: number, eh: number) =>
      !(ex > x2 || ex + ew < x1 || ey > y2 || ey + eh < y1);
    let keys: string[] = [];
    for (let t of this.tables)
      if (hit(t.x || 0, t.y || 0, t.width || 150, t.height || 150))
        keys.push(keyOf(t));
    for (let f of this.fixtures)
      if (hit(f.x || 0, f.y || 0, f.width || 100, f.height || 100))
        keys.push(keyOf(f));
    return keys;
  }
  private commitMarquee() {
    let mq = this.marquee;
    if (!mq || (mq.w < 4 && mq.h < 4)) return;
    let keys = new Set([...this.selectedKeys, ...this.hitsInMarquee()]);
    this.selectedKeys = [...keys];
  }
  deleteSelected = () => {
    if (!this.selCount) return;
    let m = this.args.model;
    let beforeT = this.tables;
    let beforeF = this.fixtures;
    let beforeFloor = m.floorPlanURL;
    let del = new Set(this.selectedKeys);
    let nt = this.tables.filter((t) => !del.has(keyOf(t)));
    let nf = this.fixtures.filter((f) => !del.has(keyOf(f)));
    let floorGone = this.floorSelected;
    m.tables = nt;
    m.fixtures = nf;
    if (floorGone) m.floorPlanURL = undefined;
    this.pushUndo(
      () => {
        m.tables = beforeT;
        m.fixtures = beforeF;
        if (floorGone) m.floorPlanURL = beforeFloor;
      },
      () => {
        m.tables = nt;
        m.fixtures = nf;
        if (floorGone) m.floorPlanURL = undefined;
      },
    );
    this.deselect();
    this.showToast('Deleted');
  };
  nudgeSelected = (dx: number, dy: number) => {
    let tabs = this.tables.filter(
      (t) => this.isSelected(keyOf(t)) && !t.locked,
    );
    let fixs = this.fixtures.filter(
      (f) => this.isSelected(keyOf(f)) && !f.locked,
    );
    let floor = this.floorSelected;
    let m = this.args.model;
    let apply = (sx: number, sy: number) => {
      for (let t of tabs) {
        t.x = (t.x || 0) + sx;
        t.y = (t.y || 0) + sy;
      }
      for (let f of fixs) {
        f.x = (f.x || 0) + sx;
        f.y = (f.y || 0) + sy;
      }
      if (floor) {
        m.floorPlanX = (m.floorPlanX || 0) + sx;
        m.floorPlanY = (m.floorPlanY || 0) + sy;
      }
    };
    apply(dx, dy);
    this.pushUndo(
      () => apply(-dx, -dy),
      () => apply(dx, dy),
    );
  };
  private snapshotSelection(): ClipItem[] {
    let items: ClipItem[] = [];
    for (let t of this.selectedTables) {
      items.push({
        kind: 'table',
        data: {
          name: t.name,
          shape: t.shape,
          seatCount: t.seatCount,
          seatingStyle: t.seatingStyle,
          rows: t.rows,
          cols: t.cols,
          seatOrder: t.seatOrder,
          x: t.x || 0,
          y: t.y || 0,
          width: t.width,
          height: t.height,
          rotation: t.rotation,
          themeColor: t.themeColor,
          vip: t.vip,
          note: t.note,
          reservedCategories: [...(t.reservedCategories ?? [])],
        },
      });
    }
    for (let f of this.selectedFixtures) {
      items.push({
        kind: 'fixture',
        data: {
          label: f.label,
          kind: f.kind,
          pattern: f.pattern,
          x: f.x || 0,
          y: f.y || 0,
          width: f.width,
          height: f.height,
          rotation: f.rotation,
          color: f.color,
        },
      });
    }
    return items;
  }
  private pasteItems = (items: ClipItem[], off: number) => {
    if (!items.length) return;
    let newTables: Table[] = [];
    let newFixtures: Fixture[] = [];
    let z = this.nextZ();
    for (let item of items) {
      if (item.kind === 'table') {
        let d = item.data;
        newTables.push(
          new Table({
            ...d,
            reservedCategories: [...d.reservedCategories],
            x: d.x + off,
            y: d.y + off,
            z: z++,
          }),
        );
      } else {
        let d = item.data;
        newFixtures.push(
          new Fixture({ ...d, x: d.x + off, y: d.y + off, z: z++ }),
        );
      }
    }
    let m = this.args.model;
    let beforeT = this.tables;
    let beforeF = this.fixtures;
    let afterT = [...beforeT, ...newTables];
    let afterF = [...beforeF, ...newFixtures];
    m.tables = afterT;
    m.fixtures = afterF;
    this.selectedKeys = [...newTables, ...newFixtures].map((o) => keyOf(o));
    this.floorSelected = false;
    this.pushUndo(
      () => {
        m.tables = beforeT;
        m.fixtures = beforeF;
        this.deselect();
      },
      () => {
        m.tables = afterT;
        m.fixtures = afterF;
      },
    );
  };
  copySelection = (): boolean => {
    let items = this.snapshotSelection();
    if (!items.length) return false;
    this.clipboard = items;
    this.pasteSeq = 0;
    this.showToast(`Copied ${items.length}`);
    return true;
  };
  cutSelection = () => {
    if (this.copySelection()) this.deleteSelected();
  };
  pasteClipboard = () => {
    if (!this.clipboard.length) return;
    this.pasteSeq += 1;
    this.pasteItems(this.clipboard, 40 * this.pasteSeq);
    this.showToast('Pasted');
  };
  duplicateSelection = () => {
    this.pasteItems(this.snapshotSelection(), 40);
  };
  get marqueeStyle() {
    let mq = this.marquee;
    if (!mq) return htmlSafe('display:none');
    return htmlSafe(
      `left:${mq.x}px;top:${mq.y}px;width:${mq.w}px;height:${mq.h}px`,
    );
  }
  resolveGuest = async (id: string): Promise<Guest | null> => {
    try {
      let g = await (this.args as any).context?.store?.get(id);
      return (g as Guest) ?? null;
    } catch {
      return null;
    }
  };
  onGuestMove = (e: PointerEvent) => {
    this.ghostX = e.clientX;
    this.ghostY = e.clientY;
    let el = document.elementFromPoint(
      e.clientX,
      e.clientY,
    ) as HTMLElement | null;
    let seat = el?.closest('[data-seat-table]') as HTMLElement | null;
    if (seat) {
      this.dropTableKey = seat.getAttribute('data-seat-table');
      this.dropSeatIndex = parseInt(
        seat.getAttribute('data-seat-index') ?? '-1',
        10,
      );
    } else {
      this.dropTableKey = null;
      this.dropSeatIndex = -1;
    }
  };
  onGuestUp = async (e: PointerEvent) => {
    let g = this.draggingGuest;
    let id = this.draggingGuestId;
    document.removeEventListener('pointermove', this.onGuestMove);
    document.removeEventListener('pointerup', this.onGuestUp);
    this.draggingGuest = null;
    this.draggingGuestId = null;
    this.dropTableKey = null;
    this.dropSeatIndex = -1;
    let el = document.elementFromPoint(
      e.clientX,
      e.clientY,
    ) as HTMLElement | null;
    let seat = el?.closest('[data-seat-table]') as HTMLElement | null;
    if (!seat) return;
    let tableId = seat.getAttribute('data-seat-table');
    let seatIndex = parseInt(seat.getAttribute('data-seat-index') ?? '0', 10);
    if (!tableId) return;
    if (!g && id) g = await this.resolveGuest(id);
    if (!g) return;
    if (!this.guests.some((x) => x === g)) {
      this.args.model.guests = [...this.guests, g];
    }
    this.assignGuest(g, tableId, seatIndex);
  };
  assignGuest = (guest: Guest, tableId: string, seatIndex: number) => {
    let target = this.tables.find((t) => keyOf(t) === tableId);
    if (!target) return;
    this.recordSeatChange(() => {
      for (let t of this.tables) {
        let arr = (t.seatedGuests ?? []) as Guest[];
        let k = arr.findIndex((x) => x === guest);
        if (k >= 0) {
          let slots = this.slotsOf(t);
          t.seatedGuests = arr.filter((_, i) => i !== k);
          t.seatSlots = slots.filter((_, i) => i !== k);
        }
      }
      let arr = [...((target!.seatedGuests ?? []) as Guest[])];
      let slots = this.slotsOf(target!);
      let occupant = slots.indexOf(seatIndex);
      if (occupant >= 0) {
        arr.splice(occupant, 1);
        slots.splice(occupant, 1);
      }
      arr.push(guest);
      slots.push(seatIndex);
      target!.seatedGuests = arr;
      target!.seatSlots = slots;
    });
  };
  grabSeatedGuest = (guest: Guest | null, e: PointerEvent) => {
    if (!guest) return;
    e.preventDefault();
    e.stopPropagation();
    this.hoverGuest = null; // hide the hover card while dragging
    this.draggingGuest = guest;
    this.draggingGuestId = (guest as any)?.id ?? null;
    this.ghostX = e.clientX;
    this.ghostY = e.clientY;
    document.addEventListener('pointermove', this.onGuestMove);
    document.addEventListener('pointerup', this.onGuestUp);
  };
  showSeatInfo = (guest: Guest | null, e: MouseEvent) => {
    if (!guest || this.draggingGuest) return;
    this.hoverGuest = guest;
    this.hoverX = e.clientX;
    this.hoverY = e.clientY;
  };
  moveSeatInfo = (evt: Event) => {
    let e = evt as MouseEvent;
    if (!this.hoverGuest) return;
    this.hoverX = e.clientX;
    this.hoverY = e.clientY;
  };
  hideSeatInfo = () => {
    this.hoverGuest = null;
  };
  freeSeat = (tableId: string, seatIndex: number) => {
    let t = this.tables.find((x) => keyOf(x) === tableId);
    if (!t) return;
    let arr = (t.seatedGuests ?? []) as Guest[];
    let slots = this.slotsOf(t);
    let k = slots.indexOf(seatIndex);
    if (k >= 0) {
      this.recordSeatChange(() => {
        t!.seatedGuests = arr.filter((_, i) => i !== k);
        t!.seatSlots = slots.filter((_, i) => i !== k);
      });
    }
  };
  stopPointer = (e: Event) => {
    e.stopPropagation();
  };
  seatClick = (tableId: string, seatIndex: number, e: Event) => {
    e.stopPropagation();
    this.freeSeat(tableId, seatIndex);
  };
  @tracked toast: string | null = null;
  @tracked toastAction: { label: string; run: () => void } | null = null;
  private toastTimer: ReturnType<typeof setTimeout> | null = null;
  private showToast(
    msg: string,
    action?: { label: string; run: () => void },
    duration = action ? 5000 : 2600,
  ) {
    this.toast = msg;
    this.toastAction = action ?? null;
    if (this.toastTimer) clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => this.dismissToast(), duration);
  }
  dismissToast = () => {
    this.toast = null;
    this.toastAction = null;
    if (this.toastTimer) clearTimeout(this.toastTimer);
    this.toastTimer = null;
  };
  runToastAction = () => {
    let a = this.toastAction;
    this.dismissToast();
    a?.run();
  };
  get floorPlanOpacity() {
    if (this.liveOpacity != null) return this.liveOpacity;
    let o = this.args.model?.floorPlanOpacity;
    return o == null ? 45 : o;
  }
  get floorPlanStyle() {
    return htmlSafe(
      `position:absolute;left:0;top:0;transform:translate(${this.effFloorX}px,${this.effFloorY}px);width:${this.effFloorW}px;height:${this.effFloorH}px;opacity:${
        this.floorPlanOpacity / 100
      };`,
    );
  }
  get floorFrameStyle() {
    return htmlSafe(
      `position:absolute;left:0;top:0;transform:translate(${this.effFloorX}px,${this.effFloorY}px);width:${this.effFloorW}px;height:${this.effFloorH}px;`,
    );
  }
  selectFloorForEdit = () => {
    this.selectedKeys = [];
    this.floorSelected = true;
    this.floorDeleteArmed = false;
  };
  setFloorOpacity = (e: Event) => {
    this.liveOpacity = Number((e.target as HTMLInputElement).value);
  };
  commitFloorOpacity = (e: Event) => {
    this.liveOpacity = null;
    this.args.model.floorPlanOpacity = Number(
      (e.target as HTMLInputElement).value,
    );
  };
  removeFloorPlan = () => {
    let m = this.args.model;
    m.floorPlanURL = undefined;
    this.showToast('Floor plan removed');
  };
  @tracked floorDeleteArmed = false;
  armFloorDelete = () => {
    this.floorDeleteArmed = true;
  };
  cancelFloorDelete = () => {
    this.floorDeleteArmed = false;
  };
  confirmRemoveFloorPlan = () => {
    this.floorDeleteArmed = false;
    this.removeFloorPlan();
  };
  replaceFloorPlan = () => {
    this.floorDeleteArmed = false;
    this.openFloorLibrary();
  };
  grabFloorPlan = (evt: Event) => {
    let e = evt as PointerEvent;
    e.stopPropagation();
    this.selectedKeys = [];
    this.floorSelected = true;
    this.beginMove(e);
  };
  @tracked aiPlanBusy = false;
  private validateFloorFile(
    file: File,
  ): { ok: true; isPdf: boolean } | { ok: false; msg: string } {
    let name = file.name.toLowerCase();
    let isPdf = file.type === 'application/pdf' || name.endsWith('.pdf');
    let isImage =
      /^image\//.test(file.type) || /\.(png|jpe?g|webp|gif|svg)$/.test(name);
    if (/\.(dwg|dxf)$/.test(name))
      return {
        ok: false,
        msg: 'CAD files aren’t supported — export the plan to PDF or PNG first',
      };
    if (!isPdf && !isImage)
      return {
        ok: false,
        msg: 'Unsupported file — use PDF, PNG, JPG, WEBP or SVG',
      };
    if (file.size > 25 * 1024 * 1024)
      return {
        ok: false,
        msg: 'That file is over 25 MB — please use a smaller image or PDF',
      };
    return { ok: true, isPdf };
  }
  private async readPlanFile(file: File, isPdf: boolean) {
    let base64 = '';
    let contentType = 'image/png';
    let dataUrl = '';
    if (isPdf) {
      dataUrl = await renderPdfToPng(file);
      base64 = dataUrl.slice(dataUrl.indexOf(',') + 1);
      contentType = 'image/png';
    } else {
      let buf = await file.arrayBuffer();
      base64 = arrayBufferToBase64(buf);
      contentType = file.type || 'image/png';
      dataUrl = `data:${contentType};base64,${base64}`;
    }
    let dims = await imageDims(dataUrl);
    return { base64, contentType, dataUrl, dims };
  }
  private commitFloorUnderlay = debounce(
    (url: string, natW: number, natH: number) => {
      this.placeFloorUnderlay(url, natW, natH);
      setTimeout(() => this.fitView(), 16);
    },
    300,
  );
  private placeFloorUnderlay(url: string, natW: number, natH: number) {
    let targetW = 860;
    let scale = targetW / (natW || targetW);
    let targetH = Math.round((natH || 600) * scale);
    let c = this.worldCenter();
    let rx = Math.round(c.x - targetW / 2);
    let ry = Math.round(c.y - targetH / 2);
    this.args.model.floorPlanURL = url;
    this.args.model.floorPlanX = rx;
    this.args.model.floorPlanY = ry;
    this.args.model.floorPlanWidth = targetW;
    this.args.model.floorPlanHeight = targetH;
    this.args.model.floorPlanOpacity = 45;
    return { x: rx, y: ry, w: targetW, h: targetH };
  }
  private async urlToDataUrl(url: string): Promise<string> {
    let resp = await fetch(url);
    if (!resp.ok) throw new Error(`Could not load image (${resp.status})`);
    let blob = await resp.blob();
    return await new Promise<string>((resolve, reject) => {
      let fr = new FileReader();
      fr.onload = () => resolve(String(fr.result));
      fr.onerror = () =>
        reject(new Error('Could not read the floor-plan image'));
      fr.readAsDataURL(blob);
    });
  }
  private buildLayoutFromImage = async (
    ctx: any,
    dataUrl: string,
    rect: { x: number; y: number; w: number; h: number },
  ) => {
    let { x: rx, y: ry, w: targetW, h: targetH } = rect;
    let localRect = { x: 0, y: 0, w: targetW, h: targetH };
    let gridded = await gridOverlay(dataUrl, localRect);
    let out = await withTimeout(
      new AnalyzeFloorPlanCommand(ctx).execute({
        imageUrl: gridded,
        planRect: JSON.stringify(localRect),
      }),
      90000,
      'AI floor-plan analysis',
    );
    let parsed = this.parseLlmJson((out as any)?.output ?? '');
    if (!parsed) throw new Error('Could not read a layout from the AI');
    let z = this.nextZ();
    let tMaxW = Math.round(targetW * 0.92);
    let tMaxH = Math.round(targetH * 0.92);
    let tDefW = Math.round(targetW * 0.17);
    let tDefH = Math.round(targetH * 0.17);
    let tables: Table[] = (parsed.tables ?? []).map((t: any, i: number) => {
      let shape = SHAPE_VALUES.includes(t.shape) ? t.shape : 'round';
      let aw = clampNum(t.width, 30, tMaxW, tDefW);
      let ah = clampNum(t.height, 30, tMaxH, tDefH);
      let cx = rx + clampNum(t.x, -40, targetW + 40, 0) + aw / 2;
      let cy = ry + clampNum(t.y, -40, targetH + 40, 0) + ah / 2;
      let rows = 0;
      let cols = 0;
      if (shape === 'section') {
        rows = clampNum(t.rows, 1, 60, 5);
        cols = clampNum(t.cols, 1, 60, 6);
        let min = sectionSize(rows, cols);
        aw = Math.min(Math.max(aw, min.w), tMaxW);
        ah = Math.min(Math.max(ah, min.h), tMaxH);
      }
      if (shape === 'round' || shape === 'square') {
        let s = Math.round((aw + ah) / 2);
        aw = s;
        ah = s;
      }
      let validStyle = SEATING_STYLES.some((s) => s.value === t.seatingStyle);
      let style: string = validStyle
        ? t.seatingStyle
        : shape === 'round' || shape === 'square'
          ? 'around'
          : Math.max(aw, ah) / Math.max(1, Math.min(aw, ah)) >= 1.8
            ? 'opposite'
            : 'around';
      let seatCount =
        shape === 'section' ? rows * cols : clampNum(t.seatCount, 0, 40, 8);
      let seatOrder: SeatOrder | undefined =
        shape === 'section' && SEAT_ORDERS.some((o) => o.value === t.seatOrder)
          ? t.seatOrder
          : undefined;
      let rotation = shape === 'section' ? 0 : clampNum(t.rotation, 0, 359, 0);
      if (shape === 'rect' || shape === 'oval') {
        let horizontal =
          style === 'opposite' || style === 'top' || style === 'bottom';
        let vertical = style === 'left' || style === 'right';
        if ((horizontal && ah > aw) || (vertical && aw > ah)) {
          [aw, ah] = [ah, aw];
          rotation = (rotation + 90) % 360;
        }
      }
      let margin = shape === 'seat' ? 6 : 22;
      let ext = Math.max(aw, ah) / 2 + margin;
      let clampCentre = (v: number, lo: number, hi: number) =>
        hi < lo ? (lo + hi) / 2 : Math.max(lo, Math.min(hi, v));
      cx = clampCentre(cx, rx + ext, rx + targetW - ext);
      cy = clampCentre(cy, ry + ext, ry + targetH - ext);
      return new Table({
        name: t.name || `Table ${i + 1}`,
        shape,
        seatCount,
        seatingStyle: style,
        seatOrder,
        rows: shape === 'section' ? rows : undefined,
        cols: shape === 'section' ? cols : undefined,
        x: Math.round(cx - aw / 2),
        y: Math.round(cy - ah / 2),
        width: aw,
        height: ah,
        rotation,
        themeColor: '#c5a35c',
        z: z++,
      });
    });
    let fixtures: Fixture[] = (parsed.fixtures ?? []).map((f: any) => {
      let kind = FIXTURE_VALUES.includes(f.kind) ? f.kind : 'plant';
      let fw = clampNum(f.width, 20, Math.round(targetW * 0.98), tDefW);
      let fh = clampNum(f.height, 20, Math.round(targetH * 0.98), tDefH);
      let maxX = Math.max(0, targetW - fw);
      let maxY = Math.max(0, targetH - fh);
      return new Fixture({
        label: FIXTURE_KIND_LABELS[kind] || 'Fixture',
        kind,
        pattern: 'outline',
        x: rx + clampNum(f.x, 0, maxX, 0),
        y: ry + clampNum(f.y, 0, maxY, 0),
        width: fw,
        height: fh,
        rotation: clampNum(f.rotation, 0, 359, 0),
        color: '#c5a35c',
        z: z++,
      });
    });
    let stages = fixtures.filter((f) => f.kind === 'stage');
    let arches = fixtures.filter((f) => f.kind === 'arch');
    let centreOf = (e: {
      x?: number;
      y?: number;
      width?: number;
      height?: number;
    }) => ({
      x: (e.x || 0) + (e.width || 0) / 2,
      y: (e.y || 0) + (e.height || 0) / 2,
    });
    let faceDeg = (fx: number, fy: number) =>
      Math.abs(fx) >= Math.abs(fy) ? (fx >= 0 ? 90 : 270) : fy >= 0 ? 180 : 0;
    let nearestCentre = (
      c: { x: number; y: number },
      list: Fixture[],
    ): { x: number; y: number } | null => {
      let best: { d: number; c: { x: number; y: number } } | null = null;
      for (let f of list) {
        let fc = centreOf(f);
        let d = (fc.x - c.x) ** 2 + (fc.y - c.y) ** 2;
        if (!best || d < best.d) best = { d, c: fc };
      }
      return best?.c ?? null;
    };
    for (let sec of tables) {
      if (sec.shape !== 'section') continue;
      let c = centreOf(sec);
      let deg: number | null = null;
      if (stages.length) {
        let s = nearestCentre(c, stages)!;
        deg = faceDeg(s.x - c.x, s.y - c.y); // face toward the stage
      } else if (arches.length) {
        let a = nearestCentre(c, arches)!;
        deg = faceDeg(c.x - a.x, c.y - a.y); // face away from the arch
      }
      if (deg == null) continue;
      if (
        (deg === 90 || deg === 270) &&
        (sec.width || 0) !== (sec.height || 0)
      ) {
        let w = sec.width;
        sec.width = sec.height;
        sec.height = w;
      }
      sec.rotation = deg;
    }
    let planCx = rx + targetW / 2;
    let planCy = ry + targetH / 2;
    for (let f of fixtures) {
      if (f.kind !== 'curved-wall') continue;
      let c = centreOf(f);
      let right = c.x >= planCx;
      let bottom = c.y >= planCy;
      f.rotation =
        !right && !bottom ? 0 : right && !bottom ? 90 : right ? 180 : 270;
    }
    this.applyLayout(tables, fixtures, 'AI floor-plan');
    if (this.sectionsNeedFit()) this.layoutSeatingSections(true);
  };
  @tracked inspectorCollapsed = true;
  toggleInspector = () => {
    this.inspectorCollapsed = !this.inspectorCollapsed;
  };
  private get inspectorBeckons(): boolean {
    return this.inspectorCollapsed;
  }
  private get hasInspectorSelection(): boolean {
    return !!this.selectedTable || !!this.selectedFixture;
  }
  @tracked showFloorLibrary = false;
  @tracked fpImporting = false;
  openFloorLibrary = () => {
    this.addMenuOpen = false;
    this.showFloorLibrary = true;
  };
  closeFloorLibrary = () => {
    this.showFloorLibrary = false;
  };
  get seatedGuestSet(): Set<Guest> {
    let s = new Set<Guest>();
    for (let t of this.tables)
      for (let g of t.seatedGuests ?? []) if (g) s.add(g as Guest);
    return s;
  }
  railShowsGuest = (g: Guest | undefined): boolean => {
    if (!g || this.seatedGuestSet.has(g)) return false;
    let q = this.search.trim().toLowerCase();
    if (q && !(g.fullName ?? '').toLowerCase().includes(q)) return false;
    if (this.activeCatId && g.category !== this.activeCatId) return false;
    return true;
  };
  grabGuest = (g: Guest, e: PointerEvent) => {
    e.preventDefault();
    this.draggingGuest = g;
    this.draggingGuestId = (g as any)?.id ?? null;
    this.ghostX = e.clientX;
    this.ghostY = e.clientY;
    document.addEventListener('pointermove', this.onGuestMove);
    document.addEventListener('pointerup', this.onGuestUp);
  };
  get buildDisabled() {
    return this.aiPlanBusy || !this.args.model?.floorPlanURL;
  }
  importFloorPlanCard = async (e: Event) => {
    let input = e.target as HTMLInputElement;
    let file = input.files?.[0];
    if (!file) return;
    let v = this.validateFloorFile(file);
    if (!v.ok) {
      this.showToast(v.msg);
      input.value = '';
      return;
    }
    let ctx = (this.args as any).context?.commandContext;
    if (!ctx) {
      this.showToast('Switch to Interact mode to import a plan');
      input.value = '';
      return;
    }
    if (!this.realmUrl) {
      this.showToast('Save the plan to a realm first');
      input.value = '';
      return;
    }
    this.fpImporting = true;
    this.showToast('Importing floor plan…');
    try {
      let { base64, contentType, dims } = await this.readPlanFile(
        file,
        v.isPdf,
      );
      let ext = (contentType.split('/')[1] || 'png').replace('+xml', '');
      let slug =
        file.name
          .replace(/\.[^.]+$/, '')
          .trim()
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, '-')
          .replace(/^-+|-+$/g, '') || 'floorplan';
      let res = await new WriteBinaryFileCommand(ctx).execute({
        path: `${FLOOR_PLAN_DIR}${slug}.${ext}`,
        realm: this.realmUrl,
        base64Content: base64,
        contentType,
        useNonConflictingFilename: true,
      });
      let url = (res as any)?.fileIdentifier ?? '';
      if (!url) throw new Error('upload returned no file');
      this.commitFloorUnderlay(url, dims.w, dims.h);
      this.showToast('Floor plan added — Build with AI to trace tables');
      this.closeFloorLibrary();
    } catch (err: any) {
      this.showToast(`Import failed: ${err?.message ?? 'error'}`);
    }
    this.fpImporting = false;
    input.value = '';
  };
  linkFloorPlan = async () => {
    try {
      let fileType = identifyCard(ImageDef);
      let picked: any = await chooseFile(
        fileType ? { fileType, fileTypeName: 'Image' } : undefined,
      );
      if (!picked) return;
      let url = picked.url ?? picked.id;
      if (!url) {
        this.showToast('That image has no file URL');
        return;
      }
      let w = Number(picked.width);
      let h = Number(picked.height);
      if (!w || !h) {
        let dims = await imageDims(String(url));
        w = dims.w;
        h = dims.h;
      }
      this.commitFloorUnderlay(String(url), w, h);
      this.showToast('Floor plan placed — Build with AI to trace tables');
      this.closeFloorLibrary();
    } catch (err: any) {
      this.showToast(`Could not link floor plan: ${err?.message ?? 'error'}`);
    }
  };
  buildFromFloorPlan = async () => {
    let ctx = (this.args as any).context?.commandContext;
    if (!ctx) {
      this.showToast('Switch to Interact mode to use AI');
      return;
    }
    let url = this.args.model?.floorPlanURL;
    if (!url) {
      this.showToast('Import or pick a floor plan first');
      return;
    }
    this.aiPlanBusy = true;
    this.showToast('Reading the floor plan…');
    try {
      let dataUrl = await this.urlToDataUrl(String(url));
      let rect = {
        x: this.args.model.floorPlanX || 0,
        y: this.args.model.floorPlanY || 0,
        w: this.args.model.floorPlanWidth || 860,
        h: this.args.model.floorPlanHeight || 600,
      };
      await this.buildLayoutFromImage(ctx, dataUrl, rect);
      this.aiPlanBusy = false;
      this.showFloorLibrary = false;
    } catch (err: any) {
      this.aiPlanBusy = false;
      let msg = err?.message ?? 'error';
      if (/forbidden|credit/i.test(msg)) msg = "You're out of AI credits";
      this.showToast(`AI failed: ${msg}`);
    }
  };
  grabFloorResize = (evt: Event) => {
    let e = evt as PointerEvent;
    e.stopPropagation();
    e.preventDefault();
    this.dragMode = 'resize';
    this.resizeKind = 'floorplan';
    this.resizeEdge = 'se';
    this.dragTarget = null;
    this.startPX = e.clientX;
    this.startPY = e.clientY;
    this.origW = this.args.model?.floorPlanWidth || 800;
    this.origH = this.args.model?.floorPlanHeight || 600;
    this.dragRot = 0;
    this.attachDragListeners();
  };
  private nextZ(): number {
    let zs = [...this.tables, ...this.fixtures].map((e) => e.z || 0);
    return (zs.length ? Math.max(...zs) : 0) + 1;
  }
  private minZ(): number {
    let zs = [...this.tables, ...this.fixtures].map((e) => e.z || 0);
    return (zs.length ? Math.min(...zs) : 0) - 1;
  }
  bringTableFront = () => {
    let t = this.selectedTable;
    if (t) this.recordSet((v) => (t!.z = v), t.z || 0, this.nextZ());
  };
  sendTableBack = () => {
    let t = this.selectedTable;
    if (t) this.recordSet((v) => (t!.z = v), t.z || 0, this.minZ());
  };
  bringFxFront = () => {
    let f = this.selectedFixture;
    if (f) this.recordSet((v) => (f!.z = v), f.z || 0, this.nextZ());
  };
  sendFxBack = () => {
    let f = this.selectedFixture;
    if (f) this.recordSet((v) => (f!.z = v), f.z || 0, this.minZ());
  };
  toggleTableLock = () => {
    let t = this.selectedTable;
    if (t) this.recordSet((v) => (t!.locked = v), !!t.locked, !t.locked);
  };
  toggleFixtureLock = () => {
    let f = this.selectedFixture;
    if (f) this.recordSet((v) => (f!.locked = v), !!f.locked, !f.locked);
  };
  private applyLayout = (
    tables: Table[],
    fixtures: Fixture[],
    label: string,
  ) => {
    let zi = 1;
    for (let f of fixtures) f.z = zi++;
    for (let t of tables) t.z = zi++;
    let beforeT = this.tables;
    let beforeF = this.fixtures;
    this.args.model.tables = tables;
    this.args.model.fixtures = fixtures;
    this.deselect();
    this.popoverTableKey = null;
    this.pushUndo(
      () => {
        this.args.model.tables = beforeT;
        this.args.model.fixtures = beforeF;
      },
      () => {
        this.args.model.tables = tables;
        this.args.model.fixtures = fixtures;
      },
    );
    this.showToast(`${label} layout created`);
    setTimeout(() => this.fitView(), 16);
  };
  @tracked savingTemplate = false;
  @tracked templates: LayoutTemplate[] = [];
  @tracked templatesLoading = false;
  loadTemplates = async () => {
    let store = (this.args as any).context?.store;
    let realm = this.realmUrl;
    if (!store || !realm) return;
    this.templatesLoading = true;
    try {
      let found: LayoutTemplate[] = await store.search(
        { filter: { type: identifyCard(LayoutTemplate) } },
        [realm],
      );
      let rank = (n: string) =>
        n === 'Ceremony' ? 0 : n === 'Reception' ? 1 : 2;
      this.templates = found.filter(Boolean).sort((a, b) => {
        let ra = rank(a.name ?? '');
        let rb = rank(b.name ?? '');
        return ra !== rb ? ra - rb : (a.name ?? '').localeCompare(b.name ?? '');
      });
    } catch (e) {
      console.error(e);
    } finally {
      this.templatesLoading = false;
    }
  };
  tplKey = (t: LayoutTemplate) => (t as any)?.id ?? keyOf(t);
  applyTemplate = (tpl: LayoutTemplate) => {
    this.addMenuOpen = false;
    this.templateMenuOpen = false;
    this.previewTplKey = null;
    let tables = ((tpl.tables ?? []) as Table[]).map(cloneTableGeometry);
    let fixtures = ((tpl.fixtures ?? []) as Fixture[]).map(cloneFixture);
    this.applyLayout(tables, fixtures, tpl.name?.trim() || 'Template');
  };
  @tracked previewTplKey: string | null = null;
  openTemplatePreview = (t: LayoutTemplate, e: Event) => {
    e.stopPropagation();
    this.previewTplKey = this.tplKey(t);
  };
  closeTemplatePreview = () => {
    this.previewTplKey = null;
  };
  get previewTemplate(): LayoutTemplate | null {
    if (!this.previewTplKey) return null;
    return (
      this.templates.find((t) => this.tplKey(t) === this.previewTplKey) ?? null
    );
  }
  get previewAnchor(): string {
    return `[data-tpl-preview='${this.previewTplKey}']`;
  }
  @tracked showSaveTemplate = false;
  @tracked templateName = '';
  @tracked templateError = '';
  openSaveTemplate = () => {
    if (!this.tables.length && !this.fixtures.length) {
      this.showToast('Nothing to save yet — add some tables first.');
      return;
    }
    this.addMenuOpen = false;
    this.templateError = '';
    this.templateName =
      (this.args.model?.eventTitle?.trim() || 'My') + ' layout';
    this.showSaveTemplate = true;
  };
  closeSaveTemplate = () => {
    this.showSaveTemplate = false;
  };
  onTemplateNameInput = (e: Event) => {
    this.templateName = (e.target as HTMLInputElement).value;
    if (this.templateError) this.templateError = '';
  };
  confirmSaveTemplate = async () => {
    if (this.savingTemplate) return;
    let name = this.templateName.trim();
    if (!name) {
      this.templateError = 'Give the template a name.';
      return;
    }
    let store = (this.args as any).context?.store;
    let realm = this.realmUrl;
    if (!store || !realm) {
      this.templateError = 'Templates need a realm to save into.';
      return;
    }
    this.savingTemplate = true;
    try {
      let existing: LayoutTemplate[] = await store.search(
        { filter: { type: identifyCard(LayoutTemplate) } },
        [realm],
      );
      let clash = existing.some(
        (t) => (t?.name ?? '').trim().toLowerCase() === name.toLowerCase(),
      );
      if (clash) {
        this.templateError = `“${name}” already exists — pick another name.`;
        return;
      }
      let card = new LayoutTemplate({
        name,
        tables: this.tables.map(cloneTableGeometry),
        fixtures: this.fixtures.map(cloneFixture),
      });
      await store.add(card, { realm });
      this.showSaveTemplate = false;
      this.showToast(`Saved “${name}” to your templates`);
      this.loadTemplates();
    } catch (e) {
      console.error(e);
      this.templateError = 'Could not save — please try again.';
    } finally {
      this.savingTemplate = false;
    }
  };
  @tracked savingSnapshot = false;
  saveSnapshot = async () => {
    if (this.savingSnapshot) return;
    let m = this.args.model;
    let store = (this.args as any).context?.store;
    let realm = this.realmUrl;
    if (!m) return;
    if (!store || !realm) {
      this.showToast('Snapshots need a realm to save into.');
      return;
    }
    if (!this.tables.length) {
      this.showToast('Nothing to snapshot yet — add some tables first.');
      return;
    }
    this.savingSnapshot = true;
    try {
      let Plan = m.constructor as new (props: Record<string, unknown>) => any;
      let stamp = new Date().toLocaleString(undefined, {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      });
      let card = new Plan({
        eventTitle: `${
          m.eventTitle?.trim() || 'Untitled Event'
        } — ${stamp} snapshot`,
        hosts: [...((m.hosts ?? []) as any[])],
        eventDate: m.eventDate,
        venue: m.venue,
        guests: [...this.guests],
        tables: this.tables.map(cloneTableWithSeating),
        fixtures: this.fixtures.map(cloneFixture),
        floorPlanURL: m.floorPlanURL,
        floorPlanX: m.floorPlanX,
        floorPlanY: m.floorPlanY,
        floorPlanWidth: m.floorPlanWidth,
        floorPlanHeight: m.floorPlanHeight,
        floorPlanOpacity: m.floorPlanOpacity,
        floorPlanLocked: m.floorPlanLocked,
        invitationMessage: m.invitationMessage,
        seatingMessage: m.seatingMessage,
      });
      let saved = await store.add(card, { realm });
      this.showToast(`Snapshot saved — “${(saved ?? card).eventTitle}”`, {
        label: 'View',
        run: () => this.args.viewCard?.(saved ?? card, 'isolated'),
      });
    } catch (e) {
      console.error(e);
      this.showToast('Could not save the snapshot — please try again.');
    } finally {
      this.savingSnapshot = false;
    }
  };
  private partyChildren(roster: Guest[]): Map<Guest, Guest[]> {
    let inRoster = new Set(roster);
    let rootOf = (g: Guest): Guest => {
      let cur = g;
      let seen = new Set<Guest>([cur]);
      let p: Guest | undefined;
      while ((p = cur.parentGuest as Guest | undefined)) {
        if (!inRoster.has(p) || seen.has(p)) break;
        seen.add(p);
        cur = p;
      }
      return cur;
    };
    let map = new Map<Guest, Guest[]>();
    for (let g of roster) {
      let root = rootOf(g);
      if (root === g) continue;
      let kids = map.get(root);
      if (kids) kids.push(g);
      else map.set(root, [g]);
    }
    return map;
  }
  partySizeOf = (g: Guest): number => {
    return 1 + (this.partyChildren(this.guests).get(g)?.length ?? 0);
  };
  railPartyOf = (g: Guest): number | null => {
    let n = this.partySizeOf(g);
    return n > 1 ? n : null;
  };
  private parseLlmJson(raw: string): any | null {
    if (!raw) return null;
    let fenceOpenJson = new RegExp('^```json', 'i');
    let fenceOpen = new RegExp('^```');
    let fenceClose = new RegExp('```$');
    let s = raw
      .trim()
      .replace(fenceOpenJson, '')
      .replace(fenceOpen, '')
      .replace(fenceClose, '')
      .trim();
    let start = s.indexOf('{');
    let end = s.lastIndexOf('}');
    if (start < 0 || end < 0) return null;
    try {
      return JSON.parse(s.slice(start, end + 1));
    } catch {
      return null;
    }
  }
  arrangeWithAI = async () => {
    if (this.aiStatus === 'loading') return;
    let ctx = (this.args as any).context?.commandContext;
    if (!ctx) {
      this.showToast('Switch to Interact mode to use AI');
      return;
    }
    if (!this.tables.length) {
      this.showToast('Add a table first');
      return;
    }
    let model = this.args.model as TableSeatingPlanner;
    if (!model?.id) {
      this.showToast('Save the plan first');
      return;
    }
    let roster = this.guests;
    let children = this.partyChildren(roster);
    let companionSet = new Set<Guest>();
    for (let kids of children.values()) for (let c of kids) companionSet.add(c);
    let partiesPayload: any[] = [];
    for (let g of roster) {
      if (companionSet.has(g) || !g.id) continue;
      let members = [g, ...(children.get(g) ?? [])];
      partiesPayload.push({
        id: g.id,
        name: g.fullName || 'Guest',
        size: members.length,
        members: members.map((m) => m.fullName || 'Guest'),
        category: categoryLabel(g.category) || 'Uncategorized',
        vip: members.some((m) => !!m.vip),
      });
    }
    let prominence = this.tableRank;
    let tablesPayload = this.tables.map((t, index) => ({
      index,
      name: t.name || 'Table',
      capacity: t.seatCount || 0,
      reservedCategories: (t.reservedCategories ?? []).map((c) =>
        categoryLabel(c),
      ),
      vip: !!t.vip,
      prominence: prominence.get(t) ?? 0,
      shape: t.shape || 'round',
      rows: t.shape === 'section' ? t.rows || 0 : undefined,
      cols: t.shape === 'section' ? t.cols || 0 : undefined,
    }));
    let instruction =
      'Arrange guests sociably, grouping people by their relationship category and keeping couples and families together.';
    let prompt = [
      'Please arrange the seating for this plan, then apply it with the Apply Seating Plan command.',
      `plannerCardId: ${model.id}`,
      `Requirement: ${instruction}`,
      'Seating data:',
      JSON.stringify({
        parties: partiesPayload,
        tables: tablesPayload,
        instruction,
      }),
    ].join('\n');
    this.aiStatus = 'loading';
    try {
      // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
      let skillCardId = new URL('../Skill/seat-arranger', import.meta.url).href;
      await new UseAiAssistantCommand(ctx).execute({
        roomId: 'new',
        roomName: `Seating: ${model.eventTitle || model.title || 'plan'}`,
        openRoom: true,
        llmMode: 'act',
        skillCardIds: [skillCardId],
        attachedCards: [model],
        openCardIds: [model.id],
        prompt,
      });
      this.aiStatus = 'idle';
      this.showToast('AI Assistant is arranging — the seats update live');
    } catch (e: any) {
      let msg = e?.message ?? 'Could not reach the AI Assistant';
      if (/forbidden|credit/i.test(msg)) msg = "You're out of AI credits.";
      this.aiStatus = 'idle';
      this.showToast(msg);
    }
  };
  get ghostInitials() {
    return initialsOf(this.draggingGuest?.fullName);
  }
  get hoverInitials() {
    return initialsOf(this.hoverGuest?.fullName);
  }
  get hoverParty() {
    let g = this.hoverGuest;
    let n = g ? this.partySizeOf(g) : 1;
    return n > 1 ? n : 0;
  }
  addGuests = async () => {
    let store = (this.args as any).context?.store;
    let type = identifyCard(Guest) ?? baseCardRef;
    let existingQuery = this.guests
      .map((g) =>
        (g as any)?.id ? { not: { eq: { id: (g as any).id } } } : undefined,
      )
      .filter((q): q is NonNullable<typeof q> => Boolean(q));
    let chosen = await chooseCard(
      { filter: { every: [{ type }, ...existingQuery] } },
      {
        offerToCreate: {
          ref: type,
          relativeTo: undefined,
          realmURL: this.realmUrl ? new URL(this.realmUrl) : undefined,
        },
        multiSelect: true,
        consumingRealm: this.realmUrl ? new URL(this.realmUrl) : undefined,
      },
    );
    if (!chosen) return;
    let ids: string[] = Array.isArray(chosen) ? chosen : [chosen];
    let picked = (await Promise.all(ids.map((id) => store?.get(id)))).filter(
      Boolean,
    ) as Guest[];
    if (picked.length) {
      this.args.model.guests = [...this.guests, ...picked];
    }
  };
  get hostChips() {
    return ((this.args.model?.hosts ?? []) as Host[])
      .filter(Boolean)
      .map((h) => ({
        key: keyOf(h),
        model: h,
        initials: initialsOf(h.fullName),
        photo: h.photoURL || '',
        name: h.fullName || 'Host',
      }));
  }
  addHosts = async () => {
    let store = (this.args as any).context?.store;
    let type = identifyCard(Host) ?? baseCardRef;
    let hosts = ((this.args.model?.hosts ?? []) as Host[]).filter(Boolean);
    let existingQuery = hosts
      .map((h) =>
        (h as any)?.id ? { not: { eq: { id: (h as any).id } } } : undefined,
      )
      .filter((q): q is NonNullable<typeof q> => Boolean(q));
    let chosen = await chooseCard(
      { filter: { every: [{ type }, ...existingQuery] } },
      {
        offerToCreate: {
          ref: type,
          relativeTo: undefined,
          realmURL: this.realmUrl ? new URL(this.realmUrl) : undefined,
        },
        multiSelect: true,
        consumingRealm: this.realmUrl ? new URL(this.realmUrl) : undefined,
      },
    );
    if (!chosen) return;
    let ids: string[] = Array.isArray(chosen) ? chosen : [chosen];
    let picked = (await Promise.all(ids.map((id) => store?.get(id)))).filter(
      Boolean,
    ) as Host[];
    if (picked.length) {
      this.args.model.hosts = [...hosts, ...picked];
    }
  };
  removeHost = (h: Host) => {
    let hosts = ((this.args.model?.hosts ?? []) as Host[]).filter(Boolean);
    this.args.model.hosts = hosts.filter((x) => x !== h);
    this.showToast(`${h.fullName || 'Host'} removed from hosts`);
  };
  get eventDateInput(): string {
    let d = this.args.model?.eventDate;
    if (!d) return '';
    try {
      let y = d.getFullYear();
      let m = String(d.getMonth() + 1).padStart(2, '0');
      let day = String(d.getDate()).padStart(2, '0');
      return `${y}-${m}-${day}`;
    } catch {
      return '';
    }
  }
  setEventDate = (e: Event) => {
    let v = (e.target as HTMLInputElement).value;
    this.args.model.eventDate = v ? new Date(`${v}T12:00:00`) : undefined;
  };
  openEditGuest = (g: Guest) => {
    this.args.viewCard?.(g, 'edit');
  };
  stopDrag = (e: Event) => {
    e.stopPropagation();
  };
  removeGuest = (g: Guest) => {
    let party = new Set<Guest>([
      g,
      ...(this.partyChildren(this.guests).get(g) ?? []),
    ]);
    let roster = [...this.guests];
    let seats = this.snapshotSeats();
    let apply = () => {
      for (let t of this.tables) {
        let arr = (t.seatedGuests ?? []) as Guest[];
        if (!arr.some((x) => party.has(x as Guest))) continue;
        let slots = this.slotsOf(t);
        let keep = arr
          .map((x, i) => ({ g: x as Guest, slot: slots[i] }))
          .filter((e) => !party.has(e.g));
        t.seatedGuests = keep.map((e) => e.g);
        t.seatSlots = keep.map((e) => e.slot);
      }
      this.args.model.guests = roster.filter((x) => !party.has(x));
    };
    apply();
    this.pushUndo(() => {
      this.restoreSeats(seats);
      this.args.model.guests = roster;
    }, apply);
    let name = g.fullName || 'guest';
    this.showToast(
      party.size > 1
        ? `Removed ${name} (party of ${party.size})`
        : `Removed ${name}`,
    );
  };
  @tracked confirmClearGuests = false;
  private clearGuestsTimer: number | undefined;
  clearAllGuests = () => {
    if (!this.confirmClearGuests) {
      this.confirmClearGuests = true;
      clearTimeout(this.clearGuestsTimer);
      this.clearGuestsTimer = window.setTimeout(() => {
        this.confirmClearGuests = false;
      }, 4000);
      return;
    }
    clearTimeout(this.clearGuestsTimer);
    this.confirmClearGuests = false;
    let roster = [...this.guests];
    if (!roster.length) return;
    let seats = this.snapshotSeats();
    let apply = () => {
      for (let t of this.tables) {
        if ((t.seatedGuests ?? []).length) {
          t.seatedGuests = [];
          t.seatSlots = [];
        }
      }
      this.args.model.guests = [];
    };
    apply();
    this.pushUndo(() => {
      this.restoreSeats(seats);
      this.args.model.guests = roster;
    }, apply);
    this.showToast(`Removed all ${roster.length} guests`);
  };
  get realmUrl(): string {
    let u = (this.args.model as any)?.[realmURL];
    return u ? String(u) : '';
  }
  private formatEventDate(): string {
    let d = this.args.model?.eventDate;
    if (!d) return 'our wedding day';
    try {
      return d.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      });
    } catch {
      return 'our wedding day';
    }
  }
  clearPoster = () => {
    this.args.model.poster = undefined;
    this.showToast('Using the default card');
  };
  get defaultInviteMessage(): string {
    return "Dear {name}, you're warmly invited to {event} on {date} at {venue}, Can't wait to see you there!";
  }
  get inviteTemplate(): string {
    return this.args.model?.invitationMessage || this.defaultInviteMessage;
  }
  onInviteTemplateInput = (e: Event) => {
    this.commitInviteMessage((e.target as HTMLTextAreaElement).value);
  };
  onInviteSearch = (e: Event) => {
    this.inviteSearch = (e.target as HTMLInputElement).value;
  };
  clearInviteSearch = () => {
    this.inviteSearch = '';
  };
  private matchesInviteSearch = (g: Guest): boolean => {
    let q = this.inviteSearch.trim().toLowerCase();
    if (!q) return true;
    return (g.fullName ?? '').toLowerCase().includes(q);
  };
  guestSeat = (g: Guest): { table: string; seat: number } | null => {
    for (let t of this.tables) {
      let idx = (t.seatedGuests ?? []).findIndex((x) => x === g);
      if (idx >= 0) return { table: t.name || 'Table', seat: idx + 1 };
    }
    return null;
  };
  get posterLink(): string {
    return this.args.model?.poster?.resolvedUrl || '';
  }
  @tracked posterBusy = false;
  private linkPosterFile = async (fileUrl: string) => {
    if (!fileUrl) {
      throw new Error('could not load the saved image');
    }
    // The command writes a raw image file and returns its URL — not a card id —
    // so we point the poster at it via url mode rather than a linked ImageDef.
    this.args.model.poster = new ImageSourceField({
      url: fileUrl,
      sourceMode: 'url',
    });
  };
  downloadPoster = async () => {
    let url = this.posterLink;
    if (!url) return;
    try {
      let res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      let blob = await res.blob();
      let a = document.createElement('a');
      let href = URL.createObjectURL(blob);
      a.href = href;
      a.download = url.split('/').pop()?.split('?')[0] || 'invitation-poster';
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(href);
    } catch {
      window.open(url, '_blank', 'noopener');
    }
  };
  private get posterBasePrompt(): string {
    let m = this.args.model;
    let lines = [
      'Design an elegant event invitation poster.',
      'IMPORTANT: the image IS the poster artwork itself, full-bleed edge to edge. Do NOT draw a card, sheet of paper, or frame placed on a surface or background — no mockup, no drop shadow, no table, no border of a second surface showing around the design. Every pixel of the image is the poster.',
      'Background: warm white — a soft, warm-toned white like fine letterpress stationery, with a delicate faded decorative motif behind the text — light watercolor florals or fine French line-art (sprigs, laurel, subtle Parisian flourishes) in muted gold and soft tones, very low contrast so the lettering stays crisp and dominant.',
      'Set the hosts’ names largest in a graceful handwritten script; set every other line in small, letter-spaced serif capitals. Centered composition with generous breathing room.',
      'Letter ONLY the following lines on the poster, in exactly this top-to-bottom order, each line appearing exactly once — do not add, repeat, or reorder any words:',
    ];
    let n = 1;
    if (m?.hostNames)
      lines.push(`${n++}. ${m.hostNames} (the hosts' names, largest)`);
    lines.push(`${n++}. You're invited to`);
    if (m?.eventTitle) lines.push(`${n++}. ${m.eventTitle}`);
    if (m?.eventDate) lines.push(`${n++}. ${this.formatEventDate()}`);
    if (m?.venue) lines.push(`${n++}. ${m.venue}`);
    return lines.join('\n');
  }
  onPosterPromptInput = (e: Event) => {
    this.args.model.posterPrompt =
      (e.target as HTMLTextAreaElement).value || undefined;
  };
  posterAspects = POSTER_ASPECTS;
  get posterAspect(): string {
    return this.args.model?.posterAspect || '4:5';
  }
  get posterAspectStyle(): ReturnType<typeof htmlSafe> {
    let [w, h] = this.posterAspect.split(':').map(Number);
    if (!w || !h) [w, h] = [4, 5];
    return htmlSafe(`aspect-ratio: ${w} / ${h};`);
  }
  setPosterAspect = (v: string) => {
    this.args.model.posterAspect = v;
  };
  generatePoster = async () => {
    let ctx = (this.args as any).context?.commandContext;
    if (!ctx) {
      this.showToast('Switch to Interact mode to use AI');
      return;
    }
    if (!this.realmUrl) {
      this.showToast('Save the plan to a realm first');
      return;
    }
    this.posterBusy = true;
    this.showToast('Generating poster…');
    try {
      let prompt = this.posterBasePrompt;
      let extra = this.args.model?.posterPrompt?.trim();
      if (extra) prompt += `\n\nStyle directions: ${extra}`;
      let res = await new InvitationPosterCommand(ctx).execute({
        prompt,
        aspect: this.posterAspect,
        targetRealmIdentifier: this.realmUrl,
        targetPath: POSTER_DIR,
      });
      if (!res?.imageUrl) throw new Error('no image returned');
      await this.linkPosterFile(res.imageUrl);
      this.showToast('Poster generated');
    } catch (err: any) {
      let msg = err?.message ?? 'error';
      if (/forbidden|credit/i.test(msg)) msg = "You're out of AI credits";
      this.showToast(`Generate failed: ${msg}`);
    }
    this.posterBusy = false;
  };
  composeMessage = (g: Guest, template: string): string => {
    let m = this.args.model;
    let seatObj = this.guestSeat(g);
    let table = seatObj ? seatObj.table : 'a table to be announced';
    let seat = seatObj ? `Seat ${seatObj.seat}` : 'your seat';
    let link = this.posterLink;
    return template
      .replace(/\{name\}/g, g.fullName || 'Guest')
      .replace(/\{event\}/g, m?.eventTitle || 'our wedding')
      .replace(/\{date\}/g, this.formatEventDate())
      .replace(/\{venue\}/g, m?.venue || 'the venue')
      .replace(/\{table\}/g, table)
      .replace(/\{seat\}/g, seat)
      .replace(/\{hosts\}/g, m?.hostNames || m?.eventTitle || 'us')
      .replace(/\{poster\}/g, link);
  };
  copyText = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      this.showToast('Message copied');
    } catch {
      this.showToast('Copy failed');
    }
  };
  get inviteRows() {
    return this.guests.filter(this.matchesInviteSearch).map((g) => {
      let msg = this.composeMessage(g, this.inviteTemplate);
      return {
        key: keyOf(g),
        model: g,
        msg,
        initials: initialsOf(g.fullName),
      };
    });
  }
  <template>
    {{! template-lint-disable no-pointer-down-event-binding no-invalid-interactive }}
    <div class='tsp' data-tsp-root style={{this.themeVars}} {{this.keyboard}}>
      <header class='tsp-head' aria-label='Event details'>
        <div class='tsp-brand' aria-hidden='true'>
          {{#if this.eventLogoURL}}
            <img class='tsp-brand-img' src={{this.eventLogoURL}} alt='' />
          {{else}}
            <span
              class='tsp-brand-mark'
              data-initials={{this.eventInitials}}
            ></span>
          {{/if}}
        </div>
        <div class='tsp-event'>
          <input
            class='tsp-event-title'
            placeholder='Untitled Event'
            aria-label='Event title'
            value={{@model.eventTitle}}
            {{on 'input' this.setEventTitle}}
          />
        </div>
        <div class='tsp-meta-card'>
          <div class='tsp-meta-col'>
            <span class='tsp-meta-label'>Hosts</span>
            <div class='tsp-hosts-row'>
              {{#each this.hostChips key='key' as |h|}}
                <button
                  type='button'
                  class='tsp-host'
                  title='{{h.name}} — click to remove'
                  {{on 'click' (fn this.removeHost h.model)}}
                >
                  {{#if h.photo}}
                    <img class='tsp-host-img' src={{h.photo}} alt={{h.name}} />
                  {{else}}
                    {{h.initials}}
                  {{/if}}
                </button>
              {{/each}}
              <button
                type='button'
                class='tsp-host tsp-host-add'
                title='Add hosts'
                aria-label='Add hosts'
                {{on 'click' this.addHosts}}
              >＋{{#unless this.hostChips.length}}<span
                    class='tsp-host-add-hint'
                  >Add hosts</span>{{/unless}}</button>
            </div>
          </div>
          <div class='tsp-meta-div'></div>
          <div class='tsp-meta-col'>
            <span class='tsp-meta-label'>Date</span>
            <span class='tsp-date'>
              <input
                type='date'
                aria-label='Event date'
                value={{this.eventDateInput}}
                {{on 'change' this.setEventDate}}
              />
              {{#unless this.eventDateInput}}
                <span class='tsp-date-hint'>Pick a date</span>
              {{/unless}}
            </span>
          </div>
          <div class='tsp-meta-div'></div>
          <div class='tsp-meta-col'>
            <span class='tsp-meta-label'>Venue</span>
            <input
              class='tsp-venue'
              placeholder='Add venue'
              aria-label='Venue'
              value={{@model.venue}}
              {{on 'input' this.setVenue}}
            />
          </div>
        </div>
        <div class='tsp-actions'>
          <nav class='tsp-nav'>
            <button
              type='button'
              class='tsp-navbtn {{if this.isPlan "is-on"}}'
              {{on 'click' (fn this.setView 'plan')}}
            >Seating</button>
            <button
              type='button'
              class='tsp-navbtn {{if this.isInvites "is-on"}}'
              {{on 'click' (fn this.setView 'invites')}}
            >Invitations</button>
          </nav>
        </div>
      </header>
      {{#if this.isPlan}}
        <div class='tsp-body'>
          <aside class='tsp-rail' aria-label='Guests'>
            <div class='rail-head'>
              <span class='rail-title'>Guests</span>
              <span class='rail-total'>{{this.totalGuests}}</span>
              <span class='rail-seated'>{{this.seatedCount}}
                of
                {{this.totalGuests}}
                seated</span>
            </div>
            <div class='rail-bar'><span
                class='rail-bar-fill'
                style={{htmlBarWidth this.pct}}
              ></span></div>
            <div class='rail-search'>
              <input
                placeholder='Search guests'
                aria-label='Search guests'
                value={{this.search}}
                {{on 'input' this.onSearch}}
              />
            </div>
            <div class='rail-cats'>
              <button
                type='button'
                class='cat-pill {{unless this.activeCatId "is-on"}}'
                {{on 'click' (fn this.setCat null)}}
              >All
                <span class='dim'>{{this.totalGuests}}</span></button>
              {{#each this.catChips as |c|}}
                <button
                  type='button'
                  class='cat-pill {{if (eq this.activeCatId c.id) "is-on"}}'
                  {{on 'click' (fn this.setCat c.id)}}
                >
                  <span class='cat-swatch' style={{htmlBg c.color}}></span>
                  {{c.name}}
                  <span class='dim'>{{c.countSeated}}</span>
                </button>
              {{/each}}
            </div>
            <div class='rail-list'>
              {{#if this.guests.length}}
                {{#each this.guests as |g|}}
                  {{#if (this.railShowsGuest g)}}
                    <div
                      class='rail-guest'
                      {{on 'pointerdown' (fn this.grabGuest g)}}
                    >
                      {{#if g.photoURL}}
                        <img class='rg-avatar' src={{g.photoURL}} alt='' />
                      {{else}}
                        <span class='rg-avatar rg-initials'>{{initialsOf
                            g.fullName
                          }}</span>
                      {{/if}}
                      <span class='rg-main'>
                        <span class='rg-name-line'>
                          <span class='rg-name'>{{if
                              g.fullName
                              g.fullName
                              'Unnamed Guest'
                            }}</span>
                          {{#if g.vip}}<span class='rg-vip'>VIP</span>{{/if}}
                        </span>
                        {{#if g.category}}
                          <span class='rg-cat'>
                            <span
                              class='rg-swatch'
                              style={{htmlBg (categoryColor g.category)}}
                            ></span>
                            {{categoryLabel g.category}}
                          </span>
                        {{/if}}
                      </span>
                      {{#if (this.railPartyOf g)}}
                        <span class='rg-party'>×{{this.railPartyOf g}}</span>
                      {{/if}}
                      <button
                        type='button'
                        class='rg-edit'
                        aria-label='Edit guest'
                        title='Edit guest'
                        {{on 'pointerdown' this.stopDrag}}
                        {{on 'click' (fn this.openEditGuest g)}}
                      ><PencilIcon width='13' height='13' /></button>
                      <button
                        type='button'
                        class='rg-remove'
                        aria-label='Remove guest'
                        title='Remove from guest list'
                        {{on 'pointerdown' this.stopDrag}}
                        {{on 'click' (fn this.confirmRemoveGuest g)}}
                      ><XIcon width='13' height='13' /></button>
                    </div>
                  {{/if}}
                {{/each}}
                {{#if this.allRosterSeated}}
                  <p class='rail-empty'>All guests seated 🎉</p>
                {{/if}}
              {{else}}
                <p class='rail-empty'>No guests yet — add one below.</p>
              {{/if}}
            </div>
            <div class='rail-foot'>
              <button
                type='button'
                class='rail-add'
                {{on 'click' this.addGuests}}
              >+ Add Guests</button>
              {{#if this.guests.length}}
                <button
                  type='button'
                  class='rail-clear {{if this.confirmClearGuests "is-armed"}}'
                  {{on 'click' this.clearAllGuests}}
                >{{if
                    this.confirmClearGuests
                    'Click again to confirm'
                    'Remove all guests'
                  }}</button>
              {{/if}}
            </div>
          </aside>
          <section class='tsp-canvas-wrap'>
            <div class='canvas-toolbar'>
              <div class='ct-group ct-group-build'>
                <div class='ct-menu'>
                  <button
                    type='button'
                    class='ct-btn ct-add {{if this.addMenuOpen "is-open"}}'
                    title='Add tables, seats & decorative elements'
                    {{on 'click' this.toggleAddMenu}}
                  >＋ Add element <span class='ct-caret'>▾</span></button>
                  {{#if this.addMenuOpen}}
                    <button
                      type='button'
                      class='ct-backdrop'
                      aria-label='Close menu'
                      {{on 'click' this.closeAddMenu}}
                    ></button>
                    <div class='ct-pop'>
                      <header
                        class='pop-head ct-pop-head'
                        aria-label='Add to canvas'
                      >
                        <span class='pop-title'>Add to canvas</span>
                        <button
                          type='button'
                          class='pop-close'
                          aria-label='Close menu'
                          {{on 'click' this.closeAddMenu}}
                        >✕</button>
                      </header>
                      <button
                        type='button'
                        class='ct-pop-item ct-pop-feature ct-branch
                          {{if (eq this.addBranch "table") "is-open"}}'
                        data-add-table
                        {{on 'mouseenter' (fn this.openBranch 'table')}}
                        {{on 'mouseleave' this.scheduleCloseBranch}}
                        {{on 'click' (fn this.openBranch 'table')}}
                      >
                        <span class='ct-pop-glyph ct-table-glyph'>◯</span>
                        <span class='ct-pop-text'>
                          <span class='ct-pop-name'>Table</span>
                          <span class='ct-pop-desc'>Pick a shape — seats your
                            guests</span>
                        </span>
                        <span class='ct-branch-caret'>›</span>
                      </button>
                      <button
                        type='button'
                        class='ct-pop-item ct-pop-feature ct-branch
                          {{if (eq this.addBranch "seat") "is-open"}}'
                        data-add-seat
                        {{on 'mouseenter' (fn this.openBranch 'seat')}}
                        {{on 'mouseleave' this.scheduleCloseBranch}}
                        {{on 'click' (fn this.openBranch 'seat')}}
                      >
                        <span class='ct-pop-glyph ct-table-glyph'>•</span>
                        <span class='ct-pop-text'>
                          <span class='ct-pop-name'>Seat</span>
                          <span class='ct-pop-desc'>Single chair or a seating
                            group</span>
                        </span>
                        <span class='ct-branch-caret'>›</span>
                      </button>
                      <div class='ct-pop-title'>Elements</div>
                      <div class='ct-pop-grid'>
                        {{#each this.fixtureKinds as |k|}}
                          <button
                            type='button'
                            class='ct-pop-tile'
                            title={{k.label}}
                            {{on 'click' (fn this.addFixture k.value)}}
                          >
                            <span class='ct-pop-glyph'><FixtureGlyph
                                @kind={{k.value}}
                                @color='#c5a35c'
                                @pattern='outline'
                              /></span>
                            <span class='ct-pop-tile-label'>{{k.label}}</span>
                          </button>
                        {{/each}}
                      </div>
                    </div>
                    {{#if (eq this.addBranch 'table')}}
                      <div
                        class='ct-flyout'
                        {{on 'mouseenter' (fn this.openBranch 'table')}}
                        {{on 'mouseleave' this.scheduleCloseBranch}}
                      >
                        <div class='ct-flyout-title'>Table shape</div>
                        <div class='ct-flyout-grid'>
                          <button
                            type='button'
                            class='ct-shape'
                            {{on 'click' (fn this.addTableShape 'round')}}
                          ><span
                              class='ct-shape-g sg-round'
                            ></span>Round</button>
                          <button
                            type='button'
                            class='ct-shape'
                            {{on 'click' (fn this.addTableShape 'oval')}}
                          ><span class='ct-shape-g sg-oval'></span>Oval</button>
                          <button
                            type='button'
                            class='ct-shape'
                            {{on 'click' (fn this.addTableShape 'rect')}}
                          ><span
                              class='ct-shape-g sg-rect'
                            ></span>Rectangle</button>
                          <button
                            type='button'
                            class='ct-shape'
                            {{on 'click' (fn this.addTableShape 'square')}}
                          ><span
                              class='ct-shape-g sg-square'
                            ></span>Square</button>
                          <button
                            type='button'
                            class='ct-shape'
                            {{on 'click' (fn this.addTableShape 'curved')}}
                          ><span
                              class='ct-shape-g sg-curved'
                            ></span>Curved</button>
                        </div>
                      </div>
                    {{/if}}
                    {{#if (eq this.addBranch 'seat')}}
                      <div
                        class='ct-flyout ct-flyout-seat'
                        {{on 'mouseenter' (fn this.openBranch 'seat')}}
                        {{on 'mouseleave' this.scheduleCloseBranch}}
                      >
                        <div class='ct-flyout-title'>Seat</div>
                        <button
                          type='button'
                          class='ct-pop-item ct-pop-feature'
                          {{on 'click' this.addSeat}}
                        >
                          <span class='ct-pop-glyph ct-table-glyph'>•</span>
                          <span class='ct-pop-text'>
                            <span class='ct-pop-name'>Single seat</span>
                            <span class='ct-pop-desc'>One chair, no table</span>
                          </span>
                        </button>
                        <button
                          type='button'
                          class='ct-pop-item ct-pop-feature'
                          {{on 'click' this.addSection}}
                        >
                          <span class='ct-pop-glyph ct-table-glyph'>▦</span>
                          <span class='ct-pop-text'>
                            <span class='ct-pop-name'>Seating groups</span>
                            <span class='ct-pop-desc'>Rows of chairs (a section)</span>
                          </span>
                        </button>
                      </div>
                    {{/if}}
                  {{/if}}
                </div>
                <div class='ct-menu'>
                  <button
                    type='button'
                    class='ct-btn ct-add {{if this.templateMenuOpen "is-open"}}'
                    title='Start from a saved layout template'
                    {{on 'click' this.toggleTemplateMenu}}
                  ><TemplateIcon class='ico' />
                    Add template
                    <span class='ct-caret'>▾</span></button>
                  {{#if this.templateMenuOpen}}
                    <button
                      type='button'
                      class='ct-backdrop'
                      aria-label='Close menu'
                      {{on 'click' this.closeTemplateMenu}}
                    ></button>
                    <div class='ct-pop'>
                      <header
                        class='pop-head ct-pop-head'
                        aria-label='Start from template'
                      >
                        <span class='pop-title'>Start from template</span>
                        <button
                          type='button'
                          class='pop-close'
                          aria-label='Close menu'
                          {{on 'click' this.closeTemplateMenu}}
                        >✕</button>
                      </header>
                      {{#each this.templates as |tpl|}}
                        <div class='ct-tpl'>
                          <button
                            type='button'
                            class='ct-pop-item ct-tpl-apply'
                            {{on 'click' (fn this.applyTemplate tpl)}}
                          >
                            <span
                              class='ct-pop-glyph ct-table-glyph'
                            ><TemplateIcon class='ico' /></span>
                            <span class='ct-pop-text'>
                              <span class='ct-pop-name'>{{if
                                  tpl.name
                                  tpl.name
                                  'Untitled Template'
                                }}</span>
                              <span class='ct-pop-desc'>{{if
                                  tpl.tableCount
                                  tpl.tableCount
                                  0
                                }}
                                tables ·
                                {{if tpl.seatCount tpl.seatCount 0}}
                                seats</span>
                            </span>
                          </button>
                          <button
                            type='button'
                            class='ct-tpl-eye'
                            title='Preview this layout'
                            aria-label='Preview this layout'
                            data-bx-popover-anchor
                            data-tpl-preview={{this.tplKey tpl}}
                            {{on 'click' (fn this.openTemplatePreview tpl)}}
                          >◱</button>
                        </div>
                      {{else}}
                        <div class='ct-pop-empty'>
                          {{#if this.templatesLoading}}
                            Loading templates…
                          {{else}}
                            No templates yet — build a layout and save it.
                          {{/if}}
                        </div>
                      {{/each}}
                    </div>
                  {{/if}}
                </div>
                <button
                  type='button'
                  class='ct-btn ct-secondary'
                  title='Import a floor plan / venue drawing to trace'
                  {{on 'click' this.openFloorLibrary}}
                >⬚ Import floor plan</button>
              </div>
              <div class='ct-spacer'></div>
              <div class='ct-group ct-group-arrange'>
                <button
                  type='button'
                  class='ct-primary'
                  title='Open the AI Assistant to arrange by relationships'
                  disabled={{eq this.aiStatus 'loading'}}
                  {{on 'click' this.arrangeWithAI}}
                >{{if
                    (eq this.aiStatus 'loading')
                    'Opening…'
                    '✦ AI Arrange'
                  }}</button>
              </div>
              <div class='ct-divider'></div>
              <button
                type='button'
                class='ct-btn ct-ghost'
                title='Save this layout as a reusable template'
                disabled={{this.savingTemplate}}
                data-bx-popover-anchor
                data-save-anchor
                {{on 'click' this.openSaveTemplate}}
              ><TemplateIcon class='ico' /> Save template</button>
              <button
                type='button'
                class='ct-btn ct-ghost'
                title='Save a copy of this plan with everyone seated — reopen and edit it any time'
                disabled={{this.savingSnapshot}}
                {{on 'click' this.saveSnapshot}}
              ><CameraIcon class='ico' />
                {{if this.savingSnapshot 'Saving…' 'Save snapshot'}}</button>
            </div>
            <div
              class='canvas {{if this.spaceDown "is-pan"}}'
              {{this.registerCanvas}}
              {{on 'pointerdown' this.onCanvasDown}}
              {{on 'wheel' this.onWheel}}
            >
              {{#if @model.floorPlanURL}}
                <div class='fp-build'>
                  <div
                    class='fp-toolbar'
                    {{on 'pointerdown' this.stopProp}}
                    {{on 'wheel' this.scrollToolbar}}
                  >
                    <button
                      type='button'
                      class='fp-build-btn {{if this.aiPlanBusy "is-busy"}}'
                      disabled={{this.buildDisabled}}
                      title='Trace this floor plan into tables with AI'
                      {{on 'click' this.buildFromFloorPlan}}
                    >{{if
                        this.aiPlanBusy
                        '✦ Building…'
                        '✦ Build seats with AI'
                      }}</button>
                    <span class='fp-tool-div'></span>
                    <label class='fp-tool-opacity' title='Floor plan opacity'>
                      <span class='fp-tool-ico'>◐</span>
                      <input
                        type='range'
                        class='fp-opacity'
                        min='10'
                        max='100'
                        value={{this.floorPlanOpacity}}
                        {{on 'input' this.setFloorOpacity}}
                        {{on 'change' this.commitFloorOpacity}}
                      />
                      <span
                        class='fp-tool-val'
                      >{{this.floorPlanOpacity}}%</span>
                    </label>
                    <span class='fp-tool-div'></span>
                    <button
                      type='button'
                      class='fp-tool-btn {{if this.floorSelected "is-on"}}'
                      title='Move &amp; scale on canvas'
                      {{on 'click' this.selectFloorForEdit}}
                    ><ArrowsMoveIcon class='ico' /></button>
                    {{#if this.floorDeleteArmed}}
                      <button
                        type='button'
                        class='fp-tool-confirm'
                        title='Pick a different floor plan'
                        {{on 'click' this.replaceFloorPlan}}
                      >Replace</button>
                      <button
                        type='button'
                        class='fp-tool-confirm is-danger'
                        title='Remove this floor plan'
                        {{on 'click' this.confirmRemoveFloorPlan}}
                      >Remove</button>
                      <button
                        type='button'
                        class='fp-tool-btn'
                        title='Keep floor plan'
                        {{on 'click' this.cancelFloorDelete}}
                      >✕</button>
                    {{else}}
                      <button
                        type='button'
                        class='fp-tool-btn is-del'
                        title='Delete or replace floor plan'
                        {{on 'click' this.armFloorDelete}}
                      ><TrashIcon class='ico' /></button>
                    {{/if}}
                  </div>
                </div>
                {{#if this.floorImgBroken}}
                  <div class='fp-broken' {{on 'pointerdown' this.stopProp}}>
                    <span class='fp-broken-msg'>Floor plan image failed to load</span>
                    <button
                      type='button'
                      class='fp-broken-btn'
                      {{on 'click' this.refreshFloorImg}}
                    ><RefreshIcon class='ico' /> Refresh</button>
                  </div>
                {{/if}}
              {{/if}}
              <div class='world' style={{htmlWorld this.worldStyle}}>
                <div class='grid'></div>
                {{#if @model.floorPlanURL}}
                  <div
                    class='floorplan {{if this.floorImgBroken "is-broken"}}'
                    style={{this.floorPlanStyle}}
                  >
                    <img
                      src={{this.floorPlanSrc}}
                      alt='Floor plan'
                      draggable='false'
                      {{on 'error' this.onFloorImgError}}
                      {{on 'load' this.onFloorImgLoad}}
                    />
                  </div>
                  {{#if this.aiPlanBusy}}
                    <div
                      class='fp-generating'
                      style={{this.floorFrameStyle}}
                    ></div>
                  {{/if}}
                  {{#if this.floorSelected}}
                    <div
                      class='fp-frame'
                      style={{this.floorFrameStyle}}
                      {{on 'pointerdown' this.grabFloorPlan}}
                    >
                      <span class='fp-frame-label'>Floor plan</span>
                      <span
                        class='fp-frame-rz'
                        title='Drag to scale · hold Shift to keep proportions'
                        {{on 'pointerdown' this.grabFloorResize}}
                      ></span>
                    </div>
                  {{/if}}
                {{/if}}
                {{#each this.fixtureVMs key='id' as |fx|}}
                  <div
                    class='fx-node
                      {{if fx.selected "is-sel"}}
                      {{if fx.targeting "is-targeting"}}'
                    data-fixture={{fx.id}}
                    style={{htmlWorld fx.wrapStyle}}
                    {{on 'pointerdown' (fn this.grabFixture fx.id)}}
                  >
                    <FixtureGlyph
                      @kind={{fx.model.kind}}
                      @color={{fx.fill}}
                      @pattern={{fx.model.pattern}}
                    />
                    <span class='fx-tag'>{{fx.label}}</span>
                    {{#if fx.selected}}
                      {{#if fx.model.locked}}
                        <button
                          type='button'
                          class='rz rz-rot rz-locked'
                          title='Locked — click to unlock'
                          aria-label='Unlock element'
                          {{on 'pointerdown' this.stopProp}}
                          {{on 'click' (fn this.unlockElement 'fixture' fx.id)}}
                        ><LockIcon class='ico' /></button>
                      {{else}}
                        <span
                          class='rz rz-rot'
                          title='Drag to rotate · hold Shift to snap 15°'
                          {{on
                            'pointerdown'
                            (fn this.grabRotate 'fixture' fx.id)
                          }}
                        >↻</span>
                        <span
                          class='rz rz-e'
                          title='Drag to widen · hold Shift to scale proportionally'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'fixture' fx.id 'e')
                          }}
                        ></span>
                        <span
                          class='rz rz-w'
                          title='Drag to widen · hold Shift to scale proportionally'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'fixture' fx.id 'w')
                          }}
                        ></span>
                        <span
                          class='rz rz-s'
                          title='Drag to lengthen · hold Shift to scale proportionally'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'fixture' fx.id 's')
                          }}
                        ></span>
                        <span
                          class='rz rz-n'
                          title='Drag to lengthen · hold Shift to scale proportionally'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'fixture' fx.id 'n')
                          }}
                        ></span>
                        <span
                          class='rz rz-se'
                          title='Drag to resize · hold Shift to keep proportions'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'fixture' fx.id 'se')
                          }}
                        ></span>
                      {{/if}}
                    {{/if}}
                  </div>
                {{/each}}
                {{#each this.tableVMs key='id' as |tv|}}
                  <div
                    class='t-node
                      {{if tv.curved "is-curved"}}
                      {{if tv.isSeat "is-seat"}}
                      {{if tv.isSection "is-section"}}
                      {{if tv.selected "is-sel"}}
                      {{if tv.targeting "is-targeting"}}'
                    data-table={{tv.id}}
                    style={{htmlWorld tv.wrapStyle}}
                    {{on 'pointerdown' (fn this.grabTable tv.id)}}
                  >
                    {{#if tv.curved}}
                      <svg
                        class='t-curvedsvg'
                        viewBox='0 0 100 100'
                        preserveAspectRatio='none'
                      >
                        <path
                          class='t-curvedband'
                          d='M3 72.9 A50 50 0 0 1 97 72.9 L76.3 80.4 A28 28 0 0 0 23.7 80.4 Z'
                          stroke-width='1.5'
                          stroke-linejoin='round'
                          vector-effect='non-scaling-stroke'
                        />
                      </svg>
                      {{#if tv.vip}}<span class='t-vipdot'>VIP</span>{{/if}}
                    {{else if tv.isSeat}}
                      {{#if tv.vip}}<span class='t-vipdot'>VIP</span>{{/if}}
                    {{else if tv.isSection}}
                      <div class='t-section'></div>
                      <span class='t-section-front'>▲ stage</span>
                      {{#if tv.vip}}<span class='t-vipdot'>VIP</span>{{/if}}
                    {{else}}
                      <div class={{tv.surfaceClass}}>
                        <span class='t-motif' aria-hidden='true'></span>
                        <svg
                          class='t-center'
                          viewBox='0 0 48 48'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.3'
                          stroke-linecap='round'
                          aria-hidden='true'
                        >
                          <path d='M24 40 C24 30 24 22 24 12' />
                          <path
                            d='M24 22 C18 18 13 18 8 22 C13 27 20 27 24 22'
                          />
                          <path
                            d='M24 22 C30 18 35 18 40 22 C35 27 28 27 24 22'
                          />
                          <path d='M24 12 C21 7 21 4 24 1 C27 4 27 7 24 12' />
                          <circle cx='24' cy='40' r='2.5' />
                        </svg>
                        {{#if tv.vip}}<span class='t-vipdot'>VIP</span>{{/if}}
                      </div>
                    {{/if}}
                    <button
                      type='button'
                      class='t-edit'
                      data-bx-popover-anchor
                      data-tedit={{tv.id}}
                      title='Edit table'
                      {{on 'pointerdown' (fn this.openTablePopover tv.id)}}
                    >{{#if tv.rank}}<span
                          class='t-edit-rank'
                        >#{{tv.rank}}</span>{{/if}}<span
                        class='t-edit-ico'
                      ><PencilIcon class='ico ico-sm' /></span>Edit</button>
                    {{#each tv.seats key='index' as |s|}}
                      <div
                        class='seat
                          {{if s.filled "is-filled"}}
                          {{if s.isDrop "is-drop"}}'
                        data-seat-table={{tv.id}}
                        data-seat-index={{s.index}}
                        title={{if s.filled 'Drag to move to another seat' ''}}
                        style={{htmlSeat s.leftPct s.topPct s.color}}
                        {{on 'pointerdown' (fn this.grabSeatedGuest s.guest)}}
                        {{on 'mouseenter' (fn this.showSeatInfo s.guest)}}
                        {{on 'mousemove' this.moveSeatInfo}}
                        {{on 'mouseleave' this.hideSeatInfo}}
                      >{{#if s.isDrop}}{{#if this.draggingGuest.photoURL}}<img
                              class='seat-img'
                              src={{this.draggingGuest.photoURL}}
                              alt=''
                            />{{else}}{{this.ghostInitials}}{{/if}}{{else if
                          s.photoURL
                        }}<img
                            class='seat-img'
                            src={{s.photoURL}}
                            alt=''
                          />{{else}}{{s.label}}{{/if}}</div>
                    {{/each}}
                    <span class='t-name'>{{tv.name}}</span>
                    {{#if tv.selected}}
                      {{#if tv.model.locked}}
                        <button
                          type='button'
                          class='rz rz-rot rz-locked'
                          title='Locked — click to unlock'
                          aria-label='Unlock table'
                          {{on 'pointerdown' this.stopProp}}
                          {{on 'click' (fn this.unlockElement 'table' tv.id)}}
                        ><LockIcon class='ico' /></button>
                      {{else}}
                        {{#unless tv.isSection}}
                          <span
                            class='rz rz-rot'
                            title='Drag to rotate · hold Shift to snap 15°'
                            {{on
                              'pointerdown'
                              (fn this.grabRotate 'table' tv.id)
                            }}
                          >↻</span>
                        {{/unless}}
                        <span
                          class='rz rz-e'
                          title='Drag to widen · hold Shift to scale proportionally'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'table' tv.id 'e')
                          }}
                        ></span>
                        <span
                          class='rz rz-w'
                          title='Drag to widen · hold Shift to scale proportionally'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'table' tv.id 'w')
                          }}
                        ></span>
                        <span
                          class='rz rz-s'
                          title='Drag to lengthen · hold Shift to scale proportionally'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'table' tv.id 's')
                          }}
                        ></span>
                        <span
                          class='rz rz-n'
                          title='Drag to lengthen · hold Shift to scale proportionally'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'table' tv.id 'n')
                          }}
                        ></span>
                        <span
                          class='rz rz-se'
                          title='Drag to resize · hold Shift to keep proportions'
                          {{on
                            'pointerdown'
                            (fn this.grabResize 'table' tv.id 'se')
                          }}
                        ></span>
                      {{/if}}
                    {{/if}}
                  </div>
                {{/each}}
              </div>
              {{#if this.marquee}}
                <div class='marquee' style={{this.marqueeStyle}}></div>
              {{/if}}
              {{#if this.canAlign}}
                <div class='align-bar' {{on 'pointerdown' this.stopProp}}>
                  <span class='align-cap'>Align</span>
                  <button
                    type='button'
                    class='align-btn'
                    title='Align left'
                    {{on 'click' (fn this.alignSelected 'left')}}
                  >⇤</button>
                  <button
                    type='button'
                    class='align-btn'
                    title='Align horizontal centres'
                    {{on 'click' (fn this.alignSelected 'hcenter')}}
                  >⇔</button>
                  <button
                    type='button'
                    class='align-btn'
                    title='Align right'
                    {{on 'click' (fn this.alignSelected 'right')}}
                  >⇥</button>
                  <span class='align-div'></span>
                  <button
                    type='button'
                    class='align-btn'
                    title='Align top'
                    {{on 'click' (fn this.alignSelected 'top')}}
                  >⤒</button>
                  <button
                    type='button'
                    class='align-btn'
                    title='Align vertical centres'
                    {{on 'click' (fn this.alignSelected 'vcenter')}}
                  >⇕</button>
                  <button
                    type='button'
                    class='align-btn'
                    title='Align bottom'
                    {{on 'click' (fn this.alignSelected 'bottom')}}
                  >⤓</button>
                  {{#if this.canDistribute}}
                    <span class='align-div'></span>
                    <button
                      type='button'
                      class='align-btn'
                      title='Distribute evenly across (equal horizontal gaps)'
                      {{on 'click' (fn this.distributeSelected 'h')}}
                    >⇹</button>
                    <button
                      type='button'
                      class='align-btn'
                      title='Distribute evenly down (equal vertical gaps)'
                      {{on 'click' (fn this.distributeSelected 'v')}}
                    >⤟</button>
                  {{/if}}
                </div>
              {{/if}}
              <div class='zoom-ctl' {{on 'pointerdown' this.stopProp}}>
                <button
                  type='button'
                  class='zoom-step'
                  title='Zoom out'
                  aria-label='Zoom out'
                  disabled={{this.zoomAtMin}}
                  {{on 'click' this.zoomOut}}
                >−</button>
                <button
                  type='button'
                  class='zoom-pct'
                  title='Reset to 100%'
                  aria-label='Reset zoom to 100 percent'
                  {{on 'click' this.resetZoom}}
                >{{this.zoomPct}}</button>
                <button
                  type='button'
                  class='zoom-step'
                  title='Zoom in'
                  aria-label='Zoom in'
                  disabled={{this.zoomAtMax}}
                  {{on 'click' this.zoomIn}}
                >+</button>
                <span class='zoom-div'></span>
                <button
                  type='button'
                  class='zoom-fit'
                  title='Zoom to fit everything'
                  {{on 'click' this.fitView}}
                ><span class='zoom-fit-ico' aria-hidden='true'>⤢</span>
                  <span class='zoom-fit-lbl'>Fit</span></button>
              </div>
            </div>
            <button
              type='button'
              class='insp-handle
                {{if this.inspectorBeckons "is-beckoning"}}
                {{if this.hasInspectorSelection "has-selection"}}'
              title={{if this.inspectorCollapsed 'Show panel' 'Hide panel'}}
              aria-label={{if
                this.inspectorCollapsed
                'Show panel'
                'Hide panel'
              }}
              {{on 'click' this.toggleInspector}}
            ><span class='insp-handle-ico'>{{if
                  this.inspectorCollapsed
                  '‹'
                  '›'
                }}</span></button>
          </section>
          <aside
            class='tsp-inspector {{if this.inspectorCollapsed "is-collapsed"}}'
            aria-label='Inspector'
          >
            {{#if this.selectedTable}}
              <div class='insp-deco'></div>
              <div class='insp-pad'>
                <div class='insp-top'>
                  <input
                    class='insp-name'
                    aria-label='Table name'
                    value={{this.selectedTable.name}}
                    {{on 'input' this.renameTable}}
                  />
                  <button
                    type='button'
                    class='insp-x'
                    {{on 'click' this.deselect}}
                  >✕</button>
                </div>
                <div class='insp-status'>
                  {{this.selectedTable.seatedCount}}
                  of
                  {{this.selectedTable.seatCount}}
                  seated
                </div>
                {{#if this.selectedTableVM}}
                  <div class='insp-label'>Seat Map</div>
                  <p class='insp-seatmap-hint'>Drag a guest from the roster onto
                    a seat, drag a seated guest to another seat, or use ✕ to
                    unseat.</p>
                  <div class='insp-tablemap'>
                    <div
                      class='insp-tablemap-reserve'
                      style={{this.inspTableReserveStyle}}
                    >
                      <div
                        class='insp-tablemap-box shape-{{this.selectedTableVM.model.shape}}'
                        style={{this.inspTableBoxStyle}}
                      >
                        {{#if this.selectedTableVM.curved}}
                          <svg
                            class='t-curvedsvg'
                            viewBox='0 0 100 100'
                            preserveAspectRatio='none'
                          >
                            <path
                              class='t-curvedband'
                              d='M3 72.9 A50 50 0 0 1 97 72.9 L76.3 80.4 A28 28 0 0 0 23.7 80.4 Z'
                              stroke-width='1.5'
                              stroke-linejoin='round'
                              vector-effect='non-scaling-stroke'
                            />
                          </svg>
                        {{else if this.selectedTableVM.isSection}}
                          <span class='insp-section-front'>▲ stage</span>
                        {{/if}}
                        {{#each this.selectedTableVM.seats key='index' as |s|}}
                          <div
                            class='insp-seat
                              {{if s.filled "is-filled"}}
                              {{if s.isDrop "is-drop"}}'
                            data-seat-table={{this.selectedTableVM.id}}
                            data-seat-index={{s.index}}
                            title={{if
                              s.filled
                              'Drag to move · ✕ to unseat'
                              'Drop a guest here'
                            }}
                            style={{htmlSeat s.leftPct s.topPct s.color}}
                            {{on
                              'pointerdown'
                              (fn this.grabSeatedGuest s.guest)
                            }}
                            {{on 'mouseenter' (fn this.showSeatInfo s.guest)}}
                            {{on 'mousemove' this.moveSeatInfo}}
                            {{on 'mouseleave' this.hideSeatInfo}}
                          >
                            {{#if s.isDrop}}
                              {{#if this.draggingGuest.photoURL}}
                                <img
                                  class='insp-seat-img'
                                  src={{this.draggingGuest.photoURL}}
                                  alt=''
                                />
                              {{else}}
                                {{this.ghostInitials}}
                              {{/if}}
                            {{else if s.photoURL}}
                              <img
                                class='insp-seat-img'
                                src={{s.photoURL}}
                                alt=''
                              />
                            {{else}}
                              {{s.label}}
                            {{/if}}
                            {{#if s.filled}}
                              <button
                                type='button'
                                class='insp-seat-x'
                                title='Unseat this guest'
                                aria-label='Unseat this guest'
                                {{on 'pointerdown' this.stopPointer}}
                                {{on
                                  'click'
                                  (fn
                                    this.seatClick
                                    this.selectedTableVM.id
                                    s.index
                                  )
                                }}
                              >✕</button>
                            {{/if}}
                          </div>
                        {{/each}}
                      </div>
                    </div>
                  </div>
                {{/if}}
                <TableConfig @c={{this}} />
                <button
                  type='button'
                  class='insp-vip {{if this.selectedTable.vip "is-on"}}'
                  {{on 'click' this.toggleVip}}
                ><StarIcon class='ico' /> VIP table</button>
                <div class='insp-label'>Layer</div>
                <div class='insp-layer'>
                  <button
                    type='button'
                    class='insp-opt'
                    disabled={{this.selectedTable.locked}}
                    {{on 'click' this.sendTableBack}}
                  >↓ Send back</button>
                  <button
                    type='button'
                    class='insp-opt'
                    disabled={{this.selectedTable.locked}}
                    {{on 'click' this.bringTableFront}}
                  >↑ Bring front</button>
                  <button
                    type='button'
                    class='insp-opt insp-lock
                      {{if this.selectedTable.locked "is-on"}}'
                    {{on 'click' this.toggleTableLock}}
                  >{{#if this.selectedTable.locked}}<LockIcon class='ico' />
                      Locked — click to unlock{{else}}<LockOpenIcon
                        class='ico'
                      />
                      Lock layer{{/if}}</button>
                </div>
                <div class='insp-actionbar'>
                  <button
                    type='button'
                    class='insp-clear'
                    {{on 'click' this.clearSeats}}
                  >Clear all seats</button>
                  <div class='insp-actions'>
                    <button
                      type='button'
                      {{on 'click' this.duplicateTable}}
                    ><CopyIcon class='ico' /> Duplicate</button>
                    <button
                      type='button'
                      class='danger'
                      {{on 'click' this.confirmDeleteTable}}
                    ><TrashIcon class='ico' /> Delete</button>
                  </div>
                </div>
              </div>
            {{else if this.selectedFixture}}
              <div class='insp-deco'></div>
              <div class='insp-pad'>
                <div class='insp-top'>
                  <input
                    class='insp-name'
                    aria-label='Fixture label'
                    value={{this.selectedFixture.label}}
                    {{on 'input' this.renameFixture}}
                  />
                  <button
                    type='button'
                    class='insp-x'
                    {{on 'click' this.deselect}}
                  >✕</button>
                </div>
                <div class='insp-status'>{{get
                    FIXTURE_KIND_LABELS
                    this.selectedFixture.kind
                  }}</div>
                <div class='insp-fxart'><span
                    class='insp-fxart-box'
                    style={{this.selectedFxArtStyle}}
                  ><FixtureGlyph
                      @kind={{this.selectedFixture.kind}}
                      @color={{this.selectedFxFill}}
                      @pattern={{this.selectedFixture.pattern}}
                    /></span></div>
                <div class='insp-label'>Colour</div>
                <div class='insp-swatches'>
                  <label class='insp-fxpick' title='Custom colour'>
                    <input
                      type='color'
                      value={{this.selectedFxFill}}
                      {{on 'input' this.fxColorInput}}
                      {{on 'change' this.fxColorCommit}}
                    />
                  </label>
                  {{#each this.themeSwatches as |sw|}}
                    <button
                      type='button'
                      class='insp-sw
                        {{if (this.fixtureColorIs sw.value) "is-on"}}'
                      style={{htmlBg sw.value}}
                      title={{sw.label}}
                      {{on 'click' (fn this.setFxColor sw.value)}}
                    ></button>
                  {{/each}}
                </div>
                <div class='insp-label'>Layer</div>
                <div class='insp-layer'>
                  <button
                    type='button'
                    class='insp-opt'
                    disabled={{this.selectedFixture.locked}}
                    {{on 'click' this.sendFxBack}}
                  >↓ Send back</button>
                  <button
                    type='button'
                    class='insp-opt'
                    disabled={{this.selectedFixture.locked}}
                    {{on 'click' this.bringFxFront}}
                  >↑ Bring front</button>
                  <button
                    type='button'
                    class='insp-opt insp-lock
                      {{if this.selectedFixture.locked "is-on"}}'
                    {{on 'click' this.toggleFixtureLock}}
                  >{{#if this.selectedFixture.locked}}<LockIcon class='ico' />
                      Locked — click to unlock{{else}}<LockOpenIcon
                        class='ico'
                      />
                      Lock layer{{/if}}</button>
                </div>
                <div class='insp-actionbar'>
                  <div class='insp-actions'>
                    <button
                      type='button'
                      {{on 'click' this.duplicateFixture}}
                    ><CopyIcon class='ico' /> Duplicate</button>
                    <button
                      type='button'
                      class='danger'
                      {{on 'click' this.confirmDeleteFixture}}
                    ><TrashIcon class='ico' /> Delete</button>
                  </div>
                </div>
              </div>
            {{else if this.multiSelected}}
              <div class='insp-deco'></div>
              <div class='insp-pad'>
                <div class='insp-kicker'>Selection</div>
                <div class='insp-hero'>{{this.selCount}} selected</div>
                <p class='insp-lead'>Drag any one to move them together, nudge
                  with the arrow keys, or delete. Shift-click an element to add
                  or remove it.</p>
                {{#if this.selectionHasTables}}
                  <div class='insp-label'>Table Shape</div>
                  <div class='insp-grid4'>
                    {{#each this.tableShapes as |sh|}}
                      <button
                        type='button'
                        class='insp-opt
                          {{if (eq this.selectionShape sh.value) "is-on"}}'
                        {{on 'click' (fn this.setSelectionShape sh.value)}}
                      >{{sh.label}}</button>
                    {{/each}}
                  </div>
                {{/if}}
                <div class='insp-label'>Colour</div>
                <div class='insp-swatches'>
                  <label class='insp-fxpick' title='Custom colour'>
                    <input
                      type='color'
                      value={{this.selectionColorValue}}
                      {{on 'change' this.selectionColorCommit}}
                    />
                  </label>
                  {{#each this.themeSwatches as |sw|}}
                    <button
                      type='button'
                      class='insp-sw'
                      style={{htmlBg sw.value}}
                      title={{sw.label}}
                      {{on 'click' (fn this.setSelectionColor sw.value)}}
                    ></button>
                  {{/each}}
                </div>
                {{#if this.selectionHasSeated}}
                  <div class='insp-label'>Seating</div>
                  <div class='insp-layer'>
                    <button
                      type='button'
                      class='insp-opt'
                      {{on 'click' this.clearSelectionSeats}}
                    >Clear seats</button>
                  </div>
                {{/if}}
                <div class='insp-actions'>
                  <button
                    type='button'
                    class='danger'
                    {{on 'click' this.confirmDeleteSelected}}
                  >Delete selected</button>
                </div>
              </div>
            {{else}}
              <div class='insp-deco'></div>
              <div class='insp-pad'>
                <div class='insp-kicker'>Compose</div>
                <div class='insp-hero'>Arrange the room</div>
                <div class='insp-progress'>
                  <div class='insp-progress-head'>
                    <span class='insp-progress-label'>Seated</span>
                    <span class='insp-progress-count'>{{this.seatedCount}}
                      of
                      {{this.totalGuests}}</span>
                  </div>
                  <div class='insp-progress-bar'><span
                      class='insp-progress-fill'
                      style={{htmlBarWidth this.pct}}
                    ></span></div>
                </div>
                <p class='insp-lead'>Use
                  <b>＋ Add</b>
                  to place tables, or
                  <b>✦ AI Arrange</b>
                  to seat everyone. Select a table to seat guests here.</p>
                <div class='insp-legend-title'>Categories</div>
                <div class='insp-legend'>
                  {{#each this.catChips as |c|}}
                    <div class='insp-legend-row'>
                      <span class='cat-swatch' style={{htmlBg c.color}}></span>
                      <span class='ilr-name'>{{c.name}}</span>
                      <span class='ilr-count'>{{c.countSeated}}</span>
                    </div>
                  {{else}}
                    <p class='rail-empty'>No categories yet.</p>
                  {{/each}}
                </div>
                <div class='insp-help'>
                  <div class='insp-help-title'>Need help?</div>
                  <p class='insp-help-lead'>Drag guests from the left rail onto
                    any seat, or let
                    <b>✦ AI Arrange</b>
                    compose the room for you.</p>
                </div>
              </div>
            {{/if}}
          </aside>
        </div>
      {{else}}
        <div class='tsp-invites'>
          <section class='inv-studio'>
            <div class='inv-kicker'>Invitation</div>
            <h2 class='inv-h'>Invitations</h2>
            <p class='inv-lead'>Send everyone the invitation — the poster plus a
              personalised message.</p>
            <div class='inv-poster-row'>
              <div class='poster'>
                {{#if this.posterLink}}
                  <img
                    class='poster-img'
                    src={{this.posterLink}}
                    alt='Invitation poster'
                  />
                {{else}}
                  <div class='poster-empty' style={{this.posterAspectStyle}}>
                    {{#if this.eventLogoURL}}
                      <img
                        class='poster-empty-logo'
                        src={{this.eventLogoURL}}
                        alt=''
                      />
                    {{else}}
                      <span
                        class='poster-empty-mark'
                        data-initials={{this.eventInitials}}
                      ></span>
                    {{/if}}
                    <span class='poster-empty-title'>No poster yet</span>
                    <span class='poster-empty-hint'>Generate one with AI on the
                      right, or paste an image in the edit view.</span>
                  </div>
                {{/if}}
              </div>
              <div class='inv-ai'>
                <div class='inv-label'>Generate with AI</div>
                <p class='inv-ai-lead'>Click
                  <b>✦ Generate poster</b>
                  and AI will create your poster from your hosts, event name,
                  date &amp; venue, in the size you select below. Add an extra
                  prompt if you want to describe the image yourself.</p>
                <div
                  class='inv-aspects'
                  role='radiogroup'
                  aria-label='Poster size'
                >
                  {{#each this.posterAspects as |a|}}
                    <button
                      type='button'
                      class='inv-aspect
                        {{if (eq this.posterAspect a.value) "is-on"}}'
                      aria-pressed={{if
                        (eq this.posterAspect a.value)
                        'true'
                        'false'
                      }}
                      {{on 'click' (fn this.setPosterAspect a.value)}}
                    >{{a.label}}</button>
                  {{/each}}
                </div>
                <textarea
                  class='inv-msg inv-ai-prompt'
                  aria-label='Extra style directions for the AI poster'
                  placeholder='Optional style directions (markdown) — only if you want a special design, e.g. watercolor florals, blush pink & gold, art-deco…'
                  value={{if @model.posterPrompt @model.posterPrompt ''}}
                  {{on 'input' this.onPosterPromptInput}}
                ></textarea>
                <button
                  type='button'
                  class='inv-ai-generate'
                  disabled={{this.posterBusy}}
                  {{on 'click' this.generatePoster}}
                >{{if
                    this.posterBusy
                    'Generating…'
                    '✦ Generate poster'
                  }}</button>
                {{#if this.posterLink}}
                  <button
                    type='button'
                    class='inv-download'
                    {{on 'click' this.downloadPoster}}
                  ><DownloadIcon class='ico' /> Download poster</button>
                  <button
                    type='button'
                    class='inv-ai-clear'
                    {{on 'click' this.clearPoster}}
                  >Remove image</button>
                {{/if}}
              </div>
            </div>
          </section>
          <aside class='inv-list' aria-label='Invitation guests'>
            <div class='inv-search'>
              <span class='inv-search-ico'><SearchIcon class='ico' /></span>
              <input
                class='inv-search-input'
                type='search'
                placeholder='Search guests by name'
                aria-label='Search guests by name'
                value={{this.inviteSearch}}
                {{on 'input' this.onInviteSearch}}
              />
              {{#if this.inviteSearch}}
                <button
                  type='button'
                  class='inv-search-clear'
                  aria-label='Clear search'
                  {{on 'click' this.clearInviteSearch}}
                >✕</button>
              {{/if}}
            </div>
            <div class='inv-list-head'>Invite
              {{this.totalGuests}}
              guests</div>
            <p class='inv-list-note'>Edit the message below — each guest's Copy
              button fills in their tokens for you.</p>
            <div class='inv-label'>Invite message</div>
            <textarea
              class='inv-msg'
              aria-label='Invite message'
              value={{this.inviteTemplate}}
              {{on 'input' this.onInviteTemplateInput}}
            ></textarea>
            <p class='inv-tokens'>Tokens: {name} · {event} · {date} · {venue} ·
              {hosts} · {poster}</p>
            {{#each this.inviteRows as |row|}}
              <div class='inv-row'>
                <span class='inv-av'>{{row.initials}}</span>
                <div class='inv-row-main'>
                  <div class='inv-row-name'>{{if
                      row.model.fullName
                      row.model.fullName
                      'Guest'
                    }}</div>
                </div>
                <button
                  type='button'
                  class='inv-btn copy'
                  {{on 'click' (fn this.copyText row.msg)}}
                >Copy</button>
                <button
                  type='button'
                  class='inv-edit'
                  aria-label='Edit guest details'
                  title='Edit details'
                  {{on 'click' (fn this.openEditGuest row.model)}}
                ><PencilIcon class='inv-edit-ico' /></button>
              </div>
            {{else}}
              <p class='rail-empty'>{{if
                  this.inviteSearch
                  'No guests match your search.'
                  'No guests yet.'
                }}</p>
            {{/each}}
          </aside>
        </div>
      {{/if}}
      {{#if this.pendingDelete}}
        <SeatingPlanPopover
          @anchor='[data-tsp-root]'
          @onClose={{this.cancelDelete}}
          @kicker='Confirm'
          @title={{this.pendingDelete.title}}
          @label={{this.pendingDelete.title}}
          @kind='details'
          @anchoring='center'
          @backdrop='dim'
          @elevation='raised'
          @width={{320}}
        >
          <:body>
            <p class='confirm-detail'>{{this.pendingDelete.detail}}</p>
          </:body>
          <:foot>
            <div class='pop-actions'>
              <button
                type='button'
                class='modal-cancel'
                {{on 'click' this.cancelDelete}}
              >Cancel</button>
              <button
                type='button'
                class='confirm-danger'
                {{on 'click' this.confirmDelete}}
              ><TrashIcon class='ico' /> Delete</button>
            </div>
          </:foot>
        </SeatingPlanPopover>
      {{/if}}
      {{#if this.toast}}
        <div class='tsp-toast'>✦
          {{this.toast}}
          {{#if this.toastAction}}
            <button
              type='button'
              class='tsp-toast-action'
              {{on 'click' this.runToastAction}}
            >{{this.toastAction.label}}</button>
            <button
              type='button'
              class='tsp-toast-close'
              aria-label='Dismiss'
              {{on 'click' this.dismissToast}}
            >✕</button>
          {{/if}}
        </div>
      {{/if}}
      {{#if this.draggingGuest}}
        <div class='drag-ghost' style={{htmlGhost this.ghostX this.ghostY}}>
          {{#if this.draggingGuest.photoURL}}
            <img class='dg-photo' src={{this.draggingGuest.photoURL}} alt='' />
          {{else}}
            <span class='dg-init'>{{this.ghostInitials}}</span>
          {{/if}}
        </div>
      {{/if}}
      {{#if this.hoverGuest}}
        <div class='seat-info' {{this.positionTip this.hoverX this.hoverY}}>
          <div class='si-top'>
            {{#if this.hoverGuest.photoURL}}
              <img class='si-photo' src={{this.hoverGuest.photoURL}} alt='' />
            {{else}}
              <span class='si-photo si-init'>{{this.hoverInitials}}</span>
            {{/if}}
            <div class='si-id'>
              <div class='si-name'>{{if
                  this.hoverGuest.fullName
                  this.hoverGuest.fullName
                  'Unnamed Guest'
                }}{{#if this.hoverGuest.vip}}
                  <span class='si-vip'>VIP</span>
                {{/if}}</div>
              {{#if this.hoverGuest.category}}
                <div class='si-cat'>
                  <span
                    class='si-swatch'
                    style={{htmlBg (categoryColor this.hoverGuest.category)}}
                  ></span>
                  {{categoryLabel this.hoverGuest.category}}
                </div>
              {{/if}}
            </div>
          </div>
          {{#if this.hoverParty}}
            <div class='si-line'>Party of {{this.hoverParty}}</div>
          {{/if}}
        </div>
      {{/if}}
      {{#if this.showFloorLibrary}}
        <SeatingPlanPopover
          @anchor='[data-tsp-root]'
          @onClose={{this.closeFloorLibrary}}
          @kicker='Floor Plan'
          @title='Add & trace a floor plan'
          @label='Add and trace a floor plan'
          @kind='details'
          @anchoring='center'
          @backdrop='dim'
          @elevation='raised'
          @width={{560}}
        >
          <:body>
            <p class='ai-lead'>Add a venue drawing (image) from your computer —
              it's saved to your workspace and lands on the canvas right away —
              or link one you saved before. Then let AI trace the tables &amp;
              features for you.</p>
            <label class='fp-import {{if this.fpImporting "is-busy"}}'>
              <input
                type='file'
                accept='image/*,.pdf,application/pdf'
                disabled={{this.fpImporting}}
                {{on 'change' this.importFloorPlanCard}}
              />
              <span class='fp-import-glyph'>⬚</span>
              <span class='fp-import-text'>{{if
                  this.fpImporting
                  'Adding…'
                  'Add a new floor plan…'
                }}</span>
            </label>
            <button
              type='button'
              class='fp-import fp-link'
              {{on 'click' this.linkFloorPlan}}
            >
              <span class='fp-import-glyph'>⛓</span>
              <span class='fp-import-text'>Link an existing floor plan…</span>
            </button>
          </:body>
          <:foot>
            <div class='pop-actions'>
              <button
                type='button'
                class='modal-cancel'
                {{on 'click' this.closeFloorLibrary}}
              >Close</button>
            </div>
          </:foot>
        </SeatingPlanPopover>
      {{/if}}
      {{#if this.showSaveTemplate}}
        <SeatingPlanPopover
          @anchor='[data-save-anchor]'
          @onClose={{this.closeSaveTemplate}}
          @title='Save this layout'
          @label='Save layout as template'
          @kind='edit'
          @placement='bottom-end'
          @width={{340}}
        >
          <:body>
            <p class='pop-lead'>Store the current tables &amp; elements as a
              reusable template. Guests aren’t included.</p>
            <label class='save-field'>
              <span class='save-field-label'>Template name</span>
              <input
                class='save-input'
                value={{this.templateName}}
                placeholder='e.g. Garden reception'
                autocomplete='off'
                {{on 'input' this.onTemplateNameInput}}
              />
            </label>
            {{#if this.templateError}}
              <p class='save-error'>{{this.templateError}}</p>
            {{/if}}
          </:body>
          <:foot>
            <div class='pop-actions'>
              <button
                type='button'
                class='modal-cancel'
                {{on 'click' this.closeSaveTemplate}}
              >Cancel</button>
              <button
                type='button'
                class='modal-save'
                disabled={{this.savingTemplate}}
                {{on 'click' this.confirmSaveTemplate}}
              >{{if this.savingTemplate 'Saving…' 'Save template'}}</button>
            </div>
          </:foot>
        </SeatingPlanPopover>
      {{/if}}
      {{#if this.previewTemplate}}
        <SeatingPlanPopover
          @anchor={{this.previewAnchor}}
          @onClose={{this.closeTemplatePreview}}
          @title={{if
            this.previewTemplate.name
            this.previewTemplate.name
            'Layout'
          }}
          @label='Layout preview'
          @kind='details'
          @placement='right-start'
          @offset={{22}}
          @width={{300}}
        >
          <:body>
            <div class='preview-body'>
              <LayoutPreview
                @tables={{this.previewTemplate.tables}}
                @fixtures={{this.previewTemplate.fixtures}}
              />
            </div>
          </:body>
          <:foot>
            <div class='preview-foot'>
              <span class='preview-meta'>{{if
                  this.previewTemplate.tableCount
                  this.previewTemplate.tableCount
                  0
                }}
                tables ·
                {{if
                  this.previewTemplate.seatCount
                  this.previewTemplate.seatCount
                  0
                }}
                seats</span>
              <button
                type='button'
                class='modal-save preview-apply'
                {{on 'click' (fn this.applyTemplate this.previewTemplate)}}
              >Use this layout</button>
            </div>
          </:foot>
        </SeatingPlanPopover>
      {{/if}}
      {{#if this.popoverTableKey}}
        {{#if this.selectedTable}}
          <SeatingPlanPopover
            @anchor={{this.tablePopoverAnchor}}
            @onClose={{this.closeTablePopover}}
            @label='Edit table'
          >
            <:header>
              <div class='tpop-hwrap'>
                <div class='tpop-head'>
                  <input
                    class='tpop-name'
                    aria-label='Table name'
                    value={{this.selectedTable.name}}
                    {{on 'input' this.renameTable}}
                  />
                  <button
                    type='button'
                    class='tpop-vip {{if this.selectedTable.vip "is-on"}}'
                    title='Toggle VIP'
                    {{on 'click' this.toggleVip}}
                  ><StarIcon class='ico' /></button>
                </div>
                <div class='tpop-status'>{{this.selectedTable.seatedCount}}
                  of
                  {{this.selectedTable.seatCount}}
                  seated</div>
              </div>
            </:header>
            <:body>
              <TableConfig @c={{this}} />
              <div class='tpop-hint'>#1 = nearest the front / stage. Leave on
                Auto to rank by floor position.</div>
              <div class='tpop-label'>Layer</div>
              <div class='tpop-layer'>
                <button
                  type='button'
                  disabled={{this.selectedTable.locked}}
                  {{on 'click' this.sendTableBack}}
                >↓ Send back</button>
                <button
                  type='button'
                  disabled={{this.selectedTable.locked}}
                  {{on 'click' this.bringTableFront}}
                >↑ Bring front</button>
                <button
                  type='button'
                  class='tpop-lock {{if this.selectedTable.locked "is-on"}}'
                  {{on 'click' this.toggleTableLock}}
                >{{#if this.selectedTable.locked}}<LockIcon class='ico' />
                    Locked — click to unlock{{else}}<LockOpenIcon class='ico' />
                    Lock layer{{/if}}</button>
              </div>
            </:body>
            <:foot>
              <div class='tpop-actions'>
                <button
                  type='button'
                  {{on 'click' this.popoverDuplicate}}
                ><CopyIcon class='ico' /> Duplicate</button>
                <button
                  type='button'
                  class='danger'
                  {{on 'click' this.popoverDelete}}
                ><TrashIcon class='ico' /> Delete</button>
              </div>
            </:foot>
          </SeatingPlanPopover>
        {{/if}}
      {{/if}}
    </div>
    <style scoped>
      @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400..700;1,400..700&family=Jost:ital,wght@0,300..600;1,300..600&display=swap');
      .ico {
        width: 14px;
        height: 14px;
        flex: none;
        display: inline-block;
        vertical-align: -2px;
      }
      .ico-sm {
        width: 12px;
        height: 12px;
      }
      .tsp {
        height: 100%;
        min-height: 720px;
        display: flex;
        flex-direction: column;
        background: var(--paper, #faf6ec);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        overflow: hidden;
        container-type: inline-size;
        container-name: tsp;
        --z-canvas-overlay: 60;
        --z-toolbar: 100;
        --z-inspector: 105;
        --z-handle: 110;
      }
      .tsp-head,
      .tsp-rail {
        --surface: var(--navy-2, #1a2238);
        --surface-edge: var(--navy-edge, rgba(255, 255, 255, 0.1));
        --ink: var(--navy-ink, #f3ead6);
        --gold: #e3c27d;
        --gold-soft: #f4e4b6;
        --gold-grad: linear-gradient(135deg, #f6e7b8, #e3c27d 55%, #c09a55);
        color: var(--ink, #22283f);
      }
      .tsp-head {
        min-height: 70px;
        flex: none;
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 10px 26px;
        padding: 10px 26px;
        background: var(--navy, #141b33);
        border-bottom: 1px solid rgba(197, 163, 92, 0.45);
      }
      .tsp-brand {
        flex: none;
        width: 46px;
        height: 46px;
        border-radius: 50%;
        display: grid;
        place-items: center;
        overflow: hidden;
        background: var(
          --gold-grad,
          linear-gradient(135deg, #e6cf9a, #c5a35c 55%, #a5854a)
        );
        color: var(--navy, #141b33);
        border: 1px solid var(--gold-soft, #e6cf9a);
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.25);
      }
      .tsp-brand-img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .tsp-brand-mark::before {
        content: var(--tsp-motif, attr(data-initials));
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-weight: 700;
        font-size: 22px;
        line-height: 1;
      }
      .tsp-event {
        flex: 1 1 auto;
        min-width: 160px;
      }
      .tsp-actions {
        display: flex;
        align-items: center;
        gap: 12px;
        margin-left: auto;
      }
      .tsp-event-title {
        display: block;
        width: 100%;
        appearance: none;
        background: transparent;
        border: none;
        border-bottom: 1px solid transparent;
        border-radius: 0;
        padding: 0 0 2px;
        color: var(--gold-soft, #e6cf9a);
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-weight: 600;
        font-size: 28px;
        line-height: 1.15;
        transition: border-color 0.15s;
      }
      .tsp-event-title::placeholder {
        color: var(--gold-soft, #e6cf9a);
        opacity: 0.55;
      }
      .tsp-event-title:hover {
        border-bottom-color: rgba(197, 163, 92, 0.35);
      }
      .tsp-event-title:focus {
        outline: none;
        border-bottom-color: var(--gold, #c5a35c);
      }
      .tsp-meta-card {
        display: flex;
        align-items: stretch;
        gap: 26px;
        padding: 8px 20px;
        border-radius: 14px;
        background: rgba(255, 255, 255, 0.05);
        border: 1px solid var(--navy-edge, rgba(255, 255, 255, 0.1));
      }
      .tsp-meta-col {
        display: flex;
        flex-direction: column;
        justify-content: center;
        gap: 5px;
      }
      .tsp-meta-div {
        width: 1px;
        background: var(--navy-edge, rgba(255, 255, 255, 0.1));
      }
      .tsp-meta-label {
        font-size: 8.5px;
        font-weight: 500;
        letter-spacing: 0.3em;
        text-transform: uppercase;
        color: rgba(243, 234, 214, 0.55);
      }
      .tsp-hosts-row {
        display: flex;
        align-items: center;
        min-height: 34px;
      }
      .tsp-host {
        width: 34px;
        height: 34px;
        margin-right: -8px;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: 50%;
        border: 1.5px solid var(--gold, #c5a35c);
        background: var(--navy-2, #1a2238);
        color: var(--gold-soft, #e6cf9a);
        font:
          600 12px 'Cormorant Garamond',
          serif;
        overflow: hidden;
        cursor: pointer;
        transition: 0.15s;
      }
      .tsp-host:hover {
        border-color: #e0857a;
        color: #e0857a;
        z-index: 1;
      }
      .tsp-host-img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .tsp-host-add {
        margin-right: 0;
        margin-left: 4px;
        width: auto;
        min-width: 34px;
        padding: 0 4px;
        gap: 5px;
        border-style: dashed;
        border-color: rgba(197, 163, 92, 0.55);
        background: transparent;
        color: var(--gold, #c5a35c);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 14px;
      }
      .tsp-host-add-hint {
        font-size: 10px;
        font-weight: 500;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        padding-right: 4px;
        white-space: nowrap;
      }
      .tsp-host-add:has(.tsp-host-add-hint) {
        border-radius: 30px;
        padding: 0 10px;
      }
      .tsp-host-add:hover {
        border-color: var(--gold, #c5a35c);
        color: var(--gold-soft, #e6cf9a);
      }
      .tsp-date {
        position: relative;
        display: flex;
        align-items: center;
        gap: 6px;
        min-height: 34px;
        cursor: pointer;
      }
      .tsp-date-hint {
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        display: flex;
        align-items: center;
        font-size: 10px;
        font-weight: 500;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: rgba(243, 234, 214, 0.5);
        pointer-events: none;
      }
      .tsp-date:has(.tsp-date-hint) input[type='date'] {
        color: transparent;
      }
      .tsp-date input[type='date'] {
        border: none;
        background: transparent;
        color: var(--gold, #c5a35c);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10.5px;
        font-weight: 500;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color-scheme: dark;
        cursor: pointer;
        padding: 0;
      }
      .tsp-date input[type='date']:focus {
        outline: none;
        border-bottom: 1px solid rgba(197, 163, 92, 0.5);
      }
      .tsp-venue {
        min-height: 34px;
        width: 150px;
        border: none;
        background: transparent;
        color: var(--gold, #c5a35c);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10.5px;
        font-weight: 500;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        padding: 0;
      }
      .tsp-venue::placeholder {
        color: rgba(243, 234, 214, 0.5);
      }
      .tsp-venue:focus {
        outline: none;
        border-bottom: 1px solid rgba(197, 163, 92, 0.5);
      }
      .tsp-nav {
        display: flex;
        gap: 6px;
      }
      .tsp-navbtn {
        height: 34px;
        padding: 0 18px;
        border-radius: 30px;
        border: 1px solid transparent;
        background: transparent;
        color: var(--gold, #c5a35c);
        font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        font-size: 11px;
        font-weight: 500;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        cursor: pointer;
        transition: 0.15s;
      }
      .tsp-navbtn:hover {
        color: var(--gold-soft, #e6cf9a);
        border-color: rgba(197, 163, 92, 0.5);
      }
      .tsp-navbtn.is-on {
        background: var(--popover, #fdfaf2);
        color: var(--navy, #141b33);
      }
      .tsp-body {
        flex: 1;
        display: flex;
        min-height: 0;
      }
      @container tsp (max-width: 1100px) {
        .tsp-head {
          gap: 16px;
          padding: 8px 16px;
        }
        .tsp-rail {
          width: 260px;
        }
        .tsp-inspector {
          width: 280px;
        }
      }
      @container tsp (max-width: 860px) {
        .tsp-head {
          gap: 8px 12px;
          padding: 10px 16px;
        }
        .tsp-event {
          order: 1;
          flex: 1 1 0;
        }
        .tsp-actions {
          order: 2;
        }
        .tsp-meta-card {
          order: 3;
          flex: 1 1 100%;
          gap: 16px;
          padding: 6px 14px;
        }
        .tsp-event-title {
          font-size: 17px;
        }
        .tsp-rail {
          width: 220px;
        }
        .tsp-inspector {
          width: 240px;
        }
      }
      @container tsp (max-width: 680px) {
        .tsp-rail {
          width: 200px;
        }
        .tsp-inspector {
          width: 0;
          overflow: hidden;
          border-left: none;
        }
      }
      @container tsp (max-width: 520px) {
        .tsp-rail {
          width: 160px;
        }
      }
      .tsp-rail {
        width: 320px;
        flex: none;
        display: flex;
        flex-direction: column;
        min-height: 0;
        background: var(--navy, #141b33);
        border-right: 1px solid rgba(197, 163, 92, 0.35);
      }
      .rail-head {
        display: flex;
        align-items: baseline;
        gap: 10px;
        padding: 20px 20px 10px;
      }
      .rail-title {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 28px;
        font-weight: 600;
      }
      .rail-total {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 28px;
        font-weight: 600;
        color: var(--gold, #c5a35c);
      }
      .rail-seated {
        margin-left: auto;
        font-size: 10px;
        font-weight: 500;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--gold, #c5a35c);
        text-align: right;
      }
      .rail-bar {
        height: 2px;
        margin: 0 20px;
        background: var(--navy-edge, rgba(255, 255, 255, 0.1));
        border-radius: 2px;
        overflow: hidden;
      }
      .rail-bar-fill {
        display: block;
        height: 100%;
        background: var(
          --gold-grad,
          linear-gradient(135deg, #e6cf9a, #c5a35c 55%, #a5854a)
        );
        transition: width 0.4s ease;
      }
      .rail-search {
        padding: 14px 20px 8px;
      }
      .rail-search input {
        width: 100%;
        height: 38px;
        padding: 0 14px;
        border-radius: 9px;
        border: 1px solid var(--navy-edge, rgba(255, 255, 255, 0.1));
        background: rgba(255, 255, 255, 0.06);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        font-size: 14px;
        outline: none;
      }
      .rail-search input::placeholder {
        color: var(--ink, #22283f);
        opacity: 0.5;
      }
      .rail-search input:focus {
        border-color: rgba(197, 163, 92, 0.6);
      }
      .rail-cats {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        padding: 4px 20px 12px;
      }
      .cat-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 5px 10px;
        border-radius: 999px;
        border: 1px solid var(--navy-edge, rgba(255, 255, 255, 0.1));
        background: rgba(255, 255, 255, 0.04);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        font-size: 12px;
        cursor: pointer;
        transition: 0.15s;
      }
      .cat-pill:hover {
        border-color: var(--gold, #c5a35c);
      }
      .cat-pill.is-on {
        background: var(
          --gold-grad,
          linear-gradient(135deg, #e6cf9a, #c5a35c 55%, #a5854a)
        );
        color: var(--navy, #141b33);
        border-color: transparent;
      }
      .cat-pill .dim {
        opacity: 0.55;
      }
      .cat-swatch {
        width: 9px;
        height: 9px;
        border-radius: 2px;
      }
      .rail-list {
        flex: 1;
        overflow-y: auto;
        padding: 4px 14px 10px;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .rail-guest {
        position: relative;
        cursor: grab;
        touch-action: none;
        transition: transform 0.1s ease;
        flex: none;
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 9px 12px;
        border: 1px solid var(--navy-edge, rgba(255, 255, 255, 0.1));
        border-radius: 11px;
        background: var(--navy-2, #1a2238);
        font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        color: var(--ink, #22283f);
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.18);
      }
      .rail-guest:hover {
        transform: translateY(-1px);
        border-color: var(--gold, #c5a35c);
      }
      .rail-guest:active {
        cursor: grabbing;
      }
      .rg-avatar {
        width: 38px;
        height: 38px;
        border-radius: 50%;
        flex: none;
        object-fit: cover;
      }
      .rg-initials {
        display: flex;
        align-items: center;
        justify-content: center;
        font:
          600 13px 'Cormorant Garamond',
          serif;
        color: var(--navy, #141b33);
        background: var(
          --gold-grad,
          linear-gradient(135deg, #e6cf9a, #c5a35c 55%, #a5854a)
        );
      }
      .rg-main {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 3px;
      }
      .rg-name-line {
        display: flex;
        align-items: center;
        gap: 7px;
      }
      .rg-name {
        font-size: 14px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .rg-vip {
        flex: none;
        font:
          600 8px 'Jost',
          sans-serif;
        letter-spacing: 0.12em;
        color: var(--navy, #141b33);
        background: var(--gold, #c5a35c);
        border-radius: 4px;
        padding: 2px 5px;
      }
      .rg-cat {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 11px;
        color: rgba(243, 234, 214, 0.6);
      }
      .rg-swatch {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        flex: none;
      }
      .rg-party {
        flex: none;
        font:
          11px 'Jost',
          sans-serif;
        color: var(--gold, #c5a35c);
        border: 1px solid rgba(197, 163, 92, 0.45);
        border-radius: 999px;
        padding: 2px 8px;
      }
      .rg-edit {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 26px;
        height: 26px;
        border-radius: 50%;
        border: 1px solid rgba(255, 255, 255, 0.16);
        background: transparent;
        color: rgba(243, 234, 214, 0.65);
        cursor: pointer;
        transition: 0.15s;
      }
      .rg-edit:hover {
        border-color: var(--gold, #c5a35c);
        color: var(--gold, #c5a35c);
      }
      .rg-remove {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 26px;
        height: 26px;
        border-radius: 50%;
        border: 1px solid rgba(255, 255, 255, 0.16);
        background: transparent;
        color: rgba(243, 234, 214, 0.65);
        cursor: pointer;
        transition: 0.15s;
      }
      .rg-remove:hover {
        border-color: #a8543f;
        color: #a8543f;
      }
      .rail-empty {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-style: italic;
        font-size: 15px;
        color: var(--gold, #c5a35c);
        padding: 8px 4px;
      }
      .rail-foot {
        flex: none;
        padding: 14px 20px;
        border-top: 1px solid var(--navy-edge, rgba(255, 255, 255, 0.1));
      }
      .rail-add {
        width: 100%;
        height: 44px;
        border: none;
        background: var(
          --gold-grad,
          linear-gradient(135deg, #e6cf9a, #c5a35c 55%, #a5854a)
        );
        color: var(--navy, #141b33);
        border-radius: 30px;
        font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        font-size: 11px;
        font-weight: 600;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        cursor: pointer;
        transition: 0.15s;
        box-shadow: 0 6px 16px rgba(197, 163, 92, 0.25);
      }
      .rail-add:hover {
        filter: brightness(1.06);
      }
      .rail-clear {
        width: 100%;
        margin-top: 8px;
        border: none;
        background: transparent;
        color: var(--gold, #c5a35c);
        font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
        font-size: 10px;
        font-weight: 500;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        padding: 6px 0;
        cursor: pointer;
        transition: 0.15s;
      }
      .rail-clear:hover {
        color: #e0857a;
      }
      .rail-clear.is-armed {
        color: #e0857a;
        border: 1px solid rgba(212, 122, 106, 0.5);
        border-radius: 30px;
      }
      .tsp-canvas-wrap {
        flex: 1;
        display: flex;
        flex-direction: column;
        min-width: 0;
        position: relative;
      }
      .insp-handle {
        position: absolute;
        top: 50%;
        right: 0;
        transform: translateY(-50%);
        z-index: var(--z-handle);
        width: 26px;
        height: 64px;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 0;
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-right: none;
        border-radius: 10px 0 0 10px;
        background: var(--surface, #ffffff);
        color: var(--acc-deep, #a5854a);
        font-size: 19px;
        line-height: 1;
        cursor: pointer;
        box-shadow: -4px 0 12px rgba(34, 40, 63, 0.1);
        transition:
          background 0.14s ease,
          color 0.14s ease;
      }
      .insp-handle:hover {
        background: #f5ecd9;
        color: var(--ink, #22283f);
      }
      .insp-handle-ico {
        display: inline-block;
      }
      .insp-handle.has-selection {
        background: var(--navy, #141b33);
        border-color: var(--navy, #141b33);
        color: #ffffff;
      }
      .insp-handle.has-selection:hover {
        background: var(--navy-2, #1a2238);
        color: #ffffff;
      }
      .insp-handle.is-beckoning {
        border-color: var(--gold, #c5a35c);
        box-shadow:
          -4px 0 12px rgba(34, 40, 63, 0.1),
          0 0 0 0 rgba(197, 163, 92, 0.45);
        animation: insp-pulse 2.4s ease-out infinite;
      }
      .insp-handle.is-beckoning .insp-handle-ico {
        animation: insp-beckon 2.4s ease-in-out infinite;
      }
      @keyframes insp-beckon {
        0%,
        55%,
        100% {
          transform: translateX(0);
        }
        70% {
          transform: translateX(-4px);
        }
        85% {
          transform: translateX(1px);
        }
      }
      @keyframes insp-pulse {
        0% {
          box-shadow:
            -4px 0 12px rgba(34, 40, 63, 0.1),
            0 0 0 0 rgba(197, 163, 92, 0.45);
        }
        60%,
        100% {
          box-shadow:
            -4px 0 12px rgba(34, 40, 63, 0.1),
            0 0 0 9px rgba(197, 163, 92, 0);
        }
      }
      .insp-handle.is-beckoning.has-selection {
        animation: insp-pulse-strong 1.4s ease-out infinite;
      }
      .insp-handle.is-beckoning.has-selection .insp-handle-ico {
        animation: insp-beckon-strong 1.4s ease-in-out infinite;
      }
      @keyframes insp-beckon-strong {
        0%,
        45%,
        100% {
          transform: translateX(0);
        }
        60% {
          transform: translateX(-6px);
        }
        75% {
          transform: translateX(2px);
        }
        88% {
          transform: translateX(-3px);
        }
      }
      @keyframes insp-pulse-strong {
        0% {
          box-shadow:
            -4px 0 12px rgba(34, 40, 63, 0.1),
            0 0 0 0 rgba(197, 163, 92, 0.6);
        }
        60%,
        100% {
          box-shadow:
            -4px 0 12px rgba(34, 40, 63, 0.1),
            0 0 0 13px rgba(197, 163, 92, 0);
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .insp-handle.is-beckoning,
        .insp-handle.is-beckoning .insp-handle-ico {
          animation: none;
        }
      }
      .canvas-toolbar {
        position: relative;
        z-index: var(--z-toolbar);
        min-height: 64px;
        flex: none;
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 18px;
        padding: 10px 22px;
        border-bottom: 1px solid rgba(197, 163, 92, 0.25);
        background: var(--paper, #faf6ec);
      }
      .ct-group {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
        min-width: 0;
      }
      .ct-divider {
        width: 1px;
        align-self: stretch;
        min-height: 30px;
        background: rgba(34, 40, 63, 0.1);
      }
      .ct-spacer {
        flex: 1;
      }
      .ct-btn {
        position: relative;
        height: 36px;
        padding: 0 14px;
        border-radius: 30px;
        border: 1px solid rgba(34, 40, 63, 0.1);
        background: var(--surface, #ffffff);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.08em;
        cursor: pointer;
        transition: 0.15s;
      }
      .ct-btn:hover {
        border-color: var(--acc, #c5a35c);
      }
      @container tsp (max-width: 860px) {
        .canvas-toolbar {
          gap: 10px;
          padding: 10px 14px;
        }
        .ct-spacer,
        .ct-divider {
          display: none;
        }
        .ct-btn,
        .ct-primary {
          padding: 0 11px;
          letter-spacing: 0.04em;
        }
      }
      @container tsp (max-width: 680px) {
        .canvas-toolbar {
          gap: 8px;
          padding: 8px 10px;
        }
        .ct-group {
          gap: 6px;
        }
        .ct-btn,
        .ct-primary {
          font-size: 10px;
          padding: 4px 9px;
          min-height: 30px;
          letter-spacing: 0.02em;
        }
      }
      .ct-secondary {
        background: transparent;
        border-color: rgba(197, 163, 92, 0.55);
        color: var(--acc-deep, #a5854a);
      }
      .ct-secondary:hover {
        border-color: var(--acc, #c5a35c);
        background: rgba(197, 163, 92, 0.12);
      }
      .ct-ghost {
        background: transparent;
        border-color: transparent;
        color: rgba(34, 40, 63, 0.75);
      }
      .ct-ghost:hover {
        border-color: rgba(197, 163, 92, 0.55);
        color: var(--ink, #22283f);
      }
      .ct-ghost:disabled {
        opacity: 0.5;
        cursor: default;
      }
      .ct-primary {
        height: 36px;
        padding: 0 18px;
        border-radius: 30px;
        border: none;
        background: var(--navy, #141b33);
        color: #ffffff;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.1em;
        font-weight: 500;
        cursor: pointer;
        transition: 0.15s;
        box-shadow: 0 6px 16px rgba(20, 27, 51, 0.25);
      }
      .ct-primary:hover {
        filter: brightness(1.06);
      }
      .ct-btn,
      .ct-primary {
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-box-pack: center;
        -webkit-line-clamp: 2;
        line-clamp: 2;
        overflow: hidden;
        white-space: normal;
        text-align: center;
        line-height: 1.2;
        height: auto;
        min-height: 36px;
        padding-top: 5px;
        padding-bottom: 5px;
        overflow-wrap: break-word;
      }
      .ct-menu {
        position: relative;
      }
      .ct-add {
        gap: 6px;
      }
      .ct-add .ct-caret {
        font-size: 9px;
        opacity: 0.7;
        transition: transform 0.18s ease;
      }
      .ct-add.is-open {
        border-color: var(--acc, #c5a35c);
        color: var(--acc-deep, #a5854a);
      }
      .ct-add.is-open .ct-caret {
        transform: rotate(180deg);
      }
      .ct-backdrop {
        position: absolute;
        inset: -9999px;
        z-index: 39;
        border: none;
        background: transparent;
        cursor: default;
      }
      .ct-pop {
        position: absolute;
        top: 46px;
        left: 0;
        z-index: 40;
        width: 248px;
        background: var(--surface, #ffffff);
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 16px;
        box-shadow: 0 18px 48px rgba(34, 40, 63, 0.16);
        padding: 0 8px 8px;
        transform-origin: top left;
        animation: ct-pop-in 0.14s ease;
        max-height: min(360px, calc(100vh - 56px));
        overflow-y: auto;
        overscroll-behavior: contain;
        scrollbar-width: thin;
      }
      .ct-pop::-webkit-scrollbar {
        width: 8px;
      }
      .ct-pop::-webkit-scrollbar-thumb {
        background: var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 999px;
      }
      @keyframes ct-pop-in {
        from {
          opacity: 0;
          transform: translateY(-6px) scale(0.97);
        }
        to {
          opacity: 1;
          transform: translateY(0) scale(1);
        }
      }
      .ct-pop-head {
        top: 0;
        margin: 0 -8px 6px;
        border-radius: 16px 16px 0 0;
      }
      .ct-pop-title {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 9px;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: var(--acc-deep, #a5854a);
        padding: 10px 10px 6px;
      }
      .ct-pop-item {
        display: flex;
        align-items: center;
        gap: 11px;
        width: 100%;
        text-align: left;
        padding: 8px 10px;
        border: none;
        background: none;
        border-radius: 11px;
        cursor: pointer;
        font-size: 13px;
        color: var(--ink, #22283f);
        transition: 0.13s;
      }
      .ct-pop-item:hover {
        background: rgba(197, 163, 92, 0.16);
      }
      .ct-pop-feature {
        padding: 9px 10px;
      }
      .ct-pop-text {
        display: flex;
        flex-direction: column;
        gap: 1px;
        min-width: 0;
      }
      .ct-pop-name {
        font-family: var(--font-serif, 'Cormorant Garamond', serif);
        font-size: 14px;
        color: var(--ink, #22283f);
      }
      .ct-pop-desc {
        font-size: 10.5px;
        letter-spacing: 0.02em;
        color: var(--ink, #22283f);
        opacity: 0.55;
      }
      .ct-table-glyph {
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 18px;
        color: var(--acc-deep, #a5854a);
      }
      .ct-pop-empty {
        padding: 10px 12px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        color: color-mix(in srgb, var(--ink, #22283f) 55%, transparent);
      }
      .ct-branch {
        position: relative;
      }
      .ct-branch-caret {
        margin-left: auto;
        color: var(--acc-deep, #a5854a);
        font-size: 15px;
      }
      .ct-branch.is-open {
        background: rgba(197, 163, 92, 0.16);
      }
      .ct-flyout {
        position: absolute;
        top: 46px;
        left: 256px;
        z-index: 41;
        width: 210px;
        padding: 8px;
        background: var(--surface, #ffffff);
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 16px;
        box-shadow: 0 18px 48px rgba(34, 40, 63, 0.16);
        animation: ct-pop-in 0.12s ease;
      }
      .ct-flyout-seat {
        top: 110px;
      }
      .ct-flyout-title {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 9px;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: var(--acc-deep, #a5854a);
        padding: 8px 8px 6px;
      }
      .ct-flyout-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 4px;
      }
      .ct-shape {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 7px;
        padding: 11px 6px;
        border: 1px solid transparent;
        background: none;
        border-radius: 11px;
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11.5px;
        cursor: pointer;
        transition: 0.13s;
      }
      .ct-shape:hover {
        background: rgba(197, 163, 92, 0.16);
        border-color: rgba(197, 163, 92, 0.3);
      }
      .ct-shape-g {
        width: 30px;
        height: 24px;
        border: 2px solid var(--acc-deep, #a5854a);
        background: rgba(197, 163, 92, 0.14);
      }
      .sg-round {
        border-radius: 50%;
        width: 26px;
        height: 26px;
      }
      .sg-oval {
        border-radius: 50%;
      }
      .sg-rect {
        border-radius: 4px;
      }
      .sg-square {
        width: 24px;
        height: 24px;
        border-radius: 4px;
      }
      .sg-curved {
        width: 28px;
        height: 16px;
        border: 5px solid var(--acc-deep, #a5854a);
        border-bottom: none;
        border-radius: 26px 26px 0 0;
        background: transparent;
      }
      .ct-pop-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 4px;
      }
      .ct-pop-tile {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 5px;
        padding: 9px 4px;
        border: 1px solid transparent;
        background: none;
        border-radius: 11px;
        cursor: pointer;
        color: var(--ink, #22283f);
        transition: 0.13s;
      }
      .ct-pop-tile:hover {
        background: rgba(197, 163, 92, 0.16);
        border-color: rgba(197, 163, 92, 0.3);
      }
      .ct-pop-tile-label {
        font-size: 10px;
        letter-spacing: 0.02em;
        opacity: 0.8;
        text-align: center;
        line-height: 1.15;
      }
      .ct-pop-glyph {
        width: 22px;
        height: 22px;
        flex: none;
      }
      .canvas {
        flex: 1;
        position: relative;
        overflow: hidden;
        background: var(--paper, #faf6ec);
        touch-action: none;
        cursor: default;
      }
      .canvas.is-pan {
        cursor: grab;
      }
      .canvas.is-pan:active {
        cursor: grabbing;
      }
      .marquee {
        position: absolute;
        z-index: 25;
        border: 1px solid var(--acc, #c5a35c);
        background: rgba(197, 163, 92, 0.14);
        pointer-events: none;
        border-radius: 2px;
      }
      .world {
        will-change: transform;
      }
      .grid {
        position: absolute;
        left: -2000px;
        top: -2000px;
        width: 6000px;
        height: 6000px;
        background-image:
          linear-gradient(
            var(--grid, rgba(191, 155, 90, 0.07)) 1px,
            transparent 1px
          ),
          linear-gradient(
            90deg,
            var(--grid, rgba(191, 155, 90, 0.07)) 1px,
            transparent 1px
          );
        background-size: 40px 40px;
      }
      .floorplan {
        z-index: 0;
        pointer-events: none;
        touch-action: none;
        filter: saturate(0.85);
      }
      .floorplan img {
        width: 100%;
        height: 100%;
        display: block;
        -webkit-user-drag: none;
        user-select: none;
        border-radius: 2px;
      }
      .fp-generating {
        z-index: 1;
        pointer-events: none;
        border-radius: 4px;
        animation: fp-glow 1.8s ease-in-out infinite;
      }
      .fp-generating::before {
        content: '';
        position: absolute;
        inset: -4px;
        border-radius: 8px;
        padding: 4px;
        background: conic-gradient(
          from var(--tsp-fp-angle, 0deg),
          rgba(197, 163, 92, 0) 0%,
          rgba(197, 163, 92, 0.35) 8%,
          #e3c27d 14%,
          #fff3cf 18%,
          #e3c27d 22%,
          rgba(197, 163, 92, 0.35) 28%,
          rgba(197, 163, 92, 0) 36%
        );
        -webkit-mask:
          linear-gradient(#fff 0 0) content-box,
          linear-gradient(#fff 0 0);
        -webkit-mask-composite: xor;
        mask:
          linear-gradient(#fff 0 0) content-box,
          linear-gradient(#fff 0 0);
        mask-composite: exclude;
        animation: fp-sweep 2.4s linear infinite;
      }
      @property --tsp-fp-angle {
        syntax: '<angle>';
        initial-value: 0deg;
        inherits: false;
      }
      @keyframes fp-sweep {
        to {
          --tsp-fp-angle: 360deg;
        }
      }
      @keyframes fp-glow {
        0%,
        100% {
          box-shadow: 0 0 0 1px rgba(197, 163, 92, 0.35);
        }
        50% {
          box-shadow:
            0 0 0 1px rgba(197, 163, 92, 0.55),
            0 0 32px rgba(227, 194, 125, 0.4);
        }
      }
      .fp-build {
        position: absolute;
        z-index: var(--z-canvas-overlay);
        top: 0;
        left: 0;
        right: 0;
        display: flex;
        align-items: flex-start;
        justify-content: center;
        padding: 14px 16px 0;
        pointer-events: none;
      }
      .fp-broken {
        position: absolute;
        z-index: var(--z-canvas-overlay);
        inset: 0;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 10px;
        pointer-events: none;
      }
      .fp-broken-msg {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 13px;
        letter-spacing: 0.02em;
        color: var(--acc-deep, #a5854a);
        padding: 4px 12px;
        border-radius: 999px;
        background: var(--surface, #ffffff);
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
      }
      .fp-broken-btn {
        pointer-events: auto;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 13px;
        font-weight: 500;
        letter-spacing: 0.02em;
        color: #ffffff;
        background: var(--navy, #141b33);
        border: none;
        border-radius: 999px;
        padding: 8px 18px;
        cursor: pointer;
        box-shadow: 0 8px 24px rgba(34, 40, 63, 0.18);
      }
      .fp-broken-btn:hover {
        background: var(--navy-2, #1a2238);
      }
      .fp-broken-btn .ico {
        width: 15px;
        height: 15px;
      }
      .floorplan.is-broken img {
        visibility: hidden;
      }
      .fp-toolbar {
        pointer-events: auto;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 5px 8px;
        border-radius: 999px;
        background: var(--surface, #ffffff);
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        box-shadow: 0 8px 24px rgba(34, 40, 63, 0.14);
        max-width: min(680px, 100%);
        overflow-x: auto;
        scrollbar-width: thin;
      }
      .fp-toolbar > * {
        flex: none;
      }
      .fp-toolbar::-webkit-scrollbar {
        height: 5px;
      }
      .fp-toolbar::-webkit-scrollbar-thumb {
        background: var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 999px;
      }
      .fp-tool-div {
        width: 1px;
        align-self: stretch;
        margin: 3px 0;
        background: var(--surface-edge, rgba(197, 163, 92, 0.35));
      }
      .fp-build-btn {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 13px;
        font-weight: 500;
        letter-spacing: 0.02em;
        color: #ffffff;
        background: var(--navy, #141b33);
        border: none;
        border-radius: 999px;
        padding: 7px 16px;
        cursor: pointer;
      }
      .fp-build-btn:hover:not(:disabled) {
        background: var(--navy-2, #1a2238);
      }
      .fp-build-btn:disabled {
        cursor: default;
        opacity: 0.55;
      }
      .fp-tool-opacity {
        display: flex;
        align-items: center;
        gap: 7px;
        cursor: pointer;
      }
      .fp-tool-ico {
        font-size: 13px;
        color: var(--acc-deep, #a5854a);
      }
      .fp-tool-val {
        min-width: 34px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        color: var(--ink, #22283f);
        text-align: right;
      }
      .fp-tool-btn {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 30px;
        height: 30px;
        border-radius: 50%;
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        background: rgba(34, 40, 63, 0.04);
        color: var(--acc-deep, #a5854a);
        font-size: 14px;
        cursor: pointer;
        transition: 0.15s;
      }
      .fp-tool-btn:hover {
        border-color: var(--acc, #c5a35c);
        color: var(--ink, #22283f);
      }
      .fp-tool-btn.is-on {
        background: var(--acc, #c5a35c);
        color: #ffffff;
        border-color: var(--acc, #c5a35c);
      }
      .fp-tool-btn.is-del:hover {
        border-color: #a8663f;
        color: #a14a2e;
      }
      .fp-tool-confirm {
        height: 30px;
        padding: 0 12px;
        border-radius: 999px;
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        background: rgba(34, 40, 63, 0.04);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10.5px;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        cursor: pointer;
        transition: 0.15s;
      }
      .fp-tool-confirm:hover {
        border-color: var(--acc, #c5a35c);
      }
      .fp-tool-confirm.is-danger {
        border-color: rgba(217, 138, 106, 0.6);
        color: #a14a2e;
      }
      .fp-tool-confirm.is-danger:hover {
        background: rgba(217, 138, 106, 0.18);
        border-color: #a8663f;
      }
      .fp-frame {
        position: absolute;
        z-index: 9990;
        border: 1.5px dashed var(--acc, #c5a35c);
        background: rgba(197, 163, 92, 0.06);
        cursor: grab;
        touch-action: none;
      }
      .fp-frame:active {
        cursor: grabbing;
      }
      .fp-frame-label {
        position: absolute;
        top: -22px;
        left: 0;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--acc-deep, #a5854a);
        background: var(--paper, #faf6ec);
        padding: 2px 6px;
        border-radius: 4px;
      }
      .fp-frame-rz {
        position: absolute;
        right: -9px;
        bottom: -9px;
        width: 18px;
        height: 18px;
        border-radius: 50%;
        background: #fff;
        border: 2px solid var(--acc, #c5a35c);
        box-shadow: 0 2px 6px rgba(34, 40, 63, 0.14);
        cursor: nwse-resize;
        touch-action: none;
      }
      .fp-opacity {
        width: 90px;
        height: 5px;
        -webkit-appearance: none;
        appearance: none;
        border-radius: 4px;
        background: rgba(34, 40, 63, 0.18);
        outline: none;
        cursor: pointer;
      }
      .fp-opacity::-webkit-slider-thumb {
        -webkit-appearance: none;
        width: 14px;
        height: 14px;
        border-radius: 50%;
        background: var(--acc, #c5a35c);
        cursor: pointer;
      }
      .fp-opacity::-moz-range-thumb {
        width: 14px;
        height: 14px;
        border: none;
        border-radius: 50%;
        background: var(--acc, #c5a35c);
        cursor: pointer;
      }
      .t-node {
        cursor: grab;
        touch-action: none;
        z-index: 2;
      }
      .t-node.is-sel .t-surface {
        box-shadow: 0 0 0 2px var(--acc, #c5a35c);
      }
      .t-node.is-targeting .t-surface {
        box-shadow: 0 0 0 2px var(--acc-deep, #a5854a);
      }
      .fx-node.is-targeting {
        outline: 2px solid rgba(197, 163, 92, 0.55);
        outline-offset: 3px;
      }
      .t-surface {
        position: absolute;
        inset: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        background: var(--popover, #fdfaf2);
        border: 1.5px solid var(--outline, #c5a35c);
        box-shadow: 0 6px 18px rgba(34, 40, 63, 0.08);
        color: var(--ink, #22283f);
      }
      .t-center {
        width: 42%;
        height: 42%;
        max-width: 46px;
        max-height: 46px;
        color: var(--gold, #c5a35c);
        opacity: var(--tsp-center-opacity, 0.5);
        pointer-events: none;
      }
      .t-motif {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        pointer-events: none;
      }
      .t-motif::before {
        content: var(--tsp-motif, '');
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-weight: 700;
        font-size: 34%;
        line-height: 1;
        color: var(--gold, #c5a35c);
      }
      .shape-round {
        border-radius: 50%;
      }
      .shape-oval {
        border-radius: 50% / 42%;
      }
      .shape-rect {
        border-radius: 0;
      }
      .shape-square {
        border-radius: 0;
      }
      .t-section {
        position: absolute;
        inset: 0;
        border: 1px dashed var(--outline, #c5a35c);
        border-radius: 6px;
        background: transparent;
        opacity: 0.5;
      }
      .t-section-front {
        position: absolute;
        left: 0;
        right: 0;
        top: 0;
        transform: translateY(-100%);
        padding-bottom: 3px;
        border-bottom: 3px solid var(--outline, #c5a35c);
        text-align: center;
        font:
          700 9px 'Jost',
          monospace;
        letter-spacing: 0.12em;
        color: var(--outline, #c5a35c);
        pointer-events: none;
      }
      .t-node.is-section.is-sel,
      .t-node.is-section.is-targeting {
        outline-offset: 4px;
        border-radius: 6px;
      }
      .t-curvedsvg {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        overflow: visible;
      }
      .t-curvedband {
        fill: var(--popover, #fdfaf2);
        stroke: var(--outline, #c5a35c);
      }
      .t-node.is-sel .t-curvedband {
        stroke: var(--acc, #c5a35c);
      }
      .t-node.is-targeting .t-curvedband {
        stroke: var(--acc-deep, #a5854a);
      }
      .t-node.is-sel {
        outline: 2px solid rgba(197, 163, 92, 0.45);
        outline-offset: 18px;
        border-radius: 0;
      }
      .t-node.is-targeting {
        outline: 2px dashed rgba(197, 163, 92, 0.45);
        outline-offset: 18px;
        border-radius: 0;
      }
      .t-node.is-seat.is-sel,
      .t-node.is-seat.is-targeting {
        outline-offset: 4px;
        border-radius: 50%;
      }
      .t-edit {
        position: absolute;
        left: 50%;
        top: 50%;
        transform-origin: 0 0;
        transform: rotate(calc(-1 * var(--rot, 0deg)))
          translate(0, calc(-1 * (var(--halfh, 0px) + 40px)))
          translate(-50%, -50%);
        display: flex;
        align-items: center;
        gap: 6px;
        height: 28px;
        padding: 0 13px;
        border-radius: 30px;
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        background: var(--acc, #c5a35c);
        color: #ffffff;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10.5px;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        font-weight: 600;
        line-height: 1;
        white-space: nowrap;
        cursor: pointer;
        opacity: 0;
        pointer-events: none;
        transition:
          opacity 0.14s ease,
          transform 0.14s ease;
        z-index: 8;
        touch-action: none;
      }
      .t-edit::after {
        content: '';
        position: absolute;
        top: 100%;
        left: 50%;
        transform: translateX(-50%);
        border: 5px solid transparent;
        border-top-color: var(--acc, #c5a35c);
      }
      .t-node.is-sel .t-edit {
        opacity: 1;
        pointer-events: auto;
      }
      .t-node.is-sel .t-edit {
        transform: rotate(calc(-1 * var(--rot, 0deg)))
          translate(0, calc(-1 * (var(--halfh, 0px) + 60px)))
          translate(-50%, -50%);
      }
      .t-node.is-sel .t-edit::after {
        display: none;
      }
      .t-edit:hover {
        filter: brightness(1.08);
      }
      .t-edit-ico {
        font-size: 13px;
      }
      .t-vipdot {
        position: absolute;
        top: 8px;
        right: 10px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 8px;
        letter-spacing: 0.12em;
        color: var(--ink, #22283f);
        background: var(--acc, #c5a35c);
        border-radius: 4px;
        padding: 2px 5px;
      }
      .t-edit-rank {
        padding-right: 8px;
        margin-right: 2px;
        border-right: 1px solid rgba(34, 40, 63, 0.3);
        font-weight: 700;
      }
      .t-name {
        position: absolute;
        left: 50%;
        bottom: -22px;
        transform: translateX(-50%);
        white-space: nowrap;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        font-weight: 500;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--ink, #22283f);
        opacity: 0.75;
      }
      .t-node.is-sel .t-name {
        bottom: -44px;
      }
      .seat {
        position: absolute;
        width: 26px;
        height: 26px;
        transform: translate(-50%, -50%);
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        color: var(--acc-deep, #a5854a);
        background: var(--popover, #fdfaf2);
        border: 1.5px solid var(--outline, #c5a35c);
        cursor: grab;
        z-index: 3;
        transition:
          transform 0.12s ease,
          background 0.15s ease;
      }
      .seat:hover,
      .seat.is-filled:hover {
        animation: seat-spin 2.2s linear infinite;
      }
      .seat.is-filled {
        border-style: solid;
        color: var(--ink, #22283f);
        background: var(--seatcol, var(--acc, #c5a35c));
        border-color: var(--seatcol, var(--acc, #c5a35c));
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-weight: 600;
        cursor: grab;
        animation: seat-pop 0.28s cubic-bezier(0.34, 1.56, 0.64, 1) both;
      }
      .seat.is-filled:active {
        cursor: grabbing;
      }
      .seat.is-drop {
        transform: translate(-50%, -50%) scale(1.35);
        z-index: 6;
        overflow: hidden;
        color: var(--ink, #22283f);
        background: var(--acc, #c5a35c);
        border: 2px solid var(--acc-deep, #a5854a);
        box-shadow: 0 4px 14px rgba(34, 40, 63, 0.15);
        font-family: var(--font-serif, 'Cormorant Garamond', serif);
        font-weight: 600;
      }
      .seat-img {
        width: 100%;
        height: 100%;
        border-radius: 50%;
        object-fit: cover;
        display: block;
      }
      @keyframes seat-pop {
        0% {
          transform: translate(-50%, -50%) scale(0.4);
          opacity: 0;
        }
        100% {
          transform: translate(-50%, -50%) scale(1);
          opacity: 1;
        }
      }
      @keyframes seat-spin {
        from {
          transform: translate(-50%, -50%) rotate(0deg);
        }
        to {
          transform: translate(-50%, -50%) rotate(360deg);
        }
      }
      .fx-node {
        z-index: 1;
        cursor: grab;
        touch-action: none;
        transition: background 0.12s ease;
      }
      .fx-node:active {
        cursor: grabbing;
      }
      .fx-node:hover {
        background: rgba(197, 163, 92, 0.05);
      }
      .fx-node.is-sel {
        background: rgba(197, 163, 92, 0.07);
        outline: 2px solid rgba(197, 163, 92, 0.45);
        outline-offset: 3px;
      }
      .rz {
        position: absolute;
        width: 14px;
        height: 14px;
        background: #fff;
        border: 1.5px solid var(--acc-deep, #a5854a);
        border-radius: 4px;
        box-shadow: 0 2px 6px rgba(34, 40, 63, 0.14);
        z-index: 6;
        touch-action: none;
        transition:
          border-color 0.12s ease,
          background 0.12s ease;
      }
      .rz:hover,
      .rz:active {
        background: var(--acc-deep, #a5854a);
        border-color: var(--acc-deep, #a5854a);
      }
      .rz-e {
        right: -32px;
        top: 50%;
        transform: translateY(-50%);
        cursor: ew-resize;
      }
      .rz-w {
        left: -32px;
        top: 50%;
        transform: translateY(-50%);
        cursor: ew-resize;
      }
      .rz-s {
        bottom: -32px;
        left: 50%;
        transform: translateX(-50%);
        cursor: ns-resize;
      }
      .rz-n {
        top: -32px;
        left: 50%;
        transform: translateX(-50%);
        cursor: ns-resize;
      }
      .rz-se {
        right: -32px;
        bottom: -32px;
        cursor: nwse-resize;
        border-radius: 50%;
      }
      .rz-rot {
        top: -24px;
        right: -24px;
        width: 22px;
        height: 22px;
        border-radius: 50%;
        background: #fff;
        border: 1.5px solid var(--acc-deep, #a5854a);
        color: var(--acc-deep, #a5854a);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 12px;
        cursor: grab;
      }
      .rz-rot:active {
        cursor: grabbing;
      }
      .rz-locked {
        cursor: pointer;
        font-size: 11px;
        border-color: var(--acc, #c5a35c);
        background: rgba(197, 163, 92, 0.18);
      }
      .rz-locked:active {
        cursor: pointer;
      }
      .fx-tag {
        position: absolute;
        left: 50%;
        bottom: -20px;
        transform: translateX(-50%);
        white-space: nowrap;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 9px;
        letter-spacing: 0.08em;
        color: var(--acc-deep, #a5854a);
        opacity: 0.8;
      }
      .align-bar {
        position: absolute;
        left: 50%;
        transform: translateX(-50%);
        bottom: 64px;
        display: flex;
        align-items: center;
        gap: 2px;
        padding: 4px 8px;
        background: color-mix(
          in srgb,
          var(--surface, #ffffff) 92%,
          transparent
        );
        -webkit-backdrop-filter: blur(10px);
        backdrop-filter: blur(10px);
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 999px;
        box-shadow: 0 8px 22px rgba(34, 40, 63, 0.15);
        z-index: 21;
      }
      .align-cap {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 9px;
        letter-spacing: 0.16em;
        text-transform: uppercase;
        color: var(--acc-deep, #a5854a);
        padding: 0 6px 0 2px;
      }
      .align-btn {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 28px;
        height: 28px;
        border: none;
        background: none;
        border-radius: 8px;
        color: var(--ink, #22283f);
        font-size: 16px;
        line-height: 1;
        cursor: pointer;
        transition: background 0.12s ease;
      }
      .align-btn:hover {
        background: rgba(197, 163, 92, 0.18);
      }
      .align-div {
        width: 1px;
        height: 18px;
        margin: 0 4px;
        background: var(--surface-edge, rgba(197, 163, 92, 0.35));
      }
      .zoom-ctl {
        position: absolute;
        left: 50%;
        transform: translateX(-50%);
        bottom: 18px;
        display: flex;
        align-items: center;
        gap: 1px;
        background: color-mix(
          in srgb,
          var(--surface, #ffffff) 88%,
          transparent
        );
        -webkit-backdrop-filter: blur(10px);
        backdrop-filter: blur(10px);
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 999px;
        padding: 4px;
        box-shadow:
          0 8px 22px rgba(20, 27, 51, 0.18),
          inset 0 1px 0 rgba(34, 40, 63, 0.03);
        z-index: 20;
      }
      .zoom-ctl button {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 28px;
        border: none;
        background: none;
        color: var(--ink, #22283f);
        border-radius: 999px;
        cursor: pointer;
        transition:
          background 0.12s ease,
          color 0.12s ease;
      }
      .zoom-ctl button:disabled {
        opacity: 0.3;
        cursor: default;
      }
      .zoom-step {
        width: 28px;
        font-size: 18px;
        line-height: 1;
      }
      .zoom-ctl button:not(:disabled):hover {
        background: rgba(197, 163, 92, 0.16);
      }
      .zoom-ctl button:not(:disabled):active {
        background: rgba(197, 163, 92, 0.28);
      }
      .zoom-pct {
        min-width: 46px;
        padding: 0 4px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        font-variant-numeric: tabular-nums;
        letter-spacing: 0.02em;
        color: var(--ink, #22283f);
      }
      .zoom-pct:hover {
        color: var(--acc, #c5a35c);
      }
      .zoom-div {
        width: 1px;
        height: 16px;
        background: var(--surface-edge, rgba(197, 163, 92, 0.35));
        margin: 0 3px;
      }
      .zoom-fit {
        gap: 5px;
        padding: 0 12px 0 10px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--ink-2, #57534b);
      }
      .zoom-fit:not(:disabled):hover {
        color: var(--acc, #c5a35c);
      }
      .zoom-fit-ico {
        font-size: 14px;
        line-height: 1;
      }
      .tsp-inspector {
        width: 336px;
        flex: none;
        position: relative;
        z-index: var(--z-inspector);
        overflow-y: auto;
        contain: size;
        background: linear-gradient(
          180deg,
          var(--popover, #fdfaf2),
          var(--paper-2, #f4eddb)
        );
        color: var(--ink, #22283f);
        border-left: 1px solid rgba(0, 0, 0, 0.1);
        transition: width 0.2s ease;
      }
      .tsp-inspector.is-collapsed {
        width: 0;
        overflow: hidden;
        border-left: none;
      }
      .insp-deco {
        position: absolute;
        inset: 0 0 auto 0;
        height: 160px;
        background:
          radial-gradient(
            120% 80% at 20% 0%,
            rgba(197, 163, 92, 0.35),
            transparent 60%
          ),
          radial-gradient(
            100% 80% at 100% 0%,
            rgba(230, 207, 154, 0.3),
            transparent 55%
          );
        pointer-events: none;
      }
      .insp-pad {
        position: relative;
        padding: 24px 22px 30px;
      }
      .insp-top {
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .insp-name {
        flex: 1;
        min-width: 0;
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 25px;
        border: none;
        background: none;
        outline: none;
        color: var(--ink, #22283f);
      }
      .insp-x {
        flex: none;
        width: 30px;
        height: 30px;
        border-radius: 50%;
        border: 1px solid rgba(0, 0, 0, 0.12);
        background: #fff;
        cursor: pointer;
        color: #8f887b;
      }
      .insp-status {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        letter-spacing: 0.08em;
        color: #6f6a61;
        margin-top: 6px;
      }
      .insp-progress {
        margin-top: 20px;
      }
      .insp-progress-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        margin-bottom: 8px;
      }
      .insp-progress-label {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: #6f6a61;
      }
      .insp-progress-count {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 16px;
        color: var(--ink, #22283f);
      }
      .insp-progress-bar {
        height: 6px;
        background: rgba(0, 0, 0, 0.08);
        border-radius: 3px;
        overflow: hidden;
      }
      .insp-progress-fill {
        display: block;
        height: 100%;
        background: var(--gold, #c5a35c);
        transition: width 0.4s ease;
      }
      .insp-seatmap-hint {
        font-size: 11.5px;
        line-height: 1.5;
        color: #8f887b;
        margin: 0 0 12px;
      }
      .insp-tablemap {
        display: flex;
        padding: 12px;
        margin-bottom: 6px;
        border-radius: 14px;
        background: linear-gradient(168deg, #ffffff, #f0eee7);
        border: 1px solid rgba(0, 0, 0, 0.1);
        overflow: auto;
        max-height: 380px;
      }
      .insp-tablemap-reserve {
        position: relative;
        flex: none;
        margin: auto;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .insp-tablemap-box {
        position: relative;
        flex: none;
      }
      .insp-tablemap-box.shape-round {
        border: 2px solid var(--outline, #22283f);
        border-radius: 50%;
      }
      .insp-tablemap-box.shape-oval {
        border: 2px solid var(--outline, #22283f);
        border-radius: 50% / 42%;
      }
      .insp-tablemap-box.shape-rect,
      .insp-tablemap-box.shape-square {
        border: 2px solid var(--outline, #22283f);
      }
      .insp-tablemap-box.shape-section {
        border: 1px dashed var(--outline, #22283f);
        border-radius: 6px;
        opacity: 0.9;
      }
      .insp-section-front {
        position: absolute;
        left: 0;
        right: 0;
        top: 0;
        transform: translateY(-140%);
        text-align: center;
        font:
          700 9px 'Jost',
          monospace;
        letter-spacing: 0.12em;
        color: var(--outline, #22283f);
        pointer-events: none;
      }
      .insp-tablemap-box .t-curvedsvg {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        overflow: visible;
      }
      .insp-tablemap-box .t-curvedband {
        stroke: var(--outline, #22283f);
      }
      .insp-tablemap-box .insp-seat {
        position: absolute;
        width: 34px;
        height: 34px;
        transform: translate(-50%, -50%);
        z-index: 2;
      }
      .insp-tablemap-box .insp-seat.is-drop {
        transform: translate(-50%, -50%) scale(1.18);
        z-index: 5;
      }
      .insp-seat {
        position: relative;
        width: 40px;
        height: 40px;
        flex: none;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 12px;
        color: #9a7d44;
        background: #fff;
        border: 1px dashed rgba(0, 0, 0, 0.25);
        cursor: pointer;
        transition:
          transform 0.12s ease,
          border-color 0.15s ease,
          background 0.15s ease;
      }
      .insp-seat:hover {
        border-color: var(--gold, #c5a35c);
      }
      .insp-seat.is-filled {
        border-style: solid;
        color: var(--ink, #22283f);
        background: var(--seatcol, #c5a35c);
        border-color: var(--seatcol, #c5a35c);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-weight: 600;
        cursor: grab;
      }
      .insp-seat.is-filled:active {
        cursor: grabbing;
      }
      .insp-seat.is-drop {
        transform: scale(1.18);
        overflow: hidden;
        color: var(--ink, #22283f);
        background: var(--gold, #c5a35c);
        border: 2px solid #9a7d44;
        box-shadow: 0 4px 14px rgba(154, 125, 68, 0.4);
      }
      .insp-seat-img {
        width: 100%;
        height: 100%;
        border-radius: 50%;
        object-fit: cover;
        display: block;
      }
      .insp-seat-x {
        position: absolute;
        top: -5px;
        right: -5px;
        width: 18px;
        height: 18px;
        padding: 0;
        border: 1px solid rgba(255, 255, 255, 0.75);
        border-radius: 50%;
        background: var(--ink, #22283f);
        color: #fff;
        font-size: 9px;
        line-height: 1;
        text-align: center;
        cursor: pointer;
        opacity: 0;
        transition: opacity 0.12s ease;
        pointer-events: none;
      }
      .insp-seat.is-filled:hover .insp-seat-x {
        opacity: 1;
        pointer-events: auto;
      }
      .insp-seat-x:hover {
        background: #b3261e;
        border-color: #b3261e;
      }
      .insp-kicker {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.24em;
        text-transform: uppercase;
        color: #9a7d44;
      }
      .insp-hero {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 27px;
        margin-top: 8px;
      }
      .insp-lead {
        font-size: 13px;
        line-height: 1.6;
        color: #8f887b;
        margin: 12px 0 0;
      }
      .insp-label {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: #6f6a61;
        margin: 22px 0 11px;
      }
      .insp-grid4 {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 8px;
      }
      .insp-opt {
        height: 40px;
        border: 1px solid rgba(0, 0, 0, 0.12);
        background: #fff;
        border-radius: 10px;
        cursor: pointer;
        font-size: 12px;
        color: var(--ink, #22283f);
        transition: 0.15s;
      }
      .insp-opt:hover {
        border-color: var(--gold, #c5a35c);
      }
      .insp-opt.is-on {
        background: var(--ink, #22283f);
        color: #fff;
        border-color: var(--ink, #22283f);
      }
      .insp-opt:disabled {
        opacity: 0.45;
        cursor: default;
      }
      .insp-opt:disabled:hover {
        border-color: rgba(0, 0, 0, 0.12);
      }
      .insp-lock {
        grid-column: 1 / -1;
      }
      .insp-swatches {
        display: flex;
        flex-wrap: wrap;
        gap: 9px;
      }
      .insp-sw {
        width: 28px;
        height: 28px;
        border-radius: 8px;
        border: 1px solid rgba(0, 0, 0, 0.12);
        cursor: pointer;
      }
      .insp-fxpick {
        position: relative;
        width: 28px;
        height: 28px;
        border-radius: 8px;
        border: 1px solid rgba(0, 0, 0, 0.12);
        overflow: hidden;
        cursor: pointer;
        background: conic-gradient(
          from 0deg,
          #e8879c,
          #e3b968,
          #93c7a4,
          #9cabde,
          #b79bd4,
          #e8879c
        );
      }
      .insp-fxpick input[type='color'] {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        opacity: 0;
        border: none;
        padding: 0;
        cursor: pointer;
      }
      .insp-vip {
        width: 100%;
        margin-top: 20px;
        height: 44px;
        border-radius: 12px;
        border: 1px solid var(--gold, #c5a35c);
        background: rgba(197, 163, 92, 0.14);
        color: #9a7d44;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        cursor: pointer;
      }
      .insp-vip.is-on {
        background: var(--gold, #c5a35c);
        color: var(--ink, #22283f);
      }
      .insp-fxart {
        width: 100%;
        margin-top: 10px;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 18px;
        background: #fff;
        border: 1px solid rgba(0, 0, 0, 0.1);
        border-radius: 14px;
      }
      .insp-fxart-box {
        display: block;
        max-width: 100%;
      }
      .insp-clear {
        width: 100%;
        height: 40px;
        margin-top: 16px;
        border: 1px solid rgba(0, 0, 0, 0.12);
        background: #fff;
        border-radius: 10px;
        cursor: pointer;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.06em;
        color: var(--ink, #22283f);
        transition: 0.15s;
      }
      .insp-clear:hover {
        border-color: var(--gold, #c5a35c);
      }
      .insp-actions {
        display: flex;
        gap: 8px;
        margin-top: 22px;
      }
      .insp-actionbar {
        position: sticky;
        bottom: 0;
        z-index: 3;
        display: flex;
        flex-direction: column;
        gap: 8px;
        margin: 26px -22px -30px;
        padding: 14px 22px 16px;
        background: var(--paper-2, #f4eddb);
        border-top: 1px solid rgba(197, 163, 92, 0.25);
      }
      .insp-actionbar .insp-clear,
      .insp-actionbar .insp-actions {
        margin-top: 0;
      }
      .insp-actions button {
        flex: 1;
        height: 40px;
        border: 1px solid rgba(0, 0, 0, 0.12);
        background: #fff;
        border-radius: 10px;
        cursor: pointer;
        font-size: 12px;
        color: var(--ink, #22283f);
      }
      .insp-actions button:hover {
        border-color: var(--gold, #c5a35c);
      }
      .insp-actions .danger {
        color: #8e3a46;
        border-color: rgba(179, 67, 63, 0.4);
      }
      .insp-legend-title {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        color: #6f6a61;
        margin: 26px 0 14px;
      }
      .insp-legend {
        display: flex;
        flex-direction: column;
        gap: 11px;
      }
      .insp-legend-row {
        display: flex;
        align-items: center;
        gap: 11px;
      }
      .ilr-name {
        flex: 1;
        font-size: 14px;
      }
      .ilr-count {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 12px;
        color: #6f6a61;
      }
      .insp-help {
        margin-top: 26px;
        padding: 18px 18px 16px;
        border-radius: 14px;
        background: linear-gradient(
          168deg,
          var(--navy, #141b33),
          var(--navy-2, #1a2238)
        );
        border: 1px solid rgba(197, 163, 92, 0.5);
        color: var(--navy-ink, #f3ead6);
        box-shadow: 0 10px 26px rgba(20, 27, 51, 0.22);
      }
      .insp-help-title {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-style: italic;
        font-size: 21px;
        color: var(--gold-soft, #e6cf9a);
      }
      .insp-help-lead {
        margin: 8px 0 0;
        font-size: 12.5px;
        line-height: 1.6;
        color: rgba(243, 234, 214, 0.85);
      }
      .insp-help-lead b {
        color: var(--gold, #c5a35c);
        font-weight: 500;
      }
      .tsp-invites {
        flex: 1;
        display: flex;
        min-height: 0;
        background: var(--paper, #faf6ec);
        color: var(--ink, #22283f);
      }
      .inv-studio {
        flex: 1;
        min-width: 0;
        overflow-y: auto;
        padding: 32px 36px;
        border-right: 1px solid rgba(34, 40, 63, 0.06);
      }
      .inv-kicker {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.24em;
        text-transform: uppercase;
        color: var(--acc-deep, #a5854a);
      }
      .inv-h {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 30px;
        margin: 8px 0 0;
      }
      .inv-lead {
        font-size: 13.5px;
        line-height: 1.6;
        color: var(--ink-2, #57534b);
        margin: 10px 0 20px;
        max-width: 460px;
      }
      .inv-poster-row {
        display: flex;
        align-items: flex-start;
        gap: 28px;
        flex-wrap: wrap;
      }
      .poster {
        flex: 0 1 300px;
        max-width: 320px;
      }
      .poster-img {
        width: 100%;
        border: 1.5px solid var(--gold, #c5a35c);
        border-radius: 16px;
        display: block;
      }
      .poster-empty {
        box-sizing: border-box;
        padding: 24px;
        border: 1.5px dashed rgba(197, 163, 92, 0.55);
        border-radius: 16px;
        background: rgba(255, 255, 255, 0.5);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        text-align: center;
        gap: 8px;
        color: var(--ink-2, #7c766c);
      }
      .poster-empty-logo {
        width: 64px;
        height: 64px;
        border-radius: 50%;
        object-fit: cover;
        border: 1px solid var(--gold-soft, #e6cf9a);
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.12);
      }
      .poster-empty-mark {
        width: 64px;
        height: 64px;
        border-radius: 50%;
        display: grid;
        place-items: center;
        background: var(
          --gold-grad,
          linear-gradient(135deg, #e6cf9a, #c5a35c 55%, #a5854a)
        );
        color: var(--navy, #141b33);
        border: 1px solid var(--gold-soft, #e6cf9a);
      }
      .poster-empty-mark::before {
        content: var(--tsp-motif, attr(data-initials));
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-weight: 700;
        font-size: 30px;
        line-height: 1;
      }
      .poster-empty-title {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-style: italic;
        font-size: 19px;
        color: var(--ink, #22283f);
      }
      .poster-empty-hint {
        font-size: 11.5px;
        line-height: 1.55;
        max-width: 210px;
      }
      .inv-ai {
        flex: 1;
        min-width: 260px;
      }
      .inv-ai > .inv-label {
        margin-top: 0;
      }
      .inv-ai-lead {
        margin: 0 0 14px;
        max-width: 480px;
        font-size: 12.5px;
        line-height: 1.6;
        color: var(--ink-2, #57534b);
      }
      .inv-ai-lead b {
        color: var(--acc-deep, #a5854a);
        font-weight: 500;
      }
      .inv-ai-clear {
        display: block;
        margin-top: 10px;
        padding: 0;
        border: none;
        background: none;
        color: var(--ink-2, #7c766c);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        text-decoration: underline;
        cursor: pointer;
      }
      .inv-label {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: var(--ink-2, #7c766c);
        margin: 26px 0 10px;
      }
      .inv-msg {
        width: 100%;
        max-width: 560px;
        height: 96px;
        padding: 13px 14px;
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 11px;
        background: var(--surface, #ffffff);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 13.5px;
        line-height: 1.5;
        outline: none;
        resize: vertical;
      }
      .inv-download {
        display: block;
        margin-top: 14px;
        padding: 9px 18px;
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 11px;
        background: none;
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 12px;
        letter-spacing: 0.04em;
        cursor: pointer;
      }
      .inv-download:hover {
        border-color: var(--acc, #c5a35c);
        color: var(--acc, #c5a35c);
      }
      .inv-aspects {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        margin-bottom: 10px;
      }
      .inv-aspect {
        padding: 6px 14px;
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 20px;
        background: var(--surface, #ffffff);
        color: var(--ink-2, #7c766c);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.04em;
        cursor: pointer;
        transition: 0.15s;
      }
      .inv-aspect:hover {
        border-color: var(--acc, #c5a35c);
        color: var(--ink, #22283f);
      }
      .inv-aspect.is-on {
        border-color: var(--acc, #c5a35c);
        background: color-mix(in oklab, var(--acc, #c5a35c) 16%, transparent);
        color: var(--acc, #c5a35c);
      }
      .inv-ai-prompt {
        height: 64px;
      }
      .inv-ai-generate {
        display: block;
        margin-top: 10px;
        padding: 9px 18px;
        border: 1px solid var(--acc, #c5a35c);
        border-radius: 11px;
        background: none;
        color: var(--acc, #c5a35c);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 12px;
        letter-spacing: 0.04em;
        cursor: pointer;
      }
      .inv-ai-generate:hover:not(:disabled) {
        background: var(--acc, #c5a35c);
        color: var(--paper, #17140f);
      }
      .inv-ai-generate:disabled {
        opacity: 0.6;
        cursor: progress;
      }
      .inv-tokens {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10.5px;
        color: var(--ink-2, #7c766c);
        margin: 9px 0 0;
      }
      .inv-list .inv-label {
        margin-top: 18px;
      }
      .inv-list .inv-tokens {
        margin-bottom: 18px;
      }
      .inv-list {
        width: 380px;
        flex: none;
        overflow-y: auto;
        padding: 24px 22px 30px;
        background: var(--paper-2, #f4eddb);
      }
      .inv-search {
        position: relative;
        display: flex;
        align-items: center;
        margin-bottom: 16px;
      }
      .inv-search-ico {
        position: absolute;
        left: 10px;
        font-size: 15px;
        color: var(--ink-2, #7c766c);
        pointer-events: none;
      }
      .inv-search-input {
        width: 100%;
        padding: 8px 30px 8px 30px;
        border-radius: 8px;
        border: 1px solid rgba(34, 40, 63, 0.1);
        background: rgba(34, 40, 63, 0.03);
        color: inherit;
        font-size: 13px;
      }
      .inv-search-input::placeholder {
        color: var(--ink-2, #7c766c);
      }
      .inv-search-input:focus {
        outline: none;
        border-color: rgba(34, 40, 63, 0.22);
      }
      .inv-search-input::-webkit-search-cancel-button {
        display: none;
      }
      .inv-search-clear {
        position: absolute;
        right: 8px;
        border: none;
        background: none;
        cursor: pointer;
        color: var(--ink-2, #7c766c);
        font-size: 12px;
        line-height: 1;
        padding: 4px;
      }
      .inv-search-clear:hover {
        color: inherit;
      }
      .inv-list-head {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 20px;
      }
      .inv-list-note {
        font-size: 12px;
        color: var(--ink-2, #7c766c);
        margin: 6px 0 16px;
      }
      .inv-row {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 0;
        border-bottom: 1px solid rgba(34, 40, 63, 0.05);
      }
      .inv-av {
        width: 34px;
        height: 34px;
        flex: none;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font:
          600 12px 'Cormorant Garamond',
          serif;
        color: var(--ink, #22283f);
        background: linear-gradient(
          135deg,
          var(--acc-deep, #a5854a),
          var(--gold, #c5a35c)
        );
      }
      .inv-row-main {
        flex: 1;
        min-width: 0;
      }
      .inv-row-name {
        font-size: 13.5px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .inv-btn {
        flex: none;
        height: 28px;
        padding: 0 10px;
        display: inline-flex;
        align-items: center;
        border-radius: 20px;
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        background: var(--surface, #ffffff);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 9.5px;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        text-decoration: none;
        cursor: pointer;
        transition: 0.15s;
      }
      .inv-btn:hover {
        border-color: var(--acc, #c5a35c);
      }
      .inv-edit {
        flex: none;
        width: 28px;
        height: 28px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: 50%;
        border: 1px solid transparent;
        background: transparent;
        color: var(--ink-2, #7c766c);
        cursor: pointer;
        transition: 0.15s;
      }
      .inv-edit:hover {
        border-color: var(--acc, #c5a35c);
        color: var(--acc, #c5a35c);
        background: color-mix(in oklab, var(--acc, #c5a35c) 12%, transparent);
      }
      .inv-edit-ico {
        width: 15px;
        height: 15px;
      }
      .fp-import {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 10px;
        width: 100%;
        height: 56px;
        margin: 4px 0 16px;
        border: 1.5px dashed var(--acc, #c5a35c);
        border-radius: 14px;
        background: rgba(197, 163, 92, 0.08);
        color: var(--acc-deep, #9a7d44);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 12px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        font-weight: 600;
        cursor: pointer;
        transition: 0.15s;
      }
      .fp-import:hover {
        background: rgba(197, 163, 92, 0.18);
      }
      .fp-import.is-busy {
        opacity: 0.6;
        cursor: progress;
      }
      .fp-import input {
        display: none;
      }
      .fp-import-glyph {
        font-size: 20px;
        line-height: 1;
      }
      .fp-link {
        margin-top: 0;
        border-style: solid;
        border-color: var(--surface-edge, rgba(34, 40, 63, 0.18));
        background: none;
        color: var(--ink-2, #57534b);
      }
      .fp-link:hover {
        border-color: var(--acc, #c5a35c);
        background: rgba(197, 163, 92, 0.08);
        color: var(--acc-deep, #9a7d44);
      }
      .ai-lead {
        font-size: 13.5px;
        line-height: 1.6;
        color: var(--ink-2, #57534b);
        margin: 14px 0 16px;
      }
      .tpop-hwrap {
        flex: 1;
        min-width: 0;
      }
      .tpop-head {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .tpop-name {
        flex: 1;
        min-width: 0;
        padding: 2px 8px;
        margin-left: -8px;
        background: none;
        border: 1px solid transparent;
        border-radius: 8px;
        outline: none;
        color: var(--navy-ink, #f3ead6);
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 21px;
        line-height: 1.2;
        text-overflow: ellipsis;
        transition: 0.15s;
      }
      .tpop-name:hover {
        background: rgba(255, 255, 255, 0.05);
      }
      .tpop-name:focus {
        border-color: rgba(197, 163, 92, 0.5);
        background: rgba(255, 255, 255, 0.08);
      }
      .tpop-name::selection {
        background: rgba(197, 163, 92, 0.35);
        color: #fff;
      }
      .tpop-vip {
        flex: none;
        width: 30px;
        height: 30px;
        border-radius: 50%;
        border: 1px solid rgba(255, 255, 255, 0.16);
        background: rgba(255, 255, 255, 0.06);
        color: rgba(243, 234, 214, 0.7);
        font-size: 14px;
        line-height: 1;
        cursor: pointer;
        transition: 0.15s;
      }
      .tpop-vip:hover {
        border-color: var(--gold, #c5a35c);
        color: var(--gold, #c5a35c);
      }
      .tpop-vip.is-on {
        background: var(--gold, #c5a35c);
        border-color: var(--gold, #c5a35c);
        color: var(--ink, #22283f);
      }
      .tpop-status {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        letter-spacing: 0.08em;
        color: var(--gold, #c5a35c);
        margin-top: 4px;
      }
      .tpop-label {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 9.5px;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: #7c766c;
        margin: 16px 0 9px;
      }
      .tpop-shapes {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 6px;
      }
      .tpop-shape {
        height: 34px;
        border: 1px solid rgba(34, 40, 63, 0.1);
        background: rgba(34, 40, 63, 0.04);
        color: var(--ink, #22283f);
        border-radius: 8px;
        font-size: 10.5px;
        cursor: pointer;
        transition: 0.15s;
      }
      .tpop-shape:hover {
        border-color: var(--gold, #c5a35c);
      }
      .tpop-shape.is-on {
        background: var(--gold, #c5a35c);
        color: var(--ink, #22283f);
        border-color: var(--gold, #c5a35c);
      }
      .tpop-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-top: 4px;
      }
      .tpop-row .tpop-label {
        margin: 16px 0 0;
      }
      .tpop-step {
        display: flex;
        align-items: center;
        gap: 4px;
        margin-top: 12px;
      }
      .tpop-step button {
        width: 30px;
        height: 30px;
        border-radius: 8px;
        border: 1px solid rgba(34, 40, 63, 0.12);
        background: rgba(34, 40, 63, 0.04);
        color: var(--ink, #22283f);
        font-size: 17px;
        cursor: pointer;
      }
      .tpop-step button:hover {
        border-color: var(--gold, #c5a35c);
      }
      .tpop-num {
        min-width: 30px;
        width: 44px;
        text-align: center;
        font-family: var(--font-serif, 'Cormorant Garamond', serif);
        font-size: 19px;
        border: none;
        background: transparent;
        color: inherit;
        padding: 0;
        appearance: textfield;
        -moz-appearance: textfield;
      }
      .tpop-num:focus {
        outline: 1px solid var(--tsp-gold, #c5a35c);
        border-radius: 6px;
      }
      .tpop-num::-webkit-outer-spin-button,
      .tpop-num::-webkit-inner-spin-button {
        appearance: none;
        margin: 0;
      }
      .tpop-orders {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 6px;
      }
      .tpop-order {
        height: 30px;
        border: 1px solid rgba(34, 40, 63, 0.1);
        background: rgba(34, 40, 63, 0.04);
        color: var(--ink, #22283f);
        border-radius: 8px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 9.5px;
        letter-spacing: 0.02em;
        cursor: pointer;
        transition: 0.15s;
      }
      .tpop-order:hover {
        border-color: var(--gold, #c5a35c);
      }
      .tpop-order.is-on {
        background: var(--gold, #c5a35c);
        color: var(--ink, #22283f);
        border-color: var(--gold, #c5a35c);
      }
      .tpop-layer {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 6px;
      }
      .tpop-layer button {
        height: 32px;
        border-radius: 8px;
        border: 1px solid rgba(34, 40, 63, 0.12);
        background: rgba(34, 40, 63, 0.04);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        cursor: pointer;
        transition: 0.15s;
      }
      .tpop-layer button:hover {
        border-color: var(--gold, #c5a35c);
      }
      .tpop-layer button:disabled {
        opacity: 0.5;
        cursor: default;
      }
      .tpop-lock {
        grid-column: 1 / -1;
      }
      .tpop-lock.is-on {
        border-color: var(--gold, #c5a35c);
        background: rgba(197, 163, 92, 0.16);
        color: #9a7d44;
      }
      .insp-layer {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 8px;
      }
      .tpop-actions {
        display: flex;
        gap: 8px;
      }
      .tpop-actions button {
        flex: 1;
        height: 38px;
        border-radius: 9px;
        border: 1px solid rgba(34, 40, 63, 0.12);
        background: rgba(34, 40, 63, 0.04);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10.5px;
        cursor: pointer;
        transition: 0.15s;
      }
      .tpop-actions button:hover {
        border-color: var(--gold, #c5a35c);
      }
      .tpop-actions .danger {
        color: #b05a48;
        border-color: rgba(224, 144, 127, 0.4);
      }
      .tpop-actions .danger:hover {
        border-color: #b05a48;
        background: rgba(224, 144, 127, 0.12);
      }
      .tpop-rank-badge {
        margin-left: 6px;
        padding: 1px 7px;
        border-radius: 20px;
        background: rgba(197, 163, 92, 0.18);
        color: var(--gold, #c5a35c);
        letter-spacing: 0.04em;
      }
      .tpop-rank {
        display: flex;
        gap: 8px;
      }
      .tpop-rank-input {
        flex: 1;
        min-width: 0;
        height: 34px;
        padding: 0 12px;
        border-radius: 8px;
        border: 1px solid rgba(34, 40, 63, 0.1);
        background: rgba(34, 40, 63, 0.04);
        color: var(--ink, #22283f);
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 12px;
      }
      .tpop-rank-input:focus {
        outline: none;
        border-color: var(--gold, #c5a35c);
      }
      .tpop-rank-auto {
        flex: none;
        padding: 0 14px;
        height: 34px;
        border-radius: 8px;
        border: 1px solid rgba(34, 40, 63, 0.1);
        background: rgba(34, 40, 63, 0.04);
        color: var(--ink, #22283f);
        font-size: 10.5px;
        cursor: pointer;
        transition: 0.15s;
      }
      .tpop-rank-auto:hover {
        border-color: var(--gold, #c5a35c);
      }
      .tpop-rank-auto.is-on {
        background: var(--gold, #c5a35c);
        border-color: var(--gold, #c5a35c);
        color: var(--ink, #22283f);
      }
      .tpop-hint {
        margin-top: 8px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10.5px;
        line-height: 1.5;
        color: #7c766c;
      }
      .tsp-toast {
        position: absolute;
        bottom: 26px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 9000;
        padding: 12px 22px;
        background: var(--navy, #141b33);
        border: 1px solid var(--gold, #c5a35c);
        color: var(--navy-ink, #f3ead6);
        border-radius: 30px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.08em;
        box-shadow: 0 12px 34px rgba(34, 40, 63, 0.15);
        animation: toast-in 0.3s ease both;
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .tsp-toast-action {
        border: none;
        background: var(--gold, #c5a35c);
        color: var(--navy, #141b33);
        border-radius: 20px;
        padding: 5px 14px;
        cursor: pointer;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        font-weight: 600;
      }
      .tsp-toast-action:hover {
        background: var(--gold-soft, #e6cf9a);
      }
      .tsp-toast-close {
        border: none;
        background: none;
        color: var(--navy-ink, #f3ead6);
        opacity: 0.6;
        cursor: pointer;
        font-size: 12px;
        padding: 2px 4px;
      }
      .tsp-toast-close:hover {
        opacity: 1;
      }
      @keyframes toast-in {
        from {
          opacity: 0;
          transform: translate(-50%, 8px);
        }
        to {
          opacity: 1;
          transform: translate(-50%, 0);
        }
      }
      .drag-ghost {
        position: absolute;
        z-index: 9999;
        transform: translate(-50%, -50%) rotate(-2deg);
        pointer-events: none;
        width: 38px;
        height: 38px;
        border-radius: 50%;
        overflow: hidden;
        border: 2px solid var(--acc, #c5a35c);
        box-shadow: 0 10px 26px rgba(34, 40, 63, 0.15);
      }
      .dg-photo {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .dg-init {
        width: 100%;
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        font:
          600 14px 'Cormorant Garamond',
          serif;
        color: var(--ink, #22283f);
        background: linear-gradient(
          135deg,
          var(--acc-deep, #a5854a),
          var(--gold, #c5a35c)
        );
      }
      .seat-info {
        position: absolute;
        z-index: 9998;
        pointer-events: none;
        box-sizing: border-box;
        width: 214px;
        padding: 12px 13px;
        background: linear-gradient(168deg, #ffffff, #f0eee7 75%);
        border: 1px solid var(--acc, #c5a35c);
        border-radius: 12px;
        color: var(--ink, #22283f);
        box-shadow: 0 16px 40px rgba(34, 40, 63, 0.16);
        font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
      }
      .si-top {
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .si-photo {
        flex: none;
        width: 40px;
        height: 40px;
        border-radius: 50%;
        object-fit: cover;
        border: 1px solid rgba(34, 40, 63, 0.18);
      }
      .si-init {
        display: flex;
        align-items: center;
        justify-content: center;
        font:
          600 15px 'Cormorant Garamond',
          serif;
        color: var(--ink, #22283f);
        background: linear-gradient(
          135deg,
          var(--acc-deep, #a5854a),
          var(--gold, #c5a35c)
        );
      }
      .si-id {
        min-width: 0;
      }
      .si-name {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 15px;
        line-height: 1.2;
      }
      .si-vip {
        margin-left: 4px;
        padding: 1px 5px;
        border-radius: 4px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 8px;
        letter-spacing: 0.1em;
        color: var(--ink, #22283f);
        background: var(--acc, #c5a35c);
        vertical-align: middle;
      }
      .si-cat {
        display: flex;
        align-items: center;
        gap: 6px;
        margin-top: 3px;
        font-size: 11px;
        color: #57534b;
      }
      .si-swatch {
        width: 9px;
        height: 9px;
        border-radius: 50%;
        flex: none;
      }
      .si-line {
        margin-top: 8px;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10.5px;
        letter-spacing: 0.04em;
        color: var(--gold, #c5a35c);
      }
      .modal-cancel {
        flex: 1;
        height: 46px;
        border: 1px solid rgba(34, 40, 63, 0.1);
        background: none;
        color: var(--ink, #22283f);
        border-radius: 30px;
        cursor: pointer;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
      }
      .modal-save {
        flex: 1;
        height: 46px;
        border: none;
        background: var(--navy, #141b33);
        color: var(--navy-ink, #f3ead6);
        border-radius: 30px;
        cursor: pointer;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        font-weight: 600;
      }
      .modal-save:hover:not(:disabled) {
        background: var(--navy-2, #1a2238);
      }
      .modal-save:disabled {
        opacity: 0.4;
        cursor: not-allowed;
      }
      .pop-head {
        position: sticky;
        top: 0;
        z-index: 2;
        flex: none;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        padding: 11px 12px 10px 16px;
        background: linear-gradient(
          168deg,
          var(--navy, #141b33),
          var(--navy-2, #1a2238)
        );
        border-bottom: 1px solid rgba(197, 163, 92, 0.25);
      }
      .pop-title {
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-size: 15px;
        font-weight: 600;
        color: var(--navy-ink, #f3ead6);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .pop-close {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 28px;
        height: 28px;
        border-radius: 50%;
        border: 1px solid rgba(255, 255, 255, 0.14);
        background: rgba(255, 255, 255, 0.05);
        color: var(--navy-ink, #f3ead6);
        font-size: 13px;
        cursor: pointer;
        transition: 0.14s;
      }
      .pop-close:hover {
        border-color: #e3c27d;
        color: #e3c27d;
      }
      .pop-lead {
        margin: 0 0 12px;
        font-size: 12.5px;
        line-height: 1.5;
        color: color-mix(in srgb, var(--ink, #22283f) 65%, transparent);
      }
      .confirm-detail {
        margin: 8px 0 4px;
        font-size: 13px;
        line-height: 1.6;
        color: var(--ink-2, #57534b);
      }
      .confirm-danger {
        flex: 1;
        height: 46px;
        border: none;
        background: #a8433f;
        color: #ffffff;
        border-radius: 30px;
        cursor: pointer;
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        font-weight: 600;
      }
      .confirm-danger:hover {
        filter: brightness(1.08);
      }
      .pop-actions {
        display: flex;
        gap: 10px;
        width: 100%;
      }
      .pop-actions > button {
        flex: 1;
      }
      .save-field {
        margin-top: 6px;
        display: flex;
        flex-direction: column;
        gap: 7px;
      }
      .save-field-label {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 10px;
        letter-spacing: 0.16em;
        text-transform: uppercase;
        color: var(--acc-deep, #a5854a);
      }
      .save-input {
        height: 44px;
        padding: 0 14px;
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 12px;
        background: rgba(34, 40, 63, 0.03);
        color: var(--ink, #22283f);
        font-family: var(--font-serif, 'Cormorant Garamond', serif);
        font-size: 15px;
      }
      .save-input:focus {
        outline: none;
        border-color: var(--acc, #c5a35c);
      }
      .save-error {
        margin: 10px 0 0;
        color: #a14a2e;
        font-size: 12px;
      }
      .preview-body {
        padding-top: 8px;
      }
      .preview-body :where(svg) {
        width: 100%;
        height: 200px;
        background: rgba(34, 40, 63, 0.03);
        border: 1px solid var(--surface-edge, rgba(197, 163, 92, 0.35));
        border-radius: 10px;
      }
      .preview-foot {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        width: 100%;
      }
      .preview-meta {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        white-space: nowrap;
        color: rgba(34, 40, 63, 0.6);
      }
      .preview-apply {
        flex: none;
        height: 34px;
        padding: 0 18px;
        font-size: 10px;
        letter-spacing: 0.12em;
      }
      .ct-tpl {
        display: flex;
        align-items: stretch;
        gap: 2px;
      }
      .ct-tpl-apply {
        flex: 1;
        min-width: 0;
      }
      .ct-tpl-eye {
        flex: none;
        width: 34px;
        display: flex;
        align-items: center;
        justify-content: center;
        border: none;
        background: none;
        border-radius: 10px;
        color: var(--acc-deep, #a5854a);
        font-size: 15px;
        cursor: pointer;
        transition: 0.13s;
      }
      .ct-tpl-eye:hover {
        background: rgba(197, 163, 92, 0.16);
        color: var(--ink, #22283f);
      }
    </style>
  </template>
}
interface TableConfigSignature {
  Args: { c: TableSeatingPlannerIsolated };
}
const TableConfig: TemplateOnlyComponent<TableConfigSignature> = <template>
  <div class='tpop-label'>Shape</div>
  <div class='tpop-shapes'>
    {{#each @c.tableShapes as |sh|}}
      <button
        type='button'
        class='tpop-shape {{if (eq @c.selectedTable.shape sh.value) "is-on"}}'
        {{on 'click' (fn @c.setShape sh.value)}}
      >{{sh.label}}</button>
    {{/each}}
  </div>
  {{#if (eq @c.selectedTable.shape 'section')}}
    <div class='tpop-row'>
      <span class='tpop-label'>Rows</span>
      <div class='tpop-step'>
        <button type='button' {{on 'click' @c.decRows}}>−</button>
        <input
          class='tpop-num'
          type='number'
          min='1'
          max='60'
          aria-label='Rows'
          value={{@c.selectedTable.rows}}
          {{on 'change' @c.rowsInput}}
        />
        <button type='button' {{on 'click' @c.incRows}}>+</button>
      </div>
    </div>
    <div class='tpop-row'>
      <span class='tpop-label'>Seats / row</span>
      <div class='tpop-step'>
        <button type='button' {{on 'click' @c.decCols}}>−</button>
        <input
          class='tpop-num'
          type='number'
          min='1'
          max='60'
          aria-label='Seats per row'
          value={{@c.selectedTable.cols}}
          {{on 'change' @c.colsInput}}
        />
        <button type='button' {{on 'click' @c.incCols}}>+</button>
      </div>
    </div>
    <div class='tpop-label'>Facing (front row → stage)</div>
    <div class='tpop-shapes'>
      <button
        type='button'
        class='tpop-shape {{if (@c.facingIs 0) "is-on"}}'
        {{on 'click' (fn @c.setFacing 0)}}
      >▲ Up</button>
      <button
        type='button'
        class='tpop-shape {{if (@c.facingIs 90) "is-on"}}'
        {{on 'click' (fn @c.setFacing 90)}}
      >▶ Right</button>
      <button
        type='button'
        class='tpop-shape {{if (@c.facingIs 180) "is-on"}}'
        {{on 'click' (fn @c.setFacing 180)}}
      >▼ Down</button>
      <button
        type='button'
        class='tpop-shape {{if (@c.facingIs 270) "is-on"}}'
        {{on 'click' (fn @c.setFacing 270)}}
      >◀ Left</button>
    </div>
    <div class='tpop-label'>Seat numbering</div>
    <div class='tpop-orders'>
      {{#each @c.seatOrders as |o|}}
        <button
          type='button'
          class='tpop-order {{if (@c.seatOrderIs o.value) "is-on"}}'
          {{on 'click' (fn @c.setSeatOrder o.value)}}
        >{{o.label}}</button>
      {{/each}}
    </div>
  {{else}}
    <div class='tpop-row'>
      <span class='tpop-label'>Seats</span>
      <div class='tpop-step'>
        <button type='button' {{on 'click' @c.decSeats}}>−</button>
        <input
          class='tpop-num'
          type='number'
          min='0'
          max='99'
          aria-label='Seats'
          value={{@c.selectedTable.seatCount}}
          {{on 'change' @c.seatsInput}}
        />
        <button type='button' {{on 'click' @c.incSeats}}>+</button>
      </div>
    </div>
    {{#if @c.showSeatingStyle}}
      <div class='tpop-label'>Seating sides</div>
      <div class='tpop-shapes'>
        {{#each @c.seatingStyles as |st|}}
          <button
            type='button'
            class='tpop-shape {{if (@c.seatingStyleIs st.value) "is-on"}}'
            {{on 'click' (fn @c.setSeatingStyle st.value)}}
          >{{st.label}}</button>
        {{/each}}
      </div>
    {{/if}}
  {{/if}}
  <div class='tpop-label'>Table rank
    <span class='tpop-rank-badge'>#{{@c.selectedTableRank}}</span>
  </div>
  <div class='tpop-rank'>
    <input
      type='number'
      min='1'
      max={{@c.tableCount}}
      class='tpop-rank-input'
      aria-label='Table rank'
      placeholder='Auto'
      value={{if @c.selectedTablePinned @c.selectedTable.rank ''}}
      {{on 'change' @c.pinTableRankInput}}
    />
    <button
      type='button'
      class='tpop-rank-auto {{unless @c.selectedTablePinned "is-on"}}'
      {{on 'click' @c.clearTableRank}}
    >Auto</button>
  </div>
  <style scoped>
    .tpop-label {
      font-family: var(--font-sans, 'Jost', sans-serif);
      font-size: 9.5px;
      letter-spacing: 0.2em;
      text-transform: uppercase;
      color: #7c766c;
      margin: 16px 0 9px;
    }
    .tpop-shapes {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 6px;
    }
    .tpop-shape {
      height: 34px;
      border: 1px solid rgba(34, 40, 63, 0.1);
      background: rgba(34, 40, 63, 0.04);
      color: var(--ink, #22283f);
      border-radius: 8px;
      font-size: 10.5px;
      cursor: pointer;
      transition: 0.15s;
    }
    .tpop-shape:hover {
      border-color: var(--gold, #c5a35c);
    }
    .tpop-shape.is-on {
      background: var(--gold, #c5a35c);
      color: var(--ink, #22283f);
      border-color: var(--gold, #c5a35c);
    }
    .tpop-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-top: 4px;
    }
    .tpop-row .tpop-label {
      margin: 16px 0 0;
    }
    .tpop-step {
      display: flex;
      align-items: center;
      gap: 4px;
      margin-top: 12px;
    }
    .tpop-step button {
      width: 30px;
      height: 30px;
      border-radius: 8px;
      border: 1px solid rgba(34, 40, 63, 0.12);
      background: rgba(34, 40, 63, 0.04);
      color: var(--ink, #22283f);
      font-size: 17px;
      cursor: pointer;
    }
    .tpop-step button:hover {
      border-color: var(--gold, #c5a35c);
    }
    .tpop-num {
      min-width: 30px;
      width: 44px;
      text-align: center;
      font-family: var(--font-serif, 'Cormorant Garamond', serif);
      font-size: 19px;
      border: none;
      background: transparent;
      color: inherit;
      padding: 0;
      appearance: textfield;
      -moz-appearance: textfield;
    }
    .tpop-num:focus {
      outline: 1px solid var(--tsp-gold, #c5a35c);
      border-radius: 6px;
    }
    .tpop-num::-webkit-outer-spin-button,
    .tpop-num::-webkit-inner-spin-button {
      appearance: none;
      margin: 0;
    }
    .tpop-orders {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 6px;
    }
    .tpop-order {
      height: 30px;
      border: 1px solid rgba(34, 40, 63, 0.1);
      background: rgba(34, 40, 63, 0.04);
      color: var(--ink, #22283f);
      border-radius: 8px;
      font-family: var(--font-sans, 'Jost', sans-serif);
      font-size: 9.5px;
      letter-spacing: 0.02em;
      cursor: pointer;
      transition: 0.15s;
    }
    .tpop-order:hover {
      border-color: var(--gold, #c5a35c);
    }
    .tpop-order.is-on {
      background: var(--gold, #c5a35c);
      color: var(--ink, #22283f);
      border-color: var(--gold, #c5a35c);
    }
    .tpop-rank-badge {
      margin-left: 6px;
      padding: 1px 7px;
      border-radius: 20px;
      background: rgba(197, 163, 92, 0.18);
      color: var(--gold, #c5a35c);
      letter-spacing: 0.04em;
    }
    .tpop-rank {
      display: flex;
      gap: 8px;
    }
    .tpop-rank-input {
      flex: 1;
      min-width: 0;
      height: 34px;
      padding: 0 12px;
      border-radius: 8px;
      border: 1px solid rgba(34, 40, 63, 0.1);
      background: rgba(34, 40, 63, 0.04);
      color: var(--ink, #22283f);
      font-family: var(--font-sans, 'Jost', sans-serif);
      font-size: 12px;
    }
    .tpop-rank-input:focus {
      outline: none;
      border-color: var(--gold, #c5a35c);
    }
    .tpop-rank-auto {
      flex: none;
      padding: 0 14px;
      height: 34px;
      border-radius: 8px;
      border: 1px solid rgba(34, 40, 63, 0.1);
      background: rgba(34, 40, 63, 0.04);
      color: var(--ink, #22283f);
      font-size: 10.5px;
      cursor: pointer;
      transition: 0.15s;
    }
    .tpop-rank-auto:hover {
      border-color: var(--gold, #c5a35c);
    }
    .tpop-rank-auto.is-on {
      background: var(--gold, #c5a35c);
      border-color: var(--gold, #c5a35c);
      color: var(--ink, #22283f);
    }
  </style>
</template>;
let _keySeq = 0;
const _keys = new WeakMap<object, string>();
function keyOf(obj: unknown): string {
  if (!obj || typeof obj !== 'object') return '';
  let k = _keys.get(obj);
  if (!k) {
    k = `k${++_keySeq}`;
    _keys.set(obj, k);
  }
  return k;
}
function htmlBg(color: string | null | undefined) {
  return htmlSafe(`background:${color || '#c5a35c'}`);
}
function htmlBarWidth(pct: string) {
  return htmlSafe(`width:${pct}`);
}
function htmlWorld(style: string) {
  return htmlSafe(style);
}
function htmlSeat(left: string, top: string, color: string) {
  return htmlSafe(`left:${left};top:${top};--seatcol:${color}`);
}
function htmlGhost(x: number, y: number) {
  return htmlSafe(`left:${x}px;top:${y}px`);
}
const SHAPE_VALUES = TABLE_SHAPES.map((s) => s.value);
const FIXTURE_VALUES = FIXTURE_KINDS.map((k) => k.value);
function clampNum(v: unknown, min: number, max: number, def: number): number {
  let n = Number(v);
  if (!isFinite(n)) return def;
  return Math.max(min, Math.min(max, Math.round(n)));
}
function arrayBufferToBase64(buffer: ArrayBuffer): string {
  let binary = '';
  let bytes = new Uint8Array(buffer);
  let chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(
      null,
      Array.from(bytes.subarray(i, i + chunk)) as unknown as number[],
    );
  }
  return btoa(binary);
}
function imageDims(src: string): Promise<{ w: number; h: number }> {
  return new Promise((resolve) => {
    let img = new Image();
    img.onload = () =>
      resolve({ w: img.naturalWidth || 800, h: img.naturalHeight || 600 });
    img.onerror = () => resolve({ w: 800, h: 600 });
    img.src = src;
  });
}
function cloneTableGeometry(t: Table): Table {
  return new Table({
    name: t.name,
    shape: t.shape,
    seatCount: t.seatCount,
    seatingStyle: t.seatingStyle,
    rows: t.rows,
    cols: t.cols,
    x: t.x,
    y: t.y,
    width: t.width,
    height: t.height,
    rotation: t.rotation,
    z: t.z,
    themeColor: t.themeColor,
    vip: t.vip,
    note: t.note,
  });
}
function cloneTableWithSeating(t: Table): Table {
  let copy = cloneTableGeometry(t);
  copy.seatOrder = t.seatOrder;
  copy.reservedCategories = [...(t.reservedCategories ?? [])];
  copy.seatedGuests = [...((t.seatedGuests ?? []) as Guest[])];
  copy.seatSlots = [...(t.seatSlots ?? [])];
  copy.rank = t.rank;
  copy.locked = t.locked;
  return copy;
}
function cloneFixture(f: Fixture): Fixture {
  return new Fixture({
    label: f.label,
    kind: f.kind,
    pattern: f.pattern,
    x: f.x,
    y: f.y,
    width: f.width,
    height: f.height,
    rotation: f.rotation,
    z: f.z,
    color: f.color,
  });
}
function loadScriptOnce(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src='${src}']`)) return resolve();
    let s = document.createElement('script');
    s.src = src;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error('Could not load PDF renderer'));
    document.head.appendChild(s);
  });
}
function loadImageEl(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    let img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('image decode failed'));
    img.src = src;
  });
}
function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    let timer = setTimeout(
      () =>
        reject(
          new Error(
            `${label} timed out after ${Math.round(
              ms / 1000,
            )}s — the AI service didn't respond. Check AI credits / connection and try again.`,
          ),
        ),
      ms,
    );
    p.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}
async function gridOverlay(
  dataUrl: string,
  rect: { x: number; y: number; w: number; h: number },
): Promise<string> {
  let img: HTMLImageElement;
  try {
    img = await loadImageEl(dataUrl);
  } catch {
    return dataUrl;
  }
  let nw = img.naturalWidth || 800;
  let nh = img.naturalHeight || 600;
  let MAX = 1400;
  let scale = Math.min(1, MAX / Math.max(nw, nh));
  let w = Math.max(1, Math.round(nw * scale));
  let h = Math.max(1, Math.round(nh * scale));
  let canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  let ctx = canvas.getContext('2d');
  if (!ctx) return dataUrl;
  ctx.drawImage(img, 0, 0, w, h);
  let N = 20;
  ctx.strokeStyle = 'rgba(220,40,40,0.4)';
  ctx.lineWidth = Math.max(1, w / 1100);
  ctx.fillStyle = 'rgba(220,40,40,0.95)';
  let fs = Math.max(10, Math.round(w / 80));
  ctx.font = `bold ${fs}px sans-serif`;
  for (let i = 0; i <= N; i++) {
    let px = (w * i) / N;
    let py = (h * i) / N;
    ctx.beginPath();
    ctx.moveTo(px, 0);
    ctx.lineTo(px, h);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(0, py);
    ctx.lineTo(w, py);
    ctx.stroke();
    ctx.fillText(String(Math.round(rect.x + (rect.w * i) / N)), px + 3, fs + 2);
    ctx.fillText(String(Math.round(rect.y + (rect.h * i) / N)), 3, py + fs + 2);
  }
  return canvas.toDataURL('image/png');
}
async function renderPdfToPng(file: File): Promise<string> {
  let base = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174';
  await loadScriptOnce(`${base}/pdf.min.js`);
  let pdfjs = (window as any).pdfjsLib;
  if (!pdfjs) throw new Error('PDF renderer unavailable');
  pdfjs.GlobalWorkerOptions.workerSrc = `${base}/pdf.worker.min.js`;
  let data = await file.arrayBuffer();
  let pdf = await pdfjs.getDocument({ data }).promise;
  let page = await pdf.getPage(1);
  let viewport = page.getViewport({ scale: 2 });
  let canvas = document.createElement('canvas');
  canvas.width = viewport.width;
  canvas.height = viewport.height;
  let context = canvas.getContext('2d');
  await page.render({ canvasContext: context, viewport }).promise;
  return canvas.toDataURL('image/png');
}
export class TableSeatingPlannerFitted extends Component<
  typeof TableSeatingPlanner
> {
  get seatedCount() {
    let ids = new Set<string>();
    for (let t of (this.args.model?.tables ?? []) as Table[]) {
      if (!t) continue;
      for (let g of t.seatedGuests ?? []) if (g) ids.add(keyOf(g));
    }
    return ids.size;
  }
  get themeVars() {
    return htmlSafe(buildThemeVars((this.args.model as any)?.cardInfo?.theme));
  }
  <template>
    <div class='cq' style={{this.themeVars}}>
      <div class='fit'>
        <div class='r-head'>
          <span class='title'>{{if
              @model.eventTitle
              @model.eventTitle
              'Seating Plan'
            }}</span>
        </div>
        <div class='r-body'>
          <span class='stat'><b>{{@model.tables.length}}</b> tables</span>
          <span class='stat'><b
            >{{this.seatedCount}}</b>/{{@model.guests.length}}
            seated</span>
        </div>
      </div>
    </div>
    <style scoped>
      @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400..700;1,400..700&family=Jost:ital,wght@0,300..600;1,300..600&display=swap');
      .cq {
        container-type: size;
        container-name: plan;
        width: 100%;
        height: 100%;
        overflow: hidden;
      }
      .fit {
        width: 100%;
        height: 100%;
        display: flex;
        flex-direction: column;
        justify-content: center;
        gap: 8px;
        padding: 16px;
        box-sizing: border-box;
        overflow: hidden;
        background: linear-gradient(
          168deg,
          var(--navy, #141b33),
          var(--navy-2, #1a2238)
        );
        color: var(--navy-ink, #f3ead6);
        font-family: var(--font-sans, 'Jost', system-ui, sans-serif);
      }
      .r-head {
        overflow: hidden;
        min-height: 0;
      }
      .title {
        display: block;
        font-family: var(--font-serif, 'Cormorant Garamond', Georgia, serif);
        font-style: italic;
        font-size: 19px;
        color: var(--gold-soft, #e6cf9a);
        margin-top: 4px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .r-body {
        display: flex;
        gap: 16px;
        overflow: hidden;
        min-height: 0;
      }
      .stat {
        font-family: var(--font-sans, 'Jost', sans-serif);
        font-size: 11px;
        color: rgba(243, 234, 214, 0.7);
      }
      .stat b {
        color: var(--gold, #c5a35c);
        font-size: 15px;
      }
      @container plan (height <= 70px) {
        .r-body {
          display: none;
        }
      }
    </style>
  </template>
}
