<script setup lang="ts">
import AppIcon from './AppIcon.vue'

/** 运行中分组的空态：本机真的没有检测到 dsh 进程时就这么说，不留假实例占位 */
defineProps<{ detail: string }>()
</script>

<template>
  <section class="empty">
    <span class="empty-icon"><AppIcon name="server" :size="26" /></span>
    <p class="line">当前没有检测到正在运行的 dsh 进程。</p>
    <p class="sub">扫描本机 /proc，带 --port 的 dsh 进程 0 个</p>
    <p class="sub" :title="detail">{{ detail }}</p>
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
.sub {
  margin: 0;
  font-size: 11px;
  color: var(--text-dim);
  max-width: 60ch;
}
</style>
