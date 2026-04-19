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

// Map projection — must match scripts/generate_europe_paths.mjs.
const VIEW_W = 800;
const VIEW_H = 700;
const LON_MIN = -12;
const LON_MAX = 32;
const LAT_MIN = 34;
const LAT_MAX = 72;
const projLng = lng => ((lng - LON_MIN) / (LON_MAX - LON_MIN)) * VIEW_W;
const projLat = lat =>
  VIEW_H - ((lat - LAT_MIN) / (LAT_MAX - LAT_MIN)) * VIEW_H;

// Active regions come from the backend, expansion set is curated marketing.
const ACTIVE_COUNTRIES = ref(new Set());
const ACTIVE_REGIONS = ref([]);
const EXPANSION = new Set(['NL', 'IE', 'ES', 'BE', 'CH', 'AT', 'DK', 'PL']);

const selectedIso = ref(null);
const hoveredIso = ref(null);
const isCreating = ref(false);
const errorMessage = ref(null);

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

const continueDisabled = computed(() => !selectedIso.value || isCreating.value);

const continueLabel = computed(() => {
  if (isCreating.value) {
    return t('ONBOARDING.COUNTRY_PICKER.STATUS.PROVISIONING');
  }
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

// Email → URL-safe instance name, identical to HookUp.vue.
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
      isCreating.value = false;
      return;
    }

    const regionCode = data?.region_code || data?.instance?.region || null;
    const instanceName =
      data?.instance?.id ||
      data?.instance?.name ||
      data?.instance?.instanceName;
    const regionLabel =
      ACTIVE_REGIONS.value.find(r => r.code === regionCode)?.label || null;

    // Hand off to the provisioning screen. It polls the framework for QR
    // readiness and moves the user to /hookup once the scan is ready.
    sessionStorage.setItem(
      'wasup_provisioning',
      JSON.stringify({
        instanceName,
        regionCode,
        regionLabel,
        countryIso: selectedIso.value,
        countryLabel: selectedLabel.value,
      })
    );

    router.push({
      name: 'onboarding_provisioning',
      params: { accountId: accountId.value },
    });
  } catch (err) {
    errorMessage.value =
      err?.response?.data?.error ||
      err?.message ||
      t('ONBOARDING.COUNTRY_PICKER.RESOLVE_FAILED');
    isCreating.value = false;
  }
};

watch(selectedIso, () => {
  errorMessage.value = null;
});

onMounted(loadRegions);
</script>

