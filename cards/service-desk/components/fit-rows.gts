import type { TemplateOnlyComponent } from '@ember/component/template-only';

interface TypeMarkSignature {
  Args: { label: string; size?: 'sm' };
}
// the record's type mark, not a person: a square, not an Avatar
export const TypeMark: TemplateOnlyComponent<TypeMarkSignature> = <template>
  <span
    class='case-mark'
    data-size={{@size}}
    aria-hidden='true'
  >{{@label}}</span>
  <style scoped>
    @layer PretComponent {
      .case-mark {
        display: inline-grid;
        flex: none;
        place-items: center;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border-radius: var(--radius);
        background: var(--muted);
        color: var(--card-foreground);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      .case-mark[data-size='sm'] {
        inline-size: 1.25rem;
        block-size: 1.25rem;
      }
    }
  </style>
</template>;

export const lowercase = (value?: string | null) => (value ?? '').toLowerCase();
