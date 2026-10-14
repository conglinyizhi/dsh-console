<script setup lang="ts">
import AppIcon from './AppIcon.vue'

/** 运行中分组的空态：监听端口扫完、一个 DSH 签名都没命中时才出现，不留假实例占位 */
defineProps<{ summary: string; detail: string }>()
</script>

<template>
  <section class="empty">
    <span class="empty-icon"><AppIcon name="server" :size="26" /></span>
    <p class="line">当前没有检测到正在运行的 dsh 实例。</p>
    <p class="sub">{{ summary }}</p>
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
