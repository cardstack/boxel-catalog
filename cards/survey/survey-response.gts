import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Survey } from './survey';

function answerItems(answers?: SurveyAnswer[] | null) {
  return (answers ?? []).filter(Boolean).map((a) => ({
    key: a.prompt || 'Question',
    value: a.response || '—',
  }));
}

export class SurveyAnswer extends FieldDef {
  static displayName = 'Survey Answer';
  @field prompt = contains(StringField);
  @field response = contains(StringField);
}

export class SurveyResponse extends CardDef {
  static displayName = 'Survey Response';
  static icon = ClipboardCheckIcon;

  // The live link is what consumers query on (`survey.id`). surveyId and
  // surveyTitle are snapshots written on submit, for reading a response whose
  // survey can't be loaded.
  @field survey = linksTo(() => Survey, { searchable: true });
  @field surveyId = contains(StringField);
  @field surveyTitle = contains(StringField);
  @field answers = containsMany(SurveyAnswer);

  @field title = contains(StringField, {
    computeVia: function (this: SurveyResponse) {
      let name = this.survey?.title ?? this.surveyTitle;
      return name ? `Response: ${name}` : 'Survey Response';
    },
  });

  static embedded = class Embedded extends Component<typeof SurveyResponse> {
    <template>
      <article class='resp'>
        <header class='resp-head'>
          <span class='resp-eyebrow'>Response</span>
          <h3 class='resp-title'>
            {{if @model.surveyTitle @model.surveyTitle 'Survey'}}
          </h3>
        </header>
        <KeyValue
          class='resp-list'
          @items={{answerItems @model.answers}}
          @layout='stacked'
        />
      </article>
      <style scoped>
        .resp {
          padding: var(--boxel-sp);
          display: flex;
          flex-direction: column;
          gap: 0.6rem;
          color: var(--foreground);
          font-family: var(--font-sans);
        }
        .resp-eyebrow {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--primary-ink);
        }
        .resp-title {
          margin: 0.1rem 0 0;
          font-size: 1.1rem;
          font-weight: 700;
        }
        .resp-list {
          margin: 0;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof SurveyResponse> {
    get count(): number {
      return this.args.model?.answers?.length ?? 0;
    }
    <template>
      <div class='resp-fitted'>
        <span class='resp-fitted-eyebrow'>Response</span>
        <span class='resp-fitted-title'>{{if
            @model.surveyTitle
            @model.surveyTitle
            'Survey'
          }}</span>
        <span class='resp-fitted-count'>{{this.count}} answers</span>
      </div>
      <style scoped>
        .resp-fitted {
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          padding: 0.75rem;
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.2rem;
          overflow: hidden;
          font-family: var(--font-sans);
          color: var(--foreground);
        }
        .resp-fitted-eyebrow {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--primary-ink);
        }
        .resp-fitted-title {
          font-size: 0.95rem;
          font-weight: 800;
          line-height: 1.2;
          overflow: hidden;
          text-overflow: ellipsis;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .resp-fitted-count {
          font-size: 0.75rem;
          font-weight: 600;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
