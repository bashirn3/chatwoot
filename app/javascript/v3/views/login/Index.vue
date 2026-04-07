<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';

// components
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import ClerkOAuthButton from '../../components/ClerkOauth/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';

export default {
  components: {
    GoogleOAuthButton,
    ClerkOAuthButton,
    Spinner,
    MfaVerification,
    Icon,
  },
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
      showPassword: false,
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    allowedLoginMethods() {
      return window.chatwootConfig.allowedLoginMethods || ['email'];
    },
    showGoogleOAuth() {
      return (
        this.allowedLoginMethods.includes('google_oauth') &&
        Boolean(window.chatwootConfig.googleOAuthClientId)
      );
    },
    showSignupLink() {
      return window.chatwootConfig.signupEnabled === 'true';
    },
    showSamlLogin() {
      return this.allowedLoginMethods.includes('saml');
    },
    showClerkLogin() {
      return (
        this.allowedLoginMethods.includes('clerk') &&
        Boolean(window.chatwootConfig.clerkPublishableKey)
      );
    },
    showOAuthDivider() {
      return this.showGoogleOAuth || this.showSamlLogin || this.showClerkLogin;
    },
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
    if (this.authError) {
      const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
      const translatedMessage = this.getTranslatedMessage(messageKey);
      useAlert(translatedMessage);
      this.requestIdleCallbackPolyfill(() => {
        const { query } = this.$route;
        this.$router.replace({ query: { ...query, error: undefined } });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
      };

      login(credentials)
        .then(result => {
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            return;
          }
          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          if (this.email) {
            window.location = '/app/login';
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }
      this.submitLogin();
    },
    handleMfaVerified() {
      this.handleImpersonation();
      window.location = '/app';
    },
    handleMfaCancel() {
      this.mfaRequired = false;
      this.mfaToken = null;
      this.credentials.password = '';
    },
  },
};
</script>

<template>
  <div class="auth-page">
    <div class="auth-overlay" />

    <div class="auth-card" :class="{ 'auth-card--error': loginApi.hasErrored }">
      <!-- Brand -->
      <div class="auth-brand">{{ $t('LOGIN.BRAND_NAME') }}</div>

      <!-- MFA Verification -->
      <div v-if="mfaRequired" class="auth-mfa">
        <MfaVerification
          :mfa-token="mfaToken"
          @verified="handleMfaVerified"
          @cancel="handleMfaCancel"
        />
      </div>

      <!-- Main login form -->
      <template v-else>
        <h3 class="auth-title">
          {{ replaceInstallationName($t('LOGIN.TITLE')) }}
        </h3>

        <!-- SSO loading spinner -->
        <div v-if="email" class="auth-spinner">
          <Spinner color-scheme="primary" size="" />
        </div>

        <div v-else class="auth-body">
          <!-- OAuth buttons -->
          <div v-if="showOAuthDivider" class="auth-oauth">
            <GoogleOAuthButton v-if="showGoogleOAuth" class="auth-oauth-btn" />
            <ClerkOAuthButton v-if="showClerkLogin" class="auth-oauth-btn" />
            <router-link
              v-if="showSamlLogin"
              to="/app/login/sso"
              class="auth-saml-btn"
            >
              <Icon icon="i-lucide-lock-keyhole" class="auth-saml-icon" />
              <span>{{ $t('LOGIN.SAML.LABEL') }}</span>
            </router-link>
            <div class="auth-or-divider">
              <span>{{ $t('COMMON.OR') }}</span>
            </div>
          </div>

          <!-- Email / Password form -->
          <form class="auth-form" @submit.prevent="submitFormLogin">
            <div class="auth-field">
              <input
                v-model="credentials.email"
                type="email"
                name="email_address"
                data-testid="email_input"
                :tabindex="1"
                required
                :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
                class="auth-input"
                :class="{ 'auth-input--error': v$.credentials.email.$error }"
                @input="v$.credentials.email.$touch"
              />
            </div>

            <div class="auth-field">
              <input
                v-model="credentials.password"
                :type="showPassword ? 'text' : 'password'"
                name="password"
                data-testid="password_input"
                :tabindex="2"
                required
                :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
                class="auth-input"
                :class="{ 'auth-input--error': v$.credentials.password.$error }"
                @input="v$.credentials.password.$touch"
              />
              <button
                type="button"
                class="auth-field-icon"
                @click="showPassword = !showPassword"
              >
                <Icon
                  :icon="showPassword ? 'i-lucide-eye-off' : 'i-lucide-eye'"
                  class="size-4"
                />
              </button>
            </div>

            <button
              type="submit"
              data-testid="submit_button"
              class="auth-btn"
              :tabindex="3"
              :disabled="loginApi.showLoading"
            >
              <span v-if="loginApi.showLoading" class="auth-btn-spinner" />
              <span v-else>{{ $t('LOGIN.SUBMIT') }}</span>
            </button>
          </form>

          <!-- Links -->
          <div class="auth-links">
            <router-link
              v-if="showSignupLink"
              to="auth/signup"
              class="auth-link"
            >
              {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
            </router-link>
            <router-link
              v-if="!globalConfig.disableUserProfileUpdate"
              to="auth/reset/password"
              class="auth-link auth-link--muted"
              :tabindex="4"
            >
              {{ $t('LOGIN.FORGOT_PASSWORD') }}
            </router-link>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* ── Page shell ── */
.auth-page {
  position: relative;
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #000;
  overflow: hidden;
  font-family: inherit;
}

.auth-page::before {
  content: '';
  position: absolute;
  inset: 0;
  background: radial-gradient(
      ellipse 80% 60% at 50% 0%,
      rgba(34, 197, 94, 0.15) 0%,
      transparent 70%
    ),
    radial-gradient(
      ellipse 60% 40% at 80% 100%,
      rgba(34, 197, 94, 0.08) 0%,
      transparent 60%
    );
  pointer-events: none;
}

.auth-overlay {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    160deg,
    rgba(0, 0, 0, 0.85) 0%,
    rgba(0, 0, 0, 0.65) 50%,
    rgba(0, 0, 0, 0.85) 100%
  );
  z-index: 0;
}

/* ── Card ── */
.auth-card {
  position: relative;
  z-index: 1;
  width: 100%;
  max-width: 420px;
  padding: 2.5rem 2rem;
  background: rgba(255, 255, 255, 0.04);
  backdrop-filter: blur(24px);
  -webkit-backdrop-filter: blur(24px);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 20px;
  display: flex;
  flex-direction: column;
  align-items: center;
  animation: auth-fade-in 0.5s ease-out;
  margin: 1rem;
}

.auth-card--error {
  animation: auth-wiggle 0.4s ease-in-out;
}

/* ── Brand ── */
.auth-brand {
  font-size: 1.6rem;
  font-weight: 700;
  letter-spacing: 0.12em;
  color: #22c55e;
  margin-bottom: 1.25rem;
  text-transform: uppercase;
}

/* ── Title ── */
.auth-title {
  font-size: 1.1rem;
  font-weight: 300;
  color: rgba(255, 255, 255, 0.8);
  margin: 0 0 1.5rem 0;
  letter-spacing: -0.01em;
  text-align: center;
}

/* ── Body ── */
.auth-body {
  width: 100%;
}

.auth-spinner {
  display: flex;
  justify-content: center;
  padding: 2rem 0;
}

.auth-mfa {
  width: 100%;
}

/* ── OAuth section ── */
.auth-oauth {
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
  margin-bottom: 0.5rem;
  width: 100%;
}

.auth-oauth-btn {
  width: 100%;
}

.auth-saml-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  height: 46px;
  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 40px;
  background: rgba(255, 255, 255, 0.04);
  color: #fff;
  font-size: 0.875rem;
  text-decoration: none;
  transition:
    background 0.2s,
    border-color 0.2s;
}

