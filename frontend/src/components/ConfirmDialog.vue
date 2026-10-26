<script setup lang="ts">
import ModalDialog from './ModalDialog.vue'

withDefaults(defineProps<{ title: string; confirmText?: string; danger?: boolean }>(), {
  confirmText: 'Подтвердить',
  danger: true,
})
const emit = defineEmits<{ confirm: []; cancel: [] }>()
</script>

<template>
  <ModalDialog :title="title" @close="emit('cancel')">
    <slot />
    <template #actions>
      <button class="btn btn-ghost" @click="emit('cancel')">Отмена</button>
      <button class="btn" :class="danger ? 'btn-danger' : 'btn-primary'" @click="emit('confirm')">
        {{ confirmText }}
      </button>
    </template>
  </ModalDialog>
</template>
