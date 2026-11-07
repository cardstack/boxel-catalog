import {
  CardDef,
  field,
  contains,
  linksTo,
  StringField,
  Component,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import { statusField } from '@cardstack/catalog/fields/status/status';
import MultiImageSourceField from '@cardstack/catalog/fields/multi-image-source/multi-image-source';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { CollectionItem } from './collection-item';
import { DotLabel } from '../hr/dot-enum-field';
import { FitTile } from '../shared/fit-tile';
import {
  CaAtom,
  CaEmbedded,
  CaKv,
  CaMark,
  CaRow,
  CaSection,
  CaSheet,
  CaStat,
  caDay,
} from './ca-parts';

// AuthenticationRecord — one legit-check on one item: who checked it, when, the
// verdict, and the certificate reference.
//
// It is the inspection itself, not the certifying authority, a cryptographic
// signature, or trust metadata on another record.
//
// THE SPLIT AGAINST CollectionItem is deliberate and is the reason both exist:
// this card is the full RECORD (submitted photos, authenticator notes, the
// service, the certificate id — everything a dispute needs), while
// CollectionItem keeps only the OUTCOME (`verifiedOn`, `verifiedBy`,
// `verificationReference`). The outcome is duplicated on purpose: a collection
// grid is prerendered fitted, which cannot resolve a link to this record, so a
// tile could not show a verified badge otherwise. That is denormalization for the
// one legitimate reason — a rendering constraint — not to avoid a query.

export type AuthOutcome = 'pending' | 'passed' | 'failed';

// An authentication outcome is a genuine lifecycle, so the transition graph is
// the point: a verdict must not be edited from `passed` to `failed` in a
// dropdown, because a reversal is a new inspection with its own certificate,
// not a correction to this record. Both verdicts are therefore terminal.
export const AuthOutcomeField = statusField({
  displayName: 'Authentication Outcome',
  options: [
    {
      value: 'pending',
      label: 'Pending',
      hue: 'amber',
      meaning: 'Submitted and awaiting a verdict.',
    },
    {
      value: 'passed',
      label: 'Passed',
      hue: 'green',
      terminal: true,
      holds: true,
      meaning: 'Verified genuine. This is the badge a listing shows.',
    },
    {
      value: 'failed',
      label: 'Failed',
      hue: 'red',
      terminal: true,
      holds: true,
      meaning: 'Judged not genuine. In an escrow flow this refunds the buyer.',
    },
  ],
  transitions: {
    pending: ['passed', 'failed'],
    passed: [],
    failed: [],
  },
});

export class AuthenticationRecord extends CardDef {
  static displayName = 'Authentication Record';
  static icon = ShieldCheckIcon;

  @field item = linksTo(() => CollectionItem, { searchable: true });

  // The transaction this check belongs to, when it is part of an escrow flow.
  @field order = linksTo(CardDef, { searchable: true });

  // 'Check Check', 'GOAT', 'In-house'. The consumer supplies enum options if it
  // wants a select; the block does not name anyone's list of services.
  @field service = contains(StringField);

  @field outcome = contains(AuthOutcomeField);

  @field submittedAt = contains(DateField);
  @field completedAt = contains(DateField);

  @field certificateId = contains(StringField);
  @field authenticator = contains(StringField);
  @field authenticatorNotes = contains(TextAreaField);
  @field submittedPhotos = contains(MultiImageSourceField);

  // Denormalized for fitted, same reason as everywhere else in this family.
  @field itemTitle = contains(StringField, {
    computeVia: function (this: AuthenticationRecord) {
      return this.item?.itemTitle ?? this.cardInfo?.name ?? '';
    },
  });

  // Turnaround is a real fact a queue view wants, and it is cheap and bounded —
  // both dates are on this card, so it is safe as a computed field. Calendar-day
  // arithmetic, not instants: both sides are read as local Y/M/D by DateField.
  @field turnaroundDays = contains(StringField, {
    computeVia: function (this: AuthenticationRecord) {
      let a = this.submittedAt;
      let b = this.completedAt;
      if (!a || !b) {
        return '';
      }
      let ms = b.getTime() - a.getTime();
      if (ms < 0) {
        return '';
      }
      let days = Math.round(ms / 86400000);
      return days === 1 ? '1 day' : `${days} days`;
    },
  });

  static isolated = class Isolated extends Component<
    typeof AuthenticationRecord
  > {
    <template>
      <CaSheet @title={{titleOf @model}} @src={{photoOf @model}}>
        <:meta>{{metaLine @model}}</:meta>
        <:aside><Outcome @model={{@model}} /></:aside>
        <:stats>
          <CaStat
            @label='Outcome'
            @value={{outcomeLabel @model.outcome}}
            @hint={{@model.service}}
          />
          <CaStat
            @label='Turnaround'
            @value={{or @model.turnaroundDays}}
            @hint={{spanText @model}}
          />
          <CaStat
            @label='Certificate'
            @value={{or @model.certificateId}}
            @hint={{@model.authenticator}}
          />
        </:stats>
        <:main>
          <CaSection @title='Authenticator notes'>
            {{#if @model.authenticatorNotes}}<@fields.authenticatorNotes
              />{{else}}—{{/if}}
          </CaSection>
          <CaSection @title='Record' @flush={{true}}>
            <CaKv>
              <CaRow @label='Service'>{{or @model.service}}</CaRow>
              <CaRow @label='Authenticator'>{{or @model.authenticator}}</CaRow>
              <CaRow @label='Submitted'>{{caDay @model.submittedAt}}</CaRow>
              <CaRow @label='Completed'>{{caDay @model.completedAt}}</CaRow>
              <CaRow @label='Certificate'>{{or @model.certificateId}}</CaRow>
              <CaRow @label='Order'>{{#if @model.order}}<@fields.order
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</CaRow>
            </CaKv>
          </CaSection>
        </:main>
        <:side>
          <CaSection @title='Linked' @flush={{true}}>
            <ItemRow @model={{@model}} @fields={{@fields}} />
          </CaSection>
          <CaSection @title='Details' @flush={{true}}>
            <DetailRows @model={{@model}} />
          </CaSection>
        </:side>
      </CaSheet>
    </template>
  };

  static embedded = class Embedded extends Component<
    typeof AuthenticationRecord
  > {
    <template>
      <CaEmbedded @title={{titleOf @model}} @src={{photoOf @model}}>
        <:meta>{{metaLine @model}}</:meta>
        <:status><Outcome @model={{@model}} /></:status>
        <:default>
          <DetailRows @model={{@model}} />
          <ItemRow @model={{@model}} @fields={{@fields}} />
        </:default>
      </CaEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof AuthenticationRecord> {
    <template>
      <CaAtom @title={{titleOf @model}} @src={{photoOf @model}} />
    </template>
  };

  static fitted = class Fitted extends Component<typeof AuthenticationRecord> {
    <template>
      <FitTile>
        <:avatar><CaMark @src={{photoOf @model}} @size='md' /></:avatar>
        <:title>{{titleOf @model}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><Outcome @model={{@model}} /></:status>
        <:fact>{{spanText @model}}
          ·
          {{or @model.turnaroundDays}}</:fact>
      </FitTile>
    </template>
  };
}

const Outcome: TemplateOnlyComponent<{
  Args: { model: Partial<AuthenticationRecord> };
}> = <template>
  <DotLabel
    @label={{if @model.outcome @model.outcome 'pending'}}
    @hue={{outcomeHue @model.outcome}}
  />
</template>;

const ItemRow: TemplateOnlyComponent<{
  Args: { model: Partial<AuthenticationRecord>; fields: any };
}> = <template>
  <CaKv>
    <CaRow @label='Item'>{{#if @model.item}}<@fields.item
          @format='atom'
          @displayContainer={{false}}
        />{{#if @model.item.condition.code}}<DotLabel
            @label={{@model.item.condition.code}}
            @hue='green'
          />{{/if}}{{else}}—{{/if}}</CaRow>
  </CaKv>
</template>;

const DetailRows: TemplateOnlyComponent<{
  Args: { model: Partial<AuthenticationRecord> };
}> = <template>
  <CaKv>
    <CaRow @label='Service'>{{or @model.service}}</CaRow>
    <CaRow @label='Outcome'>{{outcomeLabel @model.outcome}}</CaRow>
    <CaRow @label='Submitted'>{{caDay @model.submittedAt}}</CaRow>
    <CaRow @label='Completed'>{{caDay @model.completedAt}}</CaRow>
    <CaRow @label='Turnaround'>{{or @model.turnaroundDays}}</CaRow>
    <CaRow @label='Authenticator'>{{or @model.authenticator}}</CaRow>
    <CaRow @label='Certificate'>{{or @model.certificateId}}</CaRow>
  </CaKv>
</template>;

function or(v: string | null | undefined): string {
  return v || '—';
}

function titleOf(m: Partial<AuthenticationRecord>): string {
  return m.certificateId || m.cardTitle || 'Authentication';
}

function photoOf(m: Partial<AuthenticationRecord>): string | undefined {
  return m.submittedPhotos?.resolvedUrls?.[0];
}

function metaLine(m: Partial<AuthenticationRecord>): string {
  return [m.service, m.itemTitle].filter(Boolean).join(' · ') || '—';
}

function outcomeLabel(outcome: string | undefined): string {
  return outcome ? outcome.charAt(0).toUpperCase() + outcome.slice(1) : '—';
}

function outcomeHue(outcome: string | undefined): DotLabel['args']['hue'] {
  return outcome === 'passed'
    ? 'green'
    : outcome === 'failed'
      ? 'red'
      : 'amber';
}

function spanText(m: Partial<AuthenticationRecord>): string {
  if (!m.submittedAt && !m.completedAt) {
    return '—';
  }
  return `${caDay(m.submittedAt)} – ${caDay(m.completedAt)}`;
}

export default AuthenticationRecord;
