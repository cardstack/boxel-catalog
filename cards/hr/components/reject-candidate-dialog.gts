import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { not } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { Dialog } from '@cardstack/pretui/components/dialog';
import { RadioGroup } from '@cardstack/pretui/components/radio-group';
import { Textarea } from '@cardstack/pretui/components/textarea';

import { REJECTION_REASON_OPTIONS } from '@cardstack/catalog/cards/hr/rejection-reason-field';

interface RejectCandidateDialogSignature {
  Args: {
    isOpen: boolean;
    candidateName?: string;
    onConfirm: (reason: string, note: string) => void;
    onCancel: () => void;
  };
  Element: HTMLElement;
}

// A plain Glimmer component (not a card or field), so a board can render one
// dialog for every candidate instead of one per candidate card.
export class RejectCandidateDialog extends GlimmerComponent<RejectCandidateDialogSignature> {
  reasonOptions = REJECTION_REASON_OPTIONS.map((opt) => ({
    value: opt.value,
    label: opt.label,
  }));

  @tracked reason: string | undefined;
  @tracked note = '';

  private reset() {
    this.reason = undefined;
    this.note = '';
  }

  // The note shows for every reason, so whatever is submitted is on screen.
  get showNoteField(): boolean {
    return Boolean(this.reason);
  }

  get noteLabel(): string {
    return this.reason === 'other'
      ? 'Details (required)'
      : 'Details (optional)';
  }

  get canConfirm(): boolean {
    if (!this.reason) {
      return false;
    }
    if (this.reason === 'other' && !this.note.trim()) {
      return false;
    }
    return true;
  }

  get title(): string {
    return this.args.candidateName
      ? `Reject ${this.args.candidateName}?`
      : 'Reject candidate?';
  }

  setReason = (id: string) => {
    this.reason = id;
  };

  setNote = (value: string) => {
    this.note = value;
  };

  confirm = () => {
    if (!this.canConfirm || !this.reason) {
      return;
    }
    let reason = this.reason;
    let note = this.note.trim();
    this.reset();
    this.args.onConfirm(reason, note);
  };

  // Reset happens on the way out (cancel or confirm), not on open — a getter
  // that mutates tracked state to react to a just-opened prop risks Ember's
  // "backtracking rerender" assertion. Resetting on close has the same
  // observable effect: the dialog can only reopen after one of these fires.
  cancel = () => {
    this.reset();
    this.args.onCancel();
  };

  <template>
    <Dialog @open={{@isOpen}} @onClose={{this.cancel}} @size='s'>
      <:title>{{this.title}}</:title>
      <:default>
        <div class='reject-dialog'>
          <p class='rd-sub'>Choose a reason, so rejections can be counted by
            cause.</p>
          <RadioGroup
            @options={{this.reasonOptions}}
            @value={{this.reason}}
            @onValueChange={{this.setReason}}
            aria-label='Rejection reason'
          />
          {{#if this.showNoteField}}
            <label
              class='rd-note-label'
              for='reject-dialog-note'
            >{{this.noteLabel}}</label>
            <Textarea
              @controlId='reject-dialog-note'
              @value={{this.note}}
              @onInput={{this.setNote}}
              @placeholder='What happened?'
            />
          {{/if}}
        </div>
      </:default>
      <:footer>
        <Button @variant='secondary' {{on 'click' this.cancel}}>Cancel</Button>
        <Button
          @variant='destructive'
          @disabled={{not this.canConfirm}}
          {{on 'click' this.confirm}}
        >Confirm rejection</Button>
      </:footer>
    </Dialog>
    <style scoped>
      .reject-dialog {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .rd-sub {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .rd-note-label {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
