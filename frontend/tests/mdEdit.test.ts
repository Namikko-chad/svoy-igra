import { describe, expect, it } from 'vitest'
import { insertBlock, insertLink, toggleLinePrefix, toggleWrap, type EditState } from '@/utils/mdEdit'

/** Render a state as text with [ ] around the selection (or | for a cursor). */
const show = (s: EditState) =>
  s.start === s.end ? s.text.slice(0, s.start) + '|' + s.text.slice(s.start) : s.text.slice(0, s.start) + '[' + s.text.slice(s.start, s.end) + ']' + s.text.slice(s.end)
/** Parse the same notation. */
const st = (t: string): EditState => {
  const c = t.indexOf('|')
  if (c >= 0) return { text: t.replace('|', ''), start: c, end: c }
  const a = t.indexOf('[')
  const b = t.indexOf(']')
  return { text: t.slice(0, a) + t.slice(a + 1, b) + t.slice(b + 1), start: a, end: b - 1 }
}

describe('toggleWrap', () => {
  it('wraps the selection', () => {
    expect(show(toggleWrap(st('a [bc] d'), '**'))).toBe('a **[bc]** d')
  })
  it('unwraps when markers surround the selection', () => {
    expect(show(toggleWrap(st('a **[bc]** d'), '**'))).toBe('a [bc] d')
  })
  it('unwraps when the selection includes the markers', () => {
    expect(show(toggleWrap(st('a [**bc**] d'), '**'))).toBe('a [bc] d')
  })
  it('inserts a pair around the cursor', () => {
    expect(show(toggleWrap(st('ab|'), '*'))).toBe('ab*|*')
  })
  it('does not mistake bold for italic', () => {
    expect(show(toggleWrap(st('**[x]**'), '*'))).toBe('***[x]***')
    expect(show(toggleWrap(st('*[x]*'), '*'))).toBe('[x]')
  })
})

describe('toggleLinePrefix', () => {
  it('prefixes every selected line and toggles back', () => {
    const on = toggleLinePrefix(st('[a\nb]'), '- ')
    expect(show(on)).toBe('[- a\n- b]')
    expect(show(toggleLinePrefix(on, '- '))).toBe('[a\nb]')
  })
  it('works on the cursor line only', () => {
    expect(show(toggleLinePrefix(st('x\nhe|llo\ny'), '## '))).toBe('x\n## he|llo\ny')
    expect(show(toggleLinePrefix(st('Кто [это]'), '## '))).toBe('## Кто [это]')
    expect(show(toggleLinePrefix(st('## Кто [это]'), '## '))).toBe('Кто [это]')
  })
  it('numbers lines and replaces bullets', () => {
    expect(show(toggleLinePrefix(st('[- a\n- b\n- c]'), { numbered: true }))).toBe('[1. a\n2. b\n3. c]')
    expect(show(toggleLinePrefix(st('[1. a\n2. b]'), { numbered: true }))).toBe('[a\nb]')
  })
  it('quotes partial selections by whole lines', () => {
    expect(show(toggleLinePrefix(st('ab[c\nd]e'), '> '))).toBe('[> abc\n> de]')
    expect(show(toggleLinePrefix(st('a[b]c'), '> '))).toBe('> a[b]c')
  })
})

describe('insertLink', () => {
  it('uses the selection as label', () => {
    expect(show(insertLink(st('see [docs] now'), 'https://e.com'))).toBe('see [[docs]](https://e.com) now')
  })
  it('uses a placeholder label', () => {
    const r = insertLink(st('|'), 'https://e.com')
    expect(r.text).toBe('[текст](https://e.com)')
    expect(r.text.slice(r.start, r.end)).toBe('текст')
  })
})

describe('insertBlock', () => {
  it('separates the snippet with blank lines', () => {
    expect(show(insertBlock(st('Вопрос|текст'), '![](media:a.png)'))).toBe('Вопрос\n\n![](media:a.png)|\n\nтекст')
  })
  it('does not add padding at the edges', () => {
    expect(show(insertBlock(st('|'), '![](media:a.png)'))).toBe('![](media:a.png)|')
    expect(show(insertBlock(st('A\n\n|'), '![](media:a.png)'))).toBe('A\n\n![](media:a.png)|')
  })
  it('replaces the selection', () => {
    expect(insertBlock(st('[old]'), 'X').text).toBe('X')
  })
})
