<script setup lang="ts">
import AppIcon from './AppIcon.vue'
</script>

<template>
  <header class="topbar">
    <span class="spacer" />
    <button type="button" class="settings">
      <AppIcon name="settings" :size="14" />
      <span>设置</span>
    </button>
  </header>
</template>

<style scoped>
.topbar {
  flex: none;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  padding: 0 22px;
  border-bottom: 1px solid var(--line);
  background: var(--bg);
}
.spacer {
  flex: 1;
}
.settings {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 30px;
  padding: 0 12px;
  border: 1px solid var(--line-strong);
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-mid);
  font-size: 12.5px;
  cursor: pointer;
}
.settings:hover {
  background: var(--panel-soft);
  color: var(--text);
}
</style>
