import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  field,
  contains,
  containsMany,
  Component,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import TextAreaField from '@cardstack/base/text-area';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import enumField from '@cardstack/base/enum';
import GavelIcon from '@cardstack/boxel-icons/gavel';

import { ContractTypeField, contractTypeLabel } from './contract-type';
import { formatMoney } from '../commerce/line-item-totals';
import {
  AtomLayout,
  EmbLayout,
  Facts,
  IsoLayout,
  Mark,
  Rows,
  Section,
  Text,
  fitParts,
  stats,
  type Dot,
  type Fact,
  type Row,
} from './compact-card';
import { Dot as DotChip } from '../shared/compact-parts';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import { cap, longMoney, shortMoney } from '../shared/compact-format';
import { IsoFrame } from '../shared/compact-sheet';

/**
 * APPROVAL RULE — a declarative approval-routing engine.
 *
 *     IF contract_type = "Vendor" AND value > $100,000
 *       THEN require: [Legal] -> [Finance] -> [CFO]
 *
 * WHY THIS IS A CARD, not a config file. The rule that fired is the answer to
 * "why does this need my approval", and every researched CLM product models
 * that condition and then throws it away at render time, falling back to
 * instruction text a human typed. Keeping the rule as data means the app can
 * state the actual reason, and the reason cannot drift from the routing.
 *
 * CONDITIONS ARE AND-ED. Each populated condition must hold. That is a
 * deliberate limit: OR across rules is expressed by writing two rules, which
 * keeps each rule readable on its own. Nested boolean groups are not modelled —
 * they make a rule unreadable at exactly the moment someone is trying to work
 * out why they were asked to approve something.
 */

export interface RuleSubject {
  contractType?: string | null;
  value?: { amount?: number | null } | null;
  riskGrade?: string | null;
  deviationCount?: number | null;
  handlesSensitiveData?: boolean | null;
}

const RISK_ORDER = ['low', 'medium', 'high', 'critical'];

/**
 * The ordered grades, as a closed set.
 *
 * `ruleMatches` compares by INDEX in `RISK_ORDER`, so a value outside the set
 * scores -1 and the rule silently never fires. Free text here is therefore not
 * merely untidy — a typo disables the rule with no error anywhere.
 */
export const RiskGradeField = markDefinition(
  enumField(StringField, {
    options: RISK_ORDER.map((value) => ({
      value,
      label: value.charAt(0).toUpperCase() + value.slice(1),
    })),
    displayName: 'Minimum Risk Grade',
    icon: GavelIcon,
  }),
);

/* Defined ABOVE the class on purpose: `@field` decorators run at
   class-definition time, so a field type declared further down the module is
   still in its temporal dead zone and fails with
   "Cannot access 'RiskGradeField' before initialization" — at index time, not
   at lint or typecheck time. */

export class ApprovalRule extends CardDef {
  static displayName = 'Approval Rule';
  static icon = GavelIcon;

  @field ruleName = contains(StringField);

  /** Lower runs first when several rules match. */
  @field priority = contains(NumberField);
  @field isActive = contains(BooleanField);

  // ---- conditions (all populated ones must hold) ---------------------------

  @field appliesToTypes = containsMany(ContractTypeField);
  @field minValue = contains(AmountWithCurrency);
  @field minRiskGrade = contains(RiskGradeField);
  @field minDeviations = contains(NumberField);
  @field requiresSensitiveData = contains(BooleanField);

  // ---- outcome -------------------------------------------------------------

