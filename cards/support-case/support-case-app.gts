import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Field } from '@cardstack/pretui/components/field';
import HeadsetIcon from '@cardstack/boxel-icons/headset';

import { AppConfigurationField } from '../../fields/app-configuration/app-configuration-field';
import { Employee } from '../hr/employee';
import { Role } from '../service-desk/role';
import { Workflow } from '../service-desk/workflow';
import { EditSectionNav } from '../../components/edit-section-nav';

import { SupportDesk } from './components/support-desk';

class SupportCaseAppEdit extends Component<typeof SupportCaseApp> {
  @tracked activeSection = 'identity';

  sections = [
    { id: 'identity', label: 'Desk' },
    { id: 'config', label: 'Configuration' },
    { id: 'links', label: 'Process & people' },
  ];

  goTo = (id: string, event: Event) => {
    this.activeSection = id;
    let root = (event.currentTarget as HTMLElement).closest('.desk-edit');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='desk-edit'>
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
            <h3>Desk</h3>
            <Field @label='Name'>
              <@fields.appName />
            </Field>
            <Field @label='Operator (who is at the desk)'>
              <@fields.operator />
            </Field>
          </section>
          <section
            class='sect {{if (eq this.activeSection "config") "focused"}}'
            data-sect='config'
          >
            <h3>Configuration
              <span class='sect-hint'>the Setup tab edits this step by step</span></h3>
            <Field @label='Configuration'>
              <@fields.config />
            </Field>
          </section>
          <section
            class='sect {{if (eq this.activeSection "links") "focused"}}'
            data-sect='links'
          >
            <h3>Process & people</h3>
            <Field @label='Default workflow'>
              <@fields.defaultWorkflow />
            </Field>
            <Field @label='Roles'>
              <@fields.roles />
            </Field>
            <Field @label='Round-robin pool'>
              <@fields.candidatePool />
            </Field>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      /* Same edit shell as Case / Escalation in this kit (edit-card Rule 1):
         the root is the named container AND the scroller, so the rail can
         be sticky and the query below can actually fire. */
      .desk-edit {
        container-type: inline-size;
        container-name: edit;
        height: 100%;
        overflow-y: auto;
        padding: var(--boxel-sp);
        background: var(--background);
        color: var(--foreground);
        --desk-ink: var(--foreground);
      }
      .edit-body {
        display: grid;
        grid-template-columns: 9.5rem minmax(0, 1fr);
        gap: var(--boxel-sp);
        align-items: start;
      }
      .sect-nav {
        position: sticky;
        top: 0;
      }
      @container edit (width < 640px) {
        .edit-body {
          grid-template-columns: 1fr;
        }
        .sect-nav {
          position: static;
        }
      }
      .sects {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .sect {
        display: grid;
        gap: var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        padding: var(--boxel-sp);
        scroll-margin-top: var(--boxel-sp);
        outline: 2px solid transparent;
        outline-offset: 2px;
        transition:
          outline-color 160ms ease,
          box-shadow 160ms ease;
      }
      /* the section the rail points at mirrors the rail's active state */
      .sect.focused {
        outline-color: var(--desk-ink);
        box-shadow: 0 0 0 4px
          color-mix(in oklch, var(--desk-ink) 12%, transparent);
      }
      .sect h3 {
        margin: 0;
        font-size: 0.8125rem;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .sect-hint {
        text-transform: none;
        letter-spacing: normal;
        font-size: 0.75rem;
        font-weight: 400;
        font-style: italic;
      }
    </style>
  </template>
}

/**
 * Support Ops Command Center — the operations layer ABOVE the ServiceDesk
 * agent kit. The agent works one ticket in `service-desk`; the ops lead runs
 * fifty here: clocks, ladders, ownership, workflow, automation.
 *
 * `operator` is the acting person: the platform has no current-user concept,
 * so who is claiming/acknowledging is DECLARED on the desk, honestly, rather
 * than inferred. Every collection is a live query (membership is derived,
 * never a maintained linksToMany).
 */
export class SupportCaseApp extends CardDef {
  static displayName = 'Support Case App';
  static icon = HeadsetIcon;
  static prefersWideFormat = true;

  @field appName = contains(StringField);
  @field config = contains(AppConfigurationField);
  @field defaultWorkflow = linksTo(() => Workflow);
  @field operator = linksTo(() => Employee, {
    description: 'Who is at the desk — claims and acks are attributed to them.',
  });
  @field roles = linksToMany(() => Role);
  @field candidatePool = linksToMany(() => Employee, {
    description: 'Round-robin pool: commands take caller-loaded lists.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: SupportCaseApp) {
      return this.appName ?? 'Support Ops';
    },
  });

  // Denormalized link ids: linksTo fields load lazily on the client, so an
  // action fired before the link resolves would see undefined. These computeds
  // are produced at index time (link traversal works in computeVia) and are
  // always present on the loaded instance — the actions re-fetch by id.
  @field operatorId = contains(StringField, {
    computeVia: function (this: SupportCaseApp) {
      return this.operator?.id;
    },
  });
  @field operatorTitle = contains(StringField, {
    computeVia: function (this: SupportCaseApp) {
      return this.operator?.title as string | undefined;
    },
  });
  @field workflowId = contains(StringField, {
    computeVia: function (this: SupportCaseApp) {
      return this.defaultWorkflow?.id;
    },
  });

  static isolated = SupportDesk;
  static edit = SupportCaseAppEdit;
}

export default SupportCaseApp;
