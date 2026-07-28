import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import WriteTextFileCommand from '@cardstack/boxel-host/tools/write-text-file';

import { SculptedModel } from '../sculpted-model';
import { requestSpec, REFINE_MODEL } from '../util/llm-request';
import { serializeSpecForPrompt, parseDiffJson } from '../util/spec-io';
import { applySpecDiff } from '../util/spec-diff';
import { generateModelJs, specFromModelJs } from '../util/code-export';
import { TARGETED_EDIT_PROMPT } from '../prompts/targeted-edit';

// What the AI Assistant hands us after it has DIAGNOSED the model against the
// reference (the assistant can see both images in the chat) and the user has
// agreed on a change: which round to edit, and one precise instruction.
class RefineSculptInput extends CardDef {
  @field sculptedModelId = contains(StringField, {
    description:
      'The id of the SculptedModel round to refine — use the id of the attached model card (its selectedCreation/latestCreation).',
  });
  @field instruction = contains(StringField, {
    description:
      'ONE precise, self-contained edit in plain words — what to change and how, naming the part(s). Examples: "recolor the shorts to bright red #d81f2a", "make the ears 30% bigger", "move the bill to the front centre of the head", "add a left wheel mirroring the right", "remove the extra nose". Describe a single change; the user approves each one.',
  });
}

// Applies ONE user-approved refinement to a sculpted model, WITHOUT re-running
// the whole generate pipeline. The heavy visual diagnosis (what differs from
// the reference) is done by the AI Assistant itself — it can see the reference
// and the round's render screenshot in the chat — so this command only has to
// TURN THE INSTRUCTION INTO A SPEC EDIT and save the result as a new round.
//
// It reads the current spec back out of the round's generated .js (the spec
// rides inside it as SCULPT_SPEC), asks the model for the minimal change set
// for the instruction, applies it, regenerates the .js as a NEW round file, and
// points the source studio at that round so the open viewport live-reloads.
export default class RefineSculptCommand extends Command<
  typeof RefineSculptInput,
  undefined
> {
  static actionVerb = 'Refine Model';
  static displayName = 'Refine Model';

  description =
    'Apply one described edit (recolor / resize / move / add / remove a part) to the attached sculpted model, in place. Use after diagnosing the model against its reference and agreeing the change with the user.';

  requireInputFields = ['sculptedModelId', 'instruction'];

  async getInputType() {
    return RefineSculptInput;
  }

  // the realm root of a generated model url: everything before the per-studio
  // asset folder (or the legacy flat exports/ dir)
  private realmOf(url: string): string {
    for (let marker of ['/img-to-3d/', '/exports/']) {
      let i = url.indexOf(marker);
      if (i >= 0) return url.slice(0, i + 1);
    }
    // fall back to the directory
    return url.slice(0, url.lastIndexOf('/') + 1);
  }

  protected async run(input: RefineSculptInput): Promise<undefined> {
    if (!input.sculptedModelId) {
      throw new Error('sculptedModelId is required');
    }
    let instruction = (input.instruction ?? '').trim();
    if (!instruction) {
      throw new Error('instruction is required');
    }

    let creation = (await new GetCardCommand(this.commandContext).execute({
      cardId: input.sculptedModelId,
    })) as SculptedModel;
    let codeFileUrl = creation.codeFileUrl;
    if (!codeFileUrl) {
      throw new Error('that model has no code file to refine');
    }

    // read the spec back out of the round's source (ask for the source bytes,
    // not the realm's transpiled form, which reflows the SCULPT_SPEC constant)
    let response = await fetch(codeFileUrl, {
      headers: { Accept: 'application/vnd.card+source' },
    });
    if (!response.ok) {
      throw new Error(`could not load the model file (${response.status})`);
    }
    let spec = specFromModelJs(await response.text());
    if (!spec?.components?.length) {
      throw new Error('the model file carries no readable spec');
    }

    // instruction → minimal change set. No image is sent: the assistant has
    // already looked at the reference vs the render and produced a precise
    // instruction, so the targeted-edit prompt resolves it from the spec alone.
    let diff = await requestSpec(
      this.commandContext,
      REFINE_MODEL,
      TARGETED_EDIT_PROMPT,
      [
        {
          type: 'text',
          text:
            `PURPOSE: you are editing an EXISTING 3D model — the SCULPT_SPEC read below out of the model's own three.js file. Your change set is applied to that spec and the file is regenerated in place, so it is what re-renders in the viewport iframe. Change ONLY what the instruction asks; leave every other part exactly as it is.\n\n` +
            `SELECTED nodeIds: []\n` +
            `No parts were pre-selected — resolve the targets from the instruction and the spec below.\n` +
            `INSTRUCTION: ${instruction}\n\nCURRENT SPEC:\n${JSON.stringify(
              serializeSpecForPrompt(spec),
            )}`,
        },
      ],
      () => {},
      parseDiffJson,
    );

    let merged = applySpecDiff(spec, diff, {
      allowRemoval: true,
      allowReshape: true,
      allowAdditions: true,
    });

    // Edit IN PLACE — overwrite this same round's file and update the same
    // SculptedModel, rather than spawning a new round each turn. A refine
    // conversation can run many turns, so a new instance per turn would litter
    // the realm with SculptedModel cards and history rounds; editing in place
    // keeps one card per model, matching the lasso "Edit a part" semantics.
    let realm = this.realmOf(codeFileUrl);
    let rel = codeFileUrl.slice(realm.length);
    await new WriteTextFileCommand(this.commandContext).execute({
      path: rel,
      content: generateModelJs(merged, {
        round: creation.round ?? 1,
        score: typeof merged.score === 'number' ? merged.score : null,
      }),
      realm,
      overwrite: true,
    } as any);

    // update this round's own review fields in place (no new instance)
    creation.critique = String(merged.critique ?? `refined: ${instruction}`);
    if (typeof merged.score === 'number') {
      creation.score = merged.score;
    }
    // bump revision so the studio viewport cache-busts and re-fetches the
    // just-overwritten (same-url) .js instead of showing the stale render
    creation.revision = (creation.revision ?? 0) + 1;
    await new SaveCardCommand(this.commandContext).execute({
      card: creation,
      realm,
    } as any);

    return undefined;
  }
}
