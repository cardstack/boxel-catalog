import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import { RichMarkdownField } from '@cardstack/base/rich-markdown';
import ClipboardListIcon from '@cardstack/boxel-icons/clipboard-list';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { FittedExtras } from '../procurement/vendor';
import {
  AcademyAtom,
  AcademyEmbedded,
  AcademyIsolated,
  AcademyPanel,
  AcademyRel,
  AcademyRels,
  type FormatFact,
} from './components/card-formats';
import { EmptyState } from '../../ui-component/components/empty-state';
import { Stat } from '../../ui-component/components/stat';
import {
  DueWindowField,
  dueWindowState,
  dueWindowLabel,
  DUE_WINDOW_HUES,
} from '@cardstack/catalog/fields/due-window/due-window-field';
import { Rubric } from './rubric';
import { Module } from './course-module';
import { StatePill } from '@cardstack/catalog/components/state-pill';

/**
 * A piece of work a learner hands in. Owns the brief and the timing; borrows
 * its scoring from a Rubric so the same grid can grade three assignments.
 * `maxPoints` defaults to the rubric total but can be set lower to scale the
 * assignment's weight in the gradebook. Submissions link back here.
 */
export class Assignment extends CardDef {
  static displayName = 'Assignment';
  static icon = ClipboardListIcon;

  @field title = contains(StringField);
  @field code = contains(StringField, {
    description: 'Short label used in the gradebook header, e.g. A2.',
  });
  @field brief = contains(RichMarkdownField);
  @field dueWindow = contains(DueWindowField);
  @field required = contains(BooleanField, {
    description: 'Required assignments count toward completion.',
  });
  @field allowResubmission = contains(BooleanField);
  @field maxPoints = contains(NumberField, {
    description: 'Leave empty to use the rubric total.',
  });
  @field rubric = linksTo(() => Rubric);
  @field module = linksTo(() => Module as any);

