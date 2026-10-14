<script setup lang="ts">
import type { Instance, SourceTag } from '../data/types'
import ArchivedRow from './ArchivedRow.vue'
import SourceBadge from './SourceBadge.vue'

/** 归档区：本轮不接真实数据（磁盘上没有「归档记录」这种概念），整组都是演示 */
defineProps<{ items: Instance[]; source: SourceTag }>()
defineEmits<{
  unarchive: [id: string]
  delete: [id: string, trigger: HTMLElement | null]
}>()
</script>

<template>
  <template v-if="items.length > 0">
    <div class="section-head">
      <h2 class="section-title">已归档 ({{ items.length }})</h2>
      <SourceBadge :tag="source" />
    </div>

    <div class="rows">
      <ArchivedRow
        v-for="item in items"
        :key="item.id"
        :instance="item"
        @unarchive="$emit('unarchive', $event)"
        @delete="(id, trigger) => $emit('delete', id, trigger)"
      />
    </div>
  </template>
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
