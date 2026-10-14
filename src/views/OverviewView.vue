<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { demoTag, fallbackTag, fetchInstances, fetchProfiles, fetchRuntime, realTag } from '../api/local'
import type { LocalInstances, LocalProfileFact, LocalRuntime } from '../api/local'
import { profileInstances, runningInstances } from '../data/mapLocal'
import type { Instance, SourceTag } from '../data/types'
import { ARCHIVED_AT, demoArchived, demoRunning, demoStopped } from '../mock/instances'
import { nextPort, pickPort } from '../portProbe'
import type { ActionKey } from '../actions'
import ArchivedSection from '../components/ArchivedSection.vue'
import ConfirmDialog from '../components/ConfirmDialog.vue'
import InstanceGroup from '../components/InstanceGroup.vue'
import InstanceRow from '../components/InstanceRow.vue'
import RenameDialog from '../components/RenameDialog.vue'
import RunningEmpty from '../components/RunningEmpty.vue'
import SideInfoPanel from '../components/SideInfoPanel.vue'
import SourceBadge from '../components/SourceBadge.vue'
import StoppedEmpty from '../components/StoppedEmpty.vue'

/** 启动等待时长（前端演示，没有真实进程可等） */
const START_DELAY_MS = 2500

const list = reactive<Instance[]>([])

/**
 * 数据源标记，逐处标：运行中/已停止两组跟真实读数走，归档区本轮固定演示。
 * 真实读取失败时整组换成演示实例，标记同时变成「演示数据 · 真实读取失败」，不静默混用。
 */
const sources = reactive<Record<'runtime' | 'instances' | 'profiles' | 'archived', SourceTag>>({
  runtime: demoTag('本地只读接口还没返回'),
  instances: demoTag('本地只读接口还没返回'),
  profiles: demoTag('本地只读接口还没返回'),
  archived: demoTag('归档区本轮不接真实数据：磁盘上没有「归档记录」这种概念，这组一直是前端演示'),
})

/** 端口探测的元信息，只用来给空态和分组标记报口径，不参与卡片内容 */
const instancesMeta = ref<LocalInstances | null>(null)

/** 空态口径：扫了多少个 loopback 监听端口、命中几个 DSH 签名 */
const runningSummary = computed(() => {
  const meta = instancesMeta.value
  if (!meta) return '监听端口扫描还没返回结果'
  return `扫了本机 ${meta.candidateCount} 个 loopback 监听端口，其中 ${meta.probe.hits} 个命中 DSH 签名`
})

const running = computed(() => list.filter((item) => !item.archivedAt && item.status === 'running'))
/** 启动等待中的行留在原分组，所以「已停止」组把 starting 一起算进来 */
const stopped = computed(() => list.filter((item) => !item.archivedAt && item.status !== 'running'))
const archived = computed(() => list.filter((item) => item.archivedAt))

function clone(items: Instance[]): Instance[] {
  return items.map((item) => ({ ...item }))
}

/** 页面启动时拉一次本机真实状态：三个只读接口，都是 GET */
async function loadLocal() {
  const [runtimeRead, profilesRead, instancesRead] = await Promise.all([
    fetchRuntime(),
    fetchProfiles(),
    fetchInstances(),
  ])

  const runtime: LocalRuntime | null = runtimeRead.ok ? runtimeRead.data : null
  const profileFacts: LocalProfileFact[] = profilesRead.data?.profiles ?? []
  const instanceFacts = instancesRead.data?.instances ?? []
  const dshHome = profilesRead.data?.dshHome ?? runtime?.dshHome ?? '—'

  const readTime = new Date().toLocaleTimeString('zh-CN', { hour12: false })

  sources.runtime = runtime
    ? realTag(
        `dsh ${runtime.dshVersion} · 后端 ${runtime.backendRuntime} ${runtime.backendVersion} · DSH_HOME ${runtime.dshHome}（${runtime.dshHomeSource}） · ${readTime} 读取`,
      )
    : fallbackTag(`/api/local/runtime 读取失败：${runtimeRead.error ?? '未知原因'}`)

  // 运行中实例的口径：监听端口 + HTTP 签名探测，进程扫描只在接口内部做补充
  const meta = instancesRead.ok ? instancesRead.data : null
  instancesMeta.value = meta ?? null
  sources.instances = meta
    ? realTag(
        `/api/local/instances 读 ${meta.sources.join(' + ')}：扫 ${meta.candidateCount} 个 loopback LISTEN 端口，命中 DSH 签名 ${meta.probe.hits} 个（判据 ${meta.signatures.map((item) => item.id).join(' / ')}）· 进程补充：${meta.processSupplement.note} · ${readTime} 读取`,
      )
    : fallbackTag(`/api/local/instances 读取失败：${instancesRead.error ?? '未知原因'}`)

  sources.profiles = profilesRead.ok
    ? realTag(`/api/local/profiles 扫 ${profilesRead.data?.profilesRoot ?? '—'}，${profileFacts.length} 个 profile`)
    : fallbackTag(`/api/local/profiles 读取失败：${profilesRead.error ?? '未知原因'}`)

  const runningItems = instancesRead.ok ? runningInstances(instanceFacts, profileFacts) : clone(demoRunning)
  const stoppedItems = profilesRead.ok ? profileInstances(profileFacts, runtime, dshHome) : clone(demoStopped)
  list.splice(0, list.length, ...runningItems, ...stoppedItems, ...clone(demoArchived))
}

onMounted(() => {
  void loadLocal()
})

/** 派生编号：在 plugin-dev-N 里取第一个没被占用的号。
   按 id 判断占用而不是按 name，改名不会把 id 让出去，也就不会派生出重号 */
function nextForkIndex() {
  const used = new Set(list.map((item) => item.id))
  let index = 2
  while (used.has(`plugin-dev-${index}`)) index += 1
  return index
}

const timers: number[] = []

function schedule(fn: () => void, delay: number) {
  timers.push(window.setTimeout(fn, delay))
}

onBeforeUnmount(() => {
  for (const id of timers) window.clearTimeout(id)
})

/** 启动：先留在原分组显示等待态，再落成运行中（前端演示，不拉起真实进程） */
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

  const basePort = nextPort(list)
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
          <SourceBadge :tag="sources.runtime" />
          <span class="head-note">动作仍是演示</span>
        </div>
        <button type="button" class="new-btn">
          <span class="plus">＋</span>
          <span>新建实例</span>
        </button>
      </header>

      <InstanceGroup title="当前运行的实例" :count="running.length" :source="sources.instances">
        <InstanceRow
          v-for="item in running"
          :key="item.id"
          :instance="item"
          @action="(key, trigger) => onAction(item.id, key, trigger)"
        />
        <RunningEmpty v-if="running.length === 0" :summary="runningSummary" :detail="sources.instances.detail" />
      </InstanceGroup>

      <InstanceGroup title="已停止的实例" :count="stopped.length" :source="sources.profiles">
        <InstanceRow
          v-for="item in stopped"
          :key="item.id"
          :instance="item"
          @action="(key, trigger) => onAction(item.id, key, trigger)"
        />
        <StoppedEmpty v-if="stopped.length === 0" />
      </InstanceGroup>

      <ArchivedSection
        :items="archived"
        :source="sources.archived"
        @unarchive="unarchive"
        @delete="requestDelete"
      />
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
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}
.page-title {
  margin: 0;
  font-size: 21px;
  font-weight: 600;
  letter-spacing: 0.2px;
  white-space: nowrap;
}
.head-note {
  flex: none;
  font-size: 10.5px;
  color: var(--text-dim);
  white-space: nowrap;
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
</style>
