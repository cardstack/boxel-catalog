// Tamper evidence for attached artefacts.
//
// A hash is recorded when a proof is attached and compared to the artefact's
// current hash later. Storing the comparison as a derived state rather than a
// boolean matters: "unverified" is not "intact". A missing hash on either side
// means nobody has checked, and saying so is the honest render — a green tick
// for an unhashed file would be worse than no tick at all.

export type Integrity = 'intact' | 'changed' | 'unverified';

export const INTEGRITY_LABELS: Record<Integrity, string> = {
  intact: 'intact',
  changed: 'changed',
  unverified: 'unverified',
};

/**
 * Compare the hash recorded at attach time with the artefact's current hash.
 *
 * Both sides must be present to reach a verdict. Comparison is
 * case-insensitive on the hex, so a hash written by a different tool still
 * matches.
 */
export function integrityOf(
  recorded?: string | null,
  current?: string | null,
): Integrity {
  let a = (recorded ?? '').trim().toLowerCase();
  let b = (current ?? '').trim().toLowerCase();
  if (!a || !b) {
    return 'unverified';
  }
  return a === b ? 'intact' : 'changed';
}

/** First 8 hex characters — enough to read in a table, never for comparison. */
export function shortHash(hex?: string | null): string {
  let h = (hex ?? '').trim();
  return h ? `${h.slice(0, 8)}…` : '';
}

const HEX = /^[0-9a-f]{64}$/i;

export function isSha256Hex(value?: string | null): boolean {
  return HEX.test((value ?? '').trim());
}

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * SHA-256 of the artefact's bytes, as lower-case hex.
 *
 * `crypto.subtle` is only present in a secure context, so a caller that may
 * run outside one has to handle the throw rather than silently record nothing
 * — a proof with no hash must read `unverified`, never `intact`.
 */
export async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  let subtle = globalThis.crypto?.subtle;
  if (!subtle) {
    throw new Error(
      'SHA-256 unavailable: crypto.subtle needs a secure context',
    );
  }
  return toHex(await subtle.digest('SHA-256', bytes));
}
