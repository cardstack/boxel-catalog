// UI Showcase: every migrated ui-component in a few representative states, under
// a ThemeFrame, so switching theme or dark mode shows how each one re-resolves.
import { tracked } from '@glimmer/tracking';
import { get } from '@ember/helper';
import {
  CardDef,
  Component,
  contains,
  field,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { on } from '@ember/modifier';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { ThemeFrame } from './components/theme-frame';
import { CATEGORY_OPTIONS, DASHBOARD_COMPONENTS } from './showcase-categories';
import { DASHBOARD_USAGE } from './dashboard-usage';
import { Alert } from './components/alert';
import { Avatar } from './components/avatar';
import { Button } from './components/button';
import { Checkbox } from './components/checkbox';
import { Chip } from './components/chip';
import { IconButton } from './components/icon-button';
import { Input } from './components/input';
import { Kbd } from './components/kbd';
import { ProgressBar } from './components/progress-bar';
import { RadioGroup } from './components/radio-group';
import { SegmentedControl } from './components/segmented-control';
import { Skeleton } from './components/skeleton';
import { Spinner } from './components/spinner';
import { Stat } from './components/stat';
import { StatusChip } from './components/status-chip';
import { Switch } from './components/switch';
import { Tabs } from './components/tabs';
import { Textarea } from './components/textarea';
import { AmountInput } from './components/amount-input';
import { Breadcrumb } from './components/breadcrumb';
import { BrokenLink } from './components/broken-link';
import { ButtonGroup } from './components/button-group';
import { Calendar } from './components/calendar';
import { Collapsible } from './components/collapsible';
import { Combobox } from './components/combobox';
import { CopyButton } from './components/copy-button';
import { Cue } from './components/cue';
import { DataTable } from './components/data-table';
import { DatePicker } from './components/date-picker';
import { DateRangePicker } from './components/date-range-picker';
import { Delta } from './components/delta';
import { Descriptions } from './components/descriptions';
import { EmptyState } from './components/empty-state';
import { Field } from './components/field';
import { FileTrigger } from './components/file-trigger';
import { FilterChips } from './components/filter-chips';
import { FormatDate } from './components/format-date';
import { FormatNumber } from './components/format-number';
import { FormattedValue } from './components/formatted-value';
import { KeyValue } from './components/key-value';
import { LoadingState } from './components/loading-state';
import { MoneyInput } from './components/money-input';
import { NativeSelect } from './components/native-select';
import { NumberInput } from './components/number-input';
import { Odometer } from './components/odometer';
import { Pagination } from './components/pagination';
import { Panel } from './components/panel';
import { Popover } from './components/popover';
import { Rating } from './components/rating';
import { RelativeTime } from './components/relative-time';
import { SearchInput } from './components/search-input';
import { Select } from './components/select';
import { StepList } from './components/step-list';
import { Table } from './components/table';
import { Timeline } from './components/timeline';
import { Token } from './components/token';
import { Tooltip } from './components/tooltip';
import { ActionBar } from './components/action-bar';
import { AspectRatio } from './components/aspect-ratio';
import { Badge } from './components/badge';
import { Divider } from './components/divider';
import { Fieldset } from './components/fieldset';
import { Label } from './components/label';
import { Meter } from './components/meter';
import { Notification } from './components/notification';
import { PropertyRow } from './components/property-row';
import { Result } from './components/result';
import { Slider } from './components/slider';
import { Sparkline } from './components/sparkline';
import { Stepper } from './components/stepper';
import { Toast } from './components/toast';
import { Toolbar } from './components/toolbar';
import { BottomNav } from './components/bottom-nav';
import { Tree } from './components/tree';
import { Toggle } from './components/toggle';
import { ToggleGroup } from './components/toggle-group';
import { AvatarGroup } from './components/avatar-group';
import { Indicator } from './components/indicator';
import { ProgressRadial } from './components/progress-radial';
import { RecordPill } from './components/record-pill';
import { DataGrid } from './components/data-grid';
import { Feed } from './components/feed';
import { Masonry } from './components/masonry';
import { Grid } from './components/grid';
import { Card } from './components/card';
import { PanelSection } from './components/panel-section';
import { Fold } from './components/fold';
import { Stack } from './components/stack';
import { StackDivider } from './components/stack-divider';
import { ResultCard } from './components/result-card';
import { WorkItem } from './components/work-item';
import { LoadingOverlay } from './components/loading-overlay';
import { AlertDialog } from './components/alert-dialog';
import { ApprovalFooter } from './components/approval-footer';
import { SkipLink } from './components/skip-link';
import { Menubar } from './components/menubar';
import { NavigationMenu } from './components/navigation-menu';
import { TableOfContents } from './components/table-of-contents';
import { Onboarding } from './components/onboarding';
import { Tour } from './components/tour';
import { MultiSelect } from './components/multi-select';
import { Autocomplete } from './components/autocomplete';
import { Cascader } from './components/cascader';
import { EmailInput } from './components/email-input';
import { UrlInput } from './components/url-input';
import { PhoneInput } from './components/phone-input';
import { OtpInput } from './components/otp-input';
import { RangeSlider } from './components/range-slider';
import { TimeInput } from './components/time-input';
import { EditInPlace } from './components/edit-in-place';
import { Editable } from './components/editable';
import { InteractiveInput } from './components/interactive-input';
import { Accordion } from './components/accordion';
import { BarList } from './components/bar-list';
import { Board } from './components/board';
import { Callout } from './components/callout';
import { CheckboxCard } from './components/checkbox-card';
import { RadioCard } from './components/radio-card';
import { CommandPalette } from './components/command-palette';
import { Dialog } from './components/dialog';
import { Drawer } from './components/drawer';
import { Menu } from './components/menu';
import { Popup } from './components/popup';
import { Sidebar, SidebarItem } from './components/sidebar';
import { Toaster, ToastStore } from './components/toaster';
import { Wizard } from './components/wizard';
import { List } from './components/list';
import { Item } from './components/item';
import { ReadinessPanel } from './components/readiness-panel';
import { RecordFace } from './components/record-face';
import {
  SlidingHighlight,
  slidingHighlight,
} from './components/sliding-highlight';
import { EntityDisplay } from './components/entity-display';
import { VisuallyHidden } from './components/visually-hidden';
import { RecordDetail } from './components/record-detail';
import { RuleRow } from './components/rule-row';
import { FormatBytes } from './components/format-bytes';
import { ContextMenu } from './components/context-menu';
import { DynamicIsland } from './components/dynamic-island';
import { FloatButton } from './components/float-button';
import { Scroller } from './components/scroller';
import { ScrollProgress } from './components/scroll-progress';
import { InView } from './components/in-view';
import { Presence } from './components/presence';
import { AgentQuestion } from './components/agent-question';
import { CollapsedTurn } from './components/collapsed-turn';
import { JumpChip } from './components/jump-chip';
import { ContactLink } from './components/contact-link';
import { CopyFit } from './components/copy-fit';
import { CtaBand } from './components/cta-band';
import { Marquee } from './components/marquee';
import { PathText } from './components/path-text';
import { Composer } from './components/composer';
import { DuelingPicklist } from './components/dueling-picklist';
import { KnownDate } from './components/known-date';
import { Lookup } from './components/lookup';
import { LineGrid } from './components/line-grid';
import { AiInstructions } from './components/ai-instructions';
import { CodeBlock } from './components/code-block';
import { DiffBlock } from './components/diff-block';
import { FeatureVoting } from './components/feature-voting';
import { Filmstrip } from './components/filmstrip';
import { GraphOutline } from './components/graph-outline';
import { LayerManager } from './components/layer-manager';
import { HoverVideoPlayer } from './components/hover-video-player';
import { Image } from './components/image';
import { Prose } from './components/prose';
import { Title } from './components/typography';
import { TextShimmer } from './components/text-shimmer';
import { TextRotate } from './components/text-rotate';
import { TextMorph } from './components/text-morph';
import { Typewriter } from './components/typewriter';
import { StreamingText } from './components/streaming-text';
import { Watermark } from './components/watermark';
import { Transmute } from './components/transmute';
import { PeriodInput } from './components/period-input';
import { PipScale } from './components/pip-scale';
import { DateTimePicker } from './components/date-time-picker';
import { StatementTable } from './components/statement-table';
import { DocReport } from './components/doc-report';
import { PromptLibrary } from './components/prompt-library';
import { QueuedMessage } from './components/queued-message';
import { SessionPrep } from './components/session-prep';
import { TerminalAnimation } from './components/terminal-animation';
import { Viewport } from './components/viewport';
import { Defer } from './components/defer';
import { ScrollArea } from './components/scroll-area';
import { AngleDial } from './components/angle-dial';
import { ScrubInput } from './components/scrub-input';
import { Joystick } from './components/joystick';
import { OriginGrid } from './components/origin-grid';
import { EasingCurve } from './components/easing-curve';
import { TagsInput } from './components/tags-input';
import { TokenInput } from './components/token-input';
import { ValueInput } from './components/value-input';
import { PropertySheet } from './components/property-sheet';
import { FormField } from './components/form-field';
import { Handle } from './components/handle';
import { Reorder } from './components/reorder';
import { Form } from './components/form';
import { FormLayout } from './components/form-layout';
import { FormSection } from './components/form-section';
import { FormFooter } from './components/form-footer';
import { CompoundField } from './components/compound-field';
import { ErrorSummary } from './components/error-summary';
import { FieldError } from './components/field-error';
import { ExpressionBuilder } from './components/expression-builder';
import { FilterSet } from './components/filter-set';
import { FileUpload } from './components/file-upload';
import { Dropzone } from './components/dropzone';
import { Mentions } from './components/mentions';
import { TreeSelect } from './components/tree-select';
import { Carousel } from './components/carousel';
import { InfiniteScroll } from './components/infinite-scroll';
import { Affix } from './components/affix';
import { ZoomableFrame } from './components/zoomable-frame';
import { HoverActions } from './components/hover-actions';
import { ToggleMatrix } from './components/toggle-matrix';
import { HoverCard } from './components/hover-card';
import { Popconfirm } from './components/popconfirm';
import { ImageFrame } from './components/image-frame';
import { MediaViewer } from './components/media-viewer';
import { MediaInspector } from './components/media-inspector';
import { AssetGrid } from './components/asset-grid';
import { AssetWell } from './components/asset-well';
import { Gallery } from './components/gallery';
import { HeroSplit } from './components/hero-split';
import { StepsWithMedia } from './components/steps-with-media';
import { AnimatedImage } from './components/animated-image';
import { CompactionChip } from './components/compaction-chip';
import { Recommendation } from './components/recommendation';
import { TaskRow } from './components/task-row';
import { Thinking } from './components/thinking';
import { Comparison } from './components/comparison';
import { PulsingBorder } from './components/pulsing-border';
import { JsonTree } from './components/json-tree';
import { JsonEditor } from './components/json-editor';
import { MorphingDialog } from './components/morphing-dialog';
import { MorphingPopover } from './components/morphing-popover';
import { Dock } from './components/dock';
import { StackingCards } from './components/stacking-cards';
import { Magnetic } from './components/magnetic';
import { Spotlight } from './components/spotlight';
import { Tilt } from './components/tilt';
import { Backdrop } from './components/backdrop';
import { BackgroundField } from './components/background-field';
import { PRETUI_APPEARANCES, PRETUI_TONES } from './pretui-primitives';

const OPTIONS = [
  { value: 'one', label: 'One' },
  { value: 'two', label: 'Two' },
  { value: 'three', label: 'Three' },
];

const COLUMNS = [
  { key: 'name', label: 'Name', sortable: true },
  { key: 'role', label: 'Role' },
  { key: 'seats', label: 'Seats', align: 'end' as const },
];
const ROWS = [
  { name: 'Ada', role: 'Admin', seats: 3 },
  { name: 'Grace', role: 'Editor', seats: 8 },
  { name: 'Linus', role: 'Viewer', seats: 1 },
];
const STEPS = [
  { label: 'Plan', state: 'complete' as const },
  { label: 'Build', state: 'current' as const },
  { label: 'Ship', state: 'upcoming' as const },
];
const EVENTS = [
  { id: '1', title: 'Created', at: '2026-10-01T09:00:00Z', person: 'Ada' },
  { id: '2', title: 'Reviewed', at: '2026-10-03T14:30:00Z', person: 'Grace' },
];
const ITEMS = [
  { label: 'Owner', value: 'Ada' },
  { label: 'Plan', value: 'Team' },
  { label: 'Region', value: 'EU' },
];
const KV = [
  { key: 'Status', value: 'Active' },
  { key: 'Seats', value: '12' },
];
const CRUMBS = [
  { label: 'Home', href: '#' },
  { label: 'Settings', href: '#' },
  { label: 'Billing' },
];
const FILTERS = [
  { value: 'all', label: 'All', count: 12 },
  { value: 'open', label: 'Open', count: 5 },
  { value: 'done', label: 'Done', count: 7 },
];

const SECTION_COMPONENTS: Record<string, string[]> = {
  button: ['Button', 'IconButton'],
  form: [
    'Input',
    'Textarea',
    'Checkbox',
    'Switch',
    'RadioGroup',
    'SegmentedControl',
    'Stepper',
    'Slider',
    'Fieldset',
    'Toggle',
    'ToggleGroup',
    'Form',
    'FormLayout',
    'FormSection',
    'FormFooter',
    'CompoundField',
    'ErrorSummary',
    'CheckboxCard',
    'RadioCard',
  ],
  nav: [
    'Tabs',
    'BottomNav',
    'Tree',
    'Menubar',
    'NavigationMenu',
    'TableOfContents',
    'Onboarding',
    'Tour',
    'Carousel',
    'InfiniteScroll',
    'Wizard',
    'Sidebar',
  ],
  feedback: [
    'Alert',
    'Spinner',
    'Skeleton',
    'ProgressBar',
    'Meter',
    'Result',
    'Notification',
    'Toast',
    'AgentQuestion',
    'CollapsedTurn',
    'JumpChip',
    'FieldError',
    'Callout',
    'ReadinessPanel',
    'Toaster',
  ],
  display: [
    'Chip',
    'StatusChip',
    'Avatar',
    'Kbd',
    'Stat',
    'Badge',
    'Label',
    'Divider',
    'AvatarGroup',
    'Indicator',
    'ProgressRadial',
    'RecordPill',
    'ContactLink',
    'CopyFit',
    'CtaBand',
    'Marquee',
    'PathText',
    'HoverVideoPlayer',
    'Image',
    'Prose',
    'Title',
    'TextShimmer',
    'TextRotate',
    'TextMorph',
    'Typewriter',
    'StreamingText',
    'Watermark',
    'Transmute',
    'ImageFrame',
    'MediaViewer',
    'MediaInspector',
    'AssetGrid',
    'AssetWell',
    'Gallery',
    'HeroSplit',
    'StepsWithMedia',
    'AnimatedImage',
    'CompactionChip',
    'Recommendation',
    'TaskRow',
    'Thinking',
    'Comparison',
    'PulsingBorder',
    'RecordFace',
    'EntityDisplay',
    'SlidingHighlight',
    'VisuallyHidden',
  ],
  inputs: [
    'Field',
    'SearchInput',
    'NumberInput',
    'AmountInput',
    'MoneyInput',
    'Select',
    'NativeSelect',
    'Combobox',
    'DatePicker',
    'DateRangePicker',
    'Rating',
    'FileTrigger',
    'CopyButton',
    'Calendar',
    'PropertyRow',
    'MultiSelect',
    'Autocomplete',
    'Cascader',
    'EmailInput',
    'UrlInput',
    'PhoneInput',
    'OtpInput',
    'RangeSlider',
    'TimeInput',
    'EditInPlace',
    'Editable',
    'InteractiveInput',
    'Composer',
    'DuelingPicklist',
    'KnownDate',
    'Lookup',
    'LineGrid',
    'PeriodInput',
    'PipScale',
    'DateTimePicker',
    'AngleDial',
    'ScrubInput',
    'Joystick',
    'OriginGrid',
    'EasingCurve',
    'TagsInput',
    'TokenInput',
    'ValueInput',
    'PropertySheet',
    'FormField',
    'Handle',
    'ExpressionBuilder',
    'FilterSet',
    'FileUpload',
    'Dropzone',
    'Mentions',
    'TreeSelect',
    'RecordDetail',
    'RuleRow',
  ],
  nav2: ['Breadcrumb', 'Pagination', 'StepList', 'FilterChips', 'ButtonGroup'],
  data: [
    'DataTable',
    'Table',
    'Descriptions',
    'KeyValue',
    'Timeline',
    'Delta',
    'FormatDate',
    'FormatNumber',
    'FormattedValue',
    'RelativeTime',
    'Odometer',
    'Token',
    'BrokenLink',
    'Sparkline',
    'DataGrid',
    'Feed',
    'Masonry',
    'Grid',
    'FormatBytes',
    'AiInstructions',
    'CodeBlock',
    'DiffBlock',
    'FeatureVoting',
    'Filmstrip',
    'GraphOutline',
    'LayerManager',
    'StatementTable',
    'DocReport',
    'PromptLibrary',
    'JsonTree',
    'JsonEditor',
    'BarList',
    'Board',
    'List',
  ],
  surfaces: [
    'Panel',
    'Collapsible',
    'EmptyState',
    'LoadingState',
    'Cue',
    'Tooltip',
    'Popover',
    'Toolbar',
    'ActionBar',
    'AspectRatio',
    'Card',
    'PanelSection',
    'Fold',
    'Stack',
    'StackDivider',
    'ResultCard',
    'WorkItem',
    'LoadingOverlay',
    'AlertDialog',
    'ApprovalFooter',
    'SkipLink',
    'ContextMenu',
    'DynamicIsland',
    'FloatButton',
    'Scroller',
    'ScrollProgress',
    'InView',
    'Presence',
    'QueuedMessage',
    'SessionPrep',
    'TerminalAnimation',
    'Viewport',
    'Defer',
    'ScrollArea',
    'Reorder',
    'Affix',
    'ZoomableFrame',
    'HoverActions',
    'ToggleMatrix',
    'HoverCard',
    'Popconfirm',
    'MorphingDialog',
    'MorphingPopover',
    'Dock',
    'StackingCards',
    'Magnetic',
    'Spotlight',
    'Tilt',
    'Backdrop',
    'BackgroundField',
    'Item',
    'Accordion',
    'Dialog',
    'Drawer',
    'Popup',
    'Menu',
    'CommandPalette',
  ],
};

// not demoed: MenuPanel (internal level renderer, needs a built MenuLevel; Menu covers it)
class Isolated extends Component<typeof UiShowcase> {
  tones = PRETUI_TONES;
  appearances = PRETUI_APPEARANCES;
  options = OPTIONS;
  categoryOptions = CATEGORY_OPTIONS;
  // the filter values live on the card (filterCategory / filterComponent)
  get category() {
    return this.args.model.filterCategory || 'all';
  }
  get section() {
    return this.args.model.filterComponent || 'all';
  }
  inCategory = (name: string) =>
    this.category === 'all' || DASHBOARD_COMPONENTS.has(name);
  get sectionOptions() {
    return [
      { value: 'all', label: 'All components' },
      ...Object.values(SECTION_COMPONENTS)
        .flat()
        .filter((label) => this.inCategory(label))
        .map((label) => ({ value: label.toLowerCase(), label })),
    ];
  }
  // the Dashboard tab shows a component's usage page in place of its demo card
  hasUsage = (name: string) =>
    this.category === 'dashboard' && name in DASHBOARD_USAGE;
  get usagePages() {
    return [...DASHBOARD_COMPONENTS]
      .filter((name) => this.hasUsage(name))
      .filter(
        (name) => this.section === 'all' || this.section === name.toLowerCase(),
      )
      .map((name) => ({ name, page: DASHBOARD_USAGE[name] }));
  }
  // a demo shows when it matches the picked component, or, with no component
  // picked, when it belongs to the picked category
  show = (key: string) => {
    let name =
      Object.values(SECTION_COMPONENTS)
        .flat()
        .find((label) => label.toLowerCase() === key) ?? key;
    if (this.hasUsage(name)) {
      return false;
    }
    if (this.section !== 'all') {
      return this.section === key;
    }
    return this.inCategory(name);
  };
  showSection = (key: string) =>
    SECTION_COMPONENTS[key].some((label) => this.show(label.toLowerCase()));
  @tracked tourOpen = false;
  setTourOpen = (open: boolean) => {
    this.tourOpen = open;
  };
  openTour = () => this.setTourOpen(true);
  setSection = (v: string) => {
    this.args.model.filterComponent = v;
  };
  setCategory = (v: string) => {
    this.args.model.filterCategory = v;
    this.args.model.filterComponent = 'all';
  };
  spark = [3, 5, 4, 8, 6, 9];
  barActions = [
    { id: 'archive', label: 'Archive' },
    { id: 'delete', label: 'Delete', tone: 'danger' as const },
  ];
  gridColumns = [
    { key: 'name', label: 'Name', sortable: true },
    { key: 'seats', label: 'Seats', num: true },
  ];
  navItems = [
    { id: 'home', label: 'Home' },
    { id: 'search', label: 'Search' },
  ];
  treeNodes = [
    {
      id: 'a',
      label: 'Folder',
      children: [{ id: 'a1', label: 'File' }],
    },
    { id: 'b', label: 'Other' },
  ];
  treeOpen = ['a'];
  pillRecord = { id: 'r1', label: 'Record' };
  lines = ['First line', 'Second line'];
  menuLeaf = [
    { label: 'Cut' },
    { label: 'Copy' },
    '---' as const,
    { label: 'Paste' },
  ];
  menuItems = [
    {
      kind: 'submenu' as const,
      label: 'File',
      items: [{ label: 'New' }, { label: 'Open' }],
    },
    {
      kind: 'submenu' as const,
      label: 'Edit',
      items: [{ label: 'Undo' }, { label: 'Redo' }],
    },
  ];
  navMenu = [
    {
      id: 'a',
      label: 'Products',
      children: [{ id: 'a1', label: 'Cards', href: '#' }],
    },
    { id: 'b', label: 'Docs', href: '#' },
  ];
  tocItems = [
    { id: 'a', label: 'Intro' },
    { id: 'b', label: 'Details', level: 2 },
  ];
  onboardSteps = [
    { id: 's1', title: 'Welcome', body: 'First step.' },
    { id: 's2', title: 'Finish', body: 'Last step.' },
  ];
  tourSteps = [{ id: 't1', title: 'Tour', body: 'A tour step.' }];
  acItems = [{ value: 'one' }, { value: 'two' }];
  cascade = [
    { value: 'a', label: 'A', children: [{ value: 'a1', label: 'A1' }] },
    { value: 'b', label: 'B' },
  ];
  noop = () => {};
  pickNames = ['One', 'Two'];
  records = [
    { id: 'r1', label: 'First record' },
    { id: 'r2', label: 'Second record' },
    { id: 'r3', label: 'Third record' },
  ];
  lineCols = [
    { key: 'item', label: 'Item' },
    { key: 'qty', label: 'Qty' },
  ];
  lineRows = [{ item: 'Widget', qty: 2 }];
  aiRules = [{ id: 'i1', text: 'Be concise', enabled: true }];
  diffLines = [
    { text: 'unchanged' },
    { op: 'add' as const, text: 'added' },
    { op: 'del' as const, text: 'removed' },
  ];
  votes = [{ id: 'v1', title: 'Dark mode', votes: 12 }];
  frames = [
    { time: 0, src: '', label: 'Start' },
    { time: 5, src: '', label: 'End' },
  ];
  gNodes = [
    { id: 'n1', data: { title: 'Start' } },
    { id: 'n2', data: { title: 'End' } },
  ];
  gEdges = [{ id: 'e1', source: 'n1', target: 'n2' }];
  layerNodes = [
    {
      id: 'l1',
      name: 'Group',
      children: [{ id: 'l2', name: 'Layer' }],
    },
  ];
  words = ['Alpha', 'Beta'];
  stmtCols = [
    { key: 'name', label: 'Account' },
    { key: 'amount', label: 'Amount', kind: 'amount' as const },
  ];
  stmtRows = [{ key: 'r1', cells: { name: 'Revenue', amount: 1200 } }];
  prompts = [{ id: 'p1', title: 'Summarise', body: 'Summarise this text.' }];
  prepSteps = [
    { id: 'a', label: 'Gather' },
    { id: 'b', label: 'Review' },
  ];
  termLines = [{ id: 't1', text: 'pnpm install' }];
  channelTrack = { kind: 'custom' as const, css: 'transparent' };
  tags = ['alpha', 'beta'];
  palette = ['#3366ff', '#22aa66', '#dd4444'];
  sheetSpecs = [{ key: 'size', kind: 'number' as const, label: 'Size' }];
  sheetValues = { size: 4 };
  noItems = [];
  formIssues = [
    { targetPath: 'name', severity: 'error', message: 'Name is required' },
  ];
  issue = {
    targetPath: 'name',
    severity: 'error',
    message: 'Name is required',
  };
  mentionItems = [
    { id: 'u1', label: 'ada' },
    { id: 'u2', label: 'grace' },
  ];
  hoverActions = [
    { id: 'edit', label: 'Edit' },
    { id: 'del', label: 'Delete' },
  ];
  matrixRows = [
    { id: 'r1', label: 'Read' },
    { id: 'r2', label: 'Write' },
  ];
  matrixCols = [
    { id: 'c1', label: 'Admin' },
    { id: 'c2', label: 'Viewer' },
  ];
  asset = { src: '', name: 'Placeholder', kind: 'image' as const };
  resolvedAsset = {
    src: '',
    name: 'Placeholder',
    label: 'Placeholder',
    kind: 'image' as const,
  };
  assets = [{ src: '', name: 'One', kind: 'image' as const }];
  mediaSteps = [{ label: 'First' }, { label: 'Second' }];
  recOptions = [
    { key: 'a', body: 'Option A', short: 'A', level: 1, label: 'Plan A' },
  ];
  thinkRows = [{ id: 't1', primary: 'Reading files', state: 'done' as const }];
  jsonText = '{"name":"Ada","tags":["a","b"]}';
  choiceOptions = [
    { value: 'basic', title: 'Basic', description: 'For individuals' },
    { value: 'pro', title: 'Pro', description: 'For teams', meta: '12 / mo' },
  ];
  choiceChecked = ['pro'];
  wizardSteps = [
    { id: 'account', label: 'Account', detail: 'Who is signing up' },
    { id: 'plan', label: 'Plan', detail: 'Pick a tier' },
    { id: 'review', label: 'Review', detail: 'Confirm' },
  ];
  gates = [
    { name: 'Lint', state: 'pass' as const },
    { name: 'Tests', state: 'running' as const },
  ];
  toastStore = new ToastStore();
  pushToast = () =>
    this.toastStore.show({ title: 'Saved', message: 'Changes stored' });
  faceRecord = { id: 'r1', label: 'Acme Corp', meta: 'Account' };
  rule = {
    ruleId: 'r1',
    label: 'Total is positive',
    severity: 'error',
    targetPath: 'Total',
    message: 'Total must be positive',
    expression: 'Total > 0',
  };
  barRows = [
    { name: 'Search', value: 420 },
    { name: 'Direct', value: 280 },
    { name: 'Referral', value: 130 },
  ];
  chartRows = [
    { grade: 'A', chests: 120 },
    { grade: 'B', chests: 80 },
    { grade: 'C', chests: 45 },
  ];
  boardColumns = [
    {
      key: 'todo',
      label: 'To do',
      color: null,
      wipLimit: null,
      collapsed: false,
      sortOrder: 1,
    },
    {
      key: 'done',
      label: 'Done',
      color: null,
      wipLimit: null,
      collapsed: false,
      sortOrder: 2,
    },
  ];
  boardPlacements = [
    { columnId: 'todo', index: 0, sortOrder: 1 },
    { columnId: 'todo', index: 1, sortOrder: 2 },
    { columnId: 'done', index: 2, sortOrder: 1 },
  ];
  boardTitles = ['Write spec', 'Review copy', 'Ship release'];
  @tracked accOpenA = true;
  @tracked accOpenB = false;
  toggleAccA = () => (this.accOpenA = !this.accOpenA);
  toggleAccB = () => (this.accOpenB = !this.accOpenB);
  @tracked dialogOpen = false;
  openDialog = () => (this.dialogOpen = true);
  closeDialog = () => (this.dialogOpen = false);
  @tracked drawerOpen = false;
  openDrawer = () => (this.drawerOpen = true);
  closeDrawer = () => (this.drawerOpen = false);
  @tracked popupOpen = false;
  togglePopup = () => (this.popupOpen = !this.popupOpen);
  @tracked paletteOpen = false;
  openPalette = () => (this.paletteOpen = true);
  closePalette = () => (this.paletteOpen = false);
  columns = COLUMNS;
  rows = ROWS;
  steps = STEPS;
  events = EVENTS;
  items = ITEMS;
  feedItems = [
    { id: '1', label: 'Created' },
    { id: '2', label: 'Reviewed' },
  ];
  kv = KV;
  crumbs = CRUMBS;
  filters = FILTERS;
  get realm() {
    return this.args.model[realmURL];
  }

  <template>
    <ThemeFrame @realm={{this.realm}} @context={{@context}}>
      <main class='showcase'>
        <h1>UI Showcase</h1>
        <div class='category'>
          <Tabs
            @options={{this.categoryOptions}}
            @value={{this.category}}
            @onValueChange={{this.setCategory}}
          />
        </div>
        <div class='filter'>
          <Select
            @options={{this.sectionOptions}}
            @value={{this.section}}
            @onValueChange={{this.setSection}}
            @searchEnabled={{true}}
            @label='Filter components'
          />
        </div>

        {{#each this.usagePages as |usage|}}
          <section class='usage' aria-labelledby='usage-{{usage.name}}'>
            <h2 id='usage-{{usage.name}}'>{{usage.name}}</h2>
            <usage.page />
          </section>
        {{/each}}

        {{#if (this.showSection 'button')}}
          <section aria-labelledby='s-button'>
            <h2 id='s-button'>Button: tone × appearance</h2>
            <div class='grid'>
              {{#if (this.show 'button')}}<div
                  class='demo'
                  data-demo='button'
                ><h3 class='demo-name'>Button</h3><div class='demo-body'>
                    {{#each this.appearances as |appearance|}}
                      <div class='row' data-appearance={{appearance}}>
                        {{#each this.tones as |tone|}}
                          <Button
                            @tone={{tone}}
                            @appearance={{appearance}}
                          >{{tone}}</Button>
                        {{/each}}
                      </div>
                    {{/each}}
                    <div class='row'>
                      <Button @busy={{true}}>Busy</Button>
                      <Button @disabled={{true}}>Disabled</Button>
                    </div>
                  </div></div>{{/if}}
              {{#if (this.show 'iconbutton')}}<div
                  class='demo'
                  data-demo='iconbutton'
                ><h3 class='demo-name'>IconButton</h3><div class='demo-body'>
                    <div class='row'><IconButton
                        @label='Add'
                        @icon={{PlusIcon}}
                      /></div>
                  </div></div>{{/if}}
            </div>
          </section>
        {{/if}}

        {{#if (this.showSection 'form')}}
          <section aria-labelledby='s-form'>
            <h2 id='s-form'>Form controls</h2>
            <div class='cols'>
              {{#if (this.show 'input')}}<div class='demo' data-demo='input'><h3
                    class='demo-name'
                  >Input</h3><div class='demo-body'>
                    <Input @placeholder='Input' />
                    <Input
                      @value='Invalid'
                      @invalid={{true}}
                      @errorMessage='Error text'
                    />
                    <Input @placeholder='Disabled' @disabled={{true}} />
                  </div></div>{{/if}}
              {{#if (this.show 'textarea')}}<div
                  class='demo'
                  data-demo='textarea'
                ><h3 class='demo-name'>Textarea</h3><div class='demo-body'>
                    <Textarea @placeholder='Textarea' />
                  </div></div>{{/if}}
              {{#if (this.show 'checkbox')}}<div
                  class='demo'
                  data-demo='checkbox'
                ><h3 class='demo-name'>Checkbox</h3><div class='demo-body'>
                    <Checkbox @label='Checkbox' @checked={{true}} />
                  </div></div>{{/if}}
              {{#if (this.show 'switch')}}<div
                  class='demo'
                  data-demo='switch'
                ><h3 class='demo-name'>Switch</h3><div class='demo-body'>
                    <Switch @checked={{true}} />
                  </div></div>{{/if}}
              {{#if (this.show 'radiogroup')}}<div
                  class='demo'
                  data-demo='radiogroup'
                  data-span='2'
                ><h3 class='demo-name'>RadioGroup</h3><div class='demo-body'>
                    <RadioGroup @options={{this.options}} @defaultValue='two' />
                  </div></div>{{/if}}
              {{#if (this.show 'segmentedcontrol')}}
                <SegmentedControl
                  @options={{this.options}}
                  @defaultValue='one'
                  @label='Segmented'
                />
              {{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'stepper')}}<div
                  class='demo'
                  data-demo='stepper'
                ><h3 class='demo-name'>Stepper</h3><div class='demo-body'>
                    <Stepper @defaultValue={{3}} @min={{0}} @max={{10}} />
                  </div></div>{{/if}}
              {{#if (this.show 'slider')}}<div
                  class='demo'
                  data-demo='slider'
                ><h3 class='demo-name'>Slider</h3><div class='demo-body'>
                    <Slider @defaultValue={{40}} @label='Slider' />
                  </div></div>{{/if}}
              {{#if (this.show 'fieldset')}}<div
                  class='demo'
                  data-demo='fieldset'
                ><h3 class='demo-name'>Fieldset</h3><div class='demo-body'>
                    <Fieldset
                      @legend='Fieldset'
                      @description='Grouped controls'
                    >
                      <Checkbox @label='One' />
                      <Checkbox @label='Two' />
                    </Fieldset>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'toggle')}}<div
                  class='demo'
                  data-demo='toggle'
                ><h3 class='demo-name'>Toggle</h3><div class='demo-body'>
                    <Toggle @label='Toggle' />
                  </div></div>{{/if}}
              {{#if (this.show 'togglegroup')}}<div
                  class='demo'
                  data-demo='togglegroup'
                ><h3 class='demo-name'>ToggleGroup</h3><div class='demo-body'>
                    <ToggleGroup
                      @options={{this.options}}
                      @label='Toggle group'
                      @defaultValue='one'
                    />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'form')}}<div class='demo' data-demo='form'><h3
                    class='demo-name'
                  >Form</h3><div class='demo-body'>
                    <Form>
                      <FormField @label='Name'><Input
                          @placeholder='Name'
                        /></FormField>
                    </Form>
                  </div></div>{{/if}}
              {{#if (this.show 'formlayout')}}<div
                  class='demo'
                  data-demo='formlayout'
                ><h3 class='demo-name'>FormLayout</h3><div class='demo-body'>
                    <FormLayout @columns={{2}}>
                      <Input @placeholder='First' />
                      <Input @placeholder='Last' />
                    </FormLayout>
                  </div></div>{{/if}}
              {{#if (this.show 'formsection')}}<div
                  class='demo'
                  data-demo='formsection'
                ><h3 class='demo-name'>FormSection</h3><div class='demo-body'>
                    <FormSection
                      @title='Section'
                      @description='Section description'
                    >
                      <Input @placeholder='Value' />
                    </FormSection>
                  </div></div>{{/if}}
              {{#if (this.show 'formfooter')}}<div
                  class='demo'
                  data-demo='formfooter'
                ><h3 class='demo-name'>FormFooter</h3><div class='demo-body'>
                    <FormFooter @dock='static' />
                  </div></div>{{/if}}
              {{#if (this.show 'compoundfield')}}<div
                  class='demo'
                  data-demo='compoundfield'
                ><h3 class='demo-name'>CompoundField</h3><div class='demo-body'>
                    <CompoundField @label='Compound field'>
                      <Input @placeholder='Part' />
                    </CompoundField>
                  </div></div>{{/if}}
              {{#if (this.show 'errorsummary')}}<div
                  class='demo'
                  data-demo='errorsummary'
                ><h3 class='demo-name'>ErrorSummary</h3><div class='demo-body'>
                    <ErrorSummary
                      @issues={{this.formIssues}}
                      @always={{true}}
                    />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'checkboxcard')}}<div
                  class='demo'
                  data-demo='checkboxcard'
                  data-span='2'
                ><h3 class='demo-name'>CheckboxCard</h3><div class='demo-body'>
                    <CheckboxCard
                      @label='Add-ons'
                      @options={{this.choiceOptions}}
                      @defaultValue={{this.choiceChecked}}
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'radiocard')}}<div
                  class='demo'
                  data-demo='radiocard'
                  data-span='2'
                ><h3 class='demo-name'>RadioCard</h3><div class='demo-body'>
                    <RadioCard
                      @label='Plan'
                      @options={{this.choiceOptions}}
                      @defaultValue='pro'
                    />
                  </div></div>{{/if}}
            </div>
          </section>
        {{/if}}

        {{#if (this.showSection 'nav')}}
          <section aria-labelledby='s-nav'>
            <h2 id='s-nav'>Navigation</h2>
            {{#if (this.show 'tabs')}}<div
                class='demo'
                data-demo='tabs'
                data-span='2'
              ><h3 class='demo-name'>Tabs</h3><div class='demo-body'>
                  <Tabs
                    @options={{this.options}}
                    @defaultValue='one'
                    as |active|
                  >
                    <p>Active tab: {{active}}</p>
                  </Tabs>
                </div></div>{{/if}}
            <div class='row'>
              {{#if (this.show 'bottomnav')}}<div
                  class='demo'
                  data-demo='bottomnav'
                ><h3 class='demo-name'>BottomNav</h3><div class='demo-body'>
                    <BottomNav
                      @items={{this.navItems}}
                      @defaultValue='home'
                      @label='Bottom nav'
                      @position='static'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'tree')}}<div class='demo' data-demo='tree'><h3
                    class='demo-name'
                  >Tree</h3><div class='demo-body'>
                    <Tree
                      @nodes={{this.treeNodes}}
                      @label='Tree'
                      @defaultExpanded={{this.treeOpen}}
                    />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'menubar')}}<div
                  class='demo'
                  data-demo='menubar'
                  data-span='2'
                ><h3 class='demo-name'>Menubar</h3><div class='demo-body'>
                    <Menubar @items={{this.menuItems}} @label='Menubar' />
                  </div></div>{{/if}}
              {{#if (this.show 'navigationmenu')}}<div
                  class='demo'
                  data-demo='navigationmenu'
                  data-span='2'
                ><h3 class='demo-name'>NavigationMenu</h3><div
                    class='demo-body'
                  >
                    <NavigationMenu
                      @items={{this.navMenu}}
                      @label='Navigation menu'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'tableofcontents')}}<div
                  class='demo'
                  data-demo='tableofcontents'
                ><h3 class='demo-name'>TableOfContents</h3><div
                    class='demo-body'
                  >
                    <TableOfContents
                      @items={{this.tocItems}}
                      @label='Contents'
                      @links={{false}}
                      @spy={{false}}
                      @defaultActiveId='a'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'onboarding')}}<div
                  class='demo'
                  data-demo='onboarding'
                  data-span='2'
                ><h3 class='demo-name'>Onboarding</h3><div class='demo-body'>
                    <Onboarding
                      @steps={{this.onboardSteps}}
                      @label='Onboarding'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'tour')}}<div
                  class='demo'
                  data-demo='tour'
                  data-span='2'
                ><h3 class='demo-name'>Tour</h3><div class='demo-body'>
                    <Button {{on 'click' this.openTour}}>Start tour</Button>
                    <Tour
                      @steps={{this.tourSteps}}
                      @open={{this.tourOpen}}
                      @onOpenChange={{this.setTourOpen}}
                      @modal={{false}}
                    />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'carousel')}}<div
                  class='demo'
                  data-demo='carousel'
                  data-span='full'
                ><h3 class='demo-name'>Carousel</h3><div class='demo-body'>
                    <Carousel @items={{this.items}} @label='Carousel'>
                      <:slide as |item|>{{item.label}}</:slide>
                    </Carousel>
                  </div></div>{{/if}}
              {{#if (this.show 'infinitescroll')}}<div
                  class='demo'
                  data-demo='infinitescroll'
                ><h3 class='demo-name'>InfiniteScroll</h3><div
                    class='demo-body'
                  >
                    <InfiniteScroll @hasMore={{false}}>
                      <:default>Content</:default>
                      <:end>End</:end>
                    </InfiniteScroll>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'wizard')}}<div
                  class='demo'
                  data-demo='wizard'
                  data-span='full'
                ><h3 class='demo-name'>Wizard</h3><div class='demo-body'>
                    <Wizard @steps={{this.wizardSteps}} @label='Set-up steps'>
                      <:step as |step|>Panel for {{step.label}}</:step>
                    </Wizard>
                  </div></div>{{/if}}
              {{#if (this.show 'sidebar')}}<div
                  class='demo'
                  data-demo='sidebar'
                  data-span='full'
                ><h3 class='demo-name'>Sidebar</h3><div class='demo-body'>
                    <div class='stage'>
                      <Sidebar
                        @label='Sidebar'
                        @mobile={{false}}
                        @collapsible='none'
                      >
                        <:header>Brand</:header>
                        <:nav as |n|>
                          <SidebarItem
                            @label='Home'
                            @href='#'
                            @active={{true}}
                            @collapsed={{n.collapsed}}
                          />
                          <SidebarItem
                            @label='Settings'
                            @href='#'
                            @collapsed={{n.collapsed}}
                          />
                        </:nav>
                        <:default>Page content</:default>
                      </Sidebar>
                    </div>
                  </div></div>{{/if}}
            </div>
          </section>
        {{/if}}

        {{#if (this.showSection 'feedback')}}
          <section aria-labelledby='s-feedback'>
            <h2 id='s-feedback'>Feedback</h2>
            <div class='cols'>
              {{#if (this.show 'alert')}}<div
                  class='demo'
                  data-demo='alert'
                  data-span='2'
                ><h3 class='demo-name'>Alert</h3><div class='demo-body'>
                    {{#each this.tones as |tone|}}
                      <Alert @tone={{tone}} @title={{tone}}>Alert body</Alert>
                    {{/each}}
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'spinner')}}<div
                  class='demo'
                  data-demo='spinner'
                ><h3 class='demo-name'>Spinner</h3><div class='demo-body'>
                    <Spinner />
                  </div></div>{{/if}}
              {{#if (this.show 'skeleton')}}<div
                  class='demo'
                  data-demo='skeleton'
                ><h3 class='demo-name'>Skeleton</h3><div class='demo-body'>
                    <Skeleton @width='8rem' />
                  </div></div>{{/if}}
              {{#if (this.show 'progressbar')}}<div
                  class='demo'
                  data-demo='progressbar'
                ><h3 class='demo-name'>ProgressBar</h3><div class='demo-body'>
                    <ProgressBar @value={{60}} @label='Progress' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'meter')}}<div class='demo' data-demo='meter'><h3
                    class='demo-name'
                  >Meter</h3><div class='demo-body'>
                    <Meter
                      @level={{3}}
                      @segments={{5}}
                      @label='Signal strength'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'result')}}<div
                  class='demo'
                  data-demo='result'
                ><h3 class='demo-name'>Result</h3><div class='demo-body'>
                    <Result
                      @status='success'
                      @title='Saved'
                      @description='Changes are live.'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'notification')}}<div
                  class='demo'
                  data-demo='notification'
                ><h3 class='demo-name'>Notification</h3><div class='demo-body'>
                    <Notification
                      @title='Heads up'
                      @message='A notification message.'
                      @tone='info'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'toast')}}<div class='demo' data-demo='toast'><h3
                    class='demo-name'
                  >Toast</h3><div class='demo-body'>
                    <Toast @title='Toast' @message='A toast message.' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'agentquestion')}}<div
                  class='demo'
                  data-demo='agentquestion'
                ><h3 class='demo-name'>AgentQuestion</h3><div class='demo-body'>
                    <AgentQuestion
                      @question='Which option?'
                      @options={{this.pickNames}}
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'collapsedturn')}}<div
                  class='demo'
                  data-demo='collapsedturn'
                ><h3 class='demo-name'>CollapsedTurn</h3><div class='demo-body'>
                    <CollapsedTurn @summary='3 steps collapsed' />
                  </div></div>{{/if}}
              {{#if (this.show 'jumpchip')}}<div
                  class='demo'
                  data-demo='jumpchip'
                ><h3 class='demo-name'>JumpChip</h3><div class='demo-body'>
                    <JumpChip
                      @visible={{true}}
                      @count={{2}}
                      @label='New messages'
                    />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'fielderror')}}<div
                  class='demo'
                  data-demo='fielderror'
                ><h3 class='demo-name'>FieldError</h3><div class='demo-body'>
                    <FieldError @issue={{this.issue}} />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'callout')}}<div
                  class='demo'
                  data-demo='callout'
                ><h3 class='demo-name'>Callout</h3><div class='demo-body'>
                    <Callout @tone='info' @title='Heads up'>Callout body</Callout>
                  </div></div>{{/if}}
              {{#if (this.show 'readinesspanel')}}<div
                  class='demo'
                  data-demo='readinesspanel'
                  data-span='2'
                ><h3 class='demo-name'>ReadinessPanel</h3><div
                    class='demo-body'
                  >
                    <ReadinessPanel
                      @title='Deploy to production'
                      @gates={{this.gates}}
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'toaster')}}<div
                  class='demo'
                  data-demo='toaster'
                ><h3 class='demo-name'>Toaster</h3><div class='demo-body'>
                    <Button {{on 'click' this.pushToast}}>Show toast</Button>
                    <Toaster @store={{this.toastStore}} />
                  </div></div>{{/if}}
            </div>
          </section>
        {{/if}}

        {{#if (this.showSection 'display')}}
          <section aria-labelledby='s-display'>
            <h2 id='s-display'>Display</h2>
            <div class='row'>
              {{#if (this.show 'chip')}}<div class='demo' data-demo='chip'><h3
                    class='demo-name'
                  >Chip</h3><div class='demo-body'>
                    {{#each this.tones as |tone|}}
                      <Chip @label={{tone}} @tone={{tone}} />
                    {{/each}}
                  </div></div>{{/if}}
              {{#if (this.show 'statuschip')}}<div
                  class='demo'
                  data-demo='statuschip'
                ><h3 class='demo-name'>StatusChip</h3><div class='demo-body'>
                    <StatusChip @value='Active' />
                    <StatusChip @value='Overdue' />
                  </div></div>{{/if}}
              {{#if (this.show 'avatar')}}<div
                  class='demo'
                  data-demo='avatar'
                ><h3 class='demo-name'>Avatar</h3><div class='demo-body'>
                    <Avatar @name='Ada Lovelace' />
                  </div></div>{{/if}}
              {{#if (this.show 'kbd')}}<div class='demo' data-demo='kbd'><h3
                    class='demo-name'
                  >Kbd</h3><div class='demo-body'>
                    <Kbd @value='Mod+K' />
                  </div></div>{{/if}}
            </div>
            {{#if (this.show 'stat')}}<div class='demo' data-demo='stat'><h3
                  class='demo-name'
                >Stat</h3><div class='demo-body'>
                  <Stat
                    @label='Revenue'
                    @value={{12480}}
                    @delta={{0.12}}
                    @hint='vs last month'
                  />
                </div></div>{{/if}}
            <div class='row'>
              {{#if (this.show 'badge')}}<div class='demo' data-demo='badge'><h3
                    class='demo-name'
                  >Badge</h3><div class='demo-body'>
                    <Badge @count={{7}}><Avatar @name='Ada Lovelace' /></Badge>
                  </div></div>{{/if}}
              {{#if (this.show 'label')}}<div class='demo' data-demo='label'><h3
                    class='demo-name'
                  >Label</h3><div class='demo-body'>
                    <Label>Label</Label>
                  </div></div>{{/if}}
              {{#if (this.show 'divider')}}<div
                  class='demo'
                  data-demo='divider'
                ><h3 class='demo-name'>Divider</h3><div class='demo-body'>
                    <Divider @label='Divider' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'avatargroup')}}<div
                  class='demo'
                  data-demo='avatargroup'
                ><h3 class='demo-name'>AvatarGroup</h3><div class='demo-body'>
                    <AvatarGroup>
                      <Avatar @name='Ada Lovelace' />
                      <Avatar @name='Grace Hopper' />
                    </AvatarGroup>
                  </div></div>{{/if}}
              {{#if (this.show 'indicator')}}<div
                  class='demo'
                  data-demo='indicator'
                ><h3 class='demo-name'>Indicator</h3><div class='demo-body'>
                    <Indicator @label='Online' @tone='success' />
                  </div></div>{{/if}}
              {{#if (this.show 'progressradial')}}<div
                  class='demo'
                  data-demo='progressradial'
                ><h3 class='demo-name'>ProgressRadial</h3><div
                    class='demo-body'
                  >
                    <ProgressRadial @value={{60}} />
                  </div></div>{{/if}}
              {{#if (this.show 'recordpill')}}<div
                  class='demo'
                  data-demo='recordpill'
                ><h3 class='demo-name'>RecordPill</h3><div class='demo-body'>
                    <RecordPill @record={{this.pillRecord}} />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'contactlink')}}<div
                  class='demo'
                  data-demo='contactlink'
                ><h3 class='demo-name'>ContactLink</h3><div class='demo-body'>
                    <ContactLink
                      @channel='email'
                      @value='ada@example.com'
                      @name='Ada'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'copyfit')}}<div
                  class='demo'
                  data-demo='copyfit'
                ><h3 class='demo-name'>CopyFit</h3><div class='demo-body'>
                    <CopyFit
                      @title='Copy fit'
                      @eyebrow='Eyebrow'
                      @meta='Meta'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'ctaband')}}<div
                  class='demo'
                  data-demo='ctaband'
                  data-span='2'
                ><h3 class='demo-name'>CtaBand</h3><div class='demo-body'>
                    <CtaBand
                      @headline='Call to action'
                      @lead='Short lead text.'
                    >
                      <:actions><Button>Go</Button></:actions>
                    </CtaBand>
                  </div></div>{{/if}}
              {{#if (this.show 'marquee')}}<div
                  class='demo'
                  data-demo='marquee'
                ><h3 class='demo-name'>Marquee</h3><div class='demo-body'>
                    <Marquee><Chip @label='One' /><Chip @label='Two' /><Chip
                        @label='Three'
                      /></Marquee>
                  </div></div>{{/if}}
              {{#if (this.show 'pathtext')}}<div
                  class='demo'
                  data-demo='pathtext'
                ><h3 class='demo-name'>PathText</h3><div class='demo-body'>
                    <PathText @text='Path text' @shape='circle' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'hovervideoplayer')}}
                <HoverVideoPlayer @src='' @label='Hover video' />
              {{/if}}
              {{#if (this.show 'image')}}<div class='demo' data-demo='image'><h3
                    class='demo-name'
                  >Image</h3><div class='demo-body'>
                    <Image @alt='Placeholder image' @ratio='16/9' />
                  </div></div>{{/if}}

              {{#if (this.show 'prose')}}<div class='demo' data-demo='prose'><h3
                    class='demo-name'
                  >Prose</h3><div class='demo-body'>
                    <Prose><p>Prose body text.</p></Prose>
                  </div></div>{{/if}}
              {{#if (this.show 'title')}}<div class='demo' data-demo='title'><h3
                    class='demo-name'
                  >Title</h3><div class='demo-body'>
                    <Title @size='heading'>Title</Title>
                  </div></div>{{/if}}
              {{#if (this.show 'textshimmer')}}<div
                  class='demo'
                  data-demo='textshimmer'
                ><h3 class='demo-name'>TextShimmer</h3><div class='demo-body'>
                    <TextShimmer @text='Shimmer' />
                  </div></div>{{/if}}
              {{#if (this.show 'textrotate')}}<div
                  class='demo'
                  data-demo='textrotate'
                ><h3 class='demo-name'>TextRotate</h3><div class='demo-body'>
                    <TextRotate @words={{this.words}} />
                  </div></div>{{/if}}
              {{#if (this.show 'textmorph')}}<div
                  class='demo'
                  data-demo='textmorph'
                ><h3 class='demo-name'>TextMorph</h3><div class='demo-body'>
                    <TextMorph @text='Morph' />
                  </div></div>{{/if}}
              {{#if (this.show 'typewriter')}}<div
                  class='demo'
                  data-demo='typewriter'
                ><h3 class='demo-name'>Typewriter</h3><div class='demo-body'>
                    <Typewriter @text='Typewriter' />
                  </div></div>{{/if}}
              {{#if (this.show 'streamingtext')}}<div
                  class='demo'
                  data-demo='streamingtext'
                ><h3 class='demo-name'>StreamingText</h3><div class='demo-body'>
                    <StreamingText @text='Streaming text' />
                  </div></div>{{/if}}
              {{#if (this.show 'watermark')}}<div
                  class='demo'
                  data-demo='watermark'
                ><h3 class='demo-name'>Watermark</h3><div class='demo-body'>
                    <Watermark @text='Draft'>Watermarked content</Watermark>
                  </div></div>{{/if}}
              {{#if (this.show 'transmute')}}<div
                  class='demo'
                  data-demo='transmute'
                ><h3 class='demo-name'>Transmute</h3><div class='demo-body'>
                    <Transmute @verb='Transmute' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>

            </div>
            <div class='row'>
              {{#if (this.show 'imageframe')}}<div
                  class='demo'
                  data-demo='imageframe'
                ><h3 class='demo-name'>ImageFrame</h3><div class='demo-body'>
                    <ImageFrame @asset={{this.resolvedAsset}} />
                  </div></div>{{/if}}
              {{#if (this.show 'mediaviewer')}}<div
                  class='demo'
                  data-demo='mediaviewer'
                  data-span='full'
                ><h3 class='demo-name'>MediaViewer</h3><div class='demo-body'>
                    <MediaViewer @asset={{this.asset}} />
                  </div></div>{{/if}}
              {{#if (this.show 'mediainspector')}}<div
                  class='demo'
                  data-demo='mediainspector'
                ><h3 class='demo-name'>MediaInspector</h3><div
                    class='demo-body'
                  >
                    <MediaInspector @asset={{this.asset}} @title='Inspector' />
                  </div></div>{{/if}}
              {{#if (this.show 'assetgrid')}}<div
                  class='demo'
                  data-demo='assetgrid'
                  data-span='2'
                ><h3 class='demo-name'>AssetGrid</h3><div class='demo-body'>
                    <AssetGrid @rows={{this.assets}} @label='Assets' />
                  </div></div>{{/if}}
              {{#if (this.show 'assetwell')}}<div
                  class='demo'
                  data-demo='assetwell'
                ><h3 class='demo-name'>AssetWell</h3><div class='demo-body'>
                    <AssetWell />
                  </div></div>{{/if}}
              {{#if (this.show 'gallery')}}<div
                  class='demo'
                  data-demo='gallery'
                  data-span='full'
                ><h3 class='demo-name'>Gallery</h3><div class='demo-body'>
                    <Gallery @assets={{this.assets}} />
                  </div></div>{{/if}}
              {{#if (this.show 'herosplit')}}<div
                  class='demo'
                  data-demo='herosplit'
                  data-span='2'
                ><h3 class='demo-name'>HeroSplit</h3><div class='demo-body'>
                    <HeroSplit @headline='Hero headline' @lead='Lead text.' />
                  </div></div>{{/if}}
              {{#if (this.show 'stepswithmedia')}}<div
                  class='demo'
                  data-demo='stepswithmedia'
                  data-span='2'
                ><h3 class='demo-name'>StepsWithMedia</h3><div
                    class='demo-body'
                  >
                    <StepsWithMedia @steps={{this.mediaSteps}} @title='Steps' />
                  </div></div>{{/if}}

              {{#if (this.show 'animatedimage')}}<div
                  class='demo'
                  data-demo='animatedimage'
                ><h3 class='demo-name'>AnimatedImage</h3><div class='demo-body'>
                    <AnimatedImage @src='' @alt='Animated' />
                  </div></div>{{/if}}
              {{#if (this.show 'compactionchip')}}<div
                  class='demo'
                  data-demo='compactionchip'
                ><h3 class='demo-name'>CompactionChip</h3><div
                    class='demo-body'
                  >
                    <CompactionChip @state='done' @messageCount={{12}} />
                  </div></div>{{/if}}
              {{#if (this.show 'recommendation')}}<div
                  class='demo'
                  data-demo='recommendation'
                ><h3 class='demo-name'>Recommendation</h3><div
                    class='demo-body'
                  >
                    <Recommendation
                      @question='Which plan?'
                      @options={{this.recOptions}}
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'taskrow')}}<div
                  class='demo'
                  data-demo='taskrow'
                ><h3 class='demo-name'>TaskRow</h3><div class='demo-body'>
                    <TaskRow @label='Task' @state='completed' />
                  </div></div>{{/if}}
              {{#if (this.show 'thinking')}}<div
                  class='demo'
                  data-demo='thinking'
                  data-span='2'
                ><h3 class='demo-name'>Thinking</h3><div class='demo-body'>
                    <Thinking @rows={{this.thinkRows}} />
                  </div></div>{{/if}}
              {{#if (this.show 'comparison')}}<div
                  class='demo'
                  data-demo='comparison'
                  data-span='2'
                ><h3 class='demo-name'>Comparison</h3><div class='demo-body'>
                    <Comparison>
                      <:before>Before</:before>
                      <:after>After</:after>
                    </Comparison>
                  </div></div>{{/if}}
              {{#if (this.show 'pulsingborder')}}<div
                  class='demo'
                  data-demo='pulsingborder'
                ><h3 class='demo-name'>PulsingBorder</h3><div class='demo-body'>
                    <PulsingBorder @label='Pulsing'>Content</PulsingBorder>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'recordface')}}<div
                  class='demo'
                  data-demo='recordface'
                ><h3 class='demo-name'>RecordFace</h3><div class='demo-body'>
                    <RecordFace @record={{this.faceRecord}} />
                  </div></div>{{/if}}
              {{#if (this.show 'entitydisplay')}}<div
                  class='demo'
                  data-demo='entitydisplay'
                ><h3 class='demo-name'>EntityDisplay</h3><div class='demo-body'>
                    <EntityDisplay
                      @title='Entity title'
                      @subtitle='Entity subtitle'
                      @tag='Tag'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'slidinghighlight')}}
                <div class='tabs' role='tablist' {{slidingHighlight}}>
                  <SlidingHighlight />
                  <button
                    type='button'
                    role='tab'
                    aria-selected='true'
                  >One</button>
                  <button
                    type='button'
                    role='tab'
                    aria-selected='false'
                  >Two</button>
                </div>
              {{/if}}
              {{#if (this.show 'visuallyhidden')}}<div
                  class='demo'
                  data-demo='visuallyhidden'
                ><h3 class='demo-name'>VisuallyHidden</h3><div
                    class='demo-body'
                  >
                    <p>Screen-reader text follows.<VisuallyHidden>Hidden text</VisuallyHidden></p>
                  </div></div>{{/if}}
            </div>
          </section>
        {{/if}}

        {{#if (this.showSection 'inputs')}}
          <section aria-labelledby='s-inputs'>
            <h2 id='s-inputs'>More inputs</h2>
            <div class='cols'>
              {{#if (this.show 'field')}}<div class='demo' data-demo='field'><h3
                    class='demo-name'
                  >Field</h3><div class='demo-body'>
                    <Field @label='Field' @hint='Hint text'>
                      <Input @placeholder='Wrapped control' />
                    </Field>
                  </div></div>{{/if}}
              {{#if (this.show 'searchinput')}}<div
                  class='demo'
                  data-demo='searchinput'
                ><h3 class='demo-name'>SearchInput</h3><div class='demo-body'>
                    <SearchInput @placeholder='Search' />
                  </div></div>{{/if}}
              {{#if (this.show 'numberinput')}}<div
                  class='demo'
                  data-demo='numberinput'
                ><h3 class='demo-name'>NumberInput</h3><div class='demo-body'>
                    <NumberInput @value={{4}} />
                  </div></div>{{/if}}
              {{#if (this.show 'amountinput')}}<div
                  class='demo'
                  data-demo='amountinput'
                ><h3 class='demo-name'>AmountInput</h3><div class='demo-body'>
                    <AmountInput @value={{25}} />
                  </div></div>{{/if}}
              {{#if (this.show 'moneyinput')}}<div
                  class='demo'
                  data-demo='moneyinput'
                ><h3 class='demo-name'>MoneyInput</h3><div class='demo-body'>
                    <MoneyInput />
                  </div></div>{{/if}}
              {{#if (this.show 'select')}}<div
                  class='demo'
                  data-demo='select'
                ><h3 class='demo-name'>Select</h3><div class='demo-body'>
                    <Select @options={{this.options}} @placeholder='Select' />
                  </div></div>{{/if}}
              {{#if (this.show 'nativeselect')}}<div
                  class='demo'
                  data-demo='nativeselect'
                ><h3 class='demo-name'>NativeSelect</h3><div class='demo-body'>
                    <NativeSelect
                      @options={{this.options}}
                      @placeholder='Native'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'combobox')}}<div
                  class='demo'
                  data-demo='combobox'
                ><h3 class='demo-name'>Combobox</h3><div class='demo-body'>
                    <Combobox
                      @options={{this.options}}
                      @placeholder='Combobox'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'datepicker')}}<div
                  class='demo'
                  data-demo='datepicker'
                ><h3 class='demo-name'>DatePicker</h3><div class='demo-body'>
                    <DatePicker />
                  </div></div>{{/if}}
              {{#if (this.show 'daterangepicker')}}<div
                  class='demo'
                  data-demo='daterangepicker'
                  data-span='full'
                ><h3 class='demo-name'>DateRangePicker</h3><div
                    class='demo-body'
                  >
                    <DateRangePicker />
                  </div></div>{{/if}}
              {{#if (this.show 'rating')}}<div
                  class='demo'
                  data-demo='rating'
                ><h3 class='demo-name'>Rating</h3><div class='demo-body'>
                    <Rating @value={{3}} />
                  </div></div>{{/if}}
              {{#if (this.show 'filetrigger')}}<div
                  class='demo'
                  data-demo='filetrigger'
                ><h3 class='demo-name'>FileTrigger</h3><div class='demo-body'>
                    <FileTrigger @label='Choose file' />
                  </div></div>{{/if}}
              {{#if (this.show 'copybutton')}}<div
                  class='demo'
                  data-demo='copybutton'
                ><h3 class='demo-name'>CopyButton</h3><div class='demo-body'>
                    <CopyButton @text='Copied' @label='Copy' />
                  </div></div>{{/if}}
            </div>
            {{#if (this.show 'calendar')}}<div
                class='demo'
                data-demo='calendar'
                data-span='full'
              ><h3 class='demo-name'>Calendar</h3><div class='demo-body'>
                  <Calendar />
                </div></div>{{/if}}
            <div class='row'>
              {{#if (this.show 'propertyrow')}}<div
                  class='demo'
                  data-demo='propertyrow'
                ><h3 class='demo-name'>PropertyRow</h3><div class='demo-body'>
                    <PropertyRow @label='Property'>
                      <:default as |controlId|>
                        <Input id={{controlId}} @placeholder='Value' />
                      </:default>
                    </PropertyRow>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'multiselect')}}<div
                  class='demo'
                  data-demo='multiselect'
                ><h3 class='demo-name'>MultiSelect</h3><div class='demo-body'>
                    <MultiSelect
                      @options={{this.options}}
                      @placeholder='Multi select'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'autocomplete')}}<div
                  class='demo'
                  data-demo='autocomplete'
                ><h3 class='demo-name'>Autocomplete</h3><div class='demo-body'>
                    <Autocomplete
                      @options={{this.acItems}}
                      @placeholder='Autocomplete'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'cascader')}}<div
                  class='demo'
                  data-demo='cascader'
                ><h3 class='demo-name'>Cascader</h3><div class='demo-body'>
                    <Cascader
                      @options={{this.cascade}}
                      @placeholder='Cascader'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'emailinput')}}<div
                  class='demo'
                  data-demo='emailinput'
                ><h3 class='demo-name'>EmailInput</h3><div class='demo-body'>
                    <EmailInput @placeholder='Email' />
                  </div></div>{{/if}}
              {{#if (this.show 'urlinput')}}<div
                  class='demo'
                  data-demo='urlinput'
                ><h3 class='demo-name'>UrlInput</h3><div class='demo-body'>
                    <UrlInput @placeholder='URL' />
                  </div></div>{{/if}}
              {{#if (this.show 'phoneinput')}}<div
                  class='demo'
                  data-demo='phoneinput'
                ><h3 class='demo-name'>PhoneInput</h3><div class='demo-body'>
                    <PhoneInput @placeholder='Phone' />
                  </div></div>{{/if}}
              {{#if (this.show 'otpinput')}}<div
                  class='demo'
                  data-demo='otpinput'
                ><h3 class='demo-name'>OtpInput</h3><div class='demo-body'>
                    <OtpInput @length={{4}} @label='One-time code' />
                  </div></div>{{/if}}
              {{#if (this.show 'rangeslider')}}<div
                  class='demo'
                  data-demo='rangeslider'
                ><h3 class='demo-name'>RangeSlider</h3><div class='demo-body'>
                    <RangeSlider @label='Range' />
                  </div></div>{{/if}}
              {{#if (this.show 'timeinput')}}<div
                  class='demo'
                  data-demo='timeinput'
                ><h3 class='demo-name'>TimeInput</h3><div class='demo-body'>
                    <TimeInput @defaultValue='09:30' @label='Time' />
                  </div></div>{{/if}}
              {{#if (this.show 'editinplace')}}<div
                  class='demo'
                  data-demo='editinplace'
                ><h3 class='demo-name'>EditInPlace</h3><div class='demo-body'>
                    <EditInPlace @value='Edit me' @label='Edit in place' />
                  </div></div>{{/if}}
              {{#if (this.show 'editable')}}<div
                  class='demo'
                  data-demo='editable'
                ><h3 class='demo-name'>Editable</h3><div class='demo-body'>
                    <Editable @defaultValue='Editable' @label='Editable' />
                  </div></div>{{/if}}
              {{#if (this.show 'interactiveinput')}}
                <InteractiveInput
                  @prompt='Pick one'
                  @options={{this.options}}
                />
              {{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'composer')}}<div
                  class='demo'
                  data-demo='composer'
                ><h3 class='demo-name'>Composer</h3><div class='demo-body'>
                    <Composer @placeholder='Write a message' />
                  </div></div>{{/if}}
              {{#if (this.show 'duelingpicklist')}}<div
                  class='demo'
                  data-demo='duelingpicklist'
                ><h3 class='demo-name'>DuelingPicklist</h3><div
                    class='demo-body'
                  >
                    <DuelingPicklist @options={{this.records}} />
                  </div></div>{{/if}}
              {{#if (this.show 'knowndate')}}<div
                  class='demo'
                  data-demo='knowndate'
                ><h3 class='demo-name'>KnownDate</h3><div class='demo-body'>
                    <KnownDate @label='Known date' />
                  </div></div>{{/if}}
              {{#if (this.show 'lookup')}}<div
                  class='demo'
                  data-demo='lookup'
                ><h3 class='demo-name'>Lookup</h3><div class='demo-body'>
                    <Lookup @records={{this.records}} @label='Lookup' />
                  </div></div>{{/if}}
              {{#if (this.show 'linegrid')}}<div
                  class='demo'
                  data-demo='linegrid'
                ><h3 class='demo-name'>LineGrid</h3><div class='demo-body'>
                    <LineGrid
                      @label='Line grid'
                      @columns={{this.lineCols}}
                      @rows={{this.lineRows}}
                      @onChange={{this.noop}}
                    />
                  </div></div>{{/if}}
            </div>
            <div class='row'>

              {{#if (this.show 'periodinput')}}<div
                  class='demo'
                  data-demo='periodinput'
                ><h3 class='demo-name'>PeriodInput</h3><div class='demo-body'>
                    <PeriodInput @label='Period' />
                  </div></div>{{/if}}
              {{#if (this.show 'pipscale')}}<div
                  class='demo'
                  data-demo='pipscale'
                ><h3 class='demo-name'>PipScale</h3><div class='demo-body'>
                    <PipScale @min={{0}} @max={{10}} />
                  </div></div>{{/if}}

              {{#if (this.show 'datetimepicker')}}<div
                  class='demo'
                  data-demo='datetimepicker'
                ><h3 class='demo-name'>DateTimePicker</h3><div
                    class='demo-body'
                  >
                    <DateTimePicker @label='Date and time' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'angledial')}}<div
                  class='demo'
                  data-demo='angledial'
                ><h3 class='demo-name'>AngleDial</h3><div class='demo-body'>
                    <AngleDial @defaultValue={{45}} @label='Angle' />
                  </div></div>{{/if}}
              {{#if (this.show 'scrubinput')}}<div
                  class='demo'
                  data-demo='scrubinput'
                ><h3 class='demo-name'>ScrubInput</h3><div class='demo-body'>
                    <ScrubInput @defaultValue={{10}} @label='Scrub' />
                  </div></div>{{/if}}
              {{#if (this.show 'joystick')}}<div
                  class='demo'
                  data-demo='joystick'
                ><h3 class='demo-name'>Joystick</h3><div class='demo-body'>
                    <Joystick @label='Joystick' />
                  </div></div>{{/if}}
              {{#if (this.show 'origingrid')}}<div
                  class='demo'
                  data-demo='origingrid'
                ><h3 class='demo-name'>OriginGrid</h3><div class='demo-body'>
                    <OriginGrid @label='Origin' />
                  </div></div>{{/if}}
              {{#if (this.show 'easingcurve')}}<div
                  class='demo'
                  data-demo='easingcurve'
                ><h3 class='demo-name'>EasingCurve</h3><div class='demo-body'>
                    <EasingCurve @label='Easing' />
                  </div></div>{{/if}}
              {{#if (this.show 'tagsinput')}}<div
                  class='demo'
                  data-demo='tagsinput'
                ><h3 class='demo-name'>TagsInput</h3><div class='demo-body'>
                    <TagsInput @defaultValue={{this.tags}} @label='Tags' />
                  </div></div>{{/if}}
              {{#if (this.show 'tokeninput')}}<div
                  class='demo'
                  data-demo='tokeninput'
                ><h3 class='demo-name'>TokenInput</h3><div class='demo-body'>
                    <TokenInput @defaultValue={{this.tags}} @label='Tokens' />
                  </div></div>{{/if}}

              {{#if (this.show 'valueinput')}}<div
                  class='demo'
                  data-demo='valueinput'
                ><h3 class='demo-name'>ValueInput</h3><div class='demo-body'>
                    <ValueInput @kind='number' />
                  </div></div>{{/if}}
              {{#if (this.show 'propertysheet')}}<div
                  class='demo'
                  data-demo='propertysheet'
                  data-span='2'
                ><h3 class='demo-name'>PropertySheet</h3><div class='demo-body'>
                    <PropertySheet
                      @specs={{this.sheetSpecs}}
                      @values={{this.sheetValues}}
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'formfield')}}<div
                  class='demo'
                  data-demo='formfield'
                ><h3 class='demo-name'>FormField</h3><div class='demo-body'>
                    <FormField @label='Form field'>
                      <Input @placeholder='Value' />
                    </FormField>
                  </div></div>{{/if}}
              {{#if (this.show 'handle')}}<div
                  class='demo'
                  data-demo='handle'
                ><h3 class='demo-name'>Handle</h3><div class='demo-body'>
                    <Handle @label='Handle' />
                  </div></div>{{/if}}

            </div>
            <div class='row'>
              {{#if (this.show 'expressionbuilder')}}
                <ExpressionBuilder @title='Expression' />
              {{/if}}
              {{#if (this.show 'filterset')}}<div
                  class='demo'
                  data-demo='filterset'
                ><h3 class='demo-name'>FilterSet</h3><div class='demo-body'>
                    <FilterSet @conditions={{this.noItems}} @title='Filters' />
                  </div></div>{{/if}}
              {{#if (this.show 'fileupload')}}<div
                  class='demo'
                  data-demo='fileupload'
                ><h3 class='demo-name'>FileUpload</h3><div class='demo-body'>
                    <FileUpload @files={{this.noItems}} @label='Upload files' />
                  </div></div>{{/if}}
              {{#if (this.show 'dropzone')}}<div
                  class='demo'
                  data-demo='dropzone'
                ><h3 class='demo-name'>Dropzone</h3><div class='demo-body'>
                    <Dropzone @label='Drop files' />
                  </div></div>{{/if}}
              {{#if (this.show 'mentions')}}<div
                  class='demo'
                  data-demo='mentions'
                ><h3 class='demo-name'>Mentions</h3><div class='demo-body'>
                    <Mentions @items={{this.mentionItems}} @label='Mentions' />
                  </div></div>{{/if}}
              {{#if (this.show 'treeselect')}}<div
                  class='demo'
                  data-demo='treeselect'
                ><h3 class='demo-name'>TreeSelect</h3><div class='demo-body'>
                    <TreeSelect
                      @nodes={{this.treeNodes}}
                      @placeholder='Tree select'
                    />
                  </div></div>{{/if}}
            </div>
            <div class='row'>

              {{#if (this.show 'recorddetail')}}<div
                  class='demo'
                  data-demo='recorddetail'
                ><h3 class='demo-name'>RecordDetail</h3><div class='demo-body'>
                    <RecordDetail @columns={{2}} @summary={{false}} as |R|>
                      <R.Field @path='Name' @label='Name' @value='Acme' />
                      <R.Field @path='Owner' @label='Owner' @value='Ada' />
                    </RecordDetail>
                  </div></div>{{/if}}
              {{#if (this.show 'rulerow')}}<div
                  class='demo'
                  data-demo='rulerow'
                ><h3 class='demo-name'>RuleRow</h3><div class='demo-body'>
                    <RuleRow @rule={{this.rule}} @readonly={{true}} />
                  </div></div>{{/if}}
            </div>
          </section>
        {{/if}}

        {{#if (this.showSection 'nav2')}}
          <section aria-labelledby='s-nav2'>
            <h2 id='s-nav2'>More navigation</h2>
            {{#if (this.show 'breadcrumb')}}<div
                class='demo'
                data-demo='breadcrumb'
                data-span='2'
              ><h3 class='demo-name'>Breadcrumb</h3><div class='demo-body'>
                  <Breadcrumb @items={{this.crumbs}} />
                </div></div>{{/if}}
            {{#if (this.show 'pagination')}}<div
                class='demo'
                data-demo='pagination'
                data-span='2'
              ><h3 class='demo-name'>Pagination</h3><div class='demo-body'>
                  <Pagination @pages={{8}} @defaultPage={{3}} />
                </div></div>{{/if}}
            {{#if (this.show 'steplist')}}<div
                class='demo'
                data-demo='steplist'
                data-span='2'
              ><h3 class='demo-name'>StepList</h3><div class='demo-body'>
                  <StepList @steps={{this.steps}} />
                </div></div>{{/if}}
            {{#if (this.show 'filterchips')}}<div
                class='demo'
                data-demo='filterchips'
                data-span='2'
              ><h3 class='demo-name'>FilterChips</h3><div class='demo-body'>
                  <FilterChips @options={{this.filters}} @defaultValue='all' />
                </div></div>{{/if}}
            {{#if (this.show 'buttongroup')}}<div
                class='demo'
                data-demo='buttongroup'
              ><h3 class='demo-name'>ButtonGroup</h3><div class='demo-body'>
                  <ButtonGroup @label='Group'>
                    <Button>One</Button>
                    <Button>Two</Button>
                    <Button>Three</Button>
                  </ButtonGroup>
                </div></div>{{/if}}
          </section>
        {{/if}}

        {{#if (this.showSection 'data')}}
          <section aria-labelledby='s-data'>
            <h2 id='s-data'>Data</h2>
            {{#if (this.show 'datatable')}}<div
                class='demo'
                data-demo='datatable'
                data-span='full'
              ><h3 class='demo-name'>DataTable</h3><div class='demo-body'>
                  <DataTable
                    @columns={{this.columns}}
                    @rows={{this.rows}}
                    @caption='Team'
                  />
                </div></div>{{/if}}
            {{#if (this.show 'table')}}<div
                class='demo'
                data-demo='table'
                data-span='full'
              ><h3 class='demo-name'>Table</h3><div class='demo-body'>
                  <Table @caption='Table'>
                    <:head><tr><th>Name</th><th>Role</th></tr></:head>
                    <:body>
                      {{#each this.rows as |row|}}
                        <tr><td>{{row.name}}</td><td>{{row.role}}</td></tr>
                      {{/each}}
                    </:body>
                  </Table>
                </div></div>{{/if}}
            <div class='cols'>
              {{#if (this.show 'descriptions')}}<div
                  class='demo'
                  data-demo='descriptions'
                  data-span='2'
                ><h3 class='demo-name'>Descriptions</h3><div class='demo-body'>
                    <Descriptions @items={{this.items}} @title='Descriptions' />
                  </div></div>{{/if}}
              {{#if (this.show 'keyvalue')}}<div
                  class='demo'
                  data-demo='keyvalue'
                  data-span='2'
                ><h3 class='demo-name'>KeyValue</h3><div class='demo-body'>
                    <KeyValue @items={{this.kv}} />
                  </div></div>{{/if}}
              {{#if (this.show 'timeline')}}<div
                  class='demo'
                  data-demo='timeline'
                  data-span='full'
                ><h3 class='demo-name'>Timeline</h3><div class='demo-body'>
                    <Timeline @events={{this.events}} @label='Timeline' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'delta')}}<div class='demo' data-demo='delta'><h3
                    class='demo-name'
                  >Delta</h3><div class='demo-body'>
                    <Delta @value={{0.12}} />
                    <Delta @value={{-0.04}} />
                  </div></div>{{/if}}
              {{#if (this.show 'formatdate')}}<div
                  class='demo'
                  data-demo='formatdate'
                ><h3 class='demo-name'>FormatDate</h3><div class='demo-body'>
                    <FormatDate @date='2026-10-26' @dateStyle='long' />
                  </div></div>{{/if}}
              {{#if (this.show 'formatnumber')}}<div
                  class='demo'
                  data-demo='formatnumber'
                ><h3 class='demo-name'>FormatNumber</h3><div class='demo-body'>
                    <FormatNumber
                      @value={{1234.5}}
                      @style='currency'
                      @currency='USD'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'formattedvalue')}}<div
                  class='demo'
                  data-demo='formattedvalue'
                ><h3 class='demo-name'>FormattedValue</h3><div
                    class='demo-body'
                  >
                    <FormattedValue @text='Formatted' />
                  </div></div>{{/if}}
              {{#if (this.show 'relativetime')}}<div
                  class='demo'
                  data-demo='relativetime'
                ><h3 class='demo-name'>RelativeTime</h3><div class='demo-body'>
                    <RelativeTime
                      @date='2026-10-20T00:00:00Z'
                      @now='2026-10-26T00:00:00Z'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'odometer')}}<div
                  class='demo'
                  data-demo='odometer'
                ><h3 class='demo-name'>Odometer</h3><div class='demo-body'>
                    <Odometer @value={{4821}} />
                  </div></div>{{/if}}
              {{#if (this.show 'token')}}<div class='demo' data-demo='token'><h3
                    class='demo-name'
                  >Token</h3><div class='demo-body'>
                    <Token @value='token-value' />
                  </div></div>{{/if}}
              {{#if (this.show 'brokenlink')}}<div
                  class='demo'
                  data-demo='brokenlink'
                ><h3 class='demo-name'>BrokenLink</h3><div class='demo-body'>
                    <BrokenLink @label='Missing' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'sparkline')}}<div
                  class='demo'
                  data-demo='sparkline'
                ><h3 class='demo-name'>Sparkline</h3><div class='demo-body'>
                    <Sparkline @values={{this.spark}} @label='Trend' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'datagrid')}}<div
                  class='demo'
                  data-demo='datagrid'
                  data-span='full'
                ><h3 class='demo-name'>DataGrid</h3><div class='demo-body'>
                    <DataGrid
                      @columns={{this.gridColumns}}
                      @rows={{this.rows}}
                      @rowKey='name'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'feed')}}<div
                  class='demo'
                  data-demo='feed'
                  data-span='full'
                ><h3 class='demo-name'>Feed</h3><div class='demo-body'>
                    <Feed @items={{this.feedItems}} @label='Activity'>
                      <:item as |item|>{{item.label}}</:item>
                    </Feed>
                  </div></div>{{/if}}
              {{#if (this.show 'masonry')}}<div
                  class='demo'
                  data-demo='masonry'
                  data-span='full'
                ><h3 class='demo-name'>Masonry</h3><div class='demo-body'>
                    <Masonry @items={{this.items}} @columns={{2}}>
                      <:item as |item|>{{item.label}}</:item>
                    </Masonry>
                  </div></div>{{/if}}
              {{#if (this.show 'grid')}}<div class='demo' data-demo='grid'><h3
                    class='demo-name'
                  >Grid</h3><div class='demo-body'>
                    <Grid @items={{this.items}} as |item|>{{item.label}}</Grid>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'formatbytes')}}<div
                  class='demo'
                  data-demo='formatbytes'
                ><h3 class='demo-name'>FormatBytes</h3><div class='demo-body'>
                    <FormatBytes @value={{1536000}} />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'aiinstructions')}}<div
                  class='demo'
                  data-demo='aiinstructions'
                ><h3 class='demo-name'>AiInstructions</h3><div
                    class='demo-body'
                  >
                    <AiInstructions
                      @instructions={{this.aiRules}}
                      @title='Instructions'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'codeblock')}}<div
                  class='demo'
                  data-demo='codeblock'
                ><h3 class='demo-name'>CodeBlock</h3><div class='demo-body'>
                    <CodeBlock
                      @code='const a = 1;'
                      @language='ts'
                      @filename='a.ts'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'diffblock')}}<div
                  class='demo'
                  data-demo='diffblock'
                ><h3 class='demo-name'>DiffBlock</h3><div class='demo-body'>
                    <DiffBlock @lines={{this.diffLines}} />
                  </div></div>{{/if}}
              {{#if (this.show 'featurevoting')}}<div
                  class='demo'
                  data-demo='featurevoting'
                ><h3 class='demo-name'>FeatureVoting</h3><div class='demo-body'>
                    <FeatureVoting
                      @features={{this.votes}}
                      @title='Feature voting'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'filmstrip')}}<div
                  class='demo'
                  data-demo='filmstrip'
                  data-span='2'
                ><h3 class='demo-name'>Filmstrip</h3><div class='demo-body'>
                    <Filmstrip @frames={{this.frames}} @label='Filmstrip' />
                  </div></div>{{/if}}
              {{#if (this.show 'graphoutline')}}<div
                  class='demo'
                  data-demo='graphoutline'
                ><h3 class='demo-name'>GraphOutline</h3><div class='demo-body'>
                    <GraphOutline
                      @nodes={{this.gNodes}}
                      @edges={{this.gEdges}}
                      @label='Graph'
                      @mode='visible'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'layermanager')}}<div
                  class='demo'
                  data-demo='layermanager'
                  data-span='2'
                ><h3 class='demo-name'>LayerManager</h3><div class='demo-body'>
                    <LayerManager @layers={{this.layerNodes}} />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'statementtable')}}<div
                  class='demo'
                  data-demo='statementtable'
                  data-span='full'
                ><h3 class='demo-name'>StatementTable</h3><div
                    class='demo-body'
                  >
                    <StatementTable
                      @caption='Statement'
                      @columns={{this.stmtCols}}
                      @rows={{this.stmtRows}}
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'docreport')}}<div
                  class='demo'
                  data-demo='docreport'
                ><h3 class='demo-name'>DocReport</h3><div class='demo-body'>
                    <DocReport @title='Report' @eyebrow='Eyebrow'>Report body</DocReport>
                  </div></div>{{/if}}
              {{#if (this.show 'promptlibrary')}}<div
                  class='demo'
                  data-demo='promptlibrary'
                ><h3 class='demo-name'>PromptLibrary</h3><div class='demo-body'>
                    <PromptLibrary @prompts={{this.prompts}} @title='Prompts' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'jsontree')}}<div
                  class='demo'
                  data-demo='jsontree'
                ><h3 class='demo-name'>JsonTree</h3><div class='demo-body'>
                    <JsonTree @json={{this.jsonText}} @label='JSON' />
                  </div></div>{{/if}}
              {{#if (this.show 'jsoneditor')}}<div
                  class='demo'
                  data-demo='jsoneditor'
                  data-span='full'
                ><h3 class='demo-name'>JsonEditor</h3><div class='demo-body'>
                    <JsonEditor @json={{this.jsonText}} @label='JSON editor' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'barlist')}}<div
                  class='demo'
                  data-demo='barlist'
                  data-span='2'
                ><h3 class='demo-name'>BarList</h3><div class='demo-body'>
                    <BarList
                      @rows={{this.barRows}}
                      @label='Traffic by source'
                    />
                  </div></div>{{/if}}

              {{#if (this.show 'board')}}<div
                  class='demo'
                  data-demo='board'
                  data-span='full'
                ><h3 class='demo-name'>Board</h3><div class='demo-body'>
                    <div class='board-stage'>
                      <Board
                        @columns={{this.boardColumns}}
                        @placements={{this.boardPlacements}}
                        @boardLabel='Board'
                      >
                        <:card as |placement|>{{get
                            this.boardTitles
                            placement.index
                          }}</:card>
                      </Board>
                    </div>
                  </div></div>{{/if}}
              {{#if (this.show 'list')}}<div
                  class='demo'
                  data-demo='list'
                  data-span='2'
                ><h3 class='demo-name'>List</h3><div class='demo-body'>
                    <List
                      @items={{this.records}}
                      @label='Records'
                      @bordered={{true}}
                    >
                      <:item as |row|>{{row.label}}</:item>
                    </List>
                  </div></div>{{/if}}
            </div>
          </section>
        {{/if}}

        {{#if (this.showSection 'surfaces')}}
          <section aria-labelledby='s-surfaces'>
            <h2 id='s-surfaces'>Surfaces and states</h2>
            <div class='cols'>
              {{#if (this.show 'panel')}}<div class='demo' data-demo='panel'><h3
                    class='demo-name'
                  >Panel</h3><div class='demo-body'>
                    <Panel @title='Panel' @eyebrow='Eyebrow'>Panel body</Panel>
                  </div></div>{{/if}}
              {{#if (this.show 'collapsible')}}<div
                  class='demo'
                  data-demo='collapsible'
                ><h3 class='demo-name'>Collapsible</h3><div class='demo-body'>
                    <Collapsible @label='Collapsible' @defaultOpen={{true}}>
                      Collapsible body
                    </Collapsible>
                  </div></div>{{/if}}
              {{#if (this.show 'emptystate')}}<div
                  class='demo'
                  data-demo='emptystate'
                ><h3 class='demo-name'>EmptyState</h3><div class='demo-body'>
                    <EmptyState
                      @title='Nothing here'
                      @message='Empty state message'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'loadingstate')}}<div
                  class='demo'
                  data-demo='loadingstate'
                ><h3 class='demo-name'>LoadingState</h3><div class='demo-body'>
                    <LoadingState @label='Loading' />
                  </div></div>{{/if}}
              {{#if (this.show 'cue')}}<div class='demo' data-demo='cue'><h3
                    class='demo-name'
                  >Cue</h3><div class='demo-body'>
                    <Cue @text='Cue' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'tooltip')}}<div
                  class='demo'
                  data-demo='tooltip'
                ><h3 class='demo-name'>Tooltip</h3><div class='demo-body'>
                    <Tooltip @content='Tooltip text'>
                      <Button>Hover me</Button>
                    </Tooltip>
                  </div></div>{{/if}}
              {{#if (this.show 'popover')}}<div
                  class='demo'
                  data-demo='popover'
                  data-span='2'
                ><h3 class='demo-name'>Popover</h3><div class='demo-body'>
                    <Popover @label='Popover'>
                      <:trigger as |open toggle|>
                        <Button {{on 'click' toggle}}>
                          {{if open 'Close' 'Open'}}
                          popover
                        </Button>
                      </:trigger>
                      <:default>Popover content</:default>
                    </Popover>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'toolbar')}}<div
                  class='demo'
                  data-demo='toolbar'
                  data-span='2'
                ><h3 class='demo-name'>Toolbar</h3><div class='demo-body'>
                    <Toolbar @title='Toolbar' @eyebrow='Eyebrow' @meta='Meta'>
                      <Button>Action</Button>
                    </Toolbar>
                  </div></div>{{/if}}
              {{#if (this.show 'actionbar')}}<div
                  class='demo'
                  data-demo='actionbar'
                ><h3 class='demo-name'>ActionBar</h3><div class='demo-body'>
                    <ActionBar
                      @count={{2}}
                      @total={{8}}
                      @position='inline'
                      @actions={{this.barActions}}
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'aspectratio')}}<div
                  class='demo'
                  data-demo='aspectratio'
                ><h3 class='demo-name'>AspectRatio</h3><div class='demo-body'>
                    <AspectRatio @ratio='16/9' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'card')}}<div class='demo' data-demo='card'><h3
                    class='demo-name'
                  >Card</h3><div class='demo-body'>
                    <Card @title='Card' @description='Card description'>Card
                      body</Card>
                  </div></div>{{/if}}
              {{#if (this.show 'panelsection')}}<div
                  class='demo'
                  data-demo='panelsection'
                ><h3 class='demo-name'>PanelSection</h3><div class='demo-body'>
                    <PanelSection
                      @title='Panel section'
                      @collapsible={{true}}
                      @defaultOpen={{true}}
                    >Section body</PanelSection>
                  </div></div>{{/if}}
              {{#if (this.show 'fold')}}<div class='demo' data-demo='fold'><h3
                    class='demo-name'
                  >Fold</h3><div class='demo-body'>
                    <Fold @receipt='3 steps done'>Folded content</Fold>
                  </div></div>{{/if}}
              {{#if (this.show 'stack')}}<div class='demo' data-demo='stack'><h3
                    class='demo-name'
                  >Stack</h3><div class='demo-body'>
                    <Stack @gap='sm'><Chip @label='One' /><Chip
                        @label='Two'
                      /></Stack>
                  </div></div>{{/if}}
              {{#if (this.show 'stackdivider')}}<div
                  class='demo'
                  data-demo='stackdivider'
                ><h3 class='demo-name'>StackDivider</h3><div class='demo-body'>
                    <StackDivider />
                  </div></div>{{/if}}
              {{#if (this.show 'resultcard')}}<div
                  class='demo'
                  data-demo='resultcard'
                ><h3 class='demo-name'>ResultCard</h3><div class='demo-body'>
                    <ResultCard
                      @eyebrow='Eyebrow'
                      @title='Result'
                      @lines={{this.lines}}
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'workitem')}}<div
                  class='demo'
                  data-demo='workitem'
                ><h3 class='demo-name'>WorkItem</h3><div class='demo-body'>
                    <WorkItem @title='Work item' @status='Running' />
                  </div></div>{{/if}}
              {{#if (this.show 'loadingoverlay')}}<div
                  class='demo'
                  data-demo='loadingoverlay'
                ><h3 class='demo-name'>LoadingOverlay</h3><div
                    class='demo-body'
                  >
                    <LoadingOverlay @open={{true}} @label='Loading'>Overlay body</LoadingOverlay>
                  </div></div>{{/if}}
              {{#if (this.show 'alertdialog')}}<div
                  class='demo'
                  data-demo='alertdialog'
                  data-span='2'
                ><h3 class='demo-name'>AlertDialog</h3><div class='demo-body'>
                    <AlertDialog
                      @title='Delete?'
                      @description='This cannot be undone.'
                      @tone='danger'
                    >
                      <:trigger as |_open toggle|>
                        <Button {{on 'click' toggle}}>Open dialog</Button>
                      </:trigger>
                    </AlertDialog>
                  </div></div>{{/if}}
              {{#if (this.show 'approvalfooter')}}<div
                  class='demo'
                  data-demo='approvalfooter'
                ><h3 class='demo-name'>ApprovalFooter</h3><div
                    class='demo-body'
                  >
                    <ApprovalFooter
                      @count={{3}}
                      @message='3 changes to review'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'skiplink')}}<div
                  class='demo'
                  data-demo='skiplink'
                ><h3 class='demo-name'>SkipLink</h3><div class='demo-body'>
                    <SkipLink @href='#main' @label='Skip to content' />
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'contextmenu')}}<div
                  class='demo'
                  data-demo='contextmenu'
                ><h3 class='demo-name'>ContextMenu</h3><div class='demo-body'>
                    <ContextMenu
                      @items={{this.menuLeaf}}
                      @label='Context menu'
                    >Right-click here</ContextMenu>
                  </div></div>{{/if}}
              {{#if (this.show 'dynamicisland')}}<div
                  class='demo'
                  data-demo='dynamicisland'
                ><h3 class='demo-name'>DynamicIsland</h3><div class='demo-body'>
                    <DynamicIsland @defaultView='compact' @label='Island'>
                      <:compact>Compact</:compact>
                      <:expanded>Expanded</:expanded>
                      <:idle>Idle</:idle>
                    </DynamicIsland>
                  </div></div>{{/if}}
              {{#if (this.show 'floatbutton')}}<div
                  class='demo'
                  data-demo='floatbutton'
                ><h3 class='demo-name'>FloatButton</h3><div class='demo-body'>
                    <FloatButton @label='Add' @position='absolute' />
                  </div></div>{{/if}}
              {{#if (this.show 'scroller')}}<div
                  class='demo'
                  data-demo='scroller'
                ><h3 class='demo-name'>Scroller</h3><div class='demo-body'>
                    <Scroller @label='Scroller'>Scrollable content</Scroller>
                  </div></div>{{/if}}
              {{#if (this.show 'scrollprogress')}}<div
                  class='demo'
                  data-demo='scrollprogress'
                ><h3 class='demo-name'>ScrollProgress</h3><div
                    class='demo-body'
                  >
                    <ScrollProgress
                      @source='nearest'
                      @label='Scroll progress'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'inview')}}<div
                  class='demo'
                  data-demo='inview'
                ><h3 class='demo-name'>InView</h3><div class='demo-body'>
                    <InView>In view content</InView>
                  </div></div>{{/if}}
              {{#if (this.show 'presence')}}<div
                  class='demo'
                  data-demo='presence'
                ><h3 class='demo-name'>Presence</h3><div class='demo-body'>
                    <Presence @show={{true}}>Presence content</Presence>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'queuedmessage')}}<div
                  class='demo'
                  data-demo='queuedmessage'
                ><h3 class='demo-name'>QueuedMessage</h3><div class='demo-body'>
                    <QueuedMessage @text='Queued message' />
                  </div></div>{{/if}}
              {{#if (this.show 'sessionprep')}}<div
                  class='demo'
                  data-demo='sessionprep'
                ><h3 class='demo-name'>SessionPrep</h3><div class='demo-body'>
                    <SessionPrep
                      @steps={{this.prepSteps}}
                      @title='Session prep'
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'terminalanimation')}}
                <TerminalAnimation
                  @lines={{this.termLines}}
                  @title='Terminal'
                />
              {{/if}}
              {{#if (this.show 'viewport')}}<div
                  class='demo'
                  data-demo='viewport'
                ><h3 class='demo-name'>Viewport</h3><div class='demo-body'>
                    <Viewport>Viewport content</Viewport>
                  </div></div>{{/if}}
              {{#if (this.show 'defer')}}<div class='demo' data-demo='defer'><h3
                    class='demo-name'
                  >Defer</h3><div class='demo-body'>
                    <Defer @trigger='visible'>Deferred content</Defer>
                  </div></div>{{/if}}
              {{#if (this.show 'scrollarea')}}<div
                  class='demo'
                  data-demo='scrollarea'
                ><h3 class='demo-name'>ScrollArea</h3><div class='demo-body'>
                    <ScrollArea @label='Scroll area'>Scroll area content</ScrollArea>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'reorder')}}<div
                  class='demo'
                  data-demo='reorder'
                ><h3 class='demo-name'>Reorder</h3><div class='demo-body'>
                    <Reorder
                      @items={{this.pickNames}}
                      @label='Reorder'
                      as |item|
                    >{{item}}</Reorder>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'affix')}}<div class='demo' data-demo='affix'><h3
                    class='demo-name'
                  >Affix</h3><div class='demo-body'>
                    <Affix>Affix content</Affix>
                  </div></div>{{/if}}
              {{#if (this.show 'zoomableframe')}}<div
                  class='demo'
                  data-demo='zoomableframe'
                ><h3 class='demo-name'>ZoomableFrame</h3><div class='demo-body'>
                    <ZoomableFrame @label='Zoomable'>Zoomable content</ZoomableFrame>
                  </div></div>{{/if}}
              {{#if (this.show 'hoveractions')}}<div
                  class='demo'
                  data-demo='hoveractions'
                ><h3 class='demo-name'>HoverActions</h3><div class='demo-body'>
                    <HoverActions
                      @label='Row'
                      @actions={{this.hoverActions}}
                      @reveal='always'
                    >Row content</HoverActions>
                  </div></div>{{/if}}
              {{#if (this.show 'togglematrix')}}<div
                  class='demo'
                  data-demo='togglematrix'
                ><h3 class='demo-name'>ToggleMatrix</h3><div class='demo-body'>
                    <ToggleMatrix
                      @label='Permissions'
                      @rows={{this.matrixRows}}
                      @columns={{this.matrixCols}}
                    />
                  </div></div>{{/if}}
              {{#if (this.show 'hovercard')}}<div
                  class='demo'
                  data-demo='hovercard'
                ><h3 class='demo-name'>HoverCard</h3><div class='demo-body'>
                    <HoverCard>
                      <:trigger>Hover me</:trigger>
                      <:default>Card content</:default>
                    </HoverCard>
                  </div></div>{{/if}}
              {{#if (this.show 'popconfirm')}}<div
                  class='demo'
                  data-demo='popconfirm'
                ><h3 class='demo-name'>Popconfirm</h3><div class='demo-body'>
                    <Popconfirm @title='Sure?'>
                      <:trigger as |_open toggle|>
                        <Button {{on 'click' toggle}}>Delete</Button>
                      </:trigger>
                    </Popconfirm>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'morphingdialog')}}<div
                  class='demo'
                  data-demo='morphingdialog'
                ><h3 class='demo-name'>MorphingDialog</h3><div
                    class='demo-body'
                  >
                    <MorphingDialog @label='Morphing dialog'>
                      <:trigger>Open</:trigger>
                      <:title>Title</:title>
                      <:default>Body</:default>
                    </MorphingDialog>
                  </div></div>{{/if}}
              {{#if (this.show 'morphingpopover')}}<div
                  class='demo'
                  data-demo='morphingpopover'
                ><h3 class='demo-name'>MorphingPopover</h3><div
                    class='demo-body'
                  >
                    <MorphingPopover @label='Morphing popover'>
                      <:trigger>Open</:trigger>
                      <:default>Content</:default>
                    </MorphingPopover>
                  </div></div>{{/if}}
              {{#if (this.show 'dock')}}<div class='demo' data-demo='dock'><h3
                    class='demo-name'
                  >Dock</h3><div class='demo-body'>
                    <Dock @label='Dock' as |d|>
                      <d.Item @label='One'>1</d.Item>
                      <d.Item @label='Two'>2</d.Item>
                    </Dock>
                  </div></div>{{/if}}
              {{#if (this.show 'stackingcards')}}<div
                  class='demo'
                  data-demo='stackingcards'
                ><h3 class='demo-name'>StackingCards</h3><div class='demo-body'>
                    <StackingCards as |s|>
                      <s.Card>One</s.Card>
                      <s.Card>Two</s.Card>
                    </StackingCards>
                  </div></div>{{/if}}
              {{#if (this.show 'magnetic')}}<div
                  class='demo'
                  data-demo='magnetic'
                ><h3 class='demo-name'>Magnetic</h3><div class='demo-body'>
                    <Magnetic><Button>Magnetic</Button></Magnetic>
                  </div></div>{{/if}}
              {{#if (this.show 'spotlight')}}<div
                  class='demo'
                  data-demo='spotlight'
                ><h3 class='demo-name'>Spotlight</h3><div class='demo-body'>
                    <Spotlight>Spotlight content</Spotlight>
                  </div></div>{{/if}}
              {{#if (this.show 'tilt')}}<div class='demo' data-demo='tilt'><h3
                    class='demo-name'
                  >Tilt</h3><div class='demo-body'>
                    <Tilt>Tilt content</Tilt>
                  </div></div>{{/if}}
              {{#if (this.show 'backdrop')}}<div
                  class='demo'
                  data-demo='backdrop'
                ><h3 class='demo-name'>Backdrop</h3><div class='demo-body'>
                    <Backdrop @open={{false}} />
                  </div></div>{{/if}}
              {{#if (this.show 'backgroundfield')}}<div
                  class='demo'
                  data-demo='backgroundfield'
                ><h3 class='demo-name'>BackgroundField</h3><div
                    class='demo-body'
                  >
                    <BackgroundField>Background field</BackgroundField>
                  </div></div>{{/if}}
            </div>
            <div class='row'>
              {{#if (this.show 'item')}}<div class='demo' data-demo='item'><h3
                    class='demo-name'
                  >Item</h3><div class='demo-body'>
                    <Item @title='Item title' @description='Supporting line'>
                      <:trailing>Meta</:trailing>
                    </Item>
                  </div></div>{{/if}}
              {{#if (this.show 'accordion')}}<div
                  class='demo'
                  data-demo='accordion'
                  data-span='2'
                ><h3 class='demo-name'>Accordion</h3><div class='demo-body'>
                    <Accordion @displayContainer={{true}} as |A|>
                      <A.Item
                        @id='a'
                        @isOpen={{this.accOpenA}}
                        @onClick={{this.toggleAccA}}
                      >
                        <:title>First</:title>
                        <:content>First content</:content>
                      </A.Item>
                      <A.Item
                        @id='b'
                        @isOpen={{this.accOpenB}}
                        @onClick={{this.toggleAccB}}
                      >
                        <:title>Second</:title>
                        <:content>Second content</:content>
                      </A.Item>
                    </Accordion>
                  </div></div>{{/if}}
              {{#if (this.show 'dialog')}}<div
                  class='demo'
                  data-demo='dialog'
                ><h3 class='demo-name'>Dialog</h3><div class='demo-body'>
                    <Button {{on 'click' this.openDialog}}>Open dialog</Button>
                    <Dialog
                      @open={{this.dialogOpen}}
                      @onClose={{this.closeDialog}}
                      @label='Dialog'
                    >
                      <:title>Dialog title</:title>
                      <:default>Dialog body</:default>
                      <:footer><Button
                          {{on 'click' this.closeDialog}}
                        >Close</Button></:footer>
                    </Dialog>
                  </div></div>{{/if}}
              {{#if (this.show 'drawer')}}<div
                  class='demo'
                  data-demo='drawer'
                ><h3 class='demo-name'>Drawer</h3><div class='demo-body'>
                    <Button {{on 'click' this.openDrawer}}>Open drawer</Button>
                    <Drawer
                      @open={{this.drawerOpen}}
                      @onClose={{this.closeDrawer}}
                      @label='Drawer'
                    >
                      <:title>Drawer title</:title>
                      <:default>Drawer body</:default>
                      <:footer><Button
                          {{on 'click' this.closeDrawer}}
                        >Close</Button></:footer>
                    </Drawer>
                  </div></div>{{/if}}
              {{#if (this.show 'popup')}}<div class='demo' data-demo='popup'><h3
                    class='demo-name'
                  >Popup</h3><div class='demo-body'>
                    <Popup @open={{this.popupOpen}}>
                      <:anchor><Button {{on 'click' this.togglePopup}}>Toggle
                          popup</Button></:anchor>
                      <:default>Popup content</:default>
                    </Popup>
                  </div></div>{{/if}}
              {{#if (this.show 'menu')}}<div class='demo' data-demo='menu'><h3
                    class='demo-name'
                  >Menu</h3><div class='demo-body'>
                    <Menu @items={{this.menuLeaf}} @label='Actions'>
                      <:trigger as |_open toggle|>
                        <Button {{on 'click' toggle}}>Menu</Button>
                      </:trigger>
                    </Menu>
                  </div></div>{{/if}}
              {{#if (this.show 'commandpalette')}}<div
                  class='demo'
                  data-demo='commandpalette'
                ><h3 class='demo-name'>CommandPalette</h3><div
                    class='demo-body'
                  >
                    <Button {{on 'click' this.openPalette}}>Open palette</Button>
                    <CommandPalette
                      @items={{this.menuLeaf}}
                      @open={{this.paletteOpen}}
                      @onClose={{this.closePalette}}
                      @label='Command palette'
                    />
                  </div></div>{{/if}}
            </div>
          </section>
        {{/if}}
      </main>
    </ThemeFrame>
    <style scoped>
      .showcase {
        container-type: inline-size;
        display: grid;
        gap: 2rem;
        padding: 1.5rem;
        font-family: var(--font-sans);
      }
      .category {
        max-width: 20rem;
      }
      .filter {
        max-width: 20rem;
      }
      section {
        display: grid;
        gap: 0.75rem;
      }
      h1,
      h2 {
        margin: 0;
        color: var(--foreground);
      }
      h2 {
        font-size: 1rem;
      }
      .grid,
      .cols {
        display: grid;
        gap: 0.75rem;
      }
      .cols {
        grid-template-columns: repeat(auto-fill, minmax(14rem, 1fr));
      }
      .stage {
        min-height: 12rem;
        width: 100%;
      }
      .board-stage {
        height: 20rem;
        width: 100%;
      }
      .tabs {
        position: relative;
        display: flex;
        gap: 0.25rem;
      }
      /* 12-column bento: three demos per row, wide ones two-up, big ones full */
      .row {
        display: grid;
        grid-template-columns: repeat(12, minmax(0, 1fr));
        grid-auto-flow: dense;
        align-items: start;
        gap: 0.75rem;
      }
      .row > .demo {
        grid-column: span 4;
      }
      .row > .demo[data-span='2'] {
        grid-column: span 6;
      }
      .row > .demo[data-span='full'] {
        grid-column: 1 / -1;
      }
      @container (max-width: 64rem) {
        .row > .demo {
          grid-column: span 6;
        }
      }
      @container (max-width: 40rem) {
        .row > .demo,
        .row > .demo[data-span='2'] {
          grid-column: 1 / -1;
        }
      }
      /* every demo is its own standalone card, so a demo that positions or
         sizes its parts absolutely stays inside it */
      .demo {
        position: relative;
        isolation: isolate;
        display: grid;
        gap: var(--boxel-sp-xs);
        align-content: start;
        min-width: 0;
        max-width: 100%;
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background-color: var(--card);
        color: var(--card-foreground);
        overflow: auto;
      }
      .demo-name {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .demo-body {
        display: grid;
        gap: var(--boxel-sp-xs);
        min-width: 0;
        min-height: 2.5rem;
      }
      /* demos fill the card, so a component that sizes itself from a container
         query gets a real width; small inline atoms keep their natural width */
      .demo-body > :deep(:is(button, a, kbd, label, small, i, b)) {
        justify-self: start;
      }
    </style>
  </template>
}

export class UiShowcase extends CardDef {
  static displayName = 'UI Showcase';
  // filter config, stored on the card: 'all' | 'dashboard'
  @field filterCategory = contains(StringField);
  // the single component shown, or 'all'
  @field filterComponent = contains(StringField);
  static prefersWideFormat = true;
  static isolated = Isolated;
}
