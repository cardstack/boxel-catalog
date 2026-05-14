export function formatCurrency(val: number | undefined, cc = 'USD') {
  if (val === undefined || !Number.isFinite(val)) return '';
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: cc,
  }).format(val);
}

export function formatCurrencyShort(val: number | undefined, cc = 'USD') {
  if (val === undefined || !Number.isFinite(val)) return '';

  const symbol =
    new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: cc,
      maximumFractionDigits: 0,
    })
      .formatToParts(0)
      .find((p) => p.type === 'currency')?.value ?? cc;

  const sep = symbol.length > 1 ? ' ' : '';

  if (Math.abs(val) >= 1_000_000)
    return `${symbol}${sep}${(val / 1_000_000).toFixed(1)}M`;

  if (Math.abs(val) >= 1_000)
    return `${symbol}${sep}${Math.round(val / 1_000)}k`;

  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: cc,
    maximumFractionDigits: 0,
  }).format(val);
}

export function svgPieStartAngle({
  data,
  index,
  total,
  start = 0,
}: {
  data: { value?: number }[];
  index: number;
  total: number;
  start?: number;
}) {
  return data.slice(0, index).reduce((sum, item) => {
    const angle = ((item.value || 0) / total) * 360 || 0;
    return sum + angle;
  }, start);
}
