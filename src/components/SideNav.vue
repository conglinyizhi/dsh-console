<script setup lang="ts">
import { navItems, type NavKey } from '../nav'
import AppIcon from './AppIcon.vue'

defineProps<{ current: NavKey }>()
const emit = defineEmits<{ select: [key: NavKey] }>()
</script>

<template>
  <aside class="side">
    <div class="brand">
      <span class="brand-icon"><AppIcon name="logo" :size="17" /></span>
      <span class="brand-title">DSH 控制台</span>
    </div>

    <nav class="nav">
      <button
        v-for="item in navItems"
        :key="item.key"
        type="button"
        class="nav-item"
        :class="{ active: item.key === current }"
        @click="emit('select', item.key)"
      >
        <span class="nav-icon"><AppIcon :name="item.icon" :size="16" /></span>
        <span class="nav-label">{{ item.label }}</span>
      </button>
    </nav>

    <p class="side-foot">
      <i class="dot" />
      <span>本机运行，仅限回环访问</span>
    </p>
  </aside>
</template>

<style scoped>
.side {
  width: 190px;
  flex: none;
  background: var(--panel);
  border-right: 1px solid var(--line);
  display: flex;
  flex-direction: column;
  padding: 12px 11px 10px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 0 4px 12px;
}
.brand-icon {
  width: 26px;
  height: 26px;
  flex: none;
  border-radius: 8px;
  display: grid;
  place-items: center;
  color: #fff;
  background: linear-gradient(140deg, var(--accent), var(--violet));
}
.brand-title {
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.2px;
}
.nav {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.nav-item {
  display: flex;
  align-items: center;
  gap: 9px;
  width: 100%;
  height: 36px;
  padding: 0 10px;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: var(--text-mid);
  cursor: pointer;
  text-align: left;
}
.nav-item:hover {
  background: var(--panel-soft);
  color: var(--text);
}
.nav-item.active {
  background: var(--accent-soft);
  color: var(--text);
}
.nav-icon {
  color: var(--text-dim);
  display: flex;
}
.nav-item.active .nav-icon {
  color: var(--accent);
}
.nav-label {
  font-size: 13px;
}
.side-foot {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: auto 0 0;
  padding: 0 2px;
  font-size: 10px;
  line-height: 1.4;
  color: var(--text-dim);
}
.dot {
  width: 5px;
  height: 5px;
  flex: none;
  border-radius: 50%;
  background: var(--ok);
}
</style>
