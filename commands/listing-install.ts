import type {
  ListingPathResolver,
  ModuleResource,
  LooseCardResource,
  RealmResourceIdentifier,
} from '@cardstack/runtime-common';
import {
  Command,
  type ResolvedCodeRef,
  join,
  planModuleInstall,
  planInstanceInstall,
  PlanBuilder,
  extractRelationshipIds,
  type Relationship,
} from '@cardstack/runtime-common';
import { logger } from '@cardstack/runtime-common';
import type {
  CopyInstanceMeta,
  CopyModuleMeta,
} from '@cardstack/runtime-common';

import type { CardDef } from 'https://cardstack.com/base/card-api';
import type * as BaseCommandModule from 'https://cardstack.com/base/command';

import { getLoaderService, loadCommandModule } from './utils';

import ExecuteAtomicOperationsCommand from '@cardstack/boxel-host/commands/execute-atomic-operations';
import FetchCardJsonCommand from '@cardstack/boxel-host/commands/fetch-card-json';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import ReadBinaryFileCommand from '@cardstack/boxel-host/commands/read-binary-file';
import ReadSourceCommand from '@cardstack/boxel-host/commands/read-source';
import WriteBinaryFileCommand from '@cardstack/boxel-host/commands/write-binary-file';
import SerializeCardCommand from '@cardstack/boxel-host/commands/serialize-card';
import ValidateRealmCommand from '@cardstack/boxel-host/commands/validate-realm';

import type { Listing } from '@cardstack/catalog/catalog-app/listing/listing';

const log = logger('catalog:install');

export type InstanceOperation = {
  op: 'add';
  href: string;
  data: LooseCardResource;
};

// file-meta resources are JSON projections of binary files in the source
// realm — they carry no bytes, and the atomic endpoint only accepts
// card/source types. Returning undefined here signals the caller to copy the
// underlying binary via a per-file octet-stream write instead; the parent
// card's relative links.self then resolves to that copy inside the install
// directory.
export function buildInstanceOperation(
  doc: unknown,
  copyInstanceMeta: CopyInstanceMeta,
  realmIdentifier: string,
): InstanceOperation | undefined {
  if (
    !doc ||
    typeof doc !== 'object' ||
    !('data' in doc) ||
    !(doc as { data: unknown }).data ||
    typeof (doc as { data: unknown }).data !== 'object'
  ) {
    throw new Error('We are only expecting single documents returned');
  }
  let data = (doc as { data: { type?: string } }).data;
  if (data.type === 'file-meta') {
    return undefined;
  }
  delete (doc as any).data.id;
  delete (doc as any).included;
  let cardResource = (doc as any).data as LooseCardResource;
  let href = join(realmIdentifier, copyInstanceMeta.lid) + '.json';
  return { op: 'add', href, data: cardResource };
}

export default class ListingInstallCommand extends Command<
  typeof BaseCommandModule.ListingInstallInput,
  typeof BaseCommandModule.ListingInstallResult
