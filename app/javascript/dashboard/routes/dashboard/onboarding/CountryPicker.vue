<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';
import Button from 'dashboard/components-next/button/Button.vue';
import { EU_MAP_VIEWBOX, COUNTRY_PATHS } from './countryPaths.js';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const accountId = computed(() => route.params.accountId);
const user = computed(() => store.getters.getCurrentUser || {});

// SVG projection constants — must match scripts/generate_europe_paths.mjs
// Do not change without regenerating countryPaths.js.
const VIEW_W = 800;
const VIEW_H = 700;
const LON_MIN = -12;
const LON_MAX = 32;
const LAT_MIN = 34;
const LAT_MAX = 72;
const projLng = lng => ((lng - LON_MIN) / (LON_MAX - LON_MIN)) * VIEW_W;
const projLat = lat =>
  VIEW_H - ((lat - LAT_MIN) / (LAT_MAX - LAT_MIN)) * VIEW_H;

// Active regions come from the backend (controls which countries light up
// as clickable). Expansion countries are a curated marketing-only list.
const ACTIVE_COUNTRIES = ref(new Set());
const ACTIVE_REGIONS = ref([]);
const EXPANSION = new Set(['NL', 'IE', 'ES', 'BE', 'CH', 'AT', 'DK', 'PL']);

const selectedIso = ref(null);
const hoveredIso = ref(null);
const isCreating = ref(false);
const isVerifying = ref(false);
const errorMessage = ref(null);
const chosenRegionLabel = ref(null);

const countryName = iso => t(`ONBOARDING.COUNTRY_PICKER.COUNTRY_NAMES.${iso}`);

const selectedLabel = computed(() =>
  selectedIso.value ? countryName(selectedIso.value) : null
);

const displayIso = computed(() => hoveredIso.value || selectedIso.value);
const displayLabel = computed(() => {
  if (!displayIso.value) return null;
  const name = countryName(displayIso.value);
  if (ACTIVE_COUNTRIES.value.has(displayIso.value)) return name;
  if (EXPANSION.has(displayIso.value)) {
    return `${name} · ${t('ONBOARDING.COUNTRY_PICKER.COMING_SOON')}`;
  }
  return null;
});

const countryClass = iso => {
  if (selectedIso.value === iso) return 'country-selected';
  if (ACTIVE_COUNTRIES.value.has(iso)) return 'country-active';
  if (EXPANSION.has(iso)) return 'country-expansion';
  return 'country-context';
};

const countryInteractive = iso =>
  ACTIVE_COUNTRIES.value.has(iso) || EXPANSION.has(iso);

const coveredLabel = computed(() =>
  t('ONBOARDING.COUNTRY_PICKER.COVERED', { count: ACTIVE_COUNTRIES.value.size })
);

const continueDisabled = computed(
  () => !selectedIso.value || isCreating.value || isVerifying.value
);

const continueLabel = computed(() => {
  if (isCreating.value)
    return t('ONBOARDING.COUNTRY_PICKER.STATUS.PROVISIONING');
  if (isVerifying.value) return t('ONBOARDING.COUNTRY_PICKER.STATUS.VERIFYING');
  if (selectedLabel.value) {
    return t('ONBOARDING.COUNTRY_PICKER.CONTINUE_WITH', {
      country: selectedLabel.value,
    });
  }
  return t('ONBOARDING.COUNTRY_PICKER.PICK_A_COUNTRY');
});

const loadRegions = async () => {
  try {
    const { data } = await WhatsAppBridgeAPI.getRegions();
    ACTIVE_REGIONS.value = data?.regions || [];
    const set = new Set();
    ACTIVE_REGIONS.value.forEach(r => set.add(r.country));
    ACTIVE_COUNTRIES.value = set;
  } catch (_e) {
    ACTIVE_COUNTRIES.value = new Set();
  }
};

const onCountryClick = iso => {
  if (!ACTIVE_COUNTRIES.value.has(iso)) return;
  selectedIso.value = iso;
  errorMessage.value = null;
};

