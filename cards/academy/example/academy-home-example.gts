import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  realmURL,
} from '@cardstack/base/card-api';
import GraduationCapIcon from '@cardstack/boxel-icons/graduation-cap';

import { AcademyHome } from '../components/academy-home';

// Usage page for Academy Home: the component over this realm's cohorts,
// courses, enrolments and submissions, opening whatever it is asked to open.
export class AcademyHomeExample extends CardDef {
  static displayName = 'Academy Home Example';
  static icon = GraduationCapIcon;

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AcademyHomeExample) {
      return this.cardInfo?.name || 'Academy Home over this realm';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get realms(): string[] {
      let realm = (this.args.model as any)?.[realmURL]?.href;
      return realm ? [realm] : [];
    }

    open = (card: any) => {
      if (card?.id) {
        (this.args as any).viewCard?.(new URL(card.id));
      }
    };

    <template>
      <AcademyHome
        @context={{@context}}
        @realms={{this.realms}}
        @onOpenCohort={{this.open}}
        @onOpenCourse={{this.open}}
        @onOpenSubmission={{this.open}}
      />
    </template>
  };
}
