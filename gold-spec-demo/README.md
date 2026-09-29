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
  section; cards come from the linked card groups instead.
- Remove this folder once the gold-Spec blocks are fully on Pret UI and the
  theming system, and their own Spec examples cover these states.

Contents:

- `gold-spec-demo.gts` + `GoldSpecDemo/all-states.json`: the Gold Spec Demo
  card. Status, Priority, Due Date and Created At in every state (embedded and
  atom), StatePill in every hue and mode (tinted, dot, emphatic, chrome), and
  the linked card clusters.
- `gold-spec-card-group.gts` + `GoldSpecCardGroup/<cluster>.json`: one Gold
  Spec Card Group per card cluster, a title and links to one existing example
  of each card in it. `GoldSpecCardGroup/crm.json` links Account, Campaign,
  Contact, Lead, Opportunity and User from `cards/crm/`. The sidebar's Cards
  group picks a cluster (Pret UI FilterChips) and lists its cards; each card's
  section renders it fitted at four sizes, embedded, atom and isolated, with a
  source link read off the card's own class. Adding a cluster is one new group
  instance linked from `GoldSpecDemo/all-states.json`, with no code change.
  The linked examples are only rendered, never written.
