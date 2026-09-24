export function diffLabel(level: number | null | undefined): string {
  if (!level) return 'UNKNOWN';
  if (level === 1) return 'SUPER EASY';
  if (level <= 4) return 'EASY';
  if (level <= 7) return 'INTERMEDIATE';
  return 'EXPERT';
}

export function diffClass(level: number | null | undefined): string {
  if (!level) return 'diff-unknown';
  if (level === 1) return 'diff-super-easy';
  if (level <= 4) return 'diff-easy';
  if (level <= 7) return 'diff-intermediate';
  return 'diff-expert';
}
