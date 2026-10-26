import { describe, expect, it } from 'vitest'
import { auctionLimits, catRecipients, clampInt, finalDeltaText, finalRows, remainingThemes, suggestBid, wrongDelta } from '@/utils/special'
import { isFinalPhase, isSpecialPhase } from '@/utils/phase'
import type { AuctionView, FinalView, PlayerView } from '@/types/protocol'

const pl = (id: string, score = 0, connected = true): PlayerView => ({ id, name: id.toUpperCase(), score, connected, avatarUrl: null })

describe('wrongDelta', () => {
  it('follows §4.5', () => {
    expect(wrongDelta({ modifier: 'cat', stake: 300, value: 300 }, false)).toBe(300)
    expect(wrongDelta({ modifier: 'auction', stake: 750, value: 300 }, false)).toBe(750)
    expect(wrongDelta({ modifier: 'no_risk', stake: 600, value: 300 }, true)).toBe(0)
    expect(wrongDelta({ modifier: 'double', stake: 600, value: 300 }, false)).toBe(0)
    expect(wrongDelta({ modifier: 'double', stake: 600, value: 300 }, true)).toBe(600)
    expect(wrongDelta({ modifier: null, stake: 300, value: 300 }, true)).toBe(300)
    expect(wrongDelta({ modifier: null, stake: 300, value: 300 }, false)).toBe(0)
  })
})

describe('catRecipients', () => {
  it('offers every other player', () => {
    expect(catRecipients([pl('a'), pl('b'), pl('c', 0, false)], 'a').map((p) => p.id)).toEqual(['b', 'c'])
  })
  it('falls back to the chooser when nobody else is connected', () => {
    expect(catRecipients([pl('a'), pl('b', 0, false)], 'a').map((p) => p.id)).toEqual(['b', 'a'])
    expect(catRecipients([pl('a')], 'a').map((p) => p.id)).toEqual(['a'])
  })
})

describe('auction', () => {
  const a: AuctionView = { turnPlayerId: 'b', highBid: 300, highBidderId: 'a', allIn: false, passedPlayerIds: [] }
  it('computes limits', () => {
    expect(auctionLimits(a, 1000)).toEqual({ min: 301, max: 1000, canRaise: true, canAllIn: true })
    expect(auctionLimits(a, 300)).toEqual({ min: 301, max: 300, canRaise: false, canAllIn: false })
    expect(auctionLimits({ ...a, allIn: true }, 1000).canRaise).toBe(false)
    expect(auctionLimits({ ...a, allIn: true }, 1000).canAllIn).toBe(true)
  })
  it('suggests the next hundred', () => {
    expect(suggestBid(300, 1000)).toBe(400)
    expect(suggestBid(350, 1000)).toBe(400)
    expect(suggestBid(300, 350)).toBe(350)
  })
  it('clamps', () => {
    expect(clampInt('12.6', 1, 10)).toBe(10)
    expect(clampInt('abc', 1, 10)).toBe(1)
    expect(clampInt(5, 1, 10)).toBe(5)
  })
})

describe('final', () => {
  const f: FinalView = {
    themes: [
      { id: 1, name: 'A', removed: true },
      { id: 2, name: 'B', removed: false },
    ],
    removerId: null,
    answerStartsAt: null,
    answerEndsAt: null,
    participants: [{ playerId: 'a', hasBet: true, bet: 200, hasAnswer: true, answer: 'x', correct: false }],
  }
  it('joins names and scores', () => {
    expect(finalRows(f, [pl('a', 500)])[0]).toMatchObject({ name: 'A', score: 500, bet: 200 })
    expect(finalRows(null, [])).toEqual([])
  })
  it('lists remaining themes', () => {
    expect(remainingThemes(f).map((t) => t.id)).toEqual([2])
  })
  it('formats judged deltas', () => {
    expect(finalDeltaText({ correct: false, bet: 200 })).toBe('−200')
    expect(finalDeltaText({ correct: true, bet: 200 })).toBe('+200')
    expect(finalDeltaText({ correct: null, bet: 200 })).toBeNull()
  })
  it('classifies phases', () => {
    expect(isSpecialPhase('auction')).toBe(true)
    expect(isSpecialPhase('question')).toBe(false)
    expect(isFinalPhase('final_bets')).toBe(true)
    expect(isFinalPhase('finished')).toBe(false)
  })
})

import { settingsForm, settingsPatch } from '@/utils/special'
describe('settings', () => {
  it('fills defaults and clamps to protocol ranges', () => {
    const f = settingsForm(null)
    expect(f).toEqual({ readingSeconds: 10, buzzSeconds: 15, wrongPenalty: false, finalSeconds: 60, modifiers: { cat: 1, auction: 1, noRisk: 1, double: 1 } })
    const p = settingsPatch({ ...f, readingSeconds: 0, buzzSeconds: 999, finalSeconds: 5, modifiers: { cat: 9, auction: -1, noRisk: 2.4, double: 5 } })
    expect(p).toMatchObject({ readingSeconds: 1, buzzSeconds: 300, finalSeconds: 10, modifiers: { cat: 5, auction: 0, noRisk: 2, double: 5 } })
  })
})
