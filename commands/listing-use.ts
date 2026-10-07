import {
  Command,
  codeRefWithAbsoluteIdentifier,
  isResolvedCodeRef,
  generateInstallFolderName,
  join,
  rri,
} from '@cardstack/runtime-common';

import type * as BaseCommandModule from 'https://cardstack.com/base/command';

import { loadListingInput, loadListingLinks } from './listing-links';
import { loadCommandModule, getLoaderService } from './utils';

import CopyCardToRealmCommand from '@cardstack/boxel-host/commands/copy-card';
import ExecuteAtomicOperationsCommand from '@cardstack/boxel-host/commands/execute-atomic-operations';
import ValidateRealmCommand from '@cardstack/boxel-host/commands/validate-realm';

export default class ListingUseCommand extends Command<
  typeof BaseCommandModule.ListingInstallInput
> {
  description = 'Catalog listing use command';

  async getInputType() {
    let commandModule = await loadCommandModule(this.commandContext);
    const { ListingInstallInput } = commandModule;
    return ListingInstallInput;
  }

  requireInputFields = ['realm', 'listing'];

  protected async run(
    input: BaseCommandModule.ListingInstallInput,
  ): Promise<undefined> {
    let { realm } = input;

    const listing = await loadListingInput(input);

    let { realmIdentifier: realmUrl } = await new ValidateRealmCommand(
      this.commandContext,
    ).execute({ realmIdentifier: realm });

    const { specs, examples, supportingCards, skills } =
      await loadListingLinks(listing);
    const specsWithoutFields = specs.filter(
      (spec) => spec.specType !== 'field',
    );

    const localDir = generateInstallFolderName(listing.name);
    let virtualNetwork = getLoaderService(
      this.commandContext,
    ).loader.getVirtualNetwork()!;

    // A blank instance is just a doc adopting from the spec's ref — write it
    // directly rather than loading the card class and instantiating it, so
    // the realm materializes field defaults at load time and the command
    // never has to fetch modules.
    let operations = [];
    for (const spec of specsWithoutFields) {
      if (spec.isComponent) {
        return;
      }
      let ref = codeRefWithAbsoluteIdentifier(
        spec.ref,
        rri(spec.id),
        undefined,
        virtualNetwork,
      );
      if (!isResolvedCodeRef(ref)) {
        throw new Error('ref is not a resolved code ref');
      }
      operations.push({
        op: 'add' as const,
        href: join(realmUrl, localDir, ref.name, crypto.randomUUID()) + '.json',
        data: { type: 'card', meta: { adoptsFrom: ref } },
      });
    }
    if (operations.length > 0) {
      await new ExecuteAtomicOperationsCommand(this.commandContext).execute({
        realmIdentifier: realmUrl,
        operations,
      });
    }

    const sourceCards = [
      ...new Map(
        [...examples, ...supportingCards].map((card) => [
          card.id ?? card,
          card,
        ]),
      ).values(),
    ];
    for (const card of sourceCards) {
      await new CopyCardToRealmCommand(this.commandContext).execute({
        sourceCard: card,
        targetRealm: realmUrl,
        localDir,
      });
    }

    await Promise.all(
      skills.map((skill) =>
        new CopyCardToRealmCommand(this.commandContext).execute({
          sourceCard: skill,
          targetRealm: realmUrl,
          localDir,
        }),
      ),
    );
  }
}
