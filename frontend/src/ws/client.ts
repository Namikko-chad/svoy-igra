import { ref, shallowRef } from 'vue'
import type { GameEvent, GameView, Welcome, WsFrame } from '@/types/protocol'
import { collectDevice } from '@/utils/device'

export const CLOSE_INVALID_TOKEN = 4001
export const CLOSE_KICKED = 4003
export const CLOSE_GAME_CLOSED = 4004
export const CLOSE_REPLACED = 4009
const FATAL = new Set([CLOSE_INVALID_TOKEN, CLOSE_KICKED, CLOSE_GAME_CLOSED, CLOSE_REPLACED])

export type SocketOptions = { token: string; onError?: (message: string, code: string) => void }

/** Every role connects with its token; the token decides game and role (protocol §4). */
export function wsUrl(token: string, loc: { protocol: string; host: string } = location): string {
  const proto = loc.protocol === 'https:' ? 'wss' : 'ws'
  return `${proto}://${loc.host}/api/ws?token=${encodeURIComponent(token)}`
}

/** Backoff sequence 1 s, 2 s, 4 s … max 10 s (attempt is 0-based). */
export function backoffMs(attempt: number): number {
  return Math.min(10_000, 1000 * 2 ** Math.max(0, attempt))
}

/** Coerce list fields a server may serialize as `null` into the `[]` the protocol promises. */
export function normalizeView(v: GameView): GameView {
  if (!v) return v
  return { ...v, players: v.players ?? [], attemptedPlayerIds: v.attemptedPlayerIds ?? [] }
}

/** One WebSocket session with automatic reconnects and a reactive game snapshot. */
export class GameSocket {
  readonly state = shallowRef<GameView | null>(null)
  readonly welcome = shallowRef<Welcome | null>(null)
  readonly connected = ref(false)
  /** serverNow − Date.now(), refreshed on every state. */
  readonly clockOffset = ref(0)
  /** Set when the server closed with a terminal code (4001/4003/4004/4009); reconnects stop. */
  readonly fatalCode = ref<number | null>(null)

  private ws: WebSocket | null = null
  private attempt = 0
  private timer: ReturnType<typeof setTimeout> | null = null
  private watchdog: ReturnType<typeof setTimeout> | null = null
  private stopped = true
  private seq = 0
  private listeners = new Set<(e: GameEvent) => void>()

  constructor(private opts: SocketOptions) {}

  /** Server time estimate (ms). */
  now(): number {
    return Date.now() + this.clockOffset.value
  }

  connect(): void {
    this.stopped = false
    this.fatalCode.value = null
    this.attempt = 0
    this.open()
  }

  close(): void {
    this.stopped = true
    this.clearTimers()
    const ws = this.ws
    this.ws = null
    if (ws) {
      ws.onclose = null
      ws.close(1000)
    }
    this.connected.value = false
  }

  /** Give the seat up (`leave`), then close. The caller forgets the token. */
  leave(): void {
    const ws = this.ws
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'leave', data: {} }))
    this.close()
  }

  onEvent(fn: (e: GameEvent) => void): () => void {
    this.listeners.add(fn)
    return () => this.listeners.delete(fn)
  }

  send(type: string, data: object = {}): boolean {
    const ws = this.ws
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      if (type !== 'pong') this.opts.onError?.('Нет соединения с сервером', 'offline')
      return false
    }
    const frame: WsFrame = { type, data }
    if (type !== 'pong') frame.reqId = String(++this.seq)
    ws.send(JSON.stringify(frame))
    return true
  }

  private open() {
    this.clearTimers()
    let ws: WebSocket
    try {
      ws = new WebSocket(wsUrl(this.opts.token))
    } catch {
      this.scheduleReconnect()
      return
    }
    this.ws = ws
    ws.onopen = () => {
      this.attempt = 0
      this.connected.value = true
      this.armWatchdog()
      // hello is required for players and harmless for everyone else.
      this.send('hello', collectDevice())
    }
    ws.onmessage = (ev) => this.handle(ev.data)
    ws.onclose = (ev) => {
      if (this.ws !== ws) return
      this.ws = null
      this.connected.value = false
      if (this.watchdog) clearTimeout(this.watchdog)
      if (FATAL.has(ev.code)) {
        this.fatalCode.value = ev.code
        this.stopped = true
        return
      }
      this.scheduleReconnect()
    }
    ws.onerror = () => {
      /* onclose follows */
    }
  }

  private handle(raw: unknown) {
    if (typeof raw !== 'string') return
    let frame: WsFrame
    try {
      frame = JSON.parse(raw) as WsFrame
    } catch {
      return
    }
    this.armWatchdog()
    switch (frame.type) {
      case 'ping':
        this.send('pong', (frame.data as object) ?? {})
        break
      case 'welcome': {
        const w = frame.data as Welcome
        this.welcome.value = w
        if (typeof w?.serverNow === 'number') this.clockOffset.value = w.serverNow - Date.now()
        break
      }
      case 'state': {
        const s = normalizeView(frame.data as GameView)
        if (typeof s?.serverNow === 'number') this.clockOffset.value = s.serverNow - Date.now()
        this.state.value = s
        break
      }
      case 'event':
        for (const fn of this.listeners) {
          try {
            fn(frame.data as GameEvent)
          } catch (e) {
            console.error(e)
          }
        }
        break
      case 'error': {
        const d = (frame.data ?? {}) as { code?: string; message?: string }
        this.opts.onError?.(d.message || d.code || 'Ошибка', d.code ?? 'error')
        break
      }
    }
  }

  /** The server pings every 2 s; 3 missed pings ≈ dead link → reconnect. */
  private armWatchdog() {
    if (this.watchdog) clearTimeout(this.watchdog)
    this.watchdog = setTimeout(() => {
      const ws = this.ws
      if (ws) {
        this.ws = null
        ws.onclose = null
        ws.close()
        this.connected.value = false
        this.scheduleReconnect()
      }
    }, 7000)
  }

  private scheduleReconnect() {
    if (this.stopped) return
    const delay = backoffMs(this.attempt++)
    this.timer = setTimeout(() => this.open(), delay)
  }

  private clearTimers() {
    if (this.timer) clearTimeout(this.timer)
    if (this.watchdog) clearTimeout(this.watchdog)
    this.timer = null
    this.watchdog = null
  }
}
