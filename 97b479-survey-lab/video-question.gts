// A video question: instead of "rate this video 1–5", the viewer just
// watches. With their camera on, their own device reads where they look and
// how their face moves (measured against their own resting face; no image is
// kept or sent), then an interviewer asks about the two or three moments that
// stood out, and the whole thing becomes a Video Response with a readout on
// how to sell to this person. Camera off still works: answers only.
import {
  CardDef,
  Component,
  field,
  contains,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import VideoIcon from '@cardstack/boxel-icons/video';
import WriteBinaryFileCommand from '@cardstack/boxel-host/tools/write-binary-file';
import { ReactionTimeline } from './reaction';
import {
  loadMarker,
  read,
  fitGaze,
  DOTS,
  baselineOf,
  binSamples,
  findMoments,
  clock,
  KIND_WORDS,
} from './face-signals';
import type { Reading, Sample, GazeFit, Bin, Moment } from './face-signals';
import { writeFollowUps, writeReadout } from './survey-ai';
import type { FollowUp, Readout } from './survey-ai';
import {
  videoBlobUrl,
  grabFrames,
  parse,
  inPrerender,
  blobToBase64,
} from './media';
import { hostOf, type ToolHost } from './tool-kit';

// @ts-ignore import.meta is fine here (the host loads cards as ES modules); the catalog's CommonJS type check rejects it
const here: string = import.meta.url;

type Step =
  | 'intro'
  | 'starting'
  | 'calibrate'
  | 'ready'
  | 'watch'
  | 'thinking'
  | 'ask'
  | 'saving'
  | 'done';

// what the interviewer reads back: how they watched, the moments, their own
// words, and the readout's gist
export function videoSummary(o: {
  camera: boolean;
  calibrated: boolean;
  duration: number;
  followUps: FollowUp[];
  readout: Readout | null;
  pauses: number[];
}) {
  const how = o.camera
    ? `with the camera on${o.calibrated ? ' (gaze calibrated)' : ' (face only, no gaze)'}`
    : 'without the camera (answers only)';
  const moments = o.followUps
    .map(
      (f) =>
        `${clock(f.t)}${f.kind !== 'pick' ? ` (${KIND_WORDS[f.kind as keyof typeof KIND_WORDS] ?? f.kind})` : ''}: asked "${f.question}" → ${f.answer ? `"${f.answer}"` : 'skipped'}`,
    )
    .join('; ');
  const r = o.readout;
  const gist = r
    ? ` Readout: ${r.headline}${r.landed?.length ? ` Landed: ${r.landed.join('; ')}.` : ''}${r.lost?.length ? ` Lost them: ${r.lost.join('; ')}.` : ''}`
    : '';
  return `Watched the ${Math.round(o.duration)} s video ${how}${o.pauses.length ? `, pausing ${o.pauses.length}×` : ''}. ${moments || 'No follow-up questions.'}${gist}`;
}

const SETTLE = 700; // ms for the eyes to land on a dot
const HOLD = 1000; // ms of readings per dot
const REST = 2000; // ms of resting face at the start

class Isolated extends Component<typeof VideoQuestion> {
  @tracked tab: 'take' | 'results' = 'take';
  @tracked step: Step = 'intro';
  @tracked src = '';
  @tracked note = '';
  @tracked error = '';
  @tracked name = '';
  @tracked camera = false;
  @tracked calibrated = false;
  @tracked dot = -1; // which calibration dot is showing (-1: the resting one in the middle)
  @tracked dotLive = false;
  @tracked paused = false;
  @tracked faceSeen = false;
  @tracked followUps: FollowUp[] = [];
  @tracked frames: string[] = [];
  @tracked qIndex = 0;
  @tracked draft = '';
  @tracked readout: Readout | null = null;
  @tracked responseId = '';
  @tracked uploading = '';

  stage: HTMLVideoElement | null = null;
  cam: HTMLVideoElement | null = null;
  stream: MediaStream | null = null;
  marker: any = null;
  raf = 0;
  lastRead = 0;
  samples: Sample[] = [];
  calRows: number[][] = [];
  calX: number[] = [];
  calY: number[] = [];
  rest: Reading[] = [];
  pauses: number[] = [];
  fit: GazeFit | null = null;
  bins: Bin[] = [];
  moments: Moment[] = [];
  private loadedFor = '';
  private alive = true;

  // inside an interview: no name to ask, no results tab; the camera stays opt-in
  get host(): ToolHost | undefined {
    return hostOf(this.args);
  }
  constructor(owner: any, args: any) {
    super(owner, args);
    const h = hostOf(args);
    if (h) this.name = h.respondent ?? '';
  }

  willDestroy() {
    super.willDestroy();
    this.alive = false;
    this.stopCamera();
  }

  get ctx() {
    return (
      (this.args.context as any)?.toolContext ??
      (this.args.context as any)?.commandContext
    );
  }
  get videoUrl() {
    const f = this.args.model.videoFile;
    return f ? new URL(f, (this.args.model as any).id ?? here).href : '';
  }
  get duration() {
    return this.stage?.duration || 0;
  }

  // ─── the video ────────────────────────────────────────────────────────
  load = modifier((_el: Element, [url]: [string]) => {
    if (inPrerender() || !url || this.loadedFor === url) return;
    this.loadedFor = url;
    this.note = 'Loading the video…';
    videoBlobUrl(
      url,
      (f) => (this.note = `Loading the video… ${Math.round(f * 100)}%`),
    )
      .then((src) => {
        if (!this.alive) return;
        this.src = src;
        this.note = '';
      })
      .catch((e) => (this.note = String(e?.message ?? e)));
  });
  registerStage = modifier((el: HTMLVideoElement) => {
    this.stage = el;
    const ended = () => this.finishWatching();
    const pause = () => {
      if (this.step === 'watch' && !el.ended) {
        this.paused = true;
        this.pauses.push(Math.round(el.currentTime * 4) / 4);
      }
    };
    const play = () => (this.paused = false);
    el.addEventListener('ended', ended);
    el.addEventListener('pause', pause);
    el.addEventListener('play', play);
    return () => {
      el.removeEventListener('ended', ended);
      el.removeEventListener('pause', pause);
      el.removeEventListener('play', play);
    };
  });
  registerCam = modifier((el: HTMLVideoElement) => {
    this.cam = el;
    if (this.stream && el.srcObject !== this.stream) {
      el.srcObject = this.stream;
      el.play().catch(() => {});
    }
  });

  // ─── starting ─────────────────────────────────────────────────────────
  setName = (e: Event) => (this.name = (e.target as HTMLInputElement).value);

  startWithCamera = async () => {
    this.error = '';
    this.step = 'starting';
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { width: 640, height: 480, facingMode: 'user' },
        audio: false,
      });
      if (this.cam) {
        this.cam.srcObject = this.stream;
        await this.cam.play();
      }
      this.marker = await loadMarker();
      if (!this.alive) return;
      this.camera = true;
      this.loop();
      this.calibrate();
    } catch (e: any) {
      this.stopCamera();
      this.camera = false;
      this.step = 'intro';
      this.error =
        e?.name === 'NotAllowedError'
          ? 'Camera access was declined. You can still take part without it.'
          : `The camera did not start (${e?.message ?? e}). You can still take part without it.`;
    }
  };
  startWithoutCamera = () => {
    this.error = '';
    this.camera = false;
    this.step = 'ready';
  };

  private stopCamera() {
    cancelAnimationFrame(this.raf);
    this.raf = 0;
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    if (this.cam) this.cam.srcObject = null;
  }

  // one loop reads the face ~15 times a second, whatever step we are on
  private loop = () => {
    // eslint-disable-next-line @cardstack/boxel/no-raf-for-state -- the face reader's frame loop
    this.raf = requestAnimationFrame(this.loop);
    const now = performance.now();
    if (
      !this.marker ||
      !this.cam ||
      this.cam.readyState < 2 ||
      now - this.lastRead < 66
    )
      return;
    this.lastRead = now;
    let r: Reading | null = null;
    try {
      r = document.hidden ? null : read(this.marker, this.cam, now);
    } catch {
      r = null;
    }
    if (Boolean(r) !== this.faceSeen) this.faceSeen = Boolean(r);
    if (this.step === 'calibrate' && r) {
      if (this.dot === -1 && this.dotLive) this.rest.push(r);
      if (this.dot >= 0 && this.dotLive) {
        this.calRows.push(r.feat);
        this.calX.push(DOTS[this.dot][0]);
        this.calY.push(DOTS[this.dot][1]);
      }
    }
    if (this.step === 'watch' && this.stage && !this.stage.paused) {
      this.samples.push({ t: this.stage.currentTime, r });
    }
  };

  private wait(ms: number) {
    return new Promise((res) => setTimeout(res, ms));
  }

  private async calibrate() {
    this.step = 'calibrate';
    this.rest = [];
    this.calRows = [];
    this.calX = [];
    this.calY = [];
    this.dot = -1;
    this.dotLive = false;
    await this.wait(900);
    this.dotLive = true;
    await this.wait(REST);
    for (let i = 0; i < DOTS.length; i++) {
      if (!this.alive || this.step !== 'calibrate') return;
      this.dotLive = false;
      this.dot = i;
      await this.wait(SETTLE);
      this.dotLive = true;
      await this.wait(HOLD);
    }
    this.dotLive = false;
    this.fit = fitGaze(this.calRows, this.calX, this.calY);
    this.calibrated = Boolean(this.fit);
    this.step = 'ready';
  }
  skipCalibration = () => {
    this.step = 'ready';
    this.calibrated = false;
    this.fit = null;
  };

  get dotStyle() {
    const [x, y] = this.dot < 0 ? [0.5, 0.5] : DOTS[this.dot];
    return htmlSafe(`left:${x * 100}%;top:${y * 100}%`);
  }
  get dotCount() {
    return this.dot < 0
      ? 'Relax and look at the dot'
      : `Follow the dot · ${this.dot + 1} of ${DOTS.length}`;
  }

  // ─── watching ─────────────────────────────────────────────────────────
  play = async () => {
    if (!this.stage) return;
    this.samples = [];
    this.pauses = [];
    this.stage.currentTime = 0;
    this.step = 'watch';
    try {
      await this.stage.play();
    } catch {
      this.paused = true;
    }
  };
  togglePause = () => {
    if (!this.stage || this.step !== 'watch') return;
    if (this.stage.paused) this.stage.play();
    else this.stage.pause();
  };

  private async finishWatching() {
    if (this.step !== 'watch') return;
    this.step = 'thinking';
    this.error = '';
    const d = this.duration || 30;
    const base = baselineOf(
      this.rest.length
        ? this.rest
        : (this.samples
            .filter((s) => s.r)
            .slice(0, 20)
            .map((s) => s.r) as Reading[]),
    );
    this.bins = this.camera ? binSamples(this.samples, d, this.fit, base) : [];
    this.moments = findMoments(this.bins, this.pauses, d);
    try {
      this.frames = await grabFrames(
        this.src,
        this.moments.map((m) => m.t),
        960,
      );
    } catch {
      this.frames = [];
    }
    try {
      this.followUps = await writeFollowUps(
        this.ctx,
        this.args.model.brief ?? '',
        this.moments,
        this.frames,
      );
    } catch {
      this.followUps = this.moments.map((m) => ({
        t: m.t,
        kind: m.kind,
        question: `What was going through your mind around ${clock(m.t)}?`,
        answer: '',
      }));
    }
    this.qIndex = 0;
    this.draft = '';
    this.showMoment();
    this.step = 'ask';
  }

  // ─── the follow-up questions ──────────────────────────────────────────
  get current() {
    return this.followUps[this.qIndex];
  }
  get currentTime() {
    return this.current ? clock(this.current.t) : '';
  }
  get currentWhy() {
    const k = this.current?.kind as keyof typeof KIND_WORDS;
    return k === 'pick' ? '' : (KIND_WORDS[k] ?? '');
  }
  get progress() {
    return `${this.qIndex + 1} of ${this.followUps.length}`;
  }
  get isLast() {
    return this.qIndex >= this.followUps.length - 1;
  }
  private showMoment() {
    if (this.stage && this.current) {
      this.stage.pause();
      this.stage.currentTime = this.current.t;
    }
  }
  setDraft = (e: Event) =>
    (this.draft = (e.target as HTMLTextAreaElement).value);
  next = (skip = false) => {
    const list = [...this.followUps];
    list[this.qIndex] = {
      ...list[this.qIndex],
      answer: skip ? '' : this.draft.trim(),
    };
    this.followUps = list;
    this.draft = '';
    if (this.isLast) {
      this.save();
      return;
    }
    this.qIndex++;
    this.showMoment();
  };
  answer = () => this.next(false);
  skip = () => this.next(true);

  private async save() {
    this.step = 'saving';
    this.error = '';
    const d = this.duration || 30;
    try {
      this.readout = await writeReadout(
        this.ctx,
        this.args.model.brief ?? '',
        this.bins,
        d,
        this.followUps,
        this.frames,
        this.camera,
      );
    } catch (e: any) {
      this.readout = null;
      this.error = `The readout could not be written (${e?.message ?? e}); the response is saved without it.`;
    }
    const summary = videoSummary({
      camera: this.camera,
      calibrated: this.calibrated,
      duration: d,
      followUps: this.followUps,
      readout: this.readout,
      pauses: this.pauses,
    });
    const doc = {
      data: {
        type: 'card',
        attributes: {
          respondent: this.name.trim() || null,
          takenAt: new Date().toISOString(),
          camera: this.camera,
          calibrated: this.calibrated,
          duration: Math.round(d * 100) / 100,
          bins: JSON.stringify(this.bins),
          followUps: JSON.stringify(this.followUps),
          readout: this.readout ? JSON.stringify(this.readout) : null,
          summary,
        },
        relationships: {
          question: { links: { self: (this.args.model as any).id } },
        },
        meta: {
          adoptsFrom: {
            module: new URL('./video-response', here).href,
            name: 'VideoResponse',
          },
        },
      },
    };
    try {
      const store = (this.args.context as any)?.store;
      if (!store?.create)
        throw new Error(
          'this view cannot save cards; open the question from its workspace',
        );
      const id = await store.create(doc as any, {
        realm: this.args.model[realmURL]?.href,
      });
      if (typeof id !== 'string')
        throw new Error(
          (id as any)?.message ?? 'the response could not be saved',
        );
      this.responseId = id;
    } catch (e: any) {
      this.error = `Saving failed: ${e?.message ?? e}`;
    }
    this.stopCamera();
    this.step = 'done';
    this.host?.done({ summary, responseId: this.responseId });
  }
  openResponse = () => {
    if (this.responseId)
      this.args.viewCard?.(new URL(this.responseId) as any, 'isolated');
  };
  again = () => {
    this.stopCamera();
    this.readout = null;
    this.responseId = '';
    this.followUps = [];
    this.camera = false;
    this.calibrated = false;
    this.fit = null;
    this.step = 'intro';
    if (this.stage) this.stage.currentTime = 0;
  };

  // ─── results (for whoever asked) ──────────────────────────────────────
  get realms() {
    const r = this.args.model[realmURL];
    return r ? [r.href] : [];
  }
  responsesQuery = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: {
            module: new URL('./video-response', here).href,
            name: 'VideoResponse',
          },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  get responses(): any[] {
    const id = (this.args.model as any).id;
    return ((this.responsesQuery?.instances ?? []) as any[]).filter(
      (r) => r.question?.id === id,
    );
  }
  get responseCount() {
    return this.responses.length;
  }
  get averageBins(): Bin[] {
    const sets = this.responses
      .filter((r) => r.camera)
      .map((r) => parse<Bin[]>(r.bins, []));
    if (!sets.length) return [];
    const n = Math.max(...sets.map((s) => s.length));
    const out: Bin[] = [];
    for (let i = 0; i < n; i++) {
      const at = sets.map((s) => s[i]).filter(Boolean);
      const avg = (f: (b: Bin) => number) =>
        at.reduce((a, b) => a + f(b), 0) / at.length;
      const gazeSets = at.filter((b) => b.on !== null);
      out.push({
        t: at[0].t,
        face: avg((b) => b.face),
        on: gazeSets.length
          ? gazeSets.reduce((a, b) => a + (b.on ?? 0), 0) / gazeSets.length
          : null,
        gx: null,
        gy: null,
        smile: avg((b) => b.smile),
        surprise: avg((b) => b.surprise),
        frown: avg((b) => b.frown),
      });
    }
    return out;
  }
  get averageDuration() {
    const r = this.responses.find((x) => x.duration);
    return r?.duration ?? 0;
  }
  get averagePins() {
    return this.responses
      .flatMap((r) => parse<FollowUp[]>(r.followUps, []))
      .filter((f) => f.kind !== 'pick')
      .map((f) => ({
        t: f.t,
        label: KIND_WORDS[f.kind as keyof typeof KIND_WORDS] ?? f.kind,
      }));
  }
  get cameraCount() {
    return this.responses.filter((r) => r.camera).length;
  }
  showTake = () => (this.tab = 'take');
  showResults = () => (this.tab = 'results');
  open = (card: any) => this.args.viewCard?.(card, 'isolated');

  // swap in a new video (saved into this workspace through the card, since
  // the command line can garble big binaries)
  upload = async (e: Event) => {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    if (!this.ctx) {
      this.error =
        'This view cannot save files. Open the card from its workspace.';
      return;
    }
    this.uploading = `Saving ${file.name}…`;
    try {
      const safe = file.name.toLowerCase().replace(/[^a-z0-9.]+/g, '-');
      const written = await new WriteBinaryFileCommand(this.ctx).execute({
        realm: this.args.model[realmURL]?.href,
        path: `Videos/${safe}`,
        base64Content: await blobToBase64(file),
        contentType: file.type || 'video/mp4',
        useNonConflictingFilename: true,
      } as any);
      const url: string = (written as any)?.fileIdentifier ?? '';
      const realm = this.args.model[realmURL]?.href ?? '';
      if (!url) throw new Error('the file was not saved');
      this.args.model.videoFile = url.startsWith(realm)
        ? `../${url.slice(realm.length)}`
        : url;
      this.uploading = '';
    } catch (err: any) {
      this.uploading = '';
      this.error = `Upload failed: ${err?.message ?? err}`;
    }
  };

  <template>
    <article
      class='sv vq {{if this.host "hosted"}}'
      {{this.load this.videoUrl}}
    >
      <header class='top'>
        <div>
          <p class='kicker'>Video question</p>
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
          >Results · {{this.responseCount}}</button>
        </nav>
      </header>

      <div class='take {{if (eq this.tab "take") "show"}}'>
        <div class='stage'>
          {{#if this.src}}
            {{! the viewer pauses by clicking the picture; the same is on the Pause button below }}
            {{! template-lint-disable no-invalid-interactive }}
            {{! the demo videos carry their own on-screen captions }}
            {{! template-lint-disable require-media-caption }}
            <video
              src={{this.src}}
              playsinline
              preload='auto'
              class='film {{if (eq this.step "calibrate") "dim"}}'
              {{this.registerStage}}
              {{on 'click' this.togglePause}}
            ></video>
          {{else}}
            <p class='loading'>{{if
                this.note
                this.note
                'No video yet. Add one under Results.'
              }}</p>
          {{/if}}
          {{#if (eq this.step 'calibrate')}}
            <div class='cal'>
              <span
                class='dot {{if this.dotLive "live"}}'
                style={{this.dotStyle}}
              ></span>
              <p class='calnote'>{{this.dotCount}}</p>
            </div>
          {{/if}}
          {{#if this.camera}}
            <div class='camtag {{if this.faceSeen "ok"}}'>
              <span class='pulse'></span>{{if
                this.faceSeen
                'Measuring on this device'
                'Looking for your face…'
              }}
            </div>
          {{/if}}
          {{! the viewer's own camera, shown only while calibrating; no sound }}
          {{! template-lint-disable require-media-caption }}
          <video
            class='self {{if (eq this.step "calibrate") "show"}}'
            muted
            playsinline
            aria-hidden='true'
            {{this.registerCam}}
          ></video>
        </div>

        <section class='panel'>
          {{#if (eq this.step 'intro')}}
            <p class='lead'>Watch a short video. With your camera on, we can see
              which moments land for you, measured on your own device. No
              picture of your face is kept or sent, only a few numbers per
              moment. Then we ask two or three quick questions.</p>
            {{#unless this.host}}
              <label class='field'>
                <span>Your first name or a nickname (optional)</span>
                <input
                  type='text'
                  value={{this.name}}
                  autocomplete='given-name'
                  {{on 'input' this.setName}}
                />
              </label>
            {{/unless}}
            <div class='actions'>
              <button
                type='button'
                class='primary'
                disabled={{if this.src false true}}
                {{on 'click' this.startWithCamera}}
              >Start with camera</button>
              <button
                type='button'
                class='quiet'
                disabled={{if this.src false true}}
                {{on 'click' this.startWithoutCamera}}
              >Watch without camera</button>
            </div>
          {{else if (eq this.step 'starting')}}
            <p class='lead'>Starting the camera and the face reader…</p>
          {{else if (eq this.step 'calibrate')}}
            <p class='lead'>About 12 seconds. Keep your head comfortable and
              follow the dot with your eyes.</p>
            <div class='actions'><button
                type='button'
                class='quiet'
                {{on 'click' this.skipCalibration}}
              >Skip (face only, no gaze)</button></div>
          {{else if (eq this.step 'ready')}}
            <p class='lead'>
              {{#if this.camera}}
                {{if
                  this.calibrated
                  'All set.'
                  'Face only: the calibration did not take, so we will skip where you look.'
                }}
              {{/if}}
              The video plays with sound. Click it to pause if you like; pauses
              count too.
            </p>
            <div class='actions'><button
                type='button'
                class='primary'
                {{on 'click' this.play}}
              >Play</button></div>
          {{else if (eq this.step 'watch')}}
            <div class='actions'>
              <button
                type='button'
                class='quiet'
                {{on 'click' this.togglePause}}
              >{{if this.paused 'Resume' 'Pause'}}</button>
            </div>
          {{else if (eq this.step 'thinking')}}
            <p class='lead'>Picking a few moments to ask you about…</p>
          {{else if (eq this.step 'ask')}}
            <div class='ask'>
              <p class='qmeta'><span
                  class='time'
                >{{this.currentTime}}</span>{{#if this.currentWhy}}
                  ·
                  {{this.currentWhy}}{{/if}}
                ·
                {{this.progress}}</p>
              <p class='question'>{{this.current.question}}</p>
              <textarea
                rows='3'
                aria-label='Your answer'
                value={{this.draft}}
                {{on 'input' this.setDraft}}
              ></textarea>
              <div class='actions'>
                <button
                  type='button'
                  class='primary'
                  {{on 'click' this.answer}}
                >{{if this.isLast 'Finish' 'Next'}}</button>
                <button
                  type='button'
                  class='quiet'
                  {{on 'click' this.skip}}
                >Skip</button>
              </div>
            </div>
          {{else if (eq this.step 'saving')}}
            <p class='lead'>Writing it up…</p>
          {{else if (eq this.step 'done')}}
            <div class='done'>
              {{#if this.readout.label}}<p
                  class='badge'
                >{{this.readout.label}}</p>{{/if}}
              <p class='lead'>{{if
                  this.readout.headline
                  this.readout.headline
                  'Thanks, your response is saved.'
                }}</p>
              <div class='actions'>
                {{#if this.responseId}}<button
                    type='button'
                    class='primary'
                    {{on 'click' this.openResponse}}
                  >Open the full response</button>{{/if}}
                <button
                  type='button'
                  class='quiet'
                  {{on 'click' this.again}}
                >Take it again</button>
              </div>
            </div>
          {{/if}}
          {{#if this.error}}<p
              class='err'
              role='alert'
            >{{this.error}}</p>{{/if}}
        </section>
      </div>

      {{#if (eq this.tab 'results')}}
        <section class='results'>
          {{#if @model.brief}}<p class='brief'><b>What we want to learn</b>
              {{@model.brief}}</p>{{/if}}
          {{#if this.responseCount}}
            <p class='sum'>{{this.responseCount}}
              {{if (eq this.responseCount 1) 'response' 'responses'}}
              ·
              {{this.cameraCount}}
              with the camera on. The lanes average everyone with the camera on;
              the dark pins are the moments people were asked about.</p>
            {{#if this.averageBins.length}}
              <ReactionTimeline
                @bins={{this.averageBins}}
                @duration={{this.averageDuration}}
                @pins={{this.averagePins}}
                @camera={{true}}
              />
            {{/if}}
            <ul class='list'>
              {{#each this.responses as |r|}}
                <li><button
                    type='button'
                    class='rowbtn'
                    {{on 'click' (fn this.open r)}}
                  >{{r.cardTitle}}</button></li>
              {{/each}}
            </ul>
          {{else}}
            <p class='sum'>No responses yet. Take it yourself to see what one
              looks like.</p>
          {{/if}}
          <div class='owner'>
            <label class='upload'>
              <span>{{if
                  this.uploading
                  this.uploading
                  'Replace the video…'
                }}</span>
              <input
                type='file'
                accept='video/mp4,video/webm,video/quicktime'
                {{on 'change' this.upload}}
              />
            </label>
            {{#if this.error}}<p
                class='err'
                role='alert'
              >{{this.error}}</p>{{/if}}
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
        --sv-att: #2f7d74;
        --sv-smile: #d48a1a;
        --sv-surprise: #7a55c9;
        --sv-frown: #4a6a9a;
        --sv-sans:
          ui-sans-serif, -apple-system, 'Segoe UI', system-ui, sans-serif;
        --sv-mono: ui-monospace, 'SF Mono', Menlo, monospace;
        container-type: inline-size;
        background: var(--sv-paper);
        color: var(--sv-ink);
        font-family: var(--sv-sans);
        box-sizing: border-box;
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
      .vq {
        min-height: 100%;
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 20px;
        align-content: start;
        max-width: 1040px;
        margin: 0 auto;
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
      .take {
        display: none;
        gap: 16px;
      }
      .take.show {
        display: grid;
      }
      .stage {
        position: relative;
        aspect-ratio: 16 / 9;
        background: #0e0e0d;
        border-radius: 14px;
        overflow: hidden;
        display: grid;
        place-items: center;
      }
      .film {
        width: 100%;
        height: 100%;
        object-fit: contain;
        display: block;
        cursor: pointer;
        transition: opacity 0.4s;
      }
      .film.dim {
        opacity: 0.12;
      }
      .loading {
        color: #bbb;
        font-size: 14px;
      }
      .cal {
        position: absolute;
        inset: 0;
      }
      .dot {
        position: absolute;
        width: 22px;
        height: 22px;
        margin: -11px 0 0 -11px;
        border-radius: 50%;
        background: var(--sv-live);
        box-shadow: 0 0 0 6px rgba(226, 85, 59, 0.25);
        transition:
          left 0.5s cubic-bezier(0.2, 0.8, 0.2, 1),
          top 0.5s cubic-bezier(0.2, 0.8, 0.2, 1),
          transform 0.2s;
        transform: scale(1.25);
      }
      .dot.live {
        transform: scale(0.7);
      }
      .calnote {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 14px;
        margin: 0;
        text-align: center;
        color: #eee;
        font-size: 13px;
      }
      .camtag {
        position: absolute;
        top: 12px;
        left: 12px;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 6px 10px;
        border-radius: 999px;
        background: rgba(0, 0, 0, 0.55);
        color: #f2f2f2;
        font-size: 12px;
        pointer-events: none;
      }
      .pulse {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: #999;
      }
      .camtag.ok .pulse {
        background: var(--sv-live);
        animation: pulse 1.6s ease-in-out infinite;
      }
      @keyframes pulse {
        50% {
          opacity: 0.35;
        }
      }
      .self {
        position: absolute;
        right: 12px;
        bottom: 12px;
        width: 18%;
        aspect-ratio: 4 / 3;
        object-fit: cover;
        border-radius: 8px;
        transform: scaleX(-1);
        opacity: 0;
        pointer-events: none;
        transition: opacity 0.3s;
      }
      .self.show {
        opacity: 0.85;
      }
      .panel {
        display: grid;
        gap: 12px;
        padding: 18px 20px;
        border-radius: 14px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .lead {
        margin: 0;
        font-size: 15px;
        line-height: 1.55;
        max-width: 68ch;
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
        border-radius: 9px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-paper);
        color: var(--sv-ink);
      }
      input[type='text']:focus-visible,
      textarea:focus-visible {
        outline: 2px solid var(--sv-ink);
        outline-offset: 1px;
      }
      .actions {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
      }
      .primary,
      .quiet {
        font: 600 14px/1 var(--sv-sans);
        padding: 11px 16px;
        border-radius: 9px;
        cursor: pointer;
      }
      .primary {
        border: 0;
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      .primary:hover {
        background: #000;
      }
      .quiet {
        border: 1px solid var(--sv-rule);
        background: transparent;
        color: var(--sv-ink);
      }
      .quiet:hover {
        border-color: var(--sv-ink);
      }
      button:disabled {
        opacity: 0.4;
        cursor: default;
      }
      button:focus-visible {
        outline: 2px solid var(--sv-live);
        outline-offset: 2px;
      }
      .ask {
        display: grid;
        gap: 10px;
      }
      .qmeta {
        margin: 0;
        color: var(--sv-muted);
        font-size: 13px;
      }
      .time {
        font-family: var(--sv-mono);
        color: var(--sv-ink);
        font-weight: 600;
      }
      .question {
        margin: 0;
        font: 600 18px/1.4 var(--sv-sans);
        max-width: 60ch;
      }
      .badge {
        justify-self: start;
        margin: 0;
        padding: 4px 10px;
        border-radius: 999px;
        background: var(--sv-ink);
        color: var(--sv-paper);
        font: 600 12px/1.4 var(--sv-sans);
      }
      .done {
        display: grid;
        gap: 12px;
      }
      .err {
        margin: 0;
        color: #b3261e;
        font-size: 13px;
      }
      .results {
        display: grid;
        gap: 16px;
      }
      .brief,
      .sum {
        margin: 0;
        line-height: 1.5;
        max-width: 72ch;
      }
      .brief b {
        margin-right: 6px;
      }
      .sum {
        color: var(--sv-muted);
        font-size: 14px;
      }
      .list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 6px;
      }
      .rowbtn {
        width: 100%;
        text-align: left;
        padding: 10px 12px;
        border-radius: 9px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-panel);
        font: 500 14px/1.3 var(--sv-sans);
        color: var(--sv-ink);
        cursor: pointer;
      }
      .rowbtn:hover {
        border-color: var(--sv-ink);
      }
      .owner {
        border-top: 1px solid var(--sv-rule);
        padding-top: 14px;
        display: grid;
        gap: 8px;
      }
      .upload {
        font-size: 13px;
        color: var(--sv-muted);
        cursor: pointer;
      }
      .upload input {
        display: block;
        margin-top: 6px;
        font-size: 13px;
      }
    </style>
  </template>
}

class Fitted extends Component<typeof VideoQuestion> {
  <template>
    <div class='sv vf'>
      <span class='icon'><VideoIcon width='18' height='18' /></span>
      <div class='txt'>
        <b>{{@model.cardTitle}}</b>
        <span>Video question</span>
      </div>
    </div>
    <style scoped>
      .sv {
        --sv-paper: #fbfaf7;
        --sv-ink: #1d1c1a;
        --sv-muted: #6b675f;
        --sv-live: #e2553b;
        background: var(--sv-paper);
        color: var(--sv-ink);
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
        box-sizing: border-box;
      }
      .vf {
        height: 100%;
        padding: 12px 14px;
        display: flex;
        gap: 10px;
        align-items: center;
        overflow: hidden;
      }
      .icon {
        flex: none;
        width: 34px;
        height: 34px;
        border-radius: 9px;
        display: grid;
        place-items: center;
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      .txt {
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
        color: var(--sv-muted);
      }
    </style>
  </template>
}

export class VideoQuestion extends CardDef {
  static displayName = 'Video Question';
  static icon = VideoIcon;
  @field title = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: VideoQuestion) {
      return this.title;
    },
  });
  @field brief = contains(TextAreaField); // what whoever asks wants to learn
  @field videoFile = contains(StringField); // relative to this card, e.g. ../Videos/clip.mp4
  static isolated = Isolated;
  static embedded = Fitted;
  static fitted = Fitted;
}

export { Isolated as VideoTool };
