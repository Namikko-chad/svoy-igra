import { onBeforeUnmount, ref } from 'vue'

/** A ticking Date.now() ref (default every 100 ms) for countdowns. */
export function useNow(intervalMs = 100) {
  const now = ref(Date.now())
  const id = setInterval(() => (now.value = Date.now()), intervalMs)
  onBeforeUnmount(() => clearInterval(id))
  return now
}
