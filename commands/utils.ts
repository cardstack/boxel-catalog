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

export function getLoaderService(_commandContext: CommandContext): {
  loader: { import<T>(url: string): Promise<T> };
} {
  // The realm Loader injects itself as `import.meta.loader` into every
  // evaluated module — see packages/base/card-serialization.ts for the
  // canonical use of this pattern in realm-served .ts files.
  return { loader: (import.meta as any).loader };
}

export function loadCommandModule(
  commandContext: CommandContext,
): Promise<typeof BaseCommandModule> {
  const loader = getLoaderService(commandContext).loader;
  return loader.import<typeof BaseCommandModule>(`${baseRealm.url}command`);
}
