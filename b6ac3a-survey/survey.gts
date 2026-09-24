import {
  CardDef,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import ClipboardListIcon from '@cardstack/boxel-icons/clipboard-list';
import { SurveyQuestion } from './survey-question';
import { SurveyIsolated } from './components/isolated-template';
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

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Survey) {
      return this.cardInfo?.name ?? this.title ?? 'Survey';
    },
  });
}

Survey.isolated = SurveyIsolated;
Survey.fitted = SurveyFitted;
