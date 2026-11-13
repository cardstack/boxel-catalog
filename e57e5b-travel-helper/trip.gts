// A trip, and the packing that goes with it. Open it on the computer to plan
// (weather, sourced notes, the checklist by category, the bag gauge) and on
// the phone to shoot: every photo is saved into this workspace, read by the
// AI, and turned into item cards the computer's checklist picks up live. The
// dossier is the trip's living summary that any helper can carry on from.
import {
  CardDef,
  Component,
  field,
  contains,
  realmURL,
  getDataBucket,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import NumberField from '@cardstack/base/number';
import MarkdownField from '@cardstack/base/markdown';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import LuggageIcon from '@cardstack/boxel-icons/luggage';
import ShirtIcon from '@cardstack/boxel-icons/shirt';
import PlugIcon from '@cardstack/boxel-icons/plug';
import DropletIcon from '@cardstack/boxel-icons/droplet';
import IdCardIcon from '@cardstack/boxel-icons/id-card';
import PillIcon from '@cardstack/boxel-icons/pill';
import PackageIcon from '@cardstack/boxel-icons/package';
import CameraIcon from '@cardstack/boxel-icons/camera';
import SmartphoneIcon from '@cardstack/boxel-icons/smartphone';
import SnowflakeIcon from '@cardstack/boxel-icons/snowflake';
import CloudRainIcon from '@cardstack/boxel-icons/cloud-rain';
import CloudIcon from '@cardstack/boxel-icons/cloud';
import CloudFogIcon from '@cardstack/boxel-icons/cloud-fog';
import CloudLightningIcon from '@cardstack/boxel-icons/cloud-lightning';
import SunIcon from '@cardstack/boxel-icons/sun';
import WriteBinaryFileCommand from '@cardstack/boxel-host/tools/write-binary-file';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import {
  PackItem,
  Snap,
  Thing,
  STATUS_NAMES,
  boxStyle,
  photosOf,
  aiNotesOf,
  day,
  type ThingPhoto,
} from './items';
import {
  CATEGORIES,
  CATEGORY_NAMES,
  asCategory,
  toolCtx,
  shrink,
  cutout,
  blobToBase64,
  see,
  placeBoxes,
  readChecklist,
  describe,
  suggestLeave,
  weather,
  research,
  palette,
  plan,
  sky,
  type SnapMode,
  type KnownItem,
  type BagSeen,
  type DayWeather,
  type Note,
  type Palette,
} from './travel-ai';

// @ts-ignore import.meta is fine here (the host loads cards as ES modules); the catalog's CommonJS type check rejects it
const here: string = import.meta.url;
const ITEMS = new URL('./items', here).href;
const TRIP = new URL('./trip', here).href;
const MODES: { key: SnapMode; label: string; hint: string }[] = [
  {
    key: 'items',
    label: 'Laying out',
    hint: 'Things you might bring, spread out',
  },
  { key: 'packing', label: 'Packing', hint: 'Things going into the bag' },
  { key: 'bag', label: 'The bag', hint: 'The empty bag, to size it' },
  {
    key: 'away',
    label: 'Put away',
    hint: 'Home again: each thing going back where it lives, with the spot in view',
  },
];
// each category keeps one hue and one picture, so a row without a photo yet
// still says what kind of thing it is
const CAT_LOOK: Record<string, { hue: number; icon: any }> = {
  wardrobe: { hue: 25, icon: ShirtIcon },
  electronics: { hue: 255, icon: PlugIcon },
  toiletries: { hue: 185, icon: DropletIcon },
  documents: { hue: 80, icon: IdCardIcon },
  medicine: { hue: 340, icon: PillIcon },
  other: { hue: 295, icon: PackageIcon },
};

const SKY_ICON: Record<string, any> = {
  Snow: SnowflakeIcon,
  Rain: CloudRainIcon,
  Cloudy: CloudIcon,
  Fog: CloudFogIcon,
  Storms: CloudLightningIcon,
  Clear: SunIcon,
};
// AI names come lower-case ("black beanie"); the list reads better capitalised
const cap = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);

// ─── the trip's colours ──────────────────────────────────────────────────
// The page takes its colours from the place (three the AI picks for that
// place in that month) and from the things going (the strongest colour in
// each photo). Only the hue and strength are kept; lightness is set here,
// so the page stays light and the text stays readable whatever comes back.
type Tint = { c: number; h: number };
function oklchOf(r: number, g: number, b: number) {
  const lin = (v: number) =>
    (v /= 255) <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  const [R, G, B] = [lin(r), lin(g), lin(b)];
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  const a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return {
    l: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    c: Math.hypot(a, bb),
    h: ((Math.atan2(bb, a) * 180) / Math.PI + 360) % 360,
  };
}
const hexTint = (hex: string): Tint => {
  const n = parseInt(hex.slice(1), 16);
  return oklchOf(n >> 16, (n >> 8) & 255, n & 255);
};
// no palette yet: a steady hue from the place's name, or a warm default
function guessTints(place: string): Tint[] {
  if (!place)
    return [
      { c: 0.1, h: 230 },
      { c: 0.1, h: 160 },
      { c: 0.15, h: 35 },
    ];
  let n = 0;
  for (const ch of place) n = (n * 31 + ch.charCodeAt(0)) % 360;
  return [
    { c: 0.1, h: n },
    { c: 0.1, h: (n + 120) % 360 },
    { c: 0.15, h: (n + 200) % 360 },
  ];
}
const ok = (l: number, c: number, h: number) =>
  `oklch(${l} ${c.toFixed(3)} ${h.toFixed(0)})`;
// `packed` (0-1): the page comes into colour as the bag fills
function lookVars(
  pal: Palette | null,
  place: string,
  things: Tint[],
  packed = 1,
) {
  const [sky, land, picked] = pal
    ? pal.colors.map((x) => hexTint(x.hex))
    : guessTints(place);
  // the accent keeps clear of the status colours (have: blue, packed: green)
  let mark = picked;
  for (const h of [152, 255]) {
    const d = ((mark.h - h + 540) % 360) - 180;
    if (Math.abs(d) < 30)
      mark = { ...mark, h: (h + (d < 0 ? -32 : 32) + 360) % 360 };
  }
  const k = 0.4 + 0.6 * Math.max(0, Math.min(1, packed));
  // a near-white pick ("snowy mountains") still gets enough colour to read as that hue
  const soft = (t: Tint, l = 0.9, cap = 0.11) =>
    ok(l, k * Math.max(0.05, Math.min(t.c, cap)), t.h);
  const [t1, t2] = [things[0] ?? mark, things[1] ?? things[0] ?? land];
  return [
    `--g1:${soft(sky, 0.88, 0.12)}`,
    `--g2:${soft(land, 0.9)}`,
    `--g3:${ok(0.975, k * 0.014, sky.h)}`,
    `--g4:${soft(t1, 0.91, 0.09)}`,
    `--g5:${soft(t2, 0.92, 0.08)}`,
    `--s1:${ok(0.82, Math.max(0.07, Math.min(sky.c, 0.12)), sky.h)}`,
    `--s2:${ok(0.6, Math.max(0.08, Math.min(land.c, 0.14)), land.h)}`,
    `--s3:${ok(0.66, Math.max(0.12, Math.min(mark.c, 0.19)), mark.h)}`,
    `--acc:${ok(0.5, Math.max(0.11, Math.min(mark.c, 0.17)), mark.h)}`,
    `--acc-soft:${ok(0.95, 0.035, mark.h)}`,
    `--ink:${ok(0.24, 0.025, land.h)}`,
    `--muted:${ok(0.48, 0.03, land.h)}`,
  ].join(';');
}
// the strongest colour near the middle of a photo (the table it sits on is
// usually dull brown at the edges, so the middle and the vivid count most)
const tintCache = new Map<string, Tint | null>();
function photoTint(url: string): Promise<Tint | null> {
  if (tintCache.has(url)) return Promise.resolve(tintCache.get(url)!);
  return new Promise((done) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    const finish = (t: Tint | null) => (tintCache.set(url, t), done(t));
    img.onerror = () => finish(null);
    img.onload = () => {
      try {
        const N = 24;
        const cv = document.createElement('canvas');
        cv.width = cv.height = N;
        const g = cv.getContext('2d')!;
        g.drawImage(img, 0, 0, N, N);
        const px = g.getImageData(0, 0, N, N).data;
        const bins = Array.from({ length: 12 }, () => ({
          w: 0,
          x: 0,
          y: 0,
          c: 0,
        }));
        for (let i = 0; i < N * N; i++) {
          const o = oklchOf(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]);
          if (o.c < 0.06 || o.l < 0.35 || o.l > 0.96) continue;
          const dx = (i % N) / N - 0.5;
          const dy = Math.floor(i / N) / N - 0.5;
          const w = o.c * o.c * Math.max(0.1, 1 - 2.2 * Math.hypot(dx, dy));
          const b = bins[Math.floor(o.h / 30) % 12];
          b.w += w;
          b.x += w * Math.cos((o.h * Math.PI) / 180);
          b.y += w * Math.sin((o.h * Math.PI) / 180);
          b.c += w * o.c;
        }
        const top = bins.reduce((a, b) => (b.w > a.w ? b : a));
        finish(
          top.w > 0.02
            ? {
                c: top.c / top.w,
                h: ((Math.atan2(top.y, top.x) * 180) / Math.PI + 360) % 360,
              }
            : null,
        );
      } catch {
        finish(null);
      }
    };
    img.src = url;
  });
}
// let the colours ease from one trip's to the next instead of jumping
let propsDone = false;
function registerLookProps() {
  if (propsDone) return;
  propsDone = true;
  for (const name of [
    '--g1',
    '--g2',
    '--g3',
    '--g4',
    '--g5',
    '--s1',
    '--s2',
    '--s3',
    '--acc',
    '--acc-soft',
  ]) {
    try {
      (CSS as any).registerProperty({
        name,
        syntax: '<color>',
        inherits: true,
        initialValue: 'transparent',
      });
    } catch {
      /* already registered */
    }
  }
}

const QR_LIB =
  'https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js';

function parse<T>(raw: string | null | undefined, fallback: T): T {
  try {
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}
const lines = (raw: string | null | undefined) =>
  (raw ?? '')
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean);
const slug = (s: string) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 40) || 'item';
// a scan's remark about the photo ("partially visible", "possibly a cloth") isn't
// worth keeping on the thing; one about the thing ("Malaysia passport") is
const keepNote = (n: string | null | undefined) =>
  n &&
  !/visible|unclear|possibly|guess|count|pile|hidden|not a |part of/i.test(n)
    ? n
    : undefined;
// where a link points, whether or not the linked card has loaded
function linkId(card: any, name: string): string | null {
  try {
    const v: any = getDataBucket(card)?.get(name);
    if (!v) return null;
    const ref = v.reference ?? v.id;
    return ref ? new URL(ref, card.id).href.replace(/\.json$/, '') : null;
  } catch {
    return null;
  }
}
const norm = (s: string) =>
  (s ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
const stamp = () => new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const round1 = (n: number) => Math.round(n * 10) / 10;
// which drawing a bag gets, from what the camera called it; a suitcase when unsure
const bagShape = (type: string): 'case' | 'backpack' | 'duffel' =>
  /back ?pack|rucksack|day ?pack|school ?bag|knapsack/i.test(type)
    ? 'backpack'
    : /duffel|duffle|holdall|weekender|gym|tote|messenger|shoulder|sling|hand ?bag|sports? bag/i.test(
          type,
        )
      ? 'duffel'
      : 'case';
// a web page's words, one block per line (scripts, styles and markup dropped)
function htmlText(raw: string) {
  const doc = new DOMParser().parseFromString(raw, 'text/html');
  doc
    .querySelectorAll('script, style, noscript, template, svg')
    .forEach((n) => n.remove());
  doc
    .querySelectorAll(
      'br, p, div, li, tr, h1, h2, h3, h4, h5, h6, label, summary, dt, dd, section, article, header, footer',
    )
    .forEach((n) => n.append('\n'));
  return (doc.body?.textContent ?? '')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n\s*\n+/g, '\n')
    .trim();
}

// the camera frame's size, and the viewfinder's, when a frame was read
interface View {
  vw: number;
  vh: number;
  ew: number;
  eh: number;
}
// where a box (0-1000 units of the frame) sits on the viewfinder, which
// crops the frame to fill itself (object-fit: cover), in %
function placeOn(v: View, box: number[]) {
  const k = Math.max(v.ew / v.vw, v.eh / v.vh);
  const dw = v.vw * k;
  const dh = v.vh * k;
  const ox = (v.ew - dw) / 2;
  const oy = (v.eh - dh) / 2;
  const [y0, x0, y1, x1] = box.map(
    (n) => Math.max(0, Math.min(1000, Number(n))) / 1000,
  );
  const clamp = (n: number) => Math.max(0, Math.min(100, n));
  const x = clamp(((ox + x0 * dw) / v.ew) * 100);
  const y = clamp(((oy + y0 * dh) / v.eh) * 100);
  const w = clamp(((ox + x1 * dw) / v.ew) * 100) - x;
  const h = clamp(((oy + y1 * dh) / v.eh) * 100) - y;
  return {
    x,
    y,
    w,
    h,
    css: `left:${x.toFixed(1)}%;top:${y.toFixed(1)}%;width:${w.toFixed(1)}%;height:${h.toFixed(1)}%`,
  };
}

class TripView extends Component<typeof Trip> {
  @tracked mode: SnapMode = 'items';
  @tracked busy = '';
  @tracked error = '';
  @tracked feed: {
    id: number;
    text: string;
    kind: string;
    item?: string;
    gone?: boolean;
  }[] = [];
  @tracked showSkipped = false;
  @tracked deleted: string[] = []; // hidden at once; the search index catches up a few seconds later
  @tracked pending = 0;
  @tracked camOn = false;
  @tracked auto = false;
  @tracked marks: {
    id: number;
    label: string;
    kind: string;
    top: boolean;
    style: any;
  }[] = [];
  @tracked lastMs = 0;
  @tracked qr = '';
  @tracked showDossier = false;
  @tracked zoom: any = null; // the item whose photo is open big
  @tracked thingTints: Tint[] = []; // the strongest colours among the things going
  private paletteAsked = false;
  private queue: { blob: Blob; mode: SnapMode; view: View | null }[] = [];
  private running = false;
  private stream: MediaStream | null = null;
  private video: HTMLVideoElement | null = null;
  private ticker: ReturnType<typeof setInterval> | null = null;
  private lastSample: Uint8ClampedArray | null = null;
  private lastSent: Uint8ClampedArray | null = null;
  private lastShot = 0;
  private feedId = 0;
  private markId = 0;
  private timers: ReturnType<typeof setTimeout>[] = [];
  private vfEl: HTMLElement | null = null;
  private trayEl: HTMLElement | null = null;

  get ctx() {
    return toolCtx(this.args.context);
  }
  get realm() {
    return this.args.model[realmURL]?.href ?? '';
  }
  get realms() {
    return this.realm ? [this.realm] : [];
  }
  get tripId(): string {
    return (this.args.model as any).id ?? '';
  }

  // this trip's own lines and photos (a search for every trip's would hit the result cap)
  itemsQ = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          on: { module: ITEMS, name: 'PackItem' },
          eq: { 'trip.id': this.tripId },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  snapsQ = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          on: { module: ITEMS, name: 'Snap' },
          eq: { 'trip.id': this.tripId },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  thingsQ = this.args.context?.getCards(
    this,
    () => ({ filter: { type: { module: ITEMS, name: 'Thing' } } }) as any,
    () => this.realms,
    { isLive: true },
  );
  // the trip a list is being copied from: its own lines, loaded on their own
  @tracked srcTrip = '';
  srcQ = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          on: { module: ITEMS, name: 'PackItem' },
          eq: { 'trip.id': this.srcTrip || 'none' },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  tripsQ = this.args.context?.getCards(
    this,
    () => ({ filter: { type: { module: TRIP, name: 'Trip' } } }) as any,
    () => this.realms,
    { isLive: true },
  );

  // everything they own, across trips
  get ownThings(): any[] {
    return ((this.thingsQ?.instances ?? []) as any[]).filter(
      (x) => x?.id && !this.deleted.includes(x.id),
    );
  }
  get thingById() {
    return new Map(this.ownThings.map((t) => [t.id, t]));
  }
  // the thing a line is, once the camera has found it
  thingOf(x: any): any {
    let t: any = null;
    try {
      t = x?.thing ?? null; // starts loading it, if it hasn't
    } catch {
      t = null;
    }
    if (t?.id) return this.thingById.get(t.id) ?? t;
    // not loaded yet: the link's address is enough to find it among their things
    const id = linkId(x, 'thing');
    return id ? (this.thingById.get(id) ?? null) : null;
  }
  // what a line shows: the thing's photo and size; the name is the thing's,
  // unless the line came from their own checklist (their wording stays)
  view(x: any) {
    const t = this.thingOf(x);
    return {
      t,
      name: (t && !x.fromList ? t.name : x.name) ?? '',
      photo: t?.photo || x.photo,
      category: t?.category ?? x.category,
      litres: t?.litres ?? x.litres,
      kg: t?.kg ?? x.kg,
      snapPhoto: t ? t.snapPhoto : x.snapPhoto,
      box: t ? t.box : x.box,
    };
  }
  // a key from the AI: a line on this trip, or a thing they own that isn't on it
  resolveMatch(id: string | null): { it?: any; th?: any } {
    if (!id) return {};
    const it = this.items.find((x) => x.id === id);
    if (it) return { it };
    const th = this.thingById.get(id);
    return th ? { th } : {};
  }

  get items(): any[] {
    return ((this.itemsQ?.instances ?? []) as any[]).filter(
      (x) => x?.trip?.id === this.tripId && !this.deleted.includes(x.id),
    );
  }
  // things to pack; tasks (from an imported checklist) are listed on their own
  get things(): any[] {
    return this.items.filter((x) => x.kind !== 'task');
  }
  get tasks() {
    return this.items
      .filter((x) => x.kind === 'task' && x.status !== 'skip')
      .map((x) => ({
        id: x.id,
        name: x.name,
        why: x.why,
        done: x.status === 'packed',
      }));
  }
  toggleTask = (t: { id: string; done: boolean }) =>
    this.patchItem(t.id, { status: t.done ? 'needed' : 'packed' });
  get snaps(): any[] {
    return ((this.snapsQ?.instances ?? []) as any[])
      .filter((x) => x?.trip?.id === this.tripId)
      .sort((a, b) =>
        String(b.takenAt ?? '').localeCompare(String(a.takenAt ?? '')),
      );
  }
  // this trip's lines, then what they own that isn't on it
  get known(): KnownItem[] {
    const lines = this.things.map((x) => {
      const v = this.view(x);
      return {
        id: x.id,
        name: v.name,
        category: v.category ?? 'other',
        status: x.status ?? '',
      };
    });
    const onIt = new Set(
      this.things.map((x) => this.thingOf(x)?.id).filter(Boolean),
    );
    const owned = this.ownThings
      .filter((t) => !onIt.has(t.id))
      .map((t) => ({
        id: t.id,
        name: t.name ?? '',
        category: t.category ?? 'other',
        status: 'owned, not on this list',
      }));
    return [...lines, ...owned];
  }

