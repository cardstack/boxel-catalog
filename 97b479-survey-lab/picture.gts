// Picture it: a projective image question. Words and pictures don't map one
// to one, and how a person links their own words to visuals says things a
// rating can't: what "calm", "organised", "trustworthy" or "a Saturday that's
// mine" looks like to them.
//   describe: they describe something; the AI draws it; they change it until
//             it feels right. The changes are the strongest signal: people
//             react more easily than they invent.
//   react:    the AI draws a deliberately open scene (or shows a screen); they
//             say what is going on and how it feels (Thematic Apperception
//             style). What they read into it is the data.
// The interviewer gets their words, every version, and what the final picture
// actually shows (an AI description), not just what was asked for.
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import NumberField from '@cardstack/base/number';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import ImageIcon from '@cardstack/boxel-icons/image';
import WriteBinaryFileCommand from '@cardstack/boxel-host/tools/write-binary-file';
import {
  saveResponse,
  lines,
  parseJson,
  secs,
  hostOf,
  toolCtx,
  askVision,
  makeImage,
  type ToolHost,
} from './tool-kit';

// @ts-ignore import.meta is fine here (the host loads cards as ES modules); the catalog's CommonJS type check rejects it
const here: string = import.meta.url;

export type PictureMode = 'describe' | 'react';
export type Look = 'photo' | 'illustration' | 'ui' | 'abstract';

interface Version {
  image: string; // saved file URL
  view?: string; // shown from memory while the new file isn't served yet (not saved)
  words: string; // what they asked for (first: the description; then each change)
  ms: number; // when, since the start
}
interface PictureData {
  mode: PictureMode;
  versions: Version[];
  answers: { q: string; a: string }[]; // react mode
  reflection: string; // describe mode: what makes it right, in their words
  shows: string; // what the final picture actually shows (AI description)
  doneMs: number;
}
const emptyData: PictureData = {
  mode: 'describe',
  versions: [],
  answers: [],
  reflection: '',
  shows: '',
  doneMs: 0,
};

const LOOKS: Record<Look, string> = {
  photo: 'A natural, realistic photograph',
  illustration: 'A warm, painterly illustration',
  ui: 'A high-fidelity app screen design seen straight on, flat, no device frame, with short generic interface labels only',
  abstract:
    'An abstract composition of shapes, colours and textures, with no recognisable objects',
};
const asLook = (x: any): Look =>
  ['photo', 'illustration', 'ui', 'abstract'].includes(x) ? x : 'illustration';
const SAFE =
  'No captions or written words in the image. No real, identifiable people, celebrities or brand logos.';

export function pictureSummary(d: PictureData): string {
  const t = (ms: number) => secs(ms);
  if (d.mode === 'react') {
    const a = d.answers
      .map((x) => `"${x.q}" → "${x.a || '(no answer)'}"`)
      .join(' ');
    return `Shown an open picture${d.shows ? ` (${d.shows})` : ''}. ${a} Took ${t(d.doneMs)}.`;
  }
  const [first, ...edits] = d.versions;
  if (!first) return 'They did not describe anything.';
  const changes = edits.length
    ? ` Then changed it ${edits.length === 1 ? 'once' : `${edits.length} times`}: ${edits.map((v) => `"${v.words}"`).join(', then ')}.`
    : ' Kept the first picture without changes.';
  return `Described: "${first.words}".${changes}${d.shows ? ` The final picture shows: ${d.shows}` : ''}${d.reflection ? ` What makes it right, in their words: "${d.reflection}".` : ''} Took ${t(d.doneMs)}.`;
}

type Step =
  | 'intro'
  | 'describe'
  | 'drawing'
  | 'look'
  | 'reflect'
  | 'react'
  | 'saving'
  | 'done';

class Isolated extends Component<typeof PictureQuestion> {
  @tracked tab: 'take' | 'results' = 'take';
  @tracked step: Step = 'intro';
  @tracked name = '';
  @tracked words = '';
  @tracked change = '';
  @tracked reflection = '';
  @tracked versions: Version[] = [];
  @tracked current = 0; // which version is on screen
  @tracked answers: string[] = [];
  @tracked qi = 0;
  @tracked error = '';
  @tracked responseId = '';
  @tracked summary = '';
  started = 0;
  private lastData = ''; // the newest image as a data URL, for the next edit

