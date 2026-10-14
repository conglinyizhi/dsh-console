<script setup lang="ts">
import AppIcon from './AppIcon.vue'
</script>

<template>
  <section class="empty">
    <span class="empty-icon"><AppIcon name="cube" :size="26" /></span>
    <p class="line">还没有已停止的实例。</p>
  </section>
</template>

<style scoped>
.empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 3px;
  padding: 30px 16px 32px;
  border: 1px dashed var(--line-strong);
  border-radius: var(--radius);
  background: rgba(255, 255, 255, 0.014);
  text-align: center;
}
.empty-icon {
  color: var(--text-dim);
  margin-bottom: 8px;
}
.line {
  margin: 0;
  font-size: 12.5px;
  color: var(--text-mid);
}
</style>
