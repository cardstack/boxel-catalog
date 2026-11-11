// An adaptive Likert: instead of "pick 1–7", the person says what they think
// in their own words. The AI places them on the scale and says why; they drag
// it if that is not quite them; then, if it helps, two statements that sit
// either side of them on the scale ask "which is closer to you?" to fine-tune
// it. Short or fed-up answers end the fine-tuning, and Skip is always there.
// A questioner can give any statement a ladder instead of agree/disagree:
// concrete reference points ("a lunch poll … payroll") that the AI writes and
// they can edit. Respondents then see only the stretch of the ladder they are
// in, and fine-tuning adds new examples inside it, zooming in each round.
// Each person becomes a Likert Response: the classic 1–7, their words, the
// gap between the AI's guess and their own, and a readout on how to sell to
// them.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq, and } from '@cardstack/boxel-ui/helpers';
import SlidersIcon from '@cardstack/boxel-icons/sliders-horizontal';
import { LikertStrip, LadderZoom } from './likert-scale';
import {
  place,
  probe,
  writeLikertReadout,
  soundsDone,
  toPoint,
  pointLabel,
  writeLadder,
  placeOnLadder,
  ladderAnchor,
  ladderLabel,
  labelFor,
  rungAt,
  likertSummary,
} from './likert-ai';
import type { LikertItem, LikertReadout, Probe, ScaleKind } from './likert-ai';
import { parse } from './media';

import { hostOf, type ToolHost } from './tool-kit';

// @ts-ignore import.meta is fine here (the host loads cards as ES modules); the catalog's CommonJS type check rejects it
const here: string = import.meta.url;

type Step =
  | 'intro'
  | 'say'
  | 'placing'
  | 'adjust'
  | 'tuning'
  | 'probe'
  | 'saving'
  | 'done';
// how far either side the in-between statements sit, per round; a pick moves
// halfway toward the chosen one, so each round halves the range they could be in
const DELTAS = [0.16, 0.08];

interface Statement {
  text: string;
  scale: ScaleKind;
  rungs: string[];
}
const rungsOf = (raw: string | null | undefined) =>
  (raw ?? '')
    .split('\n')
    .map((r) => r.trim())
    .filter(Boolean);
// the stretch of a ladder someone is in, with its two ends named
interface Win {
  lo: number;
  hi: number;
  loLabel: string;
  hiLabel: string;
}

class Isolated extends Component<typeof LikertQuestion> {
  @tracked tab: 'take' | 'results' | 'setup' = 'take';
  @tracked step: Step = 'intro';
  @tracked name = '';
  @tracked index = 0;
  @tracked draft = '';
  @tracked pos = 0.5;
  @tracked aiPos: number | null = null;
  @tracked aiWhy = '';
  @tracked probeNow: Probe | null = null;
  @tracked round = 0;
  @tracked items: LikertItem[] = [];
  @tracked readout: LikertReadout | null = null;
  @tracked responseId = '';
  @tracked error = '';
  @tracked busyNote = '';
  @tracked win: Win | null = null;
  @tracked anchorNow: { at: number; text: string } | null = null;
  @tracked writingLadder: number | null = null;
  @tracked setupError = '';
  itemStart = 0;
  probeStart = 0;
  selfPos: number | null = null;
  frustrated = false;
  probes: LikertItem['probes'] = [];

  // inside an interview: no intro, straight to the question
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

  get ctx() {
    return (
      (this.args.context as any)?.toolContext ??
      (this.args.context as any)?.commandContext
    );
  }
  get statements(): Statement[] {
    return (this.args.model.questions ?? [])
      .map((q) => {
        const rungs = rungsOf(q.rungs);
        // a ladder needs at least three rungs; until then it is agree/disagree
        const scale: ScaleKind =
          q.scale === 'ladder' && rungs.length >= 3 ? 'ladder' : 'agree';
        return { text: (q.text ?? '').trim(), scale, rungs };
      })
      .filter((q) => q.text);
  }
  get current(): Statement {
    return (
      this.statements[this.index] ?? { text: '', scale: 'agree', rungs: [] }
    );
  }
  get statement() {
    return this.current.text;
  }
  get isLadder() {
    return this.current.scale === 'ladder';
  }
  get progress() {
    return `${this.index + 1} of ${this.statements.length}`;
  }
  get posLabel() {
    return this.isLadder
      ? ladderLabel(this.pos, this.current.rungs)
      : pointLabel(this.pos);
  }
  get handleStyle() {
    return htmlSafe(`left:${(this.pos * 100).toFixed(2)}%`);
  }
  get sliderValue() {
    const w = this.win;
    const v = w ? (this.pos - w.lo) / Math.max(1e-6, w.hi - w.lo) : this.pos;
    return String(Math.round(v * 1000));
  }
  get moved() {
    return this.aiPos !== null && Math.abs(this.pos - this.aiPos) > 0.02;
  }

  setName = (e: Event) => (this.name = (e.target as HTMLInputElement).value);
  setDraft = (e: Event) =>
    (this.draft = (e.target as HTMLTextAreaElement).value);
  slide = (e: Event) => {
    const v = Number((e.target as HTMLInputElement).value) / 1000;
    const w = this.win;
    this.pos = w ? w.lo + v * (w.hi - w.lo) : v;
  };

