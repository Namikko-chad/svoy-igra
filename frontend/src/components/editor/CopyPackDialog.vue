<script setup lang="ts">
import { ref } from 'vue'
import ModalDialog from '@/components/ModalDialog.vue'

const props = defineProps<{ title: string }>()
const emit = defineEmits<{ confirm: [title: string]; cancel: [] }>()
const value = ref(`${props.title} (копия)`)
</script>

<template>
  <ModalDialog title="Редактировать копию" @close="emit('cancel')">
    <form class="col" @submit.prevent="value.trim() && emit('confirm', value.trim())">
      <p class="muted small" style="margin: 0">
        Пак «{{ title }}» заблокирован. Будет создана редактируемая копия со всеми медиафайлами.
      </p>
      <label class="field">
        Название копии
        <input v-model="value" class="input" maxlength="200" autofocus required />
      </label>
      <div class="row" style="justify-content: flex-end">
        <button type="button" class="btn btn-ghost" @click="emit('cancel')">Отмена</button>
        <button class="btn btn-primary" :disabled="!value.trim()">Создать копию</button>
      </div>
    </form>
  </ModalDialog>
</template>
