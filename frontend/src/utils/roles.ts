import type { Role } from '@/types/protocol'

export const ROLE_PATH: Record<Role, string> = { player: 'play', host: 'host', admin: 'admin', screen: 'screen' }
export const ROLE_LABEL: Record<Role, string> = {
  player: 'Игрок',
  host: 'Ведущий',
  admin: 'Администратор',
  screen: 'Экран',
}
export const rolePath = (pin: string, role: Role) => `/g/${pin}/${ROLE_PATH[role]}`
