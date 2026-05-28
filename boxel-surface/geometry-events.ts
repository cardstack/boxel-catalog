export const SURFACE_GEOMETRY_CHANGE_EVENT = 'surface:geometrychange';

export function dispatchSurfaceGeometryChange(element: HTMLElement): void {
  element.dispatchEvent(
    new CustomEvent(SURFACE_GEOMETRY_CHANGE_EVENT, {
      bubbles: true,
      composed: true,
    }),
  );
}
