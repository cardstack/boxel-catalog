import GlimmerComponent from '@glimmer/component';
import { fn } from '@ember/helper';
import { guidFor } from '@ember/object/internals';
import { Checkbox } from '@cardstack/pretui/components/checkbox';
import { describeControl } from '../real-estate-ui';

// The channel vocabulary lives HERE (a leaf module) so both this selector
// and the publish command can import it without a module cycle — the
// command imports PropertyListing, whose isolated view mounts this
// selector.
export const PUBLISH_CHANNELS = [
  'mls',
  'zillow',
  'realtor',
  'redfin',
  'agent-site',
  'facebook',
  'instagram',
];

export const PUBLISH_CHANNEL_LABELS: Record<string, string> = {
  mls: 'MLS (Multiple Listing Service)',
  zillow: 'Zillow / Trulia',
  realtor: 'Realtor.com',
  redfin: 'Redfin',
  'agent-site': 'Agent Website',
  facebook: 'Facebook',
  instagram: 'Instagram',
};

// Channel Selector — which distribution channels a listing goes to.
// Render-only: the consumer owns the selected set and flips it in
// `@onToggle`; MLS is painted checked and disabled because the command
// unions it in regardless (the portals syndicate FROM the MLS entry, so a
// publish without it is not a publish).

interface Signature {
  Args: {
    selected: string[] | undefined;
    onToggle: (channel: string) => void;
  };
  Element: HTMLElement;
}

const AUTO_SYNCED = ['zillow', 'realtor', 'redfin'];

interface ChannelRow {
  channel: string;
  label: string;
  required: boolean;
  tag: string;
  subline?: string;
  tagId: string;
  sublineId: string;
  /** the ids of the tag and subline text that describe the row's checkbox */
  describedBy: string;
}

export class ChannelSelector extends GlimmerComponent<Signature> {
  channels = PUBLISH_CHANNELS;
  idPrefix = guidFor(this);

  get rows(): ChannelRow[] {
    return this.channels.map((channel) => {
      let tagId = `${this.idPrefix}-${channel}-tag`;
      let sublineId = `${this.idPrefix}-${channel}-subline`;
      let subline =
        channel === 'mls'
          ? 'Triggers automatic syndication to major portals'
          : undefined;
      return {
        channel,
        label: PUBLISH_CHANNEL_LABELS[channel] ?? channel,
        required: channel === 'mls',
        tag:
          channel === 'mls'
            ? 'Required'
            : AUTO_SYNCED.includes(channel)
              ? 'Auto-synced'
              : 'Optional',
        subline,
        tagId,
        sublineId,
        describedBy: subline ? `${tagId} ${sublineId}` : tagId,
      };
    });
  }

  isSelected = (channel: string) =>
    channel === 'mls' || (this.args.selected ?? []).includes(channel);

  toggle = (channel: string) => {
    if (channel === 'mls') {
      return;
    }
    this.args.onToggle(channel);
  };

  <template>
    <ul class='channels' ...attributes>
      {{#each this.rows as |row|}}
        <li
          class='channel {{if row.required "required"}}'
          {{describeControl row.describedBy}}
        >
          <Checkbox
            class='channel-check'
            @label={{row.label}}
            @checked={{this.isSelected row.channel}}
            @disabled={{row.required}}
            @onCheckedChange={{fn this.toggle row.channel}}
          />
          <span class='channel-tag' id={{row.tagId}}>{{row.tag}}</span>
          {{#if row.subline}}
            <span
              class='channel-subline'
              id={{row.sublineId}}
            >{{row.subline}}</span>
          {{/if}}
        </li>
      {{/each}}
    </ul>
    <style scoped>
      .channels {
        margin: 0;
        padding: 0;
        list-style: none;
        display: grid;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      /* Pret UI Checkbox carries the box and the channel name; the tag and
         the subline sit beside it and describe the box */
      .channel {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        column-gap: var(--boxel-sp-xs);
        row-gap: 0.125rem;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-size: 0.8125rem;
      }
      .channel + .channel {
        border-top: 1px solid var(--border);
      }
      .channel-check {
        --text-ui-md: 0.8125rem;
        font-weight: 500;
        color: var(--foreground);
      }
      .required .channel-check {
        cursor: default;
      }
      .channel-tag {
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .required .channel-tag {
        color: var(--primary-ink);
        font-weight: 600;
      }
      /* the subline takes its own line, under the channel name */
      .channel-subline {
        flex-basis: 100%;
        padding-inline-start: calc(0.9375rem + var(--boxel-sp-xs));
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export default ChannelSelector;
