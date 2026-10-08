import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Thread, PostField } from '../thread';
import { PersonBase } from '@cardstack/catalog/cards/people/person-base';

export class PostToThreadInput extends CardDef {
  @field thread = linksTo(() => Thread, { searchable: true });
  /** When no thread is given, one is created about this card with this title. */
  @field about = linksTo(() => CardDef, { searchable: true });
  @field title = contains(StringField);
  @field author = linksTo(() => PersonBase, { searchable: true });
  @field body = contains(MarkdownField);
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

  protected async run(input: PostToThreadInput): Promise<PostToThreadResult> {
    let { thread, about, title, author, body, realm } = input;
    if (!body?.trim()) throw new Error('A post needs a body');
    if (!author?.id) throw new Error('A post needs an author');

    if (!thread?.id) {
      if (!about?.id)
        throw new Error(
          'Either a thread or a card to start one about is required',
        );
      if (!realm) throw new Error('A realm is required to open a new thread');
      thread = (await new SaveCardCommand(this.commandContext).execute({
        card: new Thread({
          title:
            title?.trim() ||
            `Discussion: ${(about as any).cardTitle ?? ''}`.trim(),
          about,
        }),
        realm,
      } as any)) as Thread;
    } else {
      thread = (await new GetCardCommand(this.commandContext).execute({
        cardId: thread.id,
      })) as Thread;
    }
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
