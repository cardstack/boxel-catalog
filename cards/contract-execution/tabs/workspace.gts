import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import { Contract } from '../../legal/contract';
import { ContractClause } from '../../legal/contract-clause';
import { ContractVersion } from '../../legal/contract-version';
import { formatMoney } from '../../commerce/line-item-totals';
import { StatePill } from '../../../components/state-pill';
import { ContractWorkspace } from '../../legal/components/contract-workspace';
import { SignatureBlockView } from '../../legal/components/signature-block-view';
import RequestSignatureCommand from '../../legal/commands/request-signature-command';
import VerifySignatureCommand from '../../legal/commands/verify-signature-command';
import ExecuteContractCommand from '../../legal/commands/execute-contract-command';
import GenerateDocumentCommand from '../../legal/commands/generate-document-command';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class WorkspaceTab extends GlimmerComponent<Signature> {
  @action clearWorkspace() {
    this.args.app.workspaceContract = undefined;
  }

  setProviderValue = (value: string) => {
    this.args.app.signatureProvider = value ?? '';
  };

  get workspaceBlocks() {
    return this.args.app.workspaceLive?.signatureBlocks ?? [];
  }

  requestSignature = () =>
    this.runCeremony('Request Signature', async (ctx, contract) => {
      let r = await new RequestSignatureCommand(ctx).execute({
        contract,
        provider: this.args.app.signatureProvider,
      } as any);
      return r.message ?? 'Requested.';
    });

  verifySignatures = () =>
    this.runCeremony('Verify Signature', async (ctx, contract) => {
      let r = await new VerifySignatureCommand(ctx).execute({
        contract,
      } as any);
      this.args.app.ceremonyFindings = (r.findings ?? []).filter(
        Boolean,
      ) as string[];
      return r.message ?? 'Verified.';
    });

  executeContract = () =>
    this.runCeremony('Execute Contract', async (ctx, contract) => {
      let realm = this.args.app.realmList[0];
      let r = await new ExecuteContractCommand(ctx).execute({
        contract,
        executedBy: this.args.app.actingAs,
        realm,
        priorVersions: this.workspaceVersions,
      } as any);
      return r.message ?? 'Executed.';
    });

  generateDocument = () =>
    this.runCeremony('Generate Document', async (ctx, contract) => {
      let clauses = this.workspaceClauses;
      let r = await new GenerateDocumentCommand(ctx).execute({
        contract,
        clauses,
        signatories: (this.args.app.signatoryQuery?.instances ?? []).filter(
          Boolean,
        ),
      } as any);
      return r.message ?? 'Generated.';
    });

  /** True until the app's clause and version queries have published rows. */
  get workspaceDataLoading(): boolean {
    let c = this.args.app.clauseUseQuery as any;
    let v = this.args.app.versionQuery as any;
    return Boolean(c?.isLoading) || Boolean(v?.isLoading);
  }

  /** The picked contract's clause instances and version snapshots, from the
   *  app's own live queries — handed to the commands so they need not search. */
  get workspaceClauses(): ContractClause[] {
    let id = this.args.app.workspaceLive?.id;
    return (
      (this.args.app.clauseUseQuery?.instances ?? []) as ContractClause[]
    ).filter((c) => {
      try {
        return Boolean(c) && c.contract?.id === id;
      } catch {
        return false;
      }
    });
  }

  get workspaceVersions(): ContractVersion[] {
    let id = this.args.app.workspaceLive?.id;
    return (
      (this.args.app.versionQuery?.instances ?? []) as ContractVersion[]
    ).filter((v) => {
      try {
        return Boolean(v) && v.contract?.id === id;
      } catch {
        return false;
      }
    });
  }

  async runCeremony(
    label: string,
    fn: (ctx: any, contract: Contract) => Promise<string>,
  ) {
    let contract = this.args.app.workspaceLive;
    let ctx = this.args.app.args.context?.commandContext;
    if (!contract) return;
    if (!ctx) {
      this.args.app.ceremonyProblem =
        'No command context in this host — open the app interactively.';
      return;
    }
    this.args.app.ceremonyBusy = true;
    this.args.app.ceremonyProblem = undefined;
    this.args.app.ceremonyNote = undefined;
    this.args.app.ceremonyFindings = [];
    try {
      this.args.app.ceremonyNote = await fn(ctx, contract);
    } catch (error: any) {
      this.args.app.ceremonyProblem = `${label} refused — ${error?.message ?? 'unknown error'}`;
    } finally {
      this.args.app.ceremonyBusy = false;
    }
  }

  <template>
    {{#if @app.workspaceLive}}
      {{#let @app.workspaceLive as |c|}}
        <section class='cx-sec cx-ws' aria-label='Contract workspace'>
          {{! the switcher stays visible: the reader should never
              wonder whether other contracts exist }}
          <nav class='cx-ws-switch' aria-label='Switch contract'>
            <span class='cx-ws-switch-label'>Contract</span>
            {{#each @app.contracts as |other|}}
              {{! native: a rich row (status dot and name) }}
              <button
                type='button'
                class='cx-ws-chip {{if (eq other.id c.id) "is-active"}}'
                aria-current={{if (eq other.id c.id) 'true'}}
                title={{other.cardTitle}}
                {{on 'click' (fn @app.openInWorkspace other)}}
              >
                <span
                  class='cx-ws-chip-dot hue-{{@app.statusHueOf other.status}}'
                  aria-hidden='true'
                ></span>
                <span class='cx-ws-chip-name'>{{other.cardTitle}}</span>
              </button>
            {{/each}}
          </nav>
          <div class='cx-ws-head'>
            <div class='cx-ws-id'>
              <h2 class='cx-h'>{{c.cardTitle}}</h2>
              <p class='cx-note'>{{@app.statusLabelOf c.status}}
                {{#if c.contractNumber}}· {{c.contractNumber}}{{/if}}
                {{#if c.value.amount}}·
                  {{formatMoney
                    c.value.amount
                    c.value.currency.code
                  }}{{/if}}</p>
            </div>
            <div class='cx-ws-actions'>
              <Button
                @tone='primary'
                @appearance='accent'
                {{on 'click' (fn @app.openCard c)}}
              >Open card</Button>
              <Button
                @appearance='outlined'
                {{on 'click' this.clearWorkspace}}
              >Pick another</Button>
            </div>
          </div>

          <ContractWorkspace
            @contract={{c}}
            @app.context={{@app.context}}
            @onOpen={{@app.openCard}}
          />

          <SignatureBlockView
            @blocks={{this.workspaceBlocks}}
            @contractValue={{c.value.amount}}
            @contractCurrency={{c.value.currency.code}}
            @contractType={{c.contractType}}
          />

          <div class='cx-ceremony-bar'>
            <label class='cx-provider'>
              <span>Provider</span>
              <Input
                @value={{@app.signatureProvider}}
                @onInput={{this.setProviderValue}}
              />
            </label>
            <Button
              @tone='primary'
              @appearance='accent'
              @disabled={{@app.ceremonyBusy}}
              title='approved → out for signature; sends the next line in signing order after re-checking authority'
              {{on 'click' this.requestSignature}}
            >Request signature</Button>
            <Button
              @appearance='outlined'
              @disabled={{@app.ceremonyBusy}}
              title='Re-derive every authority and order check from current data; writes nothing'
              {{on 'click' this.verifySignatures}}
            >Verify signatures</Button>
            <Button
              @tone='success'
              @appearance='accent'
              @disabled={{or @app.ceremonyBusy this.workspaceDataLoading}}
              title='out for signature → signed; refuses unless every line is signed and verification is clean; snapshots a version'
              {{on 'click' this.executeContract}}
            >Execute contract</Button>
            <Button
              @appearance='outlined'
              @disabled={{or @app.ceremonyBusy this.workspaceDataLoading}}
              title='Assemble the full agreement markdown into fullText'
              {{on 'click' this.generateDocument}}
            >Generate document</Button>
          </div>
          {{#if @app.ceremonyProblem}}
            <p
              class='cx-submit-msg is-err'
              role='alert'
            >{{@app.ceremonyProblem}}</p>
          {{else if @app.ceremonyNote}}
            <p
              class='cx-submit-msg is-ok'
              role='status'
            >{{@app.ceremonyNote}}</p>
          {{/if}}
          {{#if @app.ceremonyFindings.length}}
            <ul class='cx-findings'>
              {{#each @app.ceremonyFindings as |f|}}<li>{{f}}</li>{{/each}}
            </ul>
          {{/if}}
        </section>
      {{/let}}
    {{else}}
      <section class='cx-sec' aria-label='Pick a contract'>
        <h2 class='cx-h'>Workspace</h2>
        <p class='cx-note'>Pick a contract to review it clause by clause and run
          its signature ceremony. Legal Home and the repository also land here.</p>
        <ul class='cx-pick'>
          {{#each @app.contracts as |c|}}
            <li>
              {{! native: a rich row (name and status pill) }}
              <button
                type='button'
                class='cx-pick-row'
                {{on 'click' (fn @app.openInWorkspace c)}}
              >
                <span class='cx-pick-name'>{{c.cardTitle}}</span>
                <StatePill
                  @label={{@app.statusLabelOf c.status}}
                  @hue={{@app.statusHueOf c.status}}
                  @dot={{true}}
                />
              </button>
            </li>
          {{else}}
            <li class='cx-none'>No contracts in this realm yet.</li>
          {{/each}}
        </ul>
      </section>
    {{/if}}

    <style scoped>
      .cx-sec {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .cx-h {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }

      .cx-note {
        margin: 0 0 var(--boxel-sp);
        font-size: var(--boxel-font-size-sm);
        line-height: 1.55;
        color: var(--_cx-muted-fg);
        max-width: var(--_cx-measure);
      }
      .cx-submit-msg {
        margin: 0 0 var(--boxel-sp-xs);
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        border-radius: var(--radius);
        font-size: var(--boxel-font-size-sm);
        line-height: 1.5;
        max-width: var(--_cx-measure);
      }
      .cx-submit-msg.is-err {
        background: color-mix(in oklch, var(--destructive) 10%, transparent);
        border-left: 3px solid var(--destructive);
      }
      .cx-submit-msg.is-ok {
        background: color-mix(in oklch, var(--success) 10%, transparent);
        border-left: 3px solid var(--success);
      }
      .cx-ws {
        display: grid;
        gap: var(--boxel-sp);
      }
      .cx-ws-switch {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        flex-wrap: wrap;
        padding-bottom: var(--boxel-sp-xs);
        border-bottom: 1px solid var(--_cx-border);
      }
      .cx-ws-switch-label {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--_cx-muted-fg);
        margin-right: var(--boxel-sp-xxs);
      }
      .cx-ws-chip {
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        font-size: var(--boxel-font-size-sm);
        display: inline-flex;
        align-items: center;
        gap: 0.4rem;
        max-width: 18rem;
        min-height: 32px;
        padding: 0 0.7rem;
        border: 1px solid var(--_cx-border);
        border-radius: 999px;
        background: transparent;
        color: var(--_cx-fg);
        cursor: pointer;
      }
      .cx-ws-chip:hover {
        border-color: var(--_cx-fg);
      }
      .cx-ws-chip.is-active {
        background: var(--_cx-fg);
        border-color: var(--_cx-fg);
        color: var(--_cx-bg);
        font-weight: 600;
      }
      .cx-ws-chip-name {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .cx-ws-chip-dot {
        width: 7px;
        height: 7px;
        border-radius: 50%;
        flex: none;
        background: currentColor;
        opacity: 0.7;
      }
      .cx-ws-head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: var(--boxel-sp);
        flex-wrap: wrap;
      }
      .cx-ws-id {
        min-width: 0;
      }
      .cx-ws-actions,
      .cx-ceremony-bar {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .cx-ceremony-bar {
        padding-top: var(--boxel-sp-xs);
        border-top: 1px solid var(--_cx-border);
      }
      .cx-provider {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        font-size: var(--boxel-font-size-xs);
        color: var(--_cx-muted-fg);
        margin-right: auto;
      }
      .cx-findings {
        margin: 0;
        padding-left: 1.2rem;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.5;
        color: var(--_cx-fg);
      }
      .cx-pick {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xxs);
      }
      .cx-pick-row {
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        width: 100%;
        min-height: 44px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
        padding: 0 var(--boxel-sp-xs);
        border: 1px solid var(--_cx-border);
        border-radius: var(--radius);
        background: transparent;
        color: var(--_cx-fg);
        text-align: left;
        cursor: pointer;
      }
      .cx-pick-row:hover {
        background: color-mix(in oklch, currentColor 6%, transparent);
      }
      .cx-pick-name {
        font-weight: 600;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .cx-none {
        color: var(--_cx-muted-fg);
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}
