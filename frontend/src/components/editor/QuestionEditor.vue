<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { packsApi } from '@/api'
import { splitBlocks } from '@/utils/blocks'
import type { Media, Question, QuestionInput } from '@/types/protocol'
import ModalDialog from '@/components/ModalDialog.vue'
import QuestionBlocks from '@/components/QuestionBlocks.vue'
import MediaManager from './MediaManager.vue'
import MarkdownField from './MarkdownField.vue'

type TextField = 'question' | 'answer' | 'comment'

const props = defineProps<{
  packId: string
  token: string | null
  question: Question
  categoryName: string
  media: Media[]
  /** a final-round theme: value and readingSeconds are not used */
  final?: boolean
}>()
const emit = defineEmits<{
  saved: [q: Question]
  close: []
  'update:media': [media: Media[]]
  error: [e: unknown]
}>()
const api = packsApi(props.token)

// The last version the server confirmed; the draft is diffed against it.
let saved: Question = { ...props.question }
const draft = reactive({
  value: props.question.value,
  readingSeconds: props.question.readingSeconds == null ? '' : String(props.question.readingSeconds),
  question: props.question.question,
  answer: props.question.answer,
  comment: props.question.comment,
})
const status = ref<'idle' | 'saving' | 'saved' | 'error'>('idle')
const error = ref('')

function parseReading(): number | null | undefined {
  const s = String(draft.readingSeconds).trim()
  if (!s) return null
  const n = Math.round(Number(s))
  if (!Number.isFinite(n) || n < 1 || n > 120) return undefined
  return n
}

function diff(): QuestionInput | null {
  const patch: QuestionInput = {}
  if (!props.final) {
    const v = Math.round(Number(draft.value))
    if (Number.isFinite(v) && v !== saved.value) patch.value = v
    const r = parseReading()
    if (r !== undefined && r !== saved.readingSeconds) patch.readingSeconds = r
  }
  for (const f of ['question', 'answer', 'comment'] as const) if (draft[f] !== saved[f]) patch[f] = draft[f]
  return Object.keys(patch).length ? patch : null
}

let chain: Promise<void> = Promise.resolve()
function save(): Promise<void> {
  chain = chain.then(async () => {
    error.value = ''
    if (!props.final && parseReading() === undefined) {
      error.value = 'Время чтения — от 1 до 120 секунд или пусто (по умолчанию)'
      status.value = 'error'
      return
    }
    const patch = diff()
    if (!patch) return
    status.value = 'saving'
    try {
      const q = await api.updateQuestion(props.packId, saved.id, patch)
      saved = q
      status.value = 'saved'
      emit('saved', q)
    } catch (e) {
      status.value = 'error'
      emit('error', e)
    }
  })
  return chain
}

async function saveAndClose() {
  await save()
  if (status.value !== 'error') emit('close')
}

const questionBlocks = computed(() => splitBlocks(draft.question, props.packId))
const answerBlocks = computed(() => splitBlocks(draft.answer, props.packId))
const commentBlocks = computed(() => splitBlocks(draft.comment, props.packId))
const statusText = computed(
  () => ({ idle: '', saving: 'Сохранение…', saved: 'Сохранено', error: 'Ошибка сохранения' })[status.value],
)
const fields: { key: TextField; label: string; rows: number }[] = [
  { key: 'question', label: 'Вопрос (markdown)', rows: 6 },
  { key: 'answer', label: 'Ответ (markdown)', rows: 3 },
  { key: 'comment', label: 'Комментарий для ведущего (markdown)', rows: 2 },
]
</script>

<template>
  <ModalDialog :title="final ? `🏆 ${categoryName}` : `${categoryName} · ${draft.value}`" wide @close="saveAndClose">
    <div class="qe">
      <form class="col form" @submit.prevent="saveAndClose">
        <div v-if="!final" class="row">
          <label class="field grow">
            Стоимость
            <input v-model.number="draft.value" class="input num" type="number" step="100" min="0" @blur="save" />
          </label>
          <label class="field grow">
            Время чтения, с
            <input
              v-model="draft.readingSeconds"
              class="input num"
              type="number"
              min="1"
              max="120"
              placeholder="по умолчанию"
              @blur="save"
            />
          </label>
        </div>
        <MarkdownField
          v-for="f in fields"
          :key="f.key"
          v-model="draft[f.key]"
          :label="f.label"
          :rows="f.rows"
          :pack-id="packId"
          :token="token"
          :media="media"
          @commit="save"
          @update:media="(m) => emit('update:media', m)"
          @error="(e) => emit('error', e)"
        />
        <p class="muted xs m0">
          Медиа — кнопка «🖼 Медиа» над полем, или вручную: <code>![подпись](media:файл.jpg)</code> / <code>https://…</code>. Тип определяется по расширению.
        </p>
        <p v-if="error" class="error-text m0">{{ error }}</p>
        <div class="row">
          <span class="small muted grow" :class="{ 'error-text': status === 'error' }">{{ statusText }}</span>
          <button class="btn btn-primary">Сохранить и закрыть</button>
        </div>
      </form>

      <div class="col side">
        <details class="card preview" open>
          <summary class="small muted">Предпросмотр</summary>
          <div class="pv">
            <QuestionBlocks v-if="questionBlocks.length" :blocks="questionBlocks" mode="host" size="sm" />
            <p v-else class="muted small">Текст вопроса пуст</p>
            <div class="pv-answer">
              <div class="muted xs">Ответ</div>
              <QuestionBlocks :blocks="answerBlocks" mode="host" size="sm" />
              <template v-if="commentBlocks.length">
                <div class="muted xs">Комментарий</div>
                <QuestionBlocks :blocks="commentBlocks" mode="host" size="sm" />
              </template>
            </div>
          </div>
        </details>
        <div class="card">
          <MediaManager
            :pack-id="packId"
            :token="token"
            :media="media"
            @update:media="(m) => emit('update:media', m)"
            @error="(e) => emit('error', e)"
          />
        </div>
      </div>
    </div>
  </ModalDialog>
</template>

<style scoped>
.m0 {
  margin: 0;
}
.qe {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: var(--sp-4);
}
@media (max-width: 820px) {
  .qe {
    grid-template-columns: minmax(0, 1fr);
  }
}
.side {
  gap: var(--sp-3);
}
.side .card {
  margin: 0;
}
.preview summary {
  cursor: pointer;
}
.pv {
  margin-top: var(--sp-3);
  display: flex;
  flex-direction: column;
  gap: var(--sp-3);
}
.pv-answer {
  border-top: 1px solid var(--border);
  padding-top: var(--sp-3);
  text-align: center;
}
</style>
