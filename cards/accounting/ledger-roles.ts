// The books' roles, expressed as rules of the realm policy the books' realm names: for each role, the
// named operations it may invoke on each card type, each grant naming the users who hold the role.
//
// A policy grants an operation on its own; it can't grant one only inside the batch that keeps the
// books whole. So a role is granted only operations that are safe called alone with any parameters:
// they enter or edit drafts, which change no balance, status or journal until a writer posts them.
// Posting, settling, voiding, journaling, stock draws and closes belong to the realm's writers (its
// Admins and Accountants), whom only the realm's permissions make. A policy only widens what those
// permissions allow, so every role reads the books through the realm's read permission.

export type RoleId =
  | 'standard'
  | 'limited-sales'
  | 'limited-purchases'
  | 'reports-only';

/** The card types the grants name, by the module file they live in. */
type Grants = Record<string, Record<string, string[]>>; // file -> type -> operations

const REPORTS: Grants = { 'ledger-cards': { Ledger: ['saveReport'] } };
// Each creates a draft, or edits a draft and refuses anything else.
const SALES: Grants = {
  'ledger-cards': { Ledger: ['saveReport'] },
  'ledger-sales': {
    Customer: [
      'enterInvoice',
      'enterInvoiceOnTerms',
      'enterSalesReceipt',
      'enterRefundReceipt',
      'invoiceFromQuote',
      'receivePayment',
    ],
    Invoice: ['addLines', 'useCurrency', 'useTaxCode', 'calculateTax'],
    SalesReceipt: ['addLines', 'useTaxCode', 'calculateTax'],
    RefundReceipt: ['useTaxCode', 'calculateTax'],
  },
};
const PURCHASES: Grants = {
  'ledger-cards': {
    Ledger: [
      'saveReport',
      'enterBill',
      'enterBillOnTerms',
      'billFromPurchaseOrder',
      'enterPayment',
      'enterVendorCredit',
    ],
    Bill: ['useCurrency'],
  },
};
const OTHER_DRAFTS: Grants = {
  'ledger-cards': {
    Ledger: [
      'enterDeposit',
      'enterTransfer',
      'enterBankPayment',
      'enterTaxPayment',
      'enterPayroll',
      'enterTime',
      'enterLoanPayment',
      'enterCardCharge',
      'enterRoast',
      'enterFulfillment',
      'enterCount',
      'enterLanded',
      'enterJournal',
      'enterScheduled',
      'enterDepreciation',
      'enterDisposal',
    ],
  },
  'ledger-sales': { Invoice: ['enterCredit', 'enterWriteOff'] },
  'ledger-close': {
    MonthClose: ['reconcile'],
    BankReconciliation: ['record'],
  },
};

const merge = (...gs: Grants[]): Grants => {
  let out: Grants = {};
  for (let g of gs)
    for (let [file, types] of Object.entries(g))
      for (let [type, ops] of Object.entries(types)) {
        let t = ((out[file] ??= {})[type] ??= []);
        for (let op of ops) if (!t.includes(op)) t.push(op);
      }
  return out;
};

export interface RoleDef {
  id: RoleId;
  label: string;
  summary: string;
  grants: Grants;
}
export const ROLES: RoleDef[] = [
  {
    id: 'standard',
    label: 'Standard',
    summary:
      'Enters and edits drafts of every kind: sales, purchases, payments, payroll, journal entries and reconciliations, and records time entries, which show in unbilled time straight away. A writer of the realm posts the drafts.',
    grants: merge(SALES, PURCHASES, OTHER_DRAFTS),
  },
  {
    id: 'limited-sales',
    label: 'Limited · customers and sales',
    summary:
      'Enters and edits sales drafts: invoices, receipts, refunds and payments received. A writer of the realm posts them.',
    grants: SALES,
  },
  {
    id: 'limited-purchases',
    label: 'Limited · vendors and purchases',
    summary:
      'Enters and edits purchase drafts: bills, bill payments and vendor credits. A writer of the realm posts them.',
    grants: PURCHASES,
  },
  {
    id: 'reports-only',
    label: 'Reports only',
    summary: 'Reads the books, runs reports and saves its own.',
    grants: REPORTS,
  },
];
export const roleById = new Map(ROLES.map((r) => [r.id, r]));
/** What the realm's writers do that no role here can. */
export const WRITERS_SUMMARY =
  "Writers of the realm (Admins and Accountants): post, settle, void, journal and close, and change users and settings. The realm's permissions make them, not this page.";

export interface PolicyGrant {
  operation: string;
  where?: string | { bxl: string; snapshot: true };
  // The grant's other settings, carried through a role change unchanged.
  [setting: string]: unknown;
}
export interface PolicyRuleJSON {
  targetType: { module: string; name: string };
  grants: PolicyGrant[];
}

/** The predicate that names one user. */
export const names = (user: string) => `actor() == ${JSON.stringify(user)}`;
const NAMED = /^actor\(\) == ("(?:[^"\\]|\\.)*")$/;
const SAVER =
  /^\(\.savedBy == ("(?:[^"\\]|\\.)*")\) and \(actor\(\) == ("(?:[^"\\]|\\.)*")\)$/;