  // ─── the trip's colours ────────────────────────────────────────────────
  get pal(): Palette | null {
    return parse<Palette | null>(this.args.model.palette, null);
  }
  get lookStyle() {
    return htmlSafe(
      lookVars(
        this.pal,
        this.args.model.place ?? '',
        this.thingTints,
        this.progress.share,
      ),
    );
  }
  // what's packed of what's going: the postmark's ring and the page's colour
  get progress() {
    const going = this.things.filter(
      (x) =>
        x.status === 'packed' ||
        x.status === 'have' ||
        x.status === 'needed' ||
        x.status === 'leave',
    );
    const packed = going.filter((x) => x.status === 'packed').length;
    const share = going.length ? packed / going.length : 0;
    return {
      packed,
      total: going.length,
      share,
      ring: htmlSafe(`--p:${Math.round(share * 100)}`),
    };
  }
  // the stamp's picture follows the weather: snow on the hills, a big sun, or plain hills
  get stampArt() {
    const ds = this.days;
    if (ds.some((d) => sky(d.code, d.snow) === 'Snow')) return 'snow';
    if (ds.length && Math.max(...ds.map((d) => d.hi)) >= 26) return 'sun';
    return 'hills';
  }
  get stampWhat() {
    return this.pal?.colors[2]?.what ?? '';
  }
  get metaLine() {
    const m = this.args.model;
    return [
      m.place ? `${m.home || 'Home'} → ${this.stampName}` : '',
      this.weatherLine,
    ]
      .filter(Boolean)
      .join(' · ');
  }
  get swatches() {
    return (this.pal?.colors ?? []).map((x) => ({
      what: x.what,
      style: htmlSafe(`background:${x.hex}`),
    }));
  }
  get palCaption() {
    return this.pal?.name ?? '';
  }
  get thingDots() {
    return this.thingTints.map((t) =>
      htmlSafe(`background:${ok(0.68, Math.min(t.c, 0.17), t.h)}`),
    );
  }
  get stampName() {
    return (this.args.model.place ?? '').split(',')[0].trim() || 'Anywhere';
  }
  get postmark() {
    const a = this.args.model.startDate;
    if (!a) return null;
    const d = new Date(`${a}T00:00:00Z`);
    return {
      day: d
        .toLocaleDateString('en-GB', {
          day: 'numeric',
          month: 'short',
          timeZone: 'UTC',
        })
        .toUpperCase(),
      year: a.slice(0, 4),
    };
  }
  get weatherLine() {
    const ds = this.days;
    if (!ds.length) return '';
    const lo = Math.round(Math.min(...ds.map((d) => d.lo)));
    const hi = Math.round(Math.max(...ds.map((d) => d.hi)));
    const snow = ds.filter((d) => sky(d.code, d.snow) === 'Snow').length;
    const rain = ds.filter((d) => sky(d.code, d.snow) === 'Rain').length;
    return [
      `${lo}° to ${hi}°`,
      snow ? `snow ${snow} day${snow > 1 ? 's' : ''}` : '',
      rain ? `rain ${rain} day${rain > 1 ? 's' : ''}` : '',
    ]
      .filter(Boolean)
      .join(' · ');
  }
  // the photos of what's going, as one key: the colours are worked out again when it changes
  get photoKey() {
    return this.things
      .filter((x) => x.status !== 'skip')
      .map((x) => this.view(x).photo)
      .filter(Boolean)
      .join('|');
  }
  look = modifier((_el: Element, [key]: [string]) => {
    registerLookProps();
    this.tintFromPhotos(key);
    this.ensurePalette();
  });
  private async tintFromPhotos(key: string) {
    const urls = key ? key.split('|').slice(0, 40) : [];
    const tints = (await Promise.all(urls.map(photoTint))).filter(
      Boolean,
    ) as Tint[];
    // the two hues most of the things share, the vivid ones counting most
    const bins = new Map<
      number,
      { w: number; x: number; y: number; c: number }
    >();
    for (const t of tints) {
      const k = Math.floor(t.h / 40);
      const b = bins.get(k) ?? { w: 0, x: 0, y: 0, c: 0 };
      const w = t.c;
      b.w += w;
      b.x += w * Math.cos((t.h * Math.PI) / 180);
      b.y += w * Math.sin((t.h * Math.PI) / 180);
      b.c += w * t.c;
      bins.set(k, b);
    }
    const top = [...bins.values()].sort((a, b) => b.w - a.w).slice(0, 3);
    const next = top.map((b) => ({
      c: b.c / b.w,
      h: ((Math.atan2(b.y, b.x) * 180) / Math.PI + 360) % 360,
    }));
    if (
      next.map((t) => Math.round(t.h)).join() !==
      this.thingTints.map((t) => Math.round(t.h)).join()
    )
      this.thingTints = next;
  }
  private async ensurePalette() {
    const m = this.args.model;
    if (this.paletteAsked || !m.place || m.palette || !this.ctx) return;
    this.paletteAsked = true;
    await Promise.resolve();
    try {
      const p = await palette(this.ctx, m.place, m.startDate ?? '');
      if (p && !m.palette) m.palette = JSON.stringify(p);
    } catch {
      /* the colours guessed from the name stay */
    }
  }

  // ─── what the page shows ───────────────────────────────────────────────
  get groups() {
    const order: Record<string, number> = {
      needed: 0,
      have: 1,
      leave: 1,
      packed: 3,
      skip: 4,
    };
    const opts = this.statusOptions;
    return CATEGORIES.map((key) => {
      const its = this.things
        .filter(
          (x) =>
            asCategory(this.view(x).category) === key && x.status !== 'skip',
        )
        .sort(
          (a, b) =>
            (order[a.status] ?? 5) - (order[b.status] ?? 5) ||
            String(this.view(a).name).localeCompare(String(this.view(b).name)),
        );
      const going = its.filter((x) => x.status !== 'skip');
      return {
        key,
        name: CATEGORY_NAMES[key],
        icon: CAT_LOOK[key].icon,
        hue: htmlSafe(`--h:${CAT_LOOK[key].hue}`),
        rows: its.map((x) => {
          const v = this.view(x);
          return {
            card: x,
            id: x.id,
            name: cap(v.name),
            photo: v.photo,
            // where to look for it, while it's still to find
            lives:
              x.status === 'needed' && v.t?.storedAt
                ? `Lives: ${v.t.storedAt}`
                : '',
            status: this.shown(x),
            statusName: STATUS_NAMES[this.shown(x)] ?? x.status,
            value:
              x.status === 'packed' && this.bags.length
                ? `bag:${this.bagOf(x)}`
                : this.shown(x),
            opts,
            suggest: this.leaveSuggestion(x),
            fresh: Boolean(this.fresh[x.id]),
            count:
              x.need && x.need > 1
                ? `×${x.need}`
                : x.qty && x.qty > 1
                  ? `×${x.qty}`
                  : '',
            short:
              x.need && x.qty && x.need > x.qty && x.status !== 'needed'
                ? `seen ${x.qty} of ${x.need}`
                : '',
            why: x.status === 'leave' ? null : x.why,
          };
        }),
        packed: going.filter((x) => x.status === 'packed').length,
        total: going.length,
        missing: its.filter((x) => x.status === 'needed').length,
      };
    }).filter((g) => g.rows.length);
  }
  // ─── what just arrived from elsewhere (their phone) ───────────────────────
  // the computer doesn't scan, so a line that changes under it came from the
  // phone: it glows, and the side panel says what it was
  @tracked fresh: Record<string, number> = {};
  @tracked arrivals: {
    id: string;
    kind: string;
    label: string;
    name: string;
  }[] = [];
  private lastWrite = 0;
  private seen: Map<string, string> | null = null;
  get itemsSig() {
    return this.items.map((x) => `${x.id}=${x.status ?? ''}`).join('|');
  }
  watchItems = modifier((_el: Element, [_sig]: [string]) => {
    Promise.resolve().then(() => this.noteChanges());
  });
  private noteChanges() {
    const now = new Map<string, string>(
      this.items.map((x) => [x.id, x.status ?? '']),
    );
    const prev = this.seen;
    this.seen = now;
    if (!prev || (!prev.size && now.size)) return; // the first load is the starting point
    // their own clicks here, or this device's camera, aren't news
    if (this.camOn || Date.now() - this.lastWrite < 8000) return;
    const LABEL: Record<string, string> = {
      have: 'Found',
      packed: 'Packed',
      skip: 'Off the list',
      leave: 'Leave home',
      needed: 'Need',
    };
    const news: { id: string; kind: string; label: string; name: string }[] =
      [];
    for (const [id, st] of now) {
      const was = prev.get(id);
      if (was === st) continue;
      const it = this.items.find((x) => x.id === id);
      const name = cap(this.view(it).name);
      news.push(
        was === undefined
          ? { id, kind: 'new', label: 'New', name }
          : { id, kind: st, label: LABEL[st] ?? st, name },
      );
    }
    // a whole list arriving at once is the page catching up, not the phone
    if (!news.length || news.length > 8) return;
    const at = Date.now();
    this.fresh = {
      ...this.fresh,
      ...Object.fromEntries(
        news.filter((n) => n.kind !== 'skip').map((n) => [n.id, at]),
      ),
    };
    this.arrivals = [
      ...news.reverse(),
      ...this.arrivals.filter((a) => !news.some((n) => n.id === a.id)),
    ].slice(0, 4);
    this.timers.push(
      setTimeout(
        () =>
          (this.fresh = Object.fromEntries(
            Object.entries(this.fresh).filter(([, t]) => t !== at),
          )),
        6000,
      ),
      setTimeout(() => {
        if (
          this.arrivals.length &&
          news.some((n) => this.arrivals[0]?.id === n.id)
        )
          this.arrivals = [];
      }, 20000),
    );
  }
  goTo = (id: string) => {
    const row = document.querySelector(
      `.ln[data-id="${CSS.escape(id)}"]`,
    ) as HTMLElement | null;
    // scroll only the card's own scroller, not the page around it
    let box = row?.parentElement ?? null;
    while (
      box &&
      !(
        box.scrollHeight > box.clientHeight &&
        /auto|scroll/.test(getComputedStyle(box).overflowY)
      )
    )
      box = box.parentElement;
    if (row && box) {
      const r = row.getBoundingClientRect();
      const b = box.getBoundingClientRect();
      box.scrollBy({
        top: r.top - b.top - (b.height - r.height) / 2,
        behavior: 'smooth',
      });
    }
    const at = Date.now();
    this.fresh = { ...this.fresh, [id]: at };
    this.timers.push(
      setTimeout(
        () =>
          (this.fresh = Object.fromEntries(
            Object.entries(this.fresh).filter(([, t]) => t !== at),
          )),
        3000,
      ),
    );
  };
  // "leave home" is the AI's suggestion, never its decision: the line keeps
  // its status (older trips stored it as a status of its own, shown as before)
  shown(x: any): string {
    return x.status === 'leave'
      ? x.inherited
        ? 'needed'
        : 'have'
      : (x.status ?? 'have');
  }
  leaveSuggestion(x: any): string {
    if (x.kept || x.status === 'packed' || x.status === 'skip') return '';
    if (x.status === 'leave') return x.why || 'the list suggests it';
    return x.leaveWhy ?? '';
  }
  keepIt = (row: any) =>
    this.patchItem(row.id, {
      kept: true,
      leaveWhy: null,
      ...(row.card.status === 'leave' ? { status: row.status, why: null } : {}),
    });
  leaveIt = (row: any) =>
    this.patchItem(row.id, {
      status: 'skip',
      leaveWhy: null,
      why: `Left home: ${row.suggest}`,
    });
  // what they took off the list: kept (so a later scan doesn't add it back)
  // until they delete it for good
  get skipped() {
    return this.items
      .filter((x) => x.status === 'skip')
      .map((x) => ({ x, v: this.view(x) }))
      .sort((a, b) => String(a.v.name).localeCompare(String(b.v.name)))
      .map(({ x, v }) => ({
        card: x,
        id: x.id,
        name: cap(v.name),
        photo: v.photo,
        why: x.why,
        cat: CATEGORY_NAMES[asCategory(v.category)],
      }));
  }
  toggleSkipped = () => (this.showSkipped = !this.showSkipped);
  drop = (id: string) => {
    this.patchItem(id, { status: 'skip', why: 'Taken off the list' });
    this.feed = this.feed.map((f) =>
      f.item === id ? { ...f, gone: true } : f,
    );
  };
  bringBack = (id: string) => this.patchItem(id, { status: 'have', why: '' });
  forget = async (id: string) => {
    this.deleted = [...this.deleted, id];
    try {
      await (this.args.context as any)?.store?.delete(id);
    } catch (e: any) {
      this.deleted = this.deleted.filter((x) => x !== id);
      this.error = `Couldn't delete it (${e?.message ?? e}).`;
    }
  };
  get stillNeeded() {
    return this.things
      .filter((x) => x.status === 'needed')
      .map((x) => cap(this.view(x).name));
  }
  get toFind() {
    const all = this.stillNeeded;
    return {
      n: all.length,
      first: all.slice(0, 3),
      more: Math.max(0, all.length - 3),
      rest: all.slice(3).join(', '),
    };
  }
  // ─── bags: each one photographed in "The bag" mode gets a tab ──────────
  @tracked bagTab = ''; // the bag shown, and the one Packing mode fills
  @tracked dropping = false;
  private dragId = '';
  private newBags: { id: string; type: string; litres: number }[] = [];
  get bags(): {
    id: string;
    seen: BagSeen & { allowanceKg?: number | null };
    name: string;
    allowance: number;
  }[] {
    const seen = this.snaps
      .filter((x) => x.mode === 'bag' && x.status === 'done')
      .reverse();
    return seen.map((s, i) => {
      const b = parse<(BagSeen & { allowanceKg?: number | null }) | null>(
        s.found,
        null,
      ) ?? { type: 'bag', litres: 0, kg: 0, carryOn: false, note: '' };
      // the first bag takes the trip's allowance until it has its own
      const allowance =
        Number(b.allowanceKg) ||
        (i === 0 ? Number(this.args.model.allowanceKg) || 0 : 0);
      return { id: s.id as string, seen: b, name: `Bag ${i + 1}`, allowance };
    });
  }
  get activeBag() {
    return this.bags.find((b) => b.id === this.bagTab) ?? this.bags[0] ?? null;
  }
  get bag(): BagSeen | null {
    return this.activeBag?.seen ?? null;
  }
  get bagTabs() {
    const on = this.activeBag?.id;
    return this.bags.map((b) => ({
      id: b.id,
      name: b.name,
      on: b.id === on,
      count: this.items.filter((x) => this.bagOf(x) === b.id).length,
    }));
  }
  get bagTitle() {
    return this.bags.length > 1 ? 'The bags' : 'The bag';
  }
  // the bag a packed line is in: its own, or the first one for lines packed before there were tabs
  bagOf(x: any): string {
    if (x.status !== 'packed') return '';
    const ids = this.bags.map((b) => b.id);
    return ids.includes(x.bag) ? x.bag : (ids[0] ?? '');
  }
  pickBag = (id: string) => (this.bagTab = id);
  pickBagSelect = (e: Event) =>
    (this.bagTab = (e.target as HTMLSelectElement).value);
  get intoBags() {
    return this.mode === 'packing' && this.bags.length > 1 ? this.bagTabs : [];
  }
  setAllowance = (e: Event) => {
    const kg = Number((e.target as HTMLInputElement).value);
    const val = Number.isFinite(kg) && kg > 0 ? kg : null;
    const b = this.activeBag;
    if (b)
      this.patchItem(
        b.id,
        { found: JSON.stringify({ ...b.seen, allowanceKg: val }) },
        Snap,
      );
    else this.args.model.allowanceKg = val ?? undefined;
  };
  // not a bag of theirs after all: the tab goes, and what was in it is back to "Have it"
  removeBag = async (id?: string) => {
    const b =
      (typeof id === 'string' && this.bags.find((x) => x.id === id)) ||
      this.activeBag;
    if (!b) return;
    const inIt = this.items.filter((x) => this.bagOf(x) === b.id);
    await this.patchItem(b.id, { status: 'removed' }, Snap);
    for (const x of inIt)
      await this.patchItem(x.id, { status: 'have', bag: null });
    this.bagTab = '';
  };
  // drag a line from the list onto the bag panel (or a bag's tab) to pack it
  dragRow = (id: string, ev: Event) => {
    const e = ev as DragEvent;
    this.dragId = id;
    e.dataTransfer?.setData('text/plain', id);
    if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
  };
  dragEnd = () => {
    this.dragId = '';
    this.dropping = false;
  };
  dragOver = (ev: Event) => {
    const e = ev as DragEvent;
    if (!this.dragId) return;
    e.preventDefault();
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
    if (!this.dropping) this.dropping = true;
  };
  dragLeave = (ev: Event) => {
    const e = ev as DragEvent;
    const el = e.currentTarget as HTMLElement;
    if (!el.contains(e.relatedTarget as Node | null)) this.dropping = false;
  };
  dropOn = (bagId: string, ev: Event) => {
    const e = ev as DragEvent;
    e.preventDefault();
    e.stopPropagation();
    const id = this.dragId || e.dataTransfer?.getData('text/plain') || '';
    this.dragId = '';
    this.dropping = false;
    if (!id) return;
    const b =
      (bagId && this.bags.find((x) => x.id === bagId)) || this.activeBag;
    if (b) this.bagTab = b.id;
    this.patchItem(id, { status: 'packed', bag: b?.id ?? null });
  };
  get gauge() {
    const b = this.activeBag;
    const bag = b?.seen ?? null;
    const vol = (xs: any[]) =>
      xs.reduce(
        (t, x) =>
          t +
          (Number(this.view(x).litres) || 0) *
            Math.max(1, Number(x.need) || Number(x.qty) || 1),
        0,
      );
    const wt = (xs: any[]) =>
      xs.reduce(
        (t, x) =>
          t +
          (Number(this.view(x).kg) || 0) *
            Math.max(1, Number(x.need) || Number(x.qty) || 1),
        0,
      );
    // this bag's contents, then the rest of the list (not in any bag yet) as if it went in too
    const packed = this.items.filter(
      (x) => x.status === 'packed' && (!b || this.bagOf(x) === b.id),
    );
    // (with several bags nobody knows where the rest will go, so each bag shows only what's in it)
    const rest =
      this.bags.length > 1
        ? []
        : this.items.filter(
            (x) =>
              x.status === 'have' ||
              x.status === 'needed' ||
              x.status === 'leave',
          );
    const cap = bag?.litres || 0;
    const allowance = b
      ? b.allowance
      : Number(this.args.model.allowanceKg) || 0;
    const pct = (n: number, d: number) =>
      d ? Math.min(100, Math.round((n / d) * 100)) : 0;
    const packedL = vol(packed);
    const goingL = packedL + vol(rest);
    const kg = wt(packed) + wt(rest) + (bag?.kg || 0);
    const shape = bagShape(bag?.type ?? '');
    // the duffel fills from its rounded edge inwards: the band's depth that covers that share of the body
    const band = (n: number) => {
      const f = cap ? Math.min(1, n / cap) : 0;
      const [w, h] = [294, 76];
      return htmlSafe(
        `stroke-width:${((w + h - Math.sqrt((w + h) ** 2 - 4 * f * w * h)) / 2).toFixed(1)}px`,
      );
    };
    const dial = (n: number) =>
      (allowance ? Math.min(100, (n / (allowance * 1.25)) * 100) : 0).toFixed(
        1,
      );
    return {
      bag,
      name: b?.name ?? '',
      shape,
      bandPacked: band(packedL),
      bandGoing: band(goingL),
      several: this.bags.length > 1,
      cap,
      packedL: round1(packedL),
      goingL: round1(goingL),
      kg: round1(kg),
      packedKg: round1(wt(packed) + (bag?.kg || 0)),
      allowance,
      over: cap > 0 && goingL > cap,
      heavy: allowance > 0 && kg > allowance,
      packedStyle: htmlSafe(`width:${pct(packedL, cap)}%`),
      packedK: htmlSafe(`--k:${(pct(packedL, cap) / 100).toFixed(3)}`),
      goingK: htmlSafe(`--k:${(pct(goingL, cap) / 100).toFixed(3)}`),
      // the weight dial runs to a quarter past the allowance: the last fifth is over
      dialPacked: htmlSafe(
        `stroke-dasharray:${dial(wt(packed) + (bag?.kg || 0))} 100`,
      ),
      dialGoing: htmlSafe(`stroke-dasharray:${dial(kg)} 100`),
      needle: htmlSafe(
        `transform:rotate(${(-90 + 1.8 * Number(dial(kg))).toFixed(1)}deg)`,
      ),
      goingStyle: htmlSafe(`width:${pct(goingL, cap)}%`),
    };
  }
  get days(): DayWeather[] {
    return parse<DayWeather[]>(this.args.model.weather, []);
  }
  get weatherRows() {
    const byPlace = new Map<string, DayWeather[]>();
    for (const d of this.days)
      byPlace.set(d.place, [...(byPlace.get(d.place) ?? []), d]);
    return [...byPlace.entries()].map(([place, ds]) => ({
      place,
      days: ds.map((d) => ({
        ...d,
        sky: sky(d.code, d.snow),
        icon: SKY_ICON[sky(d.code, d.snow)] ?? CloudIcon,
        hiR: Math.round(d.hi),
        loR: Math.round(d.lo),
        // only a day that stays below freezing is marked, so the mark means something
        cold: (d.hi + d.lo) / 2 < 0,
      })),
    }));
  }
  // the dates once, above every stop's row
  get weatherDates() {
    const first = this.weatherRows[0];
    return (first?.days ?? []).map((d) => ({
      dow: new Date(`${d.date}T00:00:00Z`).toLocaleDateString('en-GB', {
        weekday: 'short',
        timeZone: 'UTC',
      }),
      dm: Number(d.date.slice(8, 10)),
    }));
  }
  get typical() {
    return this.days.some((d) => d.typical);
  }
  get notes(): Note[] {
    return parse<Note[]>(this.args.model.notes, []);
  }
  get notesTop() {
    return this.notes.slice(0, 2);
  }
  get notesMore() {
    return this.notes.slice(2);
  }
  get daysToGo() {
    const s = Date.parse(`${this.args.model.startDate ?? ''}T00:00:00`);
    if (!Number.isFinite(s)) return '';
    const n = Math.ceil((s - Date.now()) / 86400000);
    return n > 1
      ? `${n} days to go`
      : n === 1
        ? 'Tomorrow'
        : n === 0
          ? 'Today'
          : 'Under way';
  }
  get dates() {
    const a = this.args.model.startDate;
    const b = this.args.model.endDate;
    if (!a) return 'Dates not set';
    const f = (s: string) =>
      new Date(`${s}T00:00:00Z`).toLocaleDateString('en-GB', {
        day: 'numeric',
        month: 'short',
        timeZone: 'UTC',
      });
    return b ? `${f(a)} – ${f(b)}` : f(a);
  }
  get modeHint() {
    return MODES.find((m) => m.key === this.mode)?.hint ?? '';
  }
  get modes() {
    return MODES.map((m) => ({ ...m, on: m.key === this.mode }));
  }
  get secs() {
    return `${(this.lastMs / 1000).toFixed(1)} s`;
  }
  get recentSnaps() {
    return this.snaps.slice(0, 6);
  }

