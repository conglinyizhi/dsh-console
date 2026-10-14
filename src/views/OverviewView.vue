<script setup lang="ts">
import { computed, reactive } from 'vue'
import { instances as seed } from '../mock/instances'
import type { Instance } from '../mock/instances'
import InstanceRow from '../components/InstanceRow.vue'
import StoppedEmpty from '../components/StoppedEmpty.vue'
import SideInfoPanel from '../components/SideInfoPanel.vue'

const list = reactive<Instance[]>(seed.map((item) => ({ ...item })))

const running = computed(() => list.filter((item) => item.status === 'running'))
const stopped = computed(() => list.filter((item) => item.status === 'stopped'))

function toggle(id: string) {
  const item = list.find((entry) => entry.id === id)
  if (item) item.status = item.status === 'running' ? 'stopped' : 'running'
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
          @toggle="toggle"
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
          @toggle="toggle"
        />
        <StoppedEmpty v-if="stopped.length === 0" />
      </div>
    </section>

    <SideInfoPanel />
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
