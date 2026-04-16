import { frontendURL } from '../../../../helper/URLHelper';
import { ROLES } from 'dashboard/constants/permissions.js';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const BotEditorIndex = () => import('./Index.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/bot-editor'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => ({
            name: 'settings_bot_editor',
            params: to.params,
          }),
        },
        {
          path: ':inboxId?',
          name: 'settings_bot_editor',
          meta: {
            permissions: [ROLES.ADMINISTRATOR],
          },
          component: BotEditorIndex,
          props: route => ({
            inboxId: route.params.inboxId,
          }),
        },
      ],
    },
  ],
};
