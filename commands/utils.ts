import {
  baseRealm,
  devSkillLocalPath,
  envSkillLocalPath,
} from '@cardstack/runtime-common';
import type { CommandContext, Loader } from '@cardstack/runtime-common';
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
  loader: Loader;
} {
  // The realm Loader injects itself as `import.meta.loader` into every
  // evaluated module — see packages/base/card-serialization.ts for the
  // canonical use of this pattern in realm-served .ts files. When
  // type-checking as CommonJS, tsc rejects `import.meta`, but this file
  // is only ever loaded via our realm Loader.
  // @ts-ignore
  return { loader: (import.meta as any).loader as Loader };
}

export function loadCommandModule(
  commandContext: CommandContext,
): Promise<typeof BaseCommandModule> {
  const loader = getLoaderService(commandContext).loader;
  return loader.import<typeof BaseCommandModule>(`${baseRealm.url}command`);
}
