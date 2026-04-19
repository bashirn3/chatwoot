<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { COUNTRY_PATHS } from './countryPaths.js';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const accountId = computed(() => route.params.accountId);
const user = computed(() => store.getters.getCurrentUser || {});

// Must match scripts/generate_europe_paths.mjs exactly.
const VIEW_W = 1200;
const LON_MIN = -20;
const LON_MAX = 42;
const LAT_MIN = 34;
const LAT_MAX = 72;
const mercY = deg => Math.log(Math.tan(Math.PI / 4 + (deg * Math.PI) / 360));
const MERC_Y_MIN = mercY(LAT_MIN);
const MERC_Y_MAX = mercY(LAT_MAX);
const VIEW_H = Math.round(
  ((MERC_Y_MAX - MERC_Y_MIN) * (180 / Math.PI) * VIEW_W) / (LON_MAX - LON_MIN)
);
const projLng = lng => ((lng - LON_MIN) / (LON_MAX - LON_MIN)) * VIEW_W;
const projLat = lat => {
  const my = mercY(Math.max(LAT_MIN - 2, Math.min(LAT_MAX + 2, lat)));
  return VIEW_H - ((my - MERC_Y_MIN) / (MERC_Y_MAX - MERC_Y_MIN)) * VIEW_H;
};

// Initial viewBox framing (active region focus): Nordics + UK with a
// hint of Germany/France at the bottom. Computed from lat/lng bounds so
// it stays correct if the generator bounds ever change.
const FOCUS_LAT_TOP = 69;
const FOCUS_LAT_BOTTOM = 46;
const FOCUS_LNG_LEFT = -15;
const FOCUS_LNG_RIGHT = 38;
const initialBox = () => {
  const x = projLng(FOCUS_LNG_LEFT);
  const w = projLng(FOCUS_LNG_RIGHT) - x;
  const y = projLat(FOCUS_LAT_TOP);
  const h = projLat(FOCUS_LAT_BOTTOM) - y;
  return { x, y, w, h };
};

// Absolute zoom constraints: fully zoomed in can show ~8 countries;
// fully zoomed out shows the whole generated canvas.
const MIN_BOX_W = 260;
const MAX_BOX_W = VIEW_W;

const ACTIVE_COUNTRIES = ref(new Set());
const ACTIVE_REGIONS = ref([]);
const EXPANSION = new Set(['NL', 'IE', 'ES', 'BE', 'CH', 'AT', 'DK', 'PL']);

const selectedIso = ref(null);
const hoveredIso = ref(null);
const isCreating = ref(false);
const errorMessage = ref(null);

const box = ref(initialBox());
const svgEl = ref(null);
const isDragging = ref(false);
const dragState = ref(null);

const viewBoxStr = computed(
  () => `${box.value.x} ${box.value.y} ${box.value.w} ${box.value.h}`
);

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

// --- zoom + pan ---
// Convert a pointer event's clientX/clientY into viewBox coordinates so
// zoom stays anchored at the cursor.
const clientToSvg = (clientX, clientY) => {
  const svg = svgEl.value;
  if (!svg) return null;
  const rect = svg.getBoundingClientRect();
  const { x, y, w, h } = box.value;
  return {
    x: x + ((clientX - rect.left) / rect.width) * w,
    y: y + ((clientY - rect.top) / rect.height) * h,
  };
};

const clampBox = ({ x, y, w, h }) => {
  const aspect = w / h;
  // Width within [MIN, MAX]; height derived so aspect is preserved.
  const clampedW = Math.max(MIN_BOX_W, Math.min(MAX_BOX_W, w));
  const clampedH = clampedW / aspect;
  // Keep the box from wandering entirely off-canvas. Allow some overscroll
  // so dragging feels natural.
  const maxX = VIEW_W - clampedW * 0.25;
  const minX = -clampedW * 0.75;
  const maxY = VIEW_H - clampedH * 0.25;
  const minY = -clampedH * 0.75;
  return {
    x: Math.min(maxX, Math.max(minX, x)),
    y: Math.min(maxY, Math.max(minY, y)),
    w: clampedW,
    h: clampedH,
  };
};

const onWheel = event => {
  event.preventDefault();
  const anchor = clientToSvg(event.clientX, event.clientY);
  if (!anchor) return;
  const factor = Math.exp(event.deltaY * 0.0015); // 1 = no change
  const newW = box.value.w * factor;
  const newH = box.value.h * factor;
  // Adjust origin so the cursor stays anchored at `anchor`.
  const relX = (anchor.x - box.value.x) / box.value.w;
  const relY = (anchor.y - box.value.y) / box.value.h;
  box.value = clampBox({
    x: anchor.x - relX * newW,
    y: anchor.y - relY * newH,
    w: newW,
    h: newH,
  });
};

const onPointerDown = event => {
  if (event.button !== 0) return;
  isDragging.value = true;
  dragState.value = {
    clientX: event.clientX,
    clientY: event.clientY,
    startBox: { ...box.value },
  };
  svgEl.value?.setPointerCapture?.(event.pointerId);
};

const onPointerMove = event => {
  if (!isDragging.value || !dragState.value) return;
  const { clientX, clientY, startBox } = dragState.value;
  const rect = svgEl.value.getBoundingClientRect();
  const dx = ((event.clientX - clientX) / rect.width) * startBox.w;
  const dy = ((event.clientY - clientY) / rect.height) * startBox.h;
  box.value = clampBox({
    x: startBox.x - dx,
    y: startBox.y - dy,
    w: startBox.w,
    h: startBox.h,
  });
};

