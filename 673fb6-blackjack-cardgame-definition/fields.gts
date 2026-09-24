import { FieldDef, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';

export class PlayingCardField extends FieldDef {
  static displayName = 'Playing Card';
  @field suit = contains(StringField);
  @field value = contains(StringField);
  @field faceUp = contains(BooleanField);
}

export class StatsField extends FieldDef {
  static displayName = 'Hand Statistics';
  @field wins = contains(NumberField);
  @field losses = contains(NumberField);
  @field earnings = contains(NumberField);
}

export function normalizeStatistics(
  statistics?: {
    wins?: number | null;
    losses?: number | null;
    earnings?: number | null;
  } | null,
) {
  return {
    wins: statistics?.wins ?? 0,
    losses: statistics?.losses ?? 0,
    earnings: statistics?.earnings ?? 0,
  };
}
