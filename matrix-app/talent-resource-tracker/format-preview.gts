import {
  CardDef,
  Component,
  field,
  linksTo,
  realmURL,
  type BaseDef,
} from '@cardstack/base/card-api';
import { codeRef } from '@cardstack/runtime-common';

// Dev harness: one instance of every child module in embedded, three fitted
// sizes and atom, on one page, for a regression sweep.
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;
const MODULES: [string, string][] = [
  ['../hr/employee', 'Employee'],
  ['../hr/candidate', 'Candidate'],
  ['../hr/application', 'Application'],
  ['../hr/contractor', 'Contractor'],
  ['../hr/team', 'Team'],
  ['../hr/position', 'Position'],
  ['../hr/interview-plan', 'InterviewPlan'],
  ['../hr/job-requisition', 'JobRequisition'],
  ['../hr/offer', 'Offer'],
  ['../hr/meeting', 'Meeting'],
  ['../hr/pto-request', 'PtoRequest'],
  ['../hr/performance-review', 'PerformanceReview'],
  ['../hr/onboarding-checklist', 'OnboardingChecklist'],
  ['../projects/project', 'Project'],
  ['../procurement/vendor', 'Vendor'],
];
const SIZES = [
  'width:150px;height:170px',
  'width:250px;height:105px',
  'width:250px;height:275px',
  'width:400px;height:170px',
];

function comp(card: BaseDef | undefined) {
  return card
    ? (card.constructor as typeof BaseDef).getComponent(card)
    : undefined;
}

export class FormatPreview extends CardDef {
  static displayName = 'Format Preview';
  @field card = linksTo(() => CardDef);
  static isolated = class Isolated extends Component<typeof FormatPreview> {
    sizes = SIZES;
    queries = MODULES.map(([m, n]) =>
      this.args.context?.getCards(
        this,
        () => ({ filter: { type: codeRef(here, m, n) } }),
        () => {
          let url = this.args.model?.[realmURL]?.href;
          return url ? [url] : [];
        },
        { isLive: true },
      ),
    );
    get rows() {
      return this.queries.map((q, i) => ({
        name: MODULES[i][1],
        Card: comp((q?.instances ?? [])[0] as CardDef | undefined),
      }));
    }
    <template>
      <div class='sw'>
        {{#each this.rows as |r|}}
          <section class='row'>
            <h2>{{r.name}}</h2>
            {{#if r.Card}}
              <div class='emb'><r.Card @format='embedded' /></div>
              {{#each this.sizes as |s|}}
                {{! template-lint-disable no-inline-styles }}
                <div class='box' style={{s}}><r.Card @format='fitted' /></div>
              {{/each}}
              <p class='atom'>atom: <r.Card @format='atom' /></p>
            {{/if}}
          </section>
        {{/each}}
      </div>
      <style scoped>
        .sw {
          display: grid;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp);
          background: var(--muted);
        }
        .row {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-sm);
          align-items: flex-start;
        }
        h2 {
          flex-basis: 100%;
          margin: 0;
          font: 600 var(--boxel-font-size-2xs) var(--font-mono);
        }
        .emb {
          inline-size: 25rem;
        }
        .box {
          overflow: hidden;
        }
        .atom {
          margin: 0;
          inline-size: 12rem;
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}
