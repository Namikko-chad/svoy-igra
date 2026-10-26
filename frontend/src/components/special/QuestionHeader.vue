<script setup lang="ts">
import type { QuestionView } from '@/types/protocol'
import { MODIFIER_ICON, MODIFIER_LABEL } from '@/utils/special'

defineProps<{ question: Pick<QuestionView, 'categoryName' | 'value' | 'modifier' | 'stake'>; tv?: boolean; final?: boolean }>()
</script>

<template>
  <div class="qhead" :class="{ tv }">
    <span class="cat">{{ final ? 'Финал · ' : '' }}{{ question.categoryName }}</span>
    <span v-if="question.modifier" class="mod" :class="question.modifier">
      {{ MODIFIER_ICON[question.modifier] }} {{ MODIFIER_LABEL[question.modifier] }}
    </span>
    <span class="spacer" />
    <span v-if="!final" class="display gold num value">
      {{ question.modifier && question.stake !== question.value ? question.stake : question.value }}
    </span>
  </div>
</template>

<style scoped>
.qhead {
  display: flex;
  align-items: baseline;
  gap: var(--sp-2);
  flex-wrap: wrap;
  width: 100%;
}
.cat {
  text-transform: uppercase;
  font-weight: 600;
  font-size: var(--fs-14);
  color: var(--text-muted);
}
.mod {
  align-self: center;
  padding: 2px var(--sp-2);
  border-radius: var(--r-pill);
  border: 1px solid var(--gold);
  color: var(--gold);
  font-size: var(--fs-12);
  font-weight: 600;
  white-space: nowrap;
}
.value {
  font-size: var(--fs-24);
  font-weight: 800;
}
.tv .cat {
  font-size: clamp(16px, 1.6vw, 32px);
}
.tv .mod {
  font-size: clamp(14px, 1.2vw, 24px);
  padding: 4px 16px;
}
.tv .value {
  font-size: clamp(32px, 3.6vw, 72px);
}
</style>
