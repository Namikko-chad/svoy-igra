<script setup lang="ts">
import { computed } from 'vue'
import type { BoardCategory } from '@/types/protocol'

/**
 * The board (DESIGN_MANIFEST «Board»): one row per category, the name in a fixed left
 * column, value cells left → right ascending. Values are sized from the cell box with
 * container query units, so 4-digit values shrink instead of overflowing.
 */
const props = withDefaults(defineProps<{ board: BoardCategory[]; clickable?: boolean; tv?: boolean }>(), {
  clickable: false,
  tv: false,
})
const emit = defineEmits<{ select: [questionId: number] }>()

/** Widest row decides the column count; shorter rows get empty filler cells. */
const cols = computed(() => Math.max(1, ...props.board.map((c) => c.questions.length)))
const rows = computed(() =>
  props.board.map((c) => ({
    ...c,
    fill: cols.value - c.questions.length,
  })),
)
</script>

<template>
  <div class="board-scroll" :class="{ tv }">
    <div class="board" :class="{ clickable }" :style="{ '--cols': cols, '--rows': board.length || 1 }">
      <template v-for="cat in rows" :key="cat.id">
        <div class="head" :title="cat.name">
          <span>{{ cat.name }}</span>
        </div>
        <template v-for="q in cat.questions" :key="q.id">
          <div v-if="q.played" class="cell played" aria-label="Сыграно" />
          <button v-else-if="clickable" class="cell" :aria-label="`${cat.name}, ${q.value}`" @click="emit('select', q.id)">
            <span class="v">{{ q.value }}</span>
          </button>
          <div v-else class="cell">
            <span class="v">{{ q.value }}</span>
          </div>
        </template>
        <div v-for="i in cat.fill" :key="`f${i}`" class="cell filler" aria-hidden="true" />
      </template>
    </div>
  </div>
</template>

<style scoped>
.board-scroll {
  width: 100%;
}
.board {
  --name-col: clamp(120px, 18%, 260px);
  display: grid;
  grid-template-columns: var(--name-col) repeat(var(--cols), minmax(0, 1fr));
  /* Rows share the height; outside the TV the row height comes from the viewport. */
  grid-auto-rows: clamp(48px, calc((100dvh - 260px) / var(--rows)), 96px);
  gap: var(--sp-2);
  width: 100%;
}
.head {
  display: flex;
  align-items: center;
  padding: var(--sp-1) var(--sp-3);
  border-radius: var(--r-card);
  background: var(--surface);
  border: 1px solid var(--border);
  text-transform: uppercase;
  font: 600 clamp(12px, 1.1vw, 16px) / 1.2 var(--font-body);
  letter-spacing: 0.02em;
  min-width: 0;
}
.head span {
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  word-break: break-word;
}
.cell {
  /* Size container: the value below is sized from this box. */
  container-type: size;
  appearance: none;
  border: 1px solid transparent;
  border-radius: var(--r-card);
  background: var(--cell);
  color: var(--gold);
  padding: 0;
  min-width: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  transition:
    background var(--t-hover),
    box-shadow var(--t-hover),
    transform var(--t-hover);
}
.v {
  font-family: var(--font-display);
  font-weight: 800;
  font-variant-numeric: tabular-nums;
  line-height: 1;
  white-space: nowrap;
  /* ≤ 45 % of the cell height and ≤ the cell width minus padding for 4 digits. */
  font-size: min(45cqh, calc((100cqw - 12px) / 3.4), 72px);
  text-shadow: 0 2px 0 rgba(0, 0, 0, 0.35);
}
.clickable button.cell {
  cursor: pointer;
}
.clickable button.cell:hover,
.clickable button.cell:focus-visible {
  background: var(--cell-hover);
  box-shadow: var(--glow-gold);
  transform: translateY(-1px);
}
.cell.played {
  background: var(--cell-played);
  border-color: var(--border);
}
.cell.filler {
  background: transparent;
  border: 1px dashed transparent;
}

/* TV: fill the stage height, rows share it equally. */
.tv {
  height: 100%;
}
.tv .board {
  --name-col: clamp(180px, 20%, 420px);
  height: 100%;
  grid-auto-rows: minmax(0, 1fr);
  gap: clamp(6px, 0.6vw, 12px);
}
.tv .head {
  font-size: clamp(14px, 1.25vw, 24px);
  padding: 0 clamp(8px, 1vw, 20px);
}

/* Phone: fixed name column, value cells scroll horizontally. */
@media (max-width: 720px) {
  .board-scroll:not(.tv) {
    overflow-x: auto;
    scrollbar-width: thin;
    padding-bottom: 2px;
  }
  .board-scroll:not(.tv) .board {
    --name-col: 104px;
    grid-template-columns: var(--name-col) repeat(var(--cols), 72px);
    grid-auto-rows: 56px;
    width: max-content;
    min-width: 100%;
    gap: 6px;
  }
  .board-scroll:not(.tv) .head {
    position: sticky;
    left: 0;
    z-index: 1;
    font-size: 12px;
    padding: var(--sp-1) var(--sp-2);
    box-shadow: 6px 0 8px -4px rgba(7, 11, 31, 0.9);
  }
}
</style>