// Any user id written in a predicate: a quoted Matrix id.
const USER_ID = /"(@[^"\\]+)"/g;

/** A grant's predicate as text, in either the string or the snapshot form. */
export const predicateText = (where: unknown): string =>
  typeof where === 'string'
    ? where
    : typeof (where as { bxl?: unknown })?.bxl === 'string'
      ? (where as { bxl: string }).bxl
      : '';
/** The user a grant's predicate names, if it is one of the forms the roles write. */
export function userNamed(where: unknown): string | undefined {
  let text = predicateText(where);
  let m = NAMED.exec(text);
  if (m) return JSON.parse(m[1]) as string;
  let s = SAVER.exec(text);
  return s && s[1] === s[2] ? (JSON.parse(s[2]) as string) : undefined;
}
/** Every user id a grant's predicate mentions, whatever its shape. */
export const usersMentioned = (where: unknown): string[] => [
  ...new Set(
    [...predicateText(where).matchAll(USER_ID)].map((m) => m[1] as string),
  ),
];

/**
 * The policy's rules for these users and their roles: one rule per card type, each grant naming a user
 * who may invoke it. `moduleOf` turns a module file in this folder into the module the rule names.
 */
export function rolePolicyRules(
  members: { user: string; role: RoleId }[],
  moduleOf: (file: string) => string,
): PolicyRuleJSON[] {
  let rules = new Map<string, PolicyRuleJSON>();
  let ruleFor = (file: string, type: string) => {
    let key = `${file}#${type}`;
    let r = rules.get(key);
    if (!r) {
      r = { targetType: { module: moduleOf(file), name: type }, grants: [] };
      rules.set(key, r);
    }
    return r;
  };
  let sorted = [...members].sort((a, b) => a.user.localeCompare(b.user));
  for (let { user, role } of sorted) {
    let def = roleById.get(role);
    if (!def) continue;
    for (let [file, types] of Object.entries(def.grants))
      for (let [type, ops] of Object.entries(types))
        for (let op of ops)
          ruleFor(file, type).grants.push({
            operation: op,
            where: names(user),
          });
    // Anyone with a role may delete a report they saved.
    ruleFor('ledger-saved-report', 'SavedReport').grants.push({
      operation: 'delete',
      where: `(.savedBy == ${JSON.stringify(user)}) and (${names(user)})`,
    });
  }
  return [...rules.values()];
}

type RuleLike = {
  targetType?: { module?: string; name?: string } | null;
  grants?: ({ operation?: string | null; where?: unknown } | null)[] | null;
};
// A rule's type as module file and name, so two types of one name in different modules stay apart.
const typeKey = (r: RuleLike) =>
  `${(r.targetType?.module ?? '').split('/').pop()}:${r.targetType?.name ?? ''}`;

/**
 * Each user a policy's grants name: the operations their role-shaped grants give them, keyed by
 * module, type and operation, and whether any other grant names them too.
 */
export function grantsByUser(
  rules: RuleLike[],
): Map<string, { ops: Set<string>; other: boolean }> {
  let out = new Map<string, { ops: Set<string>; other: boolean }>();
  let entry = (u: string) => {
    let e = out.get(u) ?? { ops: new Set<string>(), other: false };
    out.set(u, e);
    return e;
  };
  for (let r of rules ?? [])
    for (let g of r?.grants ?? []) {
      if (!g?.operation) continue;
      let user = userNamed(g.where);
      if (user) entry(user).ops.add(`${typeKey(r)}.${g.operation}`);
      else for (let u of usersMentioned(g.where)) entry(u).other = true;
    }
  return out;
}

/** The operations a role's grants name, as "Type.operation". */
export function roleOperations(role: RoleId): Set<string> {
  let ops = grantsByUser(rolePolicyRules([{ user: '@x', role }], (f) => f)).get(
    '@x',
  )?.ops;
  return new Set([...(ops ?? [])].map((k) => k.slice(k.indexOf(':') + 1)));
}

/** Each user a policy names, with the role their grants are exactly, or 'custom'. */
export function membersOf(
  rules: RuleLike[],
  moduleOf: (file: string) => string = (f) => f,
): { user: string; role: RoleId | 'custom' }[] {
  let signatures = ROLES.map((r) => ({
    id: r.id,
    ops: grantsByUser(
      rolePolicyRules([{ user: '@x', role: r.id }], moduleOf),
    ).get('@x')!.ops,
  }));
  let same = (a: Set<string>, b: Set<string>) =>
    a.size === b.size && [...a].every((x) => b.has(x));
  return [...grantsByUser(rules)]
    .map(([user, { ops, other }]) => ({
      user,
      role: other
        ? ('custom' as const)
        : (signatures.find((s) => same(s.ops, ops))?.id ?? ('custom' as const)),
    }))
    .sort((a, b) => a.user.localeCompare(b.user));
}
