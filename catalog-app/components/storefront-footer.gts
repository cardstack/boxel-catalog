import GlimmerComponent from '@glimmer/component';

export default class StorefrontFooter extends GlimmerComponent {
  <template>
    <section class='footer' data-test-storefront-footer>
      <div class='footer-inner'>
        <div class='footer-copy'>
          <h3 class='footer-title'>Built something good?
            <span class='accent'>List it.</span></h3>
          <p class='footer-sub'>Share it with the community. Help someone skip
            the rebuild — and see your work live in realms everywhere.</p>
        </div>
      </div>
    </section>

    <style scoped>
      .footer {
        background: #14141a;
        color: #fff;
      }
      .footer-inner {
        max-width: 80rem;
        margin: 0 auto;
        padding: 2.75rem 2rem;
      }
      .footer-title {
        margin: 0;
        font: 700 1.5rem/1.1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        letter-spacing: -0.02em;
      }
      .accent {
        color: var(--accent, #16e098);
      }
      .footer-sub {
        margin: 0.5625rem 0 0;
        max-width: 34rem;
        font: 400 0.875rem/1.5 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: #b7b4ab;
      }
    </style>
  </template>
}
