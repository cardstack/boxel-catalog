// Study Analysis: a researcher's canvas beside a brief. Tiles show the study
// from different sides (each measure across people, groups compared, pooled
// This-or-that, pictures); the analyst agent arranges them in answer to the
// researcher's questions: adds tiles, brings one into focus, tucks others into
// the dock without losing them. Tiles glide between arrangements (glimmer-
// motion layout animation), so a rearranged canvas reads as the same canvas.
// Kept apart from the brief, which stays the participant's page.
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
import BooleanField from '@cardstack/base/boolean';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn, concat } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
// @ts-ignore the host provides glimmer-motion; its types aren't bundled with the CLI
import { motion, styles, LayoutGroup } from 'glimmer-motion';
import ChartIcon from '@cardstack/boxel-icons/layout-dashboard';
import { parseJson, toolCtx, SESSION_EXPIRED } from './tool-kit';
import { InterviewBrief, protocolOf } from './interview';
import { readStimuli } from './stimuli';
import {
  rowsOf,
  compare,
  poolDuels,
  digest,
  FEATURES,
  type Row,
} from './analysis-data';
import {
  ask,
  TILE_KINDS,
  type Tile,
  type Op,
  type Size,
  type ChatLine,
  type Step,
} from './analyst-ai';

// @ts-ignore import.meta is fine here (the host loads cards as ES modules); the catalog's CommonJS type check rejects it
const here: string = import.meta.url;
const SIZES: Size[] = ['s', 'm', 'l', 'xl'];
const pct = (n: number) => Math.max(0, Math.min(100, n));
const BAND: Record<string, number> = {
  none: 100,
  low: 60,
  medium: 32,
  high: 14,
};

class AnalysisView extends Component<typeof StudyAnalysis> {
  @tracked draft = '';
  @tracked busy = false;
  @tracked error = '';
  @tracked duels: { items: string[]; picks: any[] }[] = [];
  private loadedKey = '';

