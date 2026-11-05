import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import TextAreaField from 'https://cardstack.com/base/text-area';
import GlimmerComponent from '@glimmer/component';
import {
  FormatDate,
  type FormatDateSignature,
} from '@cardstack/pretui/components/format-date';

// "Jan 2020" — a resume's month-and-year precision, in en-US. No long-form
// hover title: the stored day is not something the resume claims.
class MonthYear extends GlimmerComponent<{
  Args: {
    date?: FormatDateSignature['Args']['date'];
    placeholder?: string;
  };
}> {
  <template>
    <FormatDate
      @date={{@date}}
      @locale='en-US'
      @month='short'
      @year='numeric'
      @hint={{false}}
      @placeholder={{@placeholder}}
    />
  </template>
}

// One prior job, as reported on a resume (by a human or transcribed by the
// Extract Resume command). Composed as `containsMany` on Candidate so a
// resume's whole employment history round-trips without a linked card per
// job — see candidate.gts's `workHistory` field.
export class WorkHistoryEntryField extends FieldDef {
  static displayName = 'Work History Entry';

  @field company = contains(StringField);
  @field title = contains(StringField);
  @field startDate = contains(DateField);
  @field endDate = contains(DateField);
  @field description = contains(TextAreaField);

  static embedded = class Embedded extends Component<typeof this> {
    get hasRange(): boolean {
      return Boolean(this.args.model?.startDate || this.args.model?.endDate);
    }

    <template>
      <li class='wh-row'>
        <div class='wh-head'>
          <span class='wh-title'>{{if
              @model.title
              @model.title
              'Untitled role'
            }}</span>
          {{#if @model.company}}
            <span class='wh-at'>at
              {{@model.company}}</span>
          {{/if}}
        </div>
        {{#if this.hasRange}}
          <span class='wh-range'><MonthYear
              @date={{@model.startDate}}
            />–<MonthYear
              @date={{@model.endDate}}
              @placeholder='Present'
            /></span>
        {{/if}}
        {{#if @model.description}}
          <p class='wh-desc'>{{@model.description}}</p>
        {{/if}}
      </li>
      <style scoped>
        .wh-row {
          padding: var(--boxel-sp-xs) 0;
          border-bottom: 1px solid var(--border);
        }
        .wh-row:last-child {
          border-bottom: 0;
        }
        .wh-head {
          display: flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: 0.3rem;
        }
        .wh-title {
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        .wh-at {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .wh-range {
          display: block;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
        .wh-desc {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          line-height: 1.5;
          overflow: hidden;
          text-overflow: ellipsis;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
      </style>
    </template>
  };
}
