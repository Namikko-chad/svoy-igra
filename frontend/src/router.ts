import { createRouter, createWebHistory } from 'vue-router'
import { isGamePin } from '@/utils/pin'

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: () => import('@/pages/LandingPage.vue'), meta: { title: 'Своя игра' } },
    {
      path: '/g/:pin',
      beforeEnter: (to) => (isGamePin(String(to.params.pin)) ? true : '/'),
      children: [
        { path: '', component: () => import('@/pages/JoinPage.vue'), props: true, meta: { title: 'Вход в игру — Своя игра' } },
        { path: 'play', component: () => import('@/pages/PlayPage.vue'), props: true, meta: { title: 'Игрок — Своя игра' } },
        { path: 'host', component: () => import('@/pages/HostPage.vue'), props: true, meta: { title: 'Ведущий — Своя игра' } },
        { path: 'screen', component: () => import('@/pages/ScreenPage.vue'), props: true, meta: { title: 'Экран — Своя игра' } },
        { path: 'admin', component: () => import('@/pages/AdminPage.vue'), props: true, meta: { title: 'Администратор — Своя игра' } },
        {
          path: 'admin/packs',
          component: () => import('@/pages/PackLibraryPage.vue'),
          props: true,
          meta: { title: 'Паки — Своя игра' },
        },
        {
          path: 'admin/packs/:id',
          component: () => import('@/pages/PackEditorPage.vue'),
          props: true,
          meta: { title: 'Редактор пака — Своя игра' },
        },
      ],
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})

router.afterEach((to) => {
  if (typeof to.meta.title === 'string') document.title = to.meta.title
})
