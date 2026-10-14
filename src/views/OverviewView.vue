<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, reactive, ref } from 'vue'
import { ARCHIVED_AT, instances as seed } from '../mock/instances'
import type { Instance } from '../mock/instances'
import type { ActionKey } from '../actions'
import InstanceRow from '../components/InstanceRow.vue'
import ArchivedRow from '../components/ArchivedRow.vue'
import ConfirmDialog from '../components/ConfirmDialog.vue'
import RenameDialog from '../components/RenameDialog.vue'
import StoppedEmpty from '../components/StoppedEmpty.vue'
import SideInfoPanel from '../components/SideInfoPanel.vue'

const list = reactive<Instance[]>(seed.map((item) => ({ ...item })))

/** 启动等待时长（前端演示，没有真实进程可等） */
const START_DELAY_MS = 2500
/** 端口探测上限：最多往后试 20 个 */
const PORT_PROBE_LIMIT = 20
/** 探测超时：600ms 内没有应答就按空闲处理 */
const PORT_PROBE_TIMEOUT_MS = 600

const running = computed(() => list.filter((item) => !item.archivedAt && item.status === 'running'))
/** 启动等待中的行留在原分组，所以「已停止」组把 starting 一起算进来 */
const stopped = computed(
  () => list.filter((item) => !item.archivedAt && item.status !== 'running'),
)
const archived = computed(() => list.filter((item) => item.archivedAt))

/** 派生编号：在 plugin-dev-N 里取第一个没被占用的号。
   按 id 判断占用而不是按 name，改名不会把 id 让出去，也就不会派生出重号 */
function nextForkIndex() {
  const used = new Set(list.map((item) => item.id))
  let index = 2
  while (used.has(`plugin-dev-${index}`)) index += 1
  return index
}

function nextPort() {
  let max = 0
  for (const item of list) {
    const matched = /:(\d+)$/.exec(item.url)
    if (matched) max = Math.max(max, Number(matched[1]))
  }
  return max + 1
}

/** 本次会话里已经认掉的端口，避免同一批派生撞到同一个号 */
const reservedPorts = new Set<number>()

/**
 * 探测单个候选端口。
 * no-cors 请求一旦 resolve，说明对端有东西在应答，按占用处理；
 * reject（连接被拒、超时）只说明这一次没听到应答，按大概空闲处理。
 */
async function isPortBusy(port: number): Promise<boolean> {
  try {
    await fetch(`http://127.0.0.1:${port}/`, {
      mode: 'no-cors',
      signal: AbortSignal.timeout(PORT_PROBE_TIMEOUT_MS),
    })
    return true
  } catch {
    return false
  }
}

interface PortChoice {
  port: number
  /** 被跳过时记下第一个占用的端口，用于界面提示 */
  skipped: number | null
  /** 20 个候选全被占用时为真，此时只能给出一个没探测过的号 */
  exhausted: boolean
}

/** 从候选端口往后找第一个「探测下来没被占用」的端口 */
async function pickPort(start: number): Promise<PortChoice> {
  let skipped: number | null = null
  for (let offset = 0; offset < PORT_PROBE_LIMIT; offset += 1) {
    const port = start + offset
    if (reservedPorts.has(port)) {
      skipped ??= port
      continue
    }
    const taken = await isPortBusy(port)
    if (taken) {
      skipped ??= port
      continue
    }
    reservedPorts.add(port)
    return { port, skipped, exhausted: false }
  }
  // 20 个候选全都有人应答：给一个连着往后排的号，并在界面上说清它是没探测过的
  const fallback = start + PORT_PROBE_LIMIT
  reservedPorts.add(fallback)
  return { port: fallback, skipped: start, exhausted: true }
}

const timers: number[] = []

function schedule(fn: () => void, delay: number) {
  timers.push(window.setTimeout(fn, delay))
}

onBeforeUnmount(() => {
  for (const id of timers) window.clearTimeout(id)
})

/** 启动：先留在原分组显示等待态，再落成运行中 */
function start(item: Instance) {
  if (item.status === 'starting') return
  item.status = 'starting'
  item.busy = true
  schedule(() => {
    item.busy = false
    item.portNote = undefined
    // 等待期间被归档或删掉的行不再落状态
    if (item.archivedAt || item.status !== 'starting') return
    item.status = 'running'
    item.uptime = 0
  }, START_DELAY_MS)
}

async function fork() {
  const index = nextForkIndex()
  const name = `plugin-dev-${index}`
  /** 用 reactive 包一层：后面要靠它自己的变更触发重渲染，裸对象改不动界面 */
  const item = reactive<Instance>({
    id: name,
    name,
    kind: '插件开发（试验）',
    tone: 'violet',
    status: 'starting',
    busy: true,
    uptime: 0,
    version: '0.2.0-rc.2（本地源码）',
    profile: 'dev',
    home: `/Users/you/.dsh/${name}`,
    url: 'http://127.0.0.1:0',
    pluginCount: '1 个（开发中）',
    deletable: true,
  })
  list.push(item)
  schedule(() => {
    item.busy = false
    if (item.archivedAt || item.status !== 'starting') return
    item.status = 'running'
  }, START_DELAY_MS)

  const basePort = nextPort()
  item.portNote = `端口 ${basePort} · 正在探测`
  const choice = await pickPort(basePort)
  item.url = `http://127.0.0.1:${choice.port}`
  if (choice.exhausted) {
    item.portNote = `${choice.skipped} 起 20 个都被占用，暂用 ${choice.port}（未探测）`
  } else if (choice.skipped === null) {
    item.portNote = `端口 ${choice.port} · 已探测未被占用`
  } else {
    item.portNote = `${choice.skipped} 被占用，改用 ${choice.port}`
  }
}

