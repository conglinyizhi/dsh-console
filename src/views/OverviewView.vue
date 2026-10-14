<script setup lang="ts">
import { computed, nextTick, reactive, ref } from 'vue'
import { ARCHIVED_AT, instances as seed } from '../mock/instances'
import type { Instance } from '../mock/instances'
import type { ActionKey } from '../actions'
import InstanceRow from '../components/InstanceRow.vue'
import ArchivedRow from '../components/ArchivedRow.vue'
import ConfirmDialog from '../components/ConfirmDialog.vue'
import StoppedEmpty from '../components/StoppedEmpty.vue'
import SideInfoPanel from '../components/SideInfoPanel.vue'

const list = reactive<Instance[]>(seed.map((item) => ({ ...item })))

const running = computed(() => list.filter((item) => !item.archivedAt && item.status === 'running'))
const stopped = computed(() => list.filter((item) => !item.archivedAt && item.status === 'stopped'))
const archived = computed(() => list.filter((item) => item.archivedAt))

/** 派生：插件开发实例按 plugin-dev 前缀取最大编号 +1，端口取现有最大端口 +1 */
function nextForkIndex() {
  let max = 1
  for (const item of list) {
    const matched = /^plugin-dev(?:-(\d+))?$/.exec(item.name)
    if (matched) max = Math.max(max, matched[1] ? Number(matched[1]) : 1)
  }
  return max + 1
}

function nextPort() {
  let max = 0
  for (const item of list) {
    const matched = /:(\d+)$/.exec(item.url)
    if (matched) max = Math.max(max, Number(matched[1]))
  }
  return max + 1
}

function fork() {
  const index = nextForkIndex()
  const name = `plugin-dev-${index}`
  list.push({
    id: name,
    name,
    kind: '插件开发（试验）',
    tone: 'violet',
    status: 'running',
    uptime: '0 分钟',
    version: '0.2.0-rc.2（本地源码）',
    profile: 'dev',
    home: `/Users/you/.dsh/${name}`,
    url: `http://127.0.0.1:${nextPort()}`,
    pluginCount: '1 个（开发中）',
    deletable: true,
  })
}

function find(id: string) {
  return list.find((item) => item.id === id)
}

function toggle(id: string) {
  const item = find(id)
  if (item) item.status = item.status === 'running' ? 'stopped' : 'running'
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
  else if (key === 'fork') fork()
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
