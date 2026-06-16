import GlimmerComponent from '@glimmer/component';
import { modifier } from 'ember-modifier';
import { hash } from '@ember/helper';
import { on } from '@ember/modifier';

import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import XIcon from '@cardstack/boxel-icons/x';
import { Button } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';

import Popover from '@cardstack/catalog/46f065-popover/popover';

// A styled chat bubble yielded to the :messages block as `Chat.Message`, so
// consumers supply their own message data while the panel owns the look.
interface ChatMessageSignature {
  Args: { role?: 'ai' | 'user'; kind?: 'error' };
  Blocks: { default: [] };
  Element: HTMLDivElement;
}

class ChatMessage extends GlimmerComponent<ChatMessageSignature> {
  <template>
    <div
      class='ai-chat-msg
        {{if (eq @role "user") "is-user"}}
        {{if (eq @kind "error") "is-error"}}'
      ...attributes
    >{{yield}}</div>
    <style scoped>
      .ai-chat-msg {
        max-width: 85%;
        padding: 9px 13px;
        border-radius: 16px 16px 16px 4px;
        background: var(--c-bg, #f7f7f7);
        color: var(--c-text, #222222);
        font-size: 13px;
        line-height: 1.45;
        align-self: flex-start;
        animation: ai-chat-msg-in 0.18s ease both;
      }
      .ai-chat-msg.is-user {
        align-self: flex-end;
        border-radius: 16px 16px 4px 16px;
        background: var(--c-text, #222222);
        color: var(--c-text-light, #ffffff);
        font-weight: 600;
      }
      .ai-chat-msg.is-error {
        background: var(--c-accent-bg, #fff0f3);
        color: var(--c-accent-dark, #e00b41);
        font-weight: 600;
        font-size: 12px;
      }
      @keyframes ai-chat-msg-in {
        from {
          opacity: 0;
          transform: translateY(4px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
    </style>
  </template>
}

// Re-scroll the message list to the bottom whenever the passed key changes
// (the consumer passes a value that changes per appended message).
const scrollToBottom = modifier((element: HTMLElement, [_key]: [unknown]) => {
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      element.scrollTo({ top: element.scrollHeight, behavior: 'smooth' });
    });
  });
});

interface AiChatPanelSignature {
  Args: {
    // Popover open state + the parent's trigger/close handlers.
    open?: boolean;
    onToggle: () => void;
    onClose: () => void;
    // Optional outside-click / Esc dismissal, kept distinct from onClose
    // (the header X). When omitted the panel does NOT close on outside
    // click — only the X / trigger toggle close it (the Popover treats an
    // undefined onDismiss as "no outside-dismiss").
    onDismiss?: () => void;
    // Trigger button label (the parent decides any busy variant).
    triggerLabel: string;
    title?: string;
    subtitle?: string;
    // A value that changes each time a message is appended; drives auto-scroll.
    scrollKey?: unknown;
    isAssistantTyping?: boolean;
    isUserTyping?: boolean;
  };
  Blocks: {
    messages: [{ Message: typeof ChatMessage }];
    footer: [];
  };
}

// A self-contained AI chat popover: trigger button + popover + header,
// scrolling message list, typing indicators and a footer slot. All the chat
// chrome and styling lives here; the consumer passes message content through
// the :messages block (using the yielded `Chat.Message`) and the composer UI
// through the :footer block.
export default class AiChatPanel extends GlimmerComponent<AiChatPanelSignature> {
  <template>
    <Button
      class='ai-chat-trigger {{if @open "is-open"}}'
      @kind='primary'
      @size='small'
      data-ai-chat-anchor
      data-bx-popover-anchor
      {{on 'click' @onToggle}}
    >
      <SparklesIcon width='15' height='15' />
      {{@triggerLabel}}
    </Button>
    <Popover
      @anchor='[data-ai-chat-anchor]'
      @open={{if @open true false}}
      @kind='details'
      @role='dialog'
      @autoFocus={{true}}
      @anchoring='beside'
      @backdrop='none'
      @placement='bottom-end'
      @size='auto'
      @elevation='floating'
      @label={{if @title @title 'AI Assistant'}}
      @onDismiss={{@onDismiss}}
    >
      <:details>
        <div class='ai-chat-pop'>
          <div class='ai-chat-head'>
            <span class='ai-chat-head-icon'><SparklesIcon
                width='16'
                height='16'
              /></span>
            <span class='ai-chat-head-text'>
              <span class='ai-chat-head-title'>{{if
                  @title
                  @title
                  'AI Assistant'
                }}</span>
              <span class='ai-chat-head-sub'>{{if
                  @subtitle
                  @subtitle
                  'Powered by AI'
                }}</span>
            </span>
            <button
              type='button'
              class='ai-chat-close'
              aria-label='Close'
              {{on 'click' @onClose}}
            ><XIcon width='16' height='16' /></button>
          </div>
          <div class='ai-chat-body' {{scrollToBottom @scrollKey}}>
            {{yield (hash Message=ChatMessage) to='messages'}}
            {{#if @isAssistantTyping}}
              <div class='ai-chat-typing' aria-label='Working…'>
                <span class='ai-chat-dot'></span>
                <span class='ai-chat-dot'></span>
                <span class='ai-chat-dot'></span>
              </div>
            {{/if}}
            {{#if @isUserTyping}}
              <div class='ai-chat-typing is-user' aria-label='You are typing…'>
                <span class='ai-chat-dot'></span>
                <span class='ai-chat-dot'></span>
                <span class='ai-chat-dot'></span>
              </div>
            {{/if}}
          </div>
          <div class='ai-chat-foot'>
            {{yield to='footer'}}
          </div>
        </div>
      </:details>
    </Popover>
    <style scoped>
      .ai-chat-trigger {
        --boxel-button-color: var(--c-accent, #ff385c);
        --boxel-button-text-color: var(--c-text-light, #ffffff);
        --boxel-button-border-color: var(--c-accent, #ff385c);
        --boxel-button-border-radius: 10px;
        gap: 6px;
        font-weight: 700;
        white-space: nowrap;
      }
      .ai-chat-trigger.is-open {
        --boxel-button-color: var(--c-accent-dark, #e00b41);
        --boxel-button-border-color: var(--c-accent-dark, #e00b41);
      }

      /* The popover portals to document.body, OUTSIDE the host card, so the
         palette must be re-declared on this root or every var() below resolves
         to nothing and the chrome disappears. Same --ti-* override contract as
         the host card: set --ti-accent etc. up-tree (or on :root, which the
         portaled node still inherits) to rebrand. */
      .ai-chat-pop {
        --c-accent: var(--ti-accent, var(--primary, #ff385c));
        --c-accent-dark: var(--ti-accent-dark, #e00b41);
        --c-accent-bg: var(--ti-accent-bg, #fff0f3);
        --c-text: var(--ti-text, var(--foreground, #222222));
        --c-text-light: var(
          --ti-text-light,
          var(--primary-foreground, #ffffff)
        );
        --c-muted: var(--ti-muted, var(--muted-foreground, #717171));
        --c-border: var(--ti-border, var(--border, #dddddd));
        --c-border-light: var(--ti-border-light, var(--border, #ebebeb));
        --c-bg: var(--ti-bg, var(--muted, #f7f7f7));
        display: flex;
        flex-direction: column;
        width: 300px;
        max-width: 100%;
        max-height: 450px;
        font-family:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica,
          Arial, sans-serif;
        color: var(--c-text);
      }
      .ai-chat-head {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 14px 16px;
        border-bottom: 1px solid var(--c-border-light);
      }
      .ai-chat-head-icon {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 34px;
        height: 34px;
        border-radius: 50%;
        background: linear-gradient(
          135deg,
          var(--c-accent) 0%,
          var(--c-accent-dark) 100%
        );
        color: var(--c-text-light);
        flex-shrink: 0;
      }
      .ai-chat-head-text {
        display: flex;
        flex-direction: column;
        gap: 1px;
        min-width: 0;
      }
      .ai-chat-head-title {
        font-size: 14px;
        font-weight: 800;
        letter-spacing: -0.01em;
        color: var(--c-text);
      }
      .ai-chat-head-sub {
        font-size: 11px;
        font-weight: 600;
        color: var(--c-muted);
      }
      .ai-chat-close {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 30px;
        height: 30px;
        margin-left: auto;
        flex-shrink: 0;
        border: 1px solid var(--c-border);
        border-radius: 50%;
        background: #fff;
        color: var(--c-muted);
        cursor: pointer;
        transition:
          background 0.12s ease,
          border-color 0.12s ease,
          color 0.12s ease;
      }
      .ai-chat-close:hover {
        background: var(--c-bg);
        border-color: var(--c-text);
        color: var(--c-text);
      }
      .ai-chat-body {
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 14px 16px;
        height: 300px;
        overflow-y: auto;
        scroll-behavior: smooth;
      }
      .ai-chat-typing {
        align-self: flex-start;
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 12px 14px;
        background: var(--c-bg);
        border-radius: 16px 16px 16px 4px;
        animation: ai-chat-msg-in 0.18s ease both;
      }
      .ai-chat-typing.is-user {
        align-self: flex-end;
        background: var(--c-text);
        border-radius: 16px 16px 4px 16px;
      }
      .ai-chat-typing.is-user .ai-chat-dot {
        background: var(--c-text-light);
      }
      .ai-chat-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: var(--c-muted);
        animation: ai-chat-dot-bounce 1.2s infinite ease-in-out;
      }
      .ai-chat-dot:nth-child(2) {
        animation-delay: 0.15s;
      }
      .ai-chat-dot:nth-child(3) {
        animation-delay: 0.3s;
      }
      @keyframes ai-chat-dot-bounce {
        0%,
        60%,
        100% {
          transform: translateY(0);
          opacity: 0.5;
        }
        30% {
          transform: translateY(-4px);
          opacity: 1;
        }
      }
      @keyframes ai-chat-msg-in {
        from {
          opacity: 0;
          transform: translateY(4px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      .ai-chat-foot {
        flex-shrink: 0;
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 10px 16px 14px;
        border-top: 1px solid var(--c-border-light);
        background: #fff;
      }
      .ai-chat-foot:empty {
        display: none;
      }
    </style>
  </template>
}
