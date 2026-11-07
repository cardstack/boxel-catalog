import {
  CardDef,
  field,
  contains,
  linksTo,
  Component,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import UrlField from '@cardstack/base/url';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import ScrollTextIcon from '@cardstack/boxel-icons/scroll-text';

import { Employee } from '../hr/employee';
import { Contract } from './contract';
import { realmURL } from '@cardstack/base/card-api';
import { codeRef, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import {
  AtomLayout,
  EmbLayout,
  Facts,
  FitLayout,
  IsoLayout,
  LinkRow,
  Mark,
  Rows,
  Section,
  Text,
  stats,
  type Dot,
  type Fact,
  type Row,
} from './compact-card';
import {
  dayAndYear,
  formatDay,
  longMoney,
  shortMoney,
} from '../shared/compact-format';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;
const VERSION_REF = codeRef(here, './contract-version', 'ContractVersion');

/**
 * CONTRACT VERSION — an amendment record, so "version history" is a history
 * rather than a lineage.
 *
 * WHAT WAS THERE BEFORE. `Contract.parentContract` gives the chain from an
 * amendment back to its master, which answers "what is this an amendment TO".
 * It does not answer "what CHANGED, when, and who signed it" — and that second
 * question is the one an auditor and a renewal reviewer both actually ask.
 *
 * WHY THE CHANGED VALUES ARE STORED, not derived. Reading the current contract
 * tells you where things ended up; it cannot tell you what the value was before
 * amendment 2, because the contract has since been edited. A version record
 * that recomputed from the live card would show today's numbers on every row
 * and quietly claim nothing ever changed.
 */
export class ContractVersion extends CardDef {
  static displayName = 'Contract Version';
  static icon = ScrollTextIcon;

  /** A real link, so a reader can open the contract this version belongs to. */
  @field contract = linksTo(() => Contract);

  /** The title as at this version — a snapshot, not a read-through. */
  @field contractTitle = contains(StringField);

  @field versionNumber = contains(NumberField);
  @field effectiveDate = contains(DateField);
  @field executedBy = linksTo(() => Employee);
  @field documentUrl = contains(UrlField);

  /** What this version changed, in the drafter's words. */
  @field summary = contains(TextAreaField);

  /** Values AS AT this version — snapshots, never recomputed. */
  @field valueAtVersion = contains(AmountWithCurrency);
  @field endDateAtVersion = contains(DateField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ContractVersion) {
      let n = this.versionNumber;
      let label = n === 1 ? 'Original' : `Amendment ${(n ?? 1) - 1}`;
      return this.contractTitle ? `${this.contractTitle} — ${label}` : label;
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: ContractVersion) {
      return this.summary ?? '';
    },
  });

  static isolated = class Isolated extends Component<typeof ContractVersion> {
    // every version of the same contract, for "what changed" and the list
    private siblings: ReturnType<getCards> | undefined;

    constructor(owner: Owner, args: any) {
      super(owner, args);
      this.siblings = this.args.context?.getCards(
        this,
        () => {
          let id = this.args.model?.contract?.id;
          if (!id) return undefined;
          return {
            filter: {
              on: VERSION_REF,
              every: [{ eq: { 'contract.id': id } }],
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

    get versions(): any[] {
      return ((this.siblings as any)?.instances ?? [])
        .filter(Boolean)
        .sort(
          (a: any, b: any) => (b.versionNumber ?? 0) - (a.versionNumber ?? 0),
        );
    }
    get previous(): any {
      let n = this.args.model?.versionNumber ?? 0;
      return this.versions.find((x) => x.versionNumber === n - 1);
    }
    get v() {
      return versionView(this.args.model, this.previous, this.versions.length);
    }
    get rows(): Row[] {
      let current = Math.max(...this.versions.map((x) => x.versionNumber ?? 0));
      return this.versions.map((x) => ({
        title: `Version ${x.versionNumber ?? '—'}`,
        sub: [
          x.effectiveDate
            ? `Effective ${formatDay(x.effectiveDate)}`
            : undefined,
          x.summary,
        ]
          .filter(Boolean)
          .join(' · '),
        dot:
          x.versionNumber === current
            ? { label: 'current', tone: 'info' }
            : { label: 'superseded' },
      }));
    }
    <template>
      <IsoLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @statuses={{this.v.statuses}}
        @stats={{this.v.stats}}
      >
        <:mark><Mark @text={{this.v.mark}} @size='lg' /></:mark>
        <:main>
          {{#if @model.summary}}
            <Section @title='Summary'><Text>{{@model.summary}}</Text></Section>
          {{/if}}
          {{#if this.v.changes.length}}
            <Section @title='What changed'><Facts
                @items={{this.v.changes}}
              /></Section>
          {{/if}}
          {{#if this.rows.length}}
            <Section @title='Versions' @flush={{true}}><Rows
                @rows={{this.rows}}
              /></Section>
          {{/if}}
        </:main>
        <:side>
          <Section @title='Linked'>
            <LinkRow @label='Contract'><@fields.contract
                @format='atom'
                @displayContainer={{false}}
              /></LinkRow>
            <LinkRow @label='Executed by'><@fields.executedBy
                @format='atom'
                @displayContainer={{false}}
              /></LinkRow>
          </Section>
          <Section @title='Details'><Facts @items={{this.v.facts}} /></Section>
        </:side>
      </IsoLayout>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ContractVersion> {
    get v() {
      return versionView(this.args.model);
    }
    <template>
      <EmbLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{@model.summary}}
        @facts={{this.v.facts}}
      >
        <:mark><Mark @text={{this.v.mark}} /></:mark>
        <:linked>
          <LinkRow @label='Executed by'><@fields.executedBy
              @format='atom'
              @displayContainer={{false}}
            /></LinkRow>
        </:linked>
      </EmbLayout>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ContractVersion> {
    get v() {
      return versionView(this.args.model);
    }
    <template>
      <FitLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{@model.summary}}
        @facts={{this.v.facts}}
        @stats={{this.v.fitStats}}
      >
        <:mark><Mark @text={{this.v.mark}} /></:mark>
      </FitLayout>
    </template>
  };

  static atom = class Atom extends Component<typeof ContractVersion> {
    get v() {
      return versionView(this.args.model);
    }
    <template>
      <AtomLayout @title={{this.v.title}}><:mark><Mark
            @text={{this.v.mark}}
            @size='sm'
          /></:mark></AtomLayout>
    </template>
  };
}

/** The strings every ContractVersion format shows, read once from the model. */
function versionView(
  m?: Partial<ContractVersion>,
  prev?: Partial<ContractVersion>,
  total?: number,
) {
  let n = m?.versionNumber;
  let amount = m?.valueAtVersion?.amount;
  let code = m?.valueAtVersion?.currency?.code;
  let was = prev?.valueAtVersion?.amount;
  let who = m?.executedBy?.cardTitle as string | undefined;
  let [endDay, endYear] = dayAndYear(m?.endDateAtVersion);
  let [effDay, effYear] = dayAndYear(m?.effectiveDate);
  let delta =
    typeof amount === 'number' && typeof was === 'number'
      ? amount - was
      : undefined;
  let state: Dot = { label: n ? `v${n}` : 'version', tone: 'info' };
  let changes: Fact[] = [];
  if (prev) {
    changes.push({
      key: 'Value',
      value: `${longMoney(was, code)} → ${longMoney(amount, code)}`,
    });
    changes.push({
      key: 'End date',
      value: `${formatDay(prev.endDateAtVersion)} → ${formatDay(m?.endDateAtVersion)}`,
    });
  }
  return {
    mark: n ? `v${n}` : 'v',
    title: `${m?.contractTitle ?? 'Contract'} · version ${n ?? '—'}`,
    subtitle: [
      m?.effectiveDate ? `Effective ${formatDay(m.effectiveDate)}` : undefined,
      who ? `executed by ${who}` : undefined,
    ]
      .filter(Boolean)
      .join(' · '),
    state,
    statuses: [
      state,
      ...(typeof delta === 'number' && delta !== 0
        ? [
            {
              label: `${delta > 0 ? '+' : '−'} ${longMoney(Math.abs(delta), code)}`,
              tone: delta > 0 ? 'success' : 'danger',
            },
          ]
        : []),
    ] as Dot[],
    stats: stats([
      {
        label: 'Value',
        value: shortMoney(amount, code),
        hint:
          typeof was === 'number' ? `was ${shortMoney(was, code)}` : undefined,
      },
      { label: 'End date', value: endDay, hint: endYear },
      { label: 'Effective', value: effDay, hint: effYear },
    ]),
    fitStats: [
      { key: 'Value', value: shortMoney(amount, code) },
      { key: 'End date', value: endDay },
      { key: 'Effective', value: effDay },
    ],
    changes,
    facts: [
      { key: 'Value', value: longMoney(amount, code), mono: true },
      ...(prev
        ? [{ key: 'Was', value: longMoney(was, code), mono: true }]
        : []),
      { key: 'Ends', value: formatDay(m?.endDateAtVersion), mono: true },
      ...(prev
        ? [
            {
              key: 'Was ending',
              value: formatDay(prev.endDateAtVersion),
              mono: true,
            },
          ]
        : []),
      { key: 'Effective', value: formatDay(m?.effectiveDate), mono: true },
      {
        key: 'Version',
        value: total ? `${n ?? '—'} of ${total}` : String(n ?? '—'),
      },
    ] as Fact[],
  };
}
