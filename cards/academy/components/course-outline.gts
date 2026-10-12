import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';

interface OutlineLesson {
  cardTitle?: string;
  kind?: string;
  kindLabel?: string;
  durationLabel?: string;
}

interface OutlineModule {
  id?: string;
  code?: string;
  title?: string;
  order?: number;
  summary?: string;
  releaseLabel?: string;
  lessonCount?: number;
  totalMinutes?: number;
  lessons?: OutlineLesson[];
  assignments?: { cardTitle?: string; code?: string }[];
  quizzes?: { cardTitle?: string }[];
}

interface Signature {
  Args: {
    modules?: (OutlineModule | undefined)[];
    /** Module ids already released to the cohort being viewed (optional). */
    releasedIds?: string[];
    /** Called when a module row is opened; the consumer decides what "open" means. */
    onOpenModule?: (module: OutlineModule) => void;
    /** Start collapsed except the first module. Default: all expanded. */
    collapsed?: boolean;
  };
  Element: HTMLElement;
}

const GLYPH: Record<string, string> = {
  video: '▶',
  reading: '¶',
  live: '●',
  exercise: '✎',
};

/**
 * The course as a learner will walk it: modules in order, each opening to its
 * lessons with kind and length, and the checks (assignments, quizzes) that
 * close it. Reads already-resolved cards; fetches nothing. A consumer that
 * knows which modules a cohort has released passes `releasedIds` and the
 * outline dims the rest — the same component serves authoring and delivery.
 */
export class CourseOutline extends GlimmerComponent<Signature> {
  @tracked openIds: Set<string> = new Set();
  @tracked initialised = false;

  get modules(): OutlineModule[] {
    return (this.args.modules ?? [])
      .filter((m): m is OutlineModule => !!m)
      .slice()
      .sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
  }

  get totalLessons() {
    return this.modules.reduce(
      (n, m) => n + (m.lessonCount ?? m.lessons?.length ?? 0),
      0,
    );
  }

  isOpen = (m: OutlineModule, index: number): boolean => {
    if (!this.initialised) {
      return !this.args.collapsed || index === 0;
    }
    return this.openIds.has(keyOf(m, index));
  };

  toggle = (m: OutlineModule, index: number) => {
    if (!this.initialised) {
      let seed = new Set<string>();
      this.modules.forEach((mm, i) => {
        if (!this.args.collapsed || i === 0) seed.add(keyOf(mm, i));
      });
      this.openIds = seed;
      this.initialised = true;
    }
    let next = new Set(this.openIds);
    let k = keyOf(m, index);
    if (next.has(k)) next.delete(k);
    else next.add(k);
    this.openIds = next;
  };

  isReleased = (m: OutlineModule): boolean | undefined => {
    if (!this.args.releasedIds) return undefined;
    return !!m.id && this.args.releasedIds.includes(m.id);
  };

  glyph = (kind?: string) => GLYPH[kind ?? ''] ?? '•';

  minutes = (m: OutlineModule) => {
    let min = m.totalMinutes ?? 0;
    if (!min) return '';
    if (min < 60) return `${min} min`;
    let h = Math.floor(min / 60);
    let r = min % 60;
    return r ? `${h}h ${r}m` : `${h}h`;
  };

