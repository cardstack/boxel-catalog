import PlusIcon from '@cardstack/boxel-icons/plus';
import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
  realmURL,
  type CardContext,
  type CardCrudFunctions,
} from '@cardstack/base/card-api';
import GlimmerComponent from '@glimmer/component';
import { type getCards, identifyCard } from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { array } from '@ember/helper';
import { gt } from '@cardstack/boxel-ui/helpers';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Tabs } from '@cardstack/pretui/components/tabs';
import { consume } from 'ember-provide-consume-context';
import { CardCrudFunctionsContextName } from '@cardstack/runtime-common';
import LifeBuoyIcon from '@cardstack/boxel-icons/life-buoy';

import { Ticket } from '../service-desk/ticket';
import { Queue } from '../service-desk/queue';
import { SlaPolicy } from '../service-desk/sla-policy';
import { Schedule } from '../service-desk/schedule';
import { TicketCategory } from '../service-desk/ticket-category';
import { SupportContact } from '../service-desk/support-contact';
import { SupportAgent } from '../service-desk/support-agent';
import { KnowledgeArticle } from '../service-desk/knowledge-article';
import { CollectionPanel } from '../../components/collection-panel';
import type { TableColumn } from '../../components/table';
import { QueueView } from '../service-desk/components/queue-view';
import { WorkRail } from '../service-desk/components/work-rail';
import { TicketWorkspace } from '../service-desk/components/ticket-workspace';
import type { Lens } from '../service-desk/utils/queue-lens';

interface Panel {
  id: string;
  label: string;
  /** The job this panel exists to do, in the words of whoever does it. */
  purpose: string;
  /**
   * The card CLASS, not its display name. A `_cardType` string filter is an
   * exact match and silently drops subclasses; a CodeRef derived from the
   * class includes them by construction.
   */
  cardClass?: typeof CardDef;
  /** Table columns for the catalogue panels. Keys read off the instance. */
  columns?: TableColumn[];
  searchPlaceholder?: string;
  /** Singular noun for the New button — "New" alone says nothing about what. */
  newLabel?: string;
  /** True for the one panel that renders the queue rather than a catalogue. */
  isQueue?: boolean;
}

interface Section {
  id: string;
  label: string;
  panels: Panel[];
}

