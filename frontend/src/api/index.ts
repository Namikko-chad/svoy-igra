import { request } from './http'
import { uploadWithProgress, downloadWithAuth } from './transfer'
import type { Category, GameInfo, JoinResult, Media, Pack, PackSummary, Question, QuestionInput, Role, Round, RoundKind } from '@/types/protocol'

const enc = encodeURIComponent

export const authApi = {
  me: (token: string) => request<Omit<JoinResult, 'token'>>('/api/auth/me', { token }),
}

export const gamesApi = {
  create: (adminPin: string, title?: string) =>
    request<JoinResult>('/api/games', { method: 'POST', body: title ? { adminPin, title } : { adminPin } }),
  get: (pin: string) => request<GameInfo>(`/api/games/${enc(pin)}`),
  join: (pin: string, body: { role: Role; name?: string; adminPin?: string }) =>
    request<JoinResult>(`/api/games/${enc(pin)}/join`, { method: 'POST', body }),
}

export function avatarApi(token: string) {
  return {
    /** multipart `file`; the server answers with the new relative URL */
    upload: (image: Blob, filename: string) => {
      const form = new FormData()
      form.append('file', image, filename)
      return request<{ avatarUrl: string }>('/api/avatar', { method: 'POST', token, body: form })
    },
    remove: () => request<void>('/api/avatar', { method: 'DELETE', token }),
  }
}

export const infoApi = {
  info: () => request<{ name: string; version: string; serverNow: number; webUrl: string | null }>('/api/info'),
}

export function packsApi(token: string | null) {
  const p = (id: string) => `/api/packs/${enc(id)}`
  return {
    list: () => request<PackSummary[]>('/api/packs', { token }),
    create: (title: string) => request<Pack>('/api/packs', { method: 'POST', token, body: { title } }),
    get: (id: string) => request<Pack>(p(id), { token }),
    update: (id: string, body: { title?: string; author?: string; description?: string }) =>
      request<PackSummary>(p(id), { method: 'PATCH', token, body }),
    remove: (id: string) => request<void>(p(id), { method: 'DELETE', token }),
    importDub: (file: File, onProgress?: (f: number) => void) => {
      const form = new FormData()
      form.append('file', file)
      return uploadWithProgress<PackSummary>('/api/packs/import', token, form, onProgress)
    },
    copy: (id: string, title: string) => request<Pack>(`${p(id)}/copy`, { method: 'POST', token, body: { title } }),
    lock: (id: string) => request<PackSummary>(`${p(id)}/lock`, { method: 'POST', token }),
    exportDub: (id: string, title: string) => downloadWithAuth(`${p(id)}/export`, token, `${title || 'pack'}.dub`),

    addRound: (id: string, name: string, kind: RoundKind = 'normal') =>
      request<Round>(`${p(id)}/rounds`, { method: 'POST', token, body: { name, kind } }),
    updateRound: (id: string, roundId: number, body: { name?: string; position?: number; kind?: RoundKind }) =>
      request<Round>(`${p(id)}/rounds/${roundId}`, { method: 'PATCH', token, body }),
    removeRound: (id: string, roundId: number) =>
      request<void>(`${p(id)}/rounds/${roundId}`, { method: 'DELETE', token }),

    addCategory: (id: string, roundId: number, name: string) =>
      request<Category>(`${p(id)}/rounds/${roundId}/categories`, { method: 'POST', token, body: { name } }),
    updateCategory: (id: string, categoryId: number, body: { name?: string; position?: number }) =>
      request<Category>(`${p(id)}/categories/${categoryId}`, { method: 'PATCH', token, body }),
    removeCategory: (id: string, categoryId: number) =>
      request<void>(`${p(id)}/categories/${categoryId}`, { method: 'DELETE', token }),

    addQuestion: (id: string, categoryId: number, body: QuestionInput) =>
      request<Question>(`${p(id)}/categories/${categoryId}/questions`, { method: 'POST', token, body }),
    updateQuestion: (id: string, questionId: number, body: QuestionInput & { position?: number }) =>
      request<Question>(`${p(id)}/questions/${questionId}`, { method: 'PATCH', token, body }),
    removeQuestion: (id: string, questionId: number) =>
      request<void>(`${p(id)}/questions/${questionId}`, { method: 'DELETE', token }),

    uploadMedia: (id: string, file: File, name?: string, onProgress?: (f: number) => void) => {
      const form = new FormData()
      // `name` first so a streaming multipart reader sees it before the file body.
      if (name) form.append('name', name)
      form.append('file', file)
      return uploadWithProgress<Media>(`${p(id)}/media`, token, form, onProgress)
    },
    removeMedia: (id: string, name: string) =>
      request<void>(`${p(id)}/media/${enc(name)}`, { method: 'DELETE', token }),
  }
}

export function gameApi(token: string | null) {
  return {
    exportGame: () => downloadWithAuth('/api/game/export', token, 'game.json'),
    importGame: (file: File) => {
      const form = new FormData()
      form.append('file', file)
      return request<void>('/api/game/import', { method: 'POST', token, body: form })
    },
  }
}
