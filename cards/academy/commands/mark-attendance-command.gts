import {
  CardDef,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import { Command, identifyCard } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { SearchCardsByQueryCommand } from '@cardstack/boxel-host/commands/search-cards';

import { Lesson } from '../lesson';
import type { Enrollment } from '../enrollment';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { AttendanceRecord } from '../attendance-record';
import { ATTENDANCE_STATUSES } from '../attendance-status-field';

export class AttendanceMarkField extends FieldDef {
  @field enrollmentId = contains(StringField);
  @field status = contains(StringField, {
    description: 'present | late | absent | excused',
  });
  @field note = contains(StringField);
}

export class MarkAttendanceInput extends CardDef {
  @field lesson = linksTo(() => Lesson, { searchable: true });
  @field sessionDate = contains(DateField);
  @field marks = containsMany(AttendanceMarkField);
  @field markedBy = linksTo(() => Employee, { searchable: true });
  /** The caller's already-loaded attendance records (upsert target). */
  @field existingRecords = linksToMany(() => AttendanceRecord);
  @field realm = contains(StringField);
}

export class MarkAttendanceResult extends CardDef {
  @field created = contains(NumberField);
  @field updated = contains(NumberField);
  @field message = contains(StringField);
}

/**
 * Upserts one Attendance Record per (enrolment, lesson, day). Marking the
 * same learner twice for the same session corrects the mark rather than
 * adding a second record — the grid, the completion rule and the report all
 * count records, so a duplicate would inflate attendance. Refuses a lesson
 * that is not live (nothing to attend) and any status outside the enum.
 */
export default class MarkAttendanceCommand extends Command<
  typeof MarkAttendanceInput,
  typeof MarkAttendanceResult
> {
  static actionVerb = 'Mark';
  static displayName = 'Mark Attendance';

  async getInputType() {
    return MarkAttendanceInput;
  }

  protected async run(
    input: MarkAttendanceInput,
  ): Promise<MarkAttendanceResult> {
    let { lesson, sessionDate, marks, markedBy, realm } = input;
    if (!lesson?.id) throw new Error('A lesson is required');
    if (!realm) throw new Error('A realm is required');
    if (!marks?.length) throw new Error('At least one mark is required');
    lesson = (await new GetCardCommand(this.commandContext).execute({
      cardId: lesson.id,
    })) as Lesson;
    if (lesson.kind !== 'live')
      throw new Error(
        `${lesson.cardTitle} is a ${lesson.kindLabel?.toLowerCase() ?? 'non-live'} lesson — only live lessons take attendance`,
      );

    let valid = new Set(ATTENDANCE_STATUSES.map((s) => s.value));
    for (let m of marks as any[]) {
      if (!valid.has(m.status))
        throw new Error(
          `"${m.status}" is not an attendance status (${[...valid].join(', ')})`,
        );
      if (!m.enrollmentId) throw new Error('Every mark needs an enrollmentId');
    }

    let day = sessionDate
      ? new Date(sessionDate)
      : lesson.liveSessionAt
        ? new Date(lesson.liveSessionAt)
        : new Date();
    let dayKey = calendarDay(day);

    let pool: AttendanceRecord[];
    if (input.existingRecords?.length) {
      pool = (input.existingRecords as AttendanceRecord[]).filter(
        (r) => r?.lesson?.id === lesson!.id,
      );
    } else {
      let ref = identifyCard(AttendanceRecord);
      pool = ref
        ? (((
            (await new SearchCardsByQueryCommand(this.commandContext).execute({
              query: { filter: { on: ref, eq: { 'lesson.id': lesson.id } } },
            } as any)) as any
          )?.instances ?? []) as AttendanceRecord[])
        : [];
    }
    let existing = pool.filter(
      (r) => r.sessionDate && calendarDay(new Date(r.sessionDate)) === dayKey,
    );

    let created = 0;
    let updated = 0;
    let now = new Date();
    for (let m of marks as any[]) {
      let hit = existing.find((r) => r.enrollment?.id === m.enrollmentId);
      if (hit?.id) {
        await new PatchCardInstanceCommand(this.commandContext, {
          cardType: AttendanceRecord,
        }).execute({
          cardId: hit.id,
          patch: {
            attributes: {
              attendanceStatus: m.status,
              note: m.note ?? null,
              markedAt: now.toISOString(),
            },
            relationships: {
              markedBy: { links: { self: markedBy?.id ?? null } },
            },
          },
        });
        updated += 1;
      } else {
        let enrollment = (await new GetCardCommand(this.commandContext).execute(
          { cardId: m.enrollmentId },
        )) as Enrollment;
        await new SaveCardCommand(this.commandContext).execute({
          card: new AttendanceRecord({
            enrollment,
            lesson,
            sessionDate: day,
            attendanceStatus: m.status,
            note: m.note ?? undefined,
            markedBy: markedBy ?? undefined,
            markedAt: now,
          }),
          realm,
        } as any);
        created += 1;
      }
    }

    return new MarkAttendanceResult({
      created,
      updated,
      message: `${lesson.cardTitle} (${dayKey}): ${created} marked, ${updated} corrected.`,
    });
  }
}

/** Calendar day as YYYY-MM-DD in local time — a date is a day, not an instant. */
export function calendarDay(d: Date): string {
  let y = d.getFullYear();
  let m = String(d.getMonth() + 1).padStart(2, '0');
  let day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
