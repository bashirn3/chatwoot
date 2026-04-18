<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';
import Button from 'dashboard/components-next/button/Button.vue';
import { EU_MAP_VIEWBOX, COUNTRY_PATHS } from './countryPaths.js';

// SVG projection constants — kept in sync with scripts/generate_europe_paths.mjs.
// Don't change here without regenerating countryPaths.js or the dots drift off.
const VIEW_W = 800;
const VIEW_H = 700;
const LON_MIN = -12;
const LON_MAX = 32;
const LAT_MIN = 34;
const LAT_MAX = 72;
const projLng = lng => ((lng - LON_MIN) / (LON_MAX - LON_MIN)) * VIEW_W;
const projLat = lat =>
  VIEW_H - ((lat - LAT_MIN) / (LAT_MAX - LAT_MIN)) * VIEW_H;

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const accountId = computed(() => route.params.accountId);
const user = computed(() => store.getters.getCurrentUser || {});

// Active regions (live from /regions) + locally-curated expansion set.
// Backend decides what's *available*; frontend just styles the map.
const ACTIVE_COUNTRIES = ref(new Set());
const ACTIVE_REGIONS = ref([]);
const EXPANSION = new Set(['NL', 'IE', 'ES', 'BE', 'CH', 'AT', 'DK', 'PL']);

const selectedIso = ref(null);
const hoveredIso = ref(null);
const isCreating = ref(false);
const errorMessage = ref(null);

const countryName = iso => t(`ONBOARDING.COUNTRY_PICKER.COUNTRY_NAMES.${iso}`);

const countryClass = iso => {
  if (selectedIso.value === iso) return 'country-selected';
  if (ACTIVE_COUNTRIES.value.has(iso)) return 'country-active';
  if (EXPANSION.has(iso)) return 'country-expansion';
  return 'country-context';
};

const countryInteractive = iso =>
  ACTIVE_COUNTRIES.value.has(iso) || EXPANSION.has(iso);

const sortedRegionEntries = computed(() => {
  const seen = new Set();
  const out = [];
  // Active first, preserving registry order
  ACTIVE_REGIONS.value.forEach(r => {
    if (!seen.has(r.country)) {
      seen.add(r.country);
      out.push({ iso: r.country, active: true, label: countryName(r.country) });
    }
  });
  EXPANSION.forEach(iso => {
    if (!seen.has(iso)) {
      out.push({ iso, active: false, label: countryName(iso) });
    }
  });
  return out;
});

const coveredLabel = computed(() =>
  t('ONBOARDING.COUNTRY_PICKER.COVERED', { count: ACTIVE_COUNTRIES.value.size })
);

const loadRegions = async () => {
  try {
    const { data } = await WhatsAppBridgeAPI.getRegions();
    ACTIVE_REGIONS.value = data?.regions || [];
    const set = new Set();
    ACTIVE_REGIONS.value.forEach(r => set.add(r.country));
    ACTIVE_COUNTRIES.value = set;
  } catch (_e) {
    // Backend unreachable → show empty active set so user sees the disabled map.
    ACTIVE_COUNTRIES.value = new Set();
  }
};

const onCountryClick = iso => {
  if (!ACTIVE_COUNTRIES.value.has(iso)) return;
  selectedIso.value = iso;
  errorMessage.value = null;
};

// Sanitize email into the scoped instance name that was already battle-tested
// in HookUp.vue. Keep this identical so framework-side names stay predictable.
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
  if (!selectedIso.value || isCreating.value) return;
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
    // Instance + inbox now exist on the chosen region. HookUp.vue's bootstrap
    // already picks up existing instances on mount, so we just navigate.
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
  }
};

onMounted(loadRegions);
</script>