  // ─── the ladder window ────────────────────────────────────────────────
  // the two rungs either side of a position
  private windowAround(pos: number): Win {
    const r = this.current.rungs;
    const n = r.length;
    const i = Math.min(n - 2, Math.max(0, Math.floor(pos * (n - 1) + 1e-6)));
    return {
      lo: rungAt(i, n),
      hi: rungAt(i + 1, n),
      loLabel: r[i],
      hiLabel: r[i + 1],
    };
  }
  // template-friendly: never undefined
  get w(): Win {
    return this.win ?? { lo: 0, hi: 1, loLabel: '', hiLabel: '' };
  }
  get anchorAt() {
    return this.anchorNow?.at ?? this.pos;
  }
  get rungIndex() {
    return this.win
      ? Math.round(this.win.lo * (this.current.rungs.length - 1))
      : 0;
  }
  get canGoLower() {
    return this.rungIndex > 0;
  }
  get canGoHigher() {
    return this.rungIndex < this.current.rungs.length - 2;
  }
  shift = (dir: number) => {
    const n = this.current.rungs.length;
    const i = Math.min(n - 2, Math.max(0, this.rungIndex + dir));
    this.win = this.windowAround(rungAt(i, n) + 1e-4);
    this.pos = (this.win.lo + this.win.hi) / 2;
  };
  goLower = () => this.shift(-1);
  goHigher = () => this.shift(1);
  get stretchNote() {
    const n = this.current.rungs.length;
    return `Step ${this.rungIndex + 1} of ${n - 1} on the ladder`;
  }

  start = () => {
    this.items = [];
    this.index = 0;
    this.beginItem();
  };
  private beginItem() {
    this.draft = '';
    this.aiPos = null;
    this.aiWhy = '';
    this.pos = 0.5;
    this.selfPos = null;
    this.frustrated = false;
    this.probes = [];
    this.round = 0;
    this.probeNow = null;
    this.anchorNow = null;
    this.win = this.isLadder ? this.windowAround(0.5) : null;
    this.error = '';
    this.itemStart = performance.now();
    this.step = 'say';
  }

  // they said something: place it
  submitWords = async () => {
    const words = this.draft.trim();
    if (!words) return;
    this.step = 'placing';
    this.error = '';
    try {
      const brief = this.args.model.brief ?? '';
      const p = this.isLadder
        ? await placeOnLadder(
            this.ctx,
            this.statement,
            this.current.rungs,
            words,
            brief,
          )
        : await place(this.ctx, this.statement, words, brief);
      this.aiPos = p.pos;
      this.aiWhy = p.why;
      this.pos = p.pos;
      if (this.isLadder) this.win = this.windowAround(p.pos);
      this.frustrated = p.frustrated || soundsDone(words);
    } catch (e: any) {
      this.aiPos = null;
      this.aiWhy = '';
      this.pos = 0.5;
      if (this.isLadder) {
        this.win = this.windowAround(0.5);
        this.pos = (this.win.lo + this.win.hi) / 2;
      }
      this.error = `I could not place that (${e?.message ?? e}). Put yourself on the scale instead.`;
    }
    this.step = 'adjust';
  };
  // no words, just the classic slider
  sliderOnly = () => {
    this.draft = '';
    this.aiPos = null;
    this.aiWhy = '';
    this.pos = 0.5;
    if (this.isLadder) {
      this.win = this.windowAround(0.5);
      this.pos = (this.win.lo + this.win.hi) / 2;
    }
    this.step = 'adjust';
  };

  // they settled the slider: fine-tune, unless they are done with us
  confirm = async () => {
    this.selfPos = this.pos;
    const words = this.draft.trim();
    if (this.isLadder) {
      // examples are concrete enough to compare with, so words are not needed
      if (this.frustrated) this.finishItem(false);
      else await this.nextAnchor();
      return;
    }
    if (!words || this.frustrated || this.round >= DELTAS.length) {
      this.finishItem(false);
      return;
    }
    await this.nextProbe();
  };

