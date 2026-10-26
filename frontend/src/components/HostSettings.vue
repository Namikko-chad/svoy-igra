<script setup lang="ts">
import { ref } from 'vue'
import type { Settings } from '@/types/protocol'
import { settingsForm, settingsPatch, type GameSettingsForm } from '@/utils/special'
import ModalDialog from './ModalDialog.vue'
import SettingsFields from './SettingsFields.vue'

const props = defineProps<{ settings: Settings; title?: string }>()
const emit = defineEmits<{ close: []; save: [patch: GameSettingsForm] }>()
const form = ref(settingsForm(props.settings))
</script>

<template>
  <ModalDialog :title="title ?? 'Настройки игры'" @close="emit('close')">
    <form class="col" @submit.prevent="emit('save', settingsPatch(form))">
      <SettingsFields v-model="form" />
      <p class="muted small">Таймеры применяются со следующего вопроса, спецвопросы — со следующего раунда.</p>
      <div class="row" style="justify-content: flex-end">
        <button type="button" class="btn btn-ghost" @click="emit('close')">Отмена</button>
        <button class="btn btn-primary">Сохранить</button>
      </div>
    </form>
  </ModalDialog>
</template>
