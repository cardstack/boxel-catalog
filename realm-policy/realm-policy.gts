import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { resource, use } from 'ember-resources';
import { TrackedObject } from 'tracked-built-ins';
import {
  CardDef,
  Component,
  FieldDef,
  contains,
  containsMany,
  field,
  realmURL,
  serializeCard,
} from 'https://cardstack.com/base/card-api';
import CodeRefField from 'https://cardstack.com/base/code-ref';
import { JsonField } from 'https://cardstack.com/base/json-field';
import {
  operation,
  operations,
  OperationsError,
  type OperationDeclaration,
  type PolicyExplanation,
  type PolicyExplanationListing,
  type PolicyValidation,
} from 'https://cardstack.com/base/operations';
import PolicyPredicateField from '@cardstack/catalog/fields/policy-predicate/policy-predicate';
import { subscribeToRealm } from '@cardstack/runtime-common';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import {
  BoxelInput,
  Button,
  FieldContainer,
  Pill,
  RadioInput,
} from '@cardstack/boxel-ui/components';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';

// A realm's operation policy: which callers may invoke which operations on
// which card types, beyond what the realm's own read/write permissions allow.
//
// A policy only ever widens access. It is a union of grants — a caller may
// invoke an operation on a target if the realm already permits it, or if any
// rule whose `targetType` matches the target (or one of its ancestors) holds a
// grant for that operation whose `where` predicate, when present, is true.
// Rule order carries no meaning.
//
// These definitions describe a policy; nothing in them evaluates one. The
// realm does, and `explain` asks it what it decides.

export class OperationGrant extends FieldDef {
  static displayName = 'Operation Grant';

  // The operation name as a caller invokes it — a base operation such as
  // `read` or `update`, or a name a card declares. A grant on a named
  // operation does not grant the base operation it is built on.
  @field operation = contains(StringField);
  // A BXL boolean expression over the caller and the target. Absent means
  // the grant is unconditional.
  @field where = contains(PolicyPredicateField);
  // Whether the grant also admits a caller who isn't signed in. Off, it
  // admits only signed-in callers, so a grant written before anonymous
  // callers could reach a policy never starts admitting them. A grant on a
  // base operation other than `explain` or `validate` may set it, and so may
  // one on an operation a card declares on such a base. A grant on a named
  // query may not: setting it there leaves the whole grant out, for
  // signed-in callers too. Such a caller has no actor, so a grant whose
  // `where` reads `actor()`, or whose operation does, never admits one,
  // though it still applies to signed-in callers: an anonymous grant is
  // scoped by what the target holds. How hard anonymous callers may use the
  // realm, and which addresses it refuses, are the governed realm's own
  // settings, not the policy's.
  @field anonymous = contains(BooleanField);
  // For an anonymous grant on a write: the key, exactly as written, in the
  // governed realm's `realm.json` settings, whose value is the user the write
  // is made as. The realm names the user rather than the policy, because the
  // policy can live in another realm and its writers must not decide whose
  // identity this realm's writes carry.
  @field actingUser = contains(StringField);

