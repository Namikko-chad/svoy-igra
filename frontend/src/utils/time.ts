const pad = (n: number, w = 2) => String(n).padStart(w, '0')

/** Unix ms → `YYYY-MM-DD HH:MM:SS` in the viewer's local time zone. */
export function formatDateTime(ms: number | null | undefined): string {
  if (ms == null || !Number.isFinite(ms)) return '—'
  const d = new Date(ms)
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
  )
}

/** Remaining ms → whole seconds shown on a countdown (ceil, never negative). */
export function secondsLeft(ms: number): number {
  return Math.max(0, Math.ceil(ms / 1000))
}

export function formatBytes(n: number): string {
  if (!Number.isFinite(n) || n < 0) return '—'
  const units = ['Б', 'КБ', 'МБ', 'ГБ']
  let i = 0
  let v = n
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i++
  }
  return `${i === 0 ? v : v.toFixed(v < 10 ? 1 : 0)} ${units[i]}`
}

/** Russian plural: plural(5, ['категория', 'категории', 'категорий']). */
export function plural(n: number, forms: [string, string, string]): string {
  const a = Math.abs(n) % 100
  const b = a % 10
  if (a > 10 && a < 20) return forms[2]
  if (b > 1 && b < 5) return forms[1]
  if (b === 1) return forms[0]
  return forms[2]
}
