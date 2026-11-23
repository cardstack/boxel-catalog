import { Command } from '@cardstack/runtime-common';
import { AspectRatioInput } from './aspect-ratio-input';
import { AspectRatioResult } from './aspect-ratio-result';
function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}
function format(value: number): string {
  return Number.isInteger(value)
    ? String(value)
    : String(Number(value.toFixed(3)));
}
export class AspectRatioCommand extends Command<
  typeof AspectRatioInput,
  typeof AspectRatioResult
> {
  static actionVerb = 'Calculate';
  static displayName = 'Calculate aspect ratio';
  async getInputType() {
    return AspectRatioInput;
  }
  protected async run(input: AspectRatioInput): Promise<AspectRatioResult> {
    const width = Number(input.width),
      height = Number(input.height);
    if (
      !Number.isFinite(width) ||
      width <= 0 ||
      !Number.isFinite(height) ||
      height <= 0
    )
      throw new Error('Enter positive width and height values.');
    const ratio =
      Number.isInteger(width) && Number.isInteger(height)
        ? width / gcd(width, height) + ':' + height / gcd(width, height)
        : format(width) +
          ':' +
          format(height) +
          ' (≈ ' +
          format(width / height) +
          ':1)';
    let fit = '';
    if ((input.targetWidth ?? '').trim() && (input.targetHeight ?? '').trim()) {
      const targetWidth = Number(input.targetWidth),
        targetHeight = Number(input.targetHeight);
      if (
        !Number.isFinite(targetWidth) ||
        targetWidth <= 0 ||
        !Number.isFinite(targetHeight) ||
        targetHeight <= 0
      )
        throw new Error('Target dimensions must be positive numbers.');
      const scale = Math.min(targetWidth / width, targetHeight / height);
      fit =
        String.fromCharCode(10) +
        'Fit inside ' +
        format(targetWidth) +
        ' × ' +
        format(targetHeight) +
        ': ' +
        format(width * scale) +
        ' × ' +
        format(height * scale) +
        ' (no crop).';
    } else if ((input.targetWidth ?? '').trim()) {
      const targetWidth = Number(input.targetWidth);
      if (!Number.isFinite(targetWidth) || targetWidth <= 0)
        throw new Error('Target width must be positive.');
      fit =
        String.fromCharCode(10) +
        'At width ' +
        format(targetWidth) +
        ', height is ' +
        format((targetWidth * height) / width) +
        '.';
    } else if ((input.targetHeight ?? '').trim()) {
      const targetHeight = Number(input.targetHeight);
      if (!Number.isFinite(targetHeight) || targetHeight <= 0)
        throw new Error('Target height must be positive.');
      fit =
        String.fromCharCode(10) +
        'At height ' +
        format(targetHeight) +
        ', width is ' +
        format((targetHeight * width) / height) +
        '.';
    }
    return new AspectRatioResult({
      output:
        'Aspect ratio: ' +
        ratio +
        String.fromCharCode(10) +
        'Original size: ' +
        format(width) +
        ' × ' +
        format(height) +
        fit,
    });
  }
}
