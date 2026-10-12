import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { Course, CourseStatusField } from '../course';
import { canTransition } from '@cardstack/catalog/fields/status/status';
import { getCard, inputCard } from '@cardstack/catalog/utils/find-card';
import { linkedIds } from '@cardstack/catalog/utils/linked-id';
import { describeCompletionRule } from '../completion-rule-field';
import type { Module } from '../course-module';

export class PublishCourseInput extends CardDef {
  @field course = linksTo(() => Course, { searchable: true });
}

export class PublishCourseResult extends CardDef {
  @field course = linksTo(() => Course);
  @field message = contains(StringField);
}

/**
 * draft → published, guarded. A course with no modules, a module with no
 * lessons, or no completion rule is not a course anyone can be enrolled in,
 * so the command refuses with the exact gap rather than publishing a shell.
 * Publishing a course that is already published changes nothing.
 */
export default class PublishCourseCommand extends Command<
  typeof PublishCourseInput,
  typeof PublishCourseResult
> {
  static actionVerb = 'Publish';
  static displayName = 'Publish Course';

  async getInputType() {
    return PublishCourseInput;
  }

  protected async run(input: PublishCourseInput): Promise<PublishCourseResult> {
    let course = await inputCard<Course>(this.commandContext, input, 'course');
    if (!course?.id) throw new Error('A course is required');
    course = await getCard<Course>(this.commandContext, course.id);

    let moduleIds = linkedIds(course, 'modules');
    let from = course.status ?? 'draft';
    if (from === 'published') {
      return new PublishCourseResult({
        course,
        message: `${course.cardTitle} is already published.`,
      });
    }
    if (!canTransition(CourseStatusField, from, 'published')) {
      throw new Error(`Cannot publish a course whose status is "${from}"`);
    }
    if (!moduleIds.length) {
      throw new Error('Cannot publish: the course has no modules');
    }
    let modules = await Promise.all(
      moduleIds.map((id) => getCard<Module>(this.commandContext, id)),
    );
    let empty = modules.filter((m) => !linkedIds(m, 'lessons').length);
    if (empty.length) {
      throw new Error(
        `Cannot publish: ${empty.map((m) => m.cardTitle).join(', ')} ${empty.length === 1 ? 'has' : 'have'} no lessons`,
      );
    }
    if (!describeCompletionRule(course.completionRule).length) {
      throw new Error(
        'Cannot publish: set at least one completion requirement first',
      );
    }

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: Course,
    }).execute({
      cardId: course.id,
      patch: { attributes: { status: 'published' } },
    });

    return new PublishCourseResult({
      course,
      message: `${course.cardTitle} published — ${modules.length} modules ready for cohorts.`,
    });
  }
}
