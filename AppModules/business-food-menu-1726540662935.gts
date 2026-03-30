import { Component, CardDef, FieldDef, linksTo, linksToMany, field, contains, containsMany } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import DateField from 'https://cardstack.com/base/date';
import DateTimeField from 'https://cardstack.com/base/datetime';
import NumberField from 'https://cardstack.com/base/number';
import MarkdownField from 'https://cardstack.com/base/markdown';
import { AppCard } from '../app-card';

export class MenuItemCard extends CardDef {
  static displayName = 'MenuItem';

  @field itemName = contains(StringField);
  @field description = contains(MarkdownField);
  @field price = contains(NumberField);
  @field category = linksTo(() => CategoryCard);
  @field dietaryInfo = contains(StringField); // Assuming dietary information is a string like "vegan, gluten-free"
  @field cuisineType = contains(StringField);
  @field imageUrl = contains(StringField);
}

export class CategoryCard extends CardDef {
  static displayName = 'Category';

  @field categoryName = contains(StringField);
  @field description = contains(MarkdownField);
  @field imageUrl = contains(StringField);
}

export class PromotionCard extends CardDef {
  static displayName = 'Promotion';

  @field promotionName = contains(StringField);
  @field description = contains(MarkdownField);
  @field startDate = contains(DateField);
  @field endDate = contains(DateField);
  @field applicableItems = linksToMany(MenuItemCard);
}

export class BusinessFoodMenuApp extends AppCard {
  static displayName = 'Business Food Menu App';

  @field menuItems = containsMany(MenuItemCard);
  @field categories = containsMany(CategoryCard);
  @field promotions = containsMany(PromotionCard);
}
