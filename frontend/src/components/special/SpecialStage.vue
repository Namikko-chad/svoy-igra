<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import type { GameView } from '@/types/protocol'
import { splitBlocks } from '@/utils/blocks'
import {
  auctionLimits,
  catRecipients,
  clampInt,
  finalDeltaText,
  finalRows,
  remainingThemes,
  suggestBid,
} from '@/utils/special'
import QuestionBlocks from '@/components/QuestionBlocks.vue'
import TimerBar from '@/components/TimerBar.vue'
import QuestionHeader from './QuestionHeader.vue'
import AvatarImg from '@/components/AvatarImg.vue'

/**
 * Special-question phases (cat_transfer, auction) and the final (final_*) for the player,
 * host and screen. Commands go out through `cmd`; the page sends them on its socket.
 */
const props = defineProps<{
  state: GameView
  role: 'player' | 'host' | 'screen'
  /** current server time, ms */
  now: number
  tv?: boolean
  retry?: number
}>()
const emit = defineEmits<{ cmd: [type: string, data?: object]; blocked: [] }>()
const cmd = (type: string, data: object = {}) => emit('cmd', type, data)

const s = computed(() => props.state)
const phase = computed(() => s.value.phase)
const me = computed(() => s.value.me)
const isHost = computed(() => props.role === 'host')
const mode = computed(() => (props.role === 'host' ? 'host' : props.role === 'screen' ? 'screen' : 'player'))
const nameOf = (id: string | null | undefined) => s.value.players.find((p) => p.id === id)?.name ?? '—'
const q = computed(() => s.value.question)

// ---- cat_transfer ----
const recipients = computed(() => catRecipients(s.value.players, s.value.chooserId))
const canGive = computed(() => isHost.value || !!me.value?.canGiveCat)

// ---- auction ----
const auction = computed(() => s.value.auction)
const myScore = computed(() => me.value?.score ?? 0)
const limits = computed(() => (auction.value ? auctionLimits(auction.value, myScore.value) : null))
const bid = ref(0)
watch(
  () => [auction.value?.highBid, me.value?.canBid] as const,
  () => {
    if (auction.value) bid.value = suggestBid(auction.value.highBid, myScore.value)
  },
  { immediate: true },
)
function raise(step: number) {
  if (limits.value) bid.value = clampInt(bid.value + step, limits.value.min, limits.value.max)
}
function placeBid() {
  if (!limits.value?.canRaise) return
  cmd('auction_bid', { amount: clampInt(bid.value, limits.value.min, limits.value.max) })
}
const bidders = computed(() =>
  s.value.players.map((p) => ({
    ...p,
    passed: auction.value?.passedPlayerIds.includes(p.id) ?? false,
    high: auction.value?.highBidderId === p.id,
    turn: auction.value?.turnPlayerId === p.id,
  })),
)

// ---- final ----
const final = computed(() => s.value.final)
const rows = computed(() => finalRows(final.value, s.value.players))
const myRow = computed(() => rows.value.find((r) => r.playerId === me.value?.id) ?? null)
// final_bets: the server puts the remaining theme into question.categoryName.
const themeName = computed(() => q.value?.categoryName || remainingThemes(final.value)[0]?.name || null)
const canRemove = computed(() => isHost.value || !!me.value?.canRemoveTheme)

const betInput = ref(1)
watch(
  () => myRow.value?.bet,
  (b) => {
    if (b != null) betInput.value = b
  },
  { immediate: true },
)
function placeBet() {
  cmd('final_bet', { amount: clampInt(betInput.value, 1, Math.max(1, myScore.value)) })
}

