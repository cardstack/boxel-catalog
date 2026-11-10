import { Component } from '@cardstack/base/card-api';
import type { Survey } from '../survey';
import { questionFacts, type SurveyQuestion } from '../survey-question';
import { FitTile } from '../../shared/fit-tile';

export class SurveyFitted extends Component<typeof Survey> {
  get facts() {
    return questionFacts(this.args.model?.questions as SurveyQuestion[]);
  }

  <template>
    <FitTile>
      <:avatar><span class='mark' aria-hidden='true'>Sv</span></:avatar>
      <:title>{{@model.cardTitle}}</:title>
      <:subtitle>{{this.facts.summary}}</:subtitle>
      <:status><span class='dot-text'><span
            class='dot {{if @model.isPublished "ok" "warn"}}'
          ></span>{{if @model.isPublished 'published' 'draft'}}</span></:status>
      <:fact>Required:
        {{this.facts.required}}
        of
        {{this.facts.total}}
        ·
        {{if @model.isPublished 'published' 'not yet published'}}</:fact>
    </FitTile>
    <style scoped>
      .mark {
        display: inline-grid;
        place-items: center;
        width: 1.5rem;
        height: 1.5rem;
        border-radius: 0.25rem;
        background-color: var(--muted);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 700;
      }
      .dot-text {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
        white-space: nowrap;
      }
      .dot {
        width: 0.375rem;
        height: 0.375rem;
        border-radius: 50%;
        background-color: var(--muted-foreground);
      }
      .dot.ok {
        background-color: var(--success);
      }
      .dot.warn {
        background-color: var(--warning);
      }
    </style>
  </template>
}
