<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { fetchRuntime, type LocalRuntime } from '../api/local'

const runtime = ref<LocalRuntime | null>(null)
const error = ref<string | null>(null)
const readTime = ref('')

/** 当前读数逐条来自 /api/local/runtime；读不到就写读失败与原因，不留空 */
const rows = ref<{ label: string; value: string; hint?: string }[]>([])

function buildRows(data: LocalRuntime | null, reason: string | null) {
  if (!data) {
    return [{ label: '读取状态', value: '读取失败', hint: reason ?? '未知原因' }]
  }
  return [
    { label: 'dsh 版本', value: data.dshVersion, hint: data.dshPackageName },
    { label: 'node 版本', value: data.nodeVersion },
    { label: 'DSH_HOME', value: data.dshHome, hint: data.dshHomeSource },
    { label: '活动 profile', value: data.dshProfile ?? '未指定（DSH_PROFILE 为空）' },
    { label: '平台', value: data.platform },
  ]
}

async function load() {
  const read = await fetchRuntime()
  readTime.value = new Date().toLocaleTimeString('zh-CN', { hour12: false })
  runtime.value = read.ok ? read.data : null
  error.value = read.ok ? null : read.error
  rows.value = buildRows(runtime.value, error.value)
}

onMounted(() => {
  void load()
})
</script>

<template>
  <section class="about">
    <header class="page-head">
      <h1 class="page-title">关于</h1>
      <p class="lede">本机 DSH 实例的启动与管理入口，只读展示。</p>
    </header>

    <section class="panel">
      <h2 class="panel-title">这是什么</h2>
      <p class="para">面向个人本机使用的控制台，用来查看和管理这台机器上的 DSH 实例。</p>
      <p class="para">页面只读本机 ~/.dsh 与进程事实，不参与实例的实际启停。</p>
    </section>

    <section class="panel">
      <h2 class="panel-title">当前读数</h2>
      <div class="kv">
        <div v-for="row in rows" :key="row.label" class="row">
          <span class="label">{{ row.label }}</span>
          <span class="value" :title="row.hint">{{ row.value }}</span>
        </div>
      </div>
      <p class="foot">读于 {{ readTime }} · 来源 GET /api/local/runtime</p>
    </section>

    <section class="panel">
      <h2 class="panel-title">数据与只读</h2>
      <p class="para">读的是 ~/.dsh 里的真实内容，凭据类文件只判断存在，不读内容。</p>
      <p class="para">本地接口只接受 GET，其余方法返回 405。</p>
      <p class="para">动作仍是演示：不会真的起停进程，也不写磁盘。</p>
    </section>

    <section class="panel">
      <h2 class="panel-title">技术</h2>
      <p class="para">Vite + Vue 3 + TypeScript，后续套 Electron 外壳。</p>
    </section>
  </section>
</template>

<style scoped>
.about {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 22px 24px;
  max-width: 760px;
}
.page-head {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.page-title {
  margin: 0;
  font-size: 21px;
  font-weight: 600;
  letter-spacing: 0.2px;
}
.lede {
  margin: 0;
  font-size: 12.5px;
  color: var(--text-dim);
}
.panel {
  padding: 13px 15px 14px;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--panel);
}
.panel-title {
  margin: 0 0 10px;
  font-size: 12.5px;
  font-weight: 600;
  color: var(--text-mid);
  letter-spacing: 0.2px;
}
.para {
  margin: 0 0 6px;
  font-size: 12.5px;
  line-height: 1.7;
  color: var(--text-dim);
}
.para:last-child {
  margin-bottom: 0;
}
.kv {
  display: flex;
  flex-direction: column;
}
.row {
  display: flex;
  align-items: baseline;
  gap: 12px;
  padding: 7px 0;
  border-bottom: 1px solid var(--line);
}
.row:last-child {
  border-bottom: 0;
}
.label {
  flex: none;
  width: 92px;
  font-size: 12px;
  color: var(--text-dim);
}
.value {
  min-width: 0;
  font-size: 12.5px;
  color: var(--text);
  word-break: break-all;
}
.foot {
  margin: 10px 0 0;
  font-size: 11px;
  color: var(--text-dim);
}
</style>
