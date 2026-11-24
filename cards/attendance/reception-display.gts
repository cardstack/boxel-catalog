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
  type OperationDeclaration,
} from 'https://cardstack.com/base/operations';
import QrCodeIcon from '@cardstack/boxel-icons/qr-code';
import { Button } from '@cardstack/pretui/components/button';
import { QrCode } from '@cardstack/pretui/components/qr-code';

const ROTATE_EVERY_MS = 30_000;
const CODE_LENGTH = 6;

// Bytes from 252 up are skipped, so each of the 36 characters is equally likely.
function newCode(): string {
  let code = '';
  while (code.length < CODE_LENGTH) {
    let bytes = new Uint8Array(CODE_LENGTH * 2);
    crypto.getRandomValues(bytes);
    for (let b of bytes) {
      if (b < 252 && code.length < CODE_LENGTH) {
        code += (b % 36).toString(36);
      }
    }
  }
  return code.toUpperCase();
}

// A check-in accepts the current code and the one before it, each for 165
// seconds from the realm's stamp. The screen shows the code it sent once the
// rotation comes back, times it on its own clock, and stops showing it well
// before that, so it never shows a code that would be refused.
const SHOW_FOR_MS = 140_000;
const TICK_MS = 2_000;

class DisplayView extends Component<typeof ReceptionDisplay> {
  @tracked error: string | undefined;
  @tracked live = false;
  @tracked now = Date.now();
  @tracked shownAt: number | undefined;
  @tracked shownCode: string | undefined;
  private timer: ReturnType<typeof setInterval> | undefined;
  private ticker: ReturnType<typeof setInterval> | undefined;
  private rotating = false;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    registerDestructor(this, () => this.stop());
  }

  get display(): ReceptionDisplay {
    return this.args.model as ReceptionDisplay;
  }

  get isFresh(): boolean {
    return (
      this.shownAt !== undefined &&
      Boolean(this.shownCode) &&
      this.now - this.shownAt < SHOW_FOR_MS
    );
  }

  // A failed rotation is retried on the next tick; the old code stays only
  // while it is still accepted.
  rotate = async () => {
    if (this.rotating) {
      return;
    }
    this.rotating = true;
    let sentAt = Date.now();
    let code = newCode();
    try {
      // `input` stamps issuedAt and issuedAtSerial, so the payload carries
      // only the code; the typed signature still lists every declared param.
      await operations(this.display).rotate({ code });
      // Timed from the send, which is never later than the realm's stamp.
      this.shownCode = code;
      this.shownAt = sentAt;
      this.error = undefined;
    } catch (err) {
      this.error =
        err instanceof OperationsError
          ? (err.detail ?? err.message)
          : String(err);
    } finally {
      this.rotating = false;
    }
  };

  start = () => {
    if (this.timer) {
      return;
    }
    this.live = true;
    this.shownAt = undefined;
    this.shownCode = undefined;
    this.rotate();
    this.timer = setInterval(this.rotate, ROTATE_EVERY_MS);
    this.ticker = setInterval(() => (this.now = Date.now()), TICK_MS);
  };

  stop = () => {
    if (this.timer) {
      clearInterval(this.timer);
    }
    if (this.ticker) {
      clearInterval(this.ticker);
    }
    this.timer = undefined;
    this.ticker = undefined;
    this.live = false;
  };

  <template>
    <article class='display'>
      <h1>Check in at reception</h1>
      {{#if this.live}}
        {{#if this.isFresh}}
          <QrCode
            @value={{this.shownCode}}
            @size={{320}}
            @label='Check-in code'
            @valueDisplay='text'
          />
          <p class='hint'>Enter this code in Time Card, or scan it.</p>
        {{else}}
          <p class='warning' role='alert'>Waiting for a new code…</p>
        {{/if}}
        <Button @appearance='outlined' {{on 'click' this.stop}}>Stop</Button>
      {{else}}
        <p class='hint'>The display shows a new code every 30 seconds while it
          runs.</p>
        <Button @tone='primary' @appearance='accent' {{on 'click' this.start}}>
          Start the display
        </Button>
      {{/if}}
      <p class='hint' role='status'>{{this.error}}</p>
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
      .warning {
        margin: 0;
        color: var(--destructive);
        font-weight: 600;
      }
    </style>
  </template>
}

// The reception screen's rotating code. A check-in that requires presence
// asserts against the code and issue time stored here. Whoever may call
// `rotate` or read this card can check in without being there, so grant both
// only to the account the reception screen runs as, never to staff.
export class ReceptionDisplay extends CardDef {
  static displayName = 'Reception Display';
  static icon = QrCodeIcon;

  @field location = contains(StringField);
  @field code = contains(StringField);
  @field issuedAt = contains(StringField);
  // NOW()'s serial day number, so a check-in can compare freshness.
  @field issuedAtSerial = contains(NumberField);
  // The code shown before this one, still accepted while it is fresh, so a
  // code read just before a rotation still works.
  @field previousCode = contains(StringField);
  @field previousIssuedAtSerial = contains(NumberField);

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
      .previousCode = .code;
      .previousIssuedAtSerial = .issuedAtSerial;
      .code = params("code");
      .issuedAt = params("issuedAt");
      .issuedAtSerial = params("issuedAtSerial");
    `,
  } satisfies OperationDeclaration;

  static isolated = DisplayView;
}
