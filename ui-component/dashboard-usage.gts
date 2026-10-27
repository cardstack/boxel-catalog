// Usage page (live controls, API table, source) for each Dashboard-category
// component, keyed by component name; the showcase renders these on the
// Dashboard tab.
import type { ComponentLike } from '@glint/template';
import { DEMOS_ACCORDION } from './components/accordion.usage';
import { DEMOS_ACTION_BAR } from './components/action-bar.usage';
import { DEMOS_ALERT } from './components/alert.usage';
import { DEMOS_AVATAR_GROUP } from './components/avatar-group.usage';
import { DEMOS_AVATAR } from './components/avatar.usage';
import { DEMOS_BADGE } from './components/badge.usage';
import { DEMOS_BAR_LIST } from './components/bar-list.usage';
import { DEMOS_BOARD } from './components/board.usage';
import { DEMOS_BREADCRUMB } from './components/breadcrumb.usage';
import { DEMOS_BUTTON_GROUP } from './components/button-group.usage';
import { DEMOS_BUTTON } from './components/button.usage';
import { DEMOS_CALENDAR } from './components/calendar.usage';
import { DEMOS_CALLOUT } from './components/callout.usage';
import { DEMOS_CARD } from './components/card.usage';
import { DEMOS_CHECKBOX } from './components/checkbox.usage';
import { DEMOS_CHIP } from './components/chip.usage';
import { DEMOS_COLLAPSIBLE } from './components/collapsible.usage';
import { DEMOS_COMBOBOX } from './components/combobox.usage';
import { DEMOS_DATA_GRID } from './components/data-grid.usage';
import { DEMOS_DATA_TABLE } from './components/data-table.usage';
import { DEMOS_DATE_PICKER } from './components/date-picker.usage';
import { DEMOS_DATE_RANGE_PICKER } from './components/date-range-picker.usage';
import { DEMOS_DELTA } from './components/delta.usage';
import { DEMOS_DESCRIPTIONS } from './components/descriptions.usage';
import { DEMOS_DIALOG } from './components/dialog.usage';
import { DEMOS_DIVIDER } from './components/divider.usage';
import { DEMOS_DRAWER } from './components/drawer.usage';
import { DEMOS_DROPZONE } from './components/dropzone.usage';
import { DEMOS_EMPTY_STATE } from './components/empty-state.usage';
import { DEMOS_FEED } from './components/feed.usage';
import { DEMOS_FIELD } from './components/field.usage';
import { DEMOS_FILTER_CHIPS } from './components/filter-chips.usage';
import { DEMOS_FILTER_SET } from './components/filter-set.usage';
import { DEMOS_FORMAT_DATE } from './components/format-date.usage';
import { DEMOS_FORMAT_NUMBER } from './components/format-number.usage';
import { DEMOS_GRID } from './components/grid.usage';
import { DEMOS_ICON_BUTTON } from './components/icon-button.usage';
import { DEMOS_INPUT } from './components/input.usage';
import { DEMOS_KBD } from './components/kbd.usage';
import { DEMOS_KEY_VALUE } from './components/key-value.usage';
import { DEMOS_LIST } from './components/list.usage';
import { DEMOS_LOADING_STATE } from './components/loading-state.usage';
import { DEMOS_MENU_USAGE } from './components/menu.usage';
import { DEMOS_METER } from './components/meter.usage';
import { DEMOS_NATIVE_SELECT } from './components/native-select.usage';
import { DEMOS_NOTIFICATION } from './components/notification.usage';
import { DEMOS_ODOMETER } from './components/odometer.usage';
import { DEMOS_PAGINATION } from './components/pagination.usage';
import { DEMOS_PANEL_SECTION } from './components/panel-section.usage';
import { DEMOS_PANEL } from './components/panel.usage';
import { DEMOS_POPOVER } from './components/popover.usage';
import { DEMOS_PROGRESS_BAR } from './components/progress-bar.usage';
import { DEMOS_PROGRESS_RADIAL } from './components/progress-radial.usage';
import { DEMOS_RADIO_GROUP } from './components/radio-group.usage';
import { DEMOS_RATING } from './components/rating.usage';
import { DEMOS_READINESS_PANEL } from './components/readiness-panel.usage';
import { DEMOS_RECORD_PILL } from './components/record-pill.usage';
import { DEMOS_RELATIVE_TIME } from './components/relative-time.usage';
import { DEMOS_RESULT } from './components/result.usage';
import { DEMOS_SEARCH_INPUT } from './components/search-input.usage';
import { DEMOS_SEGMENTED_CONTROL } from './components/segmented-control.usage';
import { DEMOS_SELECT } from './components/select.usage';
import { DEMOS_SIDEBAR } from './components/sidebar.usage';
import { DEMOS_SKELETON } from './components/skeleton.usage';
import { DEMOS_SPARKLINE } from './components/sparkline.usage';
import { DEMOS_SPINNER } from './components/spinner.usage';
import { DEMOS_STACK } from './components/stack.usage';
import { DEMOS_STAT } from './components/stat.usage';
import { DEMOS_STATEMENT_TABLE } from './components/statement-table.usage';
import { DEMOS_STATUS_CHIP } from './components/status-chip.usage';
import { DEMOS_STEP_LIST } from './components/step-list.usage';
import { DEMOS_SWITCH } from './components/switch.usage';
import { DEMOS_TABLE } from './components/table.usage';
import { DEMOS_TABS } from './components/tabs.usage';
import { DEMOS_TIMELINE } from './components/timeline.usage';
import { DEMOS_TOAST } from './components/toast.usage';
import { DEMOS_TOASTER } from './components/toaster.usage';
import { DEMOS_TOGGLE_GROUP } from './components/toggle-group.usage';
import { DEMOS_TOKEN } from './components/token.usage';
import { DEMOS_TOOLBAR } from './components/toolbar.usage';
import { DEMOS_TOOLTIP } from './components/tooltip.usage';
import { DEMOS_WIZARD } from './components/wizard.usage';

