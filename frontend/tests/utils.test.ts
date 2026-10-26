import { describe, expect, it } from 'vitest'
import { formatBytes, formatDateTime, plural, secondsLeft } from '@/utils/time'
import { latencyLevel } from '@/utils/latency'
import { isValidMediaName, sanitizeMediaName } from '@/utils/mediaName'
import { moveItem, suggestValue } from '@/utils/reorder'
import { parseUserAgent } from '@/utils/device'
import { filenameFromDisposition } from '@/api/transfer'
import { errorFromBody } from '@/api/http'
import { backoffMs, wsUrl } from '@/ws/client'

describe('time', () => {
  it('formats ISO local date-time', () => {
    const d = new Date(2026, 5, 15, 14, 30, 5)
    expect(formatDateTime(d.getTime())).toBe('2026-06-15 14:30:05')
    expect(formatDateTime(null)).toBe('—')
  })
  it('counts down in whole seconds', () => {
    expect(secondsLeft(9001)).toBe(10)
    expect(secondsLeft(1)).toBe(1)
    expect(secondsLeft(0)).toBe(0)
    expect(secondsLeft(-50)).toBe(0)
  })
  it('picks Russian plural forms', () => {
    const f: [string, string, string] = ['категория', 'категории', 'категорий']
    expect([1, 2, 5, 11, 21, 22, 0].map((n) => plural(n, f))).toEqual([
      'категория', 'категории', 'категорий', 'категорий', 'категория', 'категории', 'категорий',
    ])
  })
  it('formats bytes', () => {
    expect(formatBytes(512)).toBe('512 Б')
    expect(formatBytes(1536)).toBe('1.5 КБ')
    expect(formatBytes(50 * 1024 * 1024)).toBe('50 МБ')
  })
})

describe('latencyLevel', () => {
  it('follows the manifest scale', () => {
    expect(latencyLevel(59)).toBe('success')
    expect(latencyLevel(60)).toBe('warning')
    expect(latencyLevel(150)).toBe('warning')
    expect(latencyLevel(151)).toBe('danger')
    expect(latencyLevel(null)).toBe('none')
  })
})

describe('media names', () => {
  it('validates the protocol rule', () => {
    expect(isValidMediaName('a.jpg')).toBe(true)
    expect(isValidMediaName('.hidden')).toBe(false)
    expect(isValidMediaName('a b.jpg')).toBe(false)
    expect(isValidMediaName('x'.repeat(129))).toBe(false)
  })
  it('sanitizes arbitrary file names', () => {
    expect(sanitizeMediaName('Фото 1.JPG')).toBe('Foto_1.JPG')
    expect(sanitizeMediaName('..secret.png')).toBe('secret.png')
    expect(sanitizeMediaName('гимн (версия 2).mp3')).toBe('gimn_versiya_2_.mp3')
    const long = sanitizeMediaName('a'.repeat(200) + '.webm')
    expect(long.length).toBe(128)
    expect(long.endsWith('.webm')).toBe(true)
    for (const n of ['Фото 1.JPG', '..secret.png', '🙂.png', '...']) expect(isValidMediaName(sanitizeMediaName(n))).toBe(true)
  })
})

describe('reorder', () => {
  it('moves and renumbers', () => {
    const items = [0, 1, 2, 3].map((i) => ({ id: i, position: i }))
    const out = moveItem(items, 0, 2)
    expect(out.map((x) => x.id)).toEqual([1, 2, 0, 3])
    expect(out.map((x) => x.position)).toEqual([0, 1, 2, 3])
    expect(moveItem(items, 0, 9)).toBe(items)
  })
  it('suggests 100 × (index + 1)', () => {
    expect(suggestValue([])).toBe(100)
    expect(suggestValue([{ value: 100 }, { value: 200 }])).toBe(300)
  })
})

describe('parseUserAgent', () => {
  it('parses Android', () => {
    const r = parseUserAgent(
      'Mozilla/5.0 (Linux; Android 15; Pixel 8 Build/AP3A) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Mobile Safari/537.36',
    )
    expect(r).toEqual({ os: 'Android 15', model: 'Pixel 8' })
  })
  it('parses reduced Android UA (model "K")', () => {
    const r = parseUserAgent('Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36')
    expect(r.os).toBe('Android 10')
    expect(r.model).toBe('Chrome 141')
  })
  it('parses iPhone', () => {
    const r = parseUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1')
    expect(r).toEqual({ os: 'iOS 18.1', model: 'iPhone' })
  })
  it('parses desktop Windows Firefox', () => {
    const r = parseUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0')
    expect(r).toEqual({ os: 'Windows 10/11', model: 'Firefox 140' })
  })
})

describe('transfer helpers', () => {
  it('reads filename from Content-Disposition', () => {
    expect(filenameFromDisposition('attachment; filename="Мой пак.dub"', 'x')).toBe('Мой пак.dub')
    expect(filenameFromDisposition("attachment; filename*=UTF-8''%D0%9F%D0%B0%D0%BA.dub", 'x')).toBe('Пак.dub')
    expect(filenameFromDisposition('attachment; filename=game.json', 'x')).toBe('game.json')
    expect(filenameFromDisposition(null, 'fallback.dub')).toBe('fallback.dub')
  })
  it('parses {error:{message}} bodies', () => {
    const e = errorFromBody(409, '{"error":{"code":"name_taken","message":"Имя занято"}}')
    expect(e.code).toBe('name_taken')
    expect(e.message).toBe('Имя занято')
    expect(errorFromBody(500, 'oops').message).toContain('500')
  })
})

describe('ws helpers', () => {
  it('builds ws urls', () => {
    expect(wsUrl('a b', { protocol: 'https:', host: 'h:1' })).toBe('wss://h:1/api/ws?token=a%20b')
    expect(wsUrl('t', { protocol: 'http:', host: 'h' })).toBe('ws://h/api/ws?token=t')
  })
  it('backs off 1, 2, 4, 8, 10, 10 s', () => {
    expect([0, 1, 2, 3, 4, 5].map(backoffMs)).toEqual([1000, 2000, 4000, 8000, 10000, 10000])
  })
})

describe('normalizeView', () => {
  it('turns null lists into empty arrays', async () => {
    const { normalizeView } = await import('@/ws/client')
    const v = normalizeView({ players: null, attemptedPlayerIds: null } as never)
    expect(v.players).toEqual([])
    expect(v.attemptedPlayerIds).toEqual([])
  })
})
