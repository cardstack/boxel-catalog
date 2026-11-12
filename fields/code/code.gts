import GlimmerComponent from '@glimmer/component';
import { Component } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { CodeBlock } from '@cardstack/pretui/components/code-block';
import { CodeEditor } from '@cardstack/pretui/components/code-editor';
import { Token } from '@cardstack/pretui/components/token';
import CodeIcon from '@cardstack/boxel-icons/code';

// Source code as a field value: read in a highlighted, line-numbered block and
// edited in a code editor. Its language comes from the field's configuration,
// `contains(CodeField, { configuration: { language: 'javascript' } })`.
//
// `CodeView` and `CodeEdit` are the field's two faces as plain components, so
// a card that keeps its code somewhere other than a field (a file it links,
// say) shows and edits it the same way.

export type CodeLanguage = 'javascript' | 'typescript' | 'json' | 'plain';

export interface CodeConfiguration {
  language?: CodeLanguage;
}

interface CodeViewSignature {
  Args: {
    code?: string | null;
    language?: CodeLanguage;
    // Shown in the block's header, and the copy button's label.
    filename?: string;
    // The block scrolls past this many lines.
    maxLines?: number;
  };
  Element: HTMLElement;
}

export class CodeView extends GlimmerComponent<CodeViewSignature> {
  <template>
    <CodeBlock
      @code={{if @code @code ''}}
      @language={{@language}}
      @filename={{@filename}}
      @lineNumbers={{true}}
      @maxLines={{if @maxLines @maxLines 24}}
      ...attributes
    />
  </template>
}

interface CodeEditSignature {
  Args: {
    code?: string | null;
    language?: CodeLanguage;
    onInput: (code: string) => void;
    // An id on the editable element, for other elements to point at. A
    // `<label for>` can't name it: use `labelledBy` for that.
    controlId?: string;
    // The ids of the elements that name and describe the editor, such as a
    // `Field`'s span label and message line.
    labelledBy?: string;
    describedBy?: string;
    // The editor's accessible name when no element names it.
    label?: string;
    minLines?: number;
    maxLines?: number;
    readOnly?: boolean;
  };
  Element: HTMLDivElement;
}

export class CodeEdit extends GlimmerComponent<CodeEditSignature> {
  <template>
    <CodeEditor
      @value={{if @code @code ''}}
      @language={{@language}}
      @onInput={{@onInput}}
      @controlId={{@controlId}}
      @labelledBy={{@labelledBy}}
      @describedBy={{@describedBy}}
      @label={{@label}}
      @readOnly={{@readOnly}}
      @minLines={{if @minLines @minLines 8}}
      @maxLines={{if @maxLines @maxLines 32}}
      ...attributes
    />
  </template>
}

export class CodeField extends StringField {
  static displayName = 'Code';
  static icon = CodeIcon;

  static embedded = class Embedded extends Component<typeof CodeField> {
    get language() {
      return (this.args.configuration as CodeConfiguration | undefined)
        ?.language;
    }
    <template>
      <CodeView @code={{@model}} @language={{this.language}} />
    </template>
  };

  static atom = class Atom extends Component<typeof CodeField> {
    <template><Token @value={{if @model @model ''}} /></template>
  };

  static edit = class Edit extends Component<typeof CodeField> {
    get language() {
      return (this.args.configuration as CodeConfiguration | undefined)
        ?.language;
    }
    // The field's label can't name the editor, so the editor carries the
    // field's name itself.
    get label() {
      return typeof this.args.fieldName === 'string'
        ? this.args.fieldName
        : 'Code';
    }
    <template>
      <CodeEdit
        @code={{@model}}
        @language={{this.language}}
        @label={{this.label}}
        @onInput={{@set}}
        @readOnly={{if @canEdit false true}}
      />
    </template>
  };
}

export default CodeField;
