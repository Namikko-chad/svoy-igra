<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { initials } from '@/utils/avatar'

/** DESIGN_MANIFEST «Avatar»: a circle with the picture, or initials on surface-2. */
const props = withDefaults(
  defineProps<{ url?: string | null; name?: string | null; size?: number; ring?: 'gold' | 'accent' | null }>(),
  { url: null, name: '', size: 40, ring: null },
)
const failed = ref(false)
watch(
  () => props.url,
  () => (failed.value = false),
)
const text = computed(() => initials(props.name))
</script>

<template>
  <span
    class="avatar"
    :class="ring ? `ring-${ring}` : ''"
    :style="{ '--s': `${size}px` }"
    :title="name || undefined"
    aria-hidden="true"
  >
    <img v-if="url && !failed" :src="url" alt="" loading="lazy" decoding="async" @error="failed = true" />
    <span v-else class="ini display">{{ text }}</span>
  </span>
</template>

<style scoped>
.avatar {
  --s: 40px;
  width: var(--s);
  height: var(--s);
  flex: none;
  border-radius: 999px;
  overflow: hidden;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: var(--surface-2);
  border: 1px solid var(--border);
  box-sizing: border-box;
}
.avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}
.ini {
  font-weight: 600;
  font-size: calc(var(--s) * 0.38);
  line-height: 1;
  color: var(--text);
  white-space: nowrap;
}
.ring-gold {
  border: 2px solid var(--gold);
  box-shadow: var(--glow-gold);
}
.ring-accent {
  border: 2px solid var(--accent);
  box-shadow: var(--glow-accent);
}
</style>
