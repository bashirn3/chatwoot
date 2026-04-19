<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { DotLottieVue } from '@lottiefiles/dotlottie-vue';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';
import Button from 'dashboard/components-next/button/Button.vue';

// Replace with your production .lottie URL. Falls back to the inline SVG
// "provisioning" animation below if this is null — the page still looks
// great without a Lottie, and the SVG respects prefers-reduced-motion.
const PROVISIONING_LOTTIE_URL = null;

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const accountId = computed(() => route.params.accountId);

const ctx = ref(null);
const isQrReady = ref(false);
const pollTimer = ref(null);
const elapsedSec = ref(0);
const elapsedTimer = ref(null);
const errorMessage = ref(null);

const countryLabel = computed(() => ctx.value?.countryLabel || null);
const regionLabel = computed(() => ctx.value?.regionLabel || null);

// Three-step status ladder. "Instance created" is already true by the time
// this page mounts (CountryPicker awaited the POST). Step 2 flips when the
// first QR payload arrives. Step 3 flips as we navigate to the scan screen.
const step = computed(() => {
  if (isQrReady.value) return 3;
  if (ctx.value?.instanceName) return 2;
  return 1;
});

const showManualContinue = computed(
  () => elapsedSec.value >= 15 && !isQrReady.value
);

const clearTimers = () => {
  if (pollTimer.value) {
    clearInterval(pollTimer.value);
    pollTimer.value = null;
  }
  if (elapsedTimer.value) {
    clearInterval(elapsedTimer.value);
    elapsedTimer.value = null;
  }
};

const goToHookup = () => {
  clearTimers();
  // HookUp.bootstrap() calls getInstances() first, picks this instance up,
  // reads its region from the channel row, and polls for QR on the correct
  // regional framework. No extra state handoff needed.
  router.replace({
    name: 'onboarding_hookup',
    params: { accountId: accountId.value },
  });
};

const backToPicker = () => {
  clearTimers();
  sessionStorage.removeItem('wasup_provisioning');
  router.replace({
    name: 'onboarding_country',
    params: { accountId: accountId.value },
  });
};

const pollQrOnce = async () => {
  if (!ctx.value?.instanceName) return;
  try {
    const { data } = await WhatsAppBridgeAPI.qrCode(ctx.value.instanceName);
    if (data?.qrCode || data?.pairingCode) {
      isQrReady.value = true;
      // Tiny pause so the user sees the ✓ land before we navigate.
      setTimeout(goToHookup, 450);
      return;
    }
    if (data?.status === 'connected' || data?.status === 'open') {
      goToHookup();
    }
  } catch (err) {
    // Transient — keep polling. Only surface after the manual-continue
    // threshold is reached (user can proceed anyway then).
    errorMessage.value =
      err?.response?.data?.error ||
      err?.message ||
      t('ONBOARDING.PROVISIONING.ERROR_DEFAULT');
  }
};

onMounted(() => {
  try {
    const raw = sessionStorage.getItem('wasup_provisioning');
    ctx.value = raw ? JSON.parse(raw) : null;
  } catch (_e) {
    ctx.value = null;
  }

  if (!ctx.value?.instanceName) {
    // Direct hit on this URL without state — send user back to the map.
    backToPicker();
    return;
  }

  // Kick an immediate poll; then keep polling every 1.5s.
  pollQrOnce();
  pollTimer.value = setInterval(pollQrOnce, 1500);
  elapsedTimer.value = setInterval(() => {
    elapsedSec.value += 1;
  }, 1000);
});

onBeforeUnmount(() => {
  clearTimers();
  // Leave sessionStorage alone if we navigated successfully — HookUp may
  // want to read regionLabel for a UI chip. It's cleared on AllSet.
});
</script>

