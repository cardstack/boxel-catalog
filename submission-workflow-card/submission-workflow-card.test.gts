import { module, test } from 'qunit';

import {
  resolveSubmissionWorkflowState,
  type WorkflowState,
} from './submission-workflow-card';

interface ResolveArgs {
  hasListing: boolean;
  hasPr: boolean;
  prActionLabel: string | null;
  ciAllPassed: boolean;
  ciHasFailure: boolean;
  ciInProgress: boolean;
  ciIsLoading: boolean;
  reviewState: string | null;
  isMerged: boolean;
  isClosed: boolean;
  lintStatus: string | null;
  lintErrors: string[];
  prCreationError: string | null;
  failedStep: string | null;
}

function resolve(overrides: Partial<ResolveArgs> = {}): WorkflowState {
  let args: ResolveArgs = {
    hasListing: false,
    hasPr: false,
    prActionLabel: null,
    ciAllPassed: false,
    ciHasFailure: false,
    ciInProgress: false,
    ciIsLoading: false,
    reviewState: null,
    isMerged: false,
    isClosed: false,
    lintStatus: null,
    lintErrors: [],
    prCreationError: null,
    failedStep: null,
    ...overrides,
  };
  return resolveSubmissionWorkflowState(
    args.hasListing,
    args.hasPr,
    args.prActionLabel,
    args.ciAllPassed,
    args.ciHasFailure,
    args.ciInProgress,
    args.ciIsLoading,
    args.reviewState,
    args.isMerged,
    args.isClosed,
    args.lintStatus,
    args.lintErrors,
    args.prCreationError,
    args.failedStep,
  );
}

function step(state: WorkflowState, key: string) {
  let found = state.steps.find((s) => s.key === key);
  if (!found) {
    throw new Error(`no step with key "${key}"`);
  }
  return found;
}

