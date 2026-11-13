// A thing you own (it outlives any one trip: its photos, where it lives at
// home, notes), one line on a trip's packing list (which points at a thing
// once the camera has found it), and one photo the phone took. The trip card
// watches all three live, so the computer's checklist moves as the phone shoots.
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import ShirtIcon from '@cardstack/boxel-icons/shirt';
import CameraIcon from '@cardstack/boxel-icons/camera';
import PackageIcon from '@cardstack/boxel-icons/package';
import { htmlSafe } from '@ember/template';
import { CATEGORY_NAMES, asCategory } from './travel-ai';

export const STATUS_NAMES: Record<string, string> = {
  needed: 'Need',
  have: 'Have it',
  packed: 'Packed',
  leave: 'Leave home?',
  skip: 'Not bringing',
};

// a line shows its thing's photo once it has one
function lineThing(m: any) {
  try {
    return m?.thing ?? null;
  } catch {
    return null;
  }
}

class ItemFitted extends Component<typeof PackItem> {
  get photo() {
    return lineThing(this.args.model)?.photo || this.args.model.photo;
  }
  get cat() {
    return CATEGORY_NAMES[asCategory(this.args.model.category)];
  }
  get status() {
    return STATUS_NAMES[this.args.model.status ?? ''] ?? '';
  }
  <template>
    <div class='pi'>
      {{#if this.photo}}<img src={{this.photo}} alt='' />{{else}}<span
          class='ph'
        ></span>{{/if}}
      <div class='t'>
        <b>{{@model.name}}{{#if @model.qty}}{{#if (this.many @model.qty)}}
              ×{{@model.qty}}{{/if}}{{/if}}</b>
        <span>{{this.cat}} · {{this.status}}</span>
      </div>
    </div>
    <style scoped>
      .pi {
        height: 100%;
        box-sizing: border-box;
        padding: 8px 10px;
        display: flex;
        gap: 10px;
        align-items: center;
        overflow: hidden;
        background: #fbfaf7;
        color: #1d1c1a;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
      }
      img,
      .ph {
        flex: none;
        width: 44px;
        height: 44px;
        border-radius: 8px;
        object-fit: cover;
        background: #ece8df;
      }
      .t {
        display: grid;
        min-width: 0;
      }
      b {
        font-size: 14px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      span {
        font-size: 12px;
        color: #6b675f;
      }
    </style>
  </template>
  many = (n: number) => n > 1;
}

// the thing big, and where the camera saw it
export function boxStyle(raw: string | null | undefined) {
  try {
    const b = JSON.parse(raw ?? '');
    if (!Array.isArray(b) || b.length !== 4) return null;
    const [y0, x0, y1, x1] = b.map(
      (n: any) => Math.max(0, Math.min(1000, Number(n))) / 10,
    );
    return htmlSafe(
      `top:${y0}%;left:${x0}%;width:${x1 - x0}%;height:${y1 - y0}%`,
    );
  } catch {
    return null;
  }
}

class ItemView extends Component<typeof PackItem> {
  get thing() {
    return lineThing(this.args.model);
  }
  get photo() {
    return this.thing?.photo || this.args.model.photo;
  }
  get snapPhoto() {
    return this.thing ? this.thing.snapPhoto : this.args.model.snapPhoto;
  }
  get cat() {
    return CATEGORY_NAMES[asCategory(this.args.model.category)];
  }
  get status() {
    return STATUS_NAMES[this.args.model.status ?? ''] ?? '';
  }
  get boxStyle() {
    return boxStyle(this.thing ? this.thing.box : this.args.model.box);
  }
  <template>
    <article class='iv'>
      <div class='big'>{{#if this.photo}}<img
            src={{this.photo}}
            alt={{@model.name}}
          />{{else}}<span class='ph'>No photo yet: it fills in when the camera
            finds it.</span>{{/if}}</div>
      <div class='txt'>
        <h1>{{@model.name}}</h1>
        <p class='k'>{{this.cat}}
          ·
          {{this.status}}{{#if @model.need}} · bring {{@model.need}}{{/if}}{{#if
            @model.fromList
          }} · from {{@model.fromList}}{{/if}}</p>
        {{#if @model.why}}<p>{{@model.why}}</p>{{/if}}
        {{#if @model.note}}<p class='k'>{{@model.note}}</p>{{/if}}
        {{#if this.thing.storedAt}}<p class='k'>Lives:
            {{this.thing.storedAt}}</p>{{/if}}
        {{#if this.snapPhoto}}
          <p class='k'>Where the camera saw it</p>
          <div class='scan'><img
              src={{this.snapPhoto}}
              alt='Everything in that shot'
            />{{#if this.boxStyle}}<span
                class='box'
                style={{this.boxStyle}}
              ></span>{{/if}}</div>
        {{/if}}
      </div>
    </article>
    <style scoped>
      .iv {
        padding: 24px;
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        gap: 24px;
        max-width: 980px;
        margin: 0 auto;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
        color: #1d1c1a;
      }
      @container (max-width: 640px) {
        .iv {
          grid-template-columns: 1fr;
        }
      }
      .big img {
        width: 100%;
        aspect-ratio: 1;
        object-fit: contain;
        border-radius: 14px;
        background: #f4f1ea;
      }
      .ph {
        display: grid;
        place-items: center;
        aspect-ratio: 1;
        border-radius: 14px;
        background: #ece8df;
        color: #6b675f;
        padding: 24px;
        text-align: center;
        font-size: 14px;
      }
      h1 {
        margin: 0 0 4px;
        font-size: 24px;
      }
      .k {
        color: #6b675f;
        font-size: 13px;
        margin: 8px 0 4px;
      }
      .scan {
        position: relative;
        border-radius: 10px;
        overflow: hidden;
      }
      .scan img {
        width: 100%;
        display: block;
      }
      .box {
        position: absolute;
        border: 2px solid #ffcf3f;
        border-radius: 6px;
        box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.35);
      }
    </style>
  </template>
}

// ─── a thing you own ───────────────────────────────────────────────────────
export interface ThingPhoto {
  url: string;
  role: 'look' | 'stored'; // what it looks like, or where it was put away
  at: string;
  trip?: string;
  snap?: string; // the whole photo a cutout came from
  box?: string; // JSON box in that photo
  note?: string; // for "stored": the spot
}
export interface AiNote {
  text: string;
  at: string;
  photo?: string;
}
function list<T>(raw: string | null | undefined): T[] {
  try {
    const v = JSON.parse(raw ?? '[]');
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}
export const photosOf = (t: any) => list<ThingPhoto>(t?.photos);
export const aiNotesOf = (t: any) => list<AiNote>(t?.aiNotes);
export const day = (iso: string | null | undefined) => {
  const d = iso ? new Date(iso) : null;
  return d && !isNaN(+d)
    ? d.toLocaleDateString('en-GB', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
      })
    : '';
};

class ThingFitted extends Component<typeof Thing> {
  <template>
    <div class='th'>
      {{#if @model.photo}}<img src={{@model.photo}} alt='' />{{else}}<span
          class='ph'
        ></span>{{/if}}
      <div class='t'>
        <b>{{@model.name}}</b>
        <span>{{if
            @model.storedAt
            @model.storedAt
            'Where it lives: not recorded'
          }}</span>
      </div>
    </div>
    <style scoped>
      .th {
        height: 100%;
        box-sizing: border-box;
        padding: 8px 10px;
        display: flex;
        gap: 10px;
        align-items: center;
        overflow: hidden;
        background: #fbfaf7;
        color: #1d1c1a;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
      }
      img,
      .ph {
        flex: none;
        width: 44px;
        height: 44px;
        border-radius: 8px;
        object-fit: cover;
        background: #ece8df;
      }
      .t {
        display: grid;
        min-width: 0;
      }
      b,
      span {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      b {
        font-size: 14px;
      }
      span {
        font-size: 12px;
        color: #6b675f;
      }
    </style>
  </template>
}

class ThingView extends Component<typeof Thing> {
  get cat() {
    return CATEGORY_NAMES[asCategory(this.args.model.category)];
  }
  get photos() {
    return photosOf(this.args.model).map((p) => ({
      ...p,
      label: p.role === 'stored' ? 'Where it lives' : 'Look',
      when: day(p.at),
    }));
  }
  get ai() {
    return aiNotesOf(this.args.model).map((n) => ({ ...n, when: day(n.at) }));
  }
  get stored() {
    return boxStyle(this.args.model.storedBox);
  }
  get storedOn() {
    return day(this.args.model.storedOn);
  }
  <template>
    <article class='tv'>
      <div class='big'>{{#if @model.photo}}<img
            src={{@model.photo}}
            alt={{@model.name}}
          />{{else}}<span class='ph'>No photo yet: it fills in when the camera
            finds it.</span>{{/if}}</div>
      <div class='txt'>
        <p class='k'>{{this.cat}}</p>
        <h1>{{@model.name}}</h1>
        <section>
          <h2>Where it lives</h2>
          {{#if @model.storedAt}}
            <p class='spot'>{{@model.storedAt}}</p>
            {{#if this.storedOn}}<p class='k'>Put away
                {{this.storedOn}}</p>{{/if}}
            {{#if @model.storedPhoto}}<div class='scan'><img
                  src={{@model.storedPhoto}}
                  alt='The spot it was put away in'
                />{{#if this.stored}}<span
                    class='box'
                    style={{this.stored}}
                  ></span>{{/if}}</div>{{/if}}
          {{else}}
            <p class='k'>Not recorded yet. After a trip, photograph it going
              back in “Put away” mode.</p>
          {{/if}}
        </section>
        {{#if @model.myNotes}}<section><h2>Your notes</h2><p
              class='pre'
            >{{@model.myNotes}}</p></section>{{/if}}
        {{#if this.ai.length}}
          <section>
            <h2>What the camera noticed</h2>
            <ul class='ai'>{{#each this.ai as |n|}}<li>{{n.text}}
                  <span class='k'>{{n.when}}</span></li>{{/each}}</ul>
          </section>
        {{/if}}
        {{#if this.photos.length}}
          <section>
            <h2>Photos</h2>
            <div class='gal'>{{#each this.photos as |p|}}<figure><img
                    src={{p.url}}
                    alt=''
                  /><figcaption>{{p.label}}
                    ·
                    {{p.when}}</figcaption></figure>{{/each}}</div>
          </section>
        {{/if}}
      </div>
    </article>
    <style scoped>
      .tv {
        padding: 24px;
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        gap: 24px;
        max-width: 980px;
        margin: 0 auto;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
        color: #1d1c1a;
      }
      @container (max-width: 640px) {
        .tv {
          grid-template-columns: 1fr;
        }
      }
      .big img {
        width: 100%;
        aspect-ratio: 1;
        object-fit: contain;
        border-radius: 14px;
        background: #f4f1ea;
      }
      .ph {
        display: grid;
        place-items: center;
        aspect-ratio: 1;
        border-radius: 14px;
        background: #ece8df;
        color: #6b675f;
        padding: 24px;
        text-align: center;
        font-size: 14px;
      }
      .txt {
        display: grid;
        gap: 16px;
        align-content: start;
      }
      h1 {
        margin: 0;
        font-size: 24px;
      }
      h2 {
        margin: 0 0 6px;
        font-size: 12px;
        font-weight: 650;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: #6b675f;
      }
      .k {
        color: #6b675f;
        font-size: 13px;
        margin: 0;
      }
      .spot {
        margin: 0 0 4px;
        font-size: 16px;
        font-weight: 600;
      }
      .pre {
        margin: 0;
        white-space: pre-wrap;
        font-size: 14px;
        line-height: 1.5;
      }
      .ai {
        margin: 0;
        padding-left: 16px;
        display: grid;
        gap: 4px;
        font-size: 14px;
      }
      .scan {
        position: relative;
        margin-top: 8px;
        border-radius: 10px;
        overflow: hidden;
      }
      .scan img {
        width: 100%;
        display: block;
      }
      .box {
        position: absolute;
        border: 2px solid #ffcf3f;
        border-radius: 6px;
        box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.35);
      }
      .gal {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
        gap: 8px;
      }
      figure {
        margin: 0;
      }
      .gal img {
        width: 100%;
        aspect-ratio: 1;
        object-fit: cover;
        border-radius: 8px;
        display: block;
        background: #ece8df;
      }
      figcaption {
        font-size: 11px;
        color: #6b675f;
        margin-top: 3px;
      }
    </style>
  </template>
}

export class Thing extends CardDef {
  static displayName = 'Thing';
  static icon = PackageIcon;
  @field name = contains(StringField);
  @field category = contains(StringField);
  @field photo = contains(StringField); // the main "what it looks like" photo
  @field snapPhoto = contains(StringField); // the whole photo the main one was cut from
  @field box = contains(StringField); // where it was in that photo
  @field photos = contains(TextAreaField); // JSON: ThingPhoto[], every photo of it
  @field litres = contains(NumberField);
  @field kg = contains(NumberField);
  @field seenAt = contains(StringField);
  @field storedAt = contains(StringField); // where it lives, in words: "grey vacuum bag, top of the wardrobe"
  @field storedPhoto = contains(StringField); // the photo of it going there
  @field storedBox = contains(StringField);
  @field storedOn = contains(StringField);
  @field myNotes = contains(TextAreaField); // theirs only: the AI never writes here
  @field aiNotes = contains(TextAreaField); // JSON: AiNote[], what the camera noticed, each from one photo
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Thing) {
      return this.name;
    },
  });
  static isolated = ThingView;
  static embedded = ThingFitted;
  static fitted = ThingFitted;
}

export class PackItem extends CardDef {
  static displayName = 'Pack Item';
  static icon = ShirtIcon;
  @field trip = linksTo(CardDef);
  @field thing = linksTo(Thing); // the thing it is, once the camera has found it (a need until then)
  @field name = contains(StringField);
  @field category = contains(StringField); // wardrobe | electronics | toiletries | documents | medicine | other
  @field status = contains(StringField); // needed | have | packed | leave | skip
  @field qty = contains(NumberField); // how many the camera saw
  @field need = contains(NumberField); // how many the plan says to bring
  @field why = contains(StringField); // the plan's reason, or why to leave it
  @field leaveWhy = contains(StringField); // the AI suggests leaving it home, and why: theirs to take or not
  @field kept = contains(BooleanField); // they said keep it: not suggested again
  @field photo = contains(StringField); // cutout from the photo it was seen in
  @field litres = contains(NumberField); // packed volume of one
  @field kg = contains(NumberField); // weight of one
  @field note = contains(StringField);
  @field bag = contains(StringField); // the bag it's packed in: that bag's photo (a Snap id)
  @field seenAt = contains(StringField);
  @field snapPhoto = contains(StringField); // the whole photo the cutout came from
  @field box = contains(StringField); // JSON [ymin, xmin, ymax, xmax], 0-1000, where it was in that photo
  @field fromList = contains(StringField); // the imported checklist it came from: keeps its wording, the planner leaves it alone
  @field kind = contains(StringField); // item (default) | task: something to do, not to pack; the camera ignores it
  @field inherited = contains(StringField); // the earlier trip this line was copied from
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PackItem) {
      return this.name;
    },
  });
  static isolated = ItemView;
  static embedded = ItemFitted;
  static fitted = ItemFitted;
}

class SnapFitted extends Component<typeof Snap> {
  <template>
    <div class='sn'>
      {{#if @model.photo}}<img src={{@model.photo}} alt='' />{{/if}}
      <span class='m'>{{@model.mode}}</span>
    </div>
    <style scoped>
      .sn {
        position: relative;
        height: 100%;
        overflow: hidden;
        background: #1d1c1a;
      }
      img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .m {
        position: absolute;
        left: 6px;
        bottom: 6px;
        padding: 3px 6px;
        border-radius: 5px;
        background: rgba(0, 0, 0, 0.6);
        color: #fff;
        font:
          600 10px/1 ui-sans-serif,
          system-ui,
          sans-serif;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
    </style>
  </template>
}

class SnapView extends Component<typeof Snap> {
  <template>
    <article class='sv'>
      {{#if @model.photo}}<img
          src={{@model.photo}}
          alt='What the camera saw'
        />{{/if}}
      <div class='txt'>
        <p class='k'>{{@model.mode}}
          ·
          {{@model.takenAt}}
          ·
          {{@model.status}}</p>
        <pre>{{@model.found}}</pre>
        {{#if @model.notes}}<p>{{@model.notes}}</p>{{/if}}
      </div>
    </article>
    <style scoped>
      .sv {
        padding: 24px;
        display: grid;
        gap: 16px;
        max-width: 820px;
        margin: 0 auto;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
        color: #1d1c1a;
      }
      img {
        width: 100%;
        border-radius: 12px;
      }
      .k {
        margin: 0;
        color: #6b675f;
        font-size: 13px;
      }
      pre {
        white-space: pre-wrap;
        font:
          13px/1.5 ui-monospace,
          monospace;
        margin: 8px 0 0;
      }
    </style>
  </template>
}

export class Snap extends CardDef {
  static displayName = 'Snap';
  static icon = CameraIcon;
  @field trip = linksTo(CardDef);
  @field photo = contains(StringField);
  @field mode = contains(StringField); // items | packing | bag
  @field takenAt = contains(StringField);
  @field status = contains(StringField); // reading | done | failed
  @field found = contains(TextAreaField); // JSON: what it saw (bag: BagSeen; else a line per thing)
  @field notes = contains(TextAreaField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Snap) {
      return `${this.mode ?? 'photo'} · ${this.takenAt ?? ''}`;
    },
  });
  static isolated = SnapView;
  static embedded = SnapFitted;
  static fitted = SnapFitted;
}
