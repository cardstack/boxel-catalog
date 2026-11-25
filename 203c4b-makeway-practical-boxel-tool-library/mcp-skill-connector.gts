import { Component } from '@cardstack/base/card-api';
import type { MakewayHome } from './makeway-home';
import { Button } from '@cardstack/pretui/components/button';
import { Field } from '@cardstack/pretui/components/field';
import { Textarea } from '@cardstack/pretui/components/textarea';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';

type McpTool = {
  name: string;
  description?: string;
  inputSchema?: Record<string, unknown>;
};

type RpcMessage = {
  jsonrpc?: string;
  id?: number | string;
  result?: any;
  error?: { code?: number; message?: string; data?: unknown };
};

function parseEventStream(text: string): RpcMessage[] {
  const messages: RpcMessage[] = [];
  for (const block of text.split(/\r?\n\r?\n/)) {
    const data = block
      .split(/\r?\n/)
      .filter((line) => line.startsWith('data:'))
      .map((line) => line.slice(5).trim())
      .join('\n');
    if (!data || data === '[DONE]') continue;
    try {
      messages.push(JSON.parse(data) as RpcMessage);
    } catch {
      throw new Error(
        'The MCP server returned an invalid event-stream message.',
      );
    }
  }
  return messages;
}

function isPrivateOrLocalHost(hostname: string): boolean {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (
    host === 'localhost' ||
    host.endsWith('.localhost') ||
    host.endsWith('.local') ||
    host.endsWith('.internal') ||
    host === '::1' ||
    host.startsWith('fc') ||
    host.startsWith('fd') ||
    host.startsWith('fe80:')
  )
    return true;
  const ipv4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!ipv4) return false;
  const octets = ipv4.slice(1).map(Number);
  const [a, b] = octets;
  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168)
  );
}

class McpSkillConnectorView extends Component<typeof MakewayHome> {
  @tracked endpoint = '';
  @tracked tools: McpTool[] = [];
  @tracked selectedTool: McpTool | undefined;
  @tracked argumentsText = '{}';
  @tracked output = '';
  @tracked status = '';
  @tracked error = '';
  @tracked busy = false;
  @tracked connectedName = '';
  private sessionId: string | undefined;
  private protocolVersion = '2025-03-26';
  private requestId = 0;

  setEndpoint = (value: string) => {
    this.endpoint = value;
  };
  setArguments = (value: string) => {
    this.argumentsText = value;
  };
  schemaText = (schema: unknown) => JSON.stringify(schema, null, 2);

  private validatedEndpoint(): string {
    let parsed: URL;
    try {
      parsed = new URL(this.endpoint.trim());
    } catch {
      throw new Error(
        'Enter a complete HTTPS endpoint URL for the MCP server.',
      );
    }
    if (parsed.protocol !== 'https:') {
      throw new Error('For safety, the MCP endpoint must use HTTPS.');
    }
    if (parsed.username || parsed.password || parsed.search || parsed.hash) {
      throw new Error(
        'Do not put credentials, query parameters, or fragments in the endpoint URL.',
      );
    }
    if (isPrivateOrLocalHost(parsed.hostname)) {
      throw new Error(
        'Local and private-network MCP endpoints are not supported from this browser connector.',
      );
    }
    return parsed.href;
  }

  private postMessage = async (message: Record<string, unknown>) => {
    const headers: Record<string, string> = {
      Accept: 'application/json, text/event-stream',
      'Content-Type': 'application/json',
    };
    if (this.sessionId) headers['MCP-Session-Id'] = this.sessionId;
    if (message.method !== 'initialize')
      headers['MCP-Protocol-Version'] = this.protocolVersion;
    const response = await fetch(this.validatedEndpoint(), {
      method: 'POST',
      headers,
      body: JSON.stringify(message),
      credentials: 'omit',
      referrerPolicy: 'no-referrer',
      redirect: 'error',
      mode: 'cors',
    });
    if (!response.ok && response.status !== 202) {
      throw new Error(
        'MCP server answered HTTP ' +
          response.status +
          '. Check the endpoint and its CORS support.',
      );
    }
    const returnedSession = response.headers.get('MCP-Session-Id');
    if (returnedSession) this.sessionId = returnedSession;
    const text = await response.text();
    if (!text.trim()) return [] as RpcMessage[];
    const contentType =
      response.headers.get('content-type')?.toLowerCase() ?? '';
    const messages =
      contentType.includes('text/event-stream') || text.includes('\ndata:')
        ? parseEventStream(text)
        : [JSON.parse(text) as RpcMessage];
    for (const item of messages) {
      if (item.error) {
        throw new Error(
          'MCP error ' + (item.error.code ?? '') + ': ' + item.error.message,
        );
      }
    }
    return messages;
  };

