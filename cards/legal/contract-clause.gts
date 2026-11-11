import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import type { Hue } from './compact-card';
import BooleanField from '@cardstack/base/boolean';
import MarkdownField from '@cardstack/base/markdown';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import ScrollTextIcon from '@cardstack/boxel-icons/scroll-text';

import { Clause, ClauseTypeField, clauseTypeLabel } from './clause';
import { Contract } from './contract';
import {
  AtomLayout,
  EmbLayout,
  Facts,
  FitLayout,
  IsoLayout,
  LinkRow,
  Mark,
  Section,
  Text,
  stats,
  type Dot,
  type Fact,
} from './compact-card';
import { cap, dash, type Tone } from '../shared/compact-format';
import { IsoFrame } from '../shared/compact-sheet';

/**
 * What THIS contract actually says for one provision, next to what it was
 * supposed to say.
 *
 * DESIGN NOTE — why `deviationSeverity` is stored and `isDeviation` is not.
 *
 * The obvious design computes `isDeviation` by string-comparing `actualText`
 * against the linked standard. Two things break it. First, a link may not be
 * loaded when the computed runs, so the flag would silently flip to "no
 * deviation" for a contract whose standard clause simply had not resolved yet
 * — the worst possible direction for a compliance signal to fail in. Second,
 * and more fundamentally, a diff is not a judgement: reordering a sentence or
 * fixing a typo changes the string without changing the obligation, while one
 * inserted word ("shall" → "shall not") reverses it.
 *
 * So the severity is a lawyer's call, recorded once, and everything else is
 * derived from it locally. No link traversal, nothing to drift.
 */

export const DEVIATION_SEVERITIES = ['none', 'minor', 'major', 'bespoke'];

export const DEVIATION_SEVERITY_LABELS: Record<string, string> = {
  none: 'Standard',
  minor: 'Minor deviation',
  major: 'Major deviation',
  bespoke: 'Bespoke — no standard',
};

export const DEVIATION_SEVERITY_HUE: Record<string, Hue> = {
  none: 'green',
  minor: 'amber',
  major: 'red',
  bespoke: 'purple',
};

export const DeviationSeverityField = markDefinition(
  enumField(StringField, {
    options: DEVIATION_SEVERITIES.map((value) => ({
      value,
      label: DEVIATION_SEVERITY_LABELS[value],
    })),
    displayName: 'Deviation',
  }),
);

/**
 * Severity → the risk this clause contributes, when no standard is linked to
 * inherit from. A bespoke clause with no approved reference is treated as high
 * rather than unknown: language nobody has approved is the definition of an
 * unreviewed exposure.
 */
const SEVERITY_RISK: Record<string, string> = {
  none: 'low',
  minor: 'medium',
  major: 'critical',
  bespoke: 'high',
};

export function deviationLabel(value?: string | null): string {
  return DEVIATION_SEVERITY_LABELS[value ?? ''] ?? 'Not assessed';
}

export class ContractClause extends CardDef {
  static displayName = 'Contract Clause';
  static icon = ScrollTextIcon;

  // Thunked on both sides — Contract links back to its clauses, and a cycle
  // across two modules needs the lazy form at each end or one of them
  // resolves to undefined at load time.
  @field contract = linksTo(() => Contract);
  /** Absent means bespoke language with no approved reference. */
  @field standardClause = linksTo(() => Clause);

  /**
   * Denormalised from the standard on purpose: a bespoke clause has no
   * standard to read a type from, and it still has to be classifiable — a
   * liability clause nobody approved is exactly the one worth finding.
   */
  @field clauseType = contains(ClauseTypeField);
  @field actualText = contains(MarkdownField);

  @field deviationSeverity = contains(DeviationSeverityField);
  /** Why it differs, and who conceded it. Required in practice on major. */
  @field deviationNotes = contains(TextAreaField);

  @field isDeviation = contains(BooleanField, {
    computeVia: function (this: ContractClause) {
      let s = this.deviationSeverity;
      return Boolean(s) && s !== 'none';
    },
  });

  @field riskLevel = contains(StringField, {
    computeVia: function (this: ContractClause) {
      return SEVERITY_RISK[this.deviationSeverity ?? ''] ?? 'low';
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ContractClause) {
      return clauseTypeLabel(this.clauseType);
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: ContractClause) {
      return deviationLabel(this.deviationSeverity);
    },
  });

