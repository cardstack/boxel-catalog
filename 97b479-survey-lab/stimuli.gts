// Stimuli: the images and videos a study shows people (the Taste Test's app
// screens). Participants only ever see a neutral name ("Screen 7"), so where
// a screen came from (a real product, a Dribbble shot, our AI concept) can't
// sway them; the interviewer sees everything. Each screen gets a one-off AI
// description with named regions, so the interviewer can point at a part
// ("look at the sidebar here") and the chat spotlights it.
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';
import { askVision, resolveUrl } from './tool-kit';

export interface Region {
  name: string;
  box: number[]; // [ymin, xmin, ymax, xmax], 0-1000
}
export interface Stimulus {
  key: string; // s1, s2…
  name: string; // what participants see: "Screen 1"
  label: string; // what it really is, for the interviewer and researcher
  app?: string;
  screen?: string;
  source?: string; // e.g. "Real product (benchmark)", "Dribbble", "AI concept"
  image: string; // still, or the video's poster
  video?: string;
  note?: string;
  summary?: string; // AI description: what it is, how dense, what tone
  regions?: Region[];
}
export type MediaMap = Record<string, { image: string; video?: string }>;

export function readStimuli(
  raw: string | null | undefined,
  base?: string,
): Stimulus[] {
  try {
    const xs = raw ? JSON.parse(raw) : [];
    return (Array.isArray(xs) ? xs : [])
      .filter((x: any) => x?.key && x?.image)
      .map((x: any) => ({
        ...x,
        image: resolveUrl(x.image, base),
        ...(x.video ? { video: resolveUrl(x.video, base) } : {}),
      }));
  } catch {
    return [];
  }
}

// "s7", "Screen 7" or "screen 7" → the stimulus
export function findStimulus(
  list: Stimulus[],
  ref: string,
): Stimulus | undefined {
  const r = String(ref ?? '')
    .trim()
    .toLowerCase();
  return list.find(
    (s) => s.key.toLowerCase() === r || s.name.toLowerCase() === r,
  );
}

// for a tool: items that name a screen become pictures, keyed by the name shown
export function mediaFor(
  list: Stimulus[],
  items: string[],
): { items: string[]; media: MediaMap } {
  const media: MediaMap = {};
  const out = items.map((it) => {
    const s = findStimulus(list, it);
    if (!s) return it;
    media[s.name] = { image: s.image, ...(s.video ? { video: s.video } : {}) };
    return s.name;
  });
  return { items: out, media };
}
export function readMedia(raw: string | null | undefined): MediaMap {
  try {
    const m = raw ? JSON.parse(raw) : {};
    return m && typeof m === 'object' ? m : {};
  } catch {
    return {};
  }
}

// where a region sits on the picture, in %
function boxStyle(box: number[] | undefined) {
  if (!Array.isArray(box) || box.length !== 4) return null;
  const [y0, x0, y1, x1] = box.map(
    (n) => Math.max(0, Math.min(1000, Number(n))) / 10,
  );
  return htmlSafe(
    `left:${x0}%;top:${y0}%;width:${Math.max(1, x1 - x0)}%;height:${Math.max(1, y1 - y0)}%`,
  );
}