  // a new example inside their stretch; their answer halves the stretch
  private async nextAnchor() {
    const w = this.win!;
    const span = w.hi - w.lo;
    const at = Math.min(
      w.hi - span * 0.25,
      Math.max(w.lo + span * 0.25, this.pos),
    );
    this.step = 'tuning';
    try {
      const text = await ladderAnchor(
        this.ctx,
        this.statement,
        this.current.rungs,
        w.loLabel,
        w.hiLabel,
        (at - w.lo) / span,
        this.draft.trim(),
        this.args.model.brief ?? '',
        this.probes.map((p) => p.anchor ?? ''),
      );
      if (!text) throw new Error('empty example');
      this.anchorNow = { at, text };
      this.probeStart = performance.now();
      this.step = 'probe';
    } catch {
      this.finishItem(false);
    }
  }
  pickRung = async (which: 'below' | 'here' | 'above') => {
    const a = this.anchorNow!;
    const w = this.win!;
    this.probes = [
      ...this.probes,
      {
        low: '',
        high: '',
        anchor: a.text,
        at: a.at,
        picked: which,
        ms: Math.round(performance.now() - this.probeStart),
      },
    ];
    if (which === 'here') {
      this.pos = a.at;
      this.finishItem(false);
      return;
    }
    this.win =
      which === 'below'
        ? { ...w, hi: a.at, hiLabel: a.text }
        : { ...w, lo: a.at, loLabel: a.text };
    this.pos = (this.win.lo + this.win.hi) / 2;
    this.anchorNow = null;
    this.round++;
    if (this.round >= DELTAS.length) {
      this.finishItem(false);
      return;
    }
    await this.nextAnchor();
  };
  pickBelow = () => this.pickRung('below');
  pickHere = () => this.pickRung('here');
  pickAbove = () => this.pickRung('above');
  private async nextProbe() {
    this.step = 'tuning';
    try {
      this.probeNow = await probe(
        this.ctx,
        this.statement,
        this.draft.trim(),
        this.pos,
        DELTAS[this.round],
        this.args.model.brief ?? '',
        this.probes.flatMap((p) => [p.low, p.high]),
      );
      if (!this.probeNow.low.text || !this.probeNow.high.text)
        throw new Error('empty statements');
      this.probeStart = performance.now();
      this.step = 'probe';
    } catch {
      this.finishItem(false);
    }
  }
  pick = async (which: 'low' | 'high' | 'between') => {
    const p = this.probeNow!;
    this.probes = [
      ...this.probes,
      {
        low: p.low.text,
        high: p.high.text,
        picked: which,
        ms: Math.round(performance.now() - this.probeStart),
      },
    ];
    if (which === 'low') this.pos = (this.pos + p.low.pos) / 2;
    if (which === 'high') this.pos = (this.pos + p.high.pos) / 2;
    this.round++;
    if (this.round >= DELTAS.length) {
      this.finishItem(false);
      return;
    }
    await this.nextProbe();
  };
  pickLow = () => this.pick('low');
  pickHigh = () => this.pick('high');
  pickBetween = () => this.pick('between');
  skipTuning = () => {
    if (this.anchorNow)
      this.probes = [
        ...this.probes,
        {
          low: '',
          high: '',
          anchor: this.anchorNow.text,
          at: this.anchorNow.at,
          picked: 'skip',
          ms: Math.round(performance.now() - this.probeStart),
        },
      ];
    else if (this.probeNow)
      this.probes = [
        ...this.probes,
        {
          low: this.probeNow.low.text,
          high: this.probeNow.high.text,
          picked: 'skip',
          ms: Math.round(performance.now() - this.probeStart),
        },
      ];
    this.finishItem(false);
  };
  skipStatement = () => this.finishItem(true);

  private finishItem(skipped: boolean) {
    this.items = [
      ...this.items,
      {
        statement: this.statement,
        scale: this.current.scale,
        ...(this.isLadder
          ? {
              rungs: this.current.rungs,
              landed: skipped ? '' : ladderLabel(this.pos, this.current.rungs),
            }
          : {}),
        answer: this.draft.trim(),
        aiPos: this.aiPos,
        aiWhy: this.aiWhy,
        selfPos: skipped ? null : this.selfPos,
        probes: this.probes,
        final: skipped ? null : Math.round(this.pos * 1000) / 1000,
        // agree: the classic 1–7; ladder: the nearest rung, 1 = lowest
        point: skipped
          ? null
          : this.isLadder
            ? Math.round(this.pos * (this.current.rungs.length - 1)) + 1
            : toPoint(this.pos),
        frustrated: this.frustrated,
        skipped,
        ms: Math.round(performance.now() - this.itemStart),
      },
    ];
    if (this.index < this.statements.length - 1) {
      this.index++;
      this.beginItem();
      return;
    }
    this.save();
  }

  get probeLowStyle() {
    return this.probeNow
      ? htmlSafe(`left:${(this.probeNow.low.pos * 100).toFixed(2)}%`)
      : htmlSafe('');
  }
  get probeHighStyle() {
    return this.probeNow
      ? htmlSafe(`left:${(this.probeNow.high.pos * 100).toFixed(2)}%`)
      : htmlSafe('');
  }
  get roundLabel() {
    return `Fine-tuning ${this.round + 1} of ${DELTAS.length}`;
  }

