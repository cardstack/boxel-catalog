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
  params,
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

interface LeaveFacts {
  ptoType?: string | null;
  startDate?: Date | string | null;
  endDate?: Date | string | null;
  state?: string | null;
}

function typeLabel(m: LeaveFacts): string {
  return LEAVE_TYPES.find((t) => t.value === m.ptoType)?.label ?? 'Leave';
}

function rangeLabel(m: LeaveFacts): string {
  let start = dayKeyOf(m.startDate);
  let end = dayKeyOf(m.endDate);
  return start === end || !end ? start : `${start} to ${end}`;
}

function daysText(m: LeaveFacts): string {
  let days = leaveDays(m);
  return days === 1 ? '1 day' : `${days} days`;
}

class Summary extends Component<typeof LeaveRequest> {
  get typeLabel(): string {
    return typeLabel(this.args.model);
  }

  get range(): string {
    return rangeLabel(this.args.model);
  }

  get daysLabel(): string {
    return daysText(this.args.model);
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

  // The catalog names these from the linked employee, which a request filed
  // through `requestLeave` doesn't carry; name them from the card itself.
  @field employeeName = contains(StringField, {
    computeVia: function (this: LeaveRequest) {
      return this.employee?.name || this.userId || '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: LeaveRequest) {
      return `${typeLabel(this)} leave · ${daysText(this)} · ${this.employeeName}`;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: LeaveRequest) {
      return this.cardInfo?.name?.trim() || this.title;
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

  // Approved leave of the people I manage that has not ended (`since` is the
  // earliest end day); the Today board picks out who is away on the day it shows. `managerUserId` is stamped when
  // the request is filed, so when someone's manager changes an admin re-stamps
  // their open leave.
  @operation static teamLeave = {
    base: 'query',
    links: 'ids',
    html: DATA_ONLY,
    params: { since: StringField },
    query: {
      filter: {
        on: () => LeaveRequest,
        every: [
          {
            on: () => LeaveRequest,
            eq: { managerUserId: actor(), state: 'approved' },
          },
          {
            on: () => LeaveRequest,
            range: { endDate: { gte: params('since') } },
          },
        ],
      },
      sort: [{ on: () => LeaveRequest, by: 'startDate', direction: 'desc' }],
    },
  } satisfies OperationDeclaration;

  static atom = class Atom extends Component<typeof LeaveRequest> {
    <template>
      <span class='atom'>{{@model.title}}</span>
      <style scoped>
        .atom {
          font-weight: 600;
        }
      </style>
    </template>
  };
  static isolated = Summary;
  static embedded = Summary;
  static fitted = Summary;
}