  private request = async (
    method: string,
    params?: Record<string, unknown>,
  ) => {
    const id = ++this.requestId;
    const message: Record<string, unknown> = { jsonrpc: '2.0', id, method };
    if (params) message.params = params;
    const messages = await this.postMessage(message);
    const reply = messages.find((item) => item.id === id);
    if (!reply)
      throw new Error(
        'The MCP server did not return a response for ' + method + '.',
      );
    return reply.result;
  };

  connect = async () => {
    this.error = '';
    this.output = '';
    this.status = '';
    this.tools = [];
    this.selectedTool = undefined;
    this.sessionId = undefined;
    this.busy = true;
    try {
      const initialize = await this.request('initialize', {
        protocolVersion: this.protocolVersion,
        capabilities: {},
        clientInfo: { name: 'Makeway MCP Connector', version: '1.0.0' },
      });
      if (!initialize || typeof initialize.protocolVersion !== 'string') {
        throw new Error(
          'The MCP server returned an incomplete initialize response.',
        );
      }
      this.protocolVersion = initialize.protocolVersion;
      this.connectedName = initialize.serverInfo?.name ?? 'MCP server';
      await this.postMessage({
        jsonrpc: '2.0',
        method: 'notifications/initialized',
      });
      const found: McpTool[] = [];
      let cursor: string | undefined;
      let pages = 0;
      do {
        const page = await this.request(
          'tools/list',
          cursor ? { cursor } : undefined,
        );
        if (!Array.isArray(page?.tools))
          throw new Error('The MCP server did not return a tools list.');
        found.push(
          ...page.tools.filter(
            (tool: unknown) =>
              tool &&
              typeof tool === 'object' &&
              typeof (tool as McpTool).name === 'string',
          ),
        );
        cursor =
          typeof page.nextCursor === 'string' ? page.nextCursor : undefined;
        pages += 1;
      } while (cursor && pages < 10);
      if (cursor)
        throw new Error(
          'This server has more than 10 pages of tools; narrow its tool list and reconnect.',
        );
      this.tools = found;
      this.status =
        'Connected to ' +
        this.connectedName +
        ' · ' +
        found.length +
        ' tools available.';
    } catch (reason) {
      this.error = reason instanceof Error ? reason.message : String(reason);
      this.status = '';
      this.sessionId = undefined;
    } finally {
      this.busy = false;
    }
  };

  disconnect = () => {
    this.tools = [];
    this.selectedTool = undefined;
    this.sessionId = undefined;
    this.connectedName = '';
    this.status = 'Disconnected.';
    this.error = '';
    this.output = '';
  };

  selectTool = (tool: McpTool) => {
    this.selectedTool = tool;
    this.argumentsText = '{}';
    this.output = '';
    this.error = '';
  };

  runTool = async () => {
    if (!this.selectedTool) return;
    this.error = '';
    this.output = '';
    let args: unknown;
    try {
      args = JSON.parse(this.argumentsText);
      if (!args || typeof args !== 'object' || Array.isArray(args)) {
        throw new Error('Arguments must be a JSON object.');
      }
    } catch (reason) {
      this.error =
        reason instanceof Error
          ? reason.message
          : 'Arguments must be valid JSON.';
      return;
    }
    this.busy = true;
    try {
      const result = await this.request('tools/call', {
        name: this.selectedTool.name,
        arguments: args as Record<string, unknown>,
      });
      this.output =
        JSON.stringify(result, null, 2) ?? 'The tool returned no content.';
      this.status = result?.isError
        ? 'The server reports this tool call failed.'
        : 'Tool call completed.';
    } catch (reason) {
      this.error = reason instanceof Error ? reason.message : String(reason);
    } finally {
      this.busy = false;
    }
  };

