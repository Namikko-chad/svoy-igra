import type { Block } from '@/types/protocol'

/** Extension → media kind, per protocol §3. Unknown extensions are images. */
const VIDEO = new Set(['mp4', 'webm', 'mov', 'm4v', 'mkv'])
const AUDIO = new Set(['mp3', 'ogg', 'oga', 'wav', 'm4a', 'aac', 'flac', 'opus'])

export type MediaKind = 'image' | 'video' | 'audio'

export function mediaKind(src: string): MediaKind {
  const path = src.split(/[?#]/)[0] ?? ''
  const dot = path.lastIndexOf('.')
  const ext = dot >= 0 ? path.slice(dot + 1).toLowerCase() : ''
  if (VIDEO.has(ext)) return 'video'
  if (AUDIO.has(ext)) return 'audio'
  return 'image'
}

/** `media:x` → `/api/packs/{packId}/media/{x}` (path-escaped); other URLs unchanged. */
export function resolveMediaUrl(src: string, packId: string): string {
  if (src.startsWith('media:')) {
    return `/api/packs/${encodeURIComponent(packId)}/media/${encodeURIComponent(src.slice('media:'.length))}`
  }
  return src
}

/** Same pattern as the server (backend packs/blocks.go): `![alt](src)`, `![alt](<src>)`, `![alt](src "title")`. */
const IMAGE_RE = /!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/g

/**
 * Split question markdown into blocks — the same rule the server applies (protocol §3):
 * every image-syntax occurrence becomes a media block at its position, the text between
 * occurrences (trimmed) becomes a text block, empty text is dropped.
 */
export function splitBlocks(markdown: string, packId: string): Block[] {
  const blocks: Block[] = []
  const pushText = (s: string) => {
    const t = s.trim()
    if (t) blocks.push({ type: 'text', markdown: t })
  }
  let last = 0
  for (const m of markdown.matchAll(IMAGE_RE)) {
    const idx = m.index ?? 0
    pushText(markdown.slice(last, idx))
    const src = m[2] ?? ''
    blocks.push({ type: mediaKind(src), url: resolveMediaUrl(src, packId), alt: m[1] ?? '' })
    last = idx + m[0].length
  }
  pushText(markdown.slice(last))
  return blocks
}
