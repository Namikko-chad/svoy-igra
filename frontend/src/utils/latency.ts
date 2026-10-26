/** Latency colour scale (design manifest): < 60 success, 60–150 warning, > 150 danger. */
export function latencyLevel(ms: number | null | undefined): 'success' | 'warning' | 'danger' | 'none' {
  if (ms == null || !Number.isFinite(ms)) return 'none'
  if (ms < 60) return 'success'
  if (ms <= 150) return 'warning'
  return 'danger'
}

export function formatMs(ms: number | null | undefined): string {
  return ms == null || !Number.isFinite(ms) ? '—' : `${Math.round(ms)} мс`
}
