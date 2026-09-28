// The shared "is this a real date" check, so every date field treats a
// missing value and an Invalid Date the same way: both render as unset.

/** The value when it is a Date that holds a real instant; otherwise undefined. */
export function validDate(value: Date | null | undefined): Date | undefined {
  return value && !Number.isNaN(value.getTime()) ? value : undefined;
}
