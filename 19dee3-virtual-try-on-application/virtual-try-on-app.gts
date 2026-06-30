import {
  CardDef,
  Component,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import {
  codeRef,
  realmURL,
  chooseCard,
  searchEntryWireQueryFromQuery,
  type Query,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';

/* @ts-expect-error import.meta is valid ESM */
const here: string = import.meta.url;
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { task, timeout } from 'ember-concurrency';
import { eq } from '@cardstack/boxel-ui/helpers';
import { BoxelSelect } from '@cardstack/boxel-ui/components';
import Popover from '@cardstack/catalog/46f065-popover/popover';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import { GenerateTryOnCommand } from './commands/generate-try-on-command';
import { Model } from './model';
import { Garment, GARMENT_CATEGORIES } from './garment';
import { TryOnResult } from './try-on-result';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import WriteBinaryFileCommand from '@cardstack/boxel-host/commands/write-binary-file';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';

const garmentRef = codeRef(here, './garment', 'Garment');
const modelRef = codeRef(here, './model', 'Model');
const tryOnResultRef = codeRef(here, './try-on-result', 'TryOnResult');

type GenerationStatus = 'idle' | 'generating' | 'ready' | 'failed';
interface CachedResult {
  front: string;
  side?: string;
  back?: string;
}

class IsolatedTemplate extends Component<typeof VirtualTryOnApp> {
  // ── Selection ──
  @tracked modelMenuOpen = false;
  @tracked slotItems: Record<string, Garment | null> = {
    'full-body': null,
    top: null,
    bottom: null,
    shoes: null,
    outerwear: null,
    accessory: null,
  };
  @tracked dragOverSlot: string | null = null;
  // Drag carries the garment's id + category (the category comes free from the
  // section it was dragged from) — no instance is held until it's dropped.
  @tracked draggingGarmentId: string | null = null;
  @tracked draggingCategory: string | null = null;
  @tracked filterCategory = 'all';
  // Which slot's garment chooser is open (mobile-first: tap a dropzone to pick).
  @tracked chooserSlot: string | null = null;
  // Last-tapped slot (gets gold border to show "active").
  @tracked activeSlot: string | null = null;

  setSlot(key: string, g: Garment | null): void {
    const next = { ...this.slotItems, [key]: g };
    // Placing a garment clears any conflicting slot (e.g. a dress clears the
    // separate top/bottom, and vice versa) so the combo stays physically valid.
    if (g) {
      const def = this.slotDefs.find((d) => d.key === key);
      for (const c of def?.conflicts ?? []) next[c] = null;
    }
    this.slotItems = next;
  }

  // A slot is "covered" (greyed out) while a conflicting slot is filled — e.g.
  // top/bottom are covered by a full-body dress.
  isSlotDisabled = (key: string): boolean => {
    const def = this.slotDefs.find((d) => d.key === key);
    return (def?.conflicts ?? []).some((c) => !!this.slotItems[c]);
  };

  get outfitSlots(): { key: string; label: string; garment: Garment | null }[] {
    return this.slotDefs.map((d) => ({
      key: d.key,
      label: d.label,
      garment: this.slotItems[d.key] ?? null,
    }));
  }

  get filledGarments(): { slot: string; g: Garment }[] {
    return this.slotDefs
      .map((d) =>
        this.slotItems[d.key]
          ? { slot: d.key, g: this.slotItems[d.key] as Garment }
          : null,
      )
      .filter(Boolean) as { slot: string; g: Garment }[];
  }

  // ── Generation ──
  @tracked frontImageUrl: string | null = null;
  @tracked sideImageUrl: string | null = null;
  @tracked backImageUrl: string | null = null;
  @tracked generationStatus: GenerationStatus = 'idle';
  @tracked errorMessage: string | null = null;
  @tracked carouselIndex = 0;
  resultCache = new Map<string, CachedResult>();

  // ── Upload ──
  @tracked uploadMode: 'model' | 'garment' | null = null;
  @tracked capturedDataUrl: string | null = null;
  @tracked newItemName = '';

  // The slug is always derived from the typed name — words joined by `-`,
  // lowercased, with stray punctuation collapsed and edge dashes trimmed.
  get newItemSlug(): string {
    return this.newItemName
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }
  @tracked newItemCategory = '';
  @tracked uploadError: string | null = null;
  @tracked lightboxUrl: string | null = null;
  _pendingUploadMode: 'model' | 'garment' | null = null;

  // ── Static data ──
  // Placeholder slots rendered per category while garments load.
  skeletonTiles = [0, 1];
  // Category values/labels come from the Garment card so they never drift.
  get categoryOptions(): string[] {
    return GARMENT_CATEGORIES.map((c) => c.value);
  }
  get filterOptions(): string[] {
    return ['all', ...this.categoryOptions];
  }
  // One dropzone per category. `cats` lists which garment categories may drop.
  // `conflicts` lists slots that can't coexist — a full-body dress occupies the
  // torso and legs, so it's mutually exclusive with a separate top/bottom. Slot
  // keys/labels mirror GARMENT_CATEGORIES (one slot per category, same order);
  // only the app-specific conflict rules live here.
  get slotDefs(): {
    key: string;
    label: string;
    cats: string[];
    conflicts?: string[];
  }[] {
    const conflicts: Record<string, string[]> = {
      'full-body': ['top', 'bottom'],
      top: ['full-body'],
      bottom: ['full-body'],
    };
    return GARMENT_CATEGORIES.map((c) => ({
      key: c.value,
      label: c.label,
      cats: [c.value],
      conflicts: conflicts[c.value],
    }));
  }

  // ── Garment search ──
  get garmentRealms(): string[] {
    const url = this.args.model[realmURL];
    return url ? [url.href] : [];
  }

  // v2 search-entry query for one category section. The grid + chooser render
  // prerendered entries via `@context.searchResultsComponent` rather than
  // instantiating the whole palette — only the garments the user actually
  // places are hydrated (see pickGarmentById / onDrop). Scales as the catalog
  // grows.
  garmentWireQuery(category: string): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery({
        filter: { on: garmentRef, eq: { category } },
      }),
      realms: this.garmentRealms,
    };
  }

  // Live search for previously-generated results. Cache lookup queries the
  // realm directly (keyed by modelKey/garmentKey) instead of a linksToMany
  // field — so results are tied to the model, not to which app linked them.
  resultSearch = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: { type: tryOnResultRef },
      }) as Query,
    () => this.garmentRealms,
    { isLive: true },
  );

  get persistedResults(): TryOnResult[] {
    return (this.resultSearch?.instances ?? []) as TryOnResult[];
  }

  // Hydrate a single garment on demand — the grid/chooser only hold lightweight
  // search entries, so a real Garment instance is fetched (cheaply, from the
  // store) only when one is actually placed.
  async hydrateGarment(id: string): Promise<Garment | undefined> {
    const g = await (this.args as any).context?.store?.get(id);
    return g as Garment | undefined;
  }

  // Click a sidebar garment → drop it into its category slot.
  @action async pickGarmentById(id: string): Promise<void> {
    if (this.isLocked) return;
    const g = await this.hydrateGarment(id);
    if (g) this.placeGarment(g);
  }

  placeGarment(g: Garment): void {
    const cat = g.category ?? '';
    const def = this.slotDefs.find((d) => d.cats.includes(cat));
    if (!def) return;
    this.setSlot(def.key, g);
    this.clearPreview();
  }

  // ── Derived ──
  get activeModel(): Model | null {
    return this.args.model.model ?? null;
  }

  // A model only "counts" once it has a usable photo. A linked-but-photoless
  // entry is treated as no model → we show the add (+) circle instead.
  get hasUsableModel(): boolean {
    return !!this.activeModel?.photo?.resolvedUrl;
  }

  // Detection ran and found no usable full body → generation will fall back to
  // a standard body. Surface a gentle, non-blocking hint when so.
  get bodyNotDetected(): boolean {
    return (this.activeModel as any)?.bodyVisibility === 'partial';
  }

  // Body-detection notice, floated over the preview at every breakpoint. Only
  // shown when no usable full body was detected (see bodyNotDetected).
  get tipText(): string {
    return "We couldn't detect your full body in this photo — the AI will generate a standard body pose for the try-on.";
  }

  get isGenerating(): boolean {
    return this.generateOutfit.isRunning;
  }

  // The whole outfit-building UI is frozen while generating AND while a result
  // is on screen — the user must tap "Go back" (restart) to edit again.
  get isLocked(): boolean {
    return this.isGenerating || this.generationStatus === 'ready';
  }

  get showGeneratingPlaceholder(): boolean {
    return this.isGenerating && !this.frontImageUrl;
  }

  // Small status pill (top-right of the preview) telling the user which view
  // is being generated and how far along we are (front → side → back).
  get genProgress(): { label: string; step: string } | null {
    if (this.showGeneratingPlaceholder) {
      return { label: 'Front view generating', step: '1/3' };
    }
    if (this.generateAngles.isRunning) {
      if (!this.sideImageUrl) {
        return { label: 'Side view generating', step: '2/3' };
      }
      if (!this.backImageUrl) {
        return { label: 'Back view generating', step: '3/3' };
      }
    }
    return null;
  }

  // The category sections to render in the sidebar. Each section carries its
  // own v2 `search-entry` query (read in the template as `section.query`), so
  // this returns key + label + query — never garment instances. When a filter
  // is active only that section shows; otherwise every category is listed so
  // empty ones still offer their add placeholder.
  get garmentSections(): {
    key: string;
    label: string;
    query: SearchEntryWireQuery;
  }[] {
    const cats =
      this.filterCategory === 'all'
        ? this.categoryOptions
        : [this.filterCategory];
    return cats.map((key) => {
      const def = this.slotDefs.find((d) => d.key === key);
      return {
        key,
        label: def?.label ?? key,
        query: this.garmentWireQuery(key),
      };
    });
  }

  // Front / Side / Back segmented control for the result preview.
  get viewOptions(): { label: string; index: number; url: string | null }[] {
    return this.carouselSlides.map((s, i) => ({
      label: s.label,
      index: i,
      url: s.url,
    }));
  }

  get canSaveLook(): boolean {
    return this.generationStatus === 'ready' && !!this.frontImageUrl;
  }

  // "Save look": open the current view in a new tab so the user can save it.
  @action saveLook(): void {
    const url =
      this.carouselSlides[this.carouselIndex]?.url ?? this.frontImageUrl;
    if (url) this.lightboxUrl = url;
  }

  @action closeLightbox(): void {
    this.lightboxUrl = null;
  }

  // Download the currently-shown view (front/side/back) as an image file.
  // The `download` attribute is ignored for cross-origin URLs (the browser
  // navigates/opens a tab instead), so fetch the bytes and download an
  // object URL — that forces a real save regardless of the image's origin.
  downloadCurrent = task(async () => {
    const slide = this.carouselSlides[this.carouselIndex];
    const url = slide?.url ?? this.frontImageUrl;
    if (!url) return;
    const filename = `try-on-${slide?.label?.toLowerCase() ?? 'front'}.png`;
    let objectUrl: string | undefined;
    try {
      const resp = await fetch(url);
      const blob = await resp.blob();
      objectUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = objectUrl;
      a.download = filename;
      a.rel = 'noopener';
      document.body.appendChild(a);
      a.click();
      a.remove();
    } finally {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    }
  });

  // Re-run generation for the current outfit (the refresh button).
  @action regenerate(): void {
    if (this.isGenerating) return;
    this.restart();
  }

  get canGenerate(): boolean {
    return (
      !!this.activeModel && this.filledGarments.length > 0 && !this.isGenerating
    );
  }

  get canSaveUpload(): boolean {
    if (!this.capturedDataUrl || !this.newItemSlug.trim()) return false;
    if (this.uploadMode === 'garment' && !this.newItemCategory) return false;
    return true;
  }

  get carouselSlides() {
    return [
      { label: 'Front', url: this.frontImageUrl },
      { label: 'Side', url: this.sideImageUrl },
      { label: 'Back', url: this.backImageUrl },
    ];
  }

  get carouselTrackStyle(): string {
    return `transform: translateX(-${this.carouselIndex * 100}%)`;
  }

  // ── Cache ──
  get modelKey(): string {
    // Key by the model's stable id so a different model doesn't reuse the
    // wrong cached result.
    const id = (this.activeModel as any)?.id as string | undefined;
    return id ?? 'no-model';
  }

  get garmentKey(): string {
    return this.filledGarments
      .map(({ g }) => (g as any).id as string)
      .filter(Boolean)
      .sort()
      .join('|');
  }

  get cacheKey(): string {
    return `${this.modelKey}:${this.garmentKey}`;
  }

  get realmUrl(): string {
    const url = (this.args.model as any)[realmURL];
    return url ? url.href : '';
  }

  findPersistedResult(): TryOnResult | undefined {
    return this.persistedResults.find(
      (r: TryOnResult) =>
        r.modelKey === this.modelKey && r.garmentKey === this.garmentKey,
    );
  }

  // Clear the outfit and result so the user can start a fresh try-on.
  @action restart(): void {
    if (this.isGenerating) return;
    this.slotItems = {
      'full-body': null,
      top: null,
      bottom: null,
      shoes: null,
      outerwear: null,
      accessory: null,
    };
    this.clearPreview();
  }

  // Changing the outfit always resets the preview back to the model's original
  // photo. The cached result is only re-served when the user taps Try On.
  clearPreview(): void {
    this.frontImageUrl = null;
    this.sideImageUrl = null;
    this.backImageUrl = null;
    this.carouselIndex = 0;
    this.generationStatus = 'idle';
  }

  // ── Actions ──
  @action prevSlide(): void {
    this.carouselIndex = Math.max(0, this.carouselIndex - 1);
  }
  @action nextSlide(): void {
    this.carouselIndex = Math.min(2, this.carouselIndex + 1);
  }
  @action setSlide(i: number): void {
    this.carouselIndex = i;
  }

  // Drag/swipe the preview to "rotate" between front / side / back views.
  _rotateStartX: number | null = null;
  @action onRotateStart(event: Event): void {
    this._rotateStartX = (event as PointerEvent).clientX;
  }
  @action onRotateMove(event: Event): void {
    if (this._rotateStartX == null) return;
    const dx = (event as PointerEvent).clientX - this._rotateStartX;
    const threshold = 42;
    if (dx <= -threshold) {
      this.nextSlide();
      this._rotateStartX = (event as PointerEvent).clientX;
    } else if (dx >= threshold) {
      this.prevSlide();
      this._rotateStartX = (event as PointerEvent).clientX;
    }
  }
  @action onRotateEnd(): void {
    this._rotateStartX = null;
  }
  @action setFilter(cat: string): void {
    this.filterCategory = cat;
  }

  @action removeSlot(slot: string, event?: Event): void {
    event?.stopPropagation();
    if (this.isLocked) return;
    this.setSlot(slot, null);
    this.clearPreview();
  }

  // ── Garment chooser (tap a dropzone → pick a garment) ──
  @action openChooser(slot: string): void {
    if (this.isLocked) return;
    this.chooserSlot = slot;
    this.activeSlot = slot;
  }

  @action closeChooser(): void {
    this.chooserSlot = null;
  }

  get chooserDef(): { key: string; label: string; cats: string[] } | undefined {
    return this.slotDefs.find((d) => d.key === this.chooserSlot);
  }

  get chooserLabel(): string {
    return this.chooserDef?.label ?? '';
  }

  get isChooserOpen(): boolean {
    return this.chooserSlot != null;
  }

  get isUploadOpen(): boolean {
    return this.uploadMode != null;
  }

  // The picker / chooser sit BEHIND the upload form when it's open. Two
  // focus-trapping popovers fight over focus, so the background one releases
  // its trap while the upload Popover (always topmost) owns focus.
  get backgroundTrapsFocus(): boolean {
    return !this.isUploadOpen;
  }

  // CSS selector for the open slot's tile — the chooser Popover bridges its
  // theme tokens from here and restores focus to it on close.
  get chooserAnchor(): string {
    return `[data-bx-popover-anchor='vto-slot-${this.chooserSlot ?? ''}']`;
  }

  // v2 search query for the garments that can drop into the open slot.
  // Undefined when no chooser is open → the search component stays idle.
  get chooserQuery(): SearchEntryWireQuery | undefined {
    const def = this.chooserDef;
    if (!def) return undefined;
    // Slots map to a single category, so the first (only) cat is the filter.
    return this.garmentWireQuery(def.cats[0]);
  }

  @action async chooseGarment(id: string): Promise<void> {
    const slot = this.chooserSlot;
    if (!slot || this.isLocked) return;
    this.chooserSlot = null;
    const g = await this.hydrateGarment(id);
    if (!g) return;
    this.setSlot(slot, g);
    this.clearPreview();
  }

  // Keep the chooser open behind the upload form — the upload Popover stacks
  // on top, and once saved the chooser is still there (now showing the new
  // garment via its live search).
  @action uploadForChooser(): void {
    this.openLibraryUpload('garment');
  }

  // ── Model linking ──
  @action toggleModelMenu(): void {
    if (this.isLocked) return;
    this.modelMenuOpen = !this.modelMenuOpen;
  }

  @action closeModelMenu(): void {
    this.modelMenuOpen = false;
  }

  // Keep the model picker open behind the upload form (the upload Popover
  // stacks on top).
  @action uploadModel(): void {
    this.openLibraryUpload('model');
  }

  @action linkExistingModel(): void {
    this.modelMenuOpen = false;
    if (this.isLocked) return;
    this.linkModelTask.perform();
  }

  linkModelTask = task(async () => {
    const commandContext = (this.args as any).context?.commandContext;
    if (!commandContext) return;
    const chosenId = await chooseCard({ filter: { type: modelRef } });
    if (!chosenId) return;
    await new PatchCardInstanceCommand(commandContext, {
      cardType: VirtualTryOnApp,
    }).execute({
      cardId: (this.args.model as any).id,
      patch: {
        relationships: {
          model: { links: { self: chosenId } },
        },
      },
    });
    // Classify the linked model's body once, if it hasn't been already.
    try {
      const chosen: any = await (this.args as any).context?.store?.get(
        chosenId,
      );
      const photoUrl = chosen?.photo?.resolvedUrl;
      if (chosen && !chosen.bodyVisibility && photoUrl) {
        this.detectBodyVisibility.perform(chosenId, photoUrl);
      }
    } catch (e) {
      console.warn('[VirtualTryOn] link-model detection skipped:', e);
    }
  });

  @action unlinkModel(event?: Event): void {
    event?.stopPropagation();
    event?.preventDefault();
    if (this.isLocked) return;
    // Unlink directly on the card's linksTo field — autosave persists it and
    // the template reacts immediately (a server-side patch by id wouldn't
    // refresh the in-memory `this.args.model.model`).
    this.args.model.model = null as unknown as Model;
    this.clearPreview();
  }

  @action onGarmentDragStart(id: string, category: string, event: Event): void {
    if (this.isLocked) return;
    this.draggingGarmentId = id;
    this.draggingCategory = category;
    const ev = event as DragEvent;
    ev.dataTransfer?.setData('text/plain', category ?? '');
    if (ev.dataTransfer) ev.dataTransfer.effectAllowed = 'copy';
  }

  isValidDrop(slot: string): boolean {
    const cat = this.draggingCategory;
    if (!cat) return false;
    const def = this.slotDefs.find((d) => d.key === slot);
    return !!def && def.cats.includes(cat);
  }

  @action onDragOver(slot: string, event: Event): void {
    if (this.isLocked) return;
    if (!this.isValidDrop(slot)) return; // don't preventDefault → browser shows not-allowed cursor
    event.preventDefault();
    this.dragOverSlot = slot;
  }

  @action onDragLeave(): void {
    this.dragOverSlot = null;
  }

  @action async onDrop(slot: string, event: Event): Promise<void> {
    if (this.isLocked) return;
    event.preventDefault();
    this.dragOverSlot = null;
    const id = this.draggingGarmentId;
    this.draggingGarmentId = null;
    this.draggingCategory = null;
    if (!id) return;
    const g = await this.hydrateGarment(id);
    if (!g) return;
    this.setSlot(slot, g);
    this.clearPreview();
  }

  @action openLibraryUpload(mode: 'model' | 'garment'): void {
    this._pendingUploadMode = mode;
    const input = document.getElementById(
      `lib-input-${mode}`,
    ) as HTMLInputElement;
    if (input) {
      input.value = '';
      input.click();
    }
  }

  // Open the Add Garment popover first (no file picker yet). When launched from
  // a category section the BoxelSelect defaults to that category.
  @action openGarmentModal(category?: string): void {
    if (this.isLocked) return;
    this.uploadMode = 'garment';
    this.newItemCategory = category ?? '';
    this.newItemName = '';
    this.capturedDataUrl = null;
    this.uploadError = null;
  }

  @action onLibraryFileSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file || !this._pendingUploadMode) return;
    const mode = this._pendingUploadMode;
    const reader = new FileReader();
    reader.onload = (e) => {
      this.capturedDataUrl = e.target?.result as string;
      // Only initialise a fresh form when one isn't already open (the sidebar
      // Add flow opens it first with a preset category). When launched from an
      // open garment chooser, pre-select that slot's category.
      if (!this.uploadMode) {
        this.uploadMode = mode;
        this.newItemName = '';
        this.newItemCategory =
          mode === 'garment' ? (this.chooserDef?.cats[0] ?? '') : '';
      }
      // Model is a single pick — once a photo is chosen, the picker's job is
      // done, so close it (the upload form takes over). The garment chooser
      // stays open so more garments can be added.
      if (mode === 'model') {
        this.modelMenuOpen = false;
      }
      this.uploadError = null;
    };
    reader.readAsDataURL(file);
  }

  // Native file dialog dismissed with no selection. If nothing was captured
  // yet, back fully out — close the upload form and any open chooser / model
  // picker (don't disturb a replace-an-existing-image flow that already has a
  // captured image).
  @action onLibraryFileCancel(): void {
    this._pendingUploadMode = null;
    if (this.capturedDataUrl) return;
    this.uploadMode = null;
    this.chooserSlot = null;
    this.modelMenuOpen = false;
    this.newItemName = '';
    this.newItemCategory = '';
    this.uploadError = null;
  }

  @action closeUpload(): void {
    this.uploadMode = null;
    this.capturedDataUrl = null;
    this.newItemName = '';
    this.newItemCategory = '';
  }

  @action onSlugInput(event: Event): void {
    // Keep the raw, human-readable name in the field; the slug is derived.
    this.newItemName = (event.target as HTMLInputElement).value;
  }

  @action setCategory(cat: string): void {
    this.newItemCategory = cat;
  }

  @action stopModalPropagation(event: Event): void {
    event.stopPropagation();
  }

  saveUpload = task(async () => {
    const commandContext = (this.args as any).context?.commandContext;
    if (!commandContext || !this.capturedDataUrl || !this.newItemSlug.trim())
      return;
    this.uploadError = null;
    try {
      const commaIdx = this.capturedDataUrl.indexOf(',');
      const base64Content = this.capturedDataUrl.slice(commaIdx + 1);
      const mimeType = this.capturedDataUrl.slice(5, commaIdx).split(';')[0];
      const ext = mimeType.split('/')[1] ?? 'jpg';
      const slug = this.newItemSlug.trim().toLowerCase();
      const dir = this.uploadMode === 'garment' ? 'Garment' : 'Model';

      const writeResult = await new WriteBinaryFileCommand(
        commandContext,
      ).execute({
        path: `${dir}/${slug}.${ext}`,
        realm: this.realmUrl,
        base64Content,
        contentType: mimeType,
        useNonConflictingFilename: true,
      });
      const imageUrl = writeResult.fileIdentifier;
      // Store the image as a realm-RELATIVE link (./file) like the built-in
      // garments, so the card stays portable across environments. An absolute
      // fileIdentifier points at the realm it was uploaded to and breaks when
      // the realm is deployed elsewhere (localhost → prod). The card and its
      // image land in the same type folder (Garment/ or Model/), so a sibling
      // ./<file> link resolves correctly wherever the realm lives.
      const imageFile = imageUrl.split('/').pop();
      const imageLink = imageFile ? `./${imageFile}` : imageUrl;

      if (this.uploadMode === 'garment') {
        const garment = new Garment({ category: this.newItemCategory });
        // No localDir: the realm-server already files new instances under a
        // type-named folder (Garment/), so passing 'Garment' double-nests it.
        const saved = await new SaveCardCommand(commandContext).execute({
          card: garment,
          realm: this.realmUrl,
        } as any);
        await new PatchCardInstanceCommand(commandContext, {
          cardType: Garment,
        }).execute({
          cardId: (saved as any).id,
          patch: {
            attributes: {
              title: slug,
              category: this.newItemCategory,
              image: { sourceMode: 'file' },
            },
            relationships: {
              'image.file': { links: { self: imageLink } },
            },
          },
        });
        // Garment is now found via live search — no need to link to app
      } else {
        const model = new Model();
        const saved = await new SaveCardCommand(commandContext).execute({
          card: model,
          realm: this.realmUrl,
        } as any);
        await new PatchCardInstanceCommand(commandContext, {
          cardType: Model,
        }).execute({
          cardId: (saved as any).id,
          patch: {
            attributes: {
              title: slug,
              photo: { sourceMode: 'file' },
            },
            relationships: {
              'photo.file': { links: { self: imageLink } },
            },
          },
        });
        const appId = (this.args.model as any).id;
        await new PatchCardInstanceCommand(commandContext, {
          cardType: VirtualTryOnApp,
        }).execute({
          cardId: appId,
          patch: {
            relationships: {
              model: {
                links: { self: (saved as any).id },
              },
            },
          },
        });
        // Detect body visibility once, now, from the data URL we already have
        // (no extra fetch). Fire-and-forget — the upload shouldn't wait on it.
        this.detectBodyVisibility.perform(
          (saved as any).id,
          this.capturedDataUrl,
        );
      }
      this.closeUpload();
    } catch (e: any) {
      this.uploadError = e?.message ?? 'Failed to save';
    }
  });

  // One-time, cheap (Haiku) body-visibility check for a model photo. Stored on
  // the Model card so every later try-on reuses it instead of paying per
  // generation. `imageSrc` may be a data URL or an http(s) URL.
  detectBodyVisibility = task(async (modelId: string, imageSrc: string) => {
    const commandContext = (this.args as any).context?.commandContext;
    if (!commandContext || !modelId || !imageSrc) return;
    // Never spend an AI call classifying the same model twice — if it's already
    // been detected, bail before the vision request. (store.get is local, free.)
    try {
      const existing: any = await (this.args as any).context?.store?.get(
        modelId,
      );
      if (existing?.bodyVisibility) return;
    } catch {
      // Couldn't read it back — proceed with detection rather than skip.
    }
    try {
      // The vision model can't fetch realm URLs (they're behind auth), so turn
      // an http(s) source into a self-contained base64 data URL first — the
      // browser already has the session. A data URL is passed straight through.
      let src = imageSrc;
      if (/^https?:/i.test(src)) {
        const resp = await fetch(src);
        const blob = await resp.blob();
        src = await new Promise<string>((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result as string);
          reader.onerror = reject;
          reader.readAsDataURL(blob);
        });
      }
      const result = await new SendRequestViaProxyCommand(
        commandContext,
      ).execute({
        url: 'https://openrouter.ai/api/v1/chat/completions',
        method: 'POST',
        requestBody: JSON.stringify({
          model: 'anthropic/claude-haiku-4.5',
          messages: [
            {
              role: 'system',
              content:
                'You classify how much of a person\'s body is visible in a photo for a virtual clothing try-on. Reply with EXACTLY one word, no punctuation: "full" if the body from at least the torso down through the legs is visible (a usable full or near-full body shot), otherwise "partial" (headshot, face-only, or tightly cropped).',
            },
            {
              role: 'user',
              content: [
                {
                  type: 'text',
                  text: 'Classify this photo: full or partial?',
                },
                { type: 'image_url', image_url: { url: src } },
              ],
            },
          ],
          stream: false,
        }),
      } as any);
      if (!result.response.ok) return;
      const data = await result.response.json();
      const raw: string = data?.choices?.[0]?.message?.content ?? '';
      const visibility = /full/i.test(raw) ? 'full' : 'partial';
      await new PatchCardInstanceCommand(commandContext, {
        cardType: Model,
      }).execute({
        cardId: modelId,
        patch: { attributes: { bodyVisibility: visibility } },
      });
    } catch (e) {
      // Non-fatal: leave bodyVisibility undetected; generation still works.
      console.warn('[VirtualTryOn] body detection failed:', e);
    }
  });

  // ── Generation ──
  buildGarmentPrompt(
    garments: { slot: string; g: Garment }[],
    garmentImageUrls: string[],
  ): string {
    const slotLabel = (slot: string) =>
      this.slotDefs.find((d) => d.key === slot)?.label.toLowerCase() ?? slot;
    const mapping = garments
      .map(({ slot }, i) => `image ${i + 2} = ${slotLabel(slot)}`)
      .join(', ');
    const replaceRule =
      "REPLACE, do NOT combine: each selected garment must COMPLETELY replace whatever the model is already wearing on that part of the body. Remove the model's original clothing for that slot entirely and show ONLY the selected garment there — never layer, blend, peek, or mix the new garment with the model's existing clothes. Garments for slots that were NOT selected stay as they are in the original photo.";
    return garmentImageUrls.length > 0
      ? `GARMENTS: Dress the model in the exact garments shown in the reference images — ${mapping}. ${replaceRule} Reproduce each garment's color, texture, cut, logo, and branding exactly. Do NOT change any detail.`
      : `GARMENTS: Dress the model in — ${garments.map(({ slot, g }) => `${slotLabel(slot)}: ${g.cardTitle}`).join(', ')}. ${replaceRule}`;
  }

  // Clear the views, show the skeleton for a beat, then reveal a known result.
  // Used when re-serving a cached or persisted generation so it still feels
  // like work without spending an AI call.
  async serveResult(
    front: string | null,
    side: string | null,
    back: string | null,
  ): Promise<void> {
    this.frontImageUrl = null;
    this.sideImageUrl = null;
    this.backImageUrl = null;
    this.generationStatus = 'generating';
    await timeout(3000);
    this.frontImageUrl = front;
    this.sideImageUrl = side;
    this.backImageUrl = back;
    this.generationStatus = 'ready';
  }

  generateOutfit = task(async () => {
    const model = this.activeModel;
    if (!model) return;
    const commandContext = (this.args as any).context?.commandContext;
    if (!commandContext) {
      this.errorMessage = 'Switch to Interact mode to generate.';
      this.generationStatus = 'failed';
      return;
    }

    this.carouselIndex = 0;
    const key = this.cacheKey;
    const cached = this.resultCache.get(key);
    if (cached) {
      // Re-serve the same cached result, but play a fake skeleton loading so a
      // re-generate feels like real work without spending an AI generation.
      await this.serveResult(
        cached.front,
        cached.side ?? null,
        cached.back ?? null,
      );
      // Fill in any angle views the cached result is still missing.
      if (cached.front && (!cached.side || !cached.back)) {
        this.generateAngles.perform(
          key,
          cached.front,
          this.currentGarmentImageUrls,
          commandContext,
          this.findPersistedResult(),
        );
      }
      return;
    }
    // After a reload the in-memory cache is empty and the live result search
    // may not have resolved yet — wait for it so we reuse a prior generation
    // for this exact model + garment combo instead of paying to regenerate.
    try {
      await (this.resultSearch as any)?.loaded;
    } catch {
      // ignore — fall through to a fresh generation if the search failed
    }
    const persisted = this.findPersistedResult();
    if (persisted?.frontViewUrl) {
      this.resultCache.set(key, {
        front: persisted.frontViewUrl,
        side: persisted.sideViewUrl ?? undefined,
        back: persisted.backViewUrl ?? undefined,
      });
      await this.serveResult(
        persisted.frontViewUrl,
        persisted.sideViewUrl ?? null,
        persisted.backViewUrl ?? null,
      );
      // Fill in any angle views the persisted result is still missing.
      if (!persisted.sideViewUrl || !persisted.backViewUrl) {
        this.generateAngles.perform(
          key,
          persisted.frontViewUrl,
          this.currentGarmentImageUrls,
          commandContext,
          persisted,
        );
      }
      return;
    }

    this.generationStatus = 'generating';
    this.frontImageUrl = null;
    this.sideImageUrl = null;
    this.backImageUrl = null;
    this.errorMessage = null;

    const garments = this.filledGarments;

    const garmentImageUrls = garments
      .map(({ g }) => (g as any).image?.resolvedUrl)
      .filter(Boolean) as string[];

    const frontPrompt = [
      'Virtual fashion try-on. Photorealistic full-body studio photo of the person in image 1.',
      "IDENTITY: Keep the model's face, skin tone, hair, and features exactly the same.",
      "BODY: If the person's body is visible in image 1, preserve their exact body shape, size, weight, height, and proportions — whether slim, athletic, curvy, plus-size, or full-figured. Do NOT slim down, idealize, lengthen, flatter, or otherwise alter their physique; the body in the output must match the real body in the photo precisely, showing how the garments actually drape and fit on THIS body. If the body is NOT visible (e.g. a headshot or cropped photo), generate a natural, average standard body build in a neutral pose — do not exaggerate or idealize.",
      'POSE: Neutral standing pose, arms relaxed, facing directly forward.',
      this.buildGarmentPrompt(garments, garmentImageUrls),
      'ANGLE: Front view, full body head to toe. BACKGROUND: Clean seamless white studio backdrop. OUTPUT: 1:1 square aspect ratio, full body visible within frame.',
    ].join(' ');

    try {
      const cmd = new GenerateTryOnCommand(commandContext);
      const frontResult = await cmd.execute({
        prompt: frontPrompt,
        modelImageUrl: model.photo?.resolvedUrl ?? undefined,
        garmentImageUrls,
        targetRealmIdentifier: this.realmUrl,
        targetPath: 'generated',
      } as any);

      const frontUrl = frontResult.imageUrl ?? null;
      if (!frontUrl) throw new Error('No image returned');

      this.frontImageUrl = frontUrl;
      this.generationStatus = 'ready';
      this.resultCache.set(key, { front: frontUrl });

      let savedResult: TryOnResult | undefined;
      try {
        const tryOnResult = new TryOnResult({
          modelKey: this.modelKey,
          garmentKey: this.garmentKey,
          frontViewUrl: frontUrl,
        });
        savedResult = (await new SaveCardCommand(commandContext).execute({
          card: tryOnResult,
          realm: this.realmUrl,
        } as any)) as TryOnResult;
        const savedResultId = (savedResult as any).id;
        await new PatchCardInstanceCommand(commandContext, {
          cardType: TryOnResult,
        }).execute({
          cardId: savedResultId,
          patch: {
            attributes: {
              title: `try-on::${this.modelKey}::${this.garmentKey}`,
            },
          },
        });
        // No app relationship to maintain — the live result search picks this
        // up by modelKey/garmentKey once it's indexed.
      } catch (e) {
        console.warn('[VirtualTryOn] persist failed:', e);
      }

      this.generateAngles.perform(
        key,
        frontUrl,
        garmentImageUrls,
        commandContext,
        savedResult,
      );
    } catch (e: any) {
      this.errorMessage = e?.message ?? 'Generation failed';
      this.generationStatus = 'failed';
    }
  });

  generateAngles = task(
    async (
      key: string,
      frontUrl: string,
      garmentImageUrls: string[],
      commandContext: any,
      savedResult?: TryOnResult,
    ) => {
      const cmd = new GenerateTryOnCommand(commandContext);
      const base = `Fashion try-on. Image 1 is the front view — maintain identical garments, colors, textures, the person's exact identity, and their exact body shape, size, weight, and proportions (do NOT slim or idealize the physique).`;

      const patchResult = async (patch: {
        sideViewUrl?: string;
        backViewUrl?: string;
      }) => {
        if (!savedResult) return;
        const id = (savedResult as any).id;
        if (!id) return;
        try {
          await new PatchCardInstanceCommand(commandContext, {
            cardType: TryOnResult,
          }).execute({ cardId: id, patch: { attributes: patch } });
        } catch (e) {
          console.warn('[VirtualTryOn] angle patch failed:', e);
        }
      };

      // Generate one extra angle from the front view, then mirror the result
      // into the tracked field, the in-memory cache, and the persisted card.
      const runAngle = async (
        anglePrompt: string,
        apply: (url: string) => Promise<void>,
      ) => {
        try {
          const r = await cmd.execute({
            prompt: `${base} ${anglePrompt} BACKGROUND: White studio. OUTPUT: 1:1 square aspect ratio, full body visible within frame.`,
            modelImageUrl: frontUrl,
            garmentImageUrls,
            targetRealmIdentifier: this.realmUrl,
            targetPath: 'generated',
          } as any);
          if (r.imageUrl) await apply(r.imageUrl);
        } catch (e) {
          console.warn('[VirtualTryOn] angle failed:', e);
        }
      };

      // Only generate views that are still missing — lets a re-generate fill
      // in side/back for a cached result without redoing what we already have.
      if (!this.sideImageUrl) {
        await runAngle(
          'ANGLE: Side profile, 90 degrees right, full body.',
          async (url) => {
            this.sideImageUrl = url;
            const e = this.resultCache.get(key);
            if (e) e.side = url;
            await patchResult({ sideViewUrl: url });
          },
        );
      }

      if (!this.backImageUrl) {
        await runAngle(
          'ANGLE: Back view, facing away, full body.',
          async (url) => {
            this.backImageUrl = url;
            const e = this.resultCache.get(key);
            if (e) e.back = url;
            await patchResult({ backViewUrl: url });
          },
        );
      }
    },
  );

  // Build the current garment reference image urls (used when re-generating
  // the missing angle views of an already-cached result).
  get currentGarmentImageUrls(): string[] {
    return this.filledGarments
      .map(({ g }) => (g as any).image?.resolvedUrl)
      .filter(Boolean) as string[];
  }

  <template>
    {{! Hidden file inputs for library upload — always in DOM }}
    <input
      id='lib-input-model'
      type='file'
      accept='image/*'
      class='hidden-input'
      {{on 'change' this.onLibraryFileSelected}}
      {{on 'cancel' this.onLibraryFileCancel}}
    />
    <input
      id='lib-input-garment'
      type='file'
      accept='image/*'
      class='hidden-input'
      {{on 'change' this.onLibraryFileSelected}}
      {{on 'cancel' this.onLibraryFileCancel}}
    />

    <div
      class='app
        {{if this.isGenerating "app--generating" ""}}
        {{if this.isLocked "app--locked" ""}}'
    >

      {{! ── Model strip (top bar) ── }}
      <header class='model-strip'>
        <div class='brand'>
          <span class='brand-mark'>✦</span>
          <h1 class='brand-name'>{{if
              this.args.model.cardTitle
              this.args.model.cardTitle
              'Virtual Try-On'
            }}</h1>
        </div>
        {{! Linked model avatar }}
        {{#if this.hasUsableModel}}
          <div class='model-scroll'>
            <div class='model-thumb-wrap'>
              <button
                type='button'
                class='model-thumb model-thumb--active'
                disabled={{this.isLocked}}
              >
                {{#if this.activeModel.photo.resolvedUrl}}
                  <img
                    src={{this.activeModel.photo.resolvedUrl}}
                    alt={{this.activeModel.cardTitle}}
                    class='model-thumb-img'
                  />
                {{else}}
                  <div class='model-thumb-empty'>?</div>
                {{/if}}
              </button>
              <button
                type='button'
                class='model-unlink'
                title='Unlink model'
                aria-label='Unlink model'
                disabled={{this.isLocked}}
                {{on 'click' this.unlinkModel}}
              >✕</button>
            </div>
          </div>
        {{/if}}

        {{! Add model button }}
        <button
          type='button'
          class='add-model-btn'
          data-bx-popover-anchor='vto-model'
          disabled={{this.isLocked}}
          {{on 'click' this.toggleModelMenu}}
        >+ Add Model</button>

        {{! Try On / Go back CTA — lives in the strip so it never overlaps }}
        <div class='gen-action'>
          {{#if (eq this.generationStatus 'ready')}}
            <button type='button' class='gen-btn' {{on 'click' this.restart}}>←
              Go back</button>
          {{else}}
            <button
              type='button'
              class='gen-btn {{if this.isGenerating "gen-btn--busy" ""}}'
              disabled={{if this.canGenerate false true}}
              {{on 'click' this.generateOutfit.perform}}
            >
              {{#if this.isGenerating}}<span class='gen-spin'></span>{{/if}}
              {{#if this.isGenerating}}Generating…{{else}}✦ Try On Outfit{{/if}}
            </button>
          {{/if}}
        </div>

      </header>

      {{! ── Main area ── }}
      <main>

        {{! Left: garment sidebar (categorised) }}
        <aside class='sidebar'>
          <div class='sidebar-head'>
            <h2 class='sidebar-title'>Garments</h2>
          </div>

          <div class='filter-row'>
            {{#each this.filterOptions as |cat|}}
              <button
                type='button'
                class='filter-pill
                  {{if (eq cat this.filterCategory) "filter-pill--on" ""}}'
                {{on 'click' (fn this.setFilter cat)}}
              >{{cat}}</button>
            {{/each}}
          </div>

          <div class='garment-sections'>
            {{#each this.garmentSections as |section|}}
              <div class='gsection'>
                <div class='gsection-head'>
                  <h3 class='gsection-title'>{{section.label}}</h3>
                  {{#if (eq this.filterCategory 'all')}}
                    <button
                      type='button'
                      class='view-all'
                      {{on 'click' (fn this.setFilter section.key)}}
                    >View all</button>
                  {{else}}
                    <button
                      type='button'
                      class='view-all'
                      {{on 'click' (fn this.setFilter 'all')}}
                    >Back</button>
                  {{/if}}
                </div>
                <div class='gsection-grid'>
                  {{! Add placeholder — opens the popover with this category preset }}
                  <button
                    type='button'
                    class='garment-add'
                    disabled={{this.isLocked}}
                    {{on 'click' (fn this.openGarmentModal section.key)}}
                  >
                    <span class='garment-add-ico'>+</span>
                    <span class='garment-add-lbl'>Add</span>
                  </button>
                  {{! Prerendered garment entries — no instances held; a real
                      Garment is hydrated only when one is picked / dropped. }}
                  <@context.searchResultsComponent
                    @query={{section.query}}
                    @mode='none'
                    @overlays={{false}}
                    as |results|
                  >
                    {{#each results.entries key='id' as |entry|}}
                      <div
                        class='garment-item
                          {{if this.isLocked "garment-item--off" ""}}'
                        draggable='true'
                        role='button'
                        tabindex='0'
                        {{on
                          'dragstart'
                          (fn this.onGarmentDragStart entry.id section.key)
                        }}
                        {{on 'click' (fn this.pickGarmentById entry.id)}}
                      >
                        <entry.component />
                      </div>
                    {{else}}
                      {{#if results.isLoading}}
                        {{#each this.skeletonTiles as |s|}}
                          <div
                            class='garment-skeleton'
                            data-skeleton={{s}}
                          ></div>
                        {{/each}}
                      {{/if}}
                    {{/each}}
                  </@context.searchResultsComponent>
                </div>
              </div>
            {{/each}}
          </div>
        </aside>

        {{! Right: the styling stage }}
        <section class='stage' aria-label='Styling stage'>

          {{! Outfit slots — horizontal card: model photo + garment tiles with icons }}
          <div class='slots-bar'>
            <div class='slots-row'>

              {{! ── Model photo slot ── }}
              <div
                class='sq-slot sq-slot--model
                  {{if this.isLocked "sq-slot--off" ""}}'
                role='button'
                tabindex='0'
                {{on 'click' this.toggleModelMenu}}
              >
                {{#if this.activeModel.photo.resolvedUrl}}
                  <button
                    type='button'
                    class='sq-badge sq-badge--remove'
                    title='Remove model'
                    aria-label='Remove model'
                    {{on 'click' this.unlinkModel}}
                  >✕</button>
                {{else}}
                  <span class='sq-badge'>+</span>
                {{/if}}
                <div class='sq-body sq-body--photo'>
                  {{#if this.activeModel.photo.resolvedUrl}}
                    <img
                      src={{this.activeModel.photo.resolvedUrl}}
                      class='sq-img sq-img--cover'
                      alt={{this.activeModel.cardTitle}}
                    />
                  {{else}}
                    <svg
                      class='sq-icon'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='1.2'
                      stroke-linecap='round'
                    >
                      <circle cx='12' cy='8' r='3.5' />
                      <path d='M5 20C5 16.7 8.1 14 12 14S19 16.7 19 20' />
                    </svg>
                  {{/if}}
                </div>
                <span
                  class='sq-lbl'
                  title={{if
                    this.activeModel.cardTitle
                    this.activeModel.cardTitle
                    'Your photo'
                  }}
                >{{if
                    this.activeModel.cardTitle
                    this.activeModel.cardTitle
                    'Your photo'
                  }}</span>
              </div>

              {{! ── Divider ── }}
              <div class='sq-divider'></div>

              {{! ── Garment slots ── }}
              {{#each this.outfitSlots as |slot|}}
                <div
                  class='sq-slot
                    {{if (eq this.dragOverSlot slot.key) "sq-slot--over" ""}}
                    {{if slot.garment "sq-slot--filled" ""}}
                    {{if (eq this.activeSlot slot.key) "sq-slot--active" ""}}
                    {{if (this.isSlotDisabled slot.key) "sq-slot--covered" ""}}
                    {{if this.isLocked "sq-slot--off" ""}}'
                  role='button'
                  tabindex='0'
                  data-bx-popover-anchor='vto-slot-{{slot.key}}'
                  {{on 'click' (fn this.openChooser slot.key)}}
                  {{on 'dragover' (fn this.onDragOver slot.key)}}
                  {{on 'dragleave' this.onDragLeave}}
                  {{on 'drop' (fn this.onDrop slot.key)}}
                >
                  {{! + badge on empty slots; filled slots show the remove (✕) button instead }}
                  {{#unless slot.garment}}
                    <span class='sq-badge'>+</span>
                  {{/unless}}
                  <div class='sq-body'>
                    {{#if slot.garment}}
                      {{#if slot.garment.image.resolvedUrl}}
                        <img
                          src={{slot.garment.image.resolvedUrl}}
                          class='sq-img'
                          alt={{slot.garment.cardTitle}}
                        />
                      {{else}}
                        <span
                          class='sq-item-name'
                        >{{slot.garment.cardTitle}}</span>
                      {{/if}}
                    {{else}}
                      {{! Category icon (line-art SVG) }}
                      {{#if (eq slot.key 'full-body')}}
                        <svg
                          class='sq-icon'
                          viewBox='0 0 24 24'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.2'
                          stroke-linecap='round'
                          stroke-linejoin='round'
                        >
                          <path d='M9 3L15 3L13 10L17 21L7 21L11 10Z' />
                          <path d='M9 3Q12 5 15 3' />
                          <line x1='11' y1='10' x2='13' y2='10' />
                        </svg>
                      {{else if (eq slot.key 'top')}}
                        <svg
                          class='sq-icon'
                          viewBox='0 0 24 24'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.2'
                          stroke-linecap='round'
                          stroke-linejoin='round'
                        >
                          <path
                            d='M6 3L2 9H7V21H17V9H22L18 3C16.5 5.5 14.2 7 12 7C9.8 7 7.5 5.5 6 3Z'
                          />
                        </svg>
                      {{else if (eq slot.key 'bottom')}}
                        <svg
                          class='sq-icon'
                          viewBox='0 0 24 24'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.2'
                          stroke-linecap='round'
                          stroke-linejoin='round'
                        >
                          <path d='M5 3H19V14L15 21H13L12 16L11 21H9L5 14V3Z' />
                          <line x1='12' y1='3' x2='12' y2='14' />
                        </svg>
                      {{else if (eq slot.key 'shoes')}}
                        <svg
                          class='sq-icon'
                          viewBox='0 0 24 24'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.2'
                          stroke-linecap='round'
                          stroke-linejoin='round'
                        >
                          <path
                            d='M3 18C3 15.8 5 14 8 14H18C20.2 14 21 15.3 21 17V19C21 19.6 20.6 20 20 20H4C3.4 20 3 19.6 3 19V18Z'
                          />
                          <path d='M8 14L9 10C9.5 8.5 11 8 12.5 8.5L14 9' />
                        </svg>
                      {{else if (eq slot.key 'outerwear')}}
                        <svg
                          class='sq-icon'
                          viewBox='0 0 24 24'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.2'
                          stroke-linecap='round'
                          stroke-linejoin='round'
                        >
                          <path
                            d='M7 3L3 8L7 9V21H11L12 17L13 21H17V9L21 8L17 3L13.5 5.5C13 7 11 7 10.5 5.5L7 3Z'
                          />
                        </svg>
                      {{else}}
                        <svg
                          class='sq-icon'
                          viewBox='0 0 24 24'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.2'
                          stroke-linecap='round'
                          stroke-linejoin='round'
                        >
                          <circle cx='12' cy='12' r='8' />
                          <circle cx='12' cy='12' r='3' />
                          <line x1='12' y1='4' x2='12' y2='9' />
                          <line x1='12' y1='15' x2='12' y2='20' />
                          <line x1='4' y1='12' x2='9' y2='12' />
                          <line x1='15' y1='12' x2='20' y2='12' />
                        </svg>
                      {{/if}}
                    {{/if}}
                  </div>
                  {{#if slot.garment}}
                    <button
                      type='button'
                      class='sq-remove'
                      aria-label='Remove garment'
                      {{on 'click' (fn this.removeSlot slot.key)}}
                    >✕</button>
                  {{/if}}
                  <span
                    class='sq-lbl'
                    title={{slot.label}}
                  >{{slot.label}}</span>
                </div>
              {{/each}}
            </div>
          </div>

          {{#if (eq this.generationStatus 'failed')}}
            <p class='err-msg'>{{this.errorMessage}}</p>
          {{/if}}

          {{! Body: preview stage + side column }}
          <div class='stage-body'>
            <div class='preview'>
              {{#if this.bodyNotDetected}}
                {{! Desktop shows this in the Tips card; on mobile (Tips hidden)
                    it floats as an overlay — see .body-hint container query. }}
                <div class='body-hint' role='status'>
                  <span class='body-hint-ico'>ℹ</span>
                  <span>{{this.tipText}}</span>
                </div>
              {{/if}}
              <div class='result-area'>
                {{#if this.genProgress}}
                  <div class='gen-pill'>
                    <span class='gen-pill-dot'></span>
                    <span
                      class='gen-pill-text'
                    >{{this.genProgress.label}}</span>
                    <span class='gen-pill-step'>{{this.genProgress.step}}</span>
                  </div>
                {{/if}}

                {{#if this.showGeneratingPlaceholder}}
                  <div class='result-placeholder'>
                    <div class='big-spin'></div>
                    <span>Generating front view…</span>
                  </div>
                {{else if this.frontImageUrl}}
                  <div
                    class='carousel'
                    {{on 'pointerdown' this.onRotateStart}}
                    {{on 'pointermove' this.onRotateMove}}
                    {{on 'pointerup' this.onRotateEnd}}
                    {{on 'pointerleave' this.onRotateEnd}}
                  >
                    <div
                      class='carousel-track'
                      style={{this.carouselTrackStyle}}
                    >
                      {{#each this.carouselSlides as |slide|}}
                        <div class='carousel-slide'>
                          {{#if slide.url}}
                            <img
                              src={{slide.url}}
                              alt={{slide.label}}
                              class='slide-img'
                            />
                          {{else}}
                            <div class='slide-empty'>
                              {{#if this.generateAngles.isRunning}}
                                <div class='slide-spin'></div><span>Generating
                                  {{slide.label}}…</span>
                              {{else}}
                                <span
                                  class='slide-empty-lbl'
                                >{{slide.label}}</span>
                              {{/if}}
                            </div>
                          {{/if}}
                        </div>
                      {{/each}}
                    </div>
                  </div>
                {{else if this.activeModel.photo.resolvedUrl}}
                  <div class='result-model'>
                    <img
                      src={{this.activeModel.photo.resolvedUrl}}
                      alt={{this.activeModel.cardTitle}}
                      class='result-model-img'
                    />
                  </div>
                {{else}}
                  <div class='result-empty'>
                    <span class='result-empty-ico'>✦</span>
                    <span>Select garments and tap Try On</span>
                  </div>
                {{/if}}

                {{! View switcher — right-side overlay on the preview }}
                <div class='view-overlay'>
                  {{#each this.viewOptions as |v|}}
                    <button
                      type='button'
                      class='vo-btn
                        {{if (eq this.carouselIndex v.index) "vo-btn--on" ""}}'
                      disabled={{if
                        (eq v.index 0)
                        false
                        (if this.frontImageUrl false true)
                      }}
                      {{on 'click' (fn this.setSlide v.index)}}
                    >
                      {{#if (eq v.index 0)}}
                        <svg
                          class='vo-icon'
                          viewBox='0 0 20 20'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.3'
                          stroke-linecap='round'
                        >
                          <circle cx='10' cy='5' r='2.2' />
                          <path
                            d='M6.5 9.5C6.5 8 8.1 7 10 7S13.5 8 13.5 9.5V13H6.5V9.5Z'
                          />
                          <path d='M6.5 13L5.5 18M13.5 13L14.5 18' />
                        </svg>
                      {{else if (eq v.index 1)}}
                        <svg
                          class='vo-icon'
                          viewBox='0 0 20 20'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.3'
                          stroke-linecap='round'
                        >
                          <circle cx='11' cy='5' r='2.2' />
                          <path
                            d='M8 9.5C8 8 9.3 7 11 7S13.5 8.2 13.5 9.5V13H9V9.5Z'
                          />
                          <path d='M9 13L7.5 18M13.5 13L14 18' />
                        </svg>
                      {{else}}
                        <svg
                          class='vo-icon'
                          viewBox='0 0 20 20'
                          fill='none'
                          stroke='currentColor'
                          stroke-width='1.3'
                          stroke-linecap='round'
                          opacity='0.7'
                        >
                          <circle cx='10' cy='5' r='2.2' />
                          <path
                            d='M6.5 9.5C6.5 8 8.1 7 10 7S13.5 8 13.5 9.5V13H6.5V9.5Z'
                          />
                          <path d='M6.5 13L5.5 18M13.5 13L14.5 18' />
                        </svg>
                      {{/if}}
                      <span class='vo-lbl'>{{v.label}}</span>
                    </button>
                  {{/each}}
                </div>

                {{#if (eq this.generationStatus 'ready')}}
                  <div class='stage-tools'>
                    <button
                      type='button'
                      class='tool-btn'
                      title='Start over'
                      aria-label='Start over'
                      {{on 'click' this.regenerate}}
                    >↻</button>
                    <button
                      type='button'
                      class='tool-btn'
                      title='Open full size'
                      aria-label='Open full size'
                      {{on 'click' this.saveLook}}
                    >⤢</button>
                    <button
                      type='button'
                      class='tool-btn'
                      title='Download image'
                      aria-label='Download image'
                      {{on 'click' this.downloadCurrent.perform}}
                    >⤓</button>
                  </div>
                {{/if}}

              </div>
            </div>

            {{! Right column: tips only (view switcher is now an overlay) }}
            <div class='side-col'>
              <div class='side-card'>
                <h2 class='side-card-title'>Tips</h2>
                <p class='side-tip'>The AI generates a fresh full-body image
                  from your exact model and outfit, posed in a neutral stance.
                  It takes a few seconds — hang tight.</p>
              </div>
            </div>
          </div>

          {{! Bottom action bar }}
          <div class='action-bar'>
            {{#if (eq this.generationStatus 'ready')}}
              <button
                type='button'
                class='act-btn act-btn--primary'
                {{on 'click' this.restart}}
              >← Go back</button>
              <button
                type='button'
                class='act-btn act-btn--ghost'
                disabled={{if this.canSaveLook false true}}
                {{on 'click' this.saveLook}}
              ><span class='act-ico'>⌑</span> Save Look</button>
            {{else}}
              <button
                type='button'
                class='act-btn act-btn--primary
                  {{if this.isGenerating "act-btn--busy" ""}}'
                disabled={{if this.canGenerate false true}}
                {{on 'click' this.generateOutfit.perform}}
              >
                {{#if this.isGenerating}}<span class='gen-spin'></span>{{/if}}
                {{#if this.isGenerating}}Generating…{{else}}✦ Try On Outfit{{/if}}
              </button>
              <button
                type='button'
                class='act-btn act-btn--ghost'
                disabled
              ><span class='act-ico'>⌑</span> Save Look</button>
            {{/if}}
          </div>

        </section>
      </main>

      {{! ── Upload form (catalog Popover — stacks above the picker/chooser) ── }}
      <Popover
        @anchor="[data-bx-popover-anchor='vto-model']"
        @open={{this.isUploadOpen}}
        @kind='tools'
        @anchoring='center'
        @backdrop='dim'
        @elevation='floating'
        @size='auto'
        @trapFocus={{true}}
        @labelledby='vto-upload-title'
        @onDismiss={{this.closeUpload}}
      >
        <:tools>
          <div class='modal-pop'>
            <div class='modal-head'>
              <h2 id='vto-upload-title' class='modal-title'>Add
                {{if (eq this.uploadMode 'garment') 'Garment' 'Model'}}</h2>
              <button
                type='button'
                class='modal-close'
                aria-label='Close'
                {{on 'click' this.closeUpload}}
              >✕</button>
            </div>

            <div class='details-pane'>
              {{! Image insert — click to pick from the library }}
              <button
                type='button'
                class='img-drop
                  {{if this.capturedDataUrl "img-drop--filled" ""}}'
                {{on 'click' (fn this.openLibraryUpload this.uploadMode)}}
              >
                {{#if this.capturedDataUrl}}
                  <img
                    src={{this.capturedDataUrl}}
                    alt='Preview'
                    class='preview-img'
                  />
                  <span class='img-drop-hint'>Click to replace</span>
                {{else}}
                  <span class='img-drop-ico'>↑</span>
                  <span class='img-drop-lbl'>Upload from library</span>
                {{/if}}
              </button>
              <div class='field-group'>
                <label class='field-lbl'>Name
                  <span class='field-lbl-hint'>(words joined by -)</span></label>
                <input
                  type='text'
                  class='field-input'
                  value={{this.newItemName}}
                  placeholder='e.g. Red Silk Blouse'
                  {{on 'input' this.onSlugInput}}
                />
                {{#if this.newItemSlug}}
                  <span class='field-hint'>Saved as:
                    <strong>{{this.newItemSlug}}</strong></span>
                {{/if}}
              </div>
              {{#if (eq this.uploadMode 'garment')}}
                <div class='field-group'>
                  <label class='field-lbl'>Category</label>
                  <BoxelSelect
                    @placeholder='Select category'
                    @options={{this.categoryOptions}}
                    @selected={{this.newItemCategory}}
                    @onChange={{this.setCategory}}
                    as |cat|
                  >
                    <div class='cat-option'>{{cat}}</div>
                  </BoxelSelect>
                </div>
              {{/if}}
              {{#if this.uploadError}}
                <p class='upload-err'>{{this.uploadError}}</p>
              {{/if}}
              <button
                type='button'
                class='save-btn
                  {{if this.saveUpload.isRunning "save-btn--busy" ""}}'
                disabled={{if this.canSaveUpload false true}}
                {{on 'click' this.saveUpload.perform}}
              >{{#if
                  this.saveUpload.isRunning
                }}Saving…{{else}}Save{{/if}}</button>
            </div>
          </div>
        </:tools>
      </Popover>

      {{! ── Lightbox (full-size result) ── }}
      {{#if this.lightboxUrl}}
        <div
          class='lightbox-overlay'
          role='dialog'
          aria-modal='true'
          aria-label='Full-size try-on result'
          {{on 'click' this.closeLightbox}}
        >
          <button
            type='button'
            class='lightbox-close'
            aria-label='Close'
            {{on 'click' this.closeLightbox}}
          >✕</button>
          <img
            src={{this.lightboxUrl}}
            alt='Full-size try-on result'
            class='lightbox-img'
            {{on 'click' this.stopModalPropagation}}
          />
        </div>
      {{/if}}

      {{! ── Model Picker (catalog Popover — viewport-centered modal) ── }}
      <Popover
        @anchor="[data-bx-popover-anchor='vto-model']"
        @open={{this.modelMenuOpen}}
        @kind='tools'
        @anchoring='center'
        @backdrop='dim'
        @elevation='floating'
        @size='auto'
        @trapFocus={{this.backgroundTrapsFocus}}
        @labelledby='vto-mpm-title'
        @onDismiss={{this.closeModelMenu}}
      >
        <:tools>
          <div class='mpm-pop'>
            <div class='mpm-head'>
              <div class='mpm-head-left'>
                <span class='mpm-eyebrow'>Virtual Try-On</span>
                <h2 id='vto-mpm-title' class='mpm-title'>Choose your model</h2>
              </div>
              <button
                type='button'
                class='mpm-close'
                aria-label='Close'
                {{on 'click' this.closeModelMenu}}
              >✕</button>
            </div>
            <div class='mpm-body'>

              {{! Upload card }}
              <button
                type='button'
                class='mpm-card mpm-card--upload'
                {{on 'click' this.uploadModel}}
              >
                <div class='mpm-visual mpm-visual--upload'>
                  <svg
                    class='mpm-visual-icon'
                    viewBox='0 0 24 24'
                    fill='none'
                    stroke='currentColor'
                    stroke-width='1.1'
                    stroke-linecap='round'
                    stroke-linejoin='round'
                  >
                    <path d='M12 15V4' />
                    <path d='M8 8L12 4L16 8' />
                    <path
                      d='M5 14V18C5 19.1 5.9 20 7 20H17C18.1 20 19 19.1 19 18V14'
                    />
                  </svg>
                </div>
                <div class='mpm-card-content'>
                  <span class='mpm-card-title'>Upload a photo</span>
                  <span class='mpm-card-desc'>Add a new model photo from your
                    device. A full-body shot keeps your real shape — if we can't
                    detect your body, we'll generate a standard body pose</span>
                  <span class='mpm-card-cta'>↑ Choose file</span>
                </div>
              </button>

              {{! Link existing card }}
              <button
                type='button'
                class='mpm-card mpm-card--link'
                {{on 'click' this.linkExistingModel}}
              >
                <div class='mpm-visual mpm-visual--link'>
                  <svg
                    class='mpm-visual-icon'
                    viewBox='0 0 24 24'
                    fill='none'
                    stroke='currentColor'
                    stroke-width='1.1'
                    stroke-linecap='round'
                    stroke-linejoin='round'
                  >
                    <circle cx='12' cy='8' r='3.2' />
                    <path
                      d='M5.5 20C5.5 16.4 8.4 13.5 12 13.5S18.5 16.4 18.5 20'
                    />
                  </svg>
                </div>
                <div class='mpm-card-content'>
                  <span class='mpm-card-title'>Link existing model</span>
                  <span class='mpm-card-desc'>Connect a model card you've
                    already created in this realm</span>
                  <span class='mpm-card-cta'>Browse models →</span>
                </div>
              </button>

            </div>
          </div>
        </:tools>
      </Popover>

      {{! ── Garment Chooser (catalog Popover — same as the model picker) ── }}
      <Popover
        @anchor={{this.chooserAnchor}}
        @open={{this.isChooserOpen}}
        @kind='tools'
        @anchoring='center'
        @backdrop='dim'
        @elevation='floating'
        @size='auto'
        @trapFocus={{this.backgroundTrapsFocus}}
        @labelledby='vto-chooser-title'
        @onDismiss={{this.closeChooser}}
      >
        <:tools>
          <div class='chooser-pop'>
            <div class='chooser-head'>
              <div class='chooser-head-left'>
                <span class='chooser-eyebrow'>Virtual Try-On</span>
                <h2 id='vto-chooser-title' class='chooser-title'>Choose
                  {{this.chooserLabel}}</h2>
              </div>
              <button
                type='button'
                class='chooser-close'
                aria-label='Close'
                {{on 'click' this.closeChooser}}
              >✕</button>
            </div>
            <@context.searchResultsComponent
              @query={{this.chooserQuery}}
              @mode='none'
              @overlays={{false}}
              as |results|
            >
              <div class='chooser-grid'>
                {{! Upload-new is always present so an empty category can still
                    be filled straight from the chooser. Styled like the sidebar
                    Add tile — a dashed box with the + and label inside. }}
                <button
                  type='button'
                  class='chooser-add'
                  {{on 'click' this.uploadForChooser}}
                >
                  <span class='chooser-add-ico'>+</span>
                  <span class='chooser-add-lbl'>Upload New</span>
                </button>
                {{#each results.entries key='id' as |entry|}}
                  <button
                    type='button'
                    class='chooser-item'
                    {{on 'click' (fn this.chooseGarment entry.id)}}
                  >
                    <span class='chooser-thumb'><entry.component /></span>
                  </button>
                {{/each}}
              </div>
              {{#unless results.entries.length}}
                {{#unless results.isLoading}}
                  <div class='chooser-empty'>
                    <span>No {{this.chooserLabel}} garments yet.</span>
                  </div>
                {{/unless}}
              {{/unless}}
            </@context.searchResultsComponent>
          </div>
        </:tools>
      </Popover>

    </div>

    <style scoped>
      .hidden-input {
        display: none;
      }

      /* Headings carry semantics only — keep their per-class typography and
         drop the default UA block margins so layout is unchanged. */
      .app :is(h1, h2, h3) {
        margin: 0;
        font: inherit;
      }

      .app {
        /* ── Surfaces (warm cream → white, low-contrast neutrals) ── */
        --bg: #f6f4f0;
        --surface: #ffffff;
        --surface2: #f1efea;
        --border: #e4e1d9;
        --border-soft: rgba(20, 18, 14, 0.08);

        /* ── Text (near-black primary, warm-gray secondary) ── */
        --text: #1a1a1c;
        --muted: #8c887d;
        --text-2: #6b675e;

        /* ── Gold = the PRIMARY / hero action color ── */
        --gold: #c19a4b;
        --gold-deep: #a9762b;
        --gold-soft: color-mix(in srgb, var(--gold) 14%, #fff);
        --primary-grad: linear-gradient(135deg, #cba85a, var(--gold-deep));

        /* ── Near-black = neutral/secondary contrast (e.g. "All" pill) ── */
        --accent: #1a1a1c;
        --accent-2: #3a3a40;
        --accent-dim: rgba(20, 20, 22, 0.06);
        --danger: #d4452f;

        /* ── Type scale (matches mockup: bold display, letter-spaced labels) ── */
        --t-display: 700 22px/1.15
          var(--boxel-font-family, system-ui, sans-serif);
        --t-heading: 800 15px/1.2
          var(--boxel-font-family, system-ui, sans-serif);
        --t-label: 700 11px/1 var(--boxel-font-family, system-ui, sans-serif);
        --t-label-ls: 0.12em;

        --r: 14px;
        --rs: 10px;
        --shadow: 0 10px 34px rgba(30, 27, 20, 0.12);
        display: flex;
        flex-direction: column;
        /* Height that works for both host layouts:
           - Desktop host is AUTO-height → a `%` max-height is ignored, so this
             stays 100dvh and the app actually has a height (not "auto").
           - Mobile host gives a DEFINITE card region → max-height:100% clamps
             the 100dvh down to that region, so nothing overshoots under the
             host's header / bottom bar.
           (A @container rule can't restyle .app — it's its own container — so
           this base rule is the single source of truth for the app height.) */
        height: 100dvh;
        max-height: 100%;
        background:
          radial-gradient(
            130% 90% at 85% -10%,
            rgba(184, 137, 59, 0.1),
            transparent 55%
          ),
          linear-gradient(180deg, #ffffff 0%, var(--bg) 100%);
        color: var(--text);
        font-family: var(--boxel-font-family, system-ui, sans-serif);
        font-size: 13px;
        -webkit-font-smoothing: antialiased;
        container-type: size;
        container-name: app;
        overflow: hidden;
        position: relative;
        min-height: 0;
      }

      /* ── Model strip ── */
      .model-strip {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 12px 18px;
        background: rgba(255, 255, 255, 0.7);
        backdrop-filter: blur(8px);
        border-bottom: 1px solid var(--border-soft);
        flex-shrink: 0;
        overflow: visible;
        position: relative;
        z-index: 20;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-shrink: 0;
      }
      .brand-mark {
        color: var(--gold);
        font-size: 16px;
        line-height: 1;
      }
      .brand-name {
        font-size: 15px;
        font-weight: 800;
        letter-spacing: 0.01em;
        color: var(--text);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        max-width: 40cqw;
      }
      .model-scroll {
        display: flex;
        gap: 10px;
        overflow-x: auto;
        flex: 0 1 auto;
        scrollbar-width: none;
        padding: 4px;
      }
      .model-scroll::-webkit-scrollbar {
        display: none;
      }
      .model-thumb-wrap {
        position: relative;
        flex-shrink: 0;
      }
      .model-unlink {
        position: absolute;
        top: -3px;
        right: -3px;
        width: 18px;
        height: 18px;
        border-radius: 50%;
        background: var(--surface);
        border: 1px solid var(--border);
        color: #555;
        font-size: 9px;
        line-height: 1;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 0;
        box-shadow: 0 2px 6px rgba(30, 27, 20, 0.22);
        transition:
          background 0.12s,
          color 0.12s,
          transform 0.12s;
        z-index: 3;
      }
      .model-unlink:hover {
        background: var(--danger);
        color: #fff;
        border-color: var(--danger);
        transform: scale(1.1);
      }
      /* Add-model: a circular trigger that opens a text popover */
      .model-add {
        position: relative;
        flex-shrink: 0;
      }
      /* When no model is linked yet, push the lone placeholder to the right */
      .model-add--solo {
        margin-left: auto;
      }
      .model-add-circle {
        width: 46px;
        height: 46px;
        border-radius: 50%;
        border: 1.5px dashed var(--border);
        background: var(--surface);
        color: var(--muted);
        font-size: 22px;
        font-weight: 300;
        line-height: 1;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 0;
        transition:
          border-color 0.2s,
          color 0.2s,
          transform 0.2s,
          background 0.2s;
      }
      .model-add-circle:hover:not(:disabled),
      .model-add-circle.is-open {
        border-color: var(--accent);
        color: var(--accent);
        background: var(--accent-dim);
        transform: scale(1.06);
      }
      .model-add-circle:disabled {
        opacity: 0.4;
        cursor: not-allowed;
      }
      .menu-backdrop {
        position: fixed;
        inset: 0;
        background: transparent;
        border: none;
        padding: 0;
        cursor: default;
        z-index: 40;
      }
      .model-menu {
        position: absolute;
        top: calc(100% + 10px);
        right: 0;
        min-width: 200px;
        background: var(--surface);
        border: 1px solid var(--border-soft);
        border-radius: var(--rs);
        box-shadow: var(--shadow);
        padding: 8px;
        display: flex;
        flex-direction: column;
        gap: 2px;
        z-index: 50;
        animation: menu-pop 0.16s ease-out;
        transform-origin: top right;
      }
      @keyframes menu-pop {
        from {
          opacity: 0;
          transform: translateY(-6px) scale(0.97);
        }
      }
      .model-menu-title {
        font-size: 9px;
        font-weight: 800;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--muted);
        padding: 6px 10px 4px;
      }
      .model-menu-item {
        text-align: left;
        background: none;
        border: none;
        border-radius: 8px;
        padding: 10px 10px;
        font-size: 13px;
        font-weight: 600;
        color: var(--text);
        cursor: pointer;
        transition:
          background 0.12s,
          color 0.12s,
          padding-left 0.12s;
      }
      .model-menu-item:hover {
        background: var(--accent-dim);
        color: var(--gold);
        padding-left: 14px;
      }
      .model-thumb {
        flex-shrink: 0;
        width: 46px;
        height: 46px;
        border-radius: 50%;
        overflow: hidden;
        border: 2px solid var(--border);
        cursor: pointer;
        padding: 0;
        background: var(--surface2);
        transition:
          border-color 0.2s,
          transform 0.2s,
          box-shadow 0.2s;
      }
      .model-thumb:hover:not(:disabled) {
        border-color: var(--accent);
        transform: scale(1.08);
      }
      .model-thumb--active {
        border-color: var(--accent);
        transform: scale(1.04);
      }
      .model-thumb:disabled {
        opacity: 0.35;
        cursor: not-allowed;
      }
      .model-thumb-img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        object-position: top;
        display: block;
      }
      .model-thumb-empty {
        width: 100%;
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--muted);
        font-size: 1.1rem;
      }

      /* ── Add button ── */
      .add-btn {
        flex-shrink: 0;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.04em;
        color: var(--text);
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 999px;
        padding: 7px 14px;
        cursor: pointer;
        white-space: nowrap;
        box-shadow: 0 1px 3px rgba(30, 27, 20, 0.06);
        transition:
          background 0.18s,
          color 0.18s,
          border-color 0.18s,
          transform 0.12s;
      }
      .add-btn:hover {
        background: var(--accent);
        border-color: var(--accent);
        color: #fff;
        transform: translateY(-1px);
      }
      .add-btn-ico {
        font-size: 13px;
        line-height: 1;
      }

      /* ── Main ── */
      main {
        flex: 1;
        display: flex;
        min-height: 0;
        overflow: visible;
      }

      /* ── Sidebar (garments) ── */
      .sidebar {
        width: 34%;
        min-width: 0;
        border-right: 1px solid var(--border-soft);
        display: flex;
        flex-direction: column;
        overflow: hidden;
        flex-shrink: 0;
        background: rgba(255, 255, 255, 0.5);
      }
      .sidebar-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 16px 16px 10px;
        flex-shrink: 0;
      }
      .sidebar-title {
        font-size: 11px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.18em;
        color: var(--text);
      }
      .filter-row {
        display: flex;
        flex-wrap: wrap;
        gap: 5px;
        padding: 0 14px 12px;
        flex-shrink: 0;
      }
      .filter-pill {
        font-size: 10px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        padding: 5px 11px;
        border-radius: 999px;
        border: 1px solid var(--border);
        background: none;
        color: #6b675e;
        cursor: pointer;
        transition: all 0.15s;
      }
      .filter-pill:hover {
        border-color: var(--accent);
        background: var(--surface2);
      }
      .filter-pill--on {
        background: linear-gradient(135deg, var(--accent), var(--accent-2));
        border-color: transparent;
        color: #fff;
        box-shadow: 0 2px 10px rgba(20, 20, 22, 0.2);
      }
      /* Keep the active pill's gradient + white text on hover — the base
         :hover rule would otherwise out-specify and recolor it. */
      .filter-pill--on:hover {
        background: linear-gradient(135deg, var(--accent), var(--accent-2));
        color: #fff;
      }
      /* Categorised garment sections */
      .garment-sections {
        flex: 1;
        overflow-y: auto;
        padding: 4px 16px 18px;
        display: flex;
        flex-direction: column;
        gap: 20px;
      }
      .gsection {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .gsection-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
      }
      .gsection-title {
        font-size: 11px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.14em;
        color: var(--text);
      }
      .view-all {
        background: none;
        border: none;
        padding: 0;
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.02em;
        color: var(--muted);
        cursor: pointer;
        transition: color 0.15s;
      }
      .view-all:hover {
        color: var(--accent);
      }
      .gsection-grid {
        display: grid;
        grid-template-columns: 1fr 1fr 1fr;
        gap: 10px;
      }
      .garment-item {
        position: relative;
        background: var(--surface2);
        border: 1.5px solid transparent;
        border-radius: 14px;
        overflow: hidden;
        cursor: pointer;
        aspect-ratio: 1;
        display: flex;
        align-items: center;
        justify-content: center;
        transition:
          opacity 0.15s,
          border-color 0.15s,
          transform 0.15s;
      }
      .garment-item:hover {
        border-color: var(--gold);
        transform: translateY(-3px);
      }
      .garment-item--off {
        opacity: 0.4;
        pointer-events: none;
      }
      /* The tile renders the garment's prerendered fitted component — let it
         fill the square footprint. */
      .garment-item > * {
        width: 100%;
        height: 100%;
      }
      /* Add placeholder tile — shares the garment-item footprint */
      .garment-add {
        aspect-ratio: 1;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 4px;
        background: var(--surface2);
        border: 1.5px dashed var(--border);
        border-radius: 14px;
        color: var(--muted);
        cursor: pointer;
        transition:
          transform 0.18s,
          border-color 0.15s,
          color 0.15s,
          background 0.15s;
      }
      .garment-add:hover:not(:disabled) {
        transform: translateY(-2px);
        border-color: var(--gold);
        color: var(--gold);
        background: color-mix(in srgb, var(--gold) 6%, var(--surface2));
      }
      .garment-add:disabled {
        opacity: 0.4;
        cursor: not-allowed;
      }
      .garment-add-ico {
        font-size: 22px;
        font-weight: 300;
        line-height: 1;
      }
      .garment-add-lbl {
        font-size: 9px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
      }
      /* Per-category loading skeleton — shimmer tile matching garment-item */
      .garment-skeleton {
        aspect-ratio: 1;
        border-radius: 14px;
        background: linear-gradient(
          100deg,
          var(--surface2) 30%,
          rgba(255, 255, 255, 0.6) 50%,
          var(--surface2) 70%
        );
        background-size: 200% 100%;
        animation: garment-shimmer 1.2s ease-in-out infinite;
      }
      @keyframes garment-shimmer {
        from {
          background-position: 200% 0;
        }
        to {
          background-position: -200% 0;
        }
      }

      /* ── Stage (right side: slots + preview + actions) ── */
      .stage {
        flex: 1;
        display: flex;
        flex-direction: column;
        padding: 16px;
        overflow: visible;
        min-width: 0;
      }
      .stage-body {
        flex: 1;
        display: flex;
        /* nowrap so the preview sizes to the allotted height, not the tall
           image's intrinsic height (wrap let it overflow and get clipped). */
        flex-wrap: nowrap;
        gap: 16px;
        min-height: 0;
        overflow: hidden;
      }
      .preview {
        position: relative;
        flex: 1;
        display: flex;
        min-width: 0;
        /* Shrink to the height the flex parent allots instead of growing to the
           tall portrait image's intrinsic height (default min-height:auto). */
        min-height: 0;
        overflow: hidden;
      }

      /* Right info column */
      .side-col {
        display: flex;
        flex-direction: column;
        gap: 16px;
        overflow-y: auto;
      }
      .side-card {
        background: var(--surface);
        border: 1px solid var(--border-soft);
        border-radius: 16px;
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 12px;
        box-shadow: 0 4px 16px rgba(30, 27, 20, 0.05);
      }
      .side-card-title {
        font-size: 10px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.16em;
        color: var(--muted);
      }
      .view-seg {
        display: flex;
        gap: 4px;
        background: var(--surface2);
        border-radius: 999px;
        padding: 4px;
      }
      .view-seg-btn {
        flex: 1;
        padding: 8px 0;
        border: none;
        background: none;
        border-radius: 999px;
        font-size: 11px;
        font-weight: 700;
        color: var(--muted);
        cursor: pointer;
        transition:
          background 0.15s,
          color 0.15s;
      }
      .view-seg-btn:disabled {
        opacity: 0.4;
        cursor: default;
      }
      .view-seg-btn--on {
        background: color-mix(in srgb, var(--gold) 22%, #fff);
        color: var(--gold);
        box-shadow: 0 1px 4px rgba(184, 137, 59, 0.25);
      }
      /* Before a result exists, Front is the active view — don't gray it out */
      .view-seg-btn:first-child:not(:disabled) {
        color: var(--text);
      }
      .side-tip {
        margin: 0;
        font-size: 12px;
        line-height: 1.5;
        color: #6b675e;
      }

      /* View angle overlay (right side of preview) */
      .view-overlay {
        position: absolute;
        top: 50%;
        right: 14px;
        transform: translateY(-50%);
        z-index: 5;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .vo-btn {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 4px;
        padding: 10px 10px 8px;
        border-radius: 14px;
        border: 1px solid var(--border-soft);
        background: rgba(255, 255, 255, 0.88);
        backdrop-filter: blur(6px);
        color: var(--muted);
        cursor: pointer;
        min-width: 52px;
        box-shadow: 0 2px 10px rgba(30, 27, 20, 0.1);
        transition:
          background 0.15s,
          color 0.15s,
          border-color 0.15s;
      }
      .vo-btn:disabled {
        opacity: 0.35;
        cursor: not-allowed;
      }
      .vo-btn--on {
        background: color-mix(in srgb, var(--gold) 16%, #fff);
        border-color: color-mix(in srgb, var(--gold) 40%, transparent);
        color: var(--gold);
        box-shadow: 0 2px 12px rgba(184, 137, 59, 0.2);
      }
      .vo-icon {
        width: 22px;
        height: 22px;
        flex-shrink: 0;
      }
      .vo-lbl {
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.04em;
      }
      .preview-hint {
        position: absolute;
        bottom: 14px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 5;
        display: flex;
        align-items: center;
        gap: 7px;
        padding: 9px 18px;
        background: rgba(22, 21, 26, 0.72);
        backdrop-filter: blur(6px);
        border-radius: 999px;
        color: rgba(255, 255, 255, 0.9);
        font-size: 11px;
        font-weight: 600;
        white-space: nowrap;
        pointer-events: none;
      }
      .preview-hint-ico {
        color: var(--gold);
        font-size: 12px;
      }
      .sq-body--photo {
        border-radius: 50% !important;
      }
      .sq-img--cover {
        object-fit: cover !important;
        object-position: top;
        padding: 0 !important;
      }
      .sq-slot--model:not(.sq-slot--off):hover .sq-body {
        border-color: var(--gold);
        background: color-mix(in srgb, var(--gold) 6%, #fff);
      }
      .sq-model-menu {
        position: absolute;
        top: calc(100% + 8px);
        left: 50%;
        transform: translateX(-50%);
        z-index: 60;
        background: var(--surface);
        border: 1px solid var(--border-soft);
        border-radius: var(--rs);
        box-shadow: var(--shadow);
        padding: 6px;
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 160px;
        animation: menu-pop 0.14s ease-out;
        transform-origin: top center;
      }
      .sq-model-item {
        text-align: left;
        background: none;
        border: none;
        border-radius: 7px;
        padding: 9px 10px;
        font-size: 12px;
        font-weight: 600;
        color: var(--text);
        cursor: pointer;
        white-space: nowrap;
        transition: background 0.12s;
      }
      .sq-model-item:hover {
        background: var(--accent-dim);
        color: var(--gold);
      }
      .sq-divider {
        width: 1px;
        background: var(--border-soft);
        align-self: stretch;
        margin: 0 14px;
        flex-shrink: 0;
      }
      /* Bottom action bar */
      .action-bar {
        flex-shrink: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 14px;
        padding: 18px 24px 24px;
      }
      .act-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        min-width: 200px;
        padding: 15px 28px;
        border-radius: 999px;
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        cursor: pointer;
        transition:
          transform 0.15s,
          box-shadow 0.2s,
          opacity 0.15s;
      }
      .act-btn--primary {
        background: var(--primary-grad);
        color: #fff;
        border: none;
        box-shadow:
          0 8px 22px rgba(184, 137, 59, 0.34),
          inset 0 1px 0 rgba(255, 255, 255, 0.22);
      }
      .act-btn--primary:hover:not(:disabled) {
        transform: translateY(-1px);
        box-shadow:
          0 12px 30px rgba(184, 137, 59, 0.44),
          inset 0 1px 0 rgba(255, 255, 255, 0.22);
      }
      .act-btn--ghost {
        background: var(--surface);
        color: var(--text);
        border: 1px solid var(--border);
        min-width: 0;
      }
      .act-btn--ghost:hover:not(:disabled) {
        border-color: var(--accent);
      }
      .act-btn:disabled {
        opacity: 0.4;
        cursor: not-allowed;
      }
      .act-btn--busy {
        opacity: 0.65;
        cursor: wait;
      }
      .act-ico {
        font-size: 14px;
        line-height: 1;
      }

      /* Stage tools */
      .stage-tools {
        position: absolute;
        top: 16px;
        right: 16px;
        z-index: 6;
        display: flex;
        gap: 8px;
      }
      .tool-btn {
        width: 38px;
        height: 38px;
        border-radius: 12px;
        background: rgba(255, 255, 255, 0.92);
        border: 1px solid var(--border-soft);
        color: var(--text);
        font-size: 16px;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 2px 8px rgba(30, 27, 20, 0.12);
        transition:
          background 0.15s,
          transform 0.12s;
      }
      .tool-btn:hover {
        transform: translateY(-1px);
        background: #fff;
      }

      /* ── Slots bar (horizontal card of garment tiles with icons) ── */
      .slots-bar {
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 20px 24px 16px;
        flex-shrink: 0;
      }
      .body-hint {
        /* Floats over the preview at every breakpoint so the body-detection
           notice is always visible, regardless of the Tips column. */
        display: flex;
        position: absolute;
        left: 16px;
        bottom: 16px;
        z-index: 5;
        align-items: flex-start;
        gap: 8px;
        max-width: min(360px, calc(100% - 32px));
        padding: 8px 14px;
        border-radius: 12px;
        background: color-mix(in srgb, var(--gold-soft) 92%, transparent);
        backdrop-filter: blur(8px);
        border: 1px solid color-mix(in srgb, var(--gold) 30%, transparent);
        box-shadow: 0 6px 20px rgba(30, 27, 20, 0.12);
        color: var(--gold-deep);
        font-size: 12px;
        line-height: 1.45;
        pointer-events: none;
      }
      .body-hint-ico {
        flex-shrink: 0;
        font-weight: 700;
      }
      .slots-row {
        display: flex;
        align-items: flex-start;
        gap: 12px;
        min-width: 0;
        overflow-x: auto;
        scrollbar-width: none;
        padding: 16px 20px;
        background: var(--surface);
        border: 1px solid var(--border-soft);
        border-radius: 22px;
        box-shadow: 0 8px 26px rgba(30, 27, 20, 0.06);
      }
      .slots-row::-webkit-scrollbar {
        display: none;
      }

      /* Square slot tiles */
      .sq-slot {
        /* Garment slots are the chooser Popover's anchor. The Popover bridges
           these onto its portaled root so the surface stays transparent (the
           .chooser-pop box paints the card). 'floating' elevation doubles
           --bx-popover-radius, so 10px → a 20px root matching .chooser-pop. */
        --bx-popover-bg: transparent;
        --bx-popover-radius: 6px;
        position: relative;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
        cursor: pointer;
        transition: transform 0.12s;
        width: 88px;
        flex-shrink: 0;
      }
      .sq-slot:not(.sq-slot--off):hover {
        transform: translateY(-1px);
      }
      /* "+" badge top-right */
      .sq-badge {
        position: absolute;
        top: 6px;
        right: 6px;
        width: 20px;
        height: 20px;
        border-radius: 50%;
        background: var(--surface);
        border: 1px solid var(--border);
        color: var(--muted);
        font-size: 14px;
        font-weight: 300;
        line-height: 1;
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 3;
        pointer-events: none;
        box-shadow: 0 1px 4px rgba(30, 27, 20, 0.1);
      }
      /* Hide the "+" badge once filled (the ✕ remove button takes its place) */
      .sq-slot--filled .sq-badge {
        display: none;
      }
      .sq-badge--remove {
        pointer-events: auto;
        cursor: pointer;
        font-size: 11px;
        padding: 0;
        transition:
          color 0.15s,
          border-color 0.15s;
      }
      .sq-badge--remove:hover:not(:disabled) {
        color: var(--danger);
        border-color: var(--danger);
      }
      .sq-badge--remove:disabled {
        cursor: not-allowed;
        opacity: 0.4;
      }
      /* Category icon */
      .sq-icon {
        width: 40px;
        height: 40px;
        color: var(--text);
        flex-shrink: 0;
      }
      .sq-item-name {
        font-size: 9px;
        font-weight: 600;
        color: var(--muted);
        text-align: center;
        padding: 4px;
      }
      .sq-body {
        width: 88px;
        height: 88px;
        border-radius: 18px;
        border: 1.5px solid var(--border);
        background: var(--surface);
        position: relative;
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        transition:
          border-color 0.18s,
          box-shadow 0.18s,
          background 0.15s;
        flex-shrink: 0;
        box-shadow: 0 2px 8px rgba(30, 27, 20, 0.06);
      }
      .sq-slot:not(.sq-slot--filled):not(.sq-slot--off):hover .sq-body {
        border-color: var(--gold);
        background: color-mix(in srgb, var(--gold) 5%, #fff);
      }
      .sq-slot--filled .sq-body {
        border-color: var(--gold);
        border-width: 2px;
        background: #fff;
        box-shadow:
          0 3px 10px rgba(30, 27, 20, 0.14),
          0 0 0 3px color-mix(in srgb, var(--gold) 14%, transparent);
      }
      /* Active slot: gold border (last tapped to open chooser) */
      .sq-slot--active .sq-body {
        border-color: var(--gold);
        border-width: 2px;
        box-shadow: 0 0 0 3px color-mix(in srgb, var(--gold) 16%, transparent);
      }
      .sq-slot--over .sq-body {
        border-color: var(--accent);
        box-shadow:
          0 0 0 3px var(--accent-dim),
          inset 0 0 12px var(--accent-dim);
        background: var(--accent-dim);
      }
      .sq-slot--off {
        opacity: 0.45;
        pointer-events: none;
      }
      /* Slot covered by a conflicting selection (e.g. top/bottom under a dress).
         Dimmed as a hint, but still tappable — picking here auto-clears the
         conflicting garment. */
      .sq-slot--covered:not(.sq-slot--filled) {
        opacity: 0.4;
      }
      .sq-img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        padding: 0;
        background: #fff;
        display: block;
      }
      .sq-remove {
        position: absolute;
        top: -6px;
        right: -6px;
        width: 22px;
        height: 22px;
        border-radius: 50%;
        background: #fff;
        border: 1px solid var(--border-soft);
        color: #444;
        font-size: 10px;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        line-height: 1;
        z-index: 4;
        box-shadow: 0 2px 6px rgba(30, 27, 20, 0.18);
        transition:
          background 0.12s,
          color 0.12s;
      }
      .sq-remove:hover {
        background: var(--danger);
        color: #fff;
        border-color: var(--danger);
      }
      .sq-lbl {
        font-size: 10px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        color: #6b675e;
        max-width: 100%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sq-slot--filled .sq-lbl {
        color: var(--text);
      }
      .sq-slot--active .sq-lbl {
        color: var(--gold);
      }

      /* Generate button — lives inside the model-strip flex row, pushed to the right. */
      .gen-action {
        margin-left: auto;
        flex-shrink: 0;
        display: flex;
      }
      .gen-btn {
        flex-shrink: 0;
        min-width: 180px;
        padding: 13px 28px;
        background: var(--primary-grad);
        color: #fff;
        border: none;
        border-radius: 999px;
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        white-space: nowrap;
        box-shadow:
          0 6px 18px rgba(184, 137, 59, 0.32),
          inset 0 1px 0 rgba(255, 255, 255, 0.2);
        transition:
          transform 0.15s,
          box-shadow 0.2s,
          opacity 0.15s;
      }
      .gen-btn:hover:not(:disabled) {
        transform: translateY(-1px);
        box-shadow:
          0 9px 26px rgba(184, 137, 59, 0.42),
          inset 0 1px 0 rgba(255, 255, 255, 0.2);
      }
      .gen-btn:disabled {
        opacity: 0.3;
        cursor: not-allowed;
      }
      .gen-btn--busy {
        opacity: 0.65;
        cursor: wait;
      }
      .gen-btn--done {
        background: #2d7455;
        color: #fff;
      }
      .gen-spin {
        width: 12px;
        height: 12px;
        border: 2px solid rgba(255, 255, 255, 0.35);
        border-top-color: #fff;
        border-radius: 50%;
        animation: spin 0.65s linear infinite;
      }
      .err-msg {
        font-size: 11px;
        color: var(--danger);
        padding: 8px 12px;
        flex-shrink: 0;
      }

      /* Result area — the gray rounded "stage" the model stands on */
      .result-area {
        position: relative;
        flex: 1;
        min-width: 0;
        /* Shrink with the flex chain instead of expanding to the image's
           intrinsic height (default min-height:auto). */
        min-height: 0;
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        margin: 0 0 26px 26px;
        padding: 20px;
        border-radius: 24px;
        background:
          radial-gradient(
            80% 60% at 50% 18%,
            rgba(184, 137, 59, 0.06),
            transparent 70%
          ),
          var(--surface2);
      }

      /* ── Generation progress pill ── */
      /* Top-centered so it clears the pose pill (left) and the tool buttons
         (right) while side/back views generate after the front is ready. */
      .gen-pill {
        position: absolute;
        top: 16px;
        left: 16px;
        z-index: 5;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 7px 12px;
        background: rgba(20, 20, 22, 0.82);
        color: #fff;
        border-radius: 999px;
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.04em;
        backdrop-filter: blur(6px);
        box-shadow: 0 4px 14px rgba(20, 20, 22, 0.25);
      }
      .gen-pill-dot {
        width: 7px;
        height: 7px;
        border-radius: 50%;
        background: var(--gold);
        animation: pill-pulse 1s ease-in-out infinite;
      }
      @keyframes pill-pulse {
        50% {
          opacity: 0.25;
        }
      }
      .gen-pill-step {
        font-variant-numeric: tabular-nums;
        opacity: 0.7;
      }
      .result-empty {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 12px;
        width: 100%;
        color: var(--muted);
        font-size: 12px;
      }
      .result-empty-ico {
        font-size: 2rem;
        opacity: 0.3;
      }
      .result-model {
        position: relative;
        width: 100%;
        height: 100%;
        flex-shrink: 0;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .result-model-img {
        max-width: 100%;
        max-height: 100%;
        object-fit: contain;
        display: block;
      }
      .result-model-hint {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        padding: 14px 14px 12px;
        text-align: center;
        font-size: 11px;
        color: #fff;
        background: linear-gradient(transparent, rgba(0, 0, 0, 0.72));
        display: flex;
        flex-direction: column;
        gap: 4px;
      }
      .result-model-note {
        font-size: 10px;
        font-weight: 500;
        line-height: 1.35;
        opacity: 0.8;
      }
      .result-note {
        max-width: 280px;
        font-size: 10px;
        line-height: 1.4;
        opacity: 0.7;
      }
      .result-placeholder {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 14px;
        width: 100%;
        height: 100%;
        flex-shrink: 0;
        color: var(--muted);
        font-size: 12px;
        border-radius: 18px;
        background: linear-gradient(
          100deg,
          var(--surface) 30%,
          #e9e6df 50%,
          var(--surface) 70%
        );
        background-size: 200% 100%;
        animation: skeleton 1.4s ease-in-out infinite;
      }
      @keyframes skeleton {
        from {
          background-position: 200% 0;
        }
        to {
          background-position: -200% 0;
        }
      }
      .big-spin {
        width: 32px;
        height: 32px;
        border: 3px solid var(--border);
        border-top-color: var(--accent);
        border-radius: 50%;
        animation: spin 0.8s linear infinite;
      }

      /* ── Carousel ── */
      .carousel {
        position: relative;
        overflow: hidden;
        width: 100%;
        height: 100%;
        flex-shrink: 0;
        border-radius: 18px;
        cursor: grab;
        touch-action: pan-y;
        user-select: none;
      }
      .carousel:active {
        cursor: grabbing;
      }
      .slide-img {
        -webkit-user-drag: none;
        user-drag: none;
      }
      .carousel-track {
        display: flex;
        height: 100%;
        transition: transform 0.33s cubic-bezier(0.4, 0, 0.2, 1);
      }
      .carousel-slide {
        flex: 0 0 100%;
        position: relative;
      }
      .slide-img {
        width: 100%;
        height: 100%;
        object-fit: contain;
        display: block;
      }
      .slide-empty {
        width: 100%;
        height: 100%;
        min-height: 200px;
        background: var(--surface2);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 10px;
        color: var(--muted);
        font-size: 11px;
      }
      .slide-empty-lbl {
        font-size: 10px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        opacity: 0.4;
      }
      .slide-spin {
        width: 20px;
        height: 20px;
        border: 2px solid var(--border);
        border-top-color: var(--accent);
        border-radius: 50%;
        animation: spin 0.7s linear infinite;
      }
      .slide-badge {
        position: absolute;
        bottom: 10px;
        left: 12px;
        font-size: 9px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        color: rgba(255, 255, 255, 0.85);
        background: rgba(0, 0, 0, 0.5);
        padding: 2px 8px;
        border-radius: 999px;
        backdrop-filter: blur(4px);
      }
      .c-arrow {
        position: absolute;
        top: 50%;
        transform: translateY(-50%);
        background: rgba(0, 0, 0, 0.5);
        border: none;
        color: #fff;
        font-size: 22px;
        width: 34px;
        height: 34px;
        border-radius: 50%;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 0;
        backdrop-filter: blur(4px);
        transition: background 0.15s;
      }
      .c-arrow:hover:not(:disabled) {
        background: rgba(0, 0, 0, 0.72);
      }
      .c-arrow:disabled {
        opacity: 0.2;
        cursor: default;
      }
      .c-arrow--l {
        left: 10px;
      }
      .c-arrow--r {
        right: 10px;
      }
      .c-dots {
        position: absolute;
        bottom: 10px;
        left: 50%;
        transform: translateX(-50%);
        display: flex;
        gap: 5px;
      }
      .c-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.3);
        border: none;
        cursor: pointer;
        padding: 0;
        transition:
          background 0.2s,
          transform 0.2s;
      }
      .c-dot--on {
        background: #fff;
        transform: scale(1.35);
      }

      /* ── Desktop styling studio ── */
      @container app (width >= 640px) {
        .sidebar {
          width: 340px;
          flex: 0 0 340px;
          background: rgba(255, 255, 255, 0.62);
        }
        .slots-row {
          gap: 16px;
        }
        /* Smaller slot tiles + less top margin on desktop so the preview
           section is the visual focus. */
        .slots-bar {
          padding: 8px 24px 14px;
        }
        .sq-slot {
          width: 62px;
        }
        .sq-body {
          width: 62px;
          height: 62px;
          border-radius: 14px;
        }
        .sq-icon {
          width: 26px;
          height: 26px;
        }
        .sq-lbl {
          font-size: 9px;
        }
        /* The slots bar stays pinned at the top; the stage body below it is the
           scroll area (overflow-y:auto). slots-bar is a sibling ABOVE
           stage-body in .stage, so when stage-body scrolls the bar never moves.
           Without this the square is clipped when it's taller than the stage. */
        .stage-body {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 26px;
          padding: 0 26px 26px;
          overflow-y: auto;
        }
        .preview {
          overflow: visible;
          /* Square (1:1 output), capped so it isn't enormous, centered. If the
             window is short the stage body scrolls — the slots bar stays. */
          flex: 0 0 auto;
          width: 100%;
          max-width: 560px;
          aspect-ratio: 1;
          margin-inline: auto;
          min-height: 0;
          align-items: center;
          justify-content: center;
        }
        .result-area {
          margin: 0;
          flex: none;
          width: 100%;
          height: 100%;
          min-height: 0;
        }
        .side-col {
          flex-shrink: 0;
        }
        /* Bottom action bar is mobile-only */
        .action-bar {
          display: none;
        }
        /* Header model avatars + Add Model live in the slots bar on desktop */
        .model-strip .model-scroll,
        .model-strip .add-model-btn {
          display: none;
        }
      }

      /* Wide enough for the info column to sit beside the preview without
         squeezing it — go two-column. */
      @container app (width >= 960px) {
        /* Info column beside the preview: flex row, centered as a group. The
           square preview is capped so it stays reasonable; the stage body
           scrolls if a short window can't fit it (slots bar stays pinned). */
        .stage-body {
          flex-direction: row;
          align-items: flex-start;
          justify-content: center;
        }
        .preview {
          overflow: hidden;
          flex: 1 1 auto;
          max-width: 560px;
          margin-inline: 0;
        }
        .side-col {
          flex: 0 0 240px;
          overflow-y: auto;
        }
      }

      /* Wider desktop — roomier sidebar */
      @container app (width >= 1100px) {
        .sidebar {
          width: 380px;
          flex: 0 0 380px;
        }
      }

      /* ── Locked (generating or result on screen): freeze editing ── */
      .app--locked .garment-item,
      .app--locked .model-thumb,
      .app--locked .filter-pill,
      .app--locked .add-btn,
      .app--locked .sq-slot {
        pointer-events: none;
        opacity: 0.45;
      }
      /* The remove (✕) badge stays clickable even when the slot/app is locked —
         a child with pointer-events:auto overrides a pointer-events:none parent. */
      .app--locked .sq-slot--model .sq-badge--remove,
      .sq-slot--off .sq-badge--remove {
        pointer-events: auto;
        opacity: 1;
        cursor: pointer;
      }

      /* ── Lightbox ── */
      .lightbox-overlay {
        position: absolute;
        inset: 0;
        background: rgba(20, 18, 14, 0.82);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 40px;
        z-index: 200;
        backdrop-filter: blur(8px);
      }
      .lightbox-img {
        max-width: 100%;
        max-height: 100%;
        object-fit: contain;
        border-radius: 12px;
        box-shadow: 0 20px 60px rgba(0, 0, 0, 0.45);
      }
      /* Same circular control as the other modals (see .modal-close); only
         the absolute placement over the lightbox image is specific here. */
      .lightbox-close {
        position: absolute;
        top: 16px;
        right: 16px;
        width: 34px;
        height: 34px;
        border-radius: 50%;
        border: none;
        background: var(--surface2);
        color: var(--muted);
        font-size: 15px;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        transition:
          background 0.15s,
          color 0.15s;
      }
      .lightbox-close:hover {
        background: var(--border);
        color: var(--text);
      }

      /* ── Modal ── */
      /* Upload form content — rendered inside the catalog <Popover> (portaled
         to the host). Re-declare the app tokens it uses since they live on
         .app, out of reach once portaled. */
      .modal-pop {
        --surface: #ffffff;
        --surface2: #f1efea;
        --border: #e4e1d9;
        --border-soft: rgba(20, 18, 14, 0.08);
        --text: #1a1a1c;
        --muted: #8c887d;
        --gold: #c19a4b;
        --gold-deep: #a9762b;
        --accent: #1a1a1c;
        --accent-2: #3a3a40;
        --danger: #d4452f;
        --r: 14px;
        --rs: 10px;
        width: min(440px, 92vw);
        max-height: min(88dvh, 680px);
        background: var(--surface);
        border-radius: 12px;
        display: flex;
        flex-direction: column;
        gap: 16px;
        padding: 18px 16px;
        overflow-y: auto;
      }
      .modal-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }
      .modal-title {
        font-size: 12px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        color: var(--text);
      }
      /* Circular close button — shared with .chooser-close / .mpm-close /
         .lightbox-close so every modal dismisses through the same control. */
      .modal-close {
        background: var(--surface2);
        border: none;
        color: var(--muted);
        cursor: pointer;
        font-size: 15px;
        width: 34px;
        height: 34px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        transition:
          background 0.15s,
          color 0.15s;
      }
      .modal-close:hover {
        background: var(--border);
        color: var(--text);
      }

      /* Details */
      .details-pane {
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .preview-img {
        width: 100%;
        max-height: 220px;
        object-fit: contain;
        border-radius: var(--rs);
        background: var(--surface2);
      }
      .field-group {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .field-lbl {
        font-size: 9px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--muted);
      }
      .field-lbl-hint {
        font-weight: 400;
        text-transform: none;
        letter-spacing: 0;
        opacity: 0.7;
      }
      .field-input {
        background: var(--surface2);
        border: 1px solid var(--border);
        border-radius: var(--rs);
        padding: 9px 12px;
        color: var(--text);
        font-size: 13px;
        outline: none;
        transition: border-color 0.15s;
      }
      .field-input:focus {
        border-color: var(--accent);
      }
      .field-hint {
        font-size: 10px;
        color: var(--muted);
      }
      .field-hint strong {
        color: var(--text);
      }
      /* Click-to-upload image dropzone inside the Add popover */
      .img-drop {
        width: 100%;
        min-height: 160px;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 8px;
        padding: 16px;
        border: 1.5px dashed var(--border);
        border-radius: var(--rs);
        background: var(--surface2);
        color: var(--muted);
        cursor: pointer;
        position: relative;
        transition:
          border-color 0.15s,
          color 0.15s,
          background 0.15s;
      }
      .img-drop:hover {
        border-color: var(--gold);
        color: var(--gold);
        background: color-mix(in srgb, var(--gold) 5%, var(--surface2));
      }
      .img-drop--filled {
        border-style: solid;
        padding: 0;
        overflow: hidden;
      }
      .img-drop-ico {
        font-size: 26px;
        font-weight: 300;
        line-height: 1;
      }
      .img-drop-lbl {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.08em;
      }
      .img-drop-hint {
        position: absolute;
        bottom: 8px;
        right: 8px;
        font-size: 9px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: #fff;
        background: rgba(20, 20, 22, 0.7);
        padding: 4px 8px;
        border-radius: 999px;
      }
      .cat-option {
        text-transform: capitalize;
        font-size: 13px;
        padding: 2px 0;
      }
      .upload-err {
        font-size: 11px;
        color: var(--danger);
      }
      .save-btn {
        width: 100%;
        padding: 13px;
        background: linear-gradient(135deg, var(--accent), var(--accent-2));
        color: #fff;
        border: none;
        border-radius: var(--r);
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        cursor: pointer;
        transition: opacity 0.15s;
      }
      .save-btn:disabled {
        opacity: 0.3;
        cursor: not-allowed;
      }
      .save-btn--busy {
        opacity: 0.65;
        cursor: wait;
      }

      /* ── Garment chooser sheet ── */
      /* Chooser content — rendered inside the catalog <Popover> (same as the
         model picker), which portals to the host. Re-declare the app tokens
         the content uses since they live on .app, out of reach once portaled.
         Sized via dvh here is safe: the popover is fixed to the host viewport,
         not clipped by .app. */
      .chooser-pop {
        --surface: #ffffff;
        --surface2: #f1efea;
        --border: #e4e1d9;
        --border-soft: rgba(20, 18, 14, 0.08);
        --text: #1a1a1c;
        --muted: #8c887d;
        --gold: #c19a4b;
        --gold-deep: #a9762b;
        --accent: #1a1a1c;
        --accent-2: #3a3a40;
        --danger: #d4452f;
        --r: 14px;
        --rs: 10px;
        container: chooser-pop / inline-size;
        width: min(680px, 92vw);
        max-height: min(80dvh, 640px);
        background: var(--surface);
        border-radius: 12px;
        display: flex;
        flex-direction: column;
        gap: 16px;
        padding: 20px;
        overflow: hidden;
      }
      .chooser-head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 10px;
        flex-shrink: 0;
        padding-bottom: 16px;
        border-bottom: 1px solid var(--border-soft);
      }
      .chooser-head-left {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }
      .chooser-eyebrow {
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        color: var(--gold);
      }
      .chooser-title {
        font-size: 22px;
        font-weight: 800;
        letter-spacing: -0.01em;
        color: var(--text);
      }
      .chooser-head-actions {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .chooser-upload {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        font-size: 11px;
        font-weight: 700;
        color: var(--text);
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 999px;
        padding: 6px 12px;
        cursor: pointer;
        transition:
          background 0.15s,
          color 0.15s;
      }
      .chooser-upload:hover {
        background: var(--accent);
        border-color: var(--accent);
        color: #fff;
      }
      .chooser-close {
        background: var(--surface2);
        border: none;
        color: var(--muted);
        cursor: pointer;
        font-size: 15px;
        width: 34px;
        height: 34px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        transition:
          background 0.15s,
          color 0.15s;
      }
      .chooser-close:hover {
        background: var(--border);
        color: var(--text);
      }
      .chooser-grid {
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
        gap: 14px;
        align-content: start;
        padding: 2px;
      }
      .chooser-item {
        display: flex;
        flex-direction: column;
        gap: 8px;
        border: none;
        background: none;
        padding: 0;
        cursor: pointer;
      }
      .chooser-thumb {
        position: relative;
        aspect-ratio: 3 / 4;
        border: 1px solid var(--border-soft);
        border-radius: var(--rs);
        overflow: hidden;
        background: var(--surface2);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 2px 10px rgba(30, 27, 20, 0.08);
        transition:
          transform 0.15s,
          box-shadow 0.18s,
          border-color 0.15s;
      }
      .chooser-item:hover .chooser-thumb {
        transform: translateY(-3px);
        border-color: var(--accent);
        box-shadow:
          inset 0 0 0 2px var(--accent),
          0 12px 26px rgba(30, 27, 20, 0.18);
      }
      /* Upload tile — matches the sidebar Add tile (dashed gray box with the
         + and label centered inside). Sized 3/4 so it lines up with the
         garment thumbs in the chooser grid. */
      .chooser-add {
        aspect-ratio: 3 / 4;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 4px;
        background: var(--surface2);
        border: 1.5px dashed var(--border);
        border-radius: var(--rs);
        color: var(--muted);
        cursor: pointer;
        transition:
          transform 0.18s,
          border-color 0.15s,
          color 0.15s,
          background 0.15s;
      }
      .chooser-add:hover {
        transform: translateY(-3px);
        border-color: var(--gold);
        color: var(--gold);
        background: color-mix(in srgb, var(--gold) 6%, var(--surface2));
      }
      .chooser-add-ico {
        font-size: 26px;
        font-weight: 300;
        line-height: 1;
      }
      .chooser-add-lbl {
        font-size: 10px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
      }
      /* Thumb renders the garment's prerendered fitted component. */
      .chooser-thumb > * {
        width: 100%;
        height: 100%;
      }
      .chooser-empty {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 12px;
        padding: 28px 16px;
        color: var(--muted);
        font-size: 12px;
      }

      /* ── Model Picker Modal (mpm) ── */
      /* Model picker content — rendered inside the catalog <Popover>, which
         portals to the host (outside .app). The app's design tokens live on
         .app and won't resolve out there, so re-declare the subset this
         content uses. `container` lets the picker keep its own responsive
         rules now that the .app container is no longer an ancestor. Position,
         dim backdrop, shadow + enter animation are the Popover's job. */
      .mpm-pop {
        --surface: #ffffff;
        --surface2: #f1efea;
        --border: #e4e1d9;
        --border-soft: rgba(20, 18, 14, 0.08);
        --text: #1a1a1c;
        --muted: #8c887d;
        --gold: #c19a4b;
        --gold-deep: #a9762b;
        --accent: #1a1a1c;
        --accent-2: #3a3a40;
        --danger: #d4452f;
        --r: 14px;
        container: mpm-pop / inline-size;
        width: min(720px, 92vw);
        max-height: min(80dvh, 560px);
        background: var(--surface);
        border-radius: 12px;
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }
      .mpm-head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        padding: 28px 32px 20px;
        flex-shrink: 0;
        border-bottom: 1px solid var(--border-soft);
      }
      .mpm-head-left {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }
      .mpm-eyebrow {
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        color: var(--gold);
      }
      .mpm-title {
        font-size: 22px;
        font-weight: 800;
        letter-spacing: -0.01em;
        color: var(--text);
      }
      .mpm-close {
        background: var(--surface2);
        border: none;
        color: var(--muted);
        cursor: pointer;
        font-size: 15px;
        width: 34px;
        height: 34px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        transition:
          background 0.15s,
          color 0.15s;
      }
      .mpm-close:hover {
        background: var(--border);
        color: var(--text);
      }
      .mpm-body {
        flex: 1;
        display: flex;
        gap: 20px;
        padding: 28px 32px 32px;
        min-height: 0;
      }
      .mpm-card {
        flex: 1;
        display: flex;
        flex-direction: column;
        border-radius: 16px;
        overflow: hidden;
        cursor: pointer;
        border: 1.5px solid var(--border-soft);
        padding: 0;
        text-align: left;
        transition:
          transform 0.2s,
          box-shadow 0.2s,
          border-color 0.2s;
      }
      .mpm-card:hover {
        transform: translateY(-3px);
        box-shadow: 0 20px 52px rgba(30, 27, 20, 0.14);
        border-color: var(--border);
      }
      .mpm-visual {
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 0;
        position: relative;
        overflow: hidden;
      }
      .mpm-visual--upload {
        background:
          radial-gradient(
            ellipse 80% 60% at 50% 40%,
            rgba(184, 137, 59, 0.15),
            transparent 65%
          ),
          linear-gradient(160deg, #f6f1e9 0%, #ede4d0 100%);
      }
      .mpm-visual--link {
        background:
          radial-gradient(
            ellipse 80% 60% at 50% 40%,
            rgba(26, 26, 28, 0.05),
            transparent 65%
          ),
          linear-gradient(160deg, #f2f2f0 0%, #e9e6e0 100%);
      }
      .mpm-visual-icon {
        width: 84px;
        height: 84px;
        color: rgba(30, 27, 20, 0.4);
        flex-shrink: 0;
      }
      .mpm-visual--upload .mpm-visual-icon {
        color: var(--gold-deep);
        opacity: 0.72;
      }
      .mpm-card-content {
        flex-shrink: 0;
        background: var(--surface);
        padding: 20px 22px 24px;
        display: flex;
        flex-direction: column;
        gap: 6px;
        border-top: 1px solid var(--border-soft);
      }
      .mpm-card-title {
        font-size: 16px;
        font-weight: 800;
        color: var(--text);
        letter-spacing: -0.01em;
      }
      .mpm-card-desc {
        font-size: 12px;
        color: var(--muted);
        line-height: 1.55;
      }
      .mpm-card-cta {
        margin-top: 12px;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--accent);
        padding: 10px 18px;
        background: var(--surface2);
        border-radius: 999px;
        width: fit-content;
        transition:
          background 0.18s,
          color 0.18s;
      }
      .mpm-card--upload:hover .mpm-card-cta {
        background: var(--gold);
        color: #fff;
      }
      .mpm-card--link:hover .mpm-card-cta {
        background: var(--accent);
        color: #fff;
      }

      /* Phone: stack the two model cards and let the picker scroll. Keyed to
         the picker's own container (it's portaled out of .app). */
      @container mpm-pop (width < 640px) {
        .mpm-head {
          padding: 22px 22px 16px;
        }
        .mpm-body {
          flex-direction: column;
          overflow-y: auto;
          -webkit-overflow-scrolling: touch;
          gap: 14px;
          padding: 20px 22px 24px;
        }
        /* Let cards keep their natural height so the body scrolls instead of
           squashing the visuals/CTA out of view. */
        .mpm-card {
          flex: 0 0 auto;
        }
        .mpm-visual {
          min-height: 120px;
        }
      }

      /* Compact phones: scale the picker's titles + padding down. */
      @container mpm-pop (width < 480px) {
        .mpm-head {
          padding: 18px 18px 14px;
        }
        .mpm-title {
          font-size: 18px;
        }
        .mpm-body {
          padding: 16px 18px 20px;
        }
        .mpm-card-content {
          padding: 16px 18px 18px;
        }
        .mpm-card-title {
          font-size: 15px;
        }
        .mpm-visual-icon {
          width: 64px;
          height: 64px;
        }
      }

      /* Compact: small phones — scale modal titles, padding & grids down so
         all modal content fits without horizontal overflow */
      @container app (width < 480px) {
        /* Lightbox */
        .lightbox-overlay {
          padding: 20px;
        }
      }

      /* Narrow chooser (phone) — denser garment grid. */
      @container chooser-pop (width < 380px) {
        .chooser-title {
          font-size: 18px;
        }
        .chooser-grid {
          grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
          gap: 10px;
        }
      }

      /* Add Model button in the header strip */
      .add-model-btn {
        /* This button is the model picker Popover's anchor. The Popover
           bridges these tokens onto its portaled root, so the root surface
           stays transparent (the .mpm-pop box paints the visible card) and
           its shadow follows a matching radius. NB: the 'floating' elevation
           doubles --bx-popover-radius, so 10px → a 20px root that matches
           .mpm-pop's 20px (set it to half the panel radius). */
        --bx-popover-bg: transparent;
        --bx-popover-radius: 6px;
        flex-shrink: 0;
        display: inline-flex;
        align-items: center;
        gap: 5px;
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.04em;
        color: var(--muted);
        background: none;
        border: 1.5px dashed var(--border);
        border-radius: 999px;
        padding: 6px 14px;
        cursor: pointer;
        white-space: nowrap;
        transition:
          border-color 0.18s,
          color 0.18s;
      }
      .add-model-btn:hover:not(:disabled) {
        border-color: var(--accent);
        color: var(--accent);
      }
      .add-model-btn:disabled {
        opacity: 0.3;
        cursor: not-allowed;
      }

      /* Wider chooser → roomier garment grid. Keyed to the chooser's own
         container (it's portaled out of .app via the Popover). */
      @container chooser-pop (width >= 480px) {
        .chooser-grid {
          grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
          gap: 16px;
        }
      }

      /* The root height can't be set from a @container rule (.app is its own
         container), so switch it by VIEWPORT here. Phones fill the host's fixed
         card region exactly with height:100% — so the grid below lays every
         section out inside that height with no scroll. Desktop keeps the base
         100dvh (its host region is auto-height, where 100% would collapse). */
      @media (max-width: 640px) {
        .app {
          height: 100%;
          max-height: none;
        }
      }

      /* ───────────────────────────────────────────
         Mobile: stacked, app-like layout
         Big preview on top, tap a dropzone to pick a garment
      ─────────────────────────────────────────── */
      @container app (width < 640px) {
        /* (App height is set on the base .app rule — a @container rule can't
           restyle its own container.) */
        .app {
          font-size: 14px;
        }

        /* Header is hidden on mobile — the model slot and footer bar cover it */
        .model-strip {
          display: none;
        }
        .model-scroll {
          margin-left: auto;
        }
        .model-thumb {
          width: 42px;
          height: 42px;
        }

        /* Hide the header (gold) Try On on mobile — the footer bar handles it */
        .gen-action {
          display: none;
        }

        /* Main fills the space between header and footer */
        main {
          flex: 1;
          min-height: 0;
          order: 1;
        }
        .sidebar {
          display: none;
        }

        /* Stage is a grid filling the app's height: preview (1fr) → slots
           (auto) → action bar (auto). A grid can't overflow its tracks, so all
           three sections always fit the device height — no scroll. (Items keep
           their source order via `order`: preview 1 → slots 2 → button 3.)
           minmax(0,1fr) column + min-width:0 items let wide content (the
           scrollable slots row) shrink instead of widening the grid past the
           viewport — otherwise the preview gets cropped and a scrollbar shows. */
        .stage {
          flex: 1;
          min-width: 0;
          min-height: 0;
          padding: 0;
          display: grid;
          grid-template-rows: 1fr auto auto;
          grid-template-columns: minmax(0, 1fr);
          overflow: hidden;
        }
        .stage-body {
          order: 1;
          min-width: 0;
          min-height: 0;
        }
        .slots-bar {
          min-width: 0;
        }
        .action-bar {
          min-width: 0;
        }
        .side-col {
          display: none; /* swipe the preview to change views on mobile */
        }
        /* Preview is the flex:1 section between slots and the footer bar,
           bounded by the app's height. On a tall phone a square would leave big
           empty bands, so the result fills the whole area instead (no wasted
           space); the 1:1 image just `contain`s inside it. */
        .preview {
          flex: 1;
          min-width: 0;
          min-height: 0;
          overflow: hidden;
        }
        .result-area {
          margin: 0 12px;
          padding: 14px;
          box-sizing: border-box;
          flex: 1;
          width: auto;
          height: 100%;
          min-height: 0;
        }

        .slots-bar {
          order: 2;
          flex-shrink: 0;
          padding: 10px 12px;
        }
        .slots-row {
          overflow-x: auto;
          max-width: 100%;
          padding: 10px 12px;
          border-radius: 18px;
          align-items: center;
          gap: 8px;
        }
        .sq-divider {
          margin: 0 10px;
        }
        .sq-slot {
          width: 72px;
        }
        .sq-body {
          width: 72px;
          height: 72px;
          border-radius: 16px;
        }
        .sq-icon {
          width: 34px;
          height: 34px;
        }
        /* View overlay smaller on mobile */
        .view-overlay {
          right: 10px;
          gap: 5px;
        }
        .vo-btn {
          padding: 8px 8px 6px;
          min-width: 44px;
          border-radius: 12px;
        }
        .vo-icon {
          width: 18px;
          height: 18px;
        }
        .vo-lbl {
          font-size: 9px;
        }
        /* Action bar becomes the bottom footer */
        .action-bar {
          order: 3;
          flex-shrink: 0;
          gap: 10px;
          padding: 12px 14px calc(12px + env(safe-area-inset-bottom, 0px));
          background: rgba(255, 255, 255, 0.94);
          backdrop-filter: blur(10px);
          border-top: 1px solid var(--border-soft);
          box-shadow: 0 -8px 24px rgba(30, 27, 20, 0.12);
        }
        .act-btn--primary {
          flex: 1;
          min-width: 0;
          padding: 15px;
        }
        .act-btn--ghost {
          display: none;
        }
      }

      @keyframes spin {
        to {
          transform: rotate(360deg);
        }
      }
    </style>
  </template>
}

export class VirtualTryOnApp extends CardDef {
  static displayName = 'Virtual Try-On App';
  static prefersWideFormat = true;

  @field model = linksTo(() => Model, { searchable: 'photo.file' });

  static isolated = IsolatedTemplate;

  static fitted = class Fitted extends Component<typeof VirtualTryOnApp> {
    get photoUrl() {
      return this.args.model?.model?.photo?.resolvedUrl;
    }

    get tagline() {
      return (
        this.args.model?.cardDescription || 'AI-powered outfit visualization'
      );
    }

    // Fall back to the app's name when an instance has no title set, so the
    // fitted formats never render a blank label.
    get displayTitle() {
      return this.args.model?.cardTitle || 'Virtual Try-On';
    }

    <template>
      {{! Four sub-formats share one root; container queries reveal one at a time. }}
      <div class='fit'>
        {{! ── Badge: ≤150w, <170h — glowing mark + title ── }}
        <div class='badge'>
          <span class='mark-halo mark-halo--sm'><SparklesIcon
              class='mark'
            /></span>
          <span class='title'>{{this.displayTitle}}</span>
        </div>

        {{! ── Strip: >150w, <170h — thumb + label + title + tagline ── }}
        <div class='strip'>
          <div class='thumb'>
            {{#if this.photoUrl}}
              <img src={{this.photoUrl}} alt='' />
            {{else}}
              <span class='mark-halo mark-halo--sm'><SparklesIcon
                  class='mark'
                /></span>
            {{/if}}
          </div>
          <div class='strip-text'>
            <span class='eyebrow eyebrow--mini'><SparklesIcon
                class='eyebrow-ico'
              />AI Try-On</span>
            <span class='title'>{{this.displayTitle}}</span>
            <span class='tagline'>{{this.tagline}}</span>
          </div>
        </div>

        {{! ── Tile: <400w, ≥170h — media on top, text below ── }}
        <div class='tile'>
          <div class='media'>
            {{#if this.photoUrl}}
              <img src={{this.photoUrl}} alt='' />
            {{else}}
              <span class='mark-halo'><SparklesIcon
                  class='mark mark--lg'
                /></span>
            {{/if}}
            <span class='scrim'></span>
            <span class='ai-chip'><SparklesIcon class='chip-ico' />AI</span>
          </div>
          <div class='tile-text'>
            <span class='eyebrow eyebrow--mini'><SparklesIcon
                class='eyebrow-ico'
              />AI Try-On</span>
            <span class='title'>{{this.displayTitle}}</span>
            <span class='tagline'>{{this.tagline}}</span>
          </div>
        </div>

        {{! ── Card: ≥400w, ≥170h — media left, full text right ── }}
        <div class='card'>
          <div class='media'>
            {{#if this.photoUrl}}
              <img src={{this.photoUrl}} alt='' />
            {{else}}
              <span class='mark-halo'><SparklesIcon
                  class='mark mark--lg'
                /></span>
            {{/if}}
            <span class='scrim'></span>
            <span class='ai-chip'><SparklesIcon class='chip-ico' />AI Powered</span>
          </div>
          <SparklesIcon class='watermark' />
          <div class='card-text'>
            <span class='eyebrow'><SparklesIcon class='eyebrow-ico' />Virtual
              Try-On</span>
            <span class='title title--lg'>{{this.displayTitle}}</span>
            <span class='deco-rule'></span>
            <span class='tagline tagline--clamp'>{{this.tagline}}</span>
            <span class='cta'>Tap to style<span
                class='cta-arrow'
              >→</span></span>
          </div>
        </div>
      </div>

      <style scoped>
        .fit {
          /* Same warm cream/gold language as the isolated template. */
          --bg: #f6f4f0;
          --surface: #ffffff;
          --surface2: #f1efea;
          --border: #e4e1d9;
          --border-soft: rgba(20, 18, 14, 0.08);
          --text: #1a1a1c;
          --muted: #8c887d;
          --text-2: #6b675e;
          --gold: #c19a4b;
          --gold-deep: #a9762b;
          --gold-soft: color-mix(in srgb, var(--gold) 14%, #fff);
          --primary-grad: linear-gradient(135deg, #cba85a, var(--gold-deep));
          --shadow: 0 10px 34px rgba(30, 27, 20, 0.12);

          position: relative;
          width: 100%;
          height: 100%;
          background:
            radial-gradient(
              130% 90% at 85% -10%,
              rgba(184, 137, 59, 0.1),
              transparent 55%
            ),
            linear-gradient(180deg, #ffffff 0%, var(--bg) 100%);
          color: var(--text);
          font-family: var(--boxel-font-family, system-ui, sans-serif);
          overflow: hidden;
          isolation: isolate;
        }
        /* Shimmering gold hairline along the top edge — the "powered" tell. */
        .fit::before {
          content: '';
          position: absolute;
          inset: 0 0 auto 0;
          height: 2px;
          z-index: 3;
          background: linear-gradient(
            90deg,
            transparent,
            var(--gold-deep),
            #e6c878,
            var(--gold-deep),
            transparent
          );
          background-size: 200% 100%;
          animation: sheen 6s linear infinite;
        }
        @media (prefers-reduced-motion: reduce) {
          .fit::before {
            animation: none;
          }
        }
        @keyframes sheen {
          to {
            background-position: 200% 0;
          }
        }

        /* Every sub-format is hidden until its breakpoint matches. */
        .badge,
        .strip,
        .tile,
        .card {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
        }

        /* Oversized faint sparkle that decorates the card text panel. */
        .watermark {
          position: absolute;
          right: -18px;
          bottom: -22px;
          width: 150px;
          height: 150px;
          color: var(--gold);
          opacity: 0.08;
          pointer-events: none;
          z-index: 0;
        }

        /* Sparkle inside a soft gold halo. */
        .mark-halo {
          flex-shrink: 0;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          padding: 12px;
          border-radius: 50%;
          background: radial-gradient(
            circle at center,
            color-mix(in srgb, var(--gold) 22%, transparent),
            transparent 70%
          );
        }
        .mark-halo--sm {
          padding: 8px;
        }
        .mark {
          flex-shrink: 0;
          width: 22px;
          height: 22px;
          color: var(--gold-deep);
          filter: drop-shadow(
            0 1px 4px color-mix(in srgb, var(--gold) 45%, transparent)
          );
        }
        .mark--lg {
          width: 38px;
          height: 38px;
        }

        /* Gold "eyebrow" pill that reads as a product label. */
        .eyebrow {
          align-self: flex-start;
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 5px 11px;
          font-weight: 800;
          font-size: 10.5px;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--gold-deep);
          background: var(--gold-soft);
          border: 1px solid color-mix(in srgb, var(--gold) 32%, transparent);
          border-radius: 999px;
        }
        .eyebrow--mini {
          padding: 2px 7px;
          font-size: 8.5px;
          letter-spacing: 0.1em;
        }
        .eyebrow-ico {
          width: 14px;
          height: 14px;
          color: var(--gold);
        }

        /* Floating gold "AI" chip pinned to the artwork. */
        .ai-chip {
          position: absolute;
          top: 8px;
          left: 8px;
          z-index: 2;
          display: inline-flex;
          align-items: center;
          gap: 4px;
          padding: 3px 9px 3px 6px;
          font-weight: 800;
          font-size: 10px;
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: #fff;
          background: var(--primary-grad);
          border-radius: 999px;
          box-shadow: 0 2px 8px rgba(169, 118, 43, 0.35);
        }
        .chip-ico {
          width: 11px;
          height: 11px;
        }

        /* Short gold gradient flourish under the title. */
        .deco-rule {
          width: 44px;
          height: 3px;
          border-radius: 3px;
          background: var(--primary-grad);
        }

        /* Card CTA line. */
        .cta {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          margin-top: 2px;
          font-weight: 700;
          font-size: 12px;
          color: var(--gold-deep);
        }
        .cta-arrow {
          font-size: 14px;
          line-height: 1;
        }

        .title {
          font-weight: 800;
          line-height: 1.2;
          color: var(--text);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .title--lg {
          white-space: normal;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .tagline {
          color: var(--text-2);
          line-height: 1.3;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .tagline--clamp {
          white-space: normal;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }

        .thumb,
        .media {
          position: relative;
          flex-shrink: 0;
          overflow: hidden;
          background: linear-gradient(135deg, var(--surface), var(--surface2));
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .thumb img,
        .media img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }
        /* Soft bottom fade gives the photo depth against the cream frame. */
        .scrim {
          position: absolute;
          inset: 0;
          pointer-events: none;
          background: linear-gradient(
            to top,
            rgba(26, 26, 28, 0.28),
            transparent 45%
          );
        }

        /* ── Badge ── */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 4px;
            padding: 8px;
          }
          .badge .title {
            font-size: 11px;
            max-width: 100%;
          }
        }
        @container fitted-card (max-width: 150px) and (max-height: 80px) {
          .badge .title {
            font-size: 9px;
          }
        }

        /* ── Strip ── */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            flex-direction: row;
            align-items: flex-start;
            gap: 10px;
            padding: 10px 12px;
          }
          .thumb {
            width: 48px;
            height: 48px;
            border-radius: 12px;
            border: 1px solid var(--border);
          }
          .strip-text {
            display: flex;
            flex-direction: column;
            justify-content: center;
            gap: 3px;
            min-width: 0;
          }
          .strip .title {
            font-size: 13px;
          }
          .strip .tagline {
            font-size: 11px;
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 80px) {
          .strip {
            align-items: center;
          }
          .thumb {
            width: 36px;
            height: 36px;
            border-radius: 10px;
          }
          .strip .eyebrow,
          .strip .tagline {
            display: none;
          }
        }

        /* ── Tile ── */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
          }
          .tile .media {
            flex: 1;
            min-height: 0;
            width: 100%;
          }
          .tile-text {
            flex-shrink: 0;
            display: flex;
            flex-direction: column;
            gap: 4px;
            padding: 10px 13px 12px;
            background: var(--surface);
            border-top: 1px solid var(--border-soft);
          }
          .tile .eyebrow--mini {
            margin-bottom: 1px;
          }
          .tile .title {
            font-size: 14px;
          }
          .tile .tagline {
            font-size: 11px;
          }
        }

        /* ── Card ── */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            position: relative;
            display: flex;
            flex-direction: row;
            align-items: stretch;
            overflow: hidden;
          }
          .card .media {
            width: 42%;
            max-width: 240px;
            height: 100%;
            border-right: 1px solid var(--border);
          }
          .card-text {
            position: relative;
            z-index: 1;
            flex: 1;
            min-width: 0;
            display: flex;
            flex-direction: column;
            justify-content: center;
            gap: 7px;
            padding: 18px 20px;
          }
          .card .title--lg {
            font-size: 21px;
          }
          .card .tagline {
            font-size: 13px;
          }
        }
      </style>
    </template>
  };
}
