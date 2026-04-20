import { getOwner } from '@ember/-internals/owner';
import {
  baseRealm,
  devSkillLocalPath,
  envSkillLocalPath,
} from '@cardstack/runtime-common';
import type { CommandContext } from '@cardstack/runtime-common';
import type * as BaseCommandModule from 'https://cardstack.com/base/command';

/**
 * Constructs a universal @cardstack/skills/ reference to a skill card.
 */
export function skillCardURL(skillId: string): string {
  return `@cardstack/skills/Skill/${skillId}`;
}

export const devSkillId = `@cardstack/skills/${devSkillLocalPath}`;
export const envSkillId = `@cardstack/skills/${envSkillLocalPath}`;

export function getLoaderService(commandContext: CommandContext): {
  loader: { import<T>(url: string): Promise<T> };
} {
  return (getOwner(commandContext) as any).lookup(
    'service:loader-service',
  ) as { loader: { import<T>(url: string): Promise<T> } };
}

export function loadCommandModule(
  commandContext: CommandContext,
): Promise<typeof BaseCommandModule> {
  return getLoaderService(commandContext).loader.import<
    typeof BaseCommandModule
  >(`${baseRealm.url}command`);
}
