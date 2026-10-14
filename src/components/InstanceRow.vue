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

      <div class="ident">
        <div class="title-line">
          <span class="name">{{ instance.name }}</span>
        </div>
        <div class="sub-line" :class="{ off: !running }">
          <span class="kind">{{ instance.kind }}</span>
          <span class="dot-slot"><i class="dot" /></span>
          <span class="state-label">{{ running ? '运行中' : '已停止' }}</span>
          <span class="uptime">已运行 {{ instance.uptime }}</span>
        </div>
      </div>

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
  /* 两卡共用同一套列宽，逐项左右边界可比。
     副标题内部同样是固定轨道：类型标签列宽固定，状态点不跟着 pill 走 */
  --col-kind: 112px;
  --col-state: 38px;
  position: relative;
  display: flex; flex-direction: column; gap: 12px;
  padding: 14px 16px 15px;
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: var(--radius);
}
.row-head {
  /* 三列固定栅格：图标底板（跨两行垂直居中）| 两行文本块 | 按钮组。
     两卡列宽一致，标题行左边界、副标题行左边界、按钮组右边界逐项可比 */
  display: grid;
  grid-template-columns: 40px minmax(0, 1fr) auto;
  align-items: center; column-gap: 10px;
}
.tile { width: 40px; height: 40px; flex: none; border-radius: 10px; display: grid; place-items: center; }
.tile.accent { background: rgba(78, 194, 122, 0.14); color: var(--ok); }
.tile.violet { background: var(--violet-soft); color: var(--violet); }
.ident {
  /* 标题行 + 副标题行，行间距 2px，两行同一起点、左对齐 */
  min-width: 0; display: flex; flex-direction: column; gap: 2px;
}
.title-line { min-width: 0; }
.name {
  display: block;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 15px; font-weight: 600; line-height: 22px; color: var(--text);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.kind {
  justify-self: start; align-self: center;
  padding: 1px 6px;
  border: 1px solid var(--line-strong); border-radius: 999px;
  font-size: 10.5px; line-height: 1.3; color: var(--text-mid);
  background: var(--panel-soft); white-space: nowrap;
}
.sub-line {
  /* 副标题行：类型标签 + 状态点 + 状态文案 + 时长，段间只靠 6px 间距分开，不用分隔符。
     四段都是固定轨道：第一列是固定宽度的标签列，pill 靠列首摆放，
     所以状态点的 x 不随 pill 内容变化，两卡的点在同一列上。
     标签列宽（112px）大于最宽 pill（102px），pill 右缘到 13px 点槽的净间距 ≥16px，
     不再依赖"额外 padding 抵消光环"，"点吸住标签"不会回来。
     点槽恒为 13px（7px 点 + 两边各 3px 光环），光环在槽位内，
     运行中与已停止两态几何完全一致，切状态时点不跳。 */
  display: grid;
  grid-template-columns: var(--col-kind) 13px var(--col-state) minmax(0, 1fr);
  align-items: center; column-gap: 6px; min-width: 0;
  font-size: 12px; line-height: 18px; color: var(--ok);
}
.sub-line.off { color: var(--text-dim); }
.dot-slot {
  width: 13px; height: 13px;
  display: grid; place-items: center;
}
.dot {
  width: 7px; height: 7px; border-radius: 50%;
  background: currentColor; box-shadow: 0 0 0 3px rgba(78, 194, 122, 0.13);
}
.sub-line.off .dot { box-shadow: none; }
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
