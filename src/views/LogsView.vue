<script setup lang="ts">
import { computed, nextTick, onMounted, ref } from 'vue'
import { fallbackTag, fetchInstances, fetchLogs, realTag, type LocalInstanceFact, type LocalLogs } from '../api/local'
import type { SourceTag } from '../data/types'
import AppIcon from '../components/AppIcon.vue'
import SourceBadge from '../components/SourceBadge.vue'

/** 与接口默认值一致：尾部 200 行，上限 1000 由接口负责截断并说明 */
const TAIL = 200

/** 固定来源保留在分隔线之后：插件开发者要看的是文件本身，不是实例 */
const FIXED_SOURCES = [
  { id: 'host', label: '宿主日志' },
  { id: 'audit', label: '审计日志' },
]

const source = ref<string>('host')
const instances = ref<LocalInstanceFact[]>([])
const instanceNote = ref<string | null>(null)
const data = ref<LocalLogs | null>(null)
const tag = ref<SourceTag>(fallbackTag('日志还没读'))
const readTime = ref('')
const logBox = ref<HTMLElement | null>(null)

const lines = computed(() => data.value?.lines ?? [])

/** 下拉当前选中项的显示名，实例条目用实例名 */
function labelOf(id: string) {
  if (id.startsWith('instance:')) {
    const found = instances.value.find((item) => item.id === id.slice('instance:'.length))
    return found ? 'dsh :' + found.port : id
  }
  return FIXED_SOURCES.find((item) => item.id === id)?.label ?? id
}

/** 元信息行：读成功写真实口径（含实际读到的文件路径），读失败写真实原因，不留空 */
const meta = computed(() => {
  const got = data.value
  if (!got) return '只读'
  const head = got.path ?? '只读'
  if (!got.readOk) return head + ' · 读取失败 · 只读'
  const rows = got.lines.length + ' 行'
  const size = got.fileSize === null ? '大小未知' : formatBytes(got.fileSize)
  const tailPart = got.truncated ? '尾部 ' + rows + ' · ' + (got.truncatedNote ?? '窗口已截断') : '尾部 ' + rows + '（请求 ' + got.effectiveTail + '）'
  const homePart = got.kind === 'instance' && got.homeSource ? ' · 目录依据：' + got.homeSource : ''
  return tailPart + ' · ' + size + ' · ' + head + homePart + ' · 读于 ' + readTime.value + ' · 只读'
})

function formatBytes(size: number) {
  if (size < 1024) return size + ' B'
  if (size < 1024 * 1024) return (size / 1024).toFixed(1) + ' KB'
  return (size / 1024 / 1024).toFixed(2) + ' MB'
}

/** 级别只在实际读出来时上色，其余次级灰 */
function levelClass(level: string | null) {
  if (level === 'error') return 'lv-error'
  if (level === 'warn') return 'lv-warn'
  return 'lv-none'
}

/** 打开与切来源都滚到底：最新的一行在下面 */
async function scrollToBottom() {
  await nextTick()
  const box = logBox.value
  if (box) box.scrollTop = box.scrollHeight
}

/** 实例列表跟着 /api/local/instances 变；读不到就如实说明，不编条目 */
async function loadInstances() {
  const read = await fetchInstances()
  if (read.ok && read.data) {
    instances.value = read.data.instances
    instanceNote.value = null
  } else {
    instances.value = []
    instanceNote.value = read.error ?? '实例列表读取失败'
  }
}

async function load() {
  const read = await fetchLogs(source.value, TAIL)
  readTime.value = new Date().toLocaleTimeString('zh-CN', { hour12: false })
  const label = labelOf(source.value)
  const query = 'GET /api/local/logs?source=' + encodeURIComponent(source.value)
  if (read.ok && read.data) {
    data.value = read.data
    if (read.data.readOk) {
      tag.value = realTag(
        query + ' 读 ' + read.data.path +
          ' 尾部 ' + read.data.windowBytes + ' 字节窗口，返回 ' + read.data.lines.length + ' 行 · ' + readTime.value + ' 读取',
      )
    } else {
      tag.value = fallbackTag(label + '真实读取失败：' + (read.data.readError ?? '未知原因'))
    }
  } else {
    data.value = null
    tag.value = fallbackTag(query + ' 失败：' + (read.error ?? '未知原因'))
  }
  await scrollToBottom()
}

/** 使用者自己选过之后，就不再替他改默认来源 */
let userPicked = false

function onSourceChange(event: Event) {
  userPicked = true
  source.value = (event.target as HTMLSelectElement).value
  void load()
}

