import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import MarkdownField from '@cardstack/base/markdown';
import ImageDef from '@cardstack/base/image-file-def';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { concat, fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { dropTask, restartableTask, timeout } from 'ember-concurrency';
import { add, and, cssVar, eq } from '@cardstack/boxel-ui/helpers';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import BookOpenIcon from '@cardstack/boxel-icons/book-open';
import PlayIcon from '@cardstack/boxel-icons/play';
import ChevronLeftIcon from '@cardstack/boxel-icons/chevron-left';
import ChevronRightIcon from '@cardstack/boxel-icons/chevron-right';
import MusicIcon from '@cardstack/boxel-icons/music';
import SquareIcon from '@cardstack/boxel-icons/square';
import Volume2Icon from '@cardstack/boxel-icons/volume-2';
import DeleteIcon from '@cardstack/boxel-icons/delete';
import XIcon from '@cardstack/boxel-icons/x';
import RotateCcwIcon from '@cardstack/boxel-icons/rotate-ccw';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import HandIcon from '@cardstack/boxel-icons/hand';
import LockIcon from '@cardstack/boxel-icons/lock';
import CircleHelpIcon from '@cardstack/boxel-icons/circle-help';
import MessageCircleIcon from '@cardstack/boxel-icons/message-circle';
import ArrowRightIcon from '@cardstack/boxel-icons/arrow-right';
import ArrowLeftIcon from '@cardstack/boxel-icons/arrow-left';
import CheckIcon from '@cardstack/boxel-icons/check';
import StarIcon from '@cardstack/boxel-icons/star';
import PartyPopperIcon from '@cardstack/boxel-icons/party-popper';
import DownloadIcon from '@cardstack/boxel-icons/download';
import {
  AacSymbol,
  SymbolTile,
  symbolImage,
  symbolSpeech,
  wordClassColor,
} from './aac-symbol';
import {
  AacChoiceBoard,
  ChoiceBoardPlayer,
  LEVELS,
  LevelField,
} from './aac-choice-board';
import { normalizeWord, speak, speakLine, stopSpeaking } from './speech';
import {
  playSingAlong,
  TUNES,
  TUNE_OPTIONS,
  type SingAlongHandle,
} from './melody';
import enumField from '@cardstack/base/enum';
import { downloadWorksheet, type PuzzleWord } from './worksheet-pdf';
import { realmURL } from '@cardstack/runtime-common';

const TuneField = enumField(StringField, { options: TUNE_OPTIONS });

// Month values sort in calendar order; labels are what people see.
export const MONTHS = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
].map((label, i) => ({ value: String(i + 1).padStart(2, '0'), label }));

// Add a new category here and it shows up in the editor and the library.
export const CATEGORIES = [
  { value: 'nursery', label: 'Nursery rhymes' },
  { value: 'holidays', label: 'Holidays & celebrations' },
  { value: 'seasons', label: 'Seasons & weather' },
  { value: 'food', label: 'Food & cooking' },
  { value: 'animals', label: 'Animals' },
  { value: 'feelings', label: 'Feelings & friends' },
  { value: 'routines', label: 'Daily routines' },
  { value: 'nature', label: 'Nature & outdoors' },
  { value: 'concepts', label: 'Colors, shapes & numbers' },
  { value: 'movement', label: 'Music & movement' },
  { value: 'community', label: 'Community helpers' },
  { value: 'other', label: 'Other' },
];

const MonthField = enumField(StringField, { options: MONTHS });
const CategoryField = enumField(StringField, { options: CATEGORIES });

const PUZZLE_DIFFICULTY: Record<string, 'easy' | 'medium' | 'hard'> = {
  aac: 'easy',
  regular: 'medium',
  advanced: 'hard',
};

interface Word {
  index: number;
  text: string;
  // Starts a new row on the page (a line break in the activity's line).
  breakBefore?: boolean;
  symbol?: AacSymbol;
  // Key words get a picture on the page and a slot in "Your turn".
  key: boolean;
}

interface Line {
  key: number;
  text: string;
  words: Word[];
  keyWords: Word[];
}

// Most pictures a page shows when the line does not pick its own.
const AUTO_KEY_WORDS = 2;
// Which kinds of words make the best picture when choosing automatically.
const KEY_PRIORITY = ['thing', 'describe', 'action', 'person', 'social'];

// Turns the activity's lines into words, pairing each word with the
// vocabulary symbol whose label, spoken text, or alternate spelling matches.
// Words wrapped in *stars* are the line's key pictures; a line with no stars
// gets up to two picked automatically (things first, each picture once).
function buildLines(activity?: AacActivity): Line[] {
  const lookup = new Map<string, AacSymbol>();
  for (const symbol of activity?.vocabulary ?? []) {
    if (!symbol) continue;
    const keys = [symbol.label, symbol.speakAs, ...(symbol.alsoMatches ?? [])];
    for (const key of keys) {
      const k = normalizeWord(key ?? '');
      if (k && !lookup.has(k)) lookup.set(k, symbol);
    }
  }
  const find = (token: string) => {
    const k = normalizeWord(token);
    return (
      lookup.get(k) ??
      (k.endsWith('es') ? lookup.get(k.slice(0, -2)) : undefined) ??
      (k.endsWith('s') ? lookup.get(k.slice(0, -1)) : undefined)
    );
  };
  let index = 0;
  return (activity?.lines ?? []).filter(Boolean).map((raw, key) => {
    const words: Word[] = raw.split('\n').flatMap((row, r) =>
      row
        .split(/\s+/)
        .filter(Boolean)
        .map((token, t) => {
          const text = token.replace(/\*/g, '');
          return {
            index: index++,
            text,
            symbol: find(text),
            key: token.includes('*'),
            breakBefore: r > 0 && t === 0,
          };
        }),
    );
    for (const w of words) {
      if (!w.symbol) w.key = false;
    }
    if (!raw.includes('*')) {
      const seen = new Set<AacSymbol>();
      const rank = (w: Word) => {
        const r = KEY_PRIORITY.indexOf(w.symbol?.wordClass ?? '');
        return r < 0 ? KEY_PRIORITY.length : r;
      };
      words
        .filter((w) => w.symbol && !seen.has(w.symbol) && seen.add(w.symbol))
        .sort((a, b) => rank(a) - rank(b) || a.index - b.index)
        .slice(0, AUTO_KEY_WORDS)
        .forEach((w) => (w.key = true));
    }
    return {
      key,
      text: words.map((w) => w.text).join(' '),
      words,
      keyWords: words.filter((w) => w.key),
    };
  });
}

// Stable "mixed up" order for the picture bank, so it does not reshuffle on
// every render but also does not mirror the order of the song.
function mixedUp(symbols: AacSymbol[]) {
  const score = (s: AacSymbol) =>
    [...(s.label ?? '')].reduce((h, c) => (h * 31 + c.charCodeAt(0)) % 997, 7);
  return [...symbols].sort((a, b) => score(a) - score(b));
}

// The word as a word card shows it: no commas or full stops.
function cardText(word: string) {
  return word.replace(/[^\p{L}\p{N}']/gu, '');
}

type DropHandler = (symbol: AacSymbol, slotIndex: number) => void;

// Pointer-based drag so it works with a finger on iPads as well as a mouse.
// A tap without movement falls through to the tile's normal click.
const dragToSlot = modifier(
  (element: HTMLElement, [symbol, onDrop]: [AacSymbol, DropHandler]) => {
    let pointerId: number | null = null;
    let startX = 0;
    let startY = 0;
    let offsetX = 0;
    let offsetY = 0;
    let width = 0;
    let height = 0;
    let ghost: HTMLElement | null = null;
    let over: HTMLElement | null = null;

    // Magnetic: once the picture leaves the shelf, it belongs to the
    // closest empty spot that wants it — wherever the child lets go. Only a
    // picture no spot on this page wants goes to the nearest spot (which
    // just wiggles). Letting go over the shelf puts the picture back.
    const slotNear = (x: number, y: number) => {
      const under = document.elementFromPoint(x, y) as HTMLElement | null;
      if (under?.closest('.shelf')) return null;
      const cx = x - offsetX + width / 2;
      const cy = y - offsetY + height / 2;
      let best: HTMLElement | null = null;
      let bestScore = Infinity;
      for (const slot of document.querySelectorAll<HTMLElement>(
        '[data-slot-index]',
      )) {
        const r = slot.getBoundingClientRect();
        const distance = Math.hypot(
          cx - (r.left + r.width / 2),
          cy - (r.top + r.height / 2),
        );
        const wantsThis = slot.dataset.slotSymbol === symbol?.id;
        const score = distance - (wantsThis ? 100000 : 0);
        if (score < bestScore) {
          bestScore = score;
          best = slot;
        }
      }
      return best;
    };

    const setOver = (el: HTMLElement | null) => {
      if (over === el) return;
      over?.removeAttribute('data-drag-over');
      over = el;
      over?.setAttribute('data-drag-over', 'true');
    };

    const down = (e: PointerEvent) => {
      if (e.button !== 0) return;
      pointerId = e.pointerId;
      startX = e.clientX;
      startY = e.clientY;
      const rect = element.getBoundingClientRect();
      offsetX = e.clientX - rect.left;
      offsetY = e.clientY - rect.top;
      width = rect.width;
      height = rect.height;
      element.setPointerCapture?.(e.pointerId);
    };

    const move = (e: PointerEvent) => {
      if (pointerId !== e.pointerId) return;
      if (!ghost) {
        if (Math.hypot(e.clientX - startX, e.clientY - startY) < 8) return;
        const rect = element.getBoundingClientRect();
        ghost = element.cloneNode(true) as HTMLElement;
        ghost.setAttribute('aria-hidden', 'true');
        Object.assign(ghost.style, {
          position: 'fixed',
          left: '0',
          top: '0',
          margin: '0',
          width: `${rect.width}px`,
          height: `${rect.height}px`,
          pointerEvents: 'none',
          zIndex: '10000',
          boxShadow: '0 16px 32px rgb(0 0 0 / 25%)',
          transformOrigin: '50% 50%',
        });
        document.body.appendChild(ghost);
        element.setAttribute('data-dragging', 'true');
      }
      ghost.style.transform = `translate(${e.clientX - offsetX}px, ${
        e.clientY - offsetY
      }px) rotate(-4deg) scale(1.06)`;
      setOver(slotNear(e.clientX, e.clientY));
    };

    const finish = (e: PointerEvent, cancelled: boolean) => {
      if (pointerId !== e.pointerId) return;
      pointerId = null;
      if (!ghost) return;
      const flying = ghost;
      ghost = null;
      const target = cancelled ? null : slotNear(e.clientX, e.clientY);
      setOver(null);
      const fits = target?.dataset.slotSymbol === symbol?.id;
      if (target && fits) {
        // Fly the picture into its spot so the snap is visible.
        const r = target.getBoundingClientRect();
        const scale = Math.min(r.width / width, r.height / height);
        flying.style.transition = 'transform 200ms ease-out';
        flying.style.transform = `translate(${r.left + (r.width - width * scale) / 2}px, ${
          r.top + (r.height - height * scale) / 2
        }px) scale(${scale})`;
        flying.style.transformOrigin = '0 0';
        setTimeout(() => flying.remove(), 210);
      } else {
        flying.remove();
      }
      element.removeAttribute('data-dragging');
      // The browser still fires a click after a drag; swallow it so the
      // drag does not also count as a tap.
      const swallow = (ev: Event) => {
        ev.stopImmediatePropagation();
        ev.preventDefault();
      };
      element.addEventListener('click', swallow, { capture: true, once: true });
      setTimeout(
        () => element.removeEventListener('click', swallow, { capture: true }),
        0,
      );
      if (target) {
        const slotIndex = Number(target.dataset.slotIndex);
        if (fits) setTimeout(() => onDrop(symbol, slotIndex), 200);
        else onDrop(symbol, slotIndex);
      }
    };
    const up = (e: PointerEvent) => finish(e, false);
    const cancel = (e: PointerEvent) => finish(e, true);

    element.addEventListener('pointerdown', down);
    element.addEventListener('pointermove', move);
    element.addEventListener('pointerup', up);
    element.addEventListener('pointercancel', cancel);
    return () => {
      ghost?.remove();
      element.removeEventListener('pointerdown', down);
      element.removeEventListener('pointermove', move);
      element.removeEventListener('pointerup', up);
      element.removeEventListener('pointercancel', cancel);
    };
  },
);

// Swipe left/right to turn pages (finger or mouse). Small movements are
// left alone so taps on words still work.
const swipePages = modifier(
  (element: HTMLElement, [onNext, onPrev]: [() => void, () => void]) => {
    let startX: number | null = null;
    let startY = 0;
    const down = (e: PointerEvent) => {
      startX = e.clientX;
      startY = e.clientY;
    };
    const up = (e: PointerEvent) => {
      if (startX === null) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      startX = null;
      if (Math.abs(dx) < 70 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
      if (dx < 0) onNext();
      else onPrev();
    };
    element.addEventListener('pointerdown', down);
    element.addEventListener('pointerup', up);
    return () => {
      element.removeEventListener('pointerdown', down);
      element.removeEventListener('pointerup', up);
    };
  },
);

// Stops the song and the voice whenever the activity can't be seen: the
// tab or app is hidden, the iPad locks, the page is left, or the card is
// covered / scrolled fully out of view.
const stopWhenHidden = modifier(
  (element: HTMLElement, [stop]: [() => void]) => {
    const onVisibility = () => {
      if (document.hidden) stop();
    };
    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('pagehide', stop);
    window.addEventListener('blur', onVisibility);
    let observer: IntersectionObserver | undefined;
    if (typeof IntersectionObserver !== 'undefined') {
      observer = new IntersectionObserver((entries) => {
        for (const entry of entries) if (!entry.isIntersecting) stop();
      });
      observer.observe(element);
    }
    // Backup check once a second that doesn't depend on the browser drawing
    // (hidden views can pause the observer): off-screen, detached or
    // zero-size means not visible.
    const poll = setInterval(() => {
      if (document.hidden) return stop();
      if (!element.isConnected) return stop();
      const r = element.getBoundingClientRect();
      const offscreen =
        r.width === 0 ||
        r.height === 0 ||
        r.bottom <= 0 ||
        r.right <= 0 ||
        r.top >= window.innerHeight ||
        r.left >= window.innerWidth;
      if (offscreen) stop();
    }, 1000);
    return () => {
      clearInterval(poll);
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('pagehide', stop);
      window.removeEventListener('blur', onVisibility);
      observer?.disconnect();
      stop();
    };
  },
);

// Press and hold (about 0.7s) to open — so a child can't open the grown-up
// panel by tapping. Keyboard users can open it with Enter or Space.
// Shrinks a Listen page's words and pictures (CSS zoom) just enough to fit
// the page, so a long verse never needs scrolling. Short pages stay at full
// size. Re-fits when the page is resized or its line changes.
const fitPage = modifier((element: HTMLElement, [_key]: [unknown]) => {
  const line = element.querySelector<HTMLElement>('.page-line');
  if (!line) return;
  const fits = () => {
    const style = getComputedStyle(element);
    const room =
      element.clientHeight -
      parseFloat(style.paddingTop) -
      parseFloat(style.paddingBottom);
    return line.scrollHeight * (parseFloat(line.style.zoom) || 1) <= room + 1;
  };
  const fit = () => {
    line.style.zoom = '1';
    if (fits()) return;
    let lo = 0.35;
    let hi = 1;
    for (let i = 0; i < 8; i++) {
      const mid = (lo + hi) / 2;
      line.style.zoom = String(mid);
      if (fits()) lo = mid;
      else hi = mid;
    }
    line.style.zoom = String(lo);
  };
  // Zooming the line never changes the page's own size, so refitting from
  // the observer cannot loop.
  const observer = new ResizeObserver(fit);
  observer.observe(element);
  fit();
  return () => observer.disconnect();
});

const holdToOpen = modifier(
  (element: HTMLElement, [onOpen, onTap]: [() => void, () => void]) => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const start = (e: PointerEvent) => {
      if (e.button !== 0) return;
      element.setAttribute('data-holding', 'true');
      timer = setTimeout(() => {
        timer = undefined;
        element.removeAttribute('data-holding');
        onOpen();
      }, 700);
    };
    const end = () => {
      element.removeAttribute('data-holding');
      if (timer) {
        clearTimeout(timer);
        timer = undefined;
        onTap();
      }
    };
    const leave = () => {
      element.removeAttribute('data-holding');
      if (timer) {
        clearTimeout(timer);
        timer = undefined;
      }
    };
    const key = (e: KeyboardEvent) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        onOpen();
      }
    };
    element.addEventListener('pointerdown', start);
    element.addEventListener('pointerup', end);
    element.addEventListener('pointerleave', leave);
    element.addEventListener('pointercancel', leave);
    element.addEventListener('keydown', key);
    return () => {
      if (timer) clearTimeout(timer);
      element.removeEventListener('pointerdown', start);
      element.removeEventListener('pointerup', end);
      element.removeEventListener('pointerleave', leave);
      element.removeEventListener('pointercancel', leave);
      element.removeEventListener('keydown', key);
    };
  },
);

