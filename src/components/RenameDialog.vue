<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

/** 页面内重命名框：与 ConfirmDialog 同一套样式语言，中间换成一个输入框 */
const props = withDefaults(defineProps<{ title: string; initial: string }>(), {})
const emit = defineEmits<{ confirm: [name: string]; cancel: [] }>()

const cardRef = ref<HTMLElement | null>(null)
const inputRef = ref<HTMLInputElement | null>(null)
const draft = ref(props.initial)

const canConfirm = computed(() => draft.value.trim().length > 0)

function confirm() {
  if (!canConfirm.value) return
  emit('confirm', draft.value.trim())
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    event.preventDefault()
    event.stopPropagation()
    emit('cancel')
    return
  }
  if (event.key === 'Enter') {
    event.preventDefault()
    confirm()
    return
  }
  if (event.key !== 'Tab') return
  const focusables = cardRef.value?.querySelectorAll<HTMLElement>('input, button')
  if (!focusables || focusables.length === 0) return
  const first = focusables[0]
  const last = focusables[focusables.length - 1]
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault()
    last.focus()
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault()
    first.focus()
  }
}

onMounted(async () => {
  window.addEventListener('keydown', onKeydown, true)
  await nextTick()
  inputRef.value?.focus()
  inputRef.value?.select()
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown, true)
})
</script>

<template>
  <div class="scrim" @click.self="emit('cancel')">
    <div ref="cardRef" class="card" role="dialog" aria-modal="true" :aria-label="title">
      <h2 class="title">{{ title }}</h2>
      <input
        ref="inputRef"
        v-model="draft"
        class="input"
        type="text"
        aria-label="实例名称"
        spellcheck="false"
      />
      <div class="foot">
        <button type="button" class="btn primary" :disabled="!canConfirm" @click="confirm">
          确定
        </button>
        <button type="button" class="btn" @click="emit('cancel')">取消</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.scrim {
  position: fixed; inset: 0; z-index: 60;
  display: grid; place-items: center;
  background: rgba(8, 9, 11, 0.62);
}
.card {
  width: min(360px, calc(100vw - 48px));
  padding: 16px 16px 14px;
  display: flex; flex-direction: column; gap: 8px;
  background: var(--panel-soft);
  border: 1px solid var(--line-strong);
  border-radius: var(--radius);
  box-shadow: 0 18px 44px rgba(0, 0, 0, 0.5);
}
.title { margin: 0; font-size: 14px; font-weight: 600; color: var(--text); }
.input {
  height: 32px; padding: 0 10px;
  border: 1px solid var(--line-strong); border-radius: var(--radius-sm);
  background: var(--panel); color: var(--text);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 13px;
}
.input:focus-visible { outline: 2px solid var(--accent); outline-offset: -1px; }
.foot { display: flex; justify-content: flex-end; gap: 8px; margin-top: 4px; }
.btn {
  height: 30px; padding: 0 14px;
  display: inline-flex; align-items: center;
  border: 1px solid var(--line-strong); border-radius: var(--radius-sm);
  background: transparent; color: var(--text);
  font-size: 12.5px; cursor: pointer;
}
.btn:hover:not(:disabled) { background: var(--panel); }
.btn.primary { border-color: transparent; background: var(--accent); color: #fff; }
.btn.primary:hover:not(:disabled) { filter: brightness(1.08); }
.btn:disabled { opacity: 0.5; cursor: default; }
.btn:focus-visible { outline: 2px solid var(--text); outline-offset: 1px; }
</style>
