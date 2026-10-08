import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import { Command, identifyCard, realmURL } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { SearchCardsByQueryCommand } from '@cardstack/boxel-host/commands/search-cards';

import { Thread, PostField } from '../thread';
import { PersonBase } from '@cardstack/catalog/cards/people/person-base';

export class PostToThreadInput extends CardDef {
  @field thread = linksTo(() => Thread, { searchable: true });
  /**
   * When no thread is given, the open thread about this card takes the post;
   * one is opened, with this title, only when there is none.
   */
  @field about = linksTo(() => CardDef, { searchable: true });
  @field title = contains(StringField);
  @field author = linksTo(() => PersonBase, { searchable: true });
  @field body = contains(MarkdownField);
  /** Where a new thread is saved; defaults to the realm of `about`. */
  @field realm = contains(StringField);
}

export class PostToThreadResult extends CardDef {
  @field thread = linksTo(() => Thread);
  @field message = contains(StringField);
}

/**
 * Appends a post — the single writer of `posts[]`. Refuses an empty body,
 * an anonymous post, or a closed thread. Given no thread but an `about`
 * card, opens a new thread first; that is how a cohort gets its discussion
 * on the first message rather than by someone remembering to create one.
 */
export default class PostToThreadCommand extends Command<
  typeof PostToThreadInput,
  typeof PostToThreadResult
> {
  static actionVerb = 'Post';
  static displayName = 'Post to Thread';

  async getInputType() {
    return PostToThreadInput;
  }

  // The newest open thread about the card. Matched in the query, since a
  // search result's links are not loaded in a command.
  private async openThreadAbout(aboutId: string): Promise<Thread | undefined> {
    let ref = identifyCard(Thread);
    if (!ref) return undefined;
    let { instances } = await new SearchCardsByQueryCommand(
      this.commandContext,
    ).execute({
      query: {
        filter: {
          on: ref,
          every: [
            { eq: { 'about.id': aboutId } },
            // A thread whose `closed` was never set is open too.
            {
              any: [{ eq: { closed: false } }, { eq: { closed: null } }],
            },
          ],
        },
      },
    });
    let open = ((instances ?? []) as Thread[]).filter(Boolean);
    return open.sort(
      (a, b) =>
        (b.lastActivityAt?.getTime?.() ?? 0) -
        (a.lastActivityAt?.getTime?.() ?? 0),
    )[0];
  }

  protected async run(input: PostToThreadInput): Promise<PostToThreadResult> {
    let { about, title, author, body, realm } = input;
    let thread: Thread | undefined = input.thread ?? undefined;
    if (!body?.trim()) throw new Error('A post needs a body');
    if (!author?.id) throw new Error('A post needs an author');

    if (!thread?.id) {
      if (!about?.id)
        throw new Error(
          'Either a thread or a card to start one about is required',
        );
      thread = await this.openThreadAbout(about.id);
    }
    if (!thread?.id) {
      let target = realm || (about as any)?.[realmURL]?.href;
      if (!target) throw new Error('A realm is required to open a new thread');
      thread = (await new SaveCardCommand(this.commandContext).execute({
        card: new Thread({
          title:
            title?.trim() ||
            `Discussion: ${(about as any).cardTitle ?? ''}`.trim(),
          about,
        }),
        realm: target,
      } as any)) as Thread;
    } else {
      thread = (await new GetCardCommand(this.commandContext).execute({
        cardId: thread.id,
      })) as Thread;
    }
    if (!thread) throw new Error('No thread to post to');
    if (thread.closed) throw new Error(`${thread.cardTitle} is closed`);

    // Append on the loaded card and save (a containsMany of links cannot be
    // addressed as a JSON patch).
    let posts = (thread.posts ?? []) as any[];
    let n = posts.length;
    thread.posts = [
      ...posts,
      new PostField({ author, body: body.trim(), postedAt: new Date() }),
    ];
    await new SaveCardCommand(this.commandContext).execute({
      card: thread,
    } as any);

    return new PostToThreadResult({
      thread,
      message: `Posted to ${thread.cardTitle} (${n + 1} post${n === 0 ? '' : 's'}).`,
    });
  }
}
