import { describe, expect, it } from 'vitest'
import { androidIntentUrl, digitsOnly, isAdminPin, isAndroid, isGamePin } from '@/utils/pin'
import { tokenKey } from '@/utils/storage'
import { rolePath } from '@/utils/roles'

describe('pins', () => {
  it('validates game and admin PINs', () => {
    expect(isGamePin('123456')).toBe(true)
    expect(isGamePin('12345')).toBe(false)
    expect(isGamePin('12345a')).toBe(false)
    expect(isAdminPin('1234')).toBe(true)
    expect(isAdminPin('12345678')).toBe(true)
    expect(isAdminPin('123')).toBe(false)
    expect(isAdminPin('123456789')).toBe(false)
  })
  it('keeps digits only', () => {
    expect(digitsOnly(' 12-34 56 7', 6)).toBe('123456')
  })
})

describe('share links', () => {
  it('builds the Android intent URL exactly as protocol §8', () => {
    expect(androidIntentUrl('http://192.168.1.5:3000', '123456', 'http://192.168.1.5:3000/g/123456')).toBe(
      'intent://join?server=http%3A%2F%2F192.168.1.5%3A3000&pin=123456' +
        '#Intent;scheme=svoyigra;package=dev.svoyigra.mobile;' +
        'S.browser_fallback_url=http%3A%2F%2F192.168.1.5%3A3000%2Fg%2F123456;end',
    )
  })
  it('detects Android', () => {
    expect(isAndroid('Mozilla/5.0 (Linux; Android 15; Pixel 8)')).toBe(true)
    expect(isAndroid('Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X)')).toBe(false)
  })
})

describe('storage keys and routes', () => {
  it('keys tokens per server, game and role', () => {
    expect(tokenKey('123456', 'host', 'http://h:3000')).toBe('svoy.token|http://h:3000|123456|host')
  })
  it('maps roles to game-scoped paths', () => {
    expect(rolePath('123456', 'player')).toBe('/g/123456/play')
    expect(rolePath('123456', 'admin')).toBe('/g/123456/admin')
  })
})