// Three sections, grouped by the job somebody is doing: work, reference and
// configuration. An agent's whole world is the first section; the other two
// are somebody else's job.
const SECTIONS: Section[] = [
  {
    id: 'work',
    label: 'Work',
    panels: [
      {
        id: 'queue',
        label: 'Queue',
        purpose:
          'What needs attention right now. The counts are the filters — click one to narrow.',
        isQueue: true,
      },
      {
        id: 'queues',
        label: 'Teams',
        purpose:
          'Which baskets are healthy and which are drowning — the team lead’s view.',
        cardClass: Queue,
        searchPlaceholder: 'Search queues…',
        newLabel: 'queue',
        columns: [
          { key: 'title', label: 'Queue' },
          { key: 'tierLabel', label: 'Tier' },
          { key: 'agentCount', label: 'Agents' },
          { key: 'policyName', label: 'Default policy', showAbove: 640 },
        ],
      },
    ],
  },
  {
    id: 'knowledge',
    label: 'Knowledge',
    panels: [
      {
        id: 'articles',
        label: 'Articles',
        purpose:
          'Answers worth writing down once. These are what the workspace suggests while an agent types.',
        cardClass: KnowledgeArticle,
        searchPlaceholder: 'Search articles, keywords…',
        newLabel: 'article',
        columns: [
          { key: 'title', label: 'Article' },
          { key: 'categoryName', label: 'Category' },
          { key: 'status', label: 'Status' },
          { key: 'visibility', label: 'Visibility', showAbove: 640 },
        ],
      },
    ],
  },
  {
    id: 'setup',
    label: 'Setup',
    panels: [
      {
        id: 'sla',
        label: 'Commitments',
        purpose: 'What was promised, to whom, and how each priority scales it.',
        cardClass: SlaPolicy,
        searchPlaceholder: 'Search policies…',
        newLabel: 'policy',
        columns: [
          { key: 'title', label: 'Policy' },
          { key: 'conditionSummary', label: 'Applies when' },
          { key: 'targetSummary', label: 'Targets' },
          { key: 'businessHoursSummary', label: 'Hours', showAbove: 720 },
        ],
      },
      {
        id: 'hours',
        label: 'Business hours',
        purpose: 'The calendars every SLA deadline is calculated against.',
        cardClass: Schedule,
        searchPlaceholder: 'Search schedules…',
        newLabel: 'schedule',
        columns: [
          { key: 'title', label: 'Schedule' },
          { key: 'summary', label: 'Open' },
          { key: 'timeZone', label: 'Time zone' },
          { key: 'holidayCount', label: 'Holidays', showAbove: 640 },
        ],
      },
      {
        id: 'categories',
        label: 'Categories',
        purpose:
          'Where a new ticket’s priority and queue come from. Both stay overridable.',
        cardClass: TicketCategory,
        searchPlaceholder: 'Search categories…',
        newLabel: 'category',
        columns: [
          { key: 'path', label: 'Category' },
          { key: 'defaultPriority', label: 'Default priority' },
          { key: 'defaultQueueName', label: 'Routes to' },
        ],
      },
      {
        id: 'people',
        label: 'Customers',
        purpose: 'Who is asking, and what they were promised.',
        cardClass: SupportContact,
        searchPlaceholder: 'Search customers, companies…',
        newLabel: 'customer',
        columns: [
          { key: 'title', label: 'Customer' },
          { key: 'company', label: 'Company' },
          { key: 'tier', label: 'Tier' },
        ],
      },
      {
        id: 'agents',
        label: 'Agents',
        purpose: 'Who answers, at which tier, with which skills.',
        cardClass: SupportAgent,
        searchPlaceholder: 'Search agents, skills…',
        newLabel: 'agent',
        columns: [
          { key: 'title', label: 'Agent' },
          { key: 'tierLabel', label: 'Tier' },
          { key: 'skillSummary', label: 'Skills', showAbove: 640 },
        ],
      },
    ],
  },
];

/**
 * The console body.
 *
 * A top-level component rather than the format class itself, because reactive
 * state (`@tracked`) is not allowed inside a `static isolated = class { … }`
 * expression — the decorator has nowhere to install itself there.
 */
interface ConsoleSignature {
  Args: {
    title?: string;
    realm?: string;
    context?: CardContext;
  };
  Element: HTMLElement;
}

class ServiceDeskConsole extends GlimmerComponent<ConsoleSignature> {
  @consume(CardCrudFunctionsContextName)
  declare cardCrudFunctions: CardCrudFunctions | undefined;

  sections = SECTIONS;
  @tracked sectionId = SECTIONS[0]!.id;
  @tracked panelId = SECTIONS[0]!.panels[0]!.id;
  @tracked private ticketQuery: ReturnType<getCards> | undefined;