  get host(): ToolHost | undefined {
    return hostOf(this.args);
  }
  constructor(owner: any, args: any) {
    super(owner, args);
    const h = hostOf(args);
    if (h) {
      this.name = h.respondent ?? '';
      this.start();
    }
  }

  get m() {
    return this.args.model;
  }
  get mode(): PictureMode {
    return this.m.mode === 'react' ? 'react' : 'describe';
  }
  get look(): Look {
    return asLook(this.m.look);
  }
  get maxEdits() {
    const n = Number(this.m.edits);
    return Number.isFinite(n) && n >= 0 ? Math.min(4, Math.round(n)) : 2;
  }
  get editsLeft() {
    return Math.max(0, this.maxEdits - (this.versions.length - 1));
  }
  get questions() {
    const qs = lines(this.m.questions);
    return qs.length
      ? qs
      : ['What is going on in this picture?', 'How does it feel to you?'];
  }
  get question() {
    return this.questions[this.qi] ?? '';
  }
  get shown() {
    const v = this.versions[this.current];
    return v ? { ...v, image: v.view ?? v.image } : null;
  }
  get strip() {
    return this.versions.map((v, i) => ({
      ...v,
      image: v.view ?? v.image,
      i,
      n: i + 1,
      on: i === this.current,
    }));
  }
  get manyVersions() {
    return this.versions.length > 1;
  }
  get answerNow() {
    return this.answers[this.qi] ?? '';
  }
  get lastQuestion() {
    return this.qi >= this.questions.length - 1;
  }
  get aspect() {
    return this.look === 'ui' ? '16:9' : '4:3';
  }

  setName = (e: Event) => (this.name = (e.target as HTMLInputElement).value);
  setWords = (e: Event) =>
    (this.words = (e.target as HTMLTextAreaElement).value);
  setChange = (e: Event) =>
    (this.change = (e.target as HTMLTextAreaElement).value);
  setReflection = (e: Event) =>
    (this.reflection = (e.target as HTMLTextAreaElement).value);
  setAnswer = (e: Event) => {
    const a = [...this.answers];
    a[this.qi] = (e.target as HTMLTextAreaElement).value;
    this.answers = a;
  };
  pick = (i: number) => (this.current = i);

  start = () => {
    this.versions = [];
    this.answers = [];
    this.qi = 0;
    this.words = '';
    this.change = '';
    this.reflection = '';
    this.error = '';
    this.started = performance.now();
    if (this.mode === 'react') this.drawSeed();
    else this.step = 'describe';
  };