const finalAnswer = ref('')
watch(
  () => phase.value,
  (p) => {
    if (p === 'final_question') finalAnswer.value = myRow.value?.answer ?? ''
  },
  { immediate: true },
)
let answerTimer: ReturnType<typeof setTimeout> | null = null
watch(finalAnswer, (text) => {
  if (answerTimer) clearTimeout(answerTimer)
  answerTimer = setTimeout(() => {
    if (me.value?.canAnswerFinal && text !== (myRow.value?.answer ?? '')) cmd('final_answer', { text: text.slice(0, 200) })
  }, 400)
})

const showQuestion = computed(() => ['final_question', 'final_judging', 'final_reveal'].includes(phase.value) && !!q.value)
const showAnswer = computed(() => !!q.value?.answerBlocks && (isHost.value || phase.value === 'final_reveal'))
const commentBlocks = computed(() =>
  q.value?.comment && s.value.pack ? splitBlocks(q.value.comment, s.value.pack.id) : [],
)
const allJudged = computed(() => rows.value.length > 0 && rows.value.every((r) => r.correct != null))
</script>

<template>
  <section class="special" :class="{ tv }">
    <!-- ============ cat_transfer ============ -->
    <template v-if="phase === 'cat_transfer' && q">
      <QuestionHeader :question="q" :tv="tv" />
      <div class="hero">
        <div class="big-icon">🐈</div>
        <h2 class="display">Кот в мешке</h2>
        <template v-if="canGive">
          <p class="lead">{{ isHost ? `Кому ${nameOf(s.chooserId)} отдаёт кота?` : 'Кому отдать кота?' }}</p>
          <div class="chips">
            <button v-for="p in recipients" :key="p.id" class="pick" :disabled="!p.connected && p.id !== s.chooserId" @click="cmd('give_cat', { playerId: p.id })">
              <AvatarImg :url="p.avatarUrl" :name="p.name" :size="tv ? 40 : 24" /> {{ p.name }}
            </button>
          </div>
        </template>
        <p v-else class="lead"><b class="gold">{{ nameOf(s.chooserId) }}</b> выбирает, кому отдать кота</p>
      </div>
    </template>

    <!-- ============ auction ============ -->
    <template v-else-if="phase === 'auction' && q && auction">
      <QuestionHeader :question="q" :tv="tv" />
      <div class="hero">
        <div class="big-icon">🔨</div>
        <h2 class="display">Аукцион</h2>
        <p class="lead">
          Ставка <b class="display gold num bid">{{ auction.highBid }}</b>
          <span v-if="auction.allIn" class="chip allin">ва-банк</span>
          — <b>{{ nameOf(auction.highBidderId) }}</b>
        </p>
        <p v-if="auction.turnPlayerId" class="muted">Ходит: <b class="accent">{{ nameOf(auction.turnPlayerId) }}</b></p>
        <ul class="bidders">
          <li v-for="p in bidders" :key="p.id" :class="{ passed: p.passed, high: p.high, turn: p.turn }">
            <AvatarImg :url="p.avatarUrl" :name="p.name" :size="tv ? 40 : 24" />
            <span class="name">{{ p.name }}</span>
            <span class="num muted small">{{ p.score }}</span>
            <span class="tag">{{ p.high ? 'лидер' : p.passed ? 'пас' : p.turn ? 'ходит' : '' }}</span>
          </li>
        </ul>

        <div v-if="role === 'player' && me?.canBid && limits" class="card col bidpanel">
          <div class="row">
            <input
              v-model.number="bid"
              class="input num grow"
              type="number"
              :min="limits.min"
              :max="limits.max"
              step="100"
              :disabled="!limits.canRaise"
              aria-label="Ваша ставка"
            />
            <button class="btn btn-sm" :disabled="!limits.canRaise" @click="raise(100)">+100</button>
            <button class="btn btn-sm" :disabled="!limits.canRaise" @click="raise(500)">+500</button>
          </div>
          <div class="row">
            <button class="btn btn-primary grow" :disabled="!limits.canRaise" @click="placeBid">Поставить</button>
            <button class="btn btn-danger" :disabled="!limits.canAllIn" @click="cmd('auction_all_in')">Ва-банк ({{ myScore }})</button>
            <button class="btn btn-ghost" @click="cmd('auction_pass')">Пас</button>
          </div>
        </div>
        <p v-else-if="role === 'player' && me" class="muted small">Ваш счёт: {{ me.score }}</p>
        <button v-if="isHost" class="btn" @click="cmd('auction_close')">Завершить торги</button>
      </div>
    </template>

    <!-- ============ final_themes ============ -->
    <template v-else-if="phase === 'final_themes' && final">
      <h2 class="display center">Финал</h2>
      <p class="lead center">
        Убирает тему: <b class="gold">{{ nameOf(final.removerId) }}</b>
        <template v-if="me?.canRemoveTheme"> — это вы, выберите тему</template>
      </p>
      <ul class="themes">
        <li v-for="t in final.themes" :key="t.id">
          <button
            class="theme"
            :class="{ removed: t.removed }"
            :disabled="t.removed || !canRemove"
            :title="canRemove && !t.removed ? 'Убрать тему' : undefined"
            @click="cmd('final_remove_theme', { themeId: t.id })"
          >
            <span>{{ t.name }}</span>
            <span v-if="canRemove && !t.removed" class="x" aria-hidden="true">✕</span>
          </button>
        </li>
      </ul>
    </template>

    <!-- ============ final_bets ============ -->
    <template v-else-if="phase === 'final_bets' && final">
      <h2 class="display center">Финал: ставки</h2>
      <p v-if="themeName" class="theme-name display center">{{ themeName }}</p>
      <div v-if="role === 'player' && me?.canBet" class="card col betpanel">
        <label class="field">
          Ваша ставка (1 – {{ me.score }})
          <input v-model.number="betInput" class="input num" type="number" min="1" :max="me.score" />
        </label>
        <button class="btn btn-primary btn-lg" @click="placeBet">{{ myRow?.hasBet ? 'Изменить ставку' : 'Поставить' }}</button>
        <p v-if="myRow?.hasBet" class="ok center">Ставка принята: {{ myRow.bet }}</p>
      </div>
      <p v-else-if="role === 'player' && me && !me.finalist" class="muted center">В финале играют участники с положительным счётом. Следите за игрой!</p>
      <ul class="final-list">
        <li v-for="r in rows" :key="r.playerId">
          <AvatarImg :url="r.avatarUrl" :name="r.name" :size="tv ? 40 : 24" />
          <span class="name">{{ r.name }}</span>
          <span class="num muted small">{{ r.score }}</span>
          <span v-if="isHost && r.bet != null" class="num gold">{{ r.bet }}</span>
          <span :class="r.hasBet ? 'ok' : 'muted'">{{ r.hasBet ? '✓ ставка' : 'думает…' }}</span>
        </li>
      </ul>
      <button v-if="isHost" class="btn btn-primary" @click="cmd('final_close_bets')">Закрыть ставки</button>
    </template>

    <!-- ============ final_question / judging / reveal ============ -->
    <template v-else-if="showQuestion && q && final">
      <QuestionHeader :question="q" :tv="tv" final />
      <TimerBar
        v-if="phase === 'final_question' && final.answerEndsAt"
        :deadline="final.answerEndsAt"
        :now="now"
        :total="final.answerStartsAt != null ? final.answerEndsAt - final.answerStartsAt : null"
        label="Время на ответ"
      />
      <QuestionBlocks
        :key="q.id"
        :blocks="q.blocks"
        :mode="mode"
        :size="tv ? 'lg' : isHost ? 'sm' : 'md'"
        :retry="retry"
        :active="phase !== 'final_reveal'"
        @blocked="emit('blocked')"
      />

      <div v-if="role === 'player' && me?.finalist && phase === 'final_question'" class="card col answerpanel">
        <label class="field">
          Ваш ответ
          <textarea v-model="finalAnswer" class="textarea body" rows="2" maxlength="200" :disabled="!me.canAnswerFinal" />
        </label>
        <p class="small m0" :class="myRow?.hasAnswer ? 'ok' : 'muted'">
          {{ myRow?.hasAnswer ? 'Ответ сохранён — можно исправить до конца времени' : 'Начните печатать — ответ сохраняется сам' }}
        </p>
      </div>

      <div v-if="showAnswer" class="card answer">
        <div class="muted small">Правильный ответ</div>
        <QuestionBlocks :blocks="q.answerBlocks ?? []" :mode="mode" :size="tv ? 'lg' : 'sm'" :retry="retry" @blocked="emit('blocked')" />
        <QuestionBlocks v-if="commentBlocks.length" class="muted" :blocks="commentBlocks" :mode="mode" size="sm" :retry="retry" />
      </div>

      <div class="table-wrap">
        <table class="table results">
          <thead>
            <tr>
              <th>Финалист</th>
              <th v-if="phase !== 'final_question' || isHost">Ответ</th>
              <th>Ставка</th>
              <th>Итог</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in rows" :key="r.playerId" :class="{ ok: r.correct === true, bad: r.correct === false }">
              <td class="who">
                <AvatarImg :url="r.avatarUrl" :name="r.name" :size="tv ? 40 : 24" />
                <b>{{ r.name }}</b> <span class="muted num small">{{ r.score }}</span>
              </td>
              <td v-if="phase !== 'final_question' || isHost" class="ans">
                <template v-if="r.answer != null">{{ r.answer || '—' }}</template>
                <span v-else class="muted">{{ r.hasAnswer ? 'ответ скрыт' : 'нет ответа' }}</span>
              </td>
              <td class="num">{{ r.bet ?? (r.hasBet ? '?' : '—') }}</td>
              <td>
                <span v-if="finalDeltaText(r)" class="num delta">{{ finalDeltaText(r) }}</span>
                <span v-else-if="phase === 'final_question'" :class="r.hasAnswer ? 'ok' : 'muted'">{{ r.hasAnswer ? '✓ ответил' : 'пишет…' }}</span>
                <div v-else-if="isHost && phase === 'final_judging'" class="row judge">
                  <button class="btn btn-success btn-sm" @click="cmd('final_judge', { playerId: r.playerId, correct: true })">
                    Верно +{{ r.bet ?? 0 }}
                  </button>
                  <button class="btn btn-danger btn-sm" @click="cmd('final_judge', { playerId: r.playerId, correct: false })">
                    Неверно −{{ r.bet ?? 0 }}
                  </button>
                </div>
                <span v-else class="muted">проверяется…</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <button v-if="isHost && phase === 'final_question'" class="btn" @click="cmd('final_close_answers')">Завершить приём ответов</button>
      <p v-if="isHost && phase === 'final_judging' && !allJudged" class="muted small m0">Оцените каждого финалиста.</p>
      <button v-if="isHost && phase === 'final_reveal'" class="btn btn-primary btn-lg" @click="cmd('continue')">Продолжить</button>
    </template>
  </section>