// Talk board order: Fitzgerald groups left to right, then A–Z inside each
// group, so a word's spot only depends on the word, not on when it was added.
const BOARD_ORDER = [
  'person',
  'action',
  'describe',
  'thing',
  'social',
  'question',
  'stop',
  'little',
];

function boardSort(symbols: AacSymbol[]) {
  const rank = (s: AacSymbol) => {
    const r = BOARD_ORDER.indexOf(s.wordClass ?? 'little');
    return r < 0 ? BOARD_ORDER.length : r;
  };
  return [...symbols].sort(
    (a, b) => rank(a) - rank(b) || (a.label ?? '').localeCompare(b.label ?? ''),
  );
}

const TURN_COPY: Record<string, string> = {
  aac: 'Your turn! Put the pictures back in the book.',
  regular: 'Your turn! Find the missing words.',
  advanced: 'Your turn! Fill in the blanks.',
};

class ActivityIsolated extends Component<typeof AacActivity> {
  @tracked step = 'listen';
  @tracked chosenLevel: string | undefined;
  @tracked page = 0;
  @tracked buildPage = 0;
  // 'none' until the first page turn, so a book opens without flipping.
  @tracked flipDirection: 'next' | 'prev' | 'none' = 'none';
  @tracked activeIndex = -1;
  @tracked heardOnce = false;
  @tracked showHints = false;
  @tracked placed: Record<number, boolean> = {};
  @tracked selected: AacSymbol | undefined;
  @tracked shakeIndex = -1;
  @tracked strip: AacSymbol[] = [];
  // Grown-up panel
  @tracked panelOpen = false;
  @tracked holdHint = false;
  @tracked pendingLevel: string | undefined;
  @tracked confirmReset = false;
  @tracked keyOnOwnPage = true;
  // The cut-and-glue picture page is on by default for AAC learners; the
  // grown-up's checkbox overrides it for every level.
  @tracked cutStripChoice: boolean | undefined;
  @tracked addPuzzles = true;
  // Questions
  @tracked qIndex = 0;
  @tracked questionsDone = false;
  // Talk
  @tracked talkTab: 'core' | 'song' = 'core';

  get lines() {
    return buildLines(this.args.model as AacActivity);
  }

  get pageCount() {
    return this.lines.length;
  }

  // ── Levels ───────────────────────────────────────────────────────────────
  // AAC: big pictures, drag pictures. Regular: small picture cues, drag word
  // cards. Advanced: words only, with extra word cards to choose between.
  get level() {
    return this.chosenLevel ?? this.args.model?.defaultLevel ?? 'aac';
  }

  get levelName() {
    return LEVELS.find((l) => l.value === this.level)?.label ?? 'AAC';
  }

  get showPictures() {
    return this.level !== 'advanced';
  }

  get wordMode() {
    return this.level !== 'aac';
  }

  get turnCopy() {
    return TURN_COPY[this.level] ?? TURN_COPY.aac;
  }

  get bankLabel() {
    if (this.level === 'advanced') {
      return 'Drag each word to its blank — or tap it, then tap the blank. Some words don’t belong here!';
    }
    if (this.level === 'regular') {
      return 'Drag the word to its blank — or tap it, then tap the blank.';
    }
    return 'Drag a picture up to its word — or tap it, then tap its spot.';
  }

  get hasProgress() {
    return Object.keys(this.placed).length > 0;
  }

  get donePages() {
    return this.lines.filter((_, i) => this.isLineDone(i)).length;
  }

  get doneLabel() {
    return `${this.donePages} of ${this.pageCount} pages done`;
  }

  // One-item lists keyed by page, so each page turn mounts a fresh page and
  // its flip animation plays.
  get listenPages() {
    const line = this.lines[this.page];
    return line ? [line] : [];
  }

  get buildPages() {
    const line = this.lines[this.buildPage];
    return line ? [line] : [];
  }

  get isFirstPage() {
    return this.page <= 0;
  }

  get isLastPage() {
    return this.page >= this.pageCount - 1;
  }

  get isFirstBuildPage() {
    return this.buildPage <= 0;
  }

  get isLastBuildPage() {
    return this.buildPage >= this.pageCount - 1;
  }

  get pageLabel() {
    return `Page ${this.page + 1} of ${this.pageCount}`;
  }

  get buildPageLabel() {
    return `Page ${this.buildPage + 1} of ${this.pageCount}`;
  }

  get keyWords() {
    return this.lines.flatMap((l) => l.keyWords);
  }

  // Only this page's pictures, so the learner chooses from one to three.
  get pageBank() {
    const line = this.lines[this.buildPage];
    const unique = new Set<AacSymbol>();
    for (const w of line?.keyWords ?? []) unique.add(w.symbol!);
    return mixedUp([...unique]).filter((s) =>
      line?.keyWords.some((w) => w.symbol === s && !this.placed[w.index]),
    );
  }

  // Word cards for this page, plus one (Regular) or two (Advanced) words
  // from other pages that do not belong here.
  get wordBank() {
    const line = this.lines[this.buildPage];
    if (!line) return [];
    const items = new Map<AacSymbol, string>();
    for (const w of line.keyWords) {
      if (!this.placed[w.index] && !items.has(w.symbol!)) {
        items.set(w.symbol!, cardText(w.text));
      }
    }
    if (!items.size) return [];
    const onPage = new Set(line.keyWords.map((w) => w.symbol));
    const others = mixedUp(
      [...new Set(this.keyWords.map((w) => w.symbol!))].filter(
        (s) => !onPage.has(s),
      ),
    );
    const extra = this.level === 'advanced' ? 2 : 1;
    for (let i = 0; i < Math.min(extra, others.length); i++) {
      const s = others[(this.buildPage * extra + i) % others.length];
      items.set(s, s.label ?? '');
    }
    return mixedUp([...items.keys()]).map((symbol) => ({
      symbol,
      text: items.get(symbol)!,
    }));
  }

  // Advanced blanks are all the same width so the length doesn't give the
  // answer away; Regular keeps word-length blanks as a hint.
  slotWidth = (word: Word) =>
    this.level === 'advanced' ? 7 : cardText(word.text).length;

  get buildPageDone() {
    return this.isLineDone(this.buildPage);
  }

  get allPlaced() {
    return (
      this.keyWords.length > 0 &&
      this.keyWords.every((w) => this.placed[w.index])
    );
  }

  get showYourTurn() {
    return !this.isPlaying && (this.heardOnce || this.isLastPage);
  }

  get vocabulary() {
    return (this.args.model?.vocabulary ?? []).filter(Boolean) as AacSymbol[];
  }

  // Questions written for this level, plus any not tagged with a level.
  get choiceBoards() {
    return (
      (this.args.model?.choiceBoards ?? []).filter(Boolean) as AacChoiceBoard[]
    ).filter((b) => !b.level || b.level === this.level);
  }

  get isReading() {
    return this.readAloud.isRunning;
  }

  get isPlaying() {
    return this.isReading || this.isSinging;
  }

  isLineDone = (lineIndex: number) => {
    const words = this.lines[lineIndex]?.keyWords ?? [];
    return words.length > 0 && words.every((w) => this.placed[w.index]);
  };

  dotLabel = (i: number) => `Go to page ${i + 1}`;

  dotState = (i: number, current: number, forBuild: boolean) => {
    const classes = ['dot'];
    if (i === current) classes.push('current');
    if (forBuild && this.isLineDone(i)) classes.push('done');
    return classes.join(' ');
  };

  isDoneDot = (i: number) => this.isLineDone(i);

  // ── Steps ────────────────────────────────────────────────────────────────
  setStep = (value: string) => {
    this.stopReading();
    this.step = value;
  };

  goListen = () => this.setStep('listen');
  goPlay = () => this.setStep('build');
  goAsk = () => this.setStep('choose');
  goTalk = () => this.setStep('talk');

  // ── Grown-up panel ───────────────────────────────────────────────────────
  openPanel = () => {
    this.stopReading();
    this.holdHint = false;
    this.panelOpen = true;
  };

  closePanel = () => {
    this.panelOpen = false;
    this.pendingLevel = undefined;
    this.confirmReset = false;
  };

  showHoldHint = () => {
    this.holdHint = true;
    setTimeout(() => (this.holdHint = false), 2200);
  };

  // Changing level resets Your turn, so ask first if there's progress.
  pickLevel = (value: string) => {
    if (value === this.level) return;
    if (this.hasProgress) {
      this.pendingLevel = value;
    } else {
      this.applyLevel(value);
    }
  };

  applyLevel = (value: string) => {
    this.stopReading();
    this.chosenLevel = value;
    this.pendingLevel = undefined;
    this.placed = {};
    this.selected = undefined;
    this.buildPage = 0;
    this.qIndex = 0;
    this.questionsDone = false;
  };

  confirmLevel = () => {
    if (this.pendingLevel) this.applyLevel(this.pendingLevel);
  };

