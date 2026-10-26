<script setup lang="ts">
import { ref } from 'vue'
import { avatarApi } from '@/api'
import { errorMessage } from '@/api/http'
import { makeAvatar } from '@/utils/avatar'
import { useToastStore } from '@/stores/toast'
import AvatarImg from './AvatarImg.vue'

/** Pick → crop to a centered square ≤ 512 px → upload; or remove. The new URL arrives via `state`. */
const props = defineProps<{ token: string; url: string | null; name: string; compact?: boolean }>()
const toast = useToastStore()
const input = ref<HTMLInputElement | null>(null)
const busy = ref(false)
// Shown right away; the server's state replaces it a moment later.
const preview = ref<string | null>(null)

async function onPick(ev: Event) {
  const el = ev.target as HTMLInputElement
  const file = el.files?.[0]
  el.value = ''
  if (!file) return
  busy.value = true
  try {
    const { blob, filename } = await makeAvatar(file)
    const res = await avatarApi(props.token).upload(blob, filename)
    preview.value = res.avatarUrl
    toast.success('Аватар обновлён')
  } catch (e) {
    toast.error(errorMessage(e))
  } finally {
    busy.value = false
  }
}
async function remove() {
  busy.value = true
  try {
    await avatarApi(props.token).remove()
    preview.value = null
    toast.success('Аватар удалён')
  } catch (e) {
    toast.error(errorMessage(e))
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="ae" :class="{ compact }">
    <AvatarImg :url="url ?? preview" :name="name" :size="compact ? 48 : 64" />
    <div class="col actions">
      <span v-if="!compact" class="muted small">Аватар видят все участники игры</span>
      <div class="row">
        <button class="btn btn-sm" :disabled="busy" @click="input?.click()">
          {{ busy ? 'Загрузка…' : url ? 'Сменить фото' : 'Загрузить фото' }}
        </button>
        <button v-if="url" class="btn btn-ghost btn-sm danger" :disabled="busy" @click="remove">Удалить</button>
      </div>
    </div>
    <input ref="input" type="file" accept="image/png,image/jpeg,image/webp,image/gif" hidden @change="onPick" />
  </div>
</template>

<style scoped>
.ae {
  display: flex;
  align-items: center;
  gap: var(--sp-3);
}
.actions {
  gap: var(--sp-1);
}
</style>
