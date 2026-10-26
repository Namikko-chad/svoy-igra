<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { authApi, gamesApi } from '@/api'
import { ApiError, errorMessage } from '@/api/http'
import { session } from '@/stores/session'
import { LAST_NAME_KEY, storageGet, storageSet } from '@/utils/storage'
import { androidIntentUrl, digitsOnly, isAdminPin, isAndroid } from '@/utils/pin'
import { ROLE_LABEL, rolePath } from '@/utils/roles'
import { PHASE_LABEL } from '@/utils/phase'
import { unlockAudio } from '@/utils/sound'
import type { GameInfo, Role } from '@/types/protocol'

const props = defineProps<{ pin: string }>()
const router = useRouter()

const game = ref<GameInfo | null>(null)
const notFound = ref(false)
const loadError = ref('')
const resumable = ref<{ role: Role; label: string }[]>([])

onMounted(async () => {
  try {
    game.value = await gamesApi.get(props.pin)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) {
      notFound.value = true
      session.forgetGame(props.pin)
    } else loadError.value = errorMessage(e)
    return
  }
  // Offer «Продолжить как …» for every stored token the server still accepts.
  for (const { role, session: s } of session.all(props.pin)) {
    try {
      const me = await authApi.me(s.token)
      const label = role === 'player' ? me.name || s.name || 'игрок' : ROLE_LABEL[role].toLowerCase()
      resumable.value.push({ role, label })
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) session.forget(props.pin, role)
    }
  }
})

const choice = ref<Role | null>(null)
const name = ref(storageGet(LAST_NAME_KEY) ?? '')
const adminPin = ref('')
const busy = ref(false)
const error = ref('')

function pick(role: Role) {
  choice.value = role
  error.value = ''
  if (role === 'host' || role === 'screen') void join()
}

async function join() {
  const role = choice.value
  if (!role || busy.value) return
  const body: { role: Role; name?: string; adminPin?: string } = { role }
  if (role === 'player') {
    const n = name.value.trim()
    if (!n) return
    if (n.length > 32) {
      error.value = 'Имя должно быть не длиннее 32 символов'
      return
    }
    body.name = n
  }
  if (role === 'admin') {
    if (!isAdminPin(adminPin.value)) return
    body.adminPin = adminPin.value
  }
  unlockAudio()
  busy.value = true
  error.value = ''
  try {
    const res = await gamesApi.join(props.pin, body)
    session.set(props.pin, res.role, { token: res.token, name: res.name, playerId: res.playerId })
    if (res.name) storageSet(LAST_NAME_KEY, res.name)
    await router.push(rolePath(props.pin, res.role))
  } catch (e) {
    error.value = errorMessage(e)
    if (e instanceof ApiError && e.code === 'host_taken' && game.value) game.value.hostTaken = true
  } finally {
    busy.value = false
  }
}

function resume(role: Role) {
  unlockAudio()
  void router.push(rolePath(props.pin, role))
}

const android = isAndroid()
const intentUrl = () => androidIntentUrl(location.origin, props.pin, game.value?.link ?? location.href)
</script>

<template>
  <div class="center-screen stage">
    <main class="join">
      <RouterLink to="/" class="small">← Главная</RouterLink>

      <div v-if="notFound" class="card col">
        <h1 class="m0">Игра не найдена</h1>
        <p class="muted m0">Игры с PIN <b class="mono">{{ pin }}</b> нет — проверьте код. Игры без участников удаляются через час.</p>
        <RouterLink to="/" class="btn btn-primary btn-block">На главную</RouterLink>
      </div>
      <div v-else-if="loadError" class="card col">
        <p class="error-text m0">{{ loadError }}</p>
        <button class="btn" @click="$router.go(0)">Повторить</button>
      </div>
      <div v-else-if="!game" class="empty">Загрузка…</div>

      <template v-else>
        <header class="card col head">
          <div class="muted small">Игра <span class="mono">{{ game.pin ?? pin }}</span></div>
          <h1 class="m0">{{ game.title || 'Своя игра' }}</h1>
          <div class="row small muted">
            <span class="chip">{{ PHASE_LABEL[game.phase] }}</span>
            <span class="chip">📦 {{ game.pack?.title ?? 'пак не выбран' }}</span>
            <span class="chip">игроков: {{ game.players }}</span>
          </div>
          <a v-if="android" :href="intentUrl()" class="btn btn-sm">Открыть в приложении</a>
        </header>

        <section v-if="resumable.length" class="card col">
          <button v-for="r in resumable" :key="r.role" class="btn btn-primary btn-lg btn-block" @click="resume(r.role)">
            Продолжить как {{ r.label }}
          </button>
        </section>

        <section class="card col">
          <h2 class="m0">Кем вы будете?</h2>

          <div class="roles">
            <button class="role" :class="{ active: choice === 'player' }" @click="pick('player')">
              <span class="ico">🙋</span><b>Игрок</b><span class="muted xs">отвечает на вопросы</span>
            </button>
            <button class="role" :disabled="game.hostTaken" :class="{ active: choice === 'host' }" @click="pick('host')">
              <span class="ico">🎤</span><b>Ведущий</b>
              <span class="muted xs">{{ game.hostTaken ? 'уже занят' : 'ведёт игру' }}</span>
            </button>
            <button class="role" :class="{ active: choice === 'screen' }" @click="pick('screen')">
              <span class="ico">📺</span><b>Экран</b><span class="muted xs">для телевизора</span>
            </button>
            <button class="role" :class="{ active: choice === 'admin' }" @click="pick('admin')">
              <span class="ico">🛠</span><b>Администратор</b><span class="muted xs">по PIN-коду</span>
            </button>
          </div>

          <form v-if="choice === 'player'" class="col" @submit.prevent="join">
            <label class="field">
              Ваше имя
              <input v-model="name" class="input" maxlength="32" autocomplete="nickname" enterkeyhint="go" autofocus />
            </label>
            <button class="btn btn-primary btn-lg btn-block" :disabled="busy || !name.trim()">Играть</button>
          </form>
          <form v-else-if="choice === 'admin'" class="col" @submit.prevent="join">
            <label class="field">
              PIN администратора
              <input
                :value="adminPin"
                class="input mono"
                type="password"
                inputmode="numeric"
                autocomplete="current-password"
                maxlength="8"
                autofocus
                @input="adminPin = digitsOnly(($event.target as HTMLInputElement).value, 8)"
              />
            </label>
            <button class="btn btn-primary btn-lg btn-block" :disabled="busy || !isAdminPin(adminPin)">Войти</button>
          </form>
          <p v-if="game.hostTaken" class="muted xs m0">
            Ведущий в игре уже есть. Место освободится, если он выйдет или будет офлайн дольше 30 секунд.
          </p>
          <p v-if="error" class="error-text m0">{{ error }}</p>
        </section>
      </template>
    </main>
  </div>
</template>

<style scoped>
.join {
  width: min(480px, 100%);
  display: flex;
  flex-direction: column;
  gap: var(--sp-4);
}
.m0 {
  margin: 0;
}
.head h1 {
  font-size: var(--fs-24);
}
.roles {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--sp-2);
}
.role {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
  padding: var(--sp-3) var(--sp-2);
  border-radius: var(--r-card);
  border: 1px solid var(--border);
  background: var(--surface-2);
  color: var(--text);
  font: inherit;
  cursor: pointer;
  transition:
    border-color var(--t-hover),
    box-shadow var(--t-hover);
}
.role:hover:not(:disabled),
.role.active {
  border-color: var(--accent);
  box-shadow: var(--glow-accent);
}
.role:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
.ico {
  font-size: 28px;
}
</style>
