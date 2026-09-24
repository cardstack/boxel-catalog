import { themeStyleFor } from './blog-defaults';
import MarkdownField from '@cardstack/base/markdown';
import TextAreaField from '@cardstack/base/text-area';
import {
  Component,
  CardDef,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import EmailField from '@cardstack/base/email';

import Email from '@cardstack/boxel-icons/mail';
import Linkedin from '@cardstack/boxel-icons/brand-linkedin';
import XIcon from '@cardstack/boxel-icons/brand-x';
import UserIcon from '@cardstack/boxel-icons/user';
import UserRoundPen from '@cardstack/boxel-icons/user-round-pen';

import { cn, not } from '@cardstack/boxel-ui/helpers';

import { setBackgroundImage } from '../components/layout';
import FeaturedImageField from '../fields/featured-image/featured-image';
import ContactLinkField from '../fields/contact-link/contact-link';

class AuthorContactLink extends ContactLinkField {
  static values = [
    {
      type: 'social',
      label: 'X',
      icon: XIcon,
      cta: 'Follow',
    },
    {
      type: 'social',
      label: 'LinkedIn',
      icon: Linkedin,
      cta: 'Connect',
    },
    {
      type: 'email',
      label: 'Email',
      icon: Email,
      cta: 'Contact',
    },
  ];
}

export class Author extends CardDef {
  static displayName = 'Author';
  static icon = UserRoundPen;
  @field firstName = contains(StringField);
  @field lastName = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Author) {
      let fullName = [this.firstName, this.lastName].filter(Boolean).join(' ');
      return fullName.length ? fullName : 'Untitled Author';
    },
    description: 'Full name of author',
  });
  @field bio = contains(TextAreaField, {
    description: 'Default author bio for embedded and isolated views.',
  });
  @field fullBio = contains(MarkdownField, {
    description: 'Full bio for isolated view',
  });
  @field quote = contains(TextAreaField);
  @field contactLinks = containsMany(AuthorContactLink);
  @field email = contains(EmailField);
  @field featuredImage = contains(FeaturedImageField);

  static isolated = class Isolated extends Component<typeof this> {
    get themeStyle() {
      return themeStyleFor(this);
    }
    <template>
      {{! runtime-built theme CSS (defaults + linked theme) must be
          un-scoped so .blog-scope descendants can read it }}
      {{! template-lint-disable require-scoped-style }}
      <style>
        {{this.themeStyle}}
      </style>
      <article class='author-bio blog-scope'>
        <header class='author-header'>
          {{#if @model.featuredImage.imageUrl}}
            <@fields.featuredImage class='featured-image' />
          {{/if}}
          <div class='title-group'>
            <p class='eyebrow'>Author</p>
            <h1 class='name'><@fields.cardTitle /></h1>
            {{#if @model.cardDescription}}
              <p class='description'><@fields.cardDescription /></p>
            {{/if}}
            {{#if @model.contactLinks.length}}
              <div class='links'>
                <@fields.contactLinks @format='atom' />
              </div>
            {{/if}}
          </div>
        </header>

        {{#if @model.quote}}
          <blockquote class='quote'>
            <p><@fields.quote /></p>
          </blockquote>
        {{/if}}

        {{#if @model.bio}}
          <p class='summary'><@fields.bio /></p>
        {{/if}}
        {{#if @model.fullBio}}
          <div class='full-bio'><@fields.fullBio /></div>
        {{/if}}
      </article>
      <style scoped>
        .author-bio {
          --markdown-font-family: var(
            --blog-font-family,
            'Inter',
            system-ui,
            sans-serif
          );
          --markdown-heading-font-family: var(
            --blog-font-family,
            'Inter',
            system-ui,
            sans-serif
          );
          max-width: 47.5rem;
          margin: 0 auto;
          padding: var(--boxel-sp-xxl) var(--boxel-sp-lg);
          font-family: var(--blog-font-family, 'Inter', system-ui, sans-serif);
          font-size: 1rem;
          color: var(--foreground);
          text-wrap: pretty;
          background-color: var(--card);
        }
        h1,
        h2,
        h3,
        h4,
        h5,
        h6 {
          font-family: var(--blog-font-family, 'Inter', system-ui, sans-serif);
        }

        .author-header {
          display: grid;
          grid-template-columns: max-content 1fr;
          gap: var(--boxel-sp-xl);
          align-items: center;
          padding-bottom: var(--boxel-sp-xl);
          border-bottom: 1px solid var(--border);
        }
        .featured-image :deep(figure) {
          margin: 0;
        }
        .featured-image :deep(figcaption) {
          display: none;
        }
        .featured-image :deep(.image),
        .featured-image :deep(img) {
          width: 10rem;
          height: 10rem;
          border-radius: 50%;
          border: 1px solid var(--border);
          object-fit: cover;
          object-position: center;
          box-shadow: var(
            --blog-shadow-portrait,
            0 4px 14px color-mix(in oklch, var(--foreground) 8%, transparent)
          );
          display: block;
        }
        .title-group {
          min-width: 0;
        }
        .eyebrow {
          margin: 0 0 0.25rem;
          font: var(--blog-font-eyebrow, 700 0.7rem/1 sans-serif);
          letter-spacing: var(--blog-tracking-eyebrow, 0.18em);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .name {
          font: var(--blog-font-display-l, 800 2.6rem/1.05 sans-serif);
          letter-spacing: var(--blog-tracking-tight, -0.02em);
          margin: 0;
          color: var(--foreground);
        }
        .description {
          margin: var(--boxel-sp-xs) 0 0;
          font: 500 1.05rem/1.4
            var(--blog-font-family, 'Inter', system-ui, sans-serif);
          color: var(--muted-foreground);
        }
        .links {
          margin-top: var(--boxel-sp);
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .links :deep(.pill) {
          border: 1px solid var(--border);
          background-color: transparent;
          border-radius: var(--blog-radius-pill, 62.4375rem);
          padding: 0.25rem 0.75rem;
          font: 500 0.78rem
            var(--blog-font-family, 'Inter', system-ui, sans-serif);
          transition:
            background-color 0.15s,
            border-color 0.15s;
        }
        .links :deep(.pill:hover) {
          background-color: color-mix(in oklch, var(--tooltip) 4%, transparent);
          border-color: var(--boxel-500);
        }
        .links :deep(svg) {
          width: 0.875rem;
          height: 0.875rem;
        }

        .quote {
          margin: var(--boxel-sp-xxl) 0;
          padding: 0 var(--boxel-sp-lg);
          border: none;
          text-align: center;
        }
        .quote p {
          margin: 0;
          font: var(--blog-font-pullquote, 600 1.5rem/1.35 sans-serif);
          letter-spacing: var(--blog-tracking-tighter, -0.01em);
          color: var(--foreground);
          max-width: 35rem;
          margin-inline: auto;
        }
        .quote p::before {
          content: '“';
          display: block;
          font: 800 4rem/0.5
            var(--blog-font-family, 'Inter', system-ui, sans-serif);
          color: var(--primary-ink);
          margin-bottom: var(--boxel-sp-sm);
        }

        .summary {
          margin: var(--boxel-sp-xl) 0 0;
          font: var(--blog-font-body, 400 1.0625rem/1.7 sans-serif);
          color: var(--foreground);
        }
        .full-bio {
          margin-top: var(--boxel-sp-xl);
          font: 400 1rem/1.7
            var(--blog-font-family, 'Inter', system-ui, sans-serif);
        }
        .full-bio :deep(p) {
          margin: 0 0 1.25em;
        }
        .full-bio :deep(h2) {
          font: 800 1.5rem/1.2
            var(--blog-font-family, 'Inter', system-ui, sans-serif);
          letter-spacing: var(--blog-tracking-tighter, -0.01em);
          margin: 1.8em 0 0.5em;
        }
        .full-bio :deep(h3) {
          font: 700 1.15rem/1.3
            var(--blog-font-family, 'Inter', system-ui, sans-serif);
          margin: 1.5em 0 0.4em;
        }

        @media (max-width: 600px) {
          .author-header {
            grid-template-columns: 1fr;
            text-align: center;
            justify-items: center;
          }
          .name {
            font-size: 2rem;
          }
          .links {
            justify-content: center;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <article class='author-embedded'>
        <div
          class='thumbnail-image'
          style={{setBackgroundImage @model.cardThumbnailURL}}
          role={{if @model.cardThumbnailURL 'img'}}
          aria-label={{if @model.cardThumbnailURL @model.cardTitle}}
        >
          {{#unless @model.cardThumbnailURL}}
            <UserIcon width='30' height='30' />
          {{/unless}}
        </div>
        <div class='author-body'>
          <header class='author-head'>
            <p class='eyebrow'>Written by</p>
            <h3 class='name'><@fields.cardTitle /></h3>
            {{#if @model.cardDescription}}
              <p class='role'><@fields.cardDescription /></p>
            {{/if}}
          </header>
          {{#if @model.bio}}
            <p class='bio'><@fields.bio /></p>
          {{/if}}
          {{#if @model.contactLinks.length}}
            <div class='author-bio-links'>
              <@fields.contactLinks @format='embedded' />
            </div>
          {{/if}}
        </div>
      </article>
      <style scoped>
        .author-embedded {
          height: 100%;
          display: grid;
          grid-template-columns: max-content 1fr;
          align-items: start;
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp-xl) 0;
          background-color: transparent;
          font-family: var(--blog-font-family, 'Inter', system-ui, sans-serif);
          text-wrap: pretty;
          color: var(--foreground);
        }
        .thumbnail-image {
          width: 5.75rem;
          height: 5.75rem;
          display: flex;
          align-items: center;
          justify-content: center;
          background-position: center;
          background-size: cover;
          background-repeat: no-repeat;
          border-radius: 50%;
          border: 1px solid var(--border);
          color: var(--subtle-foreground);
          box-shadow: var(
            --blog-shadow-card,
            0 1px 3px color-mix(in oklch, var(--foreground) 6%, transparent)
          );
        }
        .author-body {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .author-head {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }
        h3,
        p {
          margin: 0;
        }
        .eyebrow {
          font: var(--blog-font-eyebrow, 700 0.7rem/1 sans-serif);
          letter-spacing: var(--blog-tracking-eyebrow, 0.18em);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .name {
          font: var(--blog-font-name, 800 1.5rem/1.15 sans-serif);
          letter-spacing: var(--blog-tracking-tighter, -0.01em);
          color: var(--foreground);
        }
        .role {
          font: 500 0.9rem/1.4
            var(--blog-font-family, 'Inter', system-ui, sans-serif);
          color: var(--muted-foreground);
        }
        .bio {
          font: var(--blog-font-body-sm, 400 0.95rem/1.6 sans-serif);
          color: var(--foreground);
          max-width: 56ch;
        }
        .author-bio-links {
          margin-top: var(--boxel-sp-xxs);
        }
        .author-bio-links > :deep(.embedded-format) {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .author-bio-links :deep(.pill) {
          --pill-background-color: transparent;
          border: 1px solid var(--border);
          border-radius: var(--blog-radius-pill, 62.4375rem);
          padding: 0.25rem 0.75rem;
          font: 500 0.78rem
            var(--blog-font-family, 'Inter', system-ui, sans-serif);
          color: var(--foreground);
          transition:
            background-color 0.15s,
            border-color 0.15s;
        }
        .author-bio-links :deep(.pill:hover) {
          background-color: color-mix(in oklch, var(--tooltip) 4%, transparent);
          border-color: var(--boxel-500);
        }
        .author-bio-links :deep(svg) {
          width: 0.875rem;
          height: 0.875rem;
        }

        @media (max-width: 560px) {
          .author-embedded {
            grid-template-columns: 1fr;
            text-align: center;
            justify-items: center;
          }
          .bio {
            max-width: none;
          }
          .author-bio-links > :deep(.embedded-format) {
            justify-content: center;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='author-atom'>
        {{#if @model.cardThumbnailURL}}
          <span
            class='author-thumbnail'
            style={{setBackgroundImage @model.cardThumbnailURL}}
            role='img'
            aria-label={{@model.cardTitle}}
          />
        {{else}}
          <UserIcon class='author-icon' width='20' height='20' />
        {{/if}}
        <span class='author-title'>
          <@fields.cardTitle />
        </span>
      </span>
      <style scoped>
        .author-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-xxs);
          font: 600 var(--boxel-font-sm);
          letter-spacing: var(--boxel-lsp-xs);
        }
        .author-thumbnail,
        .author-icon {
          flex-shrink: 0;
        }
        .author-thumbnail {
          width: 1.5rem;
          height: 1.5rem;
          border-radius: 50%;
          border: 1px solid var(--boxel-400);
          overflow: hidden;
          background-position: center;
          background-repeat: no-repeat;
          background-size: cover;
        }
        .author-title {
          text-wrap: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class FittedTemplate extends Component<typeof this> {
    <template>
      <article class='author-fitted'>
        <div
          class={{cn 'author-thumbnail' is-icon=(not @model.cardThumbnailURL)}}
          style={{setBackgroundImage @model.cardThumbnailURL}}
          role={{if @model.cardThumbnailURL 'img'}}
          aria-label={{if @model.cardThumbnailURL @model.cardTitle}}
        >
          {{#unless @model.cardThumbnailURL}}
            <UserIcon width='24' height='24' />
          {{/unless}}
        </div>
        <header class='title-group'>
          <h3 class='title'><@fields.cardTitle /></h3>
          <p class='description'><@fields.cardDescription /></p>
        </header>
        <p class='bio'><@fields.bio /></p>
        <div class='links'><@fields.contactLinks @format='atom' /></div>
      </article>
      <style scoped>
        .author-fitted {
          --link-icon-size: var(--author-link-icon-size, 0.9375rem);
          --thumbnail-size: var(--author-thumbnail-size, 3.75rem);
          --gap-size: var(--boxel-sp-xxs);
          width: 100%;
          height: 100%;
          min-width: 6.25rem;
          min-height: 1.8125rem;
          gap: var(--gap-size);
          overflow: hidden;
          padding: var(--boxel-sp-xs);
        }
        .author-thumbnail {
          grid-area: img;
          width: var(--thumbnail-size);
          height: var(--thumbnail-size);
          display: flex;
          align-items: center;
          justify-content: center;
          background-position: center;
          background-size: cover;
          background-repeat: no-repeat;
          border-radius: 50%;
          border: 1px solid var(--boxel-400);
          color: var(--boxel-400);
        }
        .title-group {
          grid-area: header;
          overflow: hidden;
        }
        .title {
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
          margin: 0;
          font: 600 var(--boxel-font);
          letter-spacing: var(--boxel-lsp-sm);
          line-height: 1.25;
        }
        .description {
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
          margin-top: var(--boxel-sp-4xs);
          margin-bottom: 0;
          font: 500 var(--boxel-font-xs);
          letter-spacing: var(--boxel-lsp-sm);
          line-height: 1.25;
        }
        .bio {
          grid-area: bio;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 3;
          overflow: hidden;
          margin: 0;
          font: var(--boxel-font-xs);
          letter-spacing: var(--boxel-lsp-sm);
          line-height: 1.25;
        }
        .links {
          display: flex;
          gap: var(--boxel-sp-xxxs);
          flex-wrap: wrap;
        }
        .links :deep(div) {
          display: contents;
        }
        .links :deep(.pill) {
          border: none;
        }
        .links :deep(svg) {
          width: var(--link-icon-size);
          height: var(--link-icon-size);
        }

        @container fitted-card ((aspect-ratio <= 1.0) and (226px <= height)) {
          .author-fitted {
            display: grid;
            grid-template:
              'img' max-content
              'header' max-content
              'bio' max-content
              'links' 1fr / 1fr;
          }
          .links {
            align-self: end;
          }
        }

        /* Aspect ratio < 1.0 (Vertical card) */
        @container fitted-card (aspect-ratio <= 1.0) and (224px <= height < 226px) {
          .author-fitted {
            display: grid;
            grid-template:
              'img' max-content
              'header' max-content
              'links' 1fr / 1fr;
          }
          .bio {
            display: none;
          }
          .links {
            align-self: end;
          }
        }

        @container fitted-card (aspect-ratio <= 1.0) and (180px <= height < 224px) {
          .author-fitted {
            --thumbnail-size: 2.5rem;
            display: grid;
            grid-template:
              'img' max-content
              'header' max-content
              'links' 1fr / 1fr;
          }
          .title {
            font-size: var(--boxel-font-size-sm);
          }
          .bio {
            display: none;
          }
          .links {
            align-self: end;
          }
        }

        @container fitted-card (aspect-ratio <= 1.0) and (148px <= height < 180px) {
          .author-fitted {
            --thumbnail-size: 2.5rem;
            display: grid;
            grid-template:
              'img' max-content
              'header' max-content
              'links' 1fr / 1fr;
          }
          .title {
            font-size: var(--boxel-font-size-sm);
          }
          .description,
          .bio {
            display: none;
          }
          .links {
            align-self: end;
          }
        }

        @container fitted-card (aspect-ratio <= 1.0) and (128px <= height < 148px) {
          .author-fitted {
            --thumbnail-size: 2.5rem;
            display: grid;
            grid-template:
              'img' max-content
              'header' max-content
              'links' 1fr / 1fr;
          }
          .title {
            font-size: var(--boxel-font-size-xs);
          }
          .description,
          .bio {
            display: none;
          }
          .links {
            align-self: end;
          }
        }

        @container fitted-card (aspect-ratio <= 1.0) and (118px <= height < 128px) {
          .author-fitted {
            --thumbnail-size: 2.5rem;
            --link-icon-size: 0.8125rem;
            --gap-size: var(--boxel-sp-4xs);
            display: grid;
            grid-template:
              'img' max-content
              'header' 1fr
              'links' max-content / 1fr;
          }
          .title {
            font-size: var(--boxel-font-size-xs);
          }
          .description,
          .bio {
            display: none;
          }
        }

        @container fitted-card (aspect-ratio <= 1.0) and (92px <= height < 118px) {
          .author-fitted {
            --thumbnail-size: 2.5rem;
            --link-icon-size: 0.8125rem;
            --gap-size: var(--boxel-sp-4xs);
            display: grid;
            grid-template:
              'img' max-content
              'header' 1fr
              'links' max-content / 1fr;
          }
          .title {
            font-size: var(--boxel-font-size-xs);
          }
          .description,
          .bio {
            display: none;
          }
        }

        @container fitted-card (aspect-ratio <= 1.0) and (height < 92px) {
          .author-fitted {
            --thumbnail-size: 1.25rem;
            --gap-size: var(--boxel-sp-4xs);
            display: grid;
            grid-template:
              'img' max-content
              'header' 1fr / 1fr;
          }
          .title {
            font-size: var(--boxel-font-size-xs);
          }
          .description,
          .bio,
          .links {
            display: none;
          }
        }

        @container fitted-card ((aspect-ratio <= 1.0) and (400px <= height)) {
          .author-fitted {
            --gap-size: var(--boxel-sp-xs);
            display: grid;
            grid-template:
              'img' max-content
              'header' max-content
              'bio' max-content
              'links' 1fr / 1fr;
          }
          .title {
            -webkit-line-clamp: 4;
            font-size: var(--boxel-font-size-sm);
          }
          .bio {
            -webkit-line-clamp: 10;
          }
          .links {
            align-self: end;
          }
        }

        /* 1.0 < Aspect ratio (Horizontal card) */
        @container fitted-card ((1.0 < aspect-ratio) and (151px <= height)) {
          .author-fitted {
            --gap-size: var(--boxel-sp-xxs) var(--boxel-sp-sm);
            display: grid;
            grid-template:
              'img header' minmax(var(--thumbnail-size), max-content)
              'img links' 1fr / max-content 1fr;
          }
          .title-group {
            align-self: center;
          }
          .title {
            font-size: var(--boxel-font-size-sm);
          }
          .description {
            -webkit-line-clamp: 4;
          }
          .bio {
            display: none;
          }
          .links {
            align-self: end;
          }
        }

        @container fitted-card ((1.0 < aspect-ratio) and (115px <= height <= 150px)) {
          .author-fitted {
            --gap-size: var(--boxel-sp-xxs) var(--boxel-sp-sm);
            --thumbnail-size: 3.125rem;
            display: grid;
            grid-template:
              'img header' minmax(var(--thumbnail-size), max-content)
              'img links' 1fr / max-content 1fr;
          }
          .title-group {
            align-self: center;
          }
          .title {
            font-size: var(--boxel-font-size-sm);
          }
          .bio {
            display: none;
          }
          .links {
            align-self: end;
          }
        }

        @container fitted-card ((1.0 < aspect-ratio) and (78px <= height <= 114px)) {
          .author-fitted {
            --gap-size: var(--boxel-sp-xxxs) var(--boxel-sp-xs);
            --thumbnail-size: 1.25rem;
            --link-icon-size: 0.9375rem;
            display: grid;
            grid-template:
              'img header' minmax(var(--thumbnail-size), max-content)
              'img links' 1fr / max-content 1fr;
          }
          .title-group {
            align-self: center;
          }
          .title {
            font-size: var(--boxel-font-size-sm);
          }
          .bio,
          .description {
            display: none;
          }
          .links {
            align-self: end;
          }
        }

        @container fitted-card ((1.0 < aspect-ratio) and (500px <= width) and (56px <= height <= 77px)) {
          .author-fitted {
            --gap-size: var(--boxel-sp-xs);
            --thumbnail-size: 2.125rem;
            display: grid;
            grid-template: 'img header' 1fr / max-content 1fr;
            padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
            align-items: center;
          }
          .title {
            font: 600 var(--boxel-font-sm);
          }
          .bio,
          .links {
            display: none;
          }
        }

        @container fitted-card ((1.0 < aspect-ratio) and (width <= 499px) and (height <= 77px)) {
          .author-fitted {
            --gap-size: var(--boxel-sp-xxs);
            --thumbnail-size: 2.5rem;
            display: grid;
            grid-template: 'img header' 1fr / max-content 1fr;
            align-items: center;
            padding: var(--boxel-sp-xxxs);
          }
          .title {
            font-size: var(--boxel-font-size-sm);
          }
          .bio,
          .description,
          .links {
            display: none;
          }
        }

        @container fitted-card ((1.0 < aspect-ratio) and (height <= 55px)) {
          .author-fitted {
            --gap-size: var(--boxel-sp-xs);
            --thumbnail-size: 1.25rem;
            display: grid;
            grid-template: 'img header' 1fr / max-content 1fr;
            align-items: center;
            padding: var(--boxel-sp-xxxs);
          }
          .author-thumbnail.is-icon {
            border: none;
          }
          .title-group {
            overflow: hidden;
          }
          .title {
            display: block;
            white-space: nowrap;
            text-overflow: ellipsis;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.1;
          }
          .description {
            display: block;
            white-space: nowrap;
            text-overflow: ellipsis;
          }
          .bio,
          .links {
            display: none;
          }
        }

        @container fitted-card ((1.0 < aspect-ratio) and (width <= 100px) and (height <= 55px)) {
          .author-fitted {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: var(--boxel-sp-xxxs);
          }
          .author-thumbnail,
          .description,
          .bio,
          .links {
            display: none;
          }
          .title-group {
            overflow: hidden;
          }
          .title {
            display: block;
            white-space: nowrap;
            text-overflow: ellipsis;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.1;
          }
        }
      </style>
    </template>
  };
}
