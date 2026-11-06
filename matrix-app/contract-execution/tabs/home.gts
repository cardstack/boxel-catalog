import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { CONTRACT_STATUSES } from '../../legal/contract-status';
import { formatMoney } from '../../commerce/line-item-totals';
import type { ContractExecutionView } from '../contract-execution-app';
import {
  formatDay,
  hueTone,
  noticeTone,
  riskTone,
  type Tone,
} from '../contract-execution-data';
import {
  Block,
  CeTable,
  Dot,
  StatStrip,
  SubHead,
  type Col,
} from '../components';

interface Signature {
  Args: { app: ContractExecutionView };
}

const YEAR = 365;

// The stages a contract moves through before it is in force; expired and
// terminated are history, not pipeline.
const PIPELINE = [
  'draft',
  'negotiating',
  'in review',
  'approved',
  'out for signature',
  'signed',
];

interface AttentionRow {
  key: string;
  title: string;
  sub: string;
  tone: Tone;
  state: string;
  open: () => void;
}

export class HomeTab extends GlimmerComponent<Signature> {
  columns: Col[] = [
    { label: 'Number', kind: 'mono', value: (c) => c.contractNumber ?? '—' },
    { label: 'Contract', kind: 'title', value: (c) => c.cardTitle },
    { label: 'Notice by', kind: 'mono', value: (c) => formatDay(c.noticeBy) },
    { label: 'Time left', kind: 'custom' },
    {
      label: 'Days',
      kind: 'dot',
      align: 'end',
      value: (c) => c.daysToNotice,
      tone: (c) => noticeTone(c.daysToNotice),
    },
    {
      label: 'Value',
      kind: 'mono',
      align: 'end',
      value: (c) =>
        formatMoney(c.value?.amount, c.value?.currency?.code) || '—',
    },
  ];

  get yearAhead() {
    return this.args.app.search(
      this.args.app.contracts
        .filter((c) => {
          let d = c.daysToNotice;
          return typeof d === 'number' && d >= 0 && d <= YEAR;
        })
        .sort((a, b) => (a.daysToNotice ?? 0) - (b.daysToNotice ?? 0)),
      (c) => [c.cardTitle, c.contractNumber],
    );
  }

  timeLeft = (c: any): number =>
    Math.min(100, Math.round(((c.daysToNotice ?? 0) / YEAR) * 100));

  timeHue = (c: any): string => {
    let tone = noticeTone(c.daysToNotice);
    return tone === 'bad'
      ? 'var(--destructive)'
      : tone === 'warn'
        ? 'var(--warning)'
        : 'var(--foreground)';
  };

  get stages() {
    return PIPELINE.map((value) => {
      let o = CONTRACT_STATUSES.find((s) => s.value === value);
      return {
        label: value === 'signed' ? 'Signed & in force' : (o?.label ?? value),
        value: this.args.app.contracts.filter((c) => c.status === value).length,
        tone: hueTone(o?.hue),
      };
    });
  }

  get noticeRows(): AttentionRow[] {
    return this.args.app.renewalRows
      .filter((c) => (c.daysToNotice ?? -1) >= 0)
      .map((c: any) => ({
        key: c.id,
        title: c.cardTitle,
        sub: `notice by ${formatDay(c.noticeBy)}`,
        tone: noticeTone(c.daysToNotice),
        state: `${c.daysToNotice} days`,
        open: () => this.args.app.openInWorkspace(c),
      }));
  }

  get signatureRows(): AttentionRow[] {
    return this.args.app.contracts
      .filter((c) => c.status === 'out for signature')
      .map((c: any) => ({
        key: c.id,
        title: c.cardTitle,
        sub: [
          c.signatureRequestedAt
            ? `sent ${formatDay(c.signatureRequestedAt)}`
            : undefined,
          c.signatureProvider,
        ]
          .filter(Boolean)
          .join(' · '),
        tone: 'warn' as Tone,
        state: 'pending',
        open: () => this.args.app.openInWorkspace(c),
      }));
  }

