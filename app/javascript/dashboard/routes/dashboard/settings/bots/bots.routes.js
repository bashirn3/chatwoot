import { frontendURL } from '../../../../helper/URLHelper';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const BotsIndex = () => import('./Index.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/bots'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_bots',
          meta: {
            permissions: ['administrator'],
          },
          component: BotsIndex,
        },
      ],
    },
  ],
};