export function runTests() {
  module('Unit | submission workflow state resolver', function () {
    module('baseline flow', function () {
      test('empty state starts at choose-listing', function (assert) {
        let state = resolve();
        assert.strictEqual(step(state, 'choose-listing').status, 'current');
        assert.strictEqual(step(state, 'create-pr').status, 'upcoming');
        assert.strictEqual(state.overallStatus, 'not-started');
        assert.strictEqual(state.progressPercent, 0);
      });

      test('listing chosen makes create-pr the current step', function (assert) {
        let state = resolve({ hasListing: true });
        assert.strictEqual(step(state, 'choose-listing').status, 'completed');
        assert.strictEqual(step(state, 'create-pr').status, 'current');
        assert.strictEqual(state.currentStepIndex, 1);
      });

      test('lint in progress before any PrCard exists', function (assert) {
        let state = resolve({ hasListing: true, lintStatus: 'in-progress' });
        let createPr = step(state, 'create-pr');
        assert.strictEqual(createPr.status, 'in-progress');
        assert.strictEqual(createPr.statusDetail, 'Linting files...');
      });

      test('lint failure blocks with an error count', function (assert) {
        let state = resolve({
          hasListing: true,
          lintStatus: 'failed',
          lintErrors: ['error one', 'error two'],
        });
        let createPr = step(state, 'create-pr');
        assert.strictEqual(createPr.status, 'blocked');
        assert.strictEqual(createPr.statusDetail, '2 unfixable lint errors');
        assert.strictEqual(state.overallStatus, 'blocked');
      });

      test('single lint error is not pluralized', function (assert) {
        let state = resolve({
          hasListing: true,
          lintStatus: 'failed',
          lintErrors: ['error one'],
        });
        assert.strictEqual(
          step(state, 'create-pr').statusDetail,
          '1 unfixable lint error',
        );
      });

      test('lint passed without a PrCard means creation is underway', function (assert) {
        let state = resolve({ hasListing: true, lintStatus: 'passed' });
        let createPr = step(state, 'create-pr');
        assert.strictEqual(createPr.status, 'in-progress');
        assert.strictEqual(createPr.statusDetail, 'Creating PR...');
      });

      test('collect-files failure names the failed step', function (assert) {
        let state = resolve({ hasListing: true, failedStep: 'collect-files' });
        let createPr = step(state, 'create-pr');
        assert.strictEqual(createPr.status, 'blocked');
        assert.strictEqual(createPr.statusDetail, 'Collecting files failed');
      });

      test('create-pr-card failure names the failed step', function (assert) {
        let state = resolve({
          hasListing: true,
          failedStep: 'create-pr-card',
          prCreationError: 'PR creation failed: boom',
        });
        assert.strictEqual(
          step(state, 'create-pr').statusDetail,
          'Creating PR card failed',
        );
      });

      test('linked PrCard with a clean run completes create-pr', function (assert) {
        let state = resolve({
          hasListing: true,
          hasPr: true,
          lintStatus: 'passed',
        });
        assert.strictEqual(step(state, 'create-pr').status, 'completed');
        assert.strictEqual(step(state, 'ci-checks').status, 'current');
      });

      test('ci flags drive the ci-checks step once a PrCard exists', function (assert) {
        let base = { hasListing: true, hasPr: true, lintStatus: 'passed' };
        assert.strictEqual(
          step(resolve({ ...base, ciIsLoading: true }), 'ci-checks').status,
          'in-progress',
          'loading state while checks are fetched',
        );
        assert.strictEqual(
          step(resolve({ ...base, ciInProgress: true }), 'ci-checks').status,
          'in-progress',
          'running checks',
        );
        assert.strictEqual(
          step(resolve({ ...base, ciAllPassed: true }), 'ci-checks').status,
          'completed',
          'all checks green',
        );
        assert.strictEqual(
          step(resolve({ ...base, ciHasFailure: true }), 'ci-checks').status,
          'blocked',
          'a failing check blocks',
        );
      });
    });

    module('retry with a linked PrCard (CS-12421)', function () {
      test('re-running lint shows in-progress instead of completed', function (assert) {
        let state = resolve({
          hasListing: true,
          hasPr: true,
          lintStatus: 'in-progress',
        });
        let createPr = step(state, 'create-pr');
        assert.strictEqual(createPr.status, 'in-progress');
        assert.strictEqual(createPr.statusDetail, 'Re-running lint…');
      });

      test('lint failure on retry blocks even though the PrCard is linked', function (assert) {
        let state = resolve({
          hasListing: true,
          hasPr: true,
          lintStatus: 'failed',
          lintErrors: ['error one', 'error two', 'error three'],
        });
        let createPr = step(state, 'create-pr');
        assert.strictEqual(createPr.status, 'blocked');
        assert.strictEqual(createPr.statusDetail, '3 unfixable lint errors');
        assert.strictEqual(state.overallStatus, 'blocked');
      });

      test('github-pr failure blocks the step so the icon agrees with the error box', function (assert) {
        let state = resolve({
          hasListing: true,
          hasPr: true,
          lintStatus: 'passed',
          prCreationError: 'PR creation failed: 401 from GitHub',
          failedStep: 'github-pr',
        });
        let createPr = step(state, 'create-pr');
        assert.strictEqual(createPr.status, 'blocked');
        assert.strictEqual(createPr.statusDetail, 'PR creation failed');
      });

      test('progress and current step regress while the retry runs', function (assert) {
        let clean = resolve({
          hasListing: true,
          hasPr: true,
          lintStatus: 'passed',
        });
        let retrying = resolve({
          hasListing: true,
          hasPr: true,
          lintStatus: 'in-progress',
        });
        assert.true(
          retrying.progressPercent < clean.progressPercent,
          `progress dips during the re-run (${retrying.progressPercent} < ${clean.progressPercent})`,
        );
        assert.strictEqual(
          retrying.currentStepIndex,
          1,
          'create-pr is the active step again',
        );
      });
    });

    module('tail states', function () {
      test('merged submission completes every step', function (assert) {
        let state = resolve({
          hasListing: true,
          hasPr: true,
          lintStatus: 'passed',
          ciAllPassed: true,
          reviewState: 'approved',
          isMerged: true,
        });
        assert.deepEqual(
          state.steps.map((s) => s.status),
          ['completed', 'completed', 'completed', 'completed', 'completed'],
        );
        assert.strictEqual(state.overallStatus, 'completed');
        assert.strictEqual(state.progressPercent, 100);
      });

      test('closed-without-merge blocks the merge step', function (assert) {
        let state = resolve({
          hasListing: true,
          hasPr: true,
          lintStatus: 'passed',
          ciAllPassed: true,
          isClosed: true,
        });
        assert.strictEqual(step(state, 'merge-catalog').status, 'blocked');
      });
    });
  });
}
