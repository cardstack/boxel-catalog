import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn, uniqueId } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { Item } from '@cardstack/pretui/components/item';
import { Input } from '@cardstack/pretui/components/input';
import { or } from '@cardstack/pretui/helpers';
import { Contract } from '../../legal/contract';
import { ContractClause } from '../../legal/contract-clause';
import { ContractVersion } from '../../legal/contract-version';
import {
  SIGNATURE_BLOCK_STATUS_LABELS,
  SIGNATURE_BLOCK_STATUS_HUE,
} from '../../legal/signature-block-field';
import { formatMoney } from '../../commerce/line-item-totals';
import RequestSignatureCommand from '../../legal/commands/request-signature-command';
import VerifySignatureCommand from '../../legal/commands/verify-signature-command';
import ExecuteContractCommand from '../../legal/commands/execute-contract-command';
import GenerateDocumentCommand from '../../legal/commands/generate-document-command';
import { formatDay, hueTone, type Tone } from '../../shared/compact-format';
import { CeTable, Dot, Note, SubHead, type Col } from '../components';

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
        "This host can't run signing steps. Open the app in the interactive host and try again.";
      return;
    }
    this.args.app.ceremonyBusy = true;
    this.args.app.ceremonyProblem = undefined;
    this.args.app.ceremonyNote = undefined;
    this.args.app.ceremonyFindings = [];
    try {
      this.args.app.ceremonyNote = await fn(ctx, contract);
    } catch (error: any) {
      this.args.app.ceremonyProblem = `${label} didn't run: ${
        error?.message ?? 'the host gave no reason'
      }. Fix that, then try ${label} again.`;
    } finally {
      this.args.app.ceremonyBusy = false;
    }
  }

  clauseTone = (u: any): Tone =>
    !u?.isDeviation
      ? 'success'
      : u?.deviationSeverity === 'minor'
        ? 'warning'
        : 'danger';

  clauseState = (u: any): string =>
    u?.isDeviation ? (u?.deviationSeverity ?? 'deviation') : 'on playbook';

  get sortedClauses() {
    return [...this.workspaceClauses];
  }

  get signatories(): any[] {
    return (this.args.app.signatoryQuery?.instances ?? []).filter(Boolean);
  }

  authorityOf = (b: any): string => {
    let c: any = this.args.app.workspaceLive;
    let name = b?.signerName ?? b?.displayName;
    let sg = this.signatories.find(
      (s: any) => s?.person?.cardTitle === name || s?.cardTitle === name,
    );
    let cap = sg?.signatureAuthority?.amount;
    if (typeof cap !== 'number') return '—';
    let code = sg.signatureAuthority?.currency?.code;
    let value = c?.value?.amount;
    let label = formatMoney(cap, code);
    if (typeof value !== 'number') return label;
    return cap >= value
      ? `${label} · covers ${formatMoney(value, c?.value?.currency?.code)}`
      : `${label} · below ${formatMoney(value, c?.value?.currency?.code)}`;
  };

  blockColumns: Col[] = [
    {
      label: 'Order',
      kind: 'mono',
      align: 'end',
      value: (b) => b.signingOrder ?? '—',
    },
    {
      label: 'Signer',
      value: (b) =>
        [b.signerName ?? b.displayName, b.signerTitle]
          .filter(Boolean)
          .join(', ') || '—',
    },
    {
      label: 'Side',
      value: (b) => (b.isInternal ? 'Us' : (b.entityName ?? '—')),
    },
    { label: 'Authority', value: (b) => this.authorityOf(b) },
    {
      label: 'Status',
      kind: 'dot',
      value: (b) => {
        let st = b.lineStatus ?? 'pending';
        let label = SIGNATURE_BLOCK_STATUS_LABELS[st] ?? st;
        return st === 'signed' && b.signedAt
          ? `${label} ${formatDay(b.signedAt)}`
          : label;
      },
      tone: (b) => {
        let st = b.lineStatus ?? 'pending';
        return st === 'pending'
          ? 'warning'
          : hueTone(SIGNATURE_BLOCK_STATUS_HUE[st]);
      },
    },
  ];

  get sortedBlocks() {
    return [...this.workspaceBlocks]
      .filter(Boolean)
      .sort((a: any, b: any) => (a.signingOrder ?? 0) - (b.signingOrder ?? 0));
  }

  isCurrent = (c: any): boolean => c?.id === this.args.app.workspaceLive?.id;

  <template>
    <div class='ws'>
      <div class='ws-main'>
        {{#if @app.workspaceLive}}
          {{#let @app.workspaceLive as |c|}}
            <header class='ws-head'>
              <h2 class='ws-title'>{{c.cardTitle}}</h2>
              {{#if c.contractNumber}}<span
                  class='ws-mono'
                >{{c.contractNumber}}</span>{{/if}}
              <span class='ws-meta'>{{@app.statusLabelOf c.status}}
                {{#if c.value.amount}}·
                  {{formatMoney
                    c.value.amount
                    c.value.currency.code
                  }}{{/if}}</span>
              <span class='ws-links'>
                <Button
                  @tone='neutral'
                  @appearance='plain'
                  @size='xs'
                  {{on 'click' (fn @app.openCard c)}}
                >Open card</Button>
                <Button
                  @tone='neutral'
                  @appearance='plain'
                  @size='xs'
                  {{on 'click' this.clearWorkspace}}
                >Pick another</Button>
              </span>
            </header>

            <SubHead
              @label='Clauses, against the playbook'
              @count={{this.sortedClauses.length}}
            />
            {{#if this.sortedClauses.length}}
              <ul class='ws-clauses'>
                {{#each this.sortedClauses as |u|}}
                  <li>
                    <Item @description={{u.cardDescription}}>
                      <:title>
                        <Button
                          @tone='neutral'
                          @appearance='plain'
                          @size='xs'
                          {{on 'click' (fn @app.openCard u)}}
                        >{{u.cardTitle}}</Button>
                      </:title>
                      <:trailing>
                        <Dot
                          @tone={{this.clauseTone u}}
                          @label={{this.clauseState u}}
                        />
                      </:trailing>
                    </Item>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class='ws-empty'>{{if
                  this.workspaceDataLoading
                  'Loading clauses…'
                  'No clauses recorded on this contract.'
                }}</p>
            {{/if}}

            <SubHead
              @label='Signature blocks'
              @sub='Signing order, with each signer’s authority checked against the contract value'
            />
            {{#if this.sortedBlocks.length}}
              <CeTable
                @label='Signature blocks'
                @columns={{this.blockColumns}}
                @rows={{this.sortedBlocks}}
              />
            {{else}}
              <p class='ws-empty'>No signature blocks yet.</p>
            {{/if}}

            <div class='ws-provider'>
              {{#let (uniqueId) as |providerId|}}
                <label class='ws-cap' for={{providerId}}>Provider</label>
                <Input
                  id={{providerId}}
                  @value={{@app.signatureProvider}}
                  @onInput={{this.setProviderValue}}
                />
              {{/let}}
            </div>
            {{#let
              (uniqueId) (uniqueId) (uniqueId) (uniqueId)
              as |requestHint verifyHint executeHint generateHint|
            }}
              <div class='ws-ceremony'>
                <Button
                  @size='xs'
                  @tone='primary'
                  @appearance='accent'
                  @disabled={{@app.ceremonyBusy}}
                  aria-describedby={{requestHint}}
                  {{on 'click' this.requestSignature}}
                >Request signature</Button>
                <Button
                  @size='xs'
                  @appearance='outlined'
                  @disabled={{@app.ceremonyBusy}}
                  aria-describedby={{verifyHint}}
                  {{on 'click' this.verifySignatures}}
                >Verify signatures</Button>
                <Button
                  @size='xs'
                  @appearance='outlined'
                  @disabled={{or @app.ceremonyBusy this.workspaceDataLoading}}
                  aria-describedby={{executeHint}}
                  {{on 'click' this.executeContract}}
                >Execute contract</Button>
                <Button
                  @size='xs'
                  @appearance='outlined'
                  @disabled={{or @app.ceremonyBusy this.workspaceDataLoading}}
                  aria-describedby={{generateHint}}
                  {{on 'click' this.generateDocument}}
                >Generate document</Button>
              </div>
              <ul class='ws-hints'>
                <li id={{requestHint}}><strong>Request signature</strong>
                  moves an approved contract out for signature and sends the
                  next line in signing order, after re-checking authority.</li>
                <li id={{verifyHint}}><strong>Verify signatures</strong>
                  re-checks every authority and signing-order rule against
                  current data. It changes nothing.</li>
                <li id={{executeHint}}><strong>Execute contract</strong>
                  marks the contract signed and saves a version. It runs only
                  when every line is signed and verification is clean.</li>
                <li id={{generateHint}}><strong>Generate document</strong>
                  assembles the full agreement text.</li>
              </ul>
            {{/let}}
            {{#if @app.ceremonyProblem}}
              <Note
                @tone='danger'
                @lead='Refused.'
                @text={{@app.ceremonyProblem}}
              />
            {{else if @app.ceremonyNote}}
              <Note
                @tone={{if @app.ceremonyFindings.length 'warning' 'success'}}
                @lead={{@app.ceremonyNote}}
              />
            {{/if}}
            {{#each @app.ceremonyFindings as |f|}}
              <p class='ws-finding'>{{f}}</p>
            {{/each}}
          {{/let}}
        {{else}}
          <header class='ws-head'>
            <h2 class='ws-title'>Pick a contract</h2>
          </header>
          <p class='ws-empty'>Pick a contract on the right to review it clause
            by clause and run its signature ceremony. Legal Home and the
            Repository also land here.</p>
        {{/if}}
      </div>

      {{#let (uniqueId) as |switchHeadId|}}
        <section class='ws-side' aria-labelledby={{switchHeadId}}>
          <h2 class='ws-title ws-side-head' id={{switchHeadId}}>Switch contract</h2>
          <ul class='ws-switch'>
            {{#each @app.contracts as |other|}}
              <li>
                <Item aria-current={{if (this.isCurrent other) 'true'}}>
                  <:title>
                    <Button
                      @tone='neutral'
                      @appearance='plain'
                      @size='xs'
                      {{on 'click' (fn @app.openInWorkspace other)}}
                    >{{other.cardTitle}}</Button>
                  </:title>
                  <:trailing>
                    <Dot
                      @tone={{@app.statusToneOf other.status}}
                      @label={{@app.statusLabelOf other.status}}
                    />
                  </:trailing>
                </Item>
              </li>
            {{else}}
              <li class='ws-empty'>No contracts yet.</li>
            {{/each}}
          </ul>
        </section>
      {{/let}}
    </div>
    <style scoped>
      .ws {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(16rem, 19rem);
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
      }
      .ws-main {
        min-inline-size: 0;
        overflow-x: auto;
      }
      .ws-head {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        gap: var(--boxel-sp-2xs);
        padding: var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
      }
      .ws-title {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .ws-mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .ws-meta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .ws-links {
        display: flex;
        gap: var(--boxel-sp-xs);
        margin-inline-start: auto;
      }
      .ws-clauses,
      .ws-switch {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .ws-clauses li,
      .ws-switch li {
        border-bottom: 1px solid var(--border);
      }
      .ws-switch [aria-current='true'] {
        background: var(--muted);
      }
      .ws-cap {
        font-family: var(--font-mono);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .ws-provider {
        display: grid;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
        border-bottom: 1px solid var(--border);
      }
      .ws-ceremony {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
        gap: var(--boxel-sp-2xs);
        padding: var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
      }
      .ws-hints {
        display: grid;
        gap: var(--boxel-sp-4xs);
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-xs)
          var(--boxel-sp-lg);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .ws-finding {
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
      }
      .ws-side {
        border-inline-start: 1px solid var(--border);
      }
      .ws-side-head {
        padding: var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
      }
      .ws-empty {
        margin: 0;
        padding: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
      @container cx-app (width < 52rem) {
        .ws {
          grid-template-columns: minmax(0, 1fr);
        }
        .ws-side {
          border-inline-start: 0;
          border-top: 1px solid var(--border);
        }
      }
    </style>
  </template>
}
