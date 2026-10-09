import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import StringField from '@cardstack/base/string';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import ClipboardListIcon from '@cardstack/boxel-icons/clipboard-list';
import { SurveyQuestion } from './survey-question';
import { SurveyIsolated } from './components/isolated-template';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import { SurveyFitted } from './components/fitted-template';

export class Survey extends CardDef {
  static displayName = 'Survey';
  static icon = ClipboardListIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  @field description = contains(MarkdownField);
  @field questions = containsMany(SurveyQuestion);

  @field questionCount = contains(NumberField, {
    computeVia: function (this: Survey) {
      return this.questions?.length ?? 0;
    },
  });

  // Event fact, not a flag: PublishSurveyCommand writes this once and it is
  // monotonic — `isPublished` derives from it, so the boolean can never
  // drift from the event that made it true.
  @field publishedAt = contains(DateTimeField);

  @field isPublished = contains(BooleanField, {
    computeVia: function (this: Survey) {
      return Boolean(this.publishedAt);
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Survey) {
      return this.cardInfo?.name ?? this.title ?? 'Survey';
    },
  });

  // The form for authoring a survey: name it and frame it, then write the
  // questions. `questionCount`, `isPublished`, and `cardTitle` are computed
  // and never appear here; `publishedAt` is an event fact written once by
  // PublishSurveyCommand, exposed only with a warning hint.
  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'survey', label: 'Survey' },
      { id: 'questions', label: 'Questions' },
    ];

    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Survey sections'
        as |e|
      >
        <e.Section @id='survey' @title='Survey'>
          <FieldContainer @label='Title' @vertical={{true}}>
            <@fields.title />
          </FieldContainer>
          <FieldContainer
            @label='Description (shown to respondents)'
            @vertical={{true}}
          >
            <@fields.description />
          </FieldContainer>
          <FieldContainer
            @label='Published at (stamped once by the Publish command — edit only to correct)'
            @vertical={{true}}
          >
            <@fields.publishedAt />
          </FieldContainer>
        </e.Section>
        <e.Section
          @id='questions'
          @title='Questions'
          @hint='respondents see them in this order'
        >
          <FieldContainer @label='Questions' @vertical={{true}}>
            <@fields.questions />
          </FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };
}

Survey.isolated = SurveyIsolated;
Survey.fitted = SurveyFitted;
