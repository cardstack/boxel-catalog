import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';

interface UnsetMarkerSignature {
  Args: {
    /** What a screen reader hears in place of the dash, e.g. "No due date". */
    label?: string;
  };
  Element: HTMLSpanElement;
}

/**
 * The muted dash a field or card shows where a value is missing. The dash is
 * decoration, hidden from assistive technology; a visually hidden label says
 * what is missing instead, so a screen reader hears "No due date" rather than
 * "dash" or nothing. The same visible/spoken split Pret UI's formatters use.
 */
export const UnsetMarker: TemplateOnlyComponent<UnsetMarkerSignature> =
  <template>
    <span class='unset-marker' data-test-unset-marker ...attributes><span
        aria-hidden='true'
      >—</span><VisuallyHidden>{{if
          @label
          @label
          'No value'
        }}</VisuallyHidden></span>
    <style scoped>
      .unset-marker {
        color: var(--muted-foreground);
      }
    </style>
  </template>;
