<script setup lang="ts">
import type { SourceTag } from '../data/types'
import SourceBadge from './SourceBadge.vue'

/** 一个分组：标题 + 计数 + 该组数据的数据源标记，行内容由插槽给 */
defineProps<{ title: string; count: number; source: SourceTag }>()
</script>

<template>
  <div class="section-head">
    <h2 class="section-title">{{ title }} ({{ count }})</h2>
    <SourceBadge :tag="source" />
  </div>

  <div class="rows">
    <slot />
  </div>
</template>

<style scoped>
.section-head {
  display: flex;
  align-items: center;
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
