import { describe, expect, it } from 'vitest'
import { initials, squareCrop } from '@/utils/avatar'

describe('initials', () => {
  it('takes first and last word letters', () => {
    expect(initials('Анна Петрова')).toBe('АП')
    expect(initials('боря')).toBe('Б')
    expect(initials('  Мария  Анна  Ли ')).toBe('МЛ')
    expect(initials('')).toBe('?')
    expect(initials(null)).toBe('?')
    expect(initials('😀 smile')).toBe('😀S')
  })
})

describe('squareCrop', () => {
  it('centers a square and caps the output size', () => {
    expect(squareCrop(1920, 1080)).toEqual({ sx: 420, sy: 0, side: 1080, out: 512 })
    expect(squareCrop(300, 500)).toEqual({ sx: 0, sy: 100, side: 300, out: 300 })
    expect(squareCrop(512, 512)).toEqual({ sx: 0, sy: 0, side: 512, out: 512 })
  })
})
