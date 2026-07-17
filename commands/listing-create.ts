import type {
  LooseSingleCardDocument,
  ResolvedCodeRef,
} from '@cardstack/runtime-common';
import {
  Command,
  isCardInstance,
  SupportedMimeType,
  isFieldDef,
  isResolvedCodeRef,
  trimExecutableExtension,
  loadCardDef,
  getAncestor,
  identifyCard,
  rri,
} from '@cardstack/runtime-common';

import type * as CardAPI from 'https://cardstack.com/base/card-api';
import type * as BaseCommandModule from 'https://cardstack.com/base/command';

import type { Spec } from 'https://cardstack.com/base/spec';

import { loadCommandModule, getLoaderService } from './utils';

import AuthedFetchCommand from '@cardstack/boxel-host/commands/authed-fetch';
import CreateSpecCommand from '@cardstack/boxel-host/commands/create-specs';
import GenerateThumbnailCommand from '@cardstack/boxel-host/commands/generate-thumbnail';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import GetCatalogRealmIdentifiersCommand from '@cardstack/boxel-host/commands/get-catalog-realm-identifiers';
import GetRealmOfResourceIdentifierCommand from '@cardstack/boxel-host/commands/get-realm-of-resource-identifier';
import OneShotLlmRequestCommand from '@cardstack/boxel-host/commands/one-shot-llm-request';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import SanitizeModuleListCommand from '@cardstack/boxel-host/commands/sanitize-module-list';
import ScreenshotCardCommand from '@cardstack/boxel-host/commands/screenshot-card';
import SearchAndChooseCommand from '@cardstack/boxel-host/commands/search-and-choose';
import { SearchCardsByTypeAndTitleCommand } from '@cardstack/boxel-host/commands/search-cards';
import StoreAddCommand from '@cardstack/boxel-host/commands/store-add';

type ListingType = 'card' | 'skill' | 'theme' | 'field' | 'component';

const BASE_CARD_API_MODULE = 'https://cardstack.com/base/card-api';
const BASE_SKILL_MODULE = 'https://cardstack.com/base/skill';
const GLIMMER_COMPONENT_MODULE = '@glimmer/component';

const listingSubClass: Record<ListingType, string> = {
  card: 'CardListing',
  skill: 'SkillListing',
  theme: 'ThemeListing',
  field: 'FieldListing',
  component: 'ComponentListing',
};

export default class ListingCreateCommand extends Command<
  typeof BaseCommandModule.ListingCreateInput,
  typeof BaseCommandModule.ListingCreateResult