  // ─── drawing ─────────────────────────────────────────────────────────
  private async draw(prompt: string, base: string | null, words: string) {
    const prev = this.step;
    this.step = 'drawing';
    this.error = '';
    try {
      const ctx = toolCtx(this.args.context);
      const { blob, dataUrl } = await makeImage(ctx, prompt, base, this.aspect);
      const image = await this.saveImage(blob);
      this.lastData = dataUrl;
      this.versions = [
        ...this.versions,
        {
          image,
          view: URL.createObjectURL(blob),
          words,
          ms: Math.round(performance.now() - this.started),
        },
      ];
      this.current = this.versions.length - 1;
      this.step = this.mode === 'react' ? 'react' : 'look';
    } catch (e: any) {
      this.error = `The picture didn't come out (${e?.message ?? e}). Try again, or put it differently.`;
      this.step =
        prev === 'drawing'
          ? this.versions.length
            ? 'look'
            : 'describe'
          : prev;
    }
  }
  private async saveImage(blob: Blob) {
    const bmp = await createImageBitmap(blob);
    const c = document.createElement('canvas');
    c.width = bmp.width;
    c.height = bmp.height;
    c.getContext('2d')!.drawImage(bmp, 0, 0);
    const jpg = await new Promise<Blob>((ok, fail) =>
      c.toBlob(
        (b) => (b ? ok(b) : fail(new Error('could not encode'))),
        'image/jpeg',
        0.88,
      ),
    );
    const buf = new Uint8Array(await jpg.arrayBuffer());
    let bin = '';
    for (let i = 0; i < buf.length; i += 0x8000)
      bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
    const written = await new WriteBinaryFileCommand(
      toolCtx(this.args.context),
    ).execute({
      realm: this.m[realmURL]?.href,
      path: `Pictures/${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}.jpg`,
      base64Content: btoa(bin),
      contentType: 'image/jpeg',
      useNonConflictingFilename: true,
    } as any);
    const url = (written as any)?.fileIdentifier;
    if (!url) throw new Error('the picture was made but not saved');
    return url as string;
  }
  drawFirst = () => {
    const w = this.words.trim();
    if (!w) return;
    const subject = this.m.subject ? ` of ${this.m.subject}` : '';
    this.draw(
      `${LOOKS[this.look]}${subject}, based closely on this description from a person: "${w}". Follow what they say; don't add things that change its mood. ${SAFE}`,
      null,
      w,
    );
  };
  redraw = () => {
    const c = this.change.trim();
    if (!c || !this.editsLeft) return;
    this.change = '';
    this.draw(
      `Edit this picture: ${c}. Keep everything else as it is. ${SAFE}`,
      this.lastData,
      c,
    );
  };
  private drawSeed() {
    if (this.m.seedImage) {
      this.versions = [
        { image: this.m.seedImage, words: '(a picture we showed)', ms: 0 },
      ];
      this.current = 0;
      this.step = 'react';
      return;
    }
    this.draw(
      `${LOOKS[this.look]}: ${this.m.seed || 'an everyday scene with two people and an object between them'}. Make it deliberately open to interpretation: no obvious story, faces not clearly readable, nothing that tells you what happens next. ${SAFE}`,
      null,
      '(an open picture)',
    );
  }
  keep = () => {
    this.current = this.versions.length - 1;
    this.step = 'reflect';
  };
  nextQuestion = () => {
    if (!(this.answers[this.qi] ?? '').trim()) return;
    if (this.qi < this.questions.length - 1) this.qi += 1;
    else this.finish();
  };

  // ─── saving ──────────────────────────────────────────────────────────
  finish = async () => {
    this.step = 'saving';
    const finalImage = this.versions[this.versions.length - 1]?.image;
    let shows = '';
    try {
      if (finalImage) {
        const j = await askVision(
          toolCtx(this.args.context),
          'Describe what this picture actually shows, for a researcher, in one plain sentence: the setting, the main things in it, the colours and the mood. Answer ONLY with JSON: {"shows": str}',
          'The picture:',
          finalImage,
        );
        shows = String(j?.shows ?? '');
      }
    } catch {
      shows = '';
    }
    const data: PictureData = {
      mode: this.mode,
      versions: this.versions.map(({ view: _view, ...v }) => v),
      answers:
        this.mode === 'react'
          ? this.questions.map((q, i) => ({
              q,
              a: (this.answers[i] ?? '').trim(),
            }))
          : [],
      reflection: this.reflection.trim(),
      shows,
      doneMs: Math.round(performance.now() - this.started),
    };
    this.summary = pictureSummary(data);
    try {
      this.responseId = await saveResponse(
        this.args,
        new URL('./picture', here).href,
        'PictureResponse',
        {
          respondent: this.name.trim() || null,
          data: JSON.stringify(data),
          summary: this.summary,
          finalImage: finalImage ?? null,
        },
      );
    } catch (e: any) {
      this.error = `Saving failed: ${e?.message ?? e}`;
    }
    this.step = 'done';
    this.host?.done({
      summary: this.summary,
      responseId: this.responseId,
      image: finalImage,
    });
  };
  again = () => {
    this.responseId = '';
    this.step = 'intro';
  };
  openResponse = () => {
    if (this.responseId)
      this.args.viewCard?.(new URL(this.responseId) as any, 'isolated');
  };

