<script setup lang="ts">
import { ref } from 'vue'
import type { Instance } from '../data/types'
import AppIcon from './AppIcon.vue'

const props = defineProps<{ instance: Instance }>()
const emit = defineEmits<{
  unarchive: [id: string]
  delete: [id: string, trigger: HTMLElement | null]
}>()

const deleteRef = ref<HTMLButtonElement | null>(null)

function onDelete() {
  emit('delete', props.instance.id, deleteRef.value)
}
</script>

<template>
  <article class="archive-row">
    <span class="name">{{ instance.name }}</span>
    <span class="kind">{{ instance.kind }}</span>
    <span class="stamp">
      <span class="stamp-label">归档时间</span>
      <span class="stamp-value">{{ instance.archivedAt }}</span>
    </span>

    <span class="spacer" />

    <button type="button" class="btn" @click="emit('unarchive', instance.id)">
      <AppIcon name="unarchive" :size="14" />
      <span>取消归档</span>
    </button>
    <button
      v-if="instance.deletable"
      ref="deleteRef"
      type="button"
      class="btn danger"
      @click="onDelete"
    >
      <AppIcon name="delete" :size="14" />
      <span>删除</span>
    </button>
  </article>
</template>

<style scoped>
.archive-row {
  display: flex; align-items: center; gap: 10px;
  padding: 9px 14px;
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: var(--radius);
}
.name {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 13px; font-weight: 600; color: var(--text);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.kind {
  flex: none; padding: 2px 7px;
  border: 1px solid var(--line-strong); border-radius: 999px;
  font-size: 11px; line-height: 1.35; color: var(--text-mid);
  background: var(--panel-soft); white-space: nowrap;
}
.stamp { display: flex; align-items: center; gap: 6px; min-width: 0; }
.stamp-label { font-size: 11.5px; color: var(--text-dim); }
.stamp-value {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 11.5px; color: var(--text-mid);
}
.spacer { flex: 1; }
.btn {
  flex: none; height: 28px; padding: 0 9px;
  display: inline-flex; align-items: center; gap: 6px;
  border: 1px solid var(--line-strong); border-radius: var(--radius-sm);
  background: transparent; color: var(--text);
  font-size: 12.5px; cursor: pointer; white-space: nowrap;
}
.btn:hover { background: var(--panel-soft); }
.btn.danger { color: var(--danger); border-color: rgba(224, 104, 95, 0.42); }
.btn.danger:hover { background: rgba(224, 104, 95, 0.12); }
</style>
