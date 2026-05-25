import type { ImageSourceMode } from '../image-source';

export function selectedSourceMode(
  sourceMode: string | null | undefined,
  url: string | null | undefined,
): ImageSourceMode {
  if (sourceMode === 'url') {
    return 'url';
  }
  if (sourceMode === 'file') {
    return 'file';
  }
  return url ? 'url' : 'file';
}
