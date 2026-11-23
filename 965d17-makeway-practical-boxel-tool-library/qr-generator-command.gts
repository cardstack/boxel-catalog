import { Command } from '@cardstack/runtime-common';
import { QRGeneratorInput } from './qr-generator-input';
import { QRGeneratorResult } from './qr-generator-result';
export class QRGeneratorCommand extends Command<
  typeof QRGeneratorInput,
  typeof QRGeneratorResult
> {
  static actionVerb = 'Prepare';
  static displayName = 'Prepare QR code';
  async getInputType() {
    return QRGeneratorInput;
  }
  protected async run(input: QRGeneratorInput): Promise<QRGeneratorResult> {
    const value = (input.value ?? '').trim();
    if (!value) throw new Error('Enter a URL or short text to encode.');
    if (value.length > 1800)
      throw new Error(
        'This value is too long for a QR code here. Try a shorter URL or text.',
      );
    return new QRGeneratorResult({ output: value });
  }
}
