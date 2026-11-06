import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Button } from '@cardstack/pretui/components/button';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import AiCopilotCommand from '../commands/ai-copilot-command';
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
    <section class='copilot' aria-labelledby='copilot-h'>
      <div class='copilot-head'>
        <h2 id='copilot-h'>Copilot</h2>
        <p>drafts a reply for you to review</p>
      </div>
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
              @appearance='accent'
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
        <ul class='copilot-pick'>
          {{#each @candidates as |r|}}
            <li><button
                type='button'
                class='copilot-row'
                {{on 'click' (fn this.draftFor r.card)}}
              ><SparklesIcon class='copilot-icon' aria-hidden='true' /><span
                  class='copilot-name'
                >Draft for {{@titleOf r.card}}</span></button></li>
          {{else}}
            <li class='desk-empty'>No at-risk case to draft for.</li>
          {{/each}}
        </ul>
      {{/if}}
    </section>
    <style scoped>
      .copilot {
        display: flex;
        flex-direction: column;
      }
      .copilot-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .copilot-head h2 {
        margin: 0;
        font-size: 0.75rem;
        font-weight: 700;
      }
      .copilot-head p {
        margin: 0;
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .copilot-pick {
        display: grid;
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .copilot-pick > li {
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .copilot-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        inline-size: 100%;
        padding: 0;
        border: 0;
        background: none;
        color: inherit;
        font: inherit;
        font-weight: 600;
        text-align: start;
        cursor: pointer;
      }
      .copilot-row:hover .copilot-name {
        text-decoration: underline;
      }
      .copilot-row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .copilot-icon {
        flex: none;
        inline-size: 0.75rem;
        block-size: 0.75rem;
      }
      .copilot-name {
        min-inline-size: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .copilot-draft {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .copilot-tag {
        font: 600 0.5625rem/1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .copilot-text {
        margin: 0;
        white-space: pre-wrap;
        font-size: 0.75rem;
      }
      .copilot-actions {
        display: flex;
        gap: var(--boxel-sp-4xs);
      }
      .desk-loading,
      .desk-empty {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
