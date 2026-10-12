import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import QuantityField from '@cardstack/catalog/fields/quantity/quantity';
import {
  FieldContainer,
  Button,
  BoxelInput,
} from '@cardstack/boxel-ui/components';
import GaugeIcon from '@cardstack/boxel-icons/gauge';

import MeterReadingField from './meter-reading-field';
import { MeterKindField } from './maintenance-vocabulary';
import { Asset } from './asset';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import { absoluteStamp } from './utils/relative-time';
import RecordMeterReadingCommand from './commands/record-meter-reading-command';

function sorted(readings: MeterReadingField[] | null | undefined) {
  return (readings ?? [])
    .filter((r) => r && r.value != null)
    .slice()
    .sort((a, b) => {
      let ta = a.readAt ? new Date(a.readAt).getTime() : 0;
      let tb = b.readAt ? new Date(b.readAt).getTime() : 0;
      return ta - tb;
    });
}

class MeterIsolated extends Component<typeof Meter> {
  // Commands need the host; a card rendered without one cannot act.
  private get commandContext() {
    let context = this.args.context?.commandContext;
    if (!context) {
      throw new Error('This action needs a running host.');
    }
    return context;
  }

  @tracked newValue = '';
  @tracked newNote = '';
  @tracked recordError: string | undefined;

  get rows() {
    return sorted(this.args.model.readings).slice().reverse();
  }
  get when() {
    return absoluteStamp(this.args.model.lastReadAt ?? undefined);
  }

  get canRecord() {
    return this.newValue.trim() !== '' && !isNaN(Number(this.newValue));
  }

  get recordDisabled() {
    return !this.canRecord;
  }

  setNewValue = (v: string) => {
    this.newValue = v;
  };
  setNewNote = (v: string) => {
    this.newNote = v;
  };

