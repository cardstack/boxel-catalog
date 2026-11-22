import { CardDef, Component } from '@cardstack/base/card-api';
import { isLiveRender } from '@cardstack/base/render-context';
import FolderIcon from '@cardstack/boxel-icons/folder';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { BuildPromptCommand } from './build-prompt-command';
import type { BuildPromptResult } from './build-prompt-result';
import { MarkdownOutlineCommand } from './markdown-outline-command';
import type { MarkdownOutlineResult } from './markdown-outline-result';
import { CleanTextCommand } from './clean-text-command';
import type { CleanTextResult } from './clean-text-result';
import { UTMBuilderCommand } from './utm-builder-command';
import type { UTMBuilderResult } from './utm-builder-result';
import { AspectRatioCommand } from './aspect-ratio-command';
import type { AspectRatioResult } from './aspect-ratio-result';
import { QRGeneratorCommand } from './qr-generator-command';
import type { QRGeneratorResult } from './qr-generator-result';
import { RegexTesterCommand } from './regex-tester-command';
import type { RegexTesterResult } from './regex-tester-result';
import { CsvCleanerCommand } from './csv-cleaner-command';
import type { CsvCleanerResult } from './csv-cleaner-result';
import { CurlConverterCommand } from './curl-converter-command';
import type { CurlConverterResult } from './curl-converter-result';
import UseAiAssistantCommand from '@cardstack/boxel-host/tools/ai-assistant';
import { McpSkillConnector } from './mcp-skill-connector';
import { QrCode } from '@cardstack/pretui/components/qr-code';
import { Button } from '@cardstack/pretui/components/button';
import '@cardstack/pretui/components/chip';
import { CopyButton } from '@cardstack/pretui/components/copy-button';
import { Field } from '@cardstack/pretui/components/field';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { Textarea } from '@cardstack/pretui/components/textarea';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';

const tools = [
  {
    id: 'prompt-builder',
    title: 'Prompt Builder',
    category: 'Vibe coding',
    kind: 'Works in Boxel',
    summary:
      'Turn a rough app idea into a clear, reusable prompt for your coding agent.',
    icon: 'P',
  },
  {
    id: 'markdown-outline',
    title: 'Markdown Outline',
    category: 'Everyday tools',
    kind: 'Works in Boxel',
    summary: 'Extract a clean, nested outline from Markdown headings.',
    icon: 'M',
  },
  {
    id: 'text-cleaner',
    title: 'Text Cleaner',
    category: 'Everyday tools',
    kind: 'Works in Boxel',
    summary:
      'Normalize line endings, remove trailing spaces, and tidy excess blank lines.',
    icon: 'T',
  },
  {
    id: 'utm-builder',
    title: 'UTM Campaign Builder',
    category: 'Everyday tools',
    kind: 'Works in Boxel',
    summary:
      'Build a tagged campaign URL without losing existing query parameters.',
    icon: 'U',
  },
  {
    id: 'aspect-ratio',
    title: 'Aspect Ratio Calculator',
    category: 'Everyday tools',
    kind: 'Works in Boxel',
    summary:
      'Calculate a simplified ratio and fit dimensions inside a target box without cropping.',
    icon: 'A',
  },
  {
    id: 'qr-generator',
    title: 'QR Code Generator',
    category: 'Everyday tools',
    kind: 'Works in Boxel',
    summary: 'Turn a URL or short text into a scannable QR code.',
    icon: 'Q',
  },
  {
    id: 'regex-tester',
    title: 'Regex Tester',
    category: 'Vibe coding',
    kind: 'Works in Boxel',
    summary:
      'Test a regular expression against sample text and inspect matches.',
    icon: 'R',
  },
  {
    id: 'csv-cleaner',
    title: 'CSV Cleaner',
    category: 'Everyday tools',
    kind: 'Works in Boxel',
    summary:
      'Normalize CSV text and stop safely if a record has a different number of columns than the header.',
    icon: 'C',
  },
  {
    id: 'curl-converter',
    title: 'cURL to Fetch',
    category: 'Vibe coding',
    kind: 'Works in Boxel',
    summary:
      'Convert common cURL requests into Fetch code, preserving query data and rejecting options it cannot represent.',
    icon: '↗',
  },
];
const types = ['All tools', 'Everyday tools', 'Vibe coding', 'Skills'];
const skills = [
  {
    id: 'anti-slop-ui-review',
    title: 'Anti-Slop UI Review',
    description:
      'Review a Boxel UI for generic, unsupported, inaccessible, or incoherent choices.',
    icon: 'A',
  },
  {
    id: 'boxel-motion-design',
    title: 'Boxel Motion Design',
    description:
      'Plan purposeful motion and interaction feedback for Boxel cards.',
    icon: 'M',
  },
  {
    id: 'design-from-reference',
    title: 'Design from Reference',
    description:
      'Turn supplied visual references into a clear Boxel design direction.',
    icon: 'D',
  },
  {
    id: 'github-skill-portability',
    title: 'GitHub Skill Portability',
    description:
      'Assess whether a GitHub agent skill can be safely adapted for Boxel.',
    icon: 'G',
  },
  {
    id: 'modern-web-guidance-boxel',
    title: 'Modern Web Guidance',
    description:
      'Apply accessibility, responsive, privacy, and performance practices in Boxel.',
    icon: 'W',
  },
  {
    id: 'wedding-planner-visual-direction',
    title: 'Wedding Planner Visual Direction',
    description:
      'Apply the agreed visual direction to the wedding-planning project.',
    icon: 'V',
  },
];

