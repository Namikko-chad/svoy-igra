<script setup lang="ts">
import type { Modifier } from '@/types/protocol'
import { MODIFIER_HINT, MODIFIER_ICON, MODIFIER_LABEL } from '@/utils/special'

defineProps<{ modifier: Modifier; stake: number; tv?: boolean }>()
const emit = defineEmits<{ close: [] }>()
</script>

<template>
  <Teleport to="body">
    <button class="splash" :class="{ tv }" aria-live="assertive" @click="emit('close')">
      <span class="icon">{{ MODIFIER_ICON[modifier] }}</span>
      <span class="label display">{{ MODIFIER_LABEL[modifier] }}</span>
      <span v-if="modifier !== 'auction'" class="stake display num">{{ stake }}</span>
      <span class="hint">{{ MODIFIER_HINT[modifier] }}</span>
    </button>
  </Teleport>
</template>

<style scoped>
.splash {
  position: fixed;
  inset: 0;
  z-index: 800;
  border: none;
  background: radial-gradient(ellipse at center, rgba(26, 42, 122, 0.97) 0%, rgba(7, 11, 31, 0.97) 70%);
  color: var(--text);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--sp-4);
  padding: var(--sp-6);
  cursor: pointer;
  animation: pop 400ms ease-out;
}
.icon {
  font-size: clamp(56px, 16vw, 120px);
  line-height: 1;
}
.label {
  font-size: clamp(28px, 9vw, 56px);
  font-weight: 800;
  color: var(--gold);
  text-shadow: var(--glow-gold);
  text-align: center;
}
.stake {
  font-size: clamp(24px, 7vw, 48px);
  font-weight: 800;
}
.hint {
  color: var(--text-muted);
  font-size: var(--fs-16);
  text-align: center;
  max-width: 40ch;
}
.tv .icon {
  font-size: 12vw;
}
.tv .label {
  font-size: 7vw;
}
.tv .stake {
  font-size: 5vw;
}
.tv .hint {
  font-size: 2vw;
}
@keyframes pop {
  from {
    opacity: 0;
    transform: scale(0.6);
  }
}
</style>