  <template>
    <div class='outline' ...attributes>
      {{#if this.modules.length}}
        <ol class='mods'>
          {{#each this.modules as |m i|}}
            <li
              class='mod
                {{if (this.isOpen m i) "open"}}
                {{releaseClass (this.isReleased m)}}'
            >
              <button
                type='button'
                class='mod-head'
                aria-expanded={{if (this.isOpen m i) 'true' 'false'}}
                {{on 'click' (fn this.toggle m i)}}
              >
                <span class='mod-code'>{{if
                    m.code
                    m.code
                    (orderLabel m.order i)
                  }}</span>
                <span class='mod-title'>{{if
                    m.title
                    m.title
                    'Untitled module'
                  }}</span>
                <span class='mod-meta'>
                  {{#if (isLocked (this.isReleased m))}}<span class='lock'>Not
                      released</span>{{/if}}
                  {{lessonCountOf m}}
                  lessons{{#if (this.minutes m)}} · {{this.minutes m}}{{/if}}
                  {{#if m.releaseLabel}}<span
                      class='rel-when'
                    >{{m.releaseLabel}}</span>{{/if}}
                </span>
                <span class='chev' aria-hidden='true'>{{if
                    (this.isOpen m i)
                    '−'
                    '+'
                  }}</span>
              </button>
              {{#if (this.isOpen m i)}}
                <div class='mod-body'>
                  {{#if m.summary}}<p class='mod-sum'>{{m.summary}}</p>{{/if}}
                  {{#if m.lessons.length}}
                    <ol class='lessons'>
                      {{#each m.lessons as |l|}}
                        <li>
                          <span class='glyph'>{{this.glyph l.kind}}</span>
                          <span class='l-title'>{{l.cardTitle}}</span>
                          <span class='l-kind'>{{l.kindLabel}}</span>
                          <span class='l-dur'>{{if
                              l.durationLabel
                              l.durationLabel
                              '—'
                            }}</span>
                        </li>
                      {{/each}}
                    </ol>
                  {{else}}
                    <p class='empty'>No lessons in this module yet.</p>
                  {{/if}}
                  {{#if (hasChecks m)}}
                    <div class='checks'>
                      {{#each m.assignments as |a|}}
                        <span class='chip chip-a'>{{a.cardTitle}}</span>
                      {{/each}}
                      {{#each m.quizzes as |q|}}
                        <span class='chip chip-q'>Quiz · {{q.cardTitle}}</span>
                      {{/each}}
                    </div>
                  {{/if}}
                  {{#if @onOpenModule}}
                    <button
                      type='button'
                      class='open-link'
                      {{on 'click' (fn @onOpenModule m)}}
                    >Open module →</button>
                  {{/if}}
                </div>
              {{/if}}
            </li>
          {{/each}}
        </ol>
        <p class='foot'>{{this.modules.length}}
          modules ·
          {{this.totalLessons}}
          lessons</p>
      {{else}}
        <p class='empty'>No modules yet. A course outline starts with its first
          module.</p>
      {{/if}}
    </div>
    <style scoped>
      .outline {
        color: var(--foreground, var(--boxel-dark));
      }
      .mods {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .mod {
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
        background: var(--card, var(--boxel-light));
        overflow: hidden;
      }
      .mod.locked {
        opacity: 0.62;
      }
      .mod-head {
        width: 100%;
        display: grid;
        grid-template-columns: auto 1fr auto auto;
        gap: var(--boxel-sp-sm);
        align-items: center;
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        border: 0;
        background: transparent;
        color: inherit;
        text-align: start;
        font: inherit;
        cursor: pointer;
      }
      .mod-head:hover {
        background: var(--muted, var(--boxel-100));
      }
      .mod-head:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: -2px;
      }
      .mod-code {
        min-width: 2.25rem;
        height: 2.25rem;
        padding: 0 var(--boxel-sp-4xs);
        display: grid;
        place-items: center;
        border-radius: var(--boxel-border-radius-sm);
        background: color-mix(
          in oklab,
          var(--primary, var(--boxel-highlight)) 14%,
          var(--card, var(--boxel-light))
        );
        font: 700 var(--boxel-font-size-xs)
          var(--font-mono, ui-monospace, monospace);
      }
      .mod-title {
        font-weight: 600;
      }
      .mod-meta {
        display: inline-flex;
        gap: var(--boxel-sp-xs);
        align-items: center;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
        white-space: nowrap;
      }
      .rel-when {
        padding: 1px var(--boxel-sp-xs);
        border-radius: 999px;
        background: color-mix(
          in oklab,
          var(--primary, var(--boxel-highlight)) 12%,
          var(--card, var(--boxel-light))
        );
        color: color-mix(
          in oklab,
          var(--primary, var(--boxel-highlight)) 55%,
          var(--card-foreground, var(--boxel-dark))
        );
        font-weight: 600;
      }
      .lock {
        padding: 1px var(--boxel-sp-xs);
        border-radius: 999px;
        background: var(--muted, var(--boxel-100));
        text-transform: uppercase;
        letter-spacing: 0.05em;
        font-weight: 600;
      }
      .chev {
        width: 1.25rem;
        text-align: center;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .mod-body {
        padding: 0 var(--boxel-sp) var(--boxel-sp)
          calc(var(--boxel-sp) + 2.25rem + var(--boxel-sp-sm));
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .mod-sum {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .lessons {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .lessons li {
        display: grid;
        grid-template-columns: auto 1fr auto 4.5rem;
        gap: var(--boxel-sp-xs);
        align-items: center;
        padding: var(--boxel-sp-4xs) 0;
        font-size: var(--boxel-font-size-sm);
      }
      .lessons li + li {
        border-top: 1px dashed var(--border, var(--boxel-200));
      }
      .glyph {
        width: 1.25rem;
        height: 1.25rem;
        display: grid;
        place-items: center;
        border-radius: var(--boxel-border-radius-sm);
        background: var(--muted, var(--boxel-100));
        font-size: 11px;
      }
      .l-kind,
      .l-dur {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .l-dur {
        text-align: end;
        font-variant-numeric: tabular-nums;
      }
      .checks {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
      }
      .chip {
        padding: 1px var(--boxel-sp-xs);
        border-radius: 999px;
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      .chip-a {
        background: color-mix(
          in oklab,
          var(--boxel-warning) 14%,
          var(--card, var(--boxel-light))
        );
        color: color-mix(
          in oklab,
          var(--boxel-warning) 45%,
          var(--card-foreground, var(--boxel-dark))
        );
      }
      .chip-q {
        background: color-mix(
          in oklab,
          var(--boxel-purple) 14%,
          var(--card, var(--boxel-light))
        );
        color: color-mix(
          in oklab,
          var(--boxel-purple) 45%,
          var(--card-foreground, var(--boxel-dark))
        );
      }
      .open-link {
        min-height: 44px;
        display: inline-flex;
        align-items: center;
        justify-self: start;
        border: 0;
        background: none;
        padding: 0;
        color: color-mix(
          in oklab,
          var(--primary, var(--boxel-highlight)) 60%,
          var(--foreground, var(--boxel-dark))
        );
        font: inherit;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        cursor: pointer;
      }
      .foot {
        margin: var(--boxel-sp-xs) 0 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .empty {
        margin: 0;
        color: var(--muted-foreground, var(--boxel-450));
        font-style: italic;
        font-size: var(--boxel-font-size-sm);
      }
      @container (width <= 520px) {
        .mod-meta {
          display: none;
        }
        .mod-body {
          padding-left: var(--boxel-sp);
        }
        .lessons li {
          grid-template-columns: auto 1fr 4rem;
        }
        .l-kind {
          display: none;
        }
      }
    </style>
  </template>
}

function keyOf(m: OutlineModule, i: number) {
  return m.id ?? `idx-${i}`;
}

function orderLabel(order: number | undefined, i: number) {
  return `M${order ?? i + 1}`;
}

function lessonCountOf(m: OutlineModule) {
  return m.lessonCount ?? m.lessons?.length ?? 0;
}

function hasChecks(m: OutlineModule) {
  return (m.assignments?.length ?? 0) + (m.quizzes?.length ?? 0) > 0;
}

function isLocked(released: boolean | undefined) {
  return released === false;
}

function releaseClass(released: boolean | undefined) {
  return released === false ? 'locked' : '';
}

export default CourseOutline;
