import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
  StringField,
} from 'https://cardstack.com/base/card-api';
import BooleanField from 'https://cardstack.com/base/boolean';
import MarkdownField from 'https://cardstack.com/base/markdown';
import { Skill } from 'https://cardstack.com/base/skill';
import PuzzlePieceIcon from '@cardstack/boxel-icons/blocks';

/**
 * Base class for Adventure mods.
 *
 * Mods extend the Adventure game with new mechanics:
 * - NPCMod: Dynamic NPCs with evolving personalities
 * - InventoryMod: Item management
 * - SpellbookMod: Magic system
 * - QuestMod: Quest tracking
 *
 * Each mod provides:
 * - gmInstructions: How the GM AI should use this mod
 * - modSkills: Additional skills to load when mod is active
 * - statusIcon/statusSummary: For the compact status strip
 * - embedded view: For the expandable panel
 */
export class AdventureMod extends CardDef {
  static displayName = 'Adventure Mod';
  static icon = PuzzlePieceIcon;

  /** Human-readable mod name */
  @field modName = contains(StringField);

  /** Short description of what this mod adds */
  @field modDescription = contains(StringField);

  /**
   * Instructions for the GM AI on how to use this mod.
   * This gets injected into the GM's context when the adventure starts.
   */
  @field gmInstructions = contains(MarkdownField);

  /** Skills that this mod provides (e.g., NPC personalities, combat rules) */
  @field modSkills = linksToMany(Skill);

  /** Whether this mod is currently active */
  @field isEnabled = contains(BooleanField);

  /** Icon for the status strip (emoji or icon name) */
  @field statusIcon = contains(StringField);

  /**
   * Computed summary for status strip (e.g., "3 NPCs", "12/20 items")
   * Override in subclasses with computeVia
   */
  @field statusSummary = contains(StringField);

