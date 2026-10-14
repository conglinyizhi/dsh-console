<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import type { Instance } from '../mock/instances'
import type { ActionKey } from '../actions'
import type { IconName } from './icons'
import AppIcon from './AppIcon.vue'

interface MenuEntry {
  key?: ActionKey
  icon?: IconName
  label?: string
  divider?: boolean
  danger?: boolean
}

const props = defineProps<{ instance: Instance }>()
const emit = defineEmits<{ action: [key: ActionKey, trigger: HTMLElement | null] }>()

const running = computed(() => props.instance.status === 'running')
/** 启动等待期：整行按钮都不可点（下拉触发也 disabled，所以菜单根本开不出来），菜单项上的 disabled 只是兜底 */
const busy = computed(() => props.instance.busy === true)

/** 运行中：重命名/派生/归档/删除靠上，运维三项沉底；删除只给可删实例 */
const runningMenu = computed<MenuEntry[]>(() => {
  const items: MenuEntry[] = [
    { key: 'tab', icon: 'launch', label: '在新标签页打开' },
    { key: 'copy-url', icon: 'link', label: '复制访问地址' },
    { divider: true },
    { key: 'rename', icon: 'rename', label: '重命名' },
    { key: 'fork', icon: 'branch', label: '派生开发副本' },
    { key: 'archive', icon: 'archive', label: '归档' },
  ]
  if (props.instance.deletable) {
    items.push({ key: 'delete', icon: 'delete', label: '删除', danger: true })
  }
  items.push(
    { divider: true },
    { key: 'logs', icon: 'logs', label: '查看日志' },
    { key: 'dir', icon: 'folderOpen', label: '打开工作目录' },
    { key: 'config', icon: 'sliders', label: '编辑配置' },
  )
  return items
})

/** 已停止：没有 split button，这个图标按钮是该行唯一的下拉入口；可删实例也能直接删 */
const stoppedMenu = computed<MenuEntry[]>(() => {
  const items: MenuEntry[] = [
    { key: 'logs', icon: 'logs', label: '查看日志' },
    { key: 'dir', icon: 'folderOpen', label: '打开工作目录' },
    { key: 'config', icon: 'sliders', label: '编辑配置' },
    { divider: true },
    { key: 'rename', icon: 'rename', label: '重命名' },
    { key: 'archive', icon: 'archive', label: '归档' },
  ]
  if (props.instance.deletable) {
    items.push({ key: 'delete', icon: 'delete', label: '删除', danger: true })
  }
  return items
})

const menuItems = computed(() => (running.value ? runningMenu.value : stoppedMenu.value))

const menuOpen = ref(false)
const triggerRef = ref<HTMLButtonElement | null>(null)
const menuRef = ref<HTMLElement | null>(null)

async function toggleMenu() {
  if (menuOpen.value) {
    closeMenu()
    return
  }
  menuOpen.value = true
  await nextTick()
  menuRef.value?.querySelector<HTMLButtonElement>('.menu-item')?.focus()
}

function closeMenu(restoreFocus = false) {
  if (!menuOpen.value) return
  menuOpen.value = false
  if (restoreFocus) void nextTick(() => triggerRef.value?.focus())
}

/** 菜单项：先收起菜单，再把动作连同触发元素上抛 */
function pickItem(key: ActionKey) {
  const trigger = triggerRef.value
  closeMenu()
  emit('action', key, trigger)
}

function onWindowKeydown(event: KeyboardEvent) {
  if (event.key !== 'Escape') return
  event.preventDefault()
  closeMenu(true)
}

watch(menuOpen, (open) => {
  if (open) window.addEventListener('keydown', onWindowKeydown)
  else window.removeEventListener('keydown', onWindowKeydown)
})

const restarting = ref(false)
let timer: number | undefined

function onRestart() {
  if (restarting.value) return
  restarting.value = true
  emit('action', 'restart', null)
  timer = window.setTimeout(() => {
    restarting.value = false
  }, 900)
}

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onWindowKeydown)
  if (timer !== undefined) window.clearTimeout(timer)
})
</script>

