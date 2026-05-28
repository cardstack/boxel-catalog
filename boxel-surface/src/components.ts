// Public component barrel, shaped like Boxel UI's addon-level components entry.

export {
  SurfaceComponent,
  SurfaceComponent as AbstractFoundation,
  Environment,
  Layout,
  Canvas,
  Scene,
  Grid,
  Row,
  Scroll,
  Flow,
  Frame,
  Pane,
  Plane,
  Outline,
  Cell,
  Run,
  Unit,
  nextSurfaceId,
  surfaceFocusKey,
  surfaceFocusKeyFromPath,
  surfaceId,
  surfaceIdFromPath,
  LadderContextName,
  ParentIdContextName,
  ParentContextName,
  DemoContextName,
  ModeContextName,
  InspectContextName,
  ChangeRouteContextName,
  CoordinateSpaceContextName,
  PathContextName,
} from './components/surface-component.gts';
export type {
  SurfaceComponentSignature,
  SurfaceComponentSignature as FoundationSignature,
  EnvironmentSignature,
  ChangeInput,
  ChangePreference,
  ChangeRoute,
  CoordinateSpaceContext,
  CoordinateSpace,
  DemoMode,
  Identity,
  IdentityPart,
  KeyboardMode,
  LocalCoordinate,
  Mode,
  Posture,
  Path,
  Role,
  DirectiveScope,
} from './components/surface-component.gts';

export {
  CueDescription,
  CueLabel,
  CueStatus,
  Accessory,
} from './components/accessory.gts';
export type {
  AccessoryAliasSignature,
  AccessoryKind,
  AccessoryPosition,
  AccessorySignature,
  AccessoryTone,
} from './components/accessory.gts';

export { default as Lift } from './components/lift.gts';
export type { LiftSignature } from './components/lift.gts';

export { default as LiftChevron } from './components/lift-chevron.gts';
export type { LiftChevronSignature } from './components/lift-chevron.gts';

/** @deprecated Use `Cell`. Removed in v3. */
export { Cell as FieldCell } from './components/surface-component.gts';
export type {
  CellSignature,
  CellSignature as FieldCellSignature,
  CellState,
  CellSurface,
  CellSurface as FieldCellSurface,
  CellValidationState,
} from './components/surface-component.gts';

export { default as Form } from './components/form.gts';
export type { FormSignature } from './components/form.gts';

export { default as FormField } from './components/form-field.gts';
export type { FormFieldSignature } from './components/form-field.gts';

export { default as FormSection } from './components/form-section.gts';
export type { FormSectionSignature } from './components/form-section.gts';

export { default as FormTab } from './components/form-tab.gts';
export type { FormTabSignature } from './components/form-tab.gts';

export { default as FormTabs } from './components/form-tabs.gts';
export type { FormTabsSignature } from './components/form-tabs.gts';

export { default as FormStep } from './components/form-step.gts';
export type { FormStepSignature } from './components/form-step.gts';

export { default as FormWizard } from './components/form-wizard.gts';
export type { FormWizardSignature } from './components/form-wizard.gts';

export { default as FormAlert } from './components/form-alert.gts';
export type {
  FormAlertSeverity,
  FormAlertSignature,
} from './components/form-alert.gts';

export { default as TextCell } from './components/text-cell.gts';
export type { TextCellSignature } from './components/text-cell.gts';

export { default as EmailCell } from './components/email-cell.gts';
export type { EmailCellSignature } from './components/email-cell.gts';

export { default as NumberCell } from './components/number-cell.gts';
export type { NumberCellSignature } from './components/number-cell.gts';

export { default as SwitchCell } from './components/switch-cell.gts';
export type { SwitchCellSignature } from './components/switch-cell.gts';

export {
  labelForFieldKey,
  readResolvedFormFieldValue,
  resolveFormFields,
  writeResolvedFormFieldValue,
} from './form-field-resolution.ts';
export type {
  FormMode,
  ResolvedFormField,
  ResolvedFormFieldInput,
  ResolvedFormFieldKind,
  ResolvedFormModel,
} from './form-field-resolution.ts';
