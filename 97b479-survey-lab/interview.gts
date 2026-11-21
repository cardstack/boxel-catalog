// The interview: a plain chat with an interviewer who works from a brief.
// InterviewBrief is what whoever asks writes (a few sentences, the aims, who
// interviews). Interview is one participant's session: the chat, the tools the
// interviewer pulled up inside it, and the dossier, the interviewer's living
// notes on this person. Every turn is a fresh call that reads the dossier and
// the last few turns (see interviewer-ai.ts), so an interrupted interview
// carries on from wherever it stopped, with any agent.
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  realmURL,
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
import { eq, gt } from '@cardstack/boxel-ui/helpers';
import MessagesSquareIcon from '@cardstack/boxel-icons/messages-square';
import {
  toolCtx,
  lines,
  parseJson,
  resolveUrl,
  SESSION_EXPIRED,
  type ToolResult,
} from './tool-kit';
import {
  nextTurn,
  draftAims,
  type Turn,
  type ToolCall,
  type ToolKind,
  type BriefInfo,
  type Verdict,
} from './interviewer-ai';
import { readProtocol, designStudy, type StudyProtocol } from './study';
import { performLine } from './stage-bus';
import {
  readStimuli,
  mediaFor,
  findStimulus,
  describeStimulus,
  MediaView,
  type Stimulus,
} from './stimuli';
import { ChoiceTool } from './choice';
import { LikertTool } from './likert-question';
import { DuelsTool } from './duels';
import { RecallTool } from './recall';
import { HaggleTool } from './haggle';
import { PictureTool } from './picture';
import { VideoTool } from './video-question';
import { Interviewer, Avatar } from './interviewer';

// @ts-ignore import.meta is fine here (the host loads cards as ES modules); the catalog's CommonJS type check rejects it
const here: string = import.meta.url;

const TOOL_VIEWS: Record<ToolKind, any> = {
  choice: ChoiceTool,
  likert: LikertTool,
  duels: DuelsTool,
  recall: RecallTool,
  haggle: HaggleTool,
  picture: PictureTool,
  video: VideoTool,
};
const TOOL_NAMES: Record<ToolKind, string> = {
  choice: 'Quick pick',
  likert: 'Scale',
  duels: 'This or that',
  recall: 'Off the top of your head',
  haggle: 'Haggle',
  picture: 'Picture it',
  video: 'Watch it',
};
const TOOL_MODULES: Record<ToolKind, [string, string]> = {
  choice: ['./choice', 'ChoiceQuestion'],
  likert: ['./likert-question', 'LikertQuestion'],
  duels: ['./duels', 'DuelsQuestion'],
  recall: ['./recall', 'RecallQuestion'],
  haggle: ['./haggle', 'HaggleQuestion'],
  picture: ['./picture', 'PictureQuestion'],
  video: ['./video-question', 'VideoQuestion'],
};

const strs = (x: any) =>
  Array.isArray(x) ? x.map((s) => String(s ?? '').trim()).filter(Boolean) : [];
const short = (s: string, n = 70) =>
  s.length > n ? s.slice(0, n - 1) + '…' : s;

