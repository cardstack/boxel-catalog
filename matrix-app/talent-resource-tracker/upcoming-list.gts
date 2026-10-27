import GlimmerComponent from '@glimmer/component';
import type { CardDef } from '@cardstack/base/card-api';
import { EmptyState } from '../../ui-component/components/empty-state';
import { LoadingState } from '../../ui-component/components/loading-state';
import type { Meeting } from '../hr/meeting';
import { CardTiles } from './card-tiles';
import { toLocalDate } from './dates';

interface Signature {
  Args: {
    meetings: Meeting[];
    loading?: boolean;
    onOpen: (card: CardDef) => void;
  };
}

// The next five meetings, each drawn by the Meeting card's own fitted strip.
// The dashboard and the calendar tab both show this panel body.
export class UpcomingList extends GlimmerComponent<Signature> {
  get upcoming(): Meeting[] {
    let now = Date.now();
    return this.args.meetings
      .filter((m) => m.date && toLocalDate(m.date).getTime() >= now)
      .sort(
        (a, b) =>
          toLocalDate(a.date!).getTime() - toLocalDate(b.date!).getTime(),
      )
      .slice(0, 5);
  }

  <template>
    {{#if this.upcoming.length}}
      <CardTiles
        @cards={{this.upcoming}}
        @size='double-strip'
        @list={{true}}
        @onOpen={{@onOpen}}
      />
    {{else if @loading}}
      <LoadingState @label='Loading' />
    {{else}}
      <EmptyState
        @size='s'
        @texture={{false}}
        @title='Nothing scheduled'
        @message='Pick a day on the calendar or use + Add meeting.'
      />
    {{/if}}
  </template>
}