> {
  description =
    'Install catalog listing with bringing them to code mode, and then remixing them via AI';

  async getInputType() {
    let commandModule = await loadCommandModule(this.commandContext);
    const { ListingInstallInput } = commandModule;
    return ListingInstallInput;
  }

  requireInputFields = ['realm', 'listing'];

  protected async run(
    input: BaseCommandModule.ListingInstallInput,
  ): Promise<BaseCommandModule.ListingInstallResult> {
    let { realm, listing: listingInput } = input;

    let { realmIdentifier: realmUrl } = await new ValidateRealmCommand(
      this.commandContext,
    ).execute({ realmIdentifier: realm });

    // this is intentionally to type because base command cannot interpret Listing type from catalog
    const listing = listingInput as Listing;

    // seed examples first so the primary example stays the first planned instance
    let hasPrimaryExamples = (listing.examples?.length ?? 0) > 0;
    let examplesToInstall = [
      ...(listing.examples ?? []),
      ...(listing.supportingCards ?? []),
    ];
    if (examplesToInstall.length) {
      examplesToInstall = await this.expandInstances(examplesToInstall);
    }

    // side-effects
    let exampleCardId: string | undefined;
    let selectedCodeRef: ResolvedCodeRef | undefined;
    let skillCardId: string | undefined;

    let virtualNetwork = getLoaderService(
      this.commandContext,
    ).loader.getVirtualNetwork()!;
    const builder = new PlanBuilder(realmUrl, listing, virtualNetwork);

    builder
      .addIf(listing.specs?.length > 0, (resolver: ListingPathResolver) => {
        let r = planModuleInstall(listing.specs, resolver, virtualNetwork);
        selectedCodeRef = r.modulesCopy[0].targetCodeRef;
        return r;
      })
      .addIf(examplesToInstall?.length > 0, (resolver: ListingPathResolver) => {
        let r = planInstanceInstall(
          examplesToInstall,
          resolver,
          virtualNetwork,
        );
        if (hasPrimaryExamples) {
          let firstInstance = r.instancesCopy[0];
          exampleCardId = join(realmUrl, firstInstance.lid);
          selectedCodeRef = firstInstance.targetCodeRef;
        }
        return r;
      })
      .addIf(listing.skills?.length > 0, (resolver: ListingPathResolver) => {
        let r = planInstanceInstall(listing.skills, resolver, virtualNetwork);
        skillCardId = join(realmUrl, r.instancesCopy[0].lid);
        return r;
      });

    const plan = builder.build();

    let sourceOperations = await Promise.all(
      plan.modulesToInstall.map(async (moduleMeta: CopyModuleMeta) => {
        let { sourceModule, targetModule } = moduleMeta;
        let { content } = await new ReadSourceCommand(
          this.commandContext,
        ).execute({ path: sourceModule });
        let moduleResource: ModuleResource = {
          type: 'source',
          attributes: { content },
          meta: {},
        };
        let href = targetModule + '.gts';
        return { op: 'add' as const, href, data: moduleResource };
      }),
    );

    let binaryCopies: { sourceUrl: string; targetPath: string }[] = [];
    let instanceOperations = await Promise.all(
      plan.instancesCopy.map(async (copyInstanceMeta: CopyInstanceMeta) => {
        let { sourceCard, lid } = copyInstanceMeta;
        let { document: doc } = await new FetchCardJsonCommand(
          this.commandContext,
        ).execute({ cardIdentifier: sourceCard.id });
        let operation = buildInstanceOperation(doc, copyInstanceMeta, realmUrl);
        if (!operation) {
          binaryCopies.push({ sourceUrl: sourceCard.id, targetPath: lid });
        }
        return operation;
      }),
    );

    // Binaries are written before the atomic batch so installed cards resolve
    // their file links as soon as they index. There is no rollback: an atomic
    // failure leaves these copies orphaned in the fresh install directory.
    for (let { sourceUrl, targetPath } of binaryCopies) {
      let { base64Content, contentType } = await new ReadBinaryFileCommand(
        this.commandContext,
      ).execute({ fileIdentifier: sourceUrl });
      await new WriteBinaryFileCommand(this.commandContext).execute({
        realm: realmUrl,
        path: targetPath,
        base64Content,
        contentType,
      });
    }

    const operations = [
      ...sourceOperations,
      ...instanceOperations.filter(
        (op): op is InstanceOperation => op !== undefined,
      ),
    ];

    let atomicResults;
    try {
      ({ results: atomicResults } = await new ExecuteAtomicOperationsCommand(
        this.commandContext,
      ).execute({ realmIdentifier: realmUrl, operations }));
    } catch (e: any) {
      if (
        typeof e?.message === 'string' &&
        e.message.includes('filter refers to a nonexistent type')
      ) {
        throw new Error(
          'Please click "Update Specs" on the listing and make sure all specs are linked.',
        );
      }
      throw e;
    }

    let writtenFiles = (atomicResults as Array<Record<string, any>>)
      .map((r) => r.data?.id)
      .filter(Boolean);
    log.debug('=== Final Results ===');
    log.debug(JSON.stringify(writtenFiles, null, 2));

    let commandModule = await loadCommandModule(this.commandContext);
    const { ListingInstallResult } = commandModule;
    return new ListingInstallResult({
      selectedCodeRef,
      exampleCardId,
      skillCardId,
    });
  }

  // Walk relationships by fetching linked cards and enqueueing their ids.
  private async expandInstances(instances: CardDef[]): Promise<CardDef[]> {
    let virtualNetwork = getLoaderService(
      this.commandContext,
    ).loader.getVirtualNetwork()!;
    let instancesById = new Map<string, CardDef>();
    let visited = new Set<string>();
    let queue: string[] = instances
      .map((instance) => instance.id)
      .filter((id): id is RealmResourceIdentifier => typeof id === 'string');

    // - Queue of ids to traverse; visited prevents duplicate relationship ids.
    // - Each loop extracts relationship ids and enqueues them, so we descend
    //   through the relationship graph breadth-first.
    while (queue.length > 0) {
      let id = queue.shift();
      if (!id || visited.has(id)) {
        continue;
      }
      visited.add(id);

      let instance = (await new GetCardCommand(this.commandContext).execute({
        cardId: id,
      })) as CardDef;
      instancesById.set(instance.id ?? id, instance);

      let { json: serialized } = await new SerializeCardCommand(
        this.commandContext,
      ).execute({ cardId: id });
      let baseUrl: string = (serialized as any)?.data?.id ?? id;
      let relationships: Record<string, Relationship | Relationship[]> =
        (serialized as any)?.data?.relationships ?? {};

      let entries = Object.entries(relationships);
      log.debug(`Relationships for ${id}:`);
      if (entries.length === 0) {
        log.debug('[]');
        continue;
      }
      let summary = entries.map(([field, rel]) => {
        let rels = Array.isArray(rel) ? rel : [rel];
        return {
          field,
          relationships: rels.map((relationship) => ({
            links: relationship.links ?? null,
            data: relationship.data ?? null,
          })),
        };
      });
      log.debug(JSON.stringify(summary, null, 2));

      for (let rel of Object.values(relationships)) {
        let rels = Array.isArray(rel) ? rel : [rel];
        for (let relationship of rels) {
          let relatedIds = extractRelationshipIds(
            relationship,
            baseUrl,
            virtualNetwork,
          );
          for (let relatedId of relatedIds) {
            if (!visited.has(relatedId)) {
              queue.push(relatedId);
            }
          }
        }
      }
    }

    return [...instancesById.values()];
  }
}