class MakewayHomeView extends Component<typeof MakewayHome> {
  @tracked query = '';
  @tracked selectedType = 'All tools';
  @tracked activeTool = '';
  @tracked goal = '';
  @tracked audience = '';
  @tracked mustHave = '';
  @tracked feel = '';
  @tracked source = '';
  @tracked utmUrl = '';
  @tracked utmSource = '';
  @tracked utmMedium = '';
  @tracked utmCampaign = '';
  @tracked utmTerm = '';
  @tracked utmContent = '';
  @tracked width = '';
  @tracked height = '';
  @tracked targetWidth = '';
  @tracked targetHeight = '';
  @tracked qrValue = '';
  @tracked pattern = '';
  @tracked flags = 'g';
  @tracked sample = '';
  @tracked result = '';
  @tracked error = '';
  @tracked skillError = '';
  @tracked busy = false;
  get live() {
    return isLiveRender();
  }
  get visibleTools() {
    const query = this.query.trim().toLowerCase();
    return tools.filter(
      (item) =>
        (this.selectedType === 'All tools' ||
          item.category === this.selectedType) &&
        (!query ||
          (item.title + ' ' + item.summary + ' ' + item.category)
            .toLowerCase()
            .includes(query)),
    );
  }
  get featuredTool() {
    return this.visibleTools.find((item) => item.id === 'prompt-builder');
  }
  get libraryTools() {
    return this.visibleTools.filter((item) => item.id !== 'prompt-builder');
  }
  get currentTool() {
    return tools.find((item) => item.id === this.activeTool);
  }
  get isSkillsView() {
    return this.selectedType === 'Skills';
  }
  get visibleSkills() {
    const query = this.query.trim().toLowerCase();
    return skills.filter(
      (skill) =>
        !query ||
        (skill.title + ' ' + skill.description).toLowerCase().includes(query),
    );
  }
  isType = (value: string) => this.selectedType === value;
  setType = (value: string) => {
    this.selectedType = value;
  };
  setQuery = (value: string) => {
    this.query = value;
  };
  setGoal = (value: string) => {
    this.goal = value;
  };
  setAudience = (value: string) => {
    this.audience = value;
  };
  setMustHave = (value: string) => {
    this.mustHave = value;
  };
  setFeel = (value: string) => {
    this.feel = value;
  };
  setSource = (value: string) => {
    this.source = value;
  };
  setUrl = (value: string) => {
    this.utmUrl = value;
  };
  setUtmSource = (value: string) => {
    this.utmSource = value;
  };
  setUtmMedium = (value: string) => {
    this.utmMedium = value;
  };
  setUtmCampaign = (value: string) => {
    this.utmCampaign = value;
  };
  setUtmTerm = (value: string) => {
    this.utmTerm = value;
  };
  setUtmContent = (value: string) => {
    this.utmContent = value;
  };
  setWidth = (value: string) => {
    this.width = value;
  };
  setHeight = (value: string) => {
    this.height = value;
  };
  setTargetWidth = (value: string) => {
    this.targetWidth = value;
  };
  setTargetHeight = (value: string) => {
    this.targetHeight = value;
  };
  setQrValue = (value: string) => {
    this.qrValue = value;
  };
  setPattern = (value: string) => {
    this.pattern = value;
  };
  setFlags = (value: string) => {
    this.flags = value;
  };
  setSample = (value: string) => {
    this.sample = value;
  };
  openSkill = async (id: string) => {
    this.skillError = '';
    const context = this.args.context?.toolContext;
    if (!context) {
      this.skillError = 'Open Makeway in Boxel interact mode to use a Skill.';
      return;
    }
    try {
      // @ts-expect-error import.meta is supported by the Boxel host
      const skillCardId = new URL(
        './skills/' + id + '/SKILL.md',
        import.meta.url,
      ).href;
      await new UseAiAssistantCommand(context).execute({
        skillCardIds: [skillCardId],
        attachedCards: [this.args.model],
        llmMode: 'ask',
        openRoom: true,
      });
    } catch (reason) {
      this.skillError =
        reason instanceof Error ? reason.message : String(reason);
    }
  };
  openTool = (id: string) => {
    this.activeTool = id;
    this.result = '';
    this.error = '';
  };
  closeTool = () => {
    this.activeTool = '';
    this.error = '';
  };
  goHome = () => {
    this.activeTool = '';
    this.selectedType = 'All tools';
    this.query = '';
    this.error = '';
    this.skillError = '';
  };
  runTool = async () => {
    this.error = '';
    this.result = '';
    const context = this.args.context?.toolContext;
    if (!context) {
      this.error = 'Open Makeway in Boxel interact mode to run this tool.';
      return;
    }
    this.busy = true;
    try {
      if (this.activeTool === 'prompt-builder') {
        const output = (await new BuildPromptCommand(context).execute({
          goal: this.goal,
          audience: this.audience,
          mustHave: this.mustHave,
          feel: this.feel,
        })) as BuildPromptResult;
        this.result = output.output;
      } else if (this.activeTool === 'markdown-outline') {
        const output = (await new MarkdownOutlineCommand(context).execute({
          source: this.source,
        })) as MarkdownOutlineResult;
        this.result = output.output;
      } else if (this.activeTool === 'text-cleaner') {
        const output = (await new CleanTextCommand(context).execute({
          source: this.source,
        })) as CleanTextResult;
        this.result = output.output;
      } else if (this.activeTool === 'utm-builder') {
        const output = (await new UTMBuilderCommand(context).execute({
          url: this.utmUrl,
          source: this.utmSource,
          medium: this.utmMedium,
          campaign: this.utmCampaign,
          term: this.utmTerm,
          content: this.utmContent,
        })) as UTMBuilderResult;
        this.result = output.output;
      } else if (this.activeTool === 'aspect-ratio') {
        const output = (await new AspectRatioCommand(context).execute({
          width: this.width,
          height: this.height,
          targetWidth: this.targetWidth,
          targetHeight: this.targetHeight,
        })) as AspectRatioResult;
        this.result = output.output;
      } else if (this.activeTool === 'qr-generator') {
        const output = (await new QRGeneratorCommand(context).execute({
          value: this.qrValue,
        })) as QRGeneratorResult;
        this.result = output.output;
      } else if (this.activeTool === 'regex-tester') {
        const output = (await new RegexTesterCommand(context).execute({
          pattern: this.pattern,
          flags: this.flags,
          sample: this.sample,
        })) as RegexTesterResult;
        this.result = output.output;
      } else if (this.activeTool === 'csv-cleaner') {
        const output = (await new CsvCleanerCommand(context).execute({
          source: this.source,
        })) as CsvCleanerResult;
        this.result = output.output;
      } else if (this.activeTool === 'curl-converter') {
        const output = (await new CurlConverterCommand(context).execute({
          command: this.source,
        })) as CurlConverterResult;
        this.result = output.output;
      }
    } catch (reason) {
      this.error = reason instanceof Error ? reason.message : String(reason);
    } finally {
      this.busy = false;
    }
  };
  <template>
    <main class='mw' data-live={{if this.live 'true' 'false'}}>
      <header class='mw-header'><a
          class='mw-brand'
          href='#library'
          aria-label='Makeway library'
        ><span class='mw-mark'>m.</span><span>makeway</span></a><nav
          class='mw-nav'
          aria-label='Makeway navigation'
        ><a href='#library'>Browse tools</a></nav><span class='mw-header-note'>A
          workspace for useful tools.</span></header>
      <section class='mw-hero'>
        <div class='mw-hero-copy'>
          <p class='mw-kicker'>A SMALL, PRACTICAL TOOL LIBRARY</p>
          <h1>A useful tool<br />for your next move.</h1>
          <p class='mw-dek'>Find a focused Boxel Command for the task in front
            of you—then run it without leaving your workspace.</p>
          <Field
            @label='Search the tool shelf'
            @hint='Search by name or task'
            as |controlId|
          >
            <SearchInput
              @controlId={{controlId}}
              @value={{this.query}}
              @placeholder='What are you trying to do?'
              @onInput={{this.setQuery}}
            />
          </Field>
        </div>
        {{#if this.featuredTool}}
          <aside class='mw-feature' aria-label='A place to start'>
            <div class='mw-feature-top'><span class='mw-kicker'>A PLACE TO START</span><span
                class='mw-feature-number'
              >01</span></div>
            <div class='mw-feature-body'>
              <div class='mw-feature-mark' aria-hidden='true'>P.</div>
              <div class='mw-feature-copy'>
                <span class='mw-feature-category'>{{this.featuredTool.category}}
                  · Boxel Command</span>
                <h2>{{this.featuredTool.title}}</h2>
                <p>{{this.featuredTool.summary}}</p>
              </div>
            </div>
            <Button
              @size='s'
              @tone='primary'
              @appearance='filled'
              {{on 'click' (fn this.openTool this.featuredTool.id)}}
            >Try Prompt Builder <span aria-hidden='true'>↗</span></Button>
          </aside>
        {{/if}}
      </section>
      <section class='mw-library' id='library' aria-label='Tool library'>
        <div class='mw-library-head'>
          <div><p class='mw-kicker'>THE TOOL SHELF</p><h2>Tools you can use now.</h2></div>
          <span class='mw-count'>{{this.visibleTools.length}} available</span>
        </div>
        <div
          class='mw-type-tabs'
          role='group'
          aria-label='Filter tools by type'
        >
          {{#each types key='@identity' as |type|}}
            <Button
              @size='s'
              @tone='neutral'
              @appearance={{if (this.isType type) 'filled' 'plain'}}
              aria-pressed={{if (this.isType type) 'true' 'false'}}
              {{on 'click' (fn this.setType type)}}
            >{{type}}</Button>
          {{/each}}
        </div>
        {{#if this.isSkillsView}}
          <McpSkillConnector />
          <div class='mw-tool-grid' aria-label='Skills'>
            {{#each this.visibleSkills key='id' as |skill|}}
              <article class='mw-tool-card'>
                <div class='mw-tool-card-top'><span
                    class='mw-tool-category'
                  >Skill</span><span
                    class='mw-tool-mark'
                    aria-hidden='true'
                  >{{skill.icon}}</span></div>
                <h3>{{skill.title}}</h3>
                <p class='mw-tool-description'>{{skill.description}}</p>
                <div class='mw-tool-card-footer'><span
                    class='mw-tool-meta'
                  >BOXEL SKILL</span><Button
                    @size='s'
                    @tone='primary'
                    @appearance='outlined'
                    {{on 'click' (fn this.openSkill skill.id)}}
                  >Use skill <span aria-hidden='true'>↗</span></Button></div>
              </article>
            {{else}}
              <p>No skills match this search.</p>
            {{/each}}
          </div>
          {{#if this.skillError}}<p
              class='mw-error'
              role='alert'
            >{{this.skillError}}</p>{{/if}}
        {{else}}
          {{#if this.featuredTool}}
            <div class='mw-start-note'><span>FIRST STEP</span><p>Turn a rough
                idea into a clear prompt for your coding agent.</p></div>
          {{/if}}
          <div class='mw-tool-grid' aria-label='Available tools'>
            {{#each this.libraryTools key='id' as |item|}}
              <article class='mw-tool-card'>
                <div class='mw-tool-card-top'><span
                    class='mw-tool-category'
                  >{{item.category}}</span><span
                    class='mw-tool-mark'
                    aria-hidden='true'
                  >{{item.icon}}</span></div>
                <h3>{{item.title}}</h3>
                <p class='mw-tool-description'>{{item.summary}}</p>
                <div class='mw-tool-card-footer'><span
                    class='mw-tool-meta'
                  >BOXEL COMMAND</span><Button
                    @size='s'
                    @tone='primary'
                    @appearance='outlined'
                    {{on 'click' (fn this.openTool item.id)}}
                  >Use now <span aria-hidden='true'>↗</span></Button></div>
              </article>
            {{else}}
              <div class='mw-empty-state'><span
                  class='mw-empty-mark'
                  aria-hidden='true'
                >⌕</span><h3>No tools found.</h3><p>Try another search or choose
                  a different type.</p></div>
            {{/each}}
          </div>
        {{/if}}
      </section>
      <footer class='mw-footer'><span>MAKEWAY</span><span>Find the tool. Make it
          happen.</span></footer>
      {{#if this.activeTool}}<section
          class='mw-tool-screen'
          aria-label={{this.currentTool.title}}
        ><div class='mw-tool-toolbar'><Button
              @size='s'
              @tone='neutral'
              @appearance='plain'
              {{on 'click' this.closeTool}}
            >← Tool list</Button><Button
              @size='s'
              @tone='neutral'
              @appearance='outlined'
              {{on 'click' this.goHome}}
            >⌂ Home</Button><span>{{this.currentTool.category}}
              /
              {{this.currentTool.title}}</span></div><div
            class='mw-tool-layout'
          ><section class='mw-tool-form'><p class='mw-kicker'>BOXEL COMMAND /
                READY TO USE</p><h1>{{this.currentTool.title}}</h1><p
                class='mw-tool-intro'
              >{{this.currentTool.summary}}</p>{{#if
                (eq this.activeTool 'prompt-builder')
              }}
                <Field
                  @label='What do you want to build?'
                  @hint='One or two sentences is enough.'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.goal}}
                    @placeholder='A simple app that helps me…'
                    @onInput={{this.setGoal}}
                  /></Field>
                <Field
                  @label='Who is it for?'
                  @hint='Optional'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.audience}}
                    @placeholder='My team, customers, or myself…'
                    @onInput={{this.setAudience}}
                  /></Field>
                <Field
                  @label='What must it include?'
                  @hint='Optional'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.mustHave}}
                    @placeholder='The few things it needs to do…'
                    @onInput={{this.setMustHave}}
                  /></Field>
                <Field
                  @label='How should it feel?'
                  @hint='Optional'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.feel}}
                    @placeholder='Calm, playful, minimal…'
                    @onInput={{this.setFeel}}
                  /></Field>
              {{else if (eq this.activeTool 'utm-builder')}}
                <Field
                  @label='Destination URL'
                  @hint='Use a complete http or https URL.'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.utmUrl}}
                    @placeholder='https://example.com/page'
                    @onInput={{this.setUrl}}
                  /></Field>
                <div class='mw-form-pair'><Field
                    @label='Source'
                    @hint='Required'
                    as |id|
                  ><Textarea
                      @controlId={{id}}
                      @value={{this.utmSource}}
                      @placeholder='newsletter'
                      @onInput={{this.setUtmSource}}
                    /></Field><Field
                    @label='Medium'
                    @hint='Required'
                    as |id|
                  ><Textarea
                      @controlId={{id}}
                      @value={{this.utmMedium}}
                      @placeholder='email'
                      @onInput={{this.setUtmMedium}}
                    /></Field></div>
                <Field @label='Campaign' @hint='Required' as |id|><Textarea
                    @controlId={{id}}
                    @value={{this.utmCampaign}}
                    @placeholder='spring-launch'
                    @onInput={{this.setUtmCampaign}}
                  /></Field>
                <div class='mw-form-pair'><Field
                    @label='Term'
                    @hint='Optional'
                    as |id|
                  ><Textarea
                      @controlId={{id}}
                      @value={{this.utmTerm}}
                      @placeholder='keyword'
                      @onInput={{this.setUtmTerm}}
                    /></Field><Field
                    @label='Content'
                    @hint='Optional'
                    as |id|
                  ><Textarea
                      @controlId={{id}}
                      @value={{this.utmContent}}
                      @placeholder='button-variant'
                      @onInput={{this.setUtmContent}}
                    /></Field></div>
              {{else if (eq this.activeTool 'aspect-ratio')}}
                <div class='mw-form-pair'><Field
                    @label='Width'
                    @hint='Original dimensions'
                    as |id|
                  ><Textarea
                      @controlId={{id}}
                      @value={{this.width}}
                      @placeholder='1920'
                      @onInput={{this.setWidth}}
                    /></Field><Field
                    @label='Height'
                    @hint='Original dimensions'
                    as |id|
                  ><Textarea
                      @controlId={{id}}
                      @value={{this.height}}
                      @placeholder='1080'
                      @onInput={{this.setHeight}}
                    /></Field></div>
                <div class='mw-form-pair'><Field
                    @label='Fit within width'
                    @hint='Optional'
                    as |id|
                  ><Textarea
                      @controlId={{id}}
                      @value={{this.targetWidth}}
                      @placeholder='1200'
                      @onInput={{this.setTargetWidth}}
                    /></Field><Field
                    @label='Fit within height'
                    @hint='Optional'
                    as |id|
                  ><Textarea
                      @controlId={{id}}
                      @value={{this.targetHeight}}
                      @placeholder='800'
                      @onInput={{this.setTargetHeight}}
                    /></Field></div>
              {{else if (eq this.activeTool 'qr-generator')}}
                <Field
                  @label='URL or short text to encode'
                  @hint='The result includes a scannable QR code and its encoded value.'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.qrValue}}
                    @placeholder='https://example.com'
                    @onInput={{this.setQrValue}}
                  /></Field>
              {{else if (eq this.activeTool 'regex-tester')}}
                <Field
                  @label='Regular expression'
                  @hint='Enter the pattern without slash delimiters.'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.pattern}}
                    @placeholder='[A-Z]+'
                    @onInput={{this.setPattern}}
                  /></Field>
                <Field
                  @label='Flags'
                  @hint='Optional flags such as i or m.'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.flags}}
                    @placeholder='gi'
                    @onInput={{this.setFlags}}
                  /></Field>
                <Field
                  @label='Sample text'
                  @hint='Matches include character positions.'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.sample}}
                    @placeholder='Paste sample text…'
                    @onInput={{this.setSample}}
                  /></Field>
              {{else if (eq this.activeTool 'curl-converter')}}
                <Field
                  @label='Paste a cURL command'
                  @hint='Supported: URL, method, headers, --data flags, -G, HEAD, redirects, compression, and --fail. Unsupported options are rejected.'
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.source}}
                    @placeholder='curl -G -d q=boxel https://example.com/search'
                    @onInput={{this.setSource}}
                  /></Field>
              {{else}}
                <Field
                  @label={{if
                    (eq this.activeTool 'csv-cleaner')
                    'Paste CSV'
                    (if
                      (eq this.activeTool 'markdown-outline')
                      'Paste Markdown'
                      'Paste text'
                    )
                  }}
                  @hint={{if
                    (eq this.activeTool 'csv-cleaner')
                    'Every record must match the header column count; mismatches are rejected, not dropped.'
                    'This tool runs locally through a Boxel Command.'
                  }}
                  as |id|
                ><Textarea
                    @controlId={{id}}
                    @value={{this.source}}
                    @placeholder={{if
                      (eq this.activeTool 'csv-cleaner')
                      'name,email\nAda,ada@example.com'
                      'Paste your text here…'
                    }}
                    @onInput={{this.setSource}}
                  /></Field>
              {{/if}}
              {{#if this.error}}<p
                  class='mw-error'
                  role='alert'
                >{{this.error}}</p>{{/if}}<Button
                @tone='primary'
                @appearance='accent'
                @busy={{this.busy}}
                @busyLabel='Running tool'
                {{on 'click' this.runTool}}
              >Run tool</Button></section><aside
              class='mw-output'
              aria-label='Tool result'
            ><div class='mw-output-head'><div><p class='mw-kicker'>YOUR RESULT</p><h2
                  >Ready to use</h2></div>{{#if this.result}}<CopyButton
                    @text={{this.result}}
                    @label='Copy result'
                  />{{/if}}</div>{{#if (eq this.activeTool 'qr-generator')}}
                {{#if this.result}}<QrCode
                    @value={{this.result}}
                    @label='Generated QR code'
                    @size={{220}}
                  />{{else}}<div class='mw-output-empty'><span>↳</span><p>Your
                      QR code will appear here.</p><small>Run the Command to
                      generate it.</small></div>{{/if}}
              {{else if this.result}}<pre>{{this.result}}</pre>
              {{else}}<div class='mw-output-empty'><span>↳</span><p>Your result
                    will appear here.</p><small>Run the Command to create it.</small></div>{{/if}}</aside></div></section>{{/if}}
    </main>
    <style scoped>
      .mw {
        --mw-line: var(--border);
        container-type: inline-size;
        container-name: makeway;
        height: 100%;
        overflow-y: auto;
      }
      .mw-header {
        display: flex;
        align-items: center;
        gap: 2rem;
        min-height: 4.25rem;
        padding: 0 clamp(1.25rem, 4vw, 4rem);
        border-bottom: 1px solid var(--mw-line);
      }
      .mw-brand {
        display: flex;
        align-items: center;
        gap: 0.65rem;
        color: var(--foreground);
        text-decoration: none;
        font-family: var(--font-serif);
        font-size: 1.25rem;
        font-weight: 650;
        letter-spacing: -0.04em;
      }
      .mw-mark {
        display: grid;
        place-items: center;
        width: 1.8rem;
        height: 1.8rem;
        border-radius: 0.6rem;
        background: var(--primary);
        color: var(--primary-foreground);
        font-size: 1rem;
      }
      .mw-nav {
        display: flex;
        gap: 1.35rem;
        font-size: 0.78rem;
      }
      .mw-nav a {
        color: var(--muted-foreground);
        text-decoration: none;
      }
      .mw-nav a:hover {
        color: var(--foreground);
      }
      .mw-nav a:focus-visible,
      .mw-brand:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 4px;
      }
      .mw-header-note {
        margin-inline-start: auto;
        font-size: 0.72rem;
        color: var(--muted-foreground);
      }
      .mw-hero {
        display: grid;
        grid-template-columns: minmax(0, 1.2fr) minmax(17rem, 0.8fr);
        gap: clamp(2rem, 6vw, 6rem);
        align-items: center;
        padding: clamp(2.5rem, 6vw, 5.5rem) clamp(1.25rem, 8vw, 8rem);
        border-bottom: 1px solid var(--mw-line);
      }
      .mw-kicker,
      .mw-agent-label {
        margin: 0;
        font-family: var(--font-mono);
        font-size: 0.68rem;
        font-weight: 650;
        letter-spacing: 0.13em;
        color: var(--muted-foreground);
      }
      .mw-hero h1,
      .mw-tool-form h1 {
        margin-top: 1.05rem;
        font-family: var(--font-serif);
        font-size: clamp(3.1rem, 6.5vw, 5.7rem);
        font-weight: 400;
        line-height: 0.96;
        letter-spacing: -0.05em;
      }
      .mw-dek {
        max-width: 39rem;
        margin-top: 1rem;
        font-size: 1rem;
        line-height: 1.55;
        color: var(--muted-foreground);
      }
      .mw-hero .pretui-fieldw {
        max-width: 42rem;
        margin-top: 1.6rem;
      }
      .mw-feature {
        display: grid;
        gap: 1.4rem;
        align-self: stretch;
        align-content: center;
        padding: clamp(1.25rem, 2.5vw, 2rem);
        border: 1px solid var(--mw-line);
        background: var(--muted);
        color: var(--foreground);
      }
      .mw-feature-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
      }
      .mw-feature-number {
        font-family: var(--font-mono);
        font-size: 0.78rem;
        color: var(--primary-ink);
      }
      .mw-feature-body {
        display: grid;
        grid-template-columns: 3.2rem minmax(0, 1fr);
        align-items: start;
        gap: 1rem;
      }
      .mw-feature-mark {
        font-family: var(--font-serif);
        font-size: 2rem;
        line-height: 1;
        color: var(--primary-ink);
      }
      .mw-feature-category {
        font-family: var(--font-mono);
        font-size: 0.65rem;
        letter-spacing: 0.04em;
        color: var(--muted-foreground);
      }
      .mw-feature h2 {
        margin-top: 0.4rem;
        font-family: var(--font-serif);
        font-size: 1.8rem;
        font-weight: 400;
        letter-spacing: -0.025em;
      }
      .mw-feature-copy p {
        max-width: 36ch;
        margin-top: 0.4rem;
        font-size: 0.82rem;
        line-height: 1.5;
        color: var(--muted-foreground);
      }
      .mw-feature > .pretui-btn {
        justify-self: start;
      }
      .mw-library {
        padding: 2.5rem clamp(1.25rem, 8vw, 8rem) 3rem;
      }
      .mw-library-head {
        display: flex;
        align-items: end;
        justify-content: space-between;
        gap: 1rem;
      }
      .mw-library-head h2 {
        margin-top: 0.45rem;
        font-family: var(--font-serif);
        font-size: 2.15rem;
        font-weight: 400;
        letter-spacing: -0.035em;
      }
      .mw-count {
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .mw-type-tabs {
        display: flex;
        flex-wrap: wrap;
        gap: 0.3rem;
        padding: 0.85rem 0;
        border-bottom: 1px solid var(--mw-line);
      }
      .mw-start-note {
        display: flex;
        align-items: baseline;
        gap: 1rem;
        padding: 1rem 0 0.5rem;
      }
      .mw-start-note span {
        flex: 0 0 auto;
        font-family: var(--font-mono);
        font-size: 0.65rem;
        font-weight: 650;
        letter-spacing: 0.1em;
        color: var(--primary-ink);
      }
      .mw-start-note p {
        font-size: 0.82rem;
        color: var(--muted-foreground);
      }
      .mw-tool-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 1rem;
        padding-top: 1rem;
      }
      .mw-tool-card {
        display: flex;
        min-width: 0;
        flex-direction: column;
        gap: 0.8rem;
        padding: 1.15rem;
        border: 1px solid var(--mw-line);
        background: var(--card);
        transition:
          background-color 160ms ease,
          border-color 160ms ease;
      }
      .mw-tool-card:hover {
        background: var(--hover);
        border-color: var(--border-strong);
      }
      .mw-tool-card-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
      }
      .mw-tool-category {
        font-family: var(--font-mono);
        font-size: 0.65rem;
        letter-spacing: 0.05em;
        color: var(--muted-foreground);
      }
      .mw-tool-mark {
        display: grid;
        flex: 0 0 auto;
        place-items: center;
        width: 2rem;
        height: 2rem;
        border: 1px solid var(--mw-line);
        border-radius: var(--radius);
        font-family: var(--font-serif);
        font-size: 1.05rem;
        color: var(--primary-ink);
      }
      .mw-tool-card h3 {
        font-size: 1rem;
        font-weight: 650;
        line-height: 1.25;
      }
      .mw-tool-description {
        flex: 1;
        max-width: 44ch;
        font-size: 0.8rem;
        line-height: 1.5;
        color: var(--muted-foreground);
      }
      .mw-tool-card-footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
        padding-top: 0.65rem;
        border-top: 1px solid var(--mw-line);
      }
      .mw-tool-meta {
        font-family: var(--font-mono);
        font-size: 0.62rem;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .mw-tool-status {
        margin-bottom: 0.35rem;
      }
      .mw-empty-state {
        display: grid;
        justify-items: start;
        gap: 0.55rem;
        padding: 2.5rem 0;
      }
      .mw-empty-mark {
        font-family: var(--font-serif);
        font-size: 1.7rem;
        color: var(--primary-ink);
      }
      .mw-empty-state h3 {
        font-family: var(--font-serif);
        font-size: 1.35rem;
        font-weight: 400;
      }
      .mw-empty-state p {
        max-width: 42ch;
        font-size: 0.8rem;
        line-height: 1.5;
        color: var(--muted-foreground);
      }
      .mw-curation-note {
        display: grid;
        grid-template-columns: minmax(9rem, 0.35fr) minmax(0, 1fr);
        gap: 1rem;
        margin-top: 2.2rem;
        padding-top: 1rem;
        border-top: 1px solid var(--mw-line);
      }
      .mw-curation-note p {
        max-width: 65ch;
        font-size: 0.76rem;
        line-height: 1.5;
        color: var(--muted-foreground);
      }
      .mw-footer {
        display: flex;
        justify-content: space-between;
        padding: 0.9rem clamp(1.25rem, 8vw, 8rem);
        border-top: 1px solid var(--mw-line);
        font-family: var(--font-mono);
        font-size: 0.62rem;
        letter-spacing: 0.08em;
        color: var(--muted-foreground);
      }
      .mw-tool-screen {
        position: fixed;
        inset: 0;
        z-index: 20;
        overflow: auto;
        background: var(--background);
        animation: mw-screen-in 260ms ease both;
      }
      .mw-tool-toolbar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0.75rem clamp(1rem, 5vw, 4rem);
        border-bottom: 1px solid var(--mw-line);
        font-family: var(--font-mono);
        font-size: 0.62rem;
        letter-spacing: 0.1em;
        color: var(--muted-foreground);
      }
      .mw-tool-layout {
        display: grid;
        grid-template-columns: minmax(0, 1.1fr) minmax(18rem, 0.9fr);
        gap: clamp(2rem, 7vw, 7rem);
        max-width: 76rem;
        margin: 0 auto;
        padding: clamp(2rem, 6vw, 5rem) clamp(1rem, 5vw, 4rem);
      }
      .mw-tool-form h1 {
        font-size: clamp(2.8rem, 5.5vw, 5rem);
      }
      .mw-tool-intro {
        max-width: 38rem;
        margin: 1rem 0 1.7rem;
        font-size: 0.87rem;
        line-height: 1.55;
        color: var(--muted-foreground);
      }
      .mw-form-pair {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 1rem;
      }
      @media (max-width: 560px) {
        .mw-form-pair {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      .mw-tool-form .pretui-fieldw {
        margin-top: 1rem;
      }
      .mw-tool-form > .pretui-btn {
        margin-top: 1.2rem;
      }
      .mw-error {
        margin-top: 0.75rem;
        color: var(--destructive-ink);
        font-size: 0.78rem;
      }
      .mw-output {
        position: sticky;
        top: 1rem;
        align-self: start;
        min-height: 20rem;
        padding: 1.2rem;
        border: 1px solid var(--mw-line);
        border-radius: var(--radius);
        background: var(--card);
      }
      .mw-output-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
        padding-bottom: 0.8rem;
        border-bottom: 1px solid var(--mw-line);
      }
      .mw-output-head h2 {
        margin-top: 0.35rem;
        font-family: var(--font-serif);
        font-size: 1.55rem;
        font-weight: 400;
      }
      .mw-output pre {
        max-height: 38rem;
        overflow: auto;
        margin: 1rem 0 0;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
        font-family: var(--font-mono);
        font-size: 0.72rem;
        line-height: 1.6;
      }
      .mw-output-empty {
        display: grid;
        gap: 0.65rem;
        margin-top: 2rem;
        color: var(--muted-foreground);
      }
      .mw-output-empty span {
        font-family: var(--font-serif);
        font-size: 1.7rem;
        color: var(--primary-ink);
      }
      .mw-output-empty p {
        font-family: var(--font-serif);
        font-size: 1.25rem;
        color: var(--foreground);
      }
      .mw-output-empty small {
        font-size: 0.72rem;
      }
      @container makeway (width < 850px) {
        .mw-hero {
          grid-template-columns: minmax(0, 1fr);
          gap: 2rem;
        }
        .mw-feature {
          min-height: 16rem;
        }
        .mw-tool-layout {
          grid-template-columns: minmax(0, 1fr);
        }
        .mw-output {
          position: static;
        }
      }
      @container makeway (width < 560px) {
        .mw-header {
          gap: 1rem;
          padding-inline: 1rem;
        }
        .mw-nav {
          display: none;
        }
        .mw-header-note {
          max-width: 9rem;
          text-align: end;
          font-size: 0.66rem;
        }
        .mw-hero {
          padding: 2.4rem 1rem 1.7rem;
        }
        .mw-hero h1 {
          font-size: clamp(2.7rem, 12cqi, 3.8rem);
        }
        .mw-library {
          padding-inline: 1rem;
        }
        .mw-library-head {
          align-items: start;
        }
        .mw-library-head h2 {
          font-size: 1.8rem;
        }
        .mw-count {
          text-align: end;
        }
        .mw-tool-grid {
          grid-template-columns: minmax(0, 1fr);
          gap: 0.7rem;
        }
        .mw-tool-card {
          padding: 1rem;
        }
        .mw-feature {
          gap: 1.1rem;
          padding: 1rem;
        }
        .mw-feature-body {
          grid-template-columns: 2.3rem minmax(0, 1fr);
          gap: 0.75rem;
        }
        .mw-feature-mark {
          font-size: 1.7rem;
        }
        .mw-start-note {
          align-items: start;
          gap: 0.7rem;
        }
        .mw-curation-note {
          grid-template-columns: minmax(0, 1fr);
          gap: 0.4rem;
        }
        .mw-footer {
          gap: 1rem;
          padding-inline: 1rem;
        }
        .mw-footer span:last-child {
          text-align: end;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .mw-tool-screen {
          animation: none;
        }
      }
    </style>
  </template>
}

export class MakewayHome extends CardDef {
  static displayName = 'Makeway';
  static icon = FolderIcon;
  static prefersWideFormat = true;
  static isolated = MakewayHomeView;
  static embedded = class Embedded extends Component<typeof MakewayHome> {
    <template>
      <div class='mw-embedded'><strong><@fields.cardTitle /></strong><span>Find
          the tool. Make it happen.</span></div><style scoped>
        .mw-embedded {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 0.8rem;
          padding: 0.5rem 0;
        }
        .mw-embedded strong {
          font-family: var(--font-serif);
          font-size: 1.15rem;
          font-weight: 600;
        }
        .mw-embedded span {
          font-size: 0.76rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
  static fitted = class Fitted extends Component<typeof MakewayHome> {
    <template>
      <FittedCard><:eyebrow>TOOL LIBRARY</:eyebrow><:title><@fields.cardTitle
          /></:title><:subtitle>Find the tool. Make it happen.</:subtitle></FittedCard>
    </template>
  };
}
