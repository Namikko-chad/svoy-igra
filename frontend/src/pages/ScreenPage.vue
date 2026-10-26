<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoleSocket } from '@/composables/useRoleSocket'
import { useNow } from '@/composables/useNow'
import { useQuestionTimer } from '@/composables/useQuestionTimer'
import { unlockAudio } from '@/utils/sound'
import { splitBlocks } from '@/utils/blocks'
import GameBoard from '@/components/GameBoard.vue'
import Scoreboard from '@/components/Scoreboard.vue'
import QuestionBlocks from '@/components/QuestionBlocks.vue'
import TimerBar from '@/components/TimerBar.vue'
import Standings from '@/components/Standings.vue'
import QrCode from '@/components/QrCode.vue'
import GameShell from '@/components/GameShell.vue'
import AvatarImg from '@/components/AvatarImg.vue'
import SpecialStage from '@/components/special/SpecialStage.vue'
import QuestionHeader from '@/components/special/QuestionHeader.vue'
import ModifierSplash from '@/components/special/ModifierSplash.vue'
import { useModifierSplash } from '@/composables/useModifierSplash'
import { isSpecialPhase } from '@/utils/phase'
import ConfirmDialog from '@/components/ConfirmDialog.vue'

const props = defineProps<{ pin: string }>()
const { socket, leave } = useRoleSocket(props.pin, 'screen', { sounds: true })
const confirmLeave = ref(false)
const state = socket.state
const now = useNow()
const serverNow = computed(() => now.value + socket.clockOffset.value)
const timer = useQuestionTimer(state, serverNow)
const splash = useModifierSplash(state, 3500)

const players = computed(() => state.value?.players ?? [])
const nameOf = (id: string | null | undefined) => players.value.find((p) => p.id === id)?.name ?? '—'
const phase = computed(() => state.value?.phase ?? 'lobby')
const q = computed(() => state.value?.question ?? null)
// comment is raw markdown (protocol §4.2): split it like question text.
const commentBlocks = computed(() =>
  q.value?.comment && state.value?.pack ? splitBlocks(q.value.comment, state.value.pack.id) : [],
)

// Join link and PIN (protocol §8). A screen opened from the public list (`watch`) gets
// neither — then the lobby only says that the admin hands out the link.
const joinUrl = computed(() => state.value?.game.link ?? null)
const gamePin = computed(() => state.value?.game.pin ?? null)

// Browsers block autoplay with sound until the page has been clicked once.
const soundEnabled = ref(false)
const retry = ref(0)
function enableSound() {
  unlockAudio()
  soundEnabled.value = true
  retry.value++
}
function onBlocked() {
  soundEnabled.value = false
}

function toggleFullscreen() {
  if (document.fullscreenElement) void document.exitFullscreen().catch(() => {})
  else void document.documentElement.requestFullscreen?.().catch(() => {})
}

const resultText = computed(() => {
  const r = state.value?.lastResult
  if (!r) return null
  return { ok: r.correct, text: `${nameOf(r.playerId)}: ${r.correct ? 'верно' : 'неверно'} ${r.delta > 0 ? '+' : ''}${r.delta}` }
})
</script>

