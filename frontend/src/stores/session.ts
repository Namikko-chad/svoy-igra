import type { Role } from '@/types/protocol'
import { forgetGame, loadSession, saveSession, sessionsFor, type StoredSession } from '@/utils/storage'

/** Thin facade over per-game token storage (kept non-reactive: pages read it once on mount). */
export const session = {
  get: (pin: string, role: Role): StoredSession | null => loadSession(pin, role),
  set: (pin: string, role: Role, s: StoredSession) => saveSession(pin, role, s),
  forget: (pin: string, role: Role) => saveSession(pin, role, null),
  forgetGame,
  all: sessionsFor,
}
