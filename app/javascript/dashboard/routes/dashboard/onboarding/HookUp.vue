<script setup>
import {
  ref,
  reactive,
  computed,
  nextTick,
  onMounted,
  onBeforeUnmount,
  watch,
} from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';
import Button from 'dashboard/components-next/button/Button.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();

const accountId = computed(() => route.params.accountId);
const user = computed(() => store.getters.getCurrentUser || {});

const platform = ref('ios');
const connectionMethod = ref('qr'); // 'qr' | 'phone'
const androidVideoSrc = '/videos/whatsapp-android.mp4';
const iosVideoSrc = '/videos/whatsapp-ios.mp4';
const whatsappBusinessLogoSrc = '/dashboard/images/whatsapp-business-logo.png';

const qrCodeData = ref(null);
const connectionStatus = ref(null);
const instanceId = ref(null);
const inboxId = ref(null);
const pollTimer = ref(null);
const errorMessage = ref(null);
const isBootstrapping = ref(true);

// Phone pairing state
const phoneE164 = ref(''); // emitted by PhoneNumberInput as "+447835156367"
const pairingCode = ref(null);
const isRequestingCode = ref(false);
const pairingStep = ref(1);

const isConnected = computed(() => connectionStatus.value === 'open');

// Use the signed-in user's full email as the framework instance name.
// Framework paths only accept alphanumerics and hyphens reliably, so
// replace @ and . with dashes. Backend prefixes yields e.g.
// "acct-3-arslan-gmail-com".
const instanceName = computed(() => {
  const email = (user.value?.email || '').trim().toLowerCase();
  if (email) {
    const safe = email
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 60);
    if (safe) return safe;
  }
  const nameFallback = (user.value?.name || 'whatsapp')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
  return nameFallback || 'whatsapp';
});

const totalSteps = computed(() => (platform.value === 'ios' ? 5 : 3));

const stepKeyBase = computed(() =>
  platform.value === 'ios'
    ? 'ONBOARDING.HOOKUP.IOS_STEPS'
    : 'ONBOARDING.HOOKUP.ANDROID_STEPS'
);

const formattedPairingCode = computed(() => {
  const code = pairingCode.value || '';
  if (code.length >= 8) return `${code.slice(0, 4)}-${code.slice(4, 8)}`;
  if (code.length > 4) return `${code.slice(0, 4)}-${code.slice(4)}`;
  return code;
});

// Reset step position when switching platform or method
watch([platform, connectionMethod], () => {
  pairingStep.value = 1;
});

const requestPairingCode = async () => {
  if (!instanceId.value || !phoneE164.value) return;
  // Strip leading "+" and any leading 0s from the national portion.
  // PhoneNumberInput emits "+<dial><digits>" where digits are raw keystrokes,
  // so something like "07835..." becomes "+44 07835..." and must become
  // "447835..." before being sent to the framework.
  const raw = String(phoneE164.value).replace(/^\+/, '');
  const dialMatch = raw.match(/^\d{1,3}/);
  const dial = dialMatch ? dialMatch[0] : '';
  const national = raw.slice(dial.length).replace(/^0+/, '');
  const e164NoPlus = `${dial}${national}`.replace(/\D/g, '');
  if (!e164NoPlus) return;

  isRequestingCode.value = true;
  errorMessage.value = null;
  try {
    const { data } = await WhatsAppBridgeAPI.connect(
      instanceId.value,
      e164NoPlus
    );
    if (data?.pairingCode) {
      pairingCode.value = data.pairingCode;
      if (!pollTimer.value) {
        // eslint-disable-next-line no-use-before-define
        pollTimer.value = setInterval(() => pollQr(instanceId.value), 4000);
      }
    } else if (data?.error) {
      errorMessage.value = data.error;
    }
  } catch (err) {
    errorMessage.value =
      err?.response?.data?.error || err?.message || 'Connection error';
  } finally {
    isRequestingCode.value = false;
  }
};

const resetPairingCode = () => {
  pairingCode.value = null;
  phoneE164.value = '';
};

const toggleConnectionMethod = () => {
  errorMessage.value = null;
  connectionMethod.value = connectionMethod.value === 'qr' ? 'phone' : 'qr';
};

