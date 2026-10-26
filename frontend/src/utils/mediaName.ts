const TRANSLIT: Record<string, string> = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'e', ж: 'zh', з: 'z', и: 'i', й: 'y', к: 'k', л: 'l', м: 'm',
  н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'h', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sch',
  ъ: '', ы: 'y', ь: '', э: 'e', ю: 'yu', я: 'ya',
}

/** A valid pack media name (protocol §5): 1–128 chars of [A-Za-z0-9._-], not starting with '.'. */
export function isValidMediaName(name: string): boolean {
  return /^[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$/.test(name)
}

/** Turn an arbitrary file name into a valid media name, keeping the extension. */
export function sanitizeMediaName(fileName: string): string {
  let s = ''
  for (const ch of fileName.normalize('NFC')) {
    const lower = ch.toLowerCase()
    const t = TRANSLIT[lower]
    if (t !== undefined) s += ch === lower ? t : t.charAt(0).toUpperCase() + t.slice(1)
    else s += ch
  }
  s = s.replace(/\s+/g, '_').replace(/[^A-Za-z0-9._-]/g, '_').replace(/_+/g, '_').replace(/^\.+/, '')
  if (!s || s.startsWith('.')) s = 'file' + s
  if (s.length > 128) {
    const dot = s.lastIndexOf('.')
    const ext = dot > 0 && s.length - dot <= 12 ? s.slice(dot) : ''
    s = s.slice(0, 128 - ext.length) + ext
  }
  return s
}