<template>
  <div class="actions">
    <!-- 运行中才有 split button：左半打开 UI，右半只开菜单 -->
    <div v-if="running" class="split" :class="instance.tone">
      <button type="button" class="btn primary split-main" @click="emit('action', 'open-ui', null)">
        <AppIcon name="launch" :size="14" />
        <span>打开 Web UI</span>
      </button>
      <button
        ref="triggerRef"
        type="button"
        class="btn primary split-caret"
        aria-haspopup="menu"
        :aria-expanded="menuOpen"
        :aria-label="`打开 Web UI 菜单（${instance.name}）`"
        @click="toggleMenu"
      >
        <AppIcon name="chevronRight" :size="12" class="caret" />
      </button>
    </div>

    <button
      v-if="running"
      type="button"
      class="btn"
      :disabled="busy"
      @click="emit('action', 'toggle', null)"
    >
      <i class="dot-danger" />
      <span>停止</span>
    </button>
    <button
      v-else
      type="button"
      class="btn primary"
      :disabled="busy"
      @click="emit('action', 'toggle', null)"
    >
      <AppIcon name="play" :size="13" />
      <span>{{ busy ? '启动中…' : '启动' }}</span>
    </button>

    <button type="button" class="btn" :disabled="restarting || busy" @click="onRestart">
      <AppIcon name="refresh" :size="14" />
      <span>{{ restarting ? '重启中…' : '重启' }}</span>
    </button>

    <!-- 已停止行唯一的下拉入口：纯图标，无文字 -->
    <button
      v-if="!running"
      ref="triggerRef"
      type="button"
      class="btn icon-only"
      aria-haspopup="menu"
      :aria-expanded="menuOpen"
      :disabled="busy"
      :aria-label="`更多操作（${instance.name}）`"
      @click="toggleMenu"
    >
      <AppIcon name="more" :size="16" />
    </button>

    <div v-if="menuOpen" ref="menuRef" class="menu" role="menu">
      <template v-for="(item, index) in menuItems" :key="index">
        <div v-if="item.divider" class="menu-sep" role="separator" />
        <button
          v-else
          type="button"
          class="menu-item"
          :class="{ danger: item.danger }"
          role="menuitem"
          :disabled="busy"
          :data-action="item.key"
          @click="pickItem(item.key as ActionKey)"
        >
          <AppIcon v-if="item.icon" :name="item.icon" :size="14" />
          <span>{{ item.label }}</span>
        </button>
      </template>
    </div>
  </div>

  <div v-if="menuOpen" class="overlay" @click="closeMenu()" />
</template>

<style scoped>
.actions {
  /* 一行三组：打开 Web UI（split）、停止/启动、重启，外加停止行的图标下拉 */
  position: relative;
  justify-self: end;
  display: flex;
  justify-content: flex-end;
  gap: 6px;
}
.overlay { position: fixed; inset: 0; z-index: 20; }
.menu {
  position: absolute; top: calc(100% + 6px); right: 0; z-index: 30;
  min-width: 152px; padding: 4px;
  display: flex; flex-direction: column;
  background: var(--panel-soft);
  border: 1px solid var(--line-strong);
  border-radius: var(--radius-sm);
  box-shadow: 0 12px 26px rgba(0, 0, 0, 0.45);
}
.menu-item {
  display: flex; align-items: center; gap: 8px;
  height: 30px; padding: 0 9px;
  border: 0; border-radius: 5px; background: transparent;
  color: var(--text-mid); font-size: 12.5px;
  cursor: pointer; text-align: left;
}
.menu-item:hover:not(:disabled) { background: var(--panel); color: var(--text); }
.menu-item:disabled { opacity: 0.45; cursor: default; }
.menu-item:focus-visible {
  outline: 1px solid var(--accent); outline-offset: -1px;
  background: var(--panel); color: var(--text);
}
.menu-item.danger,
.menu-item.danger:hover,
.menu-item.danger:focus-visible { color: var(--danger); }
.menu-sep { height: 1px; margin: 4px 6px; background: var(--line-strong); }
.caret { transform: rotate(90deg); opacity: 0.8; }
.btn {
  height: 30px; padding: 0 8px;
  display: inline-flex; align-items: center; gap: 6px;
  border: 1px solid var(--line-strong); border-radius: var(--radius-sm);
  background: transparent; color: var(--text);
  font-size: 12.5px; cursor: pointer; white-space: nowrap;
}
.btn:hover { background: var(--panel-soft); }
.btn:disabled { opacity: 0.6; cursor: default; }
.btn.primary {
  border-color: transparent; color: #fff;
  background: var(--split-bg, var(--accent));
}
.btn.primary:hover { filter: brightness(1.08); }
.btn.icon-only { width: 30px; padding: 0; justify-content: center; }
/* split button：主色底随实例色调，第一张卡蓝、第二张紫 */
.split { display: inline-flex; }
.split.accent { --split-bg: var(--accent); }
.split.violet { --split-bg: var(--violet); }
.split-main { border-right-width: 0; border-radius: var(--radius-sm) 0 0 var(--radius-sm); }
.split > .btn.split-caret {
  min-width: 26px; padding: 0; justify-content: center;
  border-left: 1px solid rgba(255, 255, 255, 0.34);
  border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
}
/* 悬停只加深指针所在的那一半 */
.split > .btn.primary:hover { filter: brightness(0.88); }
.dot-danger { width: 7px; height: 7px; border-radius: 50%; background: var(--danger); }
</style>
