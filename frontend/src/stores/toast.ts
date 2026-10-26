import { defineStore } from 'pinia'
import { ref } from 'vue'

export type ToastKind = 'info' | 'success' | 'error' | 'warning'
export type Toast = { id: number; kind: ToastKind; text: string }

export const useToastStore = defineStore('toast', () => {
  const toasts = ref<Toast[]>([])
  let seq = 0
  function push(text: string, kind: ToastKind = 'info', ms = 3000) {
    const id = ++seq
    toasts.value = [...toasts.value.slice(-3), { id, kind, text }]
    setTimeout(() => dismiss(id), ms)
  }
  function dismiss(id: number) {
    toasts.value = toasts.value.filter((t) => t.id !== id)
  }
  return {
    toasts,
    push,
    dismiss,
    error: (t: string) => push(t, 'error'),
    success: (t: string) => push(t, 'success'),
    info: (t: string) => push(t, 'info'),
  }
})
