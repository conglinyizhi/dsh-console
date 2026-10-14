<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

/** 页面内二次确认框：Esc 关闭、打开时焦点进框、Tab 不跑出框外 */
withDefaults(
  defineProps<{
    title: string
    message?: string
    confirmText?: string
    cancelText?: string
    danger?: boolean
  }>(),
  { message: '', confirmText: '确认', cancelText: '取消', danger: false },
)

const emit = defineEmits<{ confirm: []; cancel: [] }>()

const cardRef = ref<HTMLElement | null>(null)
const confirmRef = ref<HTMLButtonElement | null>(null)

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    event.preventDefault()
    event.stopPropagation()
    emit('cancel')
    return
  }
  if (event.key !== 'Tab') return
  const focusables = cardRef.value?.querySelectorAll<HTMLButtonElement>('button')
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
  confirmRef.value?.focus()
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown, true)
})
</script>

<template>
  <div class="scrim" @click.self="emit('cancel')">
    <div ref="cardRef" class="card" role="dialog" aria-modal="true" :aria-label="title">
      <h2 class="title">{{ title }}</h2>
      <p v-if="message" class="message">{{ message }}</p>
      <div class="foot">
        <button
          ref="confirmRef"
          type="button"
          class="btn"
          :class="danger ? 'danger' : 'primary'"
          @click="emit('confirm')"
        >
          {{ confirmText }}
        </button>
        <button type="button" class="btn" @click="emit('cancel')">{{ cancelText }}</button>
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
.message { margin: 0; font-size: 12px; line-height: 1.6; color: var(--text-mid); }
.foot { display: flex; justify-content: flex-end; gap: 8px; margin-top: 4px; }
.btn {
  height: 30px; padding: 0 14px;
  display: inline-flex; align-items: center;
  border: 1px solid var(--line-strong); border-radius: var(--radius-sm);
  background: transparent; color: var(--text);
  font-size: 12.5px; cursor: pointer;
}
.btn:hover { background: var(--panel); }
.btn.primary { border-color: transparent; background: var(--accent); color: #fff; }
.btn.primary:hover { filter: brightness(1.08); }
.btn.danger { border-color: transparent; background: var(--danger); color: #fff; }
.btn.danger:hover { filter: brightness(1.08); }
.btn:focus-visible { outline: 2px solid var(--text); outline-offset: 1px; }
</style>
