import {
  CardDef,
  field,
  contains,
  containsMany,
  linksToMany,
  Component,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import BooleanField from '@cardstack/base/boolean';
import TextAreaField from '@cardstack/base/text-area';
import MarkdownField from '@cardstack/base/markdown';
import DateField from '@cardstack/base/date';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import { ContractTypeField, contractTypeLabel } from './contract-type';
import { Clause, clauseTypeLabel } from './clause';
import {
  AtomLayout,
  Dots,
  EmbLayout,
  Facts,
  FitLayout,
  IsoLayout,
  LinkRow,
  Mark,
  Rows,
  Section,
  Text,
  riskTone,
  stats,
  type Dot,
  type Fact,
  type Row,
} from './compact-card';
import { dayAndYear, formatDay } from '../shared/compact-format';

/**
 * CONTRACT TEMPLATE — the standard starting points for a new contract.
 *
 * WHAT THIS IS NOT. Generating the document is Generate Document's job, so a
 * template here is a *starting position*, not a document factory: which
 * type it is for, which approved clauses it assumes, and the guidance a drafter
 * needs. It does not render a contract.
 *
 * WHAT IS CONSUMED. `Clause` for the standard language — a template that
 * retyped its own clause text would let the library and the templates disagree,
 * which is the drift the clause library exists to prevent.
 */
export class ContractTemplate extends CardDef {
  static displayName = 'Contract Template';
  static icon = FileTextIcon;

  @field templateName = contains(StringField);
  @field contractType = contains(ContractTypeField);
  @field useCase = contains(StringField);
  @field bodyMarkdown = contains(MarkdownField);
  @field guidance = contains(TextAreaField);

  /** Clauses this template assumes. Linked, never copied. */
  @field standardClauses = linksToMany(() => Clause);

  /** Fields a drafter must supply before this can be used. */
  @field requiredInputs = containsMany(StringField);

  /**
   * Published templates are the ones a drafter may pick.
   *
   * Juro's publish/unpublish exists so a standard cannot change under a review
   * that is already running; the same reasoning applies to a template.
   */
  @field isPublished = contains(BooleanField);
  @field lastReviewedAt = contains(DateField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ContractTemplate) {
      return this.templateName ?? contractTypeLabel(this.contractType);
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: ContractTemplate) {
      return this.useCase ?? '';
    },
  });

  static isolated = class Isolated extends Component<typeof ContractTemplate> {
    get v() {
      return templateView(this.args.model);
    }
    <template>
      <IsoLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @statuses={{this.v.statuses}}
        @stats={{this.v.stats}}
      >
        <:mark><Mark @text='Tp' @size='lg' /></:mark>
        <:main>
          {{#if @model.guidance}}
            <Section @title='Guidance'><Text
              >{{@model.guidance}}</Text></Section>
          {{/if}}
          <Section @title='Required inputs' @flush={{true}}>
            {{#if this.v.inputs.length}}
              <Dots @items={{this.v.inputs}} />
            {{else}}
              <Rows @rows={{this.v.noInputs}} />
            {{/if}}
          </Section>
          <Section @title='Standard clauses' @flush={{true}}>
            <Rows @rows={{this.v.clauses}} />
          </Section>
        </:main>
        <:side>
          {{#if this.v.clauses.length}}
            <Section @title='Linked'>
              {{#each @fields.standardClauses as |C|}}
                <LinkRow @label='Clause'><C
                    @format='atom'
                    @displayContainer={{false}}
                  /></LinkRow>
              {{/each}}
            </Section>
          {{/if}}
          <Section @title='Details'><Facts @items={{this.v.facts}} /></Section>
        </:side>
      </IsoLayout>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ContractTemplate> {
    get v() {
      return templateView(this.args.model);
    }
    <template>
      <EmbLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.fact}}
        @facts={{this.v.facts}}
      >
        <:mark><Mark @text='Tp' /></:mark>
      </EmbLayout>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ContractTemplate> {
    get v() {
      return templateView(this.args.model);
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
        <:mark><Mark @text='Tp' /></:mark>
      </FitLayout>
    </template>
  };

  static atom = class Atom extends Component<typeof ContractTemplate> {
    <template>
      <AtomLayout @title={{@model.cardTitle}}><:mark><Mark
            @text='Tp'
            @size='sm'
          /></:mark></AtomLayout>
    </template>
  };
}

/** The strings every ContractTemplate format shows, read once from the model. */
function templateView(m?: Partial<ContractTemplate>) {
  let type = contractTypeLabel(m?.contractType);
  let inputs = (m?.requiredInputs ?? []).filter(Boolean) as string[];
  let clauses = (m?.standardClauses ?? []).filter(Boolean);
  let published = Boolean(m?.isPublished);
  let [day, year] = dayAndYear(m?.lastReviewedAt);
  let state: Dot = {
    label: published ? 'published' : 'draft',
    tone: published ? 'success' : 'neutral',
  };
  return {
    title: m?.cardTitle ?? 'Untitled template',
    subtitle: [m?.useCase, type.toLowerCase()].filter(Boolean).join(' · '),
    state,
    statuses: [
      state,
      { label: `${clauses.length} clause${clauses.length === 1 ? '' : 's'}` },
    ] as Dot[],
    fact: [
      m?.lastReviewedAt
        ? `Reviewed ${formatDay(m.lastReviewedAt)}`
        : 'Never reviewed',
      `${inputs.length} required input${inputs.length === 1 ? '' : 's'}`,
    ].join(' · '),
    stats: stats([
      {
        label: 'Clauses',
        value: String(clauses.length),
        hint: 'from the library',
      },
      {
        label: 'Inputs',
        value: String(inputs.length),
        hint: 'asked at drafting',
      },
      { label: 'Reviewed', value: day, hint: year },
    ]),
    fitStats: [
      { key: 'Clauses', value: String(clauses.length) },
      { key: 'Inputs', value: String(inputs.length) },
      { key: 'Reviewed', value: day },
    ],
    inputs: inputs.map((label) => ({ label })) as Dot[],
    noInputs: [
      {
        title: 'No inputs stated',
        sub: 'Write down what a drafter must supply.',
      },
    ] as Row[],
    clauses: clauses.map((c) => ({
      title: c.cardTitle ?? 'Clause',
      sub: [
        clauseTypeLabel(c.clauseType),
        c.ownerRole ? `owned by ${c.ownerRole}` : undefined,
      ]
        .filter(Boolean)
        .join(' · '),
      dot: { label: c.riskLevel ?? 'unrated', tone: riskTone(c.riskLevel) },
    })) as Row[],
    facts: [
      { key: 'Type', value: type },
      { key: 'Published', value: published ? 'Yes' : 'No' },
      { key: 'Last reviewed', value: formatDay(m?.lastReviewedAt), mono: true },
      { key: 'Inputs', value: String(inputs.length), mono: true },
      { key: 'Clauses', value: String(clauses.length), mono: true },
    ] as Fact[],
  };
}
