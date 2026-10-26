<script setup lang="ts">
import { ref, watch } from 'vue'
import type { PlayerView } from '@/types/protocol'
import { formatDateTime } from '@/utils/time'
import { formatMs, latencyLevel } from '@/utils/latency'
import AvatarImg from '@/components/AvatarImg.vue'

const props = defineProps<{ player: PlayerView }>()
const emit = defineEmits<{
  setScore: [score: number]
  adjust: [delta: number]
  setOffset: [offsetMs: number]
  kick: []
  clearAvatar: []
}>()

const OFFSET_MIN = -5000
const OFFSET_MAX = 10000

const scoreInput = ref(props.player.score)
const scoreFocused = ref(false)
watch(
  () => props.player.score,
  (s) => {
    if (!scoreFocused.value) scoreInput.value = s
  },
)
function commitScore() {
  scoreFocused.value = false
  const v = Math.round(Number(scoreInput.value))
  if (Number.isFinite(v) && v !== props.player.score) emit('setScore', v)
  else scoreInput.value = props.player.score
}

const custom = ref(100)
function adjustCustom(sign: 1 | -1) {
  const v = Math.round(Math.abs(Number(custom.value)))
  if (v) emit('adjust', sign * v)
}

const offset = ref(props.player.admin?.buzzOffsetMs ?? 0)
const offsetDirty = ref(false)
watch(
  () => props.player.admin?.buzzOffsetMs,
  (v) => {
    if (!offsetDirty.value) offset.value = v ?? 0
  },
)
function commitOffset() {
  offsetDirty.value = false
  const v = Math.min(OFFSET_MAX, Math.max(OFFSET_MIN, Math.round(Number(offset.value) || 0)))
  offset.value = v
  if (v !== props.player.admin?.buzzOffsetMs) emit('setOffset', v)
}
</script>

<template>
  <tr>
    <td data-label="Игрок">
      <div class="who">
        <AvatarImg :url="player.avatarUrl" :name="player.name" :size="40" />
        <span class="dot" :class="{ on: player.connected }" :title="player.connected ? 'в сети' : 'не в сети'" />
        <b class="name">{{ player.name }}</b>
      </div>
      <div class="mono xs muted">{{ player.id }}</div>
    </td>

    <td data-label="Очки">
      <input
        v-model.number="scoreInput"
        class="input num score"
        :class="{ neg: player.score < 0 }"
        type="number"
        step="100"
        aria-label="Очки"
        @focus="scoreFocused = true"
        @blur="commitScore"
        @keydown.enter="($event.target as HTMLInputElement).blur()"
      />
      <div class="row quick">
        <button class="btn btn-sm" @click="emit('adjust', -100)">−100</button>
        <button class="btn btn-sm" @click="emit('adjust', 100)">+100</button>
      </div>
      <div class="row quick">
        <button class="btn btn-sm btn-icon" aria-label="Вычесть" @click="adjustCustom(-1)">−</button>
        <input v-model.number="custom" class="input num custom" type="number" min="1" aria-label="Своё значение" />
        <button class="btn btn-sm btn-icon" aria-label="Прибавить" @click="adjustCustom(1)">+</button>
      </div>
    </td>

    <td data-label="Устройство">
      <template v-if="player.admin">
        <div>
          {{ player.admin.device.platform || '—' }} · {{ player.admin.device.model || '—' }}
        </div>
        <div class="muted small">{{ player.admin.device.os || '—' }} · v{{ player.admin.device.appVersion || '?' }}</div>
        <div class="mono xs muted">{{ player.admin.device.screen || '—' }} · {{ player.admin.device.ip || '—' }}</div>
      </template>
      <span v-else class="muted">—</span>
    </td>

    <td data-label="Задержка (RTT)">
      <template v-if="player.admin">
        <div class="mono small">
          <span :class="'lvl-' + latencyLevel(player.admin.rttMs)">{{ formatMs(player.admin.rttMs) }}</span>
          <span class="muted"> посл.</span>
        </div>
        <div class="mono small">
          <span :class="'lvl-' + latencyLevel(player.admin.rttAvgMs)">{{ formatMs(player.admin.rttAvgMs) }}</span>
          <span class="muted"> сред.</span>
        </div>
        <div class="mono small muted">± {{ formatMs(player.admin.jitterMs) }} джиттер</div>
        <div class="mono xs muted" title="Последняя активность">{{ formatDateTime(player.admin.lastSeenAt) }}</div>
      </template>
    </td>

    <td data-label="Смещение кнопки">
      <template v-if="player.admin">
        <div class="row nowrap">
          <input
            v-model.number="offset"
            class="input num offset"
            type="number"
            :min="OFFSET_MIN"
            :max="OFFSET_MAX"
            step="50"
            aria-label="Смещение, мс"
            @input="offsetDirty = true"
            @change="commitOffset"
          />
          <span class="muted small">мс</span>
        </div>
        <input
          v-model.number="offset"
          class="slider"
          type="range"
          :min="OFFSET_MIN"
          :max="OFFSET_MAX"
          step="50"
          aria-label="Смещение кнопки"
          @input="offsetDirty = true"
          @change="commitOffset"
        />
        <div class="mono xs muted">эффективно: {{ player.admin.effectiveOffsetMs }} мс</div>
      </template>
    </td>

    <td data-label="Статистика">
      <template v-if="player.admin">
        <div class="small">
          <span class="lvl-success">✓ {{ player.admin.stats.correct }}</span>
          <span class="lvl-danger"> ✗ {{ player.admin.stats.wrong }}</span>
          <span class="muted"> · нажатий {{ player.admin.stats.buzzes }}</span>
        </div>
        <div class="mono xs muted">
          реакция: ср. {{ formatMs(player.admin.stats.avgReactionMs) }}, лучш. {{ formatMs(player.admin.stats.bestReactionMs) }}
        </div>
      </template>
    </td>

    <td data-label="">
      <div class="col acts">
        <button v-if="player.avatarUrl" class="btn btn-ghost btn-sm" @click="emit('clearAvatar')">Удалить аватар</button>
        <button class="btn btn-ghost btn-sm danger" @click="emit('kick')">Исключить</button>
      </div>
    </td>
  </tr>
</template>

<style scoped>
.who {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
}
.acts {
  gap: var(--sp-1);
  align-items: flex-start;
}
.name {
  word-break: break-word;
}
.score {
  width: 120px;
  font-family: var(--font-display);
  color: var(--gold);
  font-weight: 600;
}
.score.neg {
  color: var(--danger);
}
.quick {
  margin-top: var(--sp-1);
  flex-wrap: nowrap;
  gap: var(--sp-1);
}
.custom {
  width: 76px;
  min-height: 32px;
  padding: 2px 6px;
  font-size: var(--fs-14);
}
.offset {
  width: 100px;
}
.nowrap {
  flex-wrap: nowrap;
}
.slider {
  width: 160px;
  margin-top: var(--sp-1);
}
@media (max-width: 760px) {
  tr {
    display: block;
    border-bottom: 1px solid var(--border);
    padding: var(--sp-2) 0;
  }
  td {
    display: grid;
    grid-template-columns: 112px minmax(0, 1fr);
    gap: var(--sp-2);
    border: none !important;
  }
  td::before {
    content: attr(data-label);
    color: var(--text-muted);
    font-size: var(--fs-12);
  }
  td > * {
    grid-column: 2;
  }
  .slider {
    width: 100%;
  }
}
</style>
