import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { guidFor } from '@ember/object/internals';
import { Alert } from '@cardstack/pretui/components/alert';
import { Input } from '@cardstack/pretui/components/input';
import {
  RadioGroup,
  type RadioOption,
} from '@cardstack/pretui/components/radio-group';
import { ALERT_STYLE } from '../real-estate-ui';

// Schedule Picker — "publish now" or "publish later". Render-only: the
// consumer holds the chosen ISO string (or undefined for now) and gets it
// through `@onChange`. The Date is composed from LOCAL calendar parts —
// never string-concatenated into an ISO with Z — because east-of-UTC
// agents scheduling "9am Saturday" mean their 9am, not Greenwich's.

interface Signature {
  Args: {
    value?: string;
    onChange: (isoOrUndefined: string | undefined) => void;
  };
  Element: HTMLElement;
}

export class SchedulePicker extends GlimmerComponent<Signature> {
  @tracked mode: 'now' | 'later' = this.args.value ? 'later' : 'now';
  @tracked datePart = this.args.value ? toDatePart(this.args.value) : '';
  @tracked timePart = this.args.value ? toTimePart(this.args.value) : '';
  @tracked pastWarning = false;

  // Pret UI RadioGroup names its own radios per instance, so two open
  // publish panels never share a group; the id labels this picker's group.
  legendId = `schedule-legend-${guidFor(this)}`;

  modeOptions: RadioOption[] = [
    { value: 'now', label: 'Publish now' },
    { value: 'later', label: 'Schedule for later' },
  ];

  chooseMode = (value: string) => {
    if (value === 'now') {
      this.mode = 'now';
      this.pastWarning = false;
      this.args.onChange(undefined);
    } else {
      this.mode = 'later';
      this.emit();
    }
  };

  onDate = (value: string) => {
    this.datePart = value;
    this.mode = 'later';
    this.emit();
  };

  onTime = (value: string) => {
    this.timePart = value;
    this.mode = 'later';
    this.emit();
  };

  emit() {
    if (this.mode !== 'later' || !this.datePart) {
      return;
    }
    let [y, m, d] = this.datePart.split('-').map(Number);
    let [hh, mm] = (this.timePart || '09:00').split(':').map(Number);
    // Local calendar parts → a real Date → ISO for storage.
    let when = new Date(y, m - 1, d, hh, mm);
    // A moment already past is not a schedule; report nothing rather than let
    // it publish immediately under a "later" label.
    this.pastWarning = !isNaN(when.getTime()) && when.getTime() <= Date.now();
    if (this.pastWarning) {
      this.args.onChange(undefined);
      return;
    }
    if (!isNaN(when.getTime())) {
      this.args.onChange(when.toISOString());
    }
  }

  <template>
    <fieldset class='schedule' ...attributes>
      <legend class='legend' id={{this.legendId}}>When to publish</legend>
      <RadioGroup
        class='modes'
        @options={{this.modeOptions}}
        @value={{this.mode}}
        @onValueChange={{this.chooseMode}}
        aria-labelledby={{this.legendId}}
      />
      {{! picking a date or a time selects "Schedule for later" }}
      <div class='parts'>
        <Input
          @type='date'
          @value={{this.datePart}}
          @onInput={{this.onDate}}
          aria-label='Publish date'
        />
        <Input
          @type='time'
          @value={{this.timePart}}
          @onInput={{this.onTime}}
          aria-label='Publish time'
        />
      </div>
      {{#if this.pastWarning}}
        <Alert @tone='warning' style={{ALERT_STYLE.attention}}>That time has
          passed — choose a future moment, or publish now.</Alert>
      {{/if}}
    </fieldset>
    <style scoped>
      .schedule {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-sm);
        display: grid;
        gap: var(--boxel-sp-xs);
        margin: 0;
        font-size: 0.8125rem;
        color: var(--foreground);
      }
      .legend {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
        padding: 0 var(--boxel-sp-5xs);
      }
      .modes {
        --text-ui-md: 0.8125rem;
      }
      /* the date and time sit under "Schedule for later", in line with its
         label */
      .parts {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--boxel-sp-xs);
        padding-inline-start: calc(0.9375rem + 0.5rem);
      }
    </style>
  </template>
}

function toDatePart(iso: string): string {
  let d = new Date(iso);
  if (isNaN(d.getTime())) {
    return '';
  }
  let mm = String(d.getMonth() + 1).padStart(2, '0');
  let dd = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${mm}-${dd}`;
}

function toTimePart(iso: string): string {
  let d = new Date(iso);
  if (isNaN(d.getTime())) {
    return '';
  }
  let hh = String(d.getHours()).padStart(2, '0');
  let mm = String(d.getMinutes()).padStart(2, '0');
  return `${hh}:${mm}`;
}

export default SchedulePicker;