// Video play-state. Videos start paused+muted; clicking the overlay
// unmutes + plays. Switching platforms pauses the previously active video
// but remembers whether the user already started it.
const androidVideoEl = ref(null);
const iosVideoEl = ref(null);
const videoPlayed = reactive({ android: false, ios: false });

const getVideoEl = key =>
  key === 'android' ? androidVideoEl.value : iosVideoEl.value;

const playActiveVideo = () => {
  const key = platform.value;
  videoPlayed[key] = true;
  nextTick(() => {
    const el = getVideoEl(key);
    if (!el) return;
    el.muted = false;
    el.volume = 1;
    const p = el.play();
    if (p && typeof p.catch === 'function') p.catch(() => {});
  });
};

watch(platform, (newP, oldP) => {
  if (!oldP || oldP === newP) return;
  const oldEl = getVideoEl(oldP);
  if (oldEl && !oldEl.paused) oldEl.pause();
});

const stopPolling = () => {
  if (pollTimer.value) {
    clearInterval(pollTimer.value);
    pollTimer.value = null;
  }
};

const pollQr = async id => {
  try {
    const { data } = await WhatsAppBridgeAPI.qrCode(id);
    if (data.status === 'connected' || data.status === 'open') {
      connectionStatus.value = 'open';
      stopPolling();
      qrCodeData.value = null;
      pairingCode.value = null;
      return;
    }
    if (data.qrCode) qrCodeData.value = data.qrCode;
    if (data.pairingCode) pairingCode.value = data.pairingCode;
  } catch (_e) {
    // silent retry
  }
};

const bootstrap = async () => {
  try {
    const { data: existing } = await WhatsAppBridgeAPI.getInstances();
    const list = Array.isArray(existing) ? existing : existing?.instances || [];
    const first = list[0];
    if (first?.id) {
      instanceId.value = first.id;
      inboxId.value = first.inbox_id;
      await pollQr(first.id);
      if (!isConnected.value) {
        // If there's no QR yet, kick the framework to emit one.
        if (!qrCodeData.value) {
          try {
            await WhatsAppBridgeAPI.connect(first.id);
          } catch (_e) {
            // framework already connecting – ignore
          }
        }
        pollTimer.value = setInterval(() => pollQr(first.id), 4000);
      }
      return;
    }
  } catch (_e) {
    // no existing instance, create a fresh one below
  }

  try {
    const { data } = await WhatsAppBridgeAPI.createInstance(instanceName.value);
    if (data.error || data.instance?.error) {
      errorMessage.value = data.error || data.instance?.error;
      return;
    }
    const inst = data.instance || {};
    const id =
      inst.id || inst.instance?.id || inst.instance?.instanceName || inst.name;
    if (!id) {
      errorMessage.value = 'Could not start WhatsApp connection.';
      return;
    }
    instanceId.value = id;
    inboxId.value = data.inbox_id;

    const connectResp = await WhatsAppBridgeAPI.connect(id);
    const qrResp = await WhatsAppBridgeAPI.qrCode(id);
    if (qrResp.data.qrCode) qrCodeData.value = qrResp.data.qrCode;
    if (
      qrResp.data.status === 'connected' ||
      qrResp.data.status === 'open' ||
      connectResp.data?.status === 'open'
    ) {
      connectionStatus.value = 'open';
    } else {
      pollTimer.value = setInterval(() => pollQr(id), 4000);
    }
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.error || error?.message || 'Connection error';
  }
};

onMounted(async () => {
  try {
    await bootstrap();
  } finally {
    isBootstrapping.value = false;
  }
});

// Clean up orphan instance if the user leaves without completing the link.
// Covers: Skip button (OnboardingShell), Previous/Continue buttons, browser
// back, and any other route change that unmounts this component. If the
// instance is connected, we keep it so the user's inbox is preserved.
const cleanupOrphanInstance = () => {
  const id = instanceId.value;
  if (!id || isConnected.value) return;
  WhatsAppBridgeAPI.deleteInstance(id).catch(() => {
    // best-effort — admin can clean up later if the request fails
  });
};

