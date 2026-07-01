import {
  contains,
  field,
  CardDef,
  ImageDef,
  linksToMany,
  StringField,
  linksTo,
  Component,
  instanceOf,
  realmURL,
  type GetMenuItemParams,
} from 'https://cardstack.com/base/card-api';
import { commandData } from 'https://cardstack.com/base/resources/command-data';
import MarkdownField from 'https://cardstack.com/base/markdown';
import { Spec } from 'https://cardstack.com/base/spec';
import { Skill } from 'https://cardstack.com/base/skill';
import type {
  GetAllRealmMetasResult,
  RealmMetaField,
} from 'https://cardstack.com/base/command';

import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { htmlSafe } from '@ember/template';
import { tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import { task } from 'ember-concurrency';
import { eq, not, type MenuItemOptions } from '@cardstack/boxel-ui/helpers';

import { CardContainer } from '@cardstack/boxel-ui/components';
import Refresh from '@cardstack/boxel-icons/refresh';
import Wand from '@cardstack/boxel-icons/wand';
import Package from '@cardstack/boxel-icons/package';

import ChooseRealmAction from '../components/choose-realm-action';
import { ListingFittedTemplate } from '../components/listing-fitted';
import { typeMetaForDisplayName, typeMetaForKey } from './listing-type-meta';
import SpecFieldsGrid from './spec-fields-grid';
import { listingActions, isReady } from '../resources/listing-actions';
import { consumeRemixFocus } from '../resources/remix-intent';

import GetAllRealmMetasCommand from '@cardstack/boxel-host/commands/get-all-realm-metas';
import ListingGenerateExampleCommand from '@cardstack/catalog/commands/listing-generate-example';
import ListingUpdateSpecsCommand from '@cardstack/catalog/commands/listing-update-specs';
import CreateAndOpenSubmissionWorkflowCardCommand from '@cardstack/boxel-host/commands/create-and-open-submission-workflow-card';

import { getMenuItems } from '@cardstack/runtime-common';

import { Publisher } from './publisher';
import { Category } from './category';
import { License } from './license';
import { Tag } from './tag';

const DETAIL_TABS = ['Summary', 'Includes', 'Examples', 'License'];

class EmbeddedTemplate extends Component<typeof Listing> {
  @tracked selectedTab = 'Summary';
  @tracked selectedShot = 0;

  actionsResource = listingActions(this, () => ({
    listing: this.args.model as Listing,
  }));

  allRealmsInfoResource = commandData<typeof GetAllRealmMetasResult>(
    this,
    GetAllRealmMetasCommand,
  );

  get writableRealms(): { name: string; url: string; iconURL?: string }[] {
    const commandResource = this.allRealmsInfoResource;
    if (commandResource?.isSuccess && commandResource.cardResult) {
      const result = commandResource.cardResult as GetAllRealmMetasResult;
      if (result.results) {
        return result.results
          .filter(
            (realmMeta: RealmMetaField) =>
              realmMeta.canWrite &&
              realmMeta.realmIdentifier !== this.args.model[realmURL]?.href,
          )
          .map((realmMeta: RealmMetaField) => ({
            name: realmMeta.info.name,
            url: realmMeta.realmIdentifier,
            iconURL: realmMeta.info.iconURL,
          }));
      }
    }
    return [];
  }

  get isInCatalogRealm(): boolean {
    return this.args.model[realmURL]?.href.endsWith('/catalog/') ?? false;
  }

  get actions() {
    return isReady(this.actionsResource)
      ? this.actionsResource.actions
      : undefined;
  }

  get regularActions() {
    return this.actions?.type === 'regular' ? this.actions : undefined;
  }

  get themeActions() {
    return this.actions?.type === 'theme' ? this.actions : undefined;
  }

  get skillActions() {
    return this.actions?.type === 'skill' ? this.actions : undefined;
  }

  get remix() {
    return (
      this.regularActions?.remix ??
      this.themeActions?.remix ??
      this.skillActions?.remix
    );
  }

  addSkillsToCurrentRoom = task(async () => {
    this.skillActions?.addSkillsToRoom?.();
  });

  getComponent = (card: CardDef) => card.constructor.getComponent(card);

  get typeMeta() {
    return typeMetaForDisplayName(
      (this.args.model.constructor as typeof CardDef).displayName,
    );
  }

  get publisherHandle(): string {
    let name = this.args.model.publisher?.name;
    return name ? '@' + name : '';
  }

  get images(): string[] {
    return (this.args.model.images ?? [])
      .map((image) => image?.url)
      .filter((url): url is string => Boolean(url));
  }

  get previewImage(): string | undefined {
    return this.images[this.selectedShot] ?? this.images[0];
  }

  get monogram(): string {
    return (this.args.model.name?.trim()[0] ?? '?').toUpperCase();
  }

  get hasImages() {
    return this.images.length > 0;
  }

  get hasExamples() {
    return Boolean(this.args.model.examples?.length);
  }

  get hasTags() {
    return Boolean(this.args.model.tags?.length);
  }

  get specBreakdown() {
    if (!this.args.model.specs) {
      return {} as Record<string, Spec[]>;
    }
    return specBreakdown(this.args.model.specs);
  }

  get hasNonEmptySpecBreakdown() {
    return Object.values(this.specBreakdown).some((specs) => specs.length > 0);
  }

  // The spec this listing is fundamentally about — used to give the Summary
  // tab a quick "what fields does this expose" preview without opening code.
  get primarySpec(): Spec | undefined {
    return this.args.model.specs?.[0];
  }

  get infoRows() {
    let specCount = this.args.model.specs?.length ?? 0;
    return [
      { label: 'Type', value: this.typeMeta.label },
      {
        label: 'Includes',
        value: `${specCount} ${specCount === 1 ? 'spec' : 'specs'}`,
      },
      {
        label: 'License',
        value: this.args.model.license?.name || 'Open Remix',
      },
    ];
  }

  setTab = (tab: string) => {
    this.selectedTab = tab;
  };

  selectShot = (index: number) => {
    this.selectedShot = index;
  };

  preview = () => {
    this.actions?.preview?.();
  };

  get chipDotStyle() {
    return htmlSafe(`background: var(${this.typeMeta.colorVar}, #ff5b9c);`);
  }

  get coverStyle() {
    let v = this.typeMeta.colorVar;
    return htmlSafe(
      `background: linear-gradient(135deg, color-mix(in srgb, var(${v}, #ff5b9c) 22%, transparent), color-mix(in srgb, var(${v}, #ff5b9c) 6%, transparent)), #fbfaf5;`,
    );
  }

  get monogramStyle() {
    return htmlSafe(`color: var(${this.typeMeta.colorVar}, #ff5b9c);`);
  }

  specGroupDotStyle = (kind: string) =>
    htmlSafe(`background: var(${typeMetaForKey(kind).colorVar}, #ff5b9c);`);

  // When arriving from a gallery card's Remix, scroll the panel into view and
  // briefly highlight it so the user lands ready to fork.
  focusRemix = modifier((el: HTMLElement) => {
    if (!consumeRemixFocus(this.args.model.id)) {
      return undefined;
    }
    // Only scroll on the stacked one-column layout (panel below the content).
    // On the two-column layout the panel is beside the content, so scrolling
    // would drag the left column — match the `.main` container query
    // breakpoint (56rem) directly rather than parsing computed grid tracks.
    let main = el.closest('.main') as HTMLElement | null;
    let isOneColumn = (main?.getBoundingClientRect().width ?? 0) <= 56 * 16;
    if (isOneColumn) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    el.classList.add('is-focused');
    let timer = setTimeout(() => el.classList.remove('is-focused'), 1800);
    return () => clearTimeout(timer);
  });

  <template>
    <div class='listing-detail' data-test-catalog-listing-embedded>
      <section class='title-block'>
        <nav class='breadcrumb' aria-label='Breadcrumb'>
          <span>Catalog</span>
          <span class='sep'>/</span>
          <span class='crumb-type'>{{this.typeMeta.plural}}</span>
          <span class='sep'>/</span>
          <span class='crumb-current'>{{@model.name}}</span>
        </nav>
        <div class='title-row'>
          <h1 class='title'>{{@model.name}}</h1>
          <span class='type-chip'>
            <span class='type-dot' style={{this.chipDotStyle}}></span>
            {{this.typeMeta.label}}
          </span>
        </div>
        {{#if @model.cardDescription}}
          <p class='lede'>{{@model.cardDescription}}</p>
        {{/if}}
        {{#if this.publisherHandle}}
          <div class='byline'>by
            <strong>{{this.publisherHandle}}</strong></div>
        {{/if}}
      </section>

      <section class='main'>
        <div class='left'>
          <div class='preview-frame'>
            <div class='chrome'>
              <span class='chrome-dot red'></span>
              <span class='chrome-dot amber'></span>
              <span class='chrome-dot green'></span>
              <span class='chrome-label'>{{@model.name}}{{if
                  this.hasImages
                  ' · screenshot'
                }}</span>
            </div>
            <div class='preview {{unless this.hasImages "preview-empty"}}'>
              {{#if this.previewImage}}
                <img
                  src={{this.previewImage}}
                  alt={{@model.name}}
                  class='preview-img'
                />
              {{else}}
                <div class='cover' style={{this.coverStyle}}>
                  <span
                    class='monogram'
                    style={{this.monogramStyle}}
                  >{{this.monogram}}</span>
                </div>
              {{/if}}
            </div>
          </div>

          {{#if this.hasImages}}
            <div class='thumbs'>
              {{#each this.images as |shot index|}}
                <button
                  type='button'
                  class='thumb {{if (eq index this.selectedShot) "is-active"}}'
                  {{on 'click' (fn this.selectShot index)}}
                >
                  <img src={{shot}} alt='Screenshot' />
                </button>
              {{/each}}
            </div>
          {{/if}}

          <div class='tabs' role='tablist'>
            {{#each DETAIL_TABS as |tab|}}
              <button
                type='button'
                role='tab'
                aria-selected='{{if (eq this.selectedTab tab) "true" "false"}}'
                tabindex='{{if (eq this.selectedTab tab) "0" "-1"}}'
                class='tab {{if (eq this.selectedTab tab) "is-active"}}'
                data-test-listing-tab={{tab}}
                {{on 'click' (fn this.setTab tab)}}
              >{{tab}}</button>
            {{/each}}
          </div>

          {{#if (eq this.selectedTab 'Summary')}}
            <div class='panel' data-test-listing-summary>
              <h3 class='panel-title'>What this card does</h3>
              {{#if @model.summary}}
                <@fields.summary />
              {{else}}
                <p class='muted'>No summary provided.</p>
              {{/if}}
              {{#if this.primarySpec}}
                <h3 class='panel-title fields-title'>Fields</h3>
                <SpecFieldsGrid @spec={{this.primarySpec}} />
              {{/if}}
            </div>
          {{/if}}

          {{#if (eq this.selectedTab 'Includes')}}
            <div class='panel' data-test-listing-includes>
              <h3 class='panel-title'>Includes these Specs</h3>
              <p class='panel-sub'>Everything below is forked into your realm
                together. Each piece is independently remixable.</p>
              {{#if this.hasNonEmptySpecBreakdown}}
                {{#each-in this.specBreakdown as |kind specs|}}
                  <div class='include-group'>
                    <div class='include-group-head'>
                      <span
                        class='include-dot'
                        style={{this.specGroupDotStyle kind}}
                      ></span>
                      <span class='include-kind'>{{if
                          (eq kind 'unknown')
                          'Other'
                          kind
                        }}</span>
                    </div>
                    <div class='include-cards'>
                      {{#each specs as |spec|}}
                        {{#let (this.getComponent spec) as |SpecComponent|}}
                          <CardContainer class='include-card'>
                            <SpecComponent @format='fitted' />
                          </CardContainer>
                        {{/let}}
                      {{/each}}
                    </div>
                  </div>
                {{/each-in}}
              {{else}}
                <p class='muted'>No specs included.</p>
              {{/if}}
            </div>
          {{/if}}

          {{#if (eq this.selectedTab 'Examples')}}
            <div class='panel' data-test-listing-examples>
              <h3 class='panel-title'>Live instances</h3>
              <p class='panel-sub'>Real examples built by remixing this listing.</p>
              {{#if this.hasExamples}}
                <div class='examples-grid'>
                  {{#each @fields.examples as |Example|}}
                    <Example class='example-card' @format='fitted' />
                  {{/each}}
                </div>
              {{else}}
                <p class='muted'>No examples provided.</p>
              {{/if}}
            </div>
          {{/if}}

          {{#if (eq this.selectedTab 'License')}}
            <div class='panel' data-test-listing-license>
              <h3 class='panel-title'>License &amp; terms</h3>
              <div class='license-card'>
                {{#if @model.license.name}}
                  <span class='license-pill'>{{@model.license.name}}</span>
                {{else}}
                  <span class='license-pill'>Open Remix</span>
                {{/if}}
                <p class='license-body'>Fork freely, modify anything, ship it in
                  your own realm. Attribution to the original creator is kept in
                  the card's lineage.</p>
              </div>
            </div>
          {{/if}}
        </div>

        <aside class='right'>
          <div class='remix-panel' data-remix-panel {{this.focusRemix}}>
            <div class='remix-eyebrow'>Remix, don't rebuild</div>
            <div class='remix-title'>Free to remix</div>
            <p class='remix-sub'>Fork the full source into your realm in seconds
              — ready to run.</p>
            {{#if this.remix}}
              <ChooseRealmAction
                @name='Remix into my realm'
                @writableRealms={{this.writableRealms}}
                @onAction={{this.remix}}
                @hide={{not this.isInCatalogRealm}}
              />
            {{/if}}
            {{#if this.actions.preview}}
              <button
                type='button'
                class='remix-secondary'
                {{on 'click' this.preview}}
              >▷ Try live preview</button>
            {{/if}}
            {{#if this.skillActions.addSkillsToRoom}}
              <button
                type='button'
                class='remix-secondary'
                {{on 'click' this.skillActions.addSkillsToRoom}}
              >Use Skills</button>
            {{/if}}
          </div>

          <div class='info-card'>
            {{#each this.infoRows as |row|}}
              <div class='info-row'>
                <span class='info-label'>{{row.label}}</span>
                <span class='info-value'>{{row.value}}</span>
              </div>
            {{/each}}
          </div>

          {{#if this.hasTags}}
            <div class='tags-card'>
              <div class='tags-title'>Tags</div>
              <div class='tags-list'>
                {{#each @model.tags as |tag|}}
                  <span class='tag'>{{tag.name}}</span>
                {{/each}}
              </div>
            </div>
          {{/if}}
        </aside>
      </section>
    </div>

    <style scoped>
      .listing-detail {
        /* Same catalog-domain signal colors as the storefront index, so the
           type chip + monogram match the homepage (this is a separate render). */
        --type-card: var(--chart-1, #ff5b9c);
        --type-component: var(--chart-2, #2bb3ff);
        --type-field: var(--chart-3, #7b5bff);
        --type-skill: var(--chart-4, #c2e23f);
        --type-theme: var(--chart-5, #ff9d3d);
        --type-app: var(--brand, #6c4bf5);
        --brand: #6c4bf5;
        background: var(--background, #ece9e1);
        color: var(--foreground, #16161c);
        font-family: var(--font-sans, 'IBM Plex Sans', sans-serif);
        padding: 2.5rem 2rem 5.625rem;
        container-type: inline-size;
        container-name: listing-detail;
      }
      .title-block {
        max-width: 75rem;
        margin: 0 auto 1.625rem;
      }
      .breadcrumb {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font: 500 0.75rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        color: var(--muted-foreground, #8a8578);
        margin-bottom: 1rem;
      }
      .crumb-type {
        color: var(--brand, #6c4bf5);
      }
      .crumb-current {
        color: var(--foreground, #16161c);
      }
      .title-row {
        display: flex;
        align-items: center;
        gap: 0.6875rem;
        margin-bottom: 0.75rem;
      }
      .title {
        margin: 0;
        font: 700 2.625rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        letter-spacing: -0.03em;
      }
      .type-chip {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.375rem 0.6875rem;
        background: var(--card, #fff);
        border: 1px solid var(--border, #ddd8cb);
        border-radius: 999px;
        font: 600 0.625rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .type-dot {
        width: 0.375rem;
        height: 0.375rem;
        border-radius: 50%;
      }
      .lede {
        margin: 0;
        max-width: 37.5rem;
        font: 400 1rem/1.55 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #5f5b52);
      }
      .byline {
        margin-top: 1.125rem;
        font: 500 0.8125rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #6b675e);
      }
      .byline strong {
        color: var(--foreground, #16161c);
        font-weight: 600;
      }

      .main {
        max-width: 75rem;
        margin: 0 auto;
        display: grid;
        grid-template-columns: 1fr 20.75rem;
        gap: 2.5rem;
        align-items: start;
      }
      .left {
        min-width: 0;
      }

      .preview-frame {
        background: var(--card, #fff);
        border-radius: 1.125rem;
        padding: 0.875rem;
        box-shadow: var(--shadow-md, 0 18px 40px -26px rgba(0, 0, 0, 0.4));
      }
      .chrome {
        display: flex;
        align-items: center;
        gap: 0.4375rem;
        padding: 0.25rem 0.375rem 0.75rem;
      }
      .chrome-dot {
        width: 0.6875rem;
        height: 0.6875rem;
        border-radius: 50%;
      }
      .chrome-dot.red {
        background: #ff5f57;
      }
      .chrome-dot.amber {
        background: #febc2e;
      }
      .chrome-dot.green {
        background: #28c840;
      }
      .chrome-label {
        margin-left: 0.625rem;
        font: 500 0.6875rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        color: var(--muted-foreground, #b3aea2);
      }
      .live {
        margin-left: auto;
        font: 600 0.625rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        letter-spacing: 0.06em;
        color: var(--primary, #00b886);
      }
      .preview {
        position: relative;
        aspect-ratio: 4 / 3;
        background: #2a1410;
        border-radius: 0.625rem;
        overflow: hidden;
      }
      /* No screenshot: keep the monogram cover compact instead of a big 4:3. */
      .preview.preview-empty {
        aspect-ratio: auto;
        height: 12rem;
      }
      .preview.preview-empty .monogram {
        font-size: 3.5rem;
      }
      .preview-img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        object-position: top center;
        display: block;
      }
      .cover {
        width: 100%;
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .monogram {
        font: 600 5rem/1 var(--font-serif, 'IBM Plex Serif', serif);
      }

      .thumbs {
        display: flex;
        gap: 0.625rem;
        margin-top: 0.75rem;
      }
      .thumb {
        width: 6rem;
        aspect-ratio: 4 / 3;
        padding: 0;
        border-radius: 0.5625rem;
        overflow: hidden;
        cursor: pointer;
        background: #2a1410;
        border: 2px solid transparent;
      }
      .thumb.is-active {
        border-color: var(--foreground, #16161c);
      }
      .thumb img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        object-position: top center;
        display: block;
      }

      .tabs {
        margin-top: 2.25rem;
        border-bottom: 1px solid var(--border, #d8d3c6);
        display: flex;
        gap: 0.25rem;
      }
      .tab {
        padding: 0.75rem 1rem;
        background: none;
        border: none;
        border-bottom: 2px solid transparent;
        cursor: pointer;
        font: 600 0.84rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #8a8578);
        margin-bottom: -1px;
      }
      .tab.is-active {
        color: var(--foreground, #16161c);
        border-bottom-color: var(--foreground, #16161c);
      }

      .panel {
        padding-top: 1.625rem;
      }
      .panel-title {
        margin: 0 0 0.75rem;
        font: 600 1.1875rem/1.2 var(--font-sans, 'IBM Plex Sans', sans-serif);
      }
      .fields-title {
        margin-top: 1.875rem;
      }
      .panel-sub {
        margin: 0 0 1.125rem;
        font: 400 0.84rem/1.5 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #807c72);
      }
      .muted {
        color: var(--muted-foreground, #807c72);
      }

      .include-group {
        margin-bottom: 1.25rem;
      }
      .include-group-head {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        margin-bottom: 0.625rem;
      }
      .include-dot {
        width: 0.4375rem;
        height: 0.4375rem;
        border-radius: 50%;
      }
      .include-kind {
        font: 600 0.6875rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground, #8a8578);
      }
      .include-cards {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr));
        gap: 0.75rem;
      }
      .include-card {
        height: 4.5rem;
      }

      .examples-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 0.75rem;
      }
      .example-card {
        min-height: 11rem;
      }

      .license-card {
        padding: 1.125rem 1.25rem;
        background: var(--card, #fff);
        border-radius: 0.8125rem;
        border: 1px solid var(--border, #eae5da);
        max-width: 40rem;
      }
      .license-pill {
        display: inline-block;
        font: 600 0.6875rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        padding: 0.3125rem 0.625rem;
        background: #eafaf3;
        color: #00936b;
        border-radius: 999px;
        margin-bottom: 0.75rem;
      }
      .license-body {
        margin: 0;
        font: 400 0.84rem/1.6 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #5f5b52);
      }

      .right {
        position: sticky;
        top: 1.5rem;
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }
      .remix-panel {
        background: #14141a;
        color: #fff;
        border-radius: 1.125rem;
        padding: 1.375rem;
      }
      @keyframes remixPulse {
        0% {
          box-shadow: 0 0 0 0
            color-mix(in srgb, var(--accent, #16e098) 60%, transparent);
        }
        50% {
          box-shadow:
            0 0 0 6px
              color-mix(in srgb, var(--accent, #16e098) 45%, transparent),
            0 0 34px 6px
              color-mix(in srgb, var(--accent, #16e098) 60%, transparent);
        }
        100% {
          box-shadow: 0 0 0 0
            color-mix(in srgb, var(--accent, #16e098) 60%, transparent);
        }
      }
      .remix-panel.is-focused {
        animation: remixPulse 900ms ease-in-out 2;
      }
      .remix-eyebrow {
        font: 600 0.6875rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--accent, #16e098);
      }
      .remix-title {
        font: 700 2rem/1.05 var(--font-sans, 'IBM Plex Sans', sans-serif);
        margin: 0.875rem 0 0.375rem;
      }
      .remix-sub {
        margin: 0 0 1.125rem;
        font: 400 0.8125rem/1.5 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: #b7b4ab;
      }
      .remix-secondary {
        width: 100%;
        margin-top: 0.625rem;
        padding: 0.75rem;
        background: transparent;
        color: #fff;
        border: 1px solid #3a3a44;
        border-radius: 0.75rem;
        cursor: pointer;
        font: 600 0.8125rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
      }
      .remix-secondary:hover {
        background: rgba(255, 255, 255, 0.05);
      }

      .info-card {
        background: var(--card, #fff);
        border-radius: 1rem;
        border: 1px solid var(--border, #eae5da);
        padding: 0.25rem 1.25rem;
      }
      .info-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0.8125rem 0;
        border-bottom: 1px solid var(--border, #f0ece3);
      }
      .info-row:last-child {
        border-bottom: none;
      }
      .info-label {
        font: 500 0.6875rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--muted-foreground, #8a8578);
      }
      .info-value {
        font: 600 0.8125rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
      }

      .tags-card {
        background: var(--card, #fff);
        border-radius: 1rem;
        border: 1px solid var(--border, #eae5da);
        padding: 1.125rem 1.25rem;
      }
      .tags-title {
        font: 600 0.6875rem/1 var(--font-mono, 'IBM Plex Mono', monospace);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--muted-foreground, #8a8578);
        margin-bottom: 0.75rem;
      }
      .tags-list {
        display: flex;
        flex-wrap: wrap;
        gap: 0.4375rem;
      }
      .tag {
        font: 500 0.6875rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        padding: 0.375rem 0.6875rem;
        background: var(--secondary, #f3f0e8);
        border-radius: 999px;
        color: var(--foreground, #46433c);
      }

      @container listing-detail (max-width: 56rem) {
        .main {
          grid-template-columns: 1fr;
        }
        .right {
          position: static;
        }
      }
      @container listing-detail (max-width: 34rem) {
        .listing-detail {
          padding: 1.5rem 1rem 3rem;
        }
        .title {
          font-size: 2rem;
        }
        .include-cards,
        .examples-grid {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

export class Listing extends CardDef {
  static displayName = 'Listing';
  static headerColor = '#6638ff';
  static isListingDef = true;
  static prefersWideFormat = true;

  @field name = contains(StringField);
  @field summary = contains(MarkdownField);
  @field specs = linksToMany(() => Spec, {
    searchable: [
      'linkedExamples',
      'linkedExamples.authors.cardInfo.theme',
      'linkedExamples.cardInfo.theme',
      'linkedExamples.categories',
      'linkedExamples.featured.authors.cardInfo.theme',
      'linkedExamples.featured.categories',
      'linkedExamples.games',
      'linkedExamples.lead.authors.cardInfo.theme',
      'linkedExamples.lead.categories',
    ],
  });
  @field publisher = linksTo(() => Publisher);
  @field categories = linksToMany(() => Category, { searchable: 'sphere' });
  @field tags = linksToMany(() => Tag, { searchable: true });
  @field license = linksTo(() => License, { searchable: true });
  @field images = linksToMany(ImageDef, { searchable: true });
  @field examples = linksToMany(() => CardDef);
  @field skills = linksToMany(() => Skill);

  @field cardTitle = contains(StringField, {
    computeVia(this: Listing) {
      return this.name;
    },
  });

  @field cardThumbnailURL = contains(StringField, {
    computeVia(this: Listing) {
      return (
        this.cardInfo?.cardThumbnail?.url ?? this.cardInfo?.cardThumbnailURL
      );
    },
  });

  protected getGenerateExampleMenuItem(
    params: GetMenuItemParams,
  ): MenuItemOptions | undefined {
    if (!params.commandContext || !params.canEdit) {
      return;
    }
    const firstExample =
      Array.isArray(this.examples) && this.examples.length
        ? (this.examples[0] as CardDef | undefined)
        : undefined;
    if (!firstExample) {
      return undefined;
    }
    return {
      label: 'Generate Example with AI',
      action: async () => {
        const command = new ListingGenerateExampleCommand(
          params.commandContext,
        );
        try {
          await command.execute({
            listing: this,
            referenceExample: firstExample,
          });
        } catch (error) {
          console.warn('Failed to generate listing example', { error });
        }
      },
      icon: Wand,
      id: 'generate-listing-example',
    };
  }

  private getUpdateSpecsMenuItem(
    params: GetMenuItemParams,
  ): MenuItemOptions | undefined {
    if (!params.commandContext || !params.canEdit) {
      return;
    }
    const targetRealm = this[realmURL]?.href;
    if (!targetRealm) {
      return;
    }

    return {
      label: 'Update Specs',
      id: 'update-listing-specs',
      icon: Refresh,
      action: () =>
        new ListingUpdateSpecsCommand(params.commandContext).execute({
          listing: this,
        }),
    };
  }

  [getMenuItems](params: GetMenuItemParams): MenuItemOptions[] {
    let menuItems = super
      [getMenuItems](params)
      .filter((item) => item.label?.toLowerCase() !== 'create listing');
    const generateExample = this.getGenerateExampleMenuItem(params);
    if (generateExample) {
      menuItems.push(generateExample);
    }
    const updateSpecs = this.getUpdateSpecsMenuItem(params);
    if (updateSpecs) {
      menuItems.push(updateSpecs);
    }
    const createPRMenuItem = this.getCreatePRMenuItem(params);
    if (createPRMenuItem) {
      menuItems.push(createPRMenuItem);
    }
    return menuItems;
  }

  private getCreatePRMenuItem(
    params: GetMenuItemParams,
  ): MenuItemOptions | undefined {
    if (!params.commandContext || !params.canEdit) {
      return;
    }
    if (!params.canEdit) {
      return;
    }
    if (!this[realmURL]?.href) {
      return;
    }

    return {
      label: 'Submit to Catalog',
      action: async () => {
        await new CreateAndOpenSubmissionWorkflowCardCommand(
          params.commandContext,
        ).execute({
          listingId: this.id,
          realm: this[realmURL]!.href,
          listingName: this.name,
        });
      },
      icon: Package,
    };
  }

  static isolated = EmbeddedTemplate;
  static embedded = EmbeddedTemplate;
  static fitted = ListingFittedTemplate;
}

export class AppListing extends Listing {
  static displayName = 'AppListing';
}

export class CardListing extends Listing {
  static displayName = 'CardListing';
  @field skills = linksToMany(() => Skill, { searchable: true });
}

export class FieldListing extends Listing {
  static displayName = 'FieldListing';
}

export class SkillListing extends Listing {
  static displayName = 'SkillListing';
}

export class ThemeListing extends Listing {
  static displayName = 'ThemeListing';
}

export class ComponentListing extends Listing {
  static displayName = 'ComponentListing';
}

function specBreakdown(specs: Spec[]): Record<string, Spec[]> {
  return specs.reduce(
    (groupedSpecs, spec) => {
      if (!spec || !instanceOf(spec, Spec)) {
        // During prerender linksToMany may still contain not-loaded placeholders;
        // skip until the real Spec instance arrives.
        return groupedSpecs;
      }
      let key = spec.specType ?? 'unknown';
      if (!groupedSpecs[key]) {
        groupedSpecs[key] = [];
      }
      groupedSpecs[key].push(spec);
      return groupedSpecs;
    },
    {} as Record<string, Spec[]>,
  );
}
