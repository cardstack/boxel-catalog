// The books' users and their roles, read from the realm policy the books' realm names, and changed
// through that policy's own update. Only a writer of the realm can write a policy card, so the realm
// itself keeps role changes to Admins; the page asks it before offering one.
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { identifyCard } from '@cardstack/runtime-common';
import type { CardContext, CardDef } from '@cardstack/base/card-api';
import { operations } from '@cardstack/base/operations';
import { RealmPolicy } from '@cardstack/catalog/realm-policy/realm-policy';
import { Button } from '@cardstack/pretui/components/button';
import { Select } from '@cardstack/pretui/components/select';
import { Input } from '@cardstack/pretui/components/input';
import { Field } from '@cardstack/pretui/components/field';
import { Callout } from '@cardstack/pretui/components/callout';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import { DataTable } from '@cardstack/pretui/components/data-table';
import {
  ROLES,
  roleById,
  membersOf,
  rolePolicyRules,
  userNamed,
  type RoleId,
  type PolicyRuleJSON,
} from './ledger-roles';
import { instancesOf, loadingOf, failureText } from './ledger-report-custom';
import { Dialog } from '@cardstack/pretui/components/dialog';

// A grant's condition as a policy document stores it: BXL source, or the snapshot form.
const predicateOf = (
  w: any,
): string | { bxl: string; snapshot: true } | undefined => {
  if (w == null) return undefined;
  if (typeof w === 'string') return w;
  let source = w.source ?? w.bxl;
  if (typeof source !== 'string') return undefined;
  return w.snapshot ? { bxl: source, snapshot: true } : source;
};

const GRANT_SETTINGS = [
  'anonymous',
  'actingUser',
  'blocklist',
  'rateLimitRequests',
  'rateLimitWindowSeconds',
];

/** The plain rules a policy card holds. */
export const rulesOf = (policy: any): PolicyRuleJSON[] =>
  ((policy?.rules ?? []) as any[]).filter(Boolean).map((r) => ({
    targetType: {
      module: r.targetType?.module ?? '',
      name: r.targetType?.name ?? '',
    },
    grants: ((r.grants ?? []) as any[]).filter(Boolean).map((g) => ({
      // Every other setting a grant carries (an acting user, a rate limit) goes back unchanged.
      ...Object.fromEntries(
        GRANT_SETTINGS.filter((k) => g[k] != null).map((k) => [k, g[k]]),
      ),
      operation: g.operation ?? '',
      where: predicateOf(g.where),
    })),
  }));

// A rule's module, written back the way the policy card names it.
const moduleBy = (rules: PolicyRuleJSON[]) => {
  let seen = new Map<string, string>();
  for (let r of rules) {
    let file = r.targetType.module.split('/').pop() ?? '';
    if (file && !seen.has(file)) seen.set(file, r.targetType.module);
  }
  return (file: string) => seen.get(file) ?? `../${file}`;
};

/**
 * The policy's rules with one user's role changed (or the user removed, for no role), the others kept.
 * Every grant naming that user is replaced; grants naming no user, or another user whose grants match
 * no role, are kept as they are.
 */
export function withRole(
  rules: PolicyRuleJSON[],
  user: string,
  role: RoleId | '',
  moduleOf: (file: string) => string = moduleBy(rules),
) {
  let members = membersOf(rules);
  let roled = members.filter((m) => m.role !== 'custom') as {
    user: string;
    role: RoleId;
  }[];
  let next = [
    ...roled.filter((m) => m.user !== user),
    ...(role ? [{ user, role }] : []),
  ];
  let named = new Set([...roled.map((m) => m.user), user]);
  // Drop exactly the grants that define those users' roles, in either predicate form; keep the rest.
  let kept = rules
    .map((r) => ({
      ...r,
      grants: r.grants.filter((g) => !named.has(userNamed(g.where) ?? '')),
    }))
    .filter((r) => r.grants.length);
  return [...kept, ...rolePolicyRules(next, moduleOf)];
}

const ROLE_OPTIONS = [
  ...ROLES.map((r) => ({ value: r.id, label: r.label })),
  { value: '', label: 'No access' },
];
// Shown on a row whose grants match no role. Choosing it changes nothing.
const CUSTOM_OPTION = { value: 'custom', label: 'Custom grants' };
const isRole = (key: unknown) => key === 'roleLabel';
const REALM_CONFIG = {
  module: '@cardstack/base/realm-config',
  name: 'RealmConfig',
};
/**
 * The policy card a realm.json pointer names, among a realm's policy cards: the pointer resolved
 * against that realm, matched on the card's whole id.
 */
