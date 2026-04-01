import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import MarkdownField from 'https://cardstack.com/base/markdown';
import { Component } from 'https://cardstack.com/base/card-api';

export class Recipe extends CardDef {
  static displayName = 'Recipe';

  @field title = contains(StringField);
  @field servings = contains(NumberField);
  @field ingredients = contains(MarkdownField);
  @field instructions = contains(MarkdownField);

  get name() {
    return this.title;
  }

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='recipe'>
        <h1>{{@model.title}}</h1>
        <p><strong>Servings:</strong> {{@model.servings}}</p>
        <h2>Ingredients</h2>
        <@fields.ingredients />
        <h2>Instructions</h2>
        <@fields.instructions />
      </div>
      <style scoped>
        .recipe {
          max-width: 600px;
          margin: 0 auto;
          padding: 1rem;
          font-family: sans-serif;
        }
        h1 {
          font-size: 1.8rem;
          margin-bottom: 0.5rem;
        }
        h2 {
          font-size: 1.2rem;
          margin-top: 1.5rem;
          border-bottom: 1px solid #ddd;
          padding-bottom: 0.25rem;
        }
      </style>
    </template>
  };
}
