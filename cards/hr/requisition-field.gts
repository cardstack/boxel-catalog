import { StringField } from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';

import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';

// Requisition lifecycle: draft → approved → posted → filled → closed
// draft: not yet reviewed
// approved: ready to post
// posted: active job posting
// filled: position filled, stop recruiting
// closed: no longer needed
export const REQUISITION_STATUSES = [
  'draft',
  'approved',
  'posted',
  'filled',
  'closed',
];

export const REQUISITION_STATUS_LABELS: Record<string, string> = {
  draft: 'Draft',
  approved: 'Approved',
  posted: 'Posted',
  filled: 'Filled',
  closed: 'Closed',
};

export const REQUISITION_STATUS_OPTIONS = REQUISITION_STATUSES.map((value) => ({
  value,
  label: REQUISITION_STATUS_LABELS[value],
}));

// Posted and filled share the green of active work, closed the red of a
// rejected candidate, and draft stays neutral.
export const REQUISITION_STATUS_HUES: Record<string, Hue> = {
  draft: 'slate',
  approved: 'blue',
  posted: 'green',
  filled: 'green',
  closed: 'red',
};

export const REQUISITION_STATUS_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(REQUISITION_STATUS_HUES).map(([k, hue]) => [
      k,
      stateColor(hue),
    ]),
  );

export const RequisitionStatusField = enumField(StringField, {
  options: REQUISITION_STATUS_OPTIONS,
  displayName: 'Requisition Status',
});