onMounted(async () => {
  await loadInstances()
  const first = instances.value[0]
  if (!userPicked && first) {
    // 有实例在跑就默认看它：这一页要回答的是「这只实例在说什么」，
    // 宿主日志那种文件口径留给插件开发者，排在分隔线之后
    source.value = 'instance:' + first.id
  } else if (source.value.startsWith('instance:') && !instances.value.some((i) => 'instance:' + i.id === source.value)) {
    // 实例读不到就别硬切：留在宿主日志，把失败写出来
    source.value = 'host'
  }
  void load()
})
</script>

<template>
  <section class="logs">
    <header class="page-head">
      <h1 class="page-title">日志</h1>
      <SourceBadge :tag="tag" />
    </header>

    <div class="toolbar">
      <div class="tool-left">
        <label class="field-label" for="log-source">来源</label>
        <select id="log-source" class="select" :value="source" @change="onSourceChange">
          <option
            v-for="item in instances"
            :key="'instance:' + item.id"
            :value="'instance:' + item.id"
            :title="'读该实例 DSH_HOME 下 logs 目录里最新的日志文件；实例未带 home 时按本机默认位置定位'"
          >
            dsh :{{ item.port }}
          </option>
          <option class="divider" disabled value="__divider__">————</option>
          <option v-for="item in FIXED_SOURCES" :key="item.id" :value="item.id">{{ item.label }}</option>
        </select>
      </div>
      <span class="meta" :title="meta">{{ meta }}</span>
      <button type="button" class="refresh" @click="load()">
        <AppIcon name="refresh" :size="13" />
        <span>刷新</span>
      </button>
    </div>

    <p v-if="instanceNote" class="inst-note">实例列表读取失败，实例条目为空：{{ instanceNote }}</p>

    <div v-if="lines.length > 0" ref="logBox" class="log-box">
      <div v-for="(line, i) in lines" :key="i" class="log-line">
        <span class="t">{{ line.time ?? '—' }}</span>
        <span class="lv" :class="levelClass(line.level)">{{ line.level ?? '··' }}</span>
        <span class="body">{{ line.text }}</span>
      </div>
    </div>

    <div v-else class="log-empty">
      <p class="empty-title">没有可显示的行</p>
      <p class="empty-detail">{{ tag.detail }}</p>
    </div>
  </section>
</template>
<style scoped>
.logs {
  display: flex;
  flex-direction: column;
  gap: 10px;
  height: 100%;
  min-height: 0;
  padding: 16px 22px 20px;
}
.page-head {
  flex: none;
  display: flex;
  align-items: center;
  gap: 10px;
}
.page-title {
  margin: 0;
  font-size: 21px;
  font-weight: 600;
  letter-spacing: 0.2px;
  white-space: nowrap;
}
.toolbar {
  flex: none;
  display: flex;
  align-items: center;
  gap: 12px;
}
.tool-left {
  display: flex;
  align-items: center;
  gap: 7px;
  flex: none;
}
.field-label {
  font-size: 11.5px;
  color: var(--text-dim);
}
.select {
  height: 30px;
  padding: 0 8px;
  border: 1px solid var(--line-strong);
  border-radius: var(--radius-sm);
  background: var(--panel-soft);
  color: var(--text);
  font-size: 12.5px;
  cursor: pointer;
}
.select:hover {
  border-color: var(--accent);
}
.meta {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 11px;
  color: var(--text-dim);
}
.inst-note {
  flex: none;
  margin: 0;
  font-size: 11.5px;
  color: var(--warn);
}
.select option.divider {
  color: var(--text-dim);
}
.refresh {
  flex: none;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  height: 30px;
  padding: 0 11px;
  border: 1px solid var(--line-strong);
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-mid);
  font-size: 12.5px;
  cursor: pointer;
}
.refresh:hover {
  background: var(--panel-soft);
  color: var(--text);
}
.log-box {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 8px 10px;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--panel);
}
.log-line {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 1px 0;
  font-family: "JetBrains Mono", "Noto Sans Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 11.5px;
  line-height: 1.6;
  white-space: pre;
}
.t {
  flex: none;
  color: var(--text-dim);
}
.lv {
  flex: none;
  width: 30px;
  text-align: center;
}
.lv-error {
  color: var(--danger);
}
.lv-warn {
  color: var(--warn);
}
.lv-none {
  color: var(--text-dim);
  opacity: 0.55;
}
.body {
  color: var(--text);
}
.log-empty {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: flex-start;
  gap: 6px;
  padding: 0 14px;
  border: 1px dashed var(--line-strong);
  border-radius: var(--radius);
  color: var(--text-dim);
}
.empty-title {
  margin: 0;
  font-size: 13px;
  color: var(--text-mid);
}
.empty-detail {
  margin: 0;
  font-size: 11.5px;
  line-height: 1.6;
}
</style>