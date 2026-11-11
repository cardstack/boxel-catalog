/**
 * THE SOUND, AND THE CLOCK THE PICTURE FOLLOWS.
 *
 * Two ways to play a mix, so it always starts on the first tap and is exact
 * once it can be:
 *
 *   STREAM  an <audio> element, preloaded from the moment the page opens. It
 *           starts at once, even before the whole file is here; the picture
 *           follows its position (smoothed between its coarse updates).
 *   EXACT   the whole mix decoded into Web Audio, which schedules it sample
 *           by sample. The picture follows the context's clock minus the
 *           device's output latency, so lyrics and the dot land on what you
 *           hear. When the decode finishes during playback, the sound hands
 *           over from the stream to this, at the same song time.
 *
 * A phone only lets sound start inside a tap, and iOS mutes Web Audio on
 * the silent switch unless the session is marked as playback: `unlock()` is
 * called from the tap, before anything awaits.
 */
import type { Lang } from './song-clock';

type SessionNavigator = Navigator & { audioSession?: { type: string } };

export class Sound {
  private ctx?: AudioContext;
  private buffers: Partial<Record<Lang, Promise<AudioBuffer>>> = {};
  private decoded: Partial<Record<Lang, AudioBuffer>> = {};
  private streams: Partial<Record<Lang, HTMLAudioElement>> = {};
  private voice?: AudioBufferSourceNode;
  private stream?: HTMLAudioElement;
  /** EXACT: context time the voice starts at, and the song time it starts from */
  private startCtx = 0;
  private startSong = 0;
  /** STREAM: the element's last reported position and when it was seen */
  private seenAt = 0;
  private seenPos = 0;
  private run = 0;
  playing = false;
  mode: 'idle' | 'stream' | 'exact' = 'idle';
  /** the last thing that went wrong, for the debug readout */
  error = '';
  /** told when the mix on screen can start */
  onReady?: () => void;

  private born = performance.now();

  private url: (lang: Lang) => string;
  lang: Lang;

  constructor(url: (lang: Lang) => string, lang: Lang) {
    this.url = url;
    this.lang = lang;
    window.setTimeout(() => this.onReady?.(), 6100);
  }

  private context(): AudioContext {
    this.ctx ??= new AudioContext({ latencyHint: 'playback' });
    return this.ctx;
  }

  /** everything the context plays goes through here, so it can be muted */
  private gain?: GainNode;
  muted = false;

  private out(): AudioNode {
    const ctx = this.context();
    if (!this.gain) {
      this.gain = ctx.createGain();
      this.gain.connect(ctx.destination);
    }
    this.gain.gain.value = this.muted ? 0 : 1;
    return this.gain;
  }

  setMuted(muted: boolean): void {
    this.muted = muted;
    if (this.gain) this.gain.gain.value = muted ? 0 : 1;
    for (const el of Object.values(this.streams))
      if (el && !el.paused) el.muted = muted;
  }

  /** the streaming element for a mix, created (and preloading) once */
  element(lang: Lang): HTMLAudioElement {
    let el = this.streams[lang];
    if (!el) {
      el = new Audio();
      el.preload = 'auto';
      el.addEventListener('canplay', () => this.onReady?.());
      el.src = this.url(lang);
      el.load();
      this.streams[lang] = el;
    }
    return el;
  }

  /** start fetching everything for a mix now: its stream and its decode */
  preload(lang: Lang): void {
    this.element(lang);
    void this.load(lang).catch(() => {});
  }

  /** from a tap, before anything awaits */
  unlock(): void {
    const nav = navigator as SessionNavigator;
    if (nav.audioSession) nav.audioSession.type = 'playback';
    void this.context().resume();
    // a muted play-and-pause inside the gesture lets the stream start later
    const el = this.element(this.lang);
    if (el.paused && !this.playing) {
      el.muted = true;
      void el
        .play()
        .then(() => {
          if (this.mode !== 'stream') el.pause();
          el.muted = this.muted;
        })
        .catch(() => (el.muted = this.muted));
    }
  }

