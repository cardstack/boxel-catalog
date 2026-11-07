// The audit-trail action vocabulary, in a module of its own so a component
// can read labels and hues without importing the AuditEntry card. One copy of
// the map, so the timeline and the card never disagree about a label.
// `audit-entry.gts` re-exports every name below.

import type { Hue } from '@cardstack/catalog/components/state-pill';

export const AUDIT_ACTIONS = [
  { value: 'created', label: 'Created', hue: 'slate' },
  { value: 'submitted', label: 'Submitted for approval', hue: 'blue' },
  { value: 'approved', label: 'Approved', hue: 'green' },
  {
    value: 'approved_with_conditions',
    label: 'Approved with conditions',
    hue: 'teal',
  },
  { value: 'rejected', label: 'Rejected', hue: 'red' },
  { value: 'delegated', label: 'Delegated', hue: 'purple' },
  { value: 'on_hold', label: 'Placed on hold', hue: 'amber' },
  { value: 'resumed', label: 'Resumed', hue: 'blue' },
  { value: 'signed', label: 'Signed', hue: 'green' },
  { value: 'amended', label: 'Amended', hue: 'orange' },
  { value: 'renewed', label: 'Renewed', hue: 'green' },
  { value: 'terminated', label: 'Terminated', hue: 'red' },
  // A finding closes with a resolution code, which is neither an amendment
  // nor an approval.
  { value: 'closed', label: 'Closed', hue: 'green' },
] as const;

export function auditActionLabel(value?: string | null): string {
  return AUDIT_ACTIONS.find((a) => a.value === value)?.label ?? value ?? '—';
}

export function auditActionHue(value?: string | null): Hue {
  return (AUDIT_ACTIONS.find((a) => a.value === value)?.hue ?? 'slate') as Hue;
}
