import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import { typedCard } from './links';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { Certificate, CertificateStatusField } from '../certificate';
import { canTransition } from '@cardstack/catalog/fields/status/status';

export class RevokeCertificateInput extends CardDef {
  @field certificate = linksTo(() => Certificate, { searchable: true });
  @field reason = contains(StringField);
}

export class RevokeCertificateResult extends CardDef {
  @field certificate = linksTo(() => Certificate);
  @field message = contains(StringField);
}

/**
 * issued → revoked with a written reason. Refuses without one, and refuses
 * a second revocation. Nothing is deleted and the number is never freed:
 * the verify link keeps resolving, now to a record that says "revoked" and
 * why — which is the whole point of having numbers.
 */
export default class RevokeCertificateCommand extends Command<
  typeof RevokeCertificateInput,
  typeof RevokeCertificateResult
> {
  static actionVerb = 'Revoke';
  static displayName = 'Revoke Certificate';

  async getInputType() {
    return RevokeCertificateInput;
  }

  protected async run(
    input: RevokeCertificateInput,
  ): Promise<RevokeCertificateResult> {
    let { reason } = input;
    let certificateId = linkedId(input, 'certificate');
    if (!certificateId) throw new Error('A certificate is required');
    if (!reason?.trim())
      throw new Error(
        'A reason is required — it is printed on the revoked record',
      );
    let certificate = await typedCard(
      this.commandContext,
      certificateId,
      Certificate,
    );

    let from = certificate.certStatus ?? 'issued';
    if (!canTransition(CertificateStatusField, from, 'revoked')) {
      throw new Error(
        `${certificate.number ?? 'This certificate'} is already ${from}`,
      );
    }

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: Certificate,
    }).execute({
      cardId: certificate.id,
      patch: {
        attributes: {
          certStatus: 'revoked',
          revokedAt: new Date().toISOString(),
          revokedReason: reason.trim(),
        },
      },
    });

    return new RevokeCertificateResult({
      certificate,
      message: `${certificate.number ?? 'Certificate'} revoked: ${reason.trim()}`,
    });
  }
}