  recordReading = async (event?: Event) => {
    event?.preventDefault();
    this.recordError = undefined;
    let value = Number(this.newValue);
    if (this.newValue.trim() === '' || isNaN(value)) {
      this.recordError = 'Enter a numeric value.';
      return;
    }
    try {
      await new RecordMeterReadingCommand(this.commandContext).execute({
        meter: this.args.model,
        value,
        note: this.newNote || undefined,
      } as any);
      this.newValue = '';
      this.newNote = '';
    } catch (e: any) {
      this.recordError = e?.message ?? 'Could not record this reading.';
    }
  };
  <template>
    <article class='iso'>
      <header class='hero'>
        <div>
          <p class='eyebrow'>Meter ·
            {{@model.kind}}{{#if @model.assetTag}}
              ·
              <code>{{@model.assetTag}}</code>{{/if}}</p>
          <h1 class='title'>{{@model.name}}</h1>
          {{#if @model.asset}}<div class='sub'><@fields.asset
                @format='atom'
              /></div>{{/if}}
        </div>
        <div class='big {{if @model.isWarning "big--warn"}}'>
          <span class='big-v'>{{@model.currentLabel}}</span>
          <span class='big-l'>{{#if this.when}}read {{this.when}}{{else}}no
              readings yet{{/if}}</span>
        </div>
      </header>
      <section class='stats'>
        <div><span class='s-l'>Average / week</span><span class='s-v'>{{if
              @model.averagePerWeek
              @model.averagePerWeek
              '—'
            }}
            {{@model.unit}}</span></div>
        <div><span class='s-l'>Last delta</span><span class='s-v'>{{if
              @model.lastDelta
              @model.lastDelta
              '—'
            }}
            {{@model.unit}}</span></div>
        <div><span class='s-l'>Warn above</span><span class='s-v'>{{if
              @model.warnAbove
              @model.warnAbove
              '—'
            }}</span></div>
        <div><span class='s-l'>Warn below</span><span class='s-v'>{{if
              @model.warnBelow
              @model.warnBelow
              '—'
            }}</span></div>
      </section>
      <section class='panel'>
        <div class='panel-head'>
          <h2>Readings (newest first)</h2>
          <form class='record-form' {{on 'submit' this.recordReading}}>
            <label class='sr-only' for='meter-new-value'>Reading value</label>
            <BoxelInput
              id='meter-new-value'
              @value={{this.newValue}}
              @onInput={{this.setNewValue}}
              placeholder='Value'
              type='number'
            />
            <label class='sr-only' for='meter-new-note'>Note</label>
            <BoxelInput
              id='meter-new-note'
              @value={{this.newNote}}
              @onInput={{this.setNewNote}}
              placeholder='Note (optional)'
            />
            <Button
              @kind='primary'
              @size='touch'
              @disabled={{this.recordDisabled}}
              type='submit'
            >Record reading</Button>
          </form>
        </div>
        {{#if this.recordError}}
          <p class='record-error' role='alert'>{{this.recordError}}</p>
        {{/if}}
        {{#if this.rows.length}}
          <ul class='list'>
            {{#each @fields.readings as |Reading|}}
              <li><Reading @format='embedded' /></li>
            {{/each}}
          </ul>
        {{else}}
          <p class='empty'>No readings recorded — use Record Meter Reading.</p>
        {{/if}}
      </section>
    </article>
    <style scoped>
      .iso {
        container-type: inline-size;
        padding: var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp);
        color: var(--foreground);
        background: var(--card);
      }
      .hero {
        display: flex;
        justify-content: space-between;
        gap: var(--boxel-sp);
        align-items: flex-start;
        flex-wrap: wrap;
      }
      .eyebrow {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted-foreground);
      }
      .eyebrow code {
        font-family: var(
          --boxel-monospace-font-family,
          ui-monospace,
          monospace
        );
        text-transform: none;
      }
      .title {
        margin: 0;
        font-size: var(--boxel-font-size-xl);
        font-weight: 700;
      }
      .sub {
        margin-top: var(--boxel-sp-4xs);
      }
      .big {
        text-align: right;
      }
      .big-v {
        display: block;
        font-size: 2.5rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1;
      }
      .big--warn .big-v {
        color: var(--destructive, var(--foreground));
      }
      .big-l {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
        gap: 1px;
        background: var(--border);
        border: 1px solid var(--border);
        border-radius: 6px;
        overflow: hidden;
      }
      .stats > div {
        background: var(--card);
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        display: grid;
        gap: 2px;
      }
      .s-l {
        font-size: var(--boxel-font-size-xs);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .s-v {
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }
      .panel {
        border: 1px solid var(--border);
        border-radius: 6px;
        padding: var(--boxel-sp);
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .panel h2 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .panel-head {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: var(--boxel-sp);
        flex-wrap: wrap;
      }
      .record-form {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .record-form :deep(input) {
        min-width: 8rem;
      }
      .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
      }
      .record-error {
        margin: 0;
        color: var(--destructive, var(--foreground));
        font-size: var(--boxel-font-size-xs);
      }
      .list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .empty {
        margin: 0;
        color: var(--muted-foreground);
        font-style: italic;
      }
    </style>
  </template>
}

/**
 * A per-asset counter or gauge — running hours, km, cycles, kWh, °C.
 * Readings are appended (Record Meter Reading is the single writer; a
 * cumulative meter must be monotonic). Meter-based maintenance plans fire
 * when the delta since the last completion crosses their threshold.
 */
export class Meter extends CardDef {
  static displayName = 'Meter';
  static icon = GaugeIcon;

  @field asset = linksTo(() => Asset);
  @field name = contains(StringField);
  @field kind = contains(MeterKindField);
  @field unit = contains(StringField);
  @field readings = containsMany(MeterReadingField);
  @field warnAbove = contains(QuantityField, {
    configuration: { options: { min: -Infinity } },
  });
  @field warnBelow = contains(QuantityField, {
    configuration: { options: { min: -Infinity } },
  });

  @field current = contains(NumberField, {
    computeVia: function (this: Meter) {
      let s = sorted(this.readings);
      return s.length ? s[s.length - 1].value : undefined;
    },
  });
  @field lastReadAt = contains(DateTimeField, {
    computeVia: function (this: Meter) {
      let s = sorted(this.readings);
      return s.length ? s[s.length - 1].readAt : undefined;
    },
  });
  @field lastDelta = contains(NumberField, {
    computeVia: function (this: Meter) {
      let s = sorted(this.readings);
      if (s.length < 2) return undefined;
      let a = s[s.length - 2].value ?? 0;
      let b = s[s.length - 1].value ?? 0;
      return Math.round((b - a) * 100) / 100;
    },
  });
  @field averagePerWeek = contains(NumberField, {
    computeVia: function (this: Meter) {
      if (this.kind === 'gauge') return undefined;
      let s = sorted(this.readings).slice(-8);
      if (s.length < 2) return undefined;
      let first = s[0];
      let last = s[s.length - 1];
      let weeks =
        (new Date(last.readAt!).getTime() - new Date(first.readAt!).getTime()) /
        (7 * 86_400_000);
      if (weeks <= 0) return undefined;
      return (
        Math.round((((last.value ?? 0) - (first.value ?? 0)) / weeks) * 10) / 10
      );
    },
  });
  @field isWarning = contains(StringField, {
    computeVia: function (this: Meter) {
      let c = this.current;
      if (c == null) return '';
      if (this.warnAbove != null && c > this.warnAbove) return 'above';
      if (this.warnBelow != null && c < this.warnBelow) return 'below';
      return '';
    },
  });
  @field assetId = contains(StringField, {
    computeVia: function (this: Meter) {
      return this.asset?.id;
    },
  });
  @field assetTag = contains(StringField, {
    computeVia: function (this: Meter) {
      return this.asset?.identifier?.value;
    },
  });
  @field assetName = contains(StringField, {
    computeVia: function (this: Meter) {
      return this.asset?.name;
    },
  });
  @field currentLabel = contains(StringField, {
    computeVia: function (this: Meter) {
      if (this.current == null) return 'No readings';
      return `${this.current.toLocaleString()} ${this.unit ?? ''}`.trim();
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Meter) {
      let n = this.name?.trim() || 'Meter';
      return this.assetTag ? `${this.assetTag} · ${n}` : n;
    },
  });

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='m-atom'><GaugeIcon class='m-ico' />{{@model.name}}
        <strong>{{@model.currentLabel}}</strong></span>
      <style scoped>
        .m-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--foreground);
        }
        .m-ico {
          width: 0.85rem;
          height: 0.85rem;
          color: var(--muted-foreground);
        }
        strong {
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get when() {
      return absoluteStamp(this.args.model.lastReadAt ?? undefined);
    }
    <template>
      <div class='m {{if @model.isWarning "m--warn"}}'>
        <span class='m-disc'><GaugeIcon class='m-ico' /></span>
        <div class='m-body'>
          <div class='m-name'>{{@model.name}}
            <span class='m-kind'>{{@model.kind}}</span></div>
          <div class='m-meta'>{{#if this.when}}read {{this.when}}{{/if}}
            {{#if @model.averagePerWeek}}·
              {{@model.averagePerWeek}}
              {{@model.unit}}/wk{{/if}}
            {{#if @model.isWarning}}·
              <strong>warning
                {{@model.isWarning}}
                threshold</strong>{{/if}}</div>
        </div>
        <span class='m-value'>{{@model.currentLabel}}</span>
      </div>
      <style scoped>
        .m {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
          color: var(--foreground);
        }
        .m-disc {
          flex: none;
          width: 2rem;
          height: 2rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          background: var(--muted);
          color: var(--muted-foreground);
        }
        .m--warn .m-disc {
          color: var(--destructive, var(--foreground));
        }
        .m-ico {
          width: 1rem;
          height: 1rem;
        }
        .m-body {
          flex: 1;
          min-width: 0;
        }
        .m-name {
          font-weight: 600;
        }
        .m-kind,
        .m-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .m-value {
          font-variant-numeric: tabular-nums;
          font-weight: 700;
          font-size: var(--boxel-font-size);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fit'>
        <span class='fit-value'>{{@model.currentLabel}}</span>
        <span class='fit-name'>{{@model.name}}</span>
        <span class='fit-line fit-asset'>{{@model.assetTag}}
          {{@model.assetName}}</span>
        <span class='fit-line fit-rate'>{{#if
            @model.averagePerWeek
          }}{{@model.averagePerWeek}} {{@model.unit}}/wk{{/if}}{{#if
            @model.lastDelta
          }} · +{{@model.lastDelta}} last{{/if}}</span>
      </div>
      <style scoped>
        .fit {
          display: flex;
          flex-direction: column;
          align-items: stretch;
          justify-content: center;
          gap: 2px;
          width: 100%;
          height: 100%;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          box-sizing: border-box;
          overflow: hidden;
          color: var(--foreground);
        }
        .fit-value {
          font-variant-numeric: tabular-nums;
          font-weight: 700;
          font-size: var(--boxel-font-size-lg);
          line-height: 1.1;
          white-space: nowrap;
        }
        .fit-name {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .fit-line {
          display: none;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        @container fitted-card (max-height: 50px) {
          .fit {
            flex-direction: row;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fit-value {
            font-size: var(--boxel-font-size-sm);
          }
        }
        @container fitted-card (min-height: 100px) {
          .fit-asset {
            display: block;
          }
        }
        @container fitted-card (min-height: 170px) {
          .fit-value {
            font-size: var(--boxel-font-size-xxl, 2rem);
          }
          .fit-rate {
            display: block;
          }
        }
      </style>
    </template>
  };

  static isolated = MeterIsolated;

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'alarms', label: 'Alarms' },
      { id: 'readings', label: 'Readings' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Meter sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{2}}>
          <FieldContainer @label='Asset' @vertical={{true}}><@fields.asset
            /></FieldContainer>
          <FieldContainer @label='Name' @vertical={{true}}><@fields.name
            /></FieldContainer>
          <FieldContainer @label='Kind' @vertical={{true}}><@fields.kind
            /></FieldContainer>
          <FieldContainer @label='Unit' @vertical={{true}}><@fields.unit
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='alarms'
          @title='Alarms'
          @hint='gauge thresholds — a reading outside them flags the meter'
          @cols={{2}}
        >
          <FieldContainer
            @label='Warn above'
            @vertical={{true}}
          ><@fields.warnAbove /></FieldContainer>
          <FieldContainer
            @label='Warn below'
            @vertical={{true}}
          ><@fields.warnBelow /></FieldContainer>
        </e.Section>
        <e.Section
          @id='readings'
          @title='Readings'
          @hint='append with Record Meter Reading; edit here only to correct an import'
          @cols={{1}}
        >
          <@fields.readings />
        </e.Section>
      </SectionedEdit>
    </template>
  };
}

export default Meter;
