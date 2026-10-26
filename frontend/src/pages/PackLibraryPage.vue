<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { packsApi } from '@/api'
import { useToastStore } from '@/stores/toast'
import { useAdminToken } from '@/composables/useAdminToken'
import { formatBytes, formatDateTime } from '@/utils/time'
import type { PackSummary } from '@/types/protocol'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import CopyPackDialog from '@/components/editor/CopyPackDialog.vue'

const props = defineProps<{ pin: string }>()
const { token, handleError } = useAdminToken(props.pin)
const editorPath = (id: string) => `/g/${props.pin}/admin/packs/${id}`
const api = packsApi(token)
const toast = useToastStore()
const router = useRouter()

const packs = ref<PackSummary[]>([])
const loading = ref(true)

async function load() {
  loading.value = true
  try {
    packs.value = await api.list()
  } catch (e) {
    handleError(e)
  } finally {
    loading.value = false
  }
}
onMounted(() => {
  if (token) void load()
})

function upsert(p: PackSummary) {
  packs.value = [p, ...packs.value.filter((x) => x.id !== p.id)]
}

// Create
const showCreate = ref(false)
const newTitle = ref('')
async function create() {
  const title = newTitle.value.trim()
  if (!title) return
  try {
    const pack = await api.create(title)
    showCreate.value = false
    newTitle.value = ''
    await router.push(editorPath(pack.id))
  } catch (e) {
    handleError(e)
  }
}

// Import with progress
const fileInput = ref<HTMLInputElement | null>(null)
const uploading = ref<{ name: string; progress: number; abort: () => void } | null>(null)
async function onImport(ev: Event) {
  const input = ev.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file) return
  const handle = api.importDub(file, (f) => {
    if (uploading.value) uploading.value.progress = f
  })
  uploading.value = { name: file.name, progress: 0, abort: handle.abort }
  try {
    const summary = await handle.promise
    upsert(summary)
    toast.success(`Пак «${summary.title}» импортирован`)
  } catch (e) {
    handleError(e)
  } finally {
    uploading.value = null
  }
}

// Export
const exporting = ref<string | null>(null)
async function exportPack(p: PackSummary) {
  exporting.value = p.id
  try {
    await api.exportDub(p.id, p.title)
  } catch (e) {
    handleError(e)
  } finally {
    exporting.value = null
  }
}

// Lock (irreversible through the API)
const lockTarget = ref<PackSummary | null>(null)
async function doLock() {
  const p = lockTarget.value
  lockTarget.value = null
  if (!p) return
  try {
    const s = await api.lock(p.id)
    packs.value = packs.value.map((x) => (x.id === s.id ? s : x))
    toast.success('Пак заблокирован')
  } catch (e) {
    handleError(e)
  }
}

// Locked pack → edit a copy
const copyTarget = ref<PackSummary | null>(null)
async function doCopy(title: string) {
  const p = copyTarget.value
  copyTarget.value = null
  if (!p) return
  try {
    const copy = await api.copy(p.id, title)
    await router.push(editorPath(copy.id))
  } catch (e) {
    handleError(e)
  }
}

// Delete
const deleteTarget = ref<PackSummary | null>(null)
async function doDelete() {
  const p = deleteTarget.value
  deleteTarget.value = null
  if (!p) return
  try {
    await api.remove(p.id)
    packs.value = packs.value.filter((x) => x.id !== p.id)
    toast.success('Пак удалён')
  } catch (e) {
    handleError(e)
  }
}
</script>

