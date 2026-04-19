<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';
import Button from 'dashboard/components-next/button/Button.vue';
import { COUNTRY_PATHS, COUNTRY_BBOXES } from './countryPaths.js';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const accountId = computed(() => route.params.accountId);
const user = computed(() => store.getters.getCurrentUser || {});

// Must match scripts/generate_europe_paths.mjs exactly.
const VIEW_W = 1200;
const LON_MIN = -15;
const LON_MAX = 26;
const LAT_MIN = 36;
const LAT_MAX = 71;
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

// Default focus: Nordics + UK, with Germany/France/Poland peeking in.
const FOCUS_LAT_TOP = 69;
const FOCUS_LAT_BOTTOM = 46;
const FOCUS_LNG_LEFT = -15;
const FOCUS_LNG_RIGHT = 38;
const focusBox = () => {
  const x = projLng(FOCUS_LNG_LEFT);
  const w = projLng(FOCUS_LNG_RIGHT) - x;
  const y = projLat(FOCUS_LAT_TOP);
  const h = projLat(FOCUS_LAT_BOTTOM) - y;
  return { x, y, w, h };
};

// When zooming into a single country, padding keeps the silhouette from
// touching the SVG edge.
const ZOOM_PADDING = 0.3; // 30% of bounding box

const ACTIVE_COUNTRIES = ref(new Set());
const ACTIVE_REGIONS = ref([]);
const EXPANSION = new Set(['NL', 'IE', 'ES', 'BE', 'CH', 'AT', 'DK', 'PL']);

const selectedIso = ref(null);
const hoveredIso = ref(null);
const isCreating = ref(false);
const errorMessage = ref(null);

