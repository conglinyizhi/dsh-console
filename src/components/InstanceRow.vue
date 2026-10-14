<script setup lang="ts">
import { computed } from 'vue'
import type { Instance } from '../mock/instances'
import type { ActionKey } from '../actions'
import type { IconName } from './icons'
import AppIcon from './AppIcon.vue'
import InstanceActions from './InstanceActions.vue'

interface FieldRow {
  icon: IconName
  label: string
  value: string
}

const props = defineProps<{ instance: Instance }>()
const emit = defineEmits<{ action: [key: ActionKey, trigger: HTMLElement | null] }>()

const running = computed(() => props.instance.status === 'running')

function forward(key: ActionKey, trigger: HTMLElement | null) {
  emit('action', key, trigger)
}

const fields = computed<FieldRow[]>(() => {
  const it = props.instance
  return [
    { icon: 'tag', label: 'DSH 版本 / 来源', value: it.version },
    { icon: 'layers', label: 'Profile', value: it.profile },
    { icon: 'link', label: '访问地址', value: it.url },
    { icon: 'home', label: 'DSH_HOME', value: it.home },
    { icon: 'puzzle', label: '插件数量', value: it.pluginCount },
  ]
})
</script>

<template>
  <article class="row">
    <header class="row-head">
      <span class="tile" :class="instance.tone">
        <AppIcon :name="instance.tone === 'violet' ? 'puzzle' : 'launch'" :size="20" />
      </span>

      <span class="ident">
        <span class="name-line">
          <span class="name">{{ instance.name }}</span>
          <span class="kind">{{ instance.kind }}</span>
        </span>
      </span>

      <span class="state" :class="{ off: !running }">
        <i class="dot" />
        <span class="state-label">{{ running ? '运行中' : '已停止' }}</span>
        <span class="uptime">已运行 {{ instance.uptime }}</span>
      </span>

      <InstanceActions :instance="instance" @action="forward" />
    </header>

    <ul class="fields">
      <li v-for="field in fields" :key="field.label" class="field">
        <span class="field-icon"><AppIcon :name="field.icon" :size="14" /></span>
        <span class="field-label">{{ field.label }}</span>
        <span class="field-value">{{ field.value }}</span>
      </li>
    </ul>
  </article>
</template>

<style scoped>
.row {
  /* 两卡共用同一套列宽，逐项左右边界可比 */
  --col-ident: 188px;
  --col-name: 90px;
  --col-kind: 106px;
  --col-state: 38px;
  position: relative;
  display: flex; flex-direction: column; gap: 12px;
  padding: 14px 16px 15px;
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: var(--radius);
}
.row-head {
  /* 固定栅格：图标底板、名称、类型标签、状态、按钮组各自的轨道固定，
     两卡的列左边界与按钮组右边界逐项一致，不靠内容自然撑开 */
  display: grid;
  grid-template-columns: 40px var(--col-ident) minmax(0, 1fr) auto;
  align-items: center; column-gap: 10px;
}
.tile { width: 40px; height: 40px; flex: none; border-radius: 10px; display: grid; place-items: center; }
.tile.accent { background: rgba(78, 194, 122, 0.14); color: var(--ok); }
.tile.violet { background: var(--violet-soft); color: var(--violet); }
.ident { min-width: 0; display: flex; }
.name-line {
  display: grid; grid-template-columns: var(--col-name) var(--col-kind);
  align-items: center; column-gap: 6px; min-width: 0;
}
.name {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 14px; font-weight: 600; color: var(--text);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.kind {
  flex: none; padding: 2px 7px;
  border: 1px solid var(--line-strong); border-radius: 999px;
  font-size: 11px; line-height: 1.35; color: var(--text-mid);
  background: var(--panel-soft); white-space: nowrap;
}
.state {
  /* 状态点、状态文案、时长共用卡头这一条中心线：起点分别为固定轨道 */
  display: grid; grid-template-columns: 7px var(--col-state) minmax(0, 1fr);
  align-items: center; column-gap: 6px; min-width: 0; color: var(--ok);
}
.state.off { color: var(--text-dim); }
.dot {
  width: 7px; height: 7px; border-radius: 50%;
  background: currentColor; box-shadow: 0 0 0 3px rgba(78, 194, 122, 0.13);
}
.state.off .dot { box-shadow: none; }
.state-label { font-size: 12px; }
.uptime {
  font-size: 10.5px; color: var(--text-dim);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.fields {
  /* 固定两列：5 个字段恒为 2 / 2 / 1，不随窗口宽度塌成一列或涨成四列 */
  list-style: none; margin: 0; padding: 0;
  display: grid; grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 2px 20px;
}
.field { display: flex; align-items: center; gap: 7px; height: 28px; min-width: 0; }
.field-icon { color: var(--text-dim); display: flex; }
.field-label { flex: none; font-size: 11.5px; color: var(--text-dim); }
.field-value {
  margin-left: auto; min-width: 0;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 11.5px; color: var(--text);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
</style>