</template>

<style scoped>
.special {
  display: flex;
  flex-direction: column;
  gap: var(--sp-4);
  width: 100%;
}
.m0 {
  margin: 0;
}
.center {
  text-align: center;
}
.accent {
  color: var(--accent);
}
.ok {
  color: var(--success);
}
.hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--sp-3);
  text-align: center;
}
.big-icon {
  font-size: 64px;
  line-height: 1;
}
.hero h2,
.special > h2 {
  margin: 0;
  color: var(--gold);
  font-weight: 800;
  font-size: clamp(24px, 7vw, 40px);
  text-shadow: var(--glow-gold);
}
.lead {
  margin: 0;
  font-size: var(--fs-20);
}
.bid {
  font-size: var(--fs-32);
}
.allin {
  color: var(--danger);
  border-color: var(--danger);
}
.chips {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: var(--sp-2);
}
.pick {
  display: inline-flex;
  align-items: center;
  gap: var(--sp-2);
  min-height: 48px;
  padding: 0 var(--sp-4);
  border-radius: var(--r-pill);
  border: 2px solid var(--border);
  background: var(--surface);
  color: var(--text);
  font: 600 var(--fs-16) / 1 var(--font-body);
  cursor: pointer;
}
.pick:hover:not(:disabled),
.pick:focus-visible {
  border-color: var(--gold);
  box-shadow: var(--glow-gold);
}
.pick:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
.bidders,
.final-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-1);
  width: min(420px, 100%);
}
.bidders li,
.final-list li {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  padding: var(--sp-2) var(--sp-3);
  border-radius: var(--r-input);
  background: var(--surface);
  border: 1px solid var(--border);
}
.bidders .name,
.final-list .name {
  flex: 1;
  text-align: left;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.bidders li.high {
  border-color: var(--gold);
}
.bidders li.turn {
  border-color: var(--accent);
  box-shadow: var(--glow-accent);
}
.bidders li.passed {
  opacity: 0.5;
}
.tag {
  font-size: var(--fs-12);
  color: var(--text-muted);
  min-width: 4em;
  text-align: right;
}
.bidpanel,
.betpanel,
.answerpanel {
  width: min(480px, 100%);
  align-self: center;
  margin: 0;
}
.themes {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 220px), 1fr));
  gap: var(--sp-2);
}
.theme {
  width: 100%;
  min-height: 64px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--sp-2);
  padding: var(--sp-3);
  border-radius: var(--r-card);
  border: 1px solid transparent;
  background: var(--cell);
  color: var(--text);
  font: 600 var(--fs-16) / 1.2 var(--font-body);
  text-transform: uppercase;
  cursor: pointer;
}
.theme:disabled {
  cursor: default;
}
.theme:not(:disabled):hover,
.theme:not(:disabled):focus-visible {
  background: var(--cell-hover);
  box-shadow: var(--glow-gold);
}
.theme.removed {
  background: var(--cell-played);
  border-color: var(--border);
  color: var(--text-muted);
  text-decoration: line-through;
}
.theme .x {
  color: var(--danger);
}
.theme-name {
  margin: 0;
  font-size: clamp(22px, 6vw, 40px);
  font-weight: 800;
  text-transform: uppercase;
}
.answer {
  border-color: var(--success);
  text-align: center;
  margin: 0;
}
.textarea.body {
  font-family: var(--font-body);
  font-size: var(--fs-16);
  min-height: 72px;
}
.results tr.ok td {
  background: rgba(43, 212, 125, 0.08);
}
.results tr.bad td {
  background: rgba(255, 77, 94, 0.08);
}
.results .delta {
  font-weight: 700;
}
.results tr.ok .delta {
  color: var(--success);
}
.results tr.bad .delta {
  color: var(--danger);
}
.who {
  white-space: nowrap;
}
.who > * {
  vertical-align: middle;
}
.who b {
  margin: 0 4px 0 6px;
}
.ans {
  white-space: pre-wrap;
  word-break: break-word;
}
.judge {
  flex-wrap: nowrap;
}

/* TV */
.tv {
  gap: 2vh;
  font-size: clamp(16px, 1.4vw, 28px);
}
.tv .big-icon {
  font-size: 8vw;
}
.tv .hero h2,
.tv > h2 {
  font-size: 4vw;
}
.tv .lead {
  font-size: 2vw;
}
.tv .bid {
  font-size: 3vw;
}
.tv .bidders,
.tv .final-list {
  width: min(900px, 80vw);
}
.tv .theme {
  min-height: 12vh;
  font-size: 2vw;
}
.tv .theme-name {
  font-size: 4vw;
}
.tv .table {
  font-size: clamp(16px, 1.4vw, 28px);
}
</style>
