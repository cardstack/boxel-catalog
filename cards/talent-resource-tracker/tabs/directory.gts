import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import { Employee } from '../../hr/employee';
import CardList from '@cardstack/base/components/card-list';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Input } from '@cardstack/pretui/components/input';
import type { TrackerView } from '../talent-resource-tracker';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class DirectoryTab extends GlimmerComponent<Signature> {
  setDirectoryView = (view: 'grid' | 'strip') => {
    this.args.tracker.directoryView = view;
  };

  get departments(): string[] {
    let seen = new Set<string>();
    for (let employee of this.args.tracker.employees) {
      if (employee.department) {
        seen.add(employee.department);
      }
    }
    return [...seen].sort();
  }

  setDirectoryDept = (dept: string) => {
    this.args.tracker.directoryDept = dept;
  };

  setDirectorySearch = (value: string) => {
    this.args.tracker.debouncedSetDirectorySearch(value);
  };

  <template>
    <div class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Directory</h2>
          <p class='byline'>Every standing entry, searchable</p>
        </div>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            class='btn-review'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew Employee)}}
          >+ Add employee</Button>
        {{/if}}
      </div>
      <div class='directory-filters'>
        <div class='directory-search'>
          <Input
            @type='search'
            @value={{@tracker.directorySearch}}
            @placeholder='Search employees…'
            @onInput={{this.setDirectorySearch}}
            aria-label='Search employees'
          />
        </div>
        <div class='directory-chips'>
          <Button
            type='button'
            @tone='neutral'
            @appearance={{if
              (eq @tracker.directoryDept 'all')
              'filled'
              'outlined'
            }}
            class='chip {{if (eq @tracker.directoryDept "all") "active"}}'
            {{on 'click' (fn this.setDirectoryDept 'all')}}
          >All</Button>
          {{#each this.departments as |dept|}}
            <Button
              type='button'
              @tone='neutral'
              @appearance={{if
                (eq @tracker.directoryDept dept)
                'filled'
                'outlined'
              }}
              class='chip {{if (eq @tracker.directoryDept dept) "active"}}'
              {{on 'click' (fn this.setDirectoryDept dept)}}
            >{{dept}}</Button>
          {{/each}}
        </div>
        <div class='view-toggle' role='group' aria-label='View'>
          <IconButton
            type='button'
            class='view-btn {{if (eq @tracker.directoryView "grid") "active"}}'
            @label='Grid view'
            {{on 'click' (fn this.setDirectoryView 'grid')}}
          ><LayoutGridIcon class='view-icon' /></IconButton>
          <IconButton
            type='button'
            class='view-btn {{if (eq @tracker.directoryView "strip") "active"}}'
            @label='List view'
            {{on 'click' (fn this.setDirectoryView 'strip')}}
          ><ListIcon class='view-icon' /></IconButton>
        </div>
      </div>
      <CardList
        class='directory'
        @query={{@tracker.employeeQuery}}
        @realms={{@tracker.realms}}
        @context={{@context}}
        @format='fitted'
        @viewOption={{@tracker.directoryView}}
      />
    </div>
    <style scoped>
      .sec-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp);
        padding-bottom: var(--boxel-sp);
        border-bottom: 2px solid var(--card-foreground);
        margin: 0 0 var(--boxel-sp-lg);
      }
      .sec-head .htext {
        margin-right: auto;
      }
      .sec-head .htext h2 {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 20px;
        margin: 0 0 3px;
      }
      .sec-head .htext .byline {
        font-family: var(--font-mono);
        font-size: 11.5px;
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0;
      }
      .btn-review {
        font-family: var(--font-mono);
        font-size: 11.5px;
        font-weight: 700;
      }
      .review-queue-item.on {
        background: var(--muted);
      }
      .stage-act:focus-visible,
      .screen-btn:focus-visible,
      .chip:focus-visible,
      .account-row:focus-visible,
      .rail-link:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
      }
      .tab-section {
        animation: tracker-tab-fade-in 0.2s ease-out;
      }
      @keyframes tracker-tab-fade-in {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .tab-section {
          animation: none;
        }
      }
      .btn-review {
        font-size: 10px;
        margin-bottom: var(--boxel-sp-5xs);
      }
      .directory-filters {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp);
        margin-bottom: var(--boxel-sp);
      }
      .directory-search {
        flex: 1;
        min-width: 12rem;
        max-width: 20rem;
      }
      .directory-chips {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
      }
      .chip {
        font-family: var(--font-sans);
        font-size: 11.5px;
        font-weight: 600;
        text-transform: capitalize;
        transition:
          background-color 0.15s ease-out,
          color 0.15s ease-out,
          border-color 0.15s ease-out;
      }
      .view-toggle {
        display: flex;
        margin-left: auto;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
        flex: none;
      }
      .view-btn {
        --boxel-icon-button-width: 2rem;
        --boxel-icon-button-height: 2rem;
        --boxel-icon-button-background: var(--card);
        --boxel-icon-button-color: var(--muted-foreground);
        border: none;
        border-radius: 0;
        transition:
          background-color 0.15s ease-out,
          color 0.15s ease-out;
      }
      .view-btn + .view-btn {
        border-left: 1px solid var(--border);
      }
      .view-btn:hover {
        --boxel-icon-button-color: var(--card-foreground);
      }
      .view-btn.active {
        --boxel-icon-button-background: var(--card-foreground);
        --boxel-icon-button-color: var(--card);
      }
      .view-icon {
        width: 1rem;
        height: 1rem;
      }
      .directory {
        --embedded-card-min-height: 65px;
      }
      .tab-section > .directory.grid-view {
        --item-width: auto;
        --item-height: 14rem;
        grid-template-columns: repeat(auto-fill, minmax(13rem, 1fr));
      }
      .sec-head {
        flex: none;
      }
      @keyframes action-busy-pulse {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.55;
        }
      }
    </style>
  </template>
}