onBeforeUnmount(() => {
  stopPolling();
  cleanupOrphanInstance();
});

const markComplete = () => {
  const userId = user.value?.id;
  if (!userId || !accountId.value) return;
  try {
    localStorage.setItem(
      `cw_onboarding_done_${userId}_${accountId.value}`,
      'true'
    );
  } catch (_e) {
    // ignore
  }
};

const onPrevious = () => {
  markComplete();
  router.replace(`/app/accounts/${accountId.value}/dashboard`);
};

const onContinue = () => {
  router.push({
    name: 'onboarding_done',
    params: { accountId: accountId.value },
  });
};

// Deterministic 21×21 QR-ish skeleton pattern.
// Three finder squares in corners + pseudo-random data modules.
const qrSkeleton = (() => {
  const SIZE = 21;
  const cells = [];
  const isFinder = (x, y) => {
    const inTL = x < 7 && y < 7;
    const inTR = x >= SIZE - 7 && y < 7;
    const inBL = x < 7 && y >= SIZE - 7;
    return inTL || inTR || inBL;
  };
  const localCoord = v => {
    if (v < 7) return v;
    if (v >= SIZE - 7) return v - (SIZE - 7);
    return -1;
  };
  const finderFill = (x, y) => {
    // Relative coords inside a 7x7 finder
    const lx = localCoord(x);
    const ly = localCoord(y);
    if (lx < 0 || ly < 0) return false;
    const onBorder = lx === 0 || lx === 6 || ly === 0 || ly === 6;
    const innerSquare = lx >= 2 && lx <= 4 && ly >= 2 && ly <= 4;
    return onBorder || innerSquare;
  };
  // Simple deterministic hash for the data area
  let seed = 1337;
  const rand = () => {
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
  };
  for (let y = 0; y < SIZE; y += 1) {
    for (let x = 0; x < SIZE; x += 1) {
      let on = false;
      if (isFinder(x, y)) {
        on = finderFill(x, y);
      } else if (
        // horizontal & vertical timing patterns
        (x === 6 && y >= 8 && y <= SIZE - 9) ||
        (y === 6 && x >= 8 && x <= SIZE - 9)
      ) {
        on = (x + y) % 2 === 0;
      } else {
        on = rand() > 0.55;
      }
      cells.push(on);
    }
  }
  return { size: SIZE, cells };
})();
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<!-- eslint-disable @intlify/vue-i18n/no-dynamic-keys -->
<template>
  <section class="mx-auto w-full max-w-[1040px] flex flex-col gap-8 sm:gap-10">
    <header class="flex flex-col items-center text-center gap-2">
      <div
        v-tooltip.bottom="$t('ONBOARDING.HOOKUP.SUBTITLE')"
        class="relative mb-1.5 group cursor-help"
      >
        <span
          aria-hidden="true"
          class="absolute inset-0 rounded-[14px] bg-emerald-500/30 blur-xl transition-all duration-300 ease-out group-hover:bg-emerald-500/50 group-hover:blur-2xl"
        />
        <img
          :src="whatsappBusinessLogoSrc"
          alt="WhatsApp Business"
          class="relative size-12 sm:size-14 rounded-[14px] shadow-[0_8px_24px_-10px_rgba(16,185,129,0.55)] ring-1 ring-black/5 dark:ring-white/10 transition-transform duration-300 ease-out group-hover:scale-110"
        />
      </div>
      <span
        class="text-[10.5px] sm:text-[11px] font-medium uppercase tracking-[0.22em] text-n-slate-11"
      >
        {{ $t('ONBOARDING.HOOKUP.EYEBROW') }}
      </span>
      <h1
        class="text-[24px] sm:text-[32px] font-semibold tracking-tight text-balance text-n-slate-12 leading-[1.1]"
      >
        {{ $t('ONBOARDING.HOOKUP.TITLE') }}
      </h1>
    </header>

    <div
      class="grid grid-cols-1 sm:grid-cols-2 gap-4 sm:gap-6 w-full items-stretch"
    >
      <!-- Step 1 · phone -->
      <div class="flex flex-col min-w-0">
        <div
          class="rounded-2xl bg-white dark:bg-n-solid-2 border border-n-container dark:border-n-weak overflow-hidden flex flex-col h-[340px] sm:h-[360px] shadow-sm"
        >
          <!-- Tabs -->
          <div
            role="tablist"
            class="flex items-center gap-1 p-1.5 m-2.5 mb-0 rounded-lg bg-n-alpha-1 dark:bg-n-alpha-black2"
          >
            <button
              role="tab"
              type="button"
              :aria-selected="platform === 'ios'"
              class="flex-1 inline-flex items-center justify-center gap-2 rounded-md px-3 py-1.5 text-[13px] font-medium transition-colors"
              :class="
                platform === 'ios'
                  ? 'bg-n-background dark:bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="platform = 'ios'"
            >
              <svg
                viewBox="0 0 16 16"
                class="size-[13px] fill-current"
                aria-hidden="true"
              >
                <path
                  d="M11.624 8.28c-.018-1.92 1.57-2.84 1.64-2.886-.893-1.304-2.283-1.482-2.775-1.503-1.181-.12-2.308.696-2.907.696-.6 0-1.525-.679-2.51-.66-1.29.02-2.48.75-3.143 1.905-1.34 2.324-.343 5.76.963 7.649.64.923 1.4 1.962 2.398 1.925.965-.038 1.33-.62 2.498-.62 1.167 0 1.492.62 2.513.602 1.036-.017 1.693-.94 2.327-1.867.732-1.071 1.035-2.107 1.05-2.16-.023-.01-2.014-.772-2.034-3.08zM9.74 2.705c.53-.645.89-1.538.79-2.427-.765.032-1.693.51-2.244 1.153-.492.57-.925 1.486-.81 2.357.854.066 1.727-.434 2.264-1.083z"
                />
              </svg>
              {{ $t('ONBOARDING.HOOKUP.IOS') }}
            </button>
            <button
              role="tab"
              type="button"
              :aria-selected="platform === 'android'"
              class="flex-1 inline-flex items-center justify-center gap-2 rounded-md px-3 py-1.5 text-[13px] font-medium transition-colors"
              :class="
                platform === 'android'
                  ? 'bg-n-background dark:bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="platform = 'android'"
            >
              <svg
                viewBox="0 0 24 24"
                class="size-[14px]"
                fill="none"
                stroke="#A4C639"
                stroke-width="1.8"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path
                  d="M6 11h12v7a1 1 0 0 1-1 1h-1.5v2.5a1 1 0 0 1-2 0V19h-3v2.5a1 1 0 0 1-2 0V19H7a1 1 0 0 1-1-1v-7Z"
                />
                <path d="M6 11c0-3.3 2.7-6 6-6s6 2.7 6 6" />
                <path d="M3.5 12v5M20.5 12v5" />
                <path d="M9 7.5 8 5.5M15 7.5l1-2" />
                <circle cx="9.5" cy="8.5" r=".6" fill="#A4C639" stroke="none" />
                <circle
                  cx="14.5"
                  cy="8.5"
                  r=".6"
                  fill="#A4C639"
                  stroke="none"
                />
              </svg>
              {{ $t('ONBOARDING.HOOKUP.ANDROID') }}
            </button>
          </div>

          <!-- Media / instructions area -->
          <div class="flex-1 p-3 min-h-0">
            <div
              class="relative w-full h-full rounded-xl overflow-hidden bg-n-alpha-1 dark:bg-n-alpha-black2"
            >
              <Transition
                enter-active-class="transition duration-300 ease-out"
                enter-from-class="opacity-0 translate-y-1"
                enter-to-class="opacity-100 translate-y-0"
                leave-active-class="transition duration-150 ease-in absolute inset-0"
                leave-from-class="opacity-100"
                leave-to-class="opacity-0"
                mode="out-in"
              >
                <!-- QR mode: videos with play-to-start overlay -->
                <div
                  v-if="connectionMethod === 'qr'"
                  key="video"
                  class="absolute inset-0"
                >
                  <video
                    v-show="platform === 'android'"
                    ref="androidVideoEl"
                    class="absolute inset-0 w-full h-full object-contain bg-black"
                    :src="androidVideoSrc"
                    :controls="videoPlayed.android"
                    loop
                    playsinline
                    preload="metadata"
                    controlslist="nodownload noplaybackrate"
                    disablepictureinpicture
                  />
                  <video
                    v-show="platform === 'ios'"
                    ref="iosVideoEl"
                    class="absolute inset-0 w-full h-full object-contain bg-black"
                    :src="iosVideoSrc"
                    :controls="videoPlayed.ios"
                    loop
                    playsinline
                    preload="metadata"
                    controlslist="nodownload noplaybackrate"
                    disablepictureinpicture
                  />

                  <!-- Play-to-start overlay -->
                  <transition
                    enter-active-class="transition duration-200 ease-out"
                    enter-from-class="opacity-0"
                    enter-to-class="opacity-100"
                    leave-active-class="transition duration-150 ease-in"
                    leave-from-class="opacity-100"
                    leave-to-class="opacity-0"
                  >
                    <button
                      v-if="!videoPlayed[platform]"
                      type="button"
                      class="group absolute inset-0 flex items-center justify-center bg-black/15 hover:bg-black/25 transition-colors"
                      :aria-label="$t('ONBOARDING.HOOKUP.PLAY_VIDEO')"
                      @click="playActiveVideo"
                    >
                      <svg
                        viewBox="0 0 24 24"
                        fill="#0a0a0a"
                        class="size-16 sm:size-20 drop-shadow-[0_6px_18px_rgba(0,0,0,0.45)] transition-transform duration-200 ease-out group-hover:scale-110 group-active:scale-95"
                        aria-hidden="true"
                      >
                        <path
                          fill="#0a0a0a"
                          d="M7.5 4.65c-.92-.58-2.12.08-2.12 1.17v12.36c0 1.09 1.2 1.75 2.12 1.17l9.73-6.18c.86-.55.86-1.79 0-2.34L7.5 4.65Z"
                        />
                      </svg>
                    </button>
                  </transition>
                </div>

                <!-- Phone-pairing mode: step carousel -->
                <div
                  v-else
                  key="steps"
                  class="absolute inset-0 flex flex-col bg-white dark:bg-n-solid-2 p-5"
                >
                  <!-- Step progress bars -->
                  <div class="flex gap-1.5">
                    <span
                      v-for="i in totalSteps"
                      :key="i"
                      class="h-1 flex-1 rounded-full transition-colors duration-300"
                      :class="
                        i <= pairingStep
                          ? 'bg-emerald-500'
                          : 'bg-n-alpha-2 dark:bg-n-alpha-white2'
                      "
                    />
                  </div>

                  <!-- Step body -->
                  <div
                    class="flex-1 min-h-0 flex flex-col items-center justify-center text-center gap-3 px-2"
                  >
                    <span
                      class="text-[10.5px] font-medium uppercase tracking-[0.22em] text-n-slate-11"
                    >
                      {{
                        $t('ONBOARDING.HOOKUP.STEP_LABEL', {
                          current: pairingStep,
                          total: totalSteps,
                        })
                      }}
                    </span>
                    <Transition
                      enter-active-class="transition duration-200 ease-out"
                      enter-from-class="opacity-0 translate-y-1"
                      enter-to-class="opacity-100 translate-y-0"
                      leave-active-class="transition duration-100 ease-in absolute"
                      leave-from-class="opacity-100"
                      leave-to-class="opacity-0"
                      mode="out-in"
                    >
                      <p
                        :key="`${platform}-${pairingStep}`"
                        class="text-[14px] sm:text-[15px] leading-relaxed text-n-slate-12 text-pretty max-w-[360px]"
                      >
                        {{ $t(`${stepKeyBase}.${pairingStep}`) }}
                      </p>
                    </Transition>
                  </div>

                  <!-- Step nav -->
                  <div class="flex items-center justify-between">
                    <Button
                      variant="ghost"
                      color="slate"
                      size="sm"
                      icon="i-lucide-chevron-left"
                      :label="$t('ONBOARDING.HOOKUP.BACK')"
                      :disabled="pairingStep === 1"
                      @click="pairingStep = Math.max(1, pairingStep - 1)"
                    />
                    <Button
                      variant="faded"
                      color="slate"
                      size="sm"
                      icon="i-lucide-chevron-right"
                      trailing-icon
                      :label="$t('ONBOARDING.HOOKUP.NEXT')"
                      :disabled="pairingStep >= totalSteps"
                      @click="
                        pairingStep = Math.min(totalSteps, pairingStep + 1)
                      "
                    />
                  </div>
                </div>
              </Transition>
            </div>
          </div>
        </div>
      </div>

      <!-- Step 2 · QR / Phone pairing -->
      <div class="flex flex-col min-w-0">
        <div
          class="relative rounded-2xl bg-white dark:bg-n-solid-2 border border-n-container dark:border-n-weak h-[340px] sm:h-[360px] flex flex-col shadow-sm"
        >
          <!-- Content -->
          <div
            class="relative flex-1 min-h-0 flex items-center justify-center p-5"
          >
            <!-- Corner tick marks (frame) -->
            <span
              class="absolute top-3 left-3 size-5 border-t-2 border-l-2 border-n-slate-7 dark:border-n-slate-6 rounded-tl-md"
              aria-hidden="true"
            />
            <span
              class="absolute top-3 right-3 size-5 border-t-2 border-r-2 border-n-slate-7 dark:border-n-slate-6 rounded-tr-md"
              aria-hidden="true"
            />
            <span
              class="absolute bottom-3 left-3 size-5 border-b-2 border-l-2 border-n-slate-7 dark:border-n-slate-6 rounded-bl-md"
              aria-hidden="true"
            />
            <span
              class="absolute bottom-3 right-3 size-5 border-b-2 border-r-2 border-n-slate-7 dark:border-n-slate-6 rounded-br-md"
              aria-hidden="true"
            />

            <Transition
              enter-active-class="transition duration-[450ms] ease-out"
              enter-from-class="opacity-0 scale-95"
              enter-to-class="opacity-100 scale-100"
              leave-active-class="transition duration-200 ease-in absolute inset-0 flex items-center justify-center"
              leave-from-class="opacity-100 scale-100"
              leave-to-class="opacity-0 scale-95"
              mode="out-in"
            >
              <!-- Connected state -->
              <div
                v-if="isConnected"
                key="connected"
                class="flex flex-col items-center gap-3 text-center"
              >
                <div
                  class="relative size-16 rounded-full bg-emerald-50 dark:bg-emerald-500/15 flex items-center justify-center connected-pop"
                >
                  <!-- Soft radial glow behind the check -->
                  <span
                    aria-hidden="true"
                    class="absolute inset-0 rounded-full bg-emerald-400/40 blur-xl connected-glow"
                  />
                  <svg
                    viewBox="0 0 24 24"
                    class="relative size-8 text-emerald-600 dark:text-emerald-400"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.5"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <polyline class="check-draw" points="20 6 9 17 4 12" />
                  </svg>
                </div>
                <p
                  class="text-[15px] font-medium text-n-slate-12 connected-label"
                >
                  {{ $t('ONBOARDING.HOOKUP.CONNECTED') }}
                </p>
              </div>

              <!-- QR mode -->
              <div
                v-else-if="connectionMethod === 'qr'"
                key="qr"
                class="flex items-center justify-center w-full h-full"
              >
                <img
                  v-if="qrCodeData"
                  :src="qrCodeData"
                  alt="WhatsApp QR code"
                  class="max-w-[240px] max-h-[240px] w-full h-auto rounded-md"
                />

                <div
                  v-else-if="errorMessage && !isBootstrapping"
                  class="flex flex-col items-center gap-2 text-center px-4"
                >
                  <div
                    class="size-10 rounded-full bg-amber-50 dark:bg-amber-500/15 flex items-center justify-center"
                  >
                    <svg
                      viewBox="0 0 24 24"
                      class="size-5 text-amber-600 dark:text-amber-400"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      aria-hidden="true"
                    >
                      <path
                        d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0zM12 9v4M12 17h.01"
                      />
                    </svg>
                  </div>
                  <p
                    class="text-[12.5px] text-n-slate-11 max-w-[220px] text-pretty"
                  >
                    {{ $t('ONBOARDING.HOOKUP.QR_ERROR') }}
                  </p>
                </div>

                <!-- QR-shaped skeleton loader -->
                <div
                  v-else
                  class="flex flex-col items-center gap-4"
                  role="status"
                  aria-live="polite"
                >
                  <div
                    class="qr-skeleton relative w-[200px] h-[200px] p-2.5 rounded-md bg-white dark:bg-n-solid-3 shadow-inner"
                    aria-hidden="true"
                  >
                    <div
                      class="grid w-full h-full"
                      :style="{
                        gridTemplateColumns: `repeat(${qrSkeleton.size}, minmax(0, 1fr))`,
                        gridTemplateRows: `repeat(${qrSkeleton.size}, minmax(0, 1fr))`,
                        gap: '1px',
                      }"
                    >
                      <span
                        v-for="(on, i) in qrSkeleton.cells"
                        :key="i"
                        class="qr-cell rounded-[1px]"
                        :class="on ? 'qr-on' : 'qr-off'"
                        :style="{ animationDelay: `${(i * 13) % 1000}ms` }"
                      />
                    </div>
                    <span
                      class="qr-sweep pointer-events-none absolute inset-x-3 top-3 h-6 rounded-sm"
                    />
                  </div>
                  <p class="text-[12px] text-n-slate-11 tracking-tight">
                    {{ $t('ONBOARDING.HOOKUP.QR_LOADING') }}
                  </p>
                </div>
              </div>

              <!-- Phone mode -->
              <div
                v-else
                key="phone"
                class="flex items-center justify-center w-full h-full"
              >
                <!-- Code issued -->
                <div
                  v-if="pairingCode"
                  class="flex flex-col items-center gap-3 text-center w-full"
                >
                  <span
                    class="text-[10.5px] font-medium uppercase tracking-[0.22em] text-n-slate-11"
                  >
                    {{ $t('ONBOARDING.HOOKUP.PAIRING_CODE_LABEL') }}
                  </span>
                  <div
                    class="font-mono text-[30px] sm:text-[34px] font-semibold tracking-[0.18em] text-n-slate-12 select-all"
                  >
                    {{ formattedPairingCode }}
                  </div>
                  <p
                    class="text-[12px] text-n-slate-11 max-w-[240px] text-pretty"
                  >
                    {{ $t('ONBOARDING.HOOKUP.PAIRING_CODE_HINT') }}
                  </p>
                  <button
                    type="button"
                    class="text-[12px] font-medium text-n-slate-11 hover:text-n-slate-12 underline underline-offset-2"
                    @click="resetPairingCode"
                  >
                    {{ $t('ONBOARDING.HOOKUP.USE_DIFFERENT_NUMBER') }}
                  </button>
                </div>

                <!-- Phone entry form -->
                <form
                  v-else
                  class="flex flex-col gap-3 w-full max-w-[280px]"
                  @submit.prevent="requestPairingCode"
                >
                  <label
                    class="text-[11px] font-medium uppercase tracking-[0.18em] text-n-slate-11 text-center"
                  >
                    {{ $t('ONBOARDING.HOOKUP.PHONE_LABEL') }}
                  </label>
                  <PhoneNumberInput
                    v-model="phoneE164"
                    :placeholder="$t('ONBOARDING.HOOKUP.PHONE_PLACEHOLDER')"
                  />
                  <Button
                    type="submit"
                    variant="solid"
                    color="blue"
                    size="md"
                    :label="$t('ONBOARDING.HOOKUP.GET_CODE')"
                    :is-loading="isRequestingCode"
                    :disabled="!phoneE164 || !instanceId"
                  />
                  <p
                    v-if="errorMessage"
                    class="text-[11.5px] text-n-ruby-11 text-center text-pretty"
                  >
                    {{ errorMessage }}
                  </p>
                </form>
              </div>
            </Transition>
          </div>

          <!-- Subtle swap link -->
          <div
            v-if="!isConnected"
            class="relative z-10 flex items-center justify-center pb-3"
          >
            <button
              type="button"
              class="group inline-flex items-center gap-1.5 text-[11.5px] font-medium text-n-slate-11 hover:text-n-slate-12 transition-colors px-2 py-1 rounded-md"
              @click="toggleConnectionMethod"
            >
              <span
                class="size-3.5 inline-flex items-center justify-center opacity-70 group-hover:opacity-100 transition-opacity"
                aria-hidden="true"
              >
                <span
                  :class="
                    connectionMethod === 'qr'
                      ? 'i-lucide-smartphone'
                      : 'i-lucide-qr-code'
                  "
                  class="size-3.5"
                />
              </span>
              <span class="underline underline-offset-[3px] decoration-dotted">
                {{
                  connectionMethod === 'qr'
                    ? $t('ONBOARDING.HOOKUP.SWAP_TO_PHONE')
                    : $t('ONBOARDING.HOOKUP.SWAP_TO_QR')
                }}
              </span>
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Footer actions -->
    <div class="flex items-center justify-center gap-3">
      <Button
        variant="faded"
        color="slate"
        size="md"
        icon="i-lucide-arrow-left"
        :label="$t('ONBOARDING.HOOKUP.PREVIOUS')"
        @click="onPrevious"
      />
      <Button
        variant="solid"
        color="blue"
        size="md"
        icon="i-lucide-arrow-right"
        trailing-icon
        :label="$t('ONBOARDING.HOOKUP.CONTINUE')"
        @click="onContinue"
      />
    </div>
  </section>