  cancelLevel = () => {
    this.pendingLevel = undefined;
  };

  get pendingLevelName() {
    return LEVELS.find((l) => l.value === this.pendingLevel)?.label ?? '';
  }

  toggleHints = () => {
    this.showHints = !this.showHints;
  };

  askReset = () => {
    this.confirmReset = true;
  };

  cancelReset = () => {
    this.confirmReset = false;
  };

  resetBuild = () => {
    this.placed = {};
    this.selected = undefined;
    this.confirmReset = false;
    this.turnBuildTo(0);
  };

  toggleKeyPage = () => {
    this.keyOnOwnPage = !this.keyOnOwnPage;
  };

  get cutStrip() {
    return this.cutStripChoice ?? this.level === 'aac';
  }

  toggleCutStrip = () => {
    this.cutStripChoice = !this.cutStrip;
  };

  togglePuzzles = () => {
    this.addPuzzles = !this.addPuzzles;
  };

  // ── Flip book ────────────────────────────────────────────────────────────
  turnTo = (target: number) => {
    const next = Math.max(0, Math.min(this.pageCount - 1, target));
    if (next === this.page) return;
    this.flipDirection = next > this.page ? 'next' : 'prev';
    this.page = next;
  };

  nextPage = () => {
    this.stopReading();
    this.turnTo(this.page + 1);
  };

  prevPage = () => {
    this.stopReading();
    this.turnTo(this.page - 1);
  };

  goToPage = (i: number) => {
    this.stopReading();
    this.turnTo(i);
  };

  turnBuildTo = (target: number) => {
    const next = Math.max(0, Math.min(this.pageCount - 1, target));
    if (next === this.buildPage) return;
    this.flipDirection = next > this.buildPage ? 'next' : 'prev';
    this.buildPage = next;
    this.selected = undefined;
  };

  nextBuildPage = () => this.turnBuildTo(this.buildPage + 1);
  prevBuildPage = () => this.turnBuildTo(this.buildPage - 1);
  goToBuildPage = (i: number) => this.turnBuildTo(i);

  onBookKey = (e: Event) => {
    const key = (e as KeyboardEvent).key;
    if (key === 'ArrowRight') this.nextPage();
    if (key === 'ArrowLeft') this.prevPage();
  };

  // ── Listen ──────────────────────────────────────────────────────────────
  // Reads from this page to the end, turning pages as it goes; each line is
  // spoken in one breath with the current word lit up.
  readAloud = restartableTask(async () => {
    const first = this.page;
    try {
      for (let i = first; i < this.pageCount; i++) {
        this.turnTo(i);
        const line = this.lines[i];
        await timeout(i === first ? 250 : 450);
        await speakLine(
          line.words.map((w) => w.text),
          (j) => (this.activeIndex = line.words[j]?.index ?? -1),
        );
        this.activeIndex = -1;
        await timeout(500);
      }
      this.heardOnce = true;
    } finally {
      this.activeIndex = -1;
    }
  });

  startReading = () => {
    this.stopSinging();
    this.readAloud.perform();
  };

  // Sing along: the tune plays from page one, each word lights up on its
  // beat and the book turns its own pages, so everyone can sing together.
  @tracked isSinging = false;
  private singAlong: SingAlongHandle | undefined;

  // On the published site, a way back to the library at the site's home.
  get siteHome() {
    if (this.args.context?.mode !== 'host') return undefined;
    return this.args.model?.[realmURL]?.href;
  }

  // A spoken rhyme plays a beat instead of a tune.
  get isChant() {
    return Boolean(TUNES[this.args.model?.tune ?? '']?.chant);
  }

  startSinging = () => {
    this.readAloud.cancelAll();
    stopSpeaking();
    this.singAlong?.stop();
    const lines = this.lines;
    this.turnTo(0);
    const handle = playSingAlong(
      lines.map((l) => l.words.map((w) => w.text)),
      (i, j) => {
        this.turnTo(i);
        this.activeIndex = lines[i]?.words[j]?.index ?? -1;
      },
      { tune: this.args.model?.tune ?? undefined },
    );
    this.singAlong = handle;
    this.isSinging = true;
    handle.done.then(() => {
      if (this.singAlong !== handle) return;
      this.singAlong = undefined;
      this.isSinging = false;
      this.activeIndex = -1;
      this.heardOnce = true;
    });
  };

  stopSinging = () => {
    this.singAlong?.stop();
  };

  stopReading = () => {
    this.readAloud.cancelAll();
    stopSpeaking();
    this.stopSinging();
  };

  willDestroy() {
    super.willDestroy();
    this.singAlong?.stop();
    stopSpeaking();
  }

  sayWord = (word: Word) => {
    this.stopReading();
    this.activeIndex = word.index;
    speak(word.text).then(() => {
      if (this.activeIndex === word.index) this.activeIndex = -1;
    });
  };

  sayLine = (line: Line) => {
    this.stopReading();
    speakLine(
      line.words.map((w) => w.text),
      (j) => (this.activeIndex = line.words[j]?.index ?? -1),
    ).then(() => (this.activeIndex = -1));
  };

  // ── Your turn (one page at a time, only that page's pictures) ────────────
  goBuild = () => {
    this.setStep('build');
    this.turnBuildTo(0);
  };

  isPlaced = (index: number) => Boolean(this.placed[index]);

  tryPlace = (symbol: AacSymbol, slotIndex: number) => {
    const word = this.keyWords.find((w) => w.index === slotIndex);
    if (!word || this.placed[slotIndex]) return;
    if (word.symbol === symbol) {
      this.placed = { ...this.placed, [slotIndex]: true };
      this.selected = undefined;
      if (this.allPlaced) {
        speak('You finished the book! Great job!');
      } else if (this.buildPageDone) {
        // Page finished: hear the whole line as the reward.
        const line = this.lines[this.buildPage];
        speakLine(
          line.words.map((w) => w.text),
          (j) => (this.activeIndex = line.words[j]?.index ?? -1),
        ).then(() => (this.activeIndex = -1));
      } else {
        speak(word.text);
      }
    } else {
      // Errorless: nothing is marked wrong, the slot just wiggles.
      this.shakeIndex = slotIndex;
      setTimeout(() => {
        if (this.shakeIndex === slotIndex) this.shakeIndex = -1;
      }, 500);
    }
  };

  // Tap-a-picture, then tap-a-slot: the same task for learners who cannot drag.
  selectFromBank = (symbol: AacSymbol) => {
    this.selected = this.selected === symbol ? undefined : symbol;
    speak(symbolSpeech(symbol));
  };

  tapSlot = (word: Word) => {
    if (this.selected) {
      this.tryPlace(this.selected, word.index);
    } else {
      speak(word.text);
    }
  };

  bankState = (symbol: AacSymbol) =>
    this.selected === symbol ? 'selected' : undefined;

  // After finishing a page: turn to the next page, or on the last page jump
  // back to the first page that still has empty spots.
  continueBuild = () => {
    if (!this.isLastBuildPage) {
      this.nextBuildPage();
      return;
    }
    const open = this.lines.findIndex((_, i) => !this.isLineDone(i));
    if (open >= 0) this.turnBuildTo(open);
  };

  get nextIsReady() {
    return this.buildPageDone && !this.allPlaced;
  }

  singAgain = () => {
    this.step = 'listen';
    this.turnTo(0);
    this.startSinging();
  };

  // ── Questions, one at a time ─────────────────────────────────────────────
  get questionCount() {
    return this.choiceBoards.length;
  }

  get currentQuestion() {
    const board = this.choiceBoards[this.qIndex];
    return board ? [board] : [];
  }

  get questionLabel() {
    return `Question ${this.qIndex + 1} of ${this.questionCount}`;
  }

  get questionPct() {
    const n = this.questionCount || 1;
    return `${Math.round(((this.qIndex + 1) / n) * 100)}%`;
  }

  get autoReadQuestions() {
    return this.level !== 'advanced';
  }

  get isFirstQuestion() {
    return this.qIndex <= 0;
  }

  get isLastQuestion() {
    return this.qIndex >= this.questionCount - 1;
  }

  nextQuestion = () => {
    stopSpeaking();
    if (this.isLastQuestion) {
      this.questionsDone = true;
      speak('All done! Great answering!');
    } else {
      this.qIndex = this.qIndex + 1;
    }
  };

  prevQuestion = () => {
    stopSpeaking();
    if (this.qIndex > 0) this.qIndex = this.qIndex - 1;
  };

  askAgain = () => {
    this.qIndex = 0;
    this.questionsDone = false;
  };

  // ── Worksheet PDF ────────────────────────────────────────────────────────
  @tracked pdfMessage = '';

  downloadPdf = dropTask(async () => {
    this.pdfMessage = '';
    const model = this.args.model as AacActivity;
    const questions = this.choiceBoards.map((b) => {
      const choices = ((b.choices ?? []).filter(Boolean) as AacSymbol[]).map(
        (s) => ({ label: s.label ?? '', image: symbolImage(s) }),
      );
      return {
        question: b.question ?? '',
        frame: b.sentenceFrame || undefined,
        choices,
        textChoices: (b.textChoices ?? []).filter(Boolean),
        open: Boolean(b.openEnded),
        answer: b.correctChoice?.label || b.correctText || undefined,
      };
    });
    const withPictures = this.showPictures;
    const lines = this.lines.map((l) => ({
      text: l.text,
      words: l.words.map((w) => ({
        text: w.text,
        image: withPictures && w.key ? symbolImage(w.symbol) : undefined,
        breakBefore: w.breakBefore,
      })),
    }));
    const puzzles = this.addPuzzles
      ? {
          words: this.puzzleWords,
          difficulty: PUZZLE_DIFFICULTY[this.level] ?? 'easy',
          crossword: this.level !== 'aac',
        }
      : undefined;
    const usesPictures =
      withPictures ||
      questions.some((q) => q.choices.length) ||
      (puzzles && puzzles.difficulty !== 'hard');
    try {
      await downloadWorksheet({
        title: model.cardTitle ?? 'Questions',
        subtitle: model.occasion ?? undefined,
        levelLabel: this.levelName,
        lines,
        questions,
        answerKeyOwnPage: this.keyOnOwnPage,
        cutStrip: this.cutStrip,
        puzzles,
        credit: usesPictures
          ? 'Pictograms: Sergio Palao · ARASAAC (arasaac.org), CC BY-NC-SA 4.0'
          : undefined,
      });
      this.pdfMessage = 'Your PDF is downloading.';
    } catch (e) {
      this.pdfMessage =
        e instanceof Error ? e.message : 'Sorry, the PDF could not be made.';
    }
  });

