<script setup lang="ts">
import { safetyChecks, workflows } from '../mock/instances'
import AppIcon from './AppIcon.vue'

const flowIcons = ['branch', 'launch'] as const
const flowTones = ['accent', 'violet'] as const
</script>

<template>
  <aside class="side-info">
    <section class="card">
      <h2 class="card-title">工作流入口</h2>
      <div class="flows">
        <button
          v-for="(flow, i) in workflows"
          :key="flow.title"
          type="button"
          class="flow"
        >
          <span class="flow-icon" :class="flowTones[i % flowTones.length]">
            <AppIcon :name="flowIcons[i % flowIcons.length]" :size="16" />
          </span>
          <span class="flow-body">
            <span class="flow-title">{{ flow.title }}</span>
            <span class="flow-detail">{{ flow.detail }}</span>
          </span>
          <span class="flow-arrow"><AppIcon name="chevronRight" :size="14" /></span>
        </button>
      </div>
    </section>

    <section class="card">
      <h2 class="card-title">关于实例</h2>
      <ul class="notes">
        <li v-for="item in safetyChecks" :key="item" class="note">
          <span class="note-text">{{ item }}</span>
        </li>
      </ul>
    </section>
  </aside>
</template>

<style scoped>
.side-info {
  width: 260px;
  flex: none;
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 18px 16px 20px;
  border-left: 1px solid var(--line);
  background: var(--bg);
  overflow-y: auto;
}
.card {
  padding: 12px 13px 13px;
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: var(--radius);
}
.card-title {
  margin: 0 0 10px;
  font-size: 12.5px;
  font-weight: 600;
  color: var(--text-mid);
  letter-spacing: 0.2px;
}
.flows {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.flow {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: flex-start;
  gap: 8px;
  width: 100%;
  padding: 9px 8px;
  border: 1px solid transparent;
  border-radius: 8px;
  background: var(--panel-soft);
  color: inherit;
  cursor: pointer;
  text-align: left;
}
.flow:hover {
  border-color: var(--line-strong);
}
.flow-icon {
  margin-top: 1px;
  display: flex;
}
.flow-icon.accent {
  color: var(--accent);
}
.flow-icon.violet {
  color: var(--violet);
}
.flow-body {
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
}
.flow-title {
  font-size: 12px;
  color: var(--text);
}
.flow-detail {
  font-size: 10.5px;
  line-height: 1.5;
  color: var(--text-dim);
}
.flow-arrow {
  margin-top: 2px;
  color: var(--text-dim);
  display: flex;
}
.notes {
  margin: 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 11px;
}
.note {
  display: flex;
  align-items: flex-start;
}
.note-text {
  min-width: 0;
  font-size: 11px;
  line-height: 1.55;
  color: var(--text-dim);
}
</style>
