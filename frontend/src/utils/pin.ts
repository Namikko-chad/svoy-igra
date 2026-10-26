/** Game PIN: exactly 6 digits. */
export const isGamePin = (s: string) => /^\d{6}$/.test(s)
/** Admin PIN: 4–8 digits. */
export const isAdminPin = (s: string) => /^\d{4,8}$/.test(s)
/** Keep digits only (paste-friendly), capped at `max`. */
export const digitsOnly = (s: string, max: number) => s.replace(/\D/g, '').slice(0, max)

/** «Открыть в приложении» intent link — protocol §8, exactly. */
export function androidIntentUrl(base: string, pin: string, link: string): string {
  return (
    `intent://join?server=${encodeURIComponent(base)}&pin=${encodeURIComponent(pin)}` +
    `#Intent;scheme=svoyigra;package=dev.svoyigra.mobile;S.browser_fallback_url=${encodeURIComponent(link)};end`
  )
}

export const isAndroid = (ua: string = typeof navigator !== 'undefined' ? navigator.userAgent : '') => /Android/i.test(ua)
