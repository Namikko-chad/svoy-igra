<script setup lang="ts">
import type { GameSettingsForm } from '@/utils/special'
import { MODIFIER_ICON } from '@/utils/special'

const form = defineModel<GameSettingsForm>({ required: true })
const mods = [
  { key: 'cat', label: 'Кот в мешке', icon: MODIFIER_ICON.cat },
  { key: 'auction', label: 'Аукцион', icon: MODIFIER_ICON.auction },
  { key: 'noRisk', label: 'Без риска', icon: MODIFIER_ICON.no_risk },
  { key: 'double', label: 'Двойная стоимость', icon: MODIFIER_ICON.double },
] as const
</script>

<template>
  <div class="col">
    <div class="grid">
      <label class="field">
        Чтение вопроса, с (1–120)
        <input v-model.number="form.readingSeconds" class="input num" type="number" min="1" max="120" required />
      </label>
      <label class="field">
        Окно для ответа, с (3–300)
        <input v-model.number="form.buzzSeconds" class="input num" type="number" min="3" max="300" required />
      </label>
      <label class="field">
        Ответ в финале, с (10–300)
        <input v-model.number="form.finalSeconds" class="input num" type="number" min="10" max="300" required />
      </label>
    </div>
    <label class="check"><input v-model="form.wrongPenalty" type="checkbox" /> Штраф за неверный ответ</label>
    <fieldset class="mods">
      <legend class="muted small">Спецвопросов в раунде (0–5, со следующего раунда)</legend>
      <label v-for="m in mods" :key="m.key" class="field mod">
        <span>{{ m.icon }} {{ m.label }}</span>
        <input v-model.number="form.modifiers[m.key]" class="input num" type="number" min="0" max="5" />
      </label>
    </fieldset>
  </div>
</template>

<style scoped>
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: var(--sp-3);
}
.mods {
  border: 1px solid var(--border);
  border-radius: var(--r-input);
  padding: var(--sp-3);
  margin: 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
  gap: var(--sp-3);
}
.mods legend {
  padding: 0 var(--sp-1);
}
.mod span {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