<!-- eslint-disable @intlify/vue-i18n/no-dynamic-keys -->
<template>
  <section class="mx-auto w-full max-w-[1080px] flex flex-col gap-6 sm:gap-8">
    <header class="flex flex-col items-center text-center gap-2">
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

    <div class="grid grid-cols-1 lg:grid-cols-[1fr_320px] gap-5 sm:gap-6">
      <!-- Map card -->
      <div
        class="relative rounded-2xl border border-n-container dark:border-n-weak bg-gradient-to-br from-white/90 to-n-slate-2/80 dark:from-n-solid-2 dark:to-n-alpha-black2 shadow-sm overflow-hidden"
      >
        <div class="flex items-center justify-between px-5 pt-5 pb-2">
          <span
            class="text-[10.5px] font-medium uppercase tracking-[0.22em] text-n-slate-11"
          >
            {{ coveredLabel }}
          </span>
          <span
            v-if="hoveredIso && countryInteractive(hoveredIso)"
            class="text-[13px] font-medium text-n-slate-12"
          >
            {{ countryName(hoveredIso) }}
          </span>
        </div>

        <div class="relative px-4 pb-4 min-h-[380px]">
          <svg
            :viewBox="EU_MAP_VIEWBOX"
            class="w-full h-auto select-none"
            role="img"
            :aria-label="$t('ONBOARDING.COUNTRY_PICKER.TITLE')"
          >
            <!-- Subtle graticule grid for depth -->
            <defs>
              <pattern
                id="eu-grid"
                width="40"
                height="40"
                patternUnits="userSpaceOnUse"
              >
                <path
                  d="M 40 0 L 0 0 0 40"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="0.4"
                  class="text-n-slate-6/40"
                />
              </pattern>
              <radialGradient id="eu-glow" cx="50%" cy="50%" r="50%">
                <stop offset="0%" stop-color="rgba(16, 185, 129, 0.28)" />
                <stop offset="100%" stop-color="rgba(16, 185, 129, 0)" />
              </radialGradient>
            </defs>
            <rect width="100%" height="100%" fill="url(#eu-grid)" />

            <g>
              <path
                v-for="(d, iso) in COUNTRY_PATHS"
                :key="iso"
                :d="d"
                class="transition-[fill,opacity,stroke] duration-200 ease-out country-path"
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

            <!-- Selection pulse -->
            <g v-for="region in ACTIVE_REGIONS" :key="`p-${region.code}`">
              <circle
                v-if="selectedIso === region.country"
                :cx="projLng(region.lng)"
                :cy="projLat(region.lat)"
                r="6"
                class="selected-dot"
              />
            </g>
          </svg>
        </div>
      </div>

      <!-- Side panel -->
      <aside
        class="flex flex-col gap-4 rounded-2xl border border-n-container dark:border-n-weak bg-white dark:bg-n-solid-2 shadow-sm p-5"
      >
        <div class="flex flex-col gap-1">
          <span
            class="text-[10.5px] font-medium uppercase tracking-[0.22em] text-n-slate-11"
          >
            {{ $t('ONBOARDING.COUNTRY_PICKER.TAB_ACTIVE') }}
          </span>
          <ul class="flex flex-col gap-1">
            <li v-for="entry in sortedRegionEntries" :key="entry.iso">
              <button
                type="button"
                class="w-full flex items-center justify-between gap-3 px-3 py-2 rounded-lg text-[13px] font-medium transition-colors"
                :class="
                  entry.active
                    ? selectedIso === entry.iso
                      ? 'bg-emerald-500/10 text-n-slate-12 ring-1 ring-emerald-500/30'
                      : 'hover:bg-n-alpha-2 text-n-slate-12'
                    : 'text-n-slate-11/70 cursor-not-allowed'
                "
                :disabled="!entry.active"
                @click="entry.active && onCountryClick(entry.iso)"
              >
                <span class="flex items-center gap-2">
                  <span
                    class="inline-block size-2 rounded-full"
                    :class="entry.active ? 'bg-emerald-500' : 'bg-n-slate-7/70'"
                  />
                  {{ entry.label }}
                </span>
                <span
                  v-if="!entry.active"
                  class="text-[10.5px] uppercase tracking-[0.18em] text-n-slate-10"
                >
                  {{ $t('ONBOARDING.COUNTRY_PICKER.COMING_SOON') }}
                </span>
              </button>
            </li>
          </ul>
        </div>

        <div
          v-if="errorMessage"
          class="text-[12px] text-n-ruby-11 text-pretty bg-n-ruby-9/10 rounded-lg px-3 py-2"
        >
          {{ errorMessage }}
        </div>

        <div class="mt-auto flex flex-col gap-2">
          <Button
            variant="solid"
            color="blue"
            size="md"
            icon="i-lucide-arrow-right"
            trailing-icon
            :label="$t('ONBOARDING.COUNTRY_PICKER.CONTINUE')"
            :disabled="!selectedIso || isCreating"
            :is-loading="isCreating"
            @click="continueFlow"
          />
        </div>
      </aside>
    </div>
  </section>
</template>

<style scoped>
/* Country fills — designed to work on both light and dark themes by
   leaning on subtle emerald tints for covered, muted slate for expansion,
   and near-transparent for context-only shapes. */
.country-path {
  stroke: rgb(148 163 184 / 0.45);
  stroke-width: 0.6;
}
.country-context {
  fill: rgb(148 163 184 / 0.08);
}
:global(.dark) .country-context {
  fill: rgb(226 232 240 / 0.05);
}
.country-active {
  fill: rgb(16 185 129 / 0.22);
  stroke: rgb(16 185 129 / 0.55);
  stroke-width: 0.8;
}
.country-active:hover {
  fill: rgb(16 185 129 / 0.38);
  stroke: rgb(16 185 129 / 0.9);
  filter: drop-shadow(0 0 6px rgba(16, 185, 129, 0.35));
}
.country-expansion {
  fill: rgb(148 163 184 / 0.12);
  stroke-dasharray: 2 2;
  stroke: rgb(148 163 184 / 0.6);
}
.country-selected {
  fill: rgb(16 185 129 / 0.55);
  stroke: rgb(16 185 129 / 1);
  stroke-width: 1.2;
  filter: drop-shadow(0 0 10px rgba(16, 185, 129, 0.55));
}
.selected-dot {
  fill: rgb(16 185 129);
  stroke: rgba(255, 255, 255, 0.9);
  stroke-width: 1.5;
  animation: dot-pulse 1.6s ease-out infinite;
}
@keyframes dot-pulse {
  0% {
    r: 4;
    opacity: 1;
  }
  100% {
    r: 16;
    opacity: 0;
  }
}
@media (prefers-reduced-motion: reduce) {
  .selected-dot {
    animation: none;
  }
}
</style>
