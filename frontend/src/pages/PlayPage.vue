<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useNow } from '@/composables/useNow'
import { useQuestionTimer } from '@/composables/useQuestionTimer'
import { useRoleSocket } from '@/composables/useRoleSocket'
import { sounds, unlockAudio } from '@/utils/sound'
import { splitBlocks } from '@/utils/blocks'
import GameBoard from '@/components/GameBoard.vue'
import Scoreboard from '@/components/Scoreboard.vue'
import QuestionBlocks from '@/components/QuestionBlocks.vue'
import TimerBar from '@/components/TimerBar.vue'
import BuzzerButton from '@/components/BuzzerButton.vue'
import Standings from '@/components/Standings.vue'
import GameShell from '@/components/GameShell.vue'
import AvatarImg from '@/components/AvatarImg.vue'
import AvatarEditor from '@/components/AvatarEditor.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import SpecialStage from '@/components/special/SpecialStage.vue'
import QuestionHeader from '@/components/special/QuestionHeader.vue'
import ModifierSplash from '@/components/special/ModifierSplash.vue'
import { useModifierSplash } from '@/composables/useModifierSplash'
import { isSpecialPhase } from '@/utils/phase'

const props = defineProps<{ pin: string }>()
const { socket, stored, token, leave } = useRoleSocket(props.pin, 'player')
const showAvatar = ref(false)
const state = socket.state
const now = useNow()
const serverNow = computed(() => now.value + socket.clockOffset.value)
const timer = useQuestionTimer(state, serverNow)
const splash = useModifierSplash(state)
const send = (type: string, data: object = {}) => socket.send(type, data)

const me = computed(() => state.value?.me ?? null)
const players = computed(() => state.value?.players ?? [])
const commentBlocks = computed(() => {
  const s = state.value
  return s?.question?.comment && s.pack ? splitBlocks(s.question.comment, s.pack.id) : []
})
const nameOf = (id: string | null | undefined) => players.value.find((p) => p.id === id)?.name ?? '—'
const avatarOf = (id: string | null | undefined) => players.value.find((p) => p.id === id)?.avatarUrl ?? null

// Feedback when my button opens / when I get judged.
watch(
  () => me.value?.buzzer,
  (b, prev) => {
    if (b === 'open' && prev !== 'open') sounds.open()
  },
)
socket.onEvent((e) => {
  if ((e.kind === 'judged' || e.kind === 'final_judged') && e.playerId === me.value?.id) (e.correct ? sounds.correct : sounds.wrong)()
  else if (e.kind === 'modifier') sounds.fanfare()
})
// My turn in the auction / theme removal / cat choice → a short cue.
watch(
  () => !!(me.value?.canBid || me.value?.canRemoveTheme || me.value?.canGiveCat),
  (now, before) => {
    if (now && !before) sounds.open()
  },
)

const closedReason = computed(() => {
  const s = state.value
  if (!s) return ''
  if (s.phase === 'answering' && s.answeringPlayerId) return `Отвечает ${nameOf(s.answeringPlayerId)}`
  return 'Время вышло'
})

function buzz() {
  unlockAudio()
  socket.send('buzz', {})
}
function select(questionId: number) {
  socket.send('select_question', { questionId })
}

// Optional typed answer, debounced; last one wins on the server.
const typed = ref('')
let typeTimer: ReturnType<typeof setTimeout> | null = null
watch(typed, (text) => {
  if (typeTimer) clearTimeout(typeTimer)
  typeTimer = setTimeout(() => {
    if (me.value?.canType) socket.send('submit_answer', { text: text.slice(0, 200) })
  }, 350)
})
watch(
  () => me.value?.canType,
  (can) => {
    if (!can) typed.value = ''
  },
)

const resultText = computed(() => {
  const r = state.value?.lastResult
  if (!r) return null
  return { ok: r.correct, text: `${nameOf(r.playerId)}: ${r.correct ? 'верно' : 'неверно'} ${r.delta > 0 ? '+' : ''}${r.delta}` }
})

</script>