  // ─── where and when, asked on the card itself ──────────────────────────
  // a new trip opens on the questions; Change brings them back. The pencil's
  // edit view stays for fixing things, not for setting a trip up
  @tracked editing = false;
  get setupOpen() {
    const m = this.args.model;
    return this.editing || !m.place || !m.startDate || !m.endDate;
  }
  get stopsText() {
    return lines(this.args.model.stops).join(', ');
  }
  openSetup = () => {
    this.error = '';
    this.editing = true;
  };
  clearError = () => {
    if (this.error) this.error = '';
  };
  closeSetup = () => {
    this.error = '';
    this.editing = false;
  };
  saveSetup = async (e: Event) => {
    e.preventDefault();
    const form = e.target as HTMLFormElement;
    const go =
      ((e as SubmitEvent).submitter as HTMLButtonElement | null)?.value !==
      'save';
    const f = new FormData(form);
    const val = (k: string) => String(f.get(k) ?? '').trim();
    const [place, start, end] = [
      val('place'),
      val('startDate'),
      val('endDate'),
    ];
    if (!place || !start || !end) {
      this.error =
        'Where, and both dates, so the weather and the list fit the trip.';
      return;
    }
    if (end < start) {
      this.error = 'The day back is before the day you leave.';
      return;
    }
    const m = this.args.model;
    const moved =
      place !== m.place || start !== m.startDate || end !== m.endDate;
    if (place !== m.place) m.palette = undefined; // new place, new colours
    m.place = place;
    m.startDate = start;
    m.endDate = end;
    m.home = val('home') || undefined;
    m.stops =
      val('stops')
        .split(/[,\n]+/)
        .map((x) => x.trim())
        .filter(Boolean)
        .join('\n') || undefined;
    m.plans = val('plans') || undefined;
    const kg = Number(val('allowanceKg'));
    m.allowanceKg = Number.isFinite(kg) && kg > 0 ? kg : undefined;
    this.error = '';
    this.editing = false;
    if (go) await this.researchPlace();
    else if (moved && m.researchedAt)
      this.error =
        'Saved. Research again to bring the weather and list up to date.';
  };

  // ─── research and the plan (usually on the computer) ───────────────────
  researchPlace = async () => {
    const m = this.args.model;
    if (!m.place || !m.startDate || !m.endDate) {
      this.editing = true;
      return;
    }
    this.error = '';
    try {
      this.busy = 'Checking the weather…';
      const stops = lines(m.stops);
      const days: DayWeather[] = [];
      for (const st of stops.length ? stops : [m.place])
        days.push(...(await weather(st, m.startDate, m.endDate)));
      m.weather = JSON.stringify(days);
      this.busy = 'Researching the place (web search)…';
      // the colours of the place in that month, while the research runs
      palette(this.ctx, m.place, m.startDate)
        .then((p) => p && (m.palette = JSON.stringify(p)))
        .catch(() => undefined);
      const notes = await research(this.ctx, {
        place: m.place,
        stops: stops.join(', '),
        start: m.startDate,
        end: m.endDate,
        home: m.home ?? '',
        plans: m.plans ?? '',
      });
      m.notes = JSON.stringify(notes);
      m.researchedAt = new Date().toISOString();
      await this.planList();
    } catch (e: any) {
      this.error = `${e?.message ?? e}`;
    }
    this.busy = '';
  };

  planList = async () => {
    this.error = '';
    this.busy = 'Writing the list…';
    try {
      const p = await plan(
        this.ctx,
        this.args.model,
        this.days,
        this.notes,
        this.known,
        this.bag,
      );
      const matched = new Set<string>();
      for (const n of p.needs) {
        const { it, th } = this.resolveMatch(n.match);
        if (it) {
          matched.add(it.id);
          await this.patchItem(it.id, {
            need: n.qty,
            why: n.why,
            category: n.category,
            ...(it.status === 'leave' || it.status === 'skip'
              ? { status: 'have' }
              : {}),
          });
        } else if (th) {
          // something they own from an earlier trip: on the list, to find
          await this.addItem(
            {
              name: th.name,
              category: th.category,
              status: 'needed',
              need: n.qty,
              why: n.why,
            },
            th.id,
          );
        } else {
          await this.addItem({
            name: n.name,
            category: n.category,
            status: 'needed',
            need: n.qty,
            why: n.why,
            litres: n.litres || null,
            kg: n.kg || null,
          });
        }
      }
      // an old "needed" line the new plan didn't keep is dropped
      for (const it of this.things)
        if (
          it.status === 'needed' &&
          !it.fromList &&
          !it.inherited &&
          !matched.has(it.id) &&
          !p.needs.some((n) => n.name === it.name)
        )
          await this.patchItem(it.id, {
            status: 'skip',
            why: 'Dropped when the list was redone',
          });
      // last time's suggestions the new plan doesn't repeat are dropped
      for (const it of this.things)
        if (it.leaveWhy && !p.extras.some((x) => x.id === it.id))
          await this.patchItem(it.id, { leaveWhy: null });
      for (const x of p.extras) {
        const it = this.items.find((y) => y.id === x.id);
        if (
          it &&
          !it.kept &&
          (it.status === 'have' || (it.status === 'needed' && it.inherited))
        )
          await this.patchItem(x.id, { leaveWhy: x.why });
      }
      if (p.dossier) this.args.model.dossier = p.dossier;
    } catch (e: any) {
      this.error = `${e?.message ?? e}`;
    }
    this.busy = '';
  };

  // ─── cards and files ───────────────────────────────────────────────────
  private async saveFile(path: string, blob: Blob) {
    const written = await new WriteBinaryFileCommand(this.ctx).execute({
      realm: this.realm,
      path,
      base64Content: await blobToBase64(blob),
      contentType: 'image/jpeg',
      useNonConflictingFilename: true,
    } as any);
    const url = (written as any)?.fileIdentifier;
    if (!url) throw new Error('the photo was not saved');
    return url as string;
  }
  private async addCard(
    name: 'PackItem' | 'Snap' | 'Thing',
    attributes: Record<string, any>,
    links: Record<string, string> = { trip: this.tripId },
  ) {
    this.lastWrite = Date.now();
    const store = (this.args.context as any)?.store;
    if (!store?.add)
      throw new Error('open the trip from its workspace to save things');
    const relationships = Object.fromEntries(
      Object.entries(links).map(([k, v]) => [k, { links: { self: v } }]),
    );
    const card = await store.add(
      {
        data: {
          type: 'card',
          attributes,
          relationships,
          meta: { adoptsFrom: { module: ITEMS, name } },
        },
      },
      { realm: this.realm },
    );
    if (!card?.id) throw new Error(card?.message ?? 'not saved');
    return card;
  }
  private addItem(attributes: Record<string, any>, thingId?: string | null) {
    return this.addCard(
      'PackItem',
      attributes,
      thingId ? { trip: this.tripId, thing: thingId } : { trip: this.tripId },
    );
  }
  private async patchItem(
    id: string,
    attributes: Record<string, any>,
    cardType: any = PackItem,
  ) {
    this.lastWrite = Date.now();
    try {
      await new PatchCardInstanceCommand(this.ctx, { cardType }).execute({
        cardId: id,
        patch: { attributes },
      } as any);
    } catch {
      // fall back to editing the live copy, which saves itself
      const it = [...this.items, ...this.snaps, ...this.ownThings].find(
        (x) => x.id === id,
      );
      if (it) for (const [k, v] of Object.entries(attributes)) it[k] = v;
    }
  }
  private patchThing(id: string, attributes: Record<string, any>) {
    return this.patchItem(id, attributes, Thing);
  }

  // ─── things they own ───────────────────────────────────────────────────
  // a new thing, with its first photo (a cutout, or one they added)
  private async addThing(
    attrs: Record<string, any>,
    look: { url: string; snap?: string; box?: string } | null,
    aiNote?: string,
  ) {
    const at = new Date().toISOString();
    const photos: ThingPhoto[] = look
      ? [
          {
            url: look.url,
            role: 'look',
            at,
            trip: this.tripId,
            snap: look.snap,
            box: look.box,
          },
        ]
      : [];
    return this.addCard(
      'Thing',
      {
        ...attrs,
        photo: look?.url ?? null,
        snapPhoto: look?.snap ?? null,
        box: look?.box ?? null,
        photos: JSON.stringify(photos),
        aiNotes: aiNote
          ? JSON.stringify([{ text: aiNote, at, photo: look?.url }])
          : null,
      },
      {},
    );
  }
  // a line that isn't a thing yet becomes one (its photo and size move over)
  private async ensureThing(it: any, name?: string) {
    const have = this.thingOf(it);
    if (have) return have;
    // one they already own by that name (from another trip) is this line, not a copy
    const key = norm(name ?? it.name);
    const cat = it.category ?? 'other';
    const onIt = new Set(
      this.things.map((x) => this.thingOf(x)?.id).filter(Boolean),
    );
    const own = this.ownThings.find(
      (t) =>
        !onIt.has(t.id) &&
        norm(t.name) === key &&
        (t.category ?? 'other') === cat,
    );
    if (own) {
      await this.link(it, own);
      return own;
    }
    const look = it.photo
      ? {
          url: it.photo,
          snap: it.snapPhoto ?? undefined,
          box: it.box ?? undefined,
        }
      : null;
    const t = await this.addThing(
      {
        name: name ?? it.name,
        category: it.category,
        litres: it.litres ?? null,
        kg: it.kg ?? null,
        seenAt: it.seenAt ?? null,
      },
      look,
    );
    await this.link(it, t);
    return t;
  }
  private async link(it: any, t: any) {
    try {
      await new PatchCardInstanceCommand(this.ctx, {
        cardType: PackItem,
      }).execute({
        cardId: it.id,
        patch: { relationships: { thing: { links: { self: t.id } } } },
      } as any);
    } catch {
      it.thing = t;
    }
  }
  // another photo of what it looks like, made the main one
  private async addLook(
    t: any,
    look: { url: string; snap?: string; box?: string },
    aiNote?: string,
  ) {
    const at = new Date().toISOString();
    const attrs: Record<string, any> = {
      photo: look.url,
      snapPhoto: look.snap ?? null,
      box: look.box ?? null,
      photos: JSON.stringify([
        ...photosOf(t),
        {
          url: look.url,
          role: 'look',
          at,
          trip: this.tripId,
          snap: look.snap,
          box: look.box,
        },
      ]),
    };
    if (aiNote)
      attrs.aiNotes = JSON.stringify([
        ...aiNotesOf(t),
        { text: aiNote, at, photo: look.url },
      ]);
    await this.patchThing(t.id, attrs);
  }
  // home again: where it went, in words and in the photo
  private async putAway(
    t: any,
    photo: string,
    box: number[] | null,
    spot: string,
    look: { url: string; snap?: string; box?: string } | null,
  ) {
    const at = new Date().toISOString();
    const b = box ? JSON.stringify(box) : undefined;
    const photos: ThingPhoto[] = [...photosOf(t)];
    const attrs: Record<string, any> = {
      storedAt: spot || t.storedAt || null,
      storedPhoto: photo,
      storedBox: b ?? null,
      storedOn: at,
    };
    if (look && !t.photo) {
      photos.push({
        url: look.url,
        role: 'look',
        at,
        trip: this.tripId,
        snap: look.snap,
        box: look.box,
      });
      Object.assign(attrs, {
        photo: look.url,
        snapPhoto: look.snap ?? null,
        box: look.box ?? null,
      });
    }
    photos.push({
      url: photo,
      role: 'stored',
      at,
      trip: this.tripId,
      box: b,
      note: spot,
    });
    attrs.photos = JSON.stringify(photos);
    await this.patchThing(t.id, attrs);
  }

  // where a line is: still to find, here, or in one of the bags
  get statusOptions() {
    const bags = this.bags.map((b) => ({
      v: `bag:${b.id}`,
      l: this.bags.length > 1 ? `In ${b.name}` : 'Packed',
    }));
    return [
      { v: 'needed', l: 'Need' },
      { v: 'have', l: 'Have it' },
      ...(bags.length ? bags : [{ v: 'packed', l: 'Packed' }]),
    ];
  }
  setStatus = (row: any, e: Event) => {
    const v = (e.target as HTMLSelectElement).value;
    this.patchItem(
      row.id,
      v.startsWith('bag:')
        ? { status: 'packed', bag: v.slice(4) }
        : { status: v, bag: null },
    );
  };
  open = (card: any) => this.args.viewCard?.(card, 'isolated');
  // a thumbnail opens the thing big: its photos, where it lives, notes
  zoomIn = (card: any) => {
    this.zoomFresh = '';
    this.zoomPick = '';
    this.zoom = card;
  };
  zoomOut = () => (this.zoom = null);
  @tracked zoomFresh = ''; // a photo they just swapped in, shown before the card catches up
  @tracked zoomPick = ''; // another of its photos, picked from the strip
  @tracked zoomBusy = false;
  get zoomThing() {
    return this.zoom ? this.thingOf(this.zoom) : null;
  }
  get zoomView() {
    return this.zoom ? this.view(this.zoom) : null;
  }
  get zoomMain() {
    return this.zoomFresh || this.zoomView?.photo || '';
  }
  get zoomPhoto() {
    return this.zoomPick || this.zoomMain;
  }
  get zoomStrip() {
    const ps = photosOf(this.zoomThing);
    return ps.length > 1
      ? ps.map((p) => ({
          url: p.url,
          on: p.url === this.zoomPhoto,
          label: `${p.role === 'stored' ? 'Where it lives' : 'Look'}, ${day(p.at)}`,
        }))
      : [];
  }
  get zoomCanMain() {
    const p = photosOf(this.zoomThing).find((x) => x.url === this.zoomPick);
    return Boolean(p && p.role === 'look' && p.url !== this.zoomMain);
  }
  get zoomAi() {
    return aiNotesOf(this.zoomThing).map((n, i) => ({
      i,
      text: n.text,
      when: day(n.at),
    }));
  }
  get zoomStored() {
    const t = this.zoomThing;
    return t?.storedPhoto
      ? {
          photo: t.storedPhoto,
          box: boxStyle(t.storedBox),
          on: day(t.storedOn),
        }
      : null;
  }
  pickPhoto = (url: string) => (this.zoomPick = url);
  makeMain = async () => {
    const t = this.zoomThing;
    const p = photosOf(t).find((x) => x.url === this.zoomPick);
    if (!t || !p) return;
    this.zoomFresh = p.url;
    this.zoomPick = '';
    await this.patchThing(t.id, {
      photo: p.url,
      snapPhoto: p.snap ?? null,
      box: p.box ?? null,
    });
  };
  // their own photo of it: the phone (which can't shoot itself), a closed
  // laptop instead of a half-open one. It becomes the main photo; the old
  // ones stay in the strip.
  replacePhoto = async (e: Event) => {
    const input = e.target as HTMLInputElement;
    const f = input.files?.[0];
    input.value = '';
    const it = this.zoom;
    if (!f || !it) return;
    this.zoomBusy = true;
    try {
      const name = this.view(it).name;
      const { blob } = await shrink(f, 1200, 0.85);
      const url = await this.saveFile(`Items/${slug(name)}.jpg`, blob);
      this.zoomFresh = url;
      this.zoomPick = '';
      let note = '';
      try {
        note = await describe(
          this.ctx,
          `data:image/jpeg;base64,${await blobToBase64(blob)}`,
          name,
        );
      } catch {
        note = ''; // the photo matters; the note is a bonus
      }
      const t = this.thingOf(it);
      if (t) await this.addLook(t, { url }, note);
      else {
        const nt = await this.addThing(
          {
            name,
            category: it.category,
            litres: it.litres ?? null,
            kg: it.kg ?? null,
          },
          { url },
          note,
        );
        await this.link(it, nt);
      }
      if (it.status === 'needed')
        await this.patchItem(it.id, { status: 'have' });
    } catch (err: any) {
      this.say(`Couldn't save that photo: ${err?.message ?? err}`, 'err');
    } finally {
      this.zoomBusy = false;
    }
  };
  // what they say goes: where it lives, and their own notes
  private async editThing(field: string, value: string) {
    const it = this.zoom;
    if (!it) return;
    const t =
      this.thingOf(it) ?? (await this.ensureThing(it, this.view(it).name));
    await this.patchThing(t.id, { [field]: value.trim() || null });
  }
  setStoredAt = (e: Event) =>
    this.editThing('storedAt', (e.target as HTMLInputElement).value);
  setMyNotes = (e: Event) =>
    this.editThing('myNotes', (e.target as HTMLTextAreaElement).value);
  dropAiNote = (i: number) => {
    const t = this.zoomThing;
    if (!t) return;
    const ns = aiNotesOf(t);
    ns.splice(i, 1);
    this.patchThing(t.id, { aiNotes: JSON.stringify(ns) });
  };
  zoomCard = () => {
    const c = this.zoomThing ?? this.zoom;
    this.zoom = null;
    if (c) this.open(c);
  };
  get zoomBox() {
    return this.zoomPick
      ? boxStyle(
          photosOf(this.zoomThing).find((p) => p.url === this.zoomPick)?.box,
        )
      : this.zoomFresh
        ? null
        : boxStyle(this.zoomView?.box);
  }
  get zoomHue() {
    return htmlSafe(`--h:${CAT_LOOK[asCategory(this.zoomView?.category)].hue}`);
  }
  get zoomName() {
    return cap(this.zoomView?.name ?? '');
  }
  // the camera's shot, unless it's the same photo already shown as where it lives
  get zoomSnapShown() {
    const s = this.zoomSnap;
    return s && s !== this.zoomStored?.photo ? s : '';
  }
  get zoomSnap() {
    if (this.zoomPick)
      return (
        photosOf(this.zoomThing).find((p) => p.url === this.zoomPick)?.snap ??
        ''
      );
    return this.zoomFresh ? '' : (this.zoomView?.snapPhoto ?? '');
  }
  // a native dialog, opened modal; Escape or the backdrop calls `onClose`
  // (Escape is handled here too: the host keeps it from reaching a dialog
  // while a text box has focus)
  modal = modifier((el: Element, [onClose]: [() => void]) => {
    const d = el as HTMLDialogElement;
    if (!d.open) d.showModal();
    // the key stops here: let through, the host takes Escape as "close the card"
    const key = (e: Event) => {
      if ((e as KeyboardEvent).key !== 'Escape') return;
      e.preventDefault();
      e.stopPropagation();
      onClose();
    };
    d.addEventListener('close', onClose);
    d.addEventListener('keydown', key);
    return () => {
      d.removeEventListener('close', onClose);
      d.removeEventListener('keydown', key);
    };
  });

  // ─── starting the list from something they already have ─────────────
  @tracked startOpen = false;
  openStart = () => (this.startOpen = true);
  closeStart = () => (this.startOpen = false);
  get pastTrips() {
    return ((this.tripsQ?.instances ?? []) as any[])
      .filter((t) => t?.id && t.id !== this.tripId)
      .map((t) => ({
        card: t,
        place: t.place || 'A trip',
        dates: t.startDate
          ? `${t.startDate}${t.endDate ? ` → ${t.endDate}` : ''}`
          : 'no dates',
      }))
      .sort((a, b) =>
        String(b.card.startDate ?? '').localeCompare(
          String(a.card.startDate ?? ''),
        ),
      );
  }
  // everything they took last time, back to "Need"; what doesn't suit this
  // trip is suggested to stay home rather than silently left off
  inherit = async (src: any) => {
    this.startOpen = false;
    this.error = '';
    const from = src.place ? `${src.place} trip` : 'earlier trip';
    this.busy = `Copying the list from the ${from}…`;
    try {
      // wait for all of that trip's lines, not just the ones already on screen
      this.srcTrip = src.id;
      let last = -1;
      for (let i = 0; i < 40; i++) {
        await new Promise((r) => setTimeout(r, 500));
        const n = (this.srcQ?.instances ?? []).length;
        if (!this.srcQ?.isLoading && n && n === last) break;
        last = n;
      }
      const onIt = new Set(
        this.items
          .map((x) => this.thingOf(x)?.id ?? linkId(x, 'thing'))
          .filter(Boolean),
      );
      const names = new Set(this.items.map((x) => norm(this.view(x).name)));
      const rows = ((this.srcQ?.instances ?? []) as any[]).filter(
        (x) => x?.trip?.id === src.id && x.status !== 'skip',
      );
      const added: KnownItem[] = [];
      for (const x of rows) {
        const v = this.view(x);
        const tid = v.t?.id ?? linkId(x, 'thing');
        if ((tid && onIt.has(tid)) || names.has(norm(v.name))) continue;
        names.add(norm(v.name));
        const card = await this.addItem(
          {
            name: v.name,
            category: v.category,
            kind: x.kind ?? null,
            status: 'needed',
            need: x.need ?? null,
            why: x.kind === 'task' ? (x.why ?? null) : null,
            fromList: x.fromList ?? null,
            inherited: from,
          },
          tid,
        );
        if (x.kind !== 'task')
          added.push({
            id: card.id,
            name: v.name,
            category: v.category ?? 'other',
            status: 'needed',
          });
      }
      let left = 0;
      if (added.length && this.days.length) {
        this.busy = 'Checking what suits this trip…';
        for (const l of await suggestLeave(
          this.ctx,
          this.args.model,
          this.days,
          added,
        )) {
          if (!this.items.find((y) => y.id === l.id)?.kept)
            await this.patchItem(l.id, { leaveWhy: l.why });
          left++;
        }
      }
      this.srcTrip = '';
      this.say(
        `Copied ${added.length} things from the ${from}${left ? `; ${left} marked “Leave home?”` : ''}`,
        'add',
      );
      if (added.length && !this.days.length)
        this.say(
          'Research the place and the list will suggest what to leave home.',
          'hint',
        );
    } catch (e: any) {
      this.error = `Couldn't copy that list: ${e?.message ?? e}`;
    }
    this.busy = '';
  };

