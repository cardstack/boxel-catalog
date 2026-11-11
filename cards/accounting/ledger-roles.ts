// The books' roles, as QuickBooks has them, expressed as rules of the realm policy the books' realm
// names: for each role, the named operations it may invoke on each card type, each grant naming the
// users who hold the role. A policy only widens what the realm's permissions allow, so every role
// reads the books through the realm's read permission. Admin is no role here: it is being a writer of
// the realm, which only the realm's permissions grant, and only a writer can change the policy (the
// users), the realm's settings, or close and reopen a month. No role is granted a raw `update` of a
// document, which would let it write the fields only the posting operations may write.

export type RoleId =
  | 'accountant'
  | 'standard'
  | 'limited-sales'
  | 'limited-purchases'
  | 'reports-only';

/** The card types the grants name, by the module file they live in. */
type Grants = Record<string, Record<string, string[]>>; // file -> type -> operations

const SALES: Grants = {
  'ledger-cards': { Ledger: ['saveReport'] },
  'ledger-sales': {
    Customer: [
      'update',
      'enterInvoice',
      'enterInvoiceOnTerms',
      'enterSalesReceipt',
      'enterRefundReceipt',
      'invoiceFromQuote',
      'receivePayment',
    ],
    Invoice: [
      'post',
      'addLines',
      'removeTimeLine',
      'useCurrency',
      'useTaxCode',
      'calculateTax',
      'applyPayment',
      'applyCredit',
      'unapplyPayment',
      'unapplyCredit',
      'enterCredit',
    ],
    CustomerPayment: ['post', 'journal', 'markDeposited', 'unmarkDeposited'],
    SalesReceipt: [
      'post',
      'journal',
      'useTaxCode',
      'calculateTax',
      'addLines',
      'markDeposited',
      'unmarkDeposited',
    ],
    RefundReceipt: ['post', 'journal', 'useTaxCode', 'calculateTax'],
    CreditMemo: ['post', 'journal'],
  },
  'ledger-registers': { TaxAgency: ['checkOpen'] },
  'ledger-time': { TimeActivity: ['markBilled', 'unmarkBilled'] },
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
    Bill: [
      'post',
      'useCurrency',
      'applyPayment',
      'unapplyPayment',
      'receiveLot',
    ],
  },
  'ledger-payments': { BillPayment: ['post', 'journal'] },
  'ledger-cash': { VendorCredit: ['post', 'journal'] },
  'ledger-vendor': { Vendor: ['update'] },
  'ledger-stock': { StockLot: ['draw', 'restore'] },
};
// Posting a document into books kept in a journal appends its entry with JournalMonth.post, which
// takes the entry's lines from the caller: whoever may invoke it may post any balanced entry.
const JOURNAL: Grants = { 'ledger-journal': { JournalMonth: ['post'] } };
const OPERATIONS: Grants = {
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
      'enterBankLine',
      'enterBankImport',
      'enterRoast',
      'enterFulfillment',
      'enterCount',
      'enterLanded',
    ],
  },
  'ledger-sales': { Invoice: ['void'], Deposit: ['post', 'journal'] },
  'ledger-cash': {
    Transfer: ['post', 'journal'],
    BankPayment: ['post', 'journal'],
    CardCharge: ['post', 'journal'],
    LoanPayment: ['post', 'journal'],
    PayrollRun: ['post', 'journal'],
  },
  'ledger-bank': {
    BankTransaction: ['add', 'match', 'unmatch', 'exclude', 'restore'],
  },
  'ledger-close': { BankReconciliation: ['record', 'finish'] },
  'ledger-stock': {
    RoastBatch: ['post', 'journal', 'produceLot'],
    Fulfillment: ['post', 'journal', 'useDraws'],
    CountAdjustment: ['post', 'journal', 'useDraws'],
    LandedCost: ['post', 'journal'],
    StockLot: ['addCost', 'removeCost', 'refuseTaken'],
  },
};
const ACCOUNTING: Grants = {
  'ledger-cards': {
    Ledger: [
      'enterJournal',
      'enterScheduled',
      'enterDepreciation',
      'enterDisposal',
    ],
    Bill: ['void'],
  },
  'ledger-cash': {
    JournalEntry: ['post', 'journal'],
    ScheduledEntry: ['post', 'journal'],
    DepreciationRun: ['post', 'journal'],
    AssetDisposal: ['post', 'journal'],
  },
  'ledger-journal': { JournalMonth: ['reverse'], EntryPad: ['clear'] },
  'ledger-sales': {
    Invoice: ['applyWriteOff', 'unapplyWriteOff', 'enterWriteOff'],
    WriteOff: ['post', 'journal'],
  },
  'ledger-registers': {
    TaxAgency: ['markFiled', 'openReturn'],
    TaxReturn: ['file', 'markPaid', 'unmarkPaid'],
  },
  'ledger-recurring': {
    RecurringTemplate: ['advance', 'ran', 'pause', 'resume'],
  },
  'ledger-opening': { OpeningBalances: ['post'] },
};
const REPORTS: Grants = { 'ledger-cards': { Ledger: ['saveReport'] } };
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
    id: 'accountant',
    label: 'Accountant',
    summary:
      'What Standard does, and journal entries, reversals, voids of bills, write-offs, tax filing and recurring entries. Not users, settings or closes: those need a writer of the realm.',
    grants: merge(SALES, PURCHASES, JOURNAL, OPERATIONS, ACCOUNTING),
  },
  {
    id: 'standard',
    label: 'Standard',
    summary:
      "Enters and posts documents, runs payroll and reconciles. In books kept in a journal it posts each document's entry there, and the journal takes any balanced entry from it. No settings, closes or user changes.",
    grants: merge(SALES, PURCHASES, JOURNAL, OPERATIONS),
  },
  {
    id: 'limited-sales',
    label: 'Limited · customers and sales',
    summary:
      'Customers, invoices, receipts and payments received. Posts them where they post as cards; in books kept in a journal it enters them, and someone else posts them.',
    grants: SALES,
  },
  {
    id: 'limited-purchases',
    label: 'Limited · vendors and purchases',
    summary:
      'Vendors, bills and bill payments. Posts them where they post as cards; in books kept in a journal it enters them, and someone else posts them.',
    grants: PURCHASES,
  },
  {
    id: 'reports-only',
    label: 'Reports only',
    summary: 'Reads the books and runs and saves reports.',
    grants: REPORTS,
  },
];
export const roleById = new Map(ROLES.map((r) => [r.id, r]));

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
/** The user a grant's predicate names, if it is one of the forms the roles write, in either form. */
export function userNamed(where: unknown): string | undefined {
  let text =
    typeof where === 'string'
      ? where
      : typeof (where as { bxl?: unknown })?.bxl === 'string'
        ? (where as { bxl: string }).bxl
        : '';
  let m = NAMED.exec(text);
  if (m) return JSON.parse(m[1]) as string;
  let s = SAVER.exec(text);
  return s && s[1] === s[2] ? (JSON.parse(s[2]) as string) : undefined;
}

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

