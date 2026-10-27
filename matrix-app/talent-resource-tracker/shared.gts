import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { Button } from '../../ui-component/components/button';
import type { Candidate } from '../hr/candidate';
import { type BaseDef } from '@cardstack/base/card-api';
import { codeRef } from '@cardstack/runtime-common';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
export const here: string = import.meta.url;
export const employeeRef = codeRef(here, '../hr/employee', 'Employee');
export const meetingRef = codeRef(here, '../hr/meeting', 'Meeting');

// Renders a card instance fetched from a live query (which has no @fields
// entry to hand the template) via its own class's component.
export function getComponent(cardOrField: BaseDef | undefined) {
  if (!cardOrField) {
    return undefined;
  }
  return (cardOrField.constructor as typeof BaseDef).getComponent(cardOrField);
}

export const TABS = [
  'Dashboard',
  'Positions',
  'Applications',
  'Pipeline',
  'Offers',
  'Requisitions',
  'Onboarding',
  'Contractors',
  'PTO',
  'Reviews',
  'Directory',
  'Calendar',
  'Org Chart',
] as const;
export type Tab = (typeof TABS)[number];

export interface CandidateSnapshot {
  status: Candidate['status'];
  boardOrder: Candidate['boardOrder'];
  offerState: Candidate['offerState'];
}

export function snapshotCandidate(candidate: Candidate): CandidateSnapshot {
  return {
    status: candidate.status,
    boardOrder: candidate.boardOrder,
    offerState: candidate.offerState,
  };
}

export function restoreCandidate(
  candidate: Candidate,
  snapshot: CandidateSnapshot,
) {
  candidate.status = snapshot.status;
  candidate.boardOrder = snapshot.boardOrder;
  candidate.offerState = snapshot.offerState;
}

// Panel's <:header> for a list tab: the title, and its count muted at the
// end of the same row, as the mockup's panel heading has them.
export const PanelHead: TemplateOnlyComponent<{
  Args: { title: string; meta?: string };
}> = <template>
  <div class='panel-head'>
    <h2>{{@title}}</h2>
    {{#if @meta}}<span class='panel-meta'>{{@meta}}</span>{{/if}}
  </div>
  <style scoped>
    .panel-head {
      display: flex;
      flex-wrap: wrap;
      align-items: baseline;
      justify-content: space-between;
      gap: var(--boxel-sp-sm);
    }
    h2 {
      margin: 0;
      font-size: var(--pretui-panel-title-size, var(--boxel-font-size-sm));
      font-weight: 600;
    }
    .panel-meta {
      font-size: var(--boxel-font-size-xs);
      color: var(--muted-foreground);
    }
  </style>
</template>;

// A "needs attention" pill that jumps to the tab holding the work: white,
// navy label, the tone shown only by the dot before it.
export const AlertPill: TemplateOnlyComponent<{
  Args: { tone: 'warning' | 'danger'; onClick: () => void };
  Blocks: { default: [] };
}> = <template>
  <Button
    type='button'
    @tone='neutral'
    @appearance='accent'
    @size='s'
    @shape='pill'
    class='alert-pill'
    {{on 'click' @onClick}}
  ><span
      class='alert-dot'
      data-tone={{@tone}}
      aria-hidden='true'
    ></span>{{yield}}</Button>
  <style scoped>
    /* accent is the recipe that reads --pretui-button-bg/-fg */
    .alert-pill {
      --pretui-button-bg: var(--card);
      --pretui-button-fg: var(--primary-ink);
    }
    .alert-dot {
      inline-size: var(--boxel-sp-xs);
      block-size: var(--boxel-sp-xs);
      border-radius: var(--boxel-border-radius-pill);
      background: var(--warning);
    }
    .alert-dot[data-tone='danger'] {
      background: var(--destructive);
    }
  </style>
</template>;

// The first-cell text of a table row as a real button: the keyboard path for
// DataTable's @onRowActivate, which is a mouse shortcut only. It reads as
// plain text until hovered or focused.
export const RowOpen: TemplateOnlyComponent<{
  Args: { onOpen: () => void };
  Blocks: { default: [] };
}> = <template>
  <button type='button' class='row-open' {{on 'click' @onOpen}}>
    {{yield}}
  </button>
  <style scoped>
    .row-open {
      display: inline-flex;
      align-items: center;
      gap: inherit;
      margin: 0;
      padding: 0;
      border: 0;
      background: none;
      color: inherit;
      font: inherit;
      text-align: start;
      cursor: pointer;
    }
    .row-open:hover {
      color: var(--primary);
      text-decoration: underline;
    }
    .row-open:focus-visible {
      outline: 0.125rem solid var(--ring);
      outline-offset: 0.125rem;
      border-radius: var(--radius);
    }
  </style>
</template>;
