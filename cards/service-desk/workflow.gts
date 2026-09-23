import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import RouteIcon from '@cardstack/boxel-icons/route';

import {
  WorkflowStateField,
  workflowKindColor,
} from '@cardstack/catalog/fields/workflow-state/workflow-state-field';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { EditSectionNav } from '@cardstack/catalog/components/edit-section-nav';

export const TRANSITION_GUARDS = [
  'none',
  'requires-note',
  'requires-role',
] as const;

export const TransitionGuardField = enumField(StringField, {
  displayName: 'Transition Guard',
  options: TRANSITION_GUARDS as unknown as string[],
});

/** One allowed move between two state keys, with its guard. */
export class TransitionField extends FieldDef {
  static displayName = 'Transition';

  @field from = contains(StringField, { description: 'State key.' });
  @field to = contains(StringField, { description: 'State key.' });
  @field guard = contains(TransitionGuardField);
  @field guardRoleName = contains(StringField, {
    description: 'Role required, when guard is requires-role.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: TransitionField) {
      let g = this.guard && this.guard !== 'none' ? ` (${this.guard})` : '';
      return `${this.from ?? '?'} → ${this.to ?? '?'}${g}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <code class='transition'>{{@model.title}}</code>
      <style scoped>
        .transition {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

class WorkflowEdit extends Component<typeof Workflow> {
  @tracked activeSection = 'identity';

  sections = [
    { id: 'identity', label: 'Workflow' },
    { id: 'process', label: 'States & transitions' },
  ];

  goTo = (id: string, event: Event) => {
    this.activeSection = id;
    let root = (event.currentTarget as HTMLElement).closest('.wf-edit');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='wf-edit'>
      <div class='edit-body'>
        <EditSectionNav
          @sections={{this.sections}}
          @activeId={{this.activeSection}}
          @onSelect={{this.goTo}}
          class='sect-nav'
        />
        <div class='sects'>
          <section
            class='sect {{if (eq this.activeSection "identity") "focused"}}'
            data-sect='identity'
          >
            <h3>Workflow
              <span class='sect-hint'>bump the version when states change — keys
                are never renamed</span></h3>
            <FieldContainer @label='Name' @vertical={{true}}>
              <@fields.name />
            </FieldContainer>
            <FieldContainer @label='Applies to' @vertical={{true}}>
              <@fields.appliesTo />
            </FieldContainer>
            <FieldContainer @label='Version' @vertical={{true}}>
              <@fields.version />
            </FieldContainer>
          </section>
          <section
            class='sect {{if (eq this.activeSection "process") "focused"}}'
            data-sect='process'
          >
            <h3>States & transitions
              <span class='sect-hint'>waiting-kind states pause SLA clocks</span></h3>
            <FieldContainer @label='States (in order)' @vertical={{true}}>
              <@fields.states />
            </FieldContainer>
            <FieldContainer @label='Transitions' @vertical={{true}}>
              <@fields.transitions />
            </FieldContainer>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .wf-edit {
        container-type: inline-size;
      }
      .edit-body {
        display: grid;
        grid-template-columns: 10rem 1fr;
        gap: var(--boxel-sp);
        align-items: start;
      }
      @container (width < 34rem) {
        .edit-body {
          grid-template-columns: 1fr;
        }
      }
      .sects {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .sect {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        border: 1px solid var(--border, var(--boxel-border-color));
        border-radius: var(--boxel-border-radius);
        background: var(--card, var(--boxel-light));
        padding: var(--boxel-sp-sm);
        scroll-margin-top: var(--boxel-sp);
      }
      .sect.focused {
        border-color: var(--primary, var(--boxel-highlight));
      }
      .sect h3 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--muted-foreground, var(--boxel-450));
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
      }
      .sect-hint {
        text-transform: none;
        letter-spacing: 0;
        font-weight: 400;
        font-style: italic;
      }
    </style>
  </template>
}

/**
 * A team's PROCESS as an editable card: ordered states, guarded
 * transitions. An ops lead adds a "waiting-on-legal" state without an
 * engineer; the Run Workflow command is the single writer that enforces it.
 *
 * VERSIONING RULE: changing `states` or `transitions` after instances run on
 * them is a migration — bump `version` and leave the old keys valid. Keys are
 * never renamed once in use (see WorkflowStateField).
 */
export class Workflow extends CardDef {
  static displayName = 'Workflow';
  static icon = RouteIcon;

  @field name = contains(StringField);
  @field appliesTo = contains(StringField, {
    description: 'Informational card-type name this flow is meant for.',
  });
  @field states = containsMany(WorkflowStateField);
  @field transitions = containsMany(TransitionField);
  @field version = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: Workflow) {
      return this.version
        ? `${this.name ?? 'Workflow'} ${this.version}`
        : (this.name ?? 'Workflow');
    },
  });

  /** Is `from → to` allowed, and behind which guard? */
  findTransition(from?: string | null, to?: string | null) {
    return (this.transitions ?? []).find((t) => t.from === from && t.to === to);
  }

  stateByKey(key?: string | null) {
    return (this.states ?? []).find((s) => s.key === key);
  }

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class='wf-page'>
        <header>
          <h1><@fields.title /></h1>
          {{#if @model.appliesTo}}
            <p class='wf-applies'>for {{@model.appliesTo}} records</p>
          {{/if}}
        </header>
        <section>
          <h2>States (in order)</h2>
          <div class='wf-states'><@fields.states /></div>
        </section>
        <section>
          <h2>Allowed transitions</h2>
          {{#if @model.transitions.length}}
            <ul class='wf-transitions'>
              {{#each @model.transitions as |t|}}
                <li><code>{{t.title}}</code></li>
              {{/each}}
            </ul>
          {{else}}
            <p class='wf-none'>No transitions defined — every move will be
              refused until some are.</p>
          {{/if}}
        </section>
      </article>
      <style scoped>
        .wf-page {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
        }
        .wf-applies {
          margin: var(--boxel-sp-4xs) 0 0;
          color: var(--muted-foreground, var(--boxel-450));
          font-size: var(--boxel-font-size-sm);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .wf-states {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .wf-states :deep(.containsMany-field) {
          display: contents;
        }
        .wf-transitions {
          margin: 0;
          padding: 0;
          list-style: none;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
        }
        code {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-sm);
        }
        .wf-none {
          margin: 0;
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='wf-embedded'>
        <span class='wf-name'>{{@model.title}}</span>
        <span class='wf-meta'>{{@model.states.length}}
          states ·
          {{@model.transitions.length}}
          transitions</span>
      </div>
      <style scoped>
        .wf-embedded {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
        }
        .wf-name {
          font-weight: 600;
        }
        .wf-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='wf-atom'>{{@model.title}}</span>
      <style scoped>
        .wf-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get firstStateColor() {
      let first = (this.args.model.states ?? [])[0];
      let c = workflowKindColor(first?.kind);
      return `--wf-accent: ${c.ring};`;
    }
    <template>
      <div class='wf-fitted' style={{this.firstStateColor}}>
        <RouteIcon class='wf-icon' aria-hidden='true' />
        <div class='wf-fitted-body'>
          <span class='wf-fitted-title'>{{@model.title}}</span>
          <span class='wf-fitted-meta'>{{@model.states.length}}
            states ·
            {{@model.transitions.length}}
            transitions</span>
          <div class='wf-fitted-states'><@fields.states /></div>
        </div>
      </div>
      <style scoped>
        .wf-fitted {
          height: 100%;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .wf-icon {
          flex: none;
          width: 1.25rem;
          height: 1.25rem;
          color: var(--wf-accent, var(--primary, var(--boxel-highlight)));
        }
        .wf-fitted-body {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          min-width: 0;
        }
        .wf-fitted-title {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .wf-fitted-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .wf-fitted-states {
          display: none;
        }
        @container fitted-card (height > 170px) {
          .wf-fitted-states {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-5xs);
            margin-top: var(--boxel-sp-4xs);
          }
          .wf-fitted-states :deep(.containsMany-field) {
            display: contents;
          }
        }
        @container fitted-card (height <= 80px) {
          .wf-fitted {
            align-items: center;
          }
          .wf-fitted-meta {
            display: none;
          }
        }
      </style>
    </template>
  };
  static edit = WorkflowEdit;
}

export default Workflow;