  // ─── results: everyone's final picture ───────────────────────────────
  get realms() {
    const r = this.m[realmURL];
    return r ? [r.href] : [];
  }
  responsesQuery = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: {
            module: new URL('./picture', here).href,
            name: 'PictureResponse',
          },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  get responses(): any[] {
    const id = (this.m as any).id;
    return ((this.responsesQuery?.instances ?? []) as any[]).filter(
      (r) => r.question?.id === id,
    );
  }
  showTake = () => (this.tab = 'take');
  showResults = () => (this.tab = 'results');
  open = (card: any) => this.args.viewCard?.(card, 'isolated');

  <template>
    <article class='sv pq {{if this.host "hosted"}}'>
      <header class='top'>
        <div>
          <p class='kicker'>Picture it ·
            {{if
              (eq this.mode 'react')
              'what do you see?'
              'describe it, then make it yours'
            }}</p>
          <h1>{{@model.cardTitle}}</h1>
        </div>
        <nav class='tabs' aria-label='View'>
          <button
            type='button'
            class={{if (eq this.tab 'take') 'on'}}
            {{on 'click' this.showTake}}
          >Take it</button>
          <button
            type='button'
            class={{if (eq this.tab 'results') 'on'}}
            {{on 'click' this.showResults}}
          >Results · {{this.responses.length}}</button>
        </nav>
      </header>

