<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { gamesApi } from '@/api'
import { errorMessage } from '@/api/http'
import { session } from '@/stores/session'
import { digitsOnly, isAdminPin, isGamePin } from '@/utils/pin'
import { storedPins } from '@/utils/storage'
import { unlockAudio } from '@/utils/sound'

const router = useRouter()

// Join an existing game
const joinPin = ref('')
function join() {
  if (!isGamePin(joinPin.value)) return
  unlockAudio()
  void router.push(`/g/${joinPin.value}`)
}

// Create a new game
const creating = ref(false)
const adminPin = ref('')
const adminPin2 = ref('')
const title = ref('')
const busy = ref(false)
const error = ref('')
const createError = computed(() => {
  if (adminPin.value && !isAdminPin(adminPin.value)) return 'PIN администратора — от 4 до 8 цифр'
  if (adminPin2.value && adminPin2.value !== adminPin.value) return 'PIN-коды не совпадают'
  return ''
})
const canCreate = computed(
  () => isAdminPin(adminPin.value) && adminPin.value === adminPin2.value && title.value.trim().length <= 60,
)
async function create() {
  if (!canCreate.value || busy.value) return
  busy.value = true
  error.value = ''
  try {
    const res = await gamesApi.create(adminPin.value, title.value.trim() || undefined)
    const pin = res.game.pin
    if (!pin) throw new Error('Сервер не вернул PIN игры')
    session.set(pin, 'admin', { token: res.token })
    await router.push({ path: `/g/${pin}/admin`, query: { created: '1' } })
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    busy.value = false
  }
}

const recent = storedPins().slice(0, 5)
</script>

<template>
  <div class="center-screen stage">
    <main class="landing">
      <h1 class="logo display">Своя&nbsp;<span class="gold">игра</span></h1>

      <form class="card col" @submit.prevent="join">
        <h2 class="m0">Войти в игру</h2>
        <label class="field">
          PIN игры
          <input
            :value="joinPin"
            class="input mono pin-input"
            inputmode="numeric"
            autocomplete="off"
            placeholder="000000"
            maxlength="6"
            enterkeyhint="go"
            autofocus
            @input="joinPin = digitsOnly(($event.target as HTMLInputElement).value, 6)"
          />
        </label>
        <button class="btn btn-primary btn-lg btn-block" :disabled="!isGamePin(joinPin)">Продолжить</button>
        <div v-if="recent.length" class="row small">
          <span class="muted">Ваши игры:</span>
          <RouterLink v-for="p in recent" :key="p" :to="`/g/${p}`" class="chip mono">{{ p }}</RouterLink>
        </div>
      </form>

      <button v-if="!creating" class="btn btn-ghost btn-block" @click="creating = true">Создать игру</button>
      <form v-else class="card col" @submit.prevent="create">
        <h2 class="m0">Новая игра</h2>
        <label class="field">
          Название (необязательно)
          <input v-model="title" class="input" maxlength="60" placeholder="Например, Пятничный квиз" />
        </label>
        <label class="field">
          PIN администратора (4–8 цифр)
          <input
            :value="adminPin"
            class="input mono"
            type="password"
            inputmode="numeric"
            autocomplete="new-password"
            maxlength="8"
            @input="adminPin = digitsOnly(($event.target as HTMLInputElement).value, 8)"
          />
        </label>
        <label class="field">
          Повторите PIN
          <input
            :value="adminPin2"
            class="input mono"
            type="password"
            inputmode="numeric"
            autocomplete="new-password"
            maxlength="8"
            @input="adminPin2 = digitsOnly(($event.target as HTMLInputElement).value, 8)"
          />
        </label>
        <p class="muted xs m0">С этим PIN-кодом можно войти администратором игры с любого устройства.</p>
        <p v-if="createError || error" class="error-text m0">{{ createError || error }}</p>
        <div class="row">
          <button type="button" class="btn btn-ghost" @click="creating = false">Отмена</button>
          <button class="btn btn-primary grow" :disabled="!canCreate || busy">Создать</button>
        </div>
      </form>
    </main>
  </div>
</template>

<style scoped>
.landing {
  width: min(400px, 100%);
  display: flex;
  flex-direction: column;
  gap: var(--sp-4);
}
.logo {
  text-align: center;
  font-size: clamp(32px, 10vw, 48px);
  font-weight: 800;
  margin: 0 0 var(--sp-2);
  text-shadow: var(--glow-gold);
}
.m0 {
  margin: 0;
}
.pin-input {
  font-size: var(--fs-32);
  letter-spacing: 0.3em;
  text-align: center;
}
.chip {
  text-decoration: none;
}
</style>