<template>
  <GameShell :socket="socket" :pin="pin" title="Экран" leave-text="" bare>
  <div class="screen stage" @dblclick="toggleFullscreen">
    <header class="bar">
      <span class="brand display">Своя <span class="gold">игра</span></span>
      <span v-if="state?.round && phase !== 'lobby'" class="round">
        {{ state.round.name }} · {{ state.round.index + 1 }}/{{ state.round.total }}
      </span>
      <span class="spacer" />
      <span v-if="state?.game.hostTaken" class="host-chip">
        <AvatarImg :url="state.game.hostAvatarUrl" name="Ведущий" :size="40" />
        <span>Ведущий</span>
      </span>
      <span v-if="!socket.connected.value" class="chip"><span class="dot" /> нет связи</span>
      <span v-if="gamePin" class="chip mono pin-chip">PIN {{ gamePin }}</span>
      <button class="btn btn-ghost btn-sm exit" @click.stop="confirmLeave = true">Выйти</button>
    </header>

    <main class="main">
      <div v-if="!state" class="lobby muted">Подключение…</div>

      <!-- Lobby -->
      <section v-else-if="phase === 'lobby'" class="lobby">
        <h1 class="display title">{{ state.game.title || 'Своя игра' }}</h1>
        <div v-if="joinUrl || gamePin" class="joinbox">
          <QrCode v-if="joinUrl" class="qrimg" :text="joinUrl" />
          <div class="col">
            <template v-if="joinUrl">
              <p class="join">Подключайтесь с телефона:</p>
              <p class="url mono">{{ joinUrl }}</p>
            </template>
            <template v-if="gamePin">
              <p class="join">PIN игры</p>
              <p class="bigpin display num">{{ gamePin }}</p>
            </template>
          </div>
        </div>
        <p v-else class="join muted">Ссылку для входа раздаёт администратор</p>
        <Scoreboard v-if="players.length" class="lobby-players" :players="players" tv />
        <p v-if="state.pack" class="muted packname">{{ state.pack.title }}</p>
        <p v-if="!players.length" class="muted">Ждём игроков…</p>
      </section>

      <!-- Board -->
      <section v-else-if="phase === 'board' && state.board" class="board-wrap">
        <p class="chooser">Выбирает: <b class="gold">{{ nameOf(state.chooserId) }}</b></p>
        <GameBoard :board="state.board" tv />
      </section>

      <!-- Question / answering / reveal -->
      <section v-else-if="(phase === 'question' || phase === 'answering' || phase === 'reveal') && q" class="question">
        <QuestionHeader :question="q" tv />
        <TimerBar v-if="timer" class="timer" :deadline="timer.deadline" :total="timer.total" :now="serverNow" :label="timer.label" />
        <div v-if="phase === 'answering' || (phase === 'question' && state.soloPlayerId)" class="answering">
          <AvatarImg
            :url="players.find((p) => p.id === (state!.answeringPlayerId ?? state!.soloPlayerId))?.avatarUrl"
            :name="nameOf(state.answeringPlayerId ?? state.soloPlayerId)"
            :size="96"
            ring="accent"
          />
          <span>Отвечает <b>{{ nameOf(state.answeringPlayerId ?? state.soloPlayerId) }}</b></span>
        </div>

        <Transition name="zoom" appear>
          <QuestionBlocks
            :key="q.id"
            class="qblocks"
            :class="{ dim: phase === 'reveal' }"
            :blocks="q.blocks"
            mode="screen"
            :size="phase === 'reveal' ? 'md' : 'lg'"
            :retry="retry"
            :active="phase !== 'reveal'"
            @blocked="onBlocked"
          />
        </Transition>

        <div v-if="phase === 'reveal'" class="reveal">
          <p v-if="resultText" class="result" :class="resultText.ok ? 'ok' : 'bad'">{{ resultText.text }}</p>
          <div v-if="q.answerBlocks?.length || commentBlocks.length" class="answer">
            <QuestionBlocks v-if="q.answerBlocks" :blocks="q.answerBlocks" mode="screen" size="lg" :retry="retry" @blocked="onBlocked" />
            <QuestionBlocks v-if="commentBlocks.length" class="comment muted" :blocks="commentBlocks" mode="screen" size="sm" :retry="retry" @blocked="onBlocked" />
          </div>
        </div>
      </section>

      <section v-else-if="isSpecialPhase(phase)" class="special-wrap">
        <SpecialStage :state="state" role="screen" :now="serverNow" tv :retry="retry" @blocked="onBlocked" />
      </section>
      <section v-else-if="phase === 'round_end'" class="lobby">
        <Standings :players="players" :title="`Итоги раунда «${state.round?.name ?? ''}»`" tv />
      </section>
      <section v-else-if="phase === 'finished'" class="lobby">
        <Standings :players="players" title="Игра окончена" tv />
      </section>
    </main>

    <footer v-if="state && phase !== 'lobby'" class="foot">
      <Scoreboard
        :players="players"
        :chooser-id="state.chooserId"
        :answering-id="state.answeringPlayerId"
        :attempted="state.attemptedPlayerIds"
        tv
      />
    </footer>

    <button v-if="!soundEnabled" class="sound-overlay" @click="enableSound">
      <span class="display">🔊 Нажмите, чтобы включить звук</span>
      <span v-if="gamePin" class="overlay-pin display num">PIN {{ gamePin }}</span>
      <span class="muted">Двойной клик — полноэкранный режим</span>
    </button>
    <ModifierSplash v-if="splash && soundEnabled" :modifier="splash.modifier" :stake="splash.stake" tv @close="splash = null" />
    <ConfirmDialog v-if="confirmLeave" title="Отключить экран?" confirm-text="Выйти" @confirm="leave" @cancel="confirmLeave = false">
      <p>Этот экран перестанет показывать игру. Подключить снова можно по PIN игры.</p>
    </ConfirmDialog>
  </div>
  </GameShell>