  get deviationRows(): AttentionRow[] {
    return this.args.app.openDeviations.map((u: any) => ({
      key: u.id,
      title: u.cardTitle,
      sub: u.contract?.cardTitle ?? '',
      tone: riskTone(u.riskLevel),
      state: u.riskLevel ?? u.deviationSeverity ?? '—',
      open: () =>
        u.contract
          ? this.args.app.openInWorkspace(u.contract)
          : this.args.app.openCard(u),
    }));
  }

  get groups() {
    return [
      { label: 'Notice deadlines', rows: this.noticeRows },
      { label: 'Awaiting signature', rows: this.signatureRows },
      { label: 'Open deviations', rows: this.deviationRows },
    ].filter((g) => g.rows.length);
  }

  showRenewals = () => this.args.app.pickTab('renewals');

  <template>
    <div class='home'>
      <Block
        @flat={{true}}
        @title='The year ahead'
        @sub='Contracts with a notice deadline inside the next 365 days, soonest first'
      >
        <:action>
          <button
            type='button'
            class='home-link'
            {{on 'click' this.showRenewals}}
          >Renewals</button>
        </:action>
        <:default>
          {{#if this.yearAhead.length}}
            <CeTable
              @label='Notice deadlines in the next year'
              @columns={{this.columns}}
              @rows={{this.yearAhead}}
              @onOpen={{@app.openInWorkspace}}
            >
              <:cell as |row|>
                <ProgressBar
                  class='home-left'
                  @value={{this.timeLeft row}}
                  @hue={{this.timeHue row}}
                  aria-label='Time left to serve notice'
                />
              </:cell>
            </CeTable>
          {{else}}
            <p class='home-empty'>No notice deadline in the next year.</p>
          {{/if}}
          <SubHead
            @label='Where every contract sits'
            @sub='The book by lifecycle stage, first draft to in force'
          />
          <StatStrip
            @flat={{true}}
            @stats={{this.stages}}
            @label='Contracts by stage'
          />
        </:default>
      </Block>

      <Block
        class='home-side'
        @flat={{true}}
        @title='Needs attention'
        @sub='Most urgent first; each row opens its contract'
      >
        {{#each this.groups as |g|}}
          <SubHead @label={{g.label}} @count={{g.rows.length}} />
          <ul class='home-list'>
            {{#each g.rows as |r|}}
              <li>
                <button type='button' class='home-row' {{on 'click' r.open}}>
                  <span class='home-row-id'>
                    <strong>{{r.title}}</strong>
                    <span class='home-row-sub'>{{r.sub}}</span>
                  </span>
                  <Dot @tone={{r.tone}} @label={{r.state}} />
                </button>
              </li>
            {{/each}}
          </ul>
        {{else}}
          <p class='home-empty'>Nothing needs attention.</p>
        {{/each}}
      </Block>
    </div>
    <style scoped>
      .home {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(16rem, 19rem);
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
      }
      /* two columns of one block: full-height divider, flat insides */
      .home-side {
        border-inline-start: 1px solid var(--border);
      }
      .home-left {
        inline-size: 10rem;
      }
      .home-link {
        padding: 0;
        border: 0;
        background: none;
        color: inherit;
        font: inherit;
        cursor: pointer;
      }
      .home-link:hover {
        text-decoration: underline;
      }
      .home-list {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .home-list li + li {
        border-top: 1px solid var(--border);
      }
      .home-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        inline-size: 100%;
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        border: 0;
        background: none;
        color: inherit;
        font: inherit;
        text-align: start;
        cursor: pointer;
      }
      .home-row:hover {
        background: var(--muted);
      }
      .home-row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -2px;
      }
      .home-row-id {
        display: grid;
        flex: 1;
        min-inline-size: 0;
      }
      .home-row-id > * {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .home-row-sub {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .home-empty {
        margin: 0;
        padding: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
      @container cx-app (width < 52rem) {
        .home {
          grid-template-columns: minmax(0, 1fr);
        }
        .home-side {
          border-inline-start: 0;
          border-top: 1px solid var(--border);
        }
      }
    </style>
  </template>
}
