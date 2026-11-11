// LayoutControl forms: `minWidth` in rem, richest first.
export const F = (...forms: [string, number][]) =>
  forms.map(([name, minWidth]) => ({ name, minWidth }));
export const SEARCH_FORMS = F(['field', 14], ['menu', 0]);
export const VIEW_FORMS = F(['segments', 12], ['menu', 0]);
/** Stops a pointer press on an inner control from starting a drag. */
export const shield = (e: Event) => e.stopPropagation();
