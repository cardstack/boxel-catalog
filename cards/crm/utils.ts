/** "$12,000.00" from an amount and an ISO 4217 code; a bare number when the code is missing or unknown. */
export function formatMoney(amount: number | undefined, code?: string): string {
  if (amount === undefined || !Number.isFinite(amount)) return '';
  if (code) {
    try {
      return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: code,
      }).format(amount);
    } catch {
      /* unknown code: fall through to the plain number */
    }
  }
  return new Intl.NumberFormat('en-US', {
    maximumFractionDigits: 2,
  }).format(amount);
}
