import { onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import type { Role } from '@/types/protocol'
import { session } from '@/stores/session'
import { useToastStore } from '@/stores/toast'
import { useGameSocket } from './useGameSocket'
import { CLOSE_GAME_CLOSED, CLOSE_INVALID_TOKEN, CLOSE_KICKED } from '@/ws/client'

/**
 * A game-scoped role page: reads the stored token for (pin, role), connects, and maps
 * terminal close codes — 4001 forgets the token and returns to the role step,
 * 4004 forgets every token of the game, 4003 forgets the token (the page shows why).
 * With no token the page goes back to `/g/:pin`.
 */
export function useRoleSocket(pin: string, role: Role, opts: { sounds?: boolean } = {}) {
  const router = useRouter()
  const toast = useToastStore()
  const stored = session.get(pin, role)
  const token = stored?.token ?? ''
  if (!token) void router.replace(`/g/${pin}`)

  const socket = useGameSocket({ token, sounds: opts.sounds })
  onMounted(() => {
    if (token) socket.connect()
  })

  watch(socket.fatalCode, (code) => {
    if (code === CLOSE_INVALID_TOKEN) {
      session.forget(pin, role)
      toast.error('Сессия недействительна — войдите заново')
      void router.replace(`/g/${pin}`)
    } else if (code === CLOSE_GAME_CLOSED) {
      session.forgetGame(pin)
    } else if (code === CLOSE_KICKED) {
      session.forget(pin, role)
    }
  })

  /** «Выйти»: send `leave`, forget the token, go back to the role step. */
  function leave() {
    socket.leave()
    session.forget(pin, role)
    void router.push(`/g/${pin}`)
  }

  return { socket, token, stored, leave }
}
