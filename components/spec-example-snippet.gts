import { CardDef, field, contains, Component } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import CodeSnippet from './code-snippet';

class SpecExampleSnippetEdit extends Component<typeof SpecExampleSnippet> {
  <template>
    <div class='spec-example-snippet-edit'>
      <CodeSnippet @code={{@model.code}} />
    </div>
  </template>
}

class SpecExampleSnippetEmbedded extends Component<typeof SpecExampleSnippet> {
  <template>
    <CodeSnippet @code={{@model.code}} />
  </template>
}

class SpecExampleSnippetAtom extends Component<typeof SpecExampleSnippet> {
  <template>
    <CodeSnippet @code={{@model.code}} />
  </template>
}

export class SpecExampleSnippet extends CardDef {
  @field code = contains(StringField);

  static displayName = 'Spec Example Snippet';

  static edit = SpecExampleSnippetEdit;
  static embedded = SpecExampleSnippetEmbedded;
  static atom = SpecExampleSnippetAtom;
}

export default SpecExampleSnippet;
