<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import Spinner from 'shared/components/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

export default {
  components: {
    Spinner,
    NextButton,
    Icon,
  },
  data() {
    return {
      isLoading: true,
      isVerifying: false,
      clerk: null,
      showOrgPicker: false,
      organizations: [],
      clerkUserId: null,
      error: null,
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    publishableKey() {
      return window.chatwootConfig.clerkPublishableKey || '';
    },
  },
  mounted() {
    if (!this.publishableKey) {
      this.error = this.$t('LOGIN.CLERK.NOT_CONFIGURED');
      this.isLoading = false;
      return;
    }
    this.loadClerkJS();
  },
  beforeUnmount() {
    if (this.clerk) {
      this.clerk.unmountSignIn(this.$refs.clerkSignIn);
    }
  },
  methods: {
    async loadClerkJS() {
      try {
        // Extract the Clerk frontend API domain from the publishable key
        const frontendApi = this.extractFrontendApi(this.publishableKey);
        if (!frontendApi) {
          this.error = this.$t('LOGIN.CLERK.INVALID_KEY');
          this.isLoading = false;
          return;
        }

        // Load ClerkJS from Clerk's CDN with the publishable key attribute
        const cdnUrl = `https://${frontendApi}/npm/@clerk/clerk-js@latest/dist/clerk.browser.js`;
        await this.loadScript(cdnUrl, this.publishableKey);

        // Wait for Clerk instance to exist, then wait for it to fully load
        await this.waitForClerk();
        await this.clerk.load();

        const SIGNING_IN_KEY = 'clerk_signing_in';

        // If returning from OAuth redirect with an active session, verify it
        if (this.clerk.session && sessionStorage.getItem(SIGNING_IN_KEY)) {
          sessionStorage.removeItem(SIGNING_IN_KEY);
          await this.handleClerkSession();
          return;
        }

        // Otherwise, sign out any existing session so users always see provider choices
        if (this.clerk.session) {
          await this.clerk.signOut();
        }

        sessionStorage.setItem(SIGNING_IN_KEY, 'true');
        this.isLoading = false;
        this.mountSignIn();
      } catch (e) {
        // eslint-disable-next-line no-console
        console.error('Clerk load error:', e);
        this.error = this.$t('LOGIN.CLERK.LOAD_ERROR');
        this.isLoading = false;
      }
    },
    waitForClerk() {
      return new Promise((resolve, reject) => {
        const maxWait = 10000;
        const interval = 100;
        let elapsed = 0;

        const check = () => {
          // Wait for the Clerk instance to be set on window
          if (window.Clerk && typeof window.Clerk === 'object') {
            this.clerk = window.Clerk;
            resolve();
            return;
          }
          elapsed += interval;
          if (elapsed >= maxWait) {
            reject(new Error('Clerk initialization timed out'));
            return;
          }
          setTimeout(check, interval);
        };
        check();
      });
    },
    extractFrontendApi(key) {
      // Clerk publishable keys encode the frontend API
      // Format: pk_test_<base64> or pk_live_<base64>
      try {
        const parts = key.split('_');
        if (parts.length < 3) return null;
        const encoded = parts.slice(2).join('_');
        const decoded = atob(encoded);
        // Strip trailing $ or . that Clerk appends to the encoded domain
        return decoded.replace(/[.$]+$/, '');
      } catch {
        return null;
      }
    },
    loadScript(src, publishableKey) {
      return new Promise((resolve, reject) => {
        if (window.Clerk) {
          resolve();
          return;
        }
        const script = document.createElement('script');
        script.src = src;
        script.crossOrigin = 'anonymous';
        script.async = true;
        script.setAttribute('data-clerk-publishable-key', publishableKey);
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
      });
    },
    mountSignIn() {
      this.$nextTick(() => {
        if (!this.$refs.clerkSignIn) return;
        this.clerk.mountSignIn(this.$refs.clerkSignIn, {
          afterSignInUrl: window.location.href,
          appearance: {
            elements: {
              rootBox: 'w-full',
              card: 'shadow-none w-full',
            },
          },
        });
        // Listen for session changes
        this.clerk.addListener(({ session }) => {
          if (session) {
            this.handleClerkSession();
          }
        });
      });
    },
    async handleClerkSession() {
      this.isVerifying = true;
      try {
        const token = await this.clerk.session.getToken();
        const response = await this.verifyWithBackend(token);

        if (response.multi_org) {
          this.organizations = response.organizations;
          this.clerkUserId = response.clerk_user_id;
          this.showOrgPicker = true;
          this.isVerifying = false;
        } else {
          this.redirectToLogin(response.email, response.sso_auth_token);
        }
      } catch (e) {
        this.isVerifying = false;
        useAlert(e.message || this.$t('LOGIN.CLERK.VERIFY_ERROR'));
      }
    },
    async verifyWithBackend(token) {
      const csrfToken = document
        .querySelector('meta[name="csrf-token"]')
        ?.getAttribute('content');

      const response = await fetch('/api/v1/auth/clerk/verify', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken || '',
        },
        body: JSON.stringify({ token }),
      });

      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(data.error || this.$t('LOGIN.CLERK.VERIFY_ERROR'));
      }

      return response.json();
    },
    async selectOrganization(org) {
      this.isVerifying = true;
      try {
        const csrfToken = document
          .querySelector('meta[name="csrf-token"]')
          ?.getAttribute('content');

        const response = await fetch('/api/v1/auth/clerk/select_org', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrfToken || '',
          },
          body: JSON.stringify({
            clerk_user_id: this.clerkUserId,
            clerk_org_id: org.id,
          }),
        });

        if (!response.ok) {
          const data = await response.json().catch(() => ({}));
          throw new Error(data.error || this.$t('LOGIN.CLERK.VERIFY_ERROR'));
        }

        const data = await response.json();
        this.redirectToLogin(data.email, data.sso_auth_token);
      } catch (e) {
        this.isVerifying = false;
        useAlert(e.message || this.$t('LOGIN.CLERK.VERIFY_ERROR'));
      }
    },
    redirectToLogin(email, ssoAuthToken) {
      const loginUrl = `/app/login?email=${email}&sso_auth_token=${ssoAuthToken}`;
      window.location = loginUrl;
    },
    goBack() {
      this.$router.push('/app/login');
    },
  },
};
</script>