  // ─── a checklist they already have (any format) ───────────────────────
  importList = async (e: Event) => {
    const input = e.target as HTMLInputElement;
    const f = input.files?.[0];
    input.value = '';
    this.startOpen = false;
    if (!f) return;
    this.error = '';
    this.busy = `Reading ${f.name}…`;
    try {
      const name = f.name.toLowerCase();
      const src: {
        text?: string;
        images?: string[];
        files?: { name: string; data: string }[];
      } = {};
      if (f.type.startsWith('image/')) {
        const { blob } = await shrink(f, 2000, 0.9);
        src.images = [`data:image/jpeg;base64,${await blobToBase64(blob)}`];
      } else if (f.type === 'application/pdf' || name.endsWith('.pdf')) {
        src.files = [
          {
            name: f.name,
            data: `data:application/pdf;base64,${await blobToBase64(f)}`,
          },
        ];
      } else if (/\.(docx?|xlsx?|pptx?|pages|numbers|key|zip)$/.test(name)) {
        throw new Error(
          `can't open ${f.name} directly. Save it as PDF or text (or take a screenshot) and import that.`,
        );
      } else {
        const raw = await f.text();
        src.text =
          /\.html?$/.test(name) || /^\s*<(!doctype|html)/i.test(raw)
            ? htmlText(raw)
            : raw;
      }
      const { title, lines } = await readChecklist(this.ctx, src, this.known);
      let added = 0;
      for (const ln of lines) {
        const { it, th } = this.resolveMatch(ln.match);
        if (it) {
          await this.patchItem(it.id, {
            fromList: title,
            ...(ln.note ? { why: ln.note } : {}),
          });
          continue;
        }
        await this.addItem(
          {
            name: ln.name,
            category: ln.category,
            kind: ln.kind,
            status: 'needed',
            need: ln.qty > 1 ? ln.qty : null,
            why: ln.note || null,
            fromList: title,
          },
          th?.id,
        );
        added++;
      }
      this.say(
        `Imported ${title}: ${added} new line${added === 1 ? '' : 's'}, ${lines.length - added} already on the list`,
        'add',
      );
    } catch (e: any) {
      this.error = `Couldn't import that checklist: ${e?.message ?? e}`;
    }
    this.busy = '';
  };

  // ─── the camera (usually on the phone) ─────────────────────────────────
  setMode = (m: SnapMode) => (this.mode = m);
  say(text: string, kind = 'add', item?: string) {
    this.feed = [{ id: ++this.feedId, text, kind, item }, ...this.feed].slice(
      0,
      8,
    );
  }

  pick = (e: Event) => {
    const input = e.target as HTMLInputElement;
    for (const f of Array.from(input.files ?? [])) this.enqueue(f);
    input.value = '';
  };
  enqueue(blob: Blob, view: View | null = null) {
    this.queue.push({ blob, mode: this.mode, view });
    this.pending = this.queue.length + (this.running ? 1 : 0);
    this.drain();
  }
  private async drain() {
    if (this.running) return;
    this.running = true;
    while (this.queue.length) {
      const job = this.queue.shift()!;
      this.pending = this.queue.length + 1;
      try {
        await this.read(job.blob, job.mode, job.view);
      } catch (e: any) {
        this.say(`Couldn't read that photo: ${e?.message ?? e}`, 'err');
      }
    }
    this.running = false;
    this.pending = 0;
  }

  // the AI reads first, so the labels show as soon as it answers; the photo
  // and cards are written after. A live frame that only re-sees known things
  // isn't kept, so a long scan doesn't leave hundreds of photos behind.
  private async read(raw: Blob, mode: SnapMode, view: View | null) {
    const { blob } = view ? { blob: raw } : await shrink(raw, 1600);
    const t0 = Date.now();
    const res = await see(
      this.ctx,
      `data:image/jpeg;base64,${await blobToBase64(blob)}`,
      mode,
      this.known,
      { fast: Boolean(view) },
    );
    this.lastMs = Date.now() - t0;
    const takenAt = new Date().toISOString();
    if (res.bag) {
      const photo = await this.saveFile(`Snaps/${stamp()}.jpg`, blob);
      const nb = res.bag;
      // the same bag again (same kind, about the same size) is a new photo of it, not another tab
      // (the camera words it differently each time: "day backpack", "daypack backpack"; and a bag
      // added a moment ago may not be back from the index yet)
      const like = (t: string, l: number) =>
        bagShape(t) === bagShape(nb.type) &&
        Math.abs((l || 0) - nb.litres) <= Math.max(4, nb.litres * 0.25);
      const known = [
        ...this.bags.map((b) => ({
          id: b.id,
          type: b.seen.type,
          litres: b.seen.litres,
          b,
        })),
        ...this.newBags.filter((n) => !this.bags.some((b) => b.id === n.id)),
      ];
      const hit = known.find((k) => like(k.type, k.litres));
      const same = hit
        ? (this.bags.find((b) => b.id === hit.id) ?? {
            id: hit.id,
            name: 'that bag',
            seen: { ...nb, allowanceKg: null },
          })
        : null;
      if (same) {
        await this.patchItem(
          same.id,
          {
            photo,
            found: JSON.stringify({
              ...nb,
              allowanceKg: same.seen.allowanceKg ?? null,
            }),
          },
          Snap,
        );
        this.bagTab = same.id;
        this.say(
          `Same bag again: ${same.name} (${nb.type}), about ${nb.litres} L`,
          'bag',
        );
      } else {
        const card = await this.addCard('Snap', {
          photo,
          mode,
          takenAt,
          status: 'done',
          found: JSON.stringify(nb),
        });
        this.newBags.push({ id: card.id, type: nb.type, litres: nb.litres });
        this.bagTab = card.id;
        this.say(
          `Bag ${this.bags.length + 1}: ${nb.type}, about ${nb.litres} L${nb.carryOn ? ' (cabin size)' : ''}`,
          'bag',
        );
      }
      return;
    }
    const packing = mode === 'packing';
    const away = mode === 'away';
    const plan = res.items.map((s) => {
      const { it, th } = this.resolveMatch(s.match);
      const t = it ? this.thingOf(it) : (th ?? null);
      // new: never seen; off: taken off this trip; found: a need filled;
      // joins: theirs from an earlier trip, not on this list yet
      const kind = away
        ? 'away'
        : it
          ? it.status === 'skip'
            ? 'off'
            : packing
              ? it.status === 'packed'
                ? 'seen'
                : 'packed'
              : it.status === 'needed'
                ? 'found'
                : 'seen'
          : th
            ? 'joins'
            : 'new';
      const name = it ? this.view(it).name : (th?.name ?? s.name);
      const cut =
        kind !== 'off' &&
        Boolean(s.box) &&
        (kind === 'new' || !(t?.photo || it?.photo));
      return { s, it, th, t, kind, name, cut };
    });
    if (view)
      this.showMarks(
        view,
        plan.map(({ s, it, kind, name }) => ({
          box: s.box,
          kind: kind === 'joins' ? 'found' : kind,
          label: `${kind === 'new' ? '+' : kind === 'off' ? '✕' : kind === 'away' ? '⌂' : '✓'} ${it && it.status === 'needed' && !it.fromList ? s.name : name}`,
        })),
      );
    const changed =
      plan.some((x) => x.kind !== 'seen' && x.kind !== 'off') ||
      plan.some((x) => x.cut);
    if (!res.items.length && !view)
      this.say(
        away
          ? "Couldn't make out what's going away. Try with the thing and its spot both in view."
          : 'Nothing to pack in that one. Try closer, or lay things flat.',
        'err',
      );
    if (!changed && view) return;

    const found: string[] = [];
    const photo = await this.saveFile(`Snaps/${stamp()}.jpg`, blob);
    // a live frame's boxes come from the fast model: place the ones we'll keep again, carefully
    const wants = plan.filter((w) => w.cut || (away && w.s.box));
    if (view && wants.length) {
      try {
        const boxes = await placeBoxes(
          this.ctx,
          `data:image/jpeg;base64,${await blobToBase64(blob)}`,
          wants.map((w) => w.s.name),
        );
        wants.forEach((w, i) => {
          if (boxes[i]) w.s.box = boxes[i];
        });
      } catch {
        // keep the fast boxes
      }
    }
    for (const { s, it, th, t, kind, cut } of plan) {
      if (kind === 'off') continue; // taken off the list: stays off
      const c = cut ? await cutout(blob, s.box!) : null;
      const look = c
        ? {
            url: await this.saveFile(`Items/${slug(s.name)}.jpg`, c),
            snap: photo,
            box: JSON.stringify(s.box),
          }
        : null;
      if (c && view && kind === 'new') this.fly(c, view, s.box!, s.category);
      if (away) {
        const thing =
          t ??
          (it
            ? await this.ensureThing(it)
            : await this.addThing(
                {
                  name: s.name,
                  category: s.category,
                  litres: s.litres || null,
                  kg: s.kg || null,
                  seenAt: takenAt,
                },
                null,
                keepNote(s.note),
              ));
        await this.putAway(thing, photo, s.box, res.spot, look);
        found.push(`⌂ ${thing.name ?? s.name}`);
        this.say(
          `Put away: ${thing.name ?? s.name}${res.spot ? ` · ${res.spot}` : ''}`,
          'packed',
        );
        continue;
      }
      if (it) {
        const wasNeeded = it.status === 'needed';
        const nm = wasNeeded && !it.fromList ? s.name : this.view(it).name;
        const attrs: Record<string, any> = {
          seenAt: takenAt,
          qty: Math.max(Number(it.qty) || 0, s.qty),
        };
        if (kind === 'packed')
          Object.assign(attrs, {
            status: 'packed',
            bag: this.activeBag?.id ?? null,
          });
        if (kind === 'found') attrs.status = 'have';
        await this.patchItem(it.id, attrs);
        // the line becomes the real thing: a planned "warm hat" is now their
        // black beanie (a line from their own checklist keeps its wording)
        const thing =
          t ?? (await this.ensureThing(it, wasNeeded ? s.name : undefined));
        if (look && !thing.photo)
          await this.addLook(thing, look, keepNote(s.note));
        const fill: Record<string, any> = {};
        if (!thing.litres && s.litres) fill.litres = s.litres;
        if (!thing.kg && s.kg) fill.kg = s.kg;
        if (Object.keys(fill).length) await this.patchThing(thing.id, fill);
        if (kind !== 'seen') {
          found.push(`✓ ${nm}`);
          this.say(
            `${kind === 'packed' ? 'Packed' : 'Found'}: ${nm}`,
            kind === 'packed' ? 'packed' : 'tick',
          );
        }
      } else if (th) {
        const card = await this.addItem(
          {
            name: th.name,
            category: th.category,
            status: packing ? 'packed' : 'have',
            bag: packing ? (this.activeBag?.id ?? null) : null,
            qty: s.qty,
            seenAt: takenAt,
          },
          th.id,
        );
        if (look && !th.photo) await this.addLook(th, look);
        found.push(`✓ ${th.name} (theirs)`);
        this.say(
          `${packing ? 'Packed' : 'On the list'}: ${th.name} (from an earlier trip)`,
          packing ? 'packed' : 'tick',
          card.id,
        );
      } else {
        const thing = await this.addThing(
          {
            name: s.name,
            category: s.category,
            litres: s.litres || null,
            kg: s.kg || null,
            seenAt: takenAt,
          },
          look,
          keepNote(s.note),
        );
        const card = await this.addItem(
          {
            name: s.name,
            category: s.category,
            status: packing ? 'packed' : 'have',
            bag: packing ? (this.activeBag?.id ?? null) : null,
            qty: s.qty,
            seenAt: takenAt,
          },
          thing.id,
        );
        found.push(
          `+ ${s.name}${s.qty > 1 ? ` ×${s.qty}` : ''} (${s.category})`,
        );
        this.say(
          `New: ${s.name}${s.qty > 1 ? ` ×${s.qty}` : ''} · ${CATEGORY_NAMES[s.category]}`,
          'add',
          card.id,
        );
      }
    }
    await this.addCard('Snap', {
      photo,
      mode,
      takenAt,
      status: 'done',
      found: found.join('\n'),
      notes: away && res.spot ? `Put away in: ${res.spot}` : res.notes,
    });
    if (!view && !away && res.notes && /under|buried|more/i.test(res.notes))
      this.say(res.notes, 'hint');
  }

  // boxes and labels over the viewfinder, where the things were in the frame
  private showMarks(
    view: View,
    list: { box: number[] | null; kind: string; label: string }[],
  ) {
    const fresh = list
      .filter((m) => m.box)
      .map((m) => {
        const at = placeOn(view, m.box!);
        return {
          id: ++this.markId,
          kind: m.kind,
          label: m.label,
          top: at.y < 6,
          style: htmlSafe(at.css),
        };
      });
    this.marks = fresh;
    const ids = new Set(fresh.map((m) => m.id));
    this.timers.push(
      setTimeout(
        () => (this.marks = this.marks.filter((m) => !ids.has(m.id))),
        3500,
      ),
    );
  }

  // a new thing's cutout lifts off the viewfinder into its category's tray
  private fly(cut: Blob, view: View, box: number[], category: string) {
    const vf = this.vfEl;
    const tray = this.trayEl;
    if (!vf || !tray) return;
    const chip =
      (tray.querySelector(`[data-cat="${category}"]`) as HTMLElement | null) ??
      tray;
    const r = vf.getBoundingClientRect();
    const p = placeOn(view, box);
    const side = Math.max(
      24,
      Math.min((p.w / 100) * r.width, (p.h / 100) * r.height, 160),
    );
    const fx = r.left + ((p.x + p.w / 2) / 100) * r.width - side / 2;
    const fy = r.top + ((p.y + p.h / 2) / 100) * r.height - side / 2;
    const to = chip.getBoundingClientRect();
    const dx = to.left + to.width / 2 - (fx + side / 2);
    const dy = to.top + to.height / 2 - (fy + side / 2);
    const k = 22 / side;
    const url = URL.createObjectURL(cut);
    const img = document.createElement('img');
    img.src = url;
    img.alt = '';
    Object.assign(img.style, {
      position: 'fixed',
      left: `${fx}px`,
      top: `${fy}px`,
      width: `${side}px`,
      height: `${side}px`,
      objectFit: 'cover',
      borderRadius: '10px',
      zIndex: '9999',
      pointerEvents: 'none',
      boxShadow: '0 8px 24px rgba(0,0,0,.35)',
      border: '2px solid #fff',
    });
    document.body.appendChild(img);
    img
      .animate(
        [
          { transform: 'translate(0, 0) scale(.6)', opacity: 0 },
          {
            transform: 'translate(0, -10px) scale(1.08)',
            opacity: 1,
            offset: 0.25,
          },
          {
            transform: `translate(${dx * 0.55}px, ${dy * 0.55 - 30}px) scale(${(1 + k) / 2})`,
            opacity: 1,
            offset: 0.65,
          },
          {
            transform: `translate(${dx}px, ${dy}px) scale(${k})`,
            opacity: 0.3,
          },
        ],
        { duration: 900, easing: 'cubic-bezier(.3,.7,.2,1)' },
      )
      .finished.catch(() => {})
      .then(() => {
        img.remove();
        URL.revokeObjectURL(url);
        chip.animate(
          [
            { transform: 'scale(1)' },
            { transform: 'scale(1.2)' },
            { transform: 'scale(1)' },
          ],
          { duration: 320, easing: 'ease-out' },
        );
      });
  }
  registerVf = modifier((el: Element) => {
    this.vfEl = el as HTMLElement;
    return () => {
      if (this.vfEl === el) this.vfEl = null;
    };
  });
  registerTray = modifier((el: Element) => {
    this.trayEl = el as HTMLElement;
    return () => {
      if (this.trayEl === el) this.trayEl = null;
    };
  });
  get trays() {
    return CATEGORIES.map((key) => ({
      key,
      name: CATEGORY_NAMES[key],
      n: this.items.filter(
        (x) =>
          asCategory(this.view(x).category) === key &&
          (x.status === 'have' || x.status === 'packed'),
      ).length,
    }));
  }

