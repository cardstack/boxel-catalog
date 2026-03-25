/* 
  Adventure V4 - UI-focused refresh
  - Lighter header (scenario title primary)
  - Turn Bar (Turn N • time • scenario tag)
  - Compact action bar: Open Chat (primary), Generate Image (secondary), Reset (ghost)
  - Latest-only story panel (image-first, zoom affordance placeholder)
  - Mobile-first spacing and type
  - Keeps V3 logic (latest-only fields, per-instance chat room, ephemeral images, optional auto loop)
  - Legacy setupRoom + imageGenerationSkill preserved (not invoked)
*/

// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import { fn, get, hash } from '@ember/helper';
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
} from 'https://cardstack.com/base/card-api'; // ¹ Core imports
import StringField from 'https://cardstack.com/base/string';

import MarkdownField from 'https://cardstack.com/base/markdown';
import DatetimeField from 'https://cardstack.com/base/datetime';
import BooleanField from 'https://cardstack.com/base/boolean';
import NumberField from 'https://cardstack.com/base/number';
import { Button } from '@cardstack/boxel-ui/components';
import {
  formatDateTime,
  eq,
  gt,
  or,
  not,
  pick,
} from '@cardstack/boxel-ui/helpers';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { restartableTask, timeout } from 'ember-concurrency';
import BookOpenIcon from '@cardstack/boxel-icons/book-open';
import UseAiAssistantCommand from '@cardstack/boxel-host/commands/ai-assistant';
import SetActiveLLMCommand from '@cardstack/boxel-host/commands/set-active-llm';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import PatchFieldsCommand from '@cardstack/boxel-host/commands/patch-fields';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';

import { AdventureScenario } from './adventure-scenario'; // ¹ᵇ Linked Scenarios

// Optional compatibility FieldDefs (not used for display; kept for schema continuity)

export class AdventureScenarioV4 extends FieldDef {
  static displayName = 'Adventure Scenario V4';
  @field key = contains(StringField);
  @field cardTitle = contains(StringField);
  @field cardDescription = contains(StringField);
}

export class CreateYourOwnAdventureV4 extends CardDef {
  static displayName = 'Create Your Own Adventure V4';
  static icon = BookOpenIcon;
  static prefersWideFormat = true;

  // Identity and state
  @field adventureTitle = contains(StringField);
  @field selectedScenario = contains(AdventureScenarioV4); // embedded (compat)

  // Linked scenarios + one-shot editor
  @field linkedScenarios = linksToMany(AdventureScenario); // pick from real cards
  @field oneShotTitle = contains(StringField);
  @field oneShotDescription = contains(StringField);
  @field oneShotTags = containsMany(StringField);
  @field oneShotImageStyles = containsMany(StringField);

  @field gameStatus = contains(StringField); // 'setup' | 'playing' | 'completed'
  @field currentTurn = contains(NumberField);
  @field totalTurns = contains(NumberField);
  @field startedAt = contains(DatetimeField);
  @field completedAt = contains(DatetimeField);
  @field chatRoomId = contains(StringField);

  // Legacy (kept, not used by default)

  // Latest-only model
  @field lastTurnNumber = contains(NumberField);
  @field lastNarration = contains(MarkdownField);
  @field lastPlayerChoice = contains(StringField);
  @field lastTimestamp = contains(DatetimeField);
  @field lastIsPlayerTurn = contains(BooleanField);
  @field lastImagePrompt = contains(StringField);
  @field autoGenerateImages = contains(BooleanField);

  // Title
  @field cardTitle = contains(StringField, {
    computeVia: function (this: CreateYourOwnAdventureV4) {
      try {
        if (this.adventureTitle) return this.adventureTitle;
        if (this.selectedScenario?.title)
          return `Adventure V4: ${this.selectedScenario.title}`;
        return 'Create Your Own Adventure V4';
      } catch (e) {
        console.error('Adventure V4: Error computing title', e);
        return 'Adventure Game V4';
      }
    },
  });