export function policyNamed<T extends { id?: string }>(
  policies: T[],
  pointer: string,
  realm: string,
): T | undefined {
  let bare = (id: string) => id.replace(/\.json$/, '');
  let want: string;
  try {
    want = bare(new URL(pointer, realm).href);
  } catch {
    return undefined;
  }
  if (!pointer) return undefined;
  return policies.find((p) => bare(p.id ?? '') === want);
}
type Row = { user: string; role: string; roleLabel: string; summary: string };
const COLUMNS = [
  { key: 'user', label: 'User', mono: true },
  { key: 'roleLabel', label: 'Role' },
  { key: 'summary', label: 'What the role may do' },
];

interface UsersSignature {
  Args: { context?: CardContext; realms: string[] };
}
export class UsersPage extends GlimmerComponent<UsersSignature> {
  @tracked newUser = '';
  @tracked newRole: string = 'standard';
  @tracked busy = false;
  @tracked error = '';
  @tracked done = '';
  configData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: { type: REALM_CONFIG },
        page: { size: 1 },
      }) as never,
    () => this.args.realms.slice(0, 1),
    { isLive: true },
  );
  policyData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: { type: identifyCard(RealmPolicy) },
        page: { size: 50 },
      }) as never,
    () => this.args.realms,
    { isLive: true },
  );
  get loading() {
    return loadingOf(this.configData) || loadingOf(this.policyData);
  }
  // The policy realm.json names, the one the realm enforces.
  get pointer(): string {
    return instancesOf(this.configData)[0]?.policy ?? '';
  }
  get policy(): CardDef | undefined {
    return policyNamed(
      instancesOf(this.policyData),
      this.pointer,
      this.args.realms[0] ?? '',
    );
  }
  // A policy card's update is open only to the realm's writers, so the realm's answer for it says
  // whether the viewer is one: an Admin. Nothing is offered until it answers.
  get adminAnswer(): boolean | undefined {
    let p = this.policy;
    return p ? this.args.context?.canInvoke?.('update', p) : undefined;
  }
  get isAdmin() {
    return this.adminAnswer === true;
  }
  get mayChange() {
    return this.adminAnswer === true;
  }
  get adminUnknown() {
    return this.adminAnswer === undefined;
  }
  get rows(): Row[] {
    return membersOf(rulesOf(this.policy)).map((m) => {
      let def = m.role === 'custom' ? undefined : roleById.get(m.role);
      return {
        user: m.user,
        role: m.role,
        roleLabel: def?.label ?? 'Custom grants',
        summary:
          def?.summary ??
          'Grants that match no role; edit them on the policy card.',
      };
    });
  }
  roleOptions = ROLE_OPTIONS;
  rowOptions = (role: string) =>
    role === 'custom' ? [...ROLE_OPTIONS, CUSTOM_OPTION] : ROLE_OPTIONS;
  @tracked pending: { user: string; role: string } | undefined;
  @tracked newUserError = '';
  // A change waits for the Admin to confirm it in a dialog.
  ask = (user: string, role: string) => {
    if (this.busy || role === 'custom') return;
    let current = this.rows.find((r) => r.user === user)?.role;
    if (current === role) return;
    this.pending = { user, role };
  };
  cancel = () => (this.pending = undefined);
  confirm = async () => {
    let p = this.pending;
    this.pending = undefined;
    if (p) await this.change(p.user, p.role);
  };
  get pendingTitle() {
    let p = this.pending;
    if (!p) return '';
    return p.role
      ? `Change ${p.user} to ${roleById.get(p.role as RoleId)?.label ?? p.role}?`
      : `Remove access for ${p.user}?`;
  }
  get pendingMessage() {
    let p = this.pending;
    if (!p) return '';
    return p.role
      ? `${p.user} will be able to do only what ${roleById.get(p.role as RoleId)?.label ?? p.role} can, from the realm's next check.`
      : `${p.user} loses every grant the policy gives them. What the realm's own permissions give them stays.`;
  }
  get pendingTone(): 'primary' | 'danger' {
    return this.pending?.role ? 'primary' : 'danger';
  }
  get pendingAction() {
    return this.pending?.role ? 'Change role' : 'Remove access';
  }
  rowKey = (r: Row) => r.user;
  rowLabel = (r: Row) => r.user;
  setNewUser = (v: string) => {
    this.newUser = v.trim();
    this.newUserError = '';
  };
  setNewRole = (v: string) => (this.newRole = v);
  change = async (user: string, role: string) => {
    let p = this.policy;
    if (!p || !user) return;
    this.busy = true;
    this.error = '';
    this.done = '';
    try {
      await (operations(p) as any).update({
        attributes: {
          rules: withRole(rulesOf(p), user, role as RoleId | ''),
        },
      });
      this.done = role
        ? `${user} is now ${roleById.get(role as RoleId)?.label ?? role}.`
        : `${user} no longer has a role.`;
      if (user === this.newUser) this.newUser = '';
    } catch (e: any) {
      this.error = failureText(e);
    } finally {
      this.busy = false;
    }
  };
  add = () => {
    this.newUserError = this.newUser.startsWith('@')
      ? ''
      : 'Enter a user id, such as @name:server';
    if (!this.newUserError) this.ask(this.newUser, this.newRole);
  };
  <template>
    <section class='users' data-users-page>
      <p class='muted'>
        Each role is a set of grants in the realm policy the books' realm names:
        the operations the role may invoke on each kind of card, each naming its
        users. Everyone with a role reads the books through the realm's read
        permission. Admin is not a role this page gives: an Admin is an owner or
        writer of the books' realm, set in the realm's permissions, and only an
        Admin can change roles, settings or closes. An Admin listed here under a
        role still has everything.
      </p>
      {{#if this.policy}}<p class='muted' data-viewer-admin={{this.isAdmin}}>You
          are
          {{#if this.isAdmin}}an Admin: a writer of the books' realm.{{else if
            this.adminUnknown
          }}being checked for whether you're an Admin…{{else}}not an Admin of
            these books.{{/if}}</p>{{/if}}
      {{#if this.error}}<Callout
          @tone='danger'
          @title="The realm didn't change the role"
        >{{this.error}}</Callout>{{/if}}
      <p class='muted' role='status'>{{this.done}}</p>
      {{#if this.loading}}
        <p class='muted' role='status' aria-busy='true'>Loading the books'
          users…</p>
        <Skeleton @height='8rem' />
      {{else if this.policy}}
        <DataTable
          @columns={{COLUMNS}}
          @rows={{this.rows}}
          @key={{this.rowKey}}
          @rowLabel={{this.rowLabel}}
          @label='Users'
          @itemNoun='users'
          @size='s'
          @emptyTitle='No one has a role yet'
          @emptyMessage='Give a user a role below.'
        >
          <:cell as |text row col|>
            {{#if (isRole col.key)}}
              {{#if this.mayChange}}<Select
                  @label='Role for {{row.user}}'
                  @options={{this.rowOptions row.role}}
                  @value={{row.role}}
                  aria-disabled={{if this.busy 'true'}}
                  @onValueChange={{fn this.ask row.user}}
                />{{else}}{{text}}{{/if}}
            {{else}}{{text}}{{/if}}
          </:cell>
        </DataTable>
        {{#if this.mayChange}}
          <div class='add'>
            <Field @label='User' @error={{this.newUserError}}>
              <:default as |id|><Input
                  @controlId={{id}}
                  @value={{this.newUser}}
                  @placeholder='@name:server'
                  @onInput={{this.setNewUser}}
                /></:default>
            </Field>
            <Field @label='Role'>
              <:default as |id|><Select
                  @controlId={{id}}
                  @options={{this.roleOptions}}
                  @value={{this.newRole}}
                  @onValueChange={{this.setNewRole}}
                /></:default>
            </Field>
            <Button
              @tone='primary'
              @appearance='accent'
              @busy={{this.busy}}
              {{on 'click' this.add}}
            >Give this role</Button>
          </div>
        {{else}}
          <p class='muted' data-roles-locked>Only an Admin, a writer of the
            books' realm, can change roles.</p>
        {{/if}}
      {{else}}
        <EmptyState
          @title='These books have no roles yet'
          @message="Roles live in the realm policy the books' realm.json names. Point its policy at one, such as the books' Roles policy card, and its users list here."
        />
      {{/if}}
      <Dialog
        @open={{if this.pending true false}}
        @onClose={{this.cancel}}
        @size='s'
      >
        <:title>{{this.pendingTitle}}</:title>
        <:default><p>{{this.pendingMessage}}</p></:default>
        <:footer>
          <Button @appearance='plain' {{on 'click' this.cancel}}>Cancel</Button>
          <Button
            @tone={{this.pendingTone}}
            @appearance='accent'
            {{on 'click' this.confirm}}
          >{{this.pendingAction}}</Button>
        </:footer>
      </Dialog>
    </section>
    <style scoped>
      .users {
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .add {
        display: flex;
        flex-wrap: wrap;
        align-items: end;
        gap: var(--boxel-sp-sm);
      }
      .muted {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
