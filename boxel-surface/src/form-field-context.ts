import type { CellValidationState } from './components/surface-component.gts';
import type { IdentityPart } from './components/surface-component.gts';

export const FormFieldContextName = 'boxel-surface:form-field';

export interface FormFieldContext {
  state: CellValidationState;
  layout: 'vertical' | 'horizontal';
  density: 'comfortable' | 'compact';
  surfaceKey?: IdentityPart | IdentityPart[];
  describedBy?: string;
  invalid: boolean;
  disabled?: boolean;
  readonly?: boolean;
  required?: boolean;
}
