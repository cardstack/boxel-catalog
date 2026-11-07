import { markDefinition } from '@cardstack/base/mark-definition';
import { StringField } from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import { statusField } from '@cardstack/catalog/fields/status/status';
import { priorityField } from '@cardstack/catalog/fields/priority/priority';
import type { Hue } from '@cardstack/catalog/components/state-pill';

/**
 * Vocabulary for the maintenance cards — every enum their cards,
 * fields, components and commands share, defined ONCE so they can never
 * disagree. Leaf module: imports only base + catalog, never a card.
 *
 * Statuses are catalog `statusField()`s (transition graph, terminal flags,
 * hues) and the priority is a catalog `priorityField()` — consume, don't
 * rebuild.
 */

// ---------------------------------------------------------------- Asset Status
export const ASSET_STATUS_HUE: Record<string, Hue> = {
  'in-service': 'green',
  'out-of-service': 'orange',
  'under-maintenance': 'amber',
  'in-storage': 'slate',
  'on-loan': 'teal',
  disposed: 'slate',
};

export const AssetStatusField = markDefinition(
  statusField({
    displayName: 'Asset Status',
    options: [
      {
        value: 'in-service',
        label: 'In service',
        hue: 'green',
        meaning: 'Available and doing its job',
      },
      {
        value: 'out-of-service',
        label: 'Out of service',
        hue: 'orange',
        meaning: 'Down — failed or awaiting repair',
      },
      {
        value: 'under-maintenance',
        label: 'Under maintenance',
        hue: 'amber',
        holds: true,
        meaning: 'A technician has it right now',
      },
      {
        value: 'in-storage',
        label: 'In storage',
        hue: 'slate',
        meaning: 'Kept, not deployed',
      },
      {
        value: 'on-loan',
        label: 'On loan',
        hue: 'teal',
        meaning: 'Checked out to a person with a due-back date',
      },
      {
        value: 'disposed',
        label: 'Disposed',
        hue: 'slate',
        terminal: true,
        meaning: 'Sold, scrapped or returned — kept for the record',
      },
    ],
    transitions: {
      'in-service': [
        'out-of-service',
        'under-maintenance',
        'in-storage',
        'on-loan',
        'disposed',
      ],
      'out-of-service': ['under-maintenance', 'in-service', 'disposed'],
      'under-maintenance': ['in-service', 'out-of-service', 'in-storage'],
      'in-storage': ['in-service', 'on-loan', 'disposed'],
      'on-loan': ['in-service', 'in-storage'],
      disposed: [],
    },
  }),
);

// ----------------------------------------------------------- Work Order Status
export const WO_STATUS_HUE: Record<string, Hue> = {
  requested: 'slate',
  approved: 'teal',
  scheduled: 'blue',
  'in-progress': 'amber',
  'on-hold': 'orange',
  completed: 'green',
  closed: 'green',
  cancelled: 'slate',
};

export const WO_TERMINAL = new Set(['closed', 'cancelled']);

export const WorkOrderStatusField = markDefinition(
  statusField({
    displayName: 'Work Order Status',
    options: [
      {
        value: 'requested',
        label: 'Requested',
        hue: 'slate',
        meaning: 'Raised, not yet approved',
      },
      {
        value: 'approved',
        label: 'Approved',
        hue: 'teal',
        meaning: 'Cleared to schedule',
      },
      {
        value: 'scheduled',
        label: 'Scheduled',
        hue: 'blue',
        meaning: 'On the calendar with a technician',
      },
      {
        value: 'in-progress',
        label: 'In progress',
        hue: 'amber',
        meaning: 'A technician has started the work',
      },
      {
        value: 'on-hold',
        label: 'On hold',
        hue: 'orange',
        holds: true,
        meaning: 'Waiting on parts, access or approval',
      },
      {
        value: 'completed',
        label: 'Completed',
        hue: 'green',
        meaning: 'Work done — awaiting review',
      },
      {
        value: 'closed',
        label: 'Closed',
        hue: 'green',
        terminal: true,
        meaning: 'Reviewed and closed',
      },
      {
        value: 'cancelled',
        label: 'Cancelled',
        hue: 'slate',
        terminal: true,
        meaning: 'Withdrawn with a reason',
      },
    ],
    transitions: {
      requested: ['approved', 'scheduled', 'cancelled'],
      approved: ['scheduled', 'in-progress', 'cancelled'],
      scheduled: ['in-progress', 'on-hold', 'cancelled'],
      'in-progress': ['on-hold', 'completed', 'cancelled'],
      'on-hold': ['in-progress', 'scheduled', 'cancelled'],
      completed: ['closed', 'in-progress'],
      closed: [],
      cancelled: [],
    },
  }),
);

// -------------------------------------------------------------------- Priority
export const WorkOrderPriorityField = markDefinition(
  priorityField({
    displayName: 'Work Order Priority',
    options: [
      {
        value: 'P1',
        label: 'P1 · Emergency',
        hue: 'red',
        factor: 0.25,
        meaning: 'Production stopped or safety risk — respond now',
      },
      {
        value: 'P2',
        label: 'P2 · Urgent',
        hue: 'orange',
        factor: 0.5,
        meaning: 'Degraded operation — same day',
      },
      {
        value: 'P3',
        label: 'P3 · Planned',
        hue: 'amber',
        factor: 1,
        meaning: 'Scheduled work inside its window',
      },
      {
        value: 'P4',
        label: 'P4 · Low',
        hue: 'slate',
        factor: 2,
        meaning: 'Cosmetic or convenience — when capacity allows',
      },
    ],
  }),
);

