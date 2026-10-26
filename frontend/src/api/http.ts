import type { ApiErrorBody } from '@/types/protocol'

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message)
    this.name = 'ApiError'
  }
}

/** Turns a non-2xx body into an ApiError using `{error:{code,message}}` when present. */
export function errorFromBody(status: number, text: string): ApiError {
  try {
    const body = JSON.parse(text) as Partial<ApiErrorBody>
    if (body?.error?.message) return new ApiError(status, body.error.code ?? 'error', body.error.message)
  } catch {
    /* not JSON */
  }
  if (status === 0) return new ApiError(0, 'network', 'Нет связи с сервером')
  return new ApiError(status, 'http_' + status, `Ошибка сервера (${status})`)
}

export function authHeaders(token: string | null | undefined): Record<string, string> {
  return token ? { Authorization: `Bearer ${token}` } : {}
}

export type RequestOptions = {
  method?: string
  token?: string | null
  body?: unknown
  signal?: AbortSignal
}

export async function request<T>(path: string, opts: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json', ...authHeaders(opts.token) }
  let body: BodyInit | undefined
  if (opts.body instanceof FormData) body = opts.body
  else if (opts.body !== undefined) {
    headers['Content-Type'] = 'application/json'
    body = JSON.stringify(opts.body)
  }
  let res: Response
  try {
    res = await fetch(path, { method: opts.method ?? 'GET', headers, body, signal: opts.signal })
  } catch (e) {
    if ((e as Error).name === 'AbortError') throw e
    throw new ApiError(0, 'network', 'Нет связи с сервером')
  }
  if (!res.ok) throw errorFromBody(res.status, await res.text().catch(() => ''))
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

export function errorMessage(e: unknown): string {
  if (e instanceof ApiError) return e.message
  if (e instanceof Error) return e.message
  return String(e)
}