// Email → URL-safe instance name — kept identical to HookUp.vue so the
// scoped_instance_id stays predictable.
const instanceNameFromEmail = () => {
  const email = (user.value?.email || '').trim().toLowerCase();
  if (email) {
    const safe = email
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 60);
    if (safe) return safe;
  }
  const fallback = (user.value?.name || 'whatsapp')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
  return fallback || 'whatsapp';
};

// Poll the /region_health endpoint for a freshly-provisioned instance.
// Succeeds as soon as the framework acknowledges the instance (any status
// except 'unreachable' / 'unconfigured'). Gives up after ~10s and surfaces
// an error so the admin can pick another country instead of staring at a
// dead QR screen.
const verifyInstanceLive = async ({ regionCode, instanceName }) => {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    try {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await WhatsAppBridgeAPI.regionHealth({
        regionCode,
        instanceName,
      });
      if (data?.success) return true;
    } catch (_e) {
      // transient — keep polling
    }
    // eslint-disable-next-line no-await-in-loop
    await new Promise(resolve => {
      setTimeout(resolve, 1200);
    });
  }
  throw new Error(t('ONBOARDING.COUNTRY_PICKER.RESOLVE_FAILED'));
};

const continueFlow = async () => {
  if (continueDisabled.value) return;
  isCreating.value = true;
  errorMessage.value = null;
  try {
    const { data } = await WhatsAppBridgeAPI.createInstance(
      instanceNameFromEmail(),
      { countryIso: selectedIso.value }
    );
    if (data?.error) {
      errorMessage.value = data.error;
      return;
    }

    const regionCode = data?.region_code || data?.instance?.region || null;
    const instanceName =
      data?.instance?.id ||
      data?.instance?.name ||
      data?.instance?.instanceName;

    chosenRegionLabel.value =
      ACTIVE_REGIONS.value.find(r => r.code === regionCode)?.label || null;

    isCreating.value = false;
    isVerifying.value = true;

    await verifyInstanceLive({ regionCode, instanceName });

    router.push({
      name: 'onboarding_hookup',
      params: { accountId: accountId.value },
    });
  } catch (err) {
    errorMessage.value =
      err?.response?.data?.error ||
      err?.message ||
      t('ONBOARDING.COUNTRY_PICKER.RESOLVE_FAILED');
  } finally {
    isCreating.value = false;
    isVerifying.value = false;
  }
};

const onPrevious = () => {
  router.replace(`/app/accounts/${accountId.value}/dashboard`);
};

watch(selectedIso, () => {
  errorMessage.value = null;
});