  // ─── the data ──────────────────────────────────────────────────────────
  get brief(): any {
    return this.args.model.brief;
  }
  get p() {
    return protocolOf(this.brief);
  }
  get stimuli() {
    return readStimuli(this.brief?.stimuli, this.brief?.id);
  }
  get realms() {
    const r = this.args.model[realmURL];
    return r ? [r.href] : [];
  }
  interviewsQ = this.args.context?.getCards(
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
  get allRows(): Row[] {
    const id = this.brief?.id;
    const ivs = ((this.interviewsQ?.instances ?? []) as any[]).filter(
      (x) => x?.brief?.id === id,
    );
    return rowsOf(ivs, this.p);
  }
  get rows(): Row[] {
    return this.args.model.includeTests === false
      ? this.allRows.filter((r) => !r.test)
      : this.allRows;
  }
  get testCount() {
    return this.allRows.filter((r) => r.test).length;
  }
  // This or that responses live in their own cards: fetch them once per set
  loadTools = modifier((_el: Element, [key]: [string]) => {
    if (!key || key === this.loadedKey) return;
    this.loadedKey = key;
    const ids = this.rows.flatMap((r) =>
      r.tools
        .filter(
          (t) => t.kind === 'duels' && t.status === 'done' && t.responseId,
        )
        .map((t) => t.responseId!),
    );
    const store = (this.args.context as any)?.store;
    if (!store?.get || !ids.length) return;
    Promise.all(ids.map((id) => store.get(id).catch(() => null))).then(
      (cards: any[]) => {
        this.duels = cards
          .map((c) => parseJson<any>(c?.data, null))
          .filter((d) => d?.items?.length && d?.picks?.length);
      },
    );
  });
  get rowsKey() {
    return this.rows.map((r) => `${r.id}:${r.tools.length}`).join('|');
  }
  get pooled() {
    return poolDuels(this.duels, this.stimuli);
  }

  // ─── the canvas ────────────────────────────────────────────────────────
  // the board starts blank: the analyst puts things on it as it presents
  get tiles(): Tile[] {
    return parseJson<Tile[]>(this.args.model.tiles, []);
  }
  get focusId() {
    return this.args.model.focus ?? '';
  }
  save(tiles: Tile[], focus = this.focusId) {
    this.args.model.tiles = JSON.stringify(tiles);
    (this.args.model as any).focus = focus || null;
  }

  // what each tile draws
  get cards(): any[] {
    const shown = this.tiles.filter((t) => !t.min);
    const ordered = this.focusId
      ? [
          ...shown.filter((t) => t.id === this.focusId),
          ...shown.filter((t) => t.id !== this.focusId),
        ]
      : shown;
    return ordered.map((t) => ({
      id: t.id,
      t,
      focus: t.id === this.focusId,
      ...this.draw(t),
    }));
  }
  get docked() {
    return this.tiles.filter((t) => t.min);
  }
  private draw(t: Tile): Record<string, any> {
    const rows = this.rows;
    const p = this.p;
    if (t.kind === 'participation') {
      const done = rows.filter((r) => r.done).length;
      const avg = rows.length
        ? Math.round(
            (rows.reduce((a, r) => a + r.minutes, 0) / rows.length) * 10,
          ) / 10
        : 0;
      const offered = rows.filter((r) => r.offered);
      return {
        isStats: true,
        stats: [
          {
            big: rows.length,
            small: `people${this.testCount && this.args.model.includeTests !== false ? ` · ${this.testCount} test runs` : ''}`,
          },
          { big: done, small: 'finished' },
          { big: avg, small: 'minutes talking, on average' },
          {
            big: offered.length
              ? `${offered.filter((r) => r.keptGoing).length}/${offered.length}`
              : '–',
            small: 'kept going when offered',
          },
        ],
      };
    }
    if (t.kind === 'interviewers') {
      const hosts = [...new Set(rows.map((r) => r.host || 'Unknown'))];
      return {
        isTable: true,
        head: ['Interviewer', 'People', 'Finished', 'Words/answer'],
        body: hosts.map((h) => {
          const rs = rows.filter((r) => (r.host || 'Unknown') === h);
          return [
            h,
            String(rs.length),
            String(rs.filter((r) => r.done).length),
            String(Math.round(rs.reduce((a, r) => a + r.words, 0) / rs.length)),
          ];
        }),
      };
    }
    if (t.kind === 'measure' || t.kind === 'scatter') {
      if (t.kind === 'scatter') {
        const mx = p.measures[(t.config?.x ?? 1) - 1];
        const my = p.measures[(t.config?.y ?? 2) - 1];
        if (!mx || !my)
          return { isNote: true, text: 'Those measures aren’t in this study.' };
        const pos = (m: any, v: number) =>
          m.kind === 'scale' ? v * 100 : (v + 1) * 50;
        const pts = rows
          .map((r) => ({
            r,
            a: r.readings.find((x) => x.i === t.config.x),
            b: r.readings.find((x) => x.i === t.config.y),
          }))
          .filter(
            (o) =>
              o.a &&
              o.b &&
              o.a.confidence !== 'none' &&
              o.b.confidence !== 'none',
          )
          .map((o) => ({
            who: `P${o.r.n}`,
            title: `P${o.r.n} ${o.r.who}`,
            style: htmlSafe(
              `left:${pct(pos(mx, o.a!.value)).toFixed(1)}%;bottom:${pct(pos(my, o.b!.value)).toFixed(1)}%`,
            ),
          }));
        const ends = (m: any) =>
          m.kind === 'pair' ? m.poles : [m.low ?? 'low', m.high ?? 'high'];
        const [xl, xr] = ends(mx);
        const [yl, yr] = ends(my);
        return {
          isScatter: true,
          pts,
          axes: `→ ${xl} … ${xr} · ↑ ${yl} … ${yr}`,
        };
      }
      const i = Number(t.config?.measure) || 1;
      const m = p.measures[i - 1];
      if (!m)
        return { isNote: true, text: 'That measure isn’t in this study.' };
      if (m.kind === 'pair' || m.kind === 'scale') {
        const dots = rows
          .map((r) => ({ r, rd: r.readings.find((x) => x.i === i) }))
          .filter((o) => o.rd && o.rd.confidence !== 'none')
          .map((o, k) => {
            const v =
              m.kind === 'pair' ? (o.rd!.value + 1) * 50 : o.rd!.value * 100;
            const band = BAND[o.rd!.confidence] ?? 60;
            return {
              who: `P${o.r.n}`,
              title: `P${o.r.n} ${o.r.who}: ${o.rd!.lean || '?'} (${o.rd!.confidence})`,
              conf: o.rd!.confidence,
              lane: htmlSafe(`top:${(k % 6) * 15 + 6}px`),
              dot: htmlSafe(`left:${pct(v).toFixed(1)}%`),
              band: htmlSafe(
                `left:${pct(v - band / 2).toFixed(1)}%;width:${(pct(v + band / 2) - pct(v - band / 2)).toFixed(1)}%`,
              ),
            };
          });
        const ends =
          m.kind === 'pair' ? m.poles! : [m.low ?? 'low', m.high ?? 'high'];
        const sure = rows.filter((r) =>
          ['medium', 'high'].includes(
            r.readings.find((x) => x.i === i)?.confidence ?? '',
          ),
        ).length;
        return {
          isStrip: true,
          dots,
          left: `${ends[0]}${m.letters ? ` (${m.letters[0]})` : ''}`,
          right: `${ends[1]}${m.letters ? ` (${m.letters[1]})` : ''}`,
          foot: `${dots.length} people read · ${sure} fairly sure or sure`,
        };
      }
      const leans = rows
        .map((r) => ({ r, rd: r.readings.find((x) => x.i === i) }))
        .filter((o) => o.rd?.lean);
      return {
        isLeans: true,
        leans: leans.map((o) => ({
          who: `P${o.r.n}`,
          lean: o.rd!.lean,
          conf: o.rd!.confidence,
        })),
      };
    }
    if (t.kind === 'compare') {
      const c = compare(
        rows,
        t.config?.feature ?? 'words',
        t.config?.by ?? 'host',
        p,
      );
      return {
        isBars: true,
        unit: c.name,
        bars: c.groups.map((g) => ({
          label: g.group,
          value: g.mean,
          n: g.n,
          style: htmlSafe(`width:${g.pct}%`),
        })),
      };
    }
    if (t.kind === 'types') {
      const counts = new Map<string, number>();
      for (const r of rows)
        if (r.code) counts.set(r.code, (counts.get(r.code) ?? 0) + 1);
      const max = Math.max(1, ...counts.values());
      return {
        isBars: true,
        unit: 'people',
        bars: [...counts.entries()]
          .sort((a, b) => b[1] - a[1])
          .map(([label, v]) => ({
            label,
            value: v,
            n: v,
            style: htmlSafe(`width:${(v / max) * 100}%`),
          })),
      };
    }
    if (t.kind === 'duels') {
      const d = this.pooled;
      if (!d) return { isNote: true, text: 'No This-or-that rounds yet.' };
      const top = d.ranking.slice(0, 8);
      return {
        isDuels: true,
        rank: top.map((x, k) => ({
          ...x,
          k: k + 1,
          style: htmlSafe(`width:${x.score}%`),
        })),
        sources: d.sources.map((s) => ({
          ...s,
          style: htmlSafe(`width:${s.rate}%`),
        })),
        foot: `${d.people} people · ${d.picks} picks · score = chance of beating an average screen`,
      };
    }
    if (t.kind === 'gallery') {
      const pics = rows.flatMap((r) =>
        r.tools
          .filter((x) => x.kind === 'picture' && x.image)
          .map((x) => ({ who: `P${r.n}`, image: x.image, summary: x.summary })),
      );
      return { isGallery: true, pics };
    }
    if (t.kind === 'videos') {
      return {
        isQuotes: true,
        quotes: rows.flatMap((r) =>
          r.tools
            .filter((x) => x.kind === 'video' && x.summary)
            .map((x) => ({ who: `P${r.n}`, text: x.summary })),
        ),
      };
    }
    if (t.kind === 'quotes')
      return {
        isQuotes: true,
        quotes: (Array.isArray(t.config?.quotes) ? t.config.quotes : []).filter(
          (q: any) => q?.text,
        ),
      };
    return { isNote: true, text: String(t.config?.text ?? '') };
  }

  // ─── moves, by the analyst or by hand ──────────────────────────────────
  apply(ops: Op[]) {
    let tiles = [...this.tiles];
    let focus = this.focusId;
    const at = (id?: string) => tiles.findIndex((t) => t.id === id);
    for (const o of ops) {
      if (o.op === 'add' && o.tile?.kind && TILE_KINDS.includes(o.tile.kind)) {
        let id =
          String(o.tile.id || `t${Date.now().toString(36)}`)
            .replace(/[^\w-]/g, '')
            .slice(0, 24) || 'tile';
        while (at(id) >= 0) id += 'x';
        tiles.push({
          id,
          kind: o.tile.kind,
          title: String(o.tile.title ?? ''),
          size: SIZES.includes(o.tile.size as Size)
            ? (o.tile.size as Size)
            : 'm',
          config: o.tile.config ?? {},
        });
        focus = id; // born big, centre stage; the player settles it into its slot
        this.born = id;
      } else if (o.op === 'focus' && at(o.id) >= 0) {
        focus = o.id!;
        tiles[at(o.id)] = { ...tiles[at(o.id)], min: false };
      } else if (o.op === 'unfocus') {
        focus = '';
      } else if (o.op === 'clear') {
        tiles = tiles.map((t) => ({ ...t, min: true }));
        focus = '';
      } else if (
        o.op === 'chat' &&
        ['left', 'right', 'hidden'].includes(o.side ?? '')
      ) {
        (this.args.model as any).chatSide = o.side;
      } else if (o.op === 'minimize' && at(o.id) >= 0) {
        tiles[at(o.id)] = { ...tiles[at(o.id)], min: true };
        if (focus === o.id) focus = '';
      } else if (o.op === 'restore' && at(o.id) >= 0) {
        tiles[at(o.id)] = { ...tiles[at(o.id)], min: false };
      } else if (
        o.op === 'resize' &&
        at(o.id) >= 0 &&
        SIZES.includes(o.size as Size)
      ) {
        tiles[at(o.id)] = { ...tiles[at(o.id)], size: o.size as Size };
      } else if (o.op === 'move' && at(o.id) >= 0) {
        const [t] = tiles.splice(at(o.id), 1);
        tiles.splice(
          Math.max(0, Math.min(tiles.length, Number(o.to) || 0)),
          0,
          t,
        );
      } else if (o.op === 'remove' && at(o.id) >= 0) {
        tiles = tiles.filter((t) => t.id !== o.id);
        if (focus === o.id) focus = '';
      }
    }
    this.save(tiles, focus);
  }
  toggleFocus = (id: string) =>
    this.apply([this.focusId === id ? { op: 'unfocus' } : { op: 'focus', id }]);
  minimize = (id: string) => this.apply([{ op: 'minimize', id }]);
  restore = (id: string) => this.apply([{ op: 'restore', id }]);
  grow = (t: Tile) =>
    this.apply([
      {
        op: 'resize',
        id: t.id,
        size: SIZES[(SIZES.indexOf(t.size) + 1) % SIZES.length],
      },
    ]);
  reset = () => {
    this.save([], '');
    this.args.model.chat = JSON.stringify([]);
  };
  private born = '';
  private alive = true;
  willDestroy() {
    super.willDestroy();
    this.alive = false;
  }
  get side() {
    const v = (this.args.model as any).chatSide;
    return v === 'left' || v === 'hidden' ? v : 'right';
  }
  showChat = () => ((this.args.model as any).chatSide = 'right');
  hideChat = () => ((this.args.model as any).chatSide = 'hidden');
  toggleTests = () =>
    (this.args.model.includeTests = this.args.model.includeTests === false);
  get testsOn() {
    return this.args.model.includeTests !== false;
  }

  // ─── the researcher's chat ─────────────────────────────────────────────
  get chat(): ChatLine[] {
    return parseJson<ChatLine[]>(this.args.model.chat, []);
  }
  // the chat shows its newest line
  toBottom = modifier((el: Element, [_n, _b]: [number, boolean]) => {
    el.scrollTop = el.scrollHeight;
  });
  setDraft = (e: Event) =>
    (this.draft = (e.target as HTMLTextAreaElement).value);
  key = (ev: Event) => {
    const e = ev as KeyboardEvent;
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.send();
    }
  };
  send = () => this.question(this.draft.trim());
  findings = () =>
    this.question(
      'Present the 2-3 things that stand out, including how people answered, not just what they concluded.',
    );
  async question(q: string) {
    if (!q || this.busy) return;
    this.draft = '';
    this.busy = true;
    this.error = '';
    const now = () => new Date().toISOString();
    const chat = [...this.chat, { who: 'you' as const, text: q, at: now() }];
    this.args.model.chat = JSON.stringify(chat);
    try {
      const pooled = this.pooled;
      const out = await ask(toolCtx(this.args.context), {
        brief: `${this.brief?.title ?? ''}: ${this.brief?.brief ?? ''}`,
        measures: this.p.measures
          .map(
            (m, i) =>
              `${i + 1}. ${m.aim} [${m.kind}${m.poles ? `: ${m.poles.join(' ↔ ')}` : ''}${m.letters ? ` (${m.letters.join('/')})` : ''}]`,
          )
          .join('\n'),
        digest: digest(this.rows),
        pooled: pooled
          ? `This or that: ${pooled.people} people, ${pooled.picks} picks. Ranking: ${pooled.ranking.map((x) => `${x.name} (${x.source}) ${x.score}`).join(', ')}. Win rate by source: ${pooled.sources.map((s) => `${s.source} ${s.rate}% of ${s.games}`).join(', ')}.`
          : '',
        canvas: this.tiles.map((t) => ({
          ...t,
          title: `${t.title}${t.id === this.focusId ? ' *' : ''}`,
        })),
        chat,
        question: q,
      });
      await this.present(out, chat);
    } catch (e: any) {
      this.error =
        e?.message === SESSION_EXPIRED
          ? SESSION_EXPIRED
          : `The analyst got stuck (${e?.message ?? e}).`;
    }
    this.busy = false;
  }
  // one point at a time: say the line, put up its tile big, let it be read,
  // then settle it into its slot on the board
  private async present(steps: Step[], chat: ChatLine[]) {
    const wait = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
    let lines = chat;
    for (const st of steps) {
      if (!this.alive) return;
      if (st.say) {
        lines = [
          ...lines,
          { who: 'analyst', text: st.say, at: new Date().toISOString() },
        ];
        this.args.model.chat = JSON.stringify(lines);
      }
      this.born = '';
      const hadClear = st.ops.some((o) => o.op === 'clear');
      this.apply(st.ops);
      if (hadClear) await wait(500);
      if (this.born) {
        const id = this.born;
        await wait(Math.min(5200, 1600 + st.say.length * 28)); // time to read it, centre stage
        if (!this.alive) return;
        if (this.focusId === id) this.apply([{ op: 'unfocus' }]); // …then it clicks into place
        await wait(800);
      } else {
        await wait(Math.min(3000, 800 + st.say.length * 18));
      }
    }
    if (!steps.length)
      this.args.model.chat = JSON.stringify([
        ...lines,
        {
          who: 'analyst',
          text: 'I had nothing to add there.',
          at: new Date().toISOString(),
        },
      ]);
  }
  get features() {
    return Object.values(FEATURES)
      .map((f) => f.name)
      .join(', ');
  }

