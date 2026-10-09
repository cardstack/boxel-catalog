// Shared helpers for the file-metadata and records block families.
//
// These live here rather than inside one module because several blocks need
// them, and a copy in each is how a realm ends up with two byte formatters
// that disagree about whether 1 KB is 1000 or 1024 bytes, or two duration
// formatters that disagree about whether to floor or round — quietly, until
// one column shows 4:59 where another shows 5:00 for the same value.

// ── Bytes ───────────────────────────────────────────────────────────────────

// Binary units (KiB semantics) shown with the familiar KB/MB labels, which is
// what every file manager does. Deliberately NOT `toLocaleString` — the unit
// suffix has to be stable for test assertions and for a fitted cell's width
// budget.
const BYTE_UNITS = ['B', 'KB', 'MB', 'GB', 'TB'] as const;

export function formatBytes(bytes?: number | null): string {
  if (bytes == null || !Number.isFinite(bytes) || bytes < 0) {
    return '';
  }
  if (bytes === 0) {
    return '0 B';
  }
  let exponent = Math.min(
    Math.floor(Math.log(bytes) / Math.log(1024)),
    BYTE_UNITS.length - 1,
  );
  let value = bytes / Math.pow(1024, exponent);
  // Whole bytes never show a decimal; everything else shows one, so a column
  // of sizes stays the same width.
  let digits = exponent === 0 ? 0 : value >= 100 ? 0 : 1;
  return `${value.toFixed(digits)} ${BYTE_UNITS[exponent]}`;
}

// ── Licences ────────────────────────────────────────────────────────────────

// The SPDX identifiers worth recognising by name, with a display label and the
// canonical URL. Anything not listed still stores fine as a free string — this
// is a lookup for presentation, never a validation gate, because a licence the
// registry has not heard of is a real licence, not an error.
export interface LicenseInfo {
  id: string;
  label: string;
  url: string;
  // Does the licence permit commercial reuse without further permission? The
  // one fact a reader actually scans for.
  permissive: boolean;
}

export const LICENSES: LicenseInfo[] = [
  {
    id: 'CC0-1.0',
    label: 'CC0 1.0 (public domain)',
    url: 'https://creativecommons.org/publicdomain/zero/1.0/',
    permissive: true,
  },
  {
    id: 'CC-BY-4.0',
    label: 'CC BY 4.0',
    url: 'https://creativecommons.org/licenses/by/4.0/',
    permissive: true,
  },
  {
    id: 'CC-BY-SA-4.0',
    label: 'CC BY-SA 4.0',
    url: 'https://creativecommons.org/licenses/by-sa/4.0/',
    permissive: true,
  },
  {
    id: 'CC-BY-NC-4.0',
    label: 'CC BY-NC 4.0 (non-commercial)',
    url: 'https://creativecommons.org/licenses/by-nc/4.0/',
    permissive: false,
  },
  {
    id: 'MIT',
    label: 'MIT',
    url: 'https://opensource.org/license/mit',
    permissive: true,
  },
  {
    id: 'Apache-2.0',
    label: 'Apache 2.0',
    url: 'https://www.apache.org/licenses/LICENSE-2.0',
    permissive: true,
  },
  {
    id: 'GPL-3.0-only',
    label: 'GPL 3.0',
    url: 'https://www.gnu.org/licenses/gpl-3.0.html',
    permissive: true,
  },
  {
    id: 'proprietary',
    label: 'Proprietary — all rights reserved',
    url: '',
    permissive: false,
  },
];

export function licenseInfo(id?: string | null): LicenseInfo | undefined {
  if (!id) {
    return undefined;
  }
  let needle = id.trim().toLowerCase();
  return LICENSES.find((l) => l.id.toLowerCase() === needle);
}

// The registry's label when recognised, otherwise the raw value — so an
// unrecognised SPDX id still reads sensibly instead of rendering blank.
export function licenseLabel(id?: string | null): string {
  if (!id) {
    return '';
  }
  return licenseInfo(id)?.label ?? id;
}

// ── Names and durations ─────────────────────────────────────────────────────

// Join names for display, truncated after `max` with a "+N more" tail — the
// shape every contributor row wants.
export function joinNames(names: string[] | undefined, max = 3): string {
  let list = (names ?? []).filter(Boolean);
  if (list.length === 0) {
    return '';
  }
  if (list.length <= max) {
    return list.join(', ');
  }
  return `${list.slice(0, max).join(', ')} +${list.length - max} more`;
}

// m:ss. Returns '' rather than '0:00' for an absent value — a duration that
// was never measured and a zero-length one are different facts, and only one
// of them should render as a time.
export function formatDuration(seconds?: number | null): string {
  if (seconds == null || !Number.isFinite(seconds) || seconds < 0) {
    return '';
  }
  let total = Math.floor(seconds);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
}
