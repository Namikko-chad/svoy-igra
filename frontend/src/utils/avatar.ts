/** Up to two initials from a name: «Анна Петрова» → «АП», «боря» → «Б». */
export function initials(name: string | null | undefined): string {
  const words = (name ?? '').trim().split(/\s+/).filter(Boolean)
  if (!words.length) return '?'
  const letters = words.length === 1 ? [words[0]!] : [words[0]!, words[words.length - 1]!]
  return letters.map((w) => Array.from(w)[0]!.toUpperCase()).join('')
}

/** Centered square crop of a w×h image, scaled to at most `max` px (protocol §2.1 Avatars). */
export function squareCrop(w: number, h: number, max = 512) {
  const side = Math.max(1, Math.min(w, h))
  return { sx: Math.floor((w - side) / 2), sy: Math.floor((h - side) / 2), side, out: Math.min(side, max) }
}

const toBlob = (c: HTMLCanvasElement, type: string, q: number) =>
  new Promise<Blob | null>((resolve) => c.toBlob(resolve, type, q))

/**
 * Crop a picked image file to a centered square ≤ 512 px and encode it as WebP
 * (JPEG where the browser cannot encode WebP). Throws a Russian message on failure.
 */
export async function makeAvatar(file: File, max = 512): Promise<{ blob: Blob; filename: string }> {
  let bitmap: ImageBitmap
  try {
    bitmap = await createImageBitmap(file)
  } catch {
    throw new Error('Не удалось прочитать картинку — выберите PNG, JPEG, WebP или GIF')
  }
  const { sx, sy, side, out } = squareCrop(bitmap.width, bitmap.height, max)
  const canvas = document.createElement('canvas')
  canvas.width = out
  canvas.height = out
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Браузер не умеет обрабатывать картинки')
  ctx.imageSmoothingQuality = 'high'
  ctx.drawImage(bitmap, sx, sy, side, side, 0, 0, out, out)
  bitmap.close?.()
  const webp = await toBlob(canvas, 'image/webp', 0.85)
  if (webp && webp.type === 'image/webp') return { blob: webp, filename: 'avatar.webp' }
  const jpeg = await toBlob(canvas, 'image/jpeg', 0.88)
  if (!jpeg) throw new Error('Не удалось сохранить картинку')
  return { blob: jpeg, filename: 'avatar.jpg' }
}
