<script setup lang="ts">
import AppIcon from '../components/AppIcon.vue'

defineProps<{ title: string }>()
</script>

<template>
  <section class="placeholder">
    <h1 class="ph-title">{{ title }}</h1>
    <p class="ph-text">
      <AppIcon name="grid" :size="15" />
      <span>这一页还没做</span>
    </p>
  </section>
</template>

<style scoped>
.placeholder {
  padding: 22px 26px;
}
.ph-title {
  margin: 0;
  font-size: 21px;
  font-weight: 600;
}
.ph-text {
  margin: 14px 0 0;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  border: 1px dashed var(--line-strong);
  border-radius: var(--radius);
  color: var(--text-dim);
  font-size: 13px;
}
</style>