  static embedded = class Embedded extends Component<typeof OperationGrant> {
    <template>
      <div class='operation-grant' data-test-operation-grant>
        <code class='operation' data-test-operation-grant-operation>
          {{@model.operation}}
        </code>
        {{#if @model.where}}
          <span class='keyword'>where</span>
          <@fields.where />
        {{else}}
          <span class='unconditional' data-test-operation-grant-unconditional>
            always
          </span>
        {{/if}}
        {{#if @model.anonymous}}
          <Pill data-test-operation-grant-anonymous>
            anyone
          </Pill>
          {{#if @model.actingUser}}
            <span class='keyword'>as</span>
            <code
              class='acting-user'
              data-test-operation-grant-acting-user
            >config.{{@model.actingUser}}</code>
          {{/if}}
        {{/if}}
      </div>
      <style scoped>
        .operation-grant {
          display: flex;
          align-items: baseline;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .operation {
          font-family: var(--boxel-monospace-font-family, monospace);
          font-weight: 600;
        }
        .keyword,
        .unconditional {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .acting-user {
          font-family: var(--boxel-monospace-font-family, monospace);
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };
}

export class PolicyRule extends FieldDef {
  static displayName = 'Policy Rule';

  // The card type this rule governs. It also governs that type's subtypes.
  @field targetType = contains(CodeRefField);
  @field grants = containsMany(OperationGrant);

  static embedded = class Embedded extends Component<typeof PolicyRule> {
    <template>
      <section class='policy-rule' data-test-policy-rule>
        <header class='target'>
          {{#if @model.targetType}}
            <span class='type-name' data-test-policy-rule-type-name>
              {{@model.targetType.name}}
            </span>
            <span class='type-module' data-test-policy-rule-type-module>
              {{@model.targetType.module}}
            </span>
          {{else}}
            <span class='type-name missing'>No target type</span>
          {{/if}}
        </header>
        {{#if @model.grants.length}}
          <ul class='grants'>
            {{#each @fields.grants as |Grant|}}
              <li><Grant /></li>
            {{/each}}
          </ul>
        {{else}}
          <p class='empty' data-test-policy-rule-no-grants>No grants.</p>
        {{/if}}
      </section>
      <style scoped>
        .policy-rule {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .target {
          display: flex;
          align-items: baseline;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .type-name {
          font-weight: 600;
        }
        .type-name.missing,
        .type-module,
        .empty {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .type-module {
          font-family: var(--boxel-monospace-font-family, monospace);
          font-size: var(--boxel-font-size-xs);
          overflow-wrap: anywhere;
        }
        .grants {
          list-style: none;
          margin: 0;
          padding: 0 0 0 var(--boxel-sp);
          display: grid;
          gap: var(--boxel-sp-xxs);
        }
        .empty {
          margin: 0;
        }
      </style>
    </template>
  };
}

// What each reason an explanation gives means, in the words a policy author
// reads it in. `reads-actor` is named here as well as through the explanation
// type, so the map covers it whichever platform version this realm runs on.
const REASONS: Record<PolicyExplanation['reason'] | 'reads-actor', string> = {
  acl: "The realm's own permissions already allow this, so the policy isn't needed.",
  granted: 'A grant in this policy allows it.',
  'no-grant': "No rule for this card's type grants this operation.",
  'predicate-false':
    'This policy has grants for this operation on this card, but none of their conditions is met.',
  'predicate-threw':
    "A grant's condition ran into an error, so the request fails.",
  'non-grantable': 'No policy can allow this operation.',
  'query-lane':
    "This operation is a search. It doesn't act on one card: the search returns only the cards this policy's grants on it allow.",
  'authorization-infrastructure':
    "No policy can allow anything on a policy card or the realm's settings card, including reading them, or creating a policy card.",
  'unmatchable-target':
    "No rule can apply here. Either the card has an error, so its type isn't known; it is a file and this operation isn't a download of it; or it is a code file.",
  'not-resolved': "This card doesn't have this operation.",
  'actor-required':
    "Someone who isn't signed in is turned away before the policy is checked.",
  'reads-actor':
    "This operation depends on who is asking, and someone who isn't signed in can't be identified, so a grant that opens it to them doesn't apply.",
  'policy-unloadable': "The realm's policy couldn't be loaded.",
};

// A search returns rows rather than admitting or refusing a card, so the
// reasons that read differently for one are said in its terms.
const SEARCH_REASONS: Partial<Record<PolicyExplanation['reason'], string>> = {
  acl: "The realm's own permissions let this person search it, so the search returns every card it matches and the policy isn't needed.",
  granted:
    'Grants in this policy let this search return the cards their conditions match, and no others.',
  'no-grant':
    'No grant in this policy can narrow this search for this person, so it returns no cards. A grant whose condition a search can’t use doesn’t count.',
  'not-resolved':
    "This search couldn't be resolved: the card type doesn't declare a search by this name, or the filter isn't one a search accepts.",
};

const DECISION_VARIANT: Record<
  PolicyExplanation['decision'],
  'primary' | 'destructive' | 'muted'
> = {
  allowed: 'primary',
  denied: 'muted',
  failed: 'destructive',
};

const OUTCOME_LABEL: Record<
  PolicyExplanation['rules'][number]['grants'][number]['outcome'],
  string
> = {
  unconditional: 'always applies',
  held: 'condition met',
  'did-not-hold': 'condition not met',
  threw: 'condition failed with an error',
  'not-evaluated': 'not checked',
};

// Which copy of the card a grant's condition checked.
const TIER_LABEL: Record<
  NonNullable<PolicyExplanation['rules'][number]['grants'][number]['tier']>,
  string
> = {
  stored: 'checks the saved card',
  snapshot: "checks the index's copy",
};

// What to tell the author when the realm refuses or fails an operation this
// card asks of it.
function failureMessage(err: unknown): string {
  return err instanceof OperationsError
    ? (err.detail ?? err.message)
    : err instanceof Error
      ? err.message
      : String(err);
}

function decisionVariant(decision: PolicyExplanation['decision']) {
  return DECISION_VARIANT[decision];
}

function asJson(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

// A JSON object the author typed, or an error saying what is wrong with it.
function parseObject(text: string, what: string): Record<string, unknown> {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch (err) {
    throw new Error(`${what} isn't valid JSON: ${failureMessage(err)}`);
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${what} must be a JSON object.`);
  }
  return value as Record<string, unknown>;
}

// A draft to start from: the rules this card holds, as the card stores them.
function startingDraft(policy: RealmPolicy): string {
  let rules = serializeCard(policy, {}).data.attributes?.rules ?? [];
  return asJson({ rules });
}

function durationLabel(ms: number): string {
  return ms < 1000 ? `${ms} ms` : `${(ms / 1000).toFixed(1)} s`;
}

// A policy issue's message, as the compiler writes it for this card and for a
// `validate` answer. Each identifier in it is marked as code with backticks,
// as markdown marks it; a blank line separates one idea from the next; and a
// set of alternatives is a list, one per line beginning `- `. Here each idea
// is a paragraph, the alternatives are a bulleted list, and each marked
// identifier renders as code. Nothing in a message is ever read as markup, and
// a backtick with no partner is text.
const BACKTICK = String.fromCharCode(96);
const LIST_ITEM = '- ';

type MessagePart = { text: string; code: boolean };
type MessageBlock =
  | { paragraph: MessagePart[]; items?: undefined }
  | { items: MessagePart[][]; paragraph?: undefined };

function messageParts(text: string): MessagePart[] {
  let segments = text.split(BACKTICK);
  let parts: MessagePart[] = [];
  segments.forEach((segment, index) => {
    let opensSpan = index % 2 === 1;
    if (opensSpan && index === segments.length - 1) {
      // The last backtick opened a span nothing closed.
      parts.push({ text: BACKTICK + segment, code: false });
    } else if (segment) {
      parts.push({ text: segment, code: opensSpan });
    }
  });
  return parts;
}

// The paragraphs and lists a message is laid out as, in the order it writes
// them. Within a paragraph, a single line break is a space.
function messageBlocks(message: string | undefined): MessageBlock[] {
  let blocks: MessageBlock[] = [];
  let prose: string[] = [];
  let items: string[] = [];
  let flush = () => {
    if (prose.length) {
      blocks.push({ paragraph: messageParts(prose.join(' ')) });
      prose = [];
    }
    if (items.length) {
      blocks.push({ items: items.map(messageParts) });
      items = [];
    }
  };
  for (let line of (message ?? '').split('\n')) {
    let trimmed = line.trim();
    if (!trimmed) {
      flush();
    } else if (trimmed.startsWith(LIST_ITEM)) {
      if (prose.length) {
        flush();
      }
      items.push(trimmed.slice(LIST_ITEM.length));
    } else {
      if (items.length) {
        flush();
      }
      prose.push(trimmed);
    }
  }
  flush();
  return blocks;
}

interface MessagePartsSignature {
  Args: { parts: MessagePart[] };
}

class MessageParts extends GlimmerComponent<MessagePartsSignature> {
  <template>
    {{~#each @parts as |part|~}}
      {{~#if part.code~}}
        <code class='message-code'>{{part.text}}</code>
      {{~else~}}
        {{part.text}}
      {{~/if~}}
    {{~/each~}}
    <style scoped>
      .message-code {
        padding: 0.05em 0.35em;
        border-radius: var(--boxel-border-radius-xs, 3px);
        background-color: var(--muted, var(--boxel-100));
        color: var(--foreground, var(--boxel-dark));
        font-family: var(--boxel-monospace-font-family, monospace);
        font-size: 0.875em;
        -webkit-box-decoration-break: clone;
        box-decoration-break: clone;
      }
    </style>
  </template>
}

interface MessageTextSignature {
  Args: { message: string | undefined };
}

class MessageText extends GlimmerComponent<MessageTextSignature> {
  <template>
    <div class='message'>
      {{#each (messageBlocks @message) as |block|}}
        {{#if block.items}}
          <ul class='message-list'>
            {{#each block.items as |item|}}
              <li><MessageParts @parts={{item}} /></li>
            {{/each}}
          </ul>
        {{else}}
          <p class='message-paragraph'><MessageParts
              @parts={{block.paragraph}}
            /></p>
        {{/if}}
      {{/each}}
    </div>
    <style scoped>
      .message {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        overflow-wrap: anywhere;
      }
      .message-paragraph {
        margin: 0;
      }
      .message-list {
        margin: 0;
        padding-left: var(--boxel-sp-lg);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs, 0.25rem);
      }
    </style>
  </template>
}

// An issue compiling a draft recorded, in the shape a policy's own issues take.
type DraftIssue = NonNullable<PolicyExplanation['draft']>['issues'][number];

// What compiling a draft recorded against it. An empty list says the draft
// compiled cleanly, which is what an author editing one wants to know too.
interface DraftIssuesSignature {
  Args: { issues: DraftIssue[] };
}

class DraftIssues extends GlimmerComponent<DraftIssuesSignature> {
  <template>
    <div class='draft-issues' data-test-explanation-draft>
      <h3 class='draft-title'>Answered against your draft</h3>
      {{#if @issues.length}}
        <ul class='draft-issue-list'>
          {{#each @issues as |issue|}}
            <li data-test-explanation-draft-issue={{issue.code}}>
              <code class='issue-code'>{{issue.code}}</code>
              {{#if issue.path}}
                <code class='issue-path'>{{issue.path}}</code>
              {{/if}}
              <Pill
                @variant={{if
                  (eqWarning issue.severity)
                  'secondary'
                  'destructive'
                }}
              >{{issue.severity}}</Pill>
              <div class='issue-message'><MessageText
                  @message={{issue.message}}
                /></div>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class='empty' data-test-explanation-draft-clean>
          The draft has no problems.
        </p>
      {{/if}}
    </div>
    <style scoped>
      .draft-issues {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm);
        border: 1px dashed var(--border, var(--boxel-border-color));
        border-radius: var(--boxel-border-radius);
      }
      .draft-title {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .draft-issue-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .draft-issue-list li {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
      }
      .issue-code,
      .issue-path {
        font-family: var(--boxel-monospace-font-family, monospace);
        font-size: var(--boxel-font-size-xs);
      }
      .issue-message {
        flex-basis: 100%;
        margin: 0;
      }
      .empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground, var(--boxel-450));
      }
    </style>
  </template>
}

function eqWarning(severity: DraftIssue['severity']): boolean {
  return severity === 'warning';
}

// One explanation: the decision and why, the realm permissions it started
// from, and the rules and grants it read. For a search, also what the policy
// composes into it and how far behind the index the search reads is.
interface ExplanationViewSignature {
  Args: { explanation: PolicyExplanation };
}

// What an explanation reports about callers who aren't signed in: how the
// realm limits and blocks them, and for a grant that opts in to them, the
// user its writes are made as. Read where present, so the panel answers the
// same on a platform that doesn't report them.
interface AnonymousAccessDetail {
  limit: { requests: number; windowSeconds: number };
  limitFrom: 'realm' | 'platform';
  invalidBlocklistEntries: string[];
}
interface GrantAnonymousDetail {
  actingUserKey?: string;
  actingUser?: string;
  actingUserFailure?: 'key-missing' | 'not-a-matrix-id' | 'no-write';
}
type ExplainedGrantDetail = PolicyExplanation['rules'][number]['grants'][number] & {
  anonymous?: GrantAnonymousDetail;
  issues?: DraftIssue[];
};

// Why an acting-user key names no one a write may be made as, in the words a
// policy author reads it in.
const ACTING_USER_FAILURES: Record<
  NonNullable<GrantAnonymousDetail['actingUserFailure']>,
  (key: string) => string
> = {
  'key-missing': (key) =>
    `this realm's settings have no "${key}", so it admits none of them.`,
  'not-a-matrix-id': (key) =>
    `this realm's "${key}" setting isn't a user ID, so it admits none of them.`,
  'no-write': (key) =>
    `the user this realm's "${key}" setting names can't write to the realm, so it admits none of them.`,
};

class ExplanationView extends GlimmerComponent<ExplanationViewSignature> {
  get explanation() {
    return this.args.explanation;
  }

  get reason(): string {
    let { reason, search } = this.explanation;
    return (search ? SEARCH_REASONS[reason] : undefined) ?? REASONS[reason];
  }

  get anonymousAccess(): AnonymousAccessDetail | undefined {
    return (
      this.explanation as PolicyExplanation & {
        anonymous?: AnonymousAccessDetail;
      }
    ).anonymous;
  }

  get anonymousLimit(): string {
    let access = this.anonymousAccess;
    if (!access) {
      return '';
    }
    let { requests, windowSeconds } = access.limit;
    return `${requests} requests per ${windowSeconds} seconds from one address, ${
      access.limitFrom === 'realm' ? 'set by this realm' : 'the platform default'
    }`;
  }

  get invalidBlocklist(): string {
    return (this.anonymousAccess?.invalidBlocklistEntries ?? [])
      .map((entry) => `"${entry}"`)
      .join(', ');
  }

  grantDetail = (
    grant: PolicyExplanation['rules'][number]['grants'][number],
  ): ExplainedGrantDetail => grant as ExplainedGrantDetail;

  // Who a grant opened to callers who aren't signed in makes their writes
  // as, or why it admits none of them.
  actingUserLine = (anonymous: GrantAnonymousDetail): string => {
    let opened = "Open to people who aren't signed in";
    let key = anonymous.actingUserKey;
    if (!key) {
      return `${opened}.`;
    }
    if (anonymous.actingUserFailure) {
      return `${opened}, but ${ACTING_USER_FAILURES[anonymous.actingUserFailure](key)}`;
    }
    return `${opened}, writing as ${anonymous.actingUser} (the realm's "${key}" setting).`;
  };

  // What the realm's own permissions let the actor do. Write without read
  // is a shape the realm accepts, so it is named rather than read as both.
  get aclStanding(): string {
    let { acl } = this.explanation;
    if (acl.read && acl.write) {
      return 'read and write';
    }
    if (acl.write) {
      return 'write, not read';
    }
    return acl.read ? 'read' : 'none';
  }

  get decisionVariant() {
    return DECISION_VARIANT[this.explanation.decision];
  }

  get searchTypes(): string {
    let types = this.explanation.search?.types ?? [];
    return types.length
      ? types
          .map((type) => ('name' in type ? type.name : asJson(type)))
          .join(', ')
      : 'none: the filter names no card type, so no grant can reach it';
  }

  get searchFilter(): string | undefined {
    let filter = this.explanation.search?.filter;
    return filter ? asJson(filter) : undefined;
  }

  get fragment(): string | undefined {
    let fragment = this.explanation.search?.fragment;
    return fragment ? asJson(fragment) : undefined;
  }

  get indexLag(): string | undefined {
    let index = this.explanation.search?.index;
    if (!index) {
      return undefined;
    }
    if (index.pending === 0) {
      return 'Up to date.';
    }
    let passes =
      index.pending === 1
        ? '1 indexing pass has'
        : `${index.pending} indexing passes have`;
    let waited =
      index.oldestPendingMs !== undefined
        ? ` The oldest has waited ${durationLabel(index.oldestPendingMs)}.`
        : '';
    return `${passes} yet to land, so the search can answer from cards as they were before those changes.${waited}`;
  }

  isAdmitting = (ruleIndex: number, grantIndex: number): boolean =>
    this.explanation.admittedBy?.rule === ruleIndex &&
    this.explanation.admittedBy?.grant === grantIndex;

  tierLabel = (
    tier: PolicyExplanation['rules'][number]['grants'][number]['tier'],
  ) => (tier ? TIER_LABEL[tier] : undefined);

  // Whether a search-lane grant gives the search a filter, spelled out, since
  // an attribute bound to `false` is left off the element.
  filterableState = (
    grant: PolicyExplanation['rules'][number]['grants'][number],
  ): string | undefined =>
    grant.filterable === undefined ? undefined : String(grant.filterable);

  // Which copy of a card a condition reads matters only where it is checked
  // card by card. A search runs it as a filter over the index, whose lag the
  // answer reports instead.
  showsTier = (
    grant: PolicyExplanation['rules'][number]['grants'][number],
  ): boolean => grant.filterable === undefined && grant.tier !== undefined;

  // On the search lane a grant's condition is never checked card by card:
  // the search runs it as a filter, so what matters is whether it has one.
  grantLabel = (
    grant: PolicyExplanation['rules'][number]['grants'][number],
  ): string =>
    grant.filterable === undefined
      ? OUTCOME_LABEL[grant.outcome]
      : grant.filterable
        ? 'narrows the search'
        : "a search can't use its condition, so it adds nothing";

  <template>
    <div class='explanation' data-test-explanation>
      <header class='verdict'>
        <Pill @variant={{this.decisionVariant}} data-test-explanation-decision>
          {{this.explanation.decision}}
        </Pill>
        <span class='reason' data-test-explanation-reason>
          {{this.reason}}
        </span>
      </header>
      <dl class='facts'>
        <dt>Person</dt>
        <dd data-test-explanation-actor>
          {{if this.explanation.actor this.explanation.actor 'not signed in'}}
        </dd>
        <dt>Realm permissions</dt>
        <dd data-test-explanation-acl>{{this.aclStanding}}</dd>
        {{#if this.explanation.refusal}}
          <dt>Turned away with</dt>
          <dd data-test-explanation-refusal>
            {{this.explanation.refusal.status}}
            <code>{{this.explanation.refusal.code}}</code>
          </dd>
        {{/if}}
        {{#if this.anonymousAccess}}
          <dt>Limit</dt>
          <dd data-test-explanation-anonymous-limit>{{this.anonymousLimit}}</dd>
          {{#if this.anonymousAccess.invalidBlocklistEntries.length}}
            <dt>Blocklist</dt>
            <dd class='warning' data-test-explanation-anonymous-blocklist>
              Some entries aren't an address or a range ({{this.invalidBlocklist}}),
              so this realm turns away everyone who isn't signed in until
              they're fixed.
            </dd>
          {{/if}}
        {{/if}}
      </dl>
      {{#if this.explanation.search}}
        <dl class='facts search' data-test-explanation-search>
          <dt>Search</dt>
          <dd data-test-explanation-search-operation>
            <code>{{this.explanation.search.operation}}</code>
          </dd>
          <dt>Card types</dt>
          <dd data-test-explanation-search-types>{{this.searchTypes}}</dd>
          {{#if this.searchFilter}}
            <dt>The search's own filter</dt>
            <dd>
              <pre
                class='json'
                data-test-explanation-search-filter
              >{{this.searchFilter}}</pre>
            </dd>
          {{/if}}
          <dt>What this policy adds</dt>
          <dd>
            {{#if this.fragment}}
              <p class='note'>The search returns only cards that also match
                this.</p>
              <pre
                class='json'
                data-test-explanation-search-fragment
              >{{this.fragment}}</pre>
            {{else}}
              <span data-test-explanation-search-no-fragment>Nothing.</span>
            {{/if}}
          </dd>
          <dt>Index</dt>
          <dd data-test-explanation-search-index>{{this.indexLag}}</dd>
        </dl>
      {{/if}}
      {{#if this.explanation.rules.length}}
        <ol class='matched' data-test-explanation-rules>
          {{#each this.explanation.rules as |rule ruleIndex|}}
            <li class='matched-rule' data-test-explanation-rule>
              <span class='type-name'>{{rule.targetType.name}}</span>
              <span class='type-module'>{{rule.targetType.module}}</span>
              {{#if rule.grants.length}}
                <ul class='matched-grants'>
                  {{#each rule.grants as |grant grantIndex|}}
                    <li
                      class='matched-grant
                        {{if
                          (this.isAdmitting ruleIndex grantIndex)
                          "admitting"
                        }}'
                      data-test-explanation-grant={{grant.outcome}}
                      data-test-explanation-grant-filterable={{this.filterableState
                        grant
                      }}
                    >
                      {{#if grant.where}}
                        <code
                          class='where'
                          data-test-explanation-grant-where
                        >{{grant.where}}</code>
                        {{#if (this.showsTier grant)}}
                          <span class='tier'>{{this.tierLabel
                              grant.tier
                            }}</span>
                        {{/if}}
                      {{/if}}
                      <span
                        class='outcome'
                        data-test-explanation-grant-label
                      >{{this.grantLabel grant}}</span>
                      {{#if (this.isAdmitting ruleIndex grantIndex)}}
                        <Pill
                          @variant='primary'
                          data-test-explanation-admitting
                        >allowed it</Pill>
                      {{/if}}
                      {{#let (this.grantDetail grant) as |detail|}}
                        {{#if detail.anonymous}}
                          <p
                            class='grant-note'
                            data-test-explanation-grant-anonymous
                          >{{this.actingUserLine detail.anonymous}}</p>
                        {{/if}}
                        {{#each detail.issues as |issue|}}
                          <div
                            class='grant-issue'
                            data-test-explanation-grant-issue={{issue.code}}
                          >
                            <Pill
                              @tag='span'
                              @pillBackgroundColor='var(--warning, var(--boxel-warning))'
                              @pillBorderColor='var(--warning, var(--boxel-warning))'
                              @pillFontColor='var(--warning-foreground, var(--boxel-dark))'
                            >{{issue.severity}}</Pill>
                            <MessageText @message={{issue.message}} />
                          </div>
                        {{/each}}
                      {{/let}}
                    </li>
                  {{/each}}
                </ul>
              {{else}}
                <p class='empty'>No grant for this operation.</p>
              {{/if}}
            </li>
          {{/each}}
        </ol>
      {{/if}}
    </div>
    <style scoped>
      .explanation {
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .verdict {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      .facts {
        display: grid;
        grid-template-columns: max-content 1fr;
        gap: var(--boxel-sp-xxs) var(--boxel-sp);
        margin: 0;
      }
      .facts dt {
        color: var(--muted-foreground, var(--boxel-450));
      }
      .facts dd {
        margin: 0;
        min-width: 0;
        overflow-wrap: anywhere;
      }
      .json {
        margin: 0;
        padding: var(--boxel-sp-xs);
        background-color: var(--muted, var(--boxel-100));
        border-radius: var(--boxel-border-radius-sm);
        font-family: var(--boxel-monospace-font-family, monospace);
        font-size: var(--boxel-font-size-xs);
        white-space: pre-wrap;
        overflow-wrap: anywhere;
      }
      .note {
        margin: 0 0 var(--boxel-sp-xxs);
      }
      .matched,
      .matched-grants {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .matched-grants {
        padding-left: var(--boxel-sp);
      }
      .matched-rule {
        padding: var(--boxel-sp-sm);
        border: 1px solid var(--border, var(--boxel-border-color));
        border-radius: var(--boxel-border-radius);
      }
      .matched-grant {
        display: flex;
        align-items: baseline;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      .matched-grant.admitting {
        font-weight: 600;
      }
      .grant-note,
      .grant-issue {
        flex-basis: 100%;
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: normal;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .grant-issue {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
      }
      .facts .warning {
        color: var(--warning-foreground, var(--boxel-dark));
      }
      .type-name {
        font-weight: 600;
        margin-right: var(--boxel-sp-xs);
      }
      .type-module,
      .where {
        font-family: var(--boxel-monospace-font-family, monospace);
        font-size: var(--boxel-font-size-xs);
        overflow-wrap: anywhere;
      }
      .tier,
      .outcome,
      .empty {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .empty {
        margin: 0;
      }
    </style>
  </template>
}

// What the panel asks about: one card, a search a realm runs, or a page of
// the cards in a realm.
type ExplainMode = 'card' | 'search' | 'listing';

const MODES: { id: ExplainMode; label: string }[] = [
  { id: 'card', label: 'One card' },
  { id: 'search', label: 'A search' },
  { id: 'listing', label: 'Every card in a realm' },
];

// A search's filter as a search request writes it: here, every card of one
// type.
const FILTER_PLACEHOLDER = asJson({
  'item.on': { module: 'https://…/classroom', name: 'Classroom' },
});

// How many cards one page of a listing explains.
const LISTING_PAGE_SIZE = 10;

// A listing question as it was last asked, so paging through it asks the same
// question of the next page whatever has been typed since.
interface AskedListing {
  question: { actor: string; target: string; operation: string };
  on?: { module: string; name: string };
  draft?: Record<string, unknown>;
}

// Asks the realm what this policy decides, without invoking anything: for one
// caller, one card and one operation; for what a search would return to a
// caller; or for every card on one page of a realm. Each can be asked of a
// draft instead of the policy in force. Only a caller who can read both this
// card's realm and the realm asked about is answered; anyone else is told the
// target is not there, so a caller who cannot read a realm learns nothing
// about it this way.
interface ExplainPanelSignature {
  Args: { policy: RealmPolicy };
}

class ExplainPanel extends GlimmerComponent<ExplainPanelSignature> {
  @tracked mode: ExplainMode = 'card';
  @tracked actor = '';
  @tracked target = '';
  @tracked realmTarget: string | undefined;
  @tracked operationName = '';
  @tracked typeModule = '';
  @tracked typeName = '';
  @tracked searchParams = '';
  @tracked searchFilter = '';
  @tracked useDraft = false;
  @tracked draft = '';
  @tracked explanation: PolicyExplanation | undefined;
  @tracked listing: PolicyExplanationListing | undefined;
  @tracked refusal: string | undefined;
  @tracked running = false;
  private askedListing: AskedListing | undefined;

  get isCard() {
    return this.mode === 'card';
  }

  get isSearch() {
    return this.mode === 'search';
  }

  get isListing() {
    return this.mode === 'listing';
  }

  // A search or a listing runs in a realm, which starts as this card's own.
  get realmTargetValue(): string {
    return this.realmTarget ?? this.args.policy[realmURL]?.href ?? '';
  }

  // An ad-hoc search runs under the reserved name `query` and is named by its
  // filter. Any other search is a named query, named by the type that
  // declares it.
  get isAdHocSearch() {
    return this.operationName.trim() === 'query';
  }

  get hasType(): boolean {
    return this.typeModule.trim().length > 0 && this.typeName.trim().length > 0;
  }

  get canAsk(): boolean {
    if (this.running || this.operationName.trim().length === 0) {
      return false;
    }
    switch (this.mode) {
      case 'card':
        return this.target.trim().length > 0;
      case 'search':
        return (
          this.realmTargetValue.trim().length > 0 &&
          (this.isAdHocSearch
            ? this.searchFilter.trim().length > 0
            : this.hasType)
        );
      case 'listing':
        // A listing names a type or none, never half of one.
        return (
          this.realmTargetValue.trim().length > 0 &&
          (this.hasType ||
            (this.typeModule.trim().length === 0 &&
              this.typeName.trim().length === 0))
        );
    }
  }

  get cannotAsk(): boolean {
    return !this.canAsk;
  }

  // What compiling the draft recorded, where the answer was asked of one. An
  // empty list is an answer too: the draft compiled cleanly.
  get draftIssues(): DraftIssue[] | undefined {
    return (this.explanation ?? this.listing)?.draft?.issues;
  }

  get answeredAgainstDraft(): boolean {
    return this.draftIssues !== undefined;
  }

  get draftIssueList(): DraftIssue[] {
    return this.draftIssues ?? [];
  }

  get pageSummary(): string | undefined {
    let listing = this.listing;
    if (!listing) {
      return undefined;
    }
    let { number, size, total } = listing.page;
    if (listing.explanations.length === 0) {
      return total === 0
        ? 'There are no cards to explain.'
        : `There are no cards on this page. The realm has ${total}.`;
    }
    let first = number * size + 1;
    let last = number * size + listing.explanations.length;
    return `Cards ${first} to ${last} of ${total}`;
  }

  get isFirstPage(): boolean {
    return !this.listing || this.listing.page.number === 0;
  }

  get isLastPage(): boolean {
    let listing = this.listing;
    if (!listing) {
      return true;
    }
    let { number, size, total } = listing.page;
    return (number + 1) * size >= total;
  }

  get noEarlierPage() {
    return this.running || this.isFirstPage;
  }

  get noLaterPage() {
    return this.running || this.isLastPage;
  }

  // The mode can't change while an ask is out: its answer belongs to the
  // form that asked it.
  chooseMode = (mode: ExplainMode) => {
    if (this.running) {
      return;
    }
    this.mode = mode;
    this.clearAnswer();
  };

  updateActor = (value: string) => {
    this.actor = value;
  };

  updateTarget = (value: string) => {
    this.target = value;
  };

  updateRealmTarget = (value: string) => {
    this.realmTarget = value;
  };

  updateOperation = (value: string) => {
    this.operationName = value;
  };

  updateTypeModule = (value: string) => {
    this.typeModule = value;
  };

  updateTypeName = (value: string) => {
    this.typeName = value;
  };

  updateSearchParams = (value: string) => {
    this.searchParams = value;
  };

  updateSearchFilter = (value: string) => {
    this.searchFilter = value;
  };

  updateDraft = (value: string) => {
    this.draft = value;
  };

  // A draft starts as this card's own rules, the usual place to start
  // changing them from.
  toggleDraft = (event: Event) => {
    this.useDraft = (event.target as HTMLInputElement).checked;
    if (this.useDraft && this.draft.trim().length === 0) {
      this.draft = startingDraft(this.args.policy);
    }
  };

  resetDraft = () => {
    this.draft = startingDraft(this.args.policy);
  };

  private clearAnswer() {
    this.refusal = undefined;
    this.explanation = undefined;
    this.listing = undefined;
  }

  private get question() {
    return {
      actor: this.actor.trim(),
      target: this.isCard ? this.target.trim() : this.realmTargetValue.trim(),
      operation: this.operationName.trim(),
    };
  }

  private get type() {
    return this.hasType
      ? { module: this.typeModule.trim(), name: this.typeName.trim() }
      : undefined;
  }

  private get searchQuestion(): Record<string, unknown> {
    if (this.isAdHocSearch) {
      return { filter: parseObject(this.searchFilter, 'The filter') };
    }
    let params = this.searchParams.trim();
    return {
      on: this.type,
      ...(params.length > 0
        ? { params: parseObject(params, 'The params') }
        : {}),
    };
  }

  private get draftDocument(): Record<string, unknown> | undefined {
    return this.useDraft ? parseObject(this.draft, 'The draft') : undefined;
  }

  // Runs one ask, showing what the realm answered or why it refused. The
  // answer to an earlier ask is cleared first, so it is never shown as the
  // answer to this one.
  private async run(ask: () => Promise<void>) {
    this.running = true;
    this.clearAnswer();
    try {
      await ask();
    } catch (err) {
      this.refusal = failureMessage(err);
    } finally {
      this.running = false;
    }
  }

  explain = async (event?: Event) => {
    event?.preventDefault();
    if (!this.canAsk) {
      return;
    }
    await this.run(async () => {
      let ops = operations<typeof RealmPolicy>(this.args.policy);
      let question = this.question;
      let draft = this.draftDocument;
      switch (this.mode) {
        case 'card':
          this.explanation = draft
            ? await ops.explainDraft({ ...question, draft })
            : await ops.explain(question);
          return;
        case 'search': {
          let search = this.searchQuestion;
          this.explanation = draft
            ? await ops.explainDraftSearch({ ...question, search, draft })
            : await ops.explainSearch({ ...question, search });
          return;
        }
        case 'listing': {
          let on = this.type;
          this.askedListing = {
            question,
            ...(on ? { on } : {}),
            ...(draft ? { draft } : {}),
          };
          this.listing = await this.askListing(this.askedListing, 0);
          return;
        }
      }
    });
  };

  private async askListing(
    asked: AskedListing,
    number: number,
  ): Promise<PolicyExplanationListing> {
    let ops = operations<typeof RealmPolicy>(this.args.policy);
    let list = {
      ...(asked.on ? { on: asked.on } : {}),
      page: { number, size: LISTING_PAGE_SIZE },
    };
    return asked.draft
      ? await ops.explainDraftListing({
          ...asked.question,
          list,
          draft: asked.draft,
        })
      : await ops.explainListing({ ...asked.question, list });
  }

  private turnPage = async (by: number) => {
    let asked = this.askedListing;
    let current = this.listing;
    if (!asked || !current || this.running) {
      return;
    }
    let number = current.page.number + by;
    await this.run(async () => {
      this.listing = await this.askListing(asked, number);
    });
  };

  previousPage = () => this.turnPage(-1);

  nextPage = () => this.turnPage(1);

  <template>
    <form
      class='explain'
      data-test-realm-policy-explain-form
      {{on 'submit' this.explain}}
    >
      <RadioInput
        @groupDescription='Ask about'
        @items={{MODES}}
        @name='explain-mode'
        @checkedId={{this.mode}}
        @disabled={{this.running}}
        @orientation='horizontal'
        as |item|
      >
        <item.component
          @onChange={{fn this.chooseMode item.data.id}}
          data-test-explain-mode={{item.data.id}}
        >
          {{item.data.label}}
        </item.component>
      </RadioInput>
      <FieldContainer
        @label='Person (user ID)'
        @vertical={{true}}
        @fieldId='explain-actor'
      >
        <BoxelInput
          @id='explain-actor'
          @value={{this.actor}}
          @onInput={{this.updateActor}}
          @placeholder='@teacher:example.org'
          data-test-explain-actor
        />
      </FieldContainer>
      <p class='hint' data-test-explain-actor-hint>
        Leave this empty to check what someone who isn't signed in can do.
      </p>
      {{#if this.isCard}}
        <FieldContainer
          @label='Card (URL)'
          @vertical={{true}}
          @fieldId='explain-target'
        >
          <BoxelInput
            @id='explain-target'
            @value={{this.target}}
            @onInput={{this.updateTarget}}
            data-test-explain-target
          />
        </FieldContainer>
      {{else}}
        <FieldContainer
          @label='Realm (URL)'
          @vertical={{true}}
          @fieldId='explain-realm'
        >
          <BoxelInput
            @id='explain-realm'
            @value={{this.realmTargetValue}}
            @onInput={{this.updateRealmTarget}}
            data-test-explain-realm
          />
        </FieldContainer>
      {{/if}}
      <FieldContainer
        @label={{if this.isSearch 'Search operation' 'Operation'}}
        @vertical={{true}}
        @fieldId='explain-operation'
      >
        <BoxelInput
          @id='explain-operation'
          @value={{this.operationName}}
          @onInput={{this.updateOperation}}
          @placeholder={{if this.isSearch 'query' 'read'}}
          data-test-explain-operation
        />
      </FieldContainer>
      {{#if this.isSearch}}
        <p class='hint'>
          Name a search a card type declares, or
          <code>query</code>
          for a search by filter.
        </p>
      {{/if}}
      {{#if (showType this.mode this.isAdHocSearch)}}
        <div class='type-fields'>
          <FieldContainer
            @label={{if
              this.isSearch
              'Card type that declares it (module URL)'
              'Only cards of this type (module URL, optional)'
            }}
            @vertical={{true}}
            @fieldId='explain-type-module'
          >
            <BoxelInput
              @id='explain-type-module'
              @value={{this.typeModule}}
              @onInput={{this.updateTypeModule}}
              data-test-explain-type-module
            />
          </FieldContainer>
          <FieldContainer
            @label='Type name'
            @vertical={{true}}
            @fieldId='explain-type-name'
          >
            <BoxelInput
              @id='explain-type-name'
              @value={{this.typeName}}
              @onInput={{this.updateTypeName}}
              data-test-explain-type-name
            />
          </FieldContainer>
        </div>
      {{/if}}
      {{#if this.isSearch}}
        {{#if this.isAdHocSearch}}
          <FieldContainer
            @label='Filter (JSON)'
            @vertical={{true}}
            @fieldId='explain-search-filter'
          >
            <BoxelInput
              @id='explain-search-filter'
              @type='textarea'
              @value={{this.searchFilter}}
              @onInput={{this.updateSearchFilter}}
              @placeholder={{FILTER_PLACEHOLDER}}
              data-test-explain-search-filter
            />
          </FieldContainer>
        {{else}}
          <FieldContainer
            @label='Params (JSON, optional)'
            @vertical={{true}}
            @fieldId='explain-search-params'
          >
            <BoxelInput
              @id='explain-search-params'
              @type='textarea'
              @value={{this.searchParams}}
              @onInput={{this.updateSearchParams}}
              data-test-explain-search-params
            />
          </FieldContainer>
        {{/if}}
      {{/if}}
      <label class='draft-toggle'>
        <input
          type='checkbox'
          checked={{this.useDraft}}
          {{on 'change' this.toggleDraft}}
          data-test-explain-use-draft
        />
        Answer against a draft of this policy
      </label>
      {{#if this.useDraft}}
        <FieldContainer
          @label='Draft (JSON)'
          @vertical={{true}}
          @fieldId='explain-draft'
        >
          <BoxelInput
            @id='explain-draft'
            @type='textarea'
            @value={{this.draft}}
            @onInput={{this.updateDraft}}
            class='draft-input'
            data-test-explain-draft
          />
        </FieldContainer>
        <p class='hint'>
          The draft is checked as if this card held it, for this answer only.
          The policy in force doesn't change.
          <Button
            @kind='text-only'
            @size='extra-small'
            type='button'
            {{on 'click' this.resetDraft}}
            data-test-explain-draft-reset
          >Start again from this card's rules</Button>
        </p>
      {{/if}}
      <Button
        @kind='primary'
        @size='small'
        @loading={{this.running}}
        @disabled={{this.cannotAsk}}
        type='submit'
        data-test-explain-submit
      >
        Explain
      </Button>
    </form>

    {{#if this.refusal}}
      <p class='refusal' role='alert' data-test-explain-refusal>
        {{this.refusal}}
      </p>
    {{/if}}

    {{#if this.answeredAgainstDraft}}
      <DraftIssues @issues={{this.draftIssueList}} />
    {{/if}}

    {{#if this.explanation}}
      <div class='answer'>
        <ExplanationView @explanation={{this.explanation}} />
      </div>
    {{/if}}

    {{#if this.listing}}
      <div class='answer listing' data-test-explanation-listing>
        <p class='page' data-test-explanation-listing-page>
          {{this.pageSummary}}
        </p>
        {{#if this.listing.explanations.length}}
          <ol class='listed'>
            {{#each this.listing.explanations as |entry|}}
              <li data-test-explanation-listed={{entry.target}}>
                <details class='listed-entry'>
                  <summary class='listed-summary'>
                    <Pill
                      @tag='span'
                      @variant={{decisionVariant entry.decision}}
                      data-test-explanation-listed-decision
                    >{{entry.decision}}</Pill>
                    <span class='listed-target'>{{entry.target}}</span>
                  </summary>
                  <ExplanationView @explanation={{entry}} />
                </details>
              </li>
            {{/each}}
          </ol>
        {{/if}}
        <nav class='pager' aria-label='Pages'>
          <Button
            @size='extra-small'
            @disabled={{this.noEarlierPage}}
            {{on 'click' this.previousPage}}
            data-test-explanation-listing-previous
          >Previous</Button>
          <Button
            @size='extra-small'
            @disabled={{this.noLaterPage}}
            {{on 'click' this.nextPage}}
            data-test-explanation-listing-next
          >Next</Button>
        </nav>
      </div>
    {{/if}}
    <style scoped>
      .explain {
        display: grid;
        gap: var(--boxel-sp-sm);
        justify-items: start;
      }
      .explain > :deep(.boxel-field),
      .explain > :deep(.boxel-radio-fieldset),
      .type-fields {
        width: 100%;
      }
      .type-fields {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
        gap: var(--boxel-sp-sm);
      }
      .hint {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .draft-toggle {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .draft-input {
        font-family: var(--boxel-monospace-font-family, monospace);
        font-size: var(--boxel-font-size-xs);
        min-height: 12rem;
      }
      .refusal {
        margin: var(--boxel-sp-sm) 0 0;
        color: var(--destructive, var(--boxel-danger));
      }
      .answer {
        margin-top: var(--boxel-sp);
      }
      .listing {
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .page {
        margin: 0;
        font-weight: 600;
      }
      .listed {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .listed-entry {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--border, var(--boxel-border-color));
        border-radius: var(--boxel-border-radius);
      }
      .listed-entry[open] > .listed-summary {
        margin-bottom: var(--boxel-sp-sm);
      }
      .listed-summary {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        cursor: pointer;
      }
      .listed-target {
        font-family: var(--boxel-monospace-font-family, monospace);
        font-size: var(--boxel-font-size-xs);
        overflow-wrap: anywhere;
      }
      .pager {
        display: flex;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}

// A named query and a listing name a card type; an ad-hoc search names its
// types in its filter instead.
function showType(mode: ExplainMode, adHoc: boolean): boolean {
  return mode === 'listing' || (mode === 'search' && !adHoc);
}

// Whether this is a render someone is looking at, rather than the render
// indexing takes of a card. What an index render shows is served to every
// later viewer, and it runs while the card itself is being indexed, so asking
// the realm what the card compiles to there would answer for the visit before
// this one.
function isLiveRender(): boolean {
  return !(globalThis as { __boxelRenderContext?: unknown })
    .__boxelRenderContext;
}

// What an issue about the card as a whole means, said of the card itself.
// The compiler writes its message about any policy card that names it, so an
// issue with no wording here reads as the compiler wrote it.
const CARD_ISSUE_MESSAGES: Partial<Record<string, string>> = {
  'policy-card-unloadable':
    "This card couldn't be indexed this time, and the index's earlier copy of it may be out of date. It grants nothing until it's indexed again.\n\nThe realm tries again on its own, and editing the card or reindexing the realm tries again right away.",
};

// Whether a realm event says the realm has finished an index pass.
function isIndexPass(event: { eventName: string; indexType?: string }) {
  return (
    event.eventName === 'index' &&
    (event.indexType === 'incremental' || event.indexType === 'full')
  );
}

// What the realm answered when asked what this card compiles to.
type ValidationState = {
  validation: PolicyValidation | undefined;
  failure: string | undefined;
};

// What every explain asks: what this policy decides for `actor`, a user id
// or an empty string for a caller who isn't signed in, invoking `operation` on
// `target`.
const EXPLAIN_QUESTION = {
  actor: StringField,
  target: StringField,
  operation: StringField,
};

export class RealmPolicy extends CardDef {
  static displayName = 'Realm Policy';
  static icon = ShieldCheckIcon;

  @field rules = containsMany(PolicyRule);

  // A policy card is authorization infrastructure. Whoever can write one
  // decides what every realm whose policy key names it grants. So no policy
  // grant may write one, and each write is open only to a caller the realm's
  // own permissions let write. These are the writes a card carries, declared
  // in their built-in form so they can be marked. Each does what it does on
  // any other card.
  //
  // The realm refuses more than these marks reach. A grant never admits a
  // write to a card of this type or of any subtype, under whatever name the
  // write is invoked, and never admits a create that mints one. That covers a
  // subtype's own named writes, which it need not mark. It also covers a card
  // no realm's policy key names: a draft, or a card that only another realm's
  // policy key names.
  @operation static update = {
    base: 'update',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  @operation static delete = {
    base: 'delete',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  @operation static transform = {
    base: 'transform',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  @operation static appendContainsMany = {
    base: 'appendContainsMany',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  // What this policy decides for one caller, one card and one operation, as
  // the realm that holds the card decides it, without invoking anything. The
  // realm answers only for a card whose realm names this policy, and only to a
  // caller who can read both realms. No policy may grant it, since what it
  // answers is what a refusal withholds.
  @operation static explain = {
    base: 'explain',
    params: EXPLAIN_QUESTION,
    nonGrantable: true,
  } satisfies OperationDeclaration;

  // The forms below ask what a single question against the policy in force
  // can't. Each is its own declaration because a declared param is always
  // required, and each is typed for what it answers. None of them may be
  // granted, for the reason `explain` may not be.
  //
  // `explain`, answered against `draft`: a policy document holding the
  // `rules` this card holds, which the realm compiles in this card's place
  // for this answer alone. A relative module in it resolves against this
  // card. Nothing caches the draft and the policy in force doesn't change.
  // The answer carries what compiling the draft recorded. The realm answers
  // only a caller who can read every realm the draft's types live in.
  @operation static explainDraft = {
    base: 'explain',
    params: { ...EXPLAIN_QUESTION, draft: JsonField },
    nonGrantable: true,
  } satisfies OperationDeclaration;

  // What a search would return to a caller, asked of the realm it runs in,
  // which is the `target`. `search` is `{ on, params }` for a named query, by
  // the type that declares it, or `{ filter }` for an ad-hoc search, asked
  // as `query`. The answer says what this policy composes into the search
  // and how far behind its source the index the search reads is.
  @operation static explainSearch = {
    base: 'explain',
    params: { ...EXPLAIN_QUESTION, search: JsonField },
    nonGrantable: true,
  } satisfies OperationDeclaration;

  @operation static explainDraftSearch = {
    base: 'explain',
    params: { ...EXPLAIN_QUESTION, search: JsonField, draft: JsonField },
    nonGrantable: true,
  } satisfies OperationDeclaration;

  // One page of the cards in the realm that is the `target`, each explained
  // as its own question. `list` is `{ on?, page?: { number?, size? } }`: the
  // type to list, or every type, and a page of at most 100 cards, which is
  // also the most explanations one request may ask for, a batch included.
  @operation static explainListing = {
    base: 'explain',
    params: { ...EXPLAIN_QUESTION, list: JsonField },
    nonGrantable: true,
  } satisfies OperationDeclaration;

  @operation static explainDraftListing = {
    base: 'explain',
    params: { ...EXPLAIN_QUESTION, list: JsonField, draft: JsonField },
    nonGrantable: true,
  } satisfies OperationDeclaration;

  // What this policy compiles to, as a realm that names it compiles it: every
  // issue compiling records, and the rules and grants that compile, which are
  // the ones in force. Nothing is invoked or activated. No policy may grant
  // it, since only a caller who can read this card may learn what it holds.
  @operation static validate = {
    base: 'validate',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  static isolated = class Isolated extends Component<typeof RealmPolicy> {
    // `@model` is typed with every field optional, for a card still loading,
    // and an explain is asked of the loaded card.
    get policy(): RealmPolicy {
      return this.args.model as RealmPolicy;
    }

    get rules(): PolicyRule[] {
      return this.args.model.rules ?? [];
    }

    // Whether someone is looking at this view, decided when it is created. A
    // page that indexes cards itself can be partway through an index render of
    // another card when this view asks again.
    private isLive = isLiveRender();

    // What the card compiles to, asked of the realm as soon as someone looks
    // at it, and again after each index pass of a realm the compile read: the
    // card's own, and each realm a type its rules name lives in. That is when
    // an edit to the card, or to one of those types, takes effect. It is the
    // realm's compile, so it is what a realm naming this card holds in force.
    // Only the latest ask's answer is shown, whichever order the answers
    // arrive in.
    private validationState = use(
      this,
      resource(({ on }) => {
        let state = new TrackedObject<ValidationState>({
          validation: undefined,
          failure: undefined,
        });
        let policy = this.policy;
        if (!this.isLive || !policy.id) {
          return state;
        }
        let latest = 0;
        let ended = false;
        let watched = new Map<string, () => void>();
        // Watches exactly these realms: the card's own until the realm has
        // answered, then the ones each answer names.
        let watch = (realms: string[]) => {
          if (ended) {
            return;
          }
          for (let [realm, unsubscribe] of watched) {
            if (!realms.includes(realm)) {
              unsubscribe();
              watched.delete(realm);
            }
          }
          for (let realm of realms) {
            if (!watched.has(realm)) {
              watched.set(
                realm,
                subscribeToRealm(realm, (event) => {
                  if (isIndexPass(event)) {
                    ask();
                  }
                }),
              );
            }
          }
        };
        let ask = async () => {
          let asked = ++latest;
          try {
            let validation =
              await operations<typeof RealmPolicy>(policy).validate();
            if (asked === latest) {
              state.validation = validation;
              state.failure = undefined;
              watch(validation.realms);
            }
          } catch (err) {
            if (asked === latest) {
              state.validation = undefined;
              state.failure = failureMessage(err);
            }
          }
        };
        on.cleanup(() => {
          ended = true;
          for (let unsubscribe of watched.values()) {
            unsubscribe();
          }
          watched.clear();
        });
        let ownRealm = policy[realmURL]?.href;
        watch(ownRealm ? [ownRealm] : []);
        ask();
        return state;
      }),
    );

    get validation(): PolicyValidation | undefined {
      return this.validationState.current.validation;
    }

    get validationFailure(): string | undefined {
      return this.validationState.current.failure;
    }

    get uncompilable(): boolean {
      return this.validation?.uncompilable === true;
    }

    // Why the policy did not compile: the issue about the card as a whole.
    get uncompilableReason(): string | undefined {
      let issue = this.validation?.issues.find(
        (issue) => issue.rule === undefined,
      );
      return issue ? this.issueMessage(issue) : undefined;
    }

    issueMessage = (issue: PolicyValidation['issues'][number]): string =>
      (issue.rule === undefined
        ? CARD_ISSUE_MESSAGES[issue.code]
        : undefined) ?? issue.message;

    get issues(): PolicyValidation['issues'] {
      return this.validation?.issues ?? [];
    }

    // A rule that did not compile, with every grant in it. An uncompilable
    // policy says so once, above the rules, rather than on each of them.
    isRuleInactive = (ruleIndex: number): boolean => {
      let validation = this.validation;
      return (
        validation !== undefined &&
        !validation.uncompilable &&
        !validation.rules.some((rule) => rule.path === `rules[${ruleIndex}]`)
      );
    };

    isRuleOutOfForce = (ruleIndex: number): boolean =>
      this.uncompilable || this.isRuleInactive(ruleIndex);

    // The grant as the realm compiled it, or undefined for one that did not
    // compile.
    compiledGrant = (
      ruleIndex: number,
      grantIndex: number,
    ): PolicyValidation['rules'][number]['grants'][number] | undefined => {
      let rulePath = `rules[${ruleIndex}]`;
      let grantPath = `${rulePath}.grants[${grantIndex}]`;
      return this.validation?.rules
        .find((rule) => rule.path === rulePath)
        ?.grants.find((grant) => grant.path === grantPath);
    };

    // Where the grant stands, once the realm has answered: live, or inactive
    // because it did not compile or because it compiled and admits nothing.
    // Undefined before the realm answers.
    grantStatus = (
      ruleIndex: number,
      grantIndex: number,
    ): 'live' | 'inactive' | undefined => {
      if (!this.validation) {
        return undefined;
      }
      let grant = this.compiledGrant(ruleIndex, grantIndex);
      return grant && !grant.admitsNothing ? 'live' : 'inactive';
    };

    // A grant left out on its own. One in a rule left out, or in a policy
    // that did not compile, is marked where the rule or the policy is.
    isGrantInactive = (ruleIndex: number, grantIndex: number): boolean =>
      !this.isRuleOutOfForce(ruleIndex) &&
      this.grantStatus(ruleIndex, grantIndex) === 'inactive';

    isGrantOutOfForce = (ruleIndex: number, grantIndex: number): boolean =>
      this.isRuleOutOfForce(ruleIndex) ||
      this.grantStatus(ruleIndex, grantIndex) === 'inactive';

    // The warnings on a live grant: what it hands over that its author should
    // know about, such as cards of a type no rule grants. A warning leaves its
    // grant live, so it is marked only on a grant that is. One on a grant that
    // admits nothing describes cards that grant never hands over, and is only
    // listed with the issues.
    grantWarnings = (
      ruleIndex: number,
      grantIndex: number,
    ): PolicyValidation['issues'] =>
      this.grantStatus(ruleIndex, grantIndex) === 'live'
        ? this.issues.filter(
            (issue) =>
              this.isWarning(issue) &&
              issue.rule === ruleIndex &&
              issue.grant === grantIndex,
          )
        : [];

    warningLabel = (warnings: PolicyValidation['issues']): string =>
      warnings.length === 1 ? 'warning' : `${warnings.length} warnings`;

    isWarning = (issue: PolicyValidation['issues'][number]): boolean =>
      issue.severity === 'warning';

    // The rule and the grant an issue is about, named as the card names them,
    // so an author can find the one bad grant among many.
    issueRuleName = (
      issue: PolicyValidation['issues'][number],
    ): string | undefined =>
      issue.rule === undefined
        ? undefined
        : (this.rules[issue.rule]?.targetType?.name ??
          `rule ${issue.rule + 1}`);

    issueOperation = (
      issue: PolicyValidation['issues'][number],
    ): string | undefined =>
      issue.rule === undefined || issue.grant === undefined
        ? undefined
        : this.rules[issue.rule]?.grants?.[issue.grant]?.operation ||
          `grant ${issue.grant + 1}`;

    grantComponent = (grant: OperationGrant) =>
      (grant.constructor as typeof OperationGrant).getComponent(grant);

    <template>
      <article class='realm-policy' data-test-realm-policy-isolated>
        <header class='header'>
          <ShieldCheckIcon class='icon' />
          <h1 class='title'>{{@model.cardTitle}}</h1>
        </header>
        <section class='section'>
          <h2 class='section-title'>Rules</h2>
          {{#if this.uncompilable}}
            <div
              class='not-in-force'
              role='alert'
              data-test-realm-policy-uncompilable
            >
              <p class='not-in-force-summary'>
                <strong>Not in force.</strong>
                This policy has a problem that stops it from working, so it
                grants nothing. A realm that uses it turns away everyone its own
                permissions don't already allow.
              </p>
              <MessageText @message={{this.uncompilableReason}} />
            </div>
          {{/if}}
          {{#if this.rules.length}}
            <ol class='rules' data-test-realm-policy-rules>
              {{#each this.rules as |rule ruleIndex|}}
                <li
                  class='rule
                    {{if (this.isRuleOutOfForce ruleIndex) "inactive"}}'
                  data-test-policy-rule
                >
                  <header class='target'>
                    {{#if rule.targetType}}
                      <span class='type-name' data-test-policy-rule-type-name>
                        {{rule.targetType.name}}
                      </span>
                      <span
                        class='type-module'
                        data-test-policy-rule-type-module
                      >
                        {{rule.targetType.module}}
                      </span>
                    {{else}}
                      <span class='type-name missing'>No target type</span>
                    {{/if}}
                    {{#if (this.isRuleInactive ruleIndex)}}
                      <Pill
                        @variant='destructive'
                        data-test-policy-rule-inactive
                      >inactive</Pill>
                    {{/if}}
                  </header>
                  {{#if rule.grants.length}}
                    <ul class='grants'>
                      {{#each rule.grants as |grant grantIndex|}}
                        <li
                          class='grant
                            {{if
                              (this.isGrantOutOfForce ruleIndex grantIndex)
                              "inactive"
                            }}'
                          data-test-policy-grant-status={{this.grantStatus
                            ruleIndex
                            grantIndex
                          }}
                        >
                          <span class='grant-body'>
                            {{#let (this.grantComponent grant) as |Grant|}}
                              <Grant @format='embedded' />
                            {{/let}}
                          </span>
                          {{#if (this.isGrantInactive ruleIndex grantIndex)}}
                            <Pill
                              @variant='destructive'
                              data-test-policy-grant-inactive
                            >inactive</Pill>
                          {{/if}}
                          {{#let
                            (this.grantWarnings ruleIndex grantIndex)
                            as |warnings|
                          }}
                            {{#if warnings.length}}
                              <details
                                class='grant-warnings'
                                data-test-policy-grant-warning
                              >
                                <summary class='grant-warnings-summary'>
                                  <Pill
                                    @tag='span'
                                    @pillBackgroundColor='var(--warning, var(--boxel-warning))'
                                    @pillBorderColor='var(--warning, var(--boxel-warning))'
                                    @pillFontColor='var(--warning-foreground, var(--boxel-dark))'
                                  >{{this.warningLabel warnings}}</Pill>
                                </summary>
                                <ul class='grant-warning-messages'>
                                  {{#each warnings as |warning|}}
                                    <li
                                      data-test-policy-grant-warning-message={{warning.code}}
                                    ><MessageText
                                        @message={{this.issueMessage warning}}
                                      /></li>
                                  {{/each}}
                                </ul>
                              </details>
                            {{/if}}
                          {{/let}}
                        </li>
                      {{/each}}
                    </ul>
                  {{else}}
                    <p class='empty' data-test-policy-rule-no-grants>No grants.</p>
                  {{/if}}
                </li>
              {{/each}}
            </ol>
          {{else}}
            <p class='empty' data-test-realm-policy-no-rules>
              This policy has no rules, so it grants nothing.
            </p>
          {{/if}}
        </section>
        {{#if this.issues.length}}
          <section class='section' data-test-realm-policy-issues>
            <h2 class='section-title'>Issues</h2>
            <p class='hint'>
              Problems found in this policy. A rule or grant marked inactive
              doesn't grant anything, but the rest of the policy still works. A
              warning doesn't turn its grant off: it points out something the
              grant shares that you might not expect.
            </p>
            <ul class='issues'>
              {{#each this.issues as |issue|}}
                <li class='issue' data-test-policy-issue={{issue.code}}>
                  <header class='issue-heading'>
                    <code class='issue-code'>{{issue.code}}</code>
                    {{#if (this.issueRuleName issue)}}
                      <span class='type-name' data-test-policy-issue-rule>
                        {{this.issueRuleName issue}}
                      </span>
                    {{/if}}
                    {{#if (this.issueOperation issue)}}
                      <code
                        class='issue-operation'
                        data-test-policy-issue-operation
                      >{{this.issueOperation issue}}</code>
                    {{/if}}
                    {{#if (this.isWarning issue)}}
                      <Pill
                        @tag='span'
                        @pillBackgroundColor='var(--warning, var(--boxel-warning))'
                        @pillBorderColor='var(--warning, var(--boxel-warning))'
                        @pillFontColor='var(--warning-foreground, var(--boxel-dark))'
                        data-test-policy-issue-warning
                      >warning</Pill>
                    {{/if}}
                  </header>
                  <div class='issue-message' data-test-policy-issue-message>
                    <MessageText @message={{this.issueMessage issue}} />
                  </div>
                </li>
              {{/each}}
            </ul>
          </section>
        {{else if this.validationFailure}}
          <p
            class='refusal'
            role='alert'
            data-test-realm-policy-validate-failure
          >
            This policy couldn't be checked:
            {{this.validationFailure}}
          </p>
        {{/if}}
        <section class='section' data-test-realm-policy-explain>
          <h2 class='section-title'>Explain a decision</h2>
          <p class='hint'>
            Check whether this policy lets a given person do something to a
            given card, what a search would return to them, or what it lets them
            do to each card in a realm. You can ask about a draft of this policy
            before you save it. Nothing is actually done to any card. You can
            ask only about a realm that uses this policy, and only if you can
            read both that realm and this one.
          </p>
          <ExplainPanel @policy={{this.policy}} />
        </section>
      </article>
      <style scoped>
        .realm-policy {
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
        }
        .header {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
        }
        .icon {
          width: var(--boxel-icon-lg);
          height: var(--boxel-icon-lg);
          flex-shrink: 0;
        }
        .title {
          font: 700 var(--boxel-font-lg);
          margin: 0;
        }
        .section-title {
          font: 600 var(--boxel-font);
          margin: 0 0 var(--boxel-sp-xs);
        }
        .rules {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp);
        }
        .rule {
          padding: var(--boxel-sp-sm);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius);
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .target,
        .grant,
        .issue-heading {
          display: flex;
          align-items: baseline;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .type-name {
          font-weight: 600;
        }
        .type-name.missing,
        .type-module {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .grant-warnings[open] {
          flex-basis: 100%;
        }
        .grant-warnings-summary {
          cursor: pointer;
          width: fit-content;
        }
        .grant-warning-messages {
          list-style: none;
          margin: var(--boxel-sp-xxs) 0 0;
          padding: 0 0 0 var(--boxel-sp-xs);
          border-left: 0.1875rem solid var(--warning, var(--boxel-warning));
          display: grid;
          gap: var(--boxel-sp-xxs);
          font-size: var(--boxel-font-size-sm);
          overflow-wrap: anywhere;
        }
        .type-module,
        .issue-code,
        .issue-operation {
          font-family: var(--boxel-monospace-font-family, monospace);
          font-size: var(--boxel-font-size-xs);
          overflow-wrap: anywhere;
        }
        .grants,
        .issues {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-xxs);
        }
        .grants {
          padding-left: var(--boxel-sp);
        }
        .issues {
          gap: var(--boxel-sp-sm);
        }
        .rule.inactive > .target > .type-name,
        .rule.inactive > .target > .type-module,
        .grant.inactive > .grant-body {
          opacity: 0.55;
          text-decoration: line-through;
        }
        .not-in-force,
        .refusal {
          margin: 0 0 var(--boxel-sp-sm);
          color: var(--destructive, var(--boxel-danger));
        }
        .not-in-force {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .not-in-force-summary {
          margin: 0;
        }
        .issue {
          padding: var(--boxel-sp-sm);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius);
        }
        .issue-message {
          margin: var(--boxel-sp-xxs) 0 0;
          overflow-wrap: anywhere;
        }
        .empty {
          margin: 0;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .hint {
          margin: 0 0 var(--boxel-sp-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof RealmPolicy> {
    <template>
      <div class='realm-policy' data-test-realm-policy-embedded>
        <h3 class='title'>{{@model.cardTitle}}</h3>
        {{#if @model.rules.length}}
          <ol class='rules' data-test-realm-policy-rules>
            {{#each @fields.rules as |Rule|}}
              <li class='rule'><Rule /></li>
            {{/each}}
          </ol>
        {{else}}
          <p class='empty' data-test-realm-policy-no-rules>
            This policy has no rules, so it grants nothing.
          </p>
        {{/if}}
      </div>
      <style scoped>
        .realm-policy {
          padding: var(--boxel-sp);
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .title {
          font: 600 var(--boxel-font);
          margin: 0;
        }
        .rules {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp);
        }
        .rule {
          padding: var(--boxel-sp-sm);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius);
        }
        .empty {
          margin: 0;
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  // The policy at a glance, for a card that shows the policy it names, such
  // as a realm's config card: its title, how many rules and grants it holds,
  // and, where there is room, each rule's card type with the operations it
  // grants.
  static fitted = class Fitted extends Component<typeof RealmPolicy> {
    get rules() {
      return this.args.model.rules ?? [];
    }

    get summary(): string {
      let ruleCount = this.rules.length;
      if (!ruleCount) {
        return 'No rules, so it grants nothing';
      }
      // A grant that names no operation grants nothing, and the rule lines
      // leave it out, so it is not counted.
      let grantCount = this.rules.reduce(
        (count, rule) =>
          count +
          (rule?.grants ?? []).filter((grant) => grant?.operation).length,
        0,
      );
      return `${ruleCount} ${ruleCount === 1 ? 'rule' : 'rules'} · ${grantCount} ${grantCount === 1 ? 'grant' : 'grants'}`;
    }

    // Each rule as the type it governs and the operations it grants, each
    // operation once.
    get ruleLines(): { type: string; operations: string }[] {
      return this.rules.map((rule) => ({
        type: rule?.targetType?.name ?? 'No target type',
        operations:
          [
            ...new Set(
              (rule?.grants ?? [])
                .map((grant) => grant?.operation)
                .filter((operation): operation is string => Boolean(operation)),
            ),
          ].join(', ') || 'no grants',
      }));
    }

    <template>
      <div class='fit' data-test-realm-policy-fitted>
        <ShieldCheckIcon class='f-icon' aria-hidden='true' />
        <span class='f-title' data-test-realm-policy-fitted-title>
          {{@model.cardTitle}}
        </span>
        <span class='f-summary' data-test-realm-policy-fitted-summary>
          {{this.summary}}
        </span>
        {{#if this.ruleLines.length}}
          <ul class='f-rules' data-test-realm-policy-fitted-rules>
            {{#each this.ruleLines as |line|}}
              <li class='f-rule'>
                <span class='f-rule-type'>{{line.type}}</span>
                {{line.operations}}
              </li>
            {{/each}}
          </ul>
        {{/if}}
      </div>
      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          padding: var(--boxel-sp-xs);
          display: grid;
          grid-template-columns: auto minmax(0, 1fr);
          grid-template-rows: auto auto minmax(0, 1fr);
          column-gap: var(--boxel-sp-xs);
          row-gap: var(--boxel-sp-4xs);
          align-items: center;
          overflow: hidden;
        }
        .f-icon {
          width: var(--boxel-icon-sm);
          height: var(--boxel-icon-sm);
          color: var(--foreground, var(--boxel-dark));
        }
        .f-title {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          line-height: var(--boxel-line-height-sm);
          color: var(--foreground, var(--boxel-dark));
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }
        .f-summary {
          grid-column: 1 / -1;
          font-size: var(--boxel-font-size-xs);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        /* The list fills what is left of the card. Lines that don't fit wrap
           into a column beyond its edge, so only whole lines show. */
        .f-rules {
          grid-column: 1 / -1;
          align-self: stretch;
          list-style: none;
          margin: var(--boxel-sp-4xs) 0 0;
          padding: 0;
          display: flex;
          flex-flow: column wrap;
          align-content: flex-start;
          gap: var(--boxel-sp-5xs) var(--boxel-sp);
          min-height: 0;
          overflow: hidden;
        }
        .f-rule {
          width: 100%;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .f-rule-type {
          font-weight: 600;
          color: var(--foreground, var(--boxel-dark));
        }
        /* badge: icon and a one-line title only, in one row */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .fit {
            grid-template-rows: none;
          }
          .f-summary,
          .f-rules {
            display: none;
          }
          .f-title {
            display: block;
            white-space: nowrap;
            text-overflow: ellipsis;
            font-size: var(--boxel-font-size-xs);
          }
        }
        /* strip: one row, the summary beside the title. Both columns grow
           from nothing toward their content, so they share the row rather
           than the summary taking all it wants first, and neither grows past
           its content, so the row stays packed against the icon. */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .fit {
            grid-template-columns:
              max-content minmax(0, max-content)
              minmax(0, max-content);
            grid-template-rows: none;
          }
          .f-title {
            display: block;
            white-space: nowrap;
            text-overflow: ellipsis;
          }
          .f-summary {
            grid-column: auto;
          }
          .f-rules {
            display: none;
          }
        }
      </style>
    </template>
  };
}
