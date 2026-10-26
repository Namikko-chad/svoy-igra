<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { secondsLeft } from '@/utils/time'

const props = defineProps<{
  /** server-time deadline in ms */
  deadline: number
  /** current server time in ms */
  now: number
  /** full duration in ms; when unknown the remaining time at first sight is used */
  total?: number | null
  label?: string
}>()

const seenTotal = ref(0)
watch(
  () => props.deadline,
  () => {
    seenTotal.value = Math.max(1, props.deadline - props.now)
  },
  { immediate: true },
)
const remaining = computed(() => Math.max(0, props.deadline - props.now))
const fraction = computed(() => {
  const total = props.total && props.total > 0 ? props.total : seenTotal.value
  return Math.min(1, remaining.value / total)
})
const urgent = computed(() => remaining.value <= 3000)
</script>

<template>
  <div class="timer" :class="{ urgent }" role="timer">
    <div class="bar"><i :style="{ width: `${fraction * 100}%` }" /></div>
    <div class="meta">
      <span v-if="label" class="muted small">{{ label }}</span>
      <span class="count num display">{{ secondsLeft(remaining) }}</span>
    </div>
  </div>
</template>

<style scoped>
.timer {
  width: 100%;
}
.bar {
  height: 6px;
  border-radius: var(--r-pill);
  background: var(--surface-2);
  overflow: hidden;
}
.bar i {
  display: block;
  height: 100%;
  background: var(--accent);
  border-radius: inherit;
  transition: width 100ms linear;
}
.urgent .bar i {
  background: var(--warning);
}
.meta {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  margin-top: var(--sp-1);
  gap: var(--sp-2);
}
.count {
  margin-left: auto;
  font-size: var(--fs-20);
  font-weight: 600;
  color: var(--accent);
}
.urgent .count {
  color: var(--warning);
}
</style>
