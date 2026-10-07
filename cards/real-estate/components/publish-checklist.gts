import GlimmerComponent from '@glimmer/component';

// Publish Checklist — the pre-publish gate, rendered. Render-only: it
// paints the same requirements PublishListingCommand enforces (the command
// re-checks everything at write time, so this list can never grant what
// the guard refuses). Structural model type on purpose — any object with
// these facts can be checked, and the component never imports the card.

interface ChecklistModel {
  photoCount?: number | null;
  askingPrice?: { amount?: number | null } | null;
  description?: string | null;
  address?: {
    addressLine1?: string | null;
    city?: string | null;
  } | null;
  cardTitle?: string | null;
}

interface ChecklistRow {
  label: string;
  state: 'pass' | 'fail' | 'warn';
  hint?: string;
}

interface Signature {
  Args: {
    model: ChecklistModel | undefined;
  };
  Element: HTMLElement;
}

const GLYPH: Record<ChecklistRow['state'], string> = {
  pass: '✓',
  fail: '✗',
  warn: '!',
};

// What the glyph says to a screen reader, which hears no colour.
const STATE_NAME: Record<ChecklistRow['state'], string> = {
  pass: 'Done',
  fail: 'Required',
  warn: 'Recommended',
};

export class PublishChecklist extends GlimmerComponent<Signature> {
  get rows(): ChecklistRow[] {
    let m = this.args.model;
    let photoCount = m?.photoCount ?? 0;
    let descriptionLength = (m?.description ?? '').trim().length;
    let rows: ChecklistRow[] = [];

    rows.push(
      photoCount >= 10
        ? { label: `${photoCount} photos uploaded`, state: 'pass' }
        : photoCount >= 1
          ? {
              label: `${photoCount} photo${photoCount === 1 ? '' : 's'} uploaded`,
              state: 'warn',
              hint: '10+ recommended',
            }
          : {
              label: 'No photos yet',
              state: 'fail',
              hint: 'at least 1 required, 10 recommended',
            },
    );
    rows.push(
      m?.askingPrice?.amount != null
        ? { label: 'Price set', state: 'pass' }
        : { label: 'Price not set', state: 'fail' },
    );
    rows.push(
      descriptionLength >= 100
        ? { label: 'Description written', state: 'pass' }
        : {
            label: descriptionLength
              ? `Description is short (${descriptionLength} chars)`
              : 'No description',
            state: 'warn',
            hint: 'min 100 chars recommended',
          },
    );
    rows.push(
      m?.address?.addressLine1?.trim() && m?.address?.city?.trim()
        ? { label: 'Address complete', state: 'pass' }
        : { label: 'Address incomplete', state: 'fail' },
    );
    return rows;
  }

  /** True when nothing is a hard fail — warns don't block. */
  get ready(): boolean {
    return this.rows.every((row) => row.state !== 'fail');
  }

  glyphOf = (state: ChecklistRow['state']) => GLYPH[state];
  stateNameOf = (state: ChecklistRow['state']) => STATE_NAME[state];

  <template>
    <ul class='checklist' ...attributes>
      {{#each this.rows as |row|}}
        <li class='row {{row.state}}'>
          <span
            class='glyph'
            role='img'
            aria-label={{this.stateNameOf row.state}}
          >{{this.glyphOf row.state}}</span>
          <span class='label'>{{row.label}}</span>
          {{#if row.hint}}
            <span class='hint'>{{row.hint}}</span>
          {{/if}}
        </li>
      {{/each}}
    </ul>
    <style scoped>
      /* pass, fail and warn are statuses: each takes its status token's ink,
         on a tint of that ink. The --ck-*-color knobs override a state's ink. */
      .checklist {
        margin: 0;
        padding: 0;
        list-style: none;
        display: grid;
        gap: var(--boxel-sp-5xs);
        font-size: 0.8125rem;
      }
      .row {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
      }
      .row.pass {
        --ck-ink: var(--ck-pass-color, var(--success-ink));
      }
      .row.fail {
        --ck-ink: var(--ck-fail-color, var(--destructive-ink));
      }
      .row.warn {
        --ck-ink: var(--ck-warn-color, var(--attention-ink));
      }
      .glyph {
        flex: 0 0 auto;
        width: 1.25rem;
        height: 1.25rem;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: 999px;
        font-size: 0.6875rem;
        font-weight: 700;
        line-height: 1;
        color: var(--ck-ink);
        background-color: color-mix(in oklab, var(--ck-ink) 10%, transparent);
      }
      .label {
        color: var(--foreground);
      }
      .row.fail .label {
        color: var(--ck-ink);
      }
      .hint {
        font-size: 0.75rem;
        font-style: italic;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export default PublishChecklist;
