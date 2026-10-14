<script setup lang="ts">
import { computed } from 'vue'
import type { SourceTag } from '../data/types'
import AppIcon from './AppIcon.vue'

const props = defineProps<{ tag: SourceTag }>()

/** 真实数据 / 演示数据 / 演示数据 · 真实读取失败，三种标记各自一个图标与色调 */
const icon = computed(() => {
  if (props.tag.kind === 'real') return 'check'
  if (props.tag.kind === 'fallback') return 'shield'
  return 'sliders'
})
</script>

<template>
  <span class="badge" :class="tag.kind" :title="tag.detail">
    <AppIcon :name="icon" :size="12" />
    <span class="label">{{ tag.label }}</span>
  </span>
</template>

<style scoped>
.badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  flex: none;
  height: 20px;
  padding: 0 7px;
  border: 1px solid var(--line-strong);
  border-radius: 999px;
  background: var(--panel-soft);
  color: var(--text-dim);
  font-size: 10.5px;
  line-height: 1;
  white-space: nowrap;
}
.badge.real {
  color: var(--ok);
  border-color: rgba(78, 194, 122, 0.4);
  background: rgba(78, 194, 122, 0.1);
}
.badge.fallback {
  color: var(--warn);
  border-color: rgba(224, 164, 88, 0.42);
  background: rgba(224, 164, 88, 0.1);
}
</style>
