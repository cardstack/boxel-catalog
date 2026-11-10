import {
  CardDef,
  Component,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import UrlField from '@cardstack/base/url';
import SignatureIcon from '@cardstack/boxel-icons/signature';

import { ContractTypeField, contractTypeLabel } from './contract-type';
import { Employee } from '../hr/employee';
import { formatMoney } from '../commerce/line-item-totals';
import { Avatar } from '@cardstack/pretui/components/avatar';
import {
  AtomLayout,
  Dots,
  EmbLayout,
  Facts,
  FitLayout,
  IsoLayout,
  LinkRow,
  Section,
  stats,
  type Dot,
  type Fact,
} from './compact-card';
import { dash, longMoney, shortMoney } from '../shared/compact-format';

/**
 * Who may legally bind the company, and up to what number.
 *
 * A signatory is NOT an approver, and conflating the two is how a contract
 * ends up approved by three people and signed by nobody entitled to sign it.
 * Approval is internal oversight — did the right functions review this.
 * Signature is legal capacity — does this person's authority actually reach
 * this contract's value and type.
 *
 * The block earns its place on one method: `canSign`. Everything else here is
 * the data that method needs.
 */

export interface SigningVerdict {
  allowed: boolean;
  /** Plain-English reason, written for the person who has to act on it. */
  reason: string;
}

export class Signatory extends CardDef {
  static displayName = 'Signatory';
  static icon = SignatureIcon;

  @field person = linksTo(() => Employee);
  /** The title they sign under — it appears on the executed document. */
  @field signingTitle = contains(StringField);

  /**
   * The most they may bind, inclusive.
   *
   * Inclusive matters and is stated rather than assumed: a $250,000 authority
   * signing a $250,000 contract is the single most common edge in this whole
   * app, and a strict comparison would block it silently.
   */
  @field signatureAuthority = contains(AmountWithCurrency);

  /** Which contract types they may sign. Empty means all types. */
  @field contractTypes = containsMany(ContractTypeField);

  /** Specimen signature image, when one is held. */
  @field specimenUrl = contains(UrlField);
  @field isActive = contains(BooleanField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Signatory) {
      return this.signingTitle?.trim()?.length
        ? this.signingTitle
        : 'Signatory';
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: Signatory) {
      let types = (this.contractTypes ?? []).filter(Boolean);
      let scope = types.length
        ? types.map((t) => contractTypeLabel(t)).join(', ')
        : 'All contract types';
      let cap = this.signatureAuthority?.amount;
      // Raw digits read as a typo on a governance screen — "up to 1000000"
      // and "up to $1,000,000" are the same number and not the same message.
      let money = formatMoney(cap, this.signatureAuthority?.currency?.code);
      return money ? `${scope} · up to ${money}` : scope;
    },
  });

  /**
   * May this signatory bind a contract of this value and type?
   *
   * Deliberately returns a reason as well as a boolean. A bare `false` on a
   * signing screen tells the user they are stuck without telling them who to
   * route to, which is the difference between a check and an obstruction.
   *
   * Both arguments are supplied by the caller rather than read off a linked
   * Contract: the check has to run *before* anything is sent, including on a
   * contract that has not been created yet.
   */
  canSign(value?: number | null, contractType?: string | null): SigningVerdict {
    if (this.isActive === false) {
      return { allowed: false, reason: 'This signatory is no longer active.' };
    }
    let types = (this.contractTypes ?? []).filter(Boolean);
    if (types.length && contractType && !types.includes(contractType)) {
      return {
        allowed: false,
        reason: `Not authorised for ${contractTypeLabel(contractType)} contracts.`,
      };
    }
    let cap = this.signatureAuthority?.amount;
    if (typeof cap !== 'number' || !Number.isFinite(cap)) {
      return {
        allowed: false,
        reason: 'No signing authority has been set for this signatory.',
      };
    }
    if (typeof value === 'number' && Number.isFinite(value) && value > cap) {
      return {
        allowed: false,
        reason: `Authorised to ${cap}; this contract is ${value}. Route to a higher authority.`,
      };
    }
    return { allowed: true, reason: `Within authority of ${cap}.` };
  }

  static isolated = class Isolated extends Component<typeof Signatory> {
    get v() {
      return signatoryView(this.args.model);
    }
    <template>
      <IsoLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @statuses={{this.v.statuses}}
        @stats={{this.v.stats}}
      >
        <:mark><Avatar
            @name={{this.v.title}}
            @src={{this.v.photo}}
            @size={{36}}
          /></:mark>
        <:main>
          <Section @title='Signing authority'><Facts
              @items={{this.v.authority}}
            /></Section>
          <Section @title='Contract types' @flush={{true}}><Dots
              @items={{this.v.types}}
            /></Section>
        </:main>
        <:side>
          <Section @title='Linked'>
            <LinkRow @label='Person'><@fields.person
                @format='atom'
                @displayContainer={{false}}
              /></LinkRow>
          </Section>
          <Section @title='Details'><Facts @items={{this.v.facts}} /></Section>
        </:side>
      </IsoLayout>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Signatory> {
    get v() {
      return signatoryView(this.args.model);
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
        <:mark><Avatar
            @name={{this.v.title}}
            @src={{this.v.photo}}
            @size={{32}}
          /></:mark>
      </FitLayout>
    </template>
  };

  static atom = class Atom extends Component<typeof Signatory> {
    get v() {
      return signatoryView(this.args.model);
    }
    <template>
      <AtomLayout @title={{this.v.title}}><:mark><Avatar
            @name={{this.v.title}}
            @src={{this.v.photo}}
            @size={{18}}
          /></:mark></AtomLayout>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Signatory> {
    get v() {
      return signatoryView(this.args.model);
    }
    <template>
      <EmbLayout
        @title={{this.v.title}}
        @subtitle={{this.v.subtitle}}
        @status={{this.v.state}}
        @fact={{this.v.fact}}
        @facts={{this.v.facts}}
      >
        <:mark><Avatar
            @name={{this.v.title}}
            @src={{this.v.photo}}
            @size={{28}}
          /></:mark>
      </EmbLayout>
    </template>
  };
}

/** The strings every Signatory format shows, read once from the model. */
function signatoryView(m?: Partial<Signatory>) {
  let person = m?.person as any;
  let name =
    (person?.cardTitle as string | undefined) ?? m?.cardTitle ?? 'Signatory';
  let amount = m?.signatureAuthority?.amount;
  let code = m?.signatureAuthority?.currency?.code;
  let types = ((m?.contractTypes ?? []).filter(Boolean) as string[]).map((t) =>
    contractTypeLabel(t),
  );
  let active = m?.isActive !== false;
  let state: Dot = {
    label: active ? 'active' : 'inactive',
    tone: active ? 'success' : 'neutral',
  };
  let typeLine = types.length ? types.join(', ') : 'All contract types';
  return {
    title: name,
    photo: person?.photo?.resolvedUrl as string | undefined,
    subtitle: [
      m?.signingTitle,
      typeof amount === 'number'
        ? `signs up to ${longMoney(amount, code)}`
        : undefined,
    ]
      .filter(Boolean)
      .join(' · '),
    state,
    statuses: [
      state,
      { label: types.length ? `${types.length} types` : 'all types' },
    ] as Dot[],
    fact: types.length ? `${typeLine} contracts` : typeLine,
    stats: stats([
      {
        label: 'Authority',
        value: shortMoney(amount, code),
        hint: 'per contract',
      },
      {
        label: 'Contract types',
        value: types.length ? String(types.length) : 'All',
        hint: typeLine.toLowerCase(),
      },
      {
        label: 'Status',
        value: active ? 'Active' : 'Inactive',
        hint: active ? 'may sign' : 'may not sign',
      },
    ]),
    fitStats: [
      { key: 'Authority', value: shortMoney(amount, code) },
      { key: 'Types', value: types.length ? String(types.length) : 'All' },
      { key: 'Status', value: active ? 'Active' : 'Inactive' },
    ],
    authority: [
      { key: 'Signing title', value: dash(m?.signingTitle) },
      { key: 'Up to', value: longMoney(amount, code), mono: true },
      { key: 'Active', value: active ? 'Yes' : 'No' },
    ] as Fact[],
    types: (types.length ? types : ['All contract types']).map((label) => ({
      label,
    })) as Dot[],
    facts: [
      { key: 'Authority', value: longMoney(amount, code), mono: true },
      { key: 'Title', value: dash(m?.signingTitle) },
      { key: 'Types', value: typeLine },
      { key: 'Status', value: active ? 'Active' : 'Inactive' },
      { key: 'Email', value: dash(person?.email) },
      { key: 'Phone', value: dash(person?.phone) },
    ] as Fact[],
  };
}

export default Signatory;
