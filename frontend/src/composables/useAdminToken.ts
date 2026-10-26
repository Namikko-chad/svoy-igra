import { useRouter } from 'vue-router'
import { session } from '@/stores/session'
import { useToastStore } from '@/stores/toast'
import { ApiError, errorMessage } from '@/api/http'

/**
 * Admin REST pages of a game: the admin token from storage (missing → back to `/g/:pin`);
 * `handleError` turns 401/403 into a re-join and everything else into a toast.
 */
export function useAdminToken(pin: string) {
  const router = useRouter()
  const toast = useToastStore()
  const token = session.get(pin, 'admin')?.token ?? null
  if (!token) void router.replace(`/g/${pin}`)

  function handleError(e: unknown) {
    if (e instanceof ApiError && (e.status === 401 || e.status === 403)) {
      session.forget(pin, 'admin')
      toast.error('Войдите как администратор')
      void router.replace(`/g/${pin}`)
      return
    }
    toast.error(errorMessage(e))
  }
  return { token, handleError }
}
