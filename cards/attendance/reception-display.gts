import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import { registerDestructor } from '@ember/destroyable';
import type Owner from '@ember/owner';
import {
  CardDef,
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import {
  bxl,
  operation,
  operations,
  OperationsError,
  params,
  type OperationDeclaration,
} from 'https://cardstack.com/base/operations';
import QrCodeIcon from '@cardstack/boxel-icons/qr-code';
import { Button } from '@cardstack/pretui/components/button';
import { QrCode } from '@cardstack/pretui/components/qr-code';

const ROTATE_EVERY_MS = 30_000;

function newCode(): string {
  let bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => (b % 36).toString(36))
    .join('')
    .toUpperCase();
}

class DisplayView extends Component<typeof ReceptionDisplay> {
  @tracked error: string | undefined;
  @tracked live = false;
  private timer: ReturnType<typeof setInterval> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    registerDestructor(this, () => this.stop());
  }

  get display(): ReceptionDisplay {
    return this.args.model as ReceptionDisplay;
  }

  rotate = async () => {
    this.error = undefined;
    try {
      await operations<typeof ReceptionDisplay>(this.display).rotate({
        code: newCode(),
      });
    } catch (err) {
      this.error =
        err instanceof OperationsError
          ? (err.detail ?? err.message)
          : String(err);
      this.stop();
    }
  };

  start = () => {
    if (this.timer) {
      return;
    }
    this.live = true;
    this.rotate();
    this.timer = setInterval(this.rotate, ROTATE_EVERY_MS);
  };

  stop = () => {
    if (this.timer) {
      clearInterval(this.timer);
    }
    this.timer = undefined;
    this.live = false;
  };

  <template>
    <article class='display'>
      <h1>Scan to check in</h1>
      {{#if this.display.code}}
        <QrCode
          @value={{this.display.code}}
          @size={{320}}
          @label='Check-in code'
          @valueDisplay='text'
        />
      {{else}}
        <p class='hint'>No code yet. Start the display to show one.</p>
      {{/if}}
      <div class='controls'>
        {{#if this.live}}
          <Button @appearance='outlined' {{on 'click' this.stop}}>Stop</Button>
        {{else}}
          <Button @tone='primary' @appearance='accent' {{on 'click' this.start}}>
            Start the display
          </Button>
        {{/if}}
      </div>
      <p class='hint' role='status'>
        {{if
          this.error
          this.error
          (if this.live 'A new code every 30 seconds.' '')
        }}
      </p>
    </article>
    <style scoped>
      .display {
        display: grid;
        justify-items: center;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-xl);
        text-align: center;
      }
      h1 {
        margin: 0;
        font-size: var(--boxel-font-size-xl);
      }
      .hint {
        margin: 0;
        min-height: 1lh;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

// The reception screen's rotating code. A check-in that requires presence
// asserts against the code and issue time stored here.
export class ReceptionDisplay extends CardDef {
  static displayName = 'Reception Display';
  static icon = QrCodeIcon;

  @field location = contains(StringField);
  @field code = contains(StringField);
  @field issuedAt = contains(StringField);
  // NOW()'s serial day number, so a check-in can compare freshness.
  @field issuedAtSerial = contains(NumberField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ReceptionDisplay) {
      return this.location
        ? `Reception display · ${this.location}`
        : 'Reception display';
    },
  });

  @operation static rotate = {
    base: 'transform',
    params: {
      code: StringField,
      issuedAt: StringField,
      issuedAtSerial: NumberField,
    },
    input: bxl`NOW() as $n | . + { issuedAt: (TEXT($n; "yyyy-mm-dd") + "T" + TEXT($n; "hh:mm:ss") + "Z"), issuedAtSerial: $n }`,
    transformations: bxl`
      .code = params("code");
      .issuedAt = params("issuedAt");
      .issuedAtSerial = params("issuedAtSerial");
    `,
  } satisfies OperationDeclaration;

  static isolated = DisplayView;
}
