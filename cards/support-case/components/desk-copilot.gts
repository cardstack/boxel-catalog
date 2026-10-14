import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Button } from '@cardstack/pretui/components/button';
import AiCopilotCommand from '../../../commands/ai-copilot-command';
import { CustomerReply } from '../../service-desk/customer-reply';

interface Signature {
  Args: {
    /** At-risk cases, nearest breach first, each as { card }. */
    candidates: { card: any }[];
    titleOf: (card: any) => string;
    repliesFor: (card: any) => any[];
    operator: any;
    operatorName: string;
    context: any;
    realm: string | undefined;
    onNote: (message: string) => void;
  };
}

/** Drafts a reply for an at-risk case. Drafting saves nothing; accepting a
    draft is a separate act that saves it as the operator's own outbound
    Customer Reply. */
export class DeskCopilot extends GlimmerComponent<Signature> {
  @tracked draft: string | null = null;
  @tracked citations: string[] = [];
  @tracked busy = false;
  get citationList() {
    return this.citations.join(', ');
  }
  target: any = null;

  get commandContext() {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      throw new Error('No command context available in this render mode');
    }
    return ctx;
  }

  draftFor = async (card: any) => {
    this.busy = true;
    this.draft = null;
    this.target = card;
    try {
      let result = await new AiCopilotCommand(this.commandContext).execute({
        case: card,
        intent: 'draft-reply',
        replies: this.args.repliesFor(card),
      } as any);
      this.draft = (result as any).draft;
      this.citations = [...((result as any).citations ?? [])];
    } catch (e: any) {
      this.args.onNote(e?.message ?? String(e));
    } finally {
      this.busy = false;
    }
  };

  acceptDraft = async () => {
    if (!this.target || !this.draft) return;
    let reply = new CustomerReply({
      case: this.target,
      direction: 'outbound',
      channel: 'portal',
      body: this.draft,
      author: this.args.operator,
      sentAt: new Date(),
    } as any);
    await new SaveCardCommand(this.commandContext).execute({
      card: reply,
      realm: this.args.realm,
    } as any);
    this.draft = null;
    this.args.onNote(
      `Saved as an outbound reply, attributed to ${this.args.operatorName}.`,
    );
  };
  discardDraft = () => {
    this.draft = null;
  };

  <template>
    <section class='copilot'>
      <h3 class='copilot-title'>Copilot: drafts a reply for you to review</h3>
      {{#if this.busy}}
        <p class='desk-loading' role='status'>Drafting…</p>
      {{else if this.draft}}
        <div class='copilot-draft'>
          <span class='copilot-tag'>DRAFT{{#if this.citations.length}}
              · cites
              {{this.citationList}}{{/if}}</span>
          <p class='copilot-text'>{{this.draft}}</p>
          <div class='copilot-actions'>
            <Button
              @tone='primary'
              @appearance='filled'
              @size='s'
              {{on 'click' this.acceptDraft}}
            >Save as my reply</Button>
            <Button
              @tone='neutral'
              @appearance='outlined'
              @size='s'
              {{on 'click' this.discardDraft}}
            >Discard</Button>
          </div>
        </div>
      {{else}}
        <div class='copilot-pick'>
          {{#each @candidates as |r|}}
            <Button
              @tone='neutral'
              @appearance='outlined'
              @size='xs'
              {{on 'click' (fn this.draftFor r.card)}}
            >✦ Draft for {{@titleOf r.card}}</Button>
          {{else}}
            <p class='desk-empty'>No at-risk case to draft for.</p>
          {{/each}}
        </div>
      {{/if}}
    </section>
    <style scoped>
      .copilot {
        border: 1px solid transparent;
        box-shadow: 0 1px 0
          color-mix(in oklab, var(--foreground) 5%, transparent);
        border-radius: var(--radius);
        background: var(--card);
        padding: var(--boxel-sp-sm);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .copilot-title {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .copilot-pick {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
      }
      .copilot-draft {
        border: 1px dashed var(--primary);
        border-radius: var(--radius);
        padding: var(--boxel-sp-sm);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        background: color-mix(in oklab, var(--primary) 6%, var(--card));
      }
      .copilot-tag {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.1em;
        font-weight: 600;
        color: var(--primary-ink);
      }
      .copilot-text {
        margin: 0;
        white-space: pre-wrap;
        font-size: var(--boxel-font-size-sm);
        max-width: 70ch;
      }
      .copilot-actions {
        display: flex;
        gap: var(--boxel-sp-4xs);
      }

      .desk-loading,
      .desk-empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
