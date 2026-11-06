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
import { array, fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { FitTile } from '../shared/fit-tile';
import InboxIcon from '@cardstack/boxel-icons/inbox';
import UsersIcon from '@cardstack/boxel-icons/users';
import BookOpenIcon from '@cardstack/boxel-icons/book-open';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';
import ClockIcon from '@cardstack/boxel-icons/clock';
import TagIcon from '@cardstack/boxel-icons/tag';
import UserIcon from '@cardstack/boxel-icons/user';
import HeadsetIcon from '@cardstack/boxel-icons/headset';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import { Stat } from '@cardstack/pretui/components/stat';
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
import {
  CataloguePanel,
  type CatalogueColumn,
} from '../service-desk/components/catalogue-panel';
import { QueueView } from '../service-desk/components/queue-view';
import { TicketWorkspace } from '../service-desk/components/ticket-workspace';
import {
  LENSES,
  matchesLens,
  type Lens,
} from '../service-desk/utils/queue-lens';

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
  columns?: CatalogueColumn[];
  searchPlaceholder?: string;
  /** Singular noun for the New button — "New" alone says nothing about what. */
  newLabel?: string;
  icon: typeof InboxIcon;
  avatar?: boolean;
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
        icon: InboxIcon,
        label: 'Queue',
        purpose:
          'What needs attention right now. The counts are the filters — click one to narrow.',
        isQueue: true,
      },
      {
        id: 'queues',
        icon: UsersIcon,
        label: 'Teams',
        purpose:
          'Which baskets are healthy and which are drowning — the team lead’s view.',
        cardClass: Queue,
        searchPlaceholder: 'Search queues…',
        newLabel: 'queue',
        columns: [
          { key: 'title', label: 'Queue' },
          { key: 'tierLabel', label: 'Tier' },
          { key: 'agentCount', label: 'Agents', mono: true },
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
        icon: BookOpenIcon,
        label: 'Articles',
        purpose:
          'Answers worth writing down once. These are what the workspace suggests while an agent types.',
        cardClass: KnowledgeArticle,
        searchPlaceholder: 'Search articles, keywords…',
        newLabel: 'article',
        columns: [
          { key: 'title', label: 'Article' },
          { key: 'categoryName', label: 'Category' },
          { key: 'status', label: 'Status', dot: true },
          { key: 'visibility', label: 'Visibility', dot: true, showAbove: 640 },
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
        icon: ShieldCheckIcon,
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
        icon: ClockIcon,
        label: 'Business hours',
        purpose: 'The calendars every SLA deadline is calculated against.',
        cardClass: Schedule,
        searchPlaceholder: 'Search schedules…',
        newLabel: 'schedule',
        columns: [
          { key: 'title', label: 'Schedule' },
          { key: 'summary', label: 'Open', mono: true },
          { key: 'timeZone', label: 'Time zone', mono: true },
          {
            key: 'holidayCount',
            label: 'Holidays',
            showAbove: 640,
            mono: true,
          },
        ],
      },
      {
        id: 'categories',
        icon: TagIcon,
        label: 'Categories',
        purpose:
          'Where a new ticket’s priority and queue come from. Both stay overridable.',
        cardClass: TicketCategory,
        searchPlaceholder: 'Search categories…',
        newLabel: 'category',
        columns: [
          { key: 'path', label: 'Category' },
          { key: 'defaultPriority', label: 'Default priority', dot: true },
          { key: 'defaultQueueName', label: 'Routes to' },
        ],
      },
      {
        id: 'people',
        avatar: true,
        icon: UserIcon,
        label: 'Customers',
        purpose: 'Who is asking, and what they were promised.',
        cardClass: SupportContact,
        searchPlaceholder: 'Search customers, companies…',
        newLabel: 'customer',
        columns: [
          { key: 'title', label: 'Customer' },
          { key: 'company', label: 'Company' },
          { key: 'tier', label: 'Tier', dot: true },
        ],
      },
      {
        id: 'agents',
        avatar: true,
        icon: HeadsetIcon,
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
    let counts: Record<string, ReturnType<getCards> | undefined> = {};
    for (let sec of SECTIONS) {
      for (let p of sec.panels) {
        let cls = p.cardClass;
        if (!cls) continue;
        counts[p.id] = this.args.context?.getCards(
          this,
          () => {
            if (!this.isInteractive) return undefined;
            let ref = identifyCard(cls);
            return ref ? { filter: { type: ref } } : undefined;
          },
          () => (this.args.realm ? [this.args.realm] : []),
          { isLive: true },
        );
      }
    }
    this.countQueries = counts;
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

  // The rail's counts would read 0 before the first load lands; later
  // revalidations keep the counts they already have.
  get showRail(): boolean {
    return !(this.isLoadingTickets && this.tickets.length === 0);
  }

  @tracked private countQueries: Record<
    string,
    ReturnType<getCards> | undefined
  > = {};

  // SidebarItem's @badge takes a string.
  countOf = (p: Panel): string | undefined => {
    let n = p.isQueue
      ? this.tickets.filter((t) => matchesLens(t, 'open')).length
      : this.countQueries[p.id]?.instances?.length;
    return n === undefined ? undefined : String(n);
  };

  get lensStats() {
    return LENSES.map((spec) => ({
      ...spec,
      count: this.tickets.filter((t) => matchesLens(t, spec.key)).length,
      active: spec.key === this.lens,
    }));
  }

  // On the phone the rail is a drawer; picking a destination closes it.
  navTo = (
    bar: { mobile?: boolean; toggle?: () => void },
    sectionId: string,
    panelId: string,
  ) => {
    this.selectNav(sectionId, panelId);
    if (bar.mobile) bar.toggle?.();
  };

  selectNav = (sectionId: string, panelId: string) => {
    this.sectionId = sectionId;
    this.panelId = panelId;
  };

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
    <div class='app'>
      <Sidebar
        class='shell-sidebar'
        @label='Service Desk'
        @collapsible='rail'
        @railBreakpoint={{1100}}
        @mobileBreakpoint={{720}}
        @bordered={{true}}
        @scroll='content'
        @resizable={{true}}
      >
        <:header as |bar|>
          <div class='brand'>
            <span class='brand-mark' aria-hidden='true'>SD</span>
            {{#unless bar.collapsed}}
              <span class='brand-name'>Service Desk<small>Support operations</small></span>
            {{/unless}}
          </div>
        </:header>
        <:nav as |bar|>
          {{#each this.sections as |sec|}}
            <SidebarGroup @label={{sec.label}} @hideLabel={{bar.collapsed}}>
              {{#each sec.panels as |p|}}
                <SidebarItem
                  @label={{p.label}}
                  @badge={{unless bar.collapsed (this.countOf p)}}
                  @active={{eq p.id this.panelId}}
                  @collapsed={{bar.collapsed}}
                  @onClick={{fn this.navTo bar sec.id p.id}}
                >
                  <:icon><p.icon aria-hidden='true' /></:icon>
                </SidebarItem>
              {{/each}}
            </SidebarGroup>
          {{/each}}
        </:nav>
        <:default as |bar|>
          <main class='main'>
            {{#if this.createProblem}}
              <Alert @tone='danger'>{{this.createProblem}}</Alert>
            {{/if}}

            {{#if bar.mobile}}
              <SidebarTrigger
                @open={{bar.open}}
                @onToggle={{bar.toggle}}
                @controls={{bar.controls}}
                @label='Menu'
              />
            {{/if}}
            <div class='head-row'>
              <header class='head'>
                <p class='cap'>{{this.section.label}}</p>
                <h1>{{this.panel.label}}</h1>
                <p class='sub'>{{this.panel.purpose}}</p>
              </header>
              <Button
                @icon={{PlusIcon}}
                class='new-ticket'
                @tone='neutral'
                @appearance='outlined'
                @size='s'
                @busy={{this.creating}}
                {{on 'click' this.newTicket}}
              >
                New ticket
              </Button>
            </div>

            {{#if this.isInteractive}}
              {{#if this.canShowQueue}}
                <section class='strip' aria-label='Queue filters'>
                  <div class='cells'>
                    {{#each this.lensStats as |s|}}
                      <button
                        type='button'
                        class='cell {{if s.active "active"}}'
                        aria-pressed={{if s.active 'true' 'false'}}
                        {{on 'click' (fn this.setLens s.key)}}
                      >
                        <Stat
                          @label={{s.label}}
                          @value={{s.count}}
                          @tone={{if s.tone s.tone 'neutral'}}
                          @hint={{s.hint}}
                          @roll={{false}}
                        />
                      </button>
                    {{/each}}
                  </div>
                </section>
                <div class='split {{if this.selectedTicket "split-picked"}}'>
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
                      @onQueue={{this.setQueue}}
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
                {{#each (array this.panel) key='id' as |panel|}}
                  <CataloguePanel
                    @cardClass={{panel.cardClass}}
                    @context={{@context}}
                    @realms={{this.realms}}
                    @columns={{panel.columns}}
                    @label={{panel.label}}
                    @searchPlaceholder={{panel.searchPlaceholder}}
                    @newLabel={{panel.newLabel}}
                    @avatar={{panel.avatar}}
                    @mark={{if panel.avatar false true}}
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
              <p class='shell'>The console is live when you open it: queues,
                timers and search all read the realm directly.</p>
            {{/if}}
          </main>
        </:default>
      </Sidebar>
    </div>

    <style scoped>
      .app {
        container-type: inline-size;
        block-size: 100%;
        min-block-size: 0;
        overflow: hidden;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: 0.75rem;
      }
      .shell-sidebar {
        block-size: 100%;
        min-block-size: 0;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .brand-mark {
        display: grid;
        place-items: center;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border: 1px solid var(--border);
        color: var(--foreground);
        font: 600 0.5625rem/1 var(--font-mono);
      }
      .brand-name {
        display: grid;
        font-weight: 700;
        font-size: 0.75rem;
        line-height: 1.2;
      }
      .brand-name small {
        font: 600 0.5625rem/1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .main {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp-lg);
        min-width: 0;
      }
      .head-row {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
      }
      .new-ticket {
        white-space: nowrap;
        flex: none;
      }
      .head {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .cap {
        margin: 0;
        font: 600 0.5625rem/1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      h1 {
        margin: 0;
        font-family: var(--boxel-heading-font-family, var(--font-sans));
        font-weight: 400;
        font-size: 2.5rem;
        line-height: 1;
        text-transform: uppercase;
      }
      .sub {
        margin: 0;
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      /* Divided grid: every cell draws its RIGHT and BOTTOM line; the cells
         overhang the frame by 1px and the frame clips them, so a part-filled
         last row still has all its dividers and the frame is one border. */
      .strip {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .cells {
        --text-stat: 1.375rem;
        display: grid;
        grid-template-columns: repeat(6, minmax(0, 1fr));
        margin: 0 -1px -1px 0;
      }
      .cell {
        all: unset;
        box-sizing: border-box;
        cursor: pointer;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        min-width: 0;
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      .cell:hover,
      .cell.active {
        background: var(--muted);
      }
      .cell.active {
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border),
          inset 0 -2px 0 var(--foreground);
      }
      .cell:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -2px;
      }
      /* Whole rows only: 6, then 3 + 3, then 2 + 2 + 2. */
      @container (width <= 75rem) {
        .cells {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
      }
      @container (width <= 40rem) {
        .cells {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
      .split {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 18rem;
        align-items: start;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .split-list {
        min-width: 0;
      }
      .back {
        display: none;
      }
      .split-detail {
        min-width: 0;
        border-inline-start: 1px solid var(--border);
        min-height: 20rem;
      }
      .split-detail:has(.pick) {
        display: flex;
        flex-direction: column;
      }
      .pick {
        flex: 1;
        justify-content: center;
      }
      @container (width <= 60rem) {
        .split {
          grid-template-columns: minmax(0, 1fr);
        }
        .split-detail {
          border-inline-start: none;
          border-block-start: 1px solid var(--border);
        }
        .split-picked .split-list {
          display: none;
        }
        .back {
          display: inline-flex;
          margin: var(--boxel-sp-xs);
        }
      }
      .shell {
        max-width: 60ch;
        color: var(--muted-foreground);
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
        <LifeBuoyIcon
          class='sd-atom-glyph'
          width='14'
          height='14'
          role='presentation'
        />
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
          color: var(--primary-ink);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FitTile>
        <:title>{{@model.title}}</:title>
        <:subtitle>Support console</:subtitle>
        <:fact>Queue, teams, articles, commitments, hours, categories, customers
          and agents, each a live query.</:fact>
      </FitTile>
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
