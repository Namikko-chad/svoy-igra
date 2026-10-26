<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import type { BuzzerState } from '@/types/protocol'
import { secondsLeft } from '@/utils/time'

const props = defineProps<{
  state: BuzzerState
  /** server time the button opens (waiting) */
  opensAt: number | null
  /** current server time */
  now: number
  closedReason?: string
}>()
const emit = defineEmits<{ press: [] }>()

// Pressed locally, waiting for the server to confirm; reset on every state change.
const pressed = ref(false)
watch(
  () => props.state,
  () => (pressed.value = false),
)

const label = computed(() => {
  switch (props.state) {
    case 'open':
      return pressed.value ? 'Отправлено…' : 'Дать ответ'
    case 'answering':
      return 'Вы отвечаете'
    case 'used':
      return 'Вы уже отвечали'
    case 'closed':
      return props.closedReason || 'Закрыто'
    case 'waiting':
      return 'Дать ответ'
    default:
      return ''
  }
})
const countdown = computed(() =>
  props.state === 'waiting' && props.opensAt != null ? secondsLeft(props.opensAt - props.now) : null,
)

function press() {
  if (props.state !== 'open' || pressed.value) return
  pressed.value = true
  if (navigator.vibrate) {
    try {
      navigator.vibrate(30)
    } catch {
      /* ignore */
    }
  }
  emit('press')
}
function onClick(e: MouseEvent) {
  // pointerdown already handled pointer presses; this path is for keyboard / D-pad.
  if (e.detail === 0) press()
}
</script>

<template>
  <button
    class="buzzer"
    :class="[state, { pressed }]"
    :disabled="state !== 'open'"
    :aria-label="label"
    @pointerdown.prevent="press"
    @click="onClick"
  >
    <span class="label display">{{ label }}</span>
    <span v-if="countdown !== null" class="sub num">через {{ countdown }}</span>
  </button>
</template>

<style scoped>
.buzzer {
  --size: clamp(200px, 60vw, 300px);
  width: var(--size);
  height: var(--size);
  border-radius: var(--r-pill);
  border: 3px solid var(--border);
  background: var(--surface);
  color: var(--text);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--sp-2);
  padding: var(--sp-4);
  cursor: default;
  touch-action: manipulation;
  user-select: none;
  -webkit-user-select: none;
  transition:
    background var(--t-hover),
    border-color var(--t-hover),
    box-shadow var(--t-hover),
    transform 80ms ease-out;
}
.label {
  font-weight: 800;
  font-size: clamp(20px, 6vw, 28px);
  line-height: 1.15;
  text-align: center;
}
.sub {
  font-size: var(--fs-16);
  color: var(--text-muted);
  font-family: var(--font-mono);
}
.waiting {
  border-color: var(--danger);
  background: transparent;
  color: var(--text-muted);
  opacity: 0.6;
}
.open {
  background: var(--danger);
  border-color: var(--danger);
  color: #fff;
  cursor: pointer;
  animation: glow 1s ease-in-out infinite;
}
.open:active,
.open.pressed {
  transform: scale(0.96);
}
.answering {
  background: var(--gold);
  border-color: var(--gold);
  color: #2a1d00;
  box-shadow: var(--glow-gold);
  opacity: 1;
}
.used,
.closed {
  background: var(--surface-2);
  border-color: var(--disabled);
  color: var(--disabled);
}
.buzzer:disabled {
  cursor: default;
}
.answering:disabled {
  color: #2a1d00;
}
@keyframes glow {
  0%,
  100% {
    box-shadow: 0 0 24px rgba(255, 77, 94, 0.45);
  }
  50% {
    box-shadow: 0 0 56px rgba(255, 77, 94, 0.85);
  }
}
</style>