  static isolated = class Isolated extends Component<
    typeof CreateYourOwnAdventureV4
  > {
    @tracked isProcessing = false;
    @tracked roomId: string | null = null;
    @tracked selectedScenarioKey: string | null = null;
    @tracked pendingChoice: string = '';
    @tracked currentImageData: string | null = null; // ephemeral render-only
    @tracked lastImageRenderedForTurn: number | null = null;
    @tracked isImageLoading: boolean = false; // image skeleton state
    @tracked toastMessage: string | null = null; // inline toast
    @tracked isOverlayVisible: boolean = true; // VN text overlay visibility
    @tracked selectedLinkedScenario: any | null = null; // chosen linked scenario
    // One‑shot chips editors (tags + image styles)
    @tracked newTag: string = '';
    @tracked newStyle: string = '';
    @tracked showLinkedChooser: boolean = false;

    setNewTag = (value: string) => {
      this.newTag = value ?? '';
    };
    setNewStyle = (value: string) => {
      this.newStyle = value ?? '';
    };

    addTag = (raw: string) => {
      const v = (raw || '').trim();
      if (!v) return;
      let arr = Array.isArray(this.args.model?.oneShotTags)
        ? this.args.model.oneShotTags
        : (this.args.model.oneShotTags = []);
      if (!arr.includes(v)) arr.push(v);
      this.newTag = '';
    };

    addStyle = (raw: string) => {
      const v = (raw || '').trim();
      if (!v) return;
      let arr = Array.isArray(this.args.model?.oneShotImageStyles)
        ? this.args.model.oneShotImageStyles
        : (this.args.model.oneShotImageStyles = []);
      if (!arr.includes(v)) arr.push(v);
      this.newStyle = '';
    };

    onTagKey = (e: KeyboardEvent) => {
      if (e.key === 'Enter' || e.key === ',') {
        e.preventDefault();
        this.addTag(this.newTag);
      }
    };

    onStyleKey = (e: KeyboardEvent) => {
      if (e.key === 'Enter' || e.key === ',') {
        e.preventDefault();
        this.addStyle(this.newStyle);
      }
    };

    removeTag = (idx: number) => {
      let arr = Array.isArray(this.args.model?.oneShotTags)
        ? this.args.model.oneShotTags
        : null;
      if (!arr) return;
      if (idx >= 0 && idx < arr.length) {
        arr.splice(idx, 1);
      }
    };

    removeStyle = (idx: number) => {
      let arr = Array.isArray(this.args.model?.oneShotImageStyles)
        ? this.args.model.oneShotImageStyles
        : null;
      if (!arr) return;
      if (idx >= 0 && idx < arr.length) {
        arr.splice(idx, 1);
      }
    };

    sanitizeOneShotArrays = () => {
      try {
        const m = this.args?.model;
        if (!m) return;
        if (Array.isArray(m.oneShotTags)) {
          m.oneShotTags = m.oneShotTags.filter(Boolean);
        }
        if (Array.isArray(m.oneShotImageStyles)) {
          m.oneShotImageStyles = m.oneShotImageStyles.filter(Boolean);
        }
      } catch {}
    };

    // Auto-dismiss toast after ~2.5s
    dismissToast = restartableTask(async () => {
      await timeout(2500);
      this.toastMessage = null;
    });

    showToast = (msg: string) => {
      this.toastMessage = msg;
      this.dismissToast.perform();
    };

    toggleOverlay = () => {
      this.isOverlayVisible = !this.isOverlayVisible;
    };
    showChooser = () => {
      this.showLinkedChooser = true;
    };
    hideChooser = () => {
      this.showLinkedChooser = false;
    };

    constructor(owner: unknown, args: any) {
      super(owner, args);
      this.autoImageLoop.perform();
      this.sanitizeOneShotArrays();
    }

    scenarios = [];

    // Auto-image on new turn (UI-side)
    autoImageLoop = restartableTask(async () => {
      while (true) {
        await timeout(800);
        try {
          const m = this.args?.model;
          if (!m) continue;
          if (m.gameStatus !== 'playing') continue;
          const t = m.lastTurnNumber;
          const p = m.lastImagePrompt;
          const auto = m.autoGenerateImages !== false;
          if (auto && t && p && this.lastImageRenderedForTurn !== t) {
            await this.generateSceneImage();
            this.lastImageRenderedForTurn = t;
          }
        } catch {
          /* swallow */
        }
      }
    });

    // Start adventure (same orchestration as V3; UI refreshed)
    @action
    async startAdventure() {
      const hasLinked = !!this.selectedLinkedScenario;
      const hasDefault = false;
      const hasOneShot =
        !!this.args.model?.oneShotDescription &&
        (this.args.model.oneShotDescription.trim?.().length || 0) > 0;

      if (!hasLinked && !hasDefault && !hasOneShot) {
        alert('Please pick a linked Scenario or craft a one‑shot first.');
        return;
      }

      this.isProcessing = true;
      try {
        let chosen: any | null = null;

        if (hasLinked) {
          chosen = this.selectedLinkedScenario;
        } else if (hasOneShot) {
          chosen = {
            key: 'one-shot',
            title: this.args.model.oneShotTitle || 'One‑Shot Scenario',
            description: this.args.model.oneShotDescription || '',
          };
        }

        if (!chosen) throw new Error('Scenario not found');

        // Derive kickoff guidance (linked preferred, else one‑shot)
        const kickoffTags = (
          hasLinked
            ? this.selectedLinkedScenario?.tags ?? []
            : this.args.model?.oneShotTags ?? []
        ).filter(Boolean);

        const kickoffStyles = (
          hasLinked
            ? this.selectedLinkedScenario?.imageStyles ?? []
            : this.args.model?.oneShotImageStyles ?? []
        ).filter(Boolean);

        const ctx = this.args.context?.commandContext;
        if (!ctx)
          throw new Error(
            'Command context does not exist. Please switch to Interact Mode',
          );

        // Patch selected scenario + initialize
        const patch = new PatchCardInstanceCommand(ctx);
        await patch.execute({
          cardId: this.args.model.id,
          patch: {
            attributes: {
              selectedScenario: {
                key: chosen.key,
                title: chosen.title,
                description: chosen.description,
              },
              // Persist guidance for ongoing turns (linked preferred, else one‑shot)
              oneShotTags: kickoffTags,
              oneShotImageStyles: kickoffStyles,

              gameStatus: 'playing',
              autoGenerateImages: true,
              currentTurn: 1,
              startedAt: new Date().toISOString(),
            },
          },
        });

        // Open assistant with GM skill (latest-only fields)
        const gmSkillId = new URL(
          './Skill/adventure-game-master',
          import.meta.url,
        ).href;
        const kickoffPrompt = `You are the Adventure Game Master. Use the attached CreateYourOwnAdventureV4 card.

Start Turn 1 using the selected scenario as seed. End with 2–4 choices and allow open-ended replies.

GUIDANCE FIELDS (read from oneShotTags/oneShotImageStyles on the card):
- oneShotTags: Use as narrative guidance (tone, setting, atmosphere, POV, theme)
- oneShotImageStyles: Include in lastImagePrompt with concrete scene nouns

PATCH ONLY latest fields via patch-fields (no arrays):
- lastTurnNumber = 1
- lastNarration = your Markdown story (shaped by non-visual tags)
- lastIsPlayerTurn = false
- lastTimestamp = new ISO string
- lastImagePrompt = short, concrete prompt (include imageStyles + visual tags; ≤120 chars)
- currentTurn = 1
- totalTurns = max(totalTurns, 1)

Do NOT call image APIs; UI handles rendering from lastImagePrompt.`;

        const use = new UseAiAssistantCommand(ctx);
        const opts: any = {
          openRoom: true,
          attachedCards: [this.args.model as CardDef],
          prompt: kickoffPrompt,
          llmModel: 'anthropic/claude-sonnet-4',
          llmMode: 'act',
          skillCardIds: [gmSkillId],
        };
        if (this.args.model?.chatRoomId) {
          opts.roomId = this.args.model.chatRoomId;
        } else {
          opts.roomId = 'new';
          opts.roomName = `Adventure V4: ${chosen.title}`;
        }
        const result = await use.execute(opts);
        this.roomId = result.roomId;

        // Persist room id
        await patch.execute({
          cardId: this.args.model.id,
          patch: { attributes: { chatRoomId: this.roomId } },
        });

        // Ensure agentic mode
        const set = new SetActiveLLMCommand(ctx);
        await set.execute({ roomId: this.roomId, mode: 'act' });

        // Gentle toast
        alert('🎉 Adventure started! Open the chat to continue.');
      } catch (e: any) {
        console.error('Adventure V4 start error:', e);
        alert(`Failed to start: ${e?.message || String(e)}`);
        try {
          const ctx = this.args.context?.commandContext;
          const patch = new PatchCardInstanceCommand(ctx);
          await patch.execute({
            cardId: this.args.model.id,
            patch: { attributes: { gameStatus: 'setup' } },
          });
        } catch {}
      } finally {
        this.isProcessing = false;
      }
    }

    @action
    async resetAdventure() {
      if (
        !confirm(
          'Reset this adventure? Linked Scenarios remain linked; one‑shot fields stay as entered.',
        )
      )
        return;
      try {
        const ctx = this.args.context?.commandContext;
        const patch = new PatchCardInstanceCommand(ctx);
        await patch.execute({
          cardId: this.args.model.id,
          patch: {
            attributes: {
              gameStatus: 'setup',
              selectedScenario: null,
              currentTurn: 0,
              startedAt: null,
              completedAt: null,
              chatRoomId: null,
              lastTurnNumber: null,
              lastNarration: null,
              lastPlayerChoice: null,
              lastTimestamp: null,
              lastIsPlayerTurn: null,
              lastImagePrompt: null,
            },
          },
        });
        this.selectedScenarioKey = null;
        this.roomId = null;
        this.pendingChoice = '';
        this.currentImageData = null;
      } catch (e: any) {
        console.error('Reset error:', e);
        alert(`Failed to reset: ${e?.message || String(e)}`);
      }
    }

    @action
    selectScenario(key: string) {
      this.selectedScenarioKey = key;
      this.selectedLinkedScenario = null; // prefer explicit default pick
    }

    @action
    selectLinked(s: any) {
      try {
        this.selectedLinkedScenario = s || null;
        this.selectedScenarioKey = s?.key || null;
        // Sync one-shot guidance to the linked Scenario so UI and kickoff align
        if (s) {
          const tags = Array.isArray(s.tags) ? [...s.tags] : [];
          const styles = Array.isArray(s.imageStyles) ? [...s.imageStyles] : [];
          this.args.model.oneShotTags = tags;
          this.args.model.oneShotImageStyles = styles;
          this.newTag = '';
          this.newStyle = '';
        }
      } catch {
        this.selectedLinkedScenario = null;
      }
    }

    @action
    async startWithLinked(s: any) {
      try {
        this.selectLinked(s);
        await this.startAdventure();
      } catch (e) {
        console.error('Failed to start with linked scenario', e);
      }
    }

    // Generate image (ephemeral render-only)
    @action
    async generateSceneImage() {
      if (this.args.model.gameStatus !== 'playing') return;
      const imagePrompt = this.args.model?.lastImagePrompt;
      if (!imagePrompt) return;

      this.isProcessing = true;
      this.isImageLoading = true;
      // keep currentImageData until new one arrives to prevent UI flicker

      try {
        const ctx = this.args.context?.commandContext;
        if (!ctx) throw new Error('Please switch to Interact Mode');

        const proxy = new SendRequestViaProxyCommand(ctx);
        const res = await proxy.execute({
          url: 'https://openrouter.ai/api/v1/chat/completions',
          method: 'POST',
          requestBody: JSON.stringify({
            model: 'google/gemini-2.5-flash-image-preview',
            messages: [{ role: 'user', content: imagePrompt }],
          }),
        });

        if (!res.response?.ok) {
          const text = res.response ? await res.response.text() : '';
          throw new Error(
            `${res.response?.status} ${res.response?.statusText} • ${text}`,
          );
        }

        const data = await res.response.json();
        const msg = data?.choices?.[0]?.message;
        const url = Array.isArray(msg?.images)
          ? msg.images
              .map((i: any) => i?.image_url?.url)
              .find((u: string) => u?.startsWith('data:image/'))
          : null;

        if (!url) throw new Error('No data:image/* URL found');
        this.currentImageData = url;
      } catch (e: any) {
        console.error('Image generation error:', e);
        this.showToast(`Image failed: ${e?.message || String(e)}`);
        this.currentImageData = null;
      } finally {
        this.isProcessing = false;
        this.isImageLoading = false;
      }
    }

    get gameInProgress() {
      return this.args.model.gameStatus === 'playing';
    }
    get gameNotStarted() {
      return (
        !this.args.model.gameStatus || this.args.model.gameStatus === 'setup'
      );
    }

    <template>
      <div class='stage'>
        <article class='mat'>

          {{! header is removed – story becomes the very first block }}

          <!-- Scenario selection -->
          {{#if this.gameNotStarted}}
            <section class='select'>
              <h2 class='section-title'>Set Up Your Adventure</h2>
              <p class='section-help'>Link a Scenario card or craft a one‑shot
                below.</p>

              {{#if (gt @model.linkedScenarios.length 0)}}
                <h3
                  class='section-title'
                  style='font-weight:600;font-size:0.9rem;margin-top:0.25rem;'
                >Linked Scenarios</h3>
                <div class='grid'>
                  {{#each @model.linkedScenarios as |sc|}}
                    <div
                      class='card
                        {{if (eq this.selectedScenarioKey sc.key) "selected"}}'
                    >
                      <div class='card-title'>{{sc.title}}</div>
                      <div class='card-desc'>{{sc.description}}</div>
                      <div class='card-meta'>
                        {{#if (gt sc.tags.length 0)}}
                          <span class='meta-pill subtle'>{{get
                              sc.tags
                              0
                            }}</span>
                        {{/if}}
                      </div>
                      <div class='actions-center' style='margin-top:0.5rem;'>
                        <Button
                          class='btn secondary'
                          {{on 'click' (fn this.startWithLinked sc)}}
                        >
                          Use This Scenario
                        </Button>
                      </div>
                    </div>
                  {{/each}}
                </div>
              {{else}}
                <div class='placeholder' style='margin-bottom:0.75rem;'>
                  No scenarios linked yet. Click Add Adventure Scenario to link
                  one, or craft a one‑shot below.
                </div>

              {{/if}}

              <h3
                class='section-title'
                style='font-weight:600;font-size:0.9rem;margin-top:0.25rem;'
              >Add Linked Scenarios</h3>
              <p class='section-help'>Use the chooser to add Scenario cards.
                Linked scenarios appear above.</p>
              <div class='actions-center'>
                <Button class='btn secondary' {{on 'click' this.showChooser}}>
                  Add Adventure Scenario
                </Button>
              </div>
              {{#if this.showLinkedChooser}}
                <div class='chooser-panel' style='margin-top:0.5rem;'>
                  <@fields.linkedScenarios @format='edit' />
                  <div class='actions-center' style='margin-top:0.5rem;'>
                    <Button
                      class='btn ghost'
                      {{on 'click' this.hideChooser}}
                    >Close Chooser</Button>
                  </div>
                </div>
              {{/if}}
              <h3
                class='section-title'
                style='font-weight:600;font-size:0.9rem;margin-top:0.25rem;'
              >One‑Shot Scenario</h3>
              <div class='card' style='cursor:default;'>
                <div class='card-title'>Title</div>
                <@fields.oneShotTitle @format='edit' />
                <div
                  class='card-title'
                  style='margin-top:0.5rem;'
                >Description</div>
                <@fields.oneShotDescription @format='edit' />
                <div class='card-title' style='margin-top:0.5rem;'>Tags</div>
                <div class='chips'>
                  {{#if (gt (get @model.oneShotTags 'length') 0)}}
                    <div class='chip-row'>
                      {{#each @model.oneShotTags as |t idx|}}
                        <Button
                          class='chip'
                          {{on 'click' (fn this.removeTag idx)}}
                        >
                          {{t}}
                          <span aria-hidden='true'>×</span>
                        </Button>
                      {{/each}}
                    </div>
                  {{/if}}
                  <input
                    class='chip-input'
                    placeholder='Add tag… (comma or Enter)'
                    value={{this.newTag}}
                    {{on 'input' (pick 'target.value' this.setNewTag)}}
                    {{on 'keydown' this.onTagKey}}
                  />
                </div>

                <div class='card-title' style='margin-top:0.5rem;'>Image Styles</div>
                <div class='chips'>
                  {{#if (gt (get @model.oneShotImageStyles 'length') 0)}}
                    <div class='chip-row'>
                      {{#each @model.oneShotImageStyles as |s idx|}}
                        <Button
                          class='chip'
                          {{on 'click' (fn this.removeStyle idx)}}
                        >
                          {{s}}
                          <span aria-hidden='true'>×</span>
                        </Button>
                      {{/each}}
                    </div>
                  {{/if}}
                  <input
                    class='chip-input'
                    placeholder='Add style… (comma or Enter)'
                    value={{this.newStyle}}
                    {{on 'input' (pick 'target.value' this.setNewStyle)}}
                    {{on 'keydown' this.onStyleKey}}
                  />
                </div>
                <div class='actions-center' style='margin-top:0.75rem;'>
                  <Button
                    class='btn primary'
                    @disabled={{this.isProcessing}}
                    {{on 'click' this.startAdventure}}
                  >
                    {{if this.isProcessing 'Starting…' 'Begin with One‑Shot'}}
                  </Button>
                </div>
              </div>
            </section>
          {{/if}}

          <!-- Active story -->
          {{#if this.gameInProgress}}
            <section class='story {{if this.currentImageData "has-image"}}'>

              <!-- Turn Bar -->
              <div class='turnbar'>
                <div class='turn-left'>
                  <span class='turn-dot'></span>
                  <span class='turn-label'>Turn {{@model.currentTurn}}</span>
                  {{#if @model.lastTimestamp}}
                    <span class='sep'>•</span>
                    <time class='turn-time'>{{formatDateTime
                        @model.lastTimestamp
                        size='tiny'
                      }}</time>
                  {{/if}}
                </div>
                <div class='turn-right'>

                  {{#if @model.totalTurns}}
                    <span class='mini-pill subtle'>Turns:
                      {{@model.totalTurns}}</span>
                  {{/if}}
                </div>
              </div>

              <!-- Compact Action Bar -->
              <div class='actionbar'>
                {{#if (or this.roomId @model.chatRoomId)}}
                  <Button
                    class='btn primary'
                    {{on
                      'click'
                      (fn
                        this.args.context.actions.openAiAssistantRoom
                        (or this.roomId @model.chatRoomId)
                      )
                    }}
                  >
                    Open AI Chat
                  </Button>
                {{else}}
                  <Button class='btn primary' @disabled={{true}}>Open Chat</Button>
                {{/if}}

                <div class='action-right'>
                  <Button
                    class='btn secondary'
                    @disabled={{or
                      this.isProcessing
                      (not @model.lastImagePrompt)
                    }}
                    {{on 'click' this.generateSceneImage}}
                  >
                    {{if this.isProcessing 'Generating…' 'Generate Image'}}
                  </Button>
                  {{#if (not @model.lastImagePrompt)}}
                    <div class='micro-help'>Waiting for the GM's image prompt…</div>
                  {{/if}}

                  <!-- Immersive toggle removed; VN overlay controlled on image -->

                  <Button
                    class='btn ghost'
                    {{on 'click' this.resetAdventure}}
                  >Reset</Button>
                </div>
              </div>

              {{#if this.toastMessage}}
                <div class='toast' role='status'>{{this.toastMessage}}</div>
              {{/if}}

              <!-- Image-first story panel -->
              <div class='story-panel'>
                {{#if this.isImageLoading}}
                  <div class='image-skeleton'></div>
                {{else if this.currentImageData}}
                  <div class='image-wrap'>
                    <img src={{this.currentImageData}} alt='Scene image' />
                    {{#if this.isOverlayVisible}}
                      {{#if @model.lastNarration}}
                        <div class='overlay'>
                          <div class='overlay-box'>
                            <@fields.lastNarration />
                          </div>
                        </div>
                      {{/if}}
                    {{/if}}

                    <!-- Bottom over-image control ribbon -->
                    <div class='overlay-controls'>
                      <div class='oc-left'>
                        <span class='oc-turn'>Turn {{@model.currentTurn}}</span>
                        {{#if @model.lastTimestamp}}
                          <span class='oc-sep'>•</span>
                          <time class='oc-time'>{{formatDateTime
                              @model.lastTimestamp
                              size='tiny'
                            }}</time>
                        {{/if}}

                      </div>

                      <div class='oc-right'>
                        {{#if (or this.roomId @model.chatRoomId)}}
                          <Button
                            class='btn primary'
                            {{on
                              'click'
                              (fn
                                this.args.context.actions.openAiAssistantRoom
                                (or this.roomId @model.chatRoomId)
                              )
                            }}
                          >
                            Open AI Chat
                          </Button>
                        {{else}}
                          <Button class='btn primary' @disabled={{true}}>Open
                            Chat</Button>
                        {{/if}}

                        <Button
                          class='btn secondary'
                          @disabled={{or
                            this.isProcessing
                            (not @model.lastImagePrompt)
                          }}
                          {{on 'click' this.generateSceneImage}}
                        >
                          {{if
                            this.isProcessing
                            'Generating…'
                            'Generate Image'
                          }}
                        </Button>

                        {{#if (not @model.lastImagePrompt)}}
                          <div class='micro-help'>Waiting for prompt from GM…</div>
                        {{/if}}

                        <Button
                          class='btn ghost'
                          {{on 'click' this.resetAdventure}}
                        >Reset</Button>
                      </div>
                    </div>

                    <Button
                      class='overlay-toggle'
                      {{on 'click' this.toggleOverlay}}
                    >
                      {{if this.isOverlayVisible 'Hide Text' 'Show Text'}}
                    </Button>
                  </div>
                {{/if}}

                {{#if @model.lastNarration}}
                  {{#if this.currentImageData}}
                    {{#if this.isOverlayVisible}}
                      {{! narration shown in overlay when visible }}
                    {{else}}
                      <div class='narration'>
                        <@fields.lastNarration />
                      </div>
                    {{/if}}
                  {{else}}
                    <div class='narration'>
                      <@fields.lastNarration />
                    </div>
                  {{/if}}
                {{else if this.isImageLoading}}
                  <div class='text-skeleton'>
                    <div class='line w-80'></div>
                    <div class='line w-95'></div>
                    <div class='line w-70'></div>
                  </div>
                {{else}}
                  <div class='placeholder'>
                    The story will appear here after the GM posts Turn
                    {{@model.currentTurn}}…
                  </div>
                {{/if}}
              </div>

              <!-- Gameplay footer header moved to bottom -->
              <footer class='header bottom'>
                <div class='header-top'>
                  <h1 class='title'>
                    {{if
                      @model.selectedScenario.title
                      @model.selectedScenario.title
                      'Create Your Own Adventure'
                    }}
                  </h1>

                </div>
                {{#if @model.selectedScenario.description}}
                  <p
                    class='subtitle'
                  >{{@model.selectedScenario.description}}</p>
                {{/if}}
              </footer>

            </section>
          {{/if}}

          <!-- Completed -->
          {{#if (eq @model.gameStatus 'completed')}}
            <section class='complete'>
              <h2 class='section-title'>Adventure Complete</h2>
              <p class='section-help'>Thanks for playing. You can still open the
                chat or start again.</p>
              <div class='actionbar'>
                {{#if (or this.roomId @model.chatRoomId)}}
                  <Button
                    class='btn primary'
                    {{on
                      'click'
                      (fn
                        this.args.context.actions.openAiAssistantRoom
                        (or this.roomId @model.chatRoomId)
                      )
                    }}
                  >
                    Open Chat
                  </Button>
                {{/if}}
                <Button
                  class='btn ghost'
                  {{on 'click' this.resetAdventure}}
                >Start Over</Button>
              </div>
            </section>
          {{/if}}

        </article>
      </div>

      <style scoped>
        /* Shell */
        .stage {
          width: 100%;
          height: 100%;
          display: flex;
          justify-content: center;
          background: linear-gradient(135deg, #eef2ff 0%, #f8fafc 100%);
          padding: 0.75rem;
        }
        .mat {
          max-width: 52rem;
          width: 100%;
          background: white;
          border-radius: 0.75rem;
          box-shadow: 0 10px 24px rgba(15, 23, 42, 0.06);
          overflow-y: auto;
          max-height: 100%;
        }

        /* Header */
        .header {
          padding: 1.25rem 1.25rem 0.75rem 1.25rem;
          border-bottom: 1px solid #e5e7eb;
          background: linear-gradient(
            180deg,
            rgba(99, 102, 241, 0.06),
            transparent
          );
        }
        .header-top {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          flex-wrap: wrap;
        }
        .title {
          margin: 0;
          font-size: 1.25rem;
          font-weight: 800;
          letter-spacing: -0.01em;
          color: #111827;
        }
        .scenario-chip {
          border: 1px solid #e5e7eb;
          color: #374151;
          background: #fff;
          border-radius: 999px;
          padding: 0.125rem 0.5rem;
          font-size: 0.75rem;
          font-weight: 600;
        }
        .subtitle {
          margin: 0.25rem 0 0;
          color: #4b5563;
          font-size: 0.9rem;
          line-height: 1.35;
        }
        .header.collapsed {
          padding: 0.5rem 1.25rem;
          border-bottom-color: #f3f4f6;
        }
        .header.collapsed .subtitle {
          display: none;
        }

        /* Footer-style header when playing */
        .header.bottom {
          margin-top: 0.75rem;
          padding: 0.75rem 1.25rem 1rem;
          border-top: 1px solid #e5e7eb;
          border-bottom: 0;
          background: linear-gradient(
            0deg,
            rgba(99, 102, 241, 0.06),
            transparent
          );
        }
        .header.bottom .subtitle {
          margin-top: 0.25rem;
        }

        /* Section headers */
        .section-title {
          margin: 0 0 0.25rem;
          font-size: 1rem;
          font-weight: 700;
          color: #111827;
        }
        .section-help {
          margin: 0 0 1rem;
          font-size: 0.85rem;
          color: #6b7280;
        }

        /* Scenario select */
        .select {
          padding: 1rem 1.25rem 1.25rem;
        }
        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
          gap: 0.75rem;
          margin-bottom: 1rem;
        }
        .card {
          text-align: left;
          width: 100%;
          border: 1px solid #e5e7eb;
          background: #fff;
          border-radius: 0.5rem;
          padding: 0.75rem;
          transition:
            transform 120ms ease,
            box-shadow 120ms ease,
            border-color 120ms;
          cursor: pointer;
        }
        .card:hover {
          transform: translateY(-1px);
          box-shadow: 0 6px 14px rgba(15, 23, 42, 0.06);
          border-color: #cbd5e1;
        }
        .card.selected {
          border-color: #6366f1;
          box-shadow: 0 6px 16px rgba(99, 102, 241, 0.2);
        }
        .card-title {
          font-weight: 700;
          color: #0f172a;
          margin-bottom: 0.25rem;
        }
        .card-desc {
          color: #475569;
          font-size: 0.875rem;
          line-height: 1.35;
          margin-bottom: 0.5rem;
        }
        .card-meta {
          display: flex;
          gap: 0.375rem;
          flex-wrap: wrap;
        }
        .meta-pill {
          border: 1px solid #e5e7eb;
          border-radius: 999px;
          padding: 0.125rem 0.5rem;
          font-size: 0.75rem;
          font-weight: 600;
          color: #334155;
          background: #fff;
        }
        .meta-pill.subtle {
          color: #64748b;
        }

        .actions-center {
          display: flex;
          justify-content: center;
          margin-top: 0.25rem;
        }

        /* Story */
        .story {
          padding: 0.9rem 1.25rem 1.25rem;
          display: grid;
          gap: 0.75rem;
        }

        /* Turn Bar */
        .turnbar {
          display: flex;
          justify-content: space-between;
          align-items: center;
          border: 1px solid #e5e7eb;
          background: #f8fafc;
          border-radius: 0.5rem;
          padding: 0.375rem 0.5rem; /* tighter */
          gap: 0.375rem; /* tighter */
        }
        .turn-left {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          color: #0f172a;
          font-weight: 700;
        }
        .turn-dot {
          width: 0.5rem;
          height: 0.5rem;
          border-radius: 50%;
          background: #10b981;
          box-shadow: 0 0 6px rgba(16, 185, 129, 0.5);
        }
        .turn-label {
          font-size: 0.875rem;
        }
        .sep {
          color: #64748b;
        }
        .turn-time {
          font-size: 0.75rem;
          color: #475569;
        }
        .turn-right {
          display: inline-flex;
          gap: 0.375rem;
          align-items: center;
        }
        .mini-pill {
          /* outlined, compact badge for the Turn Bar */
          border: 1px solid #e5e7eb;
          border-radius: 999px;
          padding: 0.125rem 0.5rem;
          font-size: 0.75rem;
          font-weight: 600;
          color: #334155;
          background: #fff;
        }
        .mini-pill.subtle {
          color: #64748b;
          border-color: #e5e7eb;
          background: #fff;
        }

        /* Action Bar (sticky under the Turn Bar) */
        .actionbar {
          position: sticky; /* stays visible as the story scrolls */
          top: 0; /* pin to the very top of the scroller */
          z-index: 1;
          display: flex;
          gap: 0.375rem; /* tighter */
          flex-wrap: wrap;
          align-items: center;
          background: rgba(255, 255, 255, 0.75);
          backdrop-filter: blur(6px);
          border: 1px solid #e5e7eb;
          border-radius: 0.5rem;
          padding: 0.375rem; /* tighter */
        }

        /* Buttons (scoped styles for Boxel Button with class hooks) */
        .btn {
          font-size: 0.875rem;
          line-height: 1;
          padding: 0.5rem 0.75rem;
          border-radius: 0.375rem;
          font-weight: 600;
          border: 1px solid transparent;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          transition:
            transform 120ms ease,
            box-shadow 120ms ease,
            background 120ms ease,
            border-color 120ms ease;
        }
        .btn[disabled] {
          opacity: 0.6;
          cursor: not-allowed;
          transform: none;
          box-shadow: none;
        }
        .btn.primary {
          background: linear-gradient(135deg, #2563eb, #1d4ed8);
          color: #fff;
        }
        .btn.primary:hover:not([disabled]) {
          transform: translateY(-1px);
          box-shadow: 0 4px 12px rgba(37, 99, 235, 0.35);
        }
        .btn.secondary {
          background: #fff;
          color: #1f2937;
          border-color: #cbd5e1;
        }
        .btn.secondary:hover:not([disabled]) {
          transform: translateY(-1px);
          box-shadow: 0 4px 10px rgba(15, 23, 42, 0.06);
          border-color: #94a3b8;
        }
        .btn.ghost {
          background: transparent;
          color: #374151;
          border-color: #e5e7eb;
        }
        .btn.ghost:hover:not([disabled]) {
          background: #f8fafc;
          transform: translateY(-1px);
        }

        /* Hide the top bars only when an image is present; overlay controls will be used */
        .story.has-image .turnbar,
        .story.has-image .actionbar {
          display: none;
        }

        /* Story Panel — image-first, consistent ratio */
        .story-panel {
          display: grid;
          gap: 0.75rem;
        }

        /* Skeletons */
        .image-skeleton {
          border: 1px solid #e5e7eb;
          border-radius: 0.5rem;
          background: linear-gradient(
            90deg,
            #f3f4f6 25%,
            #e5e7eb 37%,
            #f3f4f6 63%
          );
          background-size: 400% 100%;
          animation: shimmer 1.2s infinite;
          aspect-ratio: 16 / 9;
        }
        .text-skeleton .line {
          height: 0.75rem;
          margin-bottom: 0.5rem;
          border-radius: 0.25rem;
          background: linear-gradient(
            90deg,
            #f3f4f6 25%,
            #e5e7eb 37%,
            #f3f4f6 63%
          );
          background-size: 400% 100%;
          animation: shimmer 1.2s infinite;
        }
        .text-skeleton .line.w-80 {
          width: 80%;
        }
        .text-skeleton .line.w-95 {
          width: 95%;
        }
        .text-skeleton .line.w-70 {
          width: 70%;
        }

        @keyframes shimmer {
          0% {
            background-position: 100% 0;
          }
          100% {
            background-position: 0 0;
          }
        }

        /* Inline toast */
        .toast {
          margin-top: 0.5rem;
          padding: 0.5rem 0.75rem;
          border: 1px solid #fecaca;
          background: #fef2f2;
          color: #991b1b;
          border-radius: 0.5rem;
          font-size: 0.8125rem;
        }

        .action-right {
          display: inline-flex;
          gap: 0.5rem;
          align-items: center;
          flex-wrap: wrap;
        }

        .micro-help {
          font-size: 0.75rem;
          color: #6b7280;
        }
        .image-wrap {
          position: relative;
          border: 1px solid #e5e7eb;
          border-radius: 0.5rem;
          overflow: hidden;
          background: #f8fafc;
        }
        .image-wrap img {
          width: 100%;
          height: auto; /* intrinsic height – no side letterboxing */
          display: block;
        }
        .overlay-toggle {
          position: absolute;
          top: 0.5rem;
          right: 0.5rem;
          z-index: 3;
          font-size: 0.75rem;
          padding: 0.25rem 0.5rem;
          border-radius: 0.375rem;
          border: 1px solid #e5e7eb;
          background: rgba(255, 255, 255, 0.85);
          color: #111827;
          backdrop-filter: blur(4px);
        }

        /* Bottom overlay controls (minimal background to keep image clear) */
        .image-wrap .overlay-controls {
          position: absolute;
          left: 0;
          right: 0;
          bottom: 0.5rem;
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 0.5rem;
          padding: 0 0.5rem;
          pointer-events: none; /* container transparent */
          z-index: 2;
        }
        .image-wrap .overlay-controls .oc-left,
        .image-wrap .overlay-controls .oc-right {
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
          flex-wrap: wrap;
          pointer-events: auto; /* enable clicks inside */
        }
        .oc-turn {
          font-weight: 700;
          color: #fff;
          text-shadow: 0 1px 2px rgba(0, 0, 0, 0.6);
        }
        .oc-sep {
          color: #cbd5e1;
        }
        .oc-time {
          font-size: 0.75rem;
          color: #e5e7eb;
          text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
        }
        .oc-pill {
          border: 1px solid rgba(255, 255, 255, 0.55);
          color: #fff;
          border-radius: 999px;
          padding: 0.125rem 0.5rem;
          font-size: 0.75rem;
          font-weight: 600;
          background: rgba(17, 24, 39, 0.25);
          backdrop-filter: blur(2px);
        }
        .image-wrap .overlay {
          position: absolute;
          inset: 0;
          display: flex;
          align-items: flex-end;
          /* Remove global scrim; rely on the box background only for legibility */
          background: none;
          pointer-events: none;
        }
        .overlay-box {
          margin: 0.5rem;
          /* Lighter box so the image remains clear, with strong text contrast */
          background: rgba(17, 24, 39, 0.5);
          color: #fff;
          border-radius: 0.5rem;
          padding: 0.75rem;
          /* Reserve slightly more space for the control bar */
          margin-bottom: 3rem;
          /* Allow a bit more height; still scrolls when long */
          max-height: 60%;
          overflow: auto;
          -webkit-overflow-scrolling: touch;
          overscroll-behavior: contain;
          pointer-events: auto; /* allow scroll/clicks inside the overlay */
          scrollbar-width: thin;
          font-size: 0.875rem;
          line-height: 1.45;
        }
        .overlay-box p {
          margin: 0 0 0.5rem;
        }
        .overlay-box ul,
        .overlay-box ol {
          margin: 0.375rem 0 0.375rem 1rem;
          padding: 0;
        }
        .overlay-box li {
          margin-bottom: 0.25rem;
        }

        /* Narration readability + choice lists */
        .narration {
          color: #111827;
          font-size: 0.875rem; /* 14px */
          line-height: 1.5;
          max-width: 70ch; /* comfortable reading width */
        }
        .narration p {
          margin: 0 0 0.75rem;
        }
        .narration ul,
        .narration ol {
          margin: 0.5rem 0 0.5rem 1rem;
          padding: 0;
        }
        .narration li {
          margin-bottom: 0.25rem;
        }

        /* Placeholder / empty state */
        .placeholder {
          color: #6b7280;
          font-style: italic;
          text-align: center;
          padding: 1rem;
          border: 1px dashed #e5e7eb;
          border-radius: 0.5rem;
          background: #f9fafb;
        }

        /* Mobile refinements */
        @media (max-width: 768px) {
          .header {
            padding: 1rem 1rem 0.5rem;
          }
          .title {
            font-size: 1.125rem;
          }
          .subtitle {
            font-size: 0.85rem;
          }
          .select {
            padding: 0.75rem 1rem 1rem;
          }
          .story {
            padding: 0.75rem 1rem 1rem;
          }
          .actionbar {
            position: static;
            gap: 0.375rem;
          }
          .btn {
            font-size: 0.8125rem;
            padding: 0.4375rem 0.625rem;
          }
          .scenario-chip,
          .meta-pill,
          .mini-pill {
            padding: 0.1rem 0.45rem;
            font-size: 0.71875rem;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<
    typeof CreateYourOwnAdventureV4
  > {
    <template>
      <div class='embedded-card'>
        <div class='top'>
          <h3 class='name'>
            {{if @model.adventureTitle @model.adventureTitle 'Adventure'}}
          </h3>
          {{#if @model.selectedScenario.title}}
            <span class='pill'>{{@model.selectedScenario.title}}</span>
          {{/if}}
        </div>

        <div class='status'>
          {{#if (eq @model.gameStatus 'playing')}}
            <span class='tag active'>Playing • Turn
              {{@model.currentTurn}}</span>
          {{else if (eq @model.gameStatus 'completed')}}
            <span class='tag done'>Completed •
              {{@model.totalTurns}}
              turns</span>
          {{else}}
            <span class='tag ready'>Ready</span>
          {{/if}}
          {{#if @model.lastTimestamp}}
            <span class='when'>{{formatDateTime
                @model.lastTimestamp
                size='tiny'
              }}</span>
          {{/if}}
        </div>

        {{#if @model.selectedScenario.description}}
          <p class='preview'>{{@model.selectedScenario.description}}</p>
        {{/if}}
      </div>

      <style scoped>
        .embedded-card {
          padding: 0.75rem;
          border: 1px solid #e5e7eb;
          border-radius: 0.5rem;
          background: #fff;
        }
        .top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
        }
        .name {
          margin: 0;
          font-size: 0.95rem;
          font-weight: 700;
          color: #111827;
        }
        .pill {
          border: 1px solid #e5e7eb;
          border-radius: 999px;
          padding: 0.125rem 0.5rem;
          font-size: 0.75rem;
          color: #374151;
          background: #fff;
          white-space: nowrap;
        }
        .status {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          margin-top: 0.25rem;
          flex-wrap: wrap;
        }
        .tag {
          padding: 0.125rem 0.5rem;
          border-radius: 0.375rem;
          font-size: 0.75rem;
          font-weight: 600;
          border: 1px solid #e5e7eb;
          color: #374151;
          background: #fff;
        }
        .tag.active {
          border-color: #bbf7d0;
          color: #166534;
        }
        .tag.done {
          border-color: #ddd6fe;
          color: #5b21b6;
        }
        .tag.ready {
          border-color: #fde68a;
          color: #92400e;
        }
        .when {
          font-size: 0.75rem;
          color: #6b7280;
        }
        .preview {
          margin: 0.25rem 0 0;
          color: #4b5563;
          font-size: 0.8125rem;
          line-height: 1.35;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<
    typeof CreateYourOwnAdventureV4
  > {
    <template>
      <div class='fitted'>
        <!-- Badge -->
        <div class='badge'>
          <div class='dot'></div>
          <div class='label'>
            <div class='title'>{{if
                @model.selectedScenario.title
                @model.selectedScenario.title
                'Adventure'
              }}</div>
            <div class='sub'>
              {{#if (eq @model.gameStatus 'playing')}}Turn
                {{@model.currentTurn}}
              {{else if (eq @model.gameStatus 'completed')}}Done
              {{else}}Ready{{/if}}
            </div>
          </div>
        </div>

        <!-- Strip -->
        <div class='strip'>
          <div class='strip-main'>
            <div class='title'>{{if
                @model.adventureTitle
                @model.adventureTitle
                'Adventure'
              }}</div>
            {{#if @model.selectedScenario}}
              <div class='sub'>{{@model.selectedScenario.title}}</div>
            {{/if}}
          </div>
          <div class='strip-status'>
            {{#if (eq @model.gameStatus 'playing')}}T{{@model.currentTurn}}
            {{else if (eq @model.gameStatus 'completed')}}Done
            {{else}}Start{{/if}}
          </div>
        </div>

        <!-- Tile -->
        <div class='tile'>
          <div class='head'>
            <h4>{{if
                @model.adventureTitle
                @model.adventureTitle
                'Adventure'
              }}</h4>

          </div>
          {{#if @model.selectedScenario}}
            <div class='desc'>
              <strong>{{@model.selectedScenario.title}}</strong>
              <p>{{@model.selectedScenario.description}}</p>
            </div>
          {{/if}}
          <div class='foot'>
            {{#if (eq @model.gameStatus 'playing')}}
              <span>Turn {{@model.currentTurn}}</span>
              {{#if (gt @model.totalTurns 0)}}<span>•
                  {{@model.totalTurns}}
                  turns</span>{{/if}}
            {{else if (eq @model.gameStatus 'completed')}}
              <span>Completed • {{@model.totalTurns}} turns</span>
            {{else}}
              <span>Ready</span>
            {{/if}}
          </div>
        </div>

        <!-- Card -->
        <div class='card'>
          <div class='card-head'>
            <div class='main'>
              <h3>{{if
                  @model.adventureTitle
                  @model.adventureTitle
                  'Adventure'
                }}</h3>
              {{#if @model.selectedScenario}}{{/if}}
            </div>
            <div class='state'>
              {{#if (eq @model.gameStatus 'playing')}}
                <span class='state-pill active'>Turn
                  {{@model.currentTurn}}</span>
              {{else if (eq @model.gameStatus 'completed')}}
                <span class='state-pill done'>Completed</span>
              {{else}}
                <span class='state-pill ready'>Ready</span>
              {{/if}}
            </div>
          </div>
          {{#if @model.selectedScenario}}
            <div class='card-desc'>{{@model.selectedScenario.description}}</div>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .fitted {
          container-type: size;
          width: 100%;
          height: 100%;
        }

        /* Hide all; activate via container queries */
        .badge,
        .strip,
        .tile,
        .card {
          display: none;
          width: 100%;
          height: 100%;
          padding: clamp(0.1875rem, 2%, 0.625rem);
          box-sizing: border-box;
        }

        /* Activations */
        @container (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            align-items: center;
            gap: 0.5rem;
          }
        }
        @container (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.75rem;
          }
        }
        @container (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
          }
        }
        @container (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
          }
        }

        /* Badge */
        .dot {
          width: 0.5rem;
          height: 0.5rem;
          border-radius: 50%;
          background: #10b981;
        }
        .label .title {
          font-size: 0.875rem;
          font-weight: 700;
          color: #111827;
        }
        .label .sub {
          font-size: 0.75rem;
          color: #6b7280;
        }

        /* Strip */
        .strip-main {
          flex: 1;
          min-width: 0;
        }
        .strip .title {
          font-size: 0.875rem;
          font-weight: 600;
          color: #111827;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .strip .sub {
          font-size: 0.75rem;
          color: #6b7280;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .strip-status {
          font-size: 0.75rem;
          color: #374151;
        }

        /* Tile */
        .head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: 0.5rem;
          margin-bottom: 0.5rem;
        }
        .head h4 {
          margin: 0;
          font-size: 1rem;
          font-weight: 600;
          color: #1f2937;
        }
        .chip {
          background: #eef2ff;
          color: #4338ca;
          padding: 0.25rem 0.5rem;
          border-radius: 0.25rem;
          font-size: 0.75rem;
        }
        .desc {
          margin-bottom: 0.5rem;
        }
        .desc strong {
          display: block;
          color: #374151;
          font-size: 0.875rem;
          margin-bottom: 0.25rem;
        }
        .desc p {
          margin: 0;
          color: #6b7280;
          font-size: 0.8125rem;
          line-height: 1.3;
          display: -webkit-box;
          -webkit-line-clamp: 3;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .foot {
          margin-top: auto;
          font-size: 0.8125rem;
          color: #374151;
        }

        /* Card */
        .card-head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: 0.75rem;
        }
        .card-head h3 {
          margin: 0;
          font-size: 1.125rem;
          font-weight: 700;
          color: #111827;
        }
        .meta {
          display: flex;
          gap: 0.375rem;
          flex-wrap: wrap;
          margin-top: 0.25rem;
        }
        .state-pill {
          padding: 0.25rem 0.5rem;
          border-radius: 0.375rem;
          font-size: 0.75rem;
          font-weight: 600;
          border: 1px solid #e5e7eb;
          color: #374151;
          background: #fff;
        }
        .state-pill.active {
          border-color: #bbf7d0;
          color: #166534;
        }
        .state-pill.done {
          border-color: #ddd6fe;
          color: #5b21b6;
        }
        .state-pill.ready {
          border-color: #fde68a;
          color: #92400e;
        }
        .card-desc {
          color: #4b5563;
          font-size: 0.8125rem;
          line-height: 1.35;
        }
        /* Chips editor */
        .chips {
          display: grid;
          gap: 0.375rem;
        }
        .chip-row {
          display: flex;
          gap: 0.375rem;
          flex-wrap: wrap;
        }
        .chip {
          font-size: 0.75rem;
          padding: 0.25rem 0.5rem;
          border-radius: 999px;
          border: 1px solid #e5e7eb;
          background: #fff;
          color: #374151;
        }
        .chip-input {
          width: 100%;
          border: 1px solid #e5e7eb;
          border-radius: 0.375rem;
          padding: 0.5rem 0.625rem;
          font-size: 0.875rem;
        }
      </style>
    </template>
  };
}