<template>
  <div>
    <header class="topbar">
      <RouterLink :to="`/g/${pin}/admin`" class="btn btn-ghost btn-sm">← Игра {{ pin }}</RouterLink>
      <span class="title">Библиотека паков</span>
      <span class="spacer" />
      <button class="btn btn-sm" :disabled="!!uploading" @click="fileInput?.click()">Импорт .dub</button>
      <button class="btn btn-primary btn-sm" @click="showCreate = true">Новый пак</button>
      <input ref="fileInput" type="file" accept=".dub" hidden @change="onImport" />
    </header>

    <main class="page col">
      <div v-if="uploading" class="card col">
        <div class="row">
          <span class="grow small">Загрузка «{{ uploading.name }}» — {{ Math.round(uploading.progress * 100) }}%</span>
          <button class="btn btn-ghost btn-sm" @click="uploading.abort()">Отмена</button>
        </div>
        <div class="progress"><i :style="{ width: `${uploading.progress * 100}%` }" /></div>
        <p v-if="uploading.progress >= 1" class="muted small m0">Обработка на сервере…</p>
      </div>

      <div v-if="loading" class="empty">Загрузка…</div>
      <div v-else-if="!packs.length" class="empty">Паков пока нет — создайте новый или импортируйте .dub.</div>

      <ul v-else class="packs">
        <li v-for="p in packs" :key="p.id" class="card pack">
          <div class="info">
            <div class="row">
              <RouterLink v-if="!p.locked" :to="editorPath(p.id)" class="ptitle">{{ p.title || 'Без названия' }}</RouterLink>
              <span v-else class="ptitle">{{ p.title || 'Без названия' }}</span>
              <span v-if="p.locked" class="chip lock" title="Пак заблокирован: изменять можно только копию">🔒 заблокирован</span>
            </div>
            <div v-if="p.author" class="small muted">{{ p.author }}</div>
            <div v-if="p.description" class="small desc">{{ p.description }}</div>
            <div class="xs muted mono meta">
              {{ p.rounds }} р. · {{ p.categories }} кат. · {{ p.questions }} вопр. · {{ p.mediaCount }} медиа ·
              {{ formatBytes(p.sizeBytes) }} · изм. {{ formatDateTime(p.updatedAt) }}
            </div>
          </div>
          <div class="actions">
            <RouterLink v-if="!p.locked" :to="editorPath(p.id)" class="btn btn-sm">Редактировать</RouterLink>
            <button v-else class="btn btn-sm" @click="copyTarget = p">Редактировать копию</button>
            <button class="btn btn-sm" :disabled="exporting === p.id" @click="exportPack(p)">
              {{ exporting === p.id ? 'Экспорт…' : 'Экспорт' }}
            </button>
            <button v-if="!p.locked" class="btn btn-ghost btn-sm" @click="lockTarget = p">Заблокировать</button>
            <button v-if="!p.locked" class="btn btn-ghost btn-sm danger" @click="deleteTarget = p">Удалить</button>
          </div>
        </li>
      </ul>
    </main>

    <ModalDialog v-if="showCreate" title="Новый пак" @close="showCreate = false">
      <form class="col" @submit.prevent="create">
        <label class="field">
          Название
          <input v-model="newTitle" class="input" maxlength="200" autofocus required />
        </label>
        <div class="row" style="justify-content: flex-end">
          <button type="button" class="btn btn-ghost" @click="showCreate = false">Отмена</button>
          <button class="btn btn-primary" :disabled="!newTitle.trim()">Создать</button>
        </div>
      </form>
    </ModalDialog>

    <ConfirmDialog v-if="lockTarget" title="Заблокировать пак?" confirm-text="Заблокировать" @confirm="doLock" @cancel="lockTarget = null">
      <p>
        «{{ lockTarget.title }}» больше нельзя будет изменить или удалить — только скопировать. Снять блокировку может лишь
        оператор сервера. Это действие необратимо.
      </p>
    </ConfirmDialog>
    <CopyPackDialog v-if="copyTarget" :title="copyTarget.title" @confirm="doCopy" @cancel="copyTarget = null" />
    <ConfirmDialog v-if="deleteTarget" title="Удалить пак?" confirm-text="Удалить" @confirm="doDelete" @cancel="deleteTarget = null">
      <p>«{{ deleteTarget.title }}» и все его медиафайлы будут удалены безвозвратно.</p>
    </ConfirmDialog>
  </div>
</template>

<style scoped>
.m0 {
  margin: 0;
}
.packs {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-3);
}
.card.pack {
  margin: 0;
  display: flex;
  gap: var(--sp-4);
  align-items: center;
  flex-wrap: wrap;
}
.info {
  flex: 1 1 320px;
  min-width: 0;
}
.ptitle {
  font-family: var(--font-display);
  font-weight: 600;
  font-size: var(--fs-16);
  color: var(--text);
  text-decoration: none;
}
.ptitle:hover {
  color: var(--accent);
}
.lock {
  color: var(--warning);
  border-color: var(--warning);
}
.desc {
  margin-top: var(--sp-1);
  white-space: pre-line;
}
.meta {
  margin-top: var(--sp-2);
}
.actions {
  display: flex;
  gap: var(--sp-2);
  flex-wrap: wrap;
}
</style>