<!-- eslint-disable @intlify/vue-i18n/no-dynamic-keys -->
<template>
  <section class="mx-auto w-full max-w-[940px] flex flex-col gap-8 sm:gap-10">
    <!-- Header — mirrors HookUp exactly so the two onboarding steps read as one flow -->
    <header class="flex flex-col items-center text-center gap-2">
      <div class="mb-1.5" aria-hidden="true">
        <span
          class="inline-flex size-12 sm:size-14 items-center justify-center rounded-[14px] bg-emerald-500 ring-1 ring-black/5 dark:ring-white/10"
        >
          <svg
            viewBox="0 0 24 24"
            class="size-6 sm:size-7 text-white"
            fill="none"
            stroke="currentColor"
            stroke-width="1.8"
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
        class="text-[12.5px] sm:text-[13.5px] text-pretty max-w-[480px] text-n-slate-11"
      >
        {{ $t('ONBOARDING.COUNTRY_PICKER.SUBTITLE') }}
      </p>
    </header>

    <!-- Map card — same card language as the HookUp video/QR cards -->
    <div
      class="relative rounded-2xl bg-white dark:bg-n-solid-2 border border-n-container dark:border-n-weak shadow-sm overflow-hidden"
    >
      <!-- Eyebrow strip: covered count + hovering country name -->
      <div
        class="flex items-center justify-between px-5 pt-4 pb-2 text-[10.5px] font-medium uppercase tracking-[0.22em] min-h-[28px]"
      >
        <span class="text-n-slate-11">
          {{
            $t('ONBOARDING.COUNTRY_PICKER.COVERED', {
              count: ACTIVE_COUNTRIES.size,
            })
          }}
        </span>
        <span
          v-if="displayLabel"
          class="text-n-slate-12 transition-opacity duration-150"
        >
          {{ displayLabel }}
        </span>
      </div>

      <div class="px-4 pb-4">
        <svg
          :viewBox="EU_MAP_VIEWBOX"
          class="w-full h-auto max-h-[380px] mx-auto select-none"
          role="img"
          :aria-label="$t('ONBOARDING.COUNTRY_PICKER.TITLE')"
          preserveAspectRatio="xMidYMid meet"
        >
          <g>
            <path
              v-for="(d, iso) in COUNTRY_PATHS"
              :key="iso"
              :d="d"
              class="country-path"
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

          <!-- Datacentre markers -->
          <g>
            <g v-for="region in ACTIVE_REGIONS" :key="`dc-${region.code}`">
              <circle
                :cx="projLng(region.lng)"
                :cy="projLat(region.lat)"
                r="2.6"
                class="dc-dot"
                :class="{ 'dc-dot-active': selectedIso === region.country }"
              />
            </g>
          </g>
        </svg>
      </div>

      <!-- Hosting chip -->
      <div
        class="px-5 pb-4 -mt-1 min-h-[42px] flex items-center justify-center"
      >
        <Transition
          enter-active-class="transition-opacity duration-150 ease-out"
          enter-from-class="opacity-0"
          enter-to-class="opacity-100"
          leave-active-class="transition-opacity duration-100 ease-in absolute"
          leave-from-class="opacity-100"
          leave-to-class="opacity-0"
          mode="out-in"
        >
          <span
            v-if="selectedLabel"
            key="chip"
            class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-emerald-500/10 ring-1 ring-emerald-500/30 text-[12.5px] font-medium text-emerald-700 dark:text-emerald-300"
          >
            <span class="size-1.5 rounded-full bg-emerald-500" />
            {{
              $t('ONBOARDING.COUNTRY_PICKER.HOSTING_IN', {
                country: selectedLabel,
              })
            }}
          </span>
          <span
            v-else
            key="hint"
            class="text-[12px] text-n-slate-11 tracking-tight"
          >
            {{ $t('ONBOARDING.COUNTRY_PICKER.CLICK_A_COUNTRY') }}
          </span>
        </Transition>
      </div>
    </div>

    <!-- Error slot -->
    <Transition
      enter-active-class="transition-opacity duration-150 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition-opacity duration-100 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <p
        v-if="errorMessage"
        role="alert"
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
        :disabled="isCreating"
        @click="router.replace(`/app/accounts/${accountId}/dashboard`)"
      />
      <Button
        variant="solid"
        color="blue"
        size="md"
        :icon="isCreating ? 'i-lucide-loader-2' : 'i-lucide-arrow-right'"
        trailing-icon
        :label="continueLabel"
        :disabled="continueDisabled"
        :is-loading="isCreating"
        @click="continueFlow"
      />
    </div>
  </section>
</template>

<style scoped>
/* Baseline-UI compliant: single emerald accent, no gradients/glows, only
   fill/stroke transitions (cheap; paint-only on small SVG paths). */
.country-path {
  stroke: rgb(148 163 184 / 0.4);
  stroke-width: 0.6;
  transition:
    fill 150ms ease-out,
    stroke 150ms ease-out;
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
  fill: rgb(16 185 129 / 0.34);
  stroke: rgb(16 185 129 / 0.85);
}
.country-expansion {
  fill: rgb(148 163 184 / 0.1);
  stroke: rgb(148 163 184 / 0.55);
  stroke-dasharray: 2 2;
}
.country-selected {
  fill: rgb(16 185 129 / 0.55);
  stroke: rgb(16 185 129);
  stroke-width: 1.1;
}
.dc-dot {
  fill: rgb(16 185 129 / 0.9);
  stroke: rgba(255, 255, 255, 0.9);
  stroke-width: 0.8;
}
.dc-dot-active {
  fill: rgb(16 185 129);
}
</style>
