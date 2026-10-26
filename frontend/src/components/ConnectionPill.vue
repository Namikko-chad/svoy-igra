<script setup lang="ts">
defineProps<{ connected: boolean }>()
</script>

<template>
  <span class="chip" :title="connected ? 'Подключено' : 'Нет связи'">
    <span class="dot" :class="{ on: connected }" />
    {{ connected ? 'онлайн' : 'переподключение…' }}
  </span>
</template>
