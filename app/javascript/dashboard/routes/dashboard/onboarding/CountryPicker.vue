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

// Mercator projection constants — must match scripts/generate_europe_paths.mjs.
const VIEW_W = 560;
const LON_MIN = -12;
const LON_MAX = 32;
const LAT_MIN = 34;
const LAT_MAX = 70;
const mercY = deg => Math.log(Math.tan(Math.PI / 4 + (deg * Math.PI) / 360));
const MERC_Y_MIN = mercY(LAT_MIN);
const MERC_Y_MAX = mercY(LAT_MAX);
const VIEW_H = Math.round(
  ((MERC_Y_MAX - MERC_Y_MIN) * (180 / Math.PI) * VIEW_W) / (LON_MAX - LON_MIN)
);
const projLng = lng => ((lng - LON_MIN) / (LON_MAX - LON_MIN)) * VIEW_W;
const projLat = lat => {
  const clamped = Math.max(LAT_MIN - 1, Math.min(LAT_MAX + 1, lat));
  const my = mercY(clamped);
  return VIEW_H - ((my - MERC_Y_MIN) / (MERC_Y_MAX - MERC_Y_MIN)) * VIEW_H;
};

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
  <section
    class="mx-auto w-full max-w-[720px] flex flex-col items-center gap-5 sm:gap-6"
  >
    <!-- Minimal header: eyebrow + title only -->
    <header class="flex flex-col items-center text-center gap-1.5">
      <span
        class="text-[10.5px] sm:text-[11px] font-medium uppercase tracking-[0.22em] text-n-slate-11"
      >
        {{ $t('ONBOARDING.COUNTRY_PICKER.EYEBROW') }}
      </span>
      <h1
        class="text-[26px] sm:text-[34px] font-semibold tracking-tight text-balance text-n-slate-12 leading-[1.05]"
      >
        {{ $t('ONBOARDING.COUNTRY_PICKER.TITLE') }}
      </h1>
    </header>

    <!-- Map, transparent. Blends with the page background -->
    <div
      class="relative w-full flex flex-col items-center"
      :aria-label="displayLabel || $t('ONBOARDING.COUNTRY_PICKER.TITLE')"
    >
      <!-- Hovering / selected country name floats above the map -->
      <div class="h-5 mb-1 text-[11px] font-medium uppercase tracking-[0.22em]">
        <span
          v-if="displayLabel"
          class="text-n-slate-12 transition-opacity duration-150"
        >
          {{ displayLabel }}
        </span>
      </div>

      <svg
        :viewBox="EU_MAP_VIEWBOX"
        class="w-full h-auto max-h-[42vh] sm:max-h-[44vh] select-none"
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
        <!-- Datacentre markers, one per active region -->
        <g>
          <circle
            v-for="region in ACTIVE_REGIONS"
            :key="`dc-${region.code}`"
            :cx="projLng(region.lng)"
            :cy="projLat(region.lat)"
            r="2.5"
            class="dc-dot"
            :class="{ 'dc-dot-active': selectedIso === region.country }"
          />
        </g>
      </svg>
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
        class="text-center text-[12.5px] text-n-ruby-11 bg-n-ruby-9/10 rounded-lg px-4 py-2 max-w-[480px]"
      >
        {{ errorMessage }}
      </p>
    </Transition>

    <!-- Footer actions -->
    <div class="flex items-center justify-center gap-3 pt-1">
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
/* Transparent page-blending aesthetic: no fills on the card, bright hairline
   borders on countries for definition, solid-colour emerald fills only on
   active / selected (no glow, no gradients — baseline-UI compliant). */
.country-path {
  stroke: rgb(255 255 255 / 0.55);
  stroke-width: 0.7;
  transition:
    fill 150ms ease-out,
    stroke 150ms ease-out;
}
:global(.dark) .country-path {
  stroke: rgb(255 255 255 / 0.45);
}
.country-context {
  fill: rgb(148 163 184 / 0.08);
}
:global(.dark) .country-context {
  fill: rgb(226 232 240 / 0.05);
}
.country-active {
  fill: rgb(16 185 129 / 0.28);
}
.country-active:hover {
  fill: rgb(16 185 129 / 0.5);
}
.country-expansion {
  fill: rgb(148 163 184 / 0.12);
  stroke: rgb(255 255 255 / 0.35);
  stroke-dasharray: 2 2;
}
.country-selected {
  fill: rgb(16 185 129 / 0.7);
  stroke: rgb(255 255 255 / 0.9);
  stroke-width: 1;
}
.dc-dot {
  fill: rgb(255 255 255 / 0.85);
  stroke: rgb(16 185 129);
  stroke-width: 1;
}
.dc-dot-active {
  fill: rgb(16 185 129);
  stroke: rgb(255 255 255);
}
</style>
