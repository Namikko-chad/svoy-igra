<script setup lang="ts">
import type { PlayerView } from '@/types/protocol'
import AvatarImg from './AvatarImg.vue'

withDefaults(
  defineProps<{
    players: PlayerView[]
    chooserId?: string | null
    answeringId?: string | null
    meId?: string | null
    attempted?: string[]
    tv?: boolean
  }>(),
  { chooserId: null, answeringId: null, meId: null, attempted: () => [], tv: false },
)
</script>

<template>
  <ul class="scoreboard" :class="{ tv }">
    <li
      v-for="p in players"
      :key="p.id"
      class="pchip"
      :class="{
        chooser: p.id === chooserId,
        answering: p.id === answeringId,
        me: p.id === meId,
        attempted: attempted.includes(p.id),
      }"
    >
      <AvatarImg :url="p.avatarUrl" :name="p.name" :size="tv ? 56 : 40" />
      <span class="dot" :class="{ on: p.connected }" :title="p.connected ? 'в сети' : 'не в сети'" />
      <span class="name">{{ p.name }}<span v-if="p.id === meId" class="muted"> (вы)</span></span>
      <span class="score display num" :class="{ neg: p.score < 0 }">{{ p.score }}</span>
    </li>
    <li v-if="!players.length" class="muted small">Игроков пока нет</li>
  </ul>
</template>

<style scoped>
.scoreboard {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: var(--sp-2);
}
.pchip {
  display: inline-flex;
  align-items: center;
  gap: var(--sp-2);
  padding: 3px var(--sp-3) 3px 3px;
  border-radius: var(--r-pill);
  background: var(--surface);
  border: 2px solid var(--border);
  min-height: 36px;
  max-width: 100%;
  transition:
    border-color var(--t-hover),
    box-shadow var(--t-hover);
}
.pchip.chooser {
  border-color: var(--gold);
  box-shadow: var(--glow-gold);
}
.pchip.answering {
  border-color: var(--accent);
  box-shadow: var(--glow-accent);
}
.pchip.attempted {
  opacity: 0.6;
}
.pchip.me .name {
  font-weight: 600;
}
.name {
  font-size: var(--fs-14);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.score {
  color: var(--gold);
  font-weight: 600;
  font-size: var(--fs-16);
}
.score.neg {
  color: var(--danger);
}
.tv {
  gap: 16px;
  justify-content: center;
}
.tv .pchip {
  padding: 4px 20px 4px 4px;
  min-height: 56px;
  border-width: 3px;
}
.tv .name {
  font-size: clamp(16px, 1.4vw, 28px);
}
.tv .score {
  font-size: clamp(20px, 1.8vw, 36px);
}
.tv .dot {
  width: 14px;
  height: 14px;
}
</style>
