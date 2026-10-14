<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { fetchRuntime, type LocalRuntime } from '../api/local'

const readTime = ref('')

/** 版本表：每项都是真实读数，读不到就写读取失败与原因，不留空 */
const rows = ref<{ label: string; value: string; hint?: string }[]>([])

function buildRows(data: LocalRuntime | null, reason: string | null) {
  if (!data) {
    return [{ label: '读取状态', value: '读取失败', hint: reason ?? '未知原因' }]
  }
  return [
    { label: 'dsh 版本', value: data.dshVersion, hint: data.dshPackageName },
    { label: 'node 版本', value: data.nodeVersion },
    { label: '控制台版本', value: data.consoleVersion ?? '未知', hint: data.consolePackageName ?? undefined },
    { label: '平台', value: data.platform },
  ]
}

async function load() {
  const read = await fetchRuntime()
  readTime.value = new Date().toLocaleTimeString('zh-CN', { hour12: false })
  rows.value = buildRows(read.ok ? read.data : null, read.error)
}

onMounted(() => {
  void load()
})
</script>

<template>
  <section class="about">
    <header class="page-head">
      <h1 class="page-title">关于</h1>
    </header>

    <section class="panel">
      <p class="para">面向个人本机使用的 DSH 控制台，用来查看这台机器上的 DeepSeek Harness 实例。</p>
      <p class="para">只读本机 ~/.dsh；页面上的动作均为演示。</p>
    </section>

    <section class="panel">
      <h2 class="panel-title">版本</h2>
      <div class="kv">
        <div v-for="row in rows" :key="row.label" class="row">
          <span class="label">{{ row.label }}</span>
          <span class="value" :title="row.hint">{{ row.value }}</span>
        </div>
      </div>
      <p class="foot">读于 {{ readTime }} · 来源 GET /api/local/runtime</p>
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
  padding: 6px 0;
  border-bottom: 1px solid var(--line);
}
.row:last-child {
  border-bottom: 0;
}
.label {
  flex: none;
  width: 88px;
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
