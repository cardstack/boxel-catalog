import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { inputCard } from '@cardstack/catalog/utils/find-card';
import { linkedId, linkedIds } from '@cardstack/catalog/utils/linked-id';

import { Cohort, ModuleReleaseField } from '../cohort';
import { Course } from '../course';
import { Module } from '../course-module';
import { linkedCard, typedCard } from './links';
import { Employee } from '../../hr/employee';

export class ReleaseModuleInput extends CardDef {
  @field cohort = linksTo(() => Cohort, { searchable: true });
  @field module = linksTo(() => Module, { searchable: true });
  @field releasedBy = linksTo(() => Employee, { searchable: true });
}

export class ReleaseModuleResult extends CardDef {
  @field cohort = linksTo(() => Cohort);
  @field message = contains(StringField);
}

/**
 * Appends a release EVENT to the cohort. Refuses when the cohort is not
 * running, when the module belongs to a different course, or when it was
 * already released — a second release would double the timeline mark and
 * lie about when learners first saw it. The release is built as a
 * ModuleReleaseField and the whole cohort is saved, because a link inside a
 * containsMany entry cannot be addressed by a JSON patch.
 */
export default class ReleaseModuleCommand extends Command<
  typeof ReleaseModuleInput,
  typeof ReleaseModuleResult
> {
  static actionVerb = 'Release';
  static displayName = 'Release Module';

  async getInputType() {
    return ReleaseModuleInput;
  }

  protected async run(input: ReleaseModuleInput): Promise<ReleaseModuleResult> {
    let cohortId = linkedId(input, 'cohort');
    let moduleId = linkedId(input, 'module');
    if (!cohortId) throw new Error('A cohort is required');
    if (!moduleId) throw new Error('A module is required');
    let cohort = await typedCard(this.commandContext, cohortId, Cohort);
    let module = await typedCard(this.commandContext, moduleId, Module);
    let releasedBy = await inputCard<Employee>(
      this.commandContext,
      input,
      'releasedBy',
    );

    if (cohort.status !== 'running') {
      throw new Error(
        `Cannot release into ${cohort.cardTitle}: cohort is ${cohort.status ?? 'planned'}, not running`,
      );
    }
    let course = await linkedCard<Course>(
      this.commandContext,
      cohort,
      'course',
    );
    let courseModuleIds = course ? linkedIds(course, 'modules') : [];
    if (courseModuleIds.length && !courseModuleIds.includes(moduleId)) {
      throw new Error(
        `${module.cardTitle} is not part of ${course?.cardTitle ?? 'this course'}`,
      );
    }
    let releases = (cohort.releases ?? []) as ModuleReleaseField[];
    if (releases.some((r) => linkedId(cohort, 'module', r) === moduleId)) {
      throw new Error(
        `${module.cardTitle} was already released to ${cohort.cardTitle}`,
      );
    }

    // Append the event to the loaded card and save it: a link inside a
    // containsMany can't be addressed by a JSON patch.
    let n = releases.length;
    cohort.releases = [
      ...releases,
      new ModuleReleaseField({
        module,
        releasedAt: new Date(),
        releasedBy,
      }),
    ];
    await new SaveCardCommand(this.commandContext).execute({
      card: cohort,
    } as any);

    return new ReleaseModuleResult({
      cohort,
      message: `${module.cardTitle} released to ${cohort.cardTitle} (${n + 1} of ${courseModuleIds.length || '?'} modules).`,
    });
  }
}
