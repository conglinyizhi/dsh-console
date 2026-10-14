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
const starting = computed(() => props.instance.status === 'starting')

/** 状态文案：启动等待期单独一档 */
const stateLabel = computed(() => {
  if (starting.value) return '正在启动…'
  return running.value ? '运行中' : '已停止'
})

/** 运行时长简写：分钟 -> 小时加分钟 */
const duration = computed(() => {
  const minutes = props.instance.uptime
  if (minutes < 60) return `${minutes} 分钟`
  return `${Math.floor(minutes / 60)} 小时 ${minutes % 60} 分钟`
})

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
  <article class="row" :data-instance="instance.name">
    <header class="row-head">
      <span class="tile" :class="instance.tone">
        <AppIcon :name="instance.tone === 'violet' ? 'puzzle' : 'launch'" :size="20" />
      </span>

      <div class="ident">
        <div class="title-line">
          <span class="name">{{ instance.name }}</span>
        </div>
        <div
          class="sub-line"
          :class="{ off: !running && !starting, starting }"
          :data-status="instance.status"
        >
          <span class="kind">{{ instance.kind }}</span>
          <span class="dot-slot"><i class="dot" /></span>
          <span class="state-label">{{ stateLabel }}</span>
          <span class="tail">
            <span v-if="starting" class="hint">等待核心就绪</span>
            <span v-else class="uptime">已运行 {{ duration }}</span>
            <span v-if="starting && instance.portNote" class="port-note">{{ instance.portNote }}</span>
          </span>
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
  /* 第三轨常态就是 --col-state（38px，容得下「运行中」的 36px）；
     「正在启动…」要 60px，用 max-content 让这一行自己撑开，别的行宽度不变，
     状态点与左侧标签轨仍然一个像素都不动 */
  grid-template-columns: var(--col-kind) 13px minmax(var(--col-state), max-content) minmax(0, 1fr);
  align-items: center; column-gap: 6px; min-width: 0;
  font-size: 12px; line-height: 18px; color: var(--ok);
}
/* 运行中 / 已停止 / 启动等待：三态共用同一副标题轨道，宽度不撑破列宽 */
.sub-line.off { color: var(--text-dim); }
.sub-line.starting { color: var(--warn); }
.sub-line.starting .dot {
  /* 等待态的点在动，收敛到 0.35 透明度再弹回 */
  box-shadow: 0 0 0 3px rgba(224, 164, 88, 0.16);
  animation: dot-pulse 900ms ease-in-out infinite;
}
@keyframes dot-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.32; }
}
.dot-slot {
  width: 13px; height: 13px;
  display: grid; place-items: center;
}
.dot {
  width: 7px; height: 7px; border-radius: 50%;
  background: currentColor; box-shadow: 0 0 0 3px rgba(78, 194, 122, 0.13);
}
.sub-line.off .dot { box-shadow: none; }
.state-label { font-size: 12px; white-space: nowrap; }
/* 末轨：常态一行「已运行」，启动等待期是「等待核心就绪」加一行端口探测说明 */
.tail { display: flex; flex-direction: column; min-width: 0; }
.uptime,
.hint,
.port-note {
  font-size: 10.5px; color: var(--text-dim);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.port-note { color: var(--text-mid); }
.fields {
  /* 固定两列：5 个字段恒为 2 / 2 / 1，不随窗口宽度塌成一列或涨成四列 */
  list-style: none; margin: 0; padding: 0;
  display: grid; grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 2px 20px;
}
.field {
  /* z-index: 0 让它成为层叠上下文，下面的 ::before 才能安全地压到内容之下 */
  position: relative; z-index: 0;
  display: flex; align-items: center; gap: 7px; height: 28px; min-width: 0;
}
/* 悬停提示：高亮画在 ::before 上并向外扩 6px，
   所以内容（图标 229 那条对齐）一个像素都不动 */
.field::before {
  content: '';
  position: absolute;
  z-index: -1;
  inset: 0 -6px;
  border-radius: var(--radius-sm);
  background: transparent;
  pointer-events: none;
}
.field:hover::before { background: var(--panel-soft); }
.field-icon { color: var(--text-dim); display: flex; }
.field-label { flex: none; font-size: 11.5px; color: var(--text-dim); }
.field-value {
  margin-left: auto; min-width: 0;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 11.5px; color: var(--text);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
</style>
