import { FieldDef, Component, contains, field } from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import NumberField from '@cardstack/base/number';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';

export class EchoNoteField extends FieldDef {
  static displayName = 'Echo Note';
  static icon = SparklesIcon;

  @field label = contains(StringField); // e.g. "Echo № 2"
  @field mode = contains(StringField); // solve | complete | explain
  @field content = contains(TextAreaField);
  @field x = contains(NumberField); // world coordinates on the board
  @field y = contains(NumberField);
  @field width = contains(NumberField);
  @field acceptedAt = contains(DateTimeField);
  @field sketchJson = contains(StringField); // red-pen sketch the AI drew back (world polylines)
  @field sceneJson = contains(StringField); // manim scene spec (validated, deterministic)

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='echo-note'>
        <div class='echo-note-label'>{{if @model.label @model.label 'Echo'}}
          ·
          {{if @model.mode @model.mode 'solve'}}</div>
        <div class='echo-note-content'>{{if
            @model.content
            @model.content
            '—'
          }}</div>
      </div>
      <style scoped>
        .echo-note {
          font-family: var(
            --ep-font-chrome,
            var(--font-mono, 'IBM Plex Mono', monospace)
          );
        }
        .echo-note-label {
          font-size: 0.65rem;
          font-weight: 600;
          letter-spacing: 0.22em;
          text-transform: uppercase;
          color: var(--ep-echo, #c33d2e);
          margin-bottom: 4px;
        }
        .echo-note-content {
          font-family: var(--ep-font-hand, 'Caveat', cursive);
          font-size: 1.3rem;
          line-height: 1.25;
          color: var(--ep-echo, #c33d2e);
          white-space: pre-wrap;
        }
      </style>
    </template>
  };
}
