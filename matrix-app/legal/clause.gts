import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import MarkdownField from '@cardstack/base/markdown';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import { realmURL } from '@cardstack/base/card-api';
import { codeRef, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';

import {
  AtomLayout,
  EmbLayout,
  Facts,
  FitLayout,
  IsoLayout,
  Mark,
  Rows,
  Section,
  Text,
  cap,
  dash,
  dayAndYear,
  longDate,
  riskTone,
  stats,
  type Dot,
  type Fact,
  type Row,
  type StatItem,
} from './compact-card';
import type { Hue } from '@cardstack/catalog/components/state-pill';

/**
 * A pre-approved piece of contract language, owned by legal.
 *
 * This is the reference every ContractClause is measured against — it is what
 * turns "this wording looks unusual" into "this departs from the approved
 * liability cap, and here is the approved cap". Without a library there is no
 * such thing as a deviation, only an opinion.
 *
 * A Clause is NOT a contract term: it has no parties, no dates and no value.
 * It is a template fragment. The instance that appears in a signed agreement
 * is `ContractClause` (contract-clause.gts), which links back here.
 */

export const CLAUSE_TYPES = [
  'payment',
  'liability',
  'indemnification',
  'termination',
  'confidentiality',
  'data_protection',
  'force_majeure',
  'auto_renewal',
  'other',
];

export const CLAUSE_TYPE_LABELS: Record<string, string> = {
  payment: 'Payment terms',
  liability: 'Liability',
  indemnification: 'Indemnification',
  termination: 'Termination',
  confidentiality: 'Confidentiality',
  data_protection: 'Data protection',
  force_majeure: 'Force majeure',
  auto_renewal: 'Auto-renewal',
  other: 'Other',
};

export const ClauseTypeField = enumField(StringField, {
  options: CLAUSE_TYPES.map((value) => ({
    value,
    label: CLAUSE_TYPE_LABELS[value],
  })),
  displayName: 'Clause Type',
  icon: FileTextIcon,
});

/**
 * The risk a clause carries when used as written.
 *
 * Deliberately the same four grades as `RiskRatingField` (contract-risk.gts),
 * because a reader who has learned the contract palette should not have to
 * learn a second one for clauses. The vocabulary is shared; the arithmetic is
 * not — a clause's level is a legal judgement, a contract's grade is computed.
 */
export const CLAUSE_RISK_LEVELS = ['low', 'medium', 'high', 'critical'];

export const CLAUSE_RISK_HUE: Record<string, Hue> = {
  low: 'green',
  medium: 'amber',
  high: 'orange',
  critical: 'red',
};

export const ClauseRiskField = enumField(StringField, {
  options: CLAUSE_RISK_LEVELS.map((value) => ({
    value,
    label: value.charAt(0).toUpperCase() + value.slice(1),
  })),
  displayName: 'Clause Risk',
});

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;
/**
 * Built with `codeRef` rather than importing ContractClause: a static import
 * here would be a module cycle (contract-clause imports this file for
 * ClauseTypeField), and a thunk does not help because the cycle is at module
 * EVALUATION time, not at field-reference time.
 */
const CONTRACT_CLAUSE_REF = codeRef(
  here,
  './contract-clause',
  'ContractClause',
);

export function clauseTypeLabel(value?: string | null): string {
  return CLAUSE_TYPE_LABELS[value ?? ''] ?? value ?? '—';
}

export class Clause extends CardDef {
  static displayName = 'Clause';
  static icon = FileTextIcon;

  @field name = contains(StringField);
  @field clauseType = contains(ClauseTypeField);
  @field standardText = contains(MarkdownField);
  @field riskLevel = contains(ClauseRiskField);
  /** When to use it, and what must never be conceded without sign-off. */
  @field guidance = contains(TextAreaField);
  /** Which role may edit the approved text. */
  @field ownerRole = contains(StringField);
  /**
   * Approved language goes stale. A clause last reviewed before a regulation
   * changed is its own risk, so the date is a first-class field rather than
   * metadata.
   */
  @field reviewedAt = contains(DateField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Clause) {
      return this.name?.trim()?.length ? this.name : 'Untitled clause';
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: Clause) {
      return clauseTypeLabel(this.clauseType);
    },
  });

  /**
   * ATTRIBUTE-ONLY, deliberately.
   *
   * Prerendered fitted does not resolve `linksTo`, so a fitted that reaches for
   * a linked card renders as "Card Error" in any grid — the exact failure this
   * card would have hit without a fitted of its own, falling back to CardDef's
   * default. Everything below is a plain attribute or a computed string.
   *
   * The type scale is capped against `cqb` on `--type-base` itself rather than
   * per-role: in a wide+short cell the `cqi` term dominates and per-role `cqb`
   * caps never bind, which is how a headline outgrows its row and gets sheared.
   */

  static isolated = class Isolated extends Component<typeof Clause> {
    private usageQuery: ReturnType<getCards> | undefined;

    constructor(owner: Owner, args: any) {
      super(owner, args);
      this.usageQuery = this.args.context?.getCards(
        this,
        () => {
          let id = this.args.model?.id;
          if (!id) return undefined;
          return {
            filter: {
              on: CONTRACT_CLAUSE_REF,
              every: [{ eq: { 'standardClause.id': id } }],
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

    get usages(): any[] {
      return ((this.usageQuery as any)?.instances ?? []).filter(Boolean);
    }
    // A live query resolving after first paint is how a card asserts "used
    // nowhere" about data it has not received.
    get isCounting() {
      let q = this.usageQuery as any;
      return Boolean(q?.isLoading) && !this.usages.length;
    }
    // Without reading errors, a failed lookup is indistinguishable from zero.
    get lookupFailed() {
      return Boolean(((this.usageQuery as any)?.errors ?? []).length);
    }
    get deviations() {
      return this.usages.filter((u) => u.isDeviation);
    }
    get v() {
      return clauseView(this.args.model);
    }
    get stats(): StatItem[] {
      let first = this.deviations[0];
      return stats([
        {
          label: 'Risk',
          value: cap(this.args.model?.riskLevel),
          hint: 'library rating',
        },
        {
          label: 'Deviations',
          value: String(this.deviations.length),
          hint:
            first?.contract?.cardTitle ??
            (this.usages.length ? 'none open' : 'not in use'),
        },
        {
          label: 'Reviewed',
          value: this.v.reviewed[0],
          hint: this.v.reviewed[1],
        },
      ]);
    }
    get rows(): Row[] {
      return this.usages.map((u) => ({
        title: u.contract?.cardTitle ?? u.cardTitle ?? 'Contract',
        sub: u.isDeviation
          ? (u.deviationNotes ?? u.cardDescription)
          : 'Standard clause',
        dot: u.isDeviation
          ? { label: u.deviationSeverity ?? 'deviation', tone: 'danger' }
          : { label: 'standard', tone: 'info' },
      }));
    }
    get details(): Fact[] {
      return [
        ...this.v.facts,
        { key: 'In use', value: String(this.usages.length), mono: true },
        {
          key: 'Deviations',
          value: String(this.deviations.length),
          mono: true,
        },
      ];
    }
    <template>
      <IsoLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @statuses={{this.v.statuses}}
        @stats={{this.stats}}
      >
        <:mark><Mark @text='Cl' @size='lg' /></:mark>
        <:main>
          <Section @title='Standard text'><@fields.standardText /></Section>
          {{#if @model.guidance}}
            <Section @title='Guidance'><Text
              >{{@model.guidance}}</Text></Section>
          {{/if}}
          <Section @title='In use' @flush={{true}}>
            {{#if this.lookupFailed}}
              <Rows @rows={{this.failedRows}} />
            {{else if this.isCounting}}
              <Rows @rows={{this.countingRows}} />
            {{else if this.rows.length}}
              <Rows @rows={{this.rows}} />
            {{else}}
              <Rows @rows={{this.unusedRows}} />
            {{/if}}
          </Section>
        </:main>
        <:side>
          <Section @title='Details'><Facts @items={{this.details}} /></Section>
        </:side>
      </IsoLayout>
    </template>
    failedRows: Row[] = [
      {
        title: 'Could not look up where this clause is used',
        sub: 'A failed query, not an unused clause; reload before changing it.',
        dot: { label: 'error', tone: 'danger' },
      },
    ];
    countingRows: Row[] = [{ title: 'Counting contracts…' }];
    unusedRows: Row[] = [{ title: 'Not used in any contract yet' }];
  };

  static embedded = class Embedded extends Component<typeof Clause> {
    <template>
      {{#let (clauseView @model) as |v|}}
        <EmbLayout
        @title={{v.title}}
        @subtitle={{v.subtitle}}
        @status={{v.state}}
        @fact={{v.fact}}
        @facts={{v.facts}}
      >
        <:mark><Mark @text='Cl' /></:mark>
      </EmbLayout>
      {{/let}}
    </template>
  };

  static fitted = class Fitted extends Component<typeof Clause> {
    <template>
      {{#let (clauseView @model) as |v|}}
        <FitLayout
        @title={{v.title}}
        @subtitle={{v.subtitle}}
        @status={{v.state}}
        @fact={{v.fact}}
        @facts={{v.facts}}
        @stats={{v.fitStats}}
      >
        <:mark><Mark @text='Cl' /></:mark>
      </FitLayout>
      {{/let}}
    </template>
  };

  static atom = class Atom extends Component<typeof Clause> {
    <template>
      <AtomLayout @title={{@model.cardTitle}}><:mark><Mark
            @text='Cl'
            @size='sm'
          /></:mark></AtomLayout>
    </template>
  };
}

/** The strings every Clause format shows, read once from the model. */
function clauseView(m?: Partial<Clause>) {
  let type = clauseTypeLabel(m?.clauseType);
  let risk = m?.riskLevel;
  let owner = m?.ownerRole;
  let reviewed = dayAndYear(m?.reviewedAt);
  return {
    title: m?.cardTitle ?? 'Untitled clause',
    subtitle: [type, owner ? `owned by ${owner}` : undefined]
      .filter(Boolean)
      .join(' · '),
    state: {
      label: risk ? `${risk} risk` : 'unrated',
      tone: riskTone(risk),
    } as Dot,
    statuses: [
      { label: risk ? `${risk} risk` : 'unrated', tone: riskTone(risk) },
      { label: type.toLowerCase() },
    ] as Dot[],
    fact: m?.reviewedAt
      ? `Reviewed ${longDate(m.reviewedAt)}`
      : 'Never reviewed',
    reviewed,
    fitStats: [
      { key: 'Risk', value: cap(risk) },
      { key: 'Reviewed', value: reviewed[0] },
      { key: 'Type', value: type },
    ],
    facts: [
      { key: 'Type', value: type },
      { key: 'Risk', value: cap(risk) },
      { key: 'Owner', value: dash(owner) },
      { key: 'Reviewed', value: longDate(m?.reviewedAt), mono: true },
    ] as Fact[],
  };
}

export default Clause;
