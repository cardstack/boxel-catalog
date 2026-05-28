import type { CellValidationState } from './components/surface-component.gts';

export type FormMode = 'edit' | 'view' | 'create';

export type ResolvedFormFieldKind = 'text' | 'email' | 'number' | 'boolean';

export type ResolvedFormModel = object | null | undefined;

export interface ResolvedFormField {
  key: string;
  label: string;
  kind: ResolvedFormFieldKind;
  required?: boolean;
  optional?: boolean;
  helperText?: string;
  errorMessage?: string;
  state?: CellValidationState;
  disabled?: boolean;
  readonly?: boolean;
  placeholder?: string;
  multiline?: boolean;
  inputType?: 'text' | 'tel' | 'url' | 'search';
  autocomplete?: string;
  prefix?: string;
  suffix?: string;
  min?: number;
  max?: number;
  step?: number | string;
  description?: string;
  value?: unknown;
  onInput?: (value: string) => void;
  onChange?: (value: boolean) => void;
}

export type ResolvedFormFieldInput = Omit<
  ResolvedFormField,
  'kind' | 'label'
> & {
  kind?: ResolvedFormFieldKind;
  label?: string;
};

export function labelForFieldKey(key: string): string {
  return key
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[-_]+/g, ' ')
    .replace(/\b\w/g, (match) => match.toUpperCase());
}

export function resolveFormFields(
  fields: readonly ResolvedFormFieldInput[] | undefined,
  labelFor: (key: string) => string = labelForFieldKey,
): readonly ResolvedFormField[] {
  return (fields ?? []).map((field) => ({
    ...field,
    kind: field.kind ?? 'text',
    label: field.label ?? labelFor(field.key),
  }));
}

export function readResolvedFormFieldValue(
  field: ResolvedFormField,
  model: ResolvedFormModel,
): unknown {
  if ('value' in field) return field.value;
  if (!isModelRecord(model)) return undefined;
  return model[field.key];
}

export function writeResolvedFormFieldValue(
  field: ResolvedFormField,
  model: ResolvedFormModel,
  value: unknown,
): void {
  if (!isModelRecord(model)) return;
  model[field.key] = value;
}

function isModelRecord(
  model: ResolvedFormModel,
): model is Record<string, unknown> {
  return typeof model === 'object' && model !== null;
}
