import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  field,
  contains,
  linksTo,
  Component,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import DateTimeField from '@cardstack/base/datetime';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import HistoryIcon from '@cardstack/boxel-icons/history';

import { Employee } from '../hr/employee';
import { realmURL } from '@cardstack/base/card-api';
import { codeRef, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import {
  AtomLayout,
  EmbLayout,
  Facts,
  IsoLayout,
  LinkRow,
  Mark,
  Rows,
  Section,
  Text,
  fitParts,
  stats,
  type Dot,
  type Fact,
  type Row,
} from '../legal/compact-card';
import { Dot as DotChip } from '../shared/compact-parts';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import {
  dayAndYear,
  formatDateTime,
  type Tone,
} from '../shared/compact-format';
import { IsoFrame } from '../shared/compact-sheet';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;
const ENTRY_REF = codeRef(here, './audit-entry', 'AuditEntry');

/**
 * AUDIT ENTRY — the append-only record of what happened to a contract.
 *
 * WHY THIS IS ITS OWN CARD, not a field on Contract.
 * An audit trail's whole value is that it cannot be rewritten by the thing it
 * describes. A `containsMany` on Contract would be edited in the same save as
 * the contract itself, so "who approved this and when" would be as mutable as
 * the contract body — which is exactly the claim an auditor is trying to test.
 * A separate card with its own id gives each event a stable address that
 * survives edits to the contract.
 *
 * WHAT IS CONSUMED. `Employee` for the actor, `StatePill` for the action chip.
 * No new vocabulary is invented for either.
 *
 * WHAT IS NOT MODELLED. Nothing enforces append-only at the platform level —
 * the realm has no immutable-record primitive — so this is a convention the app
 * honours rather than a guarantee the storage makes. Said plainly here because
 * an audit trail that is only conventionally immutable must not be described as
 * if it were tamper-proof.
 */

// The vocabulary itself lives in utils/audit-action-vocabulary so components
// can read labels and hues without importing this card. Re-exported here:
// every existing importer of these names is unaffected.
export {
  AUDIT_ACTIONS,
  auditActionLabel,
  auditActionHue,
} from './utils/audit-action-vocabulary';
import {
  AUDIT_ACTIONS,
  auditActionLabel,
  auditActionHue,
} from './utils/audit-action-vocabulary';

/**
 * A closed vocabulary, not free text.
 *
 * An audit trail whose action column accepts anything cannot be filtered,
 * charted or trusted — one entry saying "approved" and another "Approved!!"
 * are the same event to a person and two different events to a query.
 */
export const AuditActionField = markDefinition(
  enumField(StringField, {
    options: AUDIT_ACTIONS.map((a) => ({ value: a.value, label: a.label })),
    displayName: 'Audit Action',
    icon: HistoryIcon,
  }),
);

export class AuditEntry extends CardDef {
  static displayName = 'Audit Entry';
  static icon = HistoryIcon;

  @field action = contains(AuditActionField);
  /**
   * Who did the thing.
   *
   * Named `doneBy` rather than `actor`: the edit form takes its label straight
   * from the field name, and "Actor" is a system word that made a reader ask
   * what it meant. "Done by" works for every action in the vocabulary —
   * created, approved, signed, amended, terminated.
   */
  @field doneBy = linksTo(() => Employee);
  @field occurredAt = contains(DateTimeField);

  /**
   * What the entry is about — a real link, not a stored id.
   *
   * An id string cannot be navigated to, cannot be queried with
   * `{ eq: { 'subject.id': ... } }`, and gives the reader no way to open the
   * thing being audited. The earlier version stored one to keep the entry
   * readable after the contract is deleted; a broken link renders as a broken
   * link and the snapshot below preserves what it was called, so that argument
   * bought nothing that `subjectTitle` was not already buying.
   *
   * Typed CardDef, not Contract: an audit trail is raised over whatever was
   * audited — a contract, a vendor profile, a site, a Spec — and a link typed
   * to one domain card would leave every other subject unlinkable.
   */
  @field subject = linksTo(CardDef);

  /**
   * The subject's title AS AT the moment of the entry.
   *
   * Deliberately denormalised. Reading through the link would show today's
   * title, and an audit trail is supposed to say what the thing was called
   * when the decision was made.
   */
  @field subjectTitle = contains(StringField);

  /** The reason given at the time. Never back-filled. */
  @field note = contains(TextAreaField);

  /** Set when the action was `approved_with_conditions`. */
  @field conditions = contains(TextAreaField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AuditEntry) {
      let who = this.doneBy?.cardTitle ?? 'Someone';
      return `${who} — ${auditActionLabel(this.action)}`;
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: AuditEntry) {
      return this.subjectTitle ?? '';
    },
  });

  static isolated = class Isolated extends Component<typeof AuditEntry> {
    // every entry on the same subject, oldest first: the trail
    private trailQuery: ReturnType<getCards> | undefined;

    constructor(owner: Owner, args: any) {
      super(owner, args);
      this.trailQuery = this.args.context?.getCards(
        this,
        () => {
          let id = this.args.model?.subject?.id;
          if (!id) return undefined;
          return {
            filter: {
              on: ENTRY_REF,
              every: [{ eq: { 'subject.id': id } }],
            },
          };
        },
        () => this.realms,
        { isLive: true },
      );
    }

    private get realms(): string[] | undefined {
      let url = (this.args.model as any)?.[realmURL];
      return url ? [url.href] : undefined;
    }

    get trail(): any[] {
      return ((this.trailQuery as any)?.instances ?? [])
        .filter(Boolean)
        .sort(
          (a: any, b: any) =>
            new Date(a.occurredAt ?? 0).getTime() -
            new Date(b.occurredAt ?? 0).getTime(),
        );
    }
    get position(): string {
      let i = this.trail.findIndex((e) => e.id === this.args.model?.id);
      return this.trail.length
        ? `${i + 1} of ${this.trail.length} on this subject`
        : '—';
    }
    get v() {
      return entryView(this.args.model, this.trail.length);
    }
    get rows(): Row[] {
      return this.trail.map((e) => ({
        title: [auditActionLabel(e.action), e.doneBy?.cardTitle]
          .filter(Boolean)
          .join(' · '),
        sub: [formatDateTime(e.occurredAt), e.note].filter(Boolean).join(' · '),
        dot: {
          label: auditActionLabel(e.action).toLowerCase(),
          tone: actionTone(e.action),
        },
      }));
    }
    get facts(): Fact[] {
      return [...this.v.facts, { key: 'Trail', value: this.position }];
    }
    <template>
      <IsoFrame>
        <IsoLayout
          @title={{this.v.title}}
          @subtitle={{this.v.subtitle}}
          @statuses={{this.v.statuses}}
          @stats={{this.v.stats}}
        >
          <:mark><Mark @text='Au' @size='lg' /></:mark>
          <:main>
            {{#if @model.note}}
              <Section @title='Note'><Text>{{@model.note}}</Text></Section>
            {{/if}}
            {{#if @model.conditions}}
              <Section @title='Conditions'><Text
                >{{@model.conditions}}</Text></Section>
            {{/if}}
            {{#if this.rows.length}}
              <Section @title='Trail for this subject' @flush={{true}}><Rows
                  @rows={{this.rows}}
                /></Section>
            {{/if}}
          </:main>
          <:side>
            <Section @title='Linked'>
              <LinkRow @label='Subject'><@fields.subject
                  @format='atom'
                  @displayContainer={{false}}
                /></LinkRow>
              <LinkRow @label='By'><@fields.doneBy
                  @format='atom'
                  @displayContainer={{false}}
                /></LinkRow>
            </Section>
            <Section @title='Details'><Facts @items={{this.facts}} /></Section>
          </:side>
        </IsoLayout>
      </IsoFrame>
    </template>
  };

  static embedded = class Embedded extends Component<typeof AuditEntry> {
    get v() {
      return entryView(this.args.model);
    }
    <template>
      <EmbLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.fact}}
        @facts={{this.v.facts}}
      >
        <:mark><Mark @text='Au' /></:mark>
        <:linked>
          <LinkRow @label='By'><@fields.doneBy
              @format='atom'
              @displayContainer={{false}}
            /></LinkRow>
        </:linked>
      </EmbLayout>
    </template>
  };

  static fitted = class Fitted extends Component<typeof AuditEntry> {
    get v() {
      return entryView(this.args.model);
    }
    get fit() {
      return fitParts(this.v.facts, this.v.fitStats);
    }
    <template>
      <RichFittedCard>
        <:avatar><Mark @text='Au' /></:avatar>
        <:title>{{this.v.title}}</:title>
        <:status>{{#if this.v.state}}<DotChip
              @label={{this.v.state.label}}
              @tone={{this.v.state.tone}}
            />{{/if}}</:status>
        <:subtitle>{{this.v.subtitle}}</:subtitle>
        <:fact>{{this.v.fact}}</:fact>
        <:metric>{{#if this.fit.metric}}<Metric
              @value={{this.fit.metric.value}}
              @label={{this.fit.metric.key}}
            />{{/if}}</:metric>
        <:details>{{#each this.fit.details as |d|}}<Detail
              @label={{d.key}}
              @value={{d.value}}
            />{{/each}}</:details>
      </RichFittedCard>
    </template>
  };

  static atom = class Atom extends Component<typeof AuditEntry> {
    get v() {
      return entryView(this.args.model);
    }
    <template>
      <AtomLayout @title={{this.v.title}}><:mark><Mark
            @text='Au'
            @size='sm'
          /></:mark></AtomLayout>
    </template>
  };
}

const HUE_TONE: Record<string, Tone> = {
  green: 'success',
  teal: 'warning',
  blue: 'info',
  amber: 'warning',
  orange: 'warning',
  red: 'danger',
};
function actionTone(action?: string | null): Tone {
  return HUE_TONE[auditActionHue(action)] ?? 'neutral';
}

/** The strings every AuditEntry format shows, read once from the model. */
function entryView(m?: Partial<AuditEntry>, trailCount?: number) {
  let label = auditActionLabel(m?.action);
  let [head, ...rest] = label.split(' ');
  let who = m?.doneBy?.cardTitle as string | undefined;
  let when = formatDateTime(m?.occurredAt);
  let [day, year] = dayAndYear(m?.occurredAt);
  let time = when.split(', ').pop() ?? '';
  let state: Dot = { label: label.toLowerCase(), tone: actionTone(m?.action) };
  return {
    title: label,
    subtitle: [m?.subjectTitle, when].filter(Boolean).join(' · '),
    state,
    statuses: [state],
    fact: [who ? `By ${who}` : undefined, m?.conditions ?? m?.note]
      .filter(Boolean)
      .join(' · '),
    stats: stats([
      { label: 'Action', value: head, hint: rest.join(' ') || undefined },
      {
        label: 'When',
        value: day,
        hint: [year, time].filter(Boolean).join(' · '),
      },
      {
        label: 'By',
        value: who ?? '—',
        hint: trailCount ? `${trailCount} entries on this subject` : undefined,
      },
    ]),
    fitStats: [
      { key: 'Action', value: head },
      { key: 'When', value: day },
      { key: 'By', value: who ?? '—' },
    ],
    facts: [
      { key: 'Action', value: label },
      { key: 'When', value: when || '—', mono: true },
      { key: 'By', value: who ?? '—' },
      { key: 'Subject', value: m?.subjectTitle ?? '—' },
      ...(m?.conditions ? [{ key: 'Condition', value: m.conditions }] : []),
      ...(m?.note ? [{ key: 'Note', value: m.note }] : []),
    ] as Fact[],
  };
}