  startCam = async () => {
    this.error = '';
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 } },
        audio: false,
      });
      this.camOn = true;
      if (!this.auto) this.toggleAuto();
    } catch (e: any) {
      this.error = `The camera didn't start (${e?.message ?? e}). Use "Take photos" instead.`;
    }
  };
  stopCam = () => {
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    this.camOn = false;
    this.auto = false;
    this.stopTicker();
  };
  bindVideo = modifier((element: Element) => {
    const el = element as HTMLVideoElement;
    this.video = el;
    if (this.stream && el.srcObject !== this.stream) {
      el.srcObject = this.stream;
      el.play().catch(() => {});
    }
    return () => {
      if (this.video === el) this.video = null;
    };
  });
  // phones open the back camera straight away for this input
  rearCamera = modifier((el: Element) => {
    el.setAttribute('capture', 'environment');
  });
  shoot = async () => {
    const v = this.video;
    const vf = this.vfEl;
    if (!v || !v.videoWidth) return;
    // scanning frames are small: quicker to send and to read
    const { blob } = await shrink(v, 1024, 0.8);
    this.lastSent = this.sample();
    this.lastShot = Date.now();
    this.enqueue(blob, {
      vw: v.videoWidth,
      vh: v.videoHeight,
      ew: vf?.clientWidth || v.videoWidth,
      eh: vf?.clientHeight || v.videoHeight,
    });
  };
  toggleAuto = () => {
    this.auto = !this.auto;
    if (this.auto) this.ticker = setInterval(this.tick, 500);
    else this.stopTicker();
  };
  private stopTicker() {
    if (this.ticker) clearInterval(this.ticker);
    this.ticker = null;
  }
  // a tiny greyscale thumbnail, to tell "something new, held still" from noise
  private sample(): Uint8ClampedArray | null {
    const v = this.video;
    if (!v || !v.videoWidth) return null;
    const c = document.createElement('canvas');
    c.width = 48;
    c.height = 36;
    const g = c.getContext('2d', { willReadFrequently: true })!;
    g.drawImage(v, 0, 0, 48, 36);
    const d = g.getImageData(0, 0, 48, 36).data;
    const out = new Uint8ClampedArray(48 * 36);
    for (let i = 0; i < out.length; i++)
      out[i] = (d[i * 4] + d[i * 4 + 1] + d[i * 4 + 2]) / 3;
    return out;
  }
  private diff(a: Uint8ClampedArray | null, b: Uint8ClampedArray | null) {
    if (!a || !b) return 255;
    let t = 0;
    for (let i = 0; i < a.length; i++) t += Math.abs(a[i] - b[i]);
    return t / a.length;
  }
  // scanning: read a frame when the picture has changed since the last read
  // and is held still, one read at a time
  tick = () => {
    const now = this.sample();
    const moving = this.diff(now, this.lastSample);
    this.lastSample = now;
    if (this.pending || Date.now() - this.lastShot < 1200) return;
    if (moving < 6 && this.diff(now, this.lastSent) > 12) this.shoot();
  };

  willDestroy() {
    super.willDestroy();
    this.stopCam();
    this.timers.forEach((t) => clearTimeout(t));
  }

  // ─── the phone link ────────────────────────────────────────────────────
  showQr = async () => {
    try {
      const w = window as any;
      if (!w.qrcode) {
        await new Promise((ok, fail) => {
          const s = document.createElement('script');
          s.src = QR_LIB;
          s.onload = ok;
          s.onerror = () => fail(new Error('the QR code maker did not load'));
          document.head.appendChild(s);
        });
      }
      const q = w.qrcode(0, 'M');
      q.addData(this.tripId);
      q.make();
      this.qr = q.createDataURL(5, 2);
    } catch (e: any) {
      this.error = `${e?.message ?? e}`;
    }
  };
  hideQr = () => (this.qr = '');
  toggleDossier = () => (this.showDossier = !this.showDossier);

  <template>
    <div
      class='tw'
      style={{this.lookStyle}}
      {{this.look this.photoKey}}
    ><article class='trip'>
        <header class='head'>
          {{#if this.setupOpen}}
            <form
              class='ttl setup'
              {{on 'submit' this.saveSetup}}
              {{on 'input' this.clearError}}
            >
              <div class='where'>
                <p class='kicker'>{{if
                    @model.place
                    'Change the trip'
                    'A new trip'
                  }}</p>
                <input
                  name='place'
                  class='h1in'
                  type='text'
                  value={{@model.place}}
                  placeholder='Where to?'
                  aria-label='Where to?'
                  autocomplete='off'
                  required
                />
              </div>
              <div class='srow'>
                <label><span>Leaving</span><input
                    name='startDate'
                    type='date'
                    value={{@model.startDate}}
                    required
                  /></label>
                <label><span>Back</span><input
                    name='endDate'
                    type='date'
                    value={{@model.endDate}}
                    required
                  /></label>
                <label><span>Flying from</span><input
                    name='home'
                    type='text'
                    value={{@model.home}}
                    placeholder='e.g. Malaysia'
                  /></label>
                <label><span>Bag allowance</span><span class='unit'><input
                      name='allowanceKg'
                      type='number'
                      min='0'
                      step='1'
                      value={{@model.allowanceKg}}
                      placeholder='20'
                    />kg</span></label>
              </div>
              <label class='wide'><span>Towns you'll stay in
                  <em>optional</em></span><input
                  name='stops'
                  type='text'
                  value={{this.stopsText}}
                  placeholder='e.g. Sapporo, Otaru'
                /></label>
              <label class='wide'><span>What you'll do
                  <em>optional, in your words</em></span><textarea
                  name='plans'
                  rows='2'
                  placeholder='e.g. city walks, a day hike, a friend&apos;s wedding'
                >{{@model.plans}}</textarea></label>
              <div class='sacts'>
                <button
                  type='submit'
                  class='primary'
                  value='research'
                  disabled={{if this.busy true false}}
                >{{if
                    @model.researchedAt
                    'Save and research again'
                    'Research the place'
                  }}</button>
                <button type='submit' class='quiet' value='save'>{{if
                    @model.researchedAt
                    'Just save'
                    'Save, research later'
                  }}</button>
                {{#if @model.place}}<button
                    type='button'
                    class='quiet'
                    {{on 'click' this.closeSetup}}
                  >Cancel</button>{{/if}}
              </div>
              <p class='muted small'>The weather, notes and list come from
                these. You can change them any time.</p>
            </form>
          {{else}}
            <div class='ttl'>
              <p class='kicker'>{{this.dates}}{{#if this.daysToGo}}
                  ·
                  {{this.daysToGo}}{{/if}}
                <button
                  type='button'
                  class='chg'
                  {{on 'click' this.openSetup}}
                >Change</button></p>
              <h1>{{if @model.place @model.place 'Where to?'}}</h1>
              {{#if this.metaLine}}<p class='meta'>{{this.metaLine}}</p>{{/if}}
              {{#if @model.plans}}<p class='plans'>{{@model.plans}}</p>{{/if}}
              {{#if (or this.swatches.length this.thingDots.length)}}
                <p class='pal'>
                  {{#if this.swatches.length}}
                    <span class='pair'><span
                        class='dots'
                        aria-hidden='true'
                      >{{#each this.swatches as |sw|}}<i
                            style={{sw.style}}
                            title={{sw.what}}
                          ></i>{{/each}}</span>{{this.palCaption}}</span>
                  {{/if}}
                  {{#if this.thingDots.length}}
                    <span class='pair'><span
                        class='dots'
                        aria-hidden='true'
                      >{{#each this.thingDots as |dt|}}<i
                            style={{dt}}
                          ></i>{{/each}}</span>{{if
                        this.swatches.length
                        'and your things'
                        'Colours from your things'
                      }}</span>
                  {{/if}}
                </p>
              {{/if}}
            </div>
          {{/if}}
          <div class='back'>
            <div class='stampwrap' aria-hidden='true'>
              <span class='stamp'>
                <span class='art art-{{this.stampArt}}'><span
                    class='sun'
                  ></span><span class='hill'></span></span>
                <span class='sname'>{{this.stampName}}</span>
                {{#if this.stampWhat}}<span
                    class='swhat'
                  >{{this.stampWhat}}</span>{{/if}}
              </span>
              <span class='cancel'></span>
            </div>
            <span
              class='pmark'
              style={{this.progress.ring}}
              role='img'
              aria-label='{{this.progress.packed}} of {{this.progress.total}} packed'
            >
              <span>{{if this.postmark this.postmark.day 'PACKING'}}</span>
              <span class='pn'>{{this.progress.packed}}
                /
                {{this.progress.total}}</span>
              <span class='pl'>packed</span>
            </span>
          </div>
          <div class='acts {{if this.setupOpen "hidden"}}'>
            <button
              type='button'
              class='primary'
              disabled={{if this.busy true false}}
              {{on 'click' this.researchPlace}}
            >{{if
                @model.researchedAt
                'Research again'
                'Research the place'
              }}</button>
            <button
              type='button'
              class='quiet'
              disabled={{if this.busy true false}}
              {{on 'click' this.planList}}
            >Redo the list</button>
            <button
              type='button'
              class='quiet'
              disabled={{if this.busy true false}}
              {{on 'click' this.openStart}}
            >{{if this.items.length 'Add from…' 'Start from…'}}</button>
          </div>
        </header>
        <div class='msgs'>
          {{#if this.busy}}<p
              class='busy'
              role='status'
            >{{this.busy}}</p>{{/if}}
          {{#if this.error}}<p
              class='err'
              role='alert'
            >{{this.error}}</p>{{/if}}
        </div>

        <section class='weather' aria-label='Weather'>
          {{#if this.weatherRows.length}}
            <div class='wrow wdates' aria-hidden='true'>
              <span></span>
              <div class='wdays'>{{#each this.weatherDates as |wd|}}<span
                    class='wd'
                  >{{wd.dow}} <b>{{wd.dm}}</b></span>{{/each}}</div>
            </div>
          {{/if}}
          {{#each this.weatherRows as |row|}}
            <div class='wrow'>
              <span class='wplace'>{{row.place}}</span>
              <div class='wdays'>
                {{#each row.days as |dy|}}
                  <span
                    class='day {{if dy.cold "cold"}}'
                    title='{{dy.date}}: {{dy.sky}}, {{dy.hiR}}° / {{dy.loR}}°'
                  >
                    <span class='sk {{dy.sky}}'><dy.icon
                        width='18'
                        height='18'
                      /><span class='sr'>{{dy.sky}}</span></span>
                    <span class='tp'><b>{{dy.hiR}}°</b>
                      <span>{{dy.loR}}°</span></span>
                  </span>
                {{/each}}
              </div>
            </div>
          {{else}}
            <p class='muted'>Research the place to see the weather by day.</p>
          {{/each}}
          {{#if this.typical}}<p class='muted small'>Dates more than two weeks
              away show last year's weather on the same days, as a guide; it
              switches to the forecast nearer the time.</p>{{/if}}
        </section>

        <section
          class='list'
          aria-label='Packing list'
          {{this.watchItems this.itemsSig}}
        >
          {{#each this.groups as |grp|}}
            <div class='cat'>
              <h2 class='ch' style={{grp.hue}}><span class='cic'><grp.icon
                    width='15'
                    height='15'
                  /></span>{{grp.name}}
                <span class='cn'>{{grp.packed}}/{{grp.total}}
                  packed{{#if grp.missing}}
                    ·
                    {{grp.missing}}
                    to find{{/if}}</span></h2>
              <ul style={{grp.hue}}>
                {{#each grp.rows as |ln|}}
                  <li
                    class='ln {{ln.status}} {{if ln.fresh "fresh"}}'
                    data-id={{ln.id}}
                    draggable='true'
                    {{on 'dragstart' (fn this.dragRow ln.id)}}
                    {{on 'dragend' this.dragEnd}}
                  >
                    <button
                      type='button'
                      class='thumb'
                      {{on 'click' (fn this.zoomIn ln.card)}}
                      aria-label='Show {{ln.name}} big'
                    >
                      {{#if ln.photo}}<img
                          src={{ln.photo}}
                          alt=''
                        />{{else}}<span class='ph'><grp.icon
                            width='20'
                            height='20'
                          /></span>{{/if}}
                    </button>
                    <span class='nm'><b>{{ln.name}}</b>
                      {{ln.count}}{{#if ln.short}}
                        <em>{{ln.short}}</em>{{/if}}{{#if ln.why}}<span
                          class='why'
                        >{{ln.why}}</span>{{/if}}{{#if ln.lives}}<span
                          class='why lives'
                        >{{ln.lives}}</span>{{/if}}{{#if ln.suggest}}<span
                          class='sug'
                        ><span class='sq'>Leave home?
                            <span class='sw'>{{ln.suggest}}</span></span><button
                            type='button'
                            class='sb'
                            {{on 'click' (fn this.leaveIt ln)}}
                          >Leave it</button><button
                            type='button'
                            class='sb keep'
                            {{on 'click' (fn this.keepIt ln)}}
                          >Keep</button></span>{{/if}}</span>
                    <span class='rowacts'>
                      <span class='stw'><select
                          class='st {{ln.status}}'
                          aria-label='Where {{ln.name}} is'
                          {{on 'change' (fn this.setStatus ln)}}
                        >{{#each ln.opts as |o|}}<option
                              value={{o.v}}
                              selected={{eq o.v ln.value}}
                            >{{o.l}}</option>{{/each}}</select></span>
                      <button
                        type='button'
                        class='x'
                        title='Not bringing'
                        aria-label='Not bringing {{ln.name}}'
                        {{on 'click' (fn this.drop ln.id)}}
                      >✕</button>
                    </span>
                  </li>
                {{/each}}
              </ul>
            </div>
          {{else}}
            <div class='empty'>
              <p><b>Nothing on the list yet.</b></p>
              <p class='muted'>Research the place for a starting list, or
                photograph what you're thinking of bringing.</p>
            </div>
          {{/each}}
          {{#if this.tasks.length}}
            <div class='cat tasks'>
              <h2>Before you go</h2>
              <ul>
                {{#each this.tasks as |tk|}}
                  <li class='task {{if tk.done "done"}}'>
                    <label><input
                        type='checkbox'
                        checked={{tk.done}}
                        {{on 'change' (fn this.toggleTask tk)}}
                      />
                      <span><b>{{tk.name}}</b>{{#if tk.why}}<span
                            class='why'
                          >{{tk.why}}</span>{{/if}}</span></label>
                  </li>
                {{/each}}
              </ul>
            </div>
          {{/if}}
          {{#if this.skipped.length}}
            <div class='skipped'>
              <button
                type='button'
                class='link'
                aria-expanded={{if this.showSkipped 'true' 'false'}}
                {{on 'click' this.toggleSkipped}}
              >Not bringing · {{this.skipped.length}}</button>
              {{#if this.showSkipped}}
                <p class='muted small'>The camera remembers these and leaves
                  them out of this trip. Delete one to take it off this trip
                  completely; it stays among your things.</p>
                <ul>
                  {{#each this.skipped as |sk|}}
                    <li class='ln skip'>
                      <button
                        type='button'
                        class='thumb'
                        {{on 'click' (fn this.zoomIn sk.card)}}
                        aria-label='Show {{sk.name}} big'
                      >{{#if sk.photo}}<img
                            src={{sk.photo}}
                            alt=''
                          />{{else}}<span class='ph'>?</span>{{/if}}</button>
                      <span class='nm'><b>{{sk.name}}</b><span
                          class='why'
                        >{{sk.cat}}{{#if sk.why}}
                            ·
                            {{sk.why}}{{/if}}</span></span>
                      <span class='rowacts'>
                        <button
                          type='button'
                          class='st'
                          {{on 'click' (fn this.bringBack sk.id)}}
                        >Bring it</button>
                        <button
                          type='button'
                          class='st del'
                          {{on 'click' (fn this.forget sk.id)}}
                        >Delete</button>
                      </span>
                    </li>
                  {{/each}}
                </ul>
              {{/if}}
            </div>
          {{/if}}
        </section>

        {{#if this.zoom}}
          <dialog
            class='zoom'
            style={{this.zoomHue}}
            {{this.modal this.zoomOut}}
            aria-label={{this.zoomName}}
          >
            <div class='zbig'>
              {{#if this.zoomPhoto}}<img
                  src={{this.zoomPhoto}}
                  alt={{this.zoomView.name}}
                />{{else}}<span class='zph'>No photo yet: it fills in when the
                  camera finds it, or add one.</span>{{/if}}
              {{#if this.zoomStrip.length}}
                <div class='zstrip'>
                  {{#each this.zoomStrip as |ph|}}
                    <button
                      type='button'
                      class='zthumb {{if ph.on "on"}}'
                      aria-label={{ph.label}}
                      title={{ph.label}}
                      {{on 'click' (fn this.pickPhoto ph.url)}}
                    ><img src={{ph.url}} alt='' /></button>
                  {{/each}}
                </div>
              {{/if}}
            </div>
            <div class='ztxt'>
              <div class='zhead'>
                <h2>{{this.zoomName}}</h2>
                <button
                  type='button'
                  class='x'
                  aria-label='Close'
                  {{on 'click' this.zoomOut}}
                >✕</button>
              </div>
              {{#if this.zoom.why}}<p
                  class='muted small'
                >{{this.zoom.why}}</p>{{/if}}

              <div class='zsec'>
                <h3>Where it lives</h3>
                <input
                  class='zin'
                  type='text'
                  value={{this.zoomThing.storedAt}}
                  placeholder='e.g. top shelf of the bedroom wardrobe'
                  aria-label='Where it lives'
                  {{on 'change' this.setStoredAt}}
                />
                {{#if this.zoomStored}}
                  <p class='muted small'>Put away {{this.zoomStored.on}}</p>
                  <div class='zscan'><img
                      src={{this.zoomStored.photo}}
                      alt='The spot it was put away in'
                    />{{#if this.zoomStored.box}}<span
                        class='zbox'
                        style={{this.zoomStored.box}}
                      ></span>{{/if}}</div>
                {{else}}
                  <p class='muted small'>Type it, or after the trip photograph
                    it going back in “Put away” mode.</p>
                {{/if}}
              </div>

              <div class='zsec'>
                <h3>Your notes</h3>
                <textarea
                  class='zin'
                  rows='2'
                  placeholder='Only you write here'
                  aria-label='Your notes'
                  {{on 'change' this.setMyNotes}}
                >{{this.zoomThing.myNotes}}</textarea>
              </div>

              {{#if this.zoomAi.length}}
                <div class='zsec'>
                  <h3>What the camera noticed</h3>
                  <ul class='zai'>
                    {{#each this.zoomAi as |n|}}
                      <li><span>{{n.text}}
                          <span class='muted'>· {{n.when}}</span></span><button
                          type='button'
                          class='x'
                          aria-label='Remove this note'
                          {{on 'click' (fn this.dropAiNote n.i)}}
                        >✕</button></li>
                    {{/each}}
                  </ul>
                </div>
              {{/if}}

              {{#if this.zoomSnapShown}}
                <div class='zsec'>
                  <h3>Where the camera saw it</h3>
                  <div class='zscan'><img
                      src={{this.zoomSnapShown}}
                      alt='Everything in that shot'
                    />{{#if this.zoomBox}}<span
                        class='zbox'
                        style={{this.zoomBox}}
                      ></span>{{/if}}</div>
                </div>
              {{/if}}

              <div class='zacts'>
                {{#if this.zoomCanMain}}<button
                    type='button'
                    class='quiet'
                    {{on 'click' this.makeMain}}
                  >Use as main photo</button>{{/if}}
                <label class='quiet file {{if this.zoomBusy "off"}}'>{{if
                    this.zoomBusy
                    'Saving…'
                    (if this.zoomMain 'Replace photo' 'Add a photo')
                  }}<input
                    type='file'
                    accept='image/*'
                    disabled={{this.zoomBusy}}
                    {{on 'change' this.replacePhoto}}
                  /></label>
                <button
                  type='button'
                  class='quiet'
                  {{on 'click' this.zoomCard}}
                >Open the item</button>
                <button
                  type='button'
                  class='primary'
                  {{on 'click' this.zoomOut}}
                >Close</button>
              </div>
            </div>
          </dialog>
        {{/if}}

        {{#if this.startOpen}}
          <dialog
            class='pick'
            {{this.modal this.closeStart}}
            aria-label='Start the list from'
          >
            <h2>{{if
                this.items.length
                'Add to the list from…'
                'Start the list from…'
              }}</h2>
            {{#if this.pastTrips.length}}
              <p class='muted small'>A past trip: everything you took, set to
                “Need”. Anything that doesn't suit this trip's weather is marked
                “Leave home?” for you to decide.</p>
              <ul class='trips'>
                {{#each this.pastTrips as |tp|}}
                  <li><button
                      type='button'
                      class='tripbtn'
                      {{on 'click' (fn this.inherit tp.card)}}
                    ><b>{{tp.place}}</b><span>{{tp.dates}}</span></button></li>
                {{/each}}
              </ul>
            {{/if}}
            <label
              class='quiet file'
              title='Any format: a web page, text, PDF, or a photo of a list'
            >A checklist file (any format)<input
                type='file'
                {{on 'change' this.importList}}
              /></label>
            <button
              type='button'
              class='link'
              {{on 'click' this.closeStart}}
            >{{if this.items.length 'Cancel' 'Nothing: start blank'}}</button>
          </dialog>
        {{/if}}

        <aside class='side'>
          {{#if this.arrivals.length}}
            <section
              class='arrive'
              aria-live='polite'
              aria-label='Just now from your phone'
            >
              <h2 class='ah'><span class='aic'><SmartphoneIcon
                    width='15'
                    height='15'
                  /></span>Just now from your phone</h2>
              <ul>
                {{#each this.arrivals as |a|}}
                  <li><button
                      type='button'
                      class='al {{a.kind}}'
                      {{on 'click' (fn this.goTo a.id)}}
                    ><span class='ak'>{{a.label}}</span><span
                        class='an'
                      >{{a.name}}</span></button></li>
                {{/each}}
              </ul>
            </section>
          {{/if}}
          <section class='cam' aria-label='Camera'>
            <div class='modes' role='group' aria-label='What the photo shows'>
              {{#each this.modes as |md|}}
                <button
                  type='button'
                  class='md {{if md.on "on"}}'
                  aria-pressed={{if md.on 'true' 'false'}}
                  {{on 'click' (fn this.setMode md.key)}}
                >{{md.label}}</button>
              {{/each}}
            </div>
            <p class='muted small'>{{this.modeHint}}</p>
            {{#if this.intoBags.length}}
              <label class='into'>Packing into
                <select {{on 'change' this.pickBagSelect}}>{{#each
                    this.intoBags
                    as |b|
                  }}<option
                      value={{b.id}}
                      selected={{b.on}}
                    >{{b.name}}</option>{{/each}}</select>
              </label>
            {{/if}}
            {{#if this.camOn}}
              <div
                class='vf
                  {{if this.auto "scanning"}}
                  {{if this.pending "busy"}}'
                {{this.registerVf}}
              >
                <video {{this.bindVideo}} autoplay muted playsinline></video>
                {{#each this.marks key='id' as |mk|}}
                  <span
                    class='mark {{mk.kind}} {{if mk.top "in"}}'
                    style={{mk.style}}
                  ><span class='tag'>{{mk.label}}</span></span>
                {{/each}}
                <span class='scanline' aria-hidden='true'></span>
                <span class='reading'>{{if
                    this.auto
                    (if this.pending 'Reading…' 'Scanning')
                    'Paused'
                  }}{{#if this.lastMs}} · {{this.secs}}{{/if}}</span>
              </div>
              <div class='tray' {{this.registerTray}} aria-label='Found so far'>
                {{#each this.trays as |ty|}}
                  <span class='chip' data-cat={{ty.key}}><b>{{ty.n}}</b>
                    {{ty.name}}</span>
                {{/each}}
              </div>
              <div class='shoot'>
                <button
                  type='button'
                  class='quiet {{if this.auto "on"}}'
                  aria-pressed={{if this.auto 'true' 'false'}}
                  {{on 'click' this.toggleAuto}}
                >{{if this.auto 'Pause scanning' 'Scan'}}</button>
                <button
                  type='button'
                  class='shutter'
                  aria-label='Read this now'
                  {{on 'click' this.shoot}}
                ></button>
                <button
                  type='button'
                  class='link'
                  {{on 'click' this.stopCam}}
                >Stop camera</button>
              </div>
              <p class='muted small'>Point at your things and hold still for a
                moment; move on to the next part when the labels appear.</p>
            {{else}}
              <div class='vfph'>
                <CameraIcon width='28' height='28' />
                <div class='start'>
                  <button
                    type='button'
                    class='primary'
                    {{on 'click' this.startCam}}
                  >Start scanning</button>
                  <label class='quiet file'>Take photos<input
                      type='file'
                      accept='image/*'
                      multiple
                      {{this.rearCamera}}
                      {{on 'change' this.pick}}
                    /></label>
                </div>
              </div>
              {{#if this.pending}}<p class='busy'>Reading
                  {{this.pending}}
                  photo(s)…</p>{{/if}}
            {{/if}}
            {{#if this.feed.length}}
              <ul class='feed' aria-live='polite'>
                {{#each this.feed as |fd|}}
                  <li class='{{fd.kind}} {{if fd.gone "gone"}}'>
                    <span>{{fd.text}}</span>
                    {{#if fd.item}}{{#if fd.gone}}<span class='off'>off the list</span>{{else}}<button
                          type='button'
                          class='x'
                          aria-label='Not bringing this'
                          {{on 'click' (fn this.drop fd.item)}}
                        >✕</button>{{/if}}{{/if}}
                  </li>
                {{/each}}
              </ul>
            {{/if}}
            {{#if this.toFind.n}}
              <p class='need'>
                <b>{{this.toFind.n}} to find</b>
                {{#each this.toFind.first as |nm|}}<span
                    class='fchip'
                  >{{nm}}</span>{{/each}}
                {{#if this.toFind.more}}<span
                    class='fchip more'
                    title={{this.toFind.rest}}
                  >+{{this.toFind.more}}</span>{{/if}}
              </p>
            {{/if}}
          </section>

          <section
            class='kit
              {{unless this.gauge.bag "nobag"}}
              {{if this.dropping "dropping"}}'
            aria-label={{this.bagTitle}}
            {{on 'dragover' this.dragOver}}
            {{on 'dragleave' this.dragLeave}}
            {{on 'drop' (fn this.dropOn '')}}
          >
            <h2>{{this.bagTitle}}</h2>
            {{#if this.gauge.several}}
              <div class='btabs' role='group' aria-label='Bags'>
                {{#each this.bagTabs as |bt|}}
                  <span class='btw {{if bt.on "on"}}'>
                    <button
                      type='button'
                      aria-pressed={{if bt.on 'true' 'false'}}
                      class='btab'
                      {{on 'click' (fn this.pickBag bt.id)}}
                      {{on 'dragover' this.dragOver}}
                      {{on 'drop' (fn this.dropOn bt.id)}}
                    >{{bt.name}} <span class='bn'>{{bt.count}}</span></button>
                    <button
                      type='button'
                      class='bx'
                      title='Remove this bag'
                      aria-label='Remove {{bt.name}}'
                      {{on 'click' (fn this.removeBag bt.id)}}
                    >✕</button>
                  </span>
                {{/each}}
              </div>
            {{/if}}
            {{#if this.gauge.bag}}
              <p class='bagname'>{{this.gauge.bag.type}}
                · about
                {{this.gauge.cap}}
                L{{#if this.gauge.bag.carryOn}} · cabin size{{/if}}</p>
              {{#if (eq this.gauge.shape 'backpack')}}
                <svg
                  class='pack {{if this.gauge.over "over"}}'
                  viewBox='0 0 300 196'
                  aria-hidden='true'
                >
                  <defs><clipPath id='pack-body'><path
                        d='M100 66Q100 34 150 34Q200 34 200 66V164Q200 180 184 180H116Q100 180 100 164Z'
                      /></clipPath></defs>
                  <ellipse class='shadow' cx='150' cy='184' rx='72' ry='5' />
                  <rect
                    class='shell'
                    x='84'
                    y='112'
                    width='22'
                    height='56'
                    rx='8'
                  />
                  <rect
                    class='shell'
                    x='194'
                    y='112'
                    width='22'
                    height='56'
                    rx='8'
                  />
                  <path class='loop' d='M136 37C136 16 164 16 164 37' />
                  <g clip-path='url(#pack-body)'>
                    <rect
                      class='lining'
                      x='100'
                      y='30'
                      width='100'
                      height='152'
                    />
                    <rect
                      class='lvl going'
                      x='100'
                      y='34'
                      width='100'
                      height='146'
                      style={{this.gauge.goingK}}
                    />
                    <rect
                      class='lvl packed'
                      x='100'
                      y='34'
                      width='100'
                      height='146'
                      style={{this.gauge.packedK}}
                    />
                  </g>
                  <path
                    class='rim'
                    d='M100 66Q100 34 150 34Q200 34 200 66V164Q200 180 184 180H116Q100 180 100 164Z'
                  />
                  <path class='zip' d='M108 74Q150 48 192 74' />
                  <rect
                    class='pocket'
                    x='117'
                    y='118'
                    width='66'
                    height='50'
                    rx='13'
                  />
                  <path class='zip' d='M124 128H176' />
                  <path class='string' d='M162 30L184 16' />
                  <g class='tag' transform='rotate(8 206 15)'><rect
                      x='184'
                      y='4'
                      width='46'
                      height='22'
                      rx='5'
                    /><circle cx='191' cy='15' r='2.3' /><text
                      x='212'
                      y='19.5'
                      text-anchor='middle'
                    >{{this.gauge.cap}} L</text></g>
                </svg>
              {{else if (eq this.gauge.shape 'duffel')}}
                <svg
                  class='duf {{if this.gauge.over "over"}}'
                  viewBox='0 0 300 124'
                  aria-hidden='true'
                >
                  <defs><clipPath id='duf-body'><path
                        d='M36 40H264C287 40 297 60 297 78S287 116 264 116H36C13 116 3 96 3 78S13 40 36 40Z'
                      /></clipPath></defs>
                  <ellipse class='shadow' cx='150' cy='118' rx='128' ry='4.5' />
                  <path class='loop' d='M112 42C112 10 188 10 188 42' />
                  <g clip-path='url(#duf-body)'>
                    <rect class='lining' x='0' y='36' width='300' height='84' />
                    <path
                      class='band going'
                      d='M36 40H264C287 40 297 60 297 78S287 116 264 116H36C13 116 3 96 3 78S13 40 36 40Z'
                      style={{this.gauge.bandGoing}}
                    />
                    <path
                      class='band packed'
                      d='M36 40H264C287 40 297 60 297 78S287 116 264 116H36C13 116 3 96 3 78S13 40 36 40Z'
                      style={{this.gauge.bandPacked}}
                    />
                    <path
                      class='seam'
                      d='M40 42C32 64 32 94 40 114M260 42C268 64 268 94 260 114'
                    />
                  </g>
                  <path
                    class='rim'
                    d='M36 40H264C287 40 297 60 297 78S287 116 264 116H36C13 116 3 96 3 78S13 40 36 40Z'
                  />
                  <path class='zip' d='M46 52H254' />
                  <rect
                    class='tab'
                    x='104'
                    y='35'
                    width='16'
                    height='12'
                    rx='3'
                  />
                  <rect
                    class='tab'
                    x='180'
                    y='35'
                    width='16'
                    height='12'
                    rx='3'
                  />
                  <path class='string' d='M196 38L214 20' />
                  <g class='tag' transform='rotate(10 232 18)'><rect
                      x='210'
                      y='6'
                      width='46'
                      height='22'
                      rx='5'
                    /><circle cx='217' cy='17' r='2.3' /><text
                      x='238'
                      y='21.5'
                      text-anchor='middle'
                    >{{this.gauge.cap}} L</text></g>
                </svg>
              {{else}}
                <svg
                  class='case {{if this.gauge.over "over"}}'
                  viewBox='0 0 300 140'
                  aria-hidden='true'
                >
                  <defs>
                    <clipPath id='case-lining'><rect
                        x='26'
                        y='36'
                        width='248'
                        height='80'
                        rx='8'
                      /></clipPath>
                    <linearGradient
                      id='case-depth'
                      x1='0'
                      y1='0'
                      x2='0'
                      y2='1'
                    ><stop
                        offset='0'
                        stop-color='black'
                        stop-opacity='0.14'
                      /><stop
                        offset='0.22'
                        stop-color='black'
                        stop-opacity='0'
                      /><stop
                        offset='0.8'
                        stop-color='black'
                        stop-opacity='0'
                      /><stop
                        offset='1'
                        stop-color='black'
                        stop-opacity='0.08'
                      /></linearGradient>
                  </defs>
                  <ellipse class='shadow' cx='150' cy='131' rx='132' ry='5' />
                  <rect
                    class='wheel'
                    x='5'
                    y='31'
                    width='13'
                    height='18'
                    rx='5'
                  />
                  <rect
                    class='wheel'
                    x='5'
                    y='103'
                    width='13'
                    height='18'
                    rx='5'
                  />
                  <rect
                    class='grip'
                    x='280'
                    y='58'
                    width='13'
                    height='36'
                    rx='5'
                  />
                  <rect
                    class='carry'
                    x='126'
                    y='14'
                    width='48'
                    height='16'
                    rx='7'
                  />
                  <rect
                    class='shell'
                    x='12'
                    y='24'
                    width='276'
                    height='104'
                    rx='18'
                  />
                  <rect
                    class='zip'
                    x='19'
                    y='31'
                    width='262'
                    height='90'
                    rx='13'
                  />
                  <g clip-path='url(#case-lining)'>
                    <rect
                      class='lining'
                      x='26'
                      y='36'
                      width='248'
                      height='80'
                    />
                    <rect
                      class='lvl going'
                      x='26'
                      y='36'
                      width='248'
                      height='80'
                      style={{this.gauge.goingK}}
                    />
                    <rect
                      class='lvl packed'
                      x='26'
                      y='36'
                      width='248'
                      height='80'
                      style={{this.gauge.packedK}}
                    />
                    <rect
                      x='26'
                      y='36'
                      width='248'
                      height='80'
                      fill='url(#case-depth)'
                    />
                    <path class='strap' d='M104 30L196 122M196 30L104 122' />
                    <path
                      class='strap edge'
                      d='M104 30L196 122M196 30L104 122'
                    />
                  </g>
                  <rect
                    class='buckle'
                    x='140'
                    y='69'
                    width='20'
                    height='14'
                    rx='3'
                  />
                  <rect
                    class='lip'
                    x='26'
                    y='36'
                    width='248'
                    height='80'
                    rx='8'
                  />
                  <circle class='pull' cx='274' cy='45' r='3' />
                  <path class='string' d='M171 22L186 12' />
                  <g class='tag' transform='rotate(8 209 13)'><rect
                      x='184'
                      y='2'
                      width='52'
                      height='22'
                      rx='5'
                    /><circle cx='191' cy='13' r='2.3' /><text
                      x='215'
                      y='17.5'
                      text-anchor='middle'
                    >{{this.gauge.cap}} L</text></g>
                </svg>
              {{/if}}
              <p class='small'>{{#if this.gauge.several}}{{this.gauge.packedL}}
                  L in it, of about
                  {{this.gauge.cap}}
                  L{{#if this.gauge.over}}
                    ·
                    <b class='warn'>too full</b>{{/if}}{{else}}{{this.gauge.packedL}}
                  L in it ·
                  {{this.gauge.goingL}}
                  L if the rest of the list goes in too{{#if this.gauge.over}}
                    ·
                    <b class='warn'>won't all fit</b>{{/if}}{{/if}}</p>
              {{#if this.dropping}}<p class='drophint'>Drop to pack it into
                  {{this.gauge.name}}</p>{{else}}<p class='muted small'>Drag
                  things from the list onto this card to pack them. Photograph
                  another bag in “The bag” mode to add it.</p>{{/if}}
            {{else}}
              <p class='muted small'>Photograph the bag in “The bag” mode to
                size it.</p>
            {{/if}}
            {{#if this.gauge.allowance}}
              <svg
                class='dial {{if this.gauge.heavy "heavy"}}'
                viewBox='0 0 220 142'
                aria-hidden='true'
              >
                <path
                  class='track'
                  d='M22 112A88 88 0 0 1 198 112'
                  pathLength='100'
                />
                <path
                  class='redzone'
                  d='M22 112A88 88 0 0 1 198 112'
                  pathLength='100'
                />
                <path
                  class='arc going'
                  d='M22 112A88 88 0 0 1 198 112'
                  pathLength='100'
                  style={{this.gauge.dialGoing}}
                />
                <path
                  class='arc packed'
                  d='M22 112A88 88 0 0 1 198 112'
                  pathLength='100'
                  style={{this.gauge.dialPacked}}
                />
                <g class='ticks'><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(-90 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(-72 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(-54 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(-36 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(-18 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(0 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(18 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(36 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(54 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(72 110 112)'
                  /><line
                    x1='110'
                    y1='38'
                    x2='110'
                    y2='44'
                    transform='rotate(90 110 112)'
                  /><line
                    class='lim'
                    x1='110'
                    y1='30'
                    x2='110'
                    y2='46'
                    transform='rotate(54 110 112)'
                  /></g>
                <text
                  class='lab'
                  x='160.2'
                  y='79.6'
                  text-anchor='middle'
                >{{this.gauge.allowance}}</text>
                <text class='lab' x='22' y='132' text-anchor='middle'>0</text>
                <g class='needle' style={{this.gauge.needle}}><path
                    d='M106.5 112L110 34L113.5 112Z'
                  /></g>
                <circle class='hub' cx='110' cy='112' r='7' />
                <text
                  class='read'
                  x='110'
                  y='138'
                  text-anchor='middle'
                >{{this.gauge.kg}} kg</text>
              </svg>
              <p class='small'>{{this.gauge.packedKg}}
                kg in it, bag included{{#unless this.gauge.several}}
                  · about
                  {{this.gauge.kg}}
                  kg if the rest goes in too{{/unless}}, of
                {{this.gauge.allowance}}
                kg allowed{{#if this.gauge.heavy}}
                  ·
                  <b class='warn'>over</b>{{/if}}</p>
            {{/if}}
            <label class='allow'>Weight limit{{if
                this.gauge.several
                ' for this bag'
              }}
              <input
                type='number'
                min='0'
                step='1'
                value={{if this.gauge.allowance this.gauge.allowance}}
                placeholder='20'
                {{on 'change' this.setAllowance}}
              />
              kg</label>
            {{#if this.gauge.bag}}<button
                type='button'
                class='link'
                {{on 'click' (fn this.removeBag '')}}
              >Remove this bag</button>{{/if}}
            <div class='phone'>
              {{#if this.qr}}
                <img
                  class='qr'
                  src={{this.qr}}
                  alt='Code that opens this trip on your phone'
                />
                <p class='small muted'>Scan with your phone and sign in once.
                  Photos you take there land here as you shoot.</p>
                <button
                  type='button'
                  class='link'
                  {{on 'click' this.hideQr}}
                >Hide</button>
              {{else}}
                <button
                  type='button'
                  class='quiet wide'
                  {{on 'click' this.showQr}}
                >Open on my phone</button>
              {{/if}}
            </div>
            {{#if this.recentSnaps.length}}
              <div class='snaps' aria-label='Recent photos'>
                <h2>Recent photos</h2>
                <div class='sgrid'>
                  {{#each this.recentSnaps as |sn|}}
                    <button
                      type='button'
                      class='sn {{sn.status}}'
                      {{on 'click' (fn this.open sn)}}
                      aria-label='Open photo'
                    >
                      {{#if sn.photo}}<img src={{sn.photo}} alt='' />{{/if}}
                      <span>{{sn.mode}}{{#if (eq sn.status 'reading')}}
                          · reading{{/if}}</span>
                    </button>
                  {{/each}}
                </div>
              </div>
            {{/if}}
          </section>

          {{#if this.notes.length}}
            <section class='notes' aria-label='About the place'>
              <h2>Good to know</h2>
              <ul>
                {{#each this.notesTop as |nt|}}
                  <li><b>{{nt.topic}}</b>
                    {{nt.text}}{{#if nt.source}}
                      <a
                        href={{nt.source}}
                        target='_blank'
                        rel='noopener noreferrer'
                      >source</a>{{/if}}</li>
                {{/each}}
              </ul>
              {{#if this.notesMore.length}}
                <details>
                  <summary>{{this.notesMore.length}} more</summary>
                  <ul>
                    {{#each this.notesMore as |nt|}}
                      <li><b>{{nt.topic}}</b>
                        {{nt.text}}{{#if nt.source}}
                          <a
                            href={{nt.source}}
                            target='_blank'
                            rel='noopener noreferrer'
                          >source</a>{{/if}}</li>
                    {{/each}}
                  </ul>
                </details>
              {{/if}}
              <p class='muted small'>Found by web search{{#if
                  @model.researchedAt
                }}; checked {{@model.researchedAt}}{{/if}}. Rules change, so
                check the ones that matter.</p>
            </section>
          {{/if}}

          {{#if @model.dossier}}
            <section class='dossier'>
              <button
                type='button'
                class='link'
                {{on 'click' this.toggleDossier}}
              >{{if
                  this.showDossier
                  'Hide the trip notes'
                  'Trip notes (the dossier)'
                }}</button>
              {{#if this.showDossier}}<div class='dz'><@fields.dossier
                  /></div>{{/if}}
            </section>
          {{/if}}
        </aside>
      </article></div>
    <style scoped>
      @import url('https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght,SOFT@9..144,500..700,0..100&family=Figtree:wght@400..700&display=swap');
      /* the colours (--g*, --s*, --acc, --ink, --muted) come from the place and the things: see lookVars */
      .tw {
        container-type: inline-size;
        min-height: 100%;
        background:
          radial-gradient(110% 60% at 0% 0%, var(--g1), transparent 62%),
          radial-gradient(90% 55% at 100% 0%, var(--g2), transparent 60%),
          radial-gradient(70% 45% at 100% 70%, var(--g4), transparent 65%),
          radial-gradient(80% 50% at 0% 100%, var(--g5), transparent 65%),
          var(--g3);
        transition:
          --g1 1.4s ease,
          --g2 1.4s ease,
          --g3 1.4s ease,
          --g4 1.4s ease,
          --g5 1.4s ease,
          --s1 1.4s ease,
          --s2 1.4s ease,
          --s3 1.4s ease,
          --acc 1.4s ease,
          --acc-soft 1.4s ease;
      }
      .trip {
        --line: color-mix(in oklch, var(--ink) 11%, transparent);
        --paper: #fff;
        --card: rgba(255, 255, 255, 0.8);
        --well: color-mix(in oklch, var(--ink) 6%, white);
        --accent: var(--acc);
        --ok: oklch(0.55 0.13 152);
        --cold: oklch(0.5 0.13 250);
        --display: 'Fraunces', ui-serif, Georgia, serif;
        --body:
          'Figtree', ui-sans-serif, -apple-system, 'Segoe UI', system-ui,
          sans-serif;
        box-sizing: border-box;
        padding: clamp(14px, 3cqw, 32px);
        display: grid;
        gap: 18px 24px;
        align-content: start;
        grid-template-columns: minmax(0, 1fr) minmax(260px, 320px);
        grid-template-areas: 'head head' 'msg msg' 'weather weather' 'list side';
        color: var(--ink);
        font-family: var(--body);
      }
      .trip :where(button, input, textarea, label) {
        font-family: var(--body);
      }
      /* the head is a postcard: the message on the left, stamp and address on the right */
      .head {
        grid-area: head;
        display: grid;
        gap: 16px 28px;
        grid-template-columns: minmax(0, 1fr) 180px;
        grid-template-rows: auto 1fr;
        grid-template-areas: 'ttl back' 'acts back';
        padding: clamp(18px, 3cqw, 28px);
        border-radius: 20px;
        background: rgba(255, 255, 255, 0.86);
        box-shadow:
          0 1px 2px rgba(30, 25, 20, 0.06),
          0 18px 40px -18px rgba(30, 25, 20, 0.25);
      }
      .ttl {
        grid-area: ttl;
        min-width: 0;
      }
      .head .acts {
        grid-area: acts;
        align-self: start;
      }
      .meta {
        margin: 8px 0 0;
        font-size: 14px;
        font-weight: 500;
        color: var(--muted);
      }
      .head .acts.hidden {
        display: none;
      }
      .chg {
        all: unset;
        cursor: pointer;
        margin-left: 6px;
        font-weight: 600;
        color: var(--acc);
        text-decoration: underline;
        text-underline-offset: 3px;
        text-decoration-thickness: 1px;
      }
      .chg:focus-visible {
        outline: 2px solid var(--acc);
        outline-offset: 2px;
        border-radius: 4px;
      }
      .setup {
        display: grid;
        gap: 14px;
        align-content: start;
      }
      .setup label {
        display: grid;
        gap: 5px;
        min-width: 0;
      }
      .setup label > span:first-child {
        font-size: 12px;
        font-weight: 600;
        color: var(--muted);
      }
      .setup em {
        font-style: normal;
        font-weight: 500;
        opacity: 0.75;
      }
      .setup input,
      .setup textarea {
        box-sizing: border-box;
        width: 100%;
        min-width: 0;
        font: 500 15px/1.3 var(--body);
        color: var(--ink);
        background: #fff;
        border: 1px solid color-mix(in oklch, var(--ink) 18%, transparent);
        border-radius: 10px;
        padding: 9px 11px;
      }
      .setup textarea {
        resize: vertical;
      }
      .setup input:focus-visible,
      .setup textarea:focus-visible {
        outline: 2px solid var(--acc);
        outline-offset: 1px;
        border-color: transparent;
      }
      .setup .where {
        display: grid;
        gap: 6px;
      }
      .setup .where .kicker {
        margin: 0;
      }
      .setup .h1in {
        font: 600 clamp(28px, 5cqw, 46px)/1.1 var(--display);
        font-variation-settings: 'SOFT' 60;
        letter-spacing: -0.02em;
        padding: 6px 12px;
        border-radius: 14px;
      }
      .setup .h1in::placeholder {
        color: color-mix(in oklch, var(--ink) 35%, transparent);
      }
      .srow {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
        gap: 12px;
      }
      .unit {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 14px;
        color: var(--muted);
      }
      .sacts {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .setup .small {
        margin: 0;
      }
      .back {
        grid-area: back;
        position: relative;
        display: grid;
        justify-items: end;
        align-content: start;
        padding: 4px 4px 0 0;
      }
      .stampwrap {
        position: relative;
        transform: rotate(2deg);
        filter: drop-shadow(0 3px 4px rgba(30, 25, 20, 0.22));
      }
      .stamp {
        display: grid;
        grid-template-rows: minmax(0, 1fr) auto auto;
        width: 120px;
        height: 150px;
        box-sizing: border-box;
        padding: 8px 8px 6px;
        gap: 3px;
        background: #fff;
        mask:
          radial-gradient(
              circle at 5px 5px,
              transparent 3px,
              #000 3.5px
            ) -5px -5px /
            10px 10px,
          linear-gradient(#000 0 0) content-box;
        mask-composite: add;
      }
      /* the picture: sky, then hills, snowy peaks or a sea, after the weather */
      .art {
        position: relative;
        overflow: hidden;
        background: linear-gradient(
          to bottom,
          var(--s1),
          color-mix(in oklch, var(--s1) 70%, white)
        );
      }
      .sun {
        position: absolute;
        width: 30px;
        height: 30px;
        border-radius: 50%;
        right: 14px;
        top: 14px;
        background: var(--s3);
      }
      .hill {
        position: absolute;
        left: -10%;
        right: -10%;
        bottom: 0;
        height: 45%;
        border-radius: 50% 50% 0 0;
        background: var(--s2);
      }
      .art-snow .sun {
        width: 20px;
        height: 20px;
        right: 10px;
        top: 10px;
      }
      .art-snow .hill {
        left: 0;
        right: 0;
        height: 78%;
        border-radius: 0;
        background: linear-gradient(to bottom, #fff 0 24%, var(--s2) 24%);
        clip-path: polygon(
          0 100%,
          0 62%,
          22% 34%,
          38% 52%,
          60% 4%,
          82% 44%,
          100% 30%,
          100% 100%
        );
      }
      .art-sun .sun {
        width: 48px;
        height: 48px;
        left: 50%;
        right: auto;
        top: auto;
        bottom: 26%;
        transform: translate(-50%, 50%);
      }
      .art-sun .hill {
        left: 0;
        right: 0;
        height: 30%;
        border-radius: 0;
        background: repeating-linear-gradient(
          to bottom,
          var(--s2) 0 5px,
          color-mix(in oklch, var(--s2) 70%, white) 5px 7px
        );
      }
      .sname,
      .swhat {
        font: 650 9px/1.1 var(--body);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        text-align: center;
        color: var(--ink);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .swhat {
        font-size: 7px;
        font-weight: 600;
        color: var(--muted);
      }
      /* cancellation lines over the stamp's corner */
      .cancel {
        position: absolute;
        left: -26px;
        top: 18px;
        width: 80px;
        height: 26px;
        opacity: 0.4;
        mix-blend-mode: multiply;
        pointer-events: none;
        background:
          radial-gradient(
              circle at 7px -3px,
              transparent 6px,
              var(--ink) 6.5px 7.5px,
              transparent 8px
            )
            0 0 / 14px 9px,
          radial-gradient(
              circle at 0 12px,
              transparent 6px,
              var(--ink) 6.5px 7.5px,
              transparent 8px
            )
            0 0 / 14px 9px;
      }
      /* the postmark is the packing gauge: its ring fills as things go in the bag */
      .pmark {
        --p: 0;
        position: absolute;
        right: 86px;
        top: -8px;
        width: 78px;
        height: 78px;
        border-radius: 50%;
        box-sizing: border-box;
        display: grid;
        place-content: center;
        gap: 1px;
        text-align: center;
        transform: rotate(-12deg);
        color: color-mix(in oklch, var(--ink) 72%, transparent);
        background: rgba(255, 255, 255, 0.62);
        backdrop-filter: blur(2px);
        transition: --p 1.2s ease;
        font: 700 10.5px/1.1 var(--body);
        letter-spacing: 0.05em;
      }
      .pmark::before {
        content: '';
        position: absolute;
        inset: 0;
        border-radius: 50%;
        background: conic-gradient(
          var(--acc) calc(var(--p) * 1%),
          color-mix(in oklch, var(--ink) 22%, transparent) 0
        );
        mask: radial-gradient(
          farthest-side,
          transparent calc(100% - 4px),
          #000 calc(100% - 3.5px)
        );
      }
      .pmark .pn {
        font: 700 15px/1 var(--display);
        letter-spacing: 0;
        color: var(--ink);
      }
      .pmark .pl {
        font-size: 8px;
        font-weight: 600;
        letter-spacing: 0.1em;
        text-transform: uppercase;
      }
      .pal {
        margin: 12px 0 0;
        display: flex;
        flex-wrap: wrap;
        gap: 6px 14px;
        align-items: center;
        font-size: 12.5px;
        color: var(--muted);
      }
      .pair {
        display: inline-flex;
        gap: 10px;
        align-items: center;
        white-space: nowrap;
      }
      .dots {
        display: inline-flex;
      }
      .dots i {
        width: 14px;
        height: 14px;
        border-radius: 50%;
        border: 2px solid #fff;
        margin-right: -5px;
        box-shadow: 0 0 0 1px var(--line);
      }
      .msgs {
        grid-area: msg;
        display: grid;
        gap: 4px;
        margin: -8px 0;
      }
      .busy,
      .err {
        margin: 0;
        font-size: 13px;
      }
      .busy {
        color: var(--muted);
      }
      .err {
        color: #b3261e;
      }
      .kicker {
        margin: 0;
        color: var(--muted);
        font-size: 13px;
      }
      h1 {
        margin: 4px 0 0;
        font: 600 clamp(30px, 5.4cqw, 52px)/1.02 var(--display);
        font-variation-settings: 'SOFT' 60;
        letter-spacing: -0.02em;
      }
      .plans {
        margin: 6px 0 0;
        max-width: 60ch;
        color: var(--muted);
        font-size: 14px;
        line-height: 1.45;
      }
      h2 {
        margin: 0 0 8px;
        font-size: 12px;
        font-weight: 650;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted);
      }
      .acts {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }
      .primary,
      .quiet {
        font: 600 14px/1 var(--body);
        padding: 11px 15px;
        border-radius: 999px;
        cursor: pointer;
      }
      .primary {
        border: 0;
        background: var(--acc);
        color: #fff;
        box-shadow: 0 6px 16px -8px var(--acc);
      }
      .quiet {
        border: 1px solid var(--line);
        background: #fff;
        color: var(--ink);
      }
      .quiet.on {
        border-color: var(--ink);
        box-shadow: inset 0 0 0 1px var(--ink);
      }
      .wide {
        width: 100%;
      }
      .link {
        border: 0;
        background: none;
        padding: 0;
        color: var(--ink);
        text-decoration: underline;
        font: 500 13px/1.3 var(--body);
        cursor: pointer;
      }
      button:disabled {
        opacity: 0.5;
        cursor: default;
      }
      button:focus-visible,
      .file:focus-within {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }
      .muted {
        margin: 0;
        color: var(--muted);
      }
      .small {
        font-size: 12px;
        line-height: 1.45;
        margin: 0;
      }

      .weather {
        grid-area: weather;
        display: grid;
        gap: 8px;
      }
      .wrow {
        display: grid;
        grid-template-columns: 90px minmax(0, 1fr);
        gap: 10px;
        align-items: center;
      }
      .wdates {
        margin-bottom: -4px;
      }
      .wd {
        flex: 1 1 0;
        min-width: 52px;
        max-width: 96px;
        font-size: 12px;
        color: var(--muted);
        padding-left: 10px;
      }
      .wd b {
        color: var(--ink);
        font-weight: 650;
      }
      .sr {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0 0 0 0);
      }
      .wplace {
        font-size: 13px;
        font-weight: 600;
      }
      .wdays {
        display: flex;
        gap: 6px;
        overflow-x: auto;
        padding-bottom: 2px;
      }
      .day {
        flex: 1 1 0;
        min-width: 52px;
        max-width: 96px;
        box-sizing: border-box;
        display: grid;
        gap: 6px;
        padding: 10px;
        border-radius: 14px;
        background: var(--card);
        font-size: 12px;
        box-shadow: 0 1px 2px rgba(30, 25, 20, 0.06);
      }
      .day.cold {
        background: oklch(0.95 0.03 250 / 0.92);
        box-shadow: inset 0 0 0 1.5px oklch(0.82 0.07 250);
      }
      .tp b {
        font-size: 15px;
      }
      .tp span {
        color: var(--muted);
      }
      .sk {
        display: flex;
        color: var(--muted);
      }
      .sk.Snow {
        color: var(--cold);
      }
      .sk.Rain {
        color: oklch(0.5 0.09 230);
      }
      .sk.Clear {
        color: oklch(0.68 0.15 75);
      }
      .tp b {
        font-weight: 650;
      }

      .list {
        grid-area: list;
        min-width: 0;
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: 18px;
        align-content: start;
      }
      .cat {
        min-width: 0;
      }
      .cat ul {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: 0;
        border-radius: 18px;
        background: var(--card);
        box-shadow:
          0 1px 2px rgba(30, 25, 20, 0.06),
          0 12px 30px -20px rgba(30, 25, 20, 0.3);
        overflow: hidden;
      }
      .ch {
        display: flex;
        align-items: center;
        gap: 9px;
        margin: 0 0 10px;
        font: 600 20px/1.1 var(--display);
        font-variation-settings: 'SOFT' 60;
        text-transform: none;
        letter-spacing: -0.01em;
        color: var(--ink);
      }
      .cic {
        display: grid;
        place-items: center;
        width: 28px;
        height: 28px;
        border-radius: 50%;
        background: oklch(0.92 0.06 var(--h));
        color: oklch(0.45 0.14 var(--h));
      }
      .cn {
        text-transform: none;
        letter-spacing: 0;
        font: 500 12.5px/1 var(--body);
        color: var(--muted);
        margin-left: 2px;
      }
      .ln {
        display: grid;
        grid-template-columns: 40px minmax(0, 1fr) auto;
        gap: 12px;
        align-items: center;
        padding: 8px 10px;
      }
      .ln + .ln {
        border-top: 1px solid var(--line);
      }
      .ln.fresh {
        animation: arrive 2.6s ease-out both;
      }
      @keyframes arrive {
        0% {
          background: color-mix(in oklch, var(--acc) 30%, transparent);
          box-shadow: inset 4px 0 0 var(--acc);
        }
        60% {
          background: color-mix(in oklch, var(--acc) 14%, transparent);
          box-shadow: inset 4px 0 0 var(--acc);
        }
        100% {
          background: transparent;
          box-shadow: inset 4px 0 0 transparent;
        }
      }
      .side > .arrive {
        gap: 8px;
        border: 1.5px solid color-mix(in oklch, var(--acc) 45%, transparent);
        animation: pop 0.35s ease-out;
      }
      @keyframes pop {
        from {
          transform: translateY(-6px);
          opacity: 0;
        }
      }
      .ah {
        display: flex;
        align-items: center;
        gap: 8px;
        font: 600 13px/1.2 var(--body, inherit);
        color: var(--ink);
      }
      .aic {
        display: grid;
        place-items: center;
        width: 24px;
        height: 24px;
        border-radius: 50%;
        background: var(--acc);
        color: #fff;
      }
      .arrive ul {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 4px;
      }
      .al {
        all: unset;
        box-sizing: border-box;
        width: 100%;
        display: flex;
        gap: 8px;
        align-items: baseline;
        padding: 5px 8px;
        border-radius: 8px;
        cursor: pointer;
        font-size: 14px;
      }
      .al:hover,
      .al:focus-visible {
        background: color-mix(in oklch, var(--acc) 10%, transparent);
      }
      .al:focus-visible {
        outline: 2px solid var(--acc);
      }
      .ak {
        flex: none;
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--acc);
        min-width: 52px;
      }
      .al.skip .ak {
        color: var(--muted);
      }
      .al.skip .an {
        text-decoration: line-through;
        color: var(--muted);
      }
      .an {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      @media (prefers-reduced-motion: reduce) {
        .ln.fresh {
          animation: none;
          background: color-mix(in oklch, var(--acc) 14%, transparent);
        }
        .side > .arrive {
          animation: none;
        }
      }
      @media (hover: hover) {
        .ln .x {
          opacity: 0;
          transition: opacity 0.15s;
        }
        .ln:hover .x,
        .ln:focus-within .x {
          opacity: 1;
        }
      }
      .ln.skip {
        opacity: 0.6;
      }
      .sug {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 4px 6px;
        margin-top: 6px;
        padding: 5px 6px 5px 10px;
        border-radius: 10px;
        background: color-mix(in oklch, var(--acc) 9%, white);
        font-size: 12px;
      }
      .sq {
        flex: 1 1 160px;
        min-width: 0;
        font-weight: 600;
        color: var(--ink);
      }
      .sw {
        font-weight: 500;
        color: var(--muted);
      }
      .sb {
        font: 600 12px/1 var(--body);
        padding: 6px 10px;
        border-radius: 999px;
        cursor: pointer;
        border: 1px solid var(--line);
        background: #fff;
        color: var(--ink);
      }
      .sb.keep {
        border-color: transparent;
        background: var(--acc);
        color: #fff;
      }
      .thumb {
        width: 40px;
        height: 40px;
        padding: 0;
        border: 0;
        border-radius: 10px;
        overflow: hidden;
        background: oklch(0.94 0.04 var(--h, 80));
        cursor: pointer;
      }
      .thumb img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
        mix-blend-mode: multiply;
      }
      .ph {
        display: grid;
        place-items: center;
        height: 100%;
        color: oklch(0.55 0.12 var(--h, 80));
      }
      .nm {
        min-width: 0;
        font-size: 14px;
        line-height: 1.3;
      }
      .nm em {
        font-style: normal;
        color: var(--muted);
        font-size: 12px;
      }
      .why {
        display: block;
        color: var(--muted);
        font-size: 12px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .st {
        border: 0;
        border-radius: 999px;
        padding: 7px 10px;
        font: 650 11.5px/1 var(--body);
        cursor: pointer;
        white-space: nowrap;
        background: var(--well);
        color: var(--muted);
      }
      .st.needed {
        background: color-mix(in oklch, var(--ink) 7%, white);
        color: color-mix(in oklch, var(--ink) 78%, white);
      }
      .st.have {
        background: oklch(0.93 0.045 255);
        color: oklch(0.45 0.13 260);
      }
      .st.packed {
        background: oklch(0.92 0.07 152);
        color: oklch(0.42 0.12 152);
      }
      .empty {
        padding: 20px;
        border-radius: 12px;
        border: 1px dashed var(--line);
      }
      .empty p {
        margin: 0 0 4px;
      }

      .side {
        grid-area: side;
        display: grid;
        gap: 14px;
        align-content: start;
        position: sticky;
        top: 12px;
        align-self: start;
        max-height: calc(100vh - 24px);
        overflow-y: auto;
        scrollbar-width: thin;
      }
      .side h2 {
        margin: 0;
      }
      .vfph {
        aspect-ratio: 16 / 10;
        border-radius: 14px;
        border: 1.5px dashed color-mix(in oklch, var(--acc) 40%, transparent);
        background: var(--acc-soft);
        display: grid;
        place-content: center;
        justify-items: center;
        gap: 14px;
        color: var(--acc);
      }
      .vfph .start {
        justify-content: center;
      }
      .need {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        align-items: center;
      }
      .need b {
        margin-right: 2px;
      }
      .fchip {
        padding: 4px 9px;
        border-radius: 999px;
        background: var(--well);
        font-size: 12px;
      }
      .fchip.more {
        background: var(--acc-soft);
        color: var(--acc);
        font-weight: 650;
        cursor: help;
      }
      .kit .phone,
      .kit .snaps {
        display: grid;
        gap: 8px;
        margin-top: 4px;
      }
      .notes details summary {
        cursor: pointer;
        font-size: 13px;
        font-weight: 600;
        color: var(--acc);
      }
      .notes details ul {
        margin-top: 8px;
      }
      .zhead {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        gap: 12px;
      }
      .zin:focus-visible,
      .zin:focus {
        outline: 2px solid var(--acc);
        outline-offset: 1px;
      }
      .side > section {
        padding: 16px;
        border-radius: 18px;
        background: var(--card);
        display: grid;
        gap: 10px;
        box-shadow:
          0 1px 2px rgba(30, 25, 20, 0.06),
          0 12px 30px -18px rgba(30, 25, 20, 0.3);
      }
      .modes {
        display: flex;
        gap: 3px;
        padding: 3px;
        border-radius: 999px;
        background: var(--well);
      }
      .md {
        flex: 1;
        border: 0;
        border-radius: 999px;
        padding: 8px 4px;
        white-space: nowrap;
        background: transparent;
        font: 600 12px/1 var(--body);
        color: var(--muted);
        cursor: pointer;
      }
      .md.on {
        background: var(--acc);
        color: #fff;
      }
      .start {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }
      .file {
        position: relative;
        overflow: hidden;
        display: inline-flex;
        align-items: center;
      }
      .file input {
        position: absolute;
        inset: 0;
        opacity: 0;
        cursor: pointer;
      }
      .file.off {
        opacity: 0.5;
        pointer-events: none;
      }
      .tasks ul {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 0;
      }
      .task label {
        display: flex;
        gap: 10px;
        align-items: flex-start;
        padding: 10px 12px;
        cursor: pointer;
      }
      .task + .task {
        border-top: 1px solid var(--line);
      }
      .task label > span {
        min-width: 0;
      }
      .task .why {
        white-space: normal;
      }
      .task input {
        flex: none;
        margin-top: 3px;
        width: 16px;
        height: 16px;
        accent-color: var(--accent);
      }
      .task.done b {
        text-decoration: line-through;
        color: var(--muted);
      }
      .zoom {
        width: min(860px, 92vw);
        max-height: 90vh;
        padding: 0;
        border: 0;
        border-radius: 20px;
        background: #fff;
        color: inherit;
        box-shadow: 0 30px 80px rgba(0, 0, 0, 0.35);
        overflow: auto;
      }
      .zoom[open] {
        display: grid;
        grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr);
      }
      .zoom::backdrop {
        background: rgba(20, 18, 15, 0.55);
      }
      .zbig {
        background: oklch(0.95 0.035 var(--h, 80));
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        grid-template-rows: minmax(0, 1fr) auto;
        place-items: center;
        min-height: 320px;
        position: sticky;
        top: 0;
        align-self: start;
        max-height: 90vh;
      }
      .zbig > img {
        mix-blend-mode: multiply;
        width: 100%;
        height: auto;
        max-height: min(74vh, 420px);
        min-width: 0;
        aspect-ratio: auto;
        object-fit: contain;
        display: block;
      }
      .zph {
        padding: 24px;
        color: var(--muted);
        text-align: center;
        font-size: 14px;
      }
      .ztxt {
        padding: 20px 22px;
        display: grid;
        gap: 8px;
        align-content: start;
      }
      .ztxt h2 {
        margin: 0;
        font: 600 24px/1.1 var(--display);
        font-variation-settings: 'SOFT' 60;
        text-transform: none;
        letter-spacing: -0.01em;
        color: inherit;
      }
      .zscan {
        position: relative;
        border-radius: 10px;
        overflow: hidden;
      }
      .zscan img {
        width: 100%;
        display: block;
      }
      .zbox {
        position: absolute;
        border: 2px solid #ffcf3f;
        border-radius: 6px;
        box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.35);
      }
      .zstrip {
        display: flex;
        gap: 6px;
        padding: 8px;
        overflow-x: auto;
        width: 100%;
        box-sizing: border-box;
      }
      .zthumb {
        flex: none;
        width: 48px;
        height: 48px;
        padding: 0;
        border: 2px solid transparent;
        border-radius: 8px;
        overflow: hidden;
        cursor: pointer;
        background: var(--well);
      }
      .zthumb.on {
        border-color: var(--ink);
      }
      .zthumb img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .zsec {
        display: grid;
        gap: 6px;
      }
      .zsec h3 {
        margin: 0;
        font-size: 11px;
        font-weight: 650;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted);
      }
      .zin {
        box-sizing: border-box;
        width: 100%;
        padding: 9px 11px;
        border: 1px solid var(--line);
        border-radius: 10px;
        font: 14px/1.4 var(--body);
        color: var(--ink);
        background: #fff;
        resize: vertical;
      }
      .zai {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 4px;
        font-size: 13px;
        line-height: 1.4;
      }
      .zai li {
        display: flex;
        gap: 8px;
        align-items: center;
        justify-content: space-between;
        padding: 4px 4px 4px 8px;
        border-radius: 8px;
        background: var(--well);
      }
      .zai .x {
        width: 26px;
        height: 26px;
      }
      .lives {
        color: var(--cold);
      }
      .pick {
        width: min(460px, 92vw);
        padding: 22px;
        border: 0;
        border-radius: 20px;
        background: #fff;
        color: inherit;
        box-shadow: 0 30px 80px rgba(0, 0, 0, 0.35);
      }
      .pick[open] {
        display: grid;
        gap: 12px;
      }
      .pick::backdrop {
        background: rgba(20, 18, 15, 0.55);
      }
      .pick h2 {
        margin: 0;
        font: 600 22px/1.1 var(--display);
        font-variation-settings: 'SOFT' 60;
        text-transform: none;
        letter-spacing: -0.01em;
        color: inherit;
      }
      .trips {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 6px;
      }
      .tripbtn {
        width: 100%;
        display: grid;
        gap: 2px;
        text-align: left;
        padding: 11px 14px;
        border: 1px solid var(--line);
        border-radius: 14px;
        background: #fff;
        color: var(--ink);
        cursor: pointer;
        font: 14px/1.3 var(--body);
      }
      .tripbtn:hover {
        border-color: var(--ink);
      }
      .tripbtn span {
        color: var(--muted);
        font-size: 12px;
      }
      .zacts {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        justify-content: flex-end;
        margin-top: 8px;
      }
      @media (max-width: 640px) {
        .zoom[open] {
          grid-template-columns: 1fr;
        }
        .zbig {
          position: static;
        }
      }
      .vf {
        position: relative;
        border-radius: 10px;
        overflow: hidden;
        background: #000;
        aspect-ratio: 3 / 4;
      }
      .vf video {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .reading {
        position: absolute;
        left: 8px;
        bottom: 8px;
        z-index: 2;
        padding: 5px 8px;
        border-radius: 6px;
        background: rgba(0, 0, 0, 0.65);
        color: #fff;
        font-size: 12px;
      }
      .mark {
        position: absolute;
        border: 2px solid #fff;
        border-radius: 10px;
        box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.25);
        animation:
          mark-in 0.25s ease-out both,
          mark-out 0.5s ease-in 3s both;
        pointer-events: none;
      }
      .mark.new {
        border-color: #ffd23f;
      }
      .mark.found,
      .mark.packed {
        border-color: #5fd38d;
      }
      .mark.seen {
        border-color: rgba(255, 255, 255, 0.7);
        border-style: dashed;
      }
      .tag {
        position: absolute;
        left: -2px;
        top: -26px;
        max-width: 180px;
        padding: 3px 7px;
        border-radius: 6px;
        background: rgba(0, 0, 0, 0.72);
        color: #fff;
        font:
          600 12px/1.3 ui-sans-serif,
          system-ui,
          sans-serif;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .mark.in .tag {
        top: 2px;
        left: 2px;
      }
      .mark.new .tag {
        background: #ffd23f;
        color: #1d1c1a;
      }
      .mark.found .tag,
      .mark.packed .tag {
        background: #2f7d4f;
      }
      @keyframes mark-in {
        from {
          opacity: 0;
          transform: scale(1.06);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      @keyframes mark-out {
        to {
          opacity: 0;
        }
      }
      .scanline {
        position: absolute;
        left: 0;
        right: 0;
        height: 2px;
        top: 0;
        background: linear-gradient(
          90deg,
          transparent,
          rgba(255, 255, 255, 0.85),
          transparent
        );
        opacity: 0;
      }
      .vf.scanning .scanline {
        opacity: 0.7;
        animation: scan 2.4s ease-in-out infinite;
      }
      .vf.busy .scanline {
        background: linear-gradient(90deg, transparent, #ffd23f, transparent);
        animation-duration: 1s;
      }
      @keyframes scan {
        0% {
          top: 4%;
        }
        50% {
          top: 94%;
        }
        100% {
          top: 4%;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .vf.scanning .scanline {
          animation: none;
          top: 50%;
        }
        .mark {
          animation: none;
        }
      }
      .tray {
        display: flex;
        flex-wrap: wrap;
        gap: 4px;
      }
      .chip {
        display: inline-flex;
        gap: 4px;
        align-items: baseline;
        padding: 5px 8px;
        border-radius: 999px;
        background: var(--well);
        font-size: 12px;
        color: var(--muted);
      }
      .chip b {
        color: var(--ink);
        font-size: 13px;
      }
      .shoot {
        display: flex;
        gap: 10px;
        align-items: center;
      }
      .shutter {
        width: 56px;
        height: 56px;
        border-radius: 50%;
        border: 4px solid #fff;
        background: var(--acc);
        box-shadow: 0 0 0 2px var(--acc);
        cursor: pointer;
        flex: none;
      }
      .feed {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 4px;
        font-size: 13px;
      }
      .feed li {
        padding: 6px 8px;
        border-radius: 7px;
        background: var(--well);
        display: flex;
        gap: 8px;
        align-items: center;
        justify-content: space-between;
      }
      .feed li.gone span:first-child {
        text-decoration: line-through;
        color: var(--muted);
      }
      .off {
        font-size: 11px;
        color: var(--muted);
        white-space: nowrap;
      }
      .x {
        flex: none;
        width: 30px;
        height: 30px;
        border-radius: 50%;
        border: 1px solid var(--line);
        background: #fff;
        color: var(--muted);
        font: 600 13px/1 var(--body);
        cursor: pointer;
      }
      .x:hover {
        color: #a3321b;
        border-color: #e7b4a8;
      }
      .rowacts {
        display: flex;
        gap: 6px;
        align-items: center;
      }
      .st.del {
        background: #fde9e4;
        color: #a3321b;
      }
      .skipped {
        display: grid;
        gap: 8px;
      }
      .skipped ul {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: 0;
        border-radius: 18px;
        background: var(--card);
        overflow: hidden;
      }
      .skipped .ln.skip {
        opacity: 1;
      }
      .skipped .ln.skip .thumb,
      .skipped .ln.skip .nm {
        opacity: 0.55;
      }
      .feed li.packed {
        background: #e3f1e8;
      }
      .feed li.add {
        background: #eef2fb;
      }
      .feed li.err,
      .feed li.hint {
        background: #fdf3e4;
      }
      .need {
        margin: 0;
        font-size: 13px;
        line-height: 1.45;
      }
      .bagname {
        margin: 0;
        font-size: 14px;
        font-weight: 600;
      }
      .case {
        display: block;
        width: 100%;
        height: auto;
        overflow: visible;
        margin: 2px 0 -4px;
      }
      .case .shadow {
        fill: color-mix(in oklch, var(--ink) 12%, transparent);
      }
      .case .shell {
        fill: color-mix(in oklch, var(--acc) 62%, var(--ink));
      }
      .case .wheel,
      .case .grip {
        fill: color-mix(in oklch, var(--ink) 82%, var(--acc));
      }
      .case .carry {
        fill: none;
        stroke: color-mix(in oklch, var(--ink) 82%, var(--acc));
        stroke-width: 5;
      }
      .case .zip {
        fill: none;
        stroke: color-mix(in oklch, white 55%, transparent);
        stroke-width: 1.6;
        stroke-dasharray: 2 2.6;
      }
      .case .lining {
        fill: color-mix(in oklch, var(--ink) 4%, white);
      }
      .case .lvl {
        transform-box: view-box;
        transform-origin: 26px 0;
        transform: scaleX(var(--k, 0));
        transition: transform 0.9s cubic-bezier(0.2, 0.8, 0.2, 1);
      }
      .case .going {
        fill: color-mix(in oklch, var(--acc) 30%, white);
      }
      .case.over .going {
        fill: #f3c2b6;
      }
      .case .packed {
        fill: var(--ok);
      }
      .case .strap {
        fill: none;
        stroke: color-mix(in oklch, var(--ink) 65%, var(--acc));
        stroke-width: 8;
        opacity: 0.72;
      }
      .case .strap.edge {
        stroke: color-mix(in oklch, white 45%, transparent);
        stroke-width: 1.2;
        stroke-dasharray: 3 3;
        opacity: 1;
      }
      .case .buckle {
        fill: color-mix(in oklch, white 85%, var(--ink));
        stroke: color-mix(in oklch, var(--ink) 55%, transparent);
        stroke-width: 1.4;
      }
      .case .lip {
        fill: none;
        stroke: color-mix(in oklch, var(--ink) 30%, transparent);
        stroke-width: 1.5;
      }
      .case.over .lip {
        stroke: oklch(0.6 0.16 30);
        stroke-width: 2.2;
      }
      .case.over .shell {
        animation: puff 2.4s ease-in-out infinite;
        transform-box: fill-box;
        transform-origin: center;
      }
      @keyframes puff {
        50% {
          transform: scale(1.01, 1.035);
        }
      }
      .case .pull {
        fill: color-mix(in oklch, white 80%, var(--ink));
      }
      .case .string {
        stroke: color-mix(in oklch, var(--ink) 45%, transparent);
        stroke-width: 1.4;
      }
      .case .tag rect {
        fill: #fffaf0;
        stroke: color-mix(in oklch, var(--ink) 25%, transparent);
        stroke-width: 1.2;
      }
      .case .tag circle {
        fill: none;
        stroke: color-mix(in oklch, var(--ink) 40%, transparent);
        stroke-width: 1.2;
      }
      .case .tag text {
        font: 700 11px/1 var(--body);
        fill: var(--ink);
        letter-spacing: 0.02em;
      }
      @media (prefers-reduced-motion: reduce) {
        .case .lvl {
          transition: none;
        }
        .case.over .shell {
          animation: none;
        }
      }
      .pack,
      .duf {
        display: block;
        width: 100%;
        height: auto;
        overflow: visible;
        margin: 2px 0 -2px;
      }
      .pack {
        max-height: 190px;
      }
      :is(.pack, .duf) .shadow {
        fill: color-mix(in oklch, var(--ink) 12%, transparent);
      }
      :is(.pack, .duf) .shell,
      .duf .tab {
        fill: color-mix(in oklch, var(--acc) 62%, var(--ink));
      }
      :is(.pack, .duf) .loop {
        fill: none;
        stroke: color-mix(in oklch, var(--ink) 82%, var(--acc));
        stroke-width: 7;
        stroke-linecap: round;
      }
      :is(.pack, .duf) .lining {
        fill: color-mix(in oklch, var(--ink) 4%, white);
      }
      .pack .lvl {
        transform-box: view-box;
        transform-origin: 0 180px;
        transform: scaleY(var(--k, 0));
        transition: transform 0.9s cubic-bezier(0.2, 0.8, 0.2, 1);
      }
      :is(.pack, .duf) .going {
        fill: color-mix(in oklch, var(--acc) 30%, white);
      }
      :is(.pack, .duf) .packed {
        fill: var(--ok);
      }
      .duf .band {
        fill: none;
        stroke-linejoin: round;
        transition: stroke-width 0.9s cubic-bezier(0.2, 0.8, 0.2, 1);
      }
      .duf .band.going {
        stroke: color-mix(in oklch, var(--acc) 30%, white);
      }
      .duf .band.packed {
        stroke: var(--ok);
      }
      :is(.pack, .duf).over .going {
        fill: #f3c2b6;
      }
      .duf.over .band.going {
        stroke: #f3c2b6;
      }
      :is(.pack, .duf) .rim {
        fill: none;
        stroke: color-mix(in oklch, var(--acc) 62%, var(--ink));
        stroke-width: 6;
      }
      :is(.pack, .duf).over .rim {
        stroke: oklch(0.58 0.17 30);
        animation: puff 2.4s ease-in-out infinite;
        transform-box: fill-box;
        transform-origin: center;
      }
      :is(.pack, .duf) .zip {
        fill: none;
        stroke: color-mix(in oklch, var(--ink) 40%, transparent);
        stroke-width: 2;
        stroke-dasharray: 1.5 2.5;
      }
      .pack .pocket {
        fill: color-mix(in oklch, white 22%, transparent);
        stroke: color-mix(in oklch, var(--acc) 62%, var(--ink));
        stroke-width: 3;
      }
      .duf .seam {
        fill: none;
        stroke: color-mix(in oklch, white 70%, transparent);
        stroke-width: 1.4;
        stroke-dasharray: 3 3;
      }
      :is(.pack, .duf) .string {
        stroke: color-mix(in oklch, var(--ink) 45%, transparent);
        stroke-width: 1.4;
      }
      :is(.pack, .duf) .tag rect {
        fill: #fffaf0;
        stroke: color-mix(in oklch, var(--ink) 25%, transparent);
        stroke-width: 1.2;
      }
      :is(.pack, .duf) .tag circle {
        fill: none;
        stroke: color-mix(in oklch, var(--ink) 40%, transparent);
        stroke-width: 1.2;
      }
      :is(.pack, .duf) .tag text {
        font: 700 11px/1 var(--body);
        fill: var(--ink);
        letter-spacing: 0.02em;
      }
      @media (prefers-reduced-motion: reduce) {
        .pack .lvl,
        .duf .band {
          transition: none;
        }
        :is(.pack, .duf).over .rim {
          animation: none;
        }
      }
      .dial {
        display: block;
        width: min(100%, 230px);
        height: auto;
        margin: 4px auto 0;
        overflow: visible;
      }
      .dial path {
        fill: none;
        stroke-width: 13;
      }
      .dial .track {
        stroke: color-mix(in oklch, var(--ink) 7%, white);
      }
      .dial .redzone {
        stroke: #f6d2c9;
        stroke-dasharray: 0 80 20 100;
      }
      .dial .arc {
        transition: stroke-dasharray 0.9s cubic-bezier(0.2, 0.8, 0.2, 1);
      }
      .dial .going {
        stroke: color-mix(in oklch, var(--acc) 34%, white);
      }
      .dial.heavy .going {
        stroke: oklch(0.7 0.13 30);
      }
      .dial .packed {
        stroke: var(--ok);
      }
      .dial .ticks line {
        stroke: color-mix(in oklch, var(--ink) 35%, transparent);
        stroke-width: 1.5;
        stroke-linecap: round;
      }
      .dial .ticks .lim {
        stroke: oklch(0.58 0.17 30);
        stroke-width: 2.5;
      }
      .dial .lab {
        font: 600 11px/1 var(--body);
        fill: var(--muted);
      }
      .dial .needle {
        transform-box: view-box;
        transform-origin: 110px 112px;
        transition: transform 1.1s cubic-bezier(0.3, 1.5, 0.5, 1);
      }
      .dial .needle path {
        fill: color-mix(in oklch, var(--ink) 85%, var(--acc));
        stroke: none;
      }
      .dial.heavy .needle path {
        fill: oklch(0.55 0.18 30);
      }
      .dial .hub {
        fill: #fff;
        stroke: color-mix(in oklch, var(--ink) 85%, var(--acc));
        stroke-width: 3;
      }
      .dial .read {
        font: 700 17px/1 var(--display);
        fill: var(--ink);
      }
      .dial.heavy .read {
        fill: oklch(0.5 0.18 30);
      }
      @media (prefers-reduced-motion: reduce) {
        .dial .arc,
        .dial .needle {
          transition: none;
        }
      }
      .btabs {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
      }
      .btw {
        display: inline-flex;
        align-items: center;
        border-radius: 999px;
        border: 1px solid var(--line);
        background: #fff;
        color: var(--ink);
      }
      .btw.on {
        background: var(--ink);
        border-color: var(--ink);
        color: #fff;
      }
      .btab {
        font: 600 12.5px/1 var(--body);
        padding: 7px 4px 7px 11px;
        border: 0;
        background: none;
        color: inherit;
        cursor: pointer;
        border-radius: 999px 0 0 999px;
      }
      .bx {
        border: 0;
        background: none;
        color: inherit;
        opacity: 0.55;
        cursor: pointer;
        font-size: 11px;
        padding: 7px 10px 7px 6px;
        border-radius: 0 999px 999px 0;
      }
      .bx:hover,
      .bx:focus-visible {
        opacity: 1;
      }
      .btab .bn {
        font-weight: 500;
        opacity: 0.65;
        margin-left: 2px;
      }
      .kit.dropping {
        outline: 2px dashed var(--acc);
        outline-offset: -6px;
        background: color-mix(in oklch, var(--acc) 7%, white);
      }
      .drophint {
        margin: 0;
        font-size: 13px;
        font-weight: 600;
        color: var(--acc);
      }
      .allow {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 12.5px;
        color: var(--muted);
      }
      .allow input {
        width: 64px;
        font: 500 13px/1 var(--body);
        padding: 6px 8px;
        border-radius: 8px;
        border: 1px solid color-mix(in oklch, var(--ink) 18%, transparent);
        background: #fff;
        color: var(--ink);
      }
      .into {
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 13px;
        font-weight: 600;
      }
      .into select {
        font: 600 13px/1 var(--body);
        padding: 6px 8px;
        border-radius: 8px;
        border: 1px solid var(--line);
        background: #fff;
        color: var(--ink);
      }
      .stw {
        position: relative;
        display: inline-flex;
      }
      .stw::after {
        content: '';
        position: absolute;
        right: 9px;
        top: 50%;
        width: 4px;
        height: 4px;
        border-right: 1.5px solid currentColor;
        border-bottom: 1.5px solid currentColor;
        transform: translateY(-70%) rotate(45deg);
        pointer-events: none;
        color: var(--muted);
      }
      select.st {
        appearance: none;
        -webkit-appearance: none;
        padding-right: 22px;
        max-width: 150px;
        text-overflow: ellipsis;
      }
      @media (hover: hover) {
        .ln[draggable='true'] {
          cursor: grab;
        }
        .ln[draggable='true']:active {
          cursor: grabbing;
        }
      }
      .bar {
        position: relative;
        height: 12px;
        border-radius: 6px;
        background: var(--well);
        overflow: hidden;
      }
      .bar.thin {
        height: 6px;
      }
      .bar span {
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        border-radius: 6px;
        transition: width 0.6s cubic-bezier(0.2, 0.8, 0.2, 1);
      }
      .bar .going {
        background: var(--acc-soft);
        box-shadow: inset 0 0 0 1px
          color-mix(in oklch, var(--acc) 25%, transparent);
      }
      .bar.thin .going {
        background: var(--s2);
      }
      .bar .going.over {
        background: #f3c2b6;
      }
      .bar.thin .going.over {
        background: var(--accent);
      }
      .bar .packed {
        background: var(--ok);
      }
      .warn {
        color: var(--accent);
      }
      .qr {
        width: 200px;
        height: 200px;
        image-rendering: pixelated;
        justify-self: center;
      }
      .sgrid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 6px;
      }
      .sn {
        position: relative;
        padding: 0;
        border: 0;
        border-radius: 8px;
        overflow: hidden;
        aspect-ratio: 1;
        background: var(--well);
        cursor: pointer;
      }
      .sn img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .sn span {
        position: absolute;
        left: 4px;
        bottom: 4px;
        padding: 2px 5px;
        border-radius: 4px;
        background: rgba(0, 0, 0, 0.6);
        color: #fff;
        font-size: 10px;
      }
      .sn.reading {
        outline: 2px solid var(--accent);
      }
      .notes ul {
        margin: 0;
        padding-left: 16px;
        display: grid;
        gap: 6px;
        font-size: 13px;
        line-height: 1.45;
      }
      .notes a {
        color: var(--muted);
      }
      .dz {
        font-size: 13px;
        line-height: 1.5;
      }

      /* the phone: the camera first, then what's left to find */
      @container (max-width: 760px) {
        .head {
          grid-template-columns: minmax(0, 1fr) 130px;
          grid-template-areas: 'ttl back' 'acts acts';
        }
        .stampwrap {
          transform: rotate(2deg) scale(0.85);
          transform-origin: top right;
        }
        .pmark {
          right: 76px;
        }
      }
      @container (max-width: 680px) {
        .trip {
          grid-template-columns: minmax(0, 1fr);
          grid-template-areas: 'head' 'msg' 'side' 'list';
          gap: 12px;
        }
        .acts,
        .weather,
        .phone,
        .snaps,
        .notes,
        .dossier,
        .pal,
        .meta,
        .stampwrap,
        .kit.nobag {
          display: none !important;
        }
        .head {
          grid-template-areas: 'ttl back';
          padding: 16px;
          border-radius: 16px;
          gap: 10px;
          grid-template-columns: minmax(0, 1fr) 72px;
          grid-template-rows: auto;
        }
        .pmark {
          position: relative;
          right: auto;
          top: 0;
          width: 70px;
          height: 70px;
        }
        .side {
          position: static;
          max-height: none;
          overflow: visible;
        }
        .vfph {
          aspect-ratio: 3 / 4;
        }
        h1 {
          font-size: 28px;
        }
        .vf {
          aspect-ratio: 3 / 4;
        }
      }
    </style>
  </template>
}

class TripFitted extends Component<typeof Trip> {
  get lookStyle() {
    return htmlSafe(
      lookVars(
        parse<Palette | null>(this.args.model.palette, null),
        this.args.model.place ?? '',
        [],
        0.6,
      ),
    );
  }
  <template>
    <div class='tf' style={{this.lookStyle}}>
      <b>{{if @model.place @model.place 'New trip'}}</b>
      <span>{{@model.startDate}}{{#if @model.endDate}}
          →
          {{@model.endDate}}{{/if}}</span>
    </div>
    <style scoped>
      .tf {
        height: 100%;
        box-sizing: border-box;
        padding: 12px 14px;
        display: grid;
        align-content: center;
        gap: 2px;
        background:
          radial-gradient(120% 90% at 0% 0%, var(--g1), transparent 65%),
          radial-gradient(100% 90% at 100% 100%, var(--g2), transparent 65%),
          var(--g3);
        color: var(--ink);
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
        overflow: hidden;
      }
      b {
        font-size: 15px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      span {
        font-size: 12px;
        color: var(--muted);
      }
    </style>
  </template>
}

export class Trip extends CardDef {
  static displayName = 'Trip';
  static icon = LuggageIcon;
  @field place = contains(StringField); // "Hokkaido, Japan"
  @field stops = contains(TextAreaField); // one place per line, for the weather; empty: the place
  @field startDate = contains(StringField); // YYYY-MM-DD
  @field endDate = contains(StringField); // YYYY-MM-DD
  @field home = contains(StringField); // home country, for plugs, rules and money
  @field plans = contains(TextAreaField); // what they'll do, in their words
  @field allowanceKg = contains(NumberField); // baggage allowance
  @field weather = contains(TextAreaField); // JSON: DayWeather[]
  @field notes = contains(TextAreaField); // JSON: Note[] (sourced, dated)
  @field researchedAt = contains(StringField);
  @field dossier = contains(MarkdownField); // the trip's living summary
  @field palette = contains(TextAreaField); // JSON: Palette, the place's colours in that month
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Trip) {
      return this.place ? `Trip: ${this.place}` : 'Trip';
    },
  });
  static isolated = TripView;
  static embedded = TripFitted;
  static fitted = TripFitted;
}
