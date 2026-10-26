import { onBeforeUnmount } from 'vue'
import { GameSocket, type SocketOptions } from '@/ws/client'
import { useToastStore } from '@/stores/toast'
import { sounds } from '@/utils/sound'

const ERROR_TEXT: Record<string, string> = {
  forbidden: 'Действие недоступно',
  wrong_phase: 'Сейчас это действие недоступно',
  not_found: 'Не найдено',
  invalid: 'Некорректные данные',
}

/** Creates a socket bound to the calling component's lifetime. Call `connect()` yourself. */
export function useGameSocket(opts: SocketOptions & { sounds?: boolean }) {
  const toast = useToastStore()
  const socket = new GameSocket({
    ...opts,
    onError: (message, code) => toast.error(message || ERROR_TEXT[code] || 'Ошибка'),
  } as SocketOptions)
  if (opts.sounds) {
    socket.onEvent((e) => {
      if (e.kind === 'buzz') sounds.buzz()
      else if (e.kind === 'judged' || e.kind === 'final_judged') (e.correct ? sounds.correct : sounds.wrong)()
      else if (e.kind === 'timeout') sounds.timeout()
      else if (e.kind === 'modifier') sounds.fanfare()
      else if (e.kind === 'cat_given' || e.kind === 'auction_bid') sounds.tick()
      else if (e.kind === 'auction_won') sounds.gavel()
      else if (e.kind === 'final_theme_removed') sounds.swoosh()
    })
  }
  onBeforeUnmount(() => socket.close())
  return socket
}