<template>
  <GameShell
    :socket="socket"
    :pin="pin"
    :title="me?.name ?? stored?.name ?? 'Игрок'"
    leave-text="Ваше место и очки в этой игре будут удалены."
    class="play stage"
    @leave="leave"
  >
    <template #bar>
      <button v-if="me" class="avatar-btn" title="Аватар" aria-label="Изменить аватар" @click="showAvatar = true">
        <AvatarImg :url="avatarOf(me.id)" :name="me.name" :size="32" />
      </button>
      <span v-if="me" class="display num score" :class="{ neg: me.score < 0 }">{{ me.score }}</span>
    </template>
    <main v-if="state" class="content">
      <!-- Lobby -->
      <section v-if="state.phase === 'lobby'" class="center col">
        <h2>Ожидаем начала игры</h2>
        <p class="muted">Ведущий скоро начнёт. Пока можно посмотреть, кто уже здесь.</p>
        <div v-if="me" class="card">
          <AvatarEditor :token="token" :url="avatarOf(me.id)" :name="me.name" />
        </div>
      </section>

      <!-- Board -->
      <section v-else-if="state.phase === 'board' && state.board" class="col">
        <div class="row">
          <h2 class="m0">{{ state.round?.name ?? 'Раунд' }}</h2>
          <span v-if="state.round" class="chip">{{ state.round.index + 1 }} / {{ state.round.total }}</span>
        </div>
        <p v-if="me?.canSelect" class="your-turn">Ваш выбор! Нажмите на вопрос.</p>
        <p v-else class="muted m0">Выбирает: <b class="gold">{{ nameOf(state.chooserId) }}</b></p>
        <GameBoard :board="state.board" :clickable="!!me?.canSelect" @select="select" />
      </section>

      <!-- Question / answering / reveal -->
      <section
        v-else-if="(state.phase === 'question' || state.phase === 'answering' || state.phase === 'reveal') && state.question"
        class="question col"
      >
        <QuestionHeader :question="state.question" />
        <TimerBar v-if="timer" :deadline="timer.deadline" :total="timer.total" :now="serverNow" :label="timer.label" />
        <p v-else-if="state.phase === 'answering'" class="muted center m0 answering-who">
          <AvatarImg :url="avatarOf(state.answeringPlayerId)" :name="nameOf(state.answeringPlayerId)" :size="64" ring="accent" />
          <span>Отвечает <b class="accent">{{ nameOf(state.answeringPlayerId) }}</b></span>
        </p>

        <Transition name="zoom" appear>
          <QuestionBlocks :key="state.question.id" :blocks="state.question.blocks" mode="player" />
        </Transition>

        <template v-if="state.phase === 'reveal'">
          <p v-if="resultText" class="result" :class="resultText.ok ? 'ok' : 'bad'">{{ resultText.text }}</p>
          <div class="answer card">
            <div class="muted small">Правильный ответ</div>
            <QuestionBlocks v-if="state.question.answerBlocks" :blocks="state.question.answerBlocks" mode="player" />
            <QuestionBlocks v-if="commentBlocks.length" class="muted comment" :blocks="commentBlocks" mode="player" size="sm" />
          </div>
        </template>

        <!-- Solo question (cat / auction / no risk): no buttons, one player answers. -->
        <div v-else-if="state.soloPlayerId" class="buzz-area">
          <p class="solo" :class="{ mine: state.soloPlayerId === me?.id }">
            <template v-if="state.soloPlayerId === me?.id">
              {{ state.phase === 'answering' ? 'Вы отвечаете!' : 'Отвечаете вы — после чтения вопроса' }}
            </template>
            <template v-else>
              <AvatarImg :url="avatarOf(state.soloPlayerId)" :name="nameOf(state.soloPlayerId)" :size="40" ring="accent" />
              Отвечает <b>{{ nameOf(state.soloPlayerId) }}</b>
            </template>
          </p>
          <label v-if="me?.canType" class="field typed">
            Можно напечатать ответ (необязательно)
            <input v-model="typed" class="input" maxlength="200" autocomplete="off" enterkeyhint="done" />
          </label>
        </div>

        <div v-else-if="me && me.buzzer !== 'hidden'" class="buzz-area">
          <BuzzerButton
            :state="me.buzzer"
            :opens-at="me.buzzOpensAt"
            :now="serverNow"
            :closed-reason="closedReason"
            @press="buzz"
          />
          <label v-if="me.canType" class="field typed">
            Можно напечатать ответ (необязательно)
            <input v-model="typed" class="input" maxlength="200" autocomplete="off" enterkeyhint="done" />
          </label>
        </div>
      </section>

      <!-- Special questions before the question, and the final -->
      <SpecialStage v-else-if="isSpecialPhase(state.phase)" :state="state" role="player" :now="serverNow" @cmd="send" />

      <!-- Round end / finished -->
      <section v-else-if="state.phase === 'round_end'" class="col">
        <Standings :players="players" :title="`Итоги раунда «${state.round?.name ?? ''}»`" :me-id="me?.id" />
      </section>
      <section v-else-if="state.phase === 'finished'" class="col">
        <Standings :players="players" title="Игра окончена" :me-id="me?.id" />
      </section>

      <footer class="scores">
        <Scoreboard
          :players="players"
          :chooser-id="state.chooserId"
          :answering-id="state.answeringPlayerId"
          :attempted="state.attemptedPlayerIds"
          :me-id="me?.id"
        />
      </footer>
    </main>
    <div v-else class="center-screen muted">Подключение…</div>
    <ModalDialog v-if="showAvatar && me" title="Аватар" @close="showAvatar = false">
      <AvatarEditor :token="token" :url="avatarOf(me.id)" :name="me.name" />
    </ModalDialog>
    <ModifierSplash v-if="splash" :modifier="splash.modifier" :stake="splash.stake" @close="splash = null" />
  </GameShell>
