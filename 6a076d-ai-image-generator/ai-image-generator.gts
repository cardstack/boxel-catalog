import {
  CardDef,
  field,
  contains,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import AspectRatioField from '@cardstack/catalog/fields/aspect-ratio/aspect-ratio';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import { AiImage, AiImageModelField } from './ai-image';
import {
  AiImageGeneratorIsolated,
  AiImageGeneratorEmbedded,
} from './components/generator';

// ---------------------------------------------------------------------------
// AI Image Generator — a ChatGPT-style image studio. Thin card definition: the
// data model lives here; the isolated/embedded experience is composed from
// components in ./components (the studio orchestrator, version graph, refine
// editor, etc.). Every generated image is its own AI Image card linked into
// `history`, forming a referable version tree.
// ---------------------------------------------------------------------------
export class AiImageGenerator extends CardDef {
  static displayName = 'AI Image Generator';
  static prefersWideFormat = true;
  static icon = SparklesIcon;

  // The generation history — every image is its own AI Image card, in order.
  @field history = linksToMany(() => AiImage);

  // Composer defaults, persisted so the generator remembers its last choices.
  @field llmModel = contains(AiImageModelField);
  @field aspectRatio = contains(AspectRatioField);

  static isolated = AiImageGeneratorIsolated;
  static embedded = AiImageGeneratorEmbedded;
  static fitted = AiImageGeneratorEmbedded;
}
