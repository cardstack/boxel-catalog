import { Command } from '@cardstack/runtime-common';

import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import UrlField from 'https://cardstack.com/base/url';

import SearchGoogleImagesCommand from '@cardstack/boxel-host/commands/search-google-images';

import {
  isValidImageUrl,
  fetchHtml,
  extractImageCandidates,
  deriveSearchQuery,
  findLogoImageUrl,
  findWikipediaImageUrl,
} from './image-utils';

export class FindImageInput extends CardDef {
  @field sourceUrl = contains(UrlField, {
    description:
      'Optional candidate image URL or page to scrape. Verified before it is accepted.',
  });
  @field fallbackSearchText = contains(StringField, {
    description:
      'Optional text (e.g. an entity name) to search for an image when sourceUrl is missing or fails. At least one of sourceUrl/fallbackSearchText is required.',
  });
  @field preferLogo = contains(BooleanField, {
    description:
      'When true, look up a canonical brand/tech logo (devicon, Simple Icons) by fallbackSearchText first, and bias web searches toward logos.',
  });
}

export class FindImageResult extends CardDef {
  @field imageUrl = contains(StringField, {
    description:
      'A validated, directly-loadable image URL. Empty when none was found.',
  });
  @field found = contains(BooleanField, {
    description: 'Whether a usable image URL was found.',
  });
  @field recovered = contains(BooleanField, {
    description:
      'True when the result came from a fallback (scrape/search) rather than a directly-valid sourceUrl.',
  });
  @field source = contains(StringField, {
    description:
      "How the image was found: 'direct' | 'scrape' | 'wikipedia' | 'google' | 'none'.",
  });
}

// Pure resolution: turn a (possibly fake) URL and/or a search text into a
// directly-loadable image URL. Writes nothing. Does NOT throw when nothing is
// found — returns found=false so batch callers can skip cleanly.
export default class FindImageCommand extends Command<
  typeof FindImageInput,
  typeof FindImageResult
> {
  static actionVerb = 'Find';
  static displayName = 'Find Image';
  description =
    'Resolve a directly-loadable image URL from a (possibly fake) URL and/or a search text — verifying the URL, scraping the page, then Wikipedia and image search. Returns a URL only; persists nothing.';

  async getInputType() {
    return FindImageInput;
  }

  protected async run(input: FindImageInput): Promise<FindImageResult> {
    let sourceUrl = input.sourceUrl?.trim();
    let fallbackSearchText = input.fallbackSearchText?.trim();
    if (!sourceUrl && !fallbackSearchText) {
      throw new Error('Provide a sourceUrl and/or fallbackSearchText');
    }

    let found = await this.resolve(
      sourceUrl,
      fallbackSearchText,
      input.preferLogo ?? false,
    );
    return new FindImageResult(
      found
        ? {
            imageUrl: found.url,
            found: true,
            recovered: found.recovered,
            source: found.source,
          }
        : { imageUrl: '', found: false, recovered: false, source: 'none' },
    );
  }

  private async resolve(
    sourceUrl: string | undefined,
    fallbackSearchText: string | undefined,
    preferLogo: boolean,
  ): Promise<{ url: string; recovered: boolean; source: string } | undefined> {
    let html: string | undefined;

    // A canonical logo CDN match beats a possibly-wrong direct/searched image,
    // so try it first when requested.
    if (preferLogo && fallbackSearchText) {
      let logoUrl = await findLogoImageUrl(fallbackSearchText);
      if (logoUrl) {
        return { url: logoUrl, recovered: Boolean(sourceUrl), source: 'logo' };
      }
    }

    if (sourceUrl) {
      if (await isValidImageUrl(sourceUrl)) {
        return { url: sourceUrl, recovered: false, source: 'direct' };
      }
      html = await fetchHtml(sourceUrl);
      if (html) {
        for (let candidate of extractImageCandidates(html, sourceUrl)) {
          if (await isValidImageUrl(candidate)) {
            return { url: candidate, recovered: true, source: 'scrape' };
          }
        }
      }
    }

    let query =
      fallbackSearchText || (sourceUrl && deriveSearchQuery(sourceUrl, html));
    if (query) {
      // Wikipedia resolves the entity's article (whose lead image is usually the
      // logo) — keep the raw query. Google does better with an explicit "logo".
      let wikiUrl = await findWikipediaImageUrl(query);
      if (wikiUrl) {
        return { url: wikiUrl, recovered: true, source: 'wikipedia' };
      }
      let googleUrl = await this.findGoogleImageUrl(
        preferLogo ? `${query} logo` : query,
      );
      if (googleUrl) {
        return { url: googleUrl, recovered: true, source: 'google' };
      }
    }

    return undefined;
  }

  // Google image search rides the realm proxy, which needs a `proxy_endpoints`
  // row for googleapis customsearch. Absent/misconfigured → treat as unavailable.
  private async findGoogleImageUrl(query: string): Promise<string | undefined> {
    let images: Array<{ imageUrl?: string }> = [];
    try {
      let result = await new SearchGoogleImagesCommand(
        this.commandContext,
      ).execute({ query, maxResults: 5 });
      images = result.images ?? [];
    } catch {
      images = [];
    }
    for (let image of images) {
      if (image.imageUrl && (await isValidImageUrl(image.imageUrl))) {
        return image.imageUrl;
      }
    }
    return undefined;
  }
}
