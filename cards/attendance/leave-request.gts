import {
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import DateTimeField from 'https://cardstack.com/base/datetime';
import {
  actor,
  bxl,
  operation,
  type OperationDeclaration,
} from 'https://cardstack.com/base/operations';
import { StatusChip } from '@cardstack/pretui/components/status-chip';

import { PtoRequest } from '../hr/pto-request';
import {
  LEAVE_STATE_LABEL,
  LEAVE_TYPES,
  dayKeyOf,
  leaveDays,
} from './leave-days';

const STATE_TO_STATUS: Record<string, string> = {
  pending: 'in-progress',
  approved: 'approved',
  declined: 'rejected',
};

// Rows come back as data only; the app loads each card live.
const DATA_ONLY = {
  isolated: 'unshareable',
  embedded: 'unshareable',
  fitted: 'unshareable',
  atom: 'unshareable',
  head: 'unshareable',
} as const;

class Summary extends Component<typeof LeaveRequest> {
  get typeLabel(): string {
    return (
      LEAVE_TYPES.find((t) => t.value === this.args.model.ptoType)?.label ??
      this.args.model.ptoType ??
      'Leave'
    );
  }

  get range(): string {
    let start = dayKeyOf(this.args.model.startDate);
    let end = dayKeyOf(this.args.model.endDate);
    return start === end || !end ? start : `${start} to ${end}`;
  }

  get daysLabel(): string {
    let days = leaveDays(this.args.model);
    return days === 1 ? '1 day' : `${days} days`;
  }

  get stateLabel(): string {
    return LEAVE_STATE_LABEL[this.args.model.state ?? ''] ?? 'Draft';
  }

  get note(): string {
    let m = this.args.model;
    if (m.declared) {
      return 'Declared by the employee';
    }
    return m.decidedBy ? `Decided by ${m.decidedBy}` : 'Waiting on the manager';
  }

  <template>
    <article class='leave'>
      <div class='top'>
        <strong>{{this.typeLabel}}</strong>
        <StatusChip @value={{this.stateLabel}} />
      </div>
      <p>{{this.range}} · {{this.daysLabel}}</p>
      <p class='muted'>{{@model.userId}} · {{this.note}}</p>
      {{#if @model.reason}}<p class='muted'>{{@model.reason}}</p>{{/if}}
    </article>
    <style scoped>
      .leave {
        display: grid;
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp);
      }
      .top {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      p {
        margin: 0;
      }
      .muted {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}

// A request for time off, built on the catalog PtoRequest. Vacation waits for
// the manager; sick and personal days are declared and approved when filed.
// `userId` and `managerUserId` are stored because a realm policy grant reads
// only the card's own fields.
export class LeaveRequest extends PtoRequest {
  static displayName = 'Leave Request';

  @field userId = contains(StringField);
  @field managerUserId = contains(StringField);
  // 'pending', 'approved' or 'declined'
  @field state = contains(StringField);
  @field declared = contains(BooleanField);
  @field decidedBy = contains(StringField);
  @field decidedAt = contains(DateTimeField);

  // The catalog status reads an approval chain this card doesn't use, so it
  // follows `state` through the same values.
  @field status = contains(StringField, {
    computeVia: function (this: LeaveRequest) {
      return STATE_TO_STATUS[this.state ?? ''] ?? 'draft';
    },
  });

  @operation static read = {
    base: 'read',
    links: 'ids',
  } satisfies OperationDeclaration;

  // The manager approves or declines a pending request; never their own.
  @operation static decideLeave = {
    base: 'transform',
    params: { decision: StringField, decidedAt: StringField },
    input: bxl`NOW() as $n | . + { decidedAt: (TEXT($n; "yyyy-mm-dd") + "T" + TEXT($n; "hh:mm:ss") + "Z") }`,
    transformations: bxl`
      assert(OR(params("decision") == "approved"; params("decision") == "declined"); "A request is either approved or declined");
      assert(.state == "pending"; "That request is not waiting for a decision");
      assert(.userId != actor(); "You can't decide your own request");
      .state = params("decision");
      .decidedBy = actor();
      .decidedAt = params("decidedAt");
    `,
  } satisfies OperationDeclaration;

  @operation static myLeave = {
    base: 'query',
    links: 'ids',
    html: DATA_ONLY,
    query: {
      filter: { on: () => LeaveRequest, eq: { userId: actor() } },
      sort: [{ on: () => LeaveRequest, by: 'startDate', direction: 'desc' }],
    },
  } satisfies OperationDeclaration;

  @operation static leaveToApprove = {
    base: 'query',
    links: 'ids',
    html: DATA_ONLY,
    query: {
      filter: {
        on: () => LeaveRequest,
        eq: { managerUserId: actor(), state: 'pending' },
      },
      sort: [{ on: () => LeaveRequest, by: 'startDate', direction: 'asc' }],
    },
  } satisfies OperationDeclaration;

  // Approved leave of the people I manage; the Today board picks out who is
  // away on the day it shows.
  @operation static teamLeave = {
    base: 'query',
    links: 'ids',
    html: DATA_ONLY,
    query: {
      filter: {
        on: () => LeaveRequest,
        eq: { managerUserId: actor(), state: 'approved' },
      },
      sort: [{ on: () => LeaveRequest, by: 'startDate', direction: 'desc' }],
    },
  } satisfies OperationDeclaration;

  static isolated = Summary;
  static embedded = Summary;
  static fitted = Summary;
}
