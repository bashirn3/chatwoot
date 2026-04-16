import { frontendURL } from '../../../../helper/URLHelper';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const WhatsAppConnectionIndex = () => import('./Index.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/whatsapp-connection'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_whatsapp_connection',
          meta: {
            permissions: ['administrator'],
          },
          component: WhatsAppConnectionIndex,
        },
      ],
    },
  ],
};
