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
} from 'https://cardstack.com/base/card-api';
import CodeRefField from 'https://cardstack.com/base/code-ref';
import {
  operation,
  operations,
  OperationsError,
  type OperationDeclaration,
  type PolicyExplanation,
  type PolicyValidation,
} from 'https://cardstack.com/base/operations';
import PolicyPredicateField from '@cardstack/catalog/fields/policy-predicate/policy-predicate';
import { subscribeToRealm } from '@cardstack/runtime-common';
import StringField from 'https://cardstack.com/base/string';
import {
  BoxelInput,
  Button,
  FieldContainer,
  Pill,
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
// reads it in.
const REASONS: Record<PolicyExplanation['reason'], string> = {
  acl: "The realm's own permissions allow this, so the policy is not consulted.",
  granted: 'A grant in this policy admits it.',
  'no-grant':
    "No rule governing the card's type has a grant for this operation.",
  'predicate-false':
    'Grants for this operation match the card, and none of their conditions holds.',
  'predicate-threw':
    "A grant's condition failed while it was evaluated, so the invocation fails.",
  'non-grantable': "This operation is kept out of every policy's reach.",
  'query-lane':
    "This operation is a query. It runs in a search rather than on one card, and the search returns only the cards this policy's grants on it admit.",
  'authorization-infrastructure':
    "No grant writes a policy card or the realm's config card, or creates a policy card.",
  'unmatchable-target':
    'No rule can apply to this target for this operation: its index entry records an error, so its type is unknown; it is a file and the operation is not a read of its bytes; or it is module source.',
  'not-resolved': 'The card does not carry this operation.',
  'actor-required':
    'A caller who presents no credentials is refused before the policy is consulted.',
  'policy-unloadable': "The realm's policy could not be loaded.",
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
  unconditional: 'always',
  held: 'held',
  'did-not-hold': 'did not hold',
  threw: 'threw',
  'not-evaluated': 'not evaluated',
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

// Asks the realm what this policy decides for one caller, one card and one
// operation. Nothing is invoked. Only a caller who can read both this card's
// realm and the card's realm is answered; anyone else is told the card is not
// there, so a caller who cannot read the card's realm learns nothing about it
// this way.
interface ExplainPanelSignature {
  Args: { policy: RealmPolicy };
}

class ExplainPanel extends GlimmerComponent<ExplainPanelSignature> {
  @tracked actor = '';
  @tracked target = '';
  @tracked operationName = '';
  @tracked explanation: PolicyExplanation | undefined;
  @tracked refusal: string | undefined;
  @tracked running = false;

  get canAsk(): boolean {
    return (
      !this.running &&
      this.target.trim().length > 0 &&
      this.operationName.trim().length > 0
    );
  }

  get cannotAsk(): boolean {
    return !this.canAsk;
  }

  get reason(): string | undefined {
    return this.explanation ? REASONS[this.explanation.reason] : undefined;
  }

  // What the realm's own permissions let the actor do. Write without read
  // is a shape the realm accepts, so it is named rather than read as both.
  get aclStanding(): string | undefined {
    let acl = this.explanation?.acl;
    if (!acl) {
      return undefined;
    }
    if (acl.read && acl.write) {
      return 'read and write';
    }
    if (acl.write) {
      return 'write, not read';
    }
    return acl.read ? 'read' : 'none';
  }

  get decisionVariant() {
    return this.explanation
      ? DECISION_VARIANT[this.explanation.decision]
      : 'muted';
  }

  isAdmitting = (ruleIndex: number, grantIndex: number): boolean =>
    this.explanation?.admittedBy?.rule === ruleIndex &&
    this.explanation?.admittedBy?.grant === grantIndex;

  outcomeLabel = (
    outcome: PolicyExplanation['rules'][number]['grants'][number]['outcome'],
  ) => OUTCOME_LABEL[outcome];

  updateActor = (value: string) => {
    this.actor = value;
  };

  updateTarget = (value: string) => {
    this.target = value;
  };

  updateOperation = (value: string) => {
    this.operationName = value;
  };

  explain = async (event?: Event) => {
    event?.preventDefault();
    if (!this.canAsk) {
      return;
    }
    this.running = true;
    this.refusal = undefined;
    this.explanation = undefined;
    try {
      this.explanation = await operations<typeof RealmPolicy>(
        this.args.policy,
      ).explain({
        actor: this.actor.trim(),
        target: this.target.trim(),
        operation: this.operationName.trim(),
      });
    } catch (err) {
      this.refusal = failureMessage(err);
    } finally {
      this.running = false;
    }
  };

  <template>
    <form
      class='explain'
      data-test-realm-policy-explain-form
      {{on 'submit' this.explain}}
    >
      <FieldContainer
        @label='Actor (user id)'
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
      <FieldContainer
        @label='Operation'
        @vertical={{true}}
        @fieldId='explain-operation'
      >
        <BoxelInput
          @id='explain-operation'
          @value={{this.operationName}}
          @onInput={{this.updateOperation}}
          @placeholder='read'
          data-test-explain-operation
        />
      </FieldContainer>
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

    {{#if this.explanation}}
      <div class='explanation' data-test-explanation>
        <header class='verdict'>
          <Pill
            @variant={{this.decisionVariant}}
            data-test-explanation-decision
          >
            {{this.explanation.decision}}
          </Pill>
          <span class='reason' data-test-explanation-reason>
            {{this.reason}}
          </span>
        </header>
        <dl class='facts'>
          <dt>Actor</dt>
          <dd data-test-explanation-actor>
            {{if
              this.explanation.actor
              this.explanation.actor
              'no credentials'
            }}
          </dd>
          <dt>Realm permissions</dt>
          <dd data-test-explanation-acl>{{this.aclStanding}}</dd>
          {{#if this.explanation.refusal}}
            <dt>Refused with</dt>
            <dd data-test-explanation-refusal>
              {{this.explanation.refusal.status}}
              <code>{{this.explanation.refusal.code}}</code>
            </dd>
          {{/if}}
        </dl>
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
                      >
                        {{#if grant.where}}
                          <code
                            class='where'
                            data-test-explanation-grant-where
                          >{{grant.where}}</code>
                          <span class='tier'>reads {{grant.tier}}</span>
                        {{/if}}
                        <span class='outcome'>{{this.outcomeLabel
                            grant.outcome
                          }}</span>
                        {{#if (this.isAdmitting ruleIndex grantIndex)}}
                          <Pill
                            @variant='primary'
                            data-test-explanation-admitting
                          >admitted</Pill>
                        {{/if}}
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
    {{/if}}
    <style scoped>
      .explain {
        display: grid;
        gap: var(--boxel-sp-sm);
        justify-items: start;
      }
      .explain > :deep(.boxel-field) {
        width: 100%;
      }
      .refusal {
        margin: var(--boxel-sp-sm) 0 0;
        color: var(--destructive, var(--boxel-danger));
      }
      .explanation {
        margin-top: var(--boxel-sp);
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
        overflow-wrap: anywhere;
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
// The compiler's own message is written for the log of a realm that names the
// card, so an issue with no wording here reads as the compiler wrote it.
const CARD_ISSUE_MESSAGES: Partial<Record<string, string>> = {
  'policy-card-unloadable':
    "This card's latest index visit failed, so what the index holds of it is an earlier visit's, which may not be what the card holds now. It grants nothing until a visit succeeds.",
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
    params: {
      actor: StringField,
      target: StringField,
      operation: StringField,
    },
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
            <p
              class='not-in-force'
              role='alert'
              data-test-realm-policy-uncompilable
            >
              <strong>Not in force.</strong>
              This policy could not be compiled, so it grants nothing, and a
              realm that names it refuses every caller its own permissions do
              not admit.
              {{this.uncompilableReason}}
            </p>
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
              What compiling this policy found. A rule or grant marked inactive
              grants nothing, and the rest of the policy applies.
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
                  </header>
                  <p class='issue-message' data-test-policy-issue-message>
                    {{this.issueMessage issue}}
                  </p>
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
            This policy could not be checked:
            {{this.validationFailure}}
          </p>
        {{/if}}
        <section class='section' data-test-realm-policy-explain>
          <h2 class='section-title'>Explain a decision</h2>
          <p class='hint'>
            What this policy decides for one caller, one card and one operation.
            Nothing is invoked. You can ask only about a card in a realm
            governed by this policy, and only if you can read both realms.
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
