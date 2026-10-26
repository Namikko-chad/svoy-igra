<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useNow } from '@/composables/useNow'
import { useQuestionTimer } from '@/composables/useQuestionTimer'
import { useRoleSocket } from '@/composables/useRoleSocket'
import { PHASE_LABEL } from '@/utils/phase'
import { unlockAudio } from '@/utils/sound'
import { splitBlocks } from '@/utils/blocks'
import type { PlayerView } from '@/types/protocol'
import GameBoard from '@/components/GameBoard.vue'
import QuestionBlocks from '@/components/QuestionBlocks.vue'
import TimerBar from '@/components/TimerBar.vue'
import Standings from '@/components/Standings.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import HostSettings from '@/components/HostSettings.vue'
import GameShell from '@/components/GameShell.vue'
import AvatarImg from '@/components/AvatarImg.vue'
import AvatarEditor from '@/components/AvatarEditor.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import SpecialStage from '@/components/special/SpecialStage.vue'
import QuestionHeader from '@/components/special/QuestionHeader.vue'
import ModifierSplash from '@/components/special/ModifierSplash.vue'
import { useModifierSplash } from '@/composables/useModifierSplash'
import { isSpecialPhase } from '@/utils/phase'
import { wrongDelta } from '@/utils/special'

const props = defineProps<{ pin: string }>()
const { socket, token, leave } = useRoleSocket(props.pin, 'host', { sounds: true })
const showAvatar = ref(false)
const state = socket.state
const now = useNow()
const serverNow = computed(() => now.value + socket.clockOffset.value)
const timer = useQuestionTimer(state, serverNow)
const splash = useModifierSplash(state)

const send = (type: string, data: object = {}) => {
  unlockAudio()
  socket.send(type, data)
}

const phase = computed(() => state.value?.phase ?? 'lobby')
const players = computed(() => state.value?.players ?? [])
const nameOf = (id: string | null | undefined) => players.value.find((p) => p.id === id)?.name ?? '—'
const q = computed(() => state.value?.question ?? null)
// comment is raw markdown (protocol §4.2): split it like question text.
const commentBlocks = computed(() =>
  q.value?.comment && state.value?.pack ? splitBlocks(q.value.comment, state.value.pack.id) : [],
)

// ---- Board ----
const chooser = ref('')
watch(
  () => state.value?.chooserId,
  (id) => (chooser.value = id ?? ''),
  { immediate: true },
)
function setChooser() {
  if (chooser.value) send('set_chooser', { playerId: chooser.value })
}
const roundIndex = ref(0)
watch(
  () => state.value?.round?.index,
  (i) => (roundIndex.value = i ?? 0),
  { immediate: true },
)
function setRound() {
  send('set_round', { index: roundIndex.value })
}
const canSetRound = computed(() => phase.value === 'board' || phase.value === 'round_end')

// ---- Judge ----
const judgeValue = computed(() => q.value?.stake ?? q.value?.value ?? 0)
const judgeLoss = computed(() => (q.value ? wrongDelta(q.value, !!state.value?.settings?.wrongPenalty) : 0))
const resultText = computed(() => {
  const r = state.value?.lastResult
  if (!r) return null
  return { ok: r.correct, text: `${nameOf(r.playerId)}: ${r.correct ? 'верно' : 'неверно'} ${r.delta > 0 ? '+' : ''}${r.delta}` }
})

// ---- Dialogs ----
const showSettings = ref(false)
const confirmReset = ref(false)
const keepPlayers = ref(true)
const confirmFinish = ref(false)
const kickTarget = ref<PlayerView | null>(null)
function doReset() {
  send('reset_game', { keepPlayers: keepPlayers.value })
  confirmReset.value = false
}
function doFinish() {
  send('finish_game')
  confirmFinish.value = false
}
function doKick() {
  if (kickTarget.value) send('kick_player', { playerId: kickTarget.value.id })
  kickTarget.value = null
}
function saveSettings(patch: object) {
  send('update_settings', patch)
  showSettings.value = false
}

const menu = ref<HTMLDetailsElement | null>(null)
function closeMenu() {
  if (menu.value) menu.value.open = false
}
</script>

