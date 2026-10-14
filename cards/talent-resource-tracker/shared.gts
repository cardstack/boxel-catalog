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
