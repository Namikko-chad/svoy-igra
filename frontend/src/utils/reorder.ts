/** Move item `from` → `to` and renumber `position` 0..n-1 (mirrors the server's renumbering). */
export function moveItem<T extends { position: number }>(items: T[], from: number, to: number): T[] {
  if (from === to || from < 0 || to < 0 || from >= items.length || to >= items.length) return items
  const next = [...items]
  const [it] = next.splice(from, 1)
  next.splice(to, 0, it!)
  next.forEach((x, i) => (x.position = i))
  return next
}

/** Value suggested for a new question: 100 × (index + 1), as the server defaults it. */
export function suggestValue(existing: { value: number }[]): number {
  return 100 * (existing.length + 1)
}