  static isolated = class Isolated extends Component<typeof ContractClause> {
    get v() {
      return ccView(this.args.model);
    }
    <template>
      <IsoFrame>
        <IsoLayout
          @title={{this.v.title}}
          @subtitle={{this.v.subtitle}}
          @statuses={{this.v.statuses}}
          @stats={{this.v.stats}}
        >
          <:mark><Mark @text='CC' @size='lg' /></:mark>
          <:main>
            <Section @title='Actual text'><@fields.actualText /></Section>
            {{#if @model.deviationNotes}}
              <Section @title='Deviation notes'><Text
                >{{@model.deviationNotes}}</Text></Section>
            {{/if}}
            {{#if @model.standardClause}}
              <Section @title='Playbook text'><Text
                >{{@model.standardClause.standardText}}</Text></Section>
            {{else}}
              <Section @title='Playbook text'><Text>Bespoke language: no
                  approved standard to compare against.</Text></Section>
            {{/if}}
          </:main>
          <:side>
            <Section @title='Linked'>
              <LinkRow @label='Contract'><@fields.contract
                  @format='atom'
                  @displayContainer={{false}}
                /></LinkRow>
              <LinkRow @label='Standard'><@fields.standardClause
                  @format='atom'
                  @displayContainer={{false}}
                /></LinkRow>
            </Section>
            <Section @title='Details'><Facts
                @items={{this.v.facts}}
              /></Section>
          </:side>
        </IsoLayout>
      </IsoFrame>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ContractClause> {
    get v() {
      return ccView(this.args.model);
    }
    <template>
      <FitLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.fact}}
        @facts={{this.v.facts}}
        @stats={{this.v.fitStats}}
      >
        <:mark><Mark @text='CC' /></:mark>
      </FitLayout>
    </template>
  };

  static atom = class Atom extends Component<typeof ContractClause> {
    get v() {
      return ccView(this.args.model);
    }
    <template>
      <AtomLayout @title={{this.v.title}}><:mark><Mark
            @text='CC'
            @size='sm'
          /></:mark></AtomLayout>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ContractClause> {
    get v() {
      return ccView(this.args.model);
    }
    <template>
      <EmbLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.fact}}
        @facts={{this.v.facts}}
      >
        <:mark><Mark @text='CC' /></:mark>
        <:linked>
          <LinkRow @label='Contract'><@fields.contract
              @format='atom'
              @displayContainer={{false}}
            /></LinkRow>
          <LinkRow @label='Standard'><@fields.standardClause
              @format='atom'
              @displayContainer={{false}}
            /></LinkRow>
        </:linked>
      </EmbLayout>
    </template>
  };
}

const SEVERITY_TONE: Record<string, Tone> = {
  none: 'success',
  minor: 'warning',
  major: 'danger',
  bespoke: 'danger',
};

/** The strings every ContractClause format shows, read once from the model. */
function ccView(m?: Partial<ContractClause>) {
  let type = clauseTypeLabel(m?.clauseType);
  let sev = m?.deviationSeverity ?? undefined;
  let sevLabel = deviationLabel(sev);
  let contract = m?.contract?.cardTitle as string | undefined;
  let standard = m?.standardClause?.cardTitle as string | undefined;
  let playbookRisk = m?.standardClause?.riskLevel as string | undefined;
  let notes = m?.deviationNotes ?? '';
  let firstSentence = notes.split(/(?<=\.)\s/)[0];
  let state: Dot = {
    label: m?.isDeviation ? `${sevLabel.toLowerCase()}` : 'standard',
    tone: SEVERITY_TONE[sev ?? ''] ?? 'neutral',
  };
  return {
    title: contract ? `${type} — ${contract}` : type,
    subtitle: standard ? `Against ${standard}` : 'Bespoke language',
    state,
    statuses: [state, { label: type.toLowerCase() }] as Dot[],
    fact: firstSentence || sevLabel,
    stats: stats([
      { label: 'Deviation', value: cap(sev), hint: 'from the clause library' },
      {
        label: 'Clause type',
        value: type,
        hint: playbookRisk ? `playbook risk ${playbookRisk}` : undefined,
      },
      { label: 'Risk', value: cap(m?.riskLevel), hint: 'from the deviation' },
    ]),
    fitStats: [
      { key: 'Deviation', value: cap(sev) },
      { key: 'Clause type', value: type },
      { key: 'Risk', value: cap(m?.riskLevel) },
    ],
    facts: [
      { key: 'Type', value: type },
      { key: 'Deviation', value: sevLabel },
      { key: 'Standard', value: dash(standard) },
      { key: 'Contract', value: dash(contract) },
      { key: 'Playbook risk', value: cap(playbookRisk) },
      { key: 'Risk', value: cap(m?.riskLevel) },
    ] as Fact[],
  };
}

export default ContractClause;
