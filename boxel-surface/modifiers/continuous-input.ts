import { modifier } from 'ember-modifier';

export interface ContinuousInputOptions {
  /** Runs at most once per animation frame while the native control moves. */
  onPreview?: (value: string, event: Event, element: HTMLInputElement) => void;
  /** Runs when the native control settles, or per frame when commitMode is `frame`. */
  onCommit?: (value: string, event: Event, element: HTMLInputElement) => void;
  /**
   * `settled` keeps tracked/model writes off the high-frequency input path.
   * `frame` is available for consumers that truly need model writes while dragging.
   */
  commitMode?: 'settled' | 'frame';
  /**
   * When present, ArrowUp / ArrowRight nudge the input up and
   * ArrowDown / ArrowLeft nudge it down. The modifier marks the
   * input as keyboard-owned so parent surface navigation can leave
   * arrow keys with the editor.
   */
  keyboardStep?: number;
  /** Defaults to `keyboardStep * 10`. */
  keyboardShiftStep?: number;
  /** Defaults to the input's `min` attribute when present. */
  keyboardMin?: number;
  /** Defaults to the input's `max` attribute when present. */
  keyboardMax?: number;
}

function finiteNumber(
  value: string | number | null | undefined,
): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function trimNumericString(value: number): string {
  return Number.isInteger(value)
    ? String(value)
    : String(Number(value.toFixed(8)));
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

const surfaceContinuousInput = modifier<{
  Element: HTMLInputElement;
  Args: { Positional: []; Named: ContinuousInputOptions };
}>((element, _positional, opts) => {
  let previewFrame: number | null = null;
  let commitFrame: number | null = null;
  let latestInputEvent: Event | null = null;
  let activeRangePointer: number | null = null;
  const priorKeyboardOwner = element.getAttribute(
    'data-surface-keyboard-owner',
  );
  if (opts.keyboardStep !== undefined) {
    element.setAttribute('data-surface-keyboard-owner', 'value');
  }

  const stopSurfacePointerRouting = (event: Event): void => {
    event.stopPropagation();
  };

  const cancelPreview = (): void => {
    if (previewFrame !== null) cancelAnimationFrame(previewFrame);
    previewFrame = null;
  };

  const cancelCommit = (): void => {
    if (commitFrame !== null) cancelAnimationFrame(commitFrame);
    commitFrame = null;
  };

  const flushPreview = (): void => {
    previewFrame = null;
    if (!latestInputEvent) return;
    opts.onPreview?.(element.value, latestInputEvent, element);
  };

  const flushCommit = (): void => {
    commitFrame = null;
    if (!latestInputEvent) return;
    opts.onCommit?.(element.value, latestInputEvent, element);
  };

  const schedulePreview = (event: Event): void => {
    latestInputEvent = event;
    if (opts.onPreview && previewFrame === null) {
      previewFrame = requestAnimationFrame(flushPreview);
    }
  };

  const scheduleFrameCommit = (event: Event): void => {
    latestInputEvent = event;
    if (opts.commitMode === 'frame' && opts.onCommit && commitFrame === null) {
      commitFrame = requestAnimationFrame(flushCommit);
    }
  };

  const setRangeValueFromPointer = (event: PointerEvent): void => {
    const rect = element.getBoundingClientRect();
    if (rect.width <= 0) return;

    const min =
      finiteNumber(opts.keyboardMin) ?? finiteNumber(element.min) ?? 0;
    const max =
      finiteNumber(opts.keyboardMax) ?? finiteNumber(element.max) ?? 100;
    const step =
      element.step === 'any'
        ? null
        : (finiteNumber(element.step) ??
          finiteNumber(element.getAttribute('step')) ??
          1);
    const ratio = clamp((event.clientX - rect.left) / rect.width, 0, 1);
    let next = min + (max - min) * ratio;

    if (step !== null && step > 0) {
      next = Math.round((next - min) / step) * step + min;
    }

    element.value = trimNumericString(clamp(next, min, max));
  };

  const beginRangePointer = (event: PointerEvent): void => {
    if (element.type !== 'range' || event.button !== 0) return;
    activeRangePointer = event.pointerId;
    element.focus({ preventScroll: true });
    element.setPointerCapture?.(event.pointerId);
    event.preventDefault();
    event.stopPropagation();
    setRangeValueFromPointer(event);
    schedulePreview(event);
    scheduleFrameCommit(event);
  };

  const updateRangePointer = (event: PointerEvent): void => {
    if (activeRangePointer !== event.pointerId) return;
    event.preventDefault();
    event.stopPropagation();
    setRangeValueFromPointer(event);
    schedulePreview(event);
    scheduleFrameCommit(event);
  };

  const endRangePointer = (event: PointerEvent): void => {
    if (activeRangePointer !== event.pointerId) return;
    activeRangePointer = null;
    element.releasePointerCapture?.(event.pointerId);
    event.preventDefault();
    event.stopPropagation();
    setRangeValueFromPointer(event);
    latestInputEvent = event;
    cancelPreview();
    if (opts.onPreview) flushPreview();
    if (opts.commitMode !== 'frame') {
      cancelCommit();
      opts.onCommit?.(element.value, event, element);
    }
  };

  const onInput = (event: Event): void => {
    schedulePreview(event);
    scheduleFrameCommit(event);
  };

  const onChange = (event: Event): void => {
    latestInputEvent = event;
    cancelPreview();
    if (opts.onPreview) flushPreview();

    if (opts.commitMode !== 'frame') {
      cancelCommit();
      opts.onCommit?.(element.value, event, element);
    }
  };

  const onKeydown = (event: KeyboardEvent): void => {
    const step = opts.keyboardStep;
    if (step === undefined) return;

    const direction =
      event.key === 'ArrowUp' || event.key === 'ArrowRight'
        ? 1
        : event.key === 'ArrowDown' || event.key === 'ArrowLeft'
          ? -1
          : 0;

    if (direction === 0) return;

    const base =
      finiteNumber(element.value) ??
      finiteNumber(element.getAttribute('value')) ??
      0;
    const amount = event.shiftKey
      ? (opts.keyboardShiftStep ?? step * 10)
      : step;
    const min = finiteNumber(opts.keyboardMin) ?? finiteNumber(element.min);
    const max = finiteNumber(opts.keyboardMax) ?? finiteNumber(element.max);
    let next = base + amount * direction;

    if (min !== null) next = Math.max(min, next);
    if (max !== null) next = Math.min(max, next);

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();

    element.value = trimNumericString(next);
    latestInputEvent = event;
    opts.onPreview?.(element.value, event, element);
    opts.onCommit?.(element.value, event, element);
  };

  element.addEventListener('input', onInput);
  element.addEventListener('change', onChange);
  element.addEventListener('keydown', onKeydown);
  element.addEventListener('pointerdown', beginRangePointer, true);
  element.addEventListener('pointermove', updateRangePointer, true);
  element.addEventListener('pointerup', endRangePointer, true);
  element.addEventListener('pointercancel', endRangePointer, true);
  element.addEventListener('click', stopSurfacePointerRouting, true);
  element.addEventListener('dblclick', stopSurfacePointerRouting, true);

  return () => {
    element.removeEventListener('input', onInput);
    element.removeEventListener('change', onChange);
    element.removeEventListener('keydown', onKeydown);
    element.removeEventListener('pointerdown', beginRangePointer, true);
    element.removeEventListener('pointermove', updateRangePointer, true);
    element.removeEventListener('pointerup', endRangePointer, true);
    element.removeEventListener('pointercancel', endRangePointer, true);
    element.removeEventListener('click', stopSurfacePointerRouting, true);
    element.removeEventListener('dblclick', stopSurfacePointerRouting, true);
    if (priorKeyboardOwner === null) {
      element.removeAttribute('data-surface-keyboard-owner');
    } else {
      element.setAttribute('data-surface-keyboard-owner', priorKeyboardOwner);
    }
    cancelPreview();
    cancelCommit();
  };
});

export default surfaceContinuousInput;
