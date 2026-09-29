# gold-spec-demo (preview only)

A preview card for checking the Pret UI and theming work on the gold-Spec
building blocks in one place: every block, in every state and format, next to
each other.

- It is a preview, not a building block. It only mounts the real blocks and
  defines none of its own. Lists it iterates (such as the StatePill hues) are
  imported from the owning module, not re-typed.
- Each block has an entry in `BLOCKS` in `gold-spec-demo.gts` (id, label,
  kind, source path). That entry drives the sidebar group (fields and
  components), the section heading, and the link that opens the source file in
  code mode. Adding a field or component is one `BLOCKS` entry plus its
  section.
- Cards never go in the Gold Spec Demo. Each card cluster has its own
  standalone page, so card PRs only add a cluster JSON and never conflict on
  the demo.
- Remove this folder once the gold-Spec blocks are fully on Pret UI and the
  theming system, and their own Spec examples cover these states.

Contents:

- `gold-spec-demo.gts` + `GoldSpecDemo/all-states.json`: the Gold Spec Demo
  card, fields and components only. Status, Priority, Due Date and Created At
  in every state (embedded and atom), and StatePill in every hue and mode
  (tinted, dot, emphatic, chrome).
- `gold-spec-card-group.gts` + `GoldSpecCardGroup/<cluster>.json`: one
  standalone page per card cluster, with a title and links to one existing
  example of each card in it. `GoldSpecCardGroup/crm.json` links Account,
  Campaign, Contact, Lead, Opportunity and User from `cards/crm/`. Each card's
  section shows its title and type, its instance path and source path (both
  open in code mode), and the card fitted at four sizes, embedded, atom and
  isolated. Adding a cluster is one new JSON, with no code change. The linked
  examples are only rendered, never written.
- `demo-parts.gts`: the pieces both pages share (page shell, source link,
  section heading, card formats).
