import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import KanbanIcon from '@cardstack/boxel-icons/layout-kanban';

import { Opportunity } from '../opportunity';
import SalesPipeline from '../components/sales-pipeline';

// Usage page for the Sales Pipeline block: a handful of opportunities
// across the stages, with the sort and close-window controls live.
export class SalesPipelineExample extends CardDef {
  static displayName = 'Sales Pipeline Example';
  static icon = KanbanIcon;

  @field opportunities = linksToMany(() => Opportunity);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: SalesPipelineExample) {
      return 'Sales Pipeline — open and closed deals';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='demo'>
        <SalesPipeline @items={{@model.opportunities}} />
      </div>
      <style scoped>
        .demo {
          padding: var(--boxel-sp-lg);
          min-width: 0;
        }
      </style>
    </template>
  };
}