  @field effectiveMaxPoints = contains(NumberField, {
    computeVia: function (this: Assignment) {
      return this.maxPoints ?? this.rubric?.totalPoints ?? 0;
    },
  });
  @field dueLabel = contains(StringField, {
    computeVia: function (this: Assignment) {
      return this.dueWindow?.summary ?? 'No due date';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Assignment) {
      return this.title?.trim() || 'Untitled assignment';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model?.dueWindow);
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.code, m?.dueLabel].filter(Boolean).join(' · ');
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Code', value: m?.code || '—' },
        { key: 'Due', value: m?.dueLabel ?? '—' },
        { key: 'Points', value: String(m?.effectiveMaxPoints ?? 0) },
        { key: 'Required', value: m?.required ? 'Yes' : 'No' },
        {
          key: 'Resubmission',
          value: m?.allowResubmission ? 'Allowed' : 'No',
        },
      ];
    }
    <template>
      <AcademyIsolated
        @mark='As'
        @title={{@model.cardTitle}}
        @subtitle={{this.subtitle}}
      >
        <:chips>
          {{#if @model.required}}<StatePill
              @label='Required'
              @hue='amber'
            />{{/if}}
          <StatePill
            @label={{dueWindowLabel this.state}}
            @hue={{hueFor this.state}}
          />
        </:chips>
        <:stats>
          <Stat
            @label='Points'
            @value={{orZero @model.effectiveMaxPoints}}
            @hint={{if @model.maxPoints 'set on assignment' 'rubric total'}}
            @roll={{false}}
          />
          <Stat
            @label='Due'
            @value={{dueWindowLabel this.state}}
            @hint={{@model.dueLabel}}
            @roll={{false}}
          />
          <Stat
            @label='Resubmission'
            @value={{if @model.allowResubmission 'Allowed' 'No'}}
            @hint={{if @model.required 'required work' 'optional work'}}
            @roll={{false}}
          />
        </:stats>
        <:main>
          <AcademyPanel @title='Brief'>
            {{#if @model.brief.content}}
              <@fields.brief />
            {{else}}
              <EmptyState
                @size='s'
                @title='No brief yet'
                @message='Learners see this first: say what to hand in and how it is judged.'
              />
            {{/if}}
          </AcademyPanel>
          <AcademyPanel @title='Rubric'>
            {{#if @model.rubric}}
              <@fields.rubric @format='embedded' />
            {{else}}
              <EmptyState
                @size='s'
                @title='No rubric linked'
                @message='Submissions cannot be graded until one is.'
              />
            {{/if}}
          </AcademyPanel>
        </:main>
        <:side>
          <AcademyPanel @title='Linked'>
            <AcademyRels>
              <AcademyRel @label='Rubric'>{{#if @model.rubric}}<@fields.rubric
                    @format='atom'
                  />{{else}}—{{/if}}</AcademyRel>
              <AcademyRel @label='Module'>{{#if @model.module}}<@fields.module
                    @format='atom'
                  />{{else}}—{{/if}}</AcademyRel>
            </AcademyRels>
          </AcademyPanel>
          <AcademyPanel @title='Details'>
            <KeyValue @items={{this.details}} @rows='ruled' />
          </AcademyPanel>
        </:side>
      </AcademyIsolated>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model?.dueWindow);
    }
    get facts(): FormatFact[] {
      let m = this.args.model;
      return [
        { key: 'Due', value: m?.dueLabel ?? '—' },
        { key: 'Points', value: String(m?.effectiveMaxPoints ?? 0) },
        { key: 'Required', value: m?.required ? 'Yes' : 'No' },
        {
          key: 'Resubmission',
          value: m?.allowResubmission ? 'Allowed' : 'No',
        },
      ];
    }
    <template>
      <AcademyEmbedded
        @mark='As'
        @title={{@model.cardTitle}}
        @subtitle={{@model.code}}
        @facts={{this.facts}}
      >
        <:chips><StatePill
            @label={{dueWindowLabel this.state}}
            @hue={{hueFor this.state}}
          /></:chips>
        <:relations>
          {{#if @model.rubric}}<span>Rubric
              <@fields.rubric @format='atom' /></span>{{/if}}
          {{#if @model.module}}<span>Module
              <@fields.module @format='atom' /></span>{{/if}}
        </:relations>
      </AcademyEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model?.dueWindow);
    }
    <template>
      <AcademyAtom @mark='As' @name={{@model.cardTitle}}>
        <StatePill
          @label={{dueWindowLabel this.state}}
          @hue={{hueFor this.state}}
        />
      </AcademyAtom>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model?.dueWindow);
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.code, `${m?.effectiveMaxPoints ?? 0} pts`]
        .filter(Boolean)
        .join(' · ');
    }
    get fact() {
      return this.args.model?.dueLabel ?? '';
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Points', value: String(m?.effectiveMaxPoints ?? 0) },
        { key: 'Required', value: m?.required ? 'Yes' : 'No' },
        {
          key: 'Resubmission',
          value: m?.allowResubmission ? 'Allowed' : 'No',
        },
      ];
    }
    get relations() {
      let m = this.args.model;
      return [m?.rubric ? 'Rubric' : '', m?.module ? 'Module' : ''].filter(
        Boolean,
      );
    }
    <template>
      <FittedExtras @facts={{this.facts}} @relations={{this.relations}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name='As'
                @hue='var(--muted-foreground)'
                @size={{32}}
                aria-hidden='true'
              />
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.cardTitle}}</span></:title>
            <:subtitle>{{this.subtitle}}</:subtitle>
            <:status><StatePill
                @label={{dueWindowLabel this.state}}
                @hue={{hueFor this.state}}
              /></:status>
            <:fact>{{this.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          {{#if (eq label 'Rubric')}}
            <@fields.rubric @format='atom' />
          {{else}}
            <@fields.module @format='atom' />
          {{/if}}
        </:relation>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        }
      </style>
    </template>
  };
}

function hueFor(state: ReturnType<typeof dueWindowState>) {
  return DUE_WINDOW_HUES[state];
}

function orZero(n?: number | null): number {
  return n ?? 0;
}

export default Assignment;
