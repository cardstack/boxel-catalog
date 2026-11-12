import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import { Button } from '@cardstack/pretui/components/button';
import { rri } from '@cardstack/runtime-common';
import FolderIcon from '@cardstack/boxel-icons/folder';

import { Queue } from './queue';
import { TicketPriorityField } from './ticket-taxonomy';
import { priorityOption } from '@cardstack/catalog/fields/priority/priority';
import { eq } from '@cardstack/boxel-ui/helpers';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import { Avatar as PretAvatar } from '@cardstack/pretui/components/avatar';
import { FitTile } from '../shared/fit-tile';
import { FittedExtras } from '../procurement/vendor';
import {
  RecCard,
  RecHead,
  RecStats,
  RecBody,
  RecBlock,
  RecRow,
  RecLine,
} from './components/record';

// The two routing defaults as Pret UI KeyValue rows. `value` names which
// field the isolated view's value block renders for the row.

/**
 * What kind of problem this is, and what that implies.
 *
 * A category is not a label. It is where a new ticket's priority and queue
 * come from, which is why it is a card with links rather than a string on the
 * ticket: change "Outage" to route at P1 into L2, and every future outage
 * follows without anyone editing a rule.
 *
 * Both defaults are suggestions the ticket may override. A routing scheme that
 * cannot be overridden is one an agent will work around by mis-categorising,
 * and then the reports are wrong too.
 */
export class TicketCategory extends CardDef {
  static displayName = 'Category';
  static icon = FolderIcon;

  @field name = contains(StringField);
  @field parent = linksTo(() => TicketCategory);
  @field defaultPriority = contains(TicketPriorityField);
  @field defaultQueue = linksTo(() => Queue);

  @field title = contains(StringField, {
    computeVia: function (this: TicketCategory) {
      return this.name?.trim() || 'Uncategorised';
    },
  });

  // The trail, denormalized: a tile cannot walk `parent`, and "Authentication"
  // on its own does not tell you it lives under "Access issues".
  @field path = contains(StringField, {
    computeVia: function (this: TicketCategory) {
      let names: string[] = [this.name ?? '—'];
      let node: TicketCategory | undefined = this.parent;
      // Bounded rather than while(node): a category accidentally made its own
      // ancestor would otherwise hang the indexer instead of showing a mistake.
      for (let depth = 0; node && depth < 7; depth++) {
        names.unshift(node.name ?? '—');
        node = node.parent;
      }
      return names.join(' › ');
    },
  });

