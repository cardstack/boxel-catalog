import { and } from '@cardstack/boxel-ui/helpers';
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  field,
  contains,
  containsMany,
  Component,
} from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string'; // ²
import NumberField from 'https://cardstack.com/base/number'; // ³
import TextAreaField from 'https://cardstack.com/base/text-area'; // ⁴
import MarkdownField from 'https://cardstack.com/base/markdown'; // ⁵
import enumField from 'https://cardstack.com/base/enum'; // ⁶
import UtensilsIcon from '@cardstack/boxel-icons/utensils'; // ⁷

// ¹¹ Difficulty enum
const DifficultyField = enumField(StringField, {
  options: ['Easy', 'Medium', 'Hard', 'Expert'],
});

// ¹² Ingredient field definition
export class IngredientField extends FieldDef {
  // ¹³
  static displayName = 'Ingredient';

  @field name = contains(StringField); // ¹⁴
  @field amount = contains(StringField); // ¹⁵
  @field unit = contains(StringField); // ¹⁶
  @field notes = contains(StringField); // ¹⁷

  static embedded = class Embedded extends Component<typeof IngredientField> {
    // ¹⁸
    <template>
      <li class='ingredient-item'>
        <span class='ingredient-amount'>{{if
            @model.amount
            @model.amount
            ''
          }}</span>
        <span class='ingredient-unit'>{{if @model.unit @model.unit ''}}</span>
        <span class='ingredient-name'>{{if
            @model.name
            @model.name
            'Unnamed ingredient'
          }}</span>
        {{#if @model.notes}}
          <span class='ingredient-notes'>({{@model.notes}})</span>
        {{/if}}
      </li>
      <style scoped>
        .ingredient-item {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
          padding: var(--boxel-sp-4xs) 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
        .ingredient-amount {
          font-weight: 600;
          min-width: 2rem;
          color: var(--primary);
        }
        .ingredient-unit {
          color: var(--muted-foreground);
          min-width: 2.5rem;
        }
        .ingredient-name {
          flex: 1;
        }
        .ingredient-notes {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          font-style: italic;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof IngredientField> {
    // ¹⁹
    <template>
      <span>{{if @model.amount @model.amount ''}}
        {{if @model.unit @model.unit ''}}
        {{if @model.name @model.name 'Ingredient'}}</span>
    </template>
  };
}

// ²⁰ Main recipe card
export class RecipeCard extends CardDef {
  // ²¹
  static displayName = 'Recipe';
  static icon = UtensilsIcon; // ²²
  static prefersWideFormat = true; // ²³

  @field recipeName = contains(StringField); // ²⁴
  @field description = contains(TextAreaField); // ²⁵
  @field prepTime = contains(NumberField); // ²⁶ in minutes
  @field cookTime = contains(NumberField); // ²⁷ in minutes
  @field servings = contains(NumberField); // ²⁸
  @field difficulty = contains(DifficultyField); // ²⁹
  @field cuisine = contains(StringField); // ³⁰
  @field ingredients = containsMany(IngredientField); // ³¹
  @field instructions = contains(MarkdownField); // ³²
  @field tips = contains(TextAreaField); // ³³
  @field tags = containsMany(StringField); // ³⁴

  @field cardTitle = contains(StringField, {
    // ³⁵
    computeVia: function (this: RecipeCard) {
      return this.cardInfo?.name ?? this.recipeName ?? 'Untitled Recipe';
    },
  });

  // ³⁶ Total time computed
  get totalTimeDisplay() {
    // ³⁷
    try {
      const prep = this.prepTime ?? 0;
      const cook = this.cookTime ?? 0;
      const total = prep + cook;
      if (total === 0) return null;
      if (total >= 60) {
        const hours = Math.floor(total / 60);
        const mins = total % 60;
        return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
      }
      return `${total}m`;
    } catch (e) {
      return null;
    }
  }

  // ³⁸ Isolated format
  static isolated = class Isolated extends Component<typeof RecipeCard> {
    get prepDisplay() {
      // ³⁹
      try {
        const v = this.args.model?.prepTime;
        if (!v) return null;
        return v >= 60
          ? `${Math.floor(v / 60)}h ${v % 60 > 0 ? (v % 60) + 'm' : ''}`.trim()
          : `${v}m`;
      } catch (e) {
        return null;
      }
    }

    get cookDisplay() {
      // ⁴⁰
      try {
        const v = this.args.model?.cookTime;
        if (!v) return null;
        return v >= 60
          ? `${Math.floor(v / 60)}h ${v % 60 > 0 ? (v % 60) + 'm' : ''}`.trim()
          : `${v}m`;
      } catch (e) {
        return null;
      }
    }

    get totalDisplay() {
      // ⁴¹
      try {
        const prep = this.args.model?.prepTime ?? 0;
        const cook = this.args.model?.cookTime ?? 0;
        const total = prep + cook;
        if (total === 0) return null;
        return total >= 60
          ? `${Math.floor(total / 60)}h ${total % 60 > 0 ? (total % 60) + 'm' : ''}`.trim()
          : `${total}m`;
      } catch (e) {
        return null;
      }
    }

    get difficultyColor() {
      // ⁴²
      const map: Record<string, string> = {
        Easy: 'var(--chart-2)',
        Medium: 'var(--chart-3)',
        Hard: 'var(--chart-4)',
        Expert: 'var(--chart-1)',
      };
      return (
        map[this.args.model?.difficulty ?? ''] ?? 'var(--muted-foreground)'
      );
    }

    <template>
      <article class='recipe-isolated'>
        {{! Header }}
        <header class='recipe-header'>
          <div class='recipe-title-group'>
            <h1 class='recipe-title'>{{if
                @model.recipeName
                @model.recipeName
                'Untitled Recipe'
              }}</h1>
            {{#if @model.cuisine}}
              <span class='recipe-cuisine'>{{@model.cuisine}}</span>
            {{/if}}
          </div>
          {{#if @model.description}}
            <p class='recipe-description'><@fields.description /></p>
          {{/if}}
        </header>

        {{! Stats bar }}
        <div class='recipe-stats'>
          {{#if this.prepDisplay}}
            <div class='stat-item'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
                class='stat-icon'
              ><circle cx='12' cy='12' r='10' /><polyline
                  points='12 6 12 12 16 14'
                /></svg>
              <div class='stat-info'>
                <span class='stat-label'>Prep</span>
                <span class='stat-value'>{{this.prepDisplay}}</span>
              </div>
            </div>
          {{/if}}
          {{#if this.cookDisplay}}
            <div class='stat-item'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
                class='stat-icon'
              ><path
                  d='M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10S17.5 2 12 2'
                /><path d='M12 6v6l4 2' /></svg>
              <div class='stat-info'>
                <span class='stat-label'>Cook</span>
                <span class='stat-value'>{{this.cookDisplay}}</span>
              </div>
            </div>
          {{/if}}
          {{#if this.totalDisplay}}
            <div class='stat-item stat-total'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
                class='stat-icon'
              ><circle cx='12' cy='12' r='10' /><path d='M12 8v4l3 3' /></svg>
              <div class='stat-info'>
                <span class='stat-label'>Total</span>
                <span class='stat-value'>{{this.totalDisplay}}</span>
              </div>
            </div>
          {{/if}}
          {{#if @model.servings}}
            <div class='stat-item'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
                class='stat-icon'
              ><path d='M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2' /><circle
                  cx='9'
                  cy='7'
                  r='4'
                /><path d='M23 21v-2a4 4 0 0 0-3-3.87' /><path
                  d='M16 3.13a4 4 0 0 1 0 7.75'
                /></svg>
              <div class='stat-info'>
                <span class='stat-label'>Serves</span>
                <span class='stat-value'>{{@model.servings}}</span>
              </div>
            </div>
          {{/if}}
          {{#if @model.difficulty}}
            <div class='stat-item'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
                class='stat-icon'
              ><path
                  d='M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z'
                /></svg>
              <div class='stat-info'>
                <span class='stat-label'>Difficulty</span>
                <span
                  class='stat-value stat-difficulty'
                  style='color: {{this.difficultyColor}}'
                >{{@model.difficulty}}</span>
              </div>
            </div>
          {{/if}}
        </div>

        {{! Body: ingredients + instructions }}
        <div class='recipe-body'>
          {{! Ingredients sidebar }}
          <aside class='recipe-ingredients'>
            <h2 class='section-heading'>Ingredients</h2>
            {{#if @model.ingredients.length}}
              <ul class='ingredients-list'>
                <@fields.ingredients @format='embedded' />
              </ul>
            {{else}}
              <p class='empty-state'>No ingredients added yet.</p>
            {{/if}}
          </aside>

          {{! Instructions main }}
          <main class='recipe-instructions'>
            <h2 class='section-heading'>Instructions</h2>
            {{#if @model.instructions}}
              <div class='instructions-content'>
                <@fields.instructions />
              </div>
            {{else}}
              <p class='empty-state'>No instructions added yet. Edit this card
                to add your steps.</p>
            {{/if}}

            {{#if @model.tips}}
              <div class='recipe-tips'>
                <h3 class='tips-heading'>
                  <svg
                    width='16'
                    height='16'
                    viewBox='0 0 24 24'
                    fill='none'
                    stroke='currentColor'
                    stroke-width='2'
                  ><circle cx='12' cy='12' r='10' /><line
                      x1='12'
                      y1='8'
                      x2='12'
                      y2='12'
                    /><line x1='12' y1='16' x2='12.01' y2='16' /></svg>
                  Tips &amp; Notes
                </h3>
                <p class='tips-text'><@fields.tips /></p>
              </div>
            {{/if}}
          </main>
        </div>

        {{! Tags }}
        {{#if @model.tags.length}}
          <footer class='recipe-footer'>
            <div class='tags-container'>
              {{#each @model.tags as |tag|}}
                <span class='tag'>{{tag}}</span>
              {{/each}}
            </div>
          </footer>
        {{/if}}
      </article>

      <style scoped>
        /* ⁴³ Isolated styles */
        .recipe-isolated {
          container-type: inline-size;
          height: 100%;
          overflow-y: auto;
          background-color: var(--background);
          color: var(--foreground);
          font-family: var(--font-sans);
          display: flex;
          flex-direction: column;
          box-sizing: border-box;
        }

        /* Header */
        .recipe-header {
          padding: var(--boxel-sp-xl) var(--boxel-sp-xl) var(--boxel-sp-lg);
          background: linear-gradient(
            135deg,
            var(--card) 0%,
            var(--muted) 100%
          );
          border-bottom: 1px solid var(--border);
        }
        .recipe-title-group {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-sm);
          flex-wrap: wrap;
          margin-bottom: var(--boxel-sp-xs);
        }
        .recipe-title {
          font-size: var(--boxel-font-size-xl);
          font-weight: 800;
          margin: 0;
          letter-spacing: var(--boxel-lsp-xs);
          color: var(--foreground);
        }
        .recipe-cuisine {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: var(--boxel-lsp-lg);
          color: var(--muted-foreground);
          background-color: var(--secondary);
          padding: 2px var(--boxel-sp-xs);
          border-radius: var(--boxel-border-radius-xs);
        }
        .recipe-description {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          line-height: 1.5;
          margin: 0;
        }

        /* Stats bar */
        .recipe-stats {
          display: flex;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-sm) var(--boxel-sp-xl);
          background-color: var(--card);
          border-bottom: 1px solid var(--border);
          flex-wrap: wrap;
        }
        .stat-item {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-radius: var(--boxel-border-radius-sm);
          border: 1px solid var(--border);
          background-color: var(--background);
          flex: 1;
          min-width: 5rem;
        }
        .stat-total {
          border-color: var(--primary);
          background-color: var(--primary);
        }
        .stat-total .stat-icon,
        .stat-total .stat-label,
        .stat-total .stat-value {
          color: var(--primary-foreground);
        }
        .stat-icon {
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .stat-info {
          display: flex;
          flex-direction: column;
        }
        .stat-label {
          font-size: 0.625rem;
          text-transform: uppercase;
          letter-spacing: var(--boxel-lsp-lg);
          color: var(--muted-foreground);
          font-weight: 600;
        }
        .stat-value {
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          color: var(--foreground);
        }

        /* Body layout */
        .recipe-body {
          display: grid;
          grid-template-columns: 16rem 1fr;
          gap: 0;
          flex: 1;
          min-height: 0;
        }

        /* Ingredients sidebar */
        .recipe-ingredients {
          padding: var(--boxel-sp-lg) var(--boxel-sp);
          background-color: var(--sidebar);
          color: var(--sidebar-foreground);
          border-right: 1px solid var(--sidebar-border);
        }
        .ingredients-list {
          list-style: none;
          margin: 0;
          padding: 0;
        }
        .ingredients-list > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0;
        }

        /* Instructions */
        .recipe-instructions {
          padding: var(--boxel-sp-lg) var(--boxel-sp-xl);
          background-color: var(--background);
          overflow-y: auto;
        }
        .instructions-content {
          font-size: var(--boxel-font-size-sm);
          line-height: 1.6;
          color: var(--foreground);
        }

        /* Tips */
        .recipe-tips {
          margin-top: var(--boxel-sp-xl);
          padding: var(--boxel-sp);
          background-color: var(--accent);
          border-radius: var(--boxel-border-radius);
          border-left: 3px solid var(--primary);
        }
        .tips-heading {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          margin: 0 0 var(--boxel-sp-xs);
          color: var(--accent-foreground);
        }
        .tips-text {
          font-size: var(--boxel-font-size-sm);
          color: var(--accent-foreground);
          margin: 0;
          line-height: 1.5;
        }

        /* Section headings */
        .section-heading {
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: var(--boxel-lsp-lg);
          margin: 0 0 var(--boxel-sp-sm);
          color: var(--muted-foreground);
        }

        /* Empty states */
        .empty-state {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          font-style: italic;
          margin: 0;
        }

        /* Tags footer */
        .recipe-footer {
          padding: var(--boxel-sp-sm) var(--boxel-sp-xl);
          border-top: 1px solid var(--border);
          background-color: var(--card);
        }
        .tags-container {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .tag {
          font-size: var(--boxel-font-size-xs);
          padding: 2px var(--boxel-sp-xs);
          background-color: var(--secondary);
          color: var(--secondary-foreground);
          border-radius: var(--boxel-border-radius-xs);
          font-weight: 500;
        }

        /* Responsive */
        @container (max-width: 640px) {
          .recipe-body {
            grid-template-columns: 1fr;
          }
          .recipe-ingredients {
            border-right: none;
            border-bottom: 1px solid var(--sidebar-border);
          }
          .recipe-stats {
            padding: var(--boxel-sp-sm);
          }
          .recipe-header {
            padding: var(--boxel-sp) var(--boxel-sp-sm);
          }
        }
      </style>
    </template>
  };

  // ⁴⁴ Embedded format
  static embedded = class Embedded extends Component<typeof RecipeCard> {
    get totalDisplay() {
      // ⁴⁵
      try {
        const prep = this.args.model?.prepTime ?? 0;
        const cook = this.args.model?.cookTime ?? 0;
        const total = prep + cook;
        if (total === 0) return null;
        return total >= 60
          ? `${Math.floor(total / 60)}h ${total % 60 > 0 ? (total % 60) + 'm' : ''}`.trim()
          : `${total}m`;
      } catch (e) {
        return null;
      }
    }

    <template>
      <div class='recipe-embedded'>
        <div class='embedded-info'>
          <h3 class='embedded-title'>{{if
              @model.recipeName
              @model.recipeName
              'Untitled Recipe'
            }}</h3>
          <div class='embedded-meta'>
            {{#if @model.cuisine}}
              <span class='meta-tag'>{{@model.cuisine}}</span>
            {{/if}}
            {{#if @model.difficulty}}
              <span class='meta-tag'>{{@model.difficulty}}</span>
            {{/if}}
          </div>
          {{#if @model.description}}
            <p class='embedded-desc'><@fields.description /></p>
          {{/if}}
        </div>
        <div class='embedded-stats'>
          {{#if this.totalDisplay}}
            <span class='stat-badge'>
              <svg
                width='12'
                height='12'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><circle cx='12' cy='12' r='10' /><polyline
                  points='12 6 12 12 16 14'
                /></svg>
              {{this.totalDisplay}}
            </span>
          {{/if}}
          {{#if @model.servings}}
            <span class='stat-badge'>
              <svg
                width='12'
                height='12'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path d='M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2' /><circle
                  cx='9'
                  cy='7'
                  r='4'
                /></svg>
              {{@model.servings}}
              servings
            </span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .recipe-embedded {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          background-color: var(--card);
          color: var(--card-foreground);
          border-radius: var(--boxel-border-radius);
        }
        .embedded-title {
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          margin: 0;
        }
        .embedded-meta {
          display: flex;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .meta-tag {
          font-size: var(--boxel-font-size-xs);
          padding: 1px var(--boxel-sp-2xs);
          background-color: var(--secondary);
          color: var(--secondary-foreground);
          border-radius: var(--boxel-border-radius-xxs);
        }
        .embedded-desc {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          margin: 0;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .embedded-stats {
          display: flex;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .stat-badge {
          display: inline-flex;
          align-items: center;
          gap: 3px;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  // ⁴⁶ Fitted format
  static fitted = class Fitted extends Component<typeof RecipeCard> {
    get totalDisplay() {
      // ⁴⁷
      try {
        const prep = this.args.model?.prepTime ?? 0;
        const cook = this.args.model?.cookTime ?? 0;
        const total = prep + cook;
        if (total === 0) return null;
        return total >= 60
          ? `${Math.floor(total / 60)}h ${total % 60 > 0 ? (total % 60) + 'm' : ''}`.trim()
          : `${total}m`;
      } catch (e) {
        return null;
      }
    }

    <template>
      {{! Badge: ≤150px wide, <170px tall }}
      <div class='badge'>
        <svg
          width='24'
          height='24'
          viewBox='0 0 24 24'
          fill='none'
          stroke='currentColor'
          stroke-width='1.5'
          class='badge-icon'
        ><path d='M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2' /><path
            d='M7 2v20'
          /><path d='M21 15V2' /><path
            d='M18 15c-2.8 0-5 2.2-5 5s2.2 5 5 5 5-2.2 5-5-2.2-5-5-5z'
          /><path d='M21 18h-6' /></svg>
        <span class='badge-title'>{{if
            @model.recipeName
            @model.recipeName
            'Recipe'
          }}</span>
      </div>

      {{! Strip: >150px wide, <170px tall }}
      <div class='strip'>
        <div class='strip-icon'>
          <svg
            width='20'
            height='20'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          ><path d='M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2' /><path
              d='M7 2v20'
            /></svg>
        </div>
        <div class='strip-content'>
          <span class='strip-title'>{{if
              @model.recipeName
              @model.recipeName
              'Untitled Recipe'
            }}</span>
          <span class='strip-meta'>
            {{if @model.cuisine @model.cuisine ''}}
            {{#if (and @model.cuisine this.totalDisplay)}} · {{/if}}
            {{if this.totalDisplay this.totalDisplay ''}}
            {{#if @model.difficulty}} · {{@model.difficulty}}{{/if}}
          </span>
        </div>
      </div>

      {{! Tile: <400px wide, ≥170px tall }}
      <div class='tile'>
        <div class='tile-header'>
          <div class='tile-icon-wrap'>
            <svg
              width='28'
              height='28'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='1.5'
            ><path d='M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2' /><path
                d='M7 2v20'
              /><path d='M21 15V2' /><path
                d='M18 15c-2.8 0-5 2.2-5 5s2.2 5 5 5 5-2.2 5-5-2.2-5-5-5z'
              /></svg>
          </div>
          {{#if @model.difficulty}}
            <span class='tile-difficulty'>{{@model.difficulty}}</span>
          {{/if}}
        </div>
        <h3 class='tile-title'>{{if
            @model.recipeName
            @model.recipeName
            'Untitled Recipe'
          }}</h3>
        {{#if @model.cuisine}}
          <span class='tile-cuisine'>{{@model.cuisine}}</span>
        {{/if}}
        <div class='tile-stats'>
          {{#if this.totalDisplay}}
            <span class='tile-stat'>
              <svg
                width='11'
                height='11'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><circle cx='12' cy='12' r='10' /><polyline
                  points='12 6 12 12 16 14'
                /></svg>
              {{this.totalDisplay}}
            </span>
          {{/if}}
          {{#if @model.servings}}
            <span class='tile-stat'>
              <svg
                width='11'
                height='11'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path d='M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2' /><circle
                  cx='9'
                  cy='7'
                  r='4'
                /></svg>
              {{@model.servings}}
            </span>
          {{/if}}
          {{#if @model.ingredients.length}}
            <span class='tile-stat'>{{@model.ingredients.length}}
              ingredients</span>
          {{/if}}
        </div>
      </div>

      {{! Card: ≥400px wide, ≥170px tall }}
      <div class='card'>
        <div class='card-left'>
          <div class='card-icon-wrap'>
            <svg
              width='32'
              height='32'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='1.5'
            ><path d='M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2' /><path
                d='M7 2v20'
              /><path d='M21 15V2' /><path
                d='M18 15c-2.8 0-5 2.2-5 5s2.2 5 5 5 5-2.2 5-5-2.2-5-5-5z'
              /><path d='M21 18h-6' /></svg>
          </div>
        </div>
        <div class='card-body'>
          <div class='card-title-row'>
            <h3 class='card-title'>{{if
                @model.recipeName
                @model.recipeName
                'Untitled Recipe'
              }}</h3>
            {{#if @model.difficulty}}
              <span class='card-difficulty'>{{@model.difficulty}}</span>
            {{/if}}
          </div>
          {{#if @model.cuisine}}
            <span class='card-cuisine'>{{@model.cuisine}}</span>
          {{/if}}
          {{#if @model.description}}
            <p class='card-desc'>{{@model.description}}</p>
          {{/if}}
          <div class='card-meta'>
            {{#if this.totalDisplay}}
              <span class='card-stat'>
                <svg
                  width='12'
                  height='12'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                ><circle cx='12' cy='12' r='10' /><polyline
                    points='12 6 12 12 16 14'
                  /></svg>
                {{this.totalDisplay}}
              </span>
            {{/if}}
            {{#if @model.servings}}
              <span class='card-stat'>
                <svg
                  width='12'
                  height='12'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                ><path d='M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2' /><circle
                    cx='9'
                    cy='7'
                    r='4'
                  /></svg>
                {{@model.servings}}
                servings
              </span>
            {{/if}}
            {{#if @model.ingredients.length}}
              <span class='card-stat'>{{@model.ingredients.length}}
                ingredients</span>
            {{/if}}
          </div>
        </div>
      </div>

      <style scoped>
        /* ⁴⁸ Fitted sub-format defaults - hide all */
        .badge,
        .strip,
        .tile,
        .card {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
        }

        /* Badge */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: var(--boxel-sp-xs);
            padding: var(--boxel-sp-xs);
            text-align: center;
          }
        }
        .badge-icon {
          color: var(--primary);
        }
        .badge-title {
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }

        /* Strip */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
        }
        .strip-icon {
          display: flex;
          align-items: center;
          justify-content: center;
          width: 2rem;
          height: 2rem;
          background-color: var(--primary);
          color: var(--primary-foreground);
          border-radius: var(--boxel-border-radius-xs);
          flex-shrink: 0;
        }
        .strip-content {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .strip-title {
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .strip-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        /* Tile */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            padding: var(--boxel-sp-sm);
            gap: var(--boxel-sp-3xs);
          }
        }
        .tile-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
        }
        .tile-icon-wrap {
          color: var(--primary);
        }
        .tile-difficulty {
          font-size: 0.625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: var(--boxel-lsp-lg);
          color: var(--muted-foreground);
          background-color: var(--muted);
          padding: 1px var(--boxel-sp-3xs);
          border-radius: var(--boxel-border-radius-xxs);
        }
        .tile-title {
          font-size: var(--boxel-font-size-sm);
          font-weight: 800;
          margin: 0;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
          line-height: 1.2;
        }
        .tile-cuisine {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .tile-stats {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          margin-top: auto;
        }
        .tile-stat {
          display: inline-flex;
          align-items: center;
          gap: 3px;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          background-color: var(--muted);
          padding: 2px var(--boxel-sp-3xs);
          border-radius: var(--boxel-border-radius-xxs);
        }

        /* Card */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-sm) var(--boxel-sp);
            align-items: flex-start;
          }
        }
        .card-left {
          flex-shrink: 0;
        }
        .card-icon-wrap {
          display: flex;
          align-items: center;
          justify-content: center;
          width: 3rem;
          height: 3rem;
          background-color: var(--primary);
          color: var(--primary-foreground);
          border-radius: var(--boxel-border-radius);
        }
        .card-body {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-3xs);
        }
        .card-title-row {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .card-title {
          font-size: var(--boxel-font-size);
          font-weight: 800;
          margin: 0;
        }
        .card-difficulty {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--muted-foreground);
          background-color: var(--muted);
          padding: 1px var(--boxel-sp-3xs);
          border-radius: var(--boxel-border-radius-xxs);
          text-transform: uppercase;
          letter-spacing: var(--boxel-lsp-sm);
        }
        .card-cuisine {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .card-desc {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          margin: 0;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
          line-height: 1.4;
        }
        .card-meta {
          display: flex;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
          margin-top: var(--boxel-sp-3xs);
        }
        .card-stat {
          display: inline-flex;
          align-items: center;
          gap: 3px;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
