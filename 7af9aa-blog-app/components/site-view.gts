import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { Component, realmURL } from '@cardstack/base/card-api';
import {
  codeRef,
  type Query,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { Button } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { BlogPost } from '../blog-post';
import { Game } from '../games/game';
import type { BlogApp } from '../blog-app';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;

type LatestFilter = 'all' | 'latest' | 'news' | 'new-york' | 'tech';

// Reader-facing view: NYT-inspired magazine layout, lists BlogPosts via search.
export class BlogSiteView extends Component<typeof BlogApp> {
  get latestSearchQuery(): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery(this.latestQuery),
      realms: this.realmHrefs,
    };
  }
  get picksSearchQuery(): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery(this.picksQuery),
      realms: this.realmHrefs,
    };
  }
  @tracked activeFilter: LatestFilter = 'all';
  @tracked dragOverSlot: string | null = null;

  private waitForCardLoad(resource: any): Promise<void> {
    // bounded poll: resolves on load/error, gives up after 5s, and stops
    // outright if the component is torn down mid-wait
    return new Promise((resolve) => {
      const started = Date.now();
      const check = () => {
        if (
          resource.card ||
          resource.cardError ||
          Date.now() - started > 5000 ||
          this.isDestroying ||
          this.isDestroyed
        ) {
          resolve();
        } else {
          setTimeout(check, 50);
        }
      };
      check();
    });
  }

  private async resolveCardFromUrl(url: string): Promise<BlogPost | null> {
    const context = (this.args as any).context;
    if (!context?.getCard) return null;
    const resource = context.getCard(this, () => url);
    await this.waitForCardLoad(resource);
    return (resource?.card as BlogPost) ?? null;
  }

  @tracked draggingFeaturedIndex: number | null = null;
  @tracked dragOverFeaturedIndex: number | null = null;
  @tracked draggingLead = false;

  private hasInternalFeaturedDrag(event: DragEvent): boolean {
    const dt = event.dataTransfer;
    if (!dt) return false;
    const types = Array.from(dt.types ?? []);
    return types.includes('application/x-featured-index');
  }

  private hasInternalLeadDrag(event: DragEvent): boolean {
    const dt = event.dataTransfer;
    if (!dt) return false;
    const types = Array.from(dt.types ?? []);
    return types.includes('application/x-lead-slot');
  }

  @action publishLead() {
    let lead = this.args.model.lead as any;
    if (!lead) return;
    lead.published = true;
    (this.args.context as any)?.actions?.saveCard?.(lead);
  }

  @action onLeadDragStart(event: Event) {
    const ev = event as DragEvent;
    this.draggingLead = true;
    if (ev.dataTransfer) {
      ev.dataTransfer.setData('application/x-lead-slot', '1');
      ev.dataTransfer.setData('text/plain', 'lead');
      ev.dataTransfer.effectAllowed = 'move';
    }
  }

  @action onLeadDragEnd() {
    this.draggingLead = false;
  }

  private swapLeadWithFeatured(featuredIdx: number) {
    const model = this.args.model as any;
    const featured = [...((model.featured as BlogPost[]) ?? [])];
    if (featuredIdx < 0 || featuredIdx >= featured.length) return;
    const promoted = featured[featuredIdx];
    const oldLead = model.lead as BlogPost | undefined;
    if (oldLead) {
      featured[featuredIdx] = oldLead;
    } else {
      // No prior lead — pull the card out of featured entirely.
      featured.splice(featuredIdx, 1);
    }
    model.lead = promoted;
    model.featured = featured;
    const actions = (this.args as any).context?.actions;
    actions?.saveCard?.(this.args.model);
  }

  @action onFeaturedDragStart(index: number, event: DragEvent) {
    this.draggingFeaturedIndex = index;
    if (event.dataTransfer) {
      event.dataTransfer.setData('application/x-featured-index', String(index));
      event.dataTransfer.setData('text/plain', `featured:${index}`);
      event.dataTransfer.effectAllowed = 'move';
    }
  }

  @action onFeaturedDragOver(index: number, event: DragEvent) {
    // Intercept in-list reorders AND lead-to-featured swaps. External
    // drags (URL from the library drawer) fall through to the
    // .featured-list's 'featured-append' handler.
    if (
      !this.hasInternalFeaturedDrag(event) &&
      !this.hasInternalLeadDrag(event)
    ) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    this.dragOverFeaturedIndex = index;
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
  }

  @action onFeaturedDragLeave(index: number) {
    if (this.dragOverFeaturedIndex === index) {
      this.dragOverFeaturedIndex = null;
    }
  }

  @action onFeaturedDrop(index: number, event: DragEvent) {
    // Lead → featured swap
    if (this.hasInternalLeadDrag(event)) {
      event.preventDefault();
      event.stopPropagation();
      this.draggingLead = false;
      this.dragOverFeaturedIndex = null;
      this.swapLeadWithFeatured(index);
      return;
    }
    if (!this.hasInternalFeaturedDrag(event)) {
      // External drop — let .featured-list's handler turn it into an append.
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const raw =
      event.dataTransfer?.getData('application/x-featured-index') ?? '';
    const sourceIdx = parseInt(raw, 10);
    this.draggingFeaturedIndex = null;
    this.dragOverFeaturedIndex = null;
    if (Number.isNaN(sourceIdx) || sourceIdx === index) return;
    const model = this.args.model as any;
    const arr = [...((model.featured as BlogPost[]) ?? [])];
    if (sourceIdx < 0 || sourceIdx >= arr.length) return;
    const [moving] = arr.splice(sourceIdx, 1);
    const insertAt = Math.min(Math.max(0, index), arr.length);
    arr.splice(insertAt, 0, moving);
    model.featured = arr;
    const actions = (this.args as any).context?.actions;
    actions?.saveCard?.(this.args.model);
  }

  @action onFeaturedDragEnd() {
    this.draggingFeaturedIndex = null;
    this.dragOverFeaturedIndex = null;
  }

  @action onSlotDragOver(slotId: string, event: DragEvent) {
    event.preventDefault();
    event.stopPropagation();
    this.dragOverSlot = slotId;
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
  }

  @action onSlotDragLeave(slotId: string) {
    if (this.dragOverSlot === slotId) {
      this.dragOverSlot = null;
    }
  }

  @action onSlotDrop(slotId: string, event: DragEvent) {
    event.preventDefault();
    event.stopPropagation();
    this.dragOverSlot = null;
    // Featured → lead swap
    if (slotId === 'lead' && this.hasInternalFeaturedDrag(event)) {
      const sourceIdx = parseInt(
        event.dataTransfer?.getData('application/x-featured-index') ?? '-1',
        10,
      );
      this.draggingFeaturedIndex = null;
      this.dragOverFeaturedIndex = null;
      if (!Number.isNaN(sourceIdx)) {
        this.swapLeadWithFeatured(sourceIdx);
      }
      return;
    }
    // An internal lead drag dropped on its own slot — no-op, just clean up.
    if (this.hasInternalLeadDrag(event)) {
      this.draggingLead = false;
      return;
    }
    const dt = event.dataTransfer;
    const url =
      dt?.getData('text/uri-list')?.split('\n')[0]?.trim() ||
      dt?.getData('text/plain') ||
      '';
    if (!url || url.startsWith('lead') || url.startsWith('featured:')) return;
    this.assignSlot(slotId, url);
  }

  @action async assignSlot(slotId: string, url: string) {
    const card = await this.resolveCardFromUrl(url);
    if (!card) return;
    const model = this.args.model as any;
    if (slotId === 'lead') {
      model.lead = card;
    } else if (slotId === 'featured-append') {
      const next = [...((model.featured as BlogPost[]) ?? [])];
      const url = (card as any).id;
      if (!next.some((p) => (p as any).id === url)) {
        next.push(card);
        model.featured = next;
      }
    } else if (slotId === 'games-append') {
      const next = [...((model.games as Game[]) ?? [])];
      // Avoid duplicates — if this game is already linked, do nothing.
      const url = (card as any).id;
      if (!next.some((g) => (g as any).id === url)) {
        next.push(card as unknown as Game);
        model.games = next;
      }
    }
    const actions = (this.args as any).context?.actions;
    actions?.saveCard?.(this.args.model);
  }

  get hasFeatured(): boolean {
    return Boolean((this.args.model as any).featured?.length);
  }

  get hasGames(): boolean {
    return Boolean((this.args.model as any).games?.length);
  }

  get realmHrefs(): string[] {
    const u = this.args.model[realmURL];
    return u ? [u.href] : [];
  }

  get query() {
    const on = codeRef(here, '../blog-post', 'BlogPost');
    return {
      filter: { on, eq: { published: true } },
      sort: [{ on, by: 'publishDate', direction: 'desc' as const }],
    };
  }

  get picksQuery(): Query {
    const on = codeRef(here, '../blog-post', 'BlogPost');
    return {
      filter: {
        on,
        eq: { published: true, 'categories.slug': 'writers-pick' },
      },
      sort: [{ on, by: 'publishDate', direction: 'desc' as const }],
    };
  }

  get latestQuery(): Query {
    const on = codeRef(here, '../blog-post', 'BlogPost');
    const categorySlug =
      this.activeFilter === 'news'
        ? 'news'
        : this.activeFilter === 'new-york'
          ? 'new-york'
          : this.activeFilter === 'tech'
            ? 'future-tech'
            : undefined;
    return {
      filter: {
        on,
        eq: categorySlug
          ? { published: true, 'categories.slug': categorySlug }
          : { published: true },
      },
      sort: [{ on, by: 'publishDate', direction: 'desc' }],
    };
  }

  @action setFilter(f: LatestFilter) {
    this.activeFilter = f;
  }

  get todayLabel(): string {
    return new Date()
      .toLocaleDateString('en-US', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      })
      .toUpperCase();
  }

  <template>
    <article class='site'>
      <header class='site-header' aria-label='Site masthead'>
        <div class='brand'>
          {{#if @model.cardThumbnailURL}}
            <img src={{@model.cardThumbnailURL}} alt='' class='brand-logo' />
          {{/if}}
          <div class='brand-text'>
            <h1 class='brand-title'><@fields.cardTitle /></h1>
            {{#if @model.cardDescription}}
              <p class='brand-tag'>{{@model.cardDescription}}</p>
            {{/if}}
          </div>
        </div>
      </header>

      <section class='hero' aria-label='Lead stories'>
        <div class='hero-grid'>
          <div
            class='hero-lead
              {{if (eq this.dragOverSlot "lead") "is-drop-target"}}'
            {{on 'dragover' (fn this.onSlotDragOver 'lead')}}
            {{on 'dragleave' (fn this.onSlotDragLeave 'lead')}}
            {{on 'drop' (fn this.onSlotDrop 'lead')}}
          >
            {{#if @model.lead.published}}
              <div
                class='lead-list lead-pinned
                  {{if this.draggingLead "is-dragging"}}'
                draggable='true'
                title='Drag to swap with a featured post'
                {{on 'dragstart' this.onLeadDragStart}}
                {{on 'dragend' this.onLeadDragEnd}}
              >
                <@fields.lead @format='embedded' />
              </div>
            {{else}}
              <div class='lead-empty'>
                <span class='lead-empty-label'>Lead</span>
                {{#if @model.lead}}
                  <p>Lead post is unpublished. Publish it to feature it here.</p>
                  <Button
                    @size='auto'
                    @kind='text-only'
                    class='lead-publish-btn'
                    {{on 'click' this.publishLead}}
                  >Publish lead post</Button>
                {{else}}
                  <p>Drag a post here to set the lead story.</p>
                {{/if}}
              </div>
            {{/if}}
          </div>
          <aside class='hero-aside'>
            <h2 class='aside-heading'>Featured</h2>
            <div
              class='featured-list manual
                {{if
                  (eq this.dragOverSlot "featured-append")
                  "is-drop-target"
                }}'
              {{on 'dragover' (fn this.onSlotDragOver 'featured-append')}}
              {{on 'dragleave' (fn this.onSlotDragLeave 'featured-append')}}
              {{on 'drop' (fn this.onSlotDrop 'featured-append')}}
            >
              {{#if this.hasFeatured}}
                {{#each @fields.featured as |Field index|}}
                  {{#let (get @model.featured index) as |post|}}
                    {{#if post.published}}
                      <div
                        class='featured-slot
                          {{if
                            (eq this.draggingFeaturedIndex index)
                            "is-dragging"
                          }}
                          {{if
                            (eq this.dragOverFeaturedIndex index)
                            "is-drop-target"
                          }}'
                        draggable='true'
                        title='Drag to reorder'
                        {{on 'dragstart' (fn this.onFeaturedDragStart index)}}
                        {{on 'dragend' this.onFeaturedDragEnd}}
                        {{on 'dragover' (fn this.onFeaturedDragOver index)}}
                        {{on 'dragleave' (fn this.onFeaturedDragLeave index)}}
                        {{on 'drop' (fn this.onFeaturedDrop index)}}
                      >
                        <Field @format='fitted' />
                      </div>
                    {{/if}}
                  {{/let}}
                {{/each}}
              {{else}}
                <div class='featured-empty'>
                  Drop a post here
                </div>
              {{/if}}
            </div>
            <h2 class='aside-heading aside-heading--games'>Games</h2>
            <div
              class='games-list
                {{if (eq this.dragOverSlot "games-append") "is-drop-target"}}'
              {{on 'dragover' (fn this.onSlotDragOver 'games-append')}}
              {{on 'dragleave' (fn this.onSlotDragLeave 'games-append')}}
              {{on 'drop' (fn this.onSlotDrop 'games-append')}}
            >
              {{#if this.hasGames}}
                {{#each @fields.games as |Field|}}
                  <div class='games-card'>
                    <Field @format='fitted' />
                  </div>
                {{/each}}
              {{else}}
                <div class='games-empty'>
                  Drop a game here
                </div>
              {{/if}}
            </div>
          </aside>
        </div>
      </section>

      <section class='picks' aria-label="Writer's picks">
        <header class='picks-head' aria-label='Picks heading'>
          <h2 class='picks-title'>Writer's Picks</h2>
          <p class='picks-subtitle'>
            Strange, extreme, hand-picked stories the editors couldn't stop
            reading.
          </p>
        </header>
        <div class='picks-carousel'>
          {{#let (component @context.searchResultsComponent) as |Search|}}
            <Search @query={{this.picksSearchQuery}} as |results|>
              {{#each results.entries key='id' as |card|}}
                <div class='picks-card'>
                  <card.component />
                </div>
              {{else}}
                {{#if results.isLoading}}
                  <div class='aside-loading'>Loading…</div>
                {{else}}
                  <div class='section-empty'>No published posts yet — publish a
                    post and it will appear here.</div>
                {{/if}}
              {{/each}}
            </Search>
          {{/let}}
        </div>
      </section>

      <section class='recent' aria-label='Latest posts'>
        <header class='recent-head' aria-label='Latest posts heading'>
          <h2 class='recent-title'>Latest Posts</h2>
          <nav class='filter-pills' aria-label='Filter posts'>
            <Button
              @size='auto'
              @kind='text-only'
              class='pill {{if (eq this.activeFilter "all") "is-active"}}'
              {{on 'click' (fn this.setFilter 'all')}}
            >All</Button>
            <Button
              @size='auto'
              @kind='text-only'
              class='pill {{if (eq this.activeFilter "latest") "is-active"}}'
              {{on 'click' (fn this.setFilter 'latest')}}
            >Latest</Button>
            <Button
              @size='auto'
              @kind='text-only'
              class='pill {{if (eq this.activeFilter "news") "is-active"}}'
              {{on 'click' (fn this.setFilter 'news')}}
            >News</Button>
            <Button
              @size='auto'
              @kind='text-only'
              class='pill {{if (eq this.activeFilter "new-york") "is-active"}}'
              {{on 'click' (fn this.setFilter 'new-york')}}
            >New York</Button>
            <Button
              @size='auto'
              @kind='text-only'
              class='pill {{if (eq this.activeFilter "tech") "is-active"}}'
              {{on 'click' (fn this.setFilter 'tech')}}
            >Tech</Button>
          </nav>
        </header>
        <div class='recent-grid filter-{{this.activeFilter}}'>
          {{#let (component @context.searchResultsComponent) as |Search|}}
            <Search @query={{this.latestSearchQuery}} as |results|>
              {{#each results.entries key='id' as |card|}}
                <div class='recent-card'>
                  <card.component />
                </div>
              {{else}}
                {{#if results.isLoading}}
                  <div class='recent-loading'>Loading…</div>
                {{else}}
                  <div class='section-empty'>Nothing here yet — publish your
                    first post to start the feed.</div>
                {{/if}}
              {{/each}}
            </Search>
          {{/let}}
        </div>
      </section>
    </article>
    <style scoped>
      @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');

      .site {
        container-type: inline-size;
        container-name: blog-site;
        min-height: 100%;
        background-color: var(--canvas);
        color: var(--foreground);
        font-family: var(--blog-font-family, 'Inter', system-ui, sans-serif);
        padding-bottom: var(--boxel-sp-xxl);
      }

      /* ── Site header ────────────────────────────────────── */
      .site-header {
        max-width: 77.5rem;
        margin: 0 auto;
        padding: var(--boxel-sp-xxl) var(--boxel-sp-lg) var(--boxel-sp-lg);
        background-color: var(--card);
        color: var(--card-foreground);
      }
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp);
      }
      .brand-logo {
        width: 4rem;
        height: 4rem;
        flex-shrink: 0;
        border-radius: 0.75rem;
        object-fit: cover;
        background-color: var(--inset);
      }
      .brand-text {
        min-width: 0;
      }
      .brand-title {
        font: 800 2.25rem/1.05
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        letter-spacing: -0.02em;
        margin: 0 0 0.5rem;
        color: var(--foreground);
      }
      .brand-tag {
        font: 400 1rem/1.45
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        color: var(--muted-foreground);
        margin: 0;
        max-width: 40rem;
      }

      /* ── Hero section ───────────────────────────────────── */
      .hero {
        max-width: 77.5rem;
        margin: 0 auto;
        padding: 0 var(--boxel-sp-lg);
      }
      .hero-grid {
        display: grid;
        grid-template-columns: 1.55fr 1fr;
        gap: 1.75rem;
        align-items: stretch;
      }
      .aside-heading {
        font: 700 1.4rem/1.2
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        letter-spacing: -0.015em;
        color: var(--foreground);
        margin: 0 0 1rem;
      }

      /* Empty lead placeholder — shown when no lead is pinned */
      .lead-publish-btn {
        border: 1px solid var(--primary);
        border-radius: 62.4375rem;
        background-color: var(--primary);
        color: var(--primary-foreground);
        font: 600 0.8125rem var(--blog-font-family, sans-serif);
        padding: 0.5rem 1.125rem;
        cursor: pointer;
      }

      .section-empty {
        grid-column: 1 / -1;
        padding: 1.75rem 1.25rem;
        border: 1.5px dashed var(--border);
        border-radius: 0.75rem;
        text-align: center;
        font: 500 0.875rem var(--blog-font-family, sans-serif);
        color: var(--muted-foreground);
      }

      .lead-empty {
        height: 100%;
        min-height: 32.5rem;
        border-radius: 1.125rem;
        background-color: var(--inset);
        border: 2px dashed var(--border);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.75rem;
        padding: var(--boxel-sp-xl);
        text-align: center;
      }
      .lead-empty-label {
        font: 700 0.75rem
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        text-transform: uppercase;
        letter-spacing: 0.18em;
        color: var(--subtle-foreground);
      }
      .lead-empty p {
        margin: 0;
        font: 500 0.95rem/1.5
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        color: var(--muted-foreground);
      }

      /* Lead drop zone — highlights when a card is dragged over */
      .hero-lead {
        border-radius: 1.125rem;
        transition:
          outline-color 0.15s,
          outline-offset 0.15s;
        outline: 0 dashed transparent;
        outline-offset: 0;
      }
      .hero-lead.is-drop-target {
        outline: 3px dashed var(--primary);
        outline-offset: 8px;
      }

      /* Lead — single embedded card, big image overlay */
      .lead-list {
        cursor: grab;
        transition:
          opacity 0.15s,
          transform 0.15s;
      }
      .lead-list:active {
        cursor: grabbing;
      }
      .lead-list.is-dragging {
        opacity: 0.4;
        transform: scale(0.99);
      }
      .lead-list :deep(ul) {
        display: block;
        list-style: none;
        padding: 0;
        margin: 0;
      }
      .lead-list :deep(li) {
        margin: 0;
        padding: 0;
        border: none;
        gap: 0 !important;
      }
      .lead-list :deep(li ~ li) {
        display: none;
      }
      .lead-list :deep(.card) {
        min-height: 37.5rem !important;
        max-width: 100% !important;
        border-radius: 1.125rem;
        overflow: hidden;
        box-shadow: none !important;
        cursor: pointer;
      }
      .lead-list :deep(.embedded-blog-post) {
        display: block !important;
        grid-template: none !important;
        padding: 0 !important;
        position: relative;
        height: 100%;
        min-height: 37.5rem;
        border-radius: 1.125rem;
        overflow: hidden !important;
        background-color: var(--card);
        color: var(--card-foreground);
        isolation: isolate;
      }
      .lead-list :deep(.thumbnail) {
        position: absolute !important;
        inset: 0;
        width: 100% !important;
        height: 100% !important;
        margin: 0 !important;
        background-color: var(--card);
        color: var(--card-foreground);
        transition: transform 0.35s ease;
        z-index: 0;
      }
      .lead-list :deep(li):hover .thumbnail {
        transform: scale(1.03);
      }
      .lead-list :deep(.embedded-blog-post)::after {
        content: '';
        position: absolute;
        inset: 0;
        background: linear-gradient(
          to top,
          color-mix(in oklch, var(--foreground) 88%, transparent) 0%,
          color-mix(in oklch, var(--foreground) 40%, transparent) 45%,
          transparent 75%
        );
        z-index: 1;
        pointer-events: none;
      }
      .lead-list :deep(.categories) {
        position: absolute;
        left: 1.75rem;
        bottom: 6.25rem;
        z-index: 2;
        margin: 0 !important;
        display: flex !important;
        gap: 0.375rem !important;
      }
      .lead-list :deep(.category) {
        /* Fixed white-on-photo pill: text must stay dark in every theme */
        background-color: var(--card) !important;
        color: var(--foreground) !important;
        padding: 0.3125rem 0.875rem !important;
        border-radius: 62.4375rem !important;
        font: 600 0.6875rem/1
          var(--blog-font-family, 'Inter', system-ui, sans-serif) !important;
        letter-spacing: 0 !important;
        text-transform: capitalize !important;
        border: none;
      }
      .lead-list :deep(.title) {
        position: absolute;
        left: 1.75rem;
        right: 1.75rem;
        bottom: 1.75rem;
        z-index: 2;
        font: 700 2rem/1.15
          var(--blog-font-family, 'Inter', system-ui, sans-serif) !important;
        letter-spacing: -0.015em !important;
        color: var(--tooltip-foreground) !important;
        margin: 0 !important;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .lead-list :deep(.description),
      .lead-list :deep(.byline),
      .lead-list :deep(.date) {
        display: none !important;
      }

      /* Right column — fitted format, horizontal thumb + title */
      .hero-aside {
        display: flex;
        flex-direction: column;
      }
      .featured-list {
        flex: 1;
      }
      .featured-list :deep(ul) {
        display: flex;
        flex-direction: column;
        gap: 0;
        list-style: none;
        padding: 0;
        margin: 0;
      }
      .featured-list :deep(li) {
        margin: 0;
        padding: 0.875rem 0;
        border: none;
        border-top: 1px solid var(--border);
        gap: 0 !important;
      }
      .featured-list :deep(li:first-child) {
        display: none;
      }
      .featured-list :deep(li:nth-child(2)) {
        border-top: none;
        padding-top: 0;
      }
      .featured-list :deep(li:nth-child(n + 5)) {
        display: none;
      }
      .featured-list :deep(.card) {
        min-height: 0 !important;
        max-width: 100% !important;
        width: 100%;
        height: 13.75rem;
        aspect-ratio: auto;
        cursor: pointer;
        box-shadow: none !important;
        border-radius: 0.75rem;
        overflow: hidden;
        background-color: transparent;
      }
      .featured-list :deep(.fitted-blog-post) {
        padding: 0 !important;
        gap: 1rem !important;
      }
      .featured-list :deep(.fitted-blog-post .thumbnail) {
        width: 10rem !important;
        height: 13.75rem !important;
        border-radius: 0.75rem !important;
        flex-shrink: 0;
      }
      .featured-list :deep(.fitted-blog-post .title) {
        font: 600 0.95rem/1.32
          var(--blog-font-family, 'Inter', system-ui, sans-serif) !important;
        letter-spacing: -0.005em !important;
        color: var(--foreground) !important;
        -webkit-line-clamp: 3 !important;
      }
      .featured-list :deep(.card):hover .title {
        color: var(--primary-ink) !important;
      }

      /* Manual featured: one drop zone, any number of cards */
      .featured-list.manual {
        display: flex;
        flex-direction: column;
        gap: 0;
        border-radius: 0.75rem;
        transition:
          outline-color 0.15s,
          outline-offset 0.15s,
          background-color 0.15s;
      }
      .featured-list.manual.is-drop-target {
        outline: 2px dashed var(--primary);
        outline-offset: 4px;
        background-color: var(--hover);
      }
      .featured-slot {
        padding: 0.75rem 0;
        border-top: 1px solid var(--border);
        height: 13.75rem;
        cursor: grab;
        transition:
          opacity 0.15s,
          transform 0.15s;
      }
      .featured-slot:first-child {
        border-top: none;
        padding-top: 0;
        height: 13rem;
      }
      .featured-slot:active {
        cursor: grabbing;
      }
      .featured-slot.is-dragging {
        opacity: 0.4;
        transform: scale(0.98);
      }
      .featured-slot.is-drop-target {
        outline: 2px dashed var(--primary);
        outline-offset: 2px;
        border-radius: 0.375rem;
      }
      .featured-slot :deep(.fitted-blog-post) {
        height: 100%;
        width: 100%;
        padding: 0 !important;
        gap: 1rem !important;
        display: grid !important;
        grid-template-columns: 10rem 1fr !important;
        align-items: center;
      }
      .featured-slot :deep(.fitted-blog-post .thumbnail) {
        width: 10rem !important;
        height: 100% !important;
        border-radius: 0.75rem !important;
        flex-shrink: 0;
        background-size: cover !important;
        background-position: center !important;
      }
      .featured-slot :deep(.fitted-blog-post .title) {
        font: 600 1.05rem/1.3
          var(--blog-font-family, 'Inter', system-ui, sans-serif) !important;
        letter-spacing: -0.005em !important;
        color: var(--foreground) !important;
        -webkit-line-clamp: 3 !important;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .featured-slot :deep(.fitted-blog-post .description) {
        display: -webkit-box !important;
        -webkit-line-clamp: 2 !important;
        -webkit-box-orient: vertical;
        font: 400 0.85rem/1.4
          var(--blog-font-family, 'Inter', system-ui, sans-serif) !important;
        color: var(--muted-foreground) !important;
        margin-top: 0.25rem !important;
      }
      .featured-slot :hover :deep(.fitted-blog-post .title) {
        color: var(--primary-ink) !important;
      }
      .featured-empty {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 5.25rem;
        padding: 0 0.875rem;
        background-color: var(--inset);
        border: 2px dashed var(--border);
        border-radius: 0.75rem;
        color: var(--subtle-foreground);
        font: 500 0.85rem/1.3
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
      }

      /* Games subsection — horizontal strip of fitted preview tiles */
      .aside-heading--games {
        margin-top: var(--boxel-sp-xl);
      }
      .games-list {
        display: flex;
        flex-direction: row;
        gap: 0.75rem;
        overflow-x: auto;
        scroll-snap-type: x mandatory;
        scroll-behavior: smooth;
        padding: 0.25rem 2px 0.75rem;
        margin: 0 -2px;
        scrollbar-width: thin;
      }
      .games-list::-webkit-scrollbar {
        height: 0.375rem;
      }
      .games-list::-webkit-scrollbar-thumb {
        background-color: var(--border);
        border-radius: 0.1875rem;
      }
      .games-list::-webkit-scrollbar-thumb:hover {
        background-color: var(--muted);
        color: var(--muted-foreground);
      }
      .games-card {
        flex: 0 0 12.5rem;
        scroll-snap-align: start;
        height: 5.25rem;
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        overflow: hidden;
        cursor: pointer;
        background-color: var(--card);
        color: var(--card-foreground);
        transition:
          border-color 0.15s,
          box-shadow 0.15s,
          transform 0.1s;
      }
      .games-card:hover {
        border-color: var(--primary);
        box-shadow: 0 3px 10px
          color-mix(in oklch, var(--shadow-color) 8%, transparent);
        transform: translateY(-1px);
      }
      .games-card :deep(.card) {
        min-height: 0 !important;
        max-width: 100% !important;
        width: 100%;
        height: 100%;
        background-color: transparent;
        box-shadow: none !important;
        border: none;
      }
      .games-list.is-drop-target {
        outline: 2px dashed var(--primary);
        outline-offset: 4px;
        background-color: var(--hover);
        border-radius: 0.75rem;
      }
      .games-empty {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 5.25rem;
        flex: 1;
        padding: 0 0.875rem;
        background-color: var(--inset);
        border: 2px dashed var(--border);
        border-radius: 0.75rem;
        color: var(--subtle-foreground);
        font: 500 0.85rem/1.3
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
      }
      .aside-loading {
        color: var(--boxel-500);
        font: 600 0.75rem/1
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        padding: 0.75rem 0;
      }

      /* Writer's Picks — horizontal scroll carousel */
      .picks {
        max-width: 77.5rem;
        margin: 0 auto;
        padding: var(--boxel-sp-xxl) var(--boxel-sp-lg) 0;
      }
      .picks-head {
        margin-bottom: var(--boxel-sp-lg);
      }
      .picks-title {
        font: 800 2rem/1.1
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        letter-spacing: -0.02em;
        margin: 0 0 0.375rem;
        color: var(--foreground);
      }
      .picks-subtitle {
        font: 400 1rem/1.4
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        color: var(--muted-foreground);
        margin: 0;
      }
      /* Carousel — manual horizontal scroll, both directions */
      .picks-carousel {
        display: flex;
        gap: 1.25rem;
        overflow-x: auto;
        overflow-y: hidden;
        scroll-snap-type: x mandatory;
        scroll-behavior: smooth;
        scroll-padding: var(--boxel-sp-lg);
        padding: 0.375rem var(--boxel-sp-lg) 1.75rem;
        margin: 0 calc(-1 * var(--boxel-sp-lg));
        scrollbar-width: thin;
        scrollbar-color: var(--border) transparent;
      }
      .picks-carousel::-webkit-scrollbar {
        height: 0.625rem;
      }
      .picks-carousel::-webkit-scrollbar-track {
        background-color: transparent;
      }
      .picks-carousel::-webkit-scrollbar-thumb {
        background-color: var(--border);
        border-radius: 0.3125rem;
      }
      .picks-carousel::-webkit-scrollbar-thumb:hover {
        background-color: var(--muted);
        color: var(--muted-foreground);
      }
      .picks-card {
        flex: 0 0 22.5rem;
        scroll-snap-align: start;
        height: 12.5rem;
        border-radius: 0.875rem;
        overflow: hidden;
        box-shadow: 0 2px 6px
          color-mix(in oklch, var(--shadow-color) 8%, transparent);
        cursor: pointer;
        transition:
          box-shadow 0.15s,
          transform 0.15s;
      }
      .picks-card:hover {
        box-shadow: 0 8px 24px
          color-mix(in oklch, var(--shadow-color) 14%, transparent);
        transform: translateY(-2px);
      }
      .picks-card :deep(.card) {
        height: 100% !important;
        min-height: 100% !important;
        max-width: 100% !important;
        width: 100%;
      }
      /* Force the horizontal "image | content" layout so cards always
         render their thumbnail, regardless of container-query timing. */
      .picks-card :deep(.fitted-blog-post) {
        display: grid !important;
        grid-template: 'img content' 1fr / 42% 1fr !important;
        gap: 0 !important;
        padding: 0 !important;
        height: 100%;
        width: 100%;
      }
      .picks-card :deep(.fitted-blog-post .thumbnail) {
        grid-area: img !important;
        width: 100% !important;
        height: 100% !important;
        margin: 0 !important;
        background-color: var(--inset) !important;
        background-position: center !important;
        background-size: cover !important;
        background-repeat: no-repeat !important;
      }
      .picks-card :deep(.fitted-blog-post .content) {
        grid-area: content !important;
        padding: var(--boxel-sp-sm) var(--boxel-sp) !important;
        display: flex !important;
        flex-direction: column;
        gap: 0.25rem;
        overflow: hidden;
        min-width: 0;
      }
      .picks-card :deep(.fitted-blog-post .categories) {
        display: none !important;
      }
      .picks-card :deep(.fitted-blog-post .title) {
        font: 700 1rem/1.25
          var(--blog-font-family, 'Inter', system-ui, sans-serif) !important;
        letter-spacing: -0.005em !important;
        color: var(--foreground) !important;
        margin: 0 !important;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
      }
      .picks-card :deep(.fitted-blog-post .description) {
        font: 400 0.82rem/1.4
          var(--blog-font-family, 'Inter', system-ui, sans-serif) !important;
        color: var(--muted-foreground) !important;
        margin: 0 !important;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .picks-card :deep(.fitted-blog-post .byline),
      .picks-card :deep(.fitted-blog-post .date) {
        font: 600 0.7rem/1
          var(--blog-font-family, 'Inter', system-ui, sans-serif) !important;
        color: var(--subtle-foreground) !important;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        margin: 0 !important;
      }

      /* ── Recent Posts section ──────────────────────────── */
      .recent {
        max-width: 77.5rem;
        margin: 0 auto;
        padding: var(--boxel-sp-xxl) var(--boxel-sp-lg) var(--boxel-sp-xxl);
      }
      .recent-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp);
        margin-bottom: var(--boxel-sp-lg);
        flex-wrap: wrap;
      }
      .recent-title {
        font: 800 2rem/1.1
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        letter-spacing: -0.02em;
        margin: 0;
        color: var(--foreground);
      }
      .filter-pills {
        display: inline-flex;
        gap: 0.625rem;
        flex-wrap: wrap;
      }
      .filter-pills .pill {
        padding: 0.5625rem 1.25rem;
        background-color: var(--card);
        color: var(--foreground);
        border: 1px solid var(--border-strong);
        border-radius: 62.4375rem;
        cursor: pointer;
        font: 600 0.8125rem/1
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        letter-spacing: 0;
        transition:
          background-color 0.15s,
          color 0.15s,
          transform 0.1s;
      }
      .filter-pills .pill:hover {
        background-color: var(--card);
        color: var(--card-foreground);
      }
      .filter-pills .pill:active {
        transform: scale(0.97);
      }
      .filter-pills .pill.is-active {
        background-color: var(--card);
        color: var(--card-foreground);
        border-color: var(--border-strong);
      }
      .filter-pills .pill.is-active:hover {
        background-color: var(--card);
        color: var(--card-foreground);
      }
      /* Recent grid — 2 rows × 3 columns of fitted cards.
         Hides hero items 1-6 and overflow items 13+, leaving 7-12. */
      .recent-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: var(--boxel-sp-lg);
      }
      .recent-card {
        height: 26.25rem;
        border-radius: 0.875rem;
        overflow: hidden;
        box-shadow: 0 1px 3px
          color-mix(in oklch, var(--shadow-color) 8%, transparent);
        cursor: pointer;
        transition:
          box-shadow 0.15s,
          transform 0.15s;
      }
      .recent-card:hover {
        box-shadow: 0 6px 18px
          color-mix(in oklch, var(--shadow-color) 12%, transparent);
        transform: translateY(-2px);
      }
      .recent-card :deep(.card) {
        height: 100% !important;
        min-height: 100% !important;
        max-width: 100% !important;
        width: 100%;
      }
      /* Cap at 12 items always so the grid stays bounded */
      .recent-grid .recent-card:nth-child(n + 13) {
        display: none;
      }
      /* "Latest" pill: show only top 6 (2×3) */
      .recent-grid.filter-latest .recent-card:nth-child(n + 7) {
        display: none;
      }
      .recent-loading {
        grid-column: 1 / -1;
        color: var(--boxel-500);
        font: 600 0.8125rem/1
          var(--blog-font-family, 'Inter', system-ui, sans-serif);
        padding: var(--boxel-sp-lg) 0;
        text-align: center;
      }

      /* ── Responsive — keyed to the card's own width, since the isolated
         view narrows with host panels, not just the viewport ── */
      @container blog-site (max-width: 900px) {
        .hero-grid {
          grid-template-columns: 1fr;
        }
      }
      @container blog-site (max-width: 700px) {
        .brand-title {
          font-size: 1.75rem;
        }
        .recent-title {
          font-size: 1.5rem;
        }
        .recent-grid {
          grid-template-columns: 1fr;
        }
        .picks-card {
          flex-basis: 17.5rem;
        }
      }
    </style>
  </template>
}
