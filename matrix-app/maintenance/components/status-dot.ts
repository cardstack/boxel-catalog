import { htmlSafe } from '@ember/template';

export const WO_STATUS_LABEL: Record<string, string> = {
  requested: 'Requested',
  approved: 'Approved',
  scheduled: 'Scheduled',
  'in-progress': 'In progress',
  'on-hold': 'On hold',
  completed: 'Completed',
  closed: 'Closed',
  cancelled: 'Cancelled',
};

// Status dots use theme tokens only: waiting work reads hot, moving work green.
const WO_STATUS_DOT: Record<string, string> = {
  requested: 'var(--destructive)',
  'on-hold': 'var(--destructive)',
  'in-progress': 'var(--success)',
  approved: 'var(--info)',
  completed: 'var(--success)',
};

const ASSET_STATUS_DOT: Record<string, string> = {
  'in-service': 'var(--success)',
  'under-maintenance': 'var(--warning)',
  'out-of-service': 'var(--destructive)',
};

export const ASSET_STATUS_LABEL: Record<string, string> = {
  'in-service': 'In service',
  'out-of-service': 'Out of service',
  'under-maintenance': 'Under maintenance',
  'in-storage': 'In storage',
  'on-loan': 'On loan',
  disposed: 'Disposed',
};

export function dot(value: string | undefined) {
  return htmlSafe(`--dot: ${value || 'var(--muted-foreground)'}`);
}
export const woDot = (status?: string | null) =>
  dot(WO_STATUS_DOT[status ?? '']);
export const assetDot = (status?: string | null) =>
  dot(ASSET_STATUS_DOT[status ?? '']);
export const woLabel = (status?: string | null) =>
  WO_STATUS_LABEL[status ?? ''] ?? status ?? '—';
export const assetLabel = (status?: string | null) =>
  ASSET_STATUS_LABEL[status ?? ''] ?? status ?? '—';
