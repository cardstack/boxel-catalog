import { fn, get } from '@ember/helper';
import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
  realmURL,
  linksTo,
  FieldDef,
  StringField,
} from 'https://cardstack.com/base/card-api';
import MarkdownField from 'https://cardstack.com/base/markdown';
import DateTimeField from 'https://cardstack.com/base/datetime';
import BooleanField from 'https://cardstack.com/base/boolean';
import NumberField from 'https://cardstack.com/base/number';
import { Button } from '@cardstack/boxel-ui/components';
import { eq, gt, or, not, and } from '@cardstack/boxel-ui/helpers';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { restartableTask, timeout } from 'ember-concurrency';
import BookOpenIcon from '@cardstack/boxel-icons/book-open';
import CreateAiAssistantRoomCommand from '@cardstack/boxel-host/commands/create-ai-assistant-room';
import UseAiAssistantCommand from '@cardstack/boxel-host/commands/ai-assistant';
import SetActiveLLMCommand from '@cardstack/boxel-host/commands/set-active-llm';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';
import OpenAiAssistantRoomCommand from '@cardstack/boxel-host/commands/open-ai-assistant-room';
import UploadImageCommand from '@cardstack/catalog/commands/upload-image';

import ImageDef from 'https://cardstack.com/base/image-file-def';

class CloudflareImage extends ImageDef {
  static displayName = 'Cloudflare Image';
}

// Inline ChipsEditor - replaces missing ./components/chips-editor
interface ChipsEditorSignature {
  Args: {
    name: string;
    items: string[];
    onItemsUpdate: (this: void, newItems: string[]) => void;
    placeholder?: string;
  };
  Element: HTMLDivElement;
}

class ChipsEditor extends Component<ChipsEditorSignature> {
  @tracked inputValue = '';

  handleKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      this.addItem();
    }
  };

  addItem = () => {
    const v = this.inputValue.trim();
    if (!v) return;
    const current = Array.isArray(this.args.items) ? [...this.args.items] : [];
    if (!current.includes(v)) {
      this.args.onItemsUpdate([...current, v]);
    }
    this.inputValue = '';
  };

  removeItem = (item: string) => {
    const current = Array.isArray(this.args.items) ? this.args.items : [];
    this.args.onItemsUpdate(current.filter((i) => i !== item));
  };

  updateInput = (e: Event) => {
    this.inputValue = (e.target as HTMLInputElement).value;
  };

  <template>
    <div class='chips-editor'>
      <div class='chips-list'>
        {{#each @items as |item|}}
          <span class='chip-tag'>
            {{item}}
            <button
              type='button'
              class='chip-remove'
              {{on 'click' (fn this.removeItem item)}}
            >×</button>
          </span>
        {{/each}}
      </div>
      <input
        class='chips-input'
        type='text'
        value={{this.inputValue}}
        placeholder={{if @placeholder @placeholder 'Add item...'}}
        {{on 'input' this.updateInput}}
        {{on 'keydown' this.handleKeyDown}}
      />
    </div>
    <style scoped>
      .chips-editor {
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
      }
      .chips-list {
        display: flex;
        flex-wrap: wrap;
        gap: 0.375rem;
      }
      .chip-tag {
        display: inline-flex;
        align-items: center;
        gap: 0.25rem;
        padding: 0.25rem 0.5rem;
        border-radius: 999px;
        background: #ede9fe;
        color: #5b21b6;
        font-size: 0.8125rem;
        border: 1px solid #ddd6fe;
      }
      .chip-remove {
        background: none;
        border: none;
        cursor: pointer;
        color: #7c3aed;
        font-size: 0.875rem;
        line-height: 1;
        padding: 0;
        margin-left: 0.125rem;
      }
      .chips-input {
        padding: 0.375rem 0.5rem;
        border: 1px solid #e5e7eb;
        border-radius: 0.375rem;
        font-size: 0.875rem;
        width: 100%;
        box-sizing: border-box;
      }
    </style>
  </template>
}
import { AdventureScenario } from './adventure-scenario';
import { AdventureMod } from './adventure-mod';
import { MultipleChoice } from './multiple-choice';

class CustomAdventureField extends FieldDef {
  @field cardTitle = contains(StringField);
  @field cardDescription = contains(StringField);
  @field tags = containsMany(StringField);
  @field imageStyles = containsMany(StringField);
}

class AdventureIsolated extends Component<typeof Adventure> {
  @tracked isProcessing = false;
  @tracked roomId: string | null = null;
  @tracked selectedScenarioKey: string | null = null;
  @tracked pendingChoice: string = '';
  @tracked currentImageData: string | null = null;
  @tracked lastImageRenderedForTurn: number | null = null;
  @tracked isImageLoading: boolean = false;
  @tracked toastMessage: string | null = null;
  @tracked isOverlayVisible: boolean = true;
  @tracked selectedLinkedScenario: any | null = null;
  @tracked newTag: string = '';
  @tracked newStyle: string = '';
  @tracked showLinkedChooser: boolean = false;
  @tracked setupMode: 'quick' | 'custom' = 'quick';
  @tracked showResetMenu: boolean = false;
  @tracked expandedModId: string | null = null; // Track which mod panel is expanded

  exampleTags = ['fantasy', 'sci-fi', 'mystery', 'horror', 'comedy', 'drama'];
  exampleStyles = [
    'watercolor',
    'cinematic',
    'anime',
    'pixel art',
    'photorealistic',
    'sketch',
  ];

  get currentDisplayImageUrl(): string | null {
    try {
      if (this.currentImageData) {
        return this.currentImageData;
      }
      if (this.args.model?.lastCloudflareImage) {
        const uploadedUrl = this.args.model.lastCloudflareImage.url;
        if (uploadedUrl) {
          return uploadedUrl;
        }
      }
      return null;
    } catch (e) {
      console.error('Error getting display image URL:', e);
      return this.currentImageData;
    }
  }

  // === Mod helpers ===
  get activeMods() {
    return this.args.model?.mods?.filter((m) => m.isEnabled) ?? [];
  }

  get modStatusItems() {
    return this.activeMods.map((mod) => ({
      id: mod.id,
      icon: mod.statusIcon || '📦',
      summary: mod.statusSummary || mod.modName,
      name: mod.modName,
    }));
  }

  toggleModPanel = (modId: string) => {
    if (this.expandedModId === modId) {
      this.expandedModId = null;
    } else {
      this.expandedModId = modId;
    }
  };

  addTag = (raw: string) => {
    const v = (raw || '').trim();
    if (!v) return;
    if (!this.args.model?.customAdventure) return;
    let arr = Array.isArray(this.args.model.customAdventure.tags)
      ? this.args.model.customAdventure.tags
      : (this.args.model.customAdventure.tags = []);
    if (!arr.includes(v)) arr.push(v);
    this.newTag = '';
  };

  addStyle = (raw: string) => {
    const v = (raw || '').trim();
    if (!v) return;
    if (!this.args.model?.customAdventure) return;
    let arr = Array.isArray(this.args.model.customAdventure.imageStyles)
      ? this.args.model.customAdventure.imageStyles
      : (this.args.model.customAdventure.imageStyles = []);
    if (!arr.includes(v)) arr.push(v);
    this.newStyle = '';
  };

  sanitizeOneShotArrays = () => {
    try {
      const m = this.args?.model;
      if (!m?.customAdventure) return;
      if (Array.isArray(m.customAdventure.tags)) {
        m.customAdventure.tags = m.customAdventure.tags.filter(Boolean);
      }
      if (Array.isArray(m.customAdventure.imageStyles)) {
        m.customAdventure.imageStyles =
          m.customAdventure.imageStyles.filter(Boolean);
      }
    } catch {
      /* empty */
    }
  };

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

  setSetupMode = (mode: 'quick' | 'custom') => {
    this.setupMode = mode;
  };

  toggleResetMenu = () => {
    this.showResetMenu = !this.showResetMenu;
  };

  closeResetMenu = () => {
    this.showResetMenu = false;
  };

  constructor(owner: any, args: any) {
    super(owner, args);
    this.autoImageLoop.perform();
    this.sanitizeOneShotArrays();
  }

  scenarios = [];

  autoImageLoop = restartableTask(async () => {
    let running = true;
    while (running) {
      await timeout(800);
      try {
        const m = this.args?.model;
        if (!m) continue;
        if (m.gameStatus !== 'playing') continue;
        const t = m.lastTurnNumber;
        const p = m.lastImagePrompt;
        const auto = m.autoGenerateImages !== false;
        if (
          auto &&
          t &&
          p &&
          this.lastImageRenderedForTurn !== t &&
          !m.lastCloudflareImage
        ) {
          await this.generateSceneImage();
          this.lastImageRenderedForTurn = t;
        }
      } catch {
        /* swallow */
      }
    }
  });

  @action
  openAIAssistantRoom() {
    if (!this.args.context || !this.args.context.commandContext) {
      throw new Error('Missing command context for proxy request');
    }
    const roomId = this.roomId || this.args.model.chatRoomId;
    if (!roomId) return;
    const openAiAssistantRoomCommand = new OpenAiAssistantRoomCommand(
      this.args.context.commandContext,
    );
    openAiAssistantRoomCommand.execute({
      roomId,
    });
  }

  @action
  async startAdventure() {
    if (this.setupMode === 'custom') {
      this.selectedLinkedScenario = null;
    }

    const hasLinked = !!this.selectedLinkedScenario;
    const hasDefault = false;
    const hasCustom =
      !!this.args.model?.customAdventure?.cardDescription &&
      (this.args.model.customAdventure.cardDescription.trim?.().length || 0) >
        0;

    if (!hasLinked && !hasDefault && !hasCustom) {
      alert('Please pick a linked Scenario or craft a custom adventure first.');
      return;
    }

    this.isProcessing = true;
    try {
      let chosen: any | null = null;

      if (hasLinked) {
        chosen = this.selectedLinkedScenario;
      } else if (hasCustom) {
        chosen = {
          key: 'custom',
          title:
            this.args.model.customAdventure?.cardTitle || 'Custom Adventure',
          description: this.args.model.customAdventure?.cardDescription || '',
        };
      }

      if (!chosen) throw new Error('Scenario not found');

      const kickoffTags = (
        hasLinked
          ? (this.selectedLinkedScenario?.tags ?? [])
          : (this.args.model?.customAdventure?.tags ?? [])
      ).filter(Boolean);

      const kickoffStyles = (
        hasLinked
          ? (this.selectedLinkedScenario?.imageStyles ?? [])
          : (this.args.model?.customAdventure?.imageStyles ?? [])
      ).filter(Boolean);

      const ctx = this.args.context?.commandContext;
      if (!ctx)
        throw new Error(
          'Command context does not exist. Please switch to Interact Mode',
        );

      const patch = new PatchCardInstanceCommand(ctx, { cardType: Adventure });

      const now = new Date();
      const startedAtTimestamp = now.toISOString();

      await patch.execute({
        cardId: this.args.model.id,
        patch: {
          attributes: {
            oneShotTags: kickoffTags,
            oneShotImageStyles: kickoffStyles,
            gameStatus: 'playing',
            autoGenerateImages: true,
            currentTurn: 1,
            startedAt: startedAtTimestamp,
          },
          relationships: {
            selectedScenario: {
              links: {
                self: hasLinked ? this.selectedLinkedScenario?.id : null,
              },
            },
          },
        },
      });

      // === Collect skills from base GM + all active mods ===
      const gmSkillId = new URL(
        './Skill/adventure-game-master',
        import.meta.url,
      ).href;
      const suggestionSkillId = new URL(
        './Skill/suggestion-action-helper',
        import.meta.url,
      ).href;

      const skillIds = [gmSkillId, suggestionSkillId];

      // Add skills from active mods
      for (const mod of this.activeMods) {
        if (mod.modSkills?.length) {
          for (const skill of mod.modSkills) {
            if (skill.id) {
              skillIds.push(skill.id);
            }
          }
        }
      }

      // === Build mod context for the GM ===
      let modContext = '';
      if (this.activeMods.length > 0) {
        modContext = '\n\n## Active Mods\n\n';
        for (const mod of this.activeMods) {
          modContext += `### ${mod.modName}\n${mod.gmInstructions || 'No special instructions.'}\n\n`;
        }
      }

      const kickoffPrompt = `Let's begin the adventure.${modContext}`;

      const { roomId } = await new CreateAiAssistantRoomCommand(ctx).execute({
        name: `Adventure: ${chosen.title}`,
      });

      if (roomId) {
        this.roomId = roomId;
        await patch.execute({
          cardId: this.args.model.id,
          patch: { attributes: { chatRoomId: this.roomId } },
        });
        const set = new SetActiveLLMCommand(ctx);
        await set.execute({ roomId, mode: 'act' });
      }

      const use = new UseAiAssistantCommand(ctx);

      // Attach mods as cards so GM can read/write their state
      const attachedCards: CardDef[] = [this.args.model as CardDef];
      for (const mod of this.activeMods) {
        attachedCards.push(mod as CardDef);
      }

      const opts: any = {
        roomId: this.roomId || 'new',
        openRoom: true,
        attachedCards,
        prompt: kickoffPrompt,
        llmModel: 'anthropic/claude-sonnet-4.5',
        llmMode: 'act',
        skillCardIds: skillIds,
      };

      if (this.args.model?.chatRoomId) {
        opts.roomId = this.args.model.chatRoomId;
      } else {
        opts.roomId = 'new';
        opts.roomName = `Adventure: ${chosen.title}`;
      }

      await use.execute(opts);
    } catch (e: any) {
      console.error('Adventure start error:', e);
      alert(`Failed to start: ${e?.message || String(e)}`);
      try {
        const ctx = this.args.context?.commandContext;
        if (!ctx)
          throw new Error(
            'Command context does not exist. Please switch to Interact Mode',
          );

        const patch = new PatchCardInstanceCommand(ctx, {
          cardType: Adventure,
        });
        await patch.execute({
          cardId: this.args.model.id,
          patch: { attributes: { gameStatus: 'setup' } },
        });
      } catch {
        /* empty */
      }
    } finally {
      this.isProcessing = false;
    }
  }

  @action
  async resetAdventure() {
    const confirmed = confirm(
      '🔄 Reset Adventure?\n\nThis will clear all progress and start over.\n\nLinked scenarios, mods, and settings will be kept.',
    );

    if (!confirmed) return;
    try {
      const ctx = this.args.context?.commandContext;
      if (!ctx)
        throw new Error(
          'Command context does not exist. Please switch to Interact Mode',
        );

      const relationships: any = {
        lastCloudflareImage: { links: { self: null } },
        selectedScenario: { links: { self: null } },
        lastChoiceOffered: { links: { self: null } },
      };

      const patch = new PatchCardInstanceCommand(ctx, { cardType: Adventure });
      await patch.execute({
        cardId: this.args.model.id,
        patch: {
          attributes: {
            gameStatus: 'setup',
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
          relationships,
        },
      });
      this.selectedScenarioKey = null;
      this.roomId = null;
      this.pendingChoice = '';
      this.currentImageData = null;
      this.expandedModId = null;
    } catch (e: any) {
      console.error('Reset error:', e);
      alert(`Failed to reset: ${e?.message || String(e)}`);
    }
  }

  @action
  selectScenario(key: string) {
    this.selectedScenarioKey = key;
    this.selectedLinkedScenario = null;
  }

  @action
  selectLinked(s: any) {
    try {
      this.selectedLinkedScenario = s || null;
      this.selectedScenarioKey = s?.key || null;
      if (s) {
        if (!this.args.model.customAdventure) {
          this.args.model.customAdventure = new CustomAdventureField();
        }
        const tags = Array.isArray(s.tags) ? [...s.tags] : [];
        const styles = Array.isArray(s.imageStyles) ? [...s.imageStyles] : [];
        this.args.model.customAdventure.tags = tags;
        this.args.model.customAdventure.imageStyles = styles;
        this.newTag = '';
        this.newStyle = '';
      }
    } catch {
      this.selectedLinkedScenario = null;
    }
  }

  updateTags = (items: string[]) => {
    if (!this.args.model?.customAdventure) return;
    this.args.model.customAdventure.tags = items;
  };

  updateImageStyles = (items: string[]) => {
    if (!this.args.model?.customAdventure) return;
    this.args.model.customAdventure.imageStyles = items;
  };

  @action
  async startWithLinked(s: any) {
    await this.selectLinked(s);
    try {
      await this.startAdventure();
    } catch (e) {
      console.error('Failed to start with linked scenario', e);
    }
  }

  @action
  async generateSceneImage() {
    if (this.args.model.gameStatus !== 'playing') return;
    const imagePrompt = this.args.model?.lastImagePrompt;
    if (!imagePrompt) return;

    this.isProcessing = true;
    this.isImageLoading = true;

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
      const dataUrl = Array.isArray(msg?.images)
        ? msg.images
            .map((i: any) => i?.image_url?.url)
            .find((u: string) => u?.startsWith('data:image/'))
        : null;

      if (!dataUrl) throw new Error('No data:image/* URL found');

      this.currentImageData = dataUrl;
      this.isImageLoading = false;

      try {
        const uploadCmd = new UploadImageCommand(ctx);

        const modelRealmUrl = this.args.model?.[realmURL];
        if (!modelRealmUrl) {
          throw new Error('Realm URL not available on the model');
        }

        const uploadResult = await uploadCmd.execute({
          sourceImageUrl: dataUrl,
          targetRealmUrl: modelRealmUrl.href,
        });

        if (uploadResult.cardId) {
          const patch = new PatchCardInstanceCommand(ctx, {
            cardType: Adventure,
          });
          await patch.execute({
            cardId: this.args.model.id,
            patch: {
              relationships: {
                lastCloudflareImage: { links: { self: uploadResult.cardId } },
              },
            },
          });
        }
      } catch (uploadError: any) {
        console.error('Image upload error:', uploadError);
        this.showToast(
          `Upload failed: ${uploadError?.message || String(uploadError)}`,
        );
      }
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

  get currentScenario() {
    try {
      if (this.args.model?.selectedScenario) {
        return this.args.model.selectedScenario;
      }

      const custom = this.args.model?.customAdventure;
      if (custom?.cardTitle || custom?.cardDescription) {
        return {
          cardTitle: custom.cardTitle || 'Custom Adventure',
          cardDescription: custom.cardDescription || '',
          tags: custom.tags || [],
          imageStyles: custom.imageStyles || [],
        };
      }

      return this.args.model?.linkedScenarios?.[0] || null;
    } catch (e) {
      console.error('Adventure: Error getting current scenario', e);
      return this.args.model?.linkedScenarios?.[0] || null;
    }
  }

  <template>
    <div class='stage'>
      <article class='mat'>

        {{#if this.gameNotStarted}}
          <section class='select'>
            <h2 class='section-title'>Set Up Your Adventure</h2>

            <div class='mode-picker'>
              <Button
                class='mode-btn {{if (eq this.setupMode "quick") "active"}}'
                {{on 'click' (fn this.setSetupMode 'quick')}}
              >
                Quick Start
              </Button>
              <Button
                class='mode-btn {{if (eq this.setupMode "custom") "active"}}'
                {{on 'click' (fn this.setSetupMode 'custom')}}
              >
                Custom Adventure
              </Button>
            </div>

            {{#if (eq this.setupMode 'quick')}}
              <p class='section-help'>Choose from pre-built scenarios to start
                quickly.</p>

              {{#if (gt @model.linkedScenarios.length 0)}}
                <h3 class='section-title'>Linked Scenarios</h3>
                <div class='grid'>
                  {{#each @model.linkedScenarios as |sc|}}
                    <div
                      class='card
                        {{if (eq this.selectedScenarioKey sc.key) "selected"}}'
                    >
                      <div class='card-title'>{{sc.cardTitle}}</div>
                      <div class='card-desc'>{{sc.cardDescription}}</div>
                      <div class='card-meta'>
                        {{#if (gt sc.tags.length 0)}}
                          <span class='meta-pill subtle'>{{get
                              sc.tags
                              0
                            }}</span>
                        {{/if}}
                      </div>
                      <div class='actions-center'>
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
                <div class='empty-scenarios'>
                  <div class='empty-icon'>📚</div>
                  <h3>No Scenarios Yet</h3>
                  <p>Link pre-built scenarios to get started quickly</p>
                </div>
              {{/if}}

              <h3 class='section-title'>Add Linked Scenarios</h3>
              <p class='section-help'>Use the chooser to add Scenario cards.
                Linked scenarios appear above.</p>
              <div class='actions-center'>
                <Button class='btn secondary' {{on 'click' this.showChooser}}>
                  Add Adventure Scenario
                </Button>
              </div>
              {{#if this.showLinkedChooser}}
                <div class='chooser-panel'>
                  <@fields.linkedScenarios @format='edit' />
                  <div class='actions-center close-chooser'>
                    <Button
                      class='btn ghost'
                      {{on 'click' this.hideChooser}}
                    >Close Chooser</Button>
                  </div>
                </div>
              {{/if}}
            {{/if}}

            {{#if (eq this.setupMode 'custom')}}
              <p class='section-help'>Craft a unique adventure with custom tags
                and image styles.</p>

              <div class='card custom-form-card'>
                <div class='card-title'>Title</div>
                <@fields.customAdventure.cardTitle @format='edit' />
                <div class='card-title'>Description</div>
                <@fields.customAdventure.cardDescription @format='edit' />
                <div class='card-title'>Tags</div>
                <ChipsEditor
                  @name='Tags'
                  @items={{@model.customAdventure.tags}}
                  @onItemsUpdate={{this.updateTags}}
                  @placeholder='Add tag... (Enter)'
                />
                <div class='chips'>
                  {{#if
                    (and
                      (eq (get @model.customAdventure.tags 'length') 0)
                      (not this.newTag)
                    )
                  }}
                    <div class='chip-suggestions'>
                      <span class='hint'>Try:</span>
                      {{#each this.exampleTags as |tag|}}
                        <Button
                          class='chip suggested'
                          {{on 'click' (fn this.addTag tag)}}
                        >
                          {{tag}}
                        </Button>
                      {{/each}}
                    </div>
                  {{/if}}
                </div>

                <div class='card-title'>Image Styles</div>
                <div class='chips'>
                  <ChipsEditor
                    @name='Image style'
                    @items={{@model.customAdventure.imageStyles}}
                    @onItemsUpdate={{this.updateImageStyles}}
                    @placeholder='Add style... (Enter)'
                  />
                  {{#if
                    (and
                      (eq (get @model.customAdventure.imageStyles 'length') 0)
                      (not this.newStyle)
                    )
                  }}
                    <div class='chip-suggestions'>
                      <span class='hint'>Try:</span>
                      {{#each this.exampleStyles as |style|}}
                        <Button
                          class='chip suggested'
                          {{on 'click' (fn this.addStyle style)}}
                        >
                          {{style}}
                        </Button>
                      {{/each}}
                    </div>
                  {{/if}}
                </div>
                <div class='actions-center'>
                  <Button
                    class='btn primary'
                    @disabled={{this.isProcessing}}
                    {{on 'click' this.startAdventure}}
                  >
                    {{#if this.isProcessing}}
                      <span class='spinner'></span>
                    {{/if}}
                    {{if this.isProcessing 'Starting…' 'Begin'}}
                  </Button>
                </div>
              </div>
            {{/if}}

            {{! === MODS SECTION === }}
            {{#if (gt @model.mods.length 0)}}
              <section class='mods-setup'>
                <h3 class='section-title'>Active Mods ({{@model.mods.length}})</h3>
                <div class='mods-grid'>
                  {{#each @model.mods as |mod|}}
                    <mod @format='embedded' />
                  {{/each}}
                </div>
              </section>
            {{/if}}

            <section class='mods-setup'>
              <h3 class='section-title'>Manage Mods</h3>
              <p class='section-help'>Add mods to enhance your adventure with
                NPCs, inventory, spells, and more.</p>
              <@fields.mods @format='edit' />
            </section>

          </section>
        {{/if}}

        {{#if this.gameInProgress}}
          <section class='story {{if this.currentDisplayImageUrl "has-image"}}'>

            {{! === MOD STATUS STRIP === }}
            {{#if (gt this.activeMods.length 0)}}
              <div class='mod-status-strip'>
                {{#each this.modStatusItems as |item|}}
                  <button
                    class='mod-status-item
                      {{if (eq this.expandedModId item.id) "active"}}'
                    type='button'
                    {{on 'click' (fn this.toggleModPanel item.id)}}
                  >
                    <span class='mod-icon'>{{item.icon}}</span>
                    <span class='mod-summary'>{{item.summary}}</span>
                  </button>
                {{/each}}
              </div>
            {{/if}}

            <div class='turnbar'>
              <div class='turn-left'>
                <span class='turn-dot'></span>
                <span class='turn-label'>Turn {{@model.currentTurn}}</span>
              </div>
            </div>

            <div class='actionbar'>
              {{#if (or this.roomId @model.chatRoomId)}}
                <Button
                  class='btn primary'
                  {{on 'click' this.openAIAssistantRoom}}
                >
                  Open AI Chat
                </Button>
              {{else}}
                <Button class='btn primary' @disabled={{true}}>Open Chat</Button>
              {{/if}}

              <div class='action-right'>
                {{#if (not @model.autoGenerateImages)}}
                  <Button
                    class='btn secondary'
                    @disabled={{or
                      this.isProcessing
                      (not @model.lastImagePrompt)
                    }}
                    {{on 'click' this.generateSceneImage}}
                  >
                    {{#if this.isProcessing}}
                      <span class='spinner'></span>
                    {{/if}}
                    {{if this.isProcessing 'Generating…' '🎨 Generate Image'}}
                  </Button>
                {{/if}}

                {{#if
                  (and
                    (not @model.lastImagePrompt) (not @model.autoGenerateImages)
                  )
                }}
                  <div class='micro-help'>Waiting for scene description…</div>
                {{/if}}

                <Button
                  class='btn ghost'
                  {{on 'click' this.resetAdventure}}
                  title='Reset Adventure'
                >🔄</Button>
              </div>
            </div>

            {{#if this.toastMessage}}
              <div class='toast' role='status'>{{this.toastMessage}}</div>
            {{/if}}

            {{! === EXPANDED MOD PANEL === }}
            {{#if this.expandedModId}}
              <div class='mod-panel-expanded'>
                {{#each @model.mods as |mod|}}
                  {{#if (eq mod.id this.expandedModId)}}
                    <div class='mod-panel-header'>
                      <span class='mod-panel-title'>{{mod.modName}}</span>
                      <Button
                        class='btn ghost mod-panel-close'
                        {{on 'click' (fn this.toggleModPanel mod.id)}}
                      >✕</Button>
                    </div>
                    <div class='mod-panel-content'>
                      <mod @format='isolated' />
                    </div>
                  {{/if}}
                {{/each}}
              </div>
            {{/if}}

            <div class='story-panel'>
              {{#if this.isImageLoading}}
                <div class='image-skeleton'></div>
              {{else if this.currentDisplayImageUrl}}
                <div class='image-wrap'>
                  <img src={{this.currentDisplayImageUrl}} alt='Scene' />
                  {{#if this.isOverlayVisible}}
                    {{#if @model.lastNarration}}
                      <div class='overlay'>
                        <div class='overlay-box'>
                          <div class='overlay-content'>
                            <@fields.lastNarration />
                          </div>
                        </div>
                      </div>
                    {{/if}}
                  {{/if}}

                  <div class='overlay-controls'>
                    <div class='oc-left'>
                      <span class='oc-turn'>Turn {{@model.currentTurn}}</span>
                    </div>

                    <div class='oc-right'>
                      {{#if (or this.roomId @model.chatRoomId)}}
                        <Button
                          class='btn primary'
                          {{on 'click' this.openAIAssistantRoom}}
                        >
                          Open AI Chat
                        </Button>
                      {{else}}
                        <Button class='btn primary' @disabled={{true}}>Open Chat</Button>
                      {{/if}}

                      {{#if (not @model.autoGenerateImages)}}
                        <Button
                          class='btn secondary'
                          @disabled={{or
                            this.isProcessing
                            (not @model.lastImagePrompt)
                          }}
                          {{on 'click' this.generateSceneImage}}
                        >
                          {{#if this.isProcessing}}
                            <span class='spinner'></span>
                          {{/if}}
                          {{if
                            this.isProcessing
                            'Generating…'
                            '🎨 Generate Image'
                          }}
                        </Button>
                      {{/if}}

                      {{#if
                        (and
                          (not @model.lastImagePrompt)
                          (not @model.autoGenerateImages)
                        )
                      }}
                        <div class='micro-help'>Waiting for scene description…</div>
                      {{/if}}

                      <Button
                        class='btn ghost'
                        {{on 'click' this.resetAdventure}}
                        title='Reset Adventure'
                      >🔄</Button>
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
                {{#if this.currentDisplayImageUrl}}
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
                <div class='placeholder enchanted'>
                  <div class='placeholder-icon'>✨</div>
                  <h3>Your Adventure Awaits</h3>
                  <p>The narrator is crafting Turn {{@model.currentTurn}}...</p>
                  <div class='placeholder-hint'>Open the AI Chat to continue
                    your journey</div>
                </div>
              {{/if}}

              {{#if @model.lastChoiceOffered}}
                <div class='choices-section'>
                  <@fields.lastChoiceOffered @format='embedded' />
                </div>
              {{/if}}
            </div>

            <footer class='header bottom'>
              <div class='header-top'>
                <h1 class='title'>
                  {{if
                    this.currentScenario.cardTitle
                    this.currentScenario.cardTitle
                    'Create Your Own Adventure'
                  }}
                </h1>
              </div>
              {{#if this.currentScenario.cardDescription}}
                <p class='subtitle'>{{this.currentScenario.cardDescription}}</p>
              {{/if}}
            </footer>

          </section>
        {{/if}}

        {{#if (eq @model.gameStatus 'completed')}}
          <section class='complete'>
            <h2 class='section-title'>Adventure Complete</h2>
            <p class='section-help'>Thanks for playing. You can still open the
              chat or start again.</p>
            <div class='actionbar'>
              {{#if (or this.roomId @model.chatRoomId)}}
                <Button
                  class='btn primary'
                  {{on 'click' this.openAIAssistantRoom}}
                >
                  Open Chat
                </Button>
              {{/if}}
              <Button class='btn ghost' {{on 'click' this.resetAdventure}}>Start
                Over</Button>
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
        background: var(
          --background,
          linear-gradient(135deg, #eef2ff 0%, #f8fafc 100%)
        );
        padding: 0.75rem;
      }
      .mat {
        max-width: 52rem;
        width: 100%;
        background: var(--card, white);
        border-radius: var(--radius, 0.75rem);
        box-shadow: var(--shadow, 0 10px 24px rgba(15, 23, 42, 0.06));
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
        letter-spacing: var(--tracking-normal, -0.01em);
        color: var(--foreground, #111827);
      }
      .subtitle {
        margin: 0.25rem 0 0;
        color: var(--muted-foreground, #4b5563);
        font-size: 0.9rem;
        line-height: 1.35;
      }
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

      /* Section headers */
      .section-title {
        margin: 0 0 0.25rem;
        font-size: 1rem;
        font-weight: 700;
        color: var(--foreground, #111827);
      }
      .section-help {
        margin: 0 0 1rem;
        font-size: 0.85rem;
        color: var(--muted-foreground, #6b7280);
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
      .custom-form-card {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }

      .card {
        text-align: left;
        width: 100%;
        border: 1px solid var(--border, #e5e7eb);
        background: var(--card, #fff);
        border-radius: var(--radius, 0.5rem);
        padding: 1rem;
        transition:
          transform 120ms ease,
          box-shadow 120ms ease,
          border-color 120ms;
        cursor: pointer;
      }
      .card:hover {
        transform: translateY(-1px);
        box-shadow: var(--shadow, 0 6px 14px rgba(15, 23, 42, 0.06));
        border-color: var(--border, #cbd5e1);
      }
      .card.selected {
        border-color: var(--primary, #6366f1);
        box-shadow: 0 6px 16px rgba(99, 102, 241, 0.2);
      }
      .card-title {
        font-weight: 700;
        color: var(--card-foreground, #0f172a);
        font-size: 0.875rem;
        text-transform: uppercase;
        letter-spacing: 0.025em;
        opacity: 0.8;
      }
      .card-desc {
        color: var(--muted-foreground, #475569);
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
        border: 1px solid var(--border, #e5e7eb);
        border-radius: 999px;
        padding: 0.125rem 0.5rem;
        font-size: 0.75rem;
        font-weight: 600;
        color: var(--muted-foreground, #334155);
        background: var(--card, #fff);
      }
      .meta-pill.subtle {
        color: var(--muted-foreground, #64748b);
      }

      .actions-center {
        display: flex;
        justify-content: center;
        margin-top: 0.25rem;
      }

      .chooser-panel {
        padding-top: 1rem;
        padding-bottom: 1rem;
      }

      .close-chooser {
        margin-top: 0.5rem;
      }

      /* === MOD STATUS STRIP === */
      .mod-status-strip {
        display: flex;
        gap: 0.5rem;
        padding: 0.5rem;
        background: linear-gradient(135deg, #f8fafc, #f1f5f9);
        border: 1px solid #e5e7eb;
        border-radius: 0.5rem;
        margin-bottom: 0.5rem;
        flex-wrap: wrap;
      }

      .mod-status-item {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.375rem 0.625rem;
        background: white;
        border: 1px solid #e5e7eb;
        border-radius: 999px;
        font-size: 0.8125rem;
        cursor: pointer;
        transition: all 120ms ease;
      }

      .mod-status-item:hover {
        border-color: #6366f1;
        background: #eef2ff;
      }

      .mod-status-item.active {
        border-color: #6366f1;
        background: #6366f1;
        color: white;
      }

      .mod-icon {
        font-size: 0.875rem;
      }

      .mod-summary {
        font-weight: 500;
      }

      /* === EXPANDED MOD PANEL === */
      .mod-panel-expanded {
        background: white;
        border: 1px solid #e5e7eb;
        border-radius: 0.5rem;
        margin-bottom: 0.75rem;
        overflow: hidden;
      }

      .mod-panel-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 0.625rem 0.75rem;
        background: #f8fafc;
        border-bottom: 1px solid #e5e7eb;
      }

      .mod-panel-title {
        font-weight: 600;
        color: #111827;
      }

      .mod-panel-close {
        padding: 0.25rem 0.5rem;
        font-size: 0.875rem;
      }

      .mod-panel-content {
        padding: 0.75rem;
        max-height: 300px;
        overflow-y: auto;
      }

      /* === MODS SETUP SECTION === */
      .mods-setup {
        margin-top: 1.5rem;
        padding-top: 1rem;
        border-top: 1px solid #e5e7eb;
      }

      .mods-grid {
        display: grid;
        gap: 0.5rem;
        margin-bottom: 1rem;
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
        padding: 0.375rem 0.5rem;
        gap: 0.375rem;
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

      /* Action Bar */
      .actionbar {
        position: sticky;
        top: 0;
        z-index: 1;
        display: flex;
        gap: 0.375rem;
        flex-wrap: wrap;
        align-items: center;
        background: rgba(255, 255, 255, 0.75);
        backdrop-filter: blur(6px);
        border: 1px solid #e5e7eb;
        border-radius: 0.5rem;
        padding: 0.375rem;
      }

      /* Buttons */
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
      }
      .btn.primary {
        background: var(--primary, linear-gradient(135deg, #2563eb, #1d4ed8));
        color: var(--primary-foreground, #fff);
      }
      .btn.primary:hover:not([disabled]) {
        transform: translateY(-1px);
        box-shadow: var(--shadow, 0 4px 12px rgba(37, 99, 235, 0.35));
      }
      .btn.secondary {
        background: var(--secondary, #fff);
        color: var(--secondary-foreground, #1f2937);
        border-color: var(--border, #cbd5e1);
      }
      .btn.secondary:hover:not([disabled]) {
        transform: translateY(-1px);
        box-shadow: var(--shadow-sm, 0 4px 10px rgba(15, 23, 42, 0.06));
      }
      .btn.ghost {
        background: transparent;
        color: var(--muted-foreground, #374151);
        border-color: var(--border, #e5e7eb);
      }
      .btn.ghost:hover:not([disabled]) {
        background: var(--muted, #f8fafc);
        transform: translateY(-1px);
      }

      /* Hide bars when image present */
      .story.has-image .turnbar,
      .story.has-image .actionbar {
        display: none;
      }

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
        height: auto;
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
        pointer-events: none;
        z-index: 2;
      }
      .image-wrap .overlay-controls .oc-left,
      .image-wrap .overlay-controls .oc-right {
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        flex-wrap: wrap;
        pointer-events: auto;
      }

      .image-wrap .overlay-controls .btn {
        background: rgba(17, 24, 39, 0.75);
        backdrop-filter: blur(8px);
        border: 1px solid rgba(255, 255, 255, 0.2);
        color: #fff;
        text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
      }
      .image-wrap .overlay-controls .btn.ghost {
        background: rgba(17, 24, 39, 0.6);
        border-color: rgba(255, 255, 255, 0.3);
        color: #fff;
      }
      .image-wrap .overlay-controls .btn.primary {
        background: linear-gradient(135deg, #2563eb, #1d4ed8);
      }

      .oc-turn {
        font-weight: 700;
        color: #fff;
        text-shadow: 0 1px 2px rgba(0, 0, 0, 0.6);
      }

      .image-wrap .overlay {
        position: absolute;
        inset: 0;
        display: flex;
        align-items: flex-end;
        background: none;
        pointer-events: none;
      }
      .overlay-box {
        margin: 0.5rem;
        background: rgba(17, 24, 39, 0.75);
        backdrop-filter: blur(8px);
        border: 1px solid rgba(255, 255, 255, 0.2);
        color: #fff;
        border-radius: 0.5rem;
        padding: 0.75rem;
        margin-bottom: 3rem;
        max-height: 60%;
        overflow: auto;
        pointer-events: auto;
        font-size: 0.875rem;
        line-height: 1.45;
      }
      .overlay-content {
        margin-top: -24px;
      }

      .narration {
        color: #111827;
        font-size: 0.875rem;
        line-height: 1.5;
        max-width: 70ch;
      }

      .placeholder {
        color: #6b7280;
        font-style: italic;
        text-align: center;
        padding: 1rem;
        border: 1px dashed #e5e7eb;
        border-radius: 0.5rem;
        background: #f9fafb;
      }

      .placeholder.enchanted {
        padding: 2rem 1rem;
        background: linear-gradient(135deg, #fef3c7 0%, #fde68a 100%);
        border-color: #fbbf24;
      }
      .placeholder-icon {
        font-size: 2.5rem;
        margin-bottom: 0.5rem;
      }
      .placeholder.enchanted h3 {
        margin: 0 0 0.25rem;
        font-size: 1.125rem;
        font-weight: 700;
        color: #78350f;
      }
      .placeholder.enchanted p {
        margin: 0 0 0.5rem;
        color: #92400e;
        font-size: 0.875rem;
      }
      .placeholder-hint {
        font-size: 0.75rem;
        color: #a16207;
        font-weight: 600;
        padding: 0.375rem 0.75rem;
        background: rgba(255, 255, 255, 0.5);
        border-radius: 999px;
        display: inline-block;
      }

      .choices-section {
        margin-top: 1rem;
        padding-top: 1rem;
        border-top: 1px solid #e5e7eb;
      }

      .spinner {
        display: inline-block;
        width: 0.875rem;
        height: 0.875rem;
        border: 2px solid rgba(255, 255, 255, 0.3);
        border-top-color: #fff;
        border-radius: 50%;
        animation: spin 0.6s linear infinite;
        margin-right: 0.25rem;
      }
      @keyframes spin {
        to {
          transform: rotate(360deg);
        }
      }

      .mode-picker {
        display: flex;
        gap: 0.5rem;
        margin-bottom: 1rem;
        padding: 0.25rem;
        background: #f3f4f6;
        border-radius: 0.5rem;
      }
      .mode-btn {
        flex: 1;
        padding: 0.5rem 1rem;
        background: transparent;
        border: 1px solid transparent;
        border-radius: var(--radius, 0.375rem);
        font-size: 0.875rem;
        font-weight: 600;
        color: var(--muted-foreground, #6b7280);
        cursor: pointer;
        transition: all 120ms ease;
      }
      .mode-btn:hover {
        color: var(--foreground, #374151);
        background: rgba(255, 255, 255, 0.5);
      }
      .mode-btn.active {
        background: var(--card, #fff);
        color: var(--primary, #2563eb);
        border-color: var(--border, #e5e7eb);
        box-shadow: var(--shadow-sm, 0 2px 4px rgba(15, 23, 42, 0.04));
      }

      .chip-suggestions {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
        align-items: center;
        padding: 0.75rem;
        background: var(--muted, #f9fafb);
        border-radius: var(--radius, 0.5rem);
        border: 1px dashed var(--border, #e5e7eb);
      }
      .chip-suggestions .hint {
        font-size: 0.75rem;
        color: var(--muted-foreground, #6b7280);
        font-weight: 600;
        margin-right: 0.25rem;
      }
      .chip.suggested {
        font-size: 0.8125rem;
        padding: 0.375rem 0.75rem;
        border-radius: 999px;
        border: 1px solid #ddd6fe;
        background: #f5f3ff;
        color: #6366f1;
        cursor: pointer;
        transition: all 120ms ease;
        font-weight: 500;
      }
      .chip.suggested:hover {
        background: #ede9fe;
        border-color: #a78bfa;
        transform: translateY(-1px);
      }

      .empty-scenarios {
        text-align: center;
        padding: 2rem 1rem;
        border: 1px dashed #e5e7eb;
        border-radius: 0.5rem;
        background: #f9fafb;
      }
      .empty-scenarios .empty-icon {
        font-size: 3rem;
        margin-bottom: 0.5rem;
      }
      .empty-scenarios h3 {
        margin: 0 0 0.25rem;
        font-size: 1rem;
        font-weight: 700;
        color: #111827;
      }
      .empty-scenarios p {
        margin: 0;
        color: #6b7280;
        font-size: 0.875rem;
      }

      .complete {
        padding: 2rem 1.25rem;
        text-align: center;
      }

      @media (max-width: 768px) {
        .header {
          padding: 1rem 1rem 0.5rem;
        }
        .title {
          font-size: 1.125rem;
        }
        .select,
        .story {
          padding: 0.75rem 1rem 1rem;
        }
        .btn {
          font-size: 0.8125rem;
          padding: 0.4375rem 0.625rem;
        }
      }
    </style>
  </template>
}

export class Adventure extends CardDef {
  static displayName = 'Adventure';
  static icon = BookOpenIcon;
  static prefersWideFormat = true;

  @field linkedScenarios = linksToMany(AdventureScenario);
  @field selectedScenario = linksTo(AdventureScenario);

  @field customAdventure = contains(CustomAdventureField);

  // === MODS ===
  /** Mods attached to this adventure (NPCs, Inventory, Spellbook, etc.) */
  @field mods = linksToMany(AdventureMod);

  @field gameStatus = contains(StringField); // 'setup' | 'playing' | 'completed'
  @field currentTurn = contains(NumberField);
  @field startedAt = contains(DateTimeField);
  @field completedAt = contains(DateTimeField);
  @field chatRoomId = contains(StringField);

  @field lastTurnNumber = contains(NumberField);
  @field lastNarration = contains(MarkdownField);
  @field lastPlayerChoice = contains(StringField);
  @field lastTimestamp = contains(DateTimeField);
  @field lastIsPlayerTurn = contains(BooleanField);
  @field lastImagePrompt = contains(StringField);
  @field lastCloudflareImage = linksTo(CloudflareImage);
  @field autoGenerateImages = contains(BooleanField);

  @field lastChoiceOffered = linksTo(() => MultipleChoice);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Adventure) {
      try {
        if (this.selectedScenario) {
          return this.selectedScenario.cardTitle;
        }

        const custom = this.customAdventure;
        if (custom?.cardTitle) {
          return custom.cardTitle || 'Custom Adventure';
        }

        return 'Create Your Own Adventure';
      } catch (e) {
        console.error('Adventure: Error computing title', e);
        return 'Adventure Game';
      }
    },
  });

  // === Computed: Active mod skills for GM context ===
  get activeModSkillIds(): string[] {
    const ids: string[] = [];
    for (const mod of this.mods ?? []) {
      if (mod.isEnabled && mod.modSkills?.length) {
        for (const skill of mod.modSkills) {
          if (skill.id) {
            ids.push(skill.id);
          }
        }
      }
    }
    return ids;
  }

  static isolated = AdventureIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get currentScenario() {
      try {
        if (this.args.model?.selectedScenario) {
          return this.args.model.selectedScenario;
        }

        const custom = this.args.model?.customAdventure;
        if (custom?.cardTitle || custom?.cardDescription) {
          return {
            cardTitle: custom.cardTitle || 'Custom Adventure',
            cardDescription: custom.cardDescription || '',
            tags: custom.tags || [],
            imageStyles: custom.imageStyles || [],
          };
        }

        return this.args.model?.linkedScenarios?.[0] || null;
      } catch (e) {
        console.error(
          'Adventure: Error getting current scenario in embedded',
          e,
        );
        return this.args.model?.linkedScenarios?.[0] || null;
      }
    }

    get activeMods() {
      return this.args.model?.mods?.filter((m) => m.isEnabled) ?? [];
    }

    <template>
      <div class='embedded-card'>
        <div class='top'>
          {{#if this.currentScenario}}
            <span class='pill'>{{this.currentScenario.cardTitle}}</span>
          {{/if}}
        </div>

        <div class='status'>
          {{#if (eq @model.gameStatus 'playing')}}
            <span class='tag active'>Playing • Turn
              {{@model.currentTurn}}</span>
          {{else}}
            <span class='tag ready'>Ready</span>
          {{/if}}
          {{#if (gt this.activeMods.length 0)}}
            <span class='tag mods'>{{this.activeMods.length}} mods</span>
          {{/if}}
        </div>

        {{#if this.currentScenario.cardDescription}}
          <p class='preview'>{{this.currentScenario.cardDescription}}</p>
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
        .tag.ready {
          border-color: #fde68a;
          color: #92400e;
        }
        .tag.mods {
          border-color: #ddd6fe;
          color: #7c3aed;
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

  static fitted = class Fitted extends Component<typeof this> {
    get currentScenario() {
      try {
        if (this.args.model?.selectedScenario) {
          return this.args.model.selectedScenario;
        }

        const custom = this.args.model?.customAdventure;
        if (custom?.cardTitle || custom?.cardDescription) {
          return {
            cardTitle: custom.cardTitle || 'Custom Adventure',
            cardDescription: custom.cardDescription || '',
            tags: custom.tags || [],
            imageStyles: custom.imageStyles || [],
          };
        }

        return this.args.model?.linkedScenarios?.[0] || null;
      } catch (e) {
        console.error('Adventure: Error getting current scenario in fitted', e);
        return this.args.model?.linkedScenarios?.[0] || null;
      }
    }

    <template>
      <div class='fitted'>
        <div class='badge'>
          <div class='dot'></div>
          <div class='label'>
            <div class='title'>{{if
                this.currentScenario.cardTitle
                this.currentScenario.cardTitle
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

        <div class='strip'>
          <div class='strip-main'>
            {{#if this.currentScenario}}
              <div class='sub'>{{this.currentScenario.cardTitle}}</div>
            {{/if}}
          </div>
          <div class='strip-status'>
            {{#if (eq @model.gameStatus 'playing')}}T{{@model.currentTurn}}
            {{else if (eq @model.gameStatus 'completed')}}Done
            {{else}}Start{{/if}}
          </div>
        </div>

        <div class='tile'>
          {{#if this.currentScenario}}
            <div class='desc'>
              <strong>{{this.currentScenario.cardTitle}}</strong>
              <p>{{this.currentScenario.cardDescription}}</p>
            </div>
          {{/if}}
          <div class='foot'>
            {{#if (eq @model.gameStatus 'playing')}}
              <span>Turn {{@model.currentTurn}}</span>
            {{else if (eq @model.gameStatus 'completed')}}
              <span>Completed</span>
            {{else}}
              <span>Ready</span>
            {{/if}}
          </div>
        </div>

        <div class='card'>
          <div class='card-head'>
            <div class='main'>
              <h3>{{if this.currentScenario.cardTitle 'Adventure'}}</h3>
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
          {{#if this.currentScenario}}
            <div
              class='card-desc'
            >{{this.currentScenario.cardDescription}}</div>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .fitted {
          container-type: size;
          width: 100%;
          height: 100%;
        }
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

        .strip-main {
          flex: 1;
          min-width: 0;
        }
        .strip .title,
        .strip .sub {
          font-size: 0.875rem;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .strip .title {
          font-weight: 600;
          color: #111827;
        }
        .strip .sub {
          font-size: 0.75rem;
          color: #6b7280;
        }
        .strip-status {
          font-size: 0.75rem;
          color: #374151;
        }

        .tile .desc strong {
          display: block;
          color: #374151;
          font-size: 0.875rem;
          margin-bottom: 0.25rem;
        }
        .tile .desc p {
          margin: 0;
          color: #6b7280;
          font-size: 0.8125rem;
          line-height: 1.3;
          display: -webkit-box;
          -webkit-line-clamp: 3;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .tile .foot {
          margin-top: auto;
          font-size: 0.8125rem;
          color: #374151;
        }

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
      </style>
    </template>
  };
}
// touched for re-index
