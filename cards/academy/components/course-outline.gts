import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { cached, tracked } from '@glimmer/tracking';
import { Accordion } from '@cardstack/pretui/components/accordion';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';

import { StatePill } from '@cardstack/catalog/components/state-pill';

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
  cardTitle?: string;
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

  @cached
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
        <Accordion @displayContainer={{true}} as |A|>
          {{#each this.modules as |m i|}}
            <A.Item
              @id={{keyOf m i}}
              @isOpen={{this.isOpen m i}}
              @onClick={{fn this.toggle m i}}
            >
              <:title>
                <span
                  class='mod-head
                    {{if (isLocked (this.isReleased m)) "locked"}}'
                >
                  <span class='mod-code'>{{if
                      m.code
                      m.code
                      (orderLabel m.order i)
                    }}</span>
                  <span class='mod-title'>{{m.cardTitle}}</span>
                  {{#if (isLocked (this.isReleased m))}}
                    <StatePill @label='Not released' @hue='slate' />
                  {{/if}}
                  <span class='mod-meta'>
                    {{lessonCountOf m}}
                    lessons{{#if (this.minutes m)}} · {{this.minutes m}}{{/if}}
                    {{#if m.releaseLabel}}
                      <StatePill @label={{m.releaseLabel}} @hue='blue' />
                    {{/if}}
                  </span>
                </span>
              </:title>
              <:content>
                <div
                  class='mod-body
                    {{if (isLocked (this.isReleased m)) "locked"}}'
                >
                  {{#if m.summary}}<p class='mod-sum'>{{m.summary}}</p>{{/if}}
                  {{#if m.lessons.length}}
                    <ol class='lessons'>
                      {{#each m.lessons as |l|}}
                        <li>
                          <span class='glyph' aria-hidden='true'>{{this.glyph
                              l.kind
                            }}</span>
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
                    <EmptyState
                      @size='s'
                      @title='No lessons in this module yet'
                    />
                  {{/if}}
                  {{#if (hasChecks m)}}
                    <div class='checks'>
                      {{#each m.assignments as |a|}}
                        <StatePill @label={{a.cardTitle}} @hue='teal' />
                      {{/each}}
                      {{#each m.quizzes as |q|}}
                        <StatePill
                          @label={{quizLabel q.cardTitle}}
                          @hue='purple'
                        />
                      {{/each}}
                    </div>
                  {{/if}}
                  {{#if @onOpenModule}}
                    <Button
                      class='open-link'
                      @appearance='link'
                      {{on 'click' (fn @onOpenModule m)}}
                    >Open module →</Button>
                  {{/if}}
                </div>
              </:content>
            </A.Item>
          {{/each}}
        </Accordion>
        <p class='foot'>{{this.modules.length}}
          modules ·
          {{this.totalLessons}}
          lessons</p>
      {{else}}
        <EmptyState
          @size='s'
          @title='No modules yet'
          @message='A course outline starts with its first module.'
        />
      {{/if}}
    </div>
    <style scoped>
      .outline {
        container-type: inline-size;
        color: var(--foreground);
      }
      /* The "Not released" pill is the locked state's text cue, so it keeps
         full contrast; only the module's own text dims. */
      .mod-head.locked .mod-code,
      .mod-head.locked .mod-title,
      .mod-head.locked .mod-meta,
      .mod-body.locked {
        opacity: 0.62;
      }
      .mod-head {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        grid-auto-flow: column;
        grid-auto-columns: auto;
        gap: var(--boxel-sp-sm);
        align-items: center;
        min-width: 0;
      }
      .mod-code {
        min-width: 2.25rem;
        height: 2.25rem;
        padding: 0 var(--boxel-sp-4xs);
        display: grid;
        place-items: center;
        border-radius: var(--boxel-border-radius-sm);
        background: var(--muted);
        color: var(--primary-ink);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .mod-title {
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .mod-meta {
        display: inline-flex;
        gap: var(--boxel-sp-xs);
        align-items: center;
        font-size: var(--boxel-font-size-xs);
        font-weight: 400;
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .mod-body {
        padding: 0 var(--boxel-sp) var(--boxel-sp)
          calc(var(--boxel-sp) + 2.25rem + var(--boxel-sp-sm));
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .mod-sum {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .lessons {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .lessons li {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr) auto 4.5rem;
        gap: var(--boxel-sp-xs);
        align-items: center;
        padding: var(--boxel-sp-4xs) 0;
        font-size: var(--boxel-font-size-sm);
      }
      .lessons li + li {
        border-top: 1px dashed var(--border);
      }
      .glyph {
        width: 1.25rem;
        height: 1.25rem;
        display: grid;
        place-items: center;
        border-radius: var(--boxel-border-radius-sm);
        background: var(--muted);
        font-size: var(--boxel-font-size-2xs);
      }
      .l-kind,
      .l-dur {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
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
      .open-link {
        justify-self: start;
      }
      .foot {
        margin-top: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      @container (width <= 32.5rem) {
        .mod-meta {
          display: none;
        }
        .mod-body {
          padding-left: var(--boxel-sp);
        }
        .lessons li {
          grid-template-columns: auto minmax(0, 1fr) 4rem;
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

function quizLabel(title: string | undefined) {
  return `Quiz · ${title ?? ''}`;
}

export default CourseOutline;