onMounted(loadRegions);
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<!-- eslint-disable @intlify/vue-i18n/no-dynamic-keys -->
<template>
  <section class="mx-auto w-full max-w-[1040px] flex flex-col gap-8 sm:gap-10">
    <header class="flex flex-col items-center text-center gap-2">
      <div class="relative mb-1.5 group" aria-hidden="true">
        <span
          class="absolute inset-0 rounded-[14px] bg-emerald-500/30 blur-xl transition-all duration-300 ease-out group-hover:bg-emerald-500/50 group-hover:blur-2xl"
        />
        <span
          class="relative size-12 sm:size-14 rounded-[14px] shadow-[0_8px_24px_-10px_rgba(16,185,129,0.55)] ring-1 ring-black/5 dark:ring-white/10 bg-gradient-to-br from-emerald-400 to-emerald-600 grid place-content-center transition-transform duration-300 ease-out group-hover:scale-110"
        >
          <svg
            viewBox="0 0 24 24"
            class="size-6 sm:size-7 text-white"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
            <circle cx="12" cy="10" r="3" />
          </svg>
        </span>
      </div>
      <span
        class="text-[10.5px] sm:text-[11px] font-medium uppercase tracking-[0.22em] text-n-slate-11"
      >
        {{ $t('ONBOARDING.COUNTRY_PICKER.EYEBROW') }}
      </span>
      <h1
        class="text-[24px] sm:text-[32px] font-semibold tracking-tight text-balance text-n-slate-12 leading-[1.1]"
      >
        {{ $t('ONBOARDING.COUNTRY_PICKER.TITLE') }}
      </h1>
      <p
        class="text-[12.5px] sm:text-[13.5px] text-n-slate-11 text-pretty max-w-[520px]"
      >
        {{ $t('ONBOARDING.COUNTRY_PICKER.SUBTITLE') }}
      </p>
    </header>

    <!-- Map card, same visual language as HookUp's video card -->
    <div
      class="relative rounded-2xl bg-white dark:bg-n-solid-2 border border-n-container dark:border-n-weak shadow-sm overflow-hidden"
    >
      <div
        class="flex items-center justify-between px-5 pt-4 pb-2 text-[10.5px] font-medium uppercase tracking-[0.22em]"
      >
        <span class="text-n-slate-11">{{ coveredLabel }}</span>
        <span
          v-if="displayLabel"
          key="label"
          class="text-n-slate-12 transition-opacity"
        >
          {{ displayLabel }}
        </span>
      </div>

      <div class="relative px-4 pb-4">
        <svg
          :viewBox="EU_MAP_VIEWBOX"
          class="w-full h-auto select-none"
          role="img"
          :aria-label="$t('ONBOARDING.COUNTRY_PICKER.TITLE')"
        >
          <defs>
            <pattern
              id="eu-grid"
              width="38"
              height="38"
              patternUnits="userSpaceOnUse"
            >
              <path
                d="M 38 0 L 0 0 0 38"
                fill="none"
                stroke="currentColor"
                stroke-width="0.4"
                class="text-n-slate-6/40"
              />
            </pattern>
            <radialGradient id="eu-aurora" cx="50%" cy="40%" r="60%">
              <stop offset="0%" stop-color="rgba(16, 185, 129, 0.18)" />
              <stop offset="55%" stop-color="rgba(16, 185, 129, 0.04)" />
              <stop offset="100%" stop-color="rgba(16, 185, 129, 0)" />
            </radialGradient>
            <filter id="pin-glow" x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          <!-- Ambient emerald aurora behind the continent -->
          <rect width="100%" height="100%" fill="url(#eu-aurora)" />
          <rect width="100%" height="100%" fill="url(#eu-grid)" />

          <!-- Country paths -->
          <g>
            <path
              v-for="(d, iso) in COUNTRY_PATHS"
              :key="iso"
              :d="d"
              class="transition-[fill,stroke,filter] duration-300 ease-out country-path"
              :class="[
                countryClass(iso),
                countryInteractive(iso)
                  ? 'cursor-pointer'
                  : 'pointer-events-none',
              ]"
              @click="onCountryClick(iso)"
              @mouseenter="hoveredIso = iso"
              @mouseleave="hoveredIso = null"
            >
              <title v-if="countryInteractive(iso)">
                {{ countryName(iso) }}
              </title>
            </path>
          </g>

          <!-- Datacentre markers (dot + ring) on each active region -->
          <g>
            <g v-for="region in ACTIVE_REGIONS" :key="`dc-${region.code}`">
              <circle
                :cx="projLng(region.lng)"
                :cy="projLat(region.lat)"
                r="2.5"
                class="dc-dot"
                :class="{ 'dc-dot-active': selectedIso === region.country }"
              />
              <circle
                v-if="selectedIso === region.country"
                :cx="projLng(region.lng)"
                :cy="projLat(region.lat)"
                r="4"
                class="dc-pulse"
              />
            </g>
          </g>
        </svg>
      </div>

      <!-- Selection chip on the bottom of the card -->
      <div
        class="px-5 pb-4 -mt-1 min-h-[42px] flex items-center justify-center"
      >
        <Transition
          enter-active-class="transition duration-300 ease-out"
          enter-from-class="opacity-0 translate-y-1"
          enter-to-class="opacity-100 translate-y-0"
          leave-active-class="transition duration-200 ease-in absolute"
          leave-from-class="opacity-100"
          leave-to-class="opacity-0"
          mode="out-in"
        >
          <div
            v-if="selectedLabel"
            key="chip"
            class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-emerald-500/10 ring-1 ring-emerald-500/30 text-[12.5px] font-medium text-emerald-700 dark:text-emerald-300"
          >
            <span class="size-1.5 rounded-full bg-emerald-500 animate-pulse" />
            {{
              $t('ONBOARDING.COUNTRY_PICKER.HOSTING_IN', {
                country: selectedLabel,
              })
            }}
          </div>
          <div
            v-else
            key="hint"
            class="text-[12px] text-n-slate-11 tracking-tight"
          >
            {{ $t('ONBOARDING.COUNTRY_PICKER.CLICK_A_COUNTRY') }}
          </div>
        </Transition>
      </div>
    </div>

    <!-- Error slot -->
    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0 -translate-y-1"
      enter-to-class="opacity-100 translate-y-0"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <p
        v-if="errorMessage"
        class="mx-auto text-center text-[12.5px] text-n-ruby-11 bg-n-ruby-9/10 rounded-lg px-4 py-2 max-w-[520px]"
      >
        {{ errorMessage }}
      </p>
    </Transition>

    <!-- Footer actions -->
    <div class="flex items-center justify-center gap-3">
      <Button
        variant="faded"
        color="slate"
        size="md"
        icon="i-lucide-arrow-left"
        :label="$t('ONBOARDING.HOOKUP.PREVIOUS')"
        :disabled="isCreating || isVerifying"
        @click="onPrevious"
      />
      <Button
        variant="solid"
        color="blue"
        size="md"
        :icon="
          isCreating || isVerifying
            ? 'i-lucide-loader-2'
            : 'i-lucide-arrow-right'
        "
        trailing-icon
        :label="continueLabel"
        :disabled="continueDisabled"
        :is-loading="isCreating || isVerifying"
        @click="continueFlow"
      />
    </div>
  </section>
