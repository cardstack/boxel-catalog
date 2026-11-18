import { CardDef, Component, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import LayoutDashboardIcon from '@cardstack/boxel-icons/layout-dashboard';

export class PersonalDashboard extends CardDef {
  static displayName = 'Personal Dashboard';
  static icon = LayoutDashboardIcon;
  static prefersWideFormat = true;

  @field focus = contains(StringField);
  @field weeklyGoal = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: PersonalDashboard) {
      return this.cardInfo?.name?.trim() || 'Your dashboard';
    },
  });

  static isolated = class Isolated extends Component<typeof PersonalDashboard> {
    <template>
      <main class='dashboard-shell'>
        <div class='dashboard-content'>
          <header class='masthead'>
            <div class='brandline'><span class='brandmark'>P</span><span
              >PERSONAL / WORKSPACE</span></div>
            <p class='issue'>A SMALL SPACE FOR WHAT MOVES</p>
          </header>

          <section class='welcome'>
            <div class='eyebrow'>YOUR DAY, IN VIEW</div>
            <h1><@fields.cardTitle /></h1>
            <p class='intro'>A clear place to name what matters today—and what
              you want to move this week.</p>
          </section>

          <section class='workbench' aria-label='Focus and weekly goal'>
            <article class='focus-panel'>
              <div class='panel-kicker'><span class='index'>01</span><span
                >TODAY'S FOCUS</span></div>
              <p class='focus-value'>{{@model.focus}}</p>
              <p class='slot-note'>Marked slot · replace this in Edit</p>
              <div class='focus-rule'></div>
              <p class='prompt'>One thing at a time. Give today's attention a
                name.</p>
            </article>

            <article class='week-panel'>
              <div class='panel-kicker'><span class='index'>02</span><span>THIS
                  WEEK</span></div>
              <h2>One step forward.</h2>
              <p class='week-value'>{{@model.weeklyGoal}}</p>
              <p class='slot-note'>Marked slot · replace this in Edit</p>
              <div class='week-footer'><span class='footer-dot'></span><span>Set
                  a direction; the details can follow.</span></div>
            </article>
          </section>

          <footer class='closing-line'><span>START WITH THE NEXT RIGHT THING</span><span
              class='closing-rule'
            ></span><span>01 — 02</span></footer>
        </div>
      </main>
      <style scoped>
        .dashboard-shell {
          height: 100%;
          overflow-y: auto;
        }
        .dashboard-content {
          container-type: inline-size;
          container-name: dashboard-page;
          padding: clamp(1.25rem, 4cqi, 4rem);
        }
        .masthead {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 1rem;
          border-bottom: 1px solid var(--border);
          padding-bottom: 0.9rem;
        }
        .brandline {
          display: flex;
          align-items: center;
          gap: 0.7rem;
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.12em;
        }
        .brandmark {
          display: grid;
          place-items: center;
          width: 1.7rem;
          height: 1.7rem;
          background: var(--foreground);
          color: var(--background);
          font-size: 0.8rem;
          letter-spacing: 0;
        }
        .issue {
          margin: 0;
          color: var(--muted-foreground);
          font-size: 0.75rem;
          letter-spacing: 0.12em;
        }
        .welcome {
          padding: clamp(2.2rem, 6cqi, 5rem) 0 clamp(1.5rem, 3cqi, 2.6rem);
          max-width: 58rem;
        }
        .eyebrow,
        .panel-kicker,
        .closing-line {
          font-family: var(--font-mono);
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.14em;
        }
        .eyebrow {
          color: var(--primary-ink);
        }
        h1 {
          margin: 0.6rem 0 0.7rem;
          font-size: clamp(2.5rem, 7cqi, 6.2rem);
          font-weight: 700;
          letter-spacing: -0.065em;
          line-height: 0.98;
        }
        .intro {
          max-width: 35rem;
          color: var(--muted-foreground);
          font-size: clamp(1rem, 1.5cqi, 1.2rem);
          line-height: 1.55;
        }
        .workbench {
          display: grid;
          grid-template-columns: minmax(0, 1.25fr) minmax(17rem, 0.75fr);
          gap: 1rem;
          align-items: stretch;
        }
        .focus-panel,
        .week-panel {
          padding: clamp(1.25rem, 2.6cqi, 2.4rem);
          min-width: 0;
        }
        .focus-panel {
          display: flex;
          flex-direction: column;
          min-height: 22rem;
          background: var(--foreground);
          color: var(--background);
        }
        .panel-kicker {
          display: flex;
          align-items: center;
          gap: 0.8rem;
        }
        .index {
          color: var(--primary-ink);
        }
        .focus-panel .index {
          color: var(--background);
        }
        .focus-value {
          margin: auto 0 0.35rem;
          font-size: clamp(1.8rem, 4cqi, 3.4rem);
          font-weight: 600;
          letter-spacing: -0.045em;
          line-height: 1.05;
          overflow-wrap: anywhere;
        }
        .slot-note {
          margin: 0;
          color: var(--muted-foreground);
          font-size: 0.75rem;
        }
        .focus-panel .slot-note {
          color: color-mix(in srgb, var(--background) 68%, transparent);
        }
        .focus-rule {
          height: 1px;
          background: color-mix(in srgb, var(--background) 30%, transparent);
          margin: 1.5rem 0 0.9rem;
        }
        .prompt {
          max-width: 26rem;
          margin: 0;
          color: color-mix(in srgb, var(--background) 82%, transparent);
          font-size: 0.95rem;
          line-height: 1.5;
        }
        .week-panel {
          display: flex;
          flex-direction: column;
          background: var(--muted);
        }
        .week-panel h2 {
          margin: auto 0 0.6rem;
          font-size: clamp(1.6rem, 2.7cqi, 2.5rem);
          font-weight: 650;
          letter-spacing: -0.045em;
          line-height: 1.05;
        }
        .week-value {
          margin: 0 0 0.45rem;
          font-size: 1.15rem;
          line-height: 1.4;
          overflow-wrap: anywhere;
        }
        .week-footer {
          display: flex;
          align-items: center;
          gap: 0.65rem;
          margin-top: 2.5rem;
          padding-top: 0.9rem;
          border-top: 1px solid var(--border);
          color: var(--muted-foreground);
          font-size: 0.8rem;
          line-height: 1.4;
        }
        .footer-dot {
          width: 0.45rem;
          height: 0.45rem;
          flex: 0 0 auto;
          background: var(--primary);
        }
        .closing-line {
          display: flex;
          align-items: center;
          gap: 0.8rem;
          margin-top: 1.3rem;
          color: var(--muted-foreground);
          font-size: 0.75rem;
        }
        .closing-rule {
          height: 1px;
          flex: 1;
          background: var(--border);
        }
        @container dashboard-page (width < 700px) {
          .issue {
            display: none;
          }
          .workbench {
            grid-template-columns: minmax(0, 1fr);
          }
          .focus-panel {
            min-height: 17rem;
          }
          .week-panel {
            min-height: 15rem;
          }
          .week-panel h2 {
            margin-top: 2.5rem;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof PersonalDashboard> {
    <template>
      <section class='embedded-dashboard'>
        <div class='embedded-kicker'>PERSONAL / FOCUS</div>
        <h2><@fields.cardTitle /></h2>
        <div class='embedded-row'><span class='embedded-label'>TODAY</span><span
            class='embedded-value'
          >{{@model.focus}}</span></div>
        <div class='embedded-row'><span class='embedded-label'>THIS WEEK</span><span
            class='embedded-value'
          >{{@model.weeklyGoal}}</span></div>
      </section>
      <style scoped>
        .embedded-dashboard {
          display: grid;
          gap: 0.7rem;
          padding: 1rem;
          background: var(--card);
          color: var(--card-foreground);
        }
        .embedded-kicker,
        .embedded-label {
          font-family: var(--font-mono);
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.12em;
        }
        .embedded-kicker {
          color: var(--primary-ink);
        }
        h2 {
          font-size: 1.35rem;
          font-weight: 650;
          letter-spacing: -0.04em;
        }
        .embedded-row {
          display: grid;
          grid-template-columns: 5.2rem minmax(0, 1fr);
          gap: 0.6rem;
          padding-top: 0.55rem;
          border-top: 1px solid var(--border);
        }
        .embedded-label {
          color: var(--muted-foreground);
        }
        .embedded-value {
          min-width: 0;
          overflow-wrap: anywhere;
        }
        @container embedded-card (width < 360px) {
          .embedded-row {
            grid-template-columns: minmax(0, 1fr);
            gap: 0.2rem;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof PersonalDashboard> {
    <template>
      <article class='fit'>
        <div class='fit-head'>
          <span class='fit-eyebrow'>PERSONAL / TODAY</span>
          <h3 class='fit-title'><@fields.cardTitle /></h3>
        </div>
        <div class='fit-body'>
          <span class='fit-label'>FOCUS</span>
          <p class='fit-focus'>{{@model.focus}}</p>
          <span class='fit-week'>{{@model.weeklyGoal}}</span>
        </div>
        <div class='fit-meta'><span class='fit-dot'></span><span>YOUR NEXT RIGHT
            THING</span></div>
      </article>
      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          gap: clamp(0.25rem, 1.2cqi, 0.6rem);
          padding: clamp(0.35rem, 1.8cqi, 0.85rem);
          background-color: var(--foreground);
          color: var(--background);
          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --type-ratio: 1.2;
          --type-base: clamp(
            0.625rem,
            calc(0.1875rem + 2.2cqi + 1cqb - 0.6 * var(--ar)),
            1.125rem
          );
          --fit-meta-size: max(
            0.5rem,
            calc(var(--type-base) / var(--type-ratio))
          );
          --fit-body-size: max(0.5625rem, var(--type-base));
          --fit-headline-size: max(
            0.6875rem,
            calc(var(--type-base) * pow(var(--type-ratio), 2))
          );
          overflow: hidden;
        }
        .fit-head,
        .fit-body,
        .fit-meta {
          min-height: 0;
          overflow: hidden;
        }
        .fit-head {
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.15rem;
        }
        .fit-eyebrow,
        .fit-label,
        .fit-meta {
          font-family: var(--font-mono);
          font-size: var(--fit-meta-size);
          font-weight: 700;
          letter-spacing: 0.1em;
        }
        .fit-eyebrow,
        .fit-label {
          color: var(--background);
        }
        .fit-title,
        .fit-focus,
        .fit-week {
          display: -webkit-box;
          -webkit-box-orient: vertical;
          overflow: hidden;
          margin: 0;
          overflow-wrap: anywhere;
        }
        .fit-title {
          font-size: var(--fit-headline-size);
          line-height: 1.08;
          letter-spacing: -0.04em;
          -webkit-line-clamp: 2;
        }
        .fit-body {
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.18rem;
        }
        .fit-focus {
          font-size: var(--fit-body-size);
          line-height: 1.25;
          -webkit-line-clamp: 2;
        }
        .fit-week {
          color: color-mix(in srgb, var(--background) 68%, transparent);
          font-size: var(--fit-meta-size);
          line-height: 1.2;
          -webkit-line-clamp: 1;
        }
        .fit-meta {
          display: flex;
          align-items: center;
          gap: 0.35rem;
          white-space: nowrap;
          text-overflow: ellipsis;
        }
        .fit-dot {
          width: 0.4em;
          height: 0.4em;
          flex: 0 0 auto;
          background: var(--primary);
        }
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: 1fr;
          }
          .fit-body,
          .fit-meta {
            display: none;
          }
          .fit-head {
            flex-direction: row;
            align-items: center;
            gap: 0.5rem;
          }
          .fit-eyebrow {
            display: none;
          }
          .fit-title {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (50px < height <= 80px) {
          .fit {
            grid-template-rows: 1fr;
          }
          .fit-body,
          .fit-meta,
          .fit-eyebrow {
            display: none;
          }
          .fit-title {
            -webkit-line-clamp: 2;
          }
        }
        @container fitted-card (80px < height <= 130px) {
          .fit {
            grid-template-rows: auto minmax(0, 1fr);
          }
          .fit-meta,
          .fit-week {
            display: none;
          }
          .fit-title {
            -webkit-line-clamp: 2;
          }
        }
        @container fitted-card (130px < height <= 200px) {
          .fit-title {
            -webkit-line-clamp: 2;
          }
          .fit-focus {
            -webkit-line-clamp: 2;
          }
          .fit-meta {
            white-space: normal;
          }
        }
        @container fitted-card (width <= 170px) {
          .fit-eyebrow {
            display: none;
          }
          .fit-title {
            -webkit-line-clamp: 2;
          }
        }
      </style>
    </template>
  };
}
