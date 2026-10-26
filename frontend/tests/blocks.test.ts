import { describe, expect, it } from 'vitest'
import { mediaKind, resolveMediaUrl, splitBlocks } from '@/utils/blocks'

describe('mediaKind', () => {
  it('detects by extension, case-insensitive', () => {
    expect(mediaKind('media:a.PNG')).toBe('image')
    expect(mediaKind('media:a.Mp4')).toBe('video')
    expect(mediaKind('media:a.mkv')).toBe('video')
    expect(mediaKind('media:a.OGA')).toBe('audio')
    expect(mediaKind('media:a.opus')).toBe('audio')
    expect(mediaKind('https://x.org/clip.webm?t=1#f')).toBe('video')
  })
  it('falls back to image', () => {
    expect(mediaKind('media:file.xyz')).toBe('image')
    expect(mediaKind('media:noext')).toBe('image')
  })
})

describe('resolveMediaUrl', () => {
  it('maps media: to the pack media endpoint, path-escaped', () => {
    expect(resolveMediaUrl('media:a b.jpg', 'p1')).toBe('/api/packs/p1/media/a%20b.jpg')
  })
  it('keeps http(s) urls', () => {
    expect(resolveMediaUrl('https://e.com/x.png', 'p1')).toBe('https://e.com/x.png')
  })
})

describe('splitBlocks', () => {
  it('splits the protocol example in document order', () => {
    const md = 'Кто изображён на фото?\n\n![](media:portrait.jpg)\n\nПослушайте отрывок: ![гимн](media:anthem.mp3)'
    expect(splitBlocks(md, 'P')).toEqual([
      { type: 'text', markdown: 'Кто изображён на фото?' },
      { type: 'image', url: '/api/packs/P/media/portrait.jpg', alt: '' },
      { type: 'text', markdown: 'Послушайте отрывок:' },
      { type: 'audio', url: '/api/packs/P/media/anthem.mp3', alt: 'гимн' },
    ])
  })
  it('drops empty text and handles adjacent media', () => {
    expect(splitBlocks('  ![](media:a.mp4)![x](media:b.png)  ', 'P')).toEqual([
      { type: 'video', url: '/api/packs/P/media/a.mp4', alt: '' },
      { type: 'image', url: '/api/packs/P/media/b.png', alt: 'x' },
    ])
  })
  it('returns a single text block without media', () => {
    expect(splitBlocks('  Просто **текст**  ', 'P')).toEqual([{ type: 'text', markdown: 'Просто **текст**' }])
  })
  it('returns nothing for empty input', () => {
    expect(splitBlocks('   \n ', 'P')).toEqual([])
  })
  it('supports titles and angle-bracket sources', () => {
    expect(splitBlocks('![a](<media:x.jpg> "t")', 'P')).toEqual([{ type: 'image', url: '/api/packs/P/media/x.jpg', alt: 'a' }])
    expect(splitBlocks('![a](https://e.com/s.mp3 "title")', 'P')).toEqual([
      { type: 'audio', url: 'https://e.com/s.mp3', alt: 'a' },
    ])
  })
  it('leaves ordinary links in text', () => {
    expect(splitBlocks('см. [ссылку](https://e.com)', 'P')).toEqual([{ type: 'text', markdown: 'см. [ссылку](https://e.com)' }])
  })
})
