<script setup lang="ts">
import type { Block } from '@/types/protocol'
import MarkdownView from './MarkdownView.vue'
import MediaBlock, { type PlaybackMode } from './MediaBlock.vue'

withDefaults(
  defineProps<{ blocks: Block[]; mode: PlaybackMode; retry?: number; size?: 'sm' | 'md' | 'lg'; active?: boolean }>(),
  { retry: 0, active: true, size: 'md' },
)
const emit = defineEmits<{ blocked: [] }>()
</script>

<template>
  <div class="blocks" :class="size">
    <template v-for="(b, i) in blocks" :key="i + ':' + (b.type === 'text' ? 't' : b.url)">
      <MarkdownView v-if="b.type === 'text'" class="text" :source="b.markdown" />
      <MediaBlock v-else :kind="b.type" :url="b.url" :alt="b.alt" :mode="mode" :retry="retry" :active="active" @blocked="emit('blocked')" />
    </template>
  </div>
</template>

<style scoped>
.blocks {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--sp-4);
  text-align: center;
  width: 100%;
  overflow-wrap: anywhere;
}
.text {
  max-width: 60ch;
}
.sm .text {
  font-size: var(--fs-16);
}
.md .text {
  font-size: clamp(20px, 3.2vw, 32px);
  line-height: 1.3;
}
.lg .text {
  font-size: clamp(28px, 3vw, 56px);
  line-height: 1.25;
  max-width: 40ch;
}
</style>