  load(lang: Lang): Promise<AudioBuffer> {
    return (this.buffers[lang] ??= fetch(this.url(lang))
      .then((r) => r.arrayBuffer())
      .then((b) => this.context().decodeAudioData(b))
      .then((buf) => {
        this.decoded[lang] = buf;
        this.onReady?.();
        // decoded while streaming: hand over to the exact clock
        if (this.playing && this.mode === 'stream' && lang === this.lang)
          this.handOver();
        return buf;
      })
      .catch((e) => {
        this.error = `decode ${String(e)}`;
        delete this.buffers[lang];
        throw e;
      }));
  }

  /** enough of the mix on screen is here to start playing it */
  canStart(): boolean {
    return (
      !!this.decoded[this.lang] ||
      (this.streams[this.lang]?.readyState ?? 0) >= 3 ||
      // iOS won't preload a stream before a tap: never keep the controls
      // asleep for long, the stream starts on the tap anyway
      performance.now() - this.born > 6000
    );
  }

  /** seconds between a sample being played and being heard */
  private latency(): number {
    const ctx = this.ctx;
    if (!ctx) return 0;
    return (ctx.outputLatency || 0) + (ctx.baseLatency || 0);
  }

  /** play from song time t, in this.lang: exact if decoded, else stream */
  start(t: number): void {
    this.silence();
    this.run++;
    this.playing = true;
    const buffer = this.decoded[this.lang];
    if (buffer) this.startExact(buffer, t);
    else this.startStream(t);
  }

  private startExact(buffer: AudioBuffer, t: number, lead = 0.04): void {
    const ctx = this.context();
    void ctx.resume();
    const voice = ctx.createBufferSource();
    voice.buffer = buffer;
    voice.connect(this.out());
    this.startCtx = ctx.currentTime + lead;
    this.startSong = t;
    voice.start(this.startCtx, Math.min(t, buffer.duration));
    this.voice = voice;
    this.mode = 'exact';
  }

  private startStream(t: number): void {
    const el = this.element(this.lang);
    el.muted = this.muted;
    el.currentTime = t;
    this.seenPos = t;
    this.seenAt = performance.now();
    this.startSong = t;
    this.stream = el;
    this.mode = 'stream';
    const run = this.run;
    void el.play().catch((e: unknown) => {
      if (run === this.run) this.error = `stream ${String(e)}`;
    });
    // and make sure the exact version is on its way
    void this.load(this.lang).catch(() => {});
  }

  /** from the stream to the decoded mix, at the same song time */
  private handOver(): void {
    const buffer = this.decoded[this.lang];
    const el = this.stream;
    if (!buffer || !el) return;
    const lead = 0.12;
    const at = (this.clock() ?? el.currentTime) + lead;
    this.startExact(buffer, at, lead);
    // the stream stops as the exact voice takes over
    window.setTimeout(() => {
      if (this.stream === el) {
        el.pause();
        this.stream = undefined;
      }
    }, lead * 1000);
  }

  stop(): void {
    this.run++;
    this.playing = false;
    this.silence();
    this.mode = 'idle';
  }

  private silence(): void {
    try {
      this.voice?.stop();
    } catch {
      // never started
    }
    this.voice?.disconnect();
    this.voice = undefined;
    if (this.stream) {
      this.stream.pause();
      this.stream = undefined;
    }
  }

  /**
   * The song time being heard; undefined when not playing. Until sound is
   * actually coming out it holds at the start, so the picture waits for it.
   */
  clock(): number | undefined {
    if (!this.playing) return undefined;
    if (this.mode === 'exact' && this.ctx) {
      return (
        this.startSong +
        Math.max(0, this.ctx.currentTime - this.startCtx - this.latency())
      );
    }
    const el = this.stream;
    if (this.mode === 'stream' && el) {
      // buffering, or not started yet: hold
      if (el.paused || el.readyState < 3) {
        this.seenPos = el.currentTime || this.startSong;
        this.seenAt = performance.now();
        return this.seenPos;
      }
      // the element reports its position coarsely: run on between reports
      const now = performance.now();
      if (el.currentTime !== this.seenPos) {
        this.seenPos = el.currentTime;
        this.seenAt = now;
      }
      return this.seenPos + Math.min(0.25, (now - this.seenAt) / 1000);
    }
    return this.startSong;
  }

  destroy(): void {
    this.stop();
    for (const el of Object.values(this.streams)) {
      el?.pause();
      el?.removeAttribute('src');
    }
    void this.ctx?.close();
  }
}