.auth-saml-btn:hover {
  background: rgba(255, 255, 255, 0.1);
  border-color: rgba(255, 255, 255, 0.3);
}

.auth-saml-icon {
  width: 1.1rem;
  height: 1.1rem;
  color: rgba(255, 255, 255, 0.6);
}

.auth-or-divider {
  position: relative;
  text-align: center;
  margin: 0.25rem 0;
  color: rgba(255, 255, 255, 0.3);
  font-size: 0.75rem;
  letter-spacing: 0.05em;
}

.auth-or-divider::before,
.auth-or-divider::after {
  content: '';
  position: absolute;
  top: 50%;
  width: calc(50% - 1.5rem);
  height: 1px;
  background: rgba(255, 255, 255, 0.12);
}

.auth-or-divider::before {
  left: 0;
}

.auth-or-divider::after {
  right: 0;
}

/* ── Form ── */
.auth-form {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
}

.auth-field {
  position: relative;
  width: 100%;
}

.auth-input {
  width: 100%;
  height: 50px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid transparent;
  border-radius: 40px;
  padding: 0 3rem 0 1.3rem;
  color: #fff;
  font-size: 0.9rem;
  outline: none;
  transition:
    border-color 0.3s,
    background 0.3s;
  font-family: inherit;
  box-sizing: border-box;
}