export const DASHBOARD_USAGE: Record<string, ComponentLike> = {
  Stat: DEMOS_STAT.Stat as ComponentLike,
  Delta: DEMOS_DELTA.Delta as ComponentLike,
  Odometer: DEMOS_ODOMETER.Odometer as ComponentLike,
  FormatNumber: DEMOS_FORMAT_NUMBER.FormatNumber as ComponentLike,
  FormatDate: DEMOS_FORMAT_DATE.FormatDate as ComponentLike,
  RelativeTime: DEMOS_RELATIVE_TIME.RelativeTime as ComponentLike,
  DataTable: DEMOS_DATA_TABLE.DataTable as ComponentLike,
  DataGrid: DEMOS_DATA_GRID.DataGrid as ComponentLike,
  Table: DEMOS_TABLE.Table as ComponentLike,
  StatementTable: DEMOS_STATEMENT_TABLE.StatementTable as ComponentLike,
  List: DEMOS_LIST.List as ComponentLike,
  Descriptions: DEMOS_DESCRIPTIONS.Descriptions as ComponentLike,
  KeyValue: DEMOS_KEY_VALUE.KeyValue as ComponentLike,
  Timeline: DEMOS_TIMELINE.Timeline as ComponentLike,
  BarList: DEMOS_BAR_LIST.BarList as ComponentLike,
  ProgressBar: DEMOS_PROGRESS_BAR.ProgressBar as ComponentLike,
  ProgressRadial: DEMOS_PROGRESS_RADIAL.ProgressRadial as ComponentLike,
  Meter: DEMOS_METER.Meter as ComponentLike,
  Sparkline: DEMOS_SPARKLINE.Sparkline as ComponentLike,
  Pagination: DEMOS_PAGINATION.Pagination as ComponentLike,
  StatusChip: DEMOS_STATUS_CHIP.StatusChip as ComponentLike,
  Chip: DEMOS_CHIP.Chip as ComponentLike,
  Badge: DEMOS_BADGE.Badge as ComponentLike,
  Avatar: DEMOS_AVATAR.Avatar as ComponentLike,
  AvatarGroup: DEMOS_AVATAR_GROUP.AvatarGroup as ComponentLike,
  Rating: DEMOS_RATING.Rating as ComponentLike,
  RecordPill: DEMOS_RECORD_PILL.RecordPill as ComponentLike,
  Token: DEMOS_TOKEN.Token as ComponentLike,
  Panel: DEMOS_PANEL.Panel as ComponentLike,
  PanelSection: DEMOS_PANEL_SECTION.PanelSection as ComponentLike,
  Card: DEMOS_CARD.Card as ComponentLike,
  Divider: DEMOS_DIVIDER.Divider as ComponentLike,
  Grid: DEMOS_GRID.Grid as ComponentLike,
  Stack: DEMOS_STACK.Stack as ComponentLike,
  Toolbar: DEMOS_TOOLBAR.Toolbar as ComponentLike,
  Sidebar: DEMOS_SIDEBAR.Sidebar as ComponentLike,
  Breadcrumb: DEMOS_BREADCRUMB.Breadcrumb as ComponentLike,
  Tabs: DEMOS_TABS.Tabs as ComponentLike,
  SegmentedControl: DEMOS_SEGMENTED_CONTROL.SegmentedControl as ComponentLike,
  ToggleGroup: DEMOS_TOGGLE_GROUP.ToggleGroup as ComponentLike,
  Button: DEMOS_BUTTON.Button as ComponentLike,
  IconButton: DEMOS_ICON_BUTTON.IconButton as ComponentLike,
  ButtonGroup: DEMOS_BUTTON_GROUP.ButtonGroup as ComponentLike,
  ActionBar: DEMOS_ACTION_BAR.ActionBar as ComponentLike,
  SearchInput: DEMOS_SEARCH_INPUT.SearchInput as ComponentLike,
  FilterChips: DEMOS_FILTER_CHIPS.FilterChips as ComponentLike,
  FilterSet: DEMOS_FILTER_SET.FilterSet as ComponentLike,
  Select: DEMOS_SELECT.Select as ComponentLike,
  NativeSelect: DEMOS_NATIVE_SELECT.NativeSelect as ComponentLike,
  Combobox: DEMOS_COMBOBOX.Combobox as ComponentLike,
  DatePicker: DEMOS_DATE_PICKER.DatePicker as ComponentLike,
  DateRangePicker: DEMOS_DATE_RANGE_PICKER.DateRangePicker as ComponentLike,
  Input: DEMOS_INPUT.Input as ComponentLike,
  Checkbox: DEMOS_CHECKBOX.Checkbox as ComponentLike,
  Switch: DEMOS_SWITCH.Switch as ComponentLike,
  RadioGroup: DEMOS_RADIO_GROUP.RadioGroup as ComponentLike,
  Field: DEMOS_FIELD.Field as ComponentLike,
  Alert: DEMOS_ALERT.Alert as ComponentLike,
  Callout: DEMOS_CALLOUT.Callout as ComponentLike,
  Notification: DEMOS_NOTIFICATION.Notification as ComponentLike,
  Toast: DEMOS_TOAST.Toast as ComponentLike,
  Toaster: DEMOS_TOASTER.Toaster as ComponentLike,
  EmptyState: DEMOS_EMPTY_STATE.EmptyState as ComponentLike,
  Skeleton: DEMOS_SKELETON.Skeleton as ComponentLike,
  Spinner: DEMOS_SPINNER.Spinner as ComponentLike,
  LoadingState: DEMOS_LOADING_STATE.LoadingState as ComponentLike,
  Result: DEMOS_RESULT.Result as ComponentLike,
  Dialog: DEMOS_DIALOG.Dialog as ComponentLike,
  Drawer: DEMOS_DRAWER.Drawer as ComponentLike,
  Popover: DEMOS_POPOVER.Popover as ComponentLike,
  Tooltip: DEMOS_TOOLTIP.Tooltip as ComponentLike,
  Menu: DEMOS_MENU_USAGE.Menu as ComponentLike,
  Dropzone: DEMOS_DROPZONE.Dropzone as ComponentLike,
  Board: DEMOS_BOARD.Board as ComponentLike,
  Calendar: DEMOS_CALENDAR.Calendar as ComponentLike,
  StepList: DEMOS_STEP_LIST.StepList as ComponentLike,
  Wizard: DEMOS_WIZARD.Wizard as ComponentLike,
  ReadinessPanel: DEMOS_READINESS_PANEL.ReadinessPanel as ComponentLike,
  Kbd: DEMOS_KBD.Kbd as ComponentLike,
  Collapsible: DEMOS_COLLAPSIBLE.Collapsible as ComponentLike,
  Accordion: DEMOS_ACCORDION.Accordion as ComponentLike,
  Feed: DEMOS_FEED.Feed as ComponentLike,
};
