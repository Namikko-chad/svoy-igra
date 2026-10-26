import { onBeforeUnmount, ref, watch, type Ref } from 'vue'
import type { GameView, Modifier } from '@/types/protocol'

/**
 * Shows the special-question splash for ~2.6 s whenever a question with a modifier opens
 * (driven by state, so a reconnect mid-question still shows the badge in the header).
 */
export function useModifierSplash(state: Ref<GameView | null>, ms = 2600) {
  const splash = ref<{ modifier: Modifier; stake: number } | null>(null)
  let timer: ReturnType<typeof setTimeout> | null = null
  let lastId: number | null = null
  watch(
    () => [state.value?.question?.id ?? null, state.value?.question?.modifier ?? null] as const,
    ([id, modifier]) => {
      if (id == null || id === lastId) return
      lastId = id
      if (!modifier) return
      splash.value = { modifier, stake: state.value?.question?.stake ?? 0 }
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => (splash.value = null), ms)
    },
    { immediate: true },
  )
  onBeforeUnmount(() => timer && clearTimeout(timer))
  return splash
}