</template>

<style scoped>
.screen {
  height: 100vh;
  height: 100dvh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  padding: 1.5vh 2vw;
  gap: 1.5vh;
  cursor: default;
}
.bar {
  display: flex;
  align-items: center;
  gap: 2vw;
  font-size: clamp(14px, 1.2vw, 24px);
}
.brand {
  font-weight: 800;
}
.round {
  color: var(--text-muted);
}
.spacer {
  flex: 1;
}
.main {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}
.lobby {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  gap: 1vh;
  font-size: clamp(16px, 1.6vw, 32px);
}
.title {
  font-size: clamp(48px, 6vw, 120px);
  font-weight: 800;
  text-shadow: var(--glow-gold);
  margin-bottom: 3vh;
}
.join {
  margin: 0;
}
.url {
  margin: 0;
  font-size: clamp(28px, 3.4vw, 72px);
  color: var(--accent);
  text-shadow: var(--glow-accent);
}
.joinbox {
  display: flex;
  align-items: center;
  gap: 3vw;
  text-align: left;
}
.qrimg {
  width: clamp(140px, 16vw, 320px);
  flex: none;
}
.lobby-players {
  margin-top: 3vh;
  max-width: 80vw;
}
.bigpin {
  margin: 0;
  font-size: clamp(48px, 6vw, 120px);
  font-weight: 800;
  letter-spacing: 0.08em;
  color: var(--gold);
  text-shadow: var(--glow-gold);
}
.pin-chip {
  font-size: clamp(12px, 1vw, 20px);
}
.exit {
  opacity: 0.5;
}
.exit:hover,
.exit:focus-visible {
  opacity: 1;
}
.overlay-pin {
  color: var(--gold);
  font-size: clamp(24px, 3vw, 56px);
}
.packname {
  margin-top: 2vh;
}
.board-wrap {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 1.5vh;
  min-height: 0;
}
.board-wrap :deep(.board-scroll) {
  flex: 1;
  min-height: 0;
}
.chooser {
  margin: 0;
  text-align: center;
  font-size: clamp(16px, 1.6vw, 32px);
}
.question {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2vh;
  overflow: hidden;
}
.qhead {
  width: 100%;
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}
.qhead .cat {
  text-transform: uppercase;
  font-weight: 600;
  color: var(--text-muted);
  font-size: clamp(16px, 1.6vw, 32px);
}
.qhead .value {
  font-size: clamp(32px, 3.6vw, 72px);
  font-weight: 800;
}
.timer {
  width: 100%;
}
.timer :deep(.bar) {
  height: 10px;
}
.timer :deep(.meta .muted) {
  font-size: clamp(14px, 1.2vw, 24px);
}
.timer :deep(.count) {
  font-size: clamp(20px, 2vw, 40px);
}
.special-wrap {
  flex: 1;
  min-height: 0;
  overflow: auto;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.host-chip {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  color: var(--text-muted);
}
.answering {
  display: flex;
  align-items: center;
  gap: 1.5vw;
  font-size: clamp(20px, 2.4vw, 48px);
  color: var(--accent);
  text-shadow: var(--glow-accent);
}
.answering b {
  color: var(--text);
}
.qblocks {
  flex: 1;
  justify-content: center;
}
.qblocks.dim {
  flex: 0 1 auto;
  opacity: 0.75;
}
.reveal {
  width: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1.5vh;
}
.answer {
  border: 2px solid var(--success);
  border-radius: var(--r-card);
  padding: 2vh 3vw;
  background: var(--surface);
  box-shadow: 0 0 32px rgba(43, 212, 125, 0.25);
}
.comment {
  margin-top: 1vh;
  font-size: clamp(14px, 1.2vw, 24px);
  text-align: center;
}
.result {
  margin: 0;
  font-size: clamp(20px, 2vw, 40px);
  font-weight: 600;
}
.result.ok {
  color: var(--success);
}
.result.bad {
  color: var(--danger);
}
.foot {
  flex: none;
}
.sound-overlay {
  position: fixed;
  inset: 0;
  border: none;
  background: rgba(3, 6, 20, 0.82);
  color: var(--text);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2vh;
  font-size: clamp(20px, 2.4vw, 48px);
  cursor: pointer;
  z-index: 100;
}
.sound-overlay .muted {
  font-size: clamp(14px, 1.2vw, 24px);
}
.zoom-enter-active {
  transition:
    transform 380ms ease-out,
    opacity 380ms ease-out;
}
.zoom-enter-from {
  transform: scale(0.5);
  opacity: 0;
}
</style>