> {
  static actionVerb = 'Create';
  description =
    'Create a catalog listing for a card, field, skill, theme, or component';

  private async getCatalogRealm(): Promise<string> {
    const { realmIdentifiers: urls } =
      await new GetCatalogRealmIdentifiersCommand(
        this.commandContext,
      ).execute();
    let catalogRealm = urls.find((realm: string) =>
      realm.endsWith('/catalog/'),
    );
    if (!catalogRealm) {
      throw new Error(
        'Catalog realm not found. No available realm URL ends with /catalog/',
      );
    }
    return catalogRealm;
  }

  async getInputType() {
    let commandModule = await loadCommandModule(this.commandContext);
    const { ListingCreateInput } = commandModule;
    return ListingCreateInput;
  }

  requireInputFields = ['codeRef', 'targetRealm'];

  private async sanitizeModuleList(
    modulesToCreate: Iterable<string>,
  ): Promise<string[]> {
    const { moduleIdentifiers: moduleUrls } =
      await new SanitizeModuleListCommand(this.commandContext).execute({
        moduleIdentifiers: Array.from(modulesToCreate),
      });
    return moduleUrls;
  }

  protected async run(
    input: BaseCommandModule.ListingCreateInput,
  ): Promise<BaseCommandModule.ListingCreateResult> {
    let { openCardIds, codeRef, targetRealm } = input;
    // tolerate a base ListingCreateInput that predates supportingCardIds
    let explicitSupportingCardIds = (input as { supportingCardIds?: string[] })
      .supportingCardIds;

    if (!codeRef) {
      throw new Error('codeRef is required');
    }
    if (!isResolvedCodeRef(codeRef)) {
      throw new Error('codeRef must be a ResolvedCodeRef with module and name');
    }
    if (!targetRealm) {
      throw new Error('Target Realm is required');
    }
    let cardDef: CardAPI.BaseDefConstructor | undefined;
    try {
      cardDef = await loadCardDef(codeRef, {
        loader: getLoaderService(this.commandContext).loader,
      });
    } catch {
      // leave undefined; downstream falls back appropriately
    }
    let listingType = await this.guessListingType(codeRef, cardDef);
    const displayName = (cardDef as any)?.displayName ?? codeRef.name;
    const catalogRealm = await this.getCatalogRealm();

    const classified = await this.classifyOpenCards(openCardIds, codeRef);
    const exampleCardIds = classified.exampleCardIds;
    // explicit supporting cards are taken verbatim (no type check); a card
    // also picked as an example stays an example
    const supportingCardIds = [
      ...new Set([
        ...classified.supportingCardIds,
        ...(explicitSupportingCardIds ?? []),
      ]),
    ].filter((id) => !exampleCardIds.includes(id));

    let relationships: Record<string, { links: { self: string } }> = {};
    exampleCardIds.forEach((id, index) => {
      relationships[`examples.${index}`] = { links: { self: id } };
    });
    supportingCardIds.forEach((id, index) => {
      relationships[`supportingCards.${index}`] = { links: { self: id } };
    });

    const listingDoc: LooseSingleCardDocument = {
      data: {
        type: 'card',
        relationships,
        meta: {
          adoptsFrom: {
            module: rri(`${catalogRealm}catalog-app/listing/listing`),
            name: listingSubClass[listingType],
          },
        },
      },
    };
    const listing = await new StoreAddCommand(this.commandContext).execute({
      document: listingDoc,
      realm: targetRealm,
    });

    const commandModule = await loadCommandModule(this.commandContext);
    const listingCard = listing as CardAPI.CardDef;
    const firstExampleCardId = exampleCardIds[0];

    const examplePromise = this.autoLinkExample(
      listingCard,
      codeRef,
      exampleCardIds,
    );

    const backgroundTasks = [
      {
        name: 'autoPatchName',
        promise: this.autoPatchName(listingCard, codeRef, displayName),
      },
      {
        name: 'autoPatchSummary',
        promise: this.autoPatchSummary(listingCard, codeRef, displayName),
      },
      {
        name: 'autoLinkTag',
        promise: this.autoLinkTag(listingCard, codeRef, displayName),
      },
      {
        name: 'autoLinkCategory',
        promise: this.autoLinkCategory(listingCard, codeRef, displayName),
      },
      { name: 'autoLinkLicense', promise: this.autoLinkLicense(listingCard) },
      { name: 'autoLinkExample', promise: examplePromise },
      {
        name: 'autoScreenshotExample',
        promise: examplePromise.then(() =>
          this.autoScreenshotExample(listingCard),
        ),
      },
      {
        name: 'autoGenerateThumbnail',
        promise: this.autoGenerateThumbnail(
          listingCard,
          displayName,
          targetRealm,
        ),
      },
      {
        name: 'linkSpecs',
        promise: this.linkSpecs(
          listingCard,
          targetRealm,
          firstExampleCardId ?? codeRef?.module,
          codeRef.module,
          codeRef,
        ),
      },
    ];

    const backgroundWork = Promise.allSettled(
      backgroundTasks.map((t) => t.promise),
    ).then((results) => {
      results.forEach((result, i) => {
        if (result.status === 'rejected') {
          console.warn(
            `Background autopatch failed [${backgroundTasks[i].name}]:`,
            result.reason,
          );
        }
      });
    });

    const { ListingCreateResult } = commandModule;
    const result = new ListingCreateResult({ listing });
    (result as any).backgroundWork = backgroundWork;
    return result;
  }

  // Open cards that are instances of the listed type become examples; other
  // open cards (e.g. data a query-based example depends on) become
  // supportingCards, which install but don't render in the listing detail.
  private async classifyOpenCards(
    openCardIds: string[] | undefined,
    codeRef: ResolvedCodeRef,
  ): Promise<{ exampleCardIds: string[]; supportingCardIds: string[] }> {
    const classified = await Promise.all(
      (openCardIds ?? []).map(async (id) => {
        try {
          const instance = await new GetCardCommand(
            this.commandContext,
          ).execute({ cardId: id });
          return {
            id,
            isExample:
              isCardInstance(instance) &&
              this.isInstanceOfCodeRef(instance as CardAPI.CardDef, codeRef),
          };
        } catch {
          return { id, isExample: true };
        }
      }),
    );
    return {
      exampleCardIds: classified.filter((c) => c.isExample).map((c) => c.id),
      supportingCardIds: classified
        .filter((c) => !c.isExample)
        .map((c) => c.id),
    };
  }

  private isInstanceOfCodeRef(
    instance: CardAPI.CardDef,
    codeRef: ResolvedCodeRef,
  ): boolean {
    let targetModule: string;
    try {
      targetModule = trimExecutableExtension(rri(new URL(codeRef.module).href));
    } catch {
      return false;
    }
    let current: CardAPI.BaseDefConstructor | undefined =
      instance.constructor as CardAPI.BaseDefConstructor;
    while (current) {
      const ref = identifyCard(current);
      if (ref && !('type' in ref) && ref.name === codeRef.name) {
        try {
          if (
            trimExecutableExtension(rri(new URL(ref.module).href)) ===
            targetModule
          ) {
            return true;
          }
        } catch {
          // unresolvable ancestor module; keep walking
        }
      }
      current = getAncestor(current) ?? undefined;
    }
    return false;
  }

  private async guessListingType(
    codeRef: ResolvedCodeRef,
    cardDef: CardAPI.BaseDefConstructor | undefined,
  ): Promise<ListingType> {
    if (cardDef) {
      if (isFieldDef(cardDef)) {
        return 'field';
      }
      if (this.isAncestor(cardDef, BASE_CARD_API_MODULE, 'Theme')) {
        return 'theme';
      }
      if (this.isAncestor(cardDef, BASE_SKILL_MODULE, 'Skill')) {
        return 'skill';
      }
      return 'card';
    }
    // Not a card/field def — it may be a Glimmer component. loadCardDef can't
    // classify those, so check the export against the shimmed GlimmerComponent
    // base at runtime.
    if (await this.isComponentCodeRef(codeRef)) {
      return 'component';
    }
    return 'card';
  }

  private async isComponentCodeRef(codeRef: ResolvedCodeRef): Promise<boolean> {
    try {
      let loader = getLoaderService(this.commandContext).loader;
      let [mod, glimmer] = await Promise.all([
        loader.import<Record<string, unknown>>(codeRef.module),
        loader.import<{ default: unknown }>(GLIMMER_COMPONENT_MODULE),
      ]);
      // codeRef.name may be the export name ('default') or the class's local
      // name (a default-exported component is referenced by its local name),
      // so fall back to the module's default export.
      let exported = mod?.[codeRef.name] ?? mod?.default;
      let GlimmerComponent = glimmer?.default as
        | (abstract new (...args: any[]) => unknown)
        | undefined;
      return (
        typeof exported === 'function' &&
        typeof GlimmerComponent === 'function' &&
        (exported === GlimmerComponent ||
          exported.prototype instanceof GlimmerComponent)
      );
    } catch {
      return false;
    }
  }

  private isAncestor(
    cardDef: CardAPI.BaseDefConstructor,
    targetModule: string,
    targetName: string,
  ): boolean {
    let current: CardAPI.BaseDefConstructor | undefined = cardDef;
    while (current) {
      const ref = identifyCard(current);
      if (
        ref &&
        !('type' in ref) &&
        ref.module === targetModule &&
        ref.name === targetName
      ) {
        return true;
      }
      current = getAncestor(current) ?? undefined;
    }
    return false;
  }

  private async linkSpecs(
    listing: CardAPI.CardDef,
    targetRealm: string,
    resourceUrl: string, // can be module or card instance id
    moduleUrl: string, // the module URL of the card type being listed
    codeRef: ResolvedCodeRef, // the specific export being listed
  ): Promise<Spec[]> {
    const { realmIdentifier: resourceRealmUrl } =
      await new GetRealmOfResourceIdentifierCommand(
        this.commandContext,
      ).execute({ resourceIdentifier: resourceUrl });
    const resourceRealm = resourceRealmUrl || targetRealm;
    const depUrl = `${resourceRealm}_dependencies?url=${encodeURIComponent(resourceUrl)}`;
    const { ok, body: jsonApiResponse } = await new AuthedFetchCommand(
      this.commandContext,
    ).execute({ url: depUrl, acceptHeader: SupportedMimeType.JSONAPI });

    if (!ok) {
      console.warn('Failed to fetch dependencies for specs');
      (listing as any).specs = [];
      return [];
    }

    // Collect all modules (main + dependencies). Deduplication happens in sanitizeModuleList().
    // The _dependencies endpoint excludes the queried resource itself, so we
    // explicitly include the module URL to ensure a spec is created for it.
    const modulesToCreate: string[] = [moduleUrl];

    (
      jsonApiResponse as {
        data?: Array<{
          attributes?: { dependencies?: string[] };
        }>;
      }
    ).data?.forEach((entry) => {
      if (entry.attributes?.dependencies) {
        modulesToCreate.push(...entry.attributes.dependencies);
      }
    });

    const sanitizedModules = await this.sanitizeModuleList(modulesToCreate);

    // Create specs for all unique modules
    const uniqueSpecsById = new Map<string, Spec>();

    if (sanitizedModules.length > 0) {
      const createSpecCommand = new CreateSpecCommand(this.commandContext);
      const normalizedModuleUrl = trimExecutableExtension(
        rri(new URL(moduleUrl).href),
      );
      const specResults = await Promise.all(
        sanitizedModules.map((module) => {
          // For the main module, use the specific codeRef (with export name) so
          // only the listed export gets a spec, not every export in the file.
          // Normalize both sides before comparing — _dependencies can return
          // URLs with executable extensions (e.g. .gts) while moduleUrl/codeRef.module
          // is often extensionless, so a bare string comparison would create
          // duplicate specs for the same source file.
          const normalizedModule = trimExecutableExtension(
            rri(new URL(module).href),
          );
          const input =
            normalizedModule === normalizedModuleUrl
              ? { codeRef, targetRealm, autoGenerateReadme: true }
              : { module, targetRealm, autoGenerateReadme: true };
          return createSpecCommand.execute(input).catch((e: unknown) => {
            console.warn('Failed to create spec(s) for', module, e);
            return undefined;
          });
        }),
      );

      specResults.forEach((result) => {
        result?.specs?.forEach((spec) => {
          if (spec?.id) {
            uniqueSpecsById.set(spec.id, spec);
          }
        });
      });
    }

    const specs = Array.from(uniqueSpecsById.values());
    (listing as any).specs = specs;
    return specs;
  }

  // --- Linking helpers now use SearchAndChooseCommand ---
  private async chooseCards(
    params: {
      candidateTypeCodeRef: ResolvedCodeRef;
      sourceContextCodeRef?: ResolvedCodeRef;
    },
    opts?: {
      max?: number;
      additionalSystemPrompt?: string;
    },
  ) {
    const command = new SearchAndChooseCommand(this.commandContext);
    const result = await command.execute({
      candidateTypeCodeRef: params.candidateTypeCodeRef,
      sourceContextCodeRef: params.sourceContextCodeRef,
      max: opts?.max,
      additionalSystemPrompt: opts?.additionalSystemPrompt,
    });
    return result.selectedCards ?? [];
  }

  private async autoPatchName(
    listing: CardAPI.CardDef,
    codeRef: ResolvedCodeRef,
    displayName: string,
  ) {
    const name = await this.getStringPatch({
      codeRef,
      systemPrompt:
        'You are a concise and accurate summarization system. You read a Cardstack card/field definition source file and create a concise catalog listing title. Respond ONLY with the title text—no quotes, no JSON, no markdown, and no extra commentary.',
      userPrompt: [
        `Generate a catalog listing title for the ${displayName} definition referenced by:`,
        `- module: ${codeRef.module}`,
        `- exportName: ${codeRef.name}`,
        `Use ONLY the attached module source shown below (the file content).`,
        `Focus on the export named "${codeRef.name}" (ignore other exports).`,
      ].join('\n'),
    });
    if (name) {
      (listing as any).name = name;
    }
  }

  private async autoPatchSummary(
    listing: CardAPI.CardDef,
    codeRef: ResolvedCodeRef,
    displayName: string,
  ) {
    const summary = await this.getStringPatch({
      codeRef,
      systemPrompt:
        'You are a concise and accurate summarization system. You read a Cardstack card/field definition source file and write a concise spec-style summary. Output ONLY the summary text—no quotes, no JSON, no markdown, and no extra commentary.',
      userPrompt: [
        `Generate a README-style catalog listing summary for the ${displayName} definition referenced by:`,
        `- module: ${codeRef.module}`,
        `- exportName: ${codeRef.name}`,
        `Use ONLY the attached module source shown below (the file content).`,
        `Focus on the export named "${codeRef.name}" (ignore other exports).`,
        `Focus on what this listing (app/card/field/skill/theme) does and its primary purpose. Avoid implementation details and marketing fluff.`,
      ].join('\n'),
    });
    if (summary) {
      (listing as any).summary = summary;
    }
  }

  private async autoLinkExample(
    listing: CardAPI.CardDef,
    codeRef: ResolvedCodeRef,
    openCardIds?: string[],
  ) {
    const existingExamples = Array.isArray((listing as any).examples)
      ? ((listing as any).examples as CardAPI.CardDef[])
      : [];
    const uniqueById = new Map<string, CardAPI.CardDef>();
    const addCard = (card?: CardAPI.CardDef) => {
      if (!card || typeof card.id !== 'string') {
        return;
      }
      if (uniqueById.has(card.id)) {
        return;
      }
      uniqueById.set(card.id, card);
    };

    for (const existing of existingExamples) {
      addCard(existing);
    }

    if (openCardIds && openCardIds.length > 0) {
      await Promise.all(
        openCardIds.map(async (openCardId) => {
          try {
            const instance = await new GetCardCommand(
              this.commandContext,
            ).execute({ cardId: openCardId });
            if (isCardInstance(instance)) {
              addCard(instance as CardAPI.CardDef);
            } else {
              console.warn(
                'autoLinkExample: openCardId is not a card instance',
                { openCardId },
              );
            }
          } catch (error) {
            console.warn('autoLinkExample: failed to load openCardId', {
              openCardId,
              error,
            });
          }
        }),
      );
    } else {
      // If no openCardIds were provided, attempt to find any existing instance of this type.
      try {
        const search = new SearchCardsByTypeAndTitleCommand(
          this.commandContext,
        );
        const result = await search.execute({ type: codeRef });
        const instances = (result as any)?.instances as unknown;
        if (Array.isArray(instances)) {
          const first = instances.find(
            (c: any) => c && typeof c.id === 'string' && isCardInstance(c),
          );
          if (first) {
            addCard(first as CardAPI.CardDef);
          }
        }
      } catch (error) {
        console.warn(
          'autoLinkExample: failed to search for an example instance',
          { codeRef, error },
        );
      }
    }

    // Only auto-fill additional examples when the user didn't explicitly choose
    const userExplicitlyChose = openCardIds && openCardIds.length > 0;
    const MAX_EXAMPLES = 4;
    if (
      !userExplicitlyChose &&
      codeRef &&
      uniqueById.size > 0 &&
      uniqueById.size < MAX_EXAMPLES
    ) {
      try {
        const existingIds = Array.from(uniqueById.keys());
        const additionalExamples = await this.chooseCards(
          {
            candidateTypeCodeRef: codeRef,
          },
          {
            max: Math.max(1, MAX_EXAMPLES - existingIds.length),
            additionalSystemPrompt: [
              'Prefer examples that showcase common or high-impact use cases.',
              existingIds.length
                ? `Do not include any id already linked: ${existingIds.join(', ')}.`
                : '',
              'Return [] if nothing relevant is found.',
            ]
              .filter(Boolean)
              .join(' '),
          },
        );
        for (const card of additionalExamples) {
          addCard(card as CardAPI.CardDef);
        }
      } catch (error) {
        console.warn('Failed to auto-link additional examples', {
          codeRef,
          error,
        });
      }
    }
    (listing as any).examples = Array.from(uniqueById.values());
  }

  private async autoScreenshotExample(listing: CardAPI.CardDef) {
    if (!listing.id) {
      return;
    }
    const examples = Array.isArray((listing as any).examples)
      ? ((listing as any).examples as CardAPI.CardDef[])
      : [];
    const firstExample = examples[0];
    if (!firstExample?.id) {
      return;
    }

    let imageDefUrl: string | undefined;
    try {
      const result = await new ScreenshotCardCommand(
        this.commandContext,
      ).execute({ card: firstExample, format: 'isolated' });
      imageDefUrl = (result as any)?.imageDefUrl;
    } catch (error) {
      console.warn('autoScreenshotExample: screenshot failed', {
        exampleId: firstExample.id,
        error,
      });
      return;
    }
    if (!imageDefUrl) {
      return;
    }

    // ImageDef is a FileDef (not a CardDef), so we can't load it via
    // GetCardCommand and assign to the in-memory array. Instead, patch the
    // listing's relationships block directly — same shape the realm uses for
    // linksTo(ImageDef) links — letting the indexer resolve the file at
    // render time.
    const existingImages = Array.isArray((listing as any).images)
      ? ((listing as any).images as unknown[])
      : [];
    const nextIndex = existingImages.length;

    try {
      const cardApiModule = await getLoaderService(
        this.commandContext,
      ).loader.import<typeof CardAPI>('https://cardstack.com/base/card-api');

      await new PatchCardInstanceCommand(this.commandContext, {
        cardType: cardApiModule.CardDef as unknown as typeof CardAPI.CardDef,
      }).execute({
        cardId: listing.id,
        patch: {
          relationships: {
            [`images.${nextIndex}`]: {
              links: { self: imageDefUrl },
            },
          },
        },
      });
    } catch (error) {
      console.warn('autoScreenshotExample: patch failed', {
        listingId: listing.id,
        imageDefUrl,
        error,
      });
    }
  }

  private async autoLinkLicense(listing: CardAPI.CardDef) {
    const catalogRealm = await this.getCatalogRealm();
    const selected = await this.chooseCards({
      candidateTypeCodeRef: {
        module: `${catalogRealm}catalog-app/listing/license`,
        name: 'License',
      } as ResolvedCodeRef,
    });
    (listing as any).license = selected[0];
  }

  private async autoLinkTag(
    listing: CardAPI.CardDef,
    codeRef: ResolvedCodeRef,
    displayName: string,
  ) {
    const catalogRealm = await this.getCatalogRealm();
    const selected = await this.chooseCards(
      {
        candidateTypeCodeRef: {
          module: `${catalogRealm}catalog-app/listing/tag`,
          name: 'Tag',
        } as ResolvedCodeRef,
        sourceContextCodeRef: codeRef,
      },
      {
        max: 1,
        additionalSystemPrompt:
          `The card type being tagged is "${displayName}". ` +
          'You are selecting from an existing list of catalog tags. ' +
          "Choose the most specific descriptive tag that describes the card's subject matter, use case, or domain. " +
          'If no tag clearly fits the subject matter, select a Source/Origin tag as a fallback (From tag pools). ' +
          'Return [] only if no appropriate tag exists.',
      },
    );
    (listing as any).tags = selected;
  }

  private async autoLinkCategory(
    listing: CardAPI.CardDef,
    codeRef: ResolvedCodeRef,
    displayName: string,
  ) {
    const catalogRealm = await this.getCatalogRealm();
    const selected = await this.chooseCards(
      {
        candidateTypeCodeRef: {
          module: `${catalogRealm}catalog-app/listing/category`,
          name: 'Category',
        } as ResolvedCodeRef,
        sourceContextCodeRef: codeRef,
      },
      {
        max: 1,
        additionalSystemPrompt:
          `The card type being categorized is "${displayName}". ` +
          'You are selecting from an existing list of catalog categories. ' +
          "Choose the most specific descriptive category that matches the card's main purpose. " +
          'Return [] if no category clearly fits.',
      },
    );
    (listing as any).categories = selected;
  }

  private async autoGenerateThumbnail(
    listing: CardAPI.CardDef,
    displayName: string,
    targetRealm: string,
  ) {
    if (!listing.id) {
      return;
    }
    const prompt = `Create a square thumbnail for "${displayName}". Top 70%: large centered flat icon (simple, bold, minimal, slightly angled/layered if needed). Bottom 30%: "${displayName}" in big, bold, uppercase sans-serif text. Style: flat vector, solid vivid background, 2–3 colors max. Icon should be white or light-colored, clean geometric shapes, highly recognizable. No gradients, no shadows, no borders, no clutter. Must be clear at small sizes.`;

    await new GenerateThumbnailCommand(this.commandContext).execute({
      prompt,
      targetRealmIdentifier: targetRealm,
      targetPath: 'ListingThumbnails',
      targetCardId: listing.id,
      cardName: displayName,
    });
  }

  private async getStringPatch(opts: {
    systemPrompt: string;
    userPrompt: string;
    codeRef?: ResolvedCodeRef;
  }): Promise<string | undefined> {
    const { systemPrompt, userPrompt, codeRef } = opts;
    const oneShot = new OneShotLlmRequestCommand(this.commandContext);
    const result = await oneShot.execute({
      ...(codeRef ? { codeRef } : {}),
      systemPrompt,
      userPrompt,
      llmModel: 'openai/gpt-4.1-nano',
    });
    if (!result.output) return undefined;
    // We don't strictly need the key now; keep signature for compatibility.
    return parseResponseToString(result.output);
  }
}

// Parse an AI response into a concise string (e.g. title/summary first line)
// - Strips markdown code fences
// - If JSON with a single string property, returns that value
// - Falls back to first non-empty line
// - Truncates to maxLength
function parseResponseToString(
  response?: string,
  maxLength: number = 1000,
): string | undefined {
  if (!response) return undefined;
  let text = response.trim();
  if (!text) return undefined;
  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      const parsed = JSON.parse(text);
      if (typeof parsed === 'string') {
        return parsed.slice(0, maxLength);
      }
      if (Array.isArray(parsed)) {
        const first = parsed.find((v) => typeof v === 'string');
        if (first) return first.slice(0, maxLength);
        return undefined;
      }
      if (parsed && typeof parsed === 'object') {
        for (const v of Object.values(parsed as any)) {
          if (typeof v === 'string' && v.trim()) {
            return v.trim().slice(0, maxLength);
          }
        }
        return undefined;
      }
    } catch {
      // ignore parse errors and fall through
    }
  }
  const firstLine = text.split(/\s*\n\s*/)[0];
  if (!firstLine) return undefined;
  return firstLine.slice(0, maxLength);
}