</template>

<style scoped>
/* Country fills — same emerald accent language as HookUp's connected state */
.country-path {
  stroke: rgb(148 163 184 / 0.4);
  stroke-width: 0.6;
}
.country-context {
  fill: rgb(148 163 184 / 0.06);
}
:global(.dark) .country-context {
  fill: rgb(226 232 240 / 0.04);
}
.country-active {
  fill: rgb(16 185 129 / 0.18);
  stroke: rgb(16 185 129 / 0.5);
  stroke-width: 0.8;
}
.country-active:hover {
  fill: rgb(16 185 129 / 0.35);
  stroke: rgb(16 185 129 / 0.9);
  filter: drop-shadow(0 0 6px rgba(16, 185, 129, 0.35));
}
.country-expansion {
  fill: rgb(148 163 184 / 0.1);
  stroke: rgb(148 163 184 / 0.55);
  stroke-dasharray: 2 2;
}
.country-expansion:hover {
  fill: rgb(148 163 184 / 0.15);
}
.country-selected {
  fill: rgb(16 185 129 / 0.6);
  stroke: rgb(16 185 129 / 1);
  stroke-width: 1.2;
  filter: drop-shadow(0 0 12px rgba(16, 185, 129, 0.6));
  animation: country-pop 520ms cubic-bezier(0.22, 1.4, 0.36, 1);
}
@keyframes country-pop {
  0% {
    transform-origin: center;
    opacity: 0.4;
  }
  60% {
    opacity: 1;
  }
  100% {
    opacity: 1;
  }
}

/* Datacentre markers */
.dc-dot {
  fill: rgb(16 185 129 / 0.85);
  stroke: rgba(255, 255, 255, 0.9);
  stroke-width: 0.8;
  transition: r 200ms ease;
}
.dc-dot-active {
  fill: rgb(16 185 129);
}
.dc-pulse {
  fill: none;
  stroke: rgb(16 185 129);
  stroke-width: 1;
  opacity: 0;
  transform-origin: center;
  animation: dc-pulse 1.6s ease-out infinite;
}
@keyframes dc-pulse {
  0% {
    opacity: 0.8;
    r: 4;
  }
  100% {
    opacity: 0;
    r: 18;
  }
}
@media (prefers-reduced-motion: reduce) {
  .country-selected,
  .dc-pulse {
    animation: none;
  }
}
</style>
