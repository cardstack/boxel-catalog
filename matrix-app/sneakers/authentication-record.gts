import { markDefinition } from '@cardstack/base/mark-definition';
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
  SnAtom,
  SnEmbedded,
  SnKv,
  SnMark,
  SnRow,
  SnSection,
  SnSheet,
  SnStat,
  day,
} from './parts';

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
export const AuthOutcomeField = markDefinition(
  statusField({
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
        meaning:
          'Judged not genuine. In an escrow flow this refunds the buyer.',
      },
    ],
    transitions: {
      pending: ['passed', 'failed'],
      passed: [],
      failed: [],
    },
  }),
);

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
      <SnSheet @title={{titleOf @model}} @src={{photoOf @model}}>
        <:meta>{{metaLine @model}}</:meta>
        <:actions><Outcome @model={{@model}} /></:actions>
        <:stats>
          <SnStat
            @label='Outcome'
            @value={{outcomeLabel @model.outcome}}
            @hint={{@model.service}}
          />
          <SnStat
            @label='Turnaround'
            @value={{or @model.turnaroundDays}}
            @hint={{spanText @model}}
          />
          <SnStat
            @label='Certificate'
            @value={{or @model.certificateId}}
            @hint={{@model.authenticator}}
          />
        </:stats>
        <:main>
          <SnSection @title='Authenticator notes'>
            {{#if @model.authenticatorNotes}}<@fields.authenticatorNotes
              />{{else}}—{{/if}}
          </SnSection>
          <SnSection @title='Record' @flush={{true}}>
            <SnKv>
              <SnRow @label='Service'>{{or @model.service}}</SnRow>
              <SnRow @label='Authenticator'>{{or @model.authenticator}}</SnRow>
              <SnRow @label='Submitted' @value={{day @model.submittedAt}} />
              <SnRow @label='Completed' @value={{day @model.completedAt}} />
              <SnRow @label='Certificate'>{{or @model.certificateId}}</SnRow>
              <SnRow @label='Order'>{{#if @model.order}}<@fields.order
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</SnRow>
            </SnKv>
          </SnSection>
        </:main>
        <:side>
          <SnSection @title='Linked' @flush={{true}}>
            <ItemRow @model={{@model}} @fields={{@fields}} />
          </SnSection>
          <SnSection @title='Details' @flush={{true}}>
            <DetailRows @model={{@model}} />
          </SnSection>
        </:side>
      </SnSheet>
    </template>
  };

  static embedded = class Embedded extends Component<
    typeof AuthenticationRecord
  > {
    <template>
      <SnEmbedded @title={{titleOf @model}} @src={{photoOf @model}}>
        <:meta>{{metaLine @model}}</:meta>
        <:status><Outcome @model={{@model}} /></:status>
        <:default>
          <DetailRows @model={{@model}} />
          <ItemRow @model={{@model}} @fields={{@fields}} />
        </:default>
      </SnEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof AuthenticationRecord> {
    <template>
      <SnAtom @title={{titleOf @model}} @src={{photoOf @model}} />
    </template>
  };

  static fitted = class Fitted extends Component<typeof AuthenticationRecord> {
    <template>
      <FitTile>
        <:avatar><SnMark @src={{photoOf @model}} @size='lg' /></:avatar>
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
  <SnKv>
    <SnRow @label='Item'>{{#if @model.item}}<@fields.item
          @format='atom'
          @displayContainer={{false}}
        />{{#if @model.item.condition.code}}<DotLabel
            @label={{@model.item.condition.code}}
            @hue='green'
          />{{/if}}{{else}}—{{/if}}</SnRow>
  </SnKv>
</template>;

const DetailRows: TemplateOnlyComponent<{
  Args: { model: Partial<AuthenticationRecord> };
}> = <template>
  <SnKv>
    <SnRow @label='Service'>{{or @model.service}}</SnRow>
    <SnRow @label='Outcome'>{{outcomeLabel @model.outcome}}</SnRow>
    <SnRow @label='Submitted' @value={{day @model.submittedAt}} />
    <SnRow @label='Completed' @value={{day @model.completedAt}} />
    <SnRow @label='Turnaround'>{{or @model.turnaroundDays}}</SnRow>
    <SnRow @label='Authenticator'>{{or @model.authenticator}}</SnRow>
    <SnRow @label='Certificate'>{{or @model.certificateId}}</SnRow>
  </SnKv>
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
  return `${day(m.submittedAt) || '—'} – ${day(m.completedAt) || '—'}`;
}

export default AuthenticationRecord;
