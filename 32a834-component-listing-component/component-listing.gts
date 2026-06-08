import { on } from '@ember/modifier';
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import Component from '@glimmer/component'; // ¹
import { tracked } from '@glimmer/tracking'; // ²

// ³ Simple component listing Glimmer component
const components = [
  // ⁴
  {
    name: 'Button',
    description: 'A clickable button element',
    status: 'Stable',
  },
  { name: 'Input', description: 'Text input field', status: 'Stable' },
  { name: 'Modal', description: 'Overlay dialog window', status: 'Beta' },
  {
    name: 'Dropdown',
    description: 'Collapsible selection menu',
    status: 'Stable',
  },
  { name: 'Tooltip', description: 'Contextual hover hint', status: 'Draft' },
];

export default class ComponentListingComponent extends Component {
  // ⁵
  @tracked filter = '';

  get filteredComponents() {
    // ⁶
    const f = this.filter.toLowerCase();
    if (!f) return components;
    return components.filter(
      (c) =>
        c.name.toLowerCase().includes(f) ||
        c.description.toLowerCase().includes(f),
    );
  }

  updateFilter = (e: Event) => {
    // ⁷
    this.filter = (e.target as HTMLInputElement).value;
  };

  <template>
    <div class='component-listing'>
      <header class='listing-header'>
        <h1 class='listing-title'>Component Listing</h1>
        <input
          class='listing-search'
          type='text'
          placeholder='Search components...'
          value={{this.filter}}
          {{on 'input' this.updateFilter}}
        />
      </header>

      <div class='listing-count'>
        Showing
        {{this.filteredComponents.length}}
        of
        {{components.length}}
        components
      </div>

      {{#if this.filteredComponents.length}}
        <ul class='listing-grid'>
          {{#each this.filteredComponents as |comp|}}
            <li class='component-entry'>
              <div class='entry-header'>
                <span class='entry-name'>{{comp.name}}</span>
                <span
                  class='entry-status entry-status--{{comp.status}}'
                >{{comp.status}}</span>
              </div>
              <p class='entry-description'>{{comp.description}}</p>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <div class='empty-state'>
          <p>No components match your search.</p>
        </div>
      {{/if}}
    </div>

    <style scoped>
      /* ⁸ Layout */
      .component-listing {
        font-family: var(--font-sans, sans-serif);
        padding: var(--boxel-sp-xl, 1.5rem);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp, 1rem);
        background-color: var(--background, #fff);
        color: var(--foreground, #111);
        height: 100%;
        box-sizing: border-box;
      }

      /* ⁹ Header */
      .listing-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp, 1rem);
        flex-wrap: wrap;
      }
      .listing-title {
        font-size: var(--boxel-font-size-xl, 1.25rem);
        font-weight: 700;
        margin: 0;
      }
      .listing-search {
        padding: var(--boxel-sp-xs, 0.375rem) var(--boxel-sp-sm, 0.5rem);
        border: 1px solid var(--border, #ddd);
        border-radius: var(--boxel-border-radius, 0.375rem);
        font-size: var(--boxel-font-size-sm, 0.875rem);
        background-color: var(--input, #fff);
        color: var(--foreground, #111);
        min-width: 200px;
      }
      .listing-search:focus {
        outline: 2px solid var(--ring, #6366f1);
        outline-offset: 1px;
      }

      /* ¹⁰ Count */
      .listing-count {
        font-size: var(--boxel-font-size-xs, 0.75rem);
        color: var(--muted-foreground, #888);
      }

      /* ¹¹ Grid */
      .listing-grid {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(14rem, 1fr));
        gap: var(--boxel-sp, 1rem);
      }

      /* ¹² Entry card */
      .component-entry {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs, 0.375rem);
        padding: var(--boxel-sp, 1rem);
        background-color: var(--card, #fff);
        color: var(--card-foreground, #111);
        border: 1px solid var(--border, #ddd);
        border-radius: var(--boxel-border-radius, 0.375rem);
        box-shadow: var(--shadow-sm, 0 1px 2px rgba(0, 0, 0, 0.05));
      }
      .entry-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs, 0.375rem);
      }
      .entry-name {
        font-size: var(--boxel-font-size-sm, 0.875rem);
        font-weight: 600;
      }
      .entry-description {
        font-size: var(--boxel-font-size-xs, 0.75rem);
        color: var(--muted-foreground, #888);
        margin: 0;
        line-height: 1.4;
      }

      /* ¹³ Status badges */
      .entry-status {
        font-size: 0.65rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        padding: 2px 6px;
        border-radius: var(--boxel-border-radius-xs, 0.25rem);
        background-color: var(--muted, #f1f5f9);
        color: var(--muted-foreground, #64748b);
      }
      .entry-status--Stable {
        background-color: #dcfce7;
        color: #15803d;
      }
      .entry-status--Beta {
        background-color: #fef9c3;
        color: #a16207;
      }
      .entry-status--Draft {
        background-color: #fee2e2;
        color: #b91c1c;
      }

      /* ¹⁴ Empty state */
      .empty-state {
        padding: var(--boxel-sp-xl, 1.5rem);
        text-align: center;
        color: var(--muted-foreground, #888);
        font-size: var(--boxel-font-size-sm, 0.875rem);
      }
    </style>
  </template>
}
