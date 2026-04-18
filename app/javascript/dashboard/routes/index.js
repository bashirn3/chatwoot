import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import AnalyticsHelper from '../helper/AnalyticsHelper';

const routes = [...dashboard.routes];

export const router = createRouter({ history: createWebHistory(), routes });

// After a fresh deploy, tabs opened before the deploy still hold references
// to the previous chunk manifest. Client-side navigation to a route whose
// component is lazy-loaded will then 404 on the stale chunk URL and the page
// renders blank until a full refresh. Detect that class of error and hard-
// reload the target URL so the browser fetches the new manifest.
router.onError((err, to) => {
  const message = (err && err.message) || '';
  const isChunkFailure =
    /Loading chunk [\d]+ failed/i.test(message) ||
    /Failed to fetch dynamically imported module/i.test(message) ||
    err?.name === 'ChunkLoadError';
  if (!isChunkFailure) return;
  const target = to?.fullPath || window.location.pathname;
  window.location.assign(target);
});

const shouldShowOnboarding = (user, accountId) => {
  if (!user || !accountId) return false;
  if (user.inviter_id) return false;
  const account = (user.accounts || []).find(
    a => Number(a.id) === Number(accountId)
  );
  if (!account || account.role !== 'administrator') return false;
  try {
    const key = `cw_onboarding_done_${user.id}_${accountId}`;
    if (window.localStorage.getItem(key) === 'true') return false;
  } catch (_e) {
    return false;
  }
  return true;
};

export const validateAuthenticateRoutePermission = (to, next) => {
  const { isLoggedIn, getCurrentUser: user } = store.getters;

  if (!isLoggedIn) {
    window.location.assign('/app/login');
    return '';
  }

  const { accounts = [], account_id: accountId } = user;

  if (!accounts.length) {
    if (to.name === 'no_accounts') {
      return next();
    }
    return next(frontendURL('no-accounts'));
  }

  if (to.name === 'no_accounts' || !to.name) {
    if (shouldShowOnboarding(user, accountId)) {
      return next(frontendURL(`accounts/${accountId}/onboarding/country`));
    }
    return next(frontendURL(`accounts/${accountId}/dashboard`));
  }

  const nextRoute = validateLoggedInRoutes(to, store.getters.getCurrentUser);
  return nextRoute ? next(frontendURL(nextRoute)) : next();
};

export const initalizeRouter = () => {
  const userAuthentication = store.dispatch('setUser');

  router.beforeEach((to, _from, next) => {
    AnalyticsHelper.page(to.name || '', {
      path: to.path,
      name: to.name,
    });

    userAuthentication.then(() => {
      return validateAuthenticateRoutePermission(to, next, store);
    });
  });
};

export default router;
