import {
  CardDef,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import PencilRulerIcon from '@cardstack/boxel-icons/pencil-ruler';

import { EchoPadEdit } from './components/edit';
import { EchoPadEmbedded, EchoPadFitted } from './components/formats';
import { EchoPadIsolated } from './components/isolated';
import { EchoNoteField } from './fields/echo-note';

export { EchoNoteField };

export class EchoPad extends CardDef {
  static displayName = 'Echo Pad';
  static icon = PencilRulerIcon;
  static prefersWideFormat = true;

  @field boardName = contains(StringField);
  // serialized ink strokes ({v, strokes: [{w, pts}]}) — one field, written on
  // a debounced idle, never per point
  @field inkJson = contains(TextAreaField);
  // camera ({x, y, zoom}) so a board reopens where it was left
  @field viewportJson = contains(StringField);
  // accepted AI annotations; unaccepted drafts never reach the model
  @field echoes = containsMany(EchoNoteField);

  @field title = contains(StringField, {
    computeVia: function (this: EchoPad) {
      return this.boardName?.trim() || 'Echo Pad';
    },
  });
}

EchoPad.isolated = EchoPadIsolated;
EchoPad.embedded = EchoPadEmbedded;
EchoPad.fitted = EchoPadFitted;
EchoPad.edit = EchoPadEdit;
