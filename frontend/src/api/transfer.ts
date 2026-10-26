import { authHeaders, errorFromBody, ApiError } from './http'

/** `attachment; filename="x.dub"` / `filename*=UTF-8''x.dub` → file name. */
export function filenameFromDisposition(header: string | null, fallback: string): string {
  if (!header) return fallback
  const star = header.match(/filename\*\s*=\s*([^;]+)/i)
  if (star?.[1]) {
    const v = star[1].trim().replace(/^"(.*)"$/, '$1')
    const parts = v.split("''")
    try {
      return decodeURIComponent(parts.length > 1 ? parts.slice(1).join("''") : v)
    } catch {
      /* fall through */
    }
  }
  const plain = header.match(/filename\s*=\s*("((?:\\.|[^"\\])*)"|[^;]+)/i)
  if (plain) {
    const v = plain[2] !== undefined ? plain[2].replace(/\\(.)/g, '$1') : (plain[1] ?? '').trim()
    if (v) return v
  }
  return fallback
}

/** GET with Bearer → save the response as a file (name from Content-Disposition). */
export async function downloadWithAuth(path: string, token: string | null, fallbackName: string): Promise<void> {
  let res: Response
  try {
    res = await fetch(path, { headers: authHeaders(token) })
  } catch {
    throw new ApiError(0, 'network', 'Нет связи с сервером')
  }
  if (!res.ok) throw errorFromBody(res.status, await res.text().catch(() => ''))
  const blob = await res.blob()
  const name = filenameFromDisposition(res.headers.get('Content-Disposition'), fallbackName)
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = name
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 10_000)
}

export type UploadHandle<T> = { promise: Promise<T>; abort: () => void }

/** Multipart upload via XMLHttpRequest so the caller gets upload progress (0..1). */
export function uploadWithProgress<T>(
  path: string,
  token: string | null,
  form: FormData,
  onProgress?: (fraction: number) => void,
): UploadHandle<T> {
  const xhr = new XMLHttpRequest()
  const promise = new Promise<T>((resolve, reject) => {
    xhr.open('POST', path)
    for (const [k, v] of Object.entries(authHeaders(token))) xhr.setRequestHeader(k, v)
    xhr.setRequestHeader('Accept', 'application/json')
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress(e.loaded / e.total)
    }
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        onProgress?.(1)
        try {
          resolve((xhr.responseText ? JSON.parse(xhr.responseText) : undefined) as T)
        } catch {
          resolve(undefined as T)
        }
      } else reject(errorFromBody(xhr.status, xhr.responseText))
    }
    xhr.onerror = () => reject(new ApiError(0, 'network', 'Нет связи с сервером'))
    xhr.onabort = () => reject(new ApiError(0, 'aborted', 'Загрузка отменена'))
    xhr.send(form)
  })
  return { promise, abort: () => xhr.abort() }
}
