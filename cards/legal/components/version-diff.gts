import GlimmerComponent from '@glimmer/component';
import { guidFor } from '@ember/object/internals';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Table } from '@cardstack/pretui/components/table';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { formatMoney } from '@cardstack/catalog/cards/commerce/line-item-totals';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';

interface DiffRow {
  label: string;
  before: string;
  after: string;
  changed: boolean;
}

interface Signature {
  Args: {
    /** Older version first. */
    before?: any;
    after?: any;
  };
  Element: HTMLElement;
}

/**
 * VERSION DIFF — what an amendment actually changed.
 *
 * WHY FIELD-LEVEL, not text diff. A word-level diff of contract prose is
 * negotiation redlining, which this block leaves alone. What a reviewer needs
 * here is narrower and more answerable: did the value, the end date or the
 * signing party move between versions, and by how much.
 *
 * UNCHANGED ROWS ARE KEPT, not hidden. A diff that shows only what moved makes
 * the reader guess whether an absent field was unchanged or simply not
 * recorded — and "the end date didn't change" is itself a finding when someone
 * expected it to.
 */
export class VersionDiff extends GlimmerComponent<Signature> {
  private money(v: any): string {
    return formatMoney(v?.amount, v?.currency?.code) || '—';
  }

  private day(v: any): string {
    return formatDay(v);
  }

  get rows(): DiffRow[] {
    let a: any = this.args.before;
    let b: any = this.args.after;
    let make = (label: string, before: string, after: string): DiffRow => ({
      label,
      before,
      after,
      changed: before !== after,
    });
    return [
      make(
        'Value',
        this.money(a?.valueAtVersion),
        this.money(b?.valueAtVersion),
      ),
      make(
        'End date',
        this.day(a?.endDateAtVersion),
        this.day(b?.endDateAtVersion),
      ),
      make(
        'Executed by',
        a?.executedBy?.cardTitle ?? '—',
        b?.executedBy?.cardTitle ?? '—',
      ),
      make('Effective', this.day(a?.effectiveDate), this.day(b?.effectiveDate)),
    ];
  }

  get hasBoth(): boolean {
    return Boolean(this.args.before && this.args.after);
  }

  sumId = `${guidFor(this)}-sum`;

  get changedCount(): number {
    return this.rows.filter((r) => r.changed).length;
  }

  <template>
    <div class='vd' ...attributes>
      {{#if this.hasBoth}}
        <p class='vd-sum' id={{this.sumId}}>
          {{#if this.changedCount}}
            {{this.changedCount}}
            of
            {{this.rows.length}}
            tracked fields changed.
          {{else}}
            No tracked field changed between these versions.
          {{/if}}
        </p>
        <Table @labelledBy={{this.sumId}}>
          <:head>
            <tr>
              <th scope='col'>Field</th>
              <th scope='col'>Before</th>
              <th scope='col'>After</th>
            </tr>
          </:head>
          <:body>
            {{#each this.rows as |r|}}
              <tr class='{{if r.changed "is-changed"}}'>
                <th scope='row'>{{r.label}}{{#if r.changed}}<span
                      class='vd-mark'
                    >changed</span>{{/if}}</th>
                <td class='vd-was'>{{r.before}}</td>
                <td class='vd-now'>{{r.after}}</td>
              </tr>
            {{/each}}
          </:body>
        </Table>
      {{else}}
        <EmptyState
          @title='Pick two versions to compare.'
          @texture={{false}}
          style={{COMPACT_EMPTY_STYLE}}
        />
      {{/if}}
    </div>

    <style scoped>
      .vd {
        container-type: inline-size;
      }
      .vd-sum {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .vd-was,
      .vd-now {
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
      }
      /* A change is marked by weight and a word, not by colour alone. */
      .vd-mark {
        margin-inline-start: var(--boxel-sp-4xs);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--attention-ink);
      }
      .is-changed .vd-was {
        color: var(--muted-foreground);
        text-decoration: line-through;
      }
      .is-changed .vd-now {
        font-weight: 700;
      }
    </style>
  </template>
}

export default VersionDiff;