const box = ref(focusBox());
const tweenHandle = ref(null);
const svgEl = ref(null);
const isDragging = ref(false);
const dragState = ref(null);
// Set when a pointerdown→move drag just happened. Consumed by the next
// click listener to suppress the synthetic click on a path (otherwise a
// drag ending over a country would register as a selection).
const suppressNextClick = ref(false);

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
    return t('ONBOARDING.COUNTRY_PICKER.SELECT_TO_CONTINUE', {
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

// --- viewBox tween ---
// easeInOutCubic — smooth start/end, no overshoot (baseline-ui friendly).
const easeInOutCubic = p => (p < 0.5 ? 4 * p ** 3 : 1 - (-2 * p + 2) ** 3 / 2);

const tweenTo = (target, duration = 420) => {
  if (tweenHandle.value) cancelAnimationFrame(tweenHandle.value);
  const from = { ...box.value };
  const start = performance.now();
  const step = now => {
    const elapsed = now - start;
    const p = Math.min(1, elapsed / duration);
    const k = easeInOutCubic(p);
    box.value = {
      x: from.x + (target.x - from.x) * k,
      y: from.y + (target.y - from.y) * k,
      w: from.w + (target.w - from.w) * k,
      h: from.h + (target.h - from.h) * k,
    };
    if (p < 1) {
      tweenHandle.value = requestAnimationFrame(step);
    } else {
      tweenHandle.value = null;
    }
  };
  tweenHandle.value = requestAnimationFrame(step);
};

// Compute a viewBox target that frames a country's bbox with padding,
// preserving the current box aspect ratio so the rendered map doesn't
// visually resize / reflow.
const zoomTargetFor = iso => {
  const bb = COUNTRY_BBOXES[iso];
  if (!bb) return null;
  const padX = bb.w * ZOOM_PADDING;
  const padY = bb.h * ZOOM_PADDING;
  let w = bb.w + padX * 2;
  let h = bb.h + padY * 2;
  const currentAspect = box.value.w / box.value.h;
  const targetAspect = w / h;
  if (targetAspect > currentAspect) {
    h = w / currentAspect;
  } else {
    w = h * currentAspect;
  }
  const cx = bb.x + bb.w / 2;
  const cy = bb.y + bb.h / 2;
  return { x: cx - w / 2, y: cy - h / 2, w, h };
};

const onCountryClick = iso => {
  if (suppressNextClick.value) {
    suppressNextClick.value = false;
    return;
  }
  if (!ACTIVE_COUNTRIES.value.has(iso)) return;
  selectedIso.value = iso;
  errorMessage.value = null;
  const target = zoomTargetFor(iso);
  if (target) tweenTo(target);
};

// --- wheel + drag (kept behind the scenes; no visible controls) ---
const MIN_BOX_W = 200;
const MAX_BOX_W = VIEW_W;

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
  const cW = Math.max(MIN_BOX_W, Math.min(MAX_BOX_W, w));
  const cH = cW / aspect;
  const maxX = VIEW_W - cW * 0.25;
  const minX = -cW * 0.75;
  const maxY = VIEW_H - cH * 0.25;
  const minY = -cH * 0.75;
  return {
    x: Math.min(maxX, Math.max(minX, x)),
    y: Math.min(maxY, Math.max(minY, y)),
    w: cW,
    h: cH,
  };
};

const onWheel = event => {
  event.preventDefault();
  const anchor = clientToSvg(event.clientX, event.clientY);
  if (!anchor) return;
  const factor = Math.exp(event.deltaY * 0.0015);
  const newW = box.value.w * factor;
  const newH = box.value.h * factor;
  const relX = (anchor.x - box.value.x) / box.value.w;
  const relY = (anchor.y - box.value.y) / box.value.h;
  if (tweenHandle.value) cancelAnimationFrame(tweenHandle.value);
  box.value = clampBox({
    x: anchor.x - relX * newW,
    y: anchor.y - relY * newH,
    w: newW,
    h: newH,
  });
};

// Drag threshold in CSS pixels. Below this we treat the gesture as a
// click and let the path's @click fire normally. Above it we start
// panning and mark the next synthetic click to be suppressed.
const DRAG_THRESHOLD_PX = 4;

const onPointerDown = event => {
  if (event.button !== 0) return;
  // Note: deliberately NOT calling setPointerCapture — that diverts all
  // pointer events to the <svg> element and kills <path>'s @click.
  dragState.value = {
    clientX: event.clientX,
    clientY: event.clientY,
    startBox: { ...box.value },
  };
  isDragging.value = false;
};

const onPointerMove = event => {
  if (!dragState.value) return;
  const { clientX, clientY, startBox } = dragState.value;
  const dx = event.clientX - clientX;
  const dy = event.clientY - clientY;
  if (!isDragging.value) {
    if (Math.hypot(dx, dy) <= DRAG_THRESHOLD_PX) return;
    isDragging.value = true;
  }
  const rect = svgEl.value.getBoundingClientRect();
  const ndx = (dx / rect.width) * startBox.w;
  const ndy = (dy / rect.height) * startBox.h;
  if (tweenHandle.value) cancelAnimationFrame(tweenHandle.value);
  box.value = clampBox({
    x: startBox.x - ndx,
    y: startBox.y - ndy,
    w: startBox.w,
    h: startBox.h,
  });
};

const onPointerUp = () => {
  if (isDragging.value) suppressNextClick.value = true;
  isDragging.value = false;
  dragState.value = null;
};

// --- instance creation ---
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
  window.addEventListener('pointerup', onPointerUp);
});

onBeforeUnmount(() => {
  window.removeEventListener('pointerup', onPointerUp);
  if (tweenHandle.value) cancelAnimationFrame(tweenHandle.value);
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

    <!-- Map — full-bleed, transparent, no visible zoom chrome. Click a
         country to zoom into it. -->
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
      </svg>
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
  stroke: rgb(255 255 255 / 0.4);
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
  fill: rgb(16 185 129 / 0.78);
  stroke: rgb(255 255 255 / 0.9);
  stroke-width: 1;
}
</style>
