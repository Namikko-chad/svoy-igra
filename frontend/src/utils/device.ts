export type DeviceHello = {
  platform: 'web'
  model: string
  os: string
  appVersion: string
  userAgent: string
  screen: string
}

/** Best-effort OS + device model from a user-agent string. */
export function parseUserAgent(ua: string): { os: string; model: string } {
  let os = ''
  let model = ''
  let m: RegExpMatchArray | null
  if ((m = ua.match(/Android\s+([\d.]+)?/))) {
    os = m[1] ? `Android ${m[1]}` : 'Android'
    const mm = ua.match(/Android[^;)]*;\s*(?:[a-z]{2}[-_][a-zA-Z]{2};\s*)?([^;)]+?)(?:\s+Build\/[^;)]*)?\)/)
    if (mm?.[1] && mm[1].trim() !== 'K') model = mm[1].trim()
  } else if ((m = ua.match(/(iPhone|iPad|iPod)[^)]*OS\s([\d_]+)/))) {
    model = m[1] ?? ''
    os = `iOS ${(m[2] ?? '').replace(/_/g, '.')}`
  } else if ((m = ua.match(/Windows NT\s([\d.]+)/))) {
    const map: Record<string, string> = { '10.0': '10/11', '6.3': '8.1', '6.2': '8', '6.1': '7' }
    os = `Windows ${map[m[1] ?? ''] ?? m[1]}`
  } else if ((m = ua.match(/Mac OS X\s([\d_.]+)/))) {
    os = `macOS ${(m[1] ?? '').replace(/_/g, '.')}`
    model = 'Mac'
  } else if (/CrOS/.test(ua)) {
    os = 'ChromeOS'
  } else if (/Linux/.test(ua)) {
    os = 'Linux'
  }
  if (!model) {
    if ((m = ua.match(/(Edg|OPR|YaBrowser|Firefox|Chrome|Version)\/([\d]+)/))) {
      const names: Record<string, string> = { Edg: 'Edge', OPR: 'Opera', Version: 'Safari' }
      model = `${names[m[1] ?? ''] ?? m[1]} ${m[2]}`
    } else model = 'Browser'
  }
  return { os: os || 'unknown', model }
}

type UAData = { platform?: string; mobile?: boolean }

export function collectDevice(): DeviceHello {
  const ua = typeof navigator !== 'undefined' ? navigator.userAgent : ''
  const parsed = parseUserAgent(ua)
  const uaData = (typeof navigator !== 'undefined'
    ? (navigator as Navigator & { userAgentData?: UAData }).userAgentData
    : undefined)
  let os = parsed.os
  if (os === 'unknown' && uaData?.platform) os = uaData.platform
  const scr = typeof screen !== 'undefined' ? `${screen.width}x${screen.height}` : ''
  return { platform: 'web', model: parsed.model, os, appVersion: __APP_VERSION__, userAgent: ua, screen: scr }
}
