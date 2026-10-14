import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { Alert } from '@cardstack/pretui/components/alert';
import { EmptyState } from '@cardstack/pretui/components/empty-state';

import {
  VendorProfile,
  VendorProfileStatusField,
} from '../procurement/vendor-profile';
import { StatusBoard } from '../../components/status-board';

// The isolated console, hoisted out of the card class so its fields can be
// @tracked.
class VendorOnboardingIsolated extends Component<typeof VendorOnboardingApp> {
  @tracked flash: string | undefined;

  private profileList: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.profileList = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(VendorProfile);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  private get realms(): string[] | undefined {
    let url = this.args.model?.[realmURL];
    return url ? [url.href] : undefined;
  }

  // CRUD functions reach the card only in interactive contexts, so their
  // absence marks prerender, where the board must not mount.
  get isInteractive() {
    return Boolean(this.args.viewCard);
  }

  get isLoading() {
    return Boolean(this.profileList?.isLoading);
  }

  get profiles(): VendorProfile[] {
    return ((this.profileList?.instances ?? []) as VendorProfile[]).filter(
      Boolean,
    );
  }

  get compliantCount() {
    return this.profiles.filter((p) => p.complianceOk).length;
  }

  get awaitingReview() {
    return this.profiles.filter(
      (p) => (p.status ?? 'intake') === 'intake' || p.status === 'under-review',
    ).length;
  }

  // The masthead says what is waiting on the buyer right now.
  get callToAction(): string {
    if (this.isLoading) {
      return 'Loading vendor profiles…';
    }
    let waiting = this.awaitingReview;
    let lapsed = this.profiles.filter((p) => !p.complianceOk).length;
    if (this.profiles.length === 0) {
      return 'No vendor profiles yet. Add one to start vetting.';
    }
    if (waiting === 0 && lapsed === 0) {
      return 'Pipeline clear: every profile vetted, every credential current.';
    }
    let parts: string[] = [];
    if (waiting > 0) {
      parts.push(
        `${waiting} profile${waiting === 1 ? '' : 's'} waiting on your review`,
      );
    }
    if (lapsed > 0) {
      parts.push(`${lapsed} with lapsed compliance`);
    }
    return parts.join(' · ');
  }

  statusField = VendorProfileStatusField;

  statusOf = (item: any) => (item as VendorProfile).status ?? 'intake';

  openCard = (card: CardDef) => {
    this.args.viewCard?.(card, 'isolated');
  };

  addProfile = () => {
    let ref = identifyCard(VendorProfile);
    let realm = this.realms?.[0];
    if (!ref || !realm) {
      return;
    }
    this.args.createCard?.(ref, undefined, {
      realmURL: new URL(realm),
      doc: {
        data: {
          attributes: { status: 'intake' },
          meta: { adoptsFrom: ref },
        },
      },
    });
  };