<template>
  <main
    class="flex flex-col w-full min-h-screen py-20 bg-n-brand/5 dark:bg-n-background sm:px-6 lg:px-8"
  >
    <section class="max-w-5xl mx-auto">
      <img
        :src="globalConfig.logo"
        :alt="globalConfig.installationName"
        class="block w-auto h-8 mx-auto dark:hidden"
      />
      <img
        v-if="globalConfig.logoDark"
        :src="globalConfig.logoDark"
        :alt="globalConfig.installationName"
        class="hidden w-auto h-8 mx-auto dark:block"
      />
      <h2 class="mt-6 text-3xl font-medium text-center text-n-slate-12">
        {{ $t('LOGIN.CLERK.TITLE') }}
      </h2>
      <p class="mt-3 text-sm text-center text-n-slate-11">
        <button
          type="button"
          class="lowercase text-link text-n-brand cursor-pointer"
          @click="goBack"
        >
          {{ $t('LOGIN.CLERK.BACK_TO_LOGIN') }}
        </button>
      </p>
    </section>

    <!-- Loading state -->
    <section
      v-if="isLoading || isVerifying"
      class="bg-white shadow sm:mx-auto mt-11 sm:w-full sm:max-w-lg dark:bg-n-solid-2 p-11 sm:shadow-lg sm:rounded-lg"
    >
      <div class="flex flex-col items-center justify-center gap-4">
        <Spinner color-scheme="primary" size="" />
        <p class="text-sm text-n-slate-11">
          {{
            isVerifying
              ? $t('LOGIN.CLERK.VERIFYING')
              : $t('LOGIN.CLERK.LOADING')
          }}
        </p>
      </div>
    </section>

    <!-- Error state -->
    <section
      v-else-if="error"
      class="bg-white shadow sm:mx-auto mt-11 sm:w-full sm:max-w-lg dark:bg-n-solid-2 p-11 sm:shadow-lg sm:rounded-lg"
    >
      <div class="flex flex-col items-center justify-center gap-4">
        <Icon icon="i-lucide-alert-circle" class="size-10 text-n-ruby-9" />
        <p class="text-sm text-n-slate-11 text-center">
          {{ error }}
        </p>
        <NextButton
          sm
          :label="$t('LOGIN.CLERK.BACK_TO_LOGIN')"
          @click="goBack"
        />
      </div>
    </section>

    <!-- Organization picker -->
    <section
      v-else-if="showOrgPicker"
      class="bg-white shadow sm:mx-auto mt-11 sm:w-full sm:max-w-lg dark:bg-n-solid-2 p-11 sm:shadow-lg sm:rounded-lg"
    >
      <h3 class="text-lg font-medium text-n-slate-12 mb-2">
        {{ $t('LOGIN.CLERK.ORG_PICKER.TITLE') }}
      </h3>
      <p class="text-sm text-n-slate-11 mb-6">
        {{ $t('LOGIN.CLERK.ORG_PICKER.SUBTITLE') }}
      </p>
      <div class="flex flex-col gap-3">
        <button
          v-for="org in organizations"
          :key="org.id"
          type="button"
          class="flex items-center gap-3 w-full px-4 py-3 text-left bg-n-background dark:bg-n-solid-3 rounded-lg ring-1 ring-inset ring-n-container hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2 transition-colors"
          @click="selectOrganization(org)"
        >
          <div
            class="flex items-center justify-center w-10 h-10 rounded-lg bg-n-brand/10 text-n-brand"
          >
            <Icon icon="i-lucide-building-2" class="size-5" />
          </div>
          <div class="flex flex-col">
            <span class="text-sm font-medium text-n-slate-12">
              {{ org.name }}
            </span>
            <span v-if="org.slug" class="text-xs text-n-slate-10">
              {{ org.slug }}
            </span>
          </div>
          <Icon
            icon="i-lucide-chevron-right"
            class="ml-auto size-4 text-n-slate-10"
          />
        </button>
      </div>
    </section>

    <!-- Clerk Sign In component mount point -->
    <section
      v-else
      class="bg-white shadow sm:mx-auto mt-11 sm:w-full sm:max-w-lg dark:bg-n-solid-2 p-11 sm:shadow-lg sm:rounded-lg"
    >
      <div ref="clerkSignIn" />
    </section>
  </main>
</template>
