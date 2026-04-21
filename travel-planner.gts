// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
  Component,
} from 'https://cardstack.com/base/card-api'; // ¹ Core imports
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import DateField from 'https://cardstack.com/base/date';
import DatetimeField from 'https://cardstack.com/base/datetime';
import MarkdownField from 'https://cardstack.com/base/markdown';
import PlaneIcon from '@cardstack/boxel-icons/plane'; // ² Icon import
import {
  Button,
  Pill,
  FieldContainer,
  CardContainer,
} from '@cardstack/boxel-ui/components';
import {
  eq,
  gt,
  gte,
  lt,
  lte,
  and,
  or,
  not,
  cn,
  add,
  subtract,
  multiply,
  divide,
} from '@cardstack/boxel-ui/helpers';
import {
  formatDateTime,
  formatCurrency,
  formatNumber,
} from '@cardstack/boxel-ui/helpers';
import { concat, fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { TravelMapModifier } from './leaflet-map-a03db3c4-6d6a-4d1d-ac3c-7748a8e5f519/leaflet-map/leaflet-map'; // ²⁷ Import map functionality

// ³ Supporting Field Definitions
export class Destination extends FieldDef {
  // ⁴ Multi-city destination field
  static displayName = 'Destination';

  @field name = contains(StringField);
  @field country = contains(StringField);
  @field lat = contains(NumberField); // ²⁵ Added coordinates for mapping
  @field lon = contains(NumberField);
  @field arrivalDate = contains(DateField);
  @field departureDate = contains(DateField);
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='destination'>
        <strong>{{if @model.name @model.name 'Unnamed Destination'}}</strong>
        {{#if @model.country}}
          <span class='country'>, {{@model.country}}</span>
        {{/if}}
        {{#if @model.arrivalDate}}
          <div class='dates'>{{formatDateTime @model.arrivalDate size='short'}}
            -
            {{formatDateTime @model.departureDate size='short'}}</div>
        {{/if}}
      </div>

      <style scoped>
        /* ⁵ Component styles */
        .destination {
          padding: 0.5rem;
          border-radius: 0.375rem;
          background: #f8fafc;
        }
        .country {
          color: #64748b;
          font-size: 0.875rem;
        }
        .dates {
          font-size: 0.8125rem;
          color: #475569;
          margin-top: 0.25rem;
        }
      </style>
    </template>
  };
}

export class Traveler extends FieldDef {
  // ⁶ Traveler information
  static displayName = 'Traveler';

  @field name = contains(StringField);
  @field email = contains(StringField);
  @field phone = contains(StringField);
  @field passportNumber = contains(StringField);
  @field dateOfBirth = contains(DateField);
  @field role = contains(StringField); // lead, companion, child

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='traveler'>
        <div class='name'>{{if
            @model.name
            @model.name
            'Unnamed Traveler'
          }}</div>
        {{#if @model.role}}
          <Pill @kind='primary' class='role-pill'>{{@model.role}}</Pill>
        {{/if}}
        {{#if @model.email}}
          <div class='contact'>{{@model.email}}</div>
        {{/if}}
      </div>

      <style scoped>
        .traveler {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.375rem 0.5rem;
          background: #fefefe;
          border: 1px solid #e2e8f0;
          border-radius: 0.5rem;
        }
        .name {
          font-weight: 500;
          flex: 1;
        }
        .role-pill {
          font-size: 0.75rem;
        }
        .contact {
          font-size: 0.75rem;
          color: #64748b;
        }
      </style>
    </template>
  };
}

export class BudgetCategories extends FieldDef {
  // ⁷ Budget breakdown
  static displayName = 'Budget Categories';

  @field accommodation = contains(NumberField);
  @field transportation = contains(NumberField);
  @field food = contains(NumberField);
  @field activities = contains(NumberField);
  @field shopping = contains(NumberField);
  @field emergency = contains(NumberField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='budget-categories'>
        <div class='category'>
          <span>Accommodation</span>
          <span>{{formatCurrency
              @model.accommodation
              currency='USD'
              fallback='$0'
            }}</span>
        </div>
        <div class='category'>
          <span>Transportation</span>
          <span>{{formatCurrency
              @model.transportation
              currency='USD'
              fallback='$0'
            }}</span>
        </div>
        <div class='category'>
          <span>Food</span>
          <span>{{formatCurrency
              @model.food
              currency='USD'
              fallback='$0'
            }}</span>
        </div>
        <div class='category'>
          <span>Activities</span>
          <span>{{formatCurrency
              @model.activities
              currency='USD'
              fallback='$0'
            }}</span>
        </div>
        <div class='category'>
          <span>Shopping</span>
          <span>{{formatCurrency
              @model.shopping
              currency='USD'
              fallback='$0'
            }}</span>
        </div>
        <div class='category'>
          <span>Emergency</span>
          <span>{{formatCurrency
              @model.emergency
              currency='USD'
              fallback='$0'
            }}</span>
        </div>
      </div>

      <style scoped>
        .budget-categories {
          display: grid;
          gap: 0.5rem;
          font-size: 0.875rem;
        }
        .category {
          display: flex;
          justify-content: space-between;
          padding: 0.375rem 0.5rem;
          background: #f1f5f9;
          border-radius: 0.25rem;
        }
      </style>
    </template>
  };
}

export class DayPlan extends CardDef {
  // ⁸ Separate DayPlan card
  static displayName = 'Day Plan';
  static icon = PlaneIcon;

  @field date = contains(DateField);
  @field location = contains(StringField);
  @field morningActivities = contains(StringField);
  @field afternoonActivities = contains(StringField);
  @field eveningActivities = contains(StringField);
  @field notes = contains(MarkdownField);
  @field weather = contains(StringField);
  @field dailyBudget = contains(NumberField);

  @field cardTitle = contains(StringField, {
    // ⁹ Computed title
    computeVia: function (this: DayPlan) {
      try {
        const date = this.date
          ? formatDateTime(this.date, { size: 'medium' })
          : 'Unscheduled';
        const location = this.location ?? 'Unknown Location';
        return `${date} - ${location}`;
      } catch (e) {
        console.error('DayPlan: Error computing title', e);
        return 'Day Plan';
      }
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='day-plan'>
        <header class='day-header'>
          <h3>{{formatDateTime
              @model.date
              size='medium'
              fallback='Unscheduled Day'
            }}</h3>
          {{#if @model.location}}
            <div class='location'>📍 {{@model.location}}</div>
          {{/if}}
          {{#if @model.weather}}
            <div class='weather'>🌤️ {{@model.weather}}</div>
          {{/if}}
        </header>

        <div class='activities'>
          {{#if @model.morningActivities}}
            <div class='time-block'>
              <strong>Morning:</strong>
              {{@model.morningActivities}}
            </div>
          {{/if}}
          {{#if @model.afternoonActivities}}
            <div class='time-block'>
              <strong>Afternoon:</strong>
              {{@model.afternoonActivities}}
            </div>
          {{/if}}
          {{#if @model.eveningActivities}}
            <div class='time-block'>
              <strong>Evening:</strong>
              {{@model.eveningActivities}}
            </div>
          {{/if}}
        </div>

        {{#if @model.dailyBudget}}
          <div class='budget'>
            Daily Budget:
            {{formatCurrency @model.dailyBudget currency='USD'}}
          </div>
        {{/if}}
      </div>

      <style scoped>
        .day-plan {
          border: 1px solid #e2e8f0;
          border-radius: 0.5rem;
          padding: 1rem;
          background: white;
        }
        .day-header h3 {
          margin: 0 0 0.5rem 0;
          color: #1e40af;
          font-size: 1rem;
        }
        .location,
        .weather {
          font-size: 0.8125rem;
          color: #64748b;
          margin-bottom: 0.25rem;
        }
        .activities {
          margin: 1rem 0;
        }
        .time-block {
          margin-bottom: 0.5rem;
          font-size: 0.875rem;
        }
        .time-block strong {
          color: #374151;
        }
        .budget {
          font-size: 0.8125rem;
          color: #059669;
          font-weight: 500;
        }
      </style>
    </template>
  };
}

export class FlightBooking extends CardDef {
  // ¹⁰ Flight booking card
  static displayName = 'Flight Booking';
  static icon = PlaneIcon;

  @field airline = contains(StringField);
  @field flightNumber = contains(StringField);
  @field confirmationCode = contains(StringField);
  @field departureAirport = contains(StringField);
  @field arrivalAirport = contains(StringField);
  @field departureTime = contains(DatetimeField);
  @field arrivalTime = contains(DatetimeField);
  @field seatNumber = contains(StringField);
  @field price = contains(NumberField);
  @field checkinStatus = contains(StringField);

  @field cardTitle = contains(StringField, {
    // ¹¹ Computed title
    computeVia: function (this: FlightBooking) {
      try {
        const airline = this.airline ?? 'Unknown Airline';
        const flightNum = this.flightNumber ?? '';
        const route = `${this.departureAirport ?? '???'} → ${
          this.arrivalAirport ?? '???'
        }`;
        return `${airline} ${flightNum} ${route}`.trim();
      } catch (e) {
        console.error('FlightBooking: Error computing title', e);
        return 'Flight Booking';
      }
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='flight-booking'>
        <header class='flight-header'>
          <h3>{{if @model.airline @model.airline 'Unknown Airline'}}
            {{@model.flightNumber}}</h3>
          {{#if @model.confirmationCode}}
            <Pill @kind='primary'>{{@model.confirmationCode}}</Pill>
          {{/if}}
        </header>

        <div class='route'>
          <div class='airport'>
            <strong>{{@model.departureAirport}}</strong>
            <div>{{formatDateTime
                @model.departureTime
                size='short'
                fallback='TBD'
              }}</div>
          </div>
          <div class='arrow'>✈️</div>
          <div class='airport'>
            <strong>{{@model.arrivalAirport}}</strong>
            <div>{{formatDateTime
                @model.arrivalTime
                size='short'
                fallback='TBD'
              }}</div>
          </div>
        </div>

        <div class='booking-details'>
          {{#if @model.seatNumber}}
            <span>Seat: {{@model.seatNumber}}</span>
          {{/if}}
          {{#if @model.price}}
            <span>{{formatCurrency @model.price currency='USD'}}</span>
          {{/if}}
          {{#if @model.checkinStatus}}
            <Pill
              @kind={{if
                (eq @model.checkinStatus 'checked-in')
                'success'
                'warning'
              }}
            >
              {{@model.checkinStatus}}
            </Pill>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .flight-booking {
          border: 1px solid #e2e8f0;
          border-radius: 0.5rem;
          padding: 1rem;
          background: linear-gradient(135deg, #dbeafe 0%, #fef3c7 100%);
        }
        .flight-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 1rem;
        }
        .flight-header h3 {
          margin: 0;
          color: #1e40af;
          font-size: 1rem;
        }
        .route {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 1rem;
        }
        .airport {
          text-align: center;
          flex: 1;
        }
        .airport strong {
          font-size: 1.125rem;
          color: #374151;
        }
        .airport div {
          font-size: 0.8125rem;
          color: #64748b;
          margin-top: 0.25rem;
        }
        .arrow {
          font-size: 1.5rem;
          margin: 0 1rem;
        }
        .booking-details {
          display: flex;
          gap: 1rem;
          align-items: center;
          font-size: 0.875rem;
        }
      </style>
    </template>
  };
}

export class Expense extends CardDef {
  // ¹² Expense tracking card
  static displayName = 'Expense';

  @field date = contains(DateField);
  @field category = contains(StringField);
  @field cardDescription = contains(StringField);
  @field amount = contains(NumberField);
  @field currency = contains(StringField);
  @field convertedAmount = contains(NumberField);
  @field paymentMethod = contains(StringField);
  @field notes = contains(StringField);

  @field cardTitle = contains(StringField, {
    // ¹³ Computed title
    computeVia: function (this: Expense) {
      try {
        const desc = this.cardDescription ?? 'Expense';
        const amount = this.amount
          ? formatCurrency(this.amount, { currency: this.currency || 'USD' })
          : '';
        return amount ? `${desc} - ${amount}` : desc;
      } catch (e) {
        console.error('Expense: Error computing title', e);
        return 'Expense';
      }
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='expense'>
        <div class='expense-header'>
          <strong>{{if
              @model.cardDescription
              @model.cardDescription
              'Unnamed Expense'
            }}</strong>
          <span class='amount'>{{formatCurrency
              @model.amount
              currency=@model.currency
              fallback='$0'
            }}</span>
        </div>
        <div class='expense-details'>
          {{#if @model.category}}
            <Pill @kind='secondary'>{{@model.category}}</Pill>
          {{/if}}
          {{#if @model.date}}
            <span class='date'>{{formatDateTime
                @model.date
                size='short'
              }}</span>
          {{/if}}
          {{#if @model.paymentMethod}}
            <span class='payment'>{{@model.paymentMethod}}</span>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .expense {
          border: 1px solid #e2e8f0;
          border-radius: 0.375rem;
          padding: 0.75rem;
          background: white;
        }
        .expense-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.5rem;
        }
        .amount {
          font-weight: 600;
          color: #dc2626;
        }
        .expense-details {
          display: flex;
          gap: 0.5rem;
          align-items: center;
          font-size: 0.8125rem;
        }
        .date,
        .payment {
          color: #64748b;
        }
      </style>
    </template>
  };
}

// ¹⁴ Main Travel Planner Card
export class TravelPlanner extends CardDef {
  static displayName = 'Travel Planner';
  static icon = PlaneIcon;
  static prefersWideFormat = true;

  // Trip Information
  @field tripName = contains(StringField);
  @field destination = contains(StringField);
  @field primaryDestinationLat = contains(NumberField); // ²⁶ Primary destination coordinates
  @field primaryDestinationLon = contains(NumberField);
  @field additionalDestinations = containsMany(Destination);
  @field tripType = contains(StringField);
  @field startDate = contains(DateField);
  @field endDate = contains(DateField);
  @field travelers = containsMany(Traveler);
  @field tripStatus = contains(StringField);

  // Itinerary & Activities
  @field dailySchedule = linksToMany(() => DayPlan);
  @field notes = contains(MarkdownField);

  // Budget Management
  @field totalBudget = contains(NumberField);
  @field budgetBreakdown = contains(BudgetCategories);
  @field expenses = linksToMany(() => Expense);
  @field currency = contains(StringField);
  @field emergencyFund = contains(NumberField);

  // Bookings & Reservations
  @field flights = linksToMany(() => FlightBooking);

  // Travel Documents
  @field passportExpiry = contains(DateField);
  @field travelInsurance = contains(StringField);
  @field emergencyContact = contains(StringField);

  // Computed Fields
  @field duration = contains(NumberField, {
    // ¹⁵ Trip duration
    computeVia: function (this: TravelPlanner) {
      try {
        if (!this.startDate || !this.endDate) return 0;
        const start = new Date(this.startDate);
        const end = new Date(this.endDate);
        const diffTime = Math.abs(end.getTime() - start.getTime());
        return Math.ceil(diffTime / (1000 * 60 * 60 * 24));
      } catch (e) {
        console.error('TravelPlanner: Error computing duration', e);
        return 0;
      }
    },
  });

  @field remainingBudget = contains(NumberField, {
    // ¹⁶ Budget remaining
    computeVia: function (this: TravelPlanner) {
      try {
        const total = this.totalBudget || 0;
        const spent =
          this.expenses?.reduce((sum, expense) => {
            return sum + (expense.convertedAmount || expense.amount || 0);
          }, 0) || 0;
        return Math.max(0, total - spent);
      } catch (e) {
        console.error('TravelPlanner: Error computing remaining budget', e);
        return this.totalBudget || 0;
      }
    },
  });

  @field cardTitle = contains(StringField, {
    // ¹⁷ Computed title
    computeVia: function (this: TravelPlanner) {
      try {
        const name = this.tripName ?? 'Trip';
        const dest = this.destination ?? 'Unknown Destination';
        return `${name} - ${dest}`;
      } catch (e) {
        console.error('TravelPlanner: Error computing title', e);
        return 'Travel Planner';
      }
    },
  });

  // ¹⁸ Isolated format - comprehensive travel dashboard
  static isolated = class Isolated extends Component<typeof TravelPlanner> {
    @tracked activeTab = 'overview';

    get daysUntilTrip() {
      try {
        if (!this.args?.model?.startDate) return null;
        const start = new Date(this.args.model.startDate);
        const today = new Date();
        const diffTime = start.getTime() - today.getTime();
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        return diffDays > 0 ? diffDays : 0;
      } catch (e) {
        console.error('TravelPlanner: Error computing days until trip', e);
        return null;
      }
    }

    get budgetUtilization() {
      try {
        const total = this.args?.model?.totalBudget || 0;
        const remaining = this.args?.model?.remainingBudget || total;
        return total > 0 ? Math.round(((total - remaining) / total) * 100) : 0;
      } catch (e) {
        console.error('TravelPlanner: Error computing budget utilization', e);
        return 0;
      }
    }

    // ²⁸ Prepare destinations for map display
    get mapDestinations() {
      try {
        const destinations = [];

        // Add primary destination if coordinates exist
        if (
          this.args?.model?.primaryDestinationLat &&
          this.args?.model?.primaryDestinationLon
        ) {
          destinations.push({
            lat: this.args.model.primaryDestinationLat,
            lon: this.args.model.primaryDestinationLon,
            name: this.args.model.destination || 'Primary Destination',
            description: 'Main destination for this trip',
          });
        }

        // Add additional destinations with coordinates
        this.args?.model?.additionalDestinations?.forEach(
          (dest: any, index: number) => {
            if (dest.lat && dest.lon) {
              destinations.push({
                lat: dest.lat,
                lon: dest.lon,
                name: dest.name || `Destination ${index + 2}`,
                description:
                  dest.notes ||
                  `${
                    dest.country ? `${dest.country} - ` : ''
                  }Additional stop on the journey`,
              });
            }
          },
        );

        return destinations;
      } catch (e) {
        console.error('TravelPlanner: Error preparing map destinations', e);
        return [];
      }
    }

    switchTab = (tabName: string) => {
      this.activeTab = tabName;
    };

    <template>
      <div class='stage'>
        <div class='travel-planner-mat'>
          <!-- ¹⁹ Header with trip overview -->
          <header class='trip-header'>
            <div class='header-main'>
              <h1>{{if @model.tripName @model.tripName 'Untitled Trip'}}</h1>
              <div class='destination-info'>
                <span class='destination'>{{if
                    @model.destination
                    @model.destination
                    'Destination TBD'
                  }}</span>
                {{#if @model.tripType}}
                  <Pill
                    @kind='primary'
                    class='trip-type'
                  >{{@model.tripType}}</Pill>
                {{/if}}
              </div>
              <div class='trip-dates'>
                {{formatDateTime
                  @model.startDate
                  size='medium'
                  fallback='Start date TBD'
                }}
                -
                {{formatDateTime
                  @model.endDate
                  size='medium'
                  fallback='End date TBD'
                }}
                {{#if @model.duration}}
                  <span class='duration'>({{@model.duration}} days)</span>
                {{/if}}
              </div>
            </div>

            <div class='header-stats'>
              {{#if this.daysUntilTrip}}
                <div class='stat'>
                  <div class='stat-number'>{{this.daysUntilTrip}}</div>
                  <div class='stat-label'>Days Until Trip</div>
                </div>
              {{/if}}

              {{#if @model.totalBudget}}
                <div class='stat'>
                  <div class='stat-number'>{{this.budgetUtilization}}%</div>
                  <div class='stat-label'>Budget Used</div>
                </div>
              {{/if}}

              {{#if (gt @model.travelers.length 0)}}
                <div class='stat'>
                  <div class='stat-number'>{{@model.travelers.length}}</div>
                  <div class='stat-label'>{{if
                      (eq @model.travelers.length 1)
                      'Traveler'
                      'Travelers'
                    }}</div>
                </div>
              {{/if}}
            </div>
          </header>

          <!-- ²⁰ Navigation tabs -->
          <nav class='trip-nav'>
            <Button
              @variant={{if (eq this.activeTab 'overview') 'primary' 'ghost'}}
              class='nav-button'
              {{on 'click' (fn this.switchTab 'overview')}}
            >
              Overview
            </Button>
            <Button
              @variant={{if (eq this.activeTab 'map') 'primary' 'ghost'}}
              class='nav-button'
              {{on 'click' (fn this.switchTab 'map')}}
            >
              Map
            </Button>
            <Button
              @variant={{if (eq this.activeTab 'itinerary') 'primary' 'ghost'}}
              class='nav-button'
              {{on 'click' (fn this.switchTab 'itinerary')}}
            >
              Itinerary
            </Button>
            <Button
              @variant={{if (eq this.activeTab 'bookings') 'primary' 'ghost'}}
              class='nav-button'
              {{on 'click' (fn this.switchTab 'bookings')}}
            >
              Bookings
            </Button>
            <Button
              @variant={{if (eq this.activeTab 'budget') 'primary' 'ghost'}}
              class='nav-button'
              {{on 'click' (fn this.switchTab 'budget')}}
            >
              Budget
            </Button>
          </nav>

          <!-- ²¹ Tab content -->
          <main class='trip-content'>
            {{#if (eq this.activeTab 'overview')}}
              <div class='overview-tab'>
                <div class='overview-grid'>
                  <!-- Quick Stats -->
                  <section class='quick-stats'>
                    <h3>Trip Status</h3>
                    {{#if @model.tripStatus}}
                      <Pill
                        @kind='success'
                        class='status-pill'
                      >{{@model.tripStatus}}</Pill>
                    {{else}}
                      <Pill @kind='warning' class='status-pill'>Planning</Pill>
                    {{/if}}

                    {{#if @model.totalBudget}}
                      <div class='budget-overview'>
                        <div class='budget-total'>
                          Total Budget:
                          {{formatCurrency
                            @model.totalBudget
                            currency=@model.currency
                            fallback='USD'
                          }}
                        </div>
                        <div class='budget-remaining'>
                          Remaining:
                          {{formatCurrency
                            @model.remainingBudget
                            currency=@model.currency
                            fallback='USD'
                          }}
                        </div>
                      </div>
                    {{/if}}
                  </section>

                  <!-- Travelers -->
                  {{#if (gt @model.travelers.length 0)}}
                    <section class='travelers-section'>
                      <h3>Travelers</h3>
                      <div class='travelers-container'>
                        <@fields.travelers @format='embedded' />
                      </div>
                    </section>
                  {{/if}}

                  <!-- Additional Destinations -->
                  {{#if (gt @model.additionalDestinations.length 0)}}
                    <section class='destinations-section'>
                      <h3>Additional Destinations</h3>
                      <div class='destinations-container'>
                        <@fields.additionalDestinations @format='embedded' />
                      </div>
                    </section>
                  {{/if}}

                  <!-- Notes -->
                  {{#if @model.notes}}
                    <section class='notes-section'>
                      <h3>Trip Notes</h3>
                      <@fields.notes />
                    </section>
                  {{/if}}
                </div>
              </div>
            {{/if}}

            {{#if (eq this.activeTab 'map')}}
              <!-- ²⁹ Interactive map view -->
              <div class='map-tab'>
                <h3>Trip Destinations</h3>
                {{#if (gt this.mapDestinations.length 0)}}
                  <div class='map-container'>
                    <figure
                      {{TravelMapModifier
                        destinations=this.mapDestinations
                        centerLat=@model.primaryDestinationLat
                        centerLon=@model.primaryDestinationLon
                      }}
                      class='travel-map'
                    >
                      <div class='map-loading'>
                        Loading interactive map for your trip destinations...
                        <div class='loading-destinations'>
                          {{#each this.mapDestinations as |dest|}}
                            <div class='dest-preview'>📍 {{dest.name}}</div>
                          {{/each}}
                        </div>
                      </div>
                    </figure>

                    <div class='map-legend'>
                      <h4>Destinations on Map</h4>
                      <ul class='destinations-list'>
                        {{#each this.mapDestinations as |dest index|}}
                          <li class='destination-item'>
                            <span class='marker-icon'>📍</span>
                            <div class='dest-info'>
                              <strong>{{dest.name}}</strong>
                              {{#if dest.description}}
                                <p>{{dest.description}}</p>
                              {{/if}}
                            </div>
                          </li>
                        {{/each}}
                      </ul>
                    </div>
                  </div>
                {{else}}
                  <div class='empty-state'>
                    <p>Add coordinates to your destinations to see them on the
                      map.</p>
                    <div class='map-help'>
                      <h4>To show destinations on the map:</h4>
                      <ol>
                        <li>Edit your primary destination and add
                          latitude/longitude coordinates</li>
                        <li>Add coordinates to additional destinations</li>
                        <li>The map will automatically display markers for all
                          locations</li>
                      </ol>
                    </div>
                  </div>
                {{/if}}
              </div>
            {{/if}}

            {{#if (eq this.activeTab 'itinerary')}}
              <div class='itinerary-tab'>
                <h3>Daily Schedule</h3>
                {{#if (gt @model.dailySchedule.length 0)}}
                  <div class='schedule-container'>
                    <@fields.dailySchedule @format='embedded' />
                  </div>
                {{else}}
                  <div class='empty-state'>
                    <p>No daily schedule created yet. Start planning your
                      itinerary!</p>
                  </div>
                {{/if}}
              </div>
            {{/if}}

            {{#if (eq this.activeTab 'bookings')}}
              <div class='bookings-tab'>
                <h3>Flight Bookings</h3>
                {{#if (gt @model.flights.length 0)}}
                  <div class='flights-container'>
                    <@fields.flights @format='embedded' />
                  </div>
                {{else}}
                  <div class='empty-state'>
                    <p>No flight bookings added yet. Add your flight details to
                      track them here.</p>
                  </div>
                {{/if}}

                <!-- Travel Documents Section -->
                <section class='documents-section'>
                  <h3>Travel Documents</h3>
                  <div class='documents-grid'>
                    {{#if @model.passportExpiry}}
                      <div class='document-item'>
                        <strong>Passport Expiry:</strong>
                        <span>{{formatDateTime
                            @model.passportExpiry
                            size='medium'
                          }}</span>
                      </div>
                    {{/if}}
                    {{#if @model.travelInsurance}}
                      <div class='document-item'>
                        <strong>Travel Insurance:</strong>
                        <span>{{@model.travelInsurance}}</span>
                      </div>
                    {{/if}}
                    {{#if @model.emergencyContact}}
                      <div class='document-item'>
                        <strong>Emergency Contact:</strong>
                        <span>{{@model.emergencyContact}}</span>
                      </div>
                    {{/if}}
                  </div>
                </section>
              </div>
            {{/if}}

            {{#if (eq this.activeTab 'budget')}}
              <div class='budget-tab'>
                <div class='budget-overview-detailed'>
                  {{#if @model.totalBudget}}
                    <div class='budget-summary'>
                      <h3>Budget Summary</h3>
                      <div class='budget-bars'>
                        <div class='budget-bar'>
                          <div
                            class='budget-bar-fill'
                            style={{concat
                              'width: '
                              this.budgetUtilization
                              '%'
                            }}
                          ></div>
                        </div>
                        <div class='budget-amounts'>
                          <span>Spent:
                            {{formatCurrency
                              (subtract
                                @model.totalBudget @model.remainingBudget
                              )
                              currency=@model.currency
                              fallback='USD'
                            }}</span>
                          <span>Remaining:
                            {{formatCurrency
                              @model.remainingBudget
                              currency=@model.currency
                              fallback='USD'
                            }}</span>
                        </div>
                      </div>
                    </div>
                  {{/if}}

                  {{#if @model.budgetBreakdown}}
                    <div class='budget-breakdown'>
                      <h3>Budget Breakdown</h3>
                      <@fields.budgetBreakdown />
                    </div>
                  {{/if}}

                  {{#if (gt @model.expenses.length 0)}}
                    <div class='expenses-section'>
                      <h3>Recent Expenses</h3>
                      <div class='expenses-container'>
                        <@fields.expenses @format='embedded' />
                      </div>
                    </div>
                  {{/if}}
                </div>
              </div>
            {{/if}}
          </main>
        </div>
      </div>

      <style scoped>
        /* ²² Comprehensive styling */
        .stage {
          width: 100%;
          height: 100%;
          display: flex;
          justify-content: center;
          padding: 1rem;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }

        @media (max-width: 800px) {
          .stage {
            padding: 0;
          }
        }

        .travel-planner-mat {
          max-width: 75rem;
          width: 100%;
          background: white;
          border-radius: 1rem;
          box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
          overflow-y: auto;
          max-height: 100%;
          font-family: 'Inter', system-ui, sans-serif;
        }

        @media (max-width: 800px) {
          .travel-planner-mat {
            border-radius: 0;
            height: 100%;
          }
        }

        /* Header Styling */
        .trip-header {
          background: linear-gradient(135deg, #1e40af 0%, #3b82f6 100%);
          color: white;
          padding: 2rem;
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: 2rem;
        }

        .header-main h1 {
          font-size: 2rem;
          font-weight: 700;
          margin: 0 0 0.5rem 0;
          line-height: 1.2;
        }

        .destination-info {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          margin-bottom: 0.5rem;
        }

        .destination {
          font-size: 1.125rem;
          font-weight: 500;
          opacity: 0.95;
        }

        .trip-type {
          background: rgba(255, 255, 255, 0.2);
          color: white;
          border: 1px solid rgba(255, 255, 255, 0.3);
        }

        .trip-dates {
          font-size: 0.875rem;
          opacity: 0.9;
        }

        .duration {
          color: #bfdbfe;
          margin-left: 0.5rem;
        }

        .header-stats {
          display: flex;
          gap: 1.5rem;
          flex-shrink: 0;
        }

        .stat {
          text-align: center;
          min-width: 4rem;
        }

        .stat-number {
          font-size: 1.5rem;
          font-weight: 700;
          line-height: 1;
        }

        .stat-label {
          font-size: 0.75rem;
          opacity: 0.9;
          margin-top: 0.25rem;
        }

        /* Navigation */
        .trip-nav {
          display: flex;
          gap: 0.25rem;
          padding: 1rem 2rem 0 2rem;
          border-bottom: 1px solid #e5e7eb;
          background: #f9fafb;
        }

        .nav-button {
          padding: 0.5rem 1rem;
          font-size: 0.875rem;
          font-weight: 500;
          border: none;
          border-radius: 0.5rem 0.5rem 0 0;
          transition: all 0.2s ease;
        }

        /* Content Areas */
        .trip-content {
          padding: 2rem;
          min-height: 20rem;
        }

        .overview-grid {
          display: grid;
          gap: 2rem;
          grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
        }

        .quick-stats h3,
        .travelers-section h3,
        .destinations-section h3,
        .notes-section h3 {
          margin: 0 0 1rem 0;
          font-size: 1.125rem;
          font-weight: 600;
          color: #374151;
        }

        .status-pill {
          margin-bottom: 1rem;
        }

        .budget-overview {
          padding: 1rem;
          background: #f0f9ff;
          border: 1px solid #bae6fd;
          border-radius: 0.5rem;
        }

        .budget-total {
          font-weight: 600;
          color: #1e40af;
          margin-bottom: 0.5rem;
        }

        .budget-remaining {
          color: #059669;
          font-weight: 500;
        }

        /* Collection Spacing */
        .travelers-container > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }

        .destinations-container > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }

        .schedule-container > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }

        .flights-container > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }

        .expenses-container > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }

        /* Documents Section */
        .documents-section {
          margin-top: 2rem;
          padding-top: 2rem;
          border-top: 1px solid #e5e7eb;
        }

        .documents-grid {
          display: grid;
          gap: 1rem;
          grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
        }

        .document-item {
          padding: 1rem;
          background: #f8fafc;
          border: 1px solid #e2e8f0;
          border-radius: 0.5rem;
        }

        .document-item strong {
          display: block;
          margin-bottom: 0.5rem;
          color: #374151;
        }

        /* Budget Tab */
        .budget-summary {
          margin-bottom: 2rem;
        }

        .budget-bars {
          margin-top: 1rem;
        }

        .budget-bar {
          width: 100%;
          height: 0.75rem;
          background: #e5e7eb;
          border-radius: 0.375rem;
          overflow: hidden;
          margin-bottom: 0.5rem;
        }

        .budget-bar-fill {
          height: 100%;
          background: linear-gradient(
            90deg,
            #ef4444 0%,
            #f97316 50%,
            #22c55e 100%
          );
          border-radius: 0.375rem;
          transition: width 0.3s ease;
        }

        .budget-amounts {
          display: flex;
          justify-content: space-between;
          font-size: 0.875rem;
          color: #6b7280;
        }

        .budget-breakdown {
          margin-bottom: 2rem;
        }

        /* Map Tab Styling */
        .map-container {
          display: grid;
          grid-template-columns: 2fr 1fr;
          gap: 2rem;
          height: 32rem;
        }

        .travel-map {
          margin: 0;
          width: 100%;
          height: 100%;
          border-radius: 0.75rem;
          overflow: hidden;
          box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.1);
        }

        .map-loading {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100%;
          background: linear-gradient(135deg, #f0f9ff 0%, #e0f2fe 100%);
          color: #0369a1;
          font-weight: 500;
          text-align: center;
          padding: 2rem;
        }

        .loading-destinations {
          margin-top: 1rem;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }

        .dest-preview {
          font-size: 0.875rem;
          opacity: 0.8;
        }

        .map-legend {
          background: white;
          border: 1px solid #e5e7eb;
          border-radius: 0.75rem;
          padding: 1.5rem;
          height: fit-content;
        }

        .map-legend h4 {
          margin: 0 0 1rem 0;
          color: #374151;
          font-size: 1rem;
        }

        .destinations-list {
          list-style: none;
          padding: 0;
          margin: 0;
        }

        .destination-item {
          display: flex;
          align-items: flex-start;
          gap: 0.75rem;
          padding: 0.75rem;
          margin-bottom: 0.5rem;
          background: #f8fafc;
          border-radius: 0.5rem;
          border-left: 3px solid #3b82f6;
        }

        .marker-icon {
          font-size: 1.25rem;
          flex-shrink: 0;
        }

        .dest-info strong {
          display: block;
          color: #1e40af;
          margin-bottom: 0.25rem;
        }

        .dest-info p {
          margin: 0;
          font-size: 0.875rem;
          color: #6b7280;
          line-height: 1.4;
        }

        .map-help {
          background: #fef3c7;
          border: 1px solid #f59e0b;
          border-radius: 0.5rem;
          padding: 1.5rem;
          margin-top: 1.5rem;
          text-align: left;
        }

        .map-help h4 {
          margin: 0 0 1rem 0;
          color: #92400e;
        }

        .map-help ol {
          color: #92400e;
          margin: 0;
          padding-left: 1.25rem;
        }

        .map-help li {
          margin-bottom: 0.5rem;
        }

        /* Empty States */
        .empty-state {
          text-align: center;
          padding: 3rem 1rem;
          color: #6b7280;
          background: #f9fafb;
          border: 2px dashed #d1d5db;
          border-radius: 0.75rem;
        }

        .empty-state p {
          margin: 0;
          font-size: 1rem;
        }

        /* Responsive Design */
        @media (max-width: 640px) {
          .trip-header {
            flex-direction: column;
            gap: 1rem;
          }

          .header-stats {
            align-self: stretch;
            justify-content: space-around;
          }

          .trip-nav {
            padding: 1rem;
            overflow-x: auto;
          }

          .trip-content {
            padding: 1rem;
          }

          .overview-grid {
            grid-template-columns: 1fr;
          }

          .documents-grid {
            grid-template-columns: 1fr;
          }

          .map-container {
            grid-template-columns: 1fr;
            height: auto;
          }

          .travel-map {
            height: 20rem;
            margin-bottom: 1rem;
          }
        }
      </style>

      <link
        href='https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.css'
        rel='stylesheet'
      />
    </template>
  };

  // ²³ Embedded format - compact trip card
  static embedded = class Embedded extends Component<typeof TravelPlanner> {
    get daysUntilTrip() {
      try {
        if (!this.args?.model?.startDate) return null;
        const start = new Date(this.args.model.startDate);
        const today = new Date();
        const diffTime = start.getTime() - today.getTime();
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        return diffDays > 0 ? diffDays : 0;
      } catch (e) {
        return null;
      }
    }

    <template>
      <div class='travel-card'>
        <header class='card-header'>
          <h3>{{if @model.tripName @model.tripName 'Untitled Trip'}}</h3>
          {{#if @model.tripStatus}}
            <Pill
              @kind='primary'
              class='status-badge'
            >{{@model.tripStatus}}</Pill>
          {{/if}}
        </header>

        <div class='card-content'>
          <div class='destination'>
            <span class='destination-icon'>📍</span>
            {{if @model.destination @model.destination 'Destination TBD'}}
          </div>

          <div class='trip-dates'>
            {{formatDateTime
              @model.startDate
              size='short'
              fallback='Start TBD'
            }}
            -
            {{formatDateTime @model.endDate size='short' fallback='End TBD'}}
          </div>

          <div class='trip-stats'>
            {{#if this.daysUntilTrip}}
              <span class='stat'>{{this.daysUntilTrip}}
                days until departure</span>
            {{/if}}
            {{#if @model.totalBudget}}
              <span class='stat'>{{formatCurrency
                  @model.totalBudget
                  currency=@model.currency
                  fallback='USD'
                }}
                budget</span>
            {{/if}}
            {{#if (gt @model.travelers.length 0)}}
              <span class='stat'>{{@model.travelers.length}}
                {{if
                  (eq @model.travelers.length 1)
                  'traveler'
                  'travelers'
                }}</span>
            {{/if}}
          </div>
        </div>
      </div>

      <style scoped>
        .travel-card {
          border: 1px solid #e2e8f0;
          border-radius: 0.75rem;
          padding: 1.25rem;
          background: linear-gradient(135deg, #fef7ff 0%, #f0f9ff 100%);
          font-family: 'Inter', system-ui, sans-serif;
        }

        .card-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 1rem;
        }

        .card-header h3 {
          margin: 0;
          font-size: 1.125rem;
          font-weight: 600;
          color: #1e40af;
        }

        .status-badge {
          font-size: 0.75rem;
        }

        .destination {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 1rem;
          font-weight: 500;
          color: #374151;
          margin-bottom: 0.75rem;
        }

        .destination-icon {
          font-size: 1.125rem;
        }

        .trip-dates {
          font-size: 0.875rem;
          color: #6b7280;
          margin-bottom: 0.75rem;
        }

        .trip-stats {
          display: flex;
          flex-wrap: wrap;
          gap: 0.75rem;
          font-size: 0.8125rem;
        }

        .stat {
          color: #059669;
          font-weight: 500;
        }
      </style>
    </template>
  };

  // ²⁴ Fitted format - grid-friendly trip tile
  static fitted = class Fitted extends Component<typeof TravelPlanner> {
    <template>
      <div class='fitted-container'>
        <!-- Badge Format -->
        <div class='badge-format'>
          <div class='badge-content'>
            <div class='primary-text'>{{if
                @model.tripName
                @model.tripName
                'Trip'
              }}</div>
            <div class='secondary-text'>{{if
                @model.destination
                @model.destination
                'TBD'
              }}</div>
          </div>
        </div>

        <!-- Strip Format -->
        <div class='strip-format'>
          <div class='strip-content'>
            <div class='strip-main'>
              <div class='primary-text'>{{if
                  @model.tripName
                  @model.tripName
                  'Untitled Trip'
                }}</div>
              <div class='secondary-text'>{{if
                  @model.destination
                  @model.destination
                  'Destination TBD'
                }}</div>
            </div>
            <div class='strip-meta'>
              {{#if @model.startDate}}
                <div class='tertiary-text'>{{formatDateTime
                    @model.startDate
                    size='tiny'
                  }}</div>
              {{/if}}
            </div>
          </div>
        </div>

        <!-- Tile Format -->
        <div class='tile-format'>
          <div class='tile-content'>
            <header class='tile-header'>
              <h4 class='primary-text'>{{if
                  @model.tripName
                  @model.tripName
                  'Untitled Trip'
                }}</h4>
              {{#if @model.tripStatus}}
                <span class='status-indicator'>{{@model.tripStatus}}</span>
              {{/if}}
            </header>
            <div class='tile-body'>
              <div class='destination-line'>
                <span class='destination-icon'>📍</span>
                <span class='secondary-text'>{{if
                    @model.destination
                    @model.destination
                    'Destination TBD'
                  }}</span>
              </div>
              {{#if @model.startDate}}
                <div class='tertiary-text'>{{formatDateTime
                    @model.startDate
                    size='short'
                  }}
                  -
                  {{formatDateTime @model.endDate size='short'}}</div>
              {{/if}}
            </div>
            <footer class='tile-footer'>
              {{#if @model.totalBudget}}
                <span class='budget-info'>{{formatCurrency
                    @model.totalBudget
                    size='tiny'
                    currency=@model.currency
                    fallback='USD'
                  }}</span>
              {{/if}}
              {{#if (gt @model.travelers.length 0)}}
                <span class='travelers-info'>{{@model.travelers.length}}
                  {{if
                    (eq @model.travelers.length 1)
                    'traveler'
                    'travelers'
                  }}</span>
              {{/if}}
            </footer>
          </div>
        </div>

        <!-- Card Format -->
        <div class='card-format'>
          <div class='card-content'>
            <header class='card-header'>
              <h4 class='primary-text'>{{if
                  @model.tripName
                  @model.tripName
                  'Untitled Trip'
                }}</h4>
              <div class='header-badges'>
                {{#if @model.tripStatus}}
                  <span class='status-badge'>{{@model.tripStatus}}</span>
                {{/if}}
                {{#if @model.tripType}}
                  <span class='type-badge'>{{@model.tripType}}</span>
                {{/if}}
              </div>
            </header>

            <div class='card-body'>
              <div class='destination-section'>
                <span class='destination-icon'>📍</span>
                <div>
                  <div class='secondary-text'>{{if
                      @model.destination
                      @model.destination
                      'Destination TBD'
                    }}</div>
                  {{#if (gt @model.additionalDestinations.length 0)}}
                    <div
                      class='tertiary-text'
                    >+{{@model.additionalDestinations.length}}
                      more destinations</div>
                  {{/if}}
                </div>
              </div>

              {{#if @model.startDate}}
                <div class='dates-section'>
                  <div class='secondary-text'>{{formatDateTime
                      @model.startDate
                      size='medium'
                    }}
                    -
                    {{formatDateTime @model.endDate size='medium'}}</div>
                  {{#if @model.duration}}
                    <div class='tertiary-text'>{{@model.duration}} days</div>
                  {{/if}}
                </div>
              {{/if}}

              <div class='stats-grid'>
                {{#if @model.totalBudget}}
                  <div class='stat-item'>
                    <div class='stat-value'>{{formatCurrency
                        @model.totalBudget
                        size='short'
                        currency=@model.currency
                        fallback='USD'
                      }}</div>
                    <div class='stat-label'>Budget</div>
                  </div>
                {{/if}}

                {{#if (gt @model.travelers.length 0)}}
                  <div class='stat-item'>
                    <div class='stat-value'>{{@model.travelers.length}}</div>
                    <div class='stat-label'>{{if
                        (eq @model.travelers.length 1)
                        'Traveler'
                        'Travelers'
                      }}</div>
                  </div>
                {{/if}}

                {{#if (gt @model.flights.length 0)}}
                  <div class='stat-item'>
                    <div class='stat-value'>{{@model.flights.length}}</div>
                    <div class='stat-label'>{{if
                        (eq @model.flights.length 1)
                        'Flight'
                        'Flights'
                      }}</div>
                  </div>
                {{/if}}
              </div>
            </div>
          </div>
        </div>
      </div>

      <style scoped>
        .fitted-container {
          container-type: size;
          width: 100%;
          height: 100%;
          font-family: 'Inter', system-ui, sans-serif;
        }

        /* Hide all by default */
        .badge-format,
        .strip-format,
        .tile-format,
        .card-format {
          display: none;
          width: 100%;
          height: 100%;
          padding: clamp(0.1875rem, 2%, 0.625rem);
          box-sizing: border-box;
        }

        /* Typography hierarchy */
        .primary-text {
          font-size: 1em;
          font-weight: 600;
          color: #1e40af;
          line-height: 1.2;
        }

        .secondary-text {
          font-size: 0.875em;
          font-weight: 500;
          color: #374151;
          line-height: 1.3;
        }

        .tertiary-text {
          font-size: 0.75em;
          font-weight: 400;
          color: #6b7280;
          line-height: 1.4;
        }

        /* Badge Format (≤150px width, ≤169px height) */
        @container (max-width: 150px) and (max-height: 169px) {
          .badge-format {
            display: flex;
          }
        }

        .badge-content {
          display: flex;
          flex-direction: column;
          justify-content: center;
          text-align: left;
          width: 100%;
        }

        @container (max-width: 150px) and (max-height: 40px) {
          .badge-content {
            flex-direction: row;
            align-items: center;
            gap: 0.25rem;
          }
          .primary-text {
            font-size: 0.75em;
          }
          .secondary-text {
            font-size: 0.625em;
            opacity: 0.8;
          }
        }

        @container (max-width: 150px) and (min-height: 105px) {
          .badge-content {
            justify-content: space-between;
          }
        }

        /* Strip Format (>150px width, ≤169px height) */
        @container (min-width: 151px) and (max-height: 169px) {
          .strip-format {
            display: flex;
          }
        }

        .strip-content {
          display: flex;
          justify-content: space-between;
          align-items: center;
          width: 100%;
        }

        .strip-main {
          flex: 1;
        }

        .strip-meta {
          text-align: right;
          flex-shrink: 0;
          margin-left: 1rem;
        }

        @container (min-width: 151px) and (max-height: 40px) {
          .strip-main {
            display: flex;
            align-items: center;
            gap: 0.5rem;
          }
          .primary-text {
            font-size: 0.875em;
          }
          .secondary-text {
            font-size: 0.75em;
            opacity: 0.8;
          }
        }

        @container (min-width: 151px) and (min-height: 65px) and (max-height: 169px) {
          .strip-main {
            display: flex;
            flex-direction: column;
            gap: 0.25rem;
          }
        }

        /* Tile Format (≤399px width, ≥170px height) */
        @container (max-width: 399px) and (min-height: 170px) {
          .tile-format {
            display: flex;
            flex-direction: column;
          }
        }

        .tile-content {
          display: flex;
          flex-direction: column;
          height: 100%;
        }

        .tile-header {
          margin-bottom: 0.75rem;
        }

        .tile-header h4 {
          margin: 0 0 0.25rem 0;
        }

        .status-indicator {
          font-size: 0.75em;
          color: #059669;
          font-weight: 500;
        }

        .tile-body {
          flex: 1;
        }

        .destination-line {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          margin-bottom: 0.5rem;
        }

        .destination-icon {
          font-size: 0.875em;
        }

        .tile-footer {
          margin-top: auto;
          padding-top: 0.75rem;
          display: flex;
          justify-content: space-between;
          font-size: 0.75em;
          color: #6b7280;
        }

        .budget-info,
        .travelers-info {
          font-weight: 500;
        }

        /* Card Format (≥400px width, ≥170px height) */
        @container (min-width: 400px) and (min-height: 170px) {
          .card-format {
            display: flex;
            flex-direction: column;
          }
        }

        .card-content {
          display: flex;
          flex-direction: column;
          height: 100%;
          background: linear-gradient(135deg, #fef7ff 0%, #f0f9ff 100%);
          border-radius: 0.5rem;
          padding: 1rem;
        }

        .card-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          margin-bottom: 1rem;
        }

        .card-header h4 {
          margin: 0;
          flex: 1;
        }

        .header-badges {
          display: flex;
          gap: 0.5rem;
          flex-shrink: 0;
        }

        .status-badge,
        .type-badge {
          font-size: 0.75em;
          padding: 0.125rem 0.375rem;
          border-radius: 0.25rem;
          font-weight: 500;
        }

        .status-badge {
          background: #dcfce7;
          color: #166534;
        }

        .type-badge {
          background: #dbeafe;
          color: #1e40af;
        }

        .card-body {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }

        .destination-section {
          display: flex;
          align-items: flex-start;
          gap: 0.5rem;
        }

        .dates-section {
          padding: 0.5rem;
          background: rgba(255, 255, 255, 0.5);
          border-radius: 0.375rem;
        }

        .stats-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(4rem, 1fr));
          gap: 0.75rem;
          margin-top: auto;
          padding-top: 0.75rem;
        }

        .stat-item {
          text-align: center;
        }

        .stat-value {
          font-size: 0.875em;
          font-weight: 600;
          color: #1e40af;
          line-height: 1;
        }

        .stat-label {
          font-size: 0.625em;
          color: #6b7280;
          margin-top: 0.125rem;
        }

        /* Compact card layout (400px width, 170px height) */
        @container (min-width: 400px) and (height: 170px) {
          .card-content {
            flex-direction: row;
            gap: 1rem;
          }
          .card-content > * {
            display: flex;
            flex-direction: column;
          }
          .card-content > *:first-child {
            flex: 1.618;
          }
          .card-content > *:last-child {
            flex: 1;
          }
        }
      </style>
    </template>
  };
}