interface MediaSig {
  Args: {
    item: { name: string; image: string; video?: string };
    focus?: number[] | null;
    focusName?: string;
    play?: boolean;
  };
}
// one screen: a picture (or a playable video), with an optional spotlight on
// a region; click to see it full size
export class MediaView extends GlimmerComponent<MediaSig> {
  @tracked big = false;
  open = () => (this.big = true);
  close = () => (this.big = false);
  // the browser's own modal layer: above everything, Esc closes it
  modal = modifier((el: Element) => {
    const d = el as HTMLDialogElement;
    if (!d.open) d.showModal();
    const done = () => (this.big = false);
    d.addEventListener('close', done);
    return () => d.removeEventListener('close', done);
  });
  get spot() {
    return boxStyle(this.args.focus ?? undefined);
  }
  get playable() {
    return Boolean(this.args.item.video) && this.args.play !== false;
  }
  <template>
    <figure class='mv'>
      <div class='frame'>
        {{#if this.playable}}
          <video
            src={{@item.video}}
            poster={{@item.image}}
            controls
            muted
            playsinline
            preload='none'
          ></video>
        {{else}}
          <button
            type='button'
            class='zoom'
            aria-label='See {{@item.name}} full size'
            {{on 'click' this.open}}
          >
            <img src={{@item.image}} alt={{@item.name}} />
            {{#if this.spot}}<span
                class='spot'
                style={{this.spot}}
              ></span>{{/if}}
          </button>
        {{/if}}
      </div>
      <figcaption>{{@item.name}}{{#if @focusName}} · {{@focusName}}{{/if}}{{#if
          @item.video
        }} · video{{/if}}</figcaption>
    </figure>
    {{#if this.big}}
      <dialog class='lightbox' aria-label={{@item.name}} {{this.modal}}>
        <div class='lb-in'>
          <img src={{@item.image}} alt={{@item.name}} />
          {{#if this.spot}}<span class='spot' style={{this.spot}}></span>{{/if}}
        </div>
        <button
          type='button'
          class='lb-x'
          {{on 'click' this.close}}
        >Close</button>
      </dialog>
    {{/if}}
    <style scoped>
      .mv {
        margin: 0;
        display: grid;
        gap: 4px;
        min-width: 0;
      }
      .frame {
        position: relative;
        border-radius: 10px;
        overflow: hidden;
        background: #ece8df;
        aspect-ratio: 16 / 10;
      }
      .zoom {
        all: unset;
        display: block;
        position: relative;
        width: 100%;
        height: 100%;
        cursor: zoom-in;
      }
      .zoom:focus-visible {
        outline: 2px solid #e2553b;
        outline-offset: 2px;
      }
      img,
      video {
        width: 100%;
        height: 100%;
        object-fit: contain;
        display: block;
        background: #ece8df;
      }
      .spot {
        position: absolute;
        border: 2px solid #ffd23f;
        border-radius: 6px;
        box-shadow: 0 0 0 9999px rgba(20, 18, 15, 0.45);
        pointer-events: none;
      }
      figcaption {
        font:
          600 12px/1.3 ui-sans-serif,
          system-ui,
          sans-serif;
        color: #6b675f;
      }
      .lightbox {
        border: 0;
        padding: 16px;
        background: #1d1c1a;
        border-radius: 12px;
        max-width: 96vw;
        max-height: 94vh;
      }
      .lightbox::backdrop {
        background: rgba(15, 14, 12, 0.85);
      }
      .lb-in {
        position: relative;
        max-width: 100%;
        max-height: 100%;
      }
      .lb-in img {
        max-width: 92vw;
        max-height: 86vh;
        width: auto;
        height: auto;
        background: transparent;
      }
      .lb-x {
        display: block;
        margin: 10px 0 0 auto;
        border: 0;
        border-radius: 8px;
        padding: 8px 12px;
        background: #fff;
        font:
          600 13px/1 ui-sans-serif,
          system-ui,
          sans-serif;
        cursor: pointer;
      }
    </style>
  </template>
}

// ─── the one-off description ─────────────────────────────────────────────
const DESCRIBE = `You describe an app screen for a design researcher who will talk about it with participants. Look at the image.
- summary: 2 sentences: what kind of screen it is, how dense or airy, the tone (playful, serious, calm, loud), anything distinctive.
- regions: 4-7 named parts a person might notice or talk about ("left sidebar", "KPI strip", "data table", "chart", "header", "big hero number"), each with box_2d [ymin, xmin, ymax, xmax] in 0-1000 units of the image.
Answer ONLY with JSON: {"summary": str, "regions": [{"name": str, "box_2d": [int, int, int, int]}]}`;

export async function describeStimulus(
  ctx: any,
  s: Stimulus,
): Promise<Stimulus> {
  const j = await askVision(
    ctx,
    DESCRIBE,
    `${s.label}${s.screen ? ` (${s.screen})` : ''}`,
    s.image,
  );
  const regions: Region[] = (Array.isArray(j?.regions) ? j.regions : [])
    .filter(
      (r: any) => r?.name && Array.isArray(r?.box_2d) && r.box_2d.length === 4,
    )
    .map((r: any) => ({ name: String(r.name), box: r.box_2d.map(Number) }));
  return {
    ...s,
    summary: String(j?.summary ?? s.summary ?? ''),
    regions: regions.length ? regions : s.regions,
  };
}