      {{#if (eq this.tab 'take')}}
        <section class='panel'>
          {{#if (eq this.step 'intro')}}
            <p class='statement'>{{@model.prompt}}</p>
            <label class='field'><span>Your first name or a nickname</span><input
                type='text'
                value={{this.name}}
                {{on 'input' this.setName}}
              /></label>
            <div class='actions'><button
                type='button'
                class='primary'
                {{on 'click' this.start}}
              >Start</button></div>
          {{else if (eq this.step 'describe')}}
            <p class='statement'>{{@model.prompt}}</p>
            <p class='muted'>A few sentences is plenty. A picture will be drawn
              from your words, and you can change it after.</p>
            <textarea
              rows='4'
              aria-label='Your description'
              value={{this.words}}
              {{on 'input' this.setWords}}
            ></textarea>
            <div class='actions'><button
                type='button'
                class='primary'
                disabled={{if this.words false true}}
                {{on 'click' this.drawFirst}}
              >Draw it</button></div>
          {{else if (eq this.step 'drawing')}}
            {{#if this.shown}}<img
                class='pic dim'
                src={{this.shown.image}}
                alt=''
              />{{/if}}
            <p class='drawing' role='status'>Drawing… this takes about 10
              seconds.</p>
          {{else if (eq this.step 'look')}}
            {{#if this.shown}}<img
                class='pic'
                src={{this.shown.image}}
                alt='Drawn from your words'
              />{{/if}}
            {{#if this.manyVersions}}
              <div class='strip' role='group' aria-label='Versions'>
                {{#each this.strip as |v|}}<button
                    type='button'
                    class='ver {{if v.on "on"}}'
                    aria-pressed={{if v.on 'true' 'false'}}
                    {{on 'click' (fn this.pick v.i)}}
                  ><img
                      src={{v.image}}
                      alt='Version {{v.n}}'
                    /></button>{{/each}}
              </div>
            {{/if}}
            {{#if this.editsLeft}}
              <p class='qmeta'>{{if
                  @model.editPrompt
                  @model.editPrompt
                  'Is this it? Change one thing to make it feel more like yours.'
                }}</p>
              <textarea
                rows='2'
                aria-label='What to change'
                placeholder='e.g. make it quieter, add a window, warmer light'
                value={{this.change}}
                {{on 'input' this.setChange}}
              ></textarea>
            {{/if}}
            <div class='actions'>
              {{#if this.editsLeft}}<button
                  type='button'
                  class='quiet'
                  disabled={{if this.change false true}}
                  {{on 'click' this.redraw}}
                >Redraw ({{this.editsLeft}} left)</button>{{/if}}
              <button
                type='button'
                class='primary'
                {{on 'click' this.keep}}
              >That's it</button>
            </div>
          {{else if (eq this.step 'reflect')}}
            {{#if this.shown}}<img
                class='pic'
                src={{this.shown.image}}
                alt='Your final version'
              />{{/if}}
            <p class='qmeta'>In a few words: what makes this one feel right?
              (optional)</p>
            <textarea
              rows='2'
              aria-label='What makes it right'
              value={{this.reflection}}
              {{on 'input' this.setReflection}}
            ></textarea>
            <div class='actions'><button
                type='button'
                class='primary'
                {{on 'click' this.finish}}
              >Done</button></div>
          {{else if (eq this.step 'react')}}
            {{#if this.shown}}<img
                class='pic'
                src={{this.shown.image}}
                alt='An open scene'
              />{{/if}}
            <p class='statement small'>{{this.question}}</p>
            <textarea
              rows='3'
              aria-label={{this.question}}
              value={{this.answerNow}}
              {{on 'input' this.setAnswer}}
            ></textarea>
            <div class='actions'><button
                type='button'
                class='primary'
                disabled={{if this.answerNow false true}}
                {{on 'click' this.nextQuestion}}
              >{{if this.lastQuestion 'Done' 'Next'}}</button></div>
          {{else if (eq this.step 'saving')}}
            <p class='drawing' role='status'>Saving…</p>
          {{else}}
            {{#if this.shown}}<img
                class='pic'
                src={{this.shown.image}}
                alt='Your final version'
              />{{/if}}
            <p class='muted'>Thank you.</p>
            {{#unless this.host}}
              <div class='actions'>
                {{#if this.responseId}}<button
                    type='button'
                    class='primary'
                    {{on 'click' this.openResponse}}
                  >Open the response</button>{{/if}}
                <button
                  type='button'
                  class='quiet'
                  {{on 'click' this.again}}
                >Take it again</button>
              </div>
            {{/unless}}
          {{/if}}
          {{#if this.error}}<p
              class='err'
              role='alert'
            >{{this.error}}</p>{{/if}}
        </section>
      {{else}}
        <section class='panel'>
          <div class='gallery'>
            {{#each this.responses as |r|}}
              <button type='button' class='gi' {{on 'click' (fn this.open r)}}>
                {{#if r.finalImage}}<img src={{r.finalImage}} alt='' />{{/if}}
                <span>{{if r.respondent r.respondent 'Anonymous'}}</span>
              </button>
            {{else}}
              <p class='muted'>No pictures yet.</p>
            {{/each}}
          </div>
        </section>
      {{/if}}
    </article>
    <style scoped>
      .sv {
        --sv-paper: #fbfaf7;
        --sv-panel: #ffffff;
        --sv-ink: #1d1c1a;
        --sv-muted: #6b675f;
        --sv-rule: #e4e0d8;
        --sv-live: #e2553b;
        --sv-sans:
          ui-sans-serif, -apple-system, 'Segoe UI', system-ui, sans-serif;
        container-type: inline-size;
        background: var(--sv-paper);
        color: var(--sv-ink);
        font-family: var(--sv-sans);
        box-sizing: border-box;
        min-height: 100%;
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 18px;
        align-content: start;
        max-width: 860px;
        margin: 0 auto;
      }
      .hosted {
        padding: 0 !important;
        max-width: none !important;
        min-height: 0 !important;
        width: 100% !important;
        margin: 0 !important;
        background: transparent !important;
      }
      .hosted > .top {
        display: none !important;
      }
      .hosted .panel {
        padding: 0;
        border: 0;
        background: transparent;
      }
      .top {
        display: flex;
        justify-content: space-between;
        align-items: end;
        gap: 16px;
        flex-wrap: wrap;
      }
      .kicker {
        margin: 0;
        color: var(--sv-muted);
        font-size: 13px;
      }
      h1 {
        margin: 2px 0 0;
        font: 600 clamp(22px, 3.4cqw, 30px)/1.15 var(--sv-sans);
        letter-spacing: -0.01em;
      }
      .tabs {
        display: flex;
        gap: 4px;
        padding: 4px;
        border-radius: 10px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .tabs button {
        border: 0;
        background: transparent;
        padding: 7px 12px;
        border-radius: 7px;
        font: 500 13px/1 var(--sv-sans);
        color: var(--sv-muted);
        cursor: pointer;
      }
      .tabs button.on {
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      .panel {
        display: grid;
        gap: 14px;
        padding: clamp(18px, 3cqw, 32px);
        border-radius: 14px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .statement {
        margin: 0;
        font: 600 clamp(18px, 2.8cqw, 24px)/1.3 var(--sv-sans);
        letter-spacing: -0.01em;
        max-width: 40ch;
      }
      .statement.small {
        font-size: 17px;
      }
      .muted,
      .qmeta {
        margin: 0;
        color: var(--sv-muted);
        font-size: 14px;
        line-height: 1.45;
      }
      .field {
        display: grid;
        gap: 6px;
        max-width: 360px;
        font-size: 13px;
        color: var(--sv-muted);
      }
      input[type='text'],
      textarea {
        font: 400 15px/1.45 var(--sv-sans);
        padding: 10px 12px;
        border-radius: 10px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-paper);
        color: var(--sv-ink);
        resize: vertical;
      }
      textarea:focus-visible,
      input:focus-visible {
        outline: 2px solid var(--sv-ink);
        outline-offset: 1px;
      }
      .pic {
        width: 100%;
        max-height: 460px;
        object-fit: contain;
        border-radius: 12px;
        background: #ece8df;
        display: block;
      }
      .pic.dim {
        opacity: 0.4;
      }
      .drawing {
        margin: 0;
        font-size: 14px;
        color: var(--sv-muted);
      }
      .strip {
        display: flex;
        gap: 6px;
      }
      .ver {
        padding: 0;
        border: 2px solid transparent;
        border-radius: 8px;
        overflow: hidden;
        width: 64px;
        height: 48px;
        background: #ece8df;
        cursor: pointer;
      }
      .ver.on {
        border-color: var(--sv-ink);
      }
      .ver img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .actions {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
        align-items: center;
      }
      .primary,
      .quiet {
        font: 600 14px/1 var(--sv-sans);
        padding: 11px 16px;
        border-radius: 10px;
        cursor: pointer;
      }
      .primary {
        border: 0;
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      .quiet {
        border: 1px solid var(--sv-rule);
        background: #fff;
        color: var(--sv-ink);
      }
      button:disabled {
        opacity: 0.45;
        cursor: default;
      }
      button:focus-visible {
        outline: 2px solid var(--sv-live);
        outline-offset: 2px;
      }
      .err {
        margin: 0;
        color: #b3261e;
        font-size: 13px;
      }
      .gallery {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
        gap: 10px;
      }
      .gi {
        display: grid;
        gap: 6px;
        padding: 6px;
        border-radius: 10px;
        border: 1px solid var(--sv-rule);
        background: #fff;
        cursor: pointer;
        text-align: left;
        font: 500 13px/1.2 var(--sv-sans);
        color: var(--sv-ink);
      }
      .gi img {
        width: 100%;
        aspect-ratio: 4 / 3;
        object-fit: cover;
        border-radius: 6px;
      }
    </style>
  </template>
}

class Fitted extends Component<typeof PictureQuestion> {
  <template>
    <div class='tf'><span class='icon'><ImageIcon
          width='18'
          height='18'
        /></span><b>{{@model.cardTitle}}</b></div>
    <style scoped>
      .tf {
        height: 100%;
        padding: 12px 14px;
        display: flex;
        gap: 10px;
        align-items: center;
        overflow: hidden;
        box-sizing: border-box;
        background: #fbfaf7;
        color: #1d1c1a;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
      }
      .icon {
        flex: none;
        width: 34px;
        height: 34px;
        border-radius: 9px;
        display: grid;
        place-items: center;
        background: #1d1c1a;
        color: #fbfaf7;
      }
      b {
        font-size: 14px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
    </style>
  </template>
}

export class PictureQuestion extends CardDef {
  static displayName = 'Picture It';
  static icon = ImageIcon;
  @field title = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PictureQuestion) {
      return this.title;
    },
  });
  @field brief = contains(TextAreaField); // what whoever asks wants to learn
  @field mode = contains(StringField); // describe | react
  @field prompt = contains(TextAreaField); // describe: what to describe ("a place that feels like you")
  @field subject = contains(StringField); // describe: what the picture is of, for the drawing ("a living room")
  @field look = contains(StringField); // photo | illustration | ui | abstract
  @field edits = contains(NumberField); // describe: how many changes they may make (0-4; default 2)
  @field editPrompt = contains(StringField); // describe: the nudge to change it
  @field seed = contains(TextAreaField); // react: the open scene to draw
  @field seedImage = contains(StringField); // react: or a picture to show instead
  @field questions = contains(TextAreaField); // react: one per line (1-3)
  static isolated = Isolated;
  static embedded = Fitted;
  static fitted = Fitted;
}

class ResponseView extends Component<typeof PictureResponse> {
  get d(): PictureData {
    return parseJson<PictureData>(this.args.model.data, emptyData);
  }
  get versions() {
    return this.d.versions.map((v, i) => ({ ...v, n: i + 1, at: secs(v.ms) }));
  }
  <template>
    <article class='pr'>
      <p class='k'>Picture it ·
        {{if @model.respondent @model.respondent 'Anonymous'}}</p>
      <p class='sum'>{{@model.summary}}</p>
      <ol class='vs'>
        {{#each this.versions as |v|}}
          <li><img src={{v.image}} alt='Version {{v.n}}' /><p><b>{{v.n}}.</b>
              “{{v.words}}”
              <span>{{v.at}}</span></p></li>
        {{/each}}
      </ol>
    </article>
    <style scoped>
      .pr {
        padding: clamp(16px, 4cqw, 36px);
        display: grid;
        gap: 14px;
        max-width: 900px;
        margin: 0 auto;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
        color: #1d1c1a;
        background: #fbfaf7;
        min-height: 100%;
        box-sizing: border-box;
      }
      .k {
        margin: 0;
        color: #6b675f;
        font-size: 13px;
      }
      .sum {
        margin: 0;
        line-height: 1.55;
        max-width: 70ch;
      }
      .vs {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
        gap: 12px;
      }
      .vs img {
        width: 100%;
        border-radius: 10px;
        background: #ece8df;
        display: block;
      }
      .vs p {
        margin: 6px 0 0;
        font-size: 13px;
        line-height: 1.4;
      }
      .vs span {
        color: #6b675f;
      }
    </style>
  </template>
}

class ResponseRow extends Component<typeof PictureResponse> {
  <template>
    <div class='rr'>{{#if @model.finalImage}}<img
          src={{@model.finalImage}}
          alt=''
        />{{/if}}<span>{{if
          @model.respondent
          @model.respondent
          'Anonymous'
        }}</span></div>
    <style scoped>
      .rr {
        height: 100%;
        display: flex;
        gap: 10px;
        align-items: center;
        padding: 8px 10px;
        box-sizing: border-box;
        overflow: hidden;
        background: #fbfaf7;
        font:
          500 13px/1.2 ui-sans-serif,
          system-ui,
          sans-serif;
      }
      img {
        width: 56px;
        height: 42px;
        object-fit: cover;
        border-radius: 6px;
        flex: none;
      }
    </style>
  </template>
}

export class PictureResponse extends CardDef {
  static displayName = 'Picture It Response';
  static icon = ImageIcon;
  @field question = linksTo(() => PictureQuestion);
  @field respondent = contains(StringField);
  @field takenAt = contains(StringField);
  @field data = contains(TextAreaField); // JSON: PictureData
  @field summary = contains(TextAreaField); // for the interviewer
  @field finalImage = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PictureResponse) {
      return `${this.respondent || 'Anonymous'} · ${this.question?.cardTitle ?? 'Picture it'}`;
    },
  });
  static isolated = ResponseView;
  static embedded = ResponseRow;
  static fitted = ResponseRow;
}

export { Isolated as PictureTool };
