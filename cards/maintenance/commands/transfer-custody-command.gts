import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { inputCard } from '@cardstack/catalog/utils/find-card';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import { displayTitle } from '../utils/display';
import { Asset } from '../asset';
import { Employee } from '../../hr/employee';
import { CustodyTransferField } from '../custody-transfer-field';
import AssignOwnerCommand from '../../service-desk/commands/assign-owner-command';

export class TransferCustodyInput extends CardDef {
  @field asset = linksTo(() => Asset, { searchable: true });
  @field toOwner = linksTo(() => Employee, {
    description:
      'The new custodian. Omit with a teamName-only transfer (e.g. return to a pool).',
  });
  @field toTeamName = contains(StringField);
  @field kind = contains(StringField, {
    description: 'check-out | check-in | transfer | loan | return',
  });
  @field dueBack = contains(DateField, { description: 'Loans only.' });
  @field conditionCode = contains(StringField);
  @field note = contains(StringField);
}

export class TransferCustodyResult extends CardDef {
  @field message = contains(StringField);
}

/**
 * Hands an asset from one custodian to another. Appends an append-only
 * `CustodyTransferField` to the asset's `custodyLog` (the physical event —
 * who handed what to whom, when, in what condition) AND delegates the
 * current-owner rewrite to `AssignOwnerCommand`, the single writer of
 * `ownership`. This command never writes `ownership` itself.
 *
 * Order matters: the custody log entry is saved FIRST, then AssignOwnerCommand
 * re-fetches the asset by id (it always loads fresh) and writes ownership on
 * top of that — so both changes land, and ownership's provenance
 * (`previousOwnerName`) stays accurate.
 */
export default class TransferCustodyCommand extends Command<
  typeof TransferCustodyInput,
  typeof TransferCustodyResult
> {
  static actionVerb = 'Transfer';
  static displayName = 'Transfer Custody';

  async getInputType() {
    return TransferCustodyInput;
  }

  protected async run(
    input: TransferCustodyInput,
  ): Promise<TransferCustodyResult> {
    let asset = await inputCard<Asset>(this.commandContext, input, 'asset');
    if (!asset) {
      throw new Error('asset is required');
    }
    if (!linkedId(input, 'toOwner') && !input.toTeamName?.trim()) {
      throw new Error('Refused: transfer needs a toOwner or a toTeamName.');
    }
    let toOwner = await inputCard<Employee>(
      this.commandContext,
      input,
      'toOwner',
    );
    let kind = input.kind || (toOwner ? 'transfer' : 'check-in');

    let entry = new CustodyTransferField({
      kind,
      fromName: asset.ownership?.ownerName,
      fromTeamName: asset.ownership?.teamName,
      toId: toOwner?.id,
      toName: toOwner ? displayTitle(toOwner) : undefined,
      toTeamName: input.toTeamName,
      at: new Date(),
      dueBack: input.dueBack,
      conditionCode: input.conditionCode,
      note: input.note,
    });
    asset.custodyLog = [...(asset.custodyLog ?? []), entry];
    await new SaveCardCommand(this.commandContext).execute({
      card: asset,
    } as any);

    let strategy = toOwner ? 'assigned' : 'routed';
    await new AssignOwnerCommand(this.commandContext).execute({
      card: asset,
      owner: toOwner,
      teamName: input.toTeamName,
      strategy,
    } as any);

    return new TransferCustodyResult({
      message: `${displayTitle(asset, 'Asset')} custody: ${entry.label}`,
    });
  }
}