  <template>
    <div class='an side-{{this.side}}' {{this.loadTools this.rowsKey}}>
      <header class='head'>
        <div>
          <p class='kicker'>Study analysis · {{this.rows.length}} interviews</p>
          <h1>{{if
              this.brief.title
              this.brief.title
              'Pick a brief with the pencil'
            }}</h1>
        </div>
        <div class='hacts'>
          {{#if this.testCount}}<button
              type='button'
              class='quiet {{if this.testsOn "on"}}'
              aria-pressed={{if this.testsOn 'true' 'false'}}
              {{on 'click' this.toggleTests}}
            >Test runs {{if this.testsOn 'included' 'left out'}}</button>{{/if}}
          <button type='button' class='quiet' {{on 'click' this.reset}}>Start
            over</button>
          {{#if (eq this.side 'hidden')}}<button
              type='button'
              class='quiet'
              {{on 'click' this.showChat}}
            >Ask the analyst</button>{{else}}<button
              type='button'
              class='quiet'
              {{on 'click' this.hideChat}}
            >Hide the chat</button>{{/if}}
        </div>
      </header>

      <div class='body'>
        <main class='canvas board'>
          {{#unless this.cards.length}}{{#unless this.docked.length}}<p
                class='blank'
              >A blank board. Ask the analyst to present something, or press
                “What stands out?”.</p>{{/unless}}{{/unless}}
          <LayoutGroup @id={{@model.id}}>
            <div class='grid'>
              {{#each this.cards key='id' as |c|}}
                <article
                  class='tile {{c.t.size}} {{if c.focus "focus"}}'
                  {{motion
                    layout=true
                    layoutId=(concat @model.id '-' c.t.id)
                    style=(styles borderRadius='14px')
                  }}
                >
                  <div class='th' {{motion layout='position'}}>
                    <h2>{{c.t.title}}</h2>
                    <span class='tacts'>
                      <button
                        type='button'
                        title='Size'
                        aria-label='Change size'
                        {{on 'click' (fn this.grow c.t)}}
                      >⤢</button>
                      <button
                        type='button'
                        title={{if
                          c.focus
                          'Back to the grid'
                          'Bring into focus'
                        }}
                        aria-label={{if
                          c.focus
                          'Back to the grid'
                          'Bring into focus'
                        }}
                        {{on 'click' (fn this.toggleFocus c.t.id)}}
                      >{{if c.focus '◱' '◳'}}</button>
                      <button
                        type='button'
                        title='Minimise to the dock'
                        aria-label='Minimise'
                        {{on 'click' (fn this.minimize c.t.id)}}
                      >–</button>
                    </span>
                  </div>
                  <div class='tb' {{motion layout='position'}}>
                    {{#if c.isStats}}
                      <div class='stats'>{{#each c.stats as |st|}}<p><b
                            >{{st.big}}</b><span
                            >{{st.small}}</span></p>{{/each}}</div>
                    {{else if c.isTable}}
                      <table><thead><tr>{{#each c.head as |h|}}<th
                              >{{h}}</th>{{/each}}</tr></thead><tbody>{{#each
                            c.body
                            as |row|
                          }}<tr>{{#each row as |cell|}}<td
                                >{{cell}}</td>{{/each}}</tr>{{/each}}</tbody></table>
                    {{else if c.isStrip}}
                      <div class='strip'>
                        <div class='track'>
                          {{#each c.dots as |d|}}
                            <span class='lane' style={{d.lane}}><span
                                class='band {{d.conf}}'
                                style={{d.band}}
                              ></span><span
                                class='dot {{d.conf}}'
                                style={{d.dot}}
                                title={{d.title}}
                              >{{d.who}}</span></span>
                          {{/each}}
                        </div>
                        <div class='ends'><span>{{c.left}}</span><span
                          >{{c.right}}</span></div>
                        <p class='foot'>{{c.foot}}</p>
                      </div>
                    {{else if c.isScatter}}
                      <div class='scatter'>
                        <div class='plane'>{{#each c.pts as |pt|}}<span
                              class='pt'
                              style={{pt.style}}
                              title={{pt.title}}
                            >{{pt.who}}</span>{{/each}}</div>
                        <p class='foot'>{{c.axes}}</p>
                      </div>
                    {{else if c.isLeans}}
                      <ul class='leans'>{{#each c.leans as |l|}}<li><b
                            >{{l.who}}</b>
                            {{l.lean}}
                            <span class='cf'>{{l.conf}}</span></li>{{else}}<li
                            class='foot'
                          >No reads yet.</li>{{/each}}</ul>
                    {{else if c.isBars}}
                      <ul class='bars'>{{#each c.bars as |b|}}<li><span
                              class='bl'
                            >{{b.label}}</span><span class='bt'><span
                                style={{b.style}}
                              ></span></span><span
                              class='bv'
                            >{{b.value}}</span></li>{{else}}<li
                            class='foot'
                          >Nothing to compare yet.</li>{{/each}}</ul>
                      <p class='foot'>{{c.unit}}</p>
                    {{else if c.isDuels}}
                      <ol class='rank'>{{#each c.rank as |x|}}<li>{{#if
                              x.image
                            }}<img src={{x.image}} alt={{x.name}} />{{/if}}<span
                              class='rn'
                            >{{x.k}}.
                              {{x.name}}<em>{{x.source}}</em></span><span
                              class='bt'
                            ><span style={{x.style}}></span></span><span
                              class='bv'
                            >{{x.score}}</span></li>{{/each}}</ol>
                      <p class='sub'>Win rate by where the screen came from</p>
                      <ul class='bars'>{{#each c.sources as |s|}}<li><span
                              class='bl'
                            >{{s.source}}</span><span class='bt'><span
                                style={{s.style}}
                              ></span></span><span
                              class='bv'
                            >{{s.rate}}%</span></li>{{/each}}</ul>
                      <p class='foot'>{{c.foot}}</p>
                    {{else if c.isGallery}}
                      <div class='gal'>{{#each c.pics as |g|}}<figure><img
                              src={{g.image}}
                              alt=''
                            /><figcaption
                              title={{g.summary}}
                            >{{g.who}}</figcaption></figure>{{else}}<p
                            class='foot'
                          >No pictures yet.</p>{{/each}}</div>
                    {{else if c.isQuotes}}
                      <ul class='quotes'>{{#each c.quotes as |q|}}<li><p
                            >“{{q.text}}”</p><span
                            >{{q.who}}</span></li>{{else}}<li
                            class='foot'
                          >Nothing yet.</li>{{/each}}</ul>
                    {{else}}
                      <p class='note'>{{c.text}}</p>
                    {{/if}}
                  </div>
                </article>
              {{/each}}
            </div>
            {{#if this.docked.length}}
              <div class='dock' aria-label='Minimised tiles'>
                {{#each this.docked key='id' as |d|}}
                  <button
                    type='button'
                    class='chip'
                    {{motion
                      layout=true
                      layoutId=(concat @model.id '-' d.id)
                      style=(styles borderRadius='999px')
                    }}
                    {{on 'click' (fn this.restore d.id)}}
                  >{{d.title}}</button>
                {{/each}}
              </div>
            {{/if}}
          </LayoutGroup>
        </main>

        {{#unless (eq this.side 'hidden')}}
          <aside class='chat' aria-label='The analyst'>
            <p class='ck'>The analyst</p>
            <div
              class='lines'
              aria-live='polite'
              {{this.toBottom this.chat.length this.busy}}
            >
              {{#each this.chat as |ln|}}
                <p class='ln {{ln.who}}'>{{ln.text}}</p>
              {{else}}
                <p class='hint'>Ask about the results, e.g. “Do the people who
                  picked Pip answer differently?” or “What separates the dense
                  lovers from the airy ones?”. The analyst answers here and
                  rearranges the canvas.</p>
              {{/each}}
              {{#if this.busy}}<p class='ln analyst typing'>Looking…</p>{{/if}}
              {{#if this.error}}<p
                  class='err'
                  role='alert'
                >{{this.error}}</p>{{/if}}
            </div>
            <button
              type='button'
              class='quiet wide'
              disabled={{this.busy}}
              {{on 'click' this.findings}}
            >What stands out?</button>
            <textarea
              rows='3'
              aria-label='Ask the analyst'
              placeholder='Ask about the results…'
              value={{this.draft}}
              disabled={{this.busy}}
              {{on 'input' this.setDraft}}
              {{on 'keydown' this.key}}
            ></textarea>
          </aside>
        {{/unless}}
      </div>
    </div>
    <style scoped>
      .an {
        --ink: #1d1c1a;
        --paper: #f6f4ef;
        --card: #fff;
        --muted: #6b675f;
        --rule: #e4e0d8;
        --accent: #e2553b;
        --ok: #2f7d4f;
        min-height: 100%;
        box-sizing: border-box;
        padding: clamp(14px, 2.5cqw, 28px);
        display: grid;
        gap: 16px;
        align-content: start;
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
      .head {
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: 14px;
        flex-wrap: wrap;
      }
      .kicker {
        margin: 0;
        color: var(--muted);
        font-size: 13px;
      }
      h1 {
        margin: 2px 0 0;
        font:
          650 clamp(20px, 3cqw, 28px)/1.15 ui-sans-serif,
          system-ui,
          sans-serif;
        letter-spacing: -0.01em;
      }
      .hacts {
        display: flex;
        gap: 6px;
        flex-wrap: wrap;
      }
      .quiet {
        border: 1px solid var(--rule);
        background: var(--card);
        color: var(--ink);
        padding: 8px 12px;
        border-radius: 9px;
        font:
          600 13px/1 ui-sans-serif,
          system-ui,
          sans-serif;
        cursor: pointer;
      }
      .quiet.on {
        border-color: var(--ink);
      }
      .quiet:disabled {
        opacity: 0.5;
        cursor: default;
      }
      .wide {
        width: 100%;
      }
      button:focus-visible,
      textarea:focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }
      .body {
        display: grid;
        gap: 16px;
        grid-template-columns: minmax(0, 1fr);
        align-items: start;
      }
      .side-right .body {
        grid-template-columns: minmax(0, 1fr) 240px;
      }
      .side-left .body {
        grid-template-columns: 240px minmax(0, 1fr);
      }
      .side-left .chat {
        order: -1;
      }
      .board {
        container: board / inline-size;
        position: relative;
        min-height: 560px;
        padding: 16px;
        border-radius: 16px;
        background-color: #fff;
        background-image: radial-gradient(#e4e0d8 1px, transparent 1px);
        background-size: 22px 22px;
        border: 1px solid var(--rule);
      }
      .blank {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        margin: 0;
        color: var(--muted);
        font-size: 14px;
        pointer-events: none;
      }
      .tile {
        animation: arrive 0.45s ease-out both;
      }
      @keyframes arrive {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          animation: none;
        }
      }

      .grid {
        display: grid;
        grid-template-columns: repeat(12, minmax(0, 1fr));
        grid-auto-rows: 64px;
        grid-auto-flow: dense;
        gap: 12px;
      }
      .tile {
        background: var(--card);
        border: 1px solid var(--rule);
        padding: 12px 14px;
        display: grid;
        grid-template-rows: auto minmax(0, 1fr);
        gap: 8px;
        overflow: hidden;
        min-width: 0;
      }
      .tile.s {
        grid-column: span 3;
        grid-row: span 3;
      }
      .tile.m {
        grid-column: span 4;
        grid-row: span 3;
      }
      .tile.l {
        grid-column: span 6;
        grid-row: span 4;
      }
      .tile.xl {
        grid-column: span 12;
        grid-row: span 4;
      }
      .tile.focus {
        grid-column: 1 / -1;
        grid-row: span 6;
        border-color: var(--ink);
        box-shadow: 0 10px 30px rgba(29, 28, 26, 0.1);
      }
      .th {
        display: flex;
        gap: 8px;
        align-items: flex-start;
        justify-content: space-between;
      }
      h2 {
        margin: 0;
        font:
          650 13px/1.3 ui-sans-serif,
          system-ui,
          sans-serif;
      }
      .tacts {
        display: flex;
        gap: 2px;
        flex: none;
      }
      .tacts button {
        width: 24px;
        height: 24px;
        border: 0;
        border-radius: 6px;
        background: transparent;
        color: var(--muted);
        font-size: 14px;
        line-height: 1;
        cursor: pointer;
      }
      .tacts button:hover {
        background: #f1eee8;
        color: var(--ink);
      }
      .tb {
        min-height: 0;
        overflow: auto;
        font-size: 13px;
      }
      .foot {
        margin: 6px 0 0;
        color: var(--muted);
        font-size: 11px;
      }
      .sub {
        margin: 10px 0 4px;
        font-size: 11px;
        font-weight: 600;
        color: var(--muted);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .note {
        margin: 0;
        font-size: 14px;
        line-height: 1.5;
      }
      .focus .note {
        font-size: 18px;
        max-width: 60ch;
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 10px;
      }
      .stats p {
        margin: 0;
        display: grid;
      }
      .stats b {
        font:
          700 22px/1.1 ui-sans-serif,
          system-ui,
          sans-serif;
      }
      .stats span {
        font-size: 11px;
        color: var(--muted);
      }
      table {
        border-collapse: collapse;
        width: 100%;
        font-size: 12px;
      }
      th,
      td {
        text-align: left;
        padding: 4px 6px;
        border-bottom: 1px solid var(--rule);
      }
      th {
        color: var(--muted);
        font-weight: 600;
      }
      .strip {
        display: grid;
        gap: 4px;
      }
      .track {
        position: relative;
        height: 96px;
        border-radius: 8px;
        background: linear-gradient(90deg, #f6f4ef, #fff 50%, #f6f4ef);
        border: 1px solid var(--rule);
      }
      .track::after {
        content: '';
        position: absolute;
        left: 50%;
        top: 4px;
        bottom: 4px;
        border-left: 1px dashed var(--rule);
      }
      .lane {
        position: absolute;
        left: 6px;
        right: 6px;
        height: 14px;
      }
      .band {
        position: absolute;
        top: 4px;
        height: 6px;
        border-radius: 3px;
        background: rgba(29, 28, 26, 0.1);
      }
      .band.medium,
      .band.high {
        background: rgba(47, 125, 79, 0.18);
      }
      .dot {
        position: absolute;
        top: -1px;
        transform: translateX(-50%);
        padding: 1px 5px;
        border-radius: 999px;
        background: var(--ink);
        color: #fff;
        font:
          700 9px/14px ui-sans-serif,
          system-ui,
          sans-serif;
        white-space: nowrap;
      }
      .dot.low {
        background: #9b968c;
      }
      .ends {
        display: flex;
        justify-content: space-between;
        font-size: 11px;
        color: var(--muted);
        gap: 8px;
      }
      .focus .track {
        height: 140px;
      }
      .scatter .plane {
        position: relative;
        height: 150px;
        border-left: 1px solid var(--rule);
        border-bottom: 1px solid var(--rule);
        background:
          linear-gradient(
            transparent 49.5%,
            var(--rule) 50%,
            transparent 50.5%
          ),
          linear-gradient(
            90deg,
            transparent 49.5%,
            var(--rule) 50%,
            transparent 50.5%
          );
      }
      .focus .scatter .plane {
        height: 300px;
      }
      .pt {
        position: absolute;
        transform: translate(-50%, 50%);
        padding: 1px 5px;
        border-radius: 999px;
        background: var(--ink);
        color: #fff;
        font:
          700 9px/14px ui-sans-serif,
          system-ui,
          sans-serif;
      }
      .leans,
      .bars,
      .rank,
      .quotes {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 5px;
      }
      .cf {
        font-size: 10px;
        color: var(--muted);
      }
      .bars li {
        display: grid;
        grid-template-columns: minmax(60px, 34%) 1fr auto;
        gap: 8px;
        align-items: center;
      }
      .bl {
        font-size: 12px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .bt {
        height: 8px;
        border-radius: 4px;
        background: #f1eee8;
        overflow: hidden;
      }
      .bt span {
        display: block;
        height: 100%;
        background: var(--ink);
        border-radius: 4px;
      }
      .bv {
        font:
          600 12px/1 ui-monospace,
          monospace;
      }
      .rank li {
        display: grid;
        grid-template-columns: 54px minmax(0, 1fr) 1fr auto;
        gap: 8px;
        align-items: center;
      }
      .rank img {
        width: 54px;
        height: 34px;
        object-fit: cover;
        border-radius: 4px;
        background: #ece8df;
      }
      .rn {
        font-size: 12px;
        display: grid;
      }
      .rn em {
        font-style: normal;
        font-size: 10px;
        color: var(--muted);
      }
      .gal {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
        gap: 8px;
      }
      .gal figure {
        margin: 0;
        display: grid;
        gap: 3px;
      }
      .gal img {
        width: 100%;
        aspect-ratio: 4 / 3;
        object-fit: cover;
        border-radius: 6px;
        background: #ece8df;
      }
      .gal figcaption {
        font-size: 11px;
        color: var(--muted);
      }
      .quotes li {
        padding: 8px 10px;
        border-radius: 8px;
        background: #f6f4ef;
      }
      .quotes p {
        margin: 0;
        line-height: 1.45;
      }
      .quotes span {
        font-size: 11px;
        color: var(--muted);
      }
      .dock {
        margin-top: 14px;
        padding: 8px;
        border-radius: 12px;
        border: 1px dashed var(--rule);
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
      }
      .chip {
        border: 1px solid var(--rule);
        background: var(--card);
        padding: 6px 12px;
        font:
          600 12px/1.2 ui-sans-serif,
          system-ui,
          sans-serif;
        color: var(--ink);
        cursor: pointer;
        max-width: 240px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .chat {
        position: sticky;
        top: 12px;
        display: grid;
        gap: 8px;
        padding: 12px;
        border-radius: 14px;
        background: var(--card);
        border: 1px solid var(--rule);
        max-height: calc(100vh - 140px);
        grid-template-rows: auto minmax(0, 1fr) auto auto;
      }
      .ck {
        margin: 0;
        font:
          600 11px/1 ui-monospace,
          monospace;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--accent);
      }
      .lines {
        overflow: auto;
        display: grid;
        gap: 8px;
        align-content: start;
        min-height: 120px;
      }
      .ln {
        margin: 0;
        padding: 8px 10px;
        border-radius: 10px;
        font-size: 13px;
        line-height: 1.45;
        white-space: pre-wrap;
      }
      .ln.you {
        background: var(--ink);
        color: var(--paper);
        justify-self: end;
        max-width: 90%;
      }
      .ln.analyst {
        background: #f6f4ef;
      }
      .typing {
        color: var(--muted);
      }
      .hint {
        margin: 0;
        font-size: 12px;
        color: var(--muted);
        line-height: 1.45;
      }
      .err {
        margin: 0;
        color: #b3261e;
        font-size: 12px;
      }
      textarea {
        font:
          400 13px/1.45 ui-sans-serif,
          system-ui,
          sans-serif;
        padding: 8px 10px;
        border-radius: 10px;
        border: 1px solid var(--rule);
        background: var(--paper);
        color: var(--ink);
        resize: vertical;
      }

      @container (max-width: 600px) {
        .side-right .body,
        .side-left .body {
          grid-template-columns: 1fr;
        }
        .chat {
          position: static;
          max-height: 300px;
          order: -1;
        }
      }
      /* the board's own width decides the grid */
      @container board (max-width: 720px) {
        .grid {
          grid-template-columns: repeat(6, minmax(0, 1fr));
        }
        .tile.s {
          grid-column: span 3;
        }
        .tile.m,
        .tile.l,
        .tile.xl {
          grid-column: span 6;
        }
      }
    </style>
  </template>
}

class AnalysisFitted extends Component<typeof StudyAnalysis> {
  <template>
    <div class='af'><span class='icon'><ChartIcon
          width='18'
          height='18'
        /></span><div><b>Analysis</b><span
        >{{@model.brief.title}}</span></div></div>
    <style scoped>
      .af {
        height: 100%;
        box-sizing: border-box;
        padding: 12px 14px;
        display: flex;
        gap: 10px;
        align-items: center;
        overflow: hidden;
        background: #f6f4ef;
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
      div > div {
        display: grid;
        min-width: 0;
      }
      b {
        font-size: 14px;
      }
      span {
        font-size: 12px;
        color: #6b675f;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
    </style>
  </template>
}

export class StudyAnalysis extends CardDef {
  static displayName = 'Study Analysis';
  static icon = ChartIcon;
  @field brief = linksTo(() => InterviewBrief);
  @field tiles = contains(TextAreaField); // JSON: Tile[]; empty: a blank board
  @field focus = contains(StringField); // the tile in focus
  @field chat = contains(TextAreaField); // JSON: ChatLine[]
  @field includeTests = contains(BooleanField); // false: leave scripted test runs out
  @field chatSide = contains(StringField); // right (default) | left | hidden; the analyst may move it
  @field cardTitle = contains(StringField, {
    computeVia: function (this: StudyAnalysis) {
      return `Analysis · ${this.brief?.title ?? 'a study'}`;
    },
  });
  static isolated = AnalysisView;
  static embedded = AnalysisFitted;
  static fitted = AnalysisFitted;
}
