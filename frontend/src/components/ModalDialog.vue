<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'

defineProps<{ title: string; wide?: boolean }>()
const emit = defineEmits<{ close: [] }>()
const box = ref<HTMLElement | null>(null)

function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape') emit('close')
}
onMounted(() => {
  document.addEventListener('keydown', onKey)
  box.value?.querySelector<HTMLElement>('[autofocus], input, textarea, button')?.focus()
})
onBeforeUnmount(() => document.removeEventListener('keydown', onKey))
</script>

<template>
  <Teleport to="body">
    <div class="backdrop" @mousedown.self="emit('close')">
      <div ref="box" class="dialog card" :class="{ wide }" role="dialog" aria-modal="true" :aria-label="title">
        <div class="head">
          <h2>{{ title }}</h2>
          <button class="btn btn-ghost btn-icon" aria-label="Закрыть" @click="emit('close')">✕</button>
        </div>
        <div class="body"><slot /></div>
        <div v-if="$slots.actions" class="actions"><slot name="actions" /></div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.backdrop {
  position: fixed;
  inset: 0;
  background: rgba(3, 6, 20, 0.72);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: var(--sp-4);
  z-index: 900;
}
.dialog {
  width: min(440px, 100%);
  max-height: calc(100dvh - 32px);
  overflow: auto;
}
.dialog.wide {
  width: min(960px, 100%);
}
.head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--sp-2);
}
.actions {
  display: flex;
  justify-content: flex-end;
  gap: var(--sp-2);
  margin-top: var(--sp-4);
  flex-wrap: wrap;
}
</style>