  private async save() {
    this.step = 'saving';
    // inside an interview the interviewer writes its own readout
    if (!this.host) {
      try {
        this.readout = await writeLikertReadout(
          this.ctx,
          this.args.model.brief ?? '',
          this.items,
        );
      } catch (e: any) {
        this.readout = null;
        this.error = `The readout could not be written (${e?.message ?? e}); the answers are saved without it.`;
      }
    }
    const doc = {
      data: {
        type: 'card',
        attributes: {
          respondent: this.name.trim() || null,
          takenAt: new Date().toISOString(),
          items: JSON.stringify(this.items),
          readout: this.readout ? JSON.stringify(this.readout) : null,
          summary: likertSummary(this.items),
        },
        relationships: {
          question: { links: { self: (this.args.model as any).id } },
        },
        meta: {
          adoptsFrom: {
            module: new URL('./likert-response', here).href,
            name: 'LikertResponse',
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
    this.step = 'done';
    this.host?.done({
      summary: likertSummary(this.items),
      responseId: this.responseId,
    });
  }
  openResponse = () => {
    if (this.responseId)
      this.args.viewCard?.(new URL(this.responseId) as any, 'isolated');
  };
  again = () => {
    this.readout = null;
    this.responseId = '';
    this.step = 'intro';
  };

  // ─── results ──────────────────────────────────────────────────────────
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
            module: new URL('./likert-response', here).href,
            name: 'LikertResponse',
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
  get perStatement() {
    const all = this.responses.map((r) => parse<LikertItem[]>(r.items, []));
    return this.statements.map(({ text: statement, scale, rungs }) => {
      const answered = all
        .map((list) => list.find((i) => i.statement === statement))
        .filter((i): i is LikertItem => Boolean(i) && i!.final !== null);
      // positions on a ladder only mean something on that ladder: answers given
      // on an earlier version of it are counted apart, never averaged in
      const same = (i: LikertItem) =>
        scale === 'ladder'
          ? i.scale === 'ladder' &&
            (i.rungs ?? []).join('\n') === rungs.join('\n')
          : i.scale !== 'ladder';
      const its = answered.filter(same);
      const older = answered.length - its.length;
      const finals = its.map((i) => i.final as number);
      const mean = finals.length
        ? finals.reduce((a, b) => a + b, 0) / finals.length
        : null;
      const gaps = its
        .filter((i) => i.aiPos !== null && i.selfPos !== null)
        .map((i) => (i.selfPos as number) - (i.aiPos as number));
      const gap = gaps.length
        ? gaps.reduce((a, b) => a + b, 0) / gaps.length
        : null;
      const ladder = scale === 'ladder';
      return {
        statement,
        labels: ladder ? rungs : undefined,
        finals,
        mean,
        n: finals.length,
        olderNote: older
          ? `${older} more answered on an earlier version of this scale, kept apart.`
          : '',
        meanLabel:
          mean === null
            ? ''
            : ladder
              ? `On average ${labelFor(mean, scale, rungs)}`
              : `${(mean * 6 + 1).toFixed(1)} of 7 · ${pointLabel(mean)}`,
        gapLabel:
          gap === null
            ? ''
            : Math.abs(gap) < 0.03
              ? 'The AI placed people about where they put themselves.'
              : ladder
                ? `People moved the AI's guess ${gap > 0 ? 'up' : 'down'} by ${(Math.abs(gap) * (rungs.length - 1)).toFixed(1)} rungs on average.`
                : `People moved the AI's guess ${gap > 0 ? 'up' : 'down'} by ${(Math.abs(gap) * 6).toFixed(1)} points on average.`,
      };
    });
  }
  showTake = () => (this.tab = 'take');
  showSetup = () => (this.tab = 'setup');

  // ─── set up: the questioner's view ────────────────────────────────────
  get setupRows() {
    return (this.args.model.questions ?? []).map((q, i) => {
      const rungs = rungsOf(q.rungs);
      const ladder = q.scale === 'ladder';
      const key = rungs.join('\n');
      const onIt = ladder
        ? this.responses.filter((r) =>
            parse<LikertItem[]>(r.items, []).some(
              (it) =>
                it.statement === (q.text ?? '').trim() &&
                it.scale === 'ladder' &&
                (it.rungs ?? []).join('\n') === key,
            ),
          ).length
        : 0;
      return {
        i,
        n: i + 1,
        text: q.text ?? '',
        ladder,
        rungsText: q.rungs ?? '',
        rungs,
        short: ladder && rungs.length < 3,
        writing: this.writingLadder === i,
        lockNote: onIt
          ? `${onIt} ${onIt === 1 ? 'person has' : 'people have'} answered on this ladder. Changing it starts a new version; their answers stay but are reported apart.`
          : '',
      };
    });
  }
  private rewrite(
    i: number,
    patch: Partial<{ text: string; scale: string; rungs: string }>,
  ) {
    const list = (this.args.model.questions ?? []).map(
      (q, j) =>
        new ScaleItem({
          text: q.text,
          scale: q.scale,
          rungs: q.rungs,
          ...(j === i ? patch : {}),
        }),
    );
    this.args.model.questions = list;
  }
  setText = (i: number, e: Event) =>
    this.rewrite(i, { text: (e.target as HTMLTextAreaElement).value });
  setRungs = (i: number, e: Event) =>
    this.rewrite(i, { rungs: (e.target as HTMLTextAreaElement).value });
  setScale = (i: number, scale: ScaleKind) => this.rewrite(i, { scale });
  removeRow = (i: number) => {
    this.args.model.questions = (this.args.model.questions ?? [])
      .filter((_, j) => j !== i)
      .map(
        (q) => new ScaleItem({ text: q.text, scale: q.scale, rungs: q.rungs }),
      );
  };
  addRow = () => {
    this.args.model.questions = [
      ...(this.args.model.questions ?? []).map(
        (q) => new ScaleItem({ text: q.text, scale: q.scale, rungs: q.rungs }),
      ),
      new ScaleItem({ text: '', scale: 'agree', rungs: '' }),
    ];
  };
  draftLadder = async (i: number) => {
    const q = (this.args.model.questions ?? [])[i];
    if (!q?.text?.trim()) {
      this.setupError =
        'Write the question first, then the ladder can be written for it.';
      return;
    }
    this.writingLadder = i;
    this.setupError = '';
    try {
      const rungs = await writeLadder(
        this.ctx,
        q.text.trim(),
        this.args.model.brief ?? '',
      );
      this.rewrite(i, { scale: 'ladder', rungs: rungs.join('\n') });
    } catch (e: any) {
      this.setupError = `The ladder could not be written (${e?.message ?? e}). You can type the rungs yourself, one per line.`;
    }
    this.writingLadder = null;
  };
  showResults = () => (this.tab = 'results');
  open = (card: any) => this.args.viewCard?.(card, 'isolated');

  <template>
    <article class='sv lq {{if this.host "hosted"}}'>
      <header class='top'>
        <div>
          <p class='kicker'>Adaptive Likert</p>
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
          <button
            type='button'
            class={{if (eq this.tab 'setup') 'on'}}
            {{on 'click' this.showSetup}}
          >Set up</button>
        </nav>
      </header>

      {{#if (eq this.tab 'take')}}
        <section class='panel'>
          {{#if (eq this.step 'intro')}}
            <p class='lead'>A few statements. Tell us what you think in your own
              words; we will place you on the scale and you can move it if we
              got you wrong.
              {{this.statements.length}}
              statements, about a minute each.</p>
            <label class='field'>
              <span>Your first name or a nickname (optional)</span>
              <input
                type='text'
                value={{this.name}}
                autocomplete='given-name'
                {{on 'input' this.setName}}
              />
            </label>
            <div class='actions'><button
                type='button'
                class='primary'
                disabled={{if this.statements.length false true}}
                {{on 'click' this.start}}
              >Start</button></div>
          {{else if (eq this.step 'done')}}
            <div class='done'>
              {{#if this.readout.label}}<p
                  class='badge'
                >{{this.readout.label}}</p>{{/if}}
              <p class='lead'>{{if
                  this.readout.headline
                  this.readout.headline
                  'Thanks, your answers are saved.'
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
          {{else if (eq this.step 'saving')}}
            <p class='lead'>Writing it up…</p>
          {{else}}
            <p class='count'>{{this.progress}}</p>
            <blockquote class='statement'>{{this.statement}}</blockquote>

            {{#if (eq this.step 'say')}}
              <label class='field wide'>
                <span>What do you think? A sentence or two is plenty.</span>
                <textarea
                  rows='3'
                  value={{this.draft}}
                  {{on 'input' this.setDraft}}
                ></textarea>
              </label>
              <div class='actions'>
                <button
                  type='button'
                  class='primary'
                  disabled={{if this.draft false true}}
                  {{on 'click' this.submitWords}}
                >Next</button>
                <button
                  type='button'
                  class='quiet'
                  {{on 'click' this.sliderOnly}}
                >Just use the scale</button>
                <button
                  type='button'
                  class='link'
                  {{on 'click' this.skipStatement}}
                >Skip this one</button>
              </div>
            {{else if (eq this.step 'placing')}}
              <p class='said'>“{{this.draft}}”</p>
              <p class='lead muted'>Placing that on the scale…</p>
            {{else if (eq this.step 'adjust')}}
              {{#if this.draft}}<p class='said'>“{{this.draft}}”</p>{{/if}}
              {{#if this.isLadder}}
                <div class='zoom'>
                  <button
                    type='button'
                    class='nudge'
                    disabled={{if this.canGoLower false true}}
                    aria-label='Lower on the ladder'
                    {{on 'click' this.goLower}}
                  >←</button>
                  <div class='scale'>
                    <LadderZoom
                      @rungs={{this.current.rungs}}
                      @lo={{this.w.lo}}
                      @hi={{this.w.hi}}
                      @loLabel={{this.w.loLabel}}
                      @hiLabel={{this.w.hiLabel}}
                      @pos={{this.pos}}
                      @aiPos={{this.aiPos}}
                    />
                    <input
                      class='drag zdrag'
                      type='range'
                      min='0'
                      max='1000'
                      value={{this.sliderValue}}
                      aria-label='Where you are between these two'
                      {{on 'input' this.slide}}
                    />
                  </div>
                  <button
                    type='button'
                    class='nudge'
                    disabled={{if this.canGoHigher false true}}
                    aria-label='Higher on the ladder'
                    {{on 'click' this.goHigher}}
                  >→</button>
                </div>
                <p class='where'>
                  {{#if this.aiWhy}}
                    {{#if this.moved}}You are
                      <b>{{this.posLabel}}</b>. The ring is where I had you.{{else}}{{this.aiWhy}}{{/if}}
                  {{else}}
                    You are
                    <b>{{this.posLabel}}</b>. Use the arrows to move along the
                    ladder.
                  {{/if}}
                </p>
                <div class='actions'>
                  <button
                    type='button'
                    class='primary'
                    {{on 'click' this.confirm}}
                  >{{if this.moved 'This is me' 'That is right'}}</button>
                  <span class='hint'>{{this.stretchNote}}
                    · drag the dot, or the arrows for further</span>
                </div>
              {{else}}
                <div class='scale'>
                  <LikertStrip @aiPos={{this.aiPos}} @final={{this.pos}} />
                  <input
                    class='drag'
                    type='range'
                    min='0'
                    max='1000'
                    value={{this.sliderValue}}
                    aria-label='Where you stand'
                    {{on 'input' this.slide}}
                  />
                </div>
                <p class='where'>
                  {{#if this.aiWhy}}
                    {{#if this.moved}}You moved it to
                      <b>{{this.posLabel}}</b>. The ring is where I had you.{{else}}I
                      put you at
                      <b>{{this.posLabel}}</b>.
                      {{this.aiWhy}}{{/if}}
                  {{else}}
                    You are at
                    <b>{{this.posLabel}}</b>.
                  {{/if}}
                </p>
                <div class='actions'>
                  <button
                    type='button'
                    class='primary'
                    {{on 'click' this.confirm}}
                  >{{if this.moved 'This is me' 'That is right'}}</button>
                  {{#if this.aiWhy}}<span class='hint'>Not quite? Drag the dot.</span>{{/if}}
                </div>
              {{/if}}
            {{else if (eq this.step 'tuning')}}
              <p class='lead muted'>{{if
                  this.isLadder
                  'Finding an example in between…'
                  'Finding two statements either side of you…'
                }}</p>
            {{else if (and (eq this.step 'probe') this.isLadder)}}
              <p class='qmeta'>{{this.roundLabel}}
                · Compared with this, where are you?</p>
              <p class='anchor'>{{this.anchorNow.text}}</p>
              <div class='scale'>
                <LadderZoom
                  @rungs={{this.current.rungs}}
                  @lo={{this.w.lo}}
                  @hi={{this.w.hi}}
                  @loLabel={{this.w.loLabel}}
                  @hiLabel={{this.w.hiLabel}}
                  @pos={{this.anchorAt}}
                  @anchor={{this.anchorNow}}
                />
              </div>
              <div class='trio'>
                <button
                  type='button'
                  class='opt'
                  {{on 'click' this.pickBelow}}
                >← Lower than this</button>
                <button
                  type='button'
                  class='opt'
                  {{on 'click' this.pickHere}}
                >About here</button>
                <button
                  type='button'
                  class='opt'
                  {{on 'click' this.pickAbove}}
                >Higher than this →</button>
              </div>
              <div class='actions'>
                <button
                  type='button'
                  class='link'
                  {{on 'click' this.skipTuning}}
                >Skip fine-tuning</button>
              </div>
            {{else if (eq this.step 'probe')}}
              <p class='qmeta'>{{this.roundLabel}} · Which is closer to you?</p>
              <div class='pair'>
                <button
                  type='button'
                  class='opt'
                  {{on 'click' this.pickLow}}
                ><span class='tag'>A</span>{{this.probeNow.low.text}}</button>
                <button
                  type='button'
                  class='opt'
                  {{on 'click' this.pickHigh}}
                ><span class='tag'>B</span>{{this.probeNow.high.text}}</button>
              </div>
              <div class='scale probe'>
                <LikertStrip @final={{this.pos}} />
                <span class='pmark' style={{this.probeLowStyle}}>A</span>
                <span class='pmark' style={{this.probeHighStyle}}>B</span>
              </div>
              <div class='actions'>
                <button
                  type='button'
                  class='quiet'
                  {{on 'click' this.pickBetween}}
                >Somewhere between</button>
                <button
                  type='button'
                  class='link'
                  {{on 'click' this.skipTuning}}
                >Skip fine-tuning</button>
              </div>
            {{/if}}
          {{/if}}
          {{#if this.error}}<p
              class='err'
              role='alert'
            >{{this.error}}</p>{{/if}}
        </section>
      {{else if (eq this.tab 'setup')}}
        <section class='setup'>
          <p class='sum'>Each statement can use the usual agree/disagree scale,
            or a
            <b>ladder</b>: concrete examples from lowest to highest, like
            "bigger than a car, smaller than an elephant". Everyone is measured
            on the same ladder, so results still add up. Respondents only see
            the stretch they are in, and fine-tuning adds examples inside it.</p>
          {{#each this.setupRows as |r|}}
            <div class='srow'>
              <div class='shead'>
                <span class='n'>{{r.n}}</span>
                <div class='seg' role='group' aria-label='Scale'>
                  <button
                    type='button'
                    class={{unless r.ladder 'on'}}
                    {{on 'click' (fn this.setScale r.i 'agree')}}
                  >Agree / disagree</button>
                  <button
                    type='button'
                    class={{if r.ladder 'on'}}
                    {{on 'click' (fn this.setScale r.i 'ladder')}}
                  >Ladder</button>
                </div>
                <button
                  type='button'
                  class='link'
                  {{on 'click' (fn this.removeRow r.i)}}
                >Remove</button>
              </div>
              <label class='field wide'>
                <span>{{if
                    r.ladder
                    'The question (it reads best as "How far…" or "How much…")'
                    'The statement'
                  }}</span>
                <textarea
                  rows='2'
                  value={{r.text}}
                  {{on 'change' (fn this.setText r.i)}}
                ></textarea>
              </label>
              {{#if r.ladder}}
                <label class='field wide'>
                  <span>Rungs, one per line, lowest first</span>
                  <textarea
                    rows='7'
                    value={{r.rungsText}}
                    {{on 'change' (fn this.setRungs r.i)}}
                  ></textarea>
                </label>
                <div class='actions'>
                  <button
                    type='button'
                    class='quiet'
                    disabled={{r.writing}}
                    {{on 'click' (fn this.draftLadder r.i)}}
                  >{{if
                      r.writing
                      'Writing…'
                      (if
                        r.rungs.length
                        'Rewrite with AI'
                        'Write a ladder with AI'
                      )
                    }}</button>
                  {{#if r.short}}<span class='hint'>A ladder needs at least 3
                      rungs; until then this uses agree/disagree.</span>{{/if}}
                </div>
                {{#if r.lockNote}}<p class='hint'>{{r.lockNote}}</p>{{/if}}
                {{#unless r.short}}<LikertStrip
                    @labels={{r.rungs}}
                  />{{/unless}}
              {{/if}}
            </div>
          {{/each}}
          <div class='actions'><button
              type='button'
              class='quiet'
              {{on 'click' this.addRow}}
            >Add a statement</button></div>
          {{#if this.setupError}}<p
              class='err'
              role='alert'
            >{{this.setupError}}</p>{{/if}}
        </section>
      {{else}}
        <section class='results'>
          {{#if @model.brief}}<p class='brief'><b>What we want to learn</b>
              {{@model.brief}}</p>{{/if}}
          <p class='sum'>{{this.responseCount}}
            {{if (eq this.responseCount 1) 'response' 'responses'}}. Each faint
            tick is one person; the dark line is the average.</p>
          {{#each this.perStatement as |s|}}
            <div class='stat'>
              <p class='st'>{{s.statement}}</p>
              <LikertStrip
                @others={{s.finals}}
                @mean={{s.mean}}
                @labels={{s.labels}}
              />
              <p class='sm'>{{#if s.n}}{{s.meanLabel}}
                  ·
                  {{s.n}}
                  answered.
                  {{s.gapLabel}}{{else}}No answers yet.{{/if}}
                {{s.olderNote}}</p>
            </div>
          {{/each}}
          {{#if this.responseCount}}
            <ul class='list'>
              {{#each this.responses as |r|}}
                <li><button
                    type='button'
                    class='rowbtn'
                    {{on 'click' (fn this.open r)}}
                  >{{r.cardTitle}}</button></li>
              {{/each}}
            </ul>
          {{/if}}
        </section>
      {{/if}}
    </article>
    <style scoped>
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
      .sv {
        --sv-paper: #fbfaf7;
        --sv-panel: #ffffff;
        --sv-ink: #1d1c1a;
        --sv-muted: #6b675f;
        --sv-rule: #e4e0d8;
        --sv-live: #e2553b;
        --sv-surprise: #7a55c9;
        --sv-sans:
          ui-sans-serif, -apple-system, 'Segoe UI', system-ui, sans-serif;
        --sv-mono: ui-monospace, 'SF Mono', Menlo, monospace;
        container-type: inline-size;
        background: var(--sv-paper);
        color: var(--sv-ink);
        font-family: var(--sv-sans);
        box-sizing: border-box;
      }
      .lq {
        min-height: 100%;
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 20px;
        align-content: start;
        max-width: 880px;
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
      .panel {
        display: grid;
        gap: 16px;
        padding: clamp(18px, 3cqw, 32px);
        border-radius: 14px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .lead {
        margin: 0;
        font-size: 15px;
        line-height: 1.55;
        max-width: 64ch;
      }
      .muted {
        color: var(--sv-muted);
      }
      .count,
      .qmeta {
        margin: 0;
        color: var(--sv-muted);
        font-size: 13px;
      }
      .statement {
        margin: 0;
        font: 600 clamp(20px, 3cqw, 26px)/1.3 var(--sv-sans);
        letter-spacing: -0.01em;
        max-width: 30ch;
      }
      .said {
        margin: 0;
        color: var(--sv-muted);
        font-style: italic;
        line-height: 1.5;
        max-width: 64ch;
      }
      .field {
        display: grid;
        gap: 6px;
        max-width: 360px;
        font-size: 13px;
        color: var(--sv-muted);
      }
      .field.wide {
        max-width: none;
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
      .scale {
        position: relative;
        padding: 8px 0 0;
      }
      .drag {
        position: absolute;
        left: 0;
        right: 0;
        top: 4px;
        width: 100%;
        height: 34px;
        margin: 0;
        opacity: 0;
        cursor: grab;
      }
      .drag:focus-visible {
        opacity: 0.15;
      }
      .where {
        margin: 0;
        line-height: 1.5;
      }
      .hint {
        align-self: center;
        color: var(--sv-muted);
        font-size: 13px;
      }
      .pair {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 12px;
      }
      .opt {
        display: grid;
        gap: 8px;
        align-content: start;
        text-align: left;
        padding: 16px;
        border-radius: 12px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-paper);
        font: 500 15px/1.45 var(--sv-sans);
        color: var(--sv-ink);
        cursor: pointer;
        transition:
          border-color 0.15s,
          transform 0.15s;
      }
      .opt:hover {
        border-color: var(--sv-ink);
        transform: translateY(-1px);
      }
      .tag {
        justify-self: start;
        font: 700 11px/1 var(--sv-mono);
        padding: 4px 6px;
        border-radius: 5px;
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      .pmark {
        position: absolute;
        top: 0;
        transform: translateX(-50%);
        font: 700 10px/1 var(--sv-mono);
        padding: 3px 5px;
        border-radius: 4px;
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      .scale.probe {
        padding-top: 18px;
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
        border-radius: 9px;
        cursor: pointer;
      }
      .primary {
        border: 0;
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      .quiet {
        border: 1px solid var(--sv-rule);
        background: transparent;
        color: var(--sv-ink);
      }
      .quiet:hover {
        border-color: var(--sv-ink);
      }
      .link {
        border: 0;
        background: none;
        padding: 8px 4px;
        color: var(--sv-muted);
        font: 500 13px/1 var(--sv-sans);
        text-decoration: underline;
        cursor: pointer;
      }
      button:disabled {
        opacity: 0.4;
        cursor: default;
      }
      button:focus-visible {
        outline: 2px solid var(--sv-live);
        outline-offset: 2px;
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
        gap: 18px;
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
      .sum,
      .sm {
        color: var(--sv-muted);
        font-size: 13px;
      }
      .stat {
        display: grid;
        gap: 8px;
        padding: 16px 18px;
        border-radius: 12px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .st {
        margin: 0;
        font-weight: 600;
        line-height: 1.4;
      }
      .sm {
        margin: 0;
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
      .zoom {
        display: grid;
        grid-template-columns: auto 1fr auto;
        gap: 12px;
        align-items: center;
      }
      .nudge {
        width: 40px;
        height: 40px;
        border-radius: 50%;
        border: 1px solid var(--sv-rule);
        background: var(--sv-paper);
        font: 600 16px/1 var(--sv-sans);
        color: var(--sv-ink);
        cursor: pointer;
      }
      .nudge:hover:not(:disabled) {
        border-color: var(--sv-ink);
      }
      .zdrag {
        top: 40px;
      }
      .anchor {
        margin: 0;
        padding: 16px 18px;
        border-radius: 12px;
        background: var(--sv-paper);
        border: 1.5px solid var(--sv-ink);
        font: 600 18px/1.35 var(--sv-sans);
      }
      .trio {
        display: grid;
        grid-template-columns: 1fr auto 1fr;
        gap: 10px;
      }
      .trio .opt {
        text-align: center;
        justify-items: center;
      }
      .setup {
        display: grid;
        gap: 14px;
      }
      .setup .sum b {
        color: var(--sv-ink);
      }
      .srow p.hint {
        margin: 0;
      }
      .srow {
        display: grid;
        gap: 12px;
        padding: 16px 18px;
        border-radius: 12px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .shead {
        display: flex;
        gap: 12px;
        align-items: center;
      }
      .shead .link {
        margin-left: auto;
      }
      .n {
        flex: none;
        width: 24px;
        height: 24px;
        border-radius: 50%;
        display: grid;
        place-items: center;
        background: var(--sv-paper);
        border: 1px solid var(--sv-rule);
        font-size: 12px;
      }
      .seg {
        display: flex;
        gap: 2px;
        padding: 3px;
        border-radius: 9px;
        background: var(--sv-paper);
        border: 1px solid var(--sv-rule);
      }
      .seg button {
        border: 0;
        background: transparent;
        padding: 6px 10px;
        border-radius: 6px;
        font: 500 13px/1 var(--sv-sans);
        color: var(--sv-muted);
        cursor: pointer;
      }
      .seg button.on {
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      @container (max-width: 560px) {
        .pair,
        .trio {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

class Fitted extends Component<typeof LikertQuestion> {
  <template>
    <div class='lf'>
      <span class='icon'><SlidersIcon width='18' height='18' /></span>
      <div class='txt'>
        <b>{{@model.cardTitle}}</b>
        <span>Adaptive Likert</span>
      </div>
    </div>
    <style scoped>
      .lf {
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
        color: #6b675f;
      }
    </style>
  </template>
}

// one statement and how it is measured
export class ScaleItem extends FieldDef {
  static displayName = 'Scale item';
  @field text = contains(TextAreaField);
  @field scale = contains(StringField); // 'agree' (default) or 'ladder'
  @field rungs = contains(TextAreaField); // ladder only: one per line, lowest first
}

export class LikertQuestion extends CardDef {
  static displayName = 'Likert Question';
  static icon = SlidersIcon;
  @field title = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: LikertQuestion) {
      return this.title;
    },
  });
  @field brief = contains(TextAreaField); // what whoever asks wants to learn
  @field questions = containsMany(ScaleItem);
  static isolated = Isolated;
  static embedded = Fitted;
  static fitted = Fitted;
}

export { Isolated as LikertTool };
