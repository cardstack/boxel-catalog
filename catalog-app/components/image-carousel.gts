import GlimmerComponent from '@glimmer/component';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { BoxelButton } from '@cardstack/boxel-ui/components';
import { add, eq } from '@cardstack/boxel-ui/helpers';
import { fn } from '@ember/helper';

interface Signature {
  Element: HTMLElement;
  Args: {
    items: string[];
  };
  Blocks: {
    overlay?: [];
    icon: [];
  };
}

export default class ImageCarouselComponent extends GlimmerComponent<Signature> {
  @tracked currentIndex = 0;

  get totalSlides() {
    return this.args.items?.length ?? 0;
  }

  get prevIndex() {
    return this.currentIndex === 0
      ? this.totalSlides - 1
      : this.currentIndex - 1;
  }

  get nextIndex() {
    return this.currentIndex === this.totalSlides - 1
      ? 0
      : this.currentIndex + 1;
  }

  get hasSlide() {
    return this.totalSlides > 0;
  }

  get hasMultipleSlides() {
    return this.totalSlides > 1;
  }

  @action
  updateCurrentIndex(index: number, e: MouseEvent) {
    e.stopPropagation();

    if (index < 0 || index >= this.totalSlides) {
      return;
    }
    this.currentIndex = index;
  }

  <template>
    <div class='image-carousel' ...attributes>
      {{#if (has-block 'overlay')}}
        <div class='carousel-overlay'>
          {{yield to='overlay'}}
        </div>
      {{/if}}

      {{#if this.hasSlide}}
        <div class='carousel-items'>
          {{#each @items as |item index|}}
            <div
              class='carousel-item carousel-item-{{index}}
                {{if (eq this.currentIndex index) "is-active"}}'
              aria-hidden={{if (eq this.currentIndex index) 'false' 'true'}}
            >
              <img
                src={{item}}
                alt='Slide {{add index 1}} of {{this.totalSlides}}'
              />
            </div>
          {{/each}}
        </div>
      {{else if (has-block 'icon')}}
        <div class='carousel-default'>
          {{yield to='icon'}}
        </div>
      {{/if}}

      {{#if this.hasMultipleSlides}}
        <div class='carousel-nav' role='presentation'>
          <BoxelButton
            @kind='text-only'
            @size='auto'
            class='carousel-arrow carousel-arrow-prev'
            aria-label='Previous slide'
            {{on 'click' (fn this.updateCurrentIndex this.prevIndex)}}
          >
            &#10094;
          </BoxelButton>
          <BoxelButton
            @kind='text-only'
            @size='auto'
            class='carousel-arrow carousel-arrow-next'
            aria-label='Next slide'
            {{on 'click' (fn this.updateCurrentIndex this.nextIndex)}}
          >
            &#10095;
          </BoxelButton>
        </div>
      {{/if}}

      {{#if this.hasMultipleSlides}}
        <div class='carousel-dots' role='presentation'>
          {{#each @items as |_ index|}}
            <div
              class='carousel-dot
                {{if (eq this.currentIndex index) "is-active"}}'
              {{on 'click' (fn this.updateCurrentIndex index)}}
              role='button'
              aria-label='Go to slide {{add index 1}}'
            />
          {{/each}}
        </div>
      {{/if}}
    </div>

    <style scoped>
      @layer {
        .image-carousel {
          --boxel-carousel-z-index: 1;
          position: relative;
          width: 100%;
          height: 100%;
          overflow: hidden;
          container-type: inline-size;
        }

        .carousel-overlay {
          position: absolute;
          top: 0;
          left: 0;
          z-index: calc(var(--boxel-carousel-z-index) + 1);
          width: 100%;
          height: 100%;
          pointer-events: none;
        }

        .carousel-default {
          height: 100%;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .carousel-items {
          height: 100%;
          display: flex;
          align-items: center;
          justify-content: center;
          position: relative;
        }

        .carousel-item {
          position: absolute;
          visibility: hidden;
          flex: 0 0 100%;
          justify-content: center;
          align-items: center;
          padding: var(--boxel-sp) var(--boxel-sp-xs);
          display: flex;
          opacity: 0;
          transition:
            opacity 1s ease,
            visibility 0s linear 1s;
        }

        .carousel-item.is-active {
          visibility: visible;
          opacity: 1;
          transition:
            opacity 1s ease,
            visibility 0s;
        }

        .carousel-item img {
          width: 100%;
          height: auto;
          object-fit: cover;
          display: block;
          border-radius: var(--boxel-border-radius-sm);
          box-shadow:
            0 15px 20px
              color-mix(in oklch, var(--shadow-color) 12%, transparent),
            0 5px 10px color-mix(in oklch, var(--shadow-color) 10%, transparent);
        }

        .carousel-arrow {
          all: unset;
          cursor: pointer;
          user-select: none;
          padding: 0px;
          width: 2rem;
          height: 2rem;
          display: inline-flex;
          justify-content: center;
          align-items: center;
          color: var(--boxel-200);
        }

        .carousel-arrow-prev {
          position: absolute;
          left: 0;
          top: 50%;
          transform: translateY(-50%);
          z-index: calc(var(--boxel-carousel-z-index) + 2);
        }

        .carousel-arrow-next {
          position: absolute;
          right: 0;
          top: 50%;
          transform: translateY(-50%);
          z-index: calc(var(--boxel-carousel-z-index) + 2);
        }

        .carousel-dots {
          position: absolute;
          bottom: 0.3125rem;
          left: 50%;
          z-index: calc(var(--boxel-carousel-z-index) + 2);
          transform: translateX(-50%);
          display: flex;
          justify-content: center;
          gap: 0.5rem;
        }

        .carousel-dot {
          width: 0.625rem;
          height: 0.625rem;
          background-color: var(--boxel-100);
          border: 1px solid var(--boxel-500);
          border-radius: 50%;
          cursor: pointer;
          padding: 0px;
        }

        .carousel-dot.is-active {
          background-color: var(--boxel-400);
          border: 1px solid var(--boxel-700);
        }

        .image-carousel:hover .carousel-item img {
          box-shadow:
            0 15px 20px
              color-mix(in oklch, var(--shadow-color) 20%, transparent),
            0 7px 10px color-mix(in oklch, var(--shadow-color) 12%, transparent);
        }

        @container (max-height: 140px) {
          .carousel-nav,
          .carousel-dots {
            display: none;
          }
          .carousel-item {
            padding: var(--boxel-sp-4xs);
          }
          .carousel-item img,
          .image-carousel:hover .carousel-item img {
            box-shadow: none;
            border-radius: var(--boxel-border-radius-xs);
          }
        }
      }
    </style>
  </template>
}
