import GlimmerComponent from '@glimmer/component';
import { CopyButton } from '@cardstack/boxel-ui/components';

export interface CodeSnippetSignature {
  Args: {
    code: string;
  };
  Element: HTMLElement;
}

export default class CodeSnippet extends GlimmerComponent<CodeSnippetSignature> {
  <template>
    <div class='code-snippet-container'>
      <header class='code-snippet-header'>
        <span class='code-snippet-title'>CODE</span>
        <CopyButton class='code-snippet-copy-button' @textToCopy={{@code}} />
      </header>
      <pre class='code-snippet' data-test-code-snippet>{{@code}}</pre>
    </div>
    <style scoped>
      .code-snippet-container {
        display: flex;
        flex-direction: column;
      }
      .code-snippet-copy-button {
        margin-left: auto;
      }
      .code-snippet-header {
        border: 1px solid var(--border);
        border-bottom: none;
        border-top-left-radius: var(--radius);
        border-top-right-radius: var(--radius);
        background-color: var(--boxel-200);
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
      }
      .code-snippet-title {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.08em;
        font-weight: 600;
      }
      .code-snippet {
        margin-block: 0;
        padding: var(--boxel-sp);
        background-color: var(--card);
        border: 1px solid var(--border);
        border-top: none;
        border-bottom-left-radius: var(--radius);
        border-bottom-right-radius: var(--radius);
        border-top-left-radius: 0;
        border-top-right-radius: 0;
        color: var(--card-foreground);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        white-space: pre-wrap;
        word-break: break-word;
      }
    </style>
  </template>
}
