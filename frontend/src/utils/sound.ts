/** Tiny WebAudio cues — no audio files. All calls are no-ops when audio is unavailable. */
let ctx: AudioContext | null = null

function audio(): AudioContext | null {
  if (ctx) return ctx
  try {
    const C = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
    ctx = C ? new C() : null
  } catch {
    ctx = null
  }
  return ctx
}

/** Call from a user gesture so later cues are allowed to play. */
export function unlockAudio(): void {
  const a = audio()
  if (a && a.state === 'suspended') void a.resume().catch(() => {})
}

function tone(freq: number, start: number, dur: number, type: OscillatorType = 'sine', gain = 0.18) {
  const a = audio()
  if (!a || a.state !== 'running') return
  const t0 = a.currentTime + start
  const osc = a.createOscillator()
  const g = a.createGain()
  osc.type = type
  osc.frequency.setValueAtTime(freq, t0)
  g.gain.setValueAtTime(0.0001, t0)
  g.gain.exponentialRampToValueAtTime(gain, t0 + 0.01)
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur)
  osc.connect(g).connect(a.destination)
  osc.start(t0)
  osc.stop(t0 + dur + 0.02)
}

export const sounds = {
  buzz: () => {
    tone(880, 0, 0.12, 'square', 0.12)
    tone(1320, 0.1, 0.18, 'square', 0.12)
  },
  correct: () => {
    tone(660, 0, 0.12, 'triangle')
    tone(880, 0.12, 0.12, 'triangle')
    tone(1320, 0.24, 0.3, 'triangle')
  },
  wrong: () => {
    tone(220, 0, 0.25, 'sawtooth', 0.12)
    tone(160, 0.22, 0.35, 'sawtooth', 0.12)
  },
  timeout: () => {
    tone(520, 0, 0.18, 'sine')
    tone(390, 0.2, 0.18, 'sine')
    tone(260, 0.4, 0.3, 'sine')
  },
  open: () => tone(990, 0, 0.1, 'sine', 0.1),
  /** a special cell opened */
  fanfare: () => {
    tone(523, 0, 0.12, 'triangle')
    tone(659, 0.12, 0.12, 'triangle')
    tone(784, 0.24, 0.12, 'triangle')
    tone(1047, 0.36, 0.35, 'triangle')
  },
  /** auction bid / cat handed over */
  tick: () => tone(1200, 0, 0.06, 'square', 0.08),
  /** auction won */
  gavel: () => {
    tone(300, 0, 0.08, 'square', 0.15)
    tone(300, 0.15, 0.12, 'square', 0.15)
  },
  /** a final theme removed */
  swoosh: () => {
    tone(880, 0, 0.08, 'sine', 0.08)
    tone(440, 0.06, 0.12, 'sine', 0.08)
  },
}
