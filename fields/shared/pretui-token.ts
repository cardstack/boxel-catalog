import { htmlSafe } from '@ember/template';

// Pret UI `Token` sets its text at `--text-body` minus 3.5px, so a Token that
// should read at a given size takes that size plus the same offset. This
// mirrors Token's own offset; it has no size argument of its own.
const TOKEN_TEXT_OFFSET = '3.5px';

/**
 * Inline style for a Pret UI `Token` drawn in `hue` with its text at `size`
 * (a font-size custom property such as `--boxel-font-size-xs`). Token writes
 * `@hue` as its own inline style, which a caller's `style` would replace, so
 * the hue travels in this style instead of through `@hue`.
 */
export function tokenStyle(size: string, hue: string) {
  return htmlSafe(
    `--pretui-token-hue: ${hue}; --text-body: calc(var(${size}) + ${TOKEN_TEXT_OFFSET})`,
  );
}