<template>
  <GameShell
    :socket="socket"
    :pin="pin"
    title="Ведущий"
    leave-text="Место ведущего освободится — его сможет занять другой участник."
    @leave="leave"
  >
    <template #bar>
      <span class="chip">{{ PHASE_LABEL[phase] }}</span>
      <span v-if="state?.pack" class="chip pack-chip" :title="state.pack.title">📦 {{ state.pack.title }}</span>
    </template>
    <template #menu>
      <details ref="menu" class="menu">
        <summary class="btn btn-sm">Меню</summary>
        <div class="menu-body card" @click="closeMenu">
          <button class="btn btn-ghost btn-sm" @click="showAvatar = true">Мой аватар</button>
          <button class="btn btn-ghost btn-sm" :disabled="!state?.settings" @click="showSettings = true">Настройки</button>
          <button class="btn btn-ghost btn-sm" :disabled="phase === 'lobby' || phase === 'finished'" @click="confirmFinish = true">
            Завершить игру
          </button>
          <button class="btn btn-ghost btn-sm danger" @click="confirmReset = true">Сбросить игру…</button>
        </div>
      </details>
    </template>

    <div v-if="!state" class="center-screen muted">Подключение…</div>

    <div v-else class="layout">
      <main class="main col">
        <!-- Lobby -->
        <section v-if="phase === 'lobby'" class="card col">
          <h2 class="m0">Подготовка</h2>
          <p v-if="!state.pack" class="m0 waiting">Ожидаем, пока администратор выберет пак…</p>
          <p v-else class="m0">Пак: <b>{{ state.pack.title }}</b></p>
          <p v-if="!players.length" class="muted small m0">Ждём игроков…</p>
          <AvatarEditor :token="token" :url="state.game.hostAvatarUrl" name="Ведущий" compact />
          <button class="btn btn-primary btn-lg" :disabled="!state.pack || !players.length" @click="send('start_game')">
            Начать игру
          </button>
        </section>

        <section v-if="phase === 'finished'" class="col">
          <Standings :players="players" title="Игра окончена" />
          <p class="muted small m0 center">Новую игру с другим паком готовит администратор.</p>
        </section>

        <!-- Board -->
        <section v-if="phase === 'board' && state.board" class="col">
          <div class="row">
            <h2 class="m0">{{ state.round?.name }}</h2>
            <span v-if="state.round" class="chip">раунд {{ state.round.index + 1 }} / {{ state.round.total }}</span>
            <span class="spacer" />
            <span class="muted small">Выбирает: <b class="gold">{{ nameOf(state.chooserId) }}</b></span>
          </div>
          <GameBoard :board="state.board" clickable @select="(id) => send('select_question', { questionId: id })" />
          <p class="muted small m0">Нажмите на вопрос, чтобы открыть его от имени выбирающего.</p>
        </section>

        <!-- Question / answering / reveal -->
        <section v-if="(phase === 'question' || phase === 'answering' || phase === 'reveal') && q" class="col">
          <QuestionHeader :question="q" />
          <TimerBar v-if="timer" :deadline="timer.deadline" :total="timer.total" :now="serverNow" :label="timer.label" />

          <div class="card">
            <QuestionBlocks :key="q.id" :blocks="q.blocks" mode="host" size="sm" />
          </div>

          <div class="card answer">
            <div class="muted small">Правильный ответ</div>
            <QuestionBlocks v-if="q.answerBlocks" :blocks="q.answerBlocks" mode="host" size="sm" />
            <template v-if="commentBlocks.length">
              <div class="muted small" style="margin-top: 12px">Комментарий</div>
              <QuestionBlocks :blocks="commentBlocks" mode="host" size="sm" />
            </template>
          </div>

          <div v-if="phase === 'question'" class="card col">
            <p v-if="state.soloPlayerId" class="m0">
              Отвечает <b class="accent">{{ nameOf(state.soloPlayerId) }}</b> — кнопок нет, ответ после чтения вопроса.
            </p>
            <p v-else class="m0 muted">
              Ждём нажатия кнопки…
              <template v-if="state.attemptedPlayerIds.length">
                Уже ошиблись: {{ state.attemptedPlayerIds.map(nameOf).join(', ') }}
              </template>
            </p>
            <button class="btn btn-ghost" @click="send('skip_question')">Пропустить вопрос</button>
          </div>

          <div v-if="phase === 'answering'" class="card col judge">
            <p class="m0 who">
              <AvatarImg
                :url="players.find((p) => p.id === state!.answeringPlayerId)?.avatarUrl"
                :name="nameOf(state.answeringPlayerId)"
                :size="64"
                ring="accent"
              />
              <span>Отвечает: <b class="accent">{{ nameOf(state.answeringPlayerId) }}</b></span>
            </p>
            <p class="m0 typed">
              <span class="muted small">Напечатанный ответ: </span>
              <span v-if="state.typedAnswer">«{{ state.typedAnswer }}»</span>
              <span v-else class="muted">—</span>
            </p>
            <div class="judge-bar">
              <button class="btn btn-success btn-lg" @click="send('judge', { correct: true })">Верно +{{ judgeValue }}</button>
              <button class="btn btn-danger btn-lg" @click="send('judge', { correct: false })">
                Неверно<template v-if="judgeLoss"> −{{ judgeLoss }}</template>
              </button>
            </div>
            <button class="btn btn-ghost btn-sm" @click="send('skip_question')">Пропустить вопрос</button>
          </div>

          <div v-if="phase === 'reveal'" class="card col">
            <p v-if="resultText" class="m0 result" :class="resultText.ok ? 'ok' : 'bad'">{{ resultText.text }}</p>
            <p v-else class="m0 muted">Никто не ответил.</p>
            <button class="btn btn-primary btn-lg" @click="send('continue')">Продолжить</button>
          </div>
        </section>

        <!-- Special questions and the final -->
        <SpecialStage v-if="isSpecialPhase(phase)" :state="state" role="host" :now="serverNow" @cmd="send" />

        <!-- Round end -->
        <section v-if="phase === 'round_end'" class="col">
          <Standings :players="players" :title="`Итоги раунда «${state.round?.name ?? ''}»`" />
          <button class="btn btn-primary btn-lg" @click="send('next_round')">
            {{ state.round && state.round.index + 1 >= state.round.total ? 'Завершить игру' : 'Следующий раунд' }}
          </button>
        </section>

        <!-- Round controls -->
        <section v-if="canSetRound && state.round" class="card row">
          <span class="muted small">Перейти к раунду:</span>
          <select v-model.number="roundIndex" class="select" style="width: auto">
            <option v-for="i in state.round.total" :key="i" :value="i - 1">{{ i }}</option>
          </select>
          <button class="btn btn-sm" @click="setRound">Перейти</button>
          <span class="spacer" />
          <button v-if="phase === 'board'" class="btn btn-ghost btn-sm" @click="send('next_round')">Следующий раунд →</button>
        </section>
      </main>

      <aside class="side col">
        <section class="card col">
          <h3 class="m0">Игроки ({{ players.length }})</h3>
          <ul class="plist">
            <li
              v-for="p in players"
              :key="p.id"
              :class="{ chooser: p.id === state.chooserId, answering: p.id === state.answeringPlayerId }"
            >
              <AvatarImg :url="p.avatarUrl" :name="p.name" :size="24" />
              <span class="dot" :class="{ on: p.connected }" />
              <span class="grow name">{{ p.name }}</span>
              <span class="display num score" :class="{ neg: p.score < 0 }">{{ p.score }}</span>
              <button class="btn btn-ghost btn-icon danger" title="Исключить" @click="kickTarget = p">✕</button>
            </li>
            <li v-if="!players.length" class="muted small">Пока никого</li>
          </ul>
          <div v-if="phase !== 'lobby' && players.length" class="row">
            <select v-model="chooser" class="select grow" aria-label="Выбирающий">
              <option v-for="p in players" :key="p.id" :value="p.id">{{ p.name }}</option>
            </select>
            <button class="btn btn-sm" :disabled="!chooser || chooser === state.chooserId" @click="setChooser">
              Назначить выбирающим
            </button>
          </div>
        </section>
        <section v-if="state.settings" class="card small muted">
          Чтение {{ state.settings.readingSeconds }} с · окно {{ state.settings.buzzSeconds }} с · штраф
          {{ state.settings.wrongPenalty ? 'да' : 'нет' }} · финал {{ state.settings.finalSeconds }} с · спецвопросы
          {{ state.settings.modifiers.cat }}/{{ state.settings.modifiers.auction }}/{{ state.settings.modifiers.noRisk }}/{{ state.settings.modifiers.double }}
          <button class="btn btn-ghost btn-sm" @click="showSettings = true">Изменить</button>
        </section>
      </aside>
    </div>

    <ModalDialog v-if="showAvatar && state" title="Аватар ведущего" @close="showAvatar = false">
      <AvatarEditor :token="token" :url="state.game.hostAvatarUrl" name="Ведущий" />
    </ModalDialog>
    <ModifierSplash v-if="splash" :modifier="splash.modifier" :stake="splash.stake" @close="splash = null" />
    <HostSettings v-if="showSettings && state?.settings" :settings="state.settings" @close="showSettings = false" @save="saveSettings" />
    <ConfirmDialog v-if="confirmReset" title="Сбросить игру?" confirm-text="Сбросить" @confirm="doReset" @cancel="confirmReset = false">
      <p>Игра вернётся в лобби, очки обнулятся, сыгранные вопросы снова станут доступны.</p>
      <label class="check"><input v-model="keepPlayers" type="checkbox" /> Оставить игроков</label>
      <p v-if="!keepPlayers" class="error-text">Все игроки будут отключены и должны будут войти заново.</p>
    </ConfirmDialog>
    <ConfirmDialog v-if="confirmFinish" title="Завершить игру?" confirm-text="Завершить" @confirm="doFinish" @cancel="confirmFinish = false">
      <p>Игра перейдёт к итоговой таблице.</p>
    </ConfirmDialog>
    <ConfirmDialog v-if="kickTarget" title="Исключить игрока?" confirm-text="Исключить" @confirm="doKick" @cancel="kickTarget = null">
      <p>«{{ kickTarget.name }}» будет удалён из игры вместе с очками.</p>
    </ConfirmDialog>
  </GameShell>
