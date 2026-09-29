# gold-spec-demo (preview only)

One preview page per gold-Spec card cluster, for checking the Pret UI and
theming work by eye: each card in the cluster, in every format, next to each
other.

- Each cluster is one `GoldSpecCardGroup/<cluster>.json`: a title and links to
  one existing example of each card in the cluster. A cluster PR adds only its
  own JSON, so cluster PRs never conflict here.
- The page (`gold-spec-card-group.gts`) lists the cluster's cards in a sidebar.
  Each card's section shows its title and type, its instance path and source
  path (both open in code mode), and the card fitted at four sizes, embedded,
  atom and isolated. Fields and components show through the cards that use
  them.
- It is a preview, not a building block: it only renders the linked examples
  and never writes to them.
- Remove this folder once the gold-Spec blocks are fully on Pret UI and the
  theming system, and their own Spec examples cover these states.

Contents:

- `gold-spec-card-group.gts`: the Gold Spec Card Group card and its page.
- `demo-parts.gts`: the page shell, file links and card formats it uses.
- `GoldSpecCardGroup/crm.json`: Account, Campaign, Contact, Lead, Opportunity
  and User from `cards/crm/`.
