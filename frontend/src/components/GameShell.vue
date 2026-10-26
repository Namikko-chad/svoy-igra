<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import type { GameSocket } from '@/ws/client'
import { CLOSE_GAME_CLOSED, CLOSE_KICKED, CLOSE_REPLACED } from '@/ws/client'
import ConnectionPill from './ConnectionPill.vue'
import ConfirmDialog from './ConfirmDialog.vue'

const props = defineProps<{
  socket: GameSocket
  pin: string
  title: string
  /** what leaving means for this role, shown in the confirm dialog */
  leaveText: string
  /** hide the bar (TV screen draws its own) */
  bare?: boolean
}>()
const emit = defineEmits<{ leave: [] }>()
const router = useRouter()
const confirmLeave = ref(false)
const fatal = props.socket.fatalCode
const connected = props.socket.connected
</script>

<template>
  <div class="shell">
    <header v-if="!bare" class="topbar">
      <span class="title">{{ title }}</span>
      <span class="chip mono" title="PIN игры">PIN {{ pin }}</span>
      <slot name="bar" />
      <span class="spacer" />
      <ConnectionPill :connected="connected" />
      <slot name="menu" />
      <button class="btn btn-ghost btn-sm" @click="confirmLeave = true">Выйти</button>
    </header>

    <div v-if="fatal === CLOSE_GAME_CLOSED" class="center-screen">
      <div class="card col notice">
        <h2>Игра закрыта</h2>
        <p class="muted">Администратор закрыл игру, или она долго простаивала и была удалена.</p>
        <button class="btn btn-primary btn-block" @click="router.push('/')">На главную</button>
      </div>
    </div>
    <div v-else-if="fatal === CLOSE_KICKED" class="center-screen">
      <div class="card col notice">
        <h2>Вас исключили из игры</h2>
        <p class="muted">Ведущий или администратор удалил вас из списка игроков.</p>
        <button class="btn btn-primary btn-block" @click="router.push(`/g/${pin}`)">Войти снова</button>
      </div>
    </div>
    <div v-else-if="fatal === CLOSE_REPLACED" class="center-screen">
      <div class="card col notice">
        <h2>Открыто в другом месте</h2>
        <p class="muted">Эта роль подключилась с другой вкладки или устройства. Здесь соединение закрыто.</p>
        <button class="btn btn-primary btn-block" @click="socket.connect()">Продолжить здесь</button>
      </div>
    </div>
    <slot v-else />

    <ConfirmDialog v-if="confirmLeave" title="Выйти из игры?" confirm-text="Выйти" @confirm="emit('leave')" @cancel="confirmLeave = false">
      <p>{{ leaveText }}</p>
    </ConfirmDialog>
  </div>
</template>

<style scoped>
.shell {
  min-height: 100dvh;
  display: flex;
  flex-direction: column;
}
.notice {
  width: min(420px, 100%);
}
</style>