  constructor(owner: unknown, args: ConsoleSignature['Args']) {
    super(owner as never, args as never);
    // One live query feeds the counts AND the rows. Two queries is how a
    // header that says "1 breached" ends up disagreeing with the list below.
    this.ticketQuery = this.args.context?.getCards(
      this,
      () => {
        if (!this.isInteractive) {
          return undefined;
        }
        let ref = identifyCard(Ticket);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => (this.args.realm ? [this.args.realm] : []),
      { isLive: true },
    );
  }

  get sectionOptions() {
    return this.sections.map((s) => ({ value: s.id, label: s.label }));
  }

  get panelOptions() {
    return this.section.panels.map((p) => ({ value: p.id, label: p.label }));
  }

  get section(): Section {
    return (
      this.sections.find((s) => s.id === this.sectionId) ?? this.sections[0]!
    );
  }

  /**
   * A catalogue panel needs both a type to query and a realm to query in.
   *
   * A getter rather than `(and this.panel.cardClass this.realms.length)` in the
   * template: the `and` helper infers its type parameter from the FIRST
   * argument, so every later argument gets checked against `typeof CardDef`
   * and a plain boolean fails.
   */
  get canShowQueue(): boolean {
    return Boolean(this.panel.isQueue) && this.realms.length > 0;
  }

  get canShowPanel(): boolean {
    return Boolean(this.panel.cardClass) && this.realms.length > 0;
  }

  get panel(): Panel {
    return (
      this.section.panels.find((p) => p.id === this.panelId) ??
      this.section.panels[0]!
    );
  }

  get tickets(): Ticket[] {
    return ((this.ticketQuery?.instances ?? []) as Ticket[]).filter(Boolean);
  }

  get isLoadingTickets(): boolean {
    return Boolean(this.ticketQuery?.isLoading);
  }

  selectSection = (id: string) => {
    this.sectionId = id;
    this.panelId =
      this.sections.find((s) => s.id === id)?.panels[0]?.id ?? this.panelId;
  };

  selectPanel = (id: string) => {
    this.panelId = id;
  };

  @tracked selectedTicket: Ticket | undefined;

  // The three filters the console owns, because two surfaces read them: the
  // rail draws the counts and the list draws the rows.
  @tracked lens: Lens = 'open';
  @tracked queueName: string | undefined;

  setLens = (lens: Lens) => {
    this.lens = lens;
  };

  setQueue = (name: string | undefined) => {
    this.queueName = name;
  };

  clearQueue = () => {
    this.queueName = undefined;
  };

  @tracked creating = false;
  @tracked createProblem: string | undefined;

  // A ticket raised by hand opens in edit, in this console's own realm — the
  // agent is typing what a customer said on the phone, so the empty form IS
  // the point and there is nothing worth prefilling.
  newTicket = async (_event?: Event) => {
    let create = this.cardCrudFunctions?.createCard;
    let ref = identifyCard(Ticket);
    if (!create || !this.args.realm || !ref) {
      this.createProblem =
        'This console is not saved in a realm yet, so there is nowhere to put a new ticket.';
      return;
    }
    this.creating = true;
    this.createProblem = undefined;
    try {
      await create(ref, new URL(this.args.realm), {
        realmURL: new URL(this.args.realm),
      });
    } catch (error: any) {
      this.createProblem = error?.message ?? String(error);
    } finally {
      this.creating = false;
    }
  };

  // Selecting, not navigating. On a wide canvas the queue stays put and only
  // the right pane changes — an agent working a run of tickets never has to
  // find their place again.
  selectTicket = (ticket: Ticket) => {
    this.selectedTicket = ticket;
  };

  clearTicket = (_event?: Event) => {
    this.selectedTicket = undefined;
  };

  get realms(): string[] {
    return this.args.realm ? [this.args.realm] : [];
  }

  /**
   * Prerender gets a static shell, not the console.
   *
   * Indexing renders this card with no CRUD functions and no interaction, and
   * mounting the live queries there costs a full query fan-out per reindex for
   * a result nobody sees. Worse, app cards that mount heavy interactive UI
   * during prerender have been seen to trip a Glimmer backtracking assertion,
   * which is stored as an error_doc and then surfaces to a real user as
   * "Card Error" on a card that works perfectly when opened.
   *
   * The presence of `viewCard` is the honest test for "a person is looking at
   * this".
   */
  get isInteractive(): boolean {
    return Boolean(this.cardCrudFunctions?.viewCard);
  }

  <template>
    <div class='console'>
      <header class='console-head'>
        <h1>{{@title}}</h1>
        {{! One quiet control picks the section, so the only filled thing on
            the masthead is the action. }}
        <SegmentedControl
          class='sections'
          @label='Sections'
          @options={{this.sectionOptions}}
          @value={{this.sectionId}}
          @onValueChange={{this.selectSection}}
        />
        {{! Every search sits in the toolbar of the thing it searches, so the
            masthead holds only the action. }}
        <div class='head-tools'>
          <Button
            class='new-ticket'
            @tone='primary'
            @appearance='filled'
            @size='s'
            @busy={{this.creating}}
            {{on 'click' this.newTicket}}
          >
            {{#unless this.creating}}
              <PlusIcon width='15' height='15' aria-hidden='true' />
            {{/unless}}
            New ticket
          </Button>
        </div>
      </header>

      {{#if this.createProblem}}
        <Alert @tone='danger'>{{this.createProblem}}</Alert>
      {{/if}}

      {{#if (gt this.section.panels.length 1)}}
        <Tabs
          class='panels'
          @options={{this.panelOptions}}
          @value={{this.panelId}}
          @onValueChange={{this.selectPanel}}
        />
      {{/if}}

      <section class='panel' aria-label={{this.panel.label}}>
        <p class='purpose'>{{this.panel.purpose}}</p>

        {{#if this.isInteractive}}

          {{#if this.canShowQueue}}
            {{! Master-detail. The list is a fixed column and the detail fills
                what is left; below 68rem the three regions stack into one
                column. }}
            <div class='split {{if this.selectedTicket "split-picked"}}'>
              <WorkRail
                class='split-rail'
                @tickets={{this.tickets}}
                @lens={{this.lens}}
                @onLens={{this.setLens}}
                @queueName={{this.queueName}}
                @onQueue={{this.setQueue}}
              />
              <div class='split-list'>
                <QueueView
                  @tickets={{this.tickets}}
                  @isLoading={{this.isLoadingTickets}}
                  @onSelect={{this.selectTicket}}
                  @selectedId={{this.selectedTicket.id}}
                  @lens={{this.lens}}
                  @onLens={{this.setLens}}
                  @queueName={{this.queueName}}
                  @onClearQueue={{this.clearQueue}}
                />
              </div>
              <div class='split-detail'>
                {{#if this.selectedTicket}}
                  <Button
                    class='back'
                    @tone='neutral'
                    @appearance='link'
                    @size='s'
                    {{on 'click' this.clearTicket}}
                  >Back to the queue</Button>
                  {{! Keyed on the ticket id, so selecting a different row
                      builds a new workspace instead of swapping one argument
                      under the old one. Without the key, tracked editor state
                      (a half-typed reply, an open subject edit, the escalate
                      and merge panels) would carry over to the next ticket. }}
                  {{#each (array this.selectedTicket) key='id' as |picked|}}
                    <TicketWorkspace
                      @ticket={{picked}}
                      @context={{@context}}
                      @realms={{this.realms}}
                      @onLeftQueue={{this.clearTicket}}
                    />
                  {{/each}}
                {{else}}
                  <EmptyState
                    class='pick'
                    @size='s'
                    @title='Pick a ticket'
                    @message='It opens here, beside the queue, so you keep your place in the list while you work.'
                  />
                {{/if}}
              </div>
            </div>
          {{else if this.canShowPanel}}
            {{! Keyed on the panel so switching tabs builds a fresh panel with
                its own query and an empty search box. }}
            {{#each (array this.panel) key='id' as |panel|}}
              <CollectionPanel
                @cardClass={{panel.cardClass}}
                @context={{@context}}
                @realms={{this.realms}}
                @columns={{panel.columns}}
                @label={{panel.label}}
                @searchPlaceholder={{panel.searchPlaceholder}}
                @newLabel={{panel.newLabel}}
              />
            {{/each}}
          {{else}}
            <EmptyState
              @size='s'
              @title='Nothing to query yet'
              @message='This console is not saved in a realm yet.'
            />
          {{/if}}
        {{else}}
          <p class='shell'>The console is live when you open it: queues, timers
            and search all read the realm directly.</p>
        {{/if}}
      </section>
    </div>

    <style scoped>
      .console {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp-lg);
        min-height: 100%;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
      }
      .console-head {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp);
        flex-wrap: wrap;
        padding-bottom: var(--boxel-sp-xs);
        border-bottom: 2px solid var(--foreground);
      }
      .console-head h1 {
        flex: 1;
        min-width: 10rem;
      }
      .sections {
        flex: none;
      }
      .head-tools {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        margin-left: var(--boxel-sp-sm);
      }
      .new-ticket {
        gap: var(--boxel-sp-5xs);
        white-space: nowrap;
      }
      .panel {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .split {
        display: grid;
        grid-template-columns: 11rem 24rem minmax(0, 1fr);
        gap: var(--boxel-sp-sm);
        align-items: start;
        min-height: 32rem;
      }
      .split-rail {
        position: sticky;
        top: var(--boxel-sp-sm);
        padding-right: var(--boxel-sp-xs);
        border-right: 1px solid var(--border);
      }
      .split-list {
        min-width: 0;
      }
      /* The back control only exists in the one-column layout. */
      .back {
        display: none;
      }
      .split-detail {
        min-width: 0;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
        background: var(--card);
        position: sticky;
        top: var(--boxel-sp-sm);
      }
      /* The split aligns to start so the pane can be sticky, so an empty pane
         needs its own height. A flex column lets the placeholder fill it. */
      .split-detail:has(.pick) {
        min-height: 34rem;
        display: flex;
        flex-direction: column;
      }
      .pick {
        flex: 1;
        justify-content: center;
      }
      /* Narrow reflows and never deletes: the rail becomes a strip above the
         list, and the detail becomes a mode you enter and leave. */
      @container (width <= 68rem) {
        .split {
          grid-template-columns: minmax(0, 1fr);
          grid-template-areas: 'rail' 'list' 'detail';
        }
        .split-rail {
          grid-area: rail;
          position: static;
          padding: 0 0 var(--boxel-sp-xs);
          border-right: none;
          border-bottom: 1px solid var(--border);
        }
        .split-list {
          grid-area: list;
        }
        .split-detail {
          grid-area: detail;
          position: static;
        }
        /* Opening a ticket swaps the list for the conversation, instead of
           stacking them and making the reader scroll past every row. */
        .split-picked .split-list {
          display: none;
        }
        .back {
          display: inline-flex;
          margin: var(--boxel-sp-xs);
        }
      }
      .purpose {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        max-width: 72ch;
        line-height: 1.6;
      }
      .shell {
        padding: var(--boxel-sp-lg) 0;
        max-width: 60ch;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.6;
        color: var(--muted-foreground);
      }
      @media (prefers-reduced-motion: reduce) {
        * {
          transition: none !important;
          animation: none !important;
        }
      }
    </style>
  </template>
}

/**
 * The Service Desk console.
 *
 * Every tab is a live query. Nothing here keeps a list of what belongs in it,
 * so the console always reflects the realm.
 */
export class ServiceDesk extends CardDef {
  static displayName = 'Service Desk';
  static icon = LifeBuoyIcon;
  // The host caps a stacked card at 50rem unless the definition asks for the
  // full canvas, and the master-detail layout needs the width.
  static prefersWideFormat = true;

  @field name = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: ServiceDesk) {
      return this.name?.trim() || 'Service Desk';
    },
  });

  // Away from its own canvas the console is a door, not a dashboard: enough to
  // recognise the desk, and to know that opening it is where the work happens.
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <article class='sd-emb'>
        <LifeBuoyIcon
          class='sd-glyph'
          width='24'
          height='24'
          role='presentation'
        />
        <span class='sd-main'>
          <span class='sd-name'>{{@model.title}}</span>
          <span class='sd-dim'>Support console: queues, commitments and the
            knowledge base</span>
        </span>
      </article>

      <style scoped>
        .sd-emb {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          padding: var(--boxel-sp-4xs) 0;
          font-family: var(--font-sans);
          color: var(--foreground);
        }
        .sd-glyph {
          flex: none;
          color: var(--primary-ink);
        }
        .sd-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
        }
        .sd-name {
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sd-dim {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='sd-atom'>
        <LifeBuoyIcon class='sd-atom-glyph' role='presentation' />
        {{@model.title}}
      </span>

      <style scoped>
        .sd-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          min-width: 0;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--foreground);
        }
        .sd-atom-glyph {
          flex: none;
          width: 0.9rem;
          height: 0.9rem;
          color: var(--primary-ink);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FittedCard @titleTag='h3'>
        <:placeholder><LifeBuoyIcon role='presentation' /></:placeholder>
        <:title>{{@model.title}}</:title>
        <:subtitle>Front line, queues, commitments, business hours, knowledge,
          customers and agents, each a live query.</:subtitle>
        <:footer><span class='fit-meta'>Support console</span></:footer>
      </FittedCard>

      <style scoped>
        .fit-meta {
          font-size: var(--boxel-font-size-xs);
          letter-spacing: var(--boxel-lsp-sm);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get realm(): string | undefined {
      return this.args.model?.[realmURL]?.href;
    }

    <template>
      <ServiceDeskConsole
        @title={{@model.title}}
        @realm={{this.realm}}
        @context={{@context}}
      />
    </template>
  };
}
