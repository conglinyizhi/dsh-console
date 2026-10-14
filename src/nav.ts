import type { IconName } from './components/icons'

export type NavKey = 'overview' | 'plugins' | 'workspace' | 'logs' | 'about'

export interface NavItem {
  key: NavKey
  label: string
  icon: IconName
}

export const navItems: NavItem[] = [
  { key: 'overview', label: '实例总览', icon: 'grid' },
  { key: 'plugins', label: '插件管理', icon: 'puzzle' },
  { key: 'workspace', label: '工作区', icon: 'folder' },
  { key: 'logs', label: '日志', icon: 'logs' },
  { key: 'about', label: '关于', icon: 'shield' },
]