const onPointerUp = event => {
  isDragging.value = false;
  dragState.value = null;
  svgEl.value?.releasePointerCapture?.(event.pointerId);
};

const zoomBy = factor => {
  const cx = box.value.x + box.value.w / 2;
  const cy = box.value.y + box.value.h / 2;
  const newW = box.value.w * factor;
  const newH = box.value.h * factor;
  box.value = clampBox({
    x: cx - newW / 2,
    y: cy - newH / 2,
    w: newW,
    h: newH,
  });
};
const zoomIn = () => zoomBy(0.75);
const zoomOut = () => zoomBy(1.33);
const resetView = () => {
  box.value = initialBox();
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

onMounted(() => {
  loadRegions();
  // Global pointer-up in case the pointer leaves the SVG mid-drag.
  window.addEventListener('pointerup', onPointerUp);
});

onBeforeUnmount(() => {
  window.removeEventListener('pointerup', onPointerUp);
});
</script>

<!-- eslint-disable @intlify/vue-i18n/no-dynamic-keys -->
<template>
  <section class="w-full flex flex-col items-center gap-4 sm:gap-5">
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

    <div class="h-5 text-[11px] font-medium uppercase tracking-[0.22em]">
      <span
        v-if="displayLabel"
        class="text-n-slate-12 transition-opacity duration-150"
      >
        {{ displayLabel }}
      </span>
    </div>

    <!-- Map — full-bleed. Transparent background, bright country outlines,
         zoom/pan enabled. -->
    <div
      class="relative w-[100vw] -mx-[calc((100vw-100%)/2)] flex justify-center"
      :aria-label="displayLabel || $t('ONBOARDING.COUNTRY_PICKER.TITLE')"
    >
      <svg
        ref="svgEl"
        :viewBox="viewBoxStr"
        class="w-full max-w-[1400px] h-auto max-h-[48vh] sm:max-h-[52vh] select-none"
        :class="isDragging ? 'cursor-grabbing' : 'cursor-grab'"
        role="img"
        :aria-label="$t('ONBOARDING.COUNTRY_PICKER.TITLE')"
        preserveAspectRatio="xMidYMid meet"
        @wheel.passive.prevent="onWheel"
        @pointerdown="onPointerDown"
        @pointermove="onPointerMove"
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
        <g>
          <circle
            v-for="region in ACTIVE_REGIONS"
            :key="`dc-${region.code}`"
            :cx="projLng(region.lng)"
            :cy="projLat(region.lat)"
            r="3.2"
            class="dc-dot"
            :class="{ 'dc-dot-active': selectedIso === region.country }"
          />
        </g>
      </svg>

      <!-- Zoom controls, bottom-right of the map -->
      <div
        class="absolute bottom-3 right-3 sm:right-6 flex flex-col gap-1 rounded-lg bg-n-solid-2/80 dark:bg-n-alpha-black2/90 ring-1 ring-n-weak backdrop-blur-[2px] p-1"
      >
        <button
          type="button"
          class="size-7 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
          :aria-label="$t('ONBOARDING.COUNTRY_PICKER.ZOOM_IN')"
          @click="zoomIn"
        >
          <Icon icon="i-lucide-plus" class="size-4" />
        </button>
        <button
          type="button"
          class="size-7 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
          :aria-label="$t('ONBOARDING.COUNTRY_PICKER.ZOOM_OUT')"
          @click="zoomOut"
        >
          <Icon icon="i-lucide-minus" class="size-4" />
        </button>
        <button
          type="button"
          class="size-7 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
          :aria-label="$t('ONBOARDING.COUNTRY_PICKER.RESET_VIEW')"
          @click="resetView"
        >
          <Icon icon="i-lucide-locate" class="size-4" />
        </button>
      </div>
    </div>

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
/* Transparent background, bright hairline country borders. Single emerald
   accent. No glow, no gradients. */
.country-path {
  stroke: rgb(255 255 255 / 0.55);
  stroke-width: 0.6;
  vector-effect: non-scaling-stroke;
  transition:
    fill 150ms ease-out,
    stroke 150ms ease-out;
}
:global(.dark) .country-path {
  stroke: rgb(255 255 255 / 0.4);
}
.country-context {
  fill: rgb(148 163 184 / 0.22);
}
:global(.dark) .country-context {
  fill: rgb(226 232 240 / 0.09);
}
.country-expansion {
  fill: rgb(148 163 184 / 0.28);
  stroke: rgb(255 255 255 / 0.35);
  stroke-dasharray: 2 2;
}
:global(.dark) .country-expansion {
  fill: rgb(226 232 240 / 0.14);
}
.country-active {
  fill: rgb(16 185 129 / 0.35);
}
.country-active:hover {
  fill: rgb(16 185 129 / 0.55);
}
.country-selected {
  fill: rgb(16 185 129 / 0.75);
  stroke: rgb(255 255 255 / 0.9);
  stroke-width: 1;
}
.dc-dot {
  fill: rgb(255 255 255 / 0.85);
  stroke: rgb(16 185 129);
  stroke-width: 1.2;
  vector-effect: non-scaling-stroke;
}
.dc-dot-active {
  fill: rgb(16 185 129);
  stroke: rgb(255 255 255);
}
</style>
