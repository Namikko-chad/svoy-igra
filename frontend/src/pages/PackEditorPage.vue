<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { packsApi } from '@/api'
import { useRouter } from 'vue-router'
import { useAdminToken } from '@/composables/useAdminToken'
import { ApiError } from '@/api/http'
import { useToastStore } from '@/stores/toast'
import { moveItem, suggestValue } from '@/utils/reorder'
import { plural } from '@/utils/time'
import type { Category, Pack, Question, Round } from '@/types/protocol'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import QuestionEditor from '@/components/editor/QuestionEditor.vue'
import MediaManager from '@/components/editor/MediaManager.vue'
import CopyPackDialog from '@/components/editor/CopyPackDialog.vue'

const props = defineProps<{ pin: string; id: string }>()
const { token, handleError: baseHandleError } = useAdminToken(props.pin)
const router = useRouter()
/** 409 pack_locked: someone locked it meanwhile — switch the page to the read-only notice. */
function handleError(e: unknown) {
  if (e instanceof ApiError && e.code === 'pack_locked' && pack.value) {
    pack.value.locked = true
    editing.value = null
  }
  baseHandleError(e)
}
const api = packsApi(token)
const toast = useToastStore()

const pack = ref<Pack | null>(null)
const loading = ref(true)
const roundIdx = ref(0)
const round = computed<Round | null>(() => pack.value?.rounds[roundIdx.value] ?? null)

onMounted(async () => {
  if (!token) return
  try {
    pack.value = await api.get(props.id)
    snapshotMeta()
  } catch (e) {
    handleError(e)
  } finally {
    loading.value = false
  }
})

// ---- Pack meta ----
const metaSaved = ref<Record<'title' | 'author' | 'description', string>>({ title: '', author: '', description: '' })
async function saveMeta(field: 'title' | 'author' | 'description') {
  const p = pack.value
  if (!p) return
  const v = field === 'title' ? p.title.trim() : p[field]
  if (field === 'title' && !v) {
    toast.error('Название не может быть пустым')
    p.title = metaSaved.value.title
    return
  }
  if (metaSaved.value[field] === v) return
  try {
    const s = await api.update(p.id, { [field]: v })
    p.title = s.title
    p.author = s.author
    p.description = s.description
    p.updatedAt = s.updatedAt
    metaSaved.value = { title: s.title, author: s.author, description: s.description }
  } catch (e) {
    handleError(e)
  }
}
function snapshotMeta() {
  if (pack.value) {
    const { title, author, description } = pack.value
    metaSaved.value = { title, author, description }
  }
}

// ---- Rounds ----
const showAddRound = ref(false)
const newRoundName = ref('')
async function addRound() {
  const p = pack.value
  const name = newRoundName.value.trim()
  if (!p || !name) return
  try {
    const r = await api.addRound(p.id, name)
    p.rounds.push({ ...r, kind: r.kind ?? 'normal', categories: r.categories ?? [] })
    roundIdx.value = p.rounds.length - 1
    showAddRound.value = false
    newRoundName.value = ''
  } catch (e) {
    handleError(e)
  }
}
async function renameRound(r: Round, ev: Event) {
  const input = ev.target as HTMLInputElement
  const name = input.value.trim()
  if (!name || name === r.name) {
    input.value = r.name
    return
  }
  try {
    const res = await api.updateRound(props.id, r.id, { name })
    r.name = res.name
  } catch (e) {
    input.value = r.name
    handleError(e)
  }
}
async function setRoundKind(r: Round, final: boolean) {
  try {
    const res = await api.updateRound(props.id, r.id, { kind: final ? 'final' : 'normal' })
    r.kind = res.kind ?? (final ? 'final' : 'normal')
  } catch (e) {
    handleError(e)
  }
}
const isFinal = computed(() => round.value?.kind === 'final')

