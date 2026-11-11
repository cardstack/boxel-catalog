// An interviewer the participant can talk to: a name, a manner and a face.
// A brief lists the interviewers on offer; each interview keeps the one picked.
import { CardDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import NumberField from '@cardstack/base/number';
import { htmlSafe } from '@ember/template';
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import UserRoundIcon from '@cardstack/boxel-icons/user-round';
import { resolveUrl } from './tool-kit';

interface AvatarSignature {
  Args: { src?: string | null; name?: string | null };
}
export class Avatar extends GlimmerComponent<AvatarSignature> {
  @tracked failed = false;
  fail = () => (this.failed = true);
  get initial() {
    return (this.args.name || 'M').trim().charAt(0).toUpperCase();
  }
  get showImg() {
    return Boolean(this.args.src) && !this.failed;
  }
  <template>
    {{#if this.showImg}}
      <img class='av' src={{@src}} alt='' {{on 'error' this.fail}} />
    {{else}}
      <span class='av mono'>{{this.initial}}</span>
    {{/if}}
    <style scoped>
      .av {
        width: 100%;
        height: 100%;
        border-radius: 50%;
        object-fit: cover;
        object-position: 50% 22%;
        display: grid;
        place-items: center;
        background: #1d1c1a;
        color: #fbfaf7;
        font:
          600 15px/1 ui-sans-serif,
          system-ui,
          sans-serif;
      }
    </style>
  </template>
}

class InterviewerView extends Component<typeof Interviewer> {
  get src() {
    return resolveUrl(this.args.model.portrait, (this.args.model as any).id);
  }
  get dials() {
    const m = this.args.model;
    return [
      ['Warmth', m.warmth],
      ['Humour', m.humour],
      ['Length', m.length],
      ['Formality', m.formality],
    ].map(([name, v]) => {
      const n = Math.max(1, Math.min(5, Math.round(Number(v) || 3)));
      return { name, n, style: htmlSafe(`width:${n * 20}%`) };
    });
  }
  <template>
    <article class='ivr'>
      {{#if @model.portrait}}<img
          class='big'
          src={{this.src}}
          alt=''
        />{{else}}<span class='big'><Avatar
            @name={{@model.name}}
          /></span>{{/if}}
      <div class='txt'>
        <p class='kicker'>Interviewer</p>
        <h1>{{if @model.name @model.name 'Unnamed'}}</h1>
        <p class='persona'>{{@model.persona}}</p>
        <dl class='dials'>
          {{#each this.dials as |dl|}}
            <div class='dl'><dt>{{dl.name}}</dt><dd><span class='track'><span
                    class='fill'
                    style={{dl.style}}
                  ></span></span><span class='n'>{{dl.n}}</span></dd></div>
          {{/each}}
        </dl>
        <p class='fine'>Starting style. In studies that allow it, the
          interviewer moves these toward how each person talks.</p>
      </div>
    </article>
    <style scoped>
      .ivr {
        min-height: 100%;
        box-sizing: border-box;
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 24px;
        grid-template-columns: minmax(0, 320px) minmax(0, 1fr);
        align-items: center;
        max-width: 820px;
        margin: 0 auto;
        container-type: inline-size;
        background: #fbfaf7;
        color: #1d1c1a;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
      }
      .big {
        width: 100%;
        aspect-ratio: 1;
        border-radius: 16px;
        object-fit: cover;
        object-position: 50% 22%;
        display: block;
      }
      .kicker {
        margin: 0;
        color: #6b675f;
        font-size: 13px;
      }
      h1 {
        margin: 2px 0 10px;
        font:
          600 30px/1.1 ui-sans-serif,
          system-ui,
          sans-serif;
        letter-spacing: -0.01em;
      }
      .persona {
        margin: 0;
        font-size: 15px;
        line-height: 1.55;
        max-width: 52ch;
      }
      .dials {
        margin: 18px 0 0;
        display: grid;
        gap: 8px;
        max-width: 320px;
      }
      .dl {
        display: grid;
        grid-template-columns: 80px 1fr;
        gap: 10px;
        align-items: center;
      }
      dt {
        font-size: 13px;
        color: #6b675f;
      }
      dd {
        margin: 0;
        display: flex;
        gap: 8px;
        align-items: center;
      }
      .track {
        flex: 1;
        height: 6px;
        border-radius: 3px;
        background: #ece8df;
        overflow: hidden;
      }
      .fill {
        display: block;
        height: 100%;
        background: #1d1c1a;
        border-radius: 3px;
      }
      .n {
        font:
          600 12px/1 ui-monospace,
          monospace;
        width: 10px;
      }
      .fine {
        margin: 10px 0 0;
        font-size: 12px;
        color: #6b675f;
      }
      @container (max-width: 520px) {
        .ivr {
          grid-template-columns: 1fr;
        }
        .big {
          max-width: 240px;
        }
      }
    </style>
  </template>
}

class InterviewerFitted extends Component<typeof Interviewer> {
  get src() {
    return resolveUrl(this.args.model.portrait, (this.args.model as any).id);
  }
  <template>
    <div class='if'>
      <span class='face'><Avatar
          @src={{this.src}}
          @name={{@model.name}}
        /></span>
      <div class='txt'><b>{{@model.name}}</b><span
        >{{@model.persona}}</span></div>
    </div>
    <style scoped>
      .if {
        height: 100%;
        box-sizing: border-box;
        padding: 10px 12px;
        display: flex;
        gap: 10px;
        align-items: center;
        overflow: hidden;
        background: #fbfaf7;
        color: #1d1c1a;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
      }
      .face {
        flex: none;
        width: 36px;
        height: 36px;
      }
      .txt {
        display: grid;
        min-width: 0;
      }
      b {
        font-size: 14px;
      }
      span {
        font-size: 12px;
        color: #6b675f;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
    </style>
  </template>
}

export class Interviewer extends CardDef {
  static displayName = 'Interviewer';
  static icon = UserRoundIcon;
  @field name = contains(StringField); // the name they introduce themselves by
  @field persona = contains(TextAreaField); // their manner, in a few sentences
  @field portrait = contains(StringField); // image URL
  @field livingPortrait = contains(StringField); // a Living Portrait card's URL: talks beside the chat
  // default style dials, 1-5; the interviewer may shift them toward each
  // participant when the study allows it
  @field warmth = contains(NumberField);
  @field humour = contains(NumberField);
  @field length = contains(NumberField); // 1 = a few words … 5 = chatty
  @field formality = contains(NumberField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Interviewer) {
      return this.name;
    },
  });
  static isolated = InterviewerView;
  static embedded = InterviewerFitted;
  static fitted = InterviewerFitted;
}
