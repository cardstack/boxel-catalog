// Shared taxonomy metadata for the catalog storefront: maps each Listing
// subtype to its display label, the tab/query id, and the CSS custom property
// that carries its signal color (defined on the catalog root in catalog.gts).

export interface ListingTypeMeta {
  key: string; // tab id used by queries: card | field | skill | component | theme | app
  label: string; // singular human label shown in chips
  plural: string; // plural label shown in nav/pills
  colorVar: string; // css var holding the type's signal color
}

const BY_DISPLAY_NAME: Record<string, ListingTypeMeta> = {
  CardListing: {
    key: 'card',
    label: 'Card',
    plural: 'Cards',
    colorVar: '--type-card',
  },
  ComponentListing: {
    key: 'component',
    label: 'Component',
    plural: 'Components',
    colorVar: '--type-component',
  },
  FieldListing: {
    key: 'field',
    label: 'Field',
    plural: 'Fields',
    colorVar: '--type-field',
  },
  SkillListing: {
    key: 'skill',
    label: 'Skill',
    plural: 'Skills',
    colorVar: '--type-skill',
  },
  ThemeListing: {
    key: 'theme',
    label: 'Theme',
    plural: 'Themes',
    colorVar: '--type-theme',
  },
  AppListing: {
    key: 'app',
    label: 'App',
    plural: 'Apps',
    colorVar: '--type-app',
  },
  Listing: {
    key: 'app',
    label: 'App',
    plural: 'Apps',
    colorVar: '--type-app',
  },
};

const FALLBACK: ListingTypeMeta = {
  key: 'app',
  label: 'App',
  plural: 'Apps',
  colorVar: '--type-app',
};

// The pill row order on the storefront (App is implicit under "All", not a pill).
export const PILL_TYPE_KEYS = [
  'card',
  'component',
  'field',
  'skill',
  'theme',
] as const;

export function typeMetaForDisplayName(
  displayName: string | undefined,
): ListingTypeMeta {
  return (displayName && BY_DISPLAY_NAME[displayName]) || FALLBACK;
}

export function typeMetaForKey(key: string): ListingTypeMeta {
  return Object.values(BY_DISPLAY_NAME).find((m) => m.key === key) || FALLBACK;
}