  <template>
    <section class='mcp-panel' aria-label='Connect to an MCP skill server'>
      <div class='mcp-heading'>
        <p class='mw-kicker'>MCP SKILL CONNECTOR</p>
        <h2>Connect a tool server.</h2>
        <p>Connect to a public, unauthenticated MCP Streamable HTTP endpoint.
          Makeway discovers its tools and can call one you select.</p>
      </div>
      <Field
        @label='MCP server HTTPS endpoint'
        @hint='Streamable HTTP only · no sign-in or API key'
        as |id|
      >
        <Textarea
          @controlId={{id}}
          @value={{this.endpoint}}
          @placeholder='https://your-mcp-server.example/mcp'
          @onInput={{this.setEndpoint}}
        />
      </Field>
      <div class='mcp-actions'>
        <Button
          @tone='primary'
          @appearance='accent'
          @busy={{this.busy}}
          @busyLabel='Connecting to MCP server'
          {{on 'click' this.connect}}
        >Connect &amp; list tools</Button>
        {{#if this.connectedName}}<Button
            @tone='neutral'
            @appearance='outlined'
            @disabled={{this.busy}}
            {{on 'click' this.disconnect}}
          >Disconnect</Button>{{/if}}
      </div>
      {{#if this.status}}<p
          class='mcp-status'
          role='status'
        >{{this.status}}</p>{{/if}}
      {{#if this.error}}<p
          class='mw-error'
          role='alert'
        >{{this.error}}</p>{{/if}}
      {{#if this.tools.length}}
        <p class='mcp-safety'>Only connect to a server you trust. Each tool call
          is sent to that server; Makeway sends no login cookies or credentials.</p>
        <div class='mcp-tool-list' aria-label='Available MCP tools'>
          {{#each this.tools key='name' as |tool|}}
            <article class='mcp-tool'>
              <div><h3>{{tool.name}}</h3><p>{{tool.description}}</p></div>
              <Button
                @size='s'
                @tone='primary'
                @appearance='outlined'
                @disabled={{this.busy}}
                {{on 'click' (fn this.selectTool tool)}}
              >Choose tool</Button>
              {{#if tool.inputSchema}}<pre class='mcp-schema'>{{this.schemaText
                    tool.inputSchema
                  }}</pre>{{/if}}
            </article>
          {{else}}
            <p>This server did not publish any tools.</p>
          {{/each}}
        </div>
      {{/if}}
      {{#if this.selectedTool}}
        <div class='mcp-run'>
          <h3>Run {{this.selectedTool.name}}</h3>
          <p>Review the tool and its input schema above. Calls may have effects
            on the MCP server’s side.</p>
          <Field
            @label='Tool arguments (JSON object)'
            @hint='Enter the arguments required by this tool.'
            as |id|
          >
            <Textarea
              @controlId={{id}}
              @value={{this.argumentsText}}
              @onInput={{this.setArguments}}
              @placeholder='{}'
            />
          </Field>
          <Button
            @tone='primary'
            @appearance='accent'
            @busy={{this.busy}}
            @busyLabel='Running MCP tool'
            {{on 'click' this.runTool}}
          >Run selected tool</Button>
        </div>
      {{/if}}
      {{#if this.output}}<div class='mcp-result'><h3>Tool result</h3><pre
          >{{this.output}}</pre></div>{{/if}}
      <p class='mcp-limits'>Browser-only transport: the MCP server must allow
        CORS. Supports HTTPS Streamable HTTP and tool list/call. Local stdio
        servers, authenticated endpoints, prompts, resources, and legacy
        SSE-only transport are not supported.</p>
    </section>
    <style scoped>
      .mcp-panel {
        display: grid;
        gap: 1rem;
        margin: 1.5rem 0;
        padding: clamp(1rem, 3vw, 1.5rem);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--foreground);
      }
      .mcp-heading h2,
      .mcp-run h3,
      .mcp-result h3 {
        margin-top: 0.45rem;
        font-family: var(--font-serif);
        font-weight: 400;
      }
      .mcp-heading h2 {
        font-size: 1.65rem;
      }
      .mcp-heading > p:last-child,
      .mcp-run > p,
      .mcp-tool p {
        max-width: 70ch;
        margin-top: 0.45rem;
        color: var(--muted-foreground);
        font-size: 0.82rem;
        line-height: 1.5;
      }
      .mcp-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 0.6rem;
      }
      .mcp-status {
        color: var(--primary-ink);
        font-size: 0.8rem;
      }
      .mcp-safety,
      .mcp-limits {
        color: var(--muted-foreground);
        font-size: 0.72rem;
        line-height: 1.5;
      }
      .mcp-tool-list {
        display: grid;
        gap: 0.65rem;
      }
      .mcp-tool {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        align-items: start;
        gap: 0.65rem 1rem;
        min-width: 0;
        padding: 0.9rem;
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .mcp-tool h3 {
        overflow-wrap: anywhere;
        font-size: 0.9rem;
        font-weight: 650;
      }
      .mcp-tool details {
        grid-column: 1 / -1;
        color: var(--muted-foreground);
        font-size: 0.75rem;
      }
      .mcp-schema {
        grid-column: 1 / -1;
        max-height: 10rem;
        overflow: auto;
        margin: 0;
        padding: 0.65rem;
        border-radius: var(--radius);
        background: var(--muted);
        color: var(--foreground);
        white-space: pre-wrap;
        overflow-wrap: anywhere;
        font-family: var(--font-mono);
        font-size: 0.68rem;
      }
      .mcp-tool pre,
      .mcp-result pre {
        max-height: 18rem;
        overflow: auto;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
        font-family: var(--font-mono);
        font-size: 0.72rem;
        line-height: 1.5;
      }
      .mcp-run,
      .mcp-result {
        display: grid;
        gap: 0.75rem;
        padding-top: 1rem;
        border-top: 1px solid var(--border);
      }
      .mcp-result pre {
        margin: 0;
        padding: 0.9rem;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--muted);
        color: var(--foreground);
      }
      @media (max-width: 560px) {
        .mcp-tool {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    </style>
  </template>
}

export { McpSkillConnectorView as McpSkillConnector };
