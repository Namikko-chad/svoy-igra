<script setup lang="ts">
import { computed } from 'vue'
import { renderMarkdown } from '@/utils/markdown'

const props = defineProps<{ source: string }>()
// markdown-it runs with html:false, so the output contains no author-supplied HTML.
const html = computed(() => renderMarkdown(props.source))
</script>

<template>
  <div class="md" v-html="html" />
</template>