// the question card the interviewer configured, as a document to save
function toolDoc(
  kind: ToolKind,
  why: string,
  c: any,
  participant: string,
  interviewer = '',
  stimuli: Stimulus[] = [],
) {
  const title = `${participant || 'Interview'} · ${short(String(c.prompt ?? c.product ?? c.statements?.[0]?.text ?? TOOL_NAMES[kind]), 60)}`;
  let attributes: Record<string, any> = { title, brief: why };
  if (kind === 'choice') {
    const m = mediaFor(stimuli, strs(c.options));
    attributes = {
      ...attributes,
      prompt: c.prompt,
      options: m.items.join('\n'),
      multi: Boolean(c.multi),
      maxPicks: Number(c.maxPicks) || null,
      allowOther: c.allowOther !== false,
      shuffle: true,
      media: Object.keys(m.media).length ? JSON.stringify(m.media) : null,
    };
  }
  if (kind === 'recall')
    attributes = {
      ...attributes,
      prompt: c.prompt,
      options: strs(c.options).join('\n'),
    };
  if (kind === 'duels') {
    const m = mediaFor(stimuli, strs(c.items));
    attributes = {
      ...attributes,
      prompt: c.prompt || 'Which matters more to you?',
      items: m.items.join('\n'),
      media: Object.keys(m.media).length ? JSON.stringify(m.media) : null,
    };
  }
  if (kind === 'likert') {
    attributes = {
      ...attributes,
      questions: (c.statements as any[])
        .filter((s) => s?.text)
        .slice(0, 3)
        .map((s) => {
          const rungs = strs(s.rungs);
          const ladder = s.scale === 'ladder' && rungs.length >= 3;
          return {
            text: String(s.text),
            scale: ladder ? 'ladder' : 'agree',
            rungs: ladder ? rungs.join('\n') : null,
          };
        }),
    };
  }
  if (kind === 'haggle') {
    const list = Number(c.listPrice);
    const floor =
      Number(c.floorPrice) > 0 && Number(c.floorPrice) < list
        ? Number(c.floorPrice)
        : Math.round(list * 0.7);
    attributes = {
      ...attributes,
      product: c.product,
      details: c.details ?? '',
      currency: c.currency || '$',
      unit: c.unit ?? '',
      listPrice: list,
      floorPrice: floor,
      seller:
        c.seller && c.seller !== interviewer
          ? c.seller
          : interviewer === 'Sam'
            ? 'Kit'
            : 'Sam',
      context: why,
    };
  }
  if (kind === 'picture') {
    const react = c.mode === 'react';
    const seen = react
      ? findStimulus(stimuli, String(c.seed ?? ''))
      : undefined;
    attributes = {
      ...attributes,
      mode: react ? 'react' : 'describe',
      prompt: c.prompt ?? null,
      subject: c.subject ?? null,
      look: seen ? 'ui' : (c.look ?? 'illustration'),
      edits: Number.isFinite(Number(c.edits))
        ? Math.max(0, Math.min(3, Number(c.edits)))
        : 2,
      editPrompt: c.editPrompt ?? null,
      seed: seen ? null : (c.seed ?? null),
      seedImage: seen?.image ?? null,
      questions: strs(c.questions).slice(0, 3).join('\n') || null,
    };
  }
  if (kind === 'video') {
    const seen = findStimulus(stimuli, String(c.video ?? ''));
    const file =
      seen?.video ??
      (/^https?:\/\//.test(String(c.video ?? '')) ? String(c.video) : '');
    attributes = {
      ...attributes,
      title: `${participant || 'Interview'} · watching ${seen?.name ?? 'a video'}`,
      brief: [why, c.focus].filter(Boolean).join('. '),
      videoFile: file,
    };
  }
  const [mod, name] = TOOL_MODULES[kind];
  return {
    data: {
      type: 'card',
      attributes,
      meta: { adoptsFrom: { module: new URL(mod, here).href, name } },
    },
  };
}

// who is interviewing: the interviewer card picked (or the brief's first),
// else the brief's own name/persona/avatar fields
export function cast(b: any, host?: any) {
  const h = host ?? b?.hosts?.[0] ?? null;
  const persona = [
    h?.persona,
    b?.persona && (h ? `For this interview: ${b.persona}` : b.persona),
  ]
    .filter(Boolean)
    .join('\n');
  const n = (x: any) => Number(x) || 3;
  return {
    name: h?.name || b?.interviewer || 'Mei',
    persona,
    avatar:
      (h?.portrait ? resolveUrl(h.portrait, h.id) : '') || b?.avatar || null,
    style: {
      warmth: n(h?.warmth),
      humour: n(h?.humour),
      length: n(h?.length),
      formality: n(h?.formality),
    },
  };
}

export function protocolOf(b: any): StudyProtocol {
  return readProtocol(b?.protocol, {
    aims: lines(b?.aims),
    minutes: Number(b?.minutes) || 10,
  });
}

const CONF_NAME: Record<string, string> = {
  none: 'no read yet',
  low: 'a hunch',
  medium: 'fairly sure',
  high: 'sure',
};
const BAND: Record<string, number> = {
  none: 100,
  low: 60,
  medium: 32,
  high: 14,
};
const pct = (n: number) => Math.max(0, Math.min(100, n));

// the running verdict, ready to draw: pairs and scales as a track with a pin
// and an uncertainty band, choices and findings as words
export function readingsOf(p: StudyProtocol, v: Verdict | null) {
  return p.measures.map((m, k) => {
    const r = v?.readings.find((x) => x.i === k + 1);
    const conf = r?.confidence ?? 'none';
    const pos =
      m.kind === 'pair'
        ? ((r?.value ?? 0) + 1) * 50
        : m.kind === 'scale'
          ? (r?.value ?? 0.5) * 100
          : 50;
    const band = BAND[conf] ?? 100;
    return {
      aim: m.aim,
      pair: m.kind === 'pair',
      scale: m.kind === 'scale',
      left: m.kind === 'pair' ? m.poles?.[0] : (m.low ?? 'low'),
      right: m.kind === 'pair' ? m.poles?.[1] : (m.high ?? 'high'),
      lean: r?.lean ?? '',
      conf,
      confName: CONF_NAME[conf] ?? conf,
      known: conf !== 'none',
      unsure: conf !== 'high',
      evidence: r?.evidence ?? [],
      settle: r?.settle ?? '',
      pinStyle: htmlSafe(`left:${pct(pos).toFixed(1)}%`),
      bandStyle: htmlSafe(
        `left:${pct(pos - band / 2).toFixed(1)}%;width:${(pct(pos + band / 2) - pct(pos - band / 2)).toFixed(1)}%`,
      ),
      state: conf === 'none' ? 'open' : conf === 'low' ? 'partial' : 'covered',
      letter: m.letters
        ? conf === 'medium' || conf === 'high'
          ? (r?.value ?? 0) < 0
            ? m.letters[0]
            : m.letters[1]
          : 'x'
        : null,
    };
  });
}
export function codeOf(rows: { letter: string | null }[]) {
  const ls = rows.map((r) => r.letter).filter((l): l is string => l !== null);
  return ls.length >= 2 ? ls.join('') : '';
}

function briefInfo(b: any, host?: any): BriefInfo {
  const who = cast(b, host);
  return {
    title: b?.title ?? '',
    brief: b?.brief ?? '',
    aims: lines(b?.aims),
    mustAsk: lines(b?.mustAsk),
    interviewer: who.name,
    persona: who.persona,
    minutes: Number(b?.minutes) || 10,
    model: b?.model || undefined,
    style: who.style,
    protocol: protocolOf(b),
    stimuli: readStimuli(b?.stimuli, b?.id),
  };
}

// "- [covered] …" lines under ## Aims
function aimStates(dossier: string) {
  const sec = (dossier.split(/^## /m).find((s) => s.startsWith('Aims')) ?? '')
    .split('\n')
    .slice(1);
  return sec
    .map((l) => l.match(/^\s*[-*]\s*\[(open|partial|covered)\]\s*(.*)$/i))
    .filter((m): m is RegExpMatchArray => Boolean(m))
    .filter((m) => !/^must[\s-]*ask/i.test(m[2]))
    .map((m) => ({
      state: m[1].toLowerCase(),
      text: m[2].replace(/\s*\(confidence[^)]*\).*$/i, ''),
    }));
}

// ─── the brief ───────────────────────────────────────────────────────────
class BriefView extends Component<typeof InterviewBrief> {
  @tracked tab: 'start' | 'list' | 'aims' = 'start';
  @tracked name = '';
  @tracked busy = false;
  @tracked error = '';
  @tracked pick = 0;

  get hosts(): any[] {
    return ((this.args.model as any).hosts ?? []).filter(Boolean);
  }
  get chosen() {
    return this.hosts[this.pick] ?? this.hosts[0] ?? null;
  }
  get who() {
    return cast(this.args.model, this.chosen);
  }
  get choices() {
    return this.hosts.map((h, i) => ({
      h,
      i,
      on: h === this.chosen,
      src: resolveUrl(h.portrait, h.id),
    }));
  }
  choose = (i: number) => (this.pick = i);

  setName = (e: Event) => (this.name = (e.target as HTMLInputElement).value);
  key = (ev: Event) => {
    const e = ev as KeyboardEvent;
    if (e.key === 'Enter') this.start();
  };
  start = async () => {
    if (this.busy) return;
    this.busy = true;
    this.error = '';
    try {
      const store = (this.args.context as any)?.store;
      if (!store?.create)
        throw new Error(
          'open the brief from its workspace to start an interview',
        );
      const now = new Date().toISOString();
      const id = await store.create(
        {
          data: {
            type: 'card',
            attributes: {
              participant: this.name.trim() || null,
              status: 'active',
              startedAt: now,
              updatedAt: now,
              turns: '[]',
              dossier: '',
            },
            relationships: {
              brief: { links: { self: (this.args.model as any).id } },
              ...(this.chosen?.id
                ? { host: { links: { self: this.chosen.id } } }
                : {}),
            },
            meta: {
              adoptsFrom: {
                module: new URL('./interview', here).href,
                name: 'Interview',
              },
            },
          },
        } as any,
        { realm: this.args.model[realmURL]?.href },
      );
      if (typeof id !== 'string')
        throw new Error((id as any)?.message ?? 'could not start');
      this.name = '';
      this.args.viewCard?.(new URL(id) as any, 'isolated');
    } catch (e: any) {
      this.error = `${e?.message ?? e}`;
    }
    this.busy = false;
  };
  writeAims = async () => {
    this.busy = true;
    this.error = '';
    try {
      const aims = await draftAims(
        toolCtx(this.args.context),
        this.args.model.title ?? '',
        this.args.model.brief ?? '',
      );
      if (aims.length) this.args.model.aims = aims.join('\n');
    } catch (e: any) {
      this.error = `${e?.message ?? e}`;
    }
    this.busy = false;
  };
  get aims() {
    return lines(this.args.model.aims);
  }
  get p(): StudyProtocol {
    return protocolOf(this.args.model);
  }
  setP = (key: string, value: any) => {
    this.args.model.protocol = JSON.stringify({ ...this.p, [key]: value });
  };
  get designRows() {
    const p: any = this.p;
    const row = (key: string, label: string, choices: [any, string][]) => ({
      key,
      label,
      choices: choices.map(([value, l]) => ({
        value,
        label: l,
        on: p[key] === value,
      })),
    });
    return [
      row('reveal', 'At the end they see', [
        ['full', 'Their result + evidence'],
        ['summary', 'A short result'],
        ['none', 'Just thanks'],
      ]),
      row('rapport', 'Interviewer warmth', [
        ['warm', 'Warm'],
        ['balanced', 'Balanced'],
        ['strict', 'Strict (no reactions)'],
      ]),
      row('adapt', 'Style', [
        [true, 'Adapts to each person'],
        [false, 'Same for everyone'],
      ]),
      row('warmup', 'Warm-up questions', [
        [0, 'None'],
        [1, 'One'],
        [2, 'Two'],
      ]),
      row('offerMore', 'With a fair read', [
        [true, 'Offer to stop or go on'],
        [false, 'Just finish'],
      ]),
      row('showAims', 'Aim dots', [
        [true, 'Shown'],
        [false, 'Hidden'],
      ]),
      row('showNotes', "Interviewer's notes", [
        [true, 'Visible (testing)'],
        [false, 'Hidden until the end'],
      ]),
    ];
  }
  get toolRows() {
    const on = new Set(this.p.tools);
    return (Object.keys(TOOL_NAMES) as ToolKind[]).map((k) => ({
      k,
      name: TOOL_NAMES[k],
      on: on.has(k),
    }));
  }
  toggleTool = (k: ToolKind) => {
    const on = new Set(this.p.tools);
    if (on.has(k)) on.delete(k);
    else on.add(k);
    this.setP(
      'tools',
      (Object.keys(TOOL_NAMES) as ToolKind[]).filter((x) => on.has(x)),
    );
  };
  get measureRows() {
    return this.p.measures.map((m) => ({
      kind: m.kind,
      aim: m.aim,
      detail: m.poles
        ? `${m.poles[0]}${m.letters ? ` ${m.letters[0]}` : ''} ↔ ${m.poles[1]}${m.letters ? ` ${m.letters[1]}` : ''}`
        : m.options
          ? m.options.join(' / ')
          : m.kind === 'scale'
            ? `${m.low ?? 'low'} → ${m.high ?? 'high'}`
            : '',
    }));
  }
  get screens(): Stimulus[] {
    return readStimuli(this.args.model.stimuli, (this.args.model as any).id);
  }
  get described() {
    return this.screens.filter((x) => x.summary).length;
  }
  @tracked describing = '';
  describe = async () => {
    this.error = '';
    let list = this.screens;
    try {
      for (let k = 0; k < list.length; k++) {
        if (list[k].summary && list[k].regions?.length) continue;
        this.describing = `Describing ${list[k].name} (${k + 1} of ${list.length})…`;
        list = [...list];
        list[k] = await describeStimulus(toolCtx(this.args.context), list[k]);
        this.args.model.stimuli = JSON.stringify(list);
      }
    } catch (e: any) {
      this.error = `${e?.message ?? e}`;
    }
    this.describing = '';
  };
  design = async () => {
    this.busy = true;
    this.error = '';
    try {
      const m = this.args.model;
      const p = await designStudy(
        toolCtx(this.args.context),
        m.title ?? '',
        m.brief ?? '',
        lines(m.aims),
        lines(m.mustAsk),
      );
      m.protocol = JSON.stringify(p);
    } catch (e: any) {
      this.error = `${e?.message ?? e}`;
    }
    this.busy = false;
  };

  get realms() {
    const r = this.args.model[realmURL];
    return r ? [r.href] : [];
  }
  sessions = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: {
            module: new URL('./interview', here).href,
            name: 'Interview',
          },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  get interviews(): any[] {
    const id = (this.args.model as any).id;
    return ((this.sessions?.instances ?? []) as any[])
      .filter((r) => r.brief?.id === id)
      .sort((a, b) =>
        String(b.startedAt ?? '').localeCompare(String(a.startedAt ?? '')),
      );
  }
  // the researcher's canvas for this brief: open it, or make it the first time
  analysesQ = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: {
            module: new URL('./analysis', here).href,
            name: 'StudyAnalysis',
          },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  openAnalysis = async () => {
    const id = (this.args.model as any).id;
    const found = ((this.analysesQ?.instances ?? []) as any[]).find(
      (a) => a?.brief?.id === id,
    );
    if (found) {
      this.args.viewCard?.(found, 'isolated');
      return;
    }
    try {
      const store = (this.args.context as any)?.store;
      const made = await store.create(
        {
          data: {
            type: 'card',
            attributes: { includeTests: true },
            relationships: { brief: { links: { self: id } } },
            meta: {
              adoptsFrom: {
                module: new URL('./analysis', here).href,
                name: 'StudyAnalysis',
              },
            },
          },
        } as any,
        { realm: this.args.model[realmURL]?.href },
      );
      if (typeof made !== 'string')
        throw new Error((made as any)?.message ?? 'could not make it');
      this.args.viewCard?.(new URL(made) as any, 'isolated');
    } catch (e: any) {
      this.error = `${e?.message ?? e}`;
    }
  };
  showStart = () => (this.tab = 'start');
  showList = () => (this.tab = 'list');
  showAims = () => (this.tab = 'aims');
  open = (card: any) => this.args.viewCard?.(card, 'isolated');

  <template>
    <article class='ib'>
      <header class='hero'>
        <span class='face'><Avatar
            @src={{this.who.avatar}}
            @name={{this.who.name}}
          /></span>
        <div>
          <p class='kicker'>Interview · with
            {{this.who.name}}
            · about
            {{this.p.minutes}}
            min</p>
          <h1>{{@model.cardTitle}}</h1>
        </div>
      </header>
      <nav class='tabs' aria-label='View'>
        <button
          type='button'
          class={{if (eq this.tab 'start') 'on'}}
          {{on 'click' this.showStart}}
        >Start</button>
        <button
          type='button'
          class={{if (eq this.tab 'list') 'on'}}
          {{on 'click' this.showList}}
        >Interviews · {{this.interviews.length}}</button>
        <button
          type='button'
          class={{if (eq this.tab 'aims') 'on'}}
          {{on 'click' this.showAims}}
        >Brief &amp; aims</button>
      </nav>

      {{#if (eq this.tab 'start')}}
        <section class='panel'>
          {{#if this.choices.length}}
            {{#if (gt this.choices.length 1)}}
              <div class='cast'>
                <p class='ck'>Who would you like to talk to?</p>
                {{#each this.choices as |c|}}
                  <button
                    type='button'
                    aria-pressed={{if c.on 'true' 'false'}}
                    class='who {{if c.on "on"}}'
                    {{on 'click' (fn this.choose c.i)}}
                  >
                    <span class='face md'><Avatar
                        @src={{c.src}}
                        @name={{c.h.name}}
                      /></span>
                    <span class='wt'><b>{{c.h.name}}</b><span
                      >{{c.h.persona}}</span></span>
                  </button>
                {{/each}}
              </div>
            {{/if}}
          {{/if}}
          <p class='lead'>{{if
              this.p.intro
              this.p.intro
              'A short chat. There are no right answers.'
            }}
            You'll be talking with
            {{this.who.name}}, for about
            {{this.p.minutes}}
            minutes, and you can stop whenever you like.</p>
          {{#if this.p.purpose}}<p class='muted small'>What it's for:
              {{this.p.purpose}}</p>{{/if}}
          <label class='field'>
            <span>Your first name or a nickname</span>
            <input
              type='text'
              value={{this.name}}
              autocomplete='given-name'
              {{on 'input' this.setName}}
              {{on 'keydown' this.key}}
            />
          </label>
          <div class='actions'><button
              type='button'
              class='primary'
              disabled={{this.busy}}
              {{on 'click' this.start}}
            >{{if this.busy 'Starting…' 'Start the interview'}}</button></div>
        </section>
      {{else if (eq this.tab 'list')}}
        <section class='list'>
          <div class='actions'><button
              type='button'
              class='quiet'
              {{on 'click' this.openAnalysis}}
            >Open the analysis</button><span class='muted small'>A canvas for
              the researcher, with an analyst to ask.</span></div>
          {{#each this.interviews as |iv|}}
            <button
              type='button'
              class='rowbtn'
              {{on 'click' (fn this.open iv)}}
            >
              <b>{{if iv.participant iv.participant 'Anonymous'}}</b>
              <span class='st {{iv.status}}'>{{iv.status}}</span>
              <span class='lbl'>{{iv.resultLabel}}</span>
            </button>
          {{else}}
            <p class='muted'>No interviews yet.</p>
          {{/each}}
        </section>
      {{else}}
        <section class='panel'>
          <h2>What we want to learn</h2>
          <p class='lead'>{{@model.brief}}</p>
          <h2>Aims</h2>
          {{#if this.aims.length}}
            <ol class='aims'>{{#each this.aims as |aim|}}<li
                >{{aim}}</li>{{/each}}</ol>
          {{else}}
            <p class='muted'>No aims yet. The interviewer will work them out
              from the brief, or draft them here to check first.</p>
          {{/if}}
          <div class='actions'>
            <button
              type='button'
              class='quiet'
              disabled={{this.busy}}
              {{on 'click' this.writeAims}}
            >{{if
                this.busy
                'Drafting…'
                (if
                  this.aims.length
                  'Redraft the aims with AI'
                  'Draft the aims with AI'
                )
              }}</button>
            <span class='muted small'>Edit the brief, aims, interviewer and
              avatar with the pencil.</span>
          </div>
          {{#if this.screens.length}}
            <h2>Screens it can show · {{this.screens.length}}</h2>
            <p class='muted small'>Participants only see "Screen 1, 2…", never
              where a screen came from.
              {{this.described}}
              of
              {{this.screens.length}}
              described, so the interviewer can point at their parts.</p>
            <div class='scr'>
              {{#each this.screens as |sc|}}
                <div class='sc'><MediaView @item={{sc}} @play={{false}} /><p
                    class='scl'
                  >{{sc.source}} · {{sc.label}}</p></div>
              {{/each}}
            </div>
            <div class='actions'>
              <button
                type='button'
                class='quiet'
                disabled={{if this.describing true false}}
                {{on 'click' this.describe}}
              >{{if
                  this.describing
                  this.describing
                  'Describe the screens with AI'
                }}</button>
            </div>
          {{/if}}
          <h2>Study design</h2>
          <p class='muted small'>{{if
              this.p.rationale
              this.p.rationale
              'Defaults for a short, friendly interview. Draft a design from the brief, then adjust.'
            }}</p>
          <div class='sd'>
            {{#each this.designRows as |row|}}
              <div class='opt'>
                <span class='ol'>{{row.label}}</span>
                <div class='seg' role='group' aria-label={{row.label}}>
                  {{#each row.choices as |ch|}}
                    <button
                      type='button'
                      class={{if ch.on 'on'}}
                      aria-pressed={{if ch.on 'true' 'false'}}
                      {{on 'click' (fn this.setP row.key ch.value)}}
                    >{{ch.label}}</button>
                  {{/each}}
                </div>
              </div>
            {{/each}}
            <div class='opt'>
              <span class='ol'>Tools it may use</span>
              <div class='seg' role='group' aria-label='Tools it may use'>
                {{#each this.toolRows as |tr|}}
                  <button
                    type='button'
                    class={{if tr.on 'on'}}
                    aria-pressed={{if tr.on 'true' 'false'}}
                    {{on 'click' (fn this.toggleTool tr.k)}}
                  >{{tr.name}}</button>
                {{/each}}
              </div>
            </div>
          </div>
          <h2>What each interview measures</h2>
          <ol class='aims ms'>
            {{#each this.measureRows as |ms|}}
              <li><span class='kind'>{{ms.kind}}</span>
                {{ms.aim}}{{#if ms.detail}}
                  <span class='muted small'>({{ms.detail}})</span>{{/if}}</li>
            {{/each}}
          </ol>
          <div class='actions'>
            <button
              type='button'
              class='quiet'
              disabled={{this.busy}}
              {{on 'click' this.design}}
            >{{if this.busy 'Designing…' 'Design the study with AI'}}</button>
            <span class='muted small'>Reads the brief and aims, and sets all of
              the above with its reasons.</span>
          </div>
        </section>
      {{/if}}
      {{#if this.error}}<p class='err' role='alert'>{{this.error}}</p>{{/if}}
    </article>
    <style scoped>
      .ib {
        min-height: 100%;
        box-sizing: border-box;
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 20px;
        align-content: start;
        max-width: 820px;
        margin: 0 auto;
        container-type: inline-size;
        background: #fbfaf7;
        color: #1d1c1a;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
      }
      .hero {
        display: flex;
        gap: 16px;
        align-items: center;
      }
      .face {
        flex: none;
        width: 64px;
        height: 64px;
      }
      .cast {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 8px;
      }
      .ck {
        grid-column: 1 / -1;
        margin: 0;
        font-size: 13px;
        color: #6b675f;
      }
      .who {
        display: flex;
        gap: 12px;
        align-items: center;
        text-align: left;
        padding: 10px 12px;
        border-radius: 12px;
        border: 1px solid #e4e0d8;
        background: #fbfaf7;
        color: #1d1c1a;
        cursor: pointer;
        font: inherit;
      }
      .who.on {
        border-color: #1d1c1a;
        box-shadow: inset 0 0 0 1px #1d1c1a;
        background: #fff;
      }
      .face.md {
        width: 48px;
        height: 48px;
      }
      .wt {
        display: grid;
        gap: 2px;
        min-width: 0;
      }
      .wt b {
        font-size: 15px;
      }
      .wt span {
        font-size: 12px;
        line-height: 1.4;
        color: #6b675f;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .kicker {
        margin: 0;
        color: #6b675f;
        font-size: 13px;
      }
      h1 {
        margin: 2px 0 0;
        font:
          600 clamp(22px, 3.4cqw, 30px)/1.15 ui-sans-serif,
          system-ui,
          sans-serif;
        letter-spacing: -0.01em;
      }
      h2 {
        margin: 6px 0 0;
        font-size: 12px;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: #6b675f;
      }
      .tabs {
        display: flex;
        gap: 4px;
        padding: 4px;
        border-radius: 10px;
        background: #fff;
        border: 1px solid #e4e0d8;
        justify-self: start;
      }
      .tabs button {
        border: 0;
        background: transparent;
        padding: 7px 12px;
        border-radius: 7px;
        font:
          500 13px/1 ui-sans-serif,
          system-ui,
          sans-serif;
        color: #6b675f;
        cursor: pointer;
      }
      .tabs button.on {
        background: #1d1c1a;
        color: #fbfaf7;
      }
      .panel {
        display: grid;
        gap: 14px;
        padding: clamp(18px, 3cqw, 28px);
        border-radius: 14px;
        background: #fff;
        border: 1px solid #e4e0d8;
      }
      .lead {
        margin: 0;
        font-size: 15px;
        line-height: 1.55;
        max-width: 64ch;
      }
      .muted {
        margin: 0;
        color: #6b675f;
      }
      .small {
        font-size: 13px;
      }
      .field {
        display: grid;
        gap: 6px;
        max-width: 360px;
        font-size: 13px;
        color: #6b675f;
      }
      input[type='text'] {
        font:
          400 15px/1.45 ui-sans-serif,
          system-ui,
          sans-serif;
        padding: 10px 12px;
        border-radius: 9px;
        border: 1px solid #e4e0d8;
        background: #fbfaf7;
        color: #1d1c1a;
      }
      .aims {
        margin: 0;
        padding-left: 20px;
        display: grid;
        gap: 6px;
        line-height: 1.45;
      }
      .sd {
        display: grid;
        gap: 8px;
      }
      .scr {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
        gap: 10px;
      }
      .sc {
        display: grid;
        gap: 4px;
      }
      .scl {
        margin: 0;
        font-size: 11px;
        line-height: 1.35;
        color: #6b675f;
      }
      .opt {
        display: grid;
        grid-template-columns: 150px minmax(0, 1fr);
        gap: 10px;
        align-items: center;
      }
      .ol {
        font-size: 13px;
        color: #6b675f;
      }
      .seg {
        display: flex;
        flex-wrap: wrap;
        gap: 4px;
      }
      .seg button {
        border: 1px solid #e4e0d8;
        background: #fbfaf7;
        color: #1d1c1a;
        padding: 6px 10px;
        border-radius: 7px;
        font:
          500 12px/1.2 ui-sans-serif,
          system-ui,
          sans-serif;
        cursor: pointer;
      }
      .seg button.on {
        background: #1d1c1a;
        color: #fbfaf7;
        border-color: #1d1c1a;
      }
      .kind {
        font:
          600 10px/1 ui-monospace,
          monospace;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        padding: 3px 5px;
        border-radius: 4px;
        background: #f1eee8;
        color: #6b675f;
        vertical-align: 2px;
      }
      @container (max-width: 560px) {
        .opt {
          grid-template-columns: 1fr;
          gap: 4px;
        }
      }
      .actions {
        display: flex;
        gap: 12px;
        flex-wrap: wrap;
        align-items: center;
      }
      .primary,
      .quiet {
        font:
          600 14px/1 ui-sans-serif,
          system-ui,
          sans-serif;
        padding: 11px 16px;
        border-radius: 9px;
        cursor: pointer;
      }
      .primary {
        border: 0;
        background: #1d1c1a;
        color: #fbfaf7;
      }
      .quiet {
        border: 1px solid #e4e0d8;
        background: transparent;
        color: #1d1c1a;
      }
      button:disabled {
        opacity: 0.5;
        cursor: default;
      }
      button:focus-visible {
        outline: 2px solid #e2553b;
        outline-offset: 2px;
      }
      .list {
        display: grid;
        gap: 6px;
      }
      .rowbtn {
        display: flex;
        gap: 12px;
        align-items: center;
        width: 100%;
        text-align: left;
        padding: 11px 14px;
        border-radius: 9px;
        border: 1px solid #e4e0d8;
        background: #fff;
        font:
          500 14px/1.3 ui-sans-serif,
          system-ui,
          sans-serif;
        color: #1d1c1a;
        cursor: pointer;
      }
      .rowbtn:hover {
        border-color: #1d1c1a;
      }
      .st {
        font:
          600 11px/1 ui-monospace,
          monospace;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        padding: 4px 6px;
        border-radius: 5px;
        background: #f1eee8;
        color: #6b675f;
      }
      .st.done {
        background: #1d1c1a;
        color: #fbfaf7;
      }
      .lbl {
        margin-left: auto;
        color: #6b675f;
        font-size: 13px;
      }
      .err {
        margin: 0;
        color: #b3261e;
        font-size: 13px;
      }
    </style>
  </template>
}

class BriefFitted extends Component<typeof InterviewBrief> {
  get who() {
    return cast(this.args.model);
  }
  get names() {
    const hs = (((this.args.model as any).hosts ?? []) as any[])
      .filter(Boolean)
      .map((h) => h.name)
      .filter(Boolean);
    return hs.length ? hs.join(' or ') : this.who.name;
  }
  <template>
    <div class='bf'>
      <span class='face'><Avatar
          @src={{this.who.avatar}}
          @name={{this.who.name}}
        /></span>
      <div class='txt'><b>{{@model.cardTitle}}</b><span>Interview with
          {{this.names}}</span></div>
    </div>
    <style scoped>
      .bf {
        height: 100%;
        box-sizing: border-box;
        padding: 12px 14px;
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
      .face {
        flex: none;
        width: 36px;
        height: 36px;
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

export class InterviewBrief extends CardDef {
  static displayName = 'Interview Brief';
  static icon = MessagesSquareIcon;
  @field title = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: InterviewBrief) {
      return this.title;
    },
  });
  @field brief = contains(TextAreaField); // a few sentences: what we want to learn
  @field aims = contains(TextAreaField); // one per line; the interviewer drafts them if empty
  @field mustAsk = contains(TextAreaField); // one per line, asked in the interviewer's own words
  @field hosts = linksToMany(() => Interviewer); // who participants can pick to talk to; the first is the default
  @field interviewer = contains(StringField); // without hosts: the name they introduce themselves by
  @field persona = contains(TextAreaField); // with hosts: extra manner for this study only
  @field avatar = contains(StringField); // without hosts: image URL
  @field minutes = contains(NumberField); // rough time budget
  @field model = contains(StringField); // the interviewer's model (OpenRouter id); empty: the lab default
  @field protocol = contains(TextAreaField); // JSON: the study design (see study.ts); empty: defaults
  @field stimuli = contains(TextAreaField); // JSON: Stimulus[], the screens this study can show (see stimuli.gts)
  static isolated = BriefView;
  static embedded = BriefFitted;
  static fitted = BriefFitted;
}

// ─── one participant's interview ─────────────────────────────────────────
class InterviewView extends Component<typeof Interview> {
  @tracked turns: Turn[] = [];
  @tracked thinking = false;
  @tracked draft = '';
  @tracked error = '';
  @tracked activeTool: any = null;
  @tracked notesOpen = false;
  host: { respondent: string; done: (r: ToolResult) => void } | null = null;

  constructor(owner: any, args: any) {
    super(owner, args);
    this.turns = parseJson<Turn[]>(this.args.model.turns, []);
    this.resume();
  }

  get b(): BriefInfo {
    return briefInfo(this.args.model.brief, (this.args.model as any).host);
  }
  get p(): StudyProtocol {
    return this.b.protocol;
  }
  get verdict(): Verdict | null {
    return parseJson<Verdict | null>((this.args.model as any).verdict, null);
  }
  get readings() {
    return readingsOf(this.p, this.verdict);
  }
  get code() {
    return codeOf(this.readings);
  }
  get showReadings() {
    return this.done && this.p.reveal === 'full';
  }
  get showResult() {
    return this.done && this.p.reveal !== 'none';
  }
  get canSeeNotes() {
    return this.p.showNotes || this.done;
  }
  get offerOpen() {
    const last = this.turns[this.turns.length - 1];
    return (
      !this.done &&
      !this.thinking &&
      last?.who === 'agent' &&
      Boolean(last.offer)
    );
  }
  keepGoing = () => {
    this.pinned = true;
    this.turns = [
      ...this.turns,
      {
        who: 'person',
        text: "Let's keep going.",
        at: new Date().toISOString(),
      },
    ];
    this.persist();
    this.think(
      'They chose to keep going. Carry on, and end at the next fair read without offering again.',
    );
  };
  stopHere = () => {
    this.pinned = true;
    this.turns = [
      ...this.turns,
      { who: 'person', text: "Let's stop here.", at: new Date().toISOString() },
    ];
    this.persist();
    this.think(
      'They chose to stop here. End now with what you have, honest about what is unsure.',
    );
  };
  get done() {
    return this.args.model.status === 'done';
  }
  get result() {
    return parseJson<{ label: string; text: string } | null>(
      this.args.model.result,
      null,
    );
  }
  // time spent talking, not time since it started: a break (closing the tab,
  // coming back tomorrow) counts as at most two minutes
  get minutes() {
    const times = [
      Date.parse(this.args.model.startedAt ?? ''),
      ...this.turns.map((t) => Date.parse(t.at)),
      Date.now(),
    ].filter((n) => Number.isFinite(n));
    let ms = 0;
    for (let k = 1; k < times.length; k++)
      ms += Math.min(Math.max(0, times[k] - times[k - 1]), 120000);
    return ms / 60000;
  }
  get aims() {
    return this.p.measures.length
      ? this.readings.map((r) => ({ state: r.state, text: r.aim }))
      : aimStates(this.args.model.dossier ?? '');
  }
  get covered() {
    return this.aims.filter((a) => a.state === 'covered').length;
  }
  get aimDots() {
    return this.aims.map((a) => ({ ...a, title: `${a.state}: ${a.text}` }));
  }
  get openTool(): Turn | null {
    const last = this.turns[this.turns.length - 1];
    return last?.who === 'tool' && last.tool?.status === 'open' ? last : null;
  }
  get ToolView(): any {
    const k = this.openTool?.tool?.kind;
    return k ? TOOL_VIEWS[k] : null;
  }
  get rows() {
    const last = this.turns.length - 1;
    return this.turns.map((tn, i) => ({
      ...tn,
      agent: tn.who === 'agent',
      person: tn.who === 'person',
      toolDone: tn.who === 'tool' && tn.tool?.status !== 'open',
      toolLive: tn.who === 'tool' && tn.tool?.status === 'open' && i === last,
      toolName: tn.tool ? TOOL_NAMES[tn.tool.kind] : '',
      media: (tn.show?.ids ?? [])
        .map((id) => findStimulus(this.b.stimuli, id))
        .filter((x): x is Stimulus => Boolean(x))
        .map((x) => {
          const f =
            tn.show?.focus?.id === x.key
              ? x.regions?.find((r) => r.name === tn.show?.focus?.region)
              : undefined;
          return { item: x, focus: f?.box ?? null, focusName: f?.name ?? '' };
        }),
      toolNote:
        tn.tool?.status === 'done'
          ? tn.tool.summary
          : tn.tool?.status === 'skipped'
            ? 'Skipped'
            : tn.tool?.status === 'failed'
              ? 'Could not open'
              : '',
    }));
  }
  get canType() {
    return !this.thinking && !this.done && !this.openTool;
  }

  // where to pick up: a fresh interview starts; an open tool comes back; a
  // reply nobody answered gets answered (by whichever agent is here now)
  private async resume() {
    if (this.done) return;
    if (!this.turns.length) {
      this.openPortrait(); // the talking portrait comes up beside the chat, once, at the start
      await this.think(
        'The interview is starting. Greet them by name, introduce yourself and what this is about in a sentence or two, then ask your first question.',
      );
      return;
    }
    const last = this.turns[this.turns.length - 1];
    if (last.who === 'tool' && last.tool?.status === 'open') {
      await this.loadTool(last.tool);
      return;
    }
    if (last.who !== 'agent')
      await this.think(
        'Picking up after an interruption. Answer what is above and carry on.',
      );
  }

  private persist(extra: Record<string, any> = {}) {
    const m = this.args.model as any;
    m.turns = JSON.stringify(this.turns);
    m.updatedAt = new Date().toISOString();
    for (const [k, v] of Object.entries(extra)) m[k] = v;
  }

  private async think(event: string) {
    if (this.thinking) return;
    this.thinking = true;
    this.error = '';
    try {
      const d = await nextTurn(
        toolCtx(this.args.context),
        this.b,
        this.args.model.participant ?? '',
        this.args.model.dossier ?? '',
        this.turns,
        event,
        this.minutes,
        this.verdict,
      );
      const at = new Date().toISOString();
      this.turns = [
        ...this.turns,
        {
          who: 'agent',
          text: d.say,
          at,
          ...(d.offer ? { offer: true } : {}),
          ...(d.show ? { show: d.show } : {}),
        },
      ];
      performLine(
        this.b.interviewer,
        d.say,
        this.turns.length <= 1 ? 8000 : 600,
      ); // the first line waits for the portrait to open
      if (d.verdict)
        (this.args.model as any).verdict = JSON.stringify(d.verdict);
      if (d.end) {
        this.persist({
          dossier: d.dossier,
          status: 'done',
          result: d.result ? JSON.stringify(d.result) : null,
        });
      } else if (d.tool) {
        const call: ToolCall = {
          kind: d.tool.kind,
          why: d.tool.why,
          config: d.tool.config,
          status: 'open',
        };
        this.turns = [...this.turns, { who: 'tool', text: '', at, tool: call }];
        this.persist({ dossier: d.dossier });
        await this.openNewTool(call);
      } else {
        this.persist({ dossier: d.dossier });
      }
    } catch (e: any) {
      this.error =
        e?.message === SESSION_EXPIRED
          ? SESSION_EXPIRED
          : `The interviewer lost the thread (${e?.message ?? e}).`;
    }
    this.thinking = false;
  }

  private async openNewTool(call: ToolCall) {
    try {
      const store = (this.args.context as any)?.store;
      const card = await store.add(
        toolDoc(
          call.kind,
          call.why,
          call.config,
          this.args.model.participant ?? '',
          this.b.interviewer,
          this.b.stimuli,
        ),
        { realm: this.args.model[realmURL]?.href },
      );
      if (!card?.id) throw new Error(card?.message ?? 'not saved');
      call.questionId = card.id;
      this.persist();
      this.mount(card);
    } catch {
      call.status = 'failed';
      this.turns = [...this.turns];
      this.persist();
    }
  }

  private async loadTool(call: ToolCall) {
    try {
      if (!call.questionId) throw new Error('no card');
      const card = await (this.args.context as any)?.store.get(call.questionId);
      if (!card?.id) throw new Error('not found');
      this.mount(card);
    } catch {
      call.status = 'failed';
      this.turns = [...this.turns];
      this.persist();
      await this.think('The tool could not be reopened. Carry on without it.');
    }
  }

  private mount(card: any) {
    this.host = {
      respondent: this.args.model.participant ?? '',
      done: this.toolDone,
    };
    this.activeTool = card;
  }

  toolDone = (r: ToolResult) => {
    this.pinned = true;
    const last = this.openTool;
    if (!last?.tool) return;
    last.tool.status = 'done';
    last.tool.summary = r.summary;
    if (r.image) last.tool.image = r.image;
    last.tool.responseId = r.responseId;
    this.turns = [...this.turns];
    this.activeTool = null;
    this.persist();
    this.think(
      `They finished the ${last.tool.kind} tool; its result is the last turn.`,
    );
  };
  skipTool = () => {
    const last = this.openTool;
    if (!last?.tool) return;
    last.tool.status = 'skipped';
    this.turns = [...this.turns];
    this.activeTool = null;
    this.persist();
    this.think(
      'They skipped the tool. Do not push it; ask in words or move on.',
    );
  };

  setDraft = (e: Event) =>
    (this.draft = (e.target as HTMLTextAreaElement).value);
  key = (ev: Event) => {
    const e = ev as KeyboardEvent;
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.send();
    }
  };
  send = () => {
    this.pinned = true;
    const text = this.draft.trim();
    if (!text || !this.canType) return;
    this.draft = '';
    this.turns = [
      ...this.turns,
      { who: 'person', text, at: new Date().toISOString() },
    ];
    this.persist();
    this.think('They replied (last turn).');
  };
  retry = () =>
    this.think('Your last attempt failed. Carry on from the last turn.');
  wrapUp = () => {
    this.pinned = true;
    if (!this.canType) return;
    this.turns = [
      ...this.turns,
      {
        who: 'person',
        text: "I'd like to finish here, please.",
        at: new Date().toISOString(),
      },
    ];
    this.persist();
    this.think(
      'They asked to finish now. End the interview with what you have.',
    );
  };
  toggleNotes = () => (this.notesOpen = !this.notesOpen);
  openCard = (id: string | undefined) => {
    if (id) this.args.viewCard?.(new URL(id) as any, 'isolated');
  };

  // keep the newest message in view: scroll whenever the chat grows (a new
  // turn, a picture finishing loading, a tool drawing itself), unless they've
  // scrolled up to read; sending a message pins it to the bottom again
  private pinned = true;
  follow = modifier(
    (el: HTMLElement, [_n, _t, _o]: [number, boolean, boolean]) => {
      if (this.pinned) el.scrollIntoView({ block: 'end' });
    },
  );
  stick = modifier((chat: Element) => {
    const end = chat.querySelector('.end') as HTMLElement | null;
    let scroller: HTMLElement | null = chat.parentElement;
    while (
      scroller &&
      !/(auto|scroll)/.test(getComputedStyle(scroller).overflowY)
    )
      scroller = scroller.parentElement;
    const onScroll = () => {
      if (scroller)
        this.pinned =
          scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight <
          200;
    };
    scroller?.addEventListener('scroll', onScroll, { passive: true });
    const ro = new ResizeObserver(() => {
      if (this.pinned) end?.scrollIntoView({ block: 'end' });
    });
    ro.observe(chat);
    return () => {
      ro.disconnect();
      scroller?.removeEventListener('scroll', onScroll);
    };
  });

  // the interviewer's Living Portrait, if they have one: it opens in the side
  // stack; closing it is fine, and their picture in the chat brings it back
  get portrait(): string {
    const h =
      (this.args.model as any).host ?? this.args.model.brief?.hosts?.[0];
    return h?.livingPortrait ? resolveUrl(h.livingPortrait, h.id) : '';
  }
  openPortrait = () => {
    if (!this.portrait) return;
    try {
      (this.args.viewCard as any)?.(new URL(this.portrait), 'isolated', {
        openCardInRightMostStack: true,
      });
    } catch {
      // a view without stacks (e.g. a preview): the chat works without it
    }
  };
  get avatar() {
    return cast(this.args.model.brief, (this.args.model as any).host).avatar;
  }
  get barStyle() {
    const n = this.aims.length || 1;
    return htmlSafe(`width:${((this.covered / n) * 100).toFixed(0)}%`);
  }

  <template>
    <article class='iv {{if this.notesOpen "with-notes"}}'>
      <header class='bar'>
        {{#if this.portrait}}
          <button
            type='button'
            class='face facebtn'
            title='Show {{this.b.interviewer}}'
            aria-label='Show {{this.b.interviewer}} talking, beside the chat'
            {{on 'click' this.openPortrait}}
          ><Avatar @src={{this.avatar}} @name={{this.b.interviewer}} /></button>
        {{else}}
          <span class='face'><Avatar
              @src={{this.avatar}}
              @name={{this.b.interviewer}}
            /></span>
        {{/if}}
        <div class='who'>
          <b>{{this.b.interviewer}}</b>
          <span>{{this.b.title}}{{#if @model.participant}}
              · with
              {{@model.participant}}{{/if}}</span>
        </div>
        {{#if (if this.p.showAims this.aims.length false)}}
          <div class='prog' title='Aims covered'>
            <span class='dots'>{{#each this.aimDots as |ad|}}<i
                  class='dot {{ad.state}}'
                  title={{ad.title}}
                ></i>{{/each}}</span>
            <span class='pn'>{{this.covered}}/{{this.aims.length}} aims</span>
          </div>
        {{/if}}
        {{#if this.canSeeNotes}}
          <button
            type='button'
            class='notes-btn {{if this.notesOpen "on"}}'
            aria-pressed={{if this.notesOpen 'true' 'false'}}
            {{on 'click' this.toggleNotes}}
          >Interviewer's notes</button>
        {{/if}}
      </header>

      <div class='body'>
        <section class='chat' aria-live='polite' {{this.stick}}>
          {{#each this.rows as |tn|}}
            {{#if tn.agent}}
              <div class='msg agent'>{{#if this.portrait}}<button
                    type='button'
                    class='face sm facebtn'
                    title='Show {{this.b.interviewer}}'
                    aria-label='Show {{this.b.interviewer}} talking'
                    {{on 'click' this.openPortrait}}
                  ><Avatar
                      @src={{this.avatar}}
                      @name={{this.b.interviewer}}
                    /></button>{{else}}<span class='face sm'><Avatar
                      @src={{this.avatar}}
                      @name={{this.b.interviewer}}
                    /></span>{{/if}}<p>{{tn.text}}</p></div>
              {{#if tn.media.length}}
                <div class='shown n{{tn.media.length}}'>
                  {{#each tn.media as |md|}}<MediaView
                      @item={{md.item}}
                      @focus={{md.focus}}
                      @focusName={{md.focusName}}
                    />{{/each}}
                </div>
              {{/if}}
            {{else if tn.person}}
              <div class='msg person'><p>{{tn.text}}</p></div>
            {{else if tn.toolLive}}
              <div class='tool live'>
                <div class='tool-head'><span
                    class='tk'
                  >{{tn.toolName}}</span><button
                    type='button'
                    class='link'
                    {{on 'click' this.skipTool}}
                  >Skip this</button></div>
                {{#if this.activeTool}}
                  <this.ToolView
                    @model={{this.activeTool}}
                    @context={{@context}}
                    @host={{this.host}}
                  />
                {{else}}
                  <p class='muted'>Opening…</p>
                {{/if}}
              </div>
            {{else if tn.toolDone}}
              <div class='tool done'>
                {{#if tn.tool.image}}<img
                    class='tthumb'
                    src={{tn.tool.image}}
                    alt=''
                  />{{/if}}
                <span class='tk'>{{tn.toolName}}</span>
                <span class='note'>{{tn.toolNote}}</span>
                {{#if tn.tool.responseId}}<button
                    type='button'
                    class='link'
                    {{on 'click' (fn this.openCard tn.tool.responseId)}}
                  >Open</button>{{/if}}
              </div>
            {{/if}}
          {{/each}}
          {{#if this.thinking}}<div class='msg agent'><span
                class='face sm'
              ><Avatar
                  @src={{this.avatar}}
                  @name={{this.b.interviewer}}
                /></span><p class='typing'><i></i><i></i><i
                ></i></p></div>{{/if}}
          {{#if this.offerOpen}}
            <div class='offer'>
              <button
                type='button'
                class='primary'
                {{on 'click' this.stopHere}}
              >{{if
                  (eq this.p.reveal 'none')
                  'Finish here'
                  'Show my result'
                }}</button>
              <button
                type='button'
                class='quiet'
                {{on 'click' this.keepGoing}}
              >Keep going</button>
            </div>
          {{/if}}
          {{#if this.showResult}}
            {{#if this.result}}
              <div class='result'>
                <p class='rk'>Your result{{#if this.code}}
                    ·
                    {{this.code}}{{/if}}</p>
                <p class='rl'>{{this.result.label}}</p>
                <p class='rt'>{{this.result.text}}</p>
                {{#if this.showReadings}}
                  <div class='onink'><ul class='rd'>
                      {{#each this.readings as |rd|}}
                        <li class='rdi {{rd.conf}}'>
                          <p class='ra'>{{rd.aim}}
                            <span class='cf'>{{rd.confName}}</span></p>
                          {{#if rd.pair}}
                            <div class='pole'><span>{{rd.left}}</span><span
                                class='track'
                              ><span
                                  class='band'
                                  style={{rd.bandStyle}}
                                ></span>{{#if rd.known}}<span
                                    class='pin'
                                    style={{rd.pinStyle}}
                                  ></span>{{/if}}</span><span
                              >{{rd.right}}</span></div>
                          {{else if rd.scale}}
                            <div class='pole'><span>{{rd.left}}</span><span
                                class='track'
                              ><span
                                  class='band'
                                  style={{rd.bandStyle}}
                                ></span>{{#if rd.known}}<span
                                    class='pin'
                                    style={{rd.pinStyle}}
                                  ></span>{{/if}}</span><span
                              >{{rd.right}}</span></div>
                          {{else}}
                            <p class='lean'>{{if
                                rd.lean
                                rd.lean
                                'Not known yet'
                              }}</p>
                          {{/if}}
                          {{#if rd.evidence.length}}<p class='ev'>{{#each
                                rd.evidence
                                as |ev idx|
                              }}{{if idx ' · '}}“{{ev}}”{{/each}}</p>{{/if}}
                          {{#if rd.settle}}{{#if rd.unsure}}<p class='st'>Would
                                settle it:
                                {{rd.settle}}</p>{{/if}}{{/if}}
                        </li>
                      {{/each}}
                    </ul>
                  </div>
                {{/if}}
              </div>
            {{/if}}
          {{else if this.done}}
            <div class='result plain'><p class='rl'>Thank you</p><p
                class='rt'
              >That's everything. Your answers help more than you'd think.</p></div>
          {{/if}}
          {{#if this.error}}<p class='err' role='alert'>{{this.error}}
              <button type='button' class='link' {{on 'click' this.retry}}>Try
                again</button></p>{{/if}}
          <span
            class='end'
            {{this.follow this.turns.length this.thinking this.notesOpen}}
          ></span>
        </section>

        {{#if this.notesOpen}}
          <aside class='notes' aria-label="The interviewer's notes">
            <p class='nk'>Running verdict{{#if this.code}}
                ·
                {{this.code}}{{/if}}{{#if this.verdict.style}}
                · style:
                {{this.verdict.style}}{{/if}}</p>
            <ul class='rd'>
              {{#each this.readings as |rd|}}
                <li class='rdi {{rd.conf}}'>
                  <p class='ra'>{{rd.aim}}
                    <span class='cf'>{{rd.confName}}</span></p>
                  {{#if rd.pair}}
                    <div class='pole'><span>{{rd.left}}</span><span
                        class='track'
                      ><span class='band' style={{rd.bandStyle}}></span>{{#if
                          rd.known
                        }}<span
                            class='pin'
                            style={{rd.pinStyle}}
                          ></span>{{/if}}</span><span>{{rd.right}}</span></div>
                  {{else if rd.scale}}
                    <div class='pole'><span>{{rd.left}}</span><span
                        class='track'
                      ><span class='band' style={{rd.bandStyle}}></span>{{#if
                          rd.known
                        }}<span
                            class='pin'
                            style={{rd.pinStyle}}
                          ></span>{{/if}}</span><span>{{rd.right}}</span></div>
                  {{else}}
                    <p class='lean'>{{if rd.lean rd.lean 'Not known yet'}}</p>
                  {{/if}}
                  {{#if rd.evidence.length}}<p class='ev'>{{#each
                        rd.evidence
                        as |ev idx|
                      }}{{if idx ' · '}}“{{ev}}”{{/each}}</p>{{/if}}
                  {{#if rd.settle}}{{#if rd.unsure}}<p class='st'>Would settle
                        it:
                        {{rd.settle}}</p>{{/if}}{{/if}}
                </li>
              {{/each}}
            </ul>

            {{#if (if this.done (eq this.p.reveal 'none') false)}}{{#if
                this.result
              }}<p class='researcher'><b>{{this.result.label}}</b>
                  {{this.result.text}}</p>{{/if}}{{/if}}
            <p class='nk'>The dossier · rewritten every turn · any interviewer
              can carry on from it</p>
            {{#if @model.dossier}}<div class='md'><@fields.dossier
                /></div>{{else}}<p class='muted'>Empty until the first turn.</p>{{/if}}
          </aside>
        {{/if}}
      </div>

      {{#if this.done}}
        <footer class='composer closed'><p class='muted'>This interview is
            finished. Thank you.</p></footer>
      {{else}}
        <footer class='composer'>
          <textarea
            rows='2'
            placeholder={{if
              this.openTool
              'Answer the question above, or skip it'
              'Type your answer…'
            }}
            aria-label='Your answer'
            value={{this.draft}}
            disabled={{if this.canType false true}}
            {{on 'input' this.setDraft}}
            {{on 'keydown' this.key}}
          ></textarea>
          <button
            type='button'
            class='primary'
            disabled={{if this.canType false true}}
            {{on 'click' this.send}}
          >Send</button>
          <button
            type='button'
            class='link'
            disabled={{if this.canType false true}}
            {{on 'click' this.wrapUp}}
          >Finish</button>
        </footer>
      {{/if}}
    </article>
    <style scoped>
      .iv {
        --ink: #1d1c1a;
        --paper: #fbfaf7;
        --muted: #6b675f;
        --rule: #e4e0d8;
        --live: #e2553b;
        min-height: 100%;
        box-sizing: border-box;
        display: grid;
        grid-template-rows: auto 1fr auto;
        background: var(--paper);
        color: var(--ink);
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
        container-type: inline-size;
      }
      .bar {
        position: sticky;
        top: 0;
        z-index: 2;
        display: flex;
        gap: 12px;
        align-items: center;
        padding: 12px clamp(14px, 3cqw, 28px);
        background: rgba(251, 250, 247, 0.94);
        backdrop-filter: blur(6px);
        border-bottom: 1px solid var(--rule);
      }
      .face {
        flex: none;
        width: 42px;
        height: 42px;
      }
      .face.sm {
        width: 30px;
        height: 30px;
      }
      .facebtn {
        padding: 0;
        border: 0;
        background: none;
        border-radius: 50%;
        cursor: pointer;
        box-shadow: 0 0 0 2px transparent;
        transition: box-shadow 0.15s;
      }
      .facebtn:hover {
        box-shadow: 0 0 0 2px var(--live);
      }
      .who {
        display: grid;
        min-width: 0;
      }
      .who b {
        font-size: 15px;
      }
      .who span {
        font-size: 13px;
        color: var(--muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .prog {
        margin-left: auto;
        display: flex;
        gap: 8px;
        align-items: center;
      }
      .dots {
        display: flex;
        gap: 4px;
      }
      .dot {
        width: 9px;
        height: 9px;
        border-radius: 50%;
        border: 1.5px solid var(--ink);
        box-sizing: border-box;
      }
      .dot.partial {
        background: linear-gradient(90deg, var(--ink) 50%, transparent 50%);
      }
      .dot.covered {
        background: var(--ink);
      }
      .pn {
        font:
          500 12px/1 ui-monospace,
          monospace;
        color: var(--muted);
        white-space: nowrap;
      }
      .notes-btn {
        border: 1px solid var(--rule);
        background: #fff;
        color: var(--ink);
        padding: 7px 11px;
        border-radius: 8px;
        font:
          500 13px/1 ui-sans-serif,
          system-ui,
          sans-serif;
        cursor: pointer;
        white-space: nowrap;
      }
      .prog + .notes-btn {
        margin-left: 4px;
      }
      .bar > .notes-btn:only-of-type {
        margin-left: auto;
      }
      .notes-btn.on {
        background: var(--ink);
        color: var(--paper);
        border-color: var(--ink);
      }
      .body {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        align-items: start;
      }
      .with-notes .body {
        grid-template-columns: minmax(0, 1fr) minmax(280px, 0.8fr);
      }
      .chat {
        display: grid;
        gap: 14px;
        align-content: start;
        padding: 22px clamp(14px, 3cqw, 28px) 30px;
        max-width: 760px;
        width: 100%;
        margin: 0 auto;
        box-sizing: border-box;
      }
      .msg {
        display: flex;
        gap: 10px;
        align-items: flex-end;
        max-width: 88%;
      }
      .msg p {
        margin: 0;
        padding: 11px 14px;
        border-radius: 16px;
        line-height: 1.5;
        font-size: 15px;
        white-space: pre-wrap;
      }
      .msg.agent p {
        background: #fff;
        border: 1px solid var(--rule);
        border-bottom-left-radius: 5px;
      }
      .msg.person {
        justify-self: end;
      }
      .msg.person p {
        background: var(--ink);
        color: var(--paper);
        border-bottom-right-radius: 5px;
      }
      .typing {
        display: flex;
        gap: 4px;
      }
      .typing i {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: var(--muted);
        animation: blink 1.2s infinite ease-in-out;
      }
      .typing i:nth-child(2) {
        animation-delay: 0.15s;
      }
      .typing i:nth-child(3) {
        animation-delay: 0.3s;
      }
      @keyframes blink {
        0%,
        80%,
        100% {
          opacity: 0.25;
        }
        40% {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .typing i {
          animation: none;
          opacity: 0.6;
        }
      }
      .tool.live {
        display: grid;
        gap: 10px;
        padding: 14px;
        border-radius: 16px;
        background: #fff;
        border: 1px solid var(--ink);
        box-shadow: 0 6px 24px rgba(29, 28, 26, 0.08);
      }
      .tool-head {
        display: flex;
        justify-content: space-between;
        align-items: center;
      }
      .tk {
        font:
          600 11px/1 ui-monospace,
          monospace;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted);
      }
      .tool.done {
        display: flex;
        gap: 10px;
        align-items: baseline;
        padding: 9px 12px;
        border-radius: 10px;
        border: 1px dashed var(--rule);
        font-size: 13px;
        color: var(--muted);
      }
      .tthumb {
        width: 72px;
        height: 54px;
        object-fit: cover;
        border-radius: 6px;
        flex: none;
        align-self: center;
      }
      .tool.done .note {
        flex: 1;
        min-width: 0;
        line-height: 1.45;
      }
      .link {
        border: 0;
        background: none;
        padding: 0;
        color: var(--ink);
        text-decoration: underline;
        text-underline-offset: 3px;
        font:
          500 13px/1.2 ui-sans-serif,
          system-ui,
          sans-serif;
        cursor: pointer;
      }
      .link:disabled {
        opacity: 0.4;
        cursor: default;
      }
      .shown {
        display: grid;
        gap: 10px;
        margin-left: 40px;
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .shown.n1 {
        grid-template-columns: minmax(0, 560px);
      }
      .shown.n3,
      .shown.n4 {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      @container (max-width: 520px) {
        .shown {
          margin-left: 0;
          grid-template-columns: 1fr;
        }
      }
      .offer {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        justify-content: flex-end;
      }
      .quiet {
        font:
          600 14px/1 ui-sans-serif,
          system-ui,
          sans-serif;
        padding: 12px 16px;
        border-radius: 10px;
        border: 1px solid var(--rule);
        background: #fff;
        color: var(--ink);
        cursor: pointer;
      }
      .result.plain {
        background: #fff;
        color: var(--ink);
        border: 1px solid var(--rule);
      }
      .rd {
        list-style: none;
        margin: 4px 0 14px;
        padding: 0;
        display: grid;
        gap: 12px;
      }
      .rdi {
        display: grid;
        gap: 5px;
      }
      .ra {
        margin: 0;
        font-size: 13px;
        font-weight: 600;
        line-height: 1.35;
      }
      .cf {
        font-weight: 500;
        font-size: 11px;
        padding: 2px 6px;
        border-radius: 4px;
        background: #f1eee8;
        color: var(--muted);
        white-space: nowrap;
      }
      .rdi.high .cf,
      .rdi.medium .cf {
        background: #e3f1e8;
        color: #2f7d4f;
      }
      .pole {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 2fr minmax(0, 1fr);
        gap: 8px;
        align-items: center;
        font-size: 11px;
        color: var(--muted);
      }
      .pole > span:last-child {
        text-align: right;
      }
      .track {
        position: relative;
        height: 8px;
        border-radius: 4px;
        background: #f1eee8;
      }
      .band {
        position: absolute;
        top: 0;
        bottom: 0;
        border-radius: 4px;
        background: rgba(29, 28, 26, 0.18);
      }
      .pin {
        position: absolute;
        top: -3px;
        width: 4px;
        height: 14px;
        margin-left: -2px;
        border-radius: 2px;
        background: var(--ink);
      }
      .lean {
        margin: 0;
        font-size: 13px;
      }
      .ev {
        margin: 0;
        font-size: 12px;
        color: var(--muted);
        line-height: 1.4;
      }
      .st {
        margin: 0;
        font-size: 12px;
        color: var(--live);
      }
      .researcher {
        margin: 0 0 14px;
        padding: 10px 12px;
        border-radius: 8px;
        background: #f6f4ef;
        font-size: 13px;
        line-height: 1.45;
      }
      .onink {
        margin-top: 10px;
        padding: 12px 14px;
        border-radius: 12px;
        background: var(--paper);
        color: var(--ink);
      }
      .result {
        margin-top: 6px;
        padding: 20px 22px;
        border-radius: 16px;
        background: var(--ink);
        color: var(--paper);
        display: grid;
        gap: 6px;
      }
      .rk {
        margin: 0;
        font:
          600 11px/1 ui-monospace,
          monospace;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        opacity: 0.7;
      }
      .rl {
        margin: 0;
        font:
          650 26px/1.15 ui-sans-serif,
          system-ui,
          sans-serif;
        letter-spacing: -0.01em;
      }
      .rt {
        margin: 0;
        line-height: 1.55;
        max-width: 60ch;
        opacity: 0.92;
      }
      .notes {
        position: sticky;
        top: 68px;
        margin: 16px clamp(14px, 3cqw, 28px) 16px 0;
        padding: 16px 18px;
        border-radius: 12px;
        background: #fff;
        border: 1px solid var(--rule);
        max-height: calc(100vh - 220px);
        overflow: auto;
        font-size: 13px;
      }
      .nk {
        margin: 0 0 10px;
        font:
          600 11px/1.4 ui-monospace,
          monospace;
        color: var(--live);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .md :deep(h1) {
        font-size: 16px;
        margin: 0 0 8px;
      }
      .md :deep(h2) {
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--muted);
        margin: 14px 0 4px;
      }
      .md :deep(ul),
      .md :deep(ol) {
        margin: 0;
        padding-left: 18px;
      }
      .md :deep(li) {
        margin: 2px 0;
        line-height: 1.45;
      }
      .md :deep(p) {
        margin: 4px 0;
        line-height: 1.45;
      }
      .composer {
        position: sticky;
        bottom: 0;
        display: flex;
        gap: 10px;
        align-items: center;
        padding: 12px clamp(14px, 3cqw, 28px);
        background: rgba(251, 250, 247, 0.96);
        border-top: 1px solid var(--rule);
      }
      .composer textarea {
        flex: 1;
        min-width: 0;
        resize: none;
        font:
          400 15px/1.45 ui-sans-serif,
          system-ui,
          sans-serif;
        padding: 10px 12px;
        border-radius: 12px;
        border: 1px solid var(--rule);
        background: #fff;
        color: var(--ink);
      }
      .composer textarea:focus-visible {
        outline: 2px solid var(--ink);
        outline-offset: 1px;
      }
      .composer.closed {
        justify-content: center;
      }
      .primary {
        font:
          600 14px/1 ui-sans-serif,
          system-ui,
          sans-serif;
        padding: 12px 16px;
        border-radius: 10px;
        border: 0;
        background: var(--ink);
        color: var(--paper);
        cursor: pointer;
      }
      .primary:disabled {
        opacity: 0.4;
        cursor: default;
      }
      button:focus-visible {
        outline: 2px solid var(--live);
        outline-offset: 2px;
      }
      .muted {
        margin: 0;
        color: var(--muted);
      }
      .err {
        margin: 0;
        color: #b3261e;
        font-size: 13px;
      }
      .end {
        display: block;
        height: 1px;
        scroll-margin-bottom: 110px;
      } /* clear of the sticky answer box */
      @container (max-width: 720px) {
        .with-notes .body {
          grid-template-columns: 1fr;
        }
        .notes {
          position: static;
          margin: 0 14px 16px;
          max-height: none;
        }
        .pn {
          display: none;
        }
      }
    </style>
  </template>
}

class InterviewRow extends Component<typeof Interview> {
  get label() {
    return (
      parseJson<{ label: string } | null>(this.args.model.result, null)
        ?.label ?? ''
    );
  }
  <template>
    <div class='ir'>
      <b>{{if @model.participant @model.participant 'Anonymous'}}</b>
      <span>{{@model.status}}{{#if this.label}} · {{this.label}}{{/if}}</span>
    </div>
    <style scoped>
      .ir {
        height: 100%;
        box-sizing: border-box;
        padding: 12px 14px;
        display: grid;
        gap: 4px;
        align-content: start;
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
      span {
        color: #6b675f;
        font-size: 13px;
      }
    </style>
  </template>
}

export class Interview extends CardDef {
  static displayName = 'Interview';
  static icon = MessagesSquareIcon;
  @field brief = linksTo(() => InterviewBrief);
  @field host = linksTo(() => Interviewer); // who the participant picked
  @field participant = contains(StringField);
  @field status = contains(StringField); // active | done
  @field startedAt = contains(StringField);
  @field updatedAt = contains(StringField);
  @field turns = contains(TextAreaField); // JSON: Turn[]
  @field dossier = contains(MarkdownField); // the interviewer's living notes; the report at the end
  @field verdict = contains(TextAreaField); // JSON: the running read of each measure (interviewer-ai.ts Verdict)
  @field result = contains(TextAreaField); // JSON: {label, text}, for the participant
  @field resultLabel = contains(StringField, {
    computeVia: function (this: Interview) {
      try {
        return this.result ? (JSON.parse(this.result)?.label ?? '') : '';
      } catch {
        return '';
      }
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Interview) {
      const who = this.participant || 'Anonymous';
      return this.brief?.cardTitle ? `${who} · ${this.brief.cardTitle}` : who;
    },
  });
  static isolated = InterviewView;
  static embedded = InterviewRow;
  static fitted = InterviewRow;
}