  // One word per song picture, spelled as the song spells it ("MUFFINS"),
  // with its line blanked out as the crossword clue.
  get puzzleWords(): PuzzleWord[] {
    const seen = new Set<AacSymbol>();
    const words: PuzzleWord[] = [];
    this.lines.forEach((line, n) => {
      for (const w of line.keyWords) {
        if (!w.symbol || seen.has(w.symbol)) continue;
        seen.add(w.symbol);
        const word = w.text.replace(/[^A-Za-z]/g, '').toUpperCase();
        if (word.length < 3 || word.length > 12) continue;
        const blanked = line.words
          .map((x) =>
            x.symbol === w.symbol
              ? x.text.replace(/[A-Za-z']+/, '______')
              : x.text,
          )
          .join(' ');
        // A line that is only this word ("Thanksgiving, Thanksgiving")
        // would leave nothing but blanks, so point to the line instead.
        const clue = /[A-Za-z]/.test(blanked)
          ? blanked
          : `The word that fills line ${n + 1} of the song`;
        words.push({ word, image: symbolImage(w.symbol), clue });
      }
    });
    return words;
  }

  startDownload = () => {
    this.downloadPdf.perform().then(() => {
      // Let the status read for a moment, then clear it from the top bar.
      setTimeout(() => {
        if (!this.downloadPdf.isRunning) this.pdfMessage = '';
      }, 5000);
    });
  };

  // ── Talk: core words and song words, each in fixed, grouped spots ────────
  get songSymbols() {
    const inSong = new Set<AacSymbol>();
    for (const l of this.lines) {
      for (const w of l.words) if (w.symbol) inSong.add(w.symbol);
    }
    return inSong;
  }

  get talkSymbols() {
    const inSong = this.songSymbols;
    const wantSong = this.talkTab === 'song';
    return boardSort(this.vocabulary.filter((s) => inSong.has(s) === wantSong));
  }

  get talkColumns() {
    return Math.max(4, Math.ceil(this.talkSymbols.length / 3));
  }

  showCore = () => (this.talkTab = 'core');
  showSong = () => (this.talkTab = 'song');

  get stripText() {
    return this.strip.map((s) => symbolSpeech(s)).join(' ');
  }

  addToStrip = (symbol: AacSymbol) => {
    this.strip = [...this.strip, symbol];
    speak(symbolSpeech(symbol));
  };

  speakStrip = () => {
    if (this.strip.length) speak(this.stripText);
  };

  deleteLast = () => {
    this.strip = this.strip.slice(0, -1);
  };

  clearStrip = () => {
    this.strip = [];
  };

  <template>
    <article
      class='activity level-{{this.level}} step-{{this.step}}'
      style={{cssVar talk-cols=this.talkColumns q-pct=this.questionPct}}
      {{stopWhenHidden this.stopReading}}
    >
      <header class='play-bar'>
        <div class='title-block'>
          {{#if this.siteHome}}
            <a class='site-home' href={{this.siteHome}}>
              <ArrowLeftIcon width='14' height='14' aria-hidden='true' />
              All songs
            </a>
          {{/if}}
          {{#if @model.occasion}}
            <span class='kicker'>{{@model.occasion}}</span>
          {{/if}}
          <h1 class='title'><@fields.cardTitle /></h1>
        </div>
        <nav class='steps' aria-label='Steps'>
          <button
            type='button'
            class='step {{if (eq this.step "listen") "is-current"}}'
            aria-current={{if (eq this.step 'listen') 'step'}}
            {{on 'click' this.goListen}}
          >
            <BookOpenIcon width='18' height='18' aria-hidden='true' />
            <span>Listen</span>
          </button>
          <button
            type='button'
            class='step {{if (eq this.step "build") "is-current"}}'
            aria-current={{if (eq this.step 'build') 'step'}}
            {{on 'click' this.goPlay}}
          >
            <HandIcon width='18' height='18' aria-hidden='true' />
            <span>Play</span>
          </button>
          <button
            type='button'
            class='step {{if (eq this.step "choose") "is-current"}}'
            aria-current={{if (eq this.step 'choose') 'step'}}
            {{on 'click' this.goAsk}}
          >
            <CircleHelpIcon width='18' height='18' aria-hidden='true' />
            <span>Ask</span>
          </button>
          <button
            type='button'
            class='step {{if (eq this.step "talk") "is-current"}}'
            aria-current={{if (eq this.step 'talk') 'step'}}
            {{on 'click' this.goTalk}}
          >
            <MessageCircleIcon width='18' height='18' aria-hidden='true' />
            <span>Talk</span>
          </button>
        </nav>
        <div class='bar-tools'>
          <div class='bar-level' role='group' aria-label='Level'>
            <span class='bar-level-label' aria-hidden='true'>Level</span>
            <div class='level-pills'>
              {{#each LEVELS as |levelOption|}}
                <button
                  type='button'
                  class='level-pill
                    {{if (eq levelOption.value this.level) "is-current"}}'
                  aria-pressed={{if
                    (eq levelOption.value this.level)
                    'true'
                    'false'
                  }}
                  {{on 'click' (fn this.pickLevel levelOption.value)}}
                >{{levelOption.label}}</button>
              {{/each}}
            </div>
          </div>
          <div class='bar-pdf-wrap'>
            <button
              type='button'
              class='bar-pdf'
              aria-label='Download the {{this.levelName}} worksheet (PDF)'
              disabled={{this.downloadPdf.isRunning}}
              {{on 'click' this.startDownload}}
            >
              <DownloadIcon width='18' height='18' aria-hidden='true' />
              <span class='bar-pdf-label'>{{if
                  this.downloadPdf.isRunning
                  'Making…'
                  'PDF'
                }}</span>
            </button>
            {{#if this.pdfMessage}}
              {{#unless this.panelOpen}}
                <span
                  class='bar-pdf-status'
                  role='status'
                >{{this.pdfMessage}}</span>
              {{/unless}}
            {{/if}}
          </div>
          <button
            type='button'
            class='grown-ups'
            aria-label='Grown-ups: press and hold to open'
            title='Grown-ups: press and hold'
            {{holdToOpen this.openPanel this.showHoldHint}}
          >
            <LockIcon width='18' height='18' aria-hidden='true' />
          </button>
          {{#if this.holdHint}}
            <span class='hold-hint' role='status'>Grown-ups: press and hold</span>
          {{/if}}
        </div>
        {{#if this.pendingLevel}}
          {{#unless this.panelOpen}}
            <div
              class='confirm bar-confirm'
              role='alertdialog'
              aria-label='Change level'
            >
              <strong>Switch to {{this.pendingLevelName}}?</strong>
              <span>{{this.doneLabel}}. Switching starts Play over.</span>
              <div class='confirm-actions'>
                <button
                  type='button'
                  class='mid-btn'
                  {{on 'click' this.cancelLevel}}
                >Keep {{this.levelName}}</button>
                <button
                  type='button'
                  class='mid-btn danger'
                  {{on 'click' this.confirmLevel}}
                >Switch level</button>
              </div>
            </div>
          {{/unless}}
        {{/if}}
      </header>

      <div class='stage'>
        {{#if (eq this.step 'listen')}}
          <section class='step-body listen'>
            <div class='controls'>
              {{#if this.isPlaying}}
                <button
                  type='button'
                  class='big-btn stop'
                  {{on 'click' this.stopReading}}
                >
                  <SquareIcon width='24' height='24' aria-hidden='true' />
                  Stop
                </button>
              {{else}}
                <button
                  type='button'
                  class='big-btn sing'
                  {{on 'click' this.startSinging}}
                >
                  <MusicIcon width='26' height='26' aria-hidden='true' />
                  {{if this.isChant 'Chant along' 'Sing along'}}
                </button>
                <button
                  type='button'
                  class='mid-btn'
                  {{on 'click' this.startReading}}
                >
                  <PlayIcon width='20' height='20' aria-hidden='true' />
                  Read to me
                </button>
              {{/if}}
              <span class='page-count'>{{this.pageLabel}}</span>
            </div>

            {{#if this.pageCount}}
              {{! template-lint-disable no-invalid-interactive }}
              <div
                class='book {{if this.isPlaying "playing"}}'
                tabindex='0'
                role='group'
                aria-roledescription='flip book'
                aria-label={{this.pageLabel}}
                {{on 'keydown' this.onBookKey}}
                {{swipePages this.nextPage this.prevPage}}
              >
                {{#each this.listenPages key='key' as |line|}}
                  <div
                    class='page fit flip-{{this.flipDirection}}'
                    {{fitPage (concat line.key this.level)}}
                  >
                    <div class='page-line'>
                      {{#each line.words as |word|}}
                        {{#if word.breakBefore}}
                          <span class='row-break' aria-hidden='true'></span>
                        {{/if}}
                        <button
                          type='button'
                          class='word-col
                            {{if word.key "has-pic"}}
                            {{if (eq this.activeIndex word.index) "active"}}'
                          style={{cssVar
                            tile-color=(wordClassColor word.symbol.wordClass)
                          }}
                          {{on 'click' (fn this.sayWord word)}}
                        >
                          <span class='bounce' aria-hidden='true'></span>
                          <span class='pic-cell'>
                            {{#if (and word.key this.showPictures)}}
                              <span class='page-pic'>
                                <img
                                  src={{symbolImage word.symbol}}
                                  alt=''
                                  draggable='false'
                                />
                              </span>
                            {{/if}}
                          </span>
                          <span class='word-text'>{{word.text}}</span>
                          <span class='key-bar' aria-hidden='true'></span>
                        </button>
                      {{/each}}
                    </div>
                    <button
                      type='button'
                      class='line-speaker'
                      aria-label='Read this page'
                      {{on 'click' (fn this.sayLine line)}}
                    >
                      <Volume2Icon width='24' height='24' aria-hidden='true' />
                    </button>
                  </div>
                {{/each}}
                {{#unless this.isFirstPage}}
                  <button
                    type='button'
                    class='edge prev'
                    aria-label='Previous page'
                    {{on 'click' this.prevPage}}
                  >
                    <ChevronLeftIcon
                      width='34'
                      height='34'
                      aria-hidden='true'
                    />
                  </button>
                {{/unless}}
                {{#unless this.isLastPage}}
                  <button
                    type='button'
                    class='edge next'
                    aria-label='Next page'
                    {{on 'click' this.nextPage}}
                  >
                    <ChevronRightIcon
                      width='34'
                      height='34'
                      aria-hidden='true'
                    />
                  </button>
                {{/unless}}
              </div>

              <nav class='dots' aria-label='Pages'>
                {{#each this.lines as |line i|}}
                  <button
                    type='button'
                    class={{this.dotState i this.page false}}
                    aria-label={{this.dotLabel i}}
                    aria-current={{if (eq i this.page) 'page'}}
                    {{on 'click' (fn this.goToPage i)}}
                  ></button>
                {{/each}}
              </nav>
            {{else}}
              <p class='empty'>Add the lines of the song or story to start.</p>
            {{/if}}

            {{#if this.showYourTurn}}
              <div class='banner' role='status'>
                <SparklesIcon width='28' height='28' aria-hidden='true' />
                <p>{{this.turnCopy}}</p>
                <button
                  type='button'
                  class='mid-btn go'
                  {{on 'click' this.goBuild}}
                >
                  Let's go
                  <ArrowRightIcon width='20' height='20' aria-hidden='true' />
                </button>
              </div>
            {{/if}}
          </section>
        {{/if}}

        {{#if (eq this.step 'build')}}
          {{#if this.allPlaced}}
            <section class='step-body celebrate'>
              <span class='confetti c1' aria-hidden='true'></span>
              <span class='confetti c2' aria-hidden='true'></span>
              <span class='confetti c3' aria-hidden='true'></span>
              <span class='confetti c4' aria-hidden='true'></span>
              <span class='confetti c5' aria-hidden='true'></span>
              <span class='confetti c6' aria-hidden='true'></span>
              <div class='finish-card' role='status'>
                <div class='finish-badge'>
                  <PartyPopperIcon width='64' height='64' aria-hidden='true' />
                </div>
                <h2>You finished the book!</h2>
                <p class='finish-sub'>{{this.pageCount}}
                  of
                  {{this.pageCount}}
                  pages — every one is done.</p>
                <div class='stars' aria-hidden='true'>
                  {{#each this.lines as |_line|}}
                    <span class='star'><StarIcon
                        width='20'
                        height='20'
                        fill='currentColor'
                      /></span>
                  {{/each}}
                </div>
                <button
                  type='button'
                  class='big-btn primary'
                  {{on 'click' this.goAsk}}
                >
                  <CircleHelpIcon width='28' height='28' aria-hidden='true' />
                  Go to questions
                </button>
                <div class='finish-more'>
                  <button
                    type='button'
                    class='mid-btn'
                    disabled={{this.downloadPdf.isRunning}}
                    {{on 'click' this.startDownload}}
                  >
                    <DownloadIcon width='20' height='20' aria-hidden='true' />
                    {{if
                      this.downloadPdf.isRunning
                      'Making PDF…'
                      'Download worksheet (PDF)'
                    }}
                  </button>
                  <button
                    type='button'
                    class='mid-btn'
                    {{on 'click' this.singAgain}}
                  >
                    <MusicIcon width='20' height='20' aria-hidden='true' />
                    Sing it again
                  </button>
                </div>
                {{#if this.pdfMessage}}
                  <p class='pdf-message' role='status'>{{this.pdfMessage}}</p>
                {{/if}}
              </div>
            </section>
          {{else}}
            <section class='step-body build'>
              <div class='status-row'>
                <span class='page-count'>{{this.buildPageLabel}}</span>
                <span class='mini-dots' aria-label={{this.doneLabel}}>
                  {{#each this.lines as |line i|}}
                    <button
                      type='button'
                      class={{this.dotState i this.buildPage true}}
                      aria-label={{this.dotLabel i}}
                      {{on 'click' (fn this.goToBuildPage i)}}
                    >
                      {{#if (this.isDoneDot i)}}
                        <CheckIcon width='12' height='12' aria-hidden='true' />
                      {{/if}}
                    </button>
                  {{/each}}
                </span>
                {{#if this.nextIsReady}}
                  <span class='great' role='status'>Great job! Turn the page
                    <ArrowRightIcon
                      width='18'
                      height='18'
                      aria-hidden='true'
                    /></span>
                {{else}}
                  <span class='done-count'>{{this.doneLabel}}</span>
                {{/if}}
              </div>

              <div class='book compact'>
                {{#each this.buildPages key='key' as |line|}}
                  <div class='page flip-{{this.flipDirection}}'>
                    <div class='page-line'>
                      {{#each line.words as |word|}}
                        {{#if word.breakBefore}}
                          <span class='row-break' aria-hidden='true'></span>
                        {{/if}}
                        <div
                          class='word-col
                            {{if word.key "has-pic"}}
                            {{if (eq this.activeIndex word.index) "active"}}'
                          style={{cssVar
                            tile-color=(wordClassColor word.symbol.wordClass)
                          }}
                        >
                          <span class='pic-cell'>
                            {{#if word.key}}
                              {{#if this.wordMode}}
                                {{#if this.showPictures}}
                                  <span class='page-pic'>
                                    <img
                                      src={{symbolImage word.symbol}}
                                      alt=''
                                      draggable='false'
                                    />
                                  </span>
                                {{/if}}
                              {{else if (this.isPlaced word.index)}}
                                <span class='page-pic just-placed'>
                                  <img
                                    src={{symbolImage word.symbol}}
                                    alt=''
                                    draggable='false'
                                  />
                                  <span class='placed-check' aria-hidden='true'>
                                    <CheckIcon width='16' height='16' />
                                  </span>
                                </span>
                              {{else}}
                                <button
                                  type='button'
                                  class='slot
                                    {{if this.selected "ready"}}
                                    {{if
                                      (eq this.shakeIndex word.index)
                                      "shake"
                                    }}'
                                  data-slot-index={{word.index}}
                                  data-slot-symbol={{word.symbol.id}}
                                  aria-label='Empty picture spot for {{word.text}}'
                                  {{on 'click' (fn this.tapSlot word)}}
                                >
                                  {{#if this.showHints}}
                                    <img
                                      class='ghost-hint'
                                      src={{symbolImage word.symbol}}
                                      alt=''
                                      draggable='false'
                                    />
                                  {{/if}}
                                </button>
                              {{/if}}
                            {{/if}}
                          </span>
                          {{#if (and word.key this.wordMode)}}
                            {{#if (this.isPlaced word.index)}}
                              <span
                                class='word-text placed-word just-placed'
                              >{{word.text}}</span>
                            {{else}}
                              <button
                                type='button'
                                class='word-text word-slot
                                  {{if this.selected "ready"}}
                                  {{if
                                    (eq this.shakeIndex word.index)
                                    "shake"
                                  }}'
                                style={{cssVar slot-ch=(this.slotWidth word)}}
                                data-slot-index={{word.index}}
                                data-slot-symbol={{word.symbol.id}}
                                aria-label='Empty word spot'
                                {{on 'click' (fn this.tapSlot word)}}
                              >
                                {{#if this.showHints}}
                                  <span class='ghost-word'>{{word.text}}</span>
                                {{/if}}
                              </button>
                            {{/if}}
                          {{else}}
                            <span class='word-text'>{{word.text}}</span>
                          {{/if}}
                          <span class='key-bar' aria-hidden='true'></span>
                        </div>
                      {{/each}}
                    </div>
                  </div>
                {{/each}}
                {{#unless this.isFirstBuildPage}}
                  <button
                    type='button'
                    class='edge prev'
                    aria-label='Previous page'
                    {{on 'click' this.prevBuildPage}}
                  >
                    <ChevronLeftIcon
                      width='32'
                      height='32'
                      aria-hidden='true'
                    />
                  </button>
                {{/unless}}
                {{#if this.nextIsReady}}
                  <button
                    type='button'
                    class='edge next ready-next'
                    aria-label='Next page'
                    {{on 'click' this.continueBuild}}
                  >
                    <ChevronRightIcon
                      width='34'
                      height='34'
                      aria-hidden='true'
                    />
                  </button>
                {{else}}
                  {{#unless this.isLastBuildPage}}
                    <button
                      type='button'
                      class='edge next quiet'
                      aria-label='Skip to next page'
                      {{on 'click' this.nextBuildPage}}
                    >
                      <ChevronRightIcon
                        width='30'
                        height='30'
                        aria-hidden='true'
                      />
                    </button>
                  {{/unless}}
                {{/if}}
              </div>

              <div class='shelf' role='group' aria-label='Cards to place'>
                <p class='shelf-label'>{{this.bankLabel}}</p>
                <div class='shelf-tiles'>
                  {{#if this.buildPageDone}}
                    <p class='shelf-done'>
                      <CheckIcon width='24' height='24' aria-hidden='true' />
                      This page is done!
                    </p>
                  {{else if this.wordMode}}
                    {{#each this.wordBank as |item|}}
                      <button
                        type='button'
                        class='word-card
                          {{if (eq this.selected item.symbol) "selected"}}'
                        aria-pressed={{if
                          (eq this.selected item.symbol)
                          'true'
                        }}
                        {{on 'click' (fn this.selectFromBank item.symbol)}}
                        {{dragToSlot item.symbol this.tryPlace}}
                      >{{item.text}}</button>
                    {{/each}}
                  {{else}}
                    {{#each this.pageBank as |symbol|}}
                      <SymbolTile
                        @symbol={{symbol}}
                        @size='m'
                        @state={{this.bankState symbol}}
                        @onActivate={{this.selectFromBank}}
                        {{dragToSlot symbol this.tryPlace}}
                      />
                    {{/each}}
                  {{/if}}
                </div>
              </div>
            </section>
          {{/if}}
        {{/if}}

        {{#if (eq this.step 'choose')}}
          <section class='step-body ask'>
            {{#if this.questionsDone}}
              <div class='finish-card small' role='status'>
                <div class='finish-badge'>
                  <PartyPopperIcon width='52' height='52' aria-hidden='true' />
                </div>
                <h2>All done!</h2>
                <p class='finish-sub'>You answered every question.</p>
                <div class='finish-more'>
                  <button
                    type='button'
                    class='big-btn primary'
                    {{on 'click' this.goTalk}}
                  >
                    <MessageCircleIcon
                      width='26'
                      height='26'
                      aria-hidden='true'
                    />
                    Talk about it
                  </button>
                </div>
                <div class='finish-more'>
                  <button
                    type='button'
                    class='mid-btn'
                    disabled={{this.downloadPdf.isRunning}}
                    {{on 'click' this.startDownload}}
                  >
                    <DownloadIcon width='20' height='20' aria-hidden='true' />
                    {{if
                      this.downloadPdf.isRunning
                      'Making PDF…'
                      'Download worksheet (PDF)'
                    }}
                  </button>
                  <button
                    type='button'
                    class='mid-btn'
                    {{on 'click' this.askAgain}}
                  >
                    <RotateCcwIcon width='20' height='20' aria-hidden='true' />
                    Ask again
                  </button>
                </div>
                {{#if this.pdfMessage}}
                  <p class='pdf-message' role='status'>{{this.pdfMessage}}</p>
                {{/if}}
              </div>
            {{else if this.questionCount}}
              <div class='q-progress'>
                <span class='page-count'>{{this.questionLabel}}</span>
                <span
                  class='q-bar'
                  role='progressbar'
                  aria-valuemin='1'
                  aria-valuemax={{this.questionCount}}
                  aria-valuenow={{add this.qIndex 1}}
                  aria-label='Questions'
                ><span class='q-fill'></span></span>
              </div>
              {{#each this.currentQuestion key='id' as |board|}}
                <div class='q-card'>
                  <ChoiceBoardPlayer
                    @board={{board}}
                    @autoRead={{this.autoReadQuestions}}
                    @hideLevel={{true}}
                  />
                </div>
              {{/each}}
              <div class='q-nav'>
                {{#unless this.isFirstQuestion}}
                  <button
                    type='button'
                    class='mid-btn'
                    {{on 'click' this.prevQuestion}}
                  >
                    <ArrowLeftIcon width='20' height='20' aria-hidden='true' />
                    Back
                  </button>
                {{/unless}}
                <button
                  type='button'
                  class='big-btn primary next-q'
                  {{on 'click' this.nextQuestion}}
                >
                  {{if this.isLastQuestion 'Finish' 'Next question'}}
                  <ArrowRightIcon width='24' height='24' aria-hidden='true' />
                </button>
              </div>
            {{else}}
              <p class='empty'>No questions for the
                {{this.levelName}}
                level yet.</p>
            {{/if}}
          </section>
        {{/if}}

        {{#if (eq this.step 'talk')}}
          <section class='step-body talk'>
            <div class='message-bar'>
              <button
                type='button'
                class='message'
                aria-label={{if
                  this.strip.length
                  this.stripText
                  'My message is empty'
                }}
                {{on 'click' this.speakStrip}}
              >
                {{#each this.strip as |symbol|}}
                  <span
                    class='msg-tile'
                    style={{cssVar
                      tile-color=(wordClassColor symbol.wordClass)
                    }}
                  >
                    <img src={{symbolImage symbol}} alt='' />
                    <span>{{symbol.label}}</span>
                  </span>
                {{else}}
                  <span class='msg-empty'>Tap pictures to make a message</span>
                {{/each}}
              </button>
              <button
                type='button'
                class='speak-btn'
                {{on 'click' this.speakStrip}}
              >
                <Volume2Icon width='32' height='32' aria-hidden='true' />
                Speak
              </button>
              <button
                type='button'
                class='tool-btn'
                {{on 'click' this.deleteLast}}
              >
                <DeleteIcon width='26' height='26' aria-hidden='true' />
                Delete
              </button>
              <button
                type='button'
                class='tool-btn'
                {{on 'click' this.clearStrip}}
              >
                <XIcon width='26' height='26' aria-hidden='true' />
                Clear
              </button>
            </div>
            <div class='talk-tabs' role='tablist' aria-label='Word sets'>
              <button
                type='button'
                role='tab'
                aria-selected={{if (eq this.talkTab 'core') 'true' 'false'}}
                class='tab {{if (eq this.talkTab "core") "is-current"}}'
                {{on 'click' this.showCore}}
              >Core words</button>
              <button
                type='button'
                role='tab'
                aria-selected={{if (eq this.talkTab 'song') 'true' 'false'}}
                class='tab {{if (eq this.talkTab "song") "is-current"}}'
                {{on 'click' this.showSong}}
              >Song words</button>
            </div>
            <div class='talk-grid' role='tabpanel'>
              {{#each this.talkSymbols as |symbol|}}
                <SymbolTile
                  @symbol={{symbol}}
                  @fill={{true}}
                  @onActivate={{this.addToStrip}}
                />
              {{else}}
                <p class='empty'>No words here yet.</p>
              {{/each}}
            </div>
          </section>
        {{/if}}
      </div>

      <nav class='steps steps-bottom' aria-label='Steps (bottom bar)'>
        <button
          type='button'
          class='step {{if (eq this.step "listen") "is-current"}}'
          aria-current={{if (eq this.step 'listen') 'step'}}
          {{on 'click' this.goListen}}
        >
          <BookOpenIcon width='22' height='22' aria-hidden='true' />
          <span>Listen</span>
        </button>
        <button
          type='button'
          class='step {{if (eq this.step "build") "is-current"}}'
          aria-current={{if (eq this.step 'build') 'step'}}
          {{on 'click' this.goPlay}}
        >
          <HandIcon width='22' height='22' aria-hidden='true' />
          <span>Play</span>
        </button>
        <button
          type='button'
          class='step {{if (eq this.step "choose") "is-current"}}'
          aria-current={{if (eq this.step 'choose') 'step'}}
          {{on 'click' this.goAsk}}
        >
          <CircleHelpIcon width='22' height='22' aria-hidden='true' />
          <span>Ask</span>
        </button>
        <button
          type='button'
          class='step {{if (eq this.step "talk") "is-current"}}'
          aria-current={{if (eq this.step 'talk') 'step'}}
          {{on 'click' this.goTalk}}
        >
          <MessageCircleIcon width='22' height='22' aria-hidden='true' />
          <span>Talk</span>
        </button>
      </nav>

      {{#if this.panelOpen}}
        <div class='scrim' aria-hidden='true'></div>
        <aside class='panel-sheet' role='dialog' aria-label='Grown-up settings'>
          <div class='sheet-head'>
            <LockIcon width='22' height='22' aria-hidden='true' />
            <h2>Grown-ups</h2>
            <button
              type='button'
              class='close'
              aria-label='Close'
              {{on 'click' this.closePanel}}
            >
              <XIcon width='22' height='22' aria-hidden='true' />
            </button>
          </div>

          <section class='sheet-section'>
            <h3>Level</h3>
            <SegmentedControl
              @options={{LEVELS}}
              @value={{this.level}}
              @onValueChange={{this.pickLevel}}
              @label='Level'
              class='level-switch'
            />
            {{#if this.pendingLevel}}
              <div class='confirm' role='alertdialog' aria-label='Change level'>
                <strong>Switch to {{this.pendingLevelName}}?</strong>
                <span>{{this.doneLabel}}. Switching starts Play over.</span>
                <div class='confirm-actions'>
                  <button
                    type='button'
                    class='mid-btn'
                    {{on 'click' this.cancelLevel}}
                  >Keep {{this.levelName}}</button>
                  <button
                    type='button'
                    class='mid-btn danger'
                    {{on 'click' this.confirmLevel}}
                  >Switch level</button>
                </div>
              </div>
            {{/if}}
          </section>

          <section class='sheet-section'>
            <h3>Play</h3>
            <label class='check'>
              <input
                type='checkbox'
                checked={{this.showHints}}
                {{on 'change' this.toggleHints}}
              />
              Show hint outlines in empty spots
            </label>
            {{#if this.confirmReset}}
              <div class='confirm' role='alertdialog' aria-label='Start over'>
                <strong>Start the whole book over?</strong>
                <span>{{this.doneLabel}}. This clears every placed card.</span>
                <div class='confirm-actions'>
                  <button
                    type='button'
                    class='mid-btn'
                    {{on 'click' this.cancelReset}}
                  >Keep going</button>
                  <button
                    type='button'
                    class='mid-btn danger'
                    {{on 'click' this.resetBuild}}
                  >Start over</button>
                </div>
              </div>
            {{else}}
              <button
                type='button'
                class='mid-btn'
                {{on 'click' this.askReset}}
              >
                <RotateCcwIcon width='18' height='18' aria-hidden='true' />
                Start over…
              </button>
            {{/if}}
          </section>

          <section class='sheet-section'>
            <h3>Worksheet</h3>
            <button
              type='button'
              class='mid-btn wide'
              disabled={{this.downloadPdf.isRunning}}
              {{on 'click' this.startDownload}}
            >
              <DownloadIcon width='18' height='18' aria-hidden='true' />
              {{if
                this.downloadPdf.isRunning
                'Making PDF…'
                (concat 'Download ' this.levelName ' questions (PDF)')
              }}
            </button>
            <label class='check'>
              <input
                type='checkbox'
                checked={{this.keyOnOwnPage}}
                {{on 'change' this.toggleKeyPage}}
              />
              Answer key on its own last page
            </label>
            <label class='check'>
              <input
                type='checkbox'
                checked={{this.cutStrip}}
                {{on 'change' this.toggleCutStrip}}
              />
              Add a cut-and-glue picture page
            </label>
            <label class='check'>
              <input
                type='checkbox'
                checked={{this.addPuzzles}}
                {{on 'change' this.togglePuzzles}}
              />
              {{if
                (eq this.level 'aac')
                'Add a find-the-words puzzle'
                'Add word puzzles (find the words + crossword)'
              }}
            </label>
            {{#if this.pdfMessage}}
              <p class='pdf-message' role='status'>{{this.pdfMessage}}</p>
            {{/if}}
          </section>

          {{#if @model.teacherNotes}}
            <details class='sheet-section notes'>
              <summary>Notes for grown-ups</summary>
              <@fields.teacherNotes />
            </details>
          {{/if}}
        </aside>
      {{/if}}
    </article>

    <style scoped>
      .activity {
        --harvest: #f28c28;
        --harvest-deep: #9a3412;
        --ink-warm: #2b1406;
        --forest: #2f7d3a;
        --primary: #f28c28;
        --primary-foreground: #2b1406;
        --success: #2f7d3a;
        --success-foreground: #ffffff;
        --ring: #9a3412;
        --pic-h: clamp(5.5rem, 13cqi, 9rem);
        container-type: inline-size;
        position: relative;
        min-height: 100%;
        display: flex;
        flex-direction: column;
        background: #fff6e5;
        color: #1d1d1b;
        font-family: var(
          --font-sans,
          'Atkinson Hyperlegible',
          system-ui,
          sans-serif
        );
      }
      button {
        font: inherit;
      }
      button:focus-visible,
      .book:focus-visible {
        outline: 3px solid var(--ring);
        outline-offset: 3px;
      }

      /* ── Play bar ── */
      .play-bar {
        position: sticky;
        top: 0;
        z-index: 5;
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 8px 16px;
        min-height: 64px;
        box-sizing: border-box;
        padding: 8px 18px;
        background: #ffffff;
        border-bottom: 2px solid #f1e3cc;
      }
      .grown-ups {
        position: relative;
        flex: none;
        display: grid;
        place-items: center;
        width: 40px;
        height: 40px;
        padding: 0;
        border-radius: 10px;
        border: 1.5px solid #e8d5b5;
        background: #fffaf2;
        color: #8a6a4b;
        cursor: pointer;
        overflow: hidden;
        touch-action: none;
        user-select: none;
        -webkit-user-select: none;
      }
      .grown-ups::after {
        content: '';
        position: absolute;
        left: 0;
        bottom: 0;
        height: 4px;
        width: 0;
        background: var(--harvest);
      }
      .grown-ups[data-holding]::after {
        width: 100%;
        transition: width 700ms linear;
      }
      .hold-hint {
        position: absolute;
        right: 0;
        top: 48px;
        width: max-content;
        z-index: 9;
        padding: 8px 12px;
        border-radius: 10px;
        background: #1d1d1b;
        color: #ffffff;
        font-size: 15px;
        font-weight: 700;
      }
      .title-block {
        flex: 1 1 12rem;
        min-width: 0;
        display: flex;
        flex-direction: column;
      }
      .site-home {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        width: max-content;
        margin-bottom: 2px;
        color: #6b4a2b;
        font-size: 13px;
        font-weight: 700;
        text-decoration: none;
      }
      .site-home:hover {
        color: var(--harvest-deep);
        text-decoration: underline;
      }
      .kicker {
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--harvest-deep);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .title {
        margin: 0;
        font-size: 22px;
        line-height: 1.15;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .steps {
        flex: none;
        display: flex;
        gap: 8px;
      }
      .play-bar .steps {
        gap: 4px;
        padding: 4px;
        border-radius: 14px;
        background: #f6ead6;
      }
      .play-bar .step {
        width: auto;
        height: 40px;
        padding: 0 16px;
        flex-direction: row;
        gap: 8px;
        border-radius: 10px;
        background: transparent;
        color: #7a5a3b;
        font-size: 15px;
      }
      .play-bar .step:hover:not(.is-current) {
        background: #fffaf2;
      }
      .play-bar .step.is-current {
        background: #ffffff;
        color: var(--harvest-deep);
        box-shadow: 0 1px 4px rgb(80 40 10 / 18%);
      }
      .bar-tools {
        position: relative;
        flex: none;
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .bar-level {
        flex: none;
        display: flex;
        align-items: center;
        gap: 6px;
      }
      .level-pills {
        display: flex;
        gap: 2px;
        padding: 3px;
        border-radius: 12px;
        border: 1.5px solid #e8d5b5;
        background: #fffaf2;
      }
      .level-pill {
        height: 32px;
        padding: 0 12px;
        border: none;
        border-radius: 9px;
        background: transparent;
        color: #7a5a3b;
        font: inherit;
        font-size: 14px;
        font-weight: 700;
        cursor: pointer;
      }
      .level-pill:hover:not(.is-current) {
        background: #f6ead6;
      }
      .level-pill.is-current {
        background: var(--harvest);
        color: var(--ink-warm);
      }
      .level-pill:focus-visible {
        outline: 3px solid var(--harvest-deep);
        outline-offset: 1px;
      }
      .bar-pdf-wrap {
        position: relative;
        flex: none;
      }
      .bar-pdf {
        display: flex;
        align-items: center;
        gap: 6px;
        height: 40px;
        padding: 0 12px;
        border-radius: 10px;
        border: 1.5px solid #e8d5b5;
        background: #fffaf2;
        color: #4a3826;
        font-size: 15px;
        font-weight: 700;
        cursor: pointer;
      }
      .bar-pdf:hover:not(:disabled) {
        background: var(--harvest);
        color: var(--ink-warm);
      }
      .bar-pdf:disabled {
        opacity: 0.7;
        cursor: progress;
      }
      .bar-pdf-status {
        position: absolute;
        right: 0;
        top: 48px;
        z-index: 9;
        width: max-content;
        max-width: 18rem;
        padding: 8px 12px;
        border-radius: 10px;
        background: #1d1d1b;
        color: #ffffff;
        font-size: 14px;
        font-weight: 700;
      }
      .bar-level-label {
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--harvest-deep);
      }
      .bar-confirm {
        position: absolute;
        right: 18px;
        top: calc(100% + 8px);
        z-index: 8;
        width: min(24rem, calc(100% - 36px));
        box-sizing: border-box;
        box-shadow: 0 12px 28px rgb(0 0 0 / 18%);
      }
      .step {
        width: 76px;
        height: 58px;
        border-radius: 14px;
        border: none;
        background: #fff1de;
        color: #6b4a2b;
        font-size: 13px;
        font-weight: 700;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 2px;
        cursor: pointer;
      }
      .step.is-current {
        background: var(--harvest);
        color: var(--ink-warm);
      }

      .steps-bottom {
        display: none;
      }
      .stage {
        flex: 1 1 auto;
        display: flex;
        flex-direction: column;
      }
      .step-body {
        flex: 1 1 auto;
        box-sizing: border-box;
        padding: 16px 24px 20px;
        display: flex;
        flex-direction: column;
        gap: 14px;
      }

      /* ── Shared buttons ── */
      .big-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 12px;
        height: 66px;
        padding: 0 30px;
        border-radius: 999px;
        border: none;
        font-size: 24px;
        font-weight: 700;
        cursor: pointer;
      }
      .big-btn.sing {
        background: var(--forest);
        color: #ffffff;
        box-shadow: 0 4px 0 #1f5a27;
      }
      .big-btn.stop {
        background: #b42318;
        color: #ffffff;
        box-shadow: 0 4px 0 #7a1810;
      }
      .big-btn.primary {
        background: var(--harvest);
        color: var(--ink-warm);
        box-shadow: 0 5px 0 #b85f12;
      }
      .mid-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 10px;
        min-height: 50px;
        padding: 0 20px;
        border-radius: 999px;
        border: 2px solid #c9b28e;
        background: #ffffff;
        color: #3d2a16;
        font-size: 17px;
        font-weight: 700;
        cursor: pointer;
      }
      .mid-btn[disabled] {
        opacity: 0.6;
        cursor: progress;
      }
      .mid-btn.go {
        border-color: var(--forest);
        background: var(--forest);
        color: #ffffff;
      }
      .mid-btn.danger {
        border-color: #b42318;
        background: #b42318;
        color: #ffffff;
      }
      .mid-btn.wide {
        width: 100%;
      }
      .page-count {
        font-size: 17px;
        font-weight: 700;
        color: #6b4a2b;
        white-space: nowrap;
      }
      .empty {
        margin: 0;
        font-size: 18px;
        color: #5d574e;
      }

      /* ── Listen ── */
      .controls {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 12px 14px;
      }
      .controls .page-count {
        margin-left: auto;
      }
      .book {
        position: relative;
        display: flex;
        outline: none;
        touch-action: pan-y;
        perspective: 1600px;
      }
      .page {
        position: relative;
        flex: 1 1 auto;
        min-height: clamp(19rem, 40cqi, 26rem);
        box-sizing: border-box;
        padding: 26px 96px 22px;
        border-radius: 8px 26px 26px 8px;
        background:
          linear-gradient(90deg, rgb(0 0 0 / 8%), transparent 2.5rem), #fffdf7;
        box-shadow:
          inset 6px 0 0 #ead8b8,
          6px 6px 0 -1px #f3e6cf,
          12px 12px 0 -2px #e9d7b8,
          0 18px 34px rgb(80 40 10 / 16%);
        display: flex;
        align-items: center;
        justify-content: center;
        transform-origin: left center;
        backface-visibility: hidden;
      }
      /* Listen pages are all one height, capped by the screen, and fitPage
         shrinks a long verse to fit instead of letting the page grow. */
      .page.fit {
        --page-h: clamp(19rem, 40cqi, 26rem);
        height: min(var(--page-h), max(15rem, 100dvh - 19rem));
        min-height: 0;
        overflow: hidden;
      }
      .level-advanced .page.fit {
        --page-h: clamp(14rem, 28cqi, 19rem);
      }
      .page.flip-next {
        animation: flip-next 420ms cubic-bezier(0.2, 0.7, 0.3, 1);
      }
      .page.flip-prev {
        animation: flip-prev 420ms cubic-bezier(0.2, 0.7, 0.3, 1);
        transform-origin: right center;
      }
      .page-line {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-end;
        justify-content: center;
        gap: 12px clamp(8px, 1.4cqi, 16px);
      }
      .row-break {
        flex-basis: 100%;
        height: 0;
      }
      .line-speaker {
        position: absolute;
        left: 22px;
        bottom: 16px;
        width: 48px;
        height: 48px;
        border-radius: 50%;
        border: 2px solid #e2cfae;
        background: #ffffff;
        color: #6b4a2b;
        display: grid;
        place-items: center;
        cursor: pointer;
      }
      .word-col {
        display: grid;
        grid-template-rows: 22px var(--pic-h) auto 6px;
        justify-items: center;
        align-items: end;
        gap: 6px;
        min-width: 2.5rem;
        padding: 0 2px;
        border: none;
        border-radius: 12px;
        background: transparent;
        color: inherit;
        cursor: pointer;
        transition: opacity 160ms ease;
      }
      div.word-col {
        cursor: default;
      }
      .book.playing .word-col:not(.active) {
        opacity: 0.55;
      }
      .bounce {
        width: 18px;
        height: 18px;
        border-radius: 50%;
        background: var(--harvest);
        visibility: hidden;
      }
      .word-col.active .bounce {
        visibility: visible;
        animation: bob 0.8s ease-in-out infinite;
      }
      .pic-cell {
        display: grid;
        place-items: end center;
        height: var(--pic-h);
        min-height: 0;
      }
      .page-pic {
        position: relative;
        display: grid;
        place-items: center;
        box-sizing: border-box;
        width: calc(var(--pic-h) * 5 / 6);
        height: var(--pic-h);
        padding: 8px;
        border: 0.3rem solid var(--tile-color);
        border-radius: 16px;
        background: #ffffff;
        transition:
          transform 160ms ease,
          box-shadow 160ms ease;
      }
      .page-pic img {
        width: 100%;
        height: 100%;
        min-height: 0;
        object-fit: contain;
      }
      .word-col.active .page-pic {
        transform: translateY(-8px) scale(1.08);
        box-shadow:
          0 0 0 0.35rem color-mix(in srgb, var(--tile-color) 45%, transparent),
          0 14px 26px rgb(0 0 0 / 18%);
      }
      .word-text {
        font-size: clamp(1.5rem, 3.8cqi, 3rem);
        font-weight: 700;
        line-height: 1.1;
        padding: 2px 6px;
        border-radius: 8px;
      }
      .word-col.active .word-text {
        background: #ffe98a;
      }
      .key-bar {
        width: 72%;
        height: 6px;
        border-radius: 3px;
        background: transparent;
      }
      .has-pic .key-bar {
        background: var(--tile-color);
      }
      .level-advanced .pic-cell,
      .level-advanced .bounce {
        display: none;
      }
      .level-advanced .word-col {
        grid-template-rows: auto 6px;
      }
      .level-advanced .word-text {
        font-size: clamp(2rem, 5.2cqi, 4rem);
      }
      .level-advanced .page {
        min-height: clamp(14rem, 28cqi, 19rem);
      }
      .level-regular {
        --pic-h: clamp(4rem, 9cqi, 6.5rem);
      }
      .edge {
        position: absolute;
        top: 50%;
        transform: translateY(-50%);
        width: 64px;
        height: 64px;
        border-radius: 50%;
        display: grid;
        place-items: center;
        cursor: pointer;
        z-index: 2;
      }
      .edge.prev {
        left: 16px;
        border: 3px solid #e2cfae;
        background: #ffffff;
        color: #8a6a45;
      }
      .edge.next {
        right: 16px;
        border: none;
        background: var(--harvest);
        color: var(--ink-warm);
        box-shadow: 0 4px 0 #b85f12;
      }
      .edge.next.quiet {
        border: 3px solid #e2cfae;
        background: #ffffff;
        color: #8a6a45;
        box-shadow: none;
      }
      .edge.next.ready-next {
        background: var(--forest);
        color: #ffffff;
        box-shadow: 0 4px 0 #1f5a27;
        animation: nudge 1.1s ease-in-out infinite;
      }
      .dots {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: 10px;
      }
      .dot {
        width: 20px;
        height: 20px;
        padding: 0;
        border-radius: 50%;
        border: 3px solid #d9c3a0;
        background: #ffffff;
        color: #ffffff;
        display: grid;
        place-items: center;
        cursor: pointer;
      }
      .dot.done {
        border-color: var(--forest);
        background: var(--forest);
      }
      .dot.current {
        border-color: var(--harvest);
        box-shadow: 0 0 0 4px rgb(242 140 40 / 30%);
      }
      .banner {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 12px 16px;
        padding: 14px 18px;
        border-radius: 18px;
        background: #e3f6e7;
        color: #134a24;
      }
      .banner p {
        flex: 1 1 14rem;
        margin: 0;
        font-size: 22px;
        font-weight: 700;
      }

      /* ── Play (Your turn) ── */
      .status-row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 10px 16px;
        min-height: 34px;
      }
      .mini-dots {
        display: flex;
        gap: 8px;
        align-items: center;
      }
      .mini-dots .dot {
        width: 22px;
        height: 22px;
      }
      .done-count {
        margin-left: auto;
        font-size: 16px;
        font-weight: 700;
        color: #1e6b2c;
      }
      .great {
        margin-left: auto;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 6px 14px;
        border-radius: 999px;
        background: #e3f6e7;
        color: #134a24;
        font-size: 18px;
        font-weight: 700;
      }
      .book.compact {
        --pic-h: clamp(5rem, 11cqi, 7.5rem);
      }
      .level-regular .book.compact {
        --pic-h: clamp(3.75rem, 8cqi, 5.5rem);
      }
      .book.compact .page {
        min-height: 0;
        height: auto;
        padding: 22px 92px 20px;
      }
      .book.compact .word-col {
        grid-template-rows: var(--pic-h) auto 6px;
      }
      .book.compact .bounce {
        display: none;
      }
      .level-advanced .book.compact .word-col {
        grid-template-rows: auto 6px;
      }
      .level-advanced .book.compact .page {
        padding: 34px 92px;
      }
      .slot {
        position: relative;
        display: grid;
        place-items: center;
        box-sizing: border-box;
        width: calc(var(--pic-h) * 5 / 6);
        height: var(--pic-h);
        overflow: hidden;
        border: 0.3rem dashed color-mix(in srgb, var(--tile-color) 70%, #8a7553);
        border-radius: 16px;
        background: color-mix(in srgb, var(--tile-color) 10%, #fffaf2);
        cursor: pointer;
        transition:
          transform 140ms ease,
          background 140ms ease;
      }
      .slot.ready,
      .word-slot.ready {
        border-color: var(--harvest-deep);
      }
      .slot[data-drag-over],
      .word-slot[data-drag-over] {
        transform: scale(1.08);
        border-style: solid;
        border-color: var(--forest);
        background: #e7f5e9;
        box-shadow: 0 0 0 6px rgb(47 125 58 / 18%);
      }
      .slot.shake,
      .word-slot.shake {
        animation: wiggle 420ms ease;
      }
      .ghost-hint {
        width: 80%;
        height: 80%;
        object-fit: contain;
        opacity: 0.22;
        pointer-events: none;
      }
      .placed-check {
        position: absolute;
        top: -10px;
        right: -10px;
        width: 28px;
        height: 28px;
        border-radius: 50%;
        background: var(--forest);
        color: #ffffff;
        border: 3px solid #ffffff;
        display: grid;
        place-items: center;
      }
      .just-placed {
        animation: pop 260ms ease-out;
      }
      .word-slot {
        display: inline-grid;
        place-items: center;
        min-width: calc(var(--slot-ch, 5) * 0.62em + 0.6em);
        height: 1.35em;
        padding: 0 0.2em;
        border: 0.2rem dashed #a8916e;
        border-radius: 0.5rem;
        background: #fffaf2;
        color: inherit;
        cursor: pointer;
      }
      .ghost-word {
        opacity: 0.25;
      }
      .placed-word {
        color: #1e6b2c;
      }
      .shelf {
        display: flex;
        align-items: center;
        gap: 22px;
        min-height: 12rem;
        box-sizing: border-box;
        padding: 14px 26px;
        border-radius: 22px;
        background: #fdebd3;
        box-shadow: inset 0 3px 0 #f4d3a6;
      }
      .shelf-label {
        flex: 0 1 15rem;
        margin: 0;
        font-size: 18px;
        font-weight: 700;
        line-height: 1.35;
        color: #4a2e12;
      }
      .shelf-tiles {
        flex: 1 1 0;
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        align-items: center;
        gap: 22px;
      }
      .shelf-done {
        display: flex;
        align-items: center;
        gap: 8px;
        margin: 0;
        font-size: 22px;
        font-weight: 700;
        color: #134a24;
      }
      .word-card {
        padding: 0.4em 0.9em;
        border: 0.22rem solid #e8b366;
        border-radius: 0.9rem;
        background: #ffffff;
        color: #1d1d1b;
        font-size: clamp(1.4rem, 3.4cqi, 2.3rem);
        font-weight: 700;
        cursor: grab;
        touch-action: none;
        user-select: none;
        -webkit-user-select: none;
        box-shadow: 0 3px 0 #e8b366;
      }
      .word-card.selected {
        outline: 0.25rem solid var(--harvest-deep);
        outline-offset: 0.15rem;
      }
      .word-card[data-dragging] {
        opacity: 0.4;
      }

      /* ── Finish celebration ── */
      .celebrate {
        position: relative;
        align-items: center;
        justify-content: center;
        overflow: hidden;
        min-height: 36rem;
      }
      .finish-card {
        position: relative;
        width: min(44rem, 100%);
        box-sizing: border-box;
        padding: 34px 40px 30px;
        border-radius: 32px;
        background: #ffffff;
        box-shadow:
          0 0 0 4px #f7d9ae,
          0 24px 48px rgb(80 40 10 / 18%);
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 18px;
        text-align: center;
      }
      .finish-card.small {
        align-self: center;
        margin-top: 24px;
      }
      .finish-card h2 {
        margin: 0;
        font-size: clamp(2rem, 5cqi, 3.2rem);
        line-height: 1.05;
      }
      .finish-badge {
        width: 128px;
        height: 128px;
        border-radius: 50%;
        background: #fff1de;
        border: 6px solid var(--harvest);
        color: var(--harvest-deep);
        display: grid;
        place-items: center;
        animation: pop 420ms ease-out;
      }
      .finish-sub {
        margin: -6px 0 0;
        font-size: 20px;
        color: #5d574e;
      }
      .stars {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: 8px;
      }
      .star {
        width: 38px;
        height: 38px;
        border-radius: 50%;
        background: var(--forest);
        color: #ffe36e;
        display: grid;
        place-items: center;
      }
      .finish-more {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: 12px;
      }
      .pdf-message {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
        color: #134a24;
      }
      .confetti {
        position: absolute;
        border-radius: 6px;
        animation: drift 3.2s ease-in-out infinite;
      }
      .c1 {
        left: 8%;
        top: 12%;
        width: 22px;
        height: 22px;
        border-radius: 50%;
        background: #8fdb8f;
      }
      .c2 {
        left: 14%;
        top: 72%;
        width: 16px;
        height: 34px;
        background: #8ec5ff;
        transform: rotate(28deg);
      }
      .c3 {
        right: 10%;
        top: 16%;
        width: 18px;
        height: 36px;
        background: #ffa8d2;
        transform: rotate(-24deg);
      }
      .c4 {
        right: 8%;
        top: 66%;
        width: 24px;
        height: 24px;
        border-radius: 50%;
        background: #ffe36e;
      }
      .c5 {
        left: 22%;
        top: 40%;
        width: 14px;
        height: 30px;
        background: #ffb866;
        transform: rotate(-36deg);
      }
      .c6 {
        right: 22%;
        top: 44%;
        width: 16px;
        height: 16px;
        border-radius: 50%;
        background: #c9a8ff;
      }

      /* ── Ask (questions) ── */
      .q-progress {
        display: flex;
        align-items: center;
        gap: 16px;
      }
      .q-bar {
        flex: 1 1 0;
        height: 14px;
        border-radius: 7px;
        background: #f1e0c4;
        overflow: hidden;
      }
      .q-fill {
        display: block;
        width: var(--q-pct, 0%);
        height: 100%;
        border-radius: 7px;
        background: var(--harvest);
        transition: width 260ms ease;
      }
      .q-card {
        border-radius: 26px;
        box-shadow: 0 14px 30px rgb(80 40 10 / 12%);
        animation: slide-in 280ms ease-out;
      }
      .q-nav {
        display: flex;
        align-items: center;
        gap: 12px;
      }
      .q-nav .next-q {
        margin-left: auto;
      }

      /* ── Talk ── */
      .message-bar {
        display: flex;
        gap: 10px;
        min-height: 96px;
      }
      .message {
        flex: 1 1 0;
        min-width: 0;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 8px 10px;
        border-radius: 18px;
        border: 3px solid #e2cfae;
        background: #ffffff;
        overflow-x: auto;
        cursor: pointer;
      }
      .msg-tile {
        flex: none;
        width: 74px;
        height: 86px;
        box-sizing: border-box;
        padding: 4px;
        border-radius: 12px;
        border: 3px solid var(--tile-color);
        display: flex;
        flex-direction: column;
        align-items: center;
        font-size: 13px;
        font-weight: 700;
      }
      .msg-tile img {
        width: 56px;
        height: 56px;
        object-fit: contain;
      }
      .msg-empty {
        padding: 0 10px;
        font-size: 19px;
        color: #5d574e;
      }
      .speak-btn {
        flex: none;
        width: 150px;
        border-radius: 18px;
        border: none;
        background: var(--forest);
        color: #ffffff;
        font-size: 24px;
        font-weight: 700;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 4px;
        box-shadow: 0 4px 0 #1f5a27;
        cursor: pointer;
      }
      .tool-btn {
        flex: none;
        width: 96px;
        border-radius: 18px;
        border: 3px solid #e2cfae;
        background: #ffffff;
        color: #3d2a16;
        font-size: 16px;
        font-weight: 700;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 4px;
        cursor: pointer;
      }
      .talk-tabs {
        display: flex;
        gap: 10px;
      }
      .tab {
        height: 46px;
        padding: 0 22px;
        border-radius: 999px;
        border: 2px solid #d9c3a0;
        background: #ffffff;
        color: #3d2a16;
        font-size: 17px;
        font-weight: 700;
        cursor: pointer;
      }
      .tab.is-current {
        border-color: #1d1d1b;
        background: #1d1d1b;
        color: #ffffff;
      }
      .talk-grid {
        flex: none;
        height: clamp(17rem, 34cqi, 23rem);
        display: grid;
        grid-template-rows: repeat(3, minmax(0, 1fr));
        grid-template-columns: repeat(var(--talk-cols, 6), minmax(0, 1fr));
        grid-auto-flow: column;
        gap: 12px;
      }

      /* ── Grown-up panel ── */
      .scrim {
        position: absolute;
        inset: 0;
        z-index: 20;
        background: rgb(29 29 27 / 48%);
      }
      .panel-sheet {
        position: absolute;
        top: 0;
        right: 0;
        bottom: 0;
        z-index: 21;
        width: min(30rem, 100%);
        box-sizing: border-box;
        padding: 22px 26px;
        overflow-y: auto;
        background: #ffffff;
        box-shadow: -12px 0 32px rgb(0 0 0 / 20%);
        display: flex;
        flex-direction: column;
        gap: 22px;
      }
      .sheet-head {
        display: flex;
        align-items: center;
        gap: 10px;
        color: #6b4a2b;
      }
      .sheet-head h2 {
        flex: 1 1 0;
        margin: 0;
        font-size: 26px;
        color: #1d1d1b;
      }
      .close {
        width: 48px;
        height: 48px;
        border-radius: 50%;
        border: 2px solid #e2cfae;
        background: #ffffff;
        color: #3d2a16;
        display: grid;
        place-items: center;
        cursor: pointer;
      }
      .sheet-section {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .sheet-section h3 {
        margin: 0;
        font-size: 14px;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: #6b4a2b;
      }
      .level-switch {
        font-size: 17px;
        font-weight: 700;
      }
      .check {
        display: flex;
        align-items: center;
        gap: 12px;
        min-height: 44px;
        font-size: 17px;
        font-weight: 700;
      }
      .check input {
        width: 24px;
        height: 24px;
        margin: 0;
        accent-color: var(--forest);
      }
      .confirm {
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 14px 16px;
        border-radius: 14px;
        background: #fff4f2;
        border: 2px solid #f3c5be;
        font-size: 15px;
        color: #5d574e;
      }
      .confirm strong {
        font-size: 17px;
        color: #7a1f15;
      }
      .confirm-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
      }
      .notes summary {
        font-size: 17px;
        font-weight: 700;
        cursor: pointer;
      }

      /* ── Mid width: the step tabs move to their own row under the title ── */
      @container (max-width: 1140px) {
        .play-bar .steps {
          order: 10;
          flex: 1 1 100%;
          justify-content: center;
        }
        .play-bar .step {
          flex: 1 1 0;
          max-width: 10rem;
          justify-content: center;
        }
      }

      /* ── Phone / narrow ── */
      @container (max-width: 640px) {
        .play-bar {
          padding: 8px 12px;
        }
        .bar-level-label {
          display: none;
        }
        .bar-pdf-label {
          display: none;
        }
        .bar-pdf {
          width: 40px;
          padding: 0;
          justify-content: center;
        }
        .play-bar .steps {
          display: none;
        }
        .steps-bottom {
          display: grid;
          position: sticky;
          bottom: 0;
          z-index: 6;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          gap: 6px;
          padding: 8px 10px 12px;
          background: #ffffff;
          border-top: 2px solid #f1e3cc;
        }
        .steps-bottom .step {
          width: auto;
          background: transparent;
        }
        .steps-bottom .step.is-current {
          background: var(--harvest);
        }
        .step-body {
          padding: 14px 12px 18px;
        }
        .page {
          padding: 20px 34px 70px;
        }
        .book.compact .page {
          padding: 12px 34px;
          height: auto;
          min-height: 13rem;
        }
        .edge {
          width: 52px;
          height: 52px;
        }
        .edge.prev {
          left: -6px;
        }
        .edge.next {
          right: -6px;
        }
        .big-btn {
          height: 58px;
          padding: 0 22px;
          font-size: 20px;
        }
        .shelf {
          flex-direction: column;
          align-items: stretch;
          padding: 12px;
        }
        .shelf-label {
          flex: none;
        }
        .message-bar {
          flex-wrap: wrap;
        }
        .message {
          flex-basis: 100%;
          min-height: 96px;
        }
        .speak-btn,
        .tool-btn {
          flex: 1 1 0;
          height: 72px;
        }
        .talk-grid {
          grid-auto-flow: row;
          grid-template-rows: none;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          grid-auto-rows: 8.5rem;
        }
      }

      @keyframes flip-next {
        from {
          transform: rotateY(-75deg);
          opacity: 0.3;
        }
        to {
          transform: rotateY(0);
          opacity: 1;
        }
      }
      @keyframes flip-prev {
        from {
          transform: rotateY(75deg);
          opacity: 0.3;
        }
        to {
          transform: rotateY(0);
          opacity: 1;
        }
      }
      @keyframes bob {
        0%,
        100% {
          transform: translateY(0);
        }
        50% {
          transform: translateY(-8px);
        }
      }
      @keyframes nudge {
        0%,
        100% {
          transform: translateY(-50%) translateX(0);
        }
        50% {
          transform: translateY(-50%) translateX(6px);
        }
      }
      @keyframes wiggle {
        0%,
        100% {
          transform: translateX(0);
        }
        25% {
          transform: translateX(-6px);
        }
        75% {
          transform: translateX(6px);
        }
      }
      @keyframes pop {
        from {
          transform: scale(0.6);
        }
        to {
          transform: scale(1);
        }
      }
      @keyframes drift {
        0%,
        100% {
          translate: 0 0;
        }
        50% {
          translate: 0 -12px;
        }
      }
      @keyframes slide-in {
        from {
          opacity: 0;
          transform: translateX(30px);
        }
        to {
          opacity: 1;
          transform: translateX(0);
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .page.flip-next,
        .page.flip-prev,
        .edge.next.ready-next,
        .word-col.active .bounce,
        .slot.shake,
        .word-slot.shake,
        .just-placed,
        .finish-badge,
        .confetti,
        .q-card {
          animation: none;
        }
      }
    </style>
  </template>
}

export class AacActivity extends CardDef {
  static displayName = 'AAC Activity';
  static icon = BookOpenIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  // A short label above the title: "October · Song".
  @field occasion = contains(StringField);
  // One entry per line of the song or story, read and rebuilt in order.
  @field lines = containsMany(StringField);
  // Pictures for the story words plus core words for the Talk board.
  @field vocabulary = linksToMany(() => AacSymbol);
  @field choiceBoards = linksToMany(() => AacChoiceBoard);
  @field teacherNotes = contains(MarkdownField);
  // The level the activity opens at; the grown-up can switch any time.
  @field defaultLevel = contains(LevelField);
  // The tune Sing along plays; Skip to My Lou when empty.
  @field tune = contains(TuneField);
  // Where the activity shows up in the Activity Library.
  @field month = contains(MonthField);
  @field categories = containsMany(CategoryField);
  // A storybook picture for the library tile; upload any image in Edit.
  @field coverImage = linksTo(() => ImageDef);
  // A 1200×630 PNG of the cover for link previews (social sites can't show
  // SVG); the cover is used when this is empty.
  @field shareImage = linksTo(() => ImageDef);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AacActivity) {
      return (
        this.cardInfo?.name?.trim() ||
        this.title?.trim() ||
        `Untitled ${AacActivity.displayName}`
      );
    },
  });

  static isolated = ActivityIsolated;

  // Page title and share-preview tags; the storybook cover is the picture.
  static head = class Head extends Component<typeof AacActivity> {
    get description() {
      const kind = this.args.model?.occasion?.trim();
      return `${kind ? kind + '. ' : ''}A sing-along with AAC pictures, a flip book, picture games and questions at three levels.`;
    }
    get image() {
      return (
        this.args.model?.shareImage?.url ?? this.args.model?.coverImage?.url
      );
    }
    get pageURL() {
      return this.args.model?.id ?? '';
    }
    <template>
      {{! template-lint-disable no-forbidden-elements }}
      <title>{{@model.cardTitle}}</title>
      <meta name='description' content={{this.description}} />
      <meta property='og:type' content='website' />
      <meta property='og:title' content={{@model.cardTitle}} />
      <meta property='og:description' content={{this.description}} />
      {{#if this.pageURL}}
        <meta property='og:url' content={{this.pageURL}} />
      {{/if}}
      {{#if this.image}}
        <meta property='og:image' content={{this.image}} />
        <meta property='og:image:alt' content={{@model.cardTitle}} />
        <meta name='twitter:image' content={{this.image}} />
        <meta name='twitter:card' content='summary_large_image' />
      {{else}}
        <meta name='twitter:card' content='summary' />
      {{/if}}
      <meta name='twitter:title' content={{@model.cardTitle}} />
      <meta name='twitter:description' content={{this.description}} />
    </template>
  };

  static embedded = class Embedded extends Component<typeof AacActivity> {
    get firstLine() {
      return buildLines(this.args.model as AacActivity)[0];
    }
    <template>
      <div class='preview'>
        {{#if @model.occasion}}<p class='kicker'>{{@model.occasion}}</p>{{/if}}
        <h3><@fields.cardTitle /></h3>
        {{#if this.firstLine}}
          <div class='line'>
            {{#each this.firstLine.words as |word|}}
              <span class='w'>
                <span class='p'>
                  {{#if word.key}}
                    <img src={{symbolImage word.symbol}} alt='' />
                  {{/if}}
                </span>
                <span>{{word.text}}</span>
              </span>
            {{/each}}
          </div>
        {{/if}}
      </div>
      <style scoped>
        .preview {
          display: grid;
          gap: 0.5rem;
          padding: 1rem;
          background: var(--card, #fff);
          color: var(--card-foreground, #1d1d1b);
        }
        .kicker {
          margin: 0;
          font-size: 0.75rem;
          font-weight: 800;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: #8a3b12;
        }
        h3 {
          margin: 0;
          font-size: 1.3rem;
        }
        .line {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
          align-items: flex-end;
        }
        .w {
          display: grid;
          justify-items: center;
          font-weight: 800;
          font-size: 1.05rem;
        }
        .p {
          height: 2.75rem;
          display: grid;
          place-items: end center;
        }
        .p img {
          height: 2.5rem;
          object-fit: contain;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof AacActivity> {
    get pictures() {
      const seen = new Set<string>();
      const out: string[] = [];
      for (const line of buildLines(this.args.model as AacActivity)) {
        for (const w of line.keyWords) {
          const src = symbolImage(w.symbol);
          if (src && !seen.has(src)) {
            seen.add(src);
            out.push(src);
          }
        }
      }
      return out.slice(0, 3);
    }
    get cover() {
      return this.args.model?.coverImage?.url;
    }
    get meta() {
      const pages = (this.args.model?.lines ?? []).filter(Boolean).length;
      return `${pages} pages · 3 levels`;
    }
    <template>
      <div class='fit'>
        {{#if this.cover}}
          <div class='cover' aria-hidden='true'>
            <img src={{this.cover}} alt='' />
          </div>
        {{else}}
          <div class='pics' aria-hidden='true'>
            {{#each this.pictures as |src|}}
              <img src={{src}} alt='' />
            {{else}}
              <BookOpenIcon width='32' height='32' />
            {{/each}}
          </div>
        {{/if}}
        <div class='text'>
          {{#if @model.occasion}}
            <div class='eyebrow'>{{@model.occasion}}</div>
          {{/if}}
          <div class='title'><@fields.cardTitle /></div>
          <div class='meta'>{{this.meta}}</div>
        </div>
      </div>
      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: minmax(0, 1.6fr) minmax(0, 1fr);
          background: #ffffff;
          color: #1d1d1b;
          overflow: hidden;
        }
        .pics {
          min-height: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 6%;
          padding: 8px 10px;
          background: #fff1de;
          overflow: hidden;
        }
        .cover {
          min-height: 0;
          overflow: hidden;
          background: #fff1de;
        }
        .cover img {
          display: block;
          width: 100%;
          height: 100%;
          object-fit: cover;
        }
        .pics img {
          min-width: 0;
          max-width: 30%;
          max-height: 100%;
          object-fit: contain;
        }
        .text {
          min-height: 0;
          padding: 8px 12px;
          display: flex;
          flex-direction: column;
          gap: 2px;
          overflow: hidden;
        }
        .eyebrow {
          font-size: 11px;
          font-weight: 700;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: #9a3412;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .title {
          font-size: 17px;
          font-weight: 700;
          line-height: 1.15;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .meta {
          font-size: 12px;
          color: #5d574e;
          white-space: nowrap;
        }
        @container fitted-card (aspect-ratio > 1.6) {
          .fit {
            grid-template-rows: none;
            grid-template-columns: minmax(0, 0.9fr) minmax(0, 1.1fr);
          }
          .text {
            justify-content: center;
          }
        }
        @container fitted-card (height <= 80px) {
          .meta,
          .eyebrow {
            display: none;
          }
        }
      </style>
    </template>
  };
}
