import type { Phase } from '@/types/protocol'

export const PHASE_LABEL: Record<Phase, string> = {
  lobby: 'Лобби',
  board: 'Выбор вопроса',
  cat_transfer: 'Кот в мешке',
  auction: 'Аукцион',
  question: 'Вопрос',
  answering: 'Ответ игрока',
  reveal: 'Ответ',
  round_end: 'Конец раунда',
  final_themes: 'Финал: темы',
  final_bets: 'Финал: ставки',
  final_question: 'Финал: вопрос',
  final_judging: 'Финал: проверка',
  final_reveal: 'Финал: итоги',
  finished: 'Игра окончена',
}

/** Phases rendered by `SpecialStage` (special questions before the question + the final). */
export const SPECIAL_PHASES: Phase[] = [
  'cat_transfer',
  'auction',
  'final_themes',
  'final_bets',
  'final_question',
  'final_judging',
  'final_reveal',
]
export const isSpecialPhase = (p: Phase | null | undefined) => !!p && SPECIAL_PHASES.includes(p)
export const isFinalPhase = (p: Phase | null | undefined) => !!p && p.startsWith('final_')
