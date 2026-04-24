import { CardDef, Component } from 'https://cardstack.com/base/card-api';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { action } from '@ember/object';
import { eq } from '@cardstack/boxel-ui/helpers';
import { modifier } from 'ember-modifier';

// FLIP animation modifier — plays when a placed element appears with a known origin rect.
// First: the DOM node appears in the target. Last: we read its rect.
// Invert: transform back to the origin. Play: Web Animations API transitions to identity.
const flipIn = modifier(function flipIn(
  element: HTMLElement,
  [from]: [DOMRect | null],
) {
  if (!from) return;
  const to = element.getBoundingClientRect();
  if (to.width === 0 || to.height === 0) return;

  const dx = from.left - to.left;
  const dy = from.top - to.top;
  const sx = Math.max(0.15, from.width / to.width);
  const sy = Math.max(0.15, from.height / to.height);

  element.style.willChange = 'transform, opacity';
  const anim = element.animate(
    [
      {
        transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})`,
        opacity: 0.35,
        offset: 0,
      },
      {
        transform: `translate(${dx * 0.12}px, ${dy * 0.12}px) scale(0.96, 0.96)`,
        opacity: 1,
        offset: 0.7,
      },
      {
        transform: 'translate(0, 0) scale(1, 1)',
        opacity: 1,
        offset: 1,
      },
    ],
    {
      duration: 460,
      easing: 'cubic-bezier(0.22, 0.9, 0.32, 1.15)',
      fill: 'none',
    },
  );
  anim.finished.then(() => {
    element.style.willChange = '';
  }).catch(() => {});
});

interface Payload {
  id: string;
  name: string;
  type: string;
  ancestry: string[];
  avatar: string;
  tint: string;
  meta: string;
  url: string;
}

interface AcceptSpec {
  ofType: string;
}

interface Target {
  id: string;
  name: string;
  subtitle: string;
  accepts: AcceptSpec[];
  format: 'atom' | 'fitted' | 'isolated';
  dwell?: boolean;
  childOf?: string;
  async?: boolean;
}

interface Decision {
  accept: boolean;
  format?: string;
  reason?: string;
  expected?: string;
  got?: string;
  message?: string;
}

interface Session {
  payload: Payload;
  affordance: 'drag' | 'paste' | 'palette';
  mode: 'pointer' | 'keyboard';
}

interface PendingDrag {
  payload: Payload;
  startX: number;
  startY: number;
}

interface HistoryEntry {
  id: number;
  payloadName: string;
  payloadType: string;
  targetName: string;
  affordance: 'drag' | 'palette' | 'paste';
  accept: boolean;
  message?: string;
  at: Date;
  pending?: boolean;
}

interface PendingJob {
  id: string;
  entryId: number;
  payload: Payload;
  targetId: string;
  targetName: string;
  startedAt: Date;
}

const PAYLOADS: Payload[] = [
  { id: 'rosie',   name: 'Rosie',     type: 'ShowDog',  ancestry: ['ShowDog','Dog','Mammal','Pet','CardDef'], avatar: 'RO', tint: 'dog',    meta: 'Border Collie · Champion', url: 'https://app.boxel.ai/zoo/Dog/rosie' },
  { id: 'buddy',   name: 'Buddy',     type: 'Dog',      ancestry: ['Dog','Mammal','Pet','CardDef'],           avatar: 'BU', tint: 'dog',    meta: 'Mutt · 3 yrs',              url: 'https://app.boxel.ai/zoo/Dog/buddy' },
  { id: 'pickles', name: 'Pickles',   type: 'Cat',      ancestry: ['Cat','Mammal','Pet','CardDef'],           avatar: 'PK', tint: 'cat',    meta: 'Tabby · 6 yrs',             url: 'https://app.boxel.ai/zoo/Cat/pickles' },
  { id: 'sky',     name: 'Sky',       type: 'Parrot',   ancestry: ['Parrot','Bird','Pet','CardDef'],          avatar: 'SK', tint: 'bird',   meta: 'Macaw · 14 yrs',            url: 'https://app.boxel.ai/zoo/Parrot/sky' },
  { id: 'ada',     name: 'Ada L.',    type: 'Person',   ancestry: ['Person','CardDef'],                       avatar: 'AD', tint: 'person', meta: 'Lead Engineer',             url: 'https://app.boxel.ai/zoo/Person/ada' },
  { id: 'task42',  name: 'TASK-42',   type: 'Task',     ancestry: ['Task','CardDef'],                         avatar: 'T4', tint: 'task',   meta: 'Migrate enclosure schema',  url: 'https://app.boxel.ai/zoo/Task/task-42' },
  { id: 'inv42',   name: 'INV-00042', type: 'Invoice',  ancestry: ['Invoice','CardDef'],                      avatar: 'IV', tint: 'inv',    meta: 'Acme · $4,200',             url: 'https://app.boxel.ai/zoo/Invoice/inv-00042' },
];

const TARGETS: Target[] = [
  { id: 'mammal',   name: 'Mammal Enclosure',   subtitle: 'accepts Mammal+ (subtype of Pet — excludes birds)', accepts: [{ ofType: 'Mammal' }], format: 'fitted' },
  { id: 'aviary',   name: 'Aviary',             subtitle: 'accepts Bird+',           accepts: [{ ofType: 'Bird' }],    format: 'fitted' },
  { id: 'stack',    name: 'Active Stack',       subtitle: 'accepts any CardDef · isolated · insert between', accepts: [{ ofType: 'CardDef' }], format: 'isolated' },
  { id: 'composer', name: 'AI Composer',        subtitle: 'accepts any CardDef · atom · inline chip',     accepts: [{ ofType: 'CardDef' }], format: 'atom' },
  { id: 'team',     name: 'Team Sidebar',       subtitle: 'accepts Person+ · fitted',       accepts: [{ ofType: 'Person' }], format: 'fitted' },
  { id: 'foreign',  name: 'Foreign Realm',      subtitle: 'cross-realm copy · schedules a Job · 1.8s',  accepts: [{ ofType: 'CardDef' }], format: 'fitted', async: true },
  { id: 'folder',   name: 'Zoo Keeper Notes',   subtitle: 'collapsed · hover 600ms',        accepts: [{ ofType: 'CardDef' }], format: 'fitted', dwell: true },
  { id: 'folder-pets', name: 'Pet Dossiers',    subtitle: '(revealed) accepts Pet+',        accepts: [{ ofType: 'Pet' }],     format: 'fitted', childOf: 'folder' },
  { id: 'folder-ops',  name: 'Ops Invoices',    subtitle: '(revealed) accepts Invoice+',    accepts: [{ ofType: 'Invoice' }], format: 'fitted', childOf: 'folder' },
];

function evaluate(payload: Payload, target: Target): Decision {
  for (const spec of target.accepts) {
    if (payload.ancestry.includes(spec.ofType)) {
      return { accept: true, format: target.format };
    }
  }
  const expected = target.accepts.map((s) => s.ofType).join(' | ');
  return {
    accept: false,
    reason: 'type-mismatch',
    expected,
    got: payload.type,
    message: `Expected ${expected} or descendant; got ${payload.type}`,
  };
}

export class PlacementPrototype extends CardDef {
  static displayName = 'Placement Prototype';
  static prefersWideFormat = true;

  static isolated = class Isolated extends Component<typeof PlacementPrototype> {
    @tracked session: Session | null = null;
    @tracked pointerX = 0;
    @tracked pointerY = 0;
    @tracked hoveredTargetId: string | null = null;
    @tracked palettePayloadId: string | null = null;
    @tracked history: HistoryEntry[] = [];
    @tracked dwellProgress = 0;
    @tracked folderOpen = false;
    @tracked focusedPayloadId: string | null = null;
    @tracked placements: Record<string, Payload[]> = {};
    @tracked announcement = '';
    @tracked pendingDrag: PendingDrag | null = null;
    @tracked pendingJobs: PendingJob[] = [];
    @tracked stackInsertIndex: number | null = null;
    @tracked selectedSourceId: string | null = null;
    @tracked selectedSlotId: string | null = null;
    @tracked flipOrigins: Record<string, DOMRect> = {};

    historyCounter = 0;
    dwellInterval: ReturnType<typeof setInterval> | null = null;
    readonly ACTIVATION_THRESHOLD = 4;

    constructor(owner: unknown, args: any) {
      super(owner, args);
      if (typeof document !== 'undefined') {
        document.addEventListener('keydown', this.onGlobalKey);
      }
    }

    willDestroy() {
      super.willDestroy();
      if (typeof document !== 'undefined') {
        document.removeEventListener('keydown', this.onGlobalKey);
      }
      this.stopDrag();
    }

    get payloads() { return PAYLOADS; }

    get visibleTargets() {
      return TARGETS.filter((t) => !t.childOf || (t.childOf === 'folder' && this.folderOpen));
    }

    get topTargets() {
      return TARGETS.filter((t) => !t.childOf);
    }

    get folderChildren() {
      return TARGETS.filter((t) => t.childOf === 'folder');
    }

    get placedMammal()     { return this.placements['mammal']      ?? []; }
    get placedAviary()     { return this.placements['aviary']      ?? []; }
    get placedStack()      { return this.placements['stack']       ?? []; }
    get placedComposer()   { return this.placements['composer']    ?? []; }
    get placedTeam()       { return this.placements['team']        ?? []; }
    get placedForeign()    { return this.placements['foreign']     ?? []; }
    get placedFolder()     { return this.placements['folder']      ?? []; }
    get placedFolderPets() { return this.placements['folder-pets'] ?? []; }
    get placedFolderOps()  { return this.placements['folder-ops']  ?? []; }

    get foreignPendingJobs() {
      return this.pendingJobs.filter((j) => j.targetId === 'foreign');
    }

    get foreignHasContent() {
      return this.placedForeign.length > 0 || this.foreignPendingJobs.length > 0;
    }

    get stackWedgeAt0() {
      return this.hoveredTargetId === 'stack' && !this.denied && !!this.session && this.stackInsertIndex === 0;
    }

    wedgeForStackIndex = (idx: number) => {
      return this.hoveredTargetId === 'stack' && !this.denied && !!this.session && this.stackInsertIndex === idx;
    };

    get stackTailIndex() {
      return this.placedStack.length;
    }

    get paletteCandidates() {
      if (!this.palettePayloadId) return [];
      const payload = PAYLOADS.find((p) => p.id === this.palettePayloadId)!;
      return TARGETS.filter((t) => !t.childOf || this.folderOpen).map((t) => {
        const decision = evaluate(payload, t);
        return {
          target: t,
          decision,
          disabled: !decision.accept,
          rowClass: decision.accept ? 'pal-ok' : 'pal-no',
          tickGlyph: decision.accept ? '✓' : '✗',
        };
      }).sort((a, b) => Number(b.decision.accept) - Number(a.decision.accept));
    }

    get draggingId() {
      return this.session?.payload.id ?? null;
    }

    get showDeny() {
      return !!this.session && this.denied && !!this.currentDecision;
    }

    get dwellPercent() {
      return `${Math.round(this.dwellProgress * 100)}%`;
    }

    get dwellActiveFolder() {
      return this.hoveredTargetId === 'folder' && !this.folderOpen && !!this.session;
    }

    @action
    stopPropagation(event: Event) {
      event.stopPropagation();
    }

    get currentDecision(): Decision | null {
      if (!this.session || !this.hoveredTargetId) return null;
      const target = TARGETS.find((t) => t.id === this.hoveredTargetId);
      if (!target) return null;
      return evaluate(this.session.payload, target);
    }

    get ghostFormat(): string {
      if (this.currentDecision?.accept && this.currentDecision.format) {
        return this.currentDecision.format;
      }
      return 'fitted';
    }

    get ghostAtom() { return this.ghostFormat === 'atom'; }
    get ghostFitted() { return this.ghostFormat === 'fitted'; }
    get ghostIsolated() { return this.ghostFormat === 'isolated'; }

    get denied() {
      return this.currentDecision ? !this.currentDecision.accept : false;
    }

    get ghostStyle() {
      return `transform: translate(${this.pointerX + 14}px, ${this.pointerY + 14}px);`;
    }

    get dwellRingStyle() {
      const pct = Math.round(this.dwellProgress * 100);
      return `--dwell-pct: ${pct}%;`;
    }

    get palettePayload() {
      return PAYLOADS.find((p) => p.id === this.palettePayloadId) ?? null;
    }

    isHovered = (id: string) => this.hoveredTargetId === id;
    isDenied = (id: string) => this.hoveredTargetId === id && this.denied;
    isAccept = (id: string) => this.hoveredTargetId === id && !this.denied && !!this.session;
    isFolder = (id: string) => id === 'folder';
    dwellActive = (id: string) => this.hoveredTargetId === id && id === 'folder' && !this.folderOpen;

    compatOf = (id: string): 'yes' | 'no' | null => {
      if (!this.session) return null;
      if (this.hoveredTargetId === id) return null;
      const target = TARGETS.find((t) => t.id === id);
      if (!target) return null;
      const decision = evaluate(this.session.payload, target);
      return decision.accept ? 'yes' : 'no';
    };

    @action
    startDrag(payload: Payload, event: PointerEvent) {
      event.preventDefault();
      this.focusedPayloadId = payload.id;
      this.pendingDrag = { payload, startX: event.clientX, startY: event.clientY };
      this.pointerX = event.clientX;
      this.pointerY = event.clientY;
      document.addEventListener('pointermove', this.onPointerMove);
      document.addEventListener('pointerup', this.onPointerUp);
    }

    @action
    onPointerMove(event: PointerEvent) {
      this.pointerX = event.clientX;
      this.pointerY = event.clientY;

      if (this.pendingDrag && !this.session) {
        const dx = event.clientX - this.pendingDrag.startX;
        const dy = event.clientY - this.pendingDrag.startY;
        if (Math.hypot(dx, dy) < this.ACTIVATION_THRESHOLD) return;
        const payload = this.pendingDrag.payload;
        this.session = { payload, affordance: 'drag', mode: 'pointer' };
        this.pendingDrag = null;
        this.announcePickup(payload);
      }

      const el = document.elementFromPoint(event.clientX, event.clientY);
      const targetEl = el ? (el as HTMLElement).closest('[data-drop-target]') as HTMLElement | null : null;
      const nextId = targetEl?.dataset.dropTarget ?? null;

      if (nextId !== this.hoveredTargetId) {
        this.hoveredTargetId = nextId;
        this.stopDwell();
        this.stackInsertIndex = null;
        if (nextId === 'folder' && !this.folderOpen) {
          this.startDwell();
        }
        if (nextId) this.announceTarget(nextId);
      }

      if (this.hoveredTargetId === 'stack' && this.session && !this.denied) {
        this.stackInsertIndex = this.computeStackInsertIndex(event.clientY);
      }
    }

    computeStackInsertIndex(clientY: number): number {
      const stackEl = document.querySelector('[data-drop-target="stack"] .placed-iso-stack');
      if (!stackEl) return this.placedStack.length;
      const children = Array.from(stackEl.querySelectorAll('.placed-iso')) as HTMLElement[];
      if (!children.length) return 0;
      for (let i = 0; i < children.length; i++) {
        const rect = children[i].getBoundingClientRect();
        const mid = rect.top + rect.height / 2;
        if (clientY < mid) return i;
      }
      return children.length;
    }

    @action
    onPointerUp() {
      if (this.session && this.hoveredTargetId) {
        const target = TARGETS.find((t) => t.id === this.hoveredTargetId);
        if (target) {
          const decision = evaluate(this.session.payload, target);
          this.commit(this.session.payload, target, decision, 'drag');
        }
        this.stopDrag();
        return;
      }
      if (this.pendingDrag && !this.session) {
        const payloadId = this.pendingDrag.payload.id;
        this.pendingDrag = null;
        document.removeEventListener('pointermove', this.onPointerMove);
        document.removeEventListener('pointerup', this.onPointerUp);
        this.selectSource(payloadId);
        return;
      }
      this.stopDrag();
    }

    @action
    onPayloadKey(payload: Payload, event: KeyboardEvent) {
      if (event.key === ' ' || event.key === 'Enter') {
        event.preventDefault();
        this.startKeyboardDrag(payload);
      }
    }

    startKeyboardDrag(payload: Payload) {
      this.focusedPayloadId = payload.id;
      this.session = { payload, affordance: 'drag', mode: 'keyboard' };
      const ids = this.compatibleTargetIds;
      this.hoveredTargetId = ids[0] ?? null;
      this.announcePickup(payload);
      if (this.hoveredTargetId) this.announceTarget(this.hoveredTargetId);
    }

    get compatibleTargetIds(): string[] {
      if (!this.session) return [];
      return TARGETS
        .filter((t) => !t.childOf || this.folderOpen)
        .filter((t) => evaluate(this.session!.payload, t).accept)
        .map((t) => t.id);
    }

    announce(message: string) {
      this.announcement = '';
      setTimeout(() => (this.announcement = message), 30);
    }

    announcePickup(payload: Payload) {
      const compat = TARGETS
        .filter((t) => !t.childOf || this.folderOpen)
        .filter((t) => evaluate(payload, t).accept).length;
      this.announce(`${payload.name} (${payload.type}) picked up. ${compat} compatible target${compat === 1 ? '' : 's'}. Arrow keys to navigate, Enter to drop, Escape to cancel.`);
    }

    announceTarget(id: string) {
      const t = TARGETS.find((x) => x.id === id);
      if (!t || !this.session) return;
      const decision = evaluate(this.session.payload, t);
      if (decision.accept) {
        this.announce(`${t.name}, will accept as ${t.format}. Enter to drop.`);
      } else {
        this.announce(`${t.name}, ${decision.message}.`);
      }
    }

    @action
    onGlobalKey(event: KeyboardEvent) {
      const tagName = (event.target as HTMLElement | null)?.tagName;
      const isEditable = tagName === 'INPUT' || tagName === 'TEXTAREA' || (event.target as HTMLElement | null)?.isContentEditable;
      if ((event.metaKey || event.ctrlKey) && (event.key === 'v' || event.key === 'V')) {
        if (this.selectionReady && !isEditable) {
          event.preventDefault();
          this.commitSelection();
          return;
        }
      }
      if (event.key === 'Escape') {
        if (this.palettePayloadId) {
          this.closePalette();
          this.announce('Palette closed.');
          return;
        }
        if (this.session) {
          const name = this.session.payload.name;
          this.stopDrag();
          this.announce(`${name} cancelled. Returned to source.`);
          return;
        }
        if (this.hasSelection) {
          this.clearSelection();
          this.announce('Selection cleared.');
          return;
        }
      }
      if (this.session?.mode === 'keyboard') {
        const compat = this.compatibleTargetIds;
        if (!compat.length) return;
        const idx = compat.indexOf(this.hoveredTargetId ?? '');
        if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
          event.preventDefault();
          const next = compat[(idx + 1) % compat.length];
          this.hoveredTargetId = next;
          this.announceTarget(next);
        } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
          event.preventDefault();
          const next = compat[(idx - 1 + compat.length) % compat.length];
          this.hoveredTargetId = next;
          this.announceTarget(next);
        } else if (event.key === 'Enter') {
          event.preventDefault();
          if (this.hoveredTargetId) {
            const target = TARGETS.find((t) => t.id === this.hoveredTargetId);
            if (target && this.session) {
              const decision = evaluate(this.session.payload, target);
              this.commit(this.session.payload, target, decision, 'drag');
              if (decision.accept) {
                this.announce(`Placed ${this.session.payload.name} on ${target.name}.`);
              } else {
                this.announce(`Denied. ${decision.message}`);
              }
            }
          }
          this.stopDrag();
        }
      }
    }

    startDwell() {
      this.dwellProgress = 0;
      const DURATION = 600;
      const STEP = 30;
      const increment = STEP / DURATION;
      this.dwellInterval = setInterval(() => {
        this.dwellProgress = Math.min(1, this.dwellProgress + increment);
        if (this.dwellProgress >= 1) {
          this.folderOpen = true;
          this.stopDwell();
        }
      }, STEP);
    }

    stopDwell() {
      if (this.dwellInterval) {
        clearInterval(this.dwellInterval);
        this.dwellInterval = null;
      }
      if (!this.folderOpen) {
        this.dwellProgress = 0;
      }
    }

    stopDrag() {
      this.session = null;
      this.pendingDrag = null;
      this.hoveredTargetId = null;
      this.stopDwell();
      if (typeof document !== 'undefined') {
        document.removeEventListener('pointermove', this.onPointerMove);
        document.removeEventListener('pointerup', this.onPointerUp);
      }
    }

    @action
    openPalette(payloadId: string, event?: Event) {
      if (event) event.stopPropagation();
      this.palettePayloadId = payloadId;
    }

    @action
    closePalette() {
      this.palettePayloadId = null;
    }

    @action
    palettePlace(target: Target) {
      if (!this.palettePayloadId) return;
      const payload = PAYLOADS.find((p) => p.id === this.palettePayloadId)!;
      const decision = evaluate(payload, target);
      this.commit(payload, target, decision, 'palette');
      this.closePalette();
    }

    commit(payload: Payload, target: Target, decision: Decision, affordance: 'drag' | 'palette' | 'paste') {
      this.historyCounter += 1;
      const isDupe = decision.accept && (this.placements[target.id] ?? []).some((p) => p.id === payload.id);
      const pendingDupe = decision.accept && this.pendingJobs.some((j) => j.targetId === target.id && j.payload.id === payload.id);
      const blocked = isDupe || pendingDupe;
      const isAsync = !!target.async && decision.accept && !blocked;

      const entry: HistoryEntry = {
        id: this.historyCounter,
        payloadName: payload.name,
        payloadType: payload.type,
        targetName: target.name,
        affordance,
        accept: decision.accept && !blocked,
        message: blocked
          ? `${payload.name} is already on ${target.name}`
          : isAsync
            ? 'Job scheduled · pending cross-realm copy'
            : decision.message,
        at: new Date(),
        pending: isAsync,
      };
      this.history = [entry, ...this.history].slice(0, 8);

      if (!decision.accept || blocked) {
        if (blocked) this.announce(`Already placed. ${payload.name} is on ${target.name}.`);
        return;
      }

      this.stashFlipOrigin(payload.id, affordance);

      if (isAsync) {
        const jobId = `job-${this.historyCounter}`;
        const job: PendingJob = {
          id: jobId,
          entryId: entry.id,
          payload,
          targetId: target.id,
          targetName: target.name,
          startedAt: new Date(),
        };
        this.pendingJobs = [...this.pendingJobs, job];
        setTimeout(() => this.resolveJob(jobId), 1800);
        return;
      }

      const insertAt = target.id === 'stack' ? this.stackInsertIndex : null;
      const current = this.placements[target.id] ?? [];
      const next = insertAt == null
        ? [...current, payload]
        : [...current.slice(0, insertAt), payload, ...current.slice(insertAt)];
      this.placements = { ...this.placements, [target.id]: next };
      this.stackInsertIndex = null;
    }

    stashFlipOrigin(payloadId: string, affordance: 'drag' | 'palette' | 'paste') {
      let rect: DOMRect | null = null;
      if (affordance === 'drag' && this.session) {
        rect = new DOMRect(this.pointerX - 60, this.pointerY - 22, 140, 56);
      } else if (typeof document !== 'undefined') {
        const el = document.querySelector(`[data-payload="${payloadId}"]`) as HTMLElement | null;
        if (el) rect = el.getBoundingClientRect();
      }
      if (!rect) return;
      this.flipOrigins = { ...this.flipOrigins, [payloadId]: rect };
      setTimeout(() => {
        const next = { ...this.flipOrigins };
        delete next[payloadId];
        this.flipOrigins = next;
      }, 700);
    }

    resolveJob(jobId: string) {
      const job = this.pendingJobs.find((j) => j.id === jobId);
      if (!job) return;
      this.pendingJobs = this.pendingJobs.filter((j) => j.id !== jobId);
      if (typeof document !== 'undefined') {
        const pendingEl = document.querySelector(
          `[data-drop-target="${job.targetId}"] .placed-pending[data-payload-id="${job.payload.id}"]`,
        ) as HTMLElement | null;
        if (pendingEl) {
          const rect = pendingEl.getBoundingClientRect();
          this.flipOrigins = { ...this.flipOrigins, [job.payload.id]: rect };
          setTimeout(() => {
            const next = { ...this.flipOrigins };
            delete next[job.payload.id];
            this.flipOrigins = next;
          }, 700);
        }
      }
      const current = this.placements[job.targetId] ?? [];
      this.placements = { ...this.placements, [job.targetId]: [...current, job.payload] };
      const elapsed = ((Date.now() - job.startedAt.getTime()) / 1000).toFixed(1);
      this.history = this.history.map((h) =>
        h.id === job.entryId
          ? { ...h, message: `Job complete · ${elapsed}s · cross-realm copy`, pending: false }
          : h,
      );
    }

    @action
    removePlacement(targetId: string, payloadId: string, event: Event) {
      event.stopPropagation();
      const current = this.placements[targetId] ?? [];
      this.placements = {
        ...this.placements,
        [targetId]: current.filter((p) => p.id !== payloadId),
      };
    }

    @action
    clearPlacements() {
      this.placements = {};
    }

    @action
    selectSource(payloadId: string, event?: Event) {
      if (event) event.stopPropagation();
      this.selectedSourceId = this.selectedSourceId === payloadId ? null : payloadId;
      const payload = PAYLOADS.find((p) => p.id === this.selectedSourceId);
      if (payload) {
        const slot = this.selectedSlotTarget;
        this.announce(
          slot
            ? `${payload.name} selected as source. Slot: ${slot.name}. Press Command-V to commit.`
            : `${payload.name} selected as source. Click a slot next.`,
        );
      }
    }

    @action
    selectSlot(targetId: string, event?: Event) {
      if (event) event.stopPropagation();
      this.selectedSlotId = this.selectedSlotId === targetId ? null : targetId;
      const target = TARGETS.find((t) => t.id === this.selectedSlotId);
      if (target) {
        const src = this.selectedSource;
        this.announce(
          src
            ? `${target.name} selected as slot. Source: ${src.name}. Press Command-V to commit.`
            : `${target.name} selected as slot. Click a source next.`,
        );
      }
    }

    @action
    clearSelection() {
      this.selectedSourceId = null;
      this.selectedSlotId = null;
    }

    @action
    workspaceClick(event: Event) {
      const el = event.target as HTMLElement;
      if (el.closest('.selection-bar')) return;
      const dz = el.closest('[data-drop-target]') as HTMLElement | null;
      if (dz) {
        this.selectSlot(dz.dataset.dropTarget ?? '', event);
      } else {
        this.selectedSlotId = null;
      }
    }

    commitSelection() {
      if (!this.selectedSourceId || !this.selectedSlotId) return;
      const payload = PAYLOADS.find((p) => p.id === this.selectedSourceId);
      const target = TARGETS.find((t) => t.id === this.selectedSlotId);
      if (!payload || !target) return;
      const decision = evaluate(payload, target);
      this.commit(payload, target, decision, 'paste');
      if (decision.accept) {
        this.announce(`Placed ${payload.name} on ${target.name} via Command-V.`);
      }
      this.clearSelection();
    }

    get selectedSource() {
      return PAYLOADS.find((p) => p.id === this.selectedSourceId) ?? null;
    }

    get selectedSlotTarget() {
      return TARGETS.find((t) => t.id === this.selectedSlotId) ?? null;
    }

    get selectionDecision(): Decision | null {
      if (!this.selectedSource || !this.selectedSlotTarget) return null;
      return evaluate(this.selectedSource, this.selectedSlotTarget);
    }

    get hasSelection() {
      return !!(this.selectedSourceId || this.selectedSlotId);
    }

    get selectionReady() {
      return !!(this.selectedSourceId && this.selectedSlotId);
    }

    get selectionKbdLabel() {
      if (typeof navigator === 'undefined') return '⌘V';
      const mac = /Mac|iPhone|iPad/.test(navigator.platform || '');
      return mac ? '⌘V' : 'Ctrl+V';
    }

    flipOriginFor = (payloadId: string): DOMRect | null => {
      return this.flipOrigins[payloadId] ?? null;
    };

    @action
    resetFolder() {
      this.folderOpen = false;
      this.dwellProgress = 0;
    }

    @action
    clearHistory() {
      this.history = [];
    }

    formatTime = (d: Date) => {
      const hh = String(d.getHours()).padStart(2, '0');
      const mm = String(d.getMinutes()).padStart(2, '0');
      const ss = String(d.getSeconds()).padStart(2, '0');
      return `${hh}:${mm}:${ss}`;
    };

    <template>
      <article class='proto' data-root>

        {{! ARIA live region for screen-reader announcements }}
        <div class='sr-only' role='status' aria-live='polite' aria-atomic='true'>
          {{this.announcement}}
        </div>

        <header class='proto-head'>
          <div class='proto-eyebrow'>§72 · PLACEMENT · INTERACTIVE PROTOTYPE</div>
          <h2 class='proto-title'>Drag a payload. Or press <span class='chip'>Place…</span>.<br/>Watch the ghost morph, the targets light, the Command fire.</h2>
          <div class='proto-hints'>
            <span class='hint-item'><kbd>drag</kbd> any payload onto a target</span>
            <span class='hint-item'>click source · click slot · <kbd>{{this.selectionKbdLabel}}</kbd> to commit</span>
            <span class='hint-item'>Tab + <kbd>Space</kbd> · <kbd>←↑→↓</kbd> · <kbd>⏎</kbd> (keyboard drag)</span>
            <span class='hint-item'><kbd>Place…</kbd> opens the palette</span>
            <span class='hint-item'>hover <strong>Zoo Keeper Notes</strong> 600ms to dwell-open</span>
            <span class='hint-item'><kbd>Esc</kbd> cancels</span>
          </div>

          {{! visible mirror of the ARIA live region so sighted users see what SR users hear }}
          <div class='announce-strip {{if this.announcement "active"}}'>
            <span class='announce-label'>ARIA live · polite</span>
            <span class='announce-text'>{{if this.announcement this.announcement "ready"}}</span>
          </div>
        </header>

        <section class='proto-grid'>

          {{! ═══ LIBRARY ═══ }}
          <aside class='library'>
            <div class='panel-head'>
              <span class='panel-eyebrow'>LIBRARY · SOURCES</span>
              <span class='panel-count'>{{this.payloads.length}}</span>
            </div>
            <div class='payload-list'>
              {{#each this.payloads as |p|}}
                <div
                  class='payload-card tint-{{p.tint}} {{if (eq this.focusedPayloadId p.id) "focused"}} {{if (eq this.draggingId p.id) "dragging"}} {{if (eq this.selectedSourceId p.id) "selected-src"}}'
                  data-payload={{p.id}}
                  tabindex='0'
                  role='button'
                  aria-label='{{p.name}} ({{p.type}}) — click to select as source, Space to pick up for keyboard drag'
                  {{on 'pointerdown' (fn this.startDrag p)}}
                  {{on 'keydown' (fn this.onPayloadKey p)}}
                >
                  <div class='pc-avatar'>{{p.avatar}}</div>
                  <div class='pc-body'>
                    <div class='pc-name'>{{p.name}}</div>
                    <div class='pc-type'>{{p.type}}</div>
                    <div class='pc-meta'>{{p.meta}}</div>
                  </div>
                  <button
                    type='button'
                    class='pc-place'
                    {{on 'click' (fn this.openPalette p.id)}}
                    {{on 'pointerdown' this.stopPropagation}}
                  >Place…</button>
                </div>
              {{/each}}
            </div>

            <div class='lib-foot'>
              <div class='foot-line'><span>payload · type</span><span>CardDef ancestry</span></div>
              <div class='foot-grid'>
                <span>Rosie</span><span>ShowDog → Dog → <b>Mammal</b> → <b>Pet</b> → CardDef</span>
                <span>Buddy</span><span>Dog → <b>Mammal</b> → <b>Pet</b> → CardDef</span>
                <span>Pickles</span><span>Cat → <b>Mammal</b> → <b>Pet</b> → CardDef</span>
                <span>Sky</span><span>Parrot → <b>Bird</b> → <b>Pet</b> → CardDef</span>
                <span>Ada L.</span><span><b>Person</b> → CardDef</span>
                <span>TASK-42</span><span><b>Task</b> → CardDef</span>
                <span>INV-00042</span><span><b>Invoice</b> → CardDef</span>
              </div>
            </div>
          </aside>

          {{! ═══ WORKSPACE ═══ }}
          <main class='workspace' {{on 'click' this.workspaceClick}}>
            <div class='panel-head'>
              <span class='panel-eyebrow'>WORKSPACE · TARGETS <em class='panel-hint'>· click a target to paste into it</em></span>
              <div class='btn-group'>
                <button type='button' class='reset-btn' {{on 'click' this.clearPlacements}}>clear placed</button>
                <button type='button' class='reset-btn' {{on 'click' this.resetFolder}}>reset folder</button>
              </div>
            </div>

            {{#if this.hasSelection}}
              <div class='selection-bar' {{on 'click' this.stopPropagation}}>
                <span class='sb-label'>SELECTION</span>

                <span class='sb-slot sb-slot-src'>
                  <span class='sb-role'>source</span>
                  {{#if this.selectedSource}}
                    <span class='sb-chip tint-{{this.selectedSource.tint}}'>
                      <span class='sb-avatar'>{{this.selectedSource.avatar}}</span>
                      <span class='sb-name'>{{this.selectedSource.name}}</span>
                      <span class='sb-type'>{{this.selectedSource.type}}</span>
                    </span>
                  {{else}}
                    <span class='sb-empty'>click a payload</span>
                  {{/if}}
                </span>

                <span class='sb-arrow'>→</span>

                <span class='sb-slot sb-slot-dst'>
                  <span class='sb-role'>slot</span>
                  {{#if this.selectedSlotTarget}}
                    <span class='sb-chip sb-chip-dst'>
                      <span class='sb-name'>{{this.selectedSlotTarget.name}}</span>
                      <span class='sb-fmt'>{{this.selectedSlotTarget.format}}</span>
                    </span>
                  {{else}}
                    <span class='sb-empty'>click a target</span>
                  {{/if}}
                </span>

                <span class='sb-cta'>
                  {{#if this.selectionReady}}
                    {{#if this.selectionDecision.accept}}
                      press <kbd class='sb-kbd'>{{this.selectionKbdLabel}}</kbd> to commit
                    {{else}}
                      <span class='sb-deny'>✗ {{this.selectionDecision.message}}</span>
                    {{/if}}
                  {{else}}
                    <span class='sb-idle'>finish selection</span>
                  {{/if}}
                </span>

                <button type='button' class='sb-cancel' {{on 'click' this.clearSelection}}>esc</button>
              </div>
            {{/if}}

            <div class='target-grid'>

              {{! mammal enclosure }}
              <div
                class='target target-mammal {{if (eq (this.compatOf "mammal") "yes") "compat-yes"}} {{if (eq (this.compatOf "mammal") "no") "compat-no"}} {{if (this.isAccept "mammal") "accept"}} {{if (this.isDenied "mammal") "deny"}} {{if (eq this.selectedSlotId "mammal") "selected-slot"}}'
                data-drop-target='mammal'
              >
                <div class='t-head'>
                  <span class='t-icon'>◈</span>
                  <div class='t-title'>Mammal Enclosure</div>
                  <span class='t-fmt'>fitted</span>
                </div>
                <div class='t-subtitle'>accepts <code>Mammal</code> (cats, dogs — not birds)</div>
                <div class='t-body'>
                  <div class='t-slot t-slot-fitted {{if this.placedMammal.length "has"}}'>
                    {{#if this.placedMammal.length}}
                      <div class='placed-row'>
                        {{#each this.placedMammal as |pay|}}
                          <div class='placed-tile tint-{{pay.tint}}' {{flipIn (this.flipOriginFor pay.id)}}>
                            <span class='placed-avatar'>{{pay.avatar}}</span>
                            <span class='placed-tile-body'>
                              <span class='placed-name'>{{pay.name}}</span>
                              <span class='placed-tile-type'>{{pay.type}}</span>
                            </span>
                            <button type='button' class='placed-x' {{on 'click' (fn this.removePlacement "mammal" pay.id)}}>×</button>
                          </div>
                        {{/each}}
                      </div>
                    {{else}}
                      <span class='t-placeholder'>drop a Mammal here</span>
                    {{/if}}
                  </div>
                </div>
              </div>

              {{! aviary }}
              <div
                class='target target-aviary {{if (eq (this.compatOf "aviary") "yes") "compat-yes"}} {{if (eq (this.compatOf "aviary") "no") "compat-no"}} {{if (this.isAccept "aviary") "accept"}} {{if (this.isDenied "aviary") "deny"}} {{if (eq this.selectedSlotId "aviary") "selected-slot"}}'
                data-drop-target='aviary'
              >
                <div class='t-head'>
                  <span class='t-icon'>✦</span>
                  <div class='t-title'>Aviary</div>
                  <span class='t-fmt'>fitted</span>
                </div>
                <div class='t-subtitle'>accepts <code>Bird</code> only</div>
                <div class='t-body'>
                  <div class='t-slot t-slot-fitted {{if this.placedAviary.length "has"}}'>
                    {{#if this.placedAviary.length}}
                      <div class='placed-row'>
                        {{#each this.placedAviary as |pay|}}
                          <div class='placed-tile tint-{{pay.tint}}' {{flipIn (this.flipOriginFor pay.id)}}>
                            <span class='placed-avatar'>{{pay.avatar}}</span>
                            <span class='placed-tile-body'>
                              <span class='placed-name'>{{pay.name}}</span>
                              <span class='placed-tile-type'>{{pay.type}}</span>
                            </span>
                            <button type='button' class='placed-x' {{on 'click' (fn this.removePlacement "aviary" pay.id)}}>×</button>
                          </div>
                        {{/each}}
                      </div>
                    {{else}}
                      <span class='t-placeholder'>drop a Bird here</span>
                    {{/if}}
                  </div>
                </div>
              </div>

              {{! active stack }}
              <div
                class='target target-stack span-2 {{if (eq (this.compatOf "stack") "yes") "compat-yes"}} {{if (eq (this.compatOf "stack") "no") "compat-no"}} {{if (this.isAccept "stack") "accept"}} {{if (this.isDenied "stack") "deny"}} {{if (eq this.selectedSlotId "stack") "selected-slot"}}'
                data-drop-target='stack'
              >
                <div class='t-head'>
                  <span class='t-icon'>▤</span>
                  <div class='t-title'>Active Stack</div>
                  <span class='t-fmt'>isolated</span>
                </div>
                <div class='t-subtitle'>accepts <code>CardDef</code> — any card renders as isolated</div>
                <div class='t-body'>
                  <div class='t-slot t-slot-isolated {{if this.placedStack.length "has"}}'>
                    {{#if this.placedStack.length}}
                      <div class='placed-iso-stack'>
                        {{#each this.placedStack as |pay idx|}}
                          {{#if (this.wedgeForStackIndex idx)}}
                            <div class='insert-wedge'><span class='iw-dot'></span><span class='iw-line'></span><span class='iw-dot'></span></div>
                          {{/if}}
                          <div class='placed-iso tint-{{pay.tint}}' {{flipIn (this.flipOriginFor pay.id)}}>
                            <div class='piso-hero piso-hero-bg'>
                              <div class='piso-avatar'>{{pay.avatar}}</div>
                              <div class='piso-meta'>
                                <div class='piso-name'>{{pay.name}}</div>
                                <div class='piso-type-line'>
                                  <span class='piso-type-badge'>{{pay.type}}</span>
                                  <span class='piso-format'>isolated</span>
                                </div>
                              </div>
                              <button type='button' class='placed-x' {{on 'click' (fn this.removePlacement "stack" pay.id)}}>×</button>
                            </div>
                            <dl class='piso-fields'>
                              <div class='piso-field'>
                                <dt>meta</dt>
                                <dd>{{pay.meta}}</dd>
                              </div>
                              <div class='piso-field'>
                                <dt>ancestry</dt>
                                <dd class='piso-chain'>{{pay.type}} → … → CardDef</dd>
                              </div>
                              <div class='piso-field'>
                                <dt>id</dt>
                                <dd class='piso-url'>{{pay.url}}</dd>
                              </div>
                            </dl>
                            <div class='piso-footer'>
                              <span class='piso-footer-action'>open</span>
                              <span class='piso-footer-sep'>·</span>
                              <span class='piso-footer-action'>view source</span>
                            </div>
                          </div>
                        {{/each}}
                        {{#if (this.wedgeForStackIndex this.stackTailIndex)}}
                          <div class='insert-wedge'><span class='iw-dot'></span><span class='iw-line'></span><span class='iw-dot'></span></div>
                        {{/if}}
                      </div>
                    {{else}}
                      <span class='t-placeholder'>drop any card here</span>
                    {{/if}}
                  </div>
                </div>
              </div>

              {{! AI composer }}
              <div
                class='target target-composer span-2 {{if (eq (this.compatOf "composer") "yes") "compat-yes"}} {{if (eq (this.compatOf "composer") "no") "compat-no"}} {{if (this.isAccept "composer") "accept"}} {{if (this.isDenied "composer") "deny"}} {{if (eq this.selectedSlotId "composer") "selected-slot"}}'
                data-drop-target='composer'
              >
                <div class='t-head'>
                  <span class='t-icon'>✉</span>
                  <div class='t-title'>AI Composer</div>
                  <span class='t-fmt'>atom</span>
                </div>
                <div class='t-subtitle'>accepts <code>CardDef</code> — attaches as inline atom chip</div>
                <div class='t-body'>
                  <div class='t-slot t-slot-atom'>
                    <span class='t-atom-prompt'>@</span>
                    {{#each this.placedComposer as |pay|}}
                      <span class='placed-atom tint-{{pay.tint}}' {{flipIn (this.flipOriginFor pay.id)}}>
                        <span class='atom-dot'></span>
                        <span class='placed-atom-name'>@{{pay.name}}</span>
                        <button type='button' class='placed-x' {{on 'click' (fn this.removePlacement "composer" pay.id)}}>×</button>
                      </span>
                    {{/each}}
                    {{#unless this.placedComposer.length}}
                      <span class='t-placeholder t-placeholder-inline'>mention a card…</span>
                    {{/unless}}
                  </div>
                </div>
              </div>

              {{! team sidebar — Person-typed }}
              <div
                class='target target-team {{if (eq (this.compatOf "team") "yes") "compat-yes"}} {{if (eq (this.compatOf "team") "no") "compat-no"}} {{if (this.isAccept "team") "accept"}} {{if (this.isDenied "team") "deny"}} {{if (eq this.selectedSlotId "team") "selected-slot"}}'
                data-drop-target='team'
              >
                <div class='t-head'>
                  <span class='t-icon'>◉</span>
                  <div class='t-title'>Team Sidebar</div>
                  <span class='t-fmt'>fitted</span>
                </div>
                <div class='t-subtitle'>accepts <code>Person</code> only (no pets, no invoices)</div>
                <div class='t-body'>
                  <div class='t-slot t-slot-fitted {{if this.placedTeam.length "has"}}'>
                    {{#if this.placedTeam.length}}
                      <div class='placed-row'>
                        {{#each this.placedTeam as |pay|}}
                          <div class='placed-tile tint-{{pay.tint}}' {{flipIn (this.flipOriginFor pay.id)}}>
                            <span class='placed-avatar'>{{pay.avatar}}</span>
                            <span class='placed-tile-body'>
                              <span class='placed-name'>{{pay.name}}</span>
                              <span class='placed-tile-type'>{{pay.type}}</span>
                            </span>
                            <button type='button' class='placed-x' {{on 'click' (fn this.removePlacement "team" pay.id)}}>×</button>
                          </div>
                        {{/each}}
                      </div>
                    {{else}}
                      <span class='t-placeholder'>drop a Person here</span>
                    {{/if}}
                  </div>
                </div>
              </div>

              {{! foreign realm — async Job }}
              <div
                class='target target-foreign span-2 {{if (eq (this.compatOf "foreign") "yes") "compat-yes"}} {{if (eq (this.compatOf "foreign") "no") "compat-no"}} {{if (this.isAccept "foreign") "accept"}} {{if (this.isDenied "foreign") "deny"}} {{if (eq this.selectedSlotId "foreign") "selected-slot"}}'
                data-drop-target='foreign'
              >
                <div class='t-head'>
                  <span class='t-icon'>⟳</span>
                  <div class='t-title'>Foreign Realm</div>
                  <span class='t-fmt t-fmt-job'>async · Job</span>
                </div>
                <div class='t-subtitle'>accepts <code>CardDef</code> — cross-realm copy schedules a Job (1.8s)</div>
                <div class='t-body'>
                  <div class='t-slot t-slot-fitted {{if this.foreignHasContent "has"}}'>
                    {{#if this.foreignHasContent}}
                      <div class='placed-row'>
                        {{#each this.foreignPendingJobs as |job|}}
                          <div class='placed-tile placed-pending tint-{{job.payload.tint}}' data-payload-id={{job.payload.id}}>
                            <span class='placed-avatar'>{{job.payload.avatar}}</span>
                            <span class='placed-tile-body'>
                              <span class='placed-name'>{{job.payload.name}}</span>
                              <span class='placed-tile-type'>{{job.payload.type}}</span>
                            </span>
                            <span class='pending-spinner' aria-hidden='true'></span>
                            <span class='pending-label'>Job…</span>
                          </div>
                        {{/each}}
                        {{#each this.placedForeign as |pay|}}
                          <div class='placed-tile tint-{{pay.tint}}' {{flipIn (this.flipOriginFor pay.id)}}>
                            <span class='placed-avatar'>{{pay.avatar}}</span>
                            <span class='placed-tile-body'>
                              <span class='placed-name'>{{pay.name}}</span>
                              <span class='placed-tile-type'>{{pay.type}}</span>
                            </span>
                            <button type='button' class='placed-x' {{on 'click' (fn this.removePlacement "foreign" pay.id)}}>×</button>
                          </div>
                        {{/each}}
                      </div>
                    {{else}}
                      <span class='t-placeholder'>drop any card here — watch the Job spawn</span>
                    {{/if}}
                  </div>
                </div>
              </div>

              {{! folder with dwell }}
              <div
                class='target target-folder span-2 {{if (eq (this.compatOf "folder") "yes") "compat-yes"}} {{if (eq (this.compatOf "folder") "no") "compat-no"}} {{if (this.isAccept "folder") "accept"}} {{if (this.isDenied "folder") "deny"}} {{if (eq this.selectedSlotId "folder") "selected-slot"}} {{if this.folderOpen "open"}}'
                data-drop-target='folder'
              >
                <div class='t-head'>
                  <span class='t-icon folder-glyph'>{{if this.folderOpen '▼' '▶'}}</span>
                  <div class='t-title'>Zoo Keeper Notes</div>
                  <span class='t-fmt t-fmt-62'>dwell · §62</span>
                </div>
                <div class='t-subtitle'>
                  {{#if this.folderOpen}}
                    opened — child drop zones revealed
                  {{else}}
                    hover <strong>600ms</strong> during drag to open
                  {{/if}}
                </div>

                {{#if this.dwellActiveFolder}}
                  <div class='dwell-ring' style={{this.dwellRingStyle}}>
                    <svg viewBox='0 0 36 36' aria-hidden='true'>
                      <circle class='ring-bg' cx='18' cy='18' r='15'></circle>
                      <circle class='ring-fill' cx='18' cy='18' r='15'></circle>
                    </svg>
                    <span class='dwell-label'>Reflex · {{this.dwellPercent}}</span>
                  </div>
                {{/if}}

                {{#if this.folderOpen}}
                  <div class='folder-kids'>
                    <div
                      class='target target-child {{if (eq (this.compatOf "folder-pets") "yes") "compat-yes"}} {{if (eq (this.compatOf "folder-pets") "no") "compat-no"}} {{if (this.isAccept "folder-pets") "accept"}} {{if (this.isDenied "folder-pets") "deny"}} {{if (eq this.selectedSlotId "folder-pets") "selected-slot"}}'
                      data-drop-target='folder-pets'
                    >
                      <div class='t-head t-head-child'>
                        <span class='t-icon'>◆</span>
                        <div class='t-title'>Pet Dossiers</div>
                      </div>
                      <div class='t-subtitle'>accepts Pet+</div>
                      {{#if this.placedFolderPets.length}}
                        <div class='placed-row placed-row-tight'>
                          {{#each this.placedFolderPets as |pay|}}
                            <div class='placed-tile tint-{{pay.tint}}' {{flipIn (this.flipOriginFor pay.id)}}>
                              <span class='placed-avatar'>{{pay.avatar}}</span>
                              <span class='placed-tile-body'>
                                <span class='placed-name'>{{pay.name}}</span>
                                <span class='placed-tile-type'>{{pay.type}}</span>
                              </span>
                              <button type='button' class='placed-x' {{on 'click' (fn this.removePlacement "folder-pets" pay.id)}}>×</button>
                            </div>
                          {{/each}}
                        </div>
                      {{/if}}
                    </div>
                    <div
                      class='target target-child {{if (eq (this.compatOf "folder-ops") "yes") "compat-yes"}} {{if (eq (this.compatOf "folder-ops") "no") "compat-no"}} {{if (this.isAccept "folder-ops") "accept"}} {{if (this.isDenied "folder-ops") "deny"}} {{if (eq this.selectedSlotId "folder-ops") "selected-slot"}}'
                      data-drop-target='folder-ops'
                    >
                      <div class='t-head t-head-child'>
                        <span class='t-icon'>◆</span>
                        <div class='t-title'>Ops Invoices</div>
                      </div>
                      <div class='t-subtitle'>accepts Invoice+</div>
                      {{#if this.placedFolderOps.length}}
                        <div class='placed-row placed-row-tight'>
                          {{#each this.placedFolderOps as |pay|}}
                            <div class='placed-tile tint-{{pay.tint}}' {{flipIn (this.flipOriginFor pay.id)}}>
                              <span class='placed-avatar'>{{pay.avatar}}</span>
                              <span class='placed-tile-body'>
                                <span class='placed-name'>{{pay.name}}</span>
                                <span class='placed-tile-type'>{{pay.type}}</span>
                              </span>
                              <button type='button' class='placed-x' {{on 'click' (fn this.removePlacement "folder-ops" pay.id)}}>×</button>
                            </div>
                          {{/each}}
                        </div>
                      {{/if}}
                    </div>
                  </div>
                {{/if}}
              </div>

            </div>
          </main>
        </section>

        {{! ═══ AUDIT TRAIL ═══ }}
        <section class='audit'>
          <div class='panel-head'>
            <span class='panel-eyebrow'>AUDIT TRAIL · LIFECYCLE PACKETS</span>
            <button type='button' class='reset-btn' {{on 'click' this.clearHistory}}>clear</button>
          </div>
          {{#if this.history.length}}
            <ol class='audit-list'>
              {{#each this.history as |h|}}
                <li class='audit-row {{if h.accept "ok" "no"}} {{if h.pending "pending"}}'>
                  <span class='audit-time'>{{this.formatTime h.at}}</span>
                  <span class='audit-aff aff-{{h.affordance}}'>{{h.affordance}}</span>
                  <span class='audit-payload'>{{h.payloadName}}
                    <em>{{h.payloadType}}</em></span>
                  <span class='audit-arrow'>→</span>
                  <span class='audit-target'>{{h.targetName}}</span>
                  <span class='audit-result'>
                    {{#if h.pending}}
                      <span class='audit-spinner' aria-hidden='true'></span> pending
                    {{else if h.accept}}
                      placed
                    {{else}}
                      denied
                    {{/if}}
                  </span>
                  {{#if h.message}}
                    <span class='audit-msg'>{{h.message}}</span>
                  {{/if}}
                </li>
              {{/each}}
            </ol>
          {{else}}
            <div class='audit-empty'>no placements yet — drag a payload or use <code>Place…</code></div>
          {{/if}}
        </section>

        {{! ═══ GHOST (follows pointer) ═══ }}
        {{#if this.session}}
          <div
            class='ghost ghost-{{this.ghostFormat}} {{if this.denied "ghost-deny"}}'
            style={{this.ghostStyle}}
          >
            {{#if this.ghostAtom}}
              <span class='atom-dot tint-{{this.session.payload.tint}}'></span>
              <span class='atom-name'>{{this.session.payload.name}}</span>
            {{else if this.ghostIsolated}}
              <div class='iso-hero'>
                <div class='iso-avatar tint-{{this.session.payload.tint}}'>{{this.session.payload.avatar}}</div>
                <div class='iso-meta'>
                  <div class='iso-name'>{{this.session.payload.name}}</div>
                  <div class='iso-type'>{{this.session.payload.type}}</div>
                </div>
              </div>
              <div class='iso-body'>{{this.session.payload.meta}}</div>
            {{else}}
              <div class='gfit-avatar tint-{{this.session.payload.tint}}'>{{this.session.payload.avatar}}</div>
              <div class='gfit-body'>
                <div class='gfit-name'>{{this.session.payload.name}}</div>
                <div class='gfit-type'>{{this.session.payload.type}}</div>
              </div>
            {{/if}}
          </div>
        {{/if}}

        {{! ═══ DENIAL TOOLTIP (near ghost) ═══ }}
        {{#if this.showDeny}}
          <div class='deny-tooltip' style={{this.ghostStyle}}>
            <span class='dt-x'>✗</span>
            <span>Expected <strong>{{this.currentDecision.expected}}</strong>
              or descendant; got <strong>{{this.currentDecision.got}}</strong></span>
          </div>
        {{/if}}

        {{! ═══ PALETTE OVERLAY ═══ }}
        {{#if this.palettePayloadId}}
          <div class='palette-overlay' {{on 'click' this.closePalette}}>
            <div class='palette' {{on 'click' this.stopPropagation}}>
              <div class='pal-head'>
                <span class='pal-caret'>›</span>
                <span class='pal-query'>place <strong>{{this.palettePayload.name}}</strong>
                  <em>({{this.palettePayload.type}})</em>…</span>
                <button type='button' class='pal-close' {{on 'click' this.closePalette}}>esc</button>
              </div>
              <div class='pal-list'>
                {{#each this.paletteCandidates as |c|}}
                  <button
                    type='button'
                    class='pal-row {{c.rowClass}}'
                    disabled={{c.disabled}}
                    {{on 'click' (fn this.palettePlace c.target)}}
                  >
                    <span class='pal-tick'>{{c.tickGlyph}}</span>
                    <span class='pal-tgt'>
                      <span class='pal-tname'>{{c.target.name}}</span>
                      <span class='pal-tsub'>{{c.target.subtitle}}</span>
                    </span>
                    <span class='pal-fmt'>{{c.target.format}}</span>
                    {{#if c.decision.accept}}
                      <span class='pal-verdict pal-verdict-ok'>⏎ commit</span>
                    {{else}}
                      <span class='pal-verdict pal-verdict-no'>{{c.decision.got}} ∉ {{c.decision.expected}}</span>
                    {{/if}}
                  </button>
                {{/each}}
              </div>
              <div class='pal-foot'>
                palette fires <code>AddPetToEnclosure</code> (or equivalent) — same Command as drag · same audit trail · same Packet contract
              </div>
            </div>
          </div>
        {{/if}}

      </article>

      <style scoped>
        /* ─── Screen reader only ─── */
        .sr-only {
          position: absolute;
          width: 1px; height: 1px;
          padding: 0; margin: -1px;
          overflow: hidden;
          clip: rect(0, 0, 0, 0);
          white-space: nowrap;
          border: 0;
        }

        /* ─── Root ─── */
        .proto {
          position: relative;
          font-family: var(--font-sans, ui-sans-serif, system-ui, -apple-system, sans-serif);
          color: var(--foreground, #111);
          background: var(--background, #fafaf9);
          min-height: 100%;
          padding: calc(var(--spacing, 0.25rem) * 6);
          user-select: none;
          line-height: 1.5;
        }

        .proto-head {
          padding-bottom: calc(var(--spacing, 0.25rem) * 4);
          border-bottom: 1px solid var(--border, #e5e5e4);
          margin-bottom: calc(var(--spacing, 0.25rem) * 4);
        }
        .proto-eyebrow {
          font-family: var(--font-mono, ui-monospace, monospace);
          font-size: 0.72rem;
          letter-spacing: 0.14em;
          color: var(--muted-foreground, #6b6b68);
          margin-bottom: 0.35rem;
        }
        .proto-title {
          margin: 0;
          font-size: 1.5rem;
          font-weight: 600;
          line-height: 1.25;
          letter-spacing: -0.01em;
        }
        .proto-title .chip {
          display: inline-block;
          padding: 0.08rem 0.5rem;
          background: color-mix(in srgb, var(--chart-3, #3b82f6) 14%, var(--card, #fff));
          color: var(--chart-3, #3b82f6);
          border-radius: 4px;
          font-family: var(--font-mono);
          font-size: 0.9rem;
          vertical-align: middle;
        }
        .proto-hints {
          display: flex;
          flex-wrap: wrap;
          gap: 0.8rem 1.5rem;
          margin-top: 0.85rem;
          font-size: 0.82rem;
          color: var(--muted-foreground);
        }
        .hint-item kbd {
          display: inline-block;
          font-family: var(--font-mono);
          font-size: 0.72rem;
          padding: 0.1rem 0.4rem;
          border: 1px solid var(--border);
          border-radius: 3px;
          background: var(--card);
          margin-right: 0.25rem;
          box-shadow: 0 1px 0 var(--border);
        }

        .announce-strip {
          display: flex;
          align-items: center;
          gap: 0.6rem;
          margin-top: 0.75rem;
          padding: 0.45rem 0.7rem;
          background: var(--background);
          border: 1px solid var(--border);
          border-radius: 6px;
          font-family: var(--font-mono);
          font-size: 0.76rem;
          transition: background 0.15s, border-color 0.15s;
        }
        .announce-strip.active {
          background: color-mix(in srgb, var(--primary) 6%, var(--card));
          border-color: color-mix(in srgb, var(--primary) 35%, var(--border));
        }
        .announce-label {
          font-size: 0.64rem;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          padding: 0.12rem 0.45rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: 3px;
        }
        .announce-strip.active .announce-label {
          color: var(--primary);
          border-color: color-mix(in srgb, var(--primary) 40%, var(--border));
        }
        .announce-text {
          color: var(--muted-foreground);
          font-style: italic;
        }
        .announce-strip.active .announce-text {
          color: var(--foreground);
          font-style: normal;
        }

        /* ─── Grid shell ─── */
        .proto-grid {
          display: grid;
          grid-template-columns: 300px 1fr;
          gap: calc(var(--spacing, 0.25rem) * 4);
          margin-bottom: calc(var(--spacing, 0.25rem) * 4);
        }

        .panel-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 0.75rem;
        }
        .panel-eyebrow {
          font-family: var(--font-mono);
          font-size: 0.7rem;
          letter-spacing: 0.13em;
          color: var(--muted-foreground);
        }
        .panel-count {
          font-family: var(--font-mono);
          font-size: 0.7rem;
          padding: 0.1rem 0.4rem;
          background: color-mix(in srgb, var(--muted-foreground) 10%, transparent);
          border-radius: 3px;
          color: var(--muted-foreground);
        }
        .reset-btn {
          background: transparent;
          border: 1px solid var(--border);
          border-radius: 4px;
          padding: 0.15rem 0.5rem;
          font-family: var(--font-mono);
          font-size: 0.7rem;
          color: var(--muted-foreground);
          cursor: pointer;
        }
        .reset-btn:hover { background: var(--card); color: var(--foreground); }

        /* ─── Library panel ─── */
        .library {
          background: var(--card, #fff);
          border: 1px solid var(--border);
          border-radius: var(--radius, 10px);
          padding: 1rem 1.1rem;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          box-shadow: var(--shadow-sm, 0 1px 2px rgba(0,0,0,0.04));
        }
        .payload-list {
          display: grid;
          gap: 0.5rem;
        }
        .payload-card {
          display: grid;
          grid-template-columns: 40px 1fr auto;
          gap: 0.65rem;
          align-items: center;
          padding: 0.65rem 0.75rem;
          background: var(--background);
          border: 1px solid var(--border);
          border-radius: 8px;
          cursor: grab;
          transition: transform 0.12s ease, box-shadow 0.12s ease, border-color 0.12s;
          touch-action: none;
        }
        .payload-card:hover {
          border-color: color-mix(in srgb, var(--primary) 40%, var(--border));
          transform: translateY(-1px);
          box-shadow: 0 2px 6px rgba(0,0,0,0.06);
        }
        .payload-card.dragging {
          opacity: 0.45;
          cursor: grabbing;
        }
        .payload-card.focused,
        .payload-card:focus-visible {
          outline: 2px solid var(--primary);
          outline-offset: 2px;
          border-color: var(--primary);
        }
        .payload-card:focus { outline: none; }
        .payload-card:focus-visible {
          outline: 2px solid var(--primary);
          outline-offset: 2px;
        }
        .pc-avatar {
          width: 38px; height: 38px;
          border-radius: 8px;
          display: grid; place-items: center;
          font-family: var(--font-mono);
          font-size: 0.78rem;
          font-weight: 600;
          color: white;
          letter-spacing: 0.02em;
        }
        .tint-dog    .pc-avatar, .pc-avatar.tint-dog,
        .iso-avatar.tint-dog,    .gfit-avatar.tint-dog,
        .atom-dot.tint-dog       { background: linear-gradient(135deg, #c2410c, #fb923c); }
        .tint-cat    .pc-avatar, .pc-avatar.tint-cat,
        .iso-avatar.tint-cat,    .gfit-avatar.tint-cat,
        .atom-dot.tint-cat       { background: linear-gradient(135deg, #7c3aed, #c4b5fd); }
        .tint-bird   .pc-avatar, .pc-avatar.tint-bird,
        .iso-avatar.tint-bird,   .gfit-avatar.tint-bird,
        .atom-dot.tint-bird      { background: linear-gradient(135deg, #059669, #6ee7b7); }
        .tint-inv    .pc-avatar, .pc-avatar.tint-inv,
        .iso-avatar.tint-inv,    .gfit-avatar.tint-inv,
        .atom-dot.tint-inv       { background: linear-gradient(135deg, #475569, #94a3b8); }
        .tint-person .pc-avatar, .pc-avatar.tint-person,
        .iso-avatar.tint-person, .gfit-avatar.tint-person,
        .atom-dot.tint-person    { background: linear-gradient(135deg, #0369a1, #60a5fa); }
        .tint-task   .pc-avatar, .pc-avatar.tint-task,
        .iso-avatar.tint-task,   .gfit-avatar.tint-task,
        .atom-dot.tint-task      { background: linear-gradient(135deg, #a16207, #fde047); }

        .atom-dot { width: 8px; height: 8px; border-radius: 50%; }

        .pc-body { display: flex; flex-direction: column; gap: 0.05rem; min-width: 0; }
        .pc-name { font-weight: 600; font-size: 0.9rem; }
        .pc-type {
          font-family: var(--font-mono);
          font-size: 0.68rem;
          letter-spacing: 0.04em;
          color: var(--muted-foreground);
        }
        .pc-meta {
          font-size: 0.72rem;
          color: var(--muted-foreground);
          margin-top: 0.1rem;
        }
        .pc-place {
          background: transparent;
          border: 1px solid var(--chart-3, #3b82f6);
          color: var(--chart-3, #3b82f6);
          border-radius: 4px;
          padding: 0.22rem 0.55rem;
          font-family: var(--font-mono);
          font-size: 0.7rem;
          letter-spacing: 0.02em;
          cursor: pointer;
          transition: background 0.12s;
          white-space: nowrap;
        }
        .pc-place:hover {
          background: color-mix(in srgb, var(--chart-3, #3b82f6) 12%, var(--card));
        }

        /* Selection rings */
        .payload-card.selected-src {
          outline: 2.5px solid var(--chart-2, #f59e0b);
          outline-offset: 2px;
          border-color: var(--chart-2, #f59e0b);
          background: color-mix(in srgb, var(--chart-2, #f59e0b) 6%, var(--background));
          box-shadow: 0 0 0 6px color-mix(in srgb, var(--chart-2, #f59e0b) 14%, transparent);
        }
        .target.selected-slot {
          outline: 2.5px solid var(--chart-3, #3b82f6);
          outline-offset: 3px;
          box-shadow: 0 0 0 6px color-mix(in srgb, var(--chart-3, #3b82f6) 14%, transparent);
        }

        /* ─── Selection bar ─── */
        .panel-hint {
          font-family: var(--font-sans);
          font-style: italic;
          font-size: 0.72rem;
          color: var(--muted-foreground);
          letter-spacing: 0;
          text-transform: none;
          margin-left: 0.4rem;
        }
        .selection-bar {
          display: flex;
          align-items: center;
          gap: 0.6rem;
          padding: 0.55rem 0.75rem;
          margin-bottom: 0.75rem;
          background: linear-gradient(
            90deg,
            color-mix(in srgb, var(--chart-2, #f59e0b) 7%, var(--card)),
            color-mix(in srgb, var(--chart-3, #3b82f6) 7%, var(--card))
          );
          border: 1.5px solid color-mix(in srgb, var(--primary) 40%, var(--border));
          border-radius: 8px;
          animation: sb-in 0.18s ease-out;
          flex-wrap: wrap;
        }
        @keyframes sb-in {
          from { opacity: 0; transform: translateY(-3px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        .sb-label {
          font-family: var(--font-mono);
          font-size: 0.64rem;
          letter-spacing: 0.14em;
          color: var(--muted-foreground);
          padding: 0.15rem 0.45rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: 3px;
        }
        .sb-slot {
          display: flex;
          flex-direction: column;
          gap: 0.1rem;
        }
        .sb-role {
          font-family: var(--font-mono);
          font-size: 0.6rem;
          letter-spacing: 0.12em;
          text-transform: uppercase;
        }
        .sb-slot-src .sb-role { color: var(--chart-2, #f59e0b); }
        .sb-slot-dst .sb-role { color: var(--chart-3, #3b82f6); }
        .sb-chip {
          display: inline-flex;
          align-items: center;
          gap: 0.4rem;
          padding: 0.25rem 0.55rem 0.25rem 0.3rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: 999px;
          font-size: 0.82rem;
          white-space: nowrap;
        }
        .sb-avatar {
          width: 22px; height: 22px;
          border-radius: 50%;
          display: grid; place-items: center;
          color: white;
          font-family: var(--font-mono);
          font-weight: 600;
          font-size: 0.62rem;
        }
        .sb-chip.tint-dog .sb-avatar    { background: linear-gradient(135deg, #c2410c, #fb923c); }
        .sb-chip.tint-cat .sb-avatar    { background: linear-gradient(135deg, #7c3aed, #c4b5fd); }
        .sb-chip.tint-bird .sb-avatar   { background: linear-gradient(135deg, #059669, #6ee7b7); }
        .sb-chip.tint-inv .sb-avatar    { background: linear-gradient(135deg, #475569, #94a3b8); }
        .sb-chip.tint-person .sb-avatar { background: linear-gradient(135deg, #0369a1, #60a5fa); }
        .sb-chip.tint-task .sb-avatar   { background: linear-gradient(135deg, #a16207, #fde047); }
        .sb-name { font-weight: 600; }
        .sb-type {
          font-family: var(--font-mono);
          font-size: 0.68rem;
          color: var(--muted-foreground);
        }
        .sb-chip-dst {
          background: color-mix(in srgb, var(--chart-3, #3b82f6) 10%, var(--card));
          border-color: var(--chart-3, #3b82f6);
        }
        .sb-fmt {
          font-family: var(--font-mono);
          font-size: 0.66rem;
          color: var(--chart-3, #3b82f6);
          padding: 0.08rem 0.35rem;
          background: var(--card);
          border-radius: 3px;
        }
        .sb-empty {
          font-family: var(--font-mono);
          font-size: 0.78rem;
          color: var(--muted-foreground);
          font-style: italic;
          padding: 0.25rem 0.55rem;
          border: 1px dashed var(--border);
          border-radius: 999px;
        }
        .sb-arrow {
          color: var(--muted-foreground);
          font-size: 1.1rem;
        }
        .sb-cta {
          margin-left: auto;
          font-family: var(--font-mono);
          font-size: 0.76rem;
          color: var(--muted-foreground);
        }
        .sb-kbd {
          display: inline-block;
          padding: 0.18rem 0.5rem;
          border: 1.5px solid var(--chart-1, #22c1a8);
          border-radius: 4px;
          background: color-mix(in srgb, var(--chart-1, #22c1a8) 14%, var(--card));
          color: var(--chart-1, #22c1a8);
          font-weight: 600;
          font-size: 0.76rem;
          margin-right: 0.25rem;
        }
        .sb-deny {
          color: var(--destructive, #ef4444);
          font-family: var(--font-mono);
          font-size: 0.74rem;
        }
        .sb-idle {
          color: var(--muted-foreground);
          font-style: italic;
        }
        .sb-cancel {
          background: transparent;
          border: 1px solid var(--border);
          border-radius: 4px;
          padding: 0.2rem 0.5rem;
          font-family: var(--font-mono);
          font-size: 0.7rem;
          color: var(--muted-foreground);
          cursor: pointer;
        }
        .sb-cancel:hover { color: var(--foreground); background: var(--card); }

        /* Audit paste affordance */
        .aff-paste {
          background: color-mix(in srgb, var(--chart-2, #f59e0b) 14%, var(--card));
          color: var(--chart-2, #f59e0b);
        }

        .lib-foot {
          margin-top: 0.5rem;
          padding-top: 0.7rem;
          border-top: 1px dashed var(--border);
          font-size: 0.74rem;
          color: var(--muted-foreground);
        }
        .foot-line {
          display: flex; justify-content: space-between;
          font-family: var(--font-mono);
          font-size: 0.64rem;
          letter-spacing: 0.1em;
          text-transform: uppercase;
          margin-bottom: 0.45rem;
        }
        .foot-grid {
          display: grid;
          grid-template-columns: max-content 1fr;
          gap: 0.25rem 0.6rem;
          font-family: var(--font-mono);
          font-size: 0.7rem;
        }
        .foot-grid b {
          color: var(--chart-1, #22c1a8);
          font-weight: 600;
        }

        /* ─── Workspace ─── */
        .workspace {
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: 1rem 1.1rem;
          box-shadow: var(--shadow-sm);
        }
        .target-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 0.7rem;
        }
        .span-2 { grid-column: span 2; }

        .target {
          background: var(--background);
          border: 1.5px dashed var(--border);
          border-radius: 10px;
          padding: 0.85rem 1rem;
          transition: border-color 0.15s, background 0.15s, box-shadow 0.15s;
          position: relative;
          min-height: 128px;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .target.open {
          border-color: color-mix(in srgb, var(--primary) 50%, var(--border));
          border-style: solid;
          background: color-mix(in srgb, var(--primary) 3%, var(--background));
        }

        /* ── Three-tier lighting while a drag is active ── */

        /* Tier 1 · INTERMEDIATE — compatible, not hovered */
        .target.compat-yes {
          border-color: color-mix(in srgb, var(--chart-1, #22c1a8) 42%, var(--border));
          border-style: dashed;
          background: color-mix(in srgb, var(--chart-1, #22c1a8) 3%, var(--background));
          box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--chart-1, #22c1a8) 8%, transparent);
        }

        /* Tier 1 · DIMMED — incompatible, not hovered */
        .target.compat-no {
          opacity: 0.38;
          filter: grayscale(0.55);
          border-style: dashed;
        }

        /* Tier 2 · FULL ACCEPT — hovered + compatible (overrides compat-yes) */
        .target.accept {
          border-color: var(--chart-1, #22c1a8);
          border-style: solid;
          background: color-mix(in srgb, var(--chart-1, #22c1a8) 10%, var(--background));
          box-shadow:
            0 0 0 4px color-mix(in srgb, var(--chart-1, #22c1a8) 22%, transparent),
            0 6px 18px color-mix(in srgb, var(--chart-1, #22c1a8) 18%, transparent);
          transform: translateY(-1px);
          animation: accept-pulse 1.4s ease-in-out infinite;
        }
        @keyframes accept-pulse {
          0%, 100% { box-shadow:
            0 0 0 4px color-mix(in srgb, var(--chart-1, #22c1a8) 22%, transparent),
            0 6px 18px color-mix(in srgb, var(--chart-1, #22c1a8) 18%, transparent); }
          50%      { box-shadow:
            0 0 0 6px color-mix(in srgb, var(--chart-1, #22c1a8) 14%, transparent),
            0 8px 22px color-mix(in srgb, var(--chart-1, #22c1a8) 22%, transparent); }
        }

        /* Tier 2 · FULL DENY — hovered + incompatible (overrides compat-no) */
        .target.deny {
          opacity: 1;
          filter: none;
          border-color: var(--destructive, #ef4444);
          border-style: solid;
          background: color-mix(in srgb, var(--destructive, #ef4444) 8%, var(--background));
          box-shadow:
            0 0 0 4px color-mix(in srgb, var(--destructive, #ef4444) 18%, transparent),
            0 6px 18px color-mix(in srgb, var(--destructive, #ef4444) 14%, transparent);
        }

        .btn-group { display: flex; gap: 0.35rem; }

        /* ─── Fitted format (boxed tile with avatar + type subtitle) ─── */
        .t-slot.has { background: transparent; }
        .placed-row {
          display: flex;
          flex-wrap: wrap;
          gap: 0.45rem;
          padding: 0.3rem;
          width: 100%;
          align-self: start;
        }
        .placed-row-tight { padding: 0.15rem 0; }
        .placed-tile {
          display: flex;
          align-items: center;
          gap: 0.55rem;
          padding: 0.45rem 0.55rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: 8px;
          box-shadow: 0 1px 3px rgba(0,0,0,0.05);
          min-width: 140px;
          position: relative;
        }
        .placed-tile::before {
          content: '';
          position: absolute;
          left: 0; top: 0; bottom: 0;
          width: 3px;
          background: var(--tile-accent, var(--border));
          border-radius: 3px 0 0 3px;
        }
        .placed-tile.tint-dog    { --tile-accent: #fb923c; }
        .placed-tile.tint-cat    { --tile-accent: #a78bfa; }
        .placed-tile.tint-bird   { --tile-accent: #10b981; }
        .placed-tile.tint-inv    { --tile-accent: #64748b; }
        .placed-tile.tint-person { --tile-accent: #3b82f6; }
        .placed-tile.tint-task   { --tile-accent: #eab308; }
        .placed-avatar {
          width: 32px; height: 32px;
          border-radius: 7px;
          display: grid; place-items: center;
          color: white;
          font-family: var(--font-mono);
          font-weight: 600;
          font-size: 0.68rem;
          flex-shrink: 0;
        }
        .tint-dog    .placed-avatar { background: linear-gradient(135deg, #c2410c, #fb923c); }
        .tint-cat    .placed-avatar { background: linear-gradient(135deg, #7c3aed, #c4b5fd); }
        .tint-bird   .placed-avatar { background: linear-gradient(135deg, #059669, #6ee7b7); }
        .tint-inv    .placed-avatar { background: linear-gradient(135deg, #475569, #94a3b8); }
        .tint-person .placed-avatar { background: linear-gradient(135deg, #0369a1, #60a5fa); }
        .tint-task   .placed-avatar { background: linear-gradient(135deg, #a16207, #fde047); }
        .placed-tile-body {
          display: flex;
          flex-direction: column;
          gap: 0.05rem;
          flex: 1;
          min-width: 0;
        }
        .placed-name {
          font-weight: 600;
          font-size: 0.82rem;
          line-height: 1.15;
        }
        .placed-tile-type {
          font-family: var(--font-mono);
          font-size: 0.64rem;
          letter-spacing: 0.04em;
          color: var(--muted-foreground);
        }
        .placed-x {
          border: 0;
          background: transparent;
          color: var(--muted-foreground);
          font-size: 1rem;
          line-height: 1;
          padding: 0 0.2rem;
          cursor: pointer;
          border-radius: 3px;
          flex-shrink: 0;
        }
        .placed-x:hover {
          background: color-mix(in srgb, var(--destructive, #ef4444) 14%, transparent);
          color: var(--destructive, #ef4444);
        }

        /* ─── Isolated format (full card with gradient hero + field rows + footer) ─── */
        .placed-iso-stack {
          display: flex;
          flex-direction: column;
          gap: 0.6rem;
          padding: 0.3rem;
          width: 100%;
        }
        .placed-iso {
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: 10px;
          overflow: hidden;
          box-shadow: 0 2px 8px rgba(0,0,0,0.06);
          display: flex;
          flex-direction: column;
        }
        .piso-hero {
          display: flex;
          align-items: center;
          gap: 0.7rem;
          padding: 0.7rem 0.9rem;
          position: relative;
          color: white;
        }
        .piso-hero-bg {
          background: var(--hero-grad, linear-gradient(135deg, #64748b, #94a3b8));
        }
        .placed-iso.tint-dog    .piso-hero-bg { background: linear-gradient(135deg, #9a3412, #fb923c); }
        .placed-iso.tint-cat    .piso-hero-bg { background: linear-gradient(135deg, #5b21b6, #a78bfa); }
        .placed-iso.tint-bird   .piso-hero-bg { background: linear-gradient(135deg, #065f46, #10b981); }
        .placed-iso.tint-inv    .piso-hero-bg { background: linear-gradient(135deg, #334155, #64748b); }
        .placed-iso.tint-person .piso-hero-bg { background: linear-gradient(135deg, #0c4a6e, #0ea5e9); }
        .placed-iso.tint-task   .piso-hero-bg { background: linear-gradient(135deg, #713f12, #eab308); }
        .piso-avatar {
          width: 46px; height: 46px;
          border-radius: 10px;
          display: grid; place-items: center;
          color: white;
          font-family: var(--font-mono);
          font-weight: 700;
          font-size: 0.92rem;
          background: rgba(255,255,255,0.22);
          backdrop-filter: blur(6px);
          border: 1px solid rgba(255,255,255,0.35);
        }
        .piso-meta { flex: 1; min-width: 0; }
        .piso-name {
          font-weight: 700;
          font-size: 1.05rem;
          letter-spacing: -0.01em;
          margin-bottom: 0.15rem;
        }
        .piso-type-line {
          display: inline-flex;
          align-items: center;
          gap: 0.4rem;
        }
        .piso-type-badge {
          font-family: var(--font-mono);
          font-size: 0.68rem;
          letter-spacing: 0.04em;
          padding: 0.12rem 0.45rem;
          background: rgba(255,255,255,0.22);
          border-radius: 3px;
          border: 1px solid rgba(255,255,255,0.35);
        }
        .piso-format {
          font-family: var(--font-mono);
          font-size: 0.62rem;
          letter-spacing: 0.1em;
          opacity: 0.78;
        }
        .placed-iso .placed-x {
          color: rgba(255,255,255,0.85);
          font-size: 1.05rem;
        }
        .placed-iso .placed-x:hover {
          background: rgba(255,255,255,0.22);
          color: white;
        }
        .piso-fields {
          display: grid;
          gap: 0;
          margin: 0;
          padding: 0.3rem 0.9rem 0.45rem;
          background: var(--card);
        }
        .piso-field {
          display: grid;
          grid-template-columns: 72px 1fr;
          gap: 0.6rem;
          padding: 0.35rem 0;
          border-bottom: 1px solid color-mix(in srgb, var(--border) 80%, transparent);
        }
        .piso-field:last-child { border-bottom: 0; }
        .piso-field dt {
          font-family: var(--font-mono);
          font-size: 0.64rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          padding-top: 0.08rem;
        }
        .piso-field dd {
          margin: 0;
          font-size: 0.82rem;
          min-width: 0;
        }
        .piso-chain, .piso-url {
          font-family: var(--font-mono);
          font-size: 0.72rem;
          color: var(--muted-foreground);
          word-break: break-all;
        }
        .piso-footer {
          display: flex;
          gap: 0.4rem;
          align-items: center;
          padding: 0.4rem 0.9rem;
          background: color-mix(in srgb, var(--muted-foreground) 4%, transparent);
          border-top: 1px solid var(--border);
          font-family: var(--font-mono);
          font-size: 0.68rem;
          letter-spacing: 0.04em;
        }
        .piso-footer-action {
          color: var(--primary);
          cursor: pointer;
        }
        .piso-footer-action:hover { text-decoration: underline; }
        .piso-footer-sep { color: var(--muted-foreground); }

        /* ─── Atom format (tight inline chip — @mention style) ─── */
        .placed-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.28rem;
          padding: 0.14rem 0.4rem 0.14rem 0.35rem;
          background: color-mix(in srgb, var(--chart-3, #3b82f6) 10%, var(--card));
          border: 1px solid color-mix(in srgb, var(--chart-3, #3b82f6) 55%, var(--border));
          border-radius: 4px;
          font-size: 0.74rem;
          line-height: 1;
          margin-right: 0.2rem;
        }
        .placed-atom .atom-dot {
          width: 5px; height: 5px;
          border-radius: 50%;
        }
        .placed-atom.tint-dog    .atom-dot { background: #fb923c; }
        .placed-atom.tint-cat    .atom-dot { background: #a78bfa; }
        .placed-atom.tint-bird   .atom-dot { background: #10b981; }
        .placed-atom.tint-inv    .atom-dot { background: #64748b; }
        .placed-atom.tint-person .atom-dot { background: #3b82f6; }
        .placed-atom.tint-task   .atom-dot { background: #eab308; }
        .placed-atom-name {
          font-weight: 500;
          color: var(--chart-3, #3b82f6);
        }
        .placed-atom .placed-x {
          font-size: 0.78rem;
          padding: 0 0.1rem;
          color: color-mix(in srgb, var(--chart-3, #3b82f6) 60%, var(--muted-foreground));
        }

        /* Insert-between wedge (Active Stack) */
        .insert-wedge {
          display: flex;
          align-items: center;
          gap: 0;
          padding: 0.15rem 0.35rem;
          height: 12px;
          animation: wedge-in 0.14s ease-out;
        }
        @keyframes wedge-in {
          from { opacity: 0; transform: scaleY(0.4); }
          to   { opacity: 1; transform: scaleY(1); }
        }
        .iw-dot {
          width: 8px; height: 8px;
          border-radius: 50%;
          background: var(--chart-1, #22c1a8);
          flex-shrink: 0;
          box-shadow: 0 0 0 3px color-mix(in srgb, var(--chart-1, #22c1a8) 20%, transparent);
        }
        .iw-line {
          flex: 1;
          height: 2px;
          background: var(--chart-1, #22c1a8);
          box-shadow: 0 0 6px color-mix(in srgb, var(--chart-1, #22c1a8) 40%, transparent);
        }

        /* Async Job pending state */
        .placed-tile.placed-pending {
          opacity: 0.75;
          border-style: dashed;
          border-color: color-mix(in srgb, var(--primary) 50%, var(--border));
          background: color-mix(in srgb, var(--primary) 4%, var(--card));
        }
        .pending-spinner {
          display: inline-block;
          width: 10px; height: 10px;
          border: 2px solid color-mix(in srgb, var(--primary) 25%, transparent);
          border-top-color: var(--primary);
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
        }
        .pending-label {
          font-family: var(--font-mono);
          font-size: 0.68rem;
          letter-spacing: 0.04em;
          color: var(--primary);
          font-style: italic;
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }

        .t-fmt-job {
          border-color: color-mix(in srgb, var(--primary) 40%, var(--border));
          color: var(--primary);
        }

        /* Audit pending row */
        .audit-row.pending { border-left: 3px solid var(--primary); }
        .audit-row.pending .audit-result {
          background: color-mix(in srgb, var(--primary) 14%, var(--card));
          color: var(--primary);
          display: inline-flex;
          align-items: center;
          gap: 0.35rem;
          justify-content: center;
        }
        .audit-spinner {
          display: inline-block;
          width: 8px; height: 8px;
          border: 1.5px solid color-mix(in srgb, var(--primary) 25%, transparent);
          border-top-color: var(--primary);
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
        }

        .t-head {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .t-head-child { margin-bottom: 0.25rem; }
        .t-icon {
          display: grid; place-items: center;
          width: 20px; height: 20px;
          color: var(--muted-foreground);
          font-size: 0.92rem;
        }
        .target.accept .t-icon { color: var(--chart-1, #22c1a8); }
        .target.deny .t-icon { color: var(--destructive, #ef4444); }
        .t-title {
          flex: 1;
          font-weight: 600;
          font-size: 0.94rem;
        }
        .t-fmt {
          font-family: var(--font-mono);
          font-size: 0.66rem;
          letter-spacing: 0.1em;
          padding: 0.12rem 0.4rem;
          border: 1px solid var(--border);
          border-radius: 3px;
          color: var(--muted-foreground);
        }
        .t-fmt-62 {
          border-color: color-mix(in srgb, var(--primary) 40%, var(--border));
          color: var(--primary);
        }
        .t-subtitle {
          font-size: 0.78rem;
          color: var(--muted-foreground);
        }
        .t-subtitle code {
          font-size: 0.72rem;
          color: var(--foreground);
          background: color-mix(in srgb, var(--muted-foreground) 10%, transparent);
          padding: 0.05rem 0.25rem;
          border-radius: 3px;
        }
        .t-body { margin-top: auto; }
        .t-slot {
          border-radius: 6px;
          background: color-mix(in srgb, var(--muted-foreground) 4%, transparent);
          display: grid;
          place-items: center;
          color: var(--muted-foreground);
          font-size: 0.74rem;
          font-style: italic;
        }
        .t-slot-fitted { min-height: 56px; }
        .t-slot-isolated { min-height: 92px; }
        .t-slot.has.t-slot-fitted,
        .t-slot.has.t-slot-isolated {
          place-items: stretch;
          display: block;
          padding: 0;
          background: transparent;
        }
        .t-slot-atom {
          height: 34px;
          padding: 0 0.6rem;
          display: flex;
          align-items: center;
          gap: 0.4rem;
          justify-content: flex-start;
        }
        .t-atom-prompt {
          color: var(--chart-3, #3b82f6);
          font-family: var(--font-mono);
          font-weight: 600;
        }
        .t-placeholder-inline { font-style: italic; }

        /* Folder-specific */
        .target-folder { border-color: color-mix(in srgb, var(--primary) 35%, var(--border)); }
        .folder-glyph {
          color: var(--primary) !important;
          font-size: 0.72rem;
        }
        .target-folder.open .folder-glyph { color: var(--primary); }

        .dwell-ring {
          position: absolute;
          top: 0.55rem; right: 0.55rem;
          width: 32px; height: 32px;
          display: grid;
          place-items: center;
        }
        .dwell-ring svg {
          width: 32px; height: 32px;
          transform: rotate(-90deg);
        }
        .ring-bg {
          fill: none;
          stroke: color-mix(in srgb, var(--primary) 15%, var(--card));
          stroke-width: 3;
        }
        .ring-fill {
          fill: none;
          stroke: var(--primary);
          stroke-width: 3;
          stroke-linecap: round;
          stroke-dasharray: calc(2 * 3.14159 * 15);
          stroke-dashoffset: calc(2 * 3.14159 * 15 * (1 - var(--dwell-pct, 0%) / 100));
          transition: stroke-dashoffset 0.03s linear;
        }
        .dwell-label {
          position: absolute;
          top: 100%;
          right: 0;
          margin-top: 0.25rem;
          font-family: var(--font-mono);
          font-size: 0.62rem;
          color: var(--primary);
          letter-spacing: 0.04em;
          white-space: nowrap;
        }

        .folder-kids {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 0.55rem;
          margin-top: 0.35rem;
          padding-top: 0.65rem;
          border-top: 1px dashed color-mix(in srgb, var(--primary) 30%, var(--border));
        }
        .target-child {
          min-height: 70px;
          padding: 0.6rem 0.75rem;
        }

        /* ─── Audit trail ─── */
        .audit {
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: 1rem 1.1rem;
          box-shadow: var(--shadow-sm);
        }
        .audit-list {
          list-style: none;
          padding: 0;
          margin: 0;
          display: grid;
          gap: 0.3rem;
        }
        .audit-row {
          display: grid;
          grid-template-columns: 72px 78px minmax(140px, 1fr) 22px minmax(140px, 1fr) 80px 1fr;
          align-items: center;
          gap: 0.55rem;
          padding: 0.5rem 0.6rem;
          background: var(--background);
          border: 1px solid var(--border);
          border-radius: 6px;
          font-family: var(--font-mono);
          font-size: 0.76rem;
        }
        .audit-row.ok { border-left: 3px solid var(--chart-1, #22c1a8); }
        .audit-row.no { border-left: 3px solid var(--destructive, #ef4444); }
        .audit-time { color: var(--muted-foreground); font-size: 0.7rem; }
        .audit-aff {
          padding: 0.1rem 0.4rem;
          border-radius: 3px;
          font-size: 0.66rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          text-align: center;
        }
        .aff-drag { background: color-mix(in srgb, var(--chart-1, #22c1a8) 14%, var(--card)); color: var(--chart-1, #22c1a8); }
        .aff-palette { background: color-mix(in srgb, var(--chart-3, #3b82f6) 14%, var(--card)); color: var(--chart-3, #3b82f6); }
        .audit-payload em {
          font-style: normal;
          color: var(--muted-foreground);
          font-size: 0.7rem;
          margin-left: 0.3rem;
        }
        .audit-arrow { color: var(--muted-foreground); text-align: center; }
        .audit-target { font-weight: 500; }
        .audit-result {
          font-size: 0.66rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          padding: 0.1rem 0.4rem;
          border-radius: 3px;
          text-align: center;
        }
        .audit-row.ok .audit-result { background: color-mix(in srgb, var(--chart-1, #22c1a8) 16%, var(--card)); color: var(--chart-1, #22c1a8); }
        .audit-row.no .audit-result { background: color-mix(in srgb, var(--destructive, #ef4444) 14%, var(--card)); color: var(--destructive, #ef4444); }
        .audit-msg {
          font-size: 0.7rem;
          color: var(--muted-foreground);
          font-style: italic;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .audit-empty {
          padding: 0.8rem;
          text-align: center;
          font-size: 0.8rem;
          color: var(--muted-foreground);
          font-style: italic;
          border: 1px dashed var(--border);
          border-radius: 6px;
        }
        .audit-empty code {
          font-style: normal;
          color: var(--chart-3, #3b82f6);
        }

        /* ─── Ghost ─── */
        .ghost {
          position: fixed;
          top: 0; left: 0;
          pointer-events: none;
          z-index: 40;
          transition: opacity 0.08s ease;
          filter: drop-shadow(0 4px 10px rgba(0,0,0,0.15));
        }
        .ghost-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.35rem;
          padding: 0.28rem 0.6rem;
          background: var(--card);
          border: 1.5px solid var(--chart-1, #22c1a8);
          border-radius: 999px;
          font-size: 0.86rem;
          font-weight: 500;
          opacity: 0.96;
        }
        .ghost-fitted {
          display: grid;
          grid-template-columns: 36px 1fr;
          gap: 0.55rem;
          align-items: center;
          padding: 0.55rem 0.7rem;
          background: var(--card);
          border: 1.5px solid var(--chart-1, #22c1a8);
          border-radius: 8px;
          min-width: 180px;
          max-width: 220px;
          opacity: 0.96;
        }
        .gfit-avatar {
          width: 36px; height: 36px;
          border-radius: 7px;
          display: grid; place-items: center;
          color: white;
          font-family: var(--font-mono);
          font-weight: 600;
          font-size: 0.76rem;
        }
        .gfit-name { font-weight: 600; font-size: 0.86rem; line-height: 1.2; }
        .gfit-type {
          font-family: var(--font-mono);
          font-size: 0.66rem;
          color: var(--muted-foreground);
        }
        .ghost-isolated {
          display: flex;
          flex-direction: column;
          gap: 0.45rem;
          padding: 0.7rem 0.85rem;
          background: var(--card);
          border: 1.5px solid var(--chart-1, #22c1a8);
          border-radius: 10px;
          min-width: 220px;
          max-width: 260px;
          opacity: 0.97;
        }
        .ghost-isolated .iso-hero {
          display: flex;
          gap: 0.6rem;
          align-items: center;
          padding-bottom: 0.4rem;
          border-bottom: 1px solid var(--border);
        }
        .ghost-isolated .iso-avatar {
          width: 40px; height: 40px;
          border-radius: 8px;
          display: grid; place-items: center;
          color: white;
          font-family: var(--font-mono);
          font-weight: 600;
          font-size: 0.82rem;
        }
        .ghost-isolated .iso-name { font-weight: 600; font-size: 0.92rem; }
        .ghost-isolated .iso-type {
          font-family: var(--font-mono);
          font-size: 0.68rem;
          color: var(--muted-foreground);
        }
        .ghost-isolated .iso-body {
          font-size: 0.8rem;
          color: var(--muted-foreground);
        }

        .ghost-deny {
          border-color: var(--destructive, #ef4444) !important;
          filter: drop-shadow(0 4px 10px rgba(239,68,68,0.25));
          opacity: 0.75 !important;
        }

        /* ─── Deny tooltip ─── */
        .deny-tooltip {
          position: fixed;
          top: 0; left: 0;
          pointer-events: none;
          z-index: 41;
          margin-top: 78px;
          margin-left: -12px;
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.75rem;
          background: #0f172a;
          color: #f8fafc;
          border-radius: 6px;
          font-size: 0.78rem;
          max-width: 260px;
          box-shadow: 0 4px 14px rgba(0,0,0,0.25);
        }
        .deny-tooltip strong { color: #fca5a5; font-weight: 600; }
        .dt-x {
          display: inline-grid; place-items: center;
          width: 18px; height: 18px;
          background: var(--destructive, #ef4444);
          color: white;
          border-radius: 50%;
          font-size: 0.68rem;
          font-weight: 700;
          flex-shrink: 0;
        }

        /* ─── Palette ─── */
        .palette-overlay {
          position: fixed;
          inset: 0;
          background: rgba(15, 23, 42, 0.45);
          display: grid;
          place-items: center;
          z-index: 50;
          backdrop-filter: blur(2px);
        }
        .palette {
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: 12px;
          width: min(520px, 92vw);
          max-height: 78vh;
          overflow: hidden;
          display: flex;
          flex-direction: column;
          box-shadow: 0 24px 60px rgba(0,0,0,0.3);
        }
        .pal-head {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.7rem 0.95rem;
          border-bottom: 1px solid var(--border);
          background: color-mix(in srgb, var(--chart-3, #3b82f6) 6%, var(--card));
          font-family: var(--font-mono);
          font-size: 0.86rem;
        }
        .pal-caret { color: var(--chart-3, #3b82f6); font-weight: 700; }
        .pal-query { flex: 1; }
        .pal-query strong { color: var(--foreground); }
        .pal-query em {
          font-family: var(--font-sans);
          font-style: italic;
          color: var(--muted-foreground);
          font-size: 0.78rem;
          margin-left: 0.35rem;
        }
        .pal-close {
          background: transparent;
          border: 1px solid var(--border);
          border-radius: 4px;
          padding: 0.15rem 0.45rem;
          font-family: var(--font-mono);
          font-size: 0.7rem;
          color: var(--muted-foreground);
          cursor: pointer;
        }
        .pal-list {
          display: flex;
          flex-direction: column;
          overflow-y: auto;
        }
        .pal-row {
          display: grid;
          grid-template-columns: 22px 1fr 60px 100px;
          gap: 0.65rem;
          align-items: center;
          padding: 0.65rem 0.95rem;
          background: transparent;
          border: 0;
          border-bottom: 1px solid color-mix(in srgb, var(--border) 80%, transparent);
          text-align: left;
          cursor: pointer;
          font-family: var(--font-sans);
          transition: background 0.1s;
        }
        .pal-row:last-child { border-bottom: 0; }
        .pal-row.pal-ok:hover { background: color-mix(in srgb, var(--chart-1, #22c1a8) 10%, var(--card)); }
        .pal-row.pal-no { opacity: 0.55; cursor: not-allowed; }
        .pal-tick {
          font-weight: 700;
          text-align: center;
          font-size: 0.9rem;
        }
        .pal-ok .pal-tick { color: var(--chart-1, #22c1a8); }
        .pal-no .pal-tick { color: var(--destructive, #ef4444); }
        .pal-tgt { display: flex; flex-direction: column; }
        .pal-tname { font-weight: 600; font-size: 0.9rem; }
        .pal-tsub {
          font-family: var(--font-mono);
          font-size: 0.7rem;
          color: var(--muted-foreground);
        }
        .pal-fmt {
          font-family: var(--font-mono);
          font-size: 0.7rem;
          padding: 0.12rem 0.4rem;
          border: 1px solid var(--border);
          border-radius: 3px;
          color: var(--muted-foreground);
          text-align: center;
        }
        .pal-verdict {
          font-family: var(--font-mono);
          font-size: 0.68rem;
          letter-spacing: 0.04em;
          text-align: right;
        }
        .pal-verdict-ok { color: var(--chart-1, #22c1a8); }
        .pal-verdict-no { color: var(--destructive, #ef4444); }
        .pal-foot {
          padding: 0.6rem 0.95rem;
          border-top: 1px solid var(--border);
          background: color-mix(in srgb, var(--muted-foreground) 4%, transparent);
          font-size: 0.76rem;
          color: var(--muted-foreground);
        }
        .pal-foot code {
          font-family: var(--font-mono);
          color: var(--primary);
          font-size: 0.78rem;
        }

        /* ─── Responsive ─── */
        @media (max-width: 900px) {
          .proto-grid {
            grid-template-columns: 1fr;
          }
          .target-grid {
            grid-template-columns: 1fr;
          }
          .span-2 { grid-column: auto; }
          .audit-row {
            grid-template-columns: 60px 68px 1fr;
            grid-auto-rows: auto;
            gap: 0.35rem;
          }
        }
      </style>
    </template>
  };
}
// touched for re-index
