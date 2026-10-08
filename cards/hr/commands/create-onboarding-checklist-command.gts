import {
  CardDef,
  field,
  contains,
  linksTo,
  StringField,
  realmURL,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { Contractor } from '../contractor';
import { OnboardingTemplate } from '../onboarding-template';
import { durationInDays } from '../duration-field';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import {
  OnboardingChecklist,
  OnboardingChecklistTaskField,
} from '../onboarding-checklist';

class CreateOnboardingChecklistInput extends CardDef {
  @field employee = linksTo(() => Employee);
  @field contractor = linksTo(() => Contractor);
  @field template = linksTo(() => OnboardingTemplate, { searchable: true });
}

class CreateOnboardingChecklistResult extends CardDef {
  @field message = contains(StringField);
  @field checklist = linksTo(() => OnboardingChecklist);
}

export class CreateOnboardingChecklistCommand extends Command<
  typeof CreateOnboardingChecklistInput,
  typeof CreateOnboardingChecklistResult
> {
  static actionVerb = 'Create';
  static displayName = 'Create Onboarding Checklist';

  async getInputType() {
    return CreateOnboardingChecklistInput;
  }

  protected async run(
    input: CreateOnboardingChecklistInput,
  ): Promise<CreateOnboardingChecklistResult> {
    let { employee, contractor, template } = input;

    if (!employee === !contractor) {
      throw new Error(
        'Exactly one of employee or contractor is required — a checklist belongs to one person',
      );
    }
    if (!template) {
      throw new Error('template is required');
    }
    let templateTasks = (template.tasks ?? []).filter(Boolean);
    if (!templateTasks.length) {
      throw new Error(
        `${template.cardTitle ?? 'That template'} has no tasks to copy`,
      );
    }

    let createdDate = new Date();
    // Offsets count from the person's start date, or from today when none is
    // recorded. A sub-day offset rounds up to the next whole day.
    let start =
      toDate(employee ? employee.startDate : contractor?.contractStartDate) ??
      new Date(
        createdDate.getFullYear(),
        createdDate.getMonth(),
        createdDate.getDate(),
      );

    let tasks: OnboardingChecklistTaskField[] = templateTasks.map(
      (templateTask) => {
        let dueDate: Date | undefined;
        let offset = durationInDays(
          templateTask.dueDate?.value,
          templateTask.dueDate?.unit,
        );
        if (offset > 0) {
          dueDate = new Date(start);
          dueDate.setDate(dueDate.getDate() + Math.ceil(offset));
        }

        return new OnboardingChecklistTaskField({
          title: templateTask.title,
          dueDate,
          status: 'pending',
          notes: templateTask.notes,
        });
      },
    );

    let checklist = new OnboardingChecklist({
      employee: employee || undefined,
      contractor: contractor || undefined,
      template,
      tasks,
      createdDate,
    });

    // Save to realm — use the realm of the person (employee or contractor)
    let person = employee || contractor;
    let realm = person?.[realmURL]?.href;
    let saved = (await new SaveCardCommand(this.commandContext).execute({
      card: checklist,
      realm,
    } as any)) as OnboardingChecklist;

    return new CreateOnboardingChecklistResult({
      message: `Onboarding checklist created for ${
        employee?.name || contractor?.name
      } with ${tasks.length} tasks.`,
      checklist: saved,
    });
  }
}
