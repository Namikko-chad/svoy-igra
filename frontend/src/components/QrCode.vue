<script setup lang="ts">
import { computed } from 'vue'
import qrcode from 'qrcode-generator'

const props = defineProps<{ text: string }>()

// One SVG path of dark modules; colours come from the design tokens.
const qr = computed(() => {
  const q = qrcode(0, 'M')
  q.addData(props.text)
  q.make()
  const n = q.getModuleCount()
  let d = ''
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (q.isDark(r, c)) d += `M${c} ${r}h1v1h-1z`
  return { n, d }
})
</script>

<template>
  <svg class="qr" :viewBox="`-2 -2 ${qr.n + 4} ${qr.n + 4}`" role="img" :aria-label="text" shape-rendering="crispEdges">
    <rect x="-2" y="-2" :width="qr.n + 4" :height="qr.n + 4" fill="#F1F3FF" rx="1" />
    <path :d="qr.d" fill="#070B1F" />
  </svg>
</template>

<style scoped>
.qr {
  display: block;
  width: 100%;
  height: auto;
  border-radius: var(--r-card);
}
</style>