// ----------------------------------------------------------------- Criticality
export interface CriticalityLevel {
  value: string;
  label: string;
  rank: number;
  hue: Hue;
  responseTargetHours: number;
  defaultPriority: string;
}

export const CRITICALITY: CriticalityLevel[] = [
  {
    value: 'low',
    label: 'Low',
    rank: 1,
    hue: 'slate',
    responseTargetHours: 72,
    defaultPriority: 'P4',
  },
  {
    value: 'medium',
    label: 'Medium',
    rank: 2,
    hue: 'teal',
    responseTargetHours: 24,
    defaultPriority: 'P3',
  },
  {
    value: 'high',
    label: 'High',
    rank: 3,
    hue: 'amber',
    responseTargetHours: 8,
    defaultPriority: 'P2',
  },
  {
    value: 'critical',
    label: 'Critical',
    rank: 4,
    hue: 'red',
    responseTargetHours: 2,
    defaultPriority: 'P1',
  },
];

export function criticalityLevel(
  value?: string | null,
): CriticalityLevel | undefined {
  return CRITICALITY.find((c) => c.value === value);
}

export function criticalityToPriority(value?: string | null): string {
  return criticalityLevel(value)?.defaultPriority ?? 'P3';
}

export const CriticalityLevelField = markDefinition(
  enumField(StringField, {
    displayName: 'Criticality Level',
    options: CRITICALITY.map((c) => ({ value: c.value, label: c.label })),
  }),
);

// ------------------------------------------------------------- small enums
export const WORK_ORDER_KINDS = [
  'preventive',
  'corrective',
  'inspection',
  'project',
] as const;
export const WorkOrderKindField = markDefinition(
  enumField(StringField, {
    displayName: 'Work Order Kind',
    options: WORK_ORDER_KINDS as unknown as string[],
  }),
);
export const WO_KIND_LABEL: Record<string, string> = {
  preventive: 'PM',
  corrective: 'CM',
  inspection: 'INSP',
  project: 'PROJ',
};

export const HOLD_REASONS = [
  'waiting-parts',
  'waiting-access',
  'waiting-approval',
  'other',
] as const;
export const HoldReasonField = markDefinition(
  enumField(StringField, {
    displayName: 'Hold Reason',
    options: HOLD_REASONS as unknown as string[],
  }),
);

export const CUSTODY_KINDS = [
  'check-out',
  'check-in',
  'transfer',
  'loan',
  'return',
] as const;
export const CustodyKindField = markDefinition(
  enumField(StringField, {
    displayName: 'Custody Event Kind',
    options: CUSTODY_KINDS as unknown as string[],
  }),
);

export const WARRANTY_KINDS = [
  'manufacturer',
  'extended',
  'service-contract',
  'none',
] as const;
export const WarrantyKindField = markDefinition(
  enumField(StringField, {
    displayName: 'Warranty Kind',
    options: WARRANTY_KINDS as unknown as string[],
  }),
);

export const METER_KINDS = ['cumulative', 'gauge'] as const;
export const MeterKindField = markDefinition(
  enumField(StringField, {
    displayName: 'Meter Kind',
    options: METER_KINDS as unknown as string[],
  }),
);

export const READING_SOURCES = ['manual', 'import', 'sensor'] as const;
export const ReadingSourceField = markDefinition(
  enumField(StringField, {
    displayName: 'Reading Source',
    options: READING_SOURCES as unknown as string[],
  }),
);

export const CHECKLIST_ITEM_KINDS = [
  'check',
  'measure',
  'photo',
  'text',
  'signature',
] as const;
export const ChecklistItemKindField = markDefinition(
  enumField(StringField, {
    displayName: 'Checklist Item Kind',
    options: CHECKLIST_ITEM_KINDS as unknown as string[],
  }),
);

export const CHECKLIST_RESULTS = ['pending', 'pass', 'fail', 'na'] as const;
export const ChecklistResultField = markDefinition(
  enumField(StringField, {
    displayName: 'Checklist Result',
    options: CHECKLIST_RESULTS as unknown as string[],
  }),
);
export const CHECKLIST_RESULT_HUE: Record<string, Hue> = {
  pending: 'slate',
  pass: 'green',
  fail: 'orange',
  na: 'slate',
};

export const PLAN_KINDS = ['preventive', 'inspection'] as const;
export const PlanKindField = markDefinition(
  enumField(StringField, {
    displayName: 'Maintenance Plan Kind',
    options: PLAN_KINDS as unknown as string[],
  }),
);

export const DISPOSAL_METHODS = [
  'sold',
  'scrapped',
  'donated',
  'returned',
  'lost',
] as const;
export const DisposalMethodField = markDefinition(
  enumField(StringField, {
    displayName: 'Disposal Method',
    options: DISPOSAL_METHODS as unknown as string[],
  }),
);
