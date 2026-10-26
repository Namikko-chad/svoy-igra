import { computed, type Ref } from 'vue'
import type { GameView } from '@/types/protocol'

/** Which countdown the question view shows right now, in server time. */
export function useQuestionTimer(state: Ref<GameView | null>, serverNow: Ref<number>) {
  return computed(() => {
    const s = state.value
    if (!s || s.phase !== 'question') return null
    const span = (start: number | null, end: number) => (start != null && end > start ? end - start : null)
    if (s.readingEndsAt != null && serverNow.value < s.readingEndsAt) {
      return { label: 'Вопрос читается', deadline: s.readingEndsAt, total: span(s.readingStartsAt, s.readingEndsAt) }
    }
    if (s.buzzEndsAt != null) {
      return { label: 'Можно отвечать', deadline: s.buzzEndsAt, total: span(s.buzzStartsAt, s.buzzEndsAt) }
    }
    return null
  })
}
