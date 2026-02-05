import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import WhatsAppTemplatesIndex from './Index.vue';
import WhatsAppTemplatesCreate from './Create.vue';
import WhatsAppTemplatesEdit from './Edit.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/whatsapp-templates'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'settings_whatsapp_templates', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'settings_whatsapp_templates',
          component: WhatsAppTemplatesIndex,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'new',
          name: 'settings_whatsapp_templates_new',
          component: WhatsAppTemplatesCreate,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: ':templateId/edit',
          name: 'settings_whatsapp_templates_edit',
          component: WhatsAppTemplatesEdit,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
