import type { TemplateOnlyComponent } from '@ember/component/template-only';

export type FilterItem = {
  id: string;
  displayName: string;
  kind?: 'all' | 'sphere' | 'category';
};

// FilterGroupWrapper
interface FilterGroupWrapperArgs {
  Args: {
    title: string;
  };
  Element: HTMLElement;
  Blocks: {
    default: [];
  };
}

const FilterGroupWrapper: TemplateOnlyComponent<FilterGroupWrapperArgs> =
  <template>
    <section
      class='filter-group'
      aria-labelledby='filter-heading-{{@title}}'
      ...attributes
    >
      <h2 class='filter-heading' id='filter-heading-{{@title}}'>{{@title}}</h2>
      {{yield}}
    </section>

    <style scoped>
      @layer {
        .filter-group {
          display: flex;
          flex-direction: column;
          background-color: var(
            --filter-group-background-color,
            var(--boxel-light)
          );
          border-radius: var(--boxel-border-radius);
          padding: var(--boxel-sp-xs);
          gap: var(--boxel-sp-sm);
        }
        .filter-heading {
          font: 500 var(--boxel-font);
          margin: 0;
        }
      }
    </style>
  </template>;

interface FilterSidebarArgs {
  Blocks: {
    categories: [];
    tags: [];
  };
}

const FilterSidebar: TemplateOnlyComponent<FilterSidebarArgs> = <template>
  <div role='complementary' aria-label='Filters' class='filters-container'>
    {{#if (has-block 'categories')}}
      <FilterGroupWrapper @title='Categories' class='filter-category-group'>
        {{yield to='categories'}}
      </FilterGroupWrapper>
    {{/if}}

    {{#if (has-block 'tags')}}
      <FilterGroupWrapper @title='Tags'>
        {{yield to='tags'}}
      </FilterGroupWrapper>
    {{/if}}
  </div>

  <style scoped>
    .filters-container {
      background-color: transparent;
      display: flex;
      flex-direction: column;
      gap: var(--boxel-sp-lg);
      margin-top: var(--boxel-sp);
    }

    .filter-category-group {
      --filter-group-background-color: transparent;
    }
  </style>
</template>;

export default FilterSidebar;
