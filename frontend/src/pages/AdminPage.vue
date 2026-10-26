<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useRoleSocket } from '@/composables/useRoleSocket'
import { useToastStore } from '@/stores/toast'
import { gameApi, packsApi } from '@/api'
import { ApiError, errorMessage } from '@/api/http'
import { PHASE_LABEL } from '@/utils/phase'
import { digitsOnly, isAdminPin } from '@/utils/pin'
import type { PackSummary, PlayerView } from '@/types/protocol'
import { settingsForm, settingsPatch } from '@/utils/special'
import SettingsFields from '@/components/SettingsFields.vue'
import GameShell from '@/components/GameShell.vue'
import AvatarImg from '@/components/AvatarImg.vue'
import ShareCard from '@/components/ShareCard.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import AdminPlayerRow from '@/components/admin/AdminPlayerRow.vue'

const props = defineProps<{ pin: string }>()
const route = useRoute()
const toast = useToastStore()
const { socket, token, leave } = useRoleSocket(props.pin, 'admin')
const state = socket.state
const justCreated = route.query.created === '1'
// Admins always receive pin/link; the fallback only keeps the types honest.
const shareFallback = `${location.origin}/g/${props.pin}`

// The admin never renders board/question/answer — only players, pack, phase, settings.
const players = computed(() => state.value?.players ?? [])
const online = computed(() => players.value.filter((p) => p.connected).length)
const phase = computed(() => state.value?.phase ?? 'lobby')
const canLoadPack = computed(() => phase.value === 'lobby' || phase.value === 'finished')

function apiError(e: unknown) {
  if (e instanceof ApiError && e.status === 401) toast.error('Сессия администратора недействительна')
  else toast.error(errorMessage(e))
}

// ---- Packs ----
const packs = ref<PackSummary[]>([])
const packsLoading = ref(false)
const selectedPack = ref('')
async function loadPacks() {
  if (!token) return
  packsLoading.value = true
  try {
    packs.value = await packsApi(token).list()
  } catch (e) {
    apiError(e)
  } finally {
    packsLoading.value = false
  }
}
onMounted(loadPacks)
watch(
  () => state.value?.pack?.id,
  (id) => {
    if (id) selectedPack.value = id
  },
  { immediate: true },
)
function loadPack() {
  if (selectedPack.value) socket.send('load_pack', { packId: selectedPack.value })
}

// ---- Settings (all of them, incl. timers) ----
const settings = ref(settingsForm(null))
const settingsDirty = ref(false)
watch(
  () => state.value?.settings,
  (s) => {
    if (s && !settingsDirty.value) settings.value = settingsForm(s)
  },
  { immediate: true },
)
const autoComp = computed(() => state.value?.settings?.autoLatencyCompensation ?? false)
function saveSettings() {
  settingsDirty.value = false
  socket.send('update_settings', settingsPatch(settings.value))
}
function toggleAuto(ev: Event) {
  socket.send('update_settings', { autoLatencyCompensation: (ev.target as HTMLInputElement).checked })
}

// ---- Game: rename / admin PIN / close / reset ----
const showGameEdit = ref(false)
const gameForm = reactive({ title: '', pin: '', pin2: '' })
function openGameEdit() {
  gameForm.title = state.value?.game.title ?? ''
  gameForm.pin = ''
  gameForm.pin2 = ''
  showGameEdit.value = true
}
const gameFormError = computed(() => {
  if (gameForm.title.trim().length > 60) return 'Название — до 60 символов'
  if (gameForm.pin && !isAdminPin(gameForm.pin)) return 'PIN администратора — от 4 до 8 цифр'
  if (gameForm.pin && gameForm.pin !== gameForm.pin2) return 'PIN-коды не совпадают'
  return ''
})
function saveGame() {
  if (gameFormError.value) return
  const patch: { title?: string; adminPin?: string } = {}
  if (gameForm.title.trim() !== (state.value?.game.title ?? '')) patch.title = gameForm.title.trim()
  if (gameForm.pin) patch.adminPin = gameForm.pin
  if (Object.keys(patch).length && socket.send('update_game', patch)) {
    toast.success(patch.adminPin ? 'PIN администратора изменён' : 'Сохранено')
  }
  showGameEdit.value = false
}
const confirmClose = ref(false)
function doClose() {
  confirmClose.value = false
  socket.send('close_game')
}
const confirmReset = ref(false)
const keepPlayers = ref(true)
function doReset() {
  socket.send('reset_game', { keepPlayers: keepPlayers.value })
  confirmReset.value = false
}