async function moveRound(from: number, to: number) {
  const p = pack.value
  const r = p?.rounds[from]
  if (!p || !r || to < 0 || to >= p.rounds.length) return
  try {
    await api.updateRound(p.id, r.id, { position: to })
    p.rounds = moveItem(p.rounds, from, to)
    roundIdx.value = to
  } catch (e) {
    handleError(e)
  }
}
const deleteRoundTarget = ref<Round | null>(null)
async function doDeleteRound() {
  const p = pack.value
  const r = deleteRoundTarget.value
  deleteRoundTarget.value = null
  if (!p || !r) return
  try {
    await api.removeRound(p.id, r.id)
    p.rounds = p.rounds.filter((x) => x.id !== r.id)
    p.rounds.forEach((x, i) => (x.position = i))
    roundIdx.value = Math.max(0, Math.min(roundIdx.value, p.rounds.length - 1))
  } catch (e) {
    handleError(e)
  }
}

// ---- Categories ----
const MAX_CATEGORIES = 10
async function addCategory() {
  const r = round.value
  if (!r) return
  try {
    const c = await api.addCategory(props.id, r.id, `${r.kind === 'final' ? 'Тема' : 'Категория'} ${r.categories.length + 1}`)
    r.categories.push({ ...c, questions: c.questions ?? [] })
  } catch (e) {
    handleError(e)
  }
}
async function renameCategory(c: Category, ev: Event) {
  const input = ev.target as HTMLInputElement
  const name = input.value.trim()
  if (!name || name === c.name) {
    input.value = c.name
    return
  }
  try {
    const res = await api.updateCategory(props.id, c.id, { name })
    c.name = res.name
  } catch (e) {
    input.value = c.name
    handleError(e)
  }
}
async function moveCategory(from: number, to: number) {
  const r = round.value
  const c = r?.categories[from]
  if (!r || !c || to < 0 || to >= r.categories.length) return
  try {
    await api.updateCategory(props.id, c.id, { position: to })
    r.categories = moveItem(r.categories, from, to)
  } catch (e) {
    handleError(e)
  }
}
const deleteCategoryTarget = ref<Category | null>(null)
async function doDeleteCategory() {
  const r = round.value
  const c = deleteCategoryTarget.value
  deleteCategoryTarget.value = null
  if (!r || !c) return
  try {
    await api.removeCategory(props.id, c.id)
    r.categories = r.categories.filter((x) => x.id !== c.id)
    r.categories.forEach((x, i) => (x.position = i))
  } catch (e) {
    handleError(e)
  }
}