.auth-input::placeholder {
  color: rgba(255, 255, 255, 0.4);
}

.auth-input:focus {
  border-color: rgba(34, 197, 94, 0.5);
  background: rgba(255, 255, 255, 0.08);
}

.auth-input--error {
  border-color: rgba(239, 68, 68, 0.5);
}

.auth-field-icon {
  position: absolute;
  top: 50%;
  right: 16px;
  transform: translateY(-50%);
  background: none;
  border: none;
  color: rgba(255, 255, 255, 0.45);
  cursor: pointer;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
}

.auth-field-icon:hover {
  color: rgba(255, 255, 255, 0.8);
}

/* ── Submit button ── */
.auth-btn {
  width: 100%;
  height: 50px;
  border: none;
  border-radius: 40px;
  background: #22c55e;
  color: #fff;
  font-size: 0.9rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  cursor: pointer;
  transition:
    background 0.3s,
    transform 0.15s,
    box-shadow 0.3s;
  font-family: inherit;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-top: 0.25rem;
  box-shadow: 0 0 20px rgba(34, 197, 94, 0.2);
}

.auth-btn:hover:not(:disabled) {
  background: #16a34a;
  transform: translateY(-1px);
  box-shadow: 0 0 30px rgba(34, 197, 94, 0.35);
}

.auth-btn:active:not(:disabled) {
  transform: translateY(0);
}

.auth-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.auth-btn-spinner {
  width: 18px;
  height: 18px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top-color: #fff;
  border-radius: 50%;
  animation: auth-spin 0.7s linear infinite;
}

/* ── Links ── */
.auth-links {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  margin-top: 1.2rem;
  width: 100%;
}

.auth-link {
  color: #4ade80;
  font-size: 0.8rem;
  text-decoration: none;
  transition: color 0.2s;
}

.auth-link:hover {
  color: #fff;
}

.auth-link--muted {
  color: rgba(255, 255, 255, 0.4);
}

.auth-link--muted:hover {
  color: rgba(255, 255, 255, 0.7);
}

/* ── Animations ── */
@keyframes auth-fade-in {
  from {
    opacity: 0;
    transform: translateY(16px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes auth-wiggle {
  0%,
  100% {
    transform: translateX(0);
  }
  20% {
    transform: translateX(-6px);
  }
  40% {
    transform: translateX(6px);
  }
  60% {
    transform: translateX(-4px);
  }
  80% {
    transform: translateX(4px);
  }
}

@keyframes auth-spin {
  to {
    transform: rotate(360deg);
  }
}

/* ── Override OAuth button internals to match dark theme ── */
:deep(.auth-oauth-btn button),
:deep(.auth-oauth-btn a) {
  border-radius: 40px !important;
  background: rgba(255, 255, 255, 0.04) !important;
  border: 1px solid rgba(255, 255, 255, 0.15) !important;
  color: #fff !important;
  transition:
    background 0.2s,
    border-color 0.2s !important;
}

:deep(.auth-oauth-btn button:hover),
:deep(.auth-oauth-btn a:hover) {
  background: rgba(255, 255, 255, 0.1) !important;
  border-color: rgba(255, 255, 255, 0.3) !important;
}
</style>
