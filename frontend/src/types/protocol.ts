// Types mirrored from docs/en/05-protocol.md — that file is authoritative.

export type Role = 'player' | 'host' | 'admin' | 'screen'
export type Phase =
  | 'lobby'
  | 'board'
  | 'cat_transfer'
  | 'auction'
  | 'question'
  | 'answering'
  | 'reveal'
  | 'round_end'
  | 'final_themes'
  | 'final_bets'
  | 'final_question'
  | 'final_judging'
  | 'final_reveal'
  | 'finished'

export type Modifier = 'cat' | 'auction' | 'no_risk' | 'double'
export type RoundKind = 'normal' | 'final'

export type GameInfo = {
  /** public id, used by `POST /api/games/{id}/watch` */
  id: string
  /** 6 digits; null in the public list and for watch screens */
  pin: string | null
  title: string
  /** share link (§8); null like pin */
  link: string | null
  phase: Phase
  pack: { id: string; title: string } | null
  players: number
  hostTaken: boolean
  createdAt: number
}

export type JoinResult = {
  token: string
  role: Role
  playerId?: string
  name?: string
  game: GameInfo
}

export type GameMeta = {
  pin: string | null
  title: string
  link: string | null
  hostTaken: boolean
  hostConnected: boolean
  /** relative URL of the host's avatar; null = initials */
  hostAvatarUrl: string | null
}

export type PackSummary = {
  id: string
  title: string
  author: string
  description: string
  locked: boolean
  rounds: number
  categories: number
  questions: number
  mediaCount: number
  sizeBytes: number
  createdAt: number
  updatedAt: number
}

export type Media = { name: string; mime: string; size: number; url: string }

export type Question = {
  id: number
  categoryId: number
  position: number
  value: number
  question: string
  answer: string
  comment: string
  readingSeconds: number | null
}
export type Category = { id: number; roundId: number; position: number; name: string; questions: Question[] }
export type Round = { id: number; position: number; name: string; kind: RoundKind; categories: Category[] }
export type Pack = Omit<PackSummary, 'rounds' | 'categories' | 'questions' | 'mediaCount'> & {
  rounds: Round[]
  media: Media[]
}
export type QuestionInput = {
  value?: number
  question?: string
  answer?: string
  comment?: string
  readingSeconds?: number | null
}

export type Block =
  | { type: 'text'; markdown: string }
  | { type: 'image' | 'video' | 'audio'; url: string; alt: string }

export type BoardCategory = {
  id: number
  name: string
  questions: { id: number; value: number; played: boolean }[]
}

export type QuestionView = {
  id: number
  categoryName: string
  value: number
  modifier: Modifier | null
  stake: number
  blocks: Block[]
  answerBlocks: Block[] | null
  comment: string | null
}

export type AuctionView = {
  turnPlayerId: string | null
  highBid: number
  highBidderId: string
  allIn: boolean
  passedPlayerIds: string[]
}

export type FinalParticipant = {
  playerId: string
  hasBet: boolean
  bet: number | null
  hasAnswer: boolean
  answer: string | null
  correct: boolean | null
}

export type FinalView = {
  themes: { id: number; name: string; removed: boolean }[]
  removerId: string | null
  answerStartsAt: number | null
  answerEndsAt: number | null
  participants: FinalParticipant[]
}

export type DeviceInfo = {
  platform: string
  model: string
  os: string
  appVersion: string
  userAgent: string
  screen: string
  ip: string
}

export type AdminPlayerInfo = {
  device: DeviceInfo
  rttMs: number | null
  rttAvgMs: number | null
  jitterMs: number | null
  lastSeenAt: number | null
  buzzOffsetMs: number
  effectiveOffsetMs: number
  stats: {
    correct: number
    wrong: number
    buzzes: number
    avgReactionMs: number | null
    bestReactionMs: number | null
  }
}

export type PlayerView = {
  id: string
  name: string
  score: number
  connected: boolean
  /** relative URL (protocol §2.1 Avatars); null = show initials */
  avatarUrl: string | null
  admin?: AdminPlayerInfo
}

export type BuzzerState = 'hidden' | 'waiting' | 'open' | 'answering' | 'used' | 'closed'

export type MeView = {
  id: string
  name: string
  score: number
  canSelect: boolean
  buzzer: BuzzerState
  buzzOpensAt: number | null
  canType: boolean
  canGiveCat: boolean
  canBid: boolean
  canRemoveTheme: boolean
  finalist: boolean
  canBet: boolean
  canAnswerFinal: boolean
}

export type Settings = {
  readingSeconds: number
  buzzSeconds: number
  wrongPenalty: boolean
  autoLatencyCompensation: boolean
  modifiers: ModifierCounts
  finalSeconds: number
}

export type ModifierCounts = { cat: number; auction: number; noRisk: number; double: number }

export type GameView = {
  serverNow: number
  role: Role
  game: GameMeta
  phase: Phase
  pack: { id: string; title: string } | null
  round: { index: number; name: string; total: number; kind: RoundKind } | null
  board: BoardCategory[] | null
  players: PlayerView[]
  chooserId: string | null
  question: QuestionView | null
  soloPlayerId: string | null
  auction: AuctionView | null
  final: FinalView | null
  answeringPlayerId: string | null
  attemptedPlayerIds: string[]
  readingStartsAt: number | null
  readingEndsAt: number | null
  buzzStartsAt: number | null
  buzzEndsAt: number | null
  typedAnswer: string | null
  lastResult: { playerId: string; correct: boolean; delta: number } | null
  settings: Settings | null
  admins: number | null
  me: MeView | null
}

export type GameEvent =
  | { kind: 'question_opened'; questionId: number }
  | { kind: 'buzz'; playerId: string; reactionMs: number }
  | { kind: 'judged'; playerId: string; correct: boolean; delta: number }
  | { kind: 'timeout' }
  | { kind: 'score_adjusted'; playerId: string; delta: number }
  | { kind: 'round_started'; index: number }
  | { kind: 'game_finished' }
  | { kind: 'modifier'; questionId: number; modifier: Modifier }
  | { kind: 'cat_given'; fromId: string; toId: string }
  | { kind: 'auction_bid'; playerId: string; amount: number; allIn: boolean }
  | { kind: 'auction_pass'; playerId: string }
  | { kind: 'auction_won'; playerId: string; amount: number }
  | { kind: 'final_theme_removed'; playerId: string | null; themeId: number }
  | { kind: 'final_judged'; playerId: string; correct: boolean; delta: number }

export type Welcome = { role: Role; playerId?: string; pin?: string; serverNow: number }

export type WsFrame = { type: string; data?: unknown; reqId?: string }

export type ApiErrorBody = { error: { code: string; message: string } }
