<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'

export type PlaybackMode = 'player' | 'host' | 'screen'

const props = defineProps<{
  kind: 'image' | 'video' | 'audio'
  url: string
  alt: string
  mode: PlaybackMode
  /** screen: bump to retry autoplay after the user enabled sound */
  retry?: number
  /** false pauses playback (screen: question media stops when the answer is revealed) */
  active?: boolean
}>()
const emit = defineEmits<{ blocked: [] }>()

const media = ref<HTMLMediaElement | null>(null)
const playing = ref(false)

function autoplay() {
  const el = media.value
  if (!el || props.mode !== 'screen' || props.active === false) return
  el.muted = false
  el.play().catch((e: unknown) => {
    if ((e as Error)?.name === 'NotAllowedError') emit('blocked')
  })
}
onMounted(autoplay)
watch(
  () => props.retry,
  () => {
    if (media.value?.paused) autoplay()
  },
)

watch(
  () => props.active,
  (on) => {
    if (on === false) media.value?.pause()
  },
)

function togglePlayerAudio() {
  const el = media.value
  if (!el) return
  if (el.paused) void el.play().catch(() => {})
  else el.pause()
}
</script>

<template>
  <figure class="media" :class="[kind, mode]">
    <img v-if="kind === 'image'" :src="url" :alt="alt" loading="eager" />

    <video
      v-else-if="kind === 'video' && mode === 'player'"
      ref="media"
      :src="url"
      muted
      autoplay
      playsinline
      controls
      preload="auto"
    />
    <video v-else-if="kind === 'video' && mode === 'host'" ref="media" :src="url" controls playsinline preload="metadata" />
    <video v-else-if="kind === 'video'" ref="media" :src="url" playsinline preload="auto" />

    <template v-else-if="kind === 'audio' && mode === 'player'">
      <audio ref="media" :src="url" preload="none" @play="playing = true" @pause="playing = false" @ended="playing = false" />
      <div class="audio-chip">
        <span>🔊 звучит на экране</span>
        <button class="btn btn-sm" type="button" @click="togglePlayerAudio">
          {{ playing ? '⏸ Пауза' : '▶ Слушать' }}
        </button>
      </div>
    </template>
    <audio v-else-if="kind === 'audio' && mode === 'host'" ref="media" :src="url" controls preload="metadata" />
    <template v-else-if="kind === 'audio'">
      <audio ref="media" :src="url" preload="auto" @play="playing = true" @pause="playing = false" @ended="playing = false" />
      <div class="audio-screen" :class="{ playing }" aria-hidden="true">🔊</div>
    </template>

    <figcaption v-if="alt && kind !== 'image'" class="muted small">{{ alt }}</figcaption>
  </figure>
</template>

<style scoped>
.media {
  margin: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--sp-2);
  max-width: 100%;
}
img,
video {
  display: block;
  max-width: 100%;
  max-height: 70vh;
  max-height: 70dvh;
  border-radius: var(--r-card);
  object-fit: contain;
  background: #000;
}
img {
  background: transparent;
}
audio {
  max-width: 100%;
}
.audio-chip {
  display: inline-flex;
  align-items: center;
  gap: var(--sp-3);
  padding: var(--sp-2) var(--sp-3);
  border-radius: var(--r-pill);
  border: 1px solid var(--border);
  background: var(--surface);
  font-size: var(--fs-14);
}
.audio-screen {
  font-size: clamp(48px, 8vw, 160px);
  line-height: 1;
  opacity: 0.6;
}
.audio-screen.playing {
  opacity: 1;
  animation: pulse 1.2s ease-in-out infinite;
}
@keyframes pulse {
  50% {
    transform: scale(1.08);
  }
}
</style>
