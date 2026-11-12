import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import HeadsetIcon from '@cardstack/boxel-icons/headset';
import { DeskSettingsField } from '../service-desk/desk-settings-field';
import { Employee } from '../hr/employee';
import { Workflow } from '../service-desk/workflow';
import { SupportDesk } from './components/support-desk';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Case } from '../service-desk/case';
import { Escalation } from '../service-desk/escalation';
import { Sla } from '../service-desk/sla';
import { Detail, Metric, RichFittedCard } from '../shared/rich-fitted-card';
import { StatusChip } from '@cardstack/pretui/components/status-chip';

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
  @field config = contains(DeskSettingsField);
  @field defaultWorkflow = linksTo(() => Workflow);
  @field operator = linksTo(() => Employee, {
    description: 'Who is at the desk — claims and acks are attributed to them.',
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

  static embedded = class Embedded extends Component<typeof SupportCaseApp> {
    <template>
      <div class='sc-emb'>
        <Avatar
          @name={{if @model.title @model.title ''}}
          @hue='var(--primary)'
          @size={{32}}
          aria-hidden='true'
        />
        <span class='sc-emb-who'>
          <strong class='sc-emb-name'>{{@model.title}}</strong>
          <span class='sc-emb-sub'>Clocks, ladders, ownership and workflow</span>
        </span>
      </div>
      <style scoped>
        .sc-emb {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
        }
        .sc-emb-who {
          flex: 1;
          display: grid;
          min-width: 0;
        }
        .sc-emb-name,
        .sc-emb-sub {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sc-emb-name {
          font-weight: 600;
        }
        .sc-emb-sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof SupportCaseApp> {
    <template>
      <span class='sc-atom'>{{@model.title}}</span>
      <style scoped>
        .sc-atom {
          white-space: nowrap;
        }
      </style>
    </template>
  };

  // Fitted, in FITTED-RULE priority: who (desk), setup state, open cases and
  // the desk's escalation and clock counts, the one fact that explains the
  // desk's numbering, then the operator and the default workflow in their own
  // atom formats. Breach and at-risk counts need the case-to-clock join the
  // desk does, so the tile leaves them to the desk.
  static fitted = class Fitted extends Component<typeof SupportCaseApp> {
    // One query per counted type, not live: the tile shows the numbers as of
    // its last render.
    private query = (cls: typeof CardDef) => {
      let ref = identifyCard(cls);
      let query = ref ? { filter: { type: ref } } : undefined;
      let url = this.args.model?.[realmURL];
      let realms = url ? [url.href] : undefined;
      return this.args.context?.getCards(
        this,
        () => query,
        () => realms,
      );
    };
    private cases = this.query(Case);
    private escalations = this.query(Escalation);
    private slas = this.query(Sla);
    private rows<T>(q: ReturnType<getCards> | undefined): T[] {
      return ((q?.instances ?? []) as T[]).filter(Boolean);
    }

    // Undefined while loading, so the metric and details render nothing.
    get s() {
      let lists = [this.cases, this.escalations, this.slas];
      if (lists.some((q) => !q || q.isLoading)) return undefined;
      let open = this.rows<Case>(this.cases).filter(
        (c) => c.status !== 'resolved' && c.status !== 'closed',
      );
      let awaiting = this.rows<Escalation>(this.escalations).filter(
        (e) => e.status === 'open',
      );
      let slas = this.rows<Sla>(this.slas);
      let met = slas.filter((s) =>
        (s.timers ?? []).some((t: any) => t.satisfiedAt),
      ).length;
      return {
        open: String(open.length),
        awaiting: String(awaiting.length),
        overdue: String(awaiting.filter((e) => e.ackOverdue === 'yes').length),
        met: `${met} of ${slas.length}`,
      };
    }

    get setupState(): string {
      let c = this.args.model?.config;
      return c?.setupCompletedAt
        ? 'Configured'
        : `Setup step ${c?.setupStep ?? 1}`;
    }
    get numbering(): string | undefined {
      let c = this.args.model?.config;
      let parts = [
        c?.identifierSeq != null ? `Next case no. ${c.identifierSeq + 1}` : '',
        c?.timeZone ?? '',
      ].filter(Boolean);
      return parts.length ? parts.join(' · ') : undefined;
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name={{if @model.title @model.title ''}}
            @hue='var(--primary)'
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.title}}</:title>
        <:subtitle>Clocks, ladders, ownership and workflow</:subtitle>
        <:status><StatusChip @value={{this.setupState}} /></:status>
        <:metric>{{#if this.s}}<Metric
              @value={{this.s.open}}
              @label='Open cases'
            />{{/if}}</:metric>
        <:fact>{{this.numbering}}</:fact>
        <:details>{{#if this.s}}
            <Detail @label='Awaiting ack' @value={{this.s.awaiting}} />
            <Detail @label='Ack overdue' @value={{this.s.overdue}} />
            <Detail @label='Clocks met' @value={{this.s.met}} />
          {{/if}}</:details>
        <:relations>
          {{#if @model.operator}}
            <@fields.operator @format='atom' @displayContainer={{false}} />
          {{/if}}
          {{#if @model.defaultWorkflow}}
            <@fields.defaultWorkflow
              @format='atom'
              @displayContainer={{false}}
            />
          {{/if}}
        </:relations>
      </RichFittedCard>
    </template>
  };
}

export default SupportCaseApp;
