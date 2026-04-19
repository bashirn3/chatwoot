import { frontendURL } from '../../../helper/URLHelper';
import OnboardingShell from './OnboardingShell.vue';
import CountryPicker from './CountryPicker.vue';
import Provisioning from './Provisioning.vue';
import HookUp from './HookUp.vue';
import AllSet from './AllSet.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/onboarding'),
    component: OnboardingShell,
    children: [
      {
        path: '',
        name: 'onboarding_root',
        redirect: to => ({
          name: 'onboarding_country',
          params: { accountId: to.params.accountId },
        }),
      },
      {
        path: 'country',
        name: 'onboarding_country',
        component: CountryPicker,
        meta: {
          showSkip: true,
          permissions: ['administrator'],
        },
      },
      {
        path: 'provisioning',
        name: 'onboarding_provisioning',
        component: Provisioning,
        meta: {
          showSkip: false,
          permissions: ['administrator'],
        },
      },
      {
        path: 'hookup',
        name: 'onboarding_hookup',
        component: HookUp,
        meta: {
          showSkip: true,
          permissions: ['administrator'],
        },
      },
      {
        path: 'done',
        name: 'onboarding_done',
        component: AllSet,
        meta: {
          showSkip: false,
          permissions: ['administrator'],
        },
      },
    ],
  },
];

export default { routes };