</template>

<style scoped>
.play {
  min-height: 100dvh;
  display: flex;
  flex-direction: column;
}
.score {
  color: var(--gold);
  font-weight: 600;
  font-size: var(--fs-20);
}
.score.neg {
  color: var(--danger);
}
.content {
  flex: 1;
  width: 100%;
  max-width: 1200px;
  margin: 0 auto;
  padding: var(--sp-4);
  display: flex;
  flex-direction: column;
  gap: var(--sp-6);
}
.center {
  text-align: center;
  align-items: center;
}
.m0 {
  margin: 0;
}
.accent {
  color: var(--accent);
}
.your-turn {
  margin: 0;
  padding: var(--sp-3);
  border: 1px solid var(--gold);
  border-radius: var(--r-card);
  color: var(--gold);
  font-weight: 600;
  box-shadow: var(--glow-gold);
  text-align: center;
}
.question {
  align-items: stretch;
  gap: var(--sp-4);
}
.qhead {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  gap: var(--sp-3);
}
.qhead .cat {
  text-transform: uppercase;
  font-weight: 600;
  font-size: var(--fs-14);
  color: var(--text-muted);
}
.qhead .display {
  font-size: var(--fs-24);
  font-weight: 800;
}
.buzz-area {
  position: sticky;
  bottom: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--sp-4);
  padding: var(--sp-4) 0 calc(var(--sp-4) + env(safe-area-inset-bottom));
}
.avatar-btn {
  all: unset;
  cursor: pointer;
  border-radius: 999px;
  display: inline-flex;
}
.avatar-btn:focus-visible {
  outline: 2px solid var(--accent);
}
.answering-who {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--sp-2);
}
.solo {
  display: inline-flex;
  align-items: center;
  gap: var(--sp-2);
  margin: 0;
  padding: var(--sp-4) var(--sp-6);
  border-radius: var(--r-pill);
  border: 2px solid var(--accent);
  font-size: var(--fs-20);
  text-align: center;
}
.solo.mine {
  border-color: var(--gold);
  color: var(--gold);
  box-shadow: var(--glow-gold);
  font-weight: 600;
}
.typed {
  width: min(480px, 100%);
}
.answer {
  text-align: center;
}
.comment {
  margin-top: var(--sp-3);
}
.result {
  margin: 0;
  text-align: center;
  font-weight: 600;
}
.result.ok {
  color: var(--success);
}
.result.bad {
  color: var(--danger);
}
.notice {
  width: min(420px, 100%);
}
.scores {
  margin-top: auto;
}
.zoom-enter-active {
  transition:
    transform 350ms ease-out,
    opacity 350ms ease-out;
}
.zoom-enter-from {
  transform: scale(0.6);
  opacity: 0;
}
</style>
