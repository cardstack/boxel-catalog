// Pretui — Skeleton: a placeholder shape shown while content loads.
import Component from '@glimmer/component';
import { cssDeclaration, cssStyleFrom } from '../pretui-css';

export interface SkeletonSignature {
  Args: { width?: string; height?: string };
  Element: HTMLSpanElement;
}

export class Skeleton extends Component<SkeletonSignature> {
  get style() {
    return cssStyleFrom([
      cssDeclaration('--_w', this.args.width ?? '100%'),
      cssDeclaration('--_h', this.args.height ?? '0.75rem'),
    ]);
  }
  <template>
    <span
      class='pretui-skeleton'
      style={{this.style}}
      aria-hidden='true'
      data-test-pretui-skeleton
      ...attributes
    ></span>
    <style scoped>
      @layer PretComponent {
        @keyframes pretui-shimmer {
          from {
            background-position: 200% 0;
          }
          to {
            background-position: -200% 0;
          }
        }
        .pretui-skeleton {
          display: block;
          width: var(--_w, 100%);
          height: var(--_h, 0.75rem);
          border-radius: var(--boxel-border-radius-sm);
          background: linear-gradient(
            90deg,
            var(--inset) 40%,
            var(--hover) 50%,
            var(--inset) 60%
          );
          background-size: 200% 100%;
          animation: pretui-shimmer 1.6s linear infinite;
        }
        @media (prefers-reduced-motion: reduce) {
          .pretui-skeleton {
            animation: none;
          }
        }
      }
    </style>
  </template>
}