  /** Ordered approver roles: Legal -> Finance -> CFO. */
  @field requiredRoles = containsMany(StringField);
  @field isParallel = contains(BooleanField);
  @field guidance = contains(TextAreaField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ApprovalRule) {
      return this.ruleName ?? 'Untitled rule';
    },
  });

  static isolated = class Isolated extends Component<typeof ApprovalRule> {
    get v() {
      return ruleView(this.args.model);
    }
    <template>
      <IsoFrame>
        <IsoLayout
          @title={{this.v.title}}
          @subtitle={{this.v.subtitle}}
          @statuses={{this.v.statuses}}
          @stats={{this.v.stats}}
        >
          <:mark><Mark @text='AR' @size='lg' /></:mark>
          <:main>
            {{#if @model.guidance}}
              <Section @title='Guidance'><Text
                >{{@model.guidance}}</Text></Section>
            {{/if}}
            <Section @title='Required approvers' @flush={{true}}>
              {{#if this.v.steps.length}}
                <Rows @rows={{this.v.steps}} />
              {{else}}
                <Text>No approvers listed. A rule that fires and summons nobody
                  blocks the contract; add a role or deactivate the rule.</Text>
              {{/if}}
            </Section>
            <Section @title='Applies when'><Facts
                @items={{this.v.conditions}}
              /></Section>
          </:main>
          <:side>
            <Section @title='Details'><Facts
                @items={{this.v.details}}
              /></Section>
          </:side>
        </IsoLayout>
      </IsoFrame>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ApprovalRule> {
    get v() {
      return ruleView(this.args.model);
    }
    <template>
      <EmbLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.chain}}
        @facts={{this.v.embFacts}}
      >
        <:mark><Mark @text='AR' /></:mark>
      </EmbLayout>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ApprovalRule> {
    get v() {
      return ruleView(this.args.model);
    }
    get fit() {
      return fitParts(this.v.embFacts, this.v.fitStats);
    }
    <template>
      <RichFittedCard>
        <:avatar><Mark @text='AR' /></:avatar>
        <:title>{{this.v.title}}</:title>
        <:status>{{#if this.v.state}}<DotChip
              @label={{this.v.state.label}}
              @tone={{this.v.state.tone}}
            />{{/if}}</:status>
        <:subtitle>{{this.v.subtitle}}</:subtitle>
        <:fact>{{this.v.chain}}</:fact>
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

  static atom = class Atom extends Component<typeof ApprovalRule> {
    <template>
      <AtomLayout @title={{@model.cardTitle}}><:mark><Mark
            @text='AR'
            @size='sm'
          /></:mark></AtomLayout>
    </template>
  };
  /** The rule rendered as the sentence it will be explained with. */
  @field cardDescription = contains(StringField, {
    computeVia: function (this: ApprovalRule) {
      return describeRule(this);
    },
  });
}

/** Human-readable IF half, used both in the rule card and in the approver's banner. */
export function describeRule(r: any): string {
  let parts: string[] = [];
  let types = (r?.appliesToTypes ?? []).filter(Boolean);
  if (types.length) {
    parts.push(
      `type is ${types.map((t: string) => contractTypeLabel(t)).join(' or ')}`,
    );
  }
  let min = r?.minValue?.amount;
  if (typeof min === 'number') {
    parts.push(
      `value exceeds ${formatMoney(min, r?.minValue?.currency?.code)}`,
    );
  }
  if (r?.minRiskGrade) {
    parts.push(`risk is ${r.minRiskGrade} or higher`);
  }
  if (typeof r?.minDeviations === 'number' && r.minDeviations > 0) {
    parts.push(`it has ${r.minDeviations} or more clause deviations`);
  }
  if (r?.requiresSensitiveData) {
    parts.push('it handles sensitive personal data');
  }
  if (!parts.length) return 'applies to every contract';
  return parts.join(' and ');
}

/**
 * Does this rule fire for this contract?
 *
 * An unpopulated condition is skipped rather than treated as false — a rule
 * that only sets `minValue` must not silently require a contract type too.
 */
export function ruleMatches(rule: any, subject: RuleSubject): boolean {
  if (rule?.isActive === false) return false;

  let types = (rule?.appliesToTypes ?? []).filter(Boolean);
  if (types.length && !types.includes(subject.contractType ?? '')) return false;

  let min = rule?.minValue?.amount;
  if (typeof min === 'number') {
    let v = subject.value?.amount;
    if (typeof v !== 'number' || v <= min) return false;
  }

  if (rule?.minRiskGrade) {
    let need = RISK_ORDER.indexOf(rule.minRiskGrade);
    let got = RISK_ORDER.indexOf(subject.riskGrade ?? '');
    if (need < 0 || got < 0 || got < need) return false;
  }

  if (typeof rule?.minDeviations === 'number' && rule.minDeviations > 0) {
    if ((subject.deviationCount ?? 0) < rule.minDeviations) return false;
  }

  if (rule?.requiresSensitiveData && !subject.handlesSensitiveData)
    return false;

  return true;
}

/** Every rule that fires, in priority order, with the chain each demands. */
export function evaluateRules(rules: any[], subject: RuleSubject) {
  return (rules ?? [])
    .filter(Boolean)
    .filter((r) => ruleMatches(r, subject))
    .sort((a, b) => (a?.priority ?? 999) - (b?.priority ?? 999))
    .map((r) => ({
      rule: r,
      name: r?.ruleName ?? 'Untitled rule',
      because: describeRule(r),
      roles: (r?.requiredRoles ?? []).filter(Boolean) as string[],
      isParallel: Boolean(r?.isParallel),
    }));
}

/** The strings every ApprovalRule format shows, read once from the model. */
function ruleView(m?: Partial<ApprovalRule>) {
  let roles = (m?.requiredRoles ?? []).filter(Boolean) as string[];
  let parallel = Boolean(m?.isParallel);
  let order = parallel ? 'parallel' : 'sequential';
  let types = ((m?.appliesToTypes ?? []).filter(Boolean) as string[]).map((t) =>
    contractTypeLabel(t),
  );
  let min = m?.minValue?.amount;
  let code = m?.minValue?.currency?.code;
  let active = m?.isActive !== false;
  let priority = typeof m?.priority === 'number' ? String(m.priority) : '—';
  let details: Fact[] = [
    { key: 'Minimum value', value: longMoney(min, code), mono: true },
    { key: 'Applies to', value: types.length ? types.join(', ') : 'Any type' },
    { key: 'Approvers', value: roles.length ? roles.join(', ') : '—' },
    { key: 'Order', value: cap(order) },
    { key: 'Priority', value: priority, mono: true },
    { key: 'Status', value: active ? 'Active' : 'Inactive' },
  ];
  return {
    title: m?.cardTitle ?? 'Untitled rule',
    subtitle: `Priority ${priority} · ${order} · ${roles.length} approver${
      roles.length === 1 ? '' : 's'
    }`,
    state: {
      label: active ? 'active' : 'inactive',
      tone: active ? 'success' : 'neutral',
    } as Dot,
    statuses: [
      {
        label: active ? 'active' : 'inactive',
        tone: active ? 'success' : 'neutral',
      },
      ...types.map((t) => ({ label: t.toLowerCase() })),
    ] as Dot[],
    stats: stats([
      {
        label: 'Threshold',
        value: shortMoney(min, code),
        hint: types.length
          ? `${types.join(', ').toLowerCase()} contracts`
          : 'any contract',
      },
      {
        label: 'Approvers',
        value: String(roles.length),
        hint: roles.join(', '),
      },
      { label: 'Priority', value: priority, hint: order },
    ]),
    fitStats: [
      { key: 'Threshold', value: shortMoney(min, code) },
      { key: 'Approvers', value: String(roles.length) },
      { key: 'Priority', value: priority },
    ],
    chain: roles.length
      ? `${roles.join(' → ')}${parallel ? ', in any order' : ', one after another'}`
      : 'No approvers',
    steps: roles.map((r, i) => ({
      title: parallel ? r : `${i + 1} · ${r}`,
      dot: { label: parallel ? 'any order' : `step ${i + 1}`, tone: 'info' },
    })) as Row[],
    conditions: [
      { key: 'Contract type', value: types.length ? types.join(', ') : 'any' },
      {
        key: 'Value at least',
        value: typeof min === 'number' ? longMoney(min, code) : 'any',
        mono: typeof min === 'number',
      },
      {
        key: 'Risk at least',
        value: m?.minRiskGrade ? cap(m.minRiskGrade) : 'any',
      },
      {
        key: 'Sensitive data',
        value: m?.requiresSensitiveData ? 'required' : 'any',
      },
    ] as Fact[],
    details: [
      ...details,
      ...roles.map((r, i) => ({ key: `Step ${i + 1}`, value: r })),
    ],
    embFacts: details,
  };
}