<template>
  <section
    class="mx-auto w-full max-w-[560px] flex flex-col items-center text-center gap-6"
  >
    <!-- Lottie / fallback animation -->
    <div class="size-[200px] sm:size-[220px] relative" aria-hidden="true">
      <DotLottieVue
        v-if="PROVISIONING_LOTTIE_URL"
        class="size-full"
        autoplay
        loop
        :src="PROVISIONING_LOTTIE_URL"
      />
      <!-- Inline SVG fallback. Single accent, compositor-only motion,
           respects prefers-reduced-motion. Good enough to ship even if
           you never wire in a custom .lottie. -->
      <svg
        v-else
        viewBox="0 0 220 220"
        class="size-full"
        role="img"
        :aria-label="$t('ONBOARDING.PROVISIONING.ARIA_BUSY')"
      >
        <!-- concentric rings pulsing outward -->
        <circle cx="110" cy="110" r="30" class="ring ring-1" fill="none" />
        <circle cx="110" cy="110" r="30" class="ring ring-2" fill="none" />
        <circle cx="110" cy="110" r="30" class="ring ring-3" fill="none" />
        <!-- orbit -->
        <g class="orbit">
          <circle cx="110" cy="40" r="4" class="orbit-dot" />
        </g>
        <!-- core -->
        <circle cx="110" cy="110" r="18" class="core" />
        <circle cx="110" cy="110" r="8" class="core-inner" />
      </svg>
    </div>

    <div class="flex flex-col items-center gap-2">
      <span
        class="text-[10.5px] sm:text-[11px] font-medium uppercase tracking-[0.22em] text-n-slate-11"
      >
        {{ $t('ONBOARDING.PROVISIONING.EYEBROW') }}
      </span>
      <h1
        class="text-[22px] sm:text-[28px] font-semibold tracking-tight text-balance text-n-slate-12 leading-[1.15]"
        aria-live="polite"
      >
        <template v-if="countryLabel">
          {{
            $t('ONBOARDING.PROVISIONING.TITLE_WITH_COUNTRY', {
              country: countryLabel,
            })
          }}
        </template>
        <template v-else>
          {{ $t('ONBOARDING.PROVISIONING.TITLE') }}
        </template>
      </h1>
      <p
        v-if="regionLabel"
        class="text-[13px] text-pretty text-n-slate-11 max-w-[400px]"
      >
        {{ $t('ONBOARDING.PROVISIONING.SUBTITLE', { region: regionLabel }) }}
      </p>
    </div>

    <!-- Three-step status ladder -->
    <ol
      class="flex flex-col gap-2 text-left text-[13px] w-full max-w-[320px]"
      aria-live="polite"
    >
      <li class="flex items-center gap-2.5">
        <span
          class="size-4 rounded-full inline-flex items-center justify-center shrink-0"
          :class="
            step >= 1
              ? 'bg-emerald-500 text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          <svg
            v-if="step >= 1"
            viewBox="0 0 16 16"
            class="size-2.5"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <polyline points="14 4 6 12 2 8" />
          </svg>
        </span>
        <span :class="step >= 1 ? 'text-n-slate-12' : 'text-n-slate-11'">
          {{ $t('ONBOARDING.PROVISIONING.STEPS.CREATED') }}
        </span>
      </li>
      <li class="flex items-center gap-2.5">
        <span
          class="size-4 rounded-full inline-flex items-center justify-center shrink-0"
          :class="
            step >= 2
              ? 'bg-emerald-500 text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          <svg
            v-if="step > 2"
            viewBox="0 0 16 16"
            class="size-2.5"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <polyline points="14 4 6 12 2 8" />
          </svg>
          <span v-else-if="step === 2" class="size-1.5 rounded-full bg-white" />
        </span>
        <span :class="step >= 2 ? 'text-n-slate-12' : 'text-n-slate-11'">
          {{ $t('ONBOARDING.PROVISIONING.STEPS.WAITING_QR') }}
        </span>
      </li>
      <li class="flex items-center gap-2.5">
        <span
          class="size-4 rounded-full inline-flex items-center justify-center shrink-0"
          :class="
            step >= 3
              ? 'bg-emerald-500 text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          <svg
            v-if="step >= 3"
            viewBox="0 0 16 16"
            class="size-2.5"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <polyline points="14 4 6 12 2 8" />
          </svg>
        </span>
        <span :class="step >= 3 ? 'text-n-slate-12' : 'text-n-slate-11'">
          {{ $t('ONBOARDING.PROVISIONING.STEPS.READY') }}
        </span>
      </li>
    </ol>

    <!-- Escape hatches if the framework drags its feet -->
    <div
      v-if="showManualContinue"
      class="flex flex-col items-center gap-2 pt-2"
    >
      <p class="text-[12px] text-pretty text-n-slate-11 max-w-[360px]">
        {{ $t('ONBOARDING.PROVISIONING.SLOW') }}
      </p>
      <div class="flex items-center gap-2">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          :label="$t('ONBOARDING.PROVISIONING.BACK')"
          @click="backToPicker"
        />
        <Button
          variant="faded"
          color="slate"
          size="sm"
          trailing-icon
          icon="i-lucide-arrow-right"
          :label="$t('ONBOARDING.PROVISIONING.CONTINUE_ANYWAY')"
          @click="goToHookup"
        />
      </div>
    </div>
  </section>
</template>

<style scoped>
/* Inline animation fallback — pure compositor props, ≤200ms interaction,
   respects prefers-reduced-motion. No gradients, single emerald accent. */
.core {
  fill: rgb(16 185 129 / 0.18);
  stroke: rgb(16 185 129);
  stroke-width: 1.5;
}
.core-inner {
  fill: rgb(16 185 129);
}
.ring {
  stroke: rgb(16 185 129 / 0.65);
  stroke-width: 1.2;
  transform-origin: 110px 110px;
  animation: ring-pulse 2.4s cubic-bezier(0.25, 0.1, 0.25, 1) infinite;
  opacity: 0;
}
.ring-2 {
  animation-delay: 0.8s;
}
.ring-3 {
  animation-delay: 1.6s;
}
@keyframes ring-pulse {
  0% {
    transform: scale(0.6);
    opacity: 0;
  }
  20% {
    opacity: 0.9;
  }
  100% {
    transform: scale(2.1);
    opacity: 0;
  }
}
.orbit {
  transform-origin: 110px 110px;
  animation: orbit-spin 3s linear infinite;
}
.orbit-dot {
  fill: rgb(16 185 129);
}
@keyframes orbit-spin {
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
}
@media (prefers-reduced-motion: reduce) {
  .ring,
  .orbit {
    animation: none;
  }
  .ring {
    opacity: 0.3;
  }
}
</style>
