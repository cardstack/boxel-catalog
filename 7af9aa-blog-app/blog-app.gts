import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import { codeRef } from '@cardstack/runtime-common';
import { type SortOption, sortByCardTitleAsc } from '../components/sort';
import { type LayoutFilter } from '../components/layout';
import { BasicFitted } from '@cardstack/boxel-ui/components';
import CategoriesIcon from '@cardstack/boxel-icons/hierarchy-3';
import BlogPostIcon from '@cardstack/boxel-icons/newspaper';
import BlogAppIcon from '@cardstack/boxel-icons/notebook';
import AuthorIcon from '@cardstack/boxel-icons/square-user';

import { BlogPost } from './blog-post';
import { Game } from './games/game';
import { IsolatedPortal } from './components/isolated-portal';

export { formatDatetime, toISOString } from './blog-defaults';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;

// TODO: BlogApp should extend AppCard
// Using type CardDef instead of AppCard from catalog because of
// the many type issues resulting from the lack types from catalog realm
export class BlogApp extends CardDef {
  @field website = contains(StringField);
  // Manually-pinned posts; if unset, the Site view falls back to the
  // newest-first auto query.
  @field lead = linksTo(() => BlogPost, {
    searchable: ['authors', 'categories'],
  });
  @field featured = linksToMany(() => BlogPost, {
    searchable: ['authors', 'categories'],
  });
  @field games = linksToMany(() => Game, { searchable: true });
  static displayName = 'Blog App';
  static icon = BlogAppIcon;
  static prefersWideFormat = true;
  static headerColor = '#fff500';

  static sortOptionList: SortOption[] = [
    {
      id: 'datePubDesc',
      displayName: 'Date Published',
      sort: [
        {
          on: codeRef(here, './blog-post', 'BlogPost'),
          by: 'publishDate',
          direction: 'desc',
        },
      ],
    },
    {
      id: 'lastUpdatedDesc',
      displayName: 'Last Updated',
      sort: [
        {
          by: 'lastModified',
          direction: 'desc',
        },
      ],
    },
    {
      id: 'cardTitleAsc',
      displayName: 'A-Z',
      sort: sortByCardTitleAsc,
    },
  ];

  static filterList: LayoutFilter[] = [
    {
      displayName: 'Blog Posts',
      icon: BlogPostIcon,
      cardTypeName: 'Blog Post',
      createNewButtonText: 'Post',
      showAdminData: true,
      sortOptions: BlogApp.sortOptionList,
      cardRef: codeRef(here, './blog-post', 'BlogPost'),
    },
    {
      displayName: 'Author Bios',
      icon: AuthorIcon,
      cardTypeName: 'Author',
      createNewButtonText: 'Author',
      cardRef: codeRef(here, './author', 'Author'),
    },
    {
      displayName: 'Categories',
      icon: CategoriesIcon,
      cardTypeName: 'Category',
      createNewButtonText: 'Category',
      cardRef: codeRef(here, './blog-category', 'BlogCategory'),
    },
  ];

  get filters(): LayoutFilter[] {
    if (this.constructor && 'filterList' in this.constructor) {
      return this.constructor.filterList as LayoutFilter[];
    }
    return BlogApp.filterList;
  }

  static isolated = IsolatedPortal;
  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <BasicFitted
        class='fitted-blog'
        @thumbnailURL={{@model.cardThumbnailURL}}
        @iconComponent={{@model.constructor.icon}}
        @primary={{@model.cardTitle}}
        @secondary={{@model.website}}
      />
      <style scoped>
        .fitted-blog :deep(.card-description) {
          display: none;
        }

        @container fitted-card ((2.0 < aspect-ratio) and (400px <= width ) and (height < 115px)) {
          .fitted-blog {
            padding: var(--boxel-sp-xxxs);
            align-items: center;
          }
          .fitted-blog :deep(.thumbnail-section) {
            border: 1px solid var(--boxel-450);
            border-radius: var(--boxel-border-radius-lg);
            width: 40px;
            height: 40px;
            overflow: hidden;
          }
          .fitted-blog :deep(.card-thumbnail) {
            width: 100%;
            height: 100%;
          }
          .fitted-blog :deep(.card-type-icon) {
            width: 20px;
            height: 20px;
          }
          .fitted-blog :deep(.info-section) {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fitted-blog :deep(.card-title) {
            -webkit-line-clamp: 2;
            font: 600 var(--boxel-font-sm);
            letter-spacing: var(--boxel-lsp-xs);
          }
          .fitted-blog :deep(.card-display-name) {
            margin: 0;
            overflow: hidden;
          }
        }
      </style>
    </template>
  };
}
