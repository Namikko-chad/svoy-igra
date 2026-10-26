import type { AuctionView, FinalView, Modifier, PlayerView, QuestionView } from '@/types/protocol'

export const MODIFIER_LABEL: Record<Modifier, string> = {
  cat: 'Кот в мешке',
  auction: 'Аукцион',
  no_risk: 'Вопрос без риска',
  double: 'Двойная стоимость',
}
export const MODIFIER_ICON: Record<Modifier, string> = { cat: '🐈', auction: '🔨', no_risk: '🛡', double: '×2' }
export const MODIFIER_HINT: Record<Modifier, string> = {
  cat: 'Выбирающий отдаёт вопрос другому игроку',
  auction: 'Игроки торгуются за право ответить',
  no_risk: 'Отвечает выбирающий: ошибка не отнимает очков',
  double: 'Вопрос стоит вдвое больше',
}

/**
 * Score change on a wrong answer, for the host's «Неверно» label (protocol §4.5):
 * cat/auction always lose the stake, no_risk never loses, double loses 2×value only with
 * wrongPenalty, a plain question loses its value only with wrongPenalty.
 */
export function wrongDelta(q: Pick<QuestionView, 'modifier' | 'stake' | 'value'>, wrongPenalty: boolean): number {
  switch (q.modifier) {
    case 'cat':
    case 'auction':
      return q.stake
    case 'no_risk':
      return 0
    case 'double':
      return wrongPenalty ? q.stake : 0
    default:
      return wrongPenalty ? q.value : 0
  }
}

/** Who may receive the cat: every other player; if nobody else is connected, the chooser himself. */
export function catRecipients(players: PlayerView[], chooserId: string | null): PlayerView[] {
  const others = players.filter((p) => p.id !== chooserId)
  if (others.some((p) => p.connected)) return others
  const me = players.find((p) => p.id === chooserId)
  return others.length ? [...others, ...(me ? [me] : [])] : me ? [me] : []
}

/** Auction bidding limits for a player with `score` (protocol §4.5). */
export function auctionLimits(a: AuctionView, score: number) {
  const min = a.highBid + 1
  const canRaise = !a.allIn && score >= min
  const canAllIn = score > a.highBid
  return { min, max: score, canRaise, canAllIn }
}

/** Suggested raise: the next multiple of 100 above the high bid, capped at the score. */
export function suggestBid(highBid: number, score: number, step = 100): number {
  const next = (Math.floor(highBid / step) + 1) * step
  return Math.min(Math.max(next, highBid + 1), score)
}

export function clampInt(v: unknown, min: number, max: number): number {
  const n = Math.round(Number(v))
  if (!Number.isFinite(n)) return min
  return Math.min(max, Math.max(min, n))
}

export type FinalRow = {
  playerId: string
  name: string
  avatarUrl: string | null
  score: number
  hasBet: boolean
  bet: number | null
  hasAnswer: boolean
  answer: string | null
  correct: boolean | null
}

/** Finalists joined with names/scores, in participant order. */
export function finalRows(final: FinalView | null, players: PlayerView[]): FinalRow[] {
  if (!final) return []
  return final.participants.map((p) => {
    const pl = players.find((x) => x.id === p.playerId)
    return { ...p, name: pl?.name ?? '—', avatarUrl: pl?.avatarUrl ?? null, score: pl?.score ?? 0 }
  })
}

/** Themes still in play. */
export const remainingThemes = (final: FinalView | null) => (final ? final.themes.filter((t) => !t.removed) : [])

/** Human text for a judged final row: `+300` / `−300`, or null before judging. */
export function finalDeltaText(row: Pick<FinalRow, 'correct' | 'bet'>): string | null {
  if (row.correct == null || row.bet == null) return null
  return row.correct ? `+${row.bet}` : `−${row.bet}`
}

export type GameSettingsForm = {
  readingSeconds: number
  buzzSeconds: number
  wrongPenalty: boolean
  finalSeconds: number
  modifiers: { cat: number; auction: number; noRisk: number; double: number }
}

/** Clamp a settings form to the protocol ranges before `update_settings`. */
export function settingsPatch(f: GameSettingsForm): GameSettingsForm {
  return {
    readingSeconds: clampInt(f.readingSeconds, 1, 120),
    buzzSeconds: clampInt(f.buzzSeconds, 3, 300),
    wrongPenalty: !!f.wrongPenalty,
    finalSeconds: clampInt(f.finalSeconds, 10, 300),
    modifiers: {
      cat: clampInt(f.modifiers.cat, 0, 5),
      auction: clampInt(f.modifiers.auction, 0, 5),
      noRisk: clampInt(f.modifiers.noRisk, 0, 5),
      double: clampInt(f.modifiers.double, 0, 5),
    },
  }
}

/** Editable copy of the server settings (defaults when a field is missing). */
export function settingsForm(s: Partial<GameSettingsForm> | null | undefined): GameSettingsForm {
  return {
    readingSeconds: s?.readingSeconds ?? 10,
    buzzSeconds: s?.buzzSeconds ?? 15,
    wrongPenalty: s?.wrongPenalty ?? false,
    finalSeconds: s?.finalSeconds ?? 60,
    modifiers: { cat: 1, auction: 1, noRisk: 1, double: 1, ...(s?.modifiers ?? {}) },
  }
}
