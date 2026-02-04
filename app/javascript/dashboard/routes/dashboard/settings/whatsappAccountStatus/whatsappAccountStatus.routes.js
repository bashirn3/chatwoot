import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import WhatsAppAccountStatusIndex from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/whatsapp-account-status'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'settings_whatsapp_account_status', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'settings_whatsapp_account_status',
          component: WhatsAppAccountStatusIndex,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
