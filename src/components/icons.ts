// 图标全部来自 Material Symbols（Iconify 图标集，经 unplugin-icons 按需编译）
// 语义名 → 图标集里的官方名，换图标只改右边这一列
import IconHub from '~icons/material-symbols/hub-outline'
import IconGridView from '~icons/material-symbols/grid-view-outline'
import IconTune from '~icons/material-symbols/tune-outline'
import IconFolder from '~icons/material-symbols/folder-outline'
import IconDescription from '~icons/material-symbols/description-outline'
import IconOpenInNew from '~icons/material-symbols/open-in-new-outline'
import IconExtension from '~icons/material-symbols/extension-outline'
import IconLabel from '~icons/material-symbols/label-outline'
import IconLayers from '~icons/material-symbols/layers-outline'
import IconHome from '~icons/material-symbols/home-outline'
import IconDns from '~icons/material-symbols/dns-outline'
import IconLink from '~icons/material-symbols/link-outline'
import IconForkRight from '~icons/material-symbols/fork-right-outline'
import IconTerminal from '~icons/material-symbols/terminal-outline'
import IconShield from '~icons/material-symbols/shield-outline'
import IconRefresh from '~icons/material-symbols/refresh-outline'
import IconStop from '~icons/material-symbols/stop-outline'
import IconFolderOpen from '~icons/material-symbols/folder-open-outline'
import IconPlayArrow from '~icons/material-symbols/play-arrow-outline'
import IconCheck from '~icons/material-symbols/check-outline'
import IconDeployedCode from '~icons/material-symbols/deployed-code-outline'
import IconLock from '~icons/material-symbols/lock-outline'
import IconChevronRight from '~icons/material-symbols/chevron-right-outline'
import IconSettings from '~icons/material-symbols/settings-outline'
import IconMoreHoriz from '~icons/material-symbols/more-horiz-outline'

export const icons = {
  logo: IconHub,
  grid: IconGridView,
  sliders: IconTune,
  folder: IconFolder,
  logs: IconDescription,
  launch: IconOpenInNew,
  puzzle: IconExtension,
  tag: IconLabel,
  layers: IconLayers,
  home: IconHome,
  server: IconDns,
  link: IconLink,
  branch: IconForkRight,
  terminal: IconTerminal,
  shield: IconShield,
  refresh: IconRefresh,
  stop: IconStop,
  folderOpen: IconFolderOpen,
  play: IconPlayArrow,
  check: IconCheck,
  cube: IconDeployedCode,
  lock: IconLock,
  chevronRight: IconChevronRight,
  settings: IconSettings,
  more: IconMoreHoriz,
} as const

export type IconName = keyof typeof icons