  onMove = async (item: CardDef, statusValue: string) => {
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      return false;
    }
    this.flash = undefined;
    try {
      await new PatchCardInstanceCommand(commandContext, {
        cardType: VendorProfile,
      }).execute({
        cardId: item.id,
        patch: { attributes: { status: statusValue } },
      });
    } catch (error: any) {
      this.flash = error?.message ?? String(error);
      return false;
    }
    return undefined;
  };

  onRejected = (_item: CardDef, _from: string | undefined, to: string) => {
    this.flash =
      to === 'onboarded'
        ? 'Onboarding creates the active Vendor record. Open the profile and use "Onboard as Vendor" instead of dragging.'
        : 'The vetting pipeline does not allow that move.';
  };

  <template>
    <article class='app'>
      <header class='head command-band'>
        <div class='head-copy'>
          <p class='kicker'>Procurement · Intake console</p>
          <h1>Vendor Onboarding</h1>
          <p class='cta' role='status'>{{this.callToAction}}</p>
        </div>
        <div class='head-right'>
          <span class='count-big'>{{this.profiles.length}}</span>
          <span class='count-label'>profiles ·
            {{this.compliantCount}}
            compliant</span>
        </div>
      </header>

      {{#if this.flash}}
        <Alert @tone='warning'>{{this.flash}}</Alert>
      {{/if}}

      {{#if this.isInteractive}}
        <StatusBoard
          @items={{this.profiles}}
          @statusField={{this.statusField}}
          @statusOf={{this.statusOf}}
          @onMove={{this.onMove}}
          @onRejected={{this.onRejected}}
          @onOpen={{this.openCard}}
          @onAddCard={{this.addProfile}}
          @boardLabel='Vendor vetting pipeline'
          class='board'
        />
      {{else}}
        <EmptyState
          class='shell'
          @size='s'
          @title='Vetting pipeline'
          @message='Vendor profiles move intake → under review → approved → onboarded here. Open the app to work the board.'
        />
      {{/if}}
    </article>
    <style scoped>
      .app {
        container-type: inline-size;
        padding: 0 var(--boxel-sp-lg) var(--boxel-sp-lg);
        background:
          radial-gradient(
            68.75rem 22.5rem at 15% -10%,
            color-mix(in oklch, var(--primary) 7%, transparent),
            transparent 65%
          ),
          var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        min-height: 100%;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .command-band {
        background: linear-gradient(
          120deg,
          color-mix(in oklch, var(--primary) 88%, var(--foreground)),
          var(--primary) 55%,
          color-mix(in oklch, var(--primary) 82%, var(--background))
        );
        color: var(--primary-foreground);
        margin: 0 calc(-1 * var(--boxel-sp-lg));
        padding: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-sm);
        position: relative;
        overflow: hidden;
      }
      .command-band::after {
        content: '';
        position: absolute;
        inset: 0;
        background-image:
          linear-gradient(
            color-mix(in oklch, var(--primary-foreground) 7%, transparent) 1px,
            transparent 1px
          ),
          linear-gradient(
            90deg,
            color-mix(in oklch, var(--primary-foreground) 7%, transparent) 1px,
            transparent 1px
          );
        background-size: 1.75rem 1.75rem;
        mask-image: linear-gradient(to bottom, currentColor, transparent 90%);
        pointer-events: none;
      }
      .head {
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: var(--boxel-sp);
      }
      .head-copy {
        min-width: 0;
      }
      .kicker {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: color-mix(in oklch, var(--primary-foreground) 72%, transparent);
      }
      h1 {
        margin: var(--boxel-sp-5xs) 0 0;
        font-size: var(--boxel-font-size-lg);
        letter-spacing: -0.015em;
      }
      .cta {
        margin: var(--boxel-sp-5xs) 0 0;
        font-size: var(--boxel-font-size-sm);
        color: color-mix(in oklch, var(--primary-foreground) 88%, transparent);
      }
      .head-right {
        flex: none;
        text-align: right;
      }
      .count-big {
        display: block;
        font-size: var(--boxel-font-size-xl);
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1;
      }
      .count-label {
        font-size: var(--boxel-font-size-sm);
        color: color-mix(in oklch, var(--primary-foreground) 78%, transparent);
        font-variant-numeric: tabular-nums;
      }
      .board {
        flex: 1;
        min-height: 0;
      }
      @container (width < 30rem) {
        .head {
          flex-direction: column;
          align-items: flex-start;
        }
        .head-right {
          text-align: left;
        }
      }
      @media (prefers-reduced-motion: no-preference) {
        .command-band {
          animation: vo-band-in 420ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        .board,
        .shell {
          animation: vo-rise 400ms cubic-bezier(0.22, 1, 0.36, 1) both;
          animation-delay: 140ms;
        }
      }
      @keyframes vo-band-in {
        from {
          opacity: 0;
          transform: translateY(-0.5rem);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      @keyframes vo-rise {
        from {
          opacity: 0;
          transform: translateY(0.75rem);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
    </style>
  </template>
}

// The buyer's intake console. Every Vendor Profile in the realm sits on the
// shared Status Board, whose columns come from VendorProfileStatusField's
// options and whose legal moves come from that field's transition graph.
// Dragging a profile to `onboarded` is refused by the graph, because
// activation goes through the Onboard Vendor command on the profile card.
// Prerender gets a static shell: the board mounts only when the card's CRUD
// functions are present, which keeps indexing light.
export class VendorOnboardingApp extends CardDef {
  static displayName = 'Vendor Onboarding';
  static prefersWideFormat = true;

  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'Vendor Onboarding';
    },
  });

  static isolated = VendorOnboardingIsolated;

  static fitted = class Fitted extends Component<typeof VendorOnboardingApp> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow><span class='fit-eyebrow'>Procurement</span></:eyebrow>
        <:title>Vendor Onboarding</:title>
        <:subtitle>intake → review → approved → onboarded</:subtitle>
        <:footer>
          <span class='rail' aria-hidden='true'>
            <i></i><i></i><i class='lit'></i><i></i>
          </span>
        </:footer>
      </FittedCard>
      <style scoped>
        .fit-eyebrow {
          color: var(--primary-ink);
        }
        .rail {
          display: flex;
          gap: var(--boxel-sp-5xs);
          width: 100%;
        }
        .rail i {
          flex: 0 1 2.125rem;
          height: 0.3125rem;
          border-radius: var(--radius);
          background: color-mix(in oklch, var(--primary) 25%, transparent);
        }
        .rail i.lit {
          background: var(--primary);
        }
      </style>
    </template>
  };
}
