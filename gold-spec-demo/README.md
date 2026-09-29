# gold-spec-demo (preview only)

A preview card for checking the Pret UI and theming work on the gold-Spec
building blocks in one place: every block, in every state and format, next to
each other.

- It is a preview, not a building block. It only mounts the real blocks and
  defines none of its own. Lists it iterates (such as the StatePill hues) are
  imported from the owning module, not re-typed.
- Each block has an entry in `BLOCKS` in `gold-spec-demo.gts` (id, label,
  kind, source path). That entry drives the sidebar group (fields, cards,
  components), the section heading, and the link that opens the source file in
  code mode. Adding a block is one `BLOCKS` entry plus its section.
- Remove this folder once the gold-Spec blocks are fully on Pret UI and the
  theming system, and their own Spec examples cover these states.

Contents:

- `gold-spec-demo.gts` + `GoldSpecDemo/all-states.json`: the Gold Spec Demo
  card. Status, Priority, Due Date and Created At in every state (embedded and
  atom), and StatePill in every hue and mode (tinted, dot, emphatic, chrome).
