import type { Role } from '@/types/protocol'

export function storageGet(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

export function storageSet(key: string, value: string | null): void {
  try {
    if (value == null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {
    /* storage unavailable (private mode) — keep going in memory */
  }
}

/** Tokens are stored per server + game PIN + role: `svoy.token|<origin>|<pin>|<role>`. */
export function tokenKey(pin: string, role: Role, origin = location.origin): string {
  return `svoy.token|${origin}|${pin}|${role}`
}

export type StoredSession = { token: string; name?: string; playerId?: string }

export const ROLES: Role[] = ['player', 'host', 'admin', 'screen']

export function loadSession(pin: string, role: Role): StoredSession | null {
  const raw = storageGet(tokenKey(pin, role))
  if (!raw) return null
  try {
    const s = JSON.parse(raw) as StoredSession
    return typeof s?.token === 'string' && s.token ? s : null
  } catch {
    return null
  }
}

export function saveSession(pin: string, role: Role, s: StoredSession | null): void {
  storageSet(tokenKey(pin, role), s ? JSON.stringify(s) : null)
}

/** Every role this browser holds a token for in the given game. */
export function sessionsFor(pin: string): { role: Role; session: StoredSession }[] {
  return ROLES.flatMap((role) => {
    const session = loadSession(pin, role)
    return session ? [{ role, session }] : []
  })
}

export function forgetGame(pin: string): void {
  for (const role of ROLES) saveSession(pin, role, null)
}

/** Remembered player name, prefilled on the join form. */
export const LAST_NAME_KEY = 'svoy.lastName'

/** Game PINs this browser holds any token for on this server (for «Ваши игры»). */
export function storedPins(origin = location.origin): string[] {
  const prefix = `svoy.token|${origin}|`
  const pins = new Set<string>()
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i)
      if (k?.startsWith(prefix)) pins.add(k.slice(prefix.length).split('|')[0] ?? '')
    }
  } catch {
    /* storage unavailable */
  }
  pins.delete('')
  return [...pins]
}
