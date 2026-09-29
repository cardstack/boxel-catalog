import {
  FieldDef,
  Component,
  field,
  contains,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import NumberField from 'https://cardstack.com/base/number';
import TextAreaField from 'https://cardstack.com/base/text-area';
import MessageSquareIcon from '@cardstack/boxel-icons/message-square';
import { Rating } from '@cardstack/pretui/components/rating';

import { Employee } from './employee';

export class InterviewFeedbackField extends FieldDef {
  static displayName = 'Interview Feedback';
  static icon = MessageSquareIcon;

  @field interviewer = linksTo(() => Employee);
  @field interviewDate = contains(DateField);
  @field rating = contains(NumberField, {
    description: 'Interviewer score, 1-5',
  });
  @field notes = contains(TextAreaField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='feedback-row'>
        <div class='feedback-head'>
          <span class='interviewer'>{{if
              @model.interviewer.name
              @model.interviewer.name
              'Unknown interviewer'
            }}</span>
          {{#if @model.rating}}
            <Rating
              class='rating'
              @value={{@model.rating}}
              @max={{5}}
              @readonly={{true}}
              @label='Interviewer rating'
            />
          {{/if}}
        </div>
        {{#if @model.notes}}
          <p class='notes'>{{@model.notes}}</p>
        {{/if}}
      </div>
      <style scoped>
        .feedback-row {
          padding: var(--boxel-sp-sm) 0;
          border-bottom: 1px solid var(--border);
        }
        .feedback-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
        }
        .interviewer {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
        }
        /* Rating's default fill (--warning) and track (--boxel-400) fall
           under 3:1 on the card; the attention ink and the muted ink keep
           both the filled and the empty stars visible. */
        .rating {
          --pretui-rating-size: 0.875rem;
          --pretui-rating-hue: var(--attention-ink);
          --pretui-rating-track: var(--muted-foreground);
          flex: none;
        }
        .notes {
          margin: var(--boxel-sp-5xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          line-height: 1.5;
        }
      </style>
    </template>
  };
}