// ---- Game file ----
const importInput = ref<HTMLInputElement | null>(null)
async function exportGame() {
  try {
    await gameApi(token).exportGame()
  } catch (e) {
    apiError(e)
  }
}
async function importGame(ev: Event) {
  const input = ev.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file) return
  try {
    await gameApi(token).importGame(file)
    toast.success('Игра загружена из файла')
  } catch (e) {
    apiError(e)
  }
}

// ---- Players ----
const kickTarget = ref<PlayerView | null>(null)
function doKick() {
  if (kickTarget.value) socket.send('kick_player', { playerId: kickTarget.value.id })
  kickTarget.value = null
}
</script>

<template>
  <GameShell
    :socket="socket"
    :pin="pin"
    title="Администратор"
    leave-text="Этот вход администратора будет закрыт. Вернуться можно по PIN-коду администратора."
    @leave="leave"
  >
    <template #bar>
      <span v-if="state" class="chip">{{ PHASE_LABEL[state.phase] }}</span>
    </template>

    <div v-if="!state" class="center-screen muted">Подключение…</div>
    <main v-else class="page col">
      <p v-if="justCreated" class="created">Игра создана! Поделитесь PIN-кодом или ссылкой с участниками.</p>
      <div class="top">
        <ShareCard :pin="state.game.pin ?? pin" :link="state.game.link ?? shareFallback" :title="state.game.title" />

        <section class="card col">
          <div class="row">
            <h2 class="m0 grow">{{ state.game.title || 'Своя игра' }}</h2>
            <button class="btn btn-sm" @click="openGameEdit">Изменить</button>
          </div>
          <div class="row small">
            <span class="chip host">
              <AvatarImg v-if="state.game.hostTaken" :url="state.game.hostAvatarUrl" name="Ведущий" :size="24" />
              <span class="dot" :class="{ on: state.game.hostConnected }" />
              ведущий: {{ state.game.hostTaken ? (state.game.hostConnected ? 'в сети' : 'не в сети') : 'нет' }}
            </span>
            <button v-if="state.game.hostAvatarUrl" class="btn btn-ghost btn-sm" @click="socket.send('clear_avatar', {})">
              Удалить аватар ведущего
            </button>
            <span v-if="state.admins != null" class="chip">администраторов: {{ state.admins }}</span>
            <span v-if="state.round" class="chip">раунд {{ state.round.index + 1 }} / {{ state.round.total }} · {{ state.round.name }}</span>
          </div>
          <div class="row">
            <button class="btn btn-sm" @click="exportGame">Экспорт игры</button>
            <button class="btn btn-sm" @click="importInput?.click()">Импорт игры…</button>
            <input ref="importInput" type="file" accept=".json,application/json" hidden @change="importGame" />
            <span class="spacer" />
            <button class="btn btn-ghost btn-sm danger" @click="confirmReset = true">Сбросить…</button>
            <button class="btn btn-ghost btn-sm danger" @click="confirmClose = true">Закрыть игру</button>
          </div>
        </section>
      </div>

      <div class="top">
        <section class="card col">
          <h2 class="m0">Пак вопросов</h2>
          <p class="m0">Загружен: <b>{{ state.pack?.title ?? 'нет' }}</b></p>
          <div class="row">
            <select v-model="selectedPack" class="select grow" :disabled="packsLoading || !canLoadPack">
              <option value="" disabled>{{ packsLoading ? 'Загрузка…' : 'Выберите пак' }}</option>
              <option v-for="p in packs" :key="p.id" :value="p.id">
                {{ p.locked ? '🔒 ' : '' }}{{ p.title }} — {{ p.rounds }} р., {{ p.questions }} вопр.
              </option>
            </select>
            <button class="btn btn-primary" :disabled="!selectedPack || !canLoadPack || selectedPack === state.pack?.id" @click="loadPack">
              Загрузить
            </button>
            <button class="btn btn-ghost btn-sm" title="Обновить список" @click="loadPacks">↻</button>
          </div>
          <p v-if="!canLoadPack" class="muted small m0">Пак меняется в лобби или после окончания игры.</p>
          <RouterLink :to="`/g/${pin}/admin/packs`" class="small">Библиотека паков и редактор →</RouterLink>
        </section>

        <form class="card col" @submit.prevent="saveSettings" @input="settingsDirty = true">
          <h2 class="m0">Настройки</h2>
          <SettingsFields v-model="settings" />
          <label class="check">
            <input type="checkbox" :checked="autoComp" @change.stop="toggleAuto" />
            Автокомпенсация задержки (кнопка раньше на RTT/2)
          </label>
          <div class="row">
            <span class="muted xs grow">Таймеры — со следующего вопроса, спецвопросы — со следующего раунда.</span>
            <button class="btn btn-sm btn-primary" :disabled="!settingsDirty">Сохранить</button>
          </div>
        </form>
      </div>

      <div class="row">
        <h2 class="m0">Игроки</h2>
        <span class="chip">{{ online }} / {{ players.length }} в сети</span>
      </div>
      <p class="muted small m0">
        Смещение кнопки: положительное — кнопка появляется позже, отрицательное — раньше (−5000…10000 мс). Задержка:
        <span class="lvl-success">&lt; 60 мс</span>, <span class="lvl-warning">60–150 мс</span>,
        <span class="lvl-danger">&gt; 150 мс</span>.
      </p>
      <div class="table-wrap">
        <table class="table">
          <thead>
            <tr>
              <th>Игрок</th>
              <th>Очки</th>
              <th>Устройство</th>
              <th>Задержка (RTT)</th>
              <th>Смещение кнопки</th>
              <th>Статистика</th>
              <th />
            </tr>
          </thead>
          <tbody>
            <AdminPlayerRow
              v-for="p in players"
              :key="p.id"
              :player="p"
              @set-score="(score) => socket.send('set_score', { playerId: p.id, score })"
              @adjust="(delta) => socket.send('adjust_score', { playerId: p.id, delta })"
              @set-offset="(offsetMs) => socket.send('set_buzz_offset', { playerId: p.id, offsetMs })"
              @kick="kickTarget = p"
              @clear-avatar="socket.send('clear_avatar', { playerId: p.id })"
            />
            <tr v-if="!players.length">
              <td colspan="7" class="empty">Игроков пока нет</td>
            </tr>
          </tbody>
        </table>
      </div>
    </main>

    <ModalDialog v-if="showGameEdit" title="Игра" @close="showGameEdit = false">
      <form class="col" @submit.prevent="saveGame">
        <label class="field">
          Название
          <input v-model="gameForm.title" class="input" maxlength="60" />
        </label>
        <label class="field">
          Новый PIN администратора (оставьте пустым, чтобы не менять)
          <input
            :value="gameForm.pin"
            class="input mono"
            type="password"
            inputmode="numeric"
            autocomplete="new-password"
            maxlength="8"
            @input="gameForm.pin = digitsOnly(($event.target as HTMLInputElement).value, 8)"
          />
        </label>
        <label v-if="gameForm.pin" class="field">
          Повторите PIN
          <input
            :value="gameForm.pin2"
            class="input mono"
            type="password"
            inputmode="numeric"
            autocomplete="new-password"
            maxlength="8"
            @input="gameForm.pin2 = digitsOnly(($event.target as HTMLInputElement).value, 8)"
          />
        </label>
        <p v-if="gameFormError" class="error-text">{{ gameFormError }}</p>
        <div class="row" style="justify-content: flex-end">
          <button type="button" class="btn btn-ghost" @click="showGameEdit = false">Отмена</button>
          <button class="btn btn-primary" :disabled="!!gameFormError">Сохранить</button>
        </div>
      </form>
    </ModalDialog>
    <ConfirmDialog v-if="confirmClose" title="Закрыть игру?" confirm-text="Закрыть навсегда" @confirm="doClose" @cancel="confirmClose = false">
      <p>Игра будет удалена прямо сейчас: все участники отключатся, PIN перестанет работать. Паки останутся в библиотеке.</p>
    </ConfirmDialog>
    <ConfirmDialog v-if="confirmReset" title="Сбросить игру?" confirm-text="Сбросить" @confirm="doReset" @cancel="confirmReset = false">
      <p>Игра вернётся в лобби, очки обнулятся, сыгранные вопросы снова станут доступны.</p>
      <label class="check"><input v-model="keepPlayers" type="checkbox" /> Оставить игроков</label>
      <p v-if="!keepPlayers" class="error-text">Все игроки будут отключены и должны будут войти заново.</p>
    </ConfirmDialog>
    <ConfirmDialog v-if="kickTarget" title="Исключить игрока?" confirm-text="Исключить" @confirm="doKick" @cancel="kickTarget = null">
      <p>«{{ kickTarget.name }}» будет удалён из игры вместе с очками.</p>
    </ConfirmDialog>
  </GameShell>
</template>

<style scoped>
.page {
  width: 100%;
  max-width: 1400px;
}
.m0 {
  margin: 0;
}
.top {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 420px), 1fr));
  gap: var(--sp-4);
}
.top > .card {
  margin: 0;
}
.created {
  margin: 0;
  padding: var(--sp-3);
  border: 1px solid var(--success);
  border-radius: var(--r-card);
  color: var(--success);
  font-weight: 600;
}
.settings-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: var(--sp-3);
}
@media (max-width: 760px) {
  thead {
    display: none;
  }
}
</style>
