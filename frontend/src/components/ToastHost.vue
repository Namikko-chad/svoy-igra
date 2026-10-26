<script setup lang="ts">
import { useToastStore } from '@/stores/toast'
const toast = useToastStore()
</script>

<template>
  <div class="toasts" aria-live="polite">
    <TransitionGroup name="toast">
      <button v-for="t in toast.toasts" :key="t.id" class="toast" :class="t.kind" @click="toast.dismiss(t.id)">
        {{ t.text }}
      </button>
    </TransitionGroup>
  </div>
</template>

<style scoped>
.toasts {
  position: fixed;
  left: 50%;
  bottom: calc(var(--sp-4) + env(safe-area-inset-bottom));
  transform: translateX(-50%);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--sp-2);
  z-index: 1000;
  width: min(480px, calc(100vw - 32px));
  pointer-events: none;
}
.toast {
  pointer-events: auto;
  width: 100%;
  padding: var(--sp-3) var(--sp-4);
  border-radius: var(--r-card);
  border: 1px solid var(--border);
  background: var(--surface-2);
  color: var(--text);
  font: 500 var(--fs-14) / 1.35 var(--font-body);
  text-align: center;
  cursor: pointer;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
}
.toast.error {
  border-color: var(--danger);
  background: #3a0f1c;
}
.toast.success {
  border-color: var(--success);
  background: #0c2e22;
}
.toast.warning {
  border-color: var(--warning);
  background: #33260a;
}
.toast-enter-active,
.toast-leave-active {
  transition: all var(--t-phase);
}
.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translateY(12px);
}
</style>
