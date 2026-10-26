<script setup lang="ts">
import { computed, ref } from 'vue'
import { packsApi } from '@/api'
import { errorMessage } from '@/api/http'
import { useToastStore } from '@/stores/toast'
import { mediaKind } from '@/utils/blocks'
import { formatBytes } from '@/utils/time'
import { sanitizeMediaName } from '@/utils/mediaName'
import type { Media } from '@/types/protocol'
import ConfirmDialog from '@/components/ConfirmDialog.vue'

const props = defineProps<{ packId: string; token: string | null; media: Media[]; canInsert?: boolean }>()
const emit = defineEmits<{ 'update:media': [media: Media[]]; insert: [name: string]; error: [e: unknown] }>()
const toast = useToastStore()
const api = packsApi(props.token)

const filter = ref('')
const sorted = computed(() =>
  [...props.media]
    .filter((m) => !filter.value || m.name.toLowerCase().includes(filter.value.toLowerCase()))
    .sort((a, b) => a.name.localeCompare(b.name)),
)

type Upload = { id: number; name: string; progress: number; error?: string }
const uploads = ref<Upload[]>([])
let seq = 0
const fileInput = ref<HTMLInputElement | null>(null)

async function onFiles(ev: Event) {
  const input = ev.target as HTMLInputElement
  const files = Array.from(input.files ?? [])
  input.value = ''
  const queue = files.map((f) => ({ file: f, up: { id: ++seq, name: sanitizeMediaName(f.name), progress: 0 } as Upload }))
  uploads.value = [...uploads.value, ...queue.map((q) => q.up)]
  for (const { file, up } of queue) {
    const entry = () => uploads.value.find((u) => u.id === up.id)
    try {
      const media = await api.uploadMedia(props.packId, file, up.name, (f) => {
        const e = entry()
        if (e) e.progress = f
      }).promise
      emit('update:media', [...props.media.filter((m) => m.name !== media.name), media])
      uploads.value = uploads.value.filter((u) => u.id !== up.id)
    } catch (e) {
      const en = entry()
      if (en) en.error = errorMessage(e)
      emit('error', e)
    }
  }
}

const deleteTarget = ref<Media | null>(null)
async function doDelete() {
  const m = deleteTarget.value
  deleteTarget.value = null
  if (!m) return
  try {
    await api.removeMedia(props.packId, m.name)
    emit(
      'update:media',
      props.media.filter((x) => x.name !== m.name),
    )
    toast.success('Файл удалён')
  } catch (e) {
    emit('error', e)
  }
}

const icon = (name: string) => ({ image: '🖼', video: '🎬', audio: '🎵' })[mediaKind(name)]
</script>

<template>
  <section class="mm col">
    <div class="row">
      <h3 class="m0 grow">Медиафайлы ({{ media.length }})</h3>
      <button class="btn btn-sm" @click="fileInput?.click()">Загрузить…</button>
      <input ref="fileInput" type="file" multiple accept="image/*,video/*,audio/*" hidden @change="onFiles" />
    </div>
    <input v-if="media.length > 6" v-model="filter" class="input" placeholder="Поиск по имени" />

    <ul v-if="uploads.length" class="list">
      <li v-for="u in uploads" :key="u.id" class="up">
        <div class="row">
          <span class="grow small mono name">{{ u.name }}</span>
          <span v-if="!u.error" class="xs muted num">{{ Math.round(u.progress * 100) }}%</span>
          <button v-else class="btn btn-ghost btn-icon" aria-label="Скрыть" @click="uploads = uploads.filter((x) => x.id !== u.id)">
            ✕
          </button>
        </div>
        <div v-if="!u.error" class="progress"><i :style="{ width: `${u.progress * 100}%` }" /></div>
        <div v-else class="error-text xs">{{ u.error }}</div>
      </li>
    </ul>

    <ul class="list">
      <li v-for="m in sorted" :key="m.name" class="item">
        <span class="ico" aria-hidden="true">{{ icon(m.name) }}</span>
        <div class="grow meta">
          <a :href="m.url" target="_blank" rel="noopener" class="mono small name">{{ m.name }}</a>
          <div class="xs muted">{{ m.mime }} · {{ formatBytes(m.size) }}</div>
        </div>
        <button v-if="canInsert" class="btn btn-sm btn-primary" title="Вставить в поле" @click="emit('insert', m.name)">
          Вставить
        </button>
        <button class="btn btn-ghost btn-icon danger" aria-label="Удалить" @click="deleteTarget = m">✕</button>
      </li>
      <li v-if="!media.length && !uploads.length" class="muted small">Файлов пока нет</li>
    </ul>

    <ConfirmDialog v-if="deleteTarget" title="Удалить файл?" confirm-text="Удалить" @confirm="doDelete" @cancel="deleteTarget = null">
      <p>
        «{{ deleteTarget.name }}» будет удалён из пака. Вопросы, которые на него ссылаются, покажут пустое место.
      </p>
    </ConfirmDialog>
  </section>
</template>

<style scoped>
.m0 {
  margin: 0;
}
.mm {
  gap: var(--sp-3);
}
.list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-1);
  max-height: 50vh;
  overflow: auto;
}
.item {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  padding: var(--sp-1) var(--sp-2);
  border-radius: var(--r-input);
}
.item:hover {
  background: var(--surface-2);
}
.ico {
  width: 24px;
  text-align: center;
}
.meta {
  min-width: 0;
}
.name {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--text);
}
.up {
  padding: var(--sp-1) var(--sp-2);
}
</style>
