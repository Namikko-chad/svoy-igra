<script setup lang="ts">
import { nextTick, ref } from 'vue'
import type { Media } from '@/types/protocol'
import { insertBlock, insertLink, toggleLinePrefix, toggleWrap, type EditState } from '@/utils/mdEdit'
import ModalDialog from '@/components/ModalDialog.vue'
import MediaManager from './MediaManager.vue'

const props = defineProps<{
  label: string
  rows?: number
  packId: string
  token: string | null
  media: Media[]
}>()
const model = defineModel<string>({ required: true })
const emit = defineEmits<{
  /** the value changed in a way that should be saved now (blur, toolbar insert) */
  commit: []
  'update:media': [media: Media[]]
  error: [e: unknown]
}>()

const ta = ref<HTMLTextAreaElement | null>(null)
const showMedia = ref(false)
// Selection remembered when focus leaves the textarea (media dialog, link prompt).
let saved: { start: number; end: number } | null = null

function current(): EditState {
  const el = ta.value
  const start = el && document.activeElement === el ? el.selectionStart : (saved?.start ?? model.value.length)
  const end = el && document.activeElement === el ? el.selectionEnd : (saved?.end ?? start)
  return { text: model.value, start, end }
}

async function apply(next: EditState, commit = false) {
  model.value = next.text
  await nextTick()
  const el = ta.value
  if (el) {
    el.focus()
    el.setSelectionRange(next.start, next.end)
  }
  saved = { start: next.start, end: next.end }
  if (commit) emit('commit')
}

const bold = () => apply(toggleWrap(current(), '**', 'жирный'))
const italic = () => apply(toggleWrap(current(), '*', 'курсив'))
const heading = () => apply(toggleLinePrefix(current(), '## '))
const bullets = () => apply(toggleLinePrefix(current(), '- '))
const numbers = () => apply(toggleLinePrefix(current(), { numbered: true }))
const quote = () => apply(toggleLinePrefix(current(), '> '))
function link() {
  const state = current()
  const url = window.prompt('Адрес ссылки', 'https://')
  if (!url || url === 'https://') {
    void apply(state)
    return
  }
  void apply(insertLink(state, url.trim()), true)
}
function openMedia() {
  const el = ta.value
  if (el) saved = { start: el.selectionStart, end: el.selectionEnd }
  showMedia.value = true
}
function insertMedia(name: string) {
  showMedia.value = false
  void apply(insertBlock(current(), `![](media:${name})`), true)
}

function onKey(e: KeyboardEvent) {
  if (!(e.ctrlKey || e.metaKey) || e.altKey) return
  const k = e.key.toLowerCase()
  if (k === 'b' || k === 'и') {
    e.preventDefault()
    void bold()
  } else if (k === 'i' || k === 'ш') {
    e.preventDefault()
    void italic()
  }
}
function onBlur() {
  const el = ta.value
  if (el) saved = { start: el.selectionStart, end: el.selectionEnd }
  emit('commit')
}

const tools = [
  { title: 'Жирный (Ctrl+B)', label: 'B', cls: 'b', run: bold },
  { title: 'Курсив (Ctrl+I)', label: 'I', cls: 'i', run: italic },
  { title: 'Заголовок', label: 'H', cls: 'h', run: heading },
  { title: 'Маркированный список', label: '•', cls: '', run: bullets },
  { title: 'Нумерованный список', label: '1.', cls: '', run: numbers },
  { title: 'Цитата', label: '❝', cls: '', run: quote },
  { title: 'Ссылка', label: '🔗', cls: '', run: link },
]
</script>

<template>
  <div class="mdf">
    <div class="head">
      <span class="lbl">{{ label }}</span>
      <div class="toolbar" role="toolbar" :aria-label="`Форматирование: ${label}`">
        <button
          v-for="t in tools"
          :key="t.title"
          type="button"
          class="tool"
          :class="t.cls"
          :title="t.title"
          :aria-label="t.title"
          @mousedown.prevent
          @click="t.run"
        >
          {{ t.label }}
        </button>
        <button type="button" class="tool media" title="Медиа: вставить картинку, видео или звук" aria-label="Медиа" @click="openMedia">
          🖼 Медиа
        </button>
      </div>
    </div>
    <textarea
      ref="ta"
      v-model="model"
      class="textarea"
      :rows="rows ?? 4"
      :aria-label="label"
      spellcheck="true"
      @keydown="onKey"
      @blur="onBlur"
    />

    <ModalDialog v-if="showMedia" :title="`Медиа → ${label}`" @close="showMedia = false">
      <MediaManager
        :pack-id="packId"
        :token="token"
        :media="media"
        can-insert
        @update:media="(m) => emit('update:media', m)"
        @insert="insertMedia"
        @error="(e) => emit('error', e)"
      />
    </ModalDialog>
  </div>
</template>

<style scoped>
.mdf {
  display: flex;
  flex-direction: column;
  gap: var(--sp-1);
}
.head {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: var(--sp-2);
  flex-wrap: wrap;
}
.lbl {
  font-size: var(--fs-14);
  color: var(--text-muted);
}
.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 2px;
  padding: 2px;
  border: 1px solid var(--border);
  border-radius: var(--r-input);
  background: var(--surface);
}
.tool {
  min-width: 32px;
  height: 32px;
  padding: 0 var(--sp-2);
  border: 1px solid transparent;
  border-radius: 6px;
  background: transparent;
  color: var(--text);
  font: 500 var(--fs-14) / 1 var(--font-body);
  cursor: pointer;
  transition:
    background var(--t-hover),
    border-color var(--t-hover);
}
.tool:hover {
  background: var(--surface-2);
  border-color: var(--border);
}
.tool:focus-visible {
  border-color: var(--accent);
}
.tool.b {
  font-weight: 800;
}
.tool.i {
  font-style: italic;
  font-family: Georgia, serif;
}
.tool.h {
  font-family: var(--font-display);
  font-weight: 600;
}
.tool.media {
  color: var(--accent);
}
</style>
