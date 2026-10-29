import { markDefinition } from '@cardstack/base/mark-definition';
import {
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import SchoolIcon from '@cardstack/boxel-icons/school';

import { Employee } from '../hr/employee';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export const INSTRUCTOR_ROLES = [
  { value: 'lead', label: 'Lead instructor' },
  { value: 'assistant', label: 'Teaching assistant' },
  { value: 'grader', label: 'Grader' },
  { value: 'guest', label: 'Guest speaker' },
];

export const INSTRUCTOR_ROLE_HUES: Record<string, Hue> = {
  lead: 'purple',
  assistant: 'teal',
  grader: 'blue',
  guest: 'slate',
};

export const InstructorRoleField = markDefinition(
  enumField(StringField, {
    displayName: 'Instructor Role',
    options: INSTRUCTOR_ROLES,
  }),
);

/**
 * One person's teaching role on one cohort. Lives on the Cohort as
 * `instructors[]` because the same Employee leads one cohort and grades
 * another — the role is a fact about the pairing, not about the person.
 * `moduleCodes` narrows a grader or guest to the modules they cover.
 */
export class InstructorAssignmentField extends FieldDef {
  static displayName = 'Instructor Assignment';
  static icon = SchoolIcon;

  @field instructor = linksTo(() => Employee);
  @field role = contains(InstructorRoleField);
  @field moduleCodes = containsMany(StringField, {
    description: 'Module codes this person covers; empty = the whole cohort.',
  });

  @field instructorName = contains(StringField, {
    computeVia: function (this: InstructorAssignmentField) {
      return this.instructor?.name ?? '';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return INSTRUCTOR_ROLE_HUES[this.args.model?.role ?? ''] ?? 'slate';
    }
    get roleLabel() {
      return roleLabel(this.args.model?.role);
    }
    <template>
      <span class='ia'>
        <span class='ia-name'>{{if
            @model.instructorName
            @model.instructorName
            'Unassigned'
          }}</span>
        <StatePill @label={{this.roleLabel}} @hue={{this.hue}} />
        {{#if @model.moduleCodes.length}}
          <span class='ia-mods'>{{join @model.moduleCodes}}</span>
        {{/if}}
      </span>
      <style scoped>
        .ia {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .ia-name {
          font-weight: 600;
          color: var(--foreground);
        }
        .ia-mods {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='ia-atom'>{{@model.instructorName}}
        <span class='ia-role'>· {{roleLabel @model.role}}</span></span>
      <style scoped>
        .ia-atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
        .ia-role {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export function roleLabel(role?: string | null): string {
  return INSTRUCTOR_ROLES.find((r) => r.value === role)?.label ?? 'Instructor';
}

function join(list?: string[] | null): string {
  return (list ?? []).filter(Boolean).join(', ');
}

export default InstructorAssignmentField;