</template>

<style scoped>
.layout {
  width: 100%;
  max-width: 1400px;
  margin: 0 auto;
  padding: var(--sp-4);
  display: grid;
  grid-template-columns: minmax(0, 1fr) 320px;
  gap: var(--sp-4);
  align-items: start;
}
@media (max-width: 900px) {
  .layout {
    grid-template-columns: minmax(0, 1fr);
  }
}
.main {
  gap: var(--sp-4);
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
.waiting {
  color: var(--warning);
}
.pack-chip {
  max-width: 40vw;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.qhead {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}
.qhead .cat {
  text-transform: uppercase;
  font-weight: 600;
  color: var(--text-muted);
}
.qhead .value {
  font-size: var(--fs-32);
  font-weight: 800;
}
.answer {
  border-color: var(--success);
}
.judge-bar {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--sp-3);
}
.judge-bar .btn {
  min-height: 72px;
  font-size: var(--fs-20);
  white-space: normal;
}
.who {
  display: flex;
  align-items: center;
  gap: var(--sp-3);
}
.typed {
  font-size: var(--fs-20);
}
.result {
  font-weight: 600;
}
.result.ok {
  color: var(--success);
}
.result.bad {
  color: var(--danger);
}
.plist {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-1);
}
.plist li {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  padding: var(--sp-1) var(--sp-2);
  border-radius: var(--r-input);
  border: 1px solid transparent;
}
.plist li.chooser {
  border-color: var(--gold);
}
.plist li.answering {
  border-color: var(--accent);
}
.plist .name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.plist .score {
  color: var(--gold);
  font-weight: 600;
}
.plist .score.neg {
  color: var(--danger);
}
.menu {
  position: relative;
}
.menu summary {
  list-style: none;
}
.menu summary::-webkit-details-marker {
  display: none;
}
.menu-body {
  position: absolute;
  right: 0;
  top: calc(100% + 6px);
  z-index: 50;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: var(--sp-1);
  padding: var(--sp-2);
  min-width: 220px;
}
.menu-body .btn {
  justify-content: flex-start;
}
</style>
