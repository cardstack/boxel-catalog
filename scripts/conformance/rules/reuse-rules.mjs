// S13 reuse-inventory rule table. Every rule emits WARNINGS — the factory's
// conform step requires each finding to be fixed or waived with a reason.
// Detectors receive { template, styles } (one format's template text + its
// style blocks joined) and return true when the hand-rolled pattern is present.

const UI = '@cardstack/boxel-ui/components';

function styleDeclCount(styles, selectorHint, props) {
  // crude: if any rule block mentions the hint (or hint is null), count how many
  // of the given properties appear anywhere in the styles.
  if (selectorHint && !new RegExp(selectorHint, 'i').test(styles)) return 0;
  return props.filter((p) => new RegExp(`(^|[^-a-z])${p}\\s*:`, 'i').test(styles)).length;
}

export const reuseRules = [
  {
    id: 'reuse/hand-rolled-button',
    detect: ({ template, styles }) =>
      /<button\b/i.test(template) &&
      styleDeclCount(styles, 'button|btn', ['background', 'border', 'border-radius', 'padding']) >= 3,
    message: 'Hand-rolled <button> with heavy custom chrome',
    suggestion: `Use Button (or IconButton) from ${UI}`,
  },
  {
    id: 'reuse/hand-rolled-select',
    detect: ({ template }) => /<select\b/i.test(template),
    message: 'Raw <select> element',
    suggestion: `Use BoxelSelect from ${UI}`,
  },
  {
    id: 'reuse/hand-rolled-input',
    formats: ['isolated', 'embedded', 'fitted', 'atom'],
    detect: ({ template }) => /<(input|textarea)\b/i.test(template),
    message: 'Raw <input>/<textarea> outside an edit template',
    suggestion: `Use BoxelInput from ${UI} (and prefer @fields.x in edit format)`,
  },
  {
    id: 'reuse/hand-rolled-pill',
    detect: ({ template, styles }) =>
      /class=['"][^'"]*\b(pill|badge|chip)\b/i.test(template) &&
      /border-radius\s*:\s*(999px|100px|9999px|2em|50px|calc\(infinity)/i.test(styles),
    message: 'Hand-rolled pill/badge/chip',
    suggestion: `Use Pill from ${UI}`,
  },
  {
    id: 'reuse/hand-rolled-modal',
    detect: ({ template, styles }) =>
      /<dialog\b/i.test(template) ||
      (/\b(modal|overlay)\b/i.test(template) && /position\s*:\s*fixed/i.test(styles)),
    message: 'Hand-rolled modal/overlay (position:fixed also breaks the card bounding box)',
    suggestion: `Use Modal from ${UI}; never position:fixed inside a card`,
  },
  {
    id: 'reuse/hand-rolled-progress',
    detect: ({ template, styles }) =>
      /\bprogress\b/i.test(template) && /width\s*:\s*(\{\{|calc|[0-9.]+%)/i.test(styles),
    message: 'Hand-rolled progress bar',
    suggestion: `Use ProgressBar or ProgressRadial from ${UI}`,
  },
  {
    id: 'reuse/hand-rolled-tabs',
    detect: ({ template }) => /role=['"]tab['"]/i.test(template),
    message: 'Hand-rolled tab strip',
    suggestion: `Use TabbedHeader (or ViewSelector) from ${UI}`,
  },
  {
    id: 'reuse/hand-rolled-avatar',
    detect: ({ template, styles }) =>
      /\bavatar\b/i.test(template) && /border-radius\s*:\s*50%/i.test(styles),
    message: 'Hand-rolled avatar',
    suggestion: `Use Avatar from ${UI}`,
  },
  {
    id: 'reuse/hand-rolled-card-frame',
    detect: ({ styles }) =>
      styleDeclCount(styles, 'card|container|frame|wrapper', ['border-radius', 'box-shadow', 'border']) >= 3,
    message: 'Outermost wrapper re-implements card container chrome',
    suggestion: `Use CardContainer from ${UI} (or rely on the host-injected container)`,
  },
];
