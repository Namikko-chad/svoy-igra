<script setup lang="ts">
import { computed } from 'vue'
import type { PlayerView } from '@/types/protocol'
import AvatarImg from './AvatarImg.vue'

const props = withDefaults(defineProps<{ players: PlayerView[]; title: string; tv?: boolean; meId?: string | null }>(), {
  tv: false,
  meId: null,
})
const ranked = computed(() => {
  const sorted = [...props.players].sort((a, b) => b.score - a.score)
  let place = 0
  let prev: number | null = null
  return sorted.map((p, i) => {
    if (p.score !== prev) place = i + 1
    prev = p.score
    return { ...p, place }
  })
})
</script>

<template>
  <section class="standings" :class="{ tv }">
    <h2 class="title">{{ title }}</h2>
    <ol>
      <li v-for="p in ranked" :key="p.id" :class="{ first: p.place === 1, me: p.id === meId }">
        <span class="place display num">{{ p.place }}</span>
        <AvatarImg :url="p.avatarUrl" :name="p.name" :size="tv ? 96 : 64" :ring="p.place === 1 ? 'gold' : null" />
        <span class="name">{{ p.name }}</span>
        <span class="score display num" :class="{ neg: p.score < 0 }">{{ p.score }}</span>
      </li>
    </ol>
  </section>
</template>

<style scoped>
.standings {
  width: min(640px, 100%);
  margin: 0 auto;
}
.title {
  text-align: center;
  font-size: var(--fs-24);
}
ol {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-2);
}
li {
  display: flex;
  align-items: center;
  gap: var(--sp-3);
  padding: var(--sp-3) var(--sp-4);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--r-card);
}
li.first {
  border-color: var(--gold);
  box-shadow: var(--glow-gold);
}
li.me .name {
  font-weight: 600;
}
.place {
  width: 2ch;
  color: var(--text-muted);
  font-weight: 600;
}
.first .place {
  color: var(--gold);
}
.name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.score {
  color: var(--gold);
  font-weight: 600;
  font-size: var(--fs-20);
}
.score.neg {
  color: var(--danger);
}
.tv {
  width: min(1100px, 90vw);
}
.tv .title {
  font-size: clamp(28px, 3vw, 56px);
}
.tv li {
  padding: 16px 28px;
  font-size: clamp(20px, 1.8vw, 36px);
}
.tv .score {
  font-size: clamp(24px, 2.2vw, 44px);
}
</style>
