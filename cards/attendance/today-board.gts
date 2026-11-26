import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { registerDestructor } from '@ember/destroyable';
import type Owner from '@ember/owner';
import type { CardContext } from 'https://cardstack.com/base/card-api';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Stat } from '@cardstack/pretui/components/stat';

import type { AttendanceRecord } from './attendance-record';
import type { LeaveRequest } from './leave-request';
import { foldBoard, type Board, type BoardEntry } from './board-fold';

interface TodayBoardSignature {
  Args: {
    // Saved-search rows for the people I manage and for their approved leave
    teamEntries: { id: string }[] | undefined;
    leaveEntries: { id: string }[] | undefined;
    isLoading: boolean;
    context: CardContext | undefined;
    timezone: string;
  };
}

interface Group {
  key: string;
  title: string;
  entries: BoardEntry[];
}

const REFRESH_MS = 30_000;

// Who in my team is in, has left, is expected and not in yet, or is on leave
// today. Each row comes from the live cards, so a punch or an approval shows
// as soon as the searches pick it up.
export class TodayBoard extends GlimmerComponent<TodayBoardSignature> {
  @tracked now = new Date();
  private timer: ReturnType<typeof setInterval>;

  constructor(owner: Owner, args: TodayBoardSignature['Args']) {
    super(owner, args);
    this.timer = setInterval(() => (this.now = new Date()), REFRESH_MS);
    registerDestructor(this, () => clearInterval(this.timer));
  }

  team = this.args.context?.getCardCollection(this, () =>
    this.args.teamEntries?.map((e) => e.id),
  );
  leave = this.args.context?.getCardCollection(this, () =>
    this.args.leaveEntries?.map((e) => e.id),
  );

  get board(): Board {
    let records = (this.team?.cards ?? []) as AttendanceRecord[];
    let leave = (this.leave?.cards ?? []) as LeaveRequest[];
    return foldBoard(
      records.map((r) => ({
        id: r.id,
        name: r.employeeName ?? '',
        userId: r.userId ?? '',
        year: r.year,
        punches: r.punches,
        schedule: r.schedule,
      })),
      leave,
      this.args.timezone,
      this.now,
    );
  }

  get groups(): Group[] {
    let b = this.board;
    return [
      { key: 'in', title: 'In', entries: b.in },
      { key: 'out', title: 'Left', entries: b.out },
      { key: 'expected', title: 'Expected, not in yet', entries: b.expected },
      { key: 'leave', title: 'On leave', entries: b.onLeave },
      { key: 'later', title: 'Not due yet', entries: b.notDue },
    ];
  }

  get isEmpty(): boolean {
    return !this.args.isLoading && !this.args.teamEntries?.length;
  }

  <template>
    {{#if this.isEmpty}}
      <EmptyState
        @title='Nobody reports to you here'
        @message='The board lists the people whose attendance record names you as their manager.'
      />
    {{else}}
      <div class='board'>
        <div class='stats'>
          <Stat @label='In' @value={{this.board.in.length}} @roll={{false}} />
          <Stat
            @label='Left'
            @value={{this.board.out.length}}
            @roll={{false}}
          />
          <Stat
            @label='Expected'
            @value={{this.board.expected.length}}
            @roll={{false}}
          />
          <Stat
            @label='On leave'
            @value={{this.board.onLeave.length}}
            @roll={{false}}
          />
        </div>
        {{#each this.groups key='key' as |group|}}
          {{#if group.entries.length}}
            <section class='group {{group.key}}'>
              <h3>{{group.title}}</h3>
              <ul>
                {{#each group.entries key='id' as |entry|}}
                  <li>
                    <Avatar @name={{entry.name}} @size={{28}} />
                    <span class='name'>{{entry.name}}</span>
                    <span class='detail'>{{entry.detail}}</span>
                  </li>
                {{/each}}
              </ul>
            </section>
          {{/if}}
        {{/each}}
      </div>
    {{/if}}
    <style scoped>
      .board {
        display: grid;
        gap: var(--boxel-sp);
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      h3 {
        margin: 0 0 var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      ul {
        display: grid;
        gap: var(--boxel-sp-5xs);
        margin: 0;
        padding: 0;
        list-style: none;
      }
      li {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-5xs) 0;
        border-bottom: 1px solid var(--border);
      }
      .name {
        font-weight: 600;
      }
      .detail {
        margin-inline-start: auto;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .expected .detail {
        color: var(--destructive-ink);
      }
      .in .detail {
        color: var(--success-ink);
      }
    </style>
  </template>
}