  @field defaultQueueName = contains(StringField, {
    computeVia: function (this: TicketCategory) {
      return this.defaultQueue?.title ?? '';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    articles: any;
    constructor(owner: unknown, args: any) {
      super(owner as never, args as never);
      let realm = this.args.model?.[realmURL]?.href;
      // Built from the realm URL: knowledge-article.gts imports this module.
      this.articles = (this.args.context as any)?.getCards?.(
        this,
        () =>
          realm
            ? {
                filter: {
                  on: {
                    module: rri(
                      new URL('./service-desk/knowledge-article', realm).href,
                    ),
                    name: 'KnowledgeArticle',
                  },
                  eq: { categoryName: this.args.model?.title ?? '—' },
                },
              }
            : undefined,
        () => (realm ? [realm] : []),
        { isLive: true },
      );
    }
    get articleList(): any[] {
      return ((this.articles?.instances ?? []) as any[]).filter(Boolean);
    }
    get priorityHint() {
      let label =
        priorityOption(TicketPriorityField, this.args.model?.defaultPriority)
          ?.label ?? '';
      let word = label.split(' · ')[1];
      return word ? `${word} · overridable` : 'overridable';
    }
    get queueShort() {
      let n = this.args.model?.defaultQueueName ?? '';
      return n.split(' ')[0] || '—';
    }
    get queueRest() {
      return (this.args.model?.defaultQueueName ?? '')
        .split(' ')
        .slice(1)
        .join(' ');
    }
    openArticle = (a: any) => (this.args as any).viewCard?.(a);
    <template>
      <RecCard @inset={{true}}>
        <RecHead @mark='C' @title={{@model.title}} @sub={{@model.path}}>
          <:status>{{#if @model.defaultPriority}}<Chip
                @appearance='plain'
              >{{@model.defaultPriority}}</Chip>{{/if}}</:status>
        </RecHead>
        <RecStats>
          <Stat
            @label='Default priority'
            @tone='neutral'
            @value={{if @model.defaultPriority @model.defaultPriority '—'}}
            @hint={{this.priorityHint}}
            @roll={{false}}
          />
          <Stat
            @label='Routes to'
            @tone='neutral'
            @value={{this.queueShort}}
            @hint={{this.queueRest}}
            @roll={{false}}
          />
          <Stat
            @label='Articles'
            @tone='neutral'
            @value={{this.articleList.length}}
            @hint={{this.articleList.[0].title}}
            @roll={{false}}
          />
        </RecStats>
        <RecBody>
          <:main>
            <RecBlock @title='Routing'>
              <RecRow @label='Default priority'>{{if
                  @model.defaultPriority
                  @model.defaultPriority
                  '—'
                }}</RecRow>
              <RecRow @label='Routes to'>{{#if
                  @model.defaultQueue
                }}<@fields.defaultQueue
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</RecRow>
            </RecBlock>
            <RecBlock @title='Articles in this category'>
              {{#each this.articleList as |a|}}
                <RecLine>
                  <:default><Button
                      @appearance='link'
                      {{on 'click' (fn this.openArticle a)}}
                    ><b>{{a.title}}</b></Button><span
                      class='dim'
                    >{{a.visibility}} · {{a.keywordLabel}}</span></:default>
                  <:end><Chip
                      @appearance='plain'
                      @tone={{if (eq a.status 'Published') 'success' 'warning'}}
                    >{{a.status}}</Chip></:end>
                </RecLine>
              {{else}}
                <RecLine><span class='dim'>No articles yet.</span></RecLine>
              {{/each}}
            </RecBlock>
          </:main>
          <:side>
            <RecBlock @title='Details'>
              <RecRow @label='Path'>{{if @model.path @model.path '—'}}</RecRow>
              <RecRow @label='Parent'>{{#if @model.parent}}<@fields.parent
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</RecRow>
              <RecRow @label='Queue'>{{if
                  @model.defaultQueueName
                  @model.defaultQueueName
                  '—'
                }}</RecRow>
            </RecBlock>
          </:side>
        </RecBody>
      </RecCard>
      <style scoped>
        .dim {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <RecCard>
        <RecHead @mark='C' @title={{@model.title}} @sub={{@model.path}} />
        <RecRow @label='Default priority'>{{if
            @model.defaultPriority
            @model.defaultPriority
            '—'
          }}</RecRow>
        <RecRow @label='Routes to'>{{if
            @model.defaultQueueName
            @model.defaultQueueName
            '—'
          }}</RecRow>
      </RecCard>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>C</span>
        <span class='nm'>{{@model.title}}</span>
        {{#if @model.defaultPriority}}<Chip
            @appearance='plain'
          >{{@model.defaultPriority}}</Chip>{{/if}}
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-3xs);
          min-inline-size: 0;
          max-inline-size: 100%;
          font-size: var(--boxel-font-size-xs);
        }
        .mark {
          flex: none;
          display: grid;
          place-items: center;
          inline-size: 1rem;
          block-size: 1rem;
          border: 1px solid var(--border);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          line-height: 1;
          color: var(--muted-foreground);
        }
        .nm {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    // Whole ruled rows the tall fitted sizes add under the FitTile.
    get facts() {
      let m = this.args.model;
      return [
        { key: 'Path', value: String((m as any)?.path ?? '') || '—' },
        {
          key: 'Default priority',
          value: String((m as any)?.defaultPriority ?? '') || '—',
        },
        {
          key: 'Default queue',
          value: String((m as any)?.defaultQueueName ?? '') || '—',
        },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar><PretAvatar
                @name='C'
                @shape='square'
                @size={{32}}
              /></:avatar>
            <:title>{{@model.title}}</:title>
            <:subtitle>{{@model.path}}</:subtitle>
            <:status>{{#if @model.defaultPriority}}<Chip
                  @appearance='plain'
                >{{@model.defaultPriority}}</Chip>{{/if}}</:status>
            <:fact>Routes to
              {{if @model.defaultQueueName @model.defaultQueueName '—'}}</:fact>
          </FitTile>
        </:default>
      </FittedExtras>
    </template>
  };
}
