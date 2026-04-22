import {
  CardDef,
  contains,
  containsMany,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';

import BotIcon from '@cardstack/boxel-icons/bot';

import { Listing } from '@cardstack/catalog/catalog-app/listing/listing';
import { PrCard } from '../pr-card/pr-card';
import { FileContentField } from '../fields/file-content';

import { FittedTemplate } from './components/card/fitted-template';
import { IsolatedTemplate } from './components/card/isolated-template';

export class SubmissionCard extends CardDef {
  static displayName = 'SubmissionCard';
  static icon = BotIcon;

  static fitted = FittedTemplate;
  static isolated = IsolatedTemplate;

  @field cardTitle = contains(StringField, {
    computeVia: function (this: SubmissionCard) {
      return (
        this.listing?.name ?? this.listing?.cardTitle ?? 'Untitled Submission'
      );
    },
  });
  @field roomId = contains(StringField);
  @field branchName = contains(StringField);
  @field prCard = linksTo(() => PrCard);
  @field listing = linksTo(() => Listing);
  @field allFileContents = containsMany(FileContentField);
}
