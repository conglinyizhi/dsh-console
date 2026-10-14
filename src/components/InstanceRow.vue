<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import type { Instance } from '../mock/instances'
import type { IconName } from './icons'
import AppIcon from './AppIcon.vue'

interface FieldRow {
  icon: IconName
  label: string
  value: string
}

interface MenuEntry {
  icon?: IconName
  label?: string
  divider?: boolean
}

const props = defineProps<{ instance: Instance }>()
const emit = defineEmits<{ toggle: [id: string] }>()

const running = computed(() => props.instance.status === 'running')

const fields = computed<FieldRow[]>(() => {
  const it = props.instance
  return [
    { icon: 'tag', label: 'DSH 版本 / 来源', value: it.version },
    { icon: 'layers', label: 'Profile', value: it.profile },
    { icon: 'link', label: '访问地址', value: it.url },
    { icon: 'home', label: 'DSH_HOME', value: it.home },
    { icon: 'puzzle', label: '插件数量', value: it.pluginCount },
  ]
})

/** 全行只有一个菜单：原独立下拉的条目并进「打开 Web UI」右半的下拉 */
const menuItems: MenuEntry[] = [
  { icon: 'launch', label: '在新标签页打开' },
  { icon: 'link', label: '复制访问地址' },
  { divider: true },
  { icon: 'logs', label: '查看日志' },
  { icon: 'folderOpen', label: '打开工作目录' },
  { icon: 'sliders', label: '编辑配置' },
]

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

function pickItem() {
  closeMenu()
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

/** 左半：直接打开实例的 Web UI。前端占位，尚未接真实跳转 */
function openWebUi() {}

const restarting = ref(false)
let timer: number | undefined

function onRestart() {
  if (restarting.value) return
  restarting.value = true
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
  <article class="row">
    <header class="row-head">
      <span class="tile" :class="instance.tone">
        <AppIcon :name="instance.tone === 'violet' ? 'puzzle' : 'launch'" :size="20" />
      </span>

      <span class="ident">
        <span class="name-line">
          <span class="name">{{ instance.name }}</span>
          <span class="kind">{{ instance.kind }}</span>
        </span>
      </span>

      <span class="state" :class="{ off: !running }">
        <i class="dot" />
        <span class="state-label">{{ running ? '运行中' : '已停止' }}</span>
        <span class="uptime">已运行 {{ instance.uptime }}</span>
      </span>

      <div class="actions">
        <div class="menu-host">
          <!-- split button：左半直接打开、右半只开菜单，1px 分隔线来自右半的 border-left -->
          <div class="split" :class="instance.tone">
            <button type="button" class="btn primary split-main" @click="openWebUi">
              <AppIcon name="launch" :size="14" />
              <span>打开 Web UI</span>
            </button>
            <button
              ref="triggerRef"
              type="button"
              class="btn primary split-caret"
              aria-haspopup="menu"
              :aria-expanded="menuOpen"
              aria-label="打开 Web UI 菜单"
              @click="toggleMenu"
            >
              <AppIcon name="chevronRight" :size="12" class="caret" />
            </button>
          </div>

          <div v-if="menuOpen" ref="menuRef" class="menu" role="menu">
            <template v-for="(item, index) in menuItems" :key="index">
              <div v-if="item.divider" class="menu-sep" role="separator" />
              <button v-else type="button" class="menu-item" role="menuitem" @click="pickItem">
                <AppIcon v-if="item.icon" :name="item.icon" :size="14" />
                <span>{{ item.label }}</span>
              </button>
            </template>
          </div>
        </div>

        <button v-if="running" type="button" class="btn" @click="emit('toggle', instance.id)">
          <i class="dot-danger" />
          <span>停止</span>
        </button>
        <button v-else type="button" class="btn" @click="emit('toggle', instance.id)">
          <AppIcon name="play" :size="13" />
          <span>启动</span>
        </button>

        <button type="button" class="btn" :disabled="restarting" @click="onRestart">
          <AppIcon name="refresh" :size="14" />
          <span>{{ restarting ? '重启中…' : '重启' }}</span>
        </button>
      </div>
    </header>

    <ul class="fields">
      <li v-for="field in fields" :key="field.label" class="field">
        <span class="field-icon"><AppIcon :name="field.icon" :size="14" /></span>
        <span class="field-label">{{ field.label }}</span>
        <span class="field-value">{{ field.value }}</span>
      </li>
    </ul>

    <div v-if="menuOpen" class="overlay" @click="closeMenu()" />
  </article>
</template>

<style scoped>
.row {
  /* 两卡共用同一套列宽，逐项左右边界可比 */
  --col-ident: 188px;
  --col-name: 76px;
  --col-kind: 106px;
  --col-state: 38px;
  position: relative;
  display: flex; flex-direction: column; gap: 12px;
  padding: 14px 16px 15px;
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: var(--radius);
}
.row-head {
  /* 固定栅格：图标底板、名称、类型标签、状态、按钮组各自的轨道固定，
     两卡的列左边界与按钮组右边界逐项一致，不靠内容自然撑开 */
  display: grid;
  grid-template-columns: 40px var(--col-ident) minmax(0, 1fr) auto;
  align-items: center; column-gap: 10px;
}
.tile { width: 40px; height: 40px; flex: none; border-radius: 10px; display: grid; place-items: center; }
.tile.accent { background: rgba(78, 194, 122, 0.14); color: var(--ok); }
.tile.violet { background: var(--violet-soft); color: var(--violet); }
.ident { min-width: 0; display: flex; }
.name-line {
  display: grid; grid-template-columns: var(--col-name) var(--col-kind);
  align-items: center; column-gap: 6px; min-width: 0;
}
.name {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 14px; font-weight: 600; color: var(--text);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.kind {
  flex: none; padding: 2px 7px;
  border: 1px solid var(--line-strong); border-radius: 999px;
  font-size: 11px; line-height: 1.35; color: var(--text-mid);
  background: var(--panel-soft); white-space: nowrap;
}
.state {
  /* 状态点、状态文案、时长共用卡头这一条中心线：起点分别为固定轨道 */
  display: grid; grid-template-columns: 7px var(--col-state) minmax(0, 1fr);
  align-items: center; column-gap: 6px; min-width: 0; color: var(--ok);
}
.state.off { color: var(--text-dim); }
.dot {
  width: 7px; height: 7px; border-radius: 50%;
  background: currentColor; box-shadow: 0 0 0 3px rgba(78, 194, 122, 0.13);
}
.state.off .dot { box-shadow: none; }
.state-label { font-size: 12px; }
.uptime {
  font-size: 10.5px; color: var(--text-dim);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.actions {
  /* 一行三组：打开 Web UI（split）、停止/启动、重启 */
  justify-self: end; display: flex; justify-content: flex-end; gap: 6px;
}
.menu-host { position: relative; }
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
.menu-item:hover { background: var(--panel); color: var(--text); }
.menu-item:focus-visible {
  outline: 1px solid var(--accent); outline-offset: -1px;
  background: var(--panel); color: var(--text);
}
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
.fields {
  /* 固定两列：5 个字段恒为 2 / 2 / 1，不随窗口宽度塌成一列或涨成四列 */
  list-style: none; margin: 0; padding: 0;
  display: grid; grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 2px 20px;
}
.field { display: flex; align-items: center; gap: 7px; height: 28px; min-width: 0; }
.field-icon { color: var(--text-dim); display: flex; }
.field-label { flex: none; font-size: 11.5px; color: var(--text-dim); }
.field-value {
  margin-left: auto; min-width: 0;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 11.5px; color: var(--text);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
</style>