const pendingRename = ref<Instance | null>(null)
const renameReturnTo = ref<HTMLElement | null>(null)

function requestRename(id: string, trigger: HTMLElement | null) {
  const item = find(id)
  if (!item) return
  renameReturnTo.value = trigger
  pendingRename.value = item
}

/** 关闭重命名框：把焦点还给触发元素 */
function closeRename() {
  const back = renameReturnTo.value
  pendingRename.value = null
  renameReturnTo.value = null
  void nextTick(() => {
    if (back?.isConnected) back.focus()
  })
}

/** 只改 name，其它字段不动 */
function applyRename(name: string) {
  const target = pendingRename.value
  if (target) target.name = name
  closeRename()
}

function find(id: string) {
  return list.find((item) => item.id === id)
}

function toggle(id: string) {
  const item = find(id)
  if (!item) return
  if (item.status === 'running') item.status = 'stopped'
  else if (item.status === 'stopped') start(item)
}

function archive(id: string) {
  const item = find(id)
  if (item) item.archivedAt = ARCHIVED_AT
}

/** 取消归档：回到「已停止的实例」组 */
function unarchive(id: string) {
  const item = find(id)
  if (!item) return
  item.archivedAt = undefined
  item.status = 'stopped'
}

const pendingDelete = ref<Instance | null>(null)
const deleteReturnTo = ref<HTMLElement | null>(null)

function requestDelete(id: string, trigger: HTMLElement | null) {
  const item = find(id)
  if (!item) return
  deleteReturnTo.value = trigger
  pendingDelete.value = item
}

/** 关闭确认框：还焦点给触发元素（已随列表卸载时不做处理） */
function closeConfirm() {
  const back = deleteReturnTo.value
  pendingDelete.value = null
  deleteReturnTo.value = null
  void nextTick(() => {
    if (back?.isConnected) back.focus()
  })
}

function confirmDelete() {
  const target = pendingDelete.value
  if (target) {
    const index = list.findIndex((item) => item.id === target.id)
    if (index >= 0) list.splice(index, 1)
  }
  closeConfirm()
}

function onAction(id: string, key: ActionKey, trigger: HTMLElement | null) {
  if (key === 'toggle') toggle(id)
  else if (key === 'fork') void fork()
  else if (key === 'rename') requestRename(id, trigger)
  else if (key === 'archive') archive(id)
  else if (key === 'delete') requestDelete(id, trigger)
  // 其余动作（打开 UI、复制地址、日志、目录、配置、重启）仍是前端占位，不接后端
}
</script>

<template>
  <div class="overview">
    <section class="page">
      <header class="page-head">
        <div class="head-text">
          <h1 class="page-title">实例总览</h1>
        </div>
        <button type="button" class="new-btn">
          <span class="plus">＋</span>
          <span>新建实例</span>
        </button>
      </header>

      <div class="section-head">
        <h2 class="section-title">当前运行的实例 ({{ running.length }})</h2>
      </div>

      <div class="rows">
        <InstanceRow
          v-for="item in running"
          :key="item.id"
          :instance="item"
          @action="(key, trigger) => onAction(item.id, key, trigger)"
        />
      </div>

      <div class="section-head">
        <h2 class="section-title">已停止的实例 ({{ stopped.length }})</h2>
      </div>

      <div class="rows">
        <InstanceRow
          v-for="item in stopped"
          :key="item.id"
          :instance="item"
          @action="(key, trigger) => onAction(item.id, key, trigger)"
        />
        <StoppedEmpty v-if="stopped.length === 0" />
      </div>

      <template v-if="archived.length > 0">
        <div class="section-head">
          <h2 class="section-title">已归档 ({{ archived.length }})</h2>
        </div>

        <div class="rows">
          <ArchivedRow
            v-for="item in archived"
            :key="item.id"
            :instance="item"
            @unarchive="unarchive"
            @delete="requestDelete"
          />
        </div>
      </template>
    </section>

    <SideInfoPanel />

    <ConfirmDialog
      v-if="pendingDelete"
      :danger="true"
      :title="`删除实例 ${pendingDelete.name}？`"
      message="删除后该实例将从列表移除，本页不连接真实进程。"
      confirm-text="删除"
      cancel-text="取消"
      @confirm="confirmDelete"
      @cancel="closeConfirm"
    />

    <RenameDialog
      v-if="pendingRename"
      :title="`重命名实例 ${pendingRename.name}`"
      :initial="pendingRename.name"
      @confirm="applyRename"
      @cancel="closeRename"
    />
  </div>
</template>

<style scoped>
.overview {
  display: flex;
  align-items: stretch;
  min-height: 100%;
}
.page {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 22px 24px;
}
.page-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}
.head-text {
  min-width: 0;
}
.page-title {
  margin: 0;
  font-size: 21px;
  font-weight: 600;
  letter-spacing: 0.2px;
}
.new-btn {
  flex: none;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  height: 32px;
  padding: 0 13px;
  border: 0;
  border-radius: var(--radius-sm);
  background: var(--accent);
  color: #fff;
  font-size: 12.5px;
  cursor: pointer;
}
.new-btn:hover {
  filter: brightness(1.08);
}
.plus {
  font-size: 13px;
}
.section-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  margin-top: 4px;
}
.section-title {
  margin: 0;
  font-size: 13px;
  font-weight: 600;
  color: var(--text-mid);
}
.rows {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
</style>
