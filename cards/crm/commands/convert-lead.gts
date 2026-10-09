import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Lead } from '@cardstack/catalog/cards/crm/lead';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { Contact } from '@cardstack/catalog/cards/crm/contact';
import { Opportunity } from '@cardstack/catalog/cards/crm/opportunity';
import { findCard, inputCard } from '@cardstack/catalog/utils/find-card';

export class ConvertLeadInput extends CardDef {
  @field lead = linksTo(Lead, { searchable: true });
  @field realm = contains(StringField);
}

export class ConvertLeadResult extends CardDef {
  @field account = linksTo(Account);
  @field contact = linksTo(Contact);
  @field opportunity = linksTo(Opportunity);
  @field message = contains(StringField);
}

export default class ConvertLeadCommand extends Command<
  typeof ConvertLeadInput,
  typeof ConvertLeadResult
> {
  static actionVerb = 'Convert Lead';

  async getInputType() {
    return ConvertLeadInput;
  }

  protected async run(input: ConvertLeadInput): Promise<ConvertLeadResult> {
    let ctx = this.commandContext;
    let lead = await inputCard<Lead>(ctx, input, 'lead');
    if (!lead) throw new Error('A lead is required');
    let realm = input.realm?.trim() || (lead as any)[realmURL]?.href;
    if (!realm) throw new Error('A realm is required');
    if (lead.status === 'disqualified') {
      throw new Error('A disqualified lead cannot be converted');
    }
    if (lead.status === 'converted') {
      throw new Error('This lead has already been converted');
    }

    let save = async <T extends CardDef>(card: T): Promise<T> =>
      (await new SaveCardCommand(ctx).execute({ card, realm } as any)) as T;

    let emailDomain = lead.email?.split('@')[1] ?? null;
    let accountName = lead.company?.trim() || lead.name || 'New Account';
    // The lead is marked converted last, and each record is looked up before
    // it is made, so a run interrupted part way is finished by running it
    // again instead of creating a second account, contact and opportunity.
    let account =
      (await findCard<Account>(
        ctx,
        Account,
        { name: accountName, domain: emailDomain },
        realm,
      )) ||
      (await save(new Account({ name: accountName, domain: emailDomain })));

    // Named for the lead, so two leads at one company each get their own deal.
    let opportunityName = `${accountName} — ${lead.name || 'first deal'}`;
    let nameParts = (lead.name ?? '').trim().split(/\s+/);
    let contact =
      (await findCard<Contact>(
        ctx,
        Contact,
        // With no email, the lead's name keeps it from matching another
        // email-less contact on the account.
        lead.email
          ? { 'account.id': account.id, email: lead.email }
          : {
              'account.id': account.id,
              email: null,
              firstName: nameParts[0] || null,
              lastName: nameParts.slice(1).join(' ') || null,
            },
        realm,
      )) ||
      (await save(
        new Contact({
          firstName: nameParts[0],
          lastName: nameParts.slice(1).join(' ') || undefined,
          email: lead.email,
          phone: lead.phone,
          account,
        }),
      ));

    let opportunity =
      (await findCard<Opportunity>(
        ctx,
        Opportunity,
        { 'account.id': account.id, name: opportunityName },
        realm,
      )) ||
      (await save(
        new Opportunity({
          name: opportunityName,
          stage: 'qualified',
          lastStageChangedAt: new Date(),
          account,
        }),
      ));

    lead.status = 'converted';
    await save(lead);

    return new ConvertLeadResult({
      account,
      contact,
      opportunity,
      message: `Converted ${lead.name} into ${accountName} (account + contact + qualified opportunity)`,
    });
  }
}
