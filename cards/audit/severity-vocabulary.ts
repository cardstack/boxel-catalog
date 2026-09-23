import type { Hue } from '@cardstack/catalog/components/state-pill';

// The vocabulary lives apart from both the field and the badge so each can
// import it without importing the other.
export const SEVERITY_LEVELS = ['minor', 'major', 'critical'] as const;
export type SeverityLevel = (typeof SEVERITY_LEVELS)[number];

export const SEVERITY_RANK: Record<string, number> = {
  minor: 1,
  major: 2,
  critical: 3,
};

export const SEVERITY_LABELS: Record<string, string> = {
  minor: 'Minor',
  major: 'Major',
  critical: 'Critical',
};

export const SEVERITY_HUE: Record<string, Hue> = {
  minor: 'amber',
  major: 'orange',
  critical: 'red',
};

// Major and above put the certificate itself at risk; minor is an
// observation the auditor expects fixed but will not fail the audit over.
export function certificateAtRisk(level?: string | null): boolean {
  return (SEVERITY_RANK[level ?? ''] ?? 0) >= 2;
}
