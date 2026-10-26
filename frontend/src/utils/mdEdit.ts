/**
 * Pure markdown-editing helpers for the pack editor toolbar. Each takes the textarea state
 * (text + selection) and returns the new state; the component applies it.
 */
export type EditState = { text: string; start: number; end: number }

/**
 * Wrap the selection in `marker` (e.g. `**`), or unwrap it when it is already wrapped —
 * either just outside the selection or as the selection's own ends. With no selection the
 * markers are inserted and the cursor lands between them.
 */
export function toggleWrap(s: EditState, marker: string, placeholder = ''): EditState {
  const { text, start, end } = s
  const m = marker.length
  const before = text.slice(0, start)
  const sel = text.slice(start, end)
  const after = text.slice(end)
  const isMarker = (str: string, at: 'end' | 'start') => {
    // `*` must not be the inner half of `**` (and vice versa) to count as a match.
    if (at === 'end') return str.endsWith(marker) && (marker !== '*' || !str.endsWith('**') || str.endsWith('***'))
    return str.startsWith(marker) && (marker !== '*' || !str.startsWith('**') || str.startsWith('***'))
  }

  // Markers just outside the selection → remove them.
  if (isMarker(before, 'end') && isMarker(after, 'start')) {
    return { text: before.slice(0, -m) + sel + after.slice(m), start: start - m, end: end - m }
  }
  // Selection itself includes the markers → strip them.
  if (sel.length >= 2 * m && isMarker(sel, 'start') && isMarker(sel, 'end')) {
    const inner = sel.slice(m, -m)
    return { text: before + inner + after, start, end: start + inner.length }
  }
  const body = sel || placeholder
  return {
    text: before + marker + body + marker + after,
    start: start + m,
    end: start + m + body.length,
  }
}

/** [lineStart, lineEnd) of the lines the selection touches. */
function lineRange(text: string, start: number, end: number): [number, number] {
  const ls = text.lastIndexOf('\n', start - 1) + 1
  const effEnd = end > start && text[end - 1] === '\n' ? end - 1 : end
  let le = text.indexOf('\n', effEnd)
  if (le < 0) le = text.length
  return [ls, le]
}

/**
 * Toggle a line prefix (`## `, `- `, `> `) or numbering (`numbered: true` → `1. `, `2. `…)
 * on every line the selection touches. When all non-empty lines already carry it, it is removed.
 * The whole affected block stays selected.
 */
export function toggleLinePrefix(s: EditState, prefix: string | { numbered: true }): EditState {
  const [ls, le] = lineRange(s.text, s.start, s.end)
  const lines = s.text.slice(ls, le).split('\n')
  const numbered = typeof prefix !== 'string'
  const has = (l: string) => (numbered ? /^\d+\.\s/.test(l) : l.startsWith(prefix))
  const strip = (l: string) => (numbered ? l.replace(/^\d+\.\s/, '') : l.slice(prefix.length))
  const content = lines.filter((l) => l.trim() !== '')
  const remove = content.length > 0 && content.every(has)
  let n = 0
  const out = lines.map((l) => {
    if (remove) return has(l) ? strip(l) : l
    if (l.trim() === '' && lines.length > 1) return l
    // Replace another kind of prefix of the same family rather than stacking them.
    const base = numbered ? l.replace(/^(?:[-*+]\s|>\s)/, '') : l.replace(/^\d+\.\s/, '')
    return numbered ? `${++n}. ${base}` : prefix + base
  })
  const block = out.join('\n')
  const text = s.text.slice(0, ls) + block + s.text.slice(le)
  if (lines.length === 1) {
    // One line: keep the cursor/selection where it was, shifted by the prefix change.
    const delta = block.length - (le - ls)
    const clamp = (x: number) => Math.min(ls + block.length, Math.max(ls, x + delta))
    return { text, start: clamp(s.start), end: clamp(s.end) }
  }
  return { text, start: ls, end: ls + block.length }
}

/** `[selection or «текст»](url)`; the link text ends up selected. */
export function insertLink(s: EditState, url: string, placeholder = 'текст'): EditState {
  const label = s.text.slice(s.start, s.end) || placeholder
  const snippet = `[${label}](${url})`
  return {
    text: s.text.slice(0, s.start) + snippet + s.text.slice(s.end),
    start: s.start + 1,
    end: s.start + 1 + label.length,
  }
}

/**
 * Insert a block-level snippet (e.g. `![](media:x.jpg)`) at the cursor, replacing the
 * selection, separated from surrounding text by a blank line. The cursor lands after it.
 */
export function insertBlock(s: EditState, snippet: string): EditState {
  const before = s.text.slice(0, s.start)
  const after = s.text.slice(s.end)
  const pad = before && !before.endsWith('\n\n') ? (before.endsWith('\n') ? '\n' : '\n\n') : ''
  const tail = after && !after.startsWith('\n\n') ? (after.startsWith('\n') ? '\n' : '\n\n') : ''
  const pos = (before + pad + snippet).length
  return { text: before + pad + snippet + tail + after, start: pos, end: pos }
}