/** The operations each user named in a policy's rules may invoke, as "Type.operation". */
export function grantsByUser(
  rules: {
    targetType?: { name?: string } | null;
    grants?: ({ operation?: string | null; where?: unknown } | null)[] | null;
  }[],
): Map<string, Set<string>> {
  let out = new Map<string, Set<string>>();
  for (let r of rules ?? [])
    for (let g of r?.grants ?? []) {
      let user = userNamed(g?.where);
      if (!user || !g?.operation) continue;
      let set = out.get(user) ?? new Set<string>();
      set.add(`${r.targetType?.name ?? ''}.${g.operation}`);
      out.set(user, set);
    }
  return out;
}

/** The operations a role's grants name, as "Type.operation". */
export function roleOperations(role: RoleId): Set<string> {
  let rules = rolePolicyRules([{ user: '@x', role }], (f) => f);
  return grantsByUser(rules).get('@x') ?? new Set();
}

/** Each user a policy names, with the role their grants are exactly, or 'custom'. */
export function membersOf(
  rules: Parameters<typeof grantsByUser>[0],
): { user: string; role: RoleId | 'custom' }[] {
  let signatures = ROLES.map((r) => ({ id: r.id, ops: roleOperations(r.id) }));
  let same = (a: Set<string>, b: Set<string>) =>
    a.size === b.size && [...a].every((x) => b.has(x));
  return [...grantsByUser(rules)]
    .map(([user, ops]) => ({
      user,
      role: signatures.find((s) => same(s.ops, ops))?.id ?? ('custom' as const),
    }))
    .sort((a, b) => a.user.localeCompare(b.user));
}
