<script setup lang="ts">
import { computed, ref } from 'vue'
import { useToastStore } from '@/stores/toast'
import QrCode from './QrCode.vue'

const props = defineProps<{ pin: string; link: string; title?: string }>()
const toast = useToastStore()
const canShare = computed(() => typeof navigator !== 'undefined' && typeof navigator.share === 'function')
const showQr = ref(true)

async function copy(text: string, what: string) {
  try {
    await navigator.clipboard.writeText(text)
    toast.success(`${what} скопирован${what === 'PIN' ? '' : 'а'}`)
  } catch {
    // Fallback for insecure origins (LAN http): select-and-copy via a temporary field.
    const ta = document.createElement('textarea')
    ta.value = text
    ta.style.position = 'fixed'
    ta.style.opacity = '0'
    document.body.appendChild(ta)
    ta.select()
    const ok = document.execCommand('copy')
    ta.remove()
    if (ok) toast.success('Скопировано')
    else toast.error('Не удалось скопировать')
  }
}
async function share() {
  try {
    await navigator.share({ title: props.title || 'Своя игра', text: `PIN игры: ${props.pin}`, url: props.link })
  } catch {
    /* cancelled */
  }
}
</script>

<template>
  <section class="card share">
    <div class="info col">
      <div class="muted small">PIN игры</div>
      <button class="pin display num" title="Скопировать PIN" @click="copy(pin, 'PIN')">{{ pin }}</button>
      <div class="muted small">Ссылка для участников</div>
      <a class="link mono" :href="link" target="_blank" rel="noopener">{{ link }}</a>
      <div class="row">
        <button class="btn btn-sm" @click="copy(link, 'Ссылка')">Копировать ссылку</button>
        <button v-if="canShare" class="btn btn-sm btn-primary" @click="share">Поделиться…</button>
        <button class="btn btn-sm btn-ghost" @click="showQr = !showQr">{{ showQr ? 'Скрыть QR' : 'Показать QR' }}</button>
      </div>
    </div>
    <QrCode v-if="showQr" class="qr" :text="link" />
  </section>
</template>

<style scoped>
.share {
  display: flex;
  gap: var(--sp-4);
  align-items: center;
  flex-wrap: wrap;
}
.info {
  flex: 1 1 240px;
  min-width: 0;
  gap: var(--sp-2);
}
.pin {
  all: unset;
  cursor: pointer;
  font-size: clamp(32px, 10vw, 48px);
  font-weight: 800;
  color: var(--gold);
  letter-spacing: 0.08em;
  text-shadow: var(--glow-gold);
}
.pin:focus-visible {
  outline: 2px solid var(--accent);
}
.link {
  word-break: break-all;
  font-size: var(--fs-14);
}
.qr {
  width: 160px;
  flex: none;
}
</style>