// ---- Questions ----
const editing = ref<{ category: Category; question: Question } | null>(null)
async function addQuestion(c: Category) {
  try {
    const body = isFinal.value
      ? { question: '', answer: '' } // final: value / readingSeconds are ignored (protocol §5)
      : { value: suggestValue(c.questions), question: '', answer: '' }
    const q = await api.addQuestion(props.id, c.id, body)
    c.questions.push(q)
    editing.value = { category: c, question: q }
  } catch (e) {
    handleError(e)
  }
}
function onQuestionSaved(q: Question) {
  const c = editing.value?.category
  if (!c) return
  const i = c.questions.findIndex((x) => x.id === q.id)
  if (i >= 0) c.questions[i] = q
}
async function moveQuestion(c: Category, from: number, to: number) {
  const q = c.questions[from]
  if (!q || to < 0 || to >= c.questions.length) return
  try {
    await api.updateQuestion(props.id, q.id, { position: to })
    c.questions = moveItem(c.questions, from, to)
  } catch (e) {
    handleError(e)
  }
}
const deleteQuestionTarget = ref<{ category: Category; question: Question } | null>(null)
async function doDeleteQuestion() {
  const t = deleteQuestionTarget.value
  deleteQuestionTarget.value = null
  if (!t) return
  try {
    await api.removeQuestion(props.id, t.question.id)
    t.category.questions = t.category.questions.filter((x) => x.id !== t.question.id)
    t.category.questions.forEach((x, i) => (x.position = i))
  } catch (e) {
    handleError(e)
  }
}
function preview(md: string): string {
  const text = md
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '🖼')
    .replace(/[#>*_`]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
  return text || '— пусто —'
}

// ---- Locked pack → copy ----
const showCopy = ref(false)
async function doCopy(title: string) {
  showCopy.value = false
  if (!pack.value) return
  try {
    const copy = await api.copy(pack.value.id, title)
    await router.push(`/g/${props.pin}/admin/packs/${copy.id}`)
  } catch (e) {
    handleError(e)
  }
}

// ---- Media ----
const showMedia = ref(false)
</script>

<template>
  <div>
    <header class="topbar">
      <RouterLink :to="`/g/${pin}/admin/packs`" class="btn btn-ghost btn-sm">← Библиотека</RouterLink>
      <span class="title ellipsis">{{ pack?.title || 'Редактор пака' }}</span>
      <span class="spacer" />
      <button v-if="pack && !pack.locked" class="btn btn-sm" @click="showMedia = true">Медиа ({{ pack.media.length }})</button>
    </header>

    <div v-if="loading" class="empty">Загрузка…</div>
    <div v-else-if="!pack" class="empty">Пак не найден</div>

    <main v-else-if="pack.locked" class="page col">
      <div class="card col">
        <h2 class="m0">🔒 Пак заблокирован</h2>
        <p class="muted m0">«{{ pack.title }}» нельзя изменять. Создайте копию и редактируйте её.</p>
        <button class="btn btn-primary" @click="showCopy = true">Редактировать копию</button>
      </div>
    </main>

    <main v-else class="page col">
      <!-- Meta -->
      <section class="card col">
        <div class="meta-grid">
          <label class="field">
            Название
            <input v-model="pack.title" class="input" maxlength="200" @blur="saveMeta('title')" />
          </label>
          <label class="field">
            Автор
            <input v-model="pack.author" class="input" maxlength="200" @blur="saveMeta('author')" />
          </label>
        </div>
        <label class="field">
          Описание
          <textarea v-model="pack.description" class="textarea body" rows="2" @blur="saveMeta('description')" />
        </label>
      </section>

      <!-- Round tabs -->
      <nav class="tabs" role="tablist">
        <button
          v-for="(r, i) in pack.rounds"
          :key="r.id"
          role="tab"
          class="tab"
          :class="{ active: i === roundIdx }"
          :aria-selected="i === roundIdx"
          @click="roundIdx = i"
        >
          {{ i + 1 }}. {{ r.kind === 'final' ? '🏆 ' : '' }}{{ r.name }}
          <span class="count" :class="{ warn: r.kind !== 'final' && r.categories.length !== MAX_CATEGORIES }">{{ r.categories.length }}</span>
        </button>
        <button class="tab add" @click="showAddRound = true">+ Раунд</button>
      </nav>

      <div v-if="!round" class="empty">В паке нет раундов — добавьте первый.</div>

      <section v-else class="col">
        <div class="card row">
          <label class="field grow">
            Название раунда
            <input :key="round.id" class="input" :value="round.name" maxlength="200" @blur="renameRound(round, $event)" @keydown.enter="($event.target as HTMLInputElement).blur()" />
          </label>
          <div class="row">
            <button class="btn btn-sm" :disabled="roundIdx === 0" title="Сдвинуть влево" @click="moveRound(roundIdx, roundIdx - 1)">←</button>
            <button class="btn btn-sm" :disabled="roundIdx >= pack.rounds.length - 1" title="Сдвинуть вправо" @click="moveRound(roundIdx, roundIdx + 1)">→</button>
            <label class="check final-toggle" title="Финал: темы по одному вопросу, ставки игроков">
              <input type="checkbox" :checked="isFinal" @change="setRoundKind(round, ($event.target as HTMLInputElement).checked); ($event.target as HTMLInputElement).checked = isFinal" />
              🏆 Финал
            </label>
            <button class="btn btn-ghost btn-sm danger" @click="deleteRoundTarget = round">Удалить раунд</button>
          </div>
        </div>

        <p v-if="isFinal" class="hint">
          🏆 Финальный раунд: каждая тема — ровно один вопрос. Стоимость и время чтения не используются — игроки делают ставки.
        </p>
        <p v-else-if="round.categories.length !== MAX_CATEGORIES" class="warning">
          ⚠ В раунде {{ round.categories.length }} {{ plural(round.categories.length, ['категория', 'категории', 'категорий']) }} — обычно их 10.
        </p>

        <div class="cats">
          <article v-for="(c, ci) in round.categories" :key="c.id" class="card cat">
            <div class="row cat-head">
              <input
                class="input grow cat-name"
                :value="c.name"
                maxlength="200"
                aria-label="Название категории"
                @blur="renameCategory(c, $event)"
                @keydown.enter="($event.target as HTMLInputElement).blur()"
              />
              <button class="btn btn-icon btn-sm" :disabled="ci === 0" aria-label="Выше" @click="moveCategory(ci, ci - 1)">↑</button>
              <button class="btn btn-icon btn-sm" :disabled="ci === round.categories.length - 1" aria-label="Ниже" @click="moveCategory(ci, ci + 1)">↓</button>
              <button class="btn btn-ghost btn-icon danger" aria-label="Удалить категорию" @click="deleteCategoryTarget = c">✕</button>
            </div>
            <ul class="qs">
              <li v-for="(q, qi) in c.questions" :key="q.id" class="q">
                <button class="qbtn" @click="editing = { category: c, question: q }">
                  <span v-if="!isFinal" class="display gold num qv">{{ q.value }}</span>
                  <span class="qt">{{ preview(q.question) }}</span>
                  <span v-if="q.readingSeconds != null" class="chip">{{ q.readingSeconds }} с</span>
                </button>
                <template v-if="!isFinal">
                  <button class="btn btn-icon btn-sm" :disabled="qi === 0" aria-label="Выше" @click="moveQuestion(c, qi, qi - 1)">↑</button>
                  <button class="btn btn-icon btn-sm" :disabled="qi === c.questions.length - 1" aria-label="Ниже" @click="moveQuestion(c, qi, qi + 1)">↓</button>
                </template>
                <button class="btn btn-ghost btn-icon danger" aria-label="Удалить вопрос" @click="deleteQuestionTarget = { category: c, question: q }">✕</button>
              </li>
            </ul>
            <button v-if="isFinal && !c.questions.length" class="btn btn-sm btn-ghost" @click="addQuestion(c)">+ Вопрос темы</button>
            <p v-else-if="isFinal && c.questions.length > 1" class="warning xs">В теме финала должен быть один вопрос — удалите лишние.</p>
            <button v-else-if="!isFinal" class="btn btn-sm btn-ghost" @click="addQuestion(c)">+ Вопрос ({{ suggestValue(c.questions) }})</button>
          </article>
        </div>
        <button class="btn" :disabled="round.categories.length >= MAX_CATEGORIES" @click="addCategory">
          + {{ isFinal ? 'Тема' : 'Категория' }} {{ round.categories.length >= MAX_CATEGORIES ? '(максимум 10)' : '' }}
        </button>
      </section>
    </main>

    <QuestionEditor
      v-if="editing && pack"
      :key="editing.question.id"
      :pack-id="pack.id"
      :token="token"
      :question="editing.question"
      :category-name="editing.category.name"
      :final="isFinal"
      :media="pack.media"
      @update:media="(m) => pack && (pack.media = m)"
      @saved="onQuestionSaved"
      @error="handleError"
      @close="editing = null"
    />

    <ModalDialog v-if="showMedia && pack" title="Медиафайлы пака" @close="showMedia = false">
      <MediaManager :pack-id="pack.id" :token="token" :media="pack.media" @update:media="(m) => pack && (pack.media = m)" @error="handleError" />
      <p class="muted xs">Чтобы вставить файл в вопрос, откройте вопрос и нажмите «Вставить».</p>
    </ModalDialog>

    <CopyPackDialog v-if="showCopy && pack" :title="pack.title" @confirm="doCopy" @cancel="showCopy = false" />

    <ModalDialog v-if="showAddRound" title="Новый раунд" @close="showAddRound = false">
      <form class="col" @submit.prevent="addRound">
        <label class="field">
          Название
          <input v-model="newRoundName" class="input" maxlength="200" autofocus :placeholder="`Раунд ${(pack?.rounds.length ?? 0) + 1}`" />
        </label>
        <div class="row" style="justify-content: flex-end">
          <button type="button" class="btn btn-ghost" @click="showAddRound = false">Отмена</button>
          <button class="btn btn-primary" :disabled="!newRoundName.trim()">Добавить</button>
        </div>
      </form>
    </ModalDialog>

    <ConfirmDialog v-if="deleteRoundTarget" title="Удалить раунд?" confirm-text="Удалить" @confirm="doDeleteRound" @cancel="deleteRoundTarget = null">
      <p>«{{ deleteRoundTarget.name }}» со всеми категориями и вопросами будет удалён.</p>
    </ConfirmDialog>
    <ConfirmDialog v-if="deleteCategoryTarget" title="Удалить категорию?" confirm-text="Удалить" @confirm="doDeleteCategory" @cancel="deleteCategoryTarget = null">
      <p>«{{ deleteCategoryTarget.name }}» со всеми вопросами будет удалена.</p>
    </ConfirmDialog>
    <ConfirmDialog v-if="deleteQuestionTarget" title="Удалить вопрос?" confirm-text="Удалить" @confirm="doDeleteQuestion" @cancel="deleteQuestionTarget = null">
      <p>Вопрос за {{ deleteQuestionTarget.question.value }} будет удалён.</p>
    </ConfirmDialog>
  </div>
</template>

<style scoped>
.m0 {
  margin: 0;
}
.ellipsis {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  min-width: 0;
  max-width: 50vw;
}
.meta-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: var(--sp-3);
}
.textarea.body {
  font-family: var(--font-body);
  min-height: 64px;
}
.tabs {
  display: flex;
  gap: var(--sp-2);
  overflow-x: auto;
  padding-bottom: 2px;
}
.tab {
  flex: none;
  display: inline-flex;
  align-items: center;
  gap: var(--sp-2);
  min-height: 40px;
  padding: 0 var(--sp-4);
  border-radius: var(--r-pill);
  border: 1px solid var(--border);
  background: var(--surface);
  color: var(--text-muted);
  font: 500 var(--fs-14) / 1 var(--font-body);
  cursor: pointer;
}
.tab.active {
  background: var(--surface-2);
  color: var(--text);
  border-color: var(--accent);
}
.tab.add {
  border-style: dashed;
}
.count {
  font-family: var(--font-mono);
  font-size: var(--fs-12);
  color: var(--success);
}
.count.warn {
  color: var(--warning);
}
.hint {
  margin: 0;
  color: var(--gold);
  font-size: var(--fs-14);
}
.final-toggle {
  font-size: var(--fs-14);
  white-space: nowrap;
}
.warning {
  margin: 0;
  color: var(--warning);
  font-size: var(--fs-14);
}
.cats {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: var(--sp-3);
}
.card.cat {
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-2);
}
.cat-head {
  flex-wrap: nowrap;
  gap: var(--sp-1);
}
.cat-name {
  font-weight: 600;
  text-transform: uppercase;
  font-size: var(--fs-14);
}
.qs {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-1);
}
.q {
  display: flex;
  align-items: center;
  gap: var(--sp-1);
}
.qbtn {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  padding: var(--sp-2);
  border-radius: var(--r-input);
  border: 1px solid var(--border);
  background: var(--surface-2);
  color: var(--text);
  text-align: left;
  cursor: pointer;
  font: inherit;
}
.qbtn:hover {
  border-color: var(--accent);
}
.qv {
  flex: none;
  min-width: 4ch;
  font-weight: 600;
  font-size: var(--fs-14);
}
.qt {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--fs-14);
}
</style>
