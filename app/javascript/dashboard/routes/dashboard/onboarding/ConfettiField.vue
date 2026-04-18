<script setup>
/**
 * Two corner confetti compositions (top-left + bottom-right mirror),
 * hand-composed pastel paper pieces + thin curly streamers to match
 * the mock. Pointer-events are disabled; respects prefers-reduced-motion.
 */
import { computed } from 'vue';

// Deterministic pieces so the layout is stable across renders.
// Coordinates are in a 420x380 viewBox per corner.
const PIECES = [
  // rectangles — { x, y, w, h, rot, fill }
  { x: 58, y: 40, w: 22, h: 14, r: -16, c: '#FFB7CF' },
  { x: 22, y: 92, w: 18, h: 12, r: 24, c: '#FFD9A8' },
  { x: 108, y: 62, w: 20, h: 14, r: -8, c: '#C8E8C3' },
  { x: 148, y: 32, w: 16, h: 16, r: 18, c: '#F7D27A' },
  { x: 176, y: 120, w: 22, h: 12, r: -22, c: '#BFD7FF' },
  { x: 96, y: 138, w: 18, h: 14, r: 12, c: '#E2C7F5' },
  { x: 44, y: 176, w: 22, h: 14, r: -10, c: '#FFC8DC' },
  { x: 210, y: 68, w: 14, h: 14, r: 30, c: '#AFE3D3' },
  { x: 232, y: 150, w: 20, h: 12, r: -18, c: '#FFD9A8' },
  { x: 68, y: 230, w: 18, h: 14, r: 14, c: '#FCE28F' },
  { x: 140, y: 196, w: 16, h: 14, r: -28, c: '#FFB7CF' },
  { x: 18, y: 250, w: 22, h: 14, r: 8, c: '#BFD7FF' },
  { x: 284, y: 110, w: 16, h: 12, r: -14, c: '#E2C7F5' },
  // outlined rectangles
  { x: 126, y: 96, w: 18, h: 12, r: -8, c: 'none', s: '#FFB7CF' },
  { x: 184, y: 200, w: 18, h: 12, r: 18, c: 'none', s: '#BFD7FF' },
  { x: 60, y: 120, w: 14, h: 12, r: 28, c: 'none', s: '#F7D27A' },
];

// Curly streamers — SVG paths that follow a sine-like curve.
const STREAMERS = [
  {
    d: 'M 28 10 C 70 30, 40 70, 90 90 S 110 150, 60 170',
    stroke: '#FFB7CF',
  },
  {
    d: 'M 130 0 C 180 40, 150 100, 210 120 S 240 190, 180 210',
    stroke: '#C8E8C3',
  },
  {
    d: 'M 240 30 C 280 60, 250 110, 300 130',
    stroke: '#FFD9A8',
  },
];

const reducedMotion = computed(() => {
  if (typeof window === 'undefined' || !window.matchMedia) return false;
  try {
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch (_e) {
    return false;
  }
});

const pieceDelay = i => (reducedMotion.value ? 0 : 40 + i * 35);
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<template>
  <div
    aria-hidden="true"
    class="pointer-events-none absolute inset-0 overflow-hidden"
  >
    <!-- Top-left corner composition -->
    <svg
      class="absolute top-0 left-0 w-[min(46vw,560px)] h-[min(42vh,420px)]"
      viewBox="0 0 420 380"
      preserveAspectRatio="xMinYMin meet"
    >
      <g>
        <path
          v-for="(s, i) in STREAMERS"
          :key="`tl-s-${i}`"
          :d="s.d"
          :stroke="s.stroke"
          stroke-width="2.25"
          fill="none"
          stroke-linecap="round"
          class="confetti-piece"
          :style="{ animationDelay: `${pieceDelay(i)}ms` }"
        />
        <rect
          v-for="(p, i) in PIECES"
          :key="`tl-p-${i}`"
          :x="p.x"
          :y="p.y"
          :width="p.w"
          :height="p.h"
          :fill="p.c"
          :stroke="p.s || 'none'"
          :stroke-width="p.s ? 1.5 : 0"
          rx="2"
          ry="2"
          :transform="`rotate(${p.r} ${p.x + p.w / 2} ${p.y + p.h / 2})`"
          class="confetti-piece"
          :style="{ animationDelay: `${pieceDelay(i + STREAMERS.length)}ms` }"
        />
      </g>
    </svg>

    <!-- Bottom-right corner, mirrored -->
    <svg
      class="absolute bottom-0 right-0 w-[min(46vw,560px)] h-[min(42vh,420px)]"
      viewBox="0 0 420 380"
      preserveAspectRatio="xMaxYMax meet"
      style="transform: scale(-1, -1)"
    >
      <g>
        <path
          v-for="(s, i) in STREAMERS"
          :key="`br-s-${i}`"
          :d="s.d"
          :stroke="s.stroke"
          stroke-width="2.25"
          fill="none"
          stroke-linecap="round"
          class="confetti-piece"
          :style="{ animationDelay: `${pieceDelay(i) + 160}ms` }"
        />
        <rect
          v-for="(p, i) in PIECES"
          :key="`br-p-${i}`"
          :x="p.x"
          :y="p.y"
          :width="p.w"
          :height="p.h"
          :fill="p.c"
          :stroke="p.s || 'none'"
          :stroke-width="p.s ? 1.5 : 0"
          rx="2"
          ry="2"
          :transform="`rotate(${p.r} ${p.x + p.w / 2} ${p.y + p.h / 2})`"
          class="confetti-piece"
          :style="{
            animationDelay: `${pieceDelay(i + STREAMERS.length) + 160}ms`,
          }"
        />
      </g>
    </svg>
  </div>
</template>

<style scoped>
@keyframes confetti-drop-in {
  0% {
    opacity: 0;
    transform: translateY(-6px);
  }
  100% {
    opacity: 1;
    transform: translateY(0);
  }
}

.confetti-piece {
  opacity: 0;
  transform-box: fill-box;
  transform-origin: center;
  animation: confetti-drop-in 320ms cubic-bezier(0.22, 1, 0.36, 1) forwards;
}

@media (prefers-reduced-motion: reduce) {
  .confetti-piece {
    animation: none;
    opacity: 1;
    transform: none;
  }
}
</style>
