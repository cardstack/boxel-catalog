import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Cohort, ModuleReleaseField } from '../cohort';
import { Module } from '../course-module';
import { Employee } from '@cardstack/catalog/cards/hr/employee';

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
 * lie about when learners first saw it. Releases are patched as JSON
 * (compound values go through PatchCardInstance, never field instances).
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
    let { cohort, module, releasedBy } = input;
    if (!cohort?.id) throw new Error('A cohort is required');
    if (!module?.id) throw new Error('A module is required');
    cohort = (await new GetCardCommand(this.commandContext).execute({
      cardId: cohort.id,
    })) as Cohort;

    if (cohort.status !== 'running') {
      throw new Error(
        `Cannot release into ${cohort.cardTitle}: cohort is ${cohort.status ?? 'planned'}, not running`,
      );
    }
    let courseModuleIds = ((cohort.course?.modules ?? []) as any[])
      .map((m) => m?.id)
      .filter(Boolean);
    if (courseModuleIds.length && !courseModuleIds.includes(module.id)) {
      throw new Error(
        `${module.cardTitle} is not part of ${cohort.course?.cardTitle ?? 'this course'}`,
      );
    }
    let releases = (cohort.releases ?? []) as any[];
    if (releases.some((r) => r?.module?.id === module!.id)) {
      throw new Error(
        `${module.cardTitle} was already released to ${cohort.cardTitle}`,
      );
    }

    // Append the event on the loaded card and save it (the approve-chain
    // pattern): a containsMany of links cannot be addressed as a JSON patch.
    let n = releases.length;
    cohort.releases = [
      ...releases,
      new ModuleReleaseField({
        module,
        releasedAt: new Date(),
        releasedBy: releasedBy ?? undefined,
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