  static isolated = class Isolated extends Component<typeof AdventureMod> {
    <template>
      <article class='mod-isolated'>
        <header class='header'>
          <h1 class='title'>{{if
              @model.modName
              @model.modName
              'Adventure Mod'
            }}</h1>
          {{#if @model.isEnabled}}
            <span class='badge enabled'>Enabled</span>
          {{else}}
            <span class='badge disabled'>Disabled</span>
          {{/if}}
        </header>

        {{#if @model.modDescription}}
          <p class='description'>{{@model.modDescription}}</p>
        {{/if}}

        {{#if @model.gmInstructions}}
          <section class='instructions'>
            <h2>GM Instructions</h2>
            <div class='markdown-content'>
              <@fields.gmInstructions />
            </div>
          </section>
        {{/if}}

        {{#if @model.modSkills.length}}
          <section class='skills'>
            <h2>Mod Skills ({{@model.modSkills.length}})</h2>
            <ul class='skill-list'>
              {{#each @model.modSkills as |skill|}}
                <li class='skill-item'>{{skill.cardTitle}}</li>
              {{/each}}
            </ul>
          </section>
        {{/if}}
      </article>

      <style scoped>
        .mod-isolated {
          padding: 1.25rem;
          background: var(--card, #fff);
          border: 1px solid var(--border, #e5e7eb);
          border-radius: var(--radius, 0.5rem);
          max-width: 48rem;
        }

        .header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.75rem;
          margin-bottom: 0.75rem;
        }

        .title {
          margin: 0;
          font-size: 1.25rem;
          font-weight: 700;
          color: var(--foreground, #111827);
        }

        .badge {
          padding: 0.25rem 0.625rem;
          border-radius: 999px;
          font-size: 0.75rem;
          font-weight: 600;
        }

        .badge.enabled {
          background: #dcfce7;
          color: #166534;
          border: 1px solid #bbf7d0;
        }

        .badge.disabled {
          background: #f3f4f6;
          color: #6b7280;
          border: 1px solid #e5e7eb;
        }

        .description {
          margin: 0 0 1rem;
          color: var(--muted-foreground, #4b5563);
          font-size: 0.9375rem;
          line-height: 1.5;
        }

        .instructions {
          margin-bottom: 1rem;
        }

        .instructions h2,
        .skills h2 {
          margin: 0 0 0.5rem;
          font-size: 0.875rem;
          font-weight: 600;
          color: var(--muted-foreground, #6b7280);
          text-transform: uppercase;
          letter-spacing: 0.025em;
        }

        .markdown-content {
          padding: 0.75rem;
          background: var(--muted, #f9fafb);
          border: 1px solid var(--border, #e5e7eb);
          border-radius: var(--radius, 0.375rem);
          font-size: 0.875rem;
          line-height: 1.5;
        }

        .skill-list {
          margin: 0;
          padding: 0;
          list-style: none;
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
        }

        .skill-item {
          padding: 0.375rem 0.75rem;
          background: #eef2ff;
          color: #4338ca;
          border-radius: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof AdventureMod> {
    <template>
      <div class='mod-embedded'>
        <div class='mod-header'>
          {{#if @model.statusIcon}}
            <span class='icon'>{{@model.statusIcon}}</span>
          {{/if}}
          <span class='name'>{{if @model.modName @model.modName 'Mod'}}</span>
          {{#if @model.statusSummary}}
            <span class='summary'>{{@model.statusSummary}}</span>
          {{/if}}
        </div>
        {{#if @model.modDescription}}
          <div class='mod-desc'>{{@model.modDescription}}</div>
        {{/if}}
      </div>

      <style scoped>
        .mod-embedded {
          padding: 0.5rem 0.75rem;
          background: var(--card, #fff);
          border: 1px solid var(--border, #e5e7eb);
          border-radius: var(--radius, 0.375rem);
        }

        .mod-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }

        .icon {
          font-size: 1rem;
        }

        .name {
          font-weight: 600;
          color: var(--foreground, #111827);
          font-size: 0.875rem;
        }

        .summary {
          margin-left: auto;
          font-size: 0.75rem;
          color: var(--muted-foreground, #6b7280);
          background: var(--muted, #f3f4f6);
          padding: 0.125rem 0.5rem;
          border-radius: 999px;
        }

        .mod-desc {
          margin-top: 0.25rem;
          font-size: 0.8125rem;
          color: var(--muted-foreground, #6b7280);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof AdventureMod> {
    <template>
      <div class='mod-fitted'>
        <div class='badge'>
          {{#if @model.statusIcon}}
            <span class='icon'>{{@model.statusIcon}}</span>
          {{else}}
            <span class='dot'></span>
          {{/if}}
          <span class='name'>{{if @model.modName @model.modName 'Mod'}}</span>
        </div>

        <div class='strip'>
          <span class='name'>{{if @model.modName @model.modName 'Mod'}}</span>
          {{#if @model.statusSummary}}
            <span class='summary'>{{@model.statusSummary}}</span>
          {{/if}}
        </div>

        <div class='tile'>
          <div class='tile-header'>
            {{#if @model.statusIcon}}
              <span class='icon'>{{@model.statusIcon}}</span>
            {{/if}}
            <span class='name'>{{if @model.modName @model.modName 'Mod'}}</span>
          </div>
          {{#if @model.modDescription}}
            <p class='desc'>{{@model.modDescription}}</p>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .mod-fitted {
          container-type: size;
          width: 100%;
          height: 100%;
        }

        .badge,
        .strip,
        .tile {
          display: none;
          width: 100%;
          height: 100%;
          padding: clamp(0.1875rem, 2%, 0.5rem);
          box-sizing: border-box;
        }

        @container (max-width: 150px) and (max-height: 76px) {
          .badge {
            display: flex;
            align-items: center;
            gap: 0.375rem;
          }
        }

        @container (min-width: 151px) and (max-height: 76px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.5rem;
          }
        }

        @container (min-height: 77px) {
          .tile {
            display: flex;
            flex-direction: column;
            gap: 0.25rem;
          }
        }

        .icon {
          font-size: 1rem;
        }

        .dot {
          width: 0.5rem;
          height: 0.5rem;
          border-radius: 50%;
          background: #10b981;
        }

        .name {
          font-weight: 600;
          font-size: 0.875rem;
          color: var(--foreground, #111827);
        }

        .summary {
          margin-left: auto;
          font-size: 0.75rem;
          color: var(--muted-foreground, #6b7280);
        }

        .tile-header {
          display: flex;
          align-items: center;
          gap: 0.375rem;
        }

        .desc {
          margin: 0;
          font-size: 0.8125rem;
          color: var(--muted-foreground, #6b7280);
          line-height: 1.35;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
      </style>
    </template>
  };
}
// touched for re-index