</template>

<style scoped>
/* QR-shaped skeleton: dark cells shimmer, light cells stay light */
.qr-cell {
  background-color: transparent;
}
.qr-on {
  background-color: rgb(23 23 23 / 0.92);
  animation: qr-shimmer 1.6s ease-in-out infinite;
}
:global(.dark) .qr-on {
  background-color: rgb(226 232 240 / 0.9);
}
.qr-off {
  background-color: rgb(245 245 245);
}
:global(.dark) .qr-off {
  background-color: rgb(38 38 38);
}
@keyframes qr-shimmer {
  0%,
  100% {
    opacity: 0.55;
  }
  50% {
    opacity: 1;
  }
}
.qr-sweep {
  background: linear-gradient(
    180deg,
    rgba(16, 185, 129, 0) 0%,
    rgba(16, 185, 129, 0.28) 50%,
    rgba(16, 185, 129, 0) 100%
  );
  animation: qr-sweep 2.2s cubic-bezier(0.22, 1, 0.36, 1) infinite;
  filter: blur(1px);
}
@keyframes qr-sweep {
  0% {
    transform: translateY(0);
    opacity: 0;
  }
  20% {
    opacity: 1;
  }
  80% {
    opacity: 1;
  }
  100% {
    transform: translateY(190px);
    opacity: 0;
  }
}
/* Success state animations */
.connected-pop {
  animation: connected-pop 520ms cubic-bezier(0.22, 1.4, 0.36, 1) both;
}
@keyframes connected-pop {
  0% {
    transform: scale(0.4);
    opacity: 0;
  }
  55% {
    transform: scale(1.08);
    opacity: 1;
  }
  100% {
    transform: scale(1);
    opacity: 1;
  }
}
.connected-glow {
  animation: connected-glow 1.6s ease-out 250ms both;
}
@keyframes connected-glow {
  0% {
    opacity: 0;
    transform: scale(0.8);
  }
  35% {
    opacity: 0.9;
    transform: scale(1.15);
  }
  100% {
    opacity: 0;
    transform: scale(1.4);
  }
}
.check-draw {
  stroke-dasharray: 32;
  stroke-dashoffset: 32;
  animation: check-draw 420ms ease-out 180ms forwards;
}
@keyframes check-draw {
  to {
    stroke-dashoffset: 0;
  }
}
.connected-label {
  animation: connected-label 360ms ease-out 320ms both;
}
@keyframes connected-label {
  0% {
    opacity: 0;
    transform: translateY(4px);
  }
  100% {
    opacity: 1;
    transform: translateY(0);
  }
}

@media (prefers-reduced-motion: reduce) {
  .qr-on,
  .qr-sweep,
  .connected-pop,
  .connected-glow,
  .check-draw,
  .connected-label {
    animation: none;
  }
  .check-draw {
    stroke-dashoffset: 0;
  }
}
</style>
