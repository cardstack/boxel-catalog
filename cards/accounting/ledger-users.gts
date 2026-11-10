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
  type RoleId,
} from './ledger-roles';
import { instancesOf, loadingOf } from './ledger-report-custom';

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

/** The plain rules a policy card holds. */
export const rulesOf = (policy: any) =>
  ((policy?.rules ?? []) as any[]).filter(Boolean).map((r) => ({
    targetType: {
      module: r.targetType?.module ?? '',
      name: r.targetType?.name ?? '',
    },
    grants: ((r.grants ?? []) as any[]).filter(Boolean).map((g) => ({
      operation: g.operation ?? '',
      where: predicateOf(g.where),
    })),
  }));

// A rule's module, written back the way the policy card names it.
const moduleBy = (rules: ReturnType<typeof rulesOf>) => {
  let seen = new Map<string, string>();
  for (let r of rules) {
    let file = r.targetType.module.split('/').pop() ?? '';
    if (file && !seen.has(file)) seen.set(file, r.targetType.module);
  }
  return (file: string) => seen.get(file) ?? `../${file}`;
};

/**
 * The policy's rules with one user's role changed (or the user removed, for no role), the others kept.
 * Rules naming no user, or a user whose grants match no role, are kept as they are.
 */
export function withRole(
  rules: ReturnType<typeof rulesOf>,
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
  let named = new Set(roled.map((m) => m.user));
  // Keep every grant that names no user with a role: custom grants and unconditional ones.
  let kept = rules
    .map((r) => ({
      ...r,
      grants: r.grants.filter((g) => {
        let w = typeof g.where === 'string' ? g.where : '';
        return ![...named].some((u) => w.includes(JSON.stringify(u)));
      }),
    }))
    .filter((r) => r.grants.length);
  return [...kept, ...rolePolicyRules(next, moduleOf)];
}

const ROLE_OPTIONS = [
  ...ROLES.map((r) => ({ value: r.id, label: r.label })),
  { value: '', label: 'No access' },
];
const isRole = (key: unknown) => key === 'roleLabel';
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
  policyData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: { type: identifyCard(RealmPolicy) },
        page: { size: 5 },
      }) as never,
    () => this.args.realms,
    { isLive: true },
  );
  get loading() {
    return loadingOf(this.policyData);
  }
  get policy(): CardDef | undefined {
    return instancesOf(this.policyData)[0];
  }
  // Asked of the realm: a policy card's update is open only to the realm's writers.
  get mayChange() {
    let p = this.policy;
    return !!p && this.args.context?.canInvoke?.('update', p) !== false;
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
  rowKey = (r: Row) => r.user;
  rowLabel = (r: Row) => r.user;
  setNewUser = (v: string) => (this.newUser = v.trim());
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
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  add = () => this.change(this.newUser, this.newRole);
  <template>
    <section class='users' data-users-page>
      <Callout @tone='info' @title='How roles work here'>
        Each role is a set of grants in the realm policy the books' realm names:
        the operations the role may invoke on each kind of card, each naming its
        users. Everyone with a role reads the books through the realm's read
        permission. Admins are also writers of the realm, set in its
        permissions, which is what lets them change users and settings and close
        months.
      </Callout>
      {{#if this.error}}<Callout
          @tone='danger'
          @title="The realm didn't change the role"
        >{{this.error}}</Callout>{{/if}}
      {{#if this.done}}<Callout @tone='success'>{{this.done}}</Callout>{{/if}}
      {{#if this.loading}}
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
                  @options={{this.roleOptions}}
                  @value={{row.role}}
                  @disabled={{this.busy}}
                  @onValueChange={{fn this.change row.user}}
                />{{else}}{{text}}{{/if}}
            {{else}}{{text}}{{/if}}
          </:cell>
        </DataTable>
        {{#if this.mayChange}}
          <div class='add'>
            <Field @label='User'>
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
              @disabled={{if this.newUser false true}}
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
          @message="Roles live in a realm policy. Point the books' realm.json policy at one, such as the books' Roles policy card, and its users list here."
        />
      {{/if}}
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
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
